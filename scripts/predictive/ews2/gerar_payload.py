"""Gera o payload `ews2/1` (chave KV `ews2:latest`) para os 104 emissores do Radar, na liberacao operacional da nota 126.

So roda com guarda_treino em exit 0 (homologacao real ou override do operador com nota de decisao por hash).
Sinais expostos: os que tiveram limite inferior do IC95 da razao de risco acima de 1,5 no backtest real
(`--backtest`), criterio da propria G2. ATENCAO, declarado no payload: nenhum sinal passou o G2 inteiro (PR-AUC nao supera
B2) e a escolha foi feita olhando o resultado do teste. Probabilidade nunca e exibida (G3 nao calculado).
Homologacao gravada como e: g1a, g1b, g2, g3 false; g1c pelo backtest. O bloco `liberacao` cita a nota 126 e o hash.

Uso: python -I gerar_payload.py --backtest BACKTEST.json --saida PAYLOAD.json [--T AAAA-MM-DD]
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sys
from collections import defaultdict

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import eventos as EV  # noqa: E402
import features as F  # noqa: E402

BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
MAPA = os.path.join(BASE, "scripts", "predictive", "cnpj_emissores.json")
RR_MIN = 1.5


def sinais_expostos(bt):
    """Uniao dos aprovados no G2 com os de limite inferior do IC95 da RR > RR_MIN (estes declarados como escolha olhando o teste)."""
    out = set(bt.get("aprovados_g2") or [])
    for s, v in (bt.get("hipoteses") or {}).items():
        ic = v.get("rr_ic95") or [None, None]
        if ic[0] is not None and ic[0] > RR_MIN:
            out.add(s)
    return sorted(out)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--backtest", required=True)
    ap.add_argument("--saida", required=True)
    ap.add_argument("--T", default=dt.date.today().isoformat())
    a = ap.parse_args(argv)
    import guarda_treino
    est = guarda_treino.exigir("payload ews2")
    reg = json.load(open(guarda_treino.REGISTRO, encoding="utf-8-sig"))
    bt = json.load(open(a.backtest, encoding="utf-8"))
    sinais = sinais_expostos(bt)
    if not sinais:
        raise SystemExit("nenhum sinal com IC95 da razao de risco acima de %.1f: nada a expor" % RR_MIN)
    import dados as D
    t = dt.date.fromisoformat(a.T)
    docs, _ = D.ler_ipe()
    dfp, _ = D.ler_dfp()
    itr, _ = D.ler_dfp(itr=True)
    precos_ticker, _ = D.ler_cotahist()
    precos, _escolha = D.precos_por_cnpj(precos_ticker, D.ler_tickers_fca())
    selic, _ = D.ler_selic()
    cad = D.ler_cad()
    docs_por = defaultdict(list)
    for d in docs:
        docs_por[d["cnpj"]].append(d)
    for lst in docs_por.values():
        lst.sort(key=lambda d: d["data"])
    rot = EV.ler_rotulos(os.path.join(BASE, reg["arquivo_rotulos"]))
    eps = EV.marcar_prevalencia(EV.episodios(EV.eventos_de_rotulos(rot)), docs_por)
    setor_de = lambda c: (cad[c][0]["setor_ativ"] if cad.get(c) else "")  # noqa: E731
    ev_setor = defaultdict(list)
    for ep in eps:
        if not ep["prevalente"]:
            ev_setor[setor_de(ep["cnpj"])].append((ep["inicio"], ep["cnpj"]))
    mapa = json.load(open(MAPA, encoding="utf-8"))
    emissores = []
    for nome, info in sorted(mapa.items()):
        c = info["cnpj"]
        lst = docs_por.get(c, [])
        evs_outros = {s: [(d, cc) for d, cc in v if cc != c] for s, v in ev_setor.items()}
        f = F.features_em_T(c, t, lst, [d["data"] for d in lst], dfp.get(c, []), itr.get(c, []), precos.get(c), selic, setor_de(c), evs_outros)
        sv = {s: (None if f.get(s) is None else int(bool(f.get(s)))) for s in sinais}
        ativos = sum(1 for v in sv.values() if v == 1)
        emissores.append({"cnpj": c, "nome": nome, "sinais": sv, "prob_180d": None,
                          "severidade": "alta" if ativos >= 2 else ("media" if ativos == 1 else "baixa")})
    nota = os.path.join(BASE, reg["override_nota"])
    payload = {
        "schema": "ews2/1", "protocolo": "G0-v4", "versao_pipeline": bt.get("versao_pipeline"), "gerado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "data_observacao": t.isoformat(), "sha256_rotulos": est["sha256_rotulos_real"],
        "homologacao": {"g1a": reg.get("g1a_passa") is True, "g1b": reg.get("g1b_passa") is True, "g1c": (bt.get("g1c") or {}).get("passa") is True,
                        "g2": bool(bt.get("aprovados_g2")), "g3": False},
        "liberacao": {"modo": "operacional_por_decisao_do_operador", "nota": reg["override_nota"],
                      "nota_sha256": hashlib.sha256(open(nota, "rb").read()).hexdigest(),
                      "criterio_sinais": "aprovados no G2 do backtest real (%s) mais limite inferior do IC95 da razao de risco > %.1f (%s, selecao olhando o teste, sem G2)" % (
                          ",".join(sorted(bt.get("aprovados_g2") or [])) or "nenhum", RR_MIN,
                          ",".join(s for s in sinais if s not in (bt.get("aprovados_g2") or [])) or "nenhum"),
                      "dados": "IPE, DFP, ITR (CVM), COTAHIST (B3, ticker mais liquido do FCA, preco nao ajustado) e Selic over (Ipeadata)"},
        "sinais_aprovados": sinais, "exibir_probabilidade": False, "emissores": emissores,
        "resumo": {"n": len(emissores), "severidade": {k: sum(1 for e in emissores if e["severidade"] == k) for k in ("alta", "media", "baixa")}},
    }
    with open(a.saida, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print(json.dumps({"sinais": sinais, "resumo": payload["resumo"], "saida": a.saida}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
