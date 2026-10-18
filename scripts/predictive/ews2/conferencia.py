"""Conferencia automatica do EWS 2.0 contra eventos reais (EWS2CONF1, nota 126, controle "30 e 90 dias").

Tres partes, todas sem LLM e sem API paga:
  registrar  grava o pacote publicado no livro de previsoes (data/ews2-previsoes), congelado, junto com o ews_score do
             EWS atual no mesmo dia. Append-only: a previsao registrada nunca e reescrita.
  conferir   detecta eventos novos (conferencia_eventos.py), compara EWS 2.0 e EWS atual pelo criterio pre-registrado
             em data/validacao/g0v4/conferencia_criterios.json (hash fixado abaixo) e devolve a decisao.
  decidir    funcao pura, sem I/O, usada por conferir e pelos testes.

Decisao: amostra_insuficiente | manter | desligar. Desligar so com evidencia forte (>= min_eventos e teste de sinal
unilateral <= p_max a favor do EWS atual). Quem escreve ews2:flag e a rotina (run_vixradar_ews2_pacote.ps1), nunca este
modulo: aqui so sai o veredito e o relatorio.

Uso:
  python -I conferencia.py registrar --pacote P.json [--historico DIR] [--livro DIR]
  python -I conferencia.py conferir [--hoje AAAA-MM-DD] [--livro DIR] [--relatorio ARQ] [--sem-rede]
Exit: 0 manter ou amostra insuficiente | 9 desligar | 2 entrada invalida (criterio alterado, livro vazio)
"""
import argparse
import datetime as dt
import hashlib
import json
import math
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
LIVRO = os.path.join(BASE, "data", "ews2-previsoes")
HISTORICO = os.path.join(BASE, "data", "historico")
CRITERIOS = os.path.join(BASE, "data", "validacao", "g0v4", "conferencia_criterios.json")
# sha256 do arquivo de criterios com fim de linha normalizado para LF. Mudar o criterio depois de ver resultado e
# exatamente o que esta trava impede: o hash diverge, a conferencia recusa rodar (exit 2).
CRITERIOS_SHA256 = "110c426a2f318ef92a354e9814aa331885aa783d1ba7fcccf69d1a08d85cf98f"
SEV = {"alta": 2, "media": 1, "baixa": 0}
EPISODIO_DIAS = 30
PREVALENCIA_DIAS = 365


def sha_normalizado(caminho):
    with open(caminho, "rb") as fh:
        b = fh.read().replace(b"\r\n", b"\n")
    return hashlib.sha256(b).hexdigest()


def _json(caminho, enc="utf-8"):
    with open(caminho, encoding=enc) as fh:
        return json.load(fh)


def ler_criterios(caminho=CRITERIOS, sha=None):
    sha = CRITERIOS_SHA256 if sha is None else sha
    real = sha_normalizado(caminho)
    if real != sha:
        raise SystemExit("criterios alterados: sha256 %s diferente do pre-registrado %s" % (real, sha))
    return _json(caminho)


def _d(s):
    return dt.date.fromisoformat(s) if isinstance(s, str) else s


# ---------------------------------------------------------------- decisao pura
def percentil(valor, todos):
    """Posicao do valor entre todos (incluindo ele), empates pelo ponto medio, em [0, 1]."""
    menor = sum(1 for x in todos if x < valor)
    igual = sum(1 for x in todos if x == valor)
    return (menor + 0.5 * igual) / len(todos)


def p_sinal_unilateral(k, n):
    """P(X >= k), X ~ Binomial(n, 0,5). Exato."""
    if n == 0:
        return 1.0
    return sum(math.comb(n, i) for i in range(k, n + 1)) / 2 ** n


def episodios_de_eventos(eventos):
    """Funde eventos do mesmo emissor a ate EPISODIO_DIAS. Devolve [{cnpj, inicio, ultimo, prev_cat_a}] ordenado;
    prev_cat_a vem do evento que abre o episodio (emissor ja em RJ/RE por documento de categoria A nos 730 dias antes)."""
    out = []
    atual = None
    for e in sorted(eventos, key=lambda x: (x["cnpj"], _d(x["data"]))):
        d = _d(e["data"])
        if atual and atual["cnpj"] == e["cnpj"] and (d - atual["ultimo"]).days <= EPISODIO_DIAS:
            atual["ultimo"] = d
            continue
        atual = {"cnpj": e["cnpj"], "inicio": d, "ultimo": d, "prev_cat_a": bool(e.get("prev_cat_a"))}
        out.append(atual)
    return out


def decidir(snapshots, eventos, criterios, hoje):
    """snapshots: [{data_obs, ews2:{cnpj:'alta'|'media'|'baixa'}, atual:{cnpj:score}}]; eventos: [{cnpj, data}] (qualquer
    data: os anteriores ao primeiro snapshot servem so de prevalencia). Devolve o veredito e os numeros que o sustentam."""
    hoje = _d(hoje)
    snaps = sorted(({**s, "data_obs": _d(s["data_obs"])} for s in snapshots), key=lambda s: s["data_obs"])
    eps = episodios_de_eventos(eventos)
    horizonte = dt.timedelta(days=180)
    linhas, excluidos = [], []
    primeiro = snaps[0]["data_obs"] if snaps else None
    for ep in eps:
        if primeiro is None or ep["inicio"] <= primeiro or ep["inicio"] > hoje:
            continue
        if ep["prev_cat_a"]:
            excluidos.append({"cnpj": ep["cnpj"], "inicio": ep["inicio"].isoformat(), "motivo": "prevalente_categoria_a"})
            continue
        # prevalencia: outro episodio do mesmo emissor nos 365 dias antes do inicio
        if any(o["cnpj"] == ep["cnpj"] and o is not ep and 0 < (ep["inicio"] - o["ultimo"]).days <= PREVALENCIA_DIAS for o in eps):
            excluidos.append({"cnpj": ep["cnpj"], "inicio": ep["inicio"].isoformat(), "motivo": "prevalente"})
            continue
        # ultimo pacote publicado antes do evento, dentro do horizonte
        s = next((x for x in reversed(snaps) if x["data_obs"] < ep["inicio"]), None)
        if s is None or ep["inicio"] - s["data_obs"] > horizonte:
            excluidos.append({"cnpj": ep["cnpj"], "inicio": ep["inicio"].isoformat(), "motivo": "sem_pacote_no_horizonte"})
            continue
        if ep["cnpj"] not in s["ews2"] or ep["cnpj"] not in s["atual"] or s["atual"][ep["cnpj"]] is None:
            excluidos.append({"cnpj": ep["cnpj"], "inicio": ep["inicio"].isoformat(), "motivo": "emissor_fora_do_pacote_ou_sem_ews_atual"})
            continue
        comuns = [c for c in s["ews2"] if c in s["atual"] and s["atual"][c] is not None]
        e2 = [SEV[s["ews2"][c]] for c in comuns]
        ea = [s["atual"][c] for c in comuns]
        p2 = percentil(SEV[s["ews2"][ep["cnpj"]]], e2)
        pa = percentil(s["atual"][ep["cnpj"]], ea)
        linhas.append({"cnpj": ep["cnpj"], "inicio": ep["inicio"].isoformat(), "pacote": s["data_obs"].isoformat(),
                       "sev_ews2": s["ews2"][ep["cnpj"]], "score_atual": s["atual"][ep["cnpj"]],
                       "pct_ews2": round(p2, 4), "pct_atual": round(pa, 4)})
    n = len(linhas)
    dif = [(l["pct_atual"] - l["pct_ews2"]) for l in linhas if abs(l["pct_atual"] - l["pct_ews2"]) > 1e-9]
    k = sum(1 for x in dif if x > 0)
    p = p_sinal_unilateral(k, len(dif))
    m2 = sum(l["pct_ews2"] for l in linhas) / n if n else None
    ma = sum(l["pct_atual"] for l in linhas) / n if n else None
    out = {"hoje": hoje.isoformat(), "pacotes": len(snaps), "primeiro_pacote": primeiro.isoformat() if primeiro else None,
           "eventos_independentes": n, "excluidos": excluidos, "eventos": linhas,
           "pct_medio_ews2": None if m2 is None else round(m2, 4), "pct_medio_atual": None if ma is None else round(ma, 4),
           "eventos_com_diferenca": len(dif), "eventos_atual_melhor": k, "p_sinal": round(p, 6),
           "min_eventos": criterios["min_eventos"], "p_max": criterios["p_max"], "criterios": criterios["versao"]}
    if n < criterios["min_eventos"]:
        out["decisao"] = "amostra_insuficiente"
        out["motivo"] = "%d evento(s) independente(s), minimo %d: relatorio descritivo, nada a decidir" % (n, criterios["min_eventos"])
    elif ma > m2 and p <= criterios["p_max"]:
        out["decisao"] = "desligar"
        out["motivo"] = "EWS atual ranqueia os eventos acima do EWS 2.0 (percentil medio %.3f contra %.3f, %d de %d diferencas, p=%.4f <= %.2f)" % (
            ma, m2, k, len(dif), p, criterios["p_max"])
    else:
        out["decisao"] = "manter"
        out["motivo"] = "sem evidencia de que o EWS 2.0 seja pior (percentil medio %.3f contra %.3f do EWS atual, p=%.4f)" % (m2, ma, p)
    return out


# ---------------------------------------------------------------- livro de previsoes
def ews_atual_do_dia(data_obs, mapa_nomes, historico=HISTORICO):
    """ews_score do EWS atual por CNPJ no dia da observacao (export diario data/historico/AAAA-MM-DD/predictive.json).
    Dia sem export: recua ate 5 dias. Devolve ({cnpj: score|None}, dia_usado|None)."""
    d = _d(data_obs)
    for volta in range(0, 6):
        dia = d - dt.timedelta(days=volta)
        p = os.path.join(historico, dia.isoformat(), "predictive.json")
        if os.path.exists(p):
            j = _json(p, "utf-8-sig")
            por_nome = {}
            for e in j.get("emissores") or []:
                sc = (e.get("features") or {}).get("ews_score")
                if sc is None:
                    sc = (e.get("predictive_v1") or {}).get("ews_score")
                por_nome[str(e.get("name") or "").lower().strip()] = sc
            return {c: por_nome.get(n.lower().strip()) for n, c in mapa_nomes.items()}, dia.isoformat()
    return {c: None for c in mapa_nomes.values()}, None


def registrar(pacote, livro=LIVRO, historico=HISTORICO):
    """Congela o pacote publicado. Idempotente por (data_obs, sha256 do pacote): repetir nao duplica nem reescreve."""
    with open(pacote, "rb") as fh:
        raw = fh.read()
    p = json.loads(raw.decode("utf-8-sig"))
    sha = hashlib.sha256(raw).hexdigest()
    os.makedirs(livro, exist_ok=True)
    alvo = os.path.join(livro, "%s_%s.json" % (p["data_observacao"], sha[:12]))
    if os.path.exists(alvo):
        return {"ok": True, "novo": False, "arquivo": alvo}
    mapa = {e["nome"]: e["cnpj"] for e in p["emissores"]}
    atual, dia = ews_atual_do_dia(p["data_observacao"], mapa, historico)
    reg = {"data_obs": p["data_observacao"], "gerado_em": p.get("gerado_em"), "sha256_pacote": sha,
           "registrado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
           "sinais_aprovados": p.get("sinais_aprovados"), "ews_atual_dia": dia,
           "ews2": {e["cnpj"]: e["severidade"] for e in p["emissores"]}, "atual": atual,
           "atual_ausentes": sorted(c for c, v in atual.items() if v is None)}
    tmp = alvo + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, alvo)
    return {"ok": True, "novo": True, "arquivo": alvo, "ews_atual_dia": dia, "atual_ausentes": len(reg["atual_ausentes"])}


def ler_livro(livro=LIVRO):
    out = []
    if os.path.isdir(livro):
        for f in sorted(os.listdir(livro)):
            if f.endswith(".json"):
                out.append(_json(os.path.join(livro, f)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("registrar")
    r.add_argument("--pacote", required=True)
    r.add_argument("--livro", default=LIVRO)
    r.add_argument("--historico", default=HISTORICO)
    c = sub.add_parser("conferir")
    c.add_argument("--hoje", default=dt.date.today().isoformat())
    c.add_argument("--livro", default=LIVRO)
    c.add_argument("--relatorio")
    c.add_argument("--sem-rede", action="store_true")
    c.add_argument("--eventos-json", help="so teste: lista [{cnpj, data}] no lugar da deteccao; o relatorio marca fonte=arquivo")
    a = ap.parse_args(argv)
    if a.cmd == "registrar":
        print(json.dumps(registrar(a.pacote, a.livro, a.historico), ensure_ascii=False))
        return 0
    crit = ler_criterios()
    snaps = ler_livro(a.livro)
    if not snaps:
        print(json.dumps({"ok": False, "motivo": "livro de previsoes vazio"}))
        return 2
    if a.eventos_json:
        evs, det = _json(a.eventos_json), {"fonte": "arquivo", "arquivo": a.eventos_json}
    else:
        import conferencia_eventos as CE
        evs, det = CE.eventos(_d(a.hoje), sem_rede=a.sem_rede, primeiro_pacote=min(_d(s["data_obs"]) for s in snaps))
    res = decidir(snaps, evs, crit, a.hoje)
    res["deteccao"] = det
    if a.relatorio:
        os.makedirs(os.path.dirname(a.relatorio), exist_ok=True)
        with open(a.relatorio, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
    print(json.dumps({k: res[k] for k in ("decisao", "motivo", "eventos_independentes", "pacotes", "p_sinal", "pct_medio_ews2", "pct_medio_atual")}, ensure_ascii=False))
    return 9 if res["decisao"] == "desligar" else 0


if __name__ == "__main__":
    sys.exit(main())
