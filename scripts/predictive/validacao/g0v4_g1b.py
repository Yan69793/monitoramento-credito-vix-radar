"""G0-v4: G1b com rotulo final consolidado, origens de continuacao resolvidas e regua de K (nota 120 item 4).

Regua de K (G0-v1 itens 1 e 6): evento com data na janela 01/01/2011 a 30/09/2026, CNPJ com periodo de registro vigente
na data (cad_cia_aberta.csv, cancelamento conta ate o proprio dia) e fora de securitizadora (SETOR_ATIV casa
"securitiza" ou DENOM_SOCIAL casa "securitiz"; o protocolo tambem olha o Nome_Companhia do IPE, que aqui nao entra,
declarado). Evento fora da regua nao entra em K nem conta como perdido.

Origem de continuacao: datas validas de tres fontes (G0-v4 com origem completa, revisor, adjudicador). Todas entram;
se distam mais de 30 dias, o item vai como origem divergente (g1b_v2: na uniao fica fora de K; em G conta na menor
origem nao coberta). Limitacao: a origem do G0-v4 e o primeiro documento com disparo nos 180 dias, nao nos 24 meses.
Evento adicional nao entra (nao revisado), o que so poderia subir o limite. incerto conta como o protocolo manda.

Uso: python -I g0v4_g1b.py   (grava data/validacao/g0v4/g1b_g0v4.json)
"""
import csv
import datetime as dt
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import e1_eventos as V0  # noqa: E402
import g0v4_final as F  # noqa: E402
import g0v4_portoes as PT  # noqa: E402
import g0v4_processar as PR  # noqa: E402
import g1b_v2 as GB  # noqa: E402
from dimensionar_g1b import u_sup  # noqa: E402

CAD = os.path.join(PR.BASE, "data", "cvm", "cad_cia_aberta.csv")
TAM = {"F": (402, 210), "W": (2505, 540)}


def regua(cad):
    def no_escopo(cnpj, d):
        if not (V0.JANELA_INI <= d <= V0.JANELA_FIM):
            return False
        per = cad.get(cnpj) or []
        p = V0.periodo_vigente(per, d)
        if p is None:
            return False
        if any(re.search("securitiza", V0.norm(x.get("setor_ativ", ""))) or re.search("securitiz", V0.norm(x.get("denom_social", ""))) for x in per):
            return False
        return True
    return no_escopo


def origens(i, reg, rev, adj):
    ds = set()
    o = reg.get("origem") or {}
    if reg["classe"] == "continuacao" and o.get("completa") and F.data_valida(o.get("data_entrega")):
        ds.add(o["data_entrega"][:10])
    for d in ((rev.get(i) or {}).get("origem_data"), (adj.get(i) or {}).get("origem_data")):
        if F.data_valida(d):
            ds.add(d[:10])
    return sorted(dt.date.fromisoformat(x) for x in ds)


def montar(regs, fin, rev, adj, mapa, esc):
    uni, G, fora = [], [], {"uniao": 0, "G": 0}
    for i, f in fin.items():
        r, c = regs[i], f["classe_final"]
        dcand = dt.date.fromisoformat(r["data"])
        it = {"cnpj": r["cnpj"], "classe": c if c in ("evento_proprio", "continuacao", "incerto") else "nao_evento", "data": dcand,
              "adicionais": [], "divergente": False, "estrato": mapa[i]["estrato"], "id": i}
        if c == "evento_proprio":
            de = f["data_evento_final"]
            it["data_evento"] = dt.date.fromisoformat(de[:10]) if F.data_valida(de) else dcand
            it["no_escopo"] = esc(r["cnpj"], it["data_evento"])
        elif c == "continuacao":
            os_ = origens(i, r, rev, adj)
            it["origens"] = [(None, d, esc(r["cnpj"], d)) for d in os_]
            it["divergente"] = bool(os_) and (os_[-1] - os_[0]).days > 30
        evs = GB.eventos_do_item(it)[0]
        if c in ("evento_proprio", "continuacao") and evs is None:
            fora[mapa[i]["origem"]] += 1
        (uni if mapa[i]["origem"] == "uniao" else G).append(it)
    return uni, G, fora


def main(saida=PR.SAIDA):
    regs = PT.regs_oficiais(saida)
    fin = {r["id"]: r for r in csv.DictReader(open(os.path.join(saida, "rotulo_final_provisorio.csv"), encoding="utf-8-sig"), delimiter=";")}
    rev = F.revisoes(saida)
    adj = F.carregar_jsonl(os.path.join(saida, "adjudicacoes_luna.jsonl"))
    mapa = json.load(open(os.path.join(PR.ETAPA, "mapa_camadas.json"), encoding="utf-8"))
    esc = regua(V0.ler_cad(CAD))
    uni, G, fora = montar(regs, fin, rev, adj, mapa, esc)
    K, nos = GB.K_v2(uni)
    perd = GB.perdidos_v2(G, nos)
    x = GB.x_por_estrato_v2(perd, TAM)
    ok, U, revoc = GB.g1b_v2(K, x, TAM)
    # contra-prova de sensibilidade: so eventos confirmados (incerto de G NAO conta)
    G_sem_inc = [dict(it, classe="nao_evento") if it["classe"] == "incerto" else it for it in G]
    x2 = GB.x_por_estrato_v2(GB.perdidos_v2(G_sem_inc, nos), TAM)
    ok2, U2, rev2 = GB.g1b_v2(K, x2, TAM)
    out = {"K": K, "M_max": K // 9, "x": x, "U_F_mais_U_W": U, "revocacao_uniao": round(revoc, 4), "passa": ok,
           "sensibilidade_sem_incerto_de_G": {"x": x2, "U": U2, "revocacao_uniao": round(rev2, 4), "passa": ok2},
           "eventos_fora_da_regua": fora,
           "G": {"eventos_proprio": sum(1 for it in G if it["classe"] == "evento_proprio"), "continuacao": sum(1 for it in G if it["classe"] == "continuacao"),
                 "incerto": sum(1 for it in G if it["classe"] == "incerto"), "episodios_perdidos": len(perd)},
           "uniao": {"evento_proprio": sum(1 for it in uni if it["classe"] == "evento_proprio"), "continuacao": sum(1 for it in uni if it["classe"] == "continuacao"),
                     "incerto": sum(1 for it in uni if it["classe"] == "incerto"),
                     "continuacao_divergente": sum(1 for it in uni if it["classe"] == "continuacao" and it["divergente"])},
           "gerado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    json.dump(out, open(os.path.join(saida, "g1b_g0v4.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print(json.dumps(out, ensure_ascii=False, indent=1, default=str))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
