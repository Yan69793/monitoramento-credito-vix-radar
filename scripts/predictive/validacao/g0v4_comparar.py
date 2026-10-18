"""G0-v4: compara classificacoes locais com os 150 rotulos legados G0-v3 (referencia, NUNCA alterada).

Falso negativo material = legado evento_proprio/continuacao e G0-v4 nao_evento (automatico, sem revisao).
PENDENTE_REVISAO nao e falso negativo: e encaminhamento a revisao. Mede tambem a taxa de pendentes por classe legada.
Uso: python -I g0v4_comparar.py CLASSIFICACOES.jsonl ROTULOS_LEGADOS.csv [--json SAIDA]
"""
import collections
import csv
import json
import sys

MATERIAL = ("evento_proprio", "continuacao")


def carregar(cls, leg):
    novo = {}
    for ln in open(cls, encoding="utf-8"):
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        novo[r["id"]] = r
    antigo = {}
    with open(leg, encoding="utf-8-sig", newline="") as fh:
        for r in csv.DictReader(fh, delimiter=";"):
            antigo.setdefault(r["id"], r)  # primeira linha por id (so ha uma)
    return novo, antigo


def comparar(novo, antigo):
    ids = sorted(set(novo) & set(antigo))
    mat = collections.Counter()
    fn, pend_mat, discord = [], [], []
    for i in ids:
        a, n = antigo[i]["classe1"], novo[i]["classe"]
        mat[(a, n)] += 1
        if a in MATERIAL and n == "nao_evento":
            fn.append(i)
        if a in MATERIAL and n == "PENDENTE_REVISAO":
            pend_mat.append(i)
        if a == "evento_proprio" and n == "evento_proprio":
            d1, d2 = antigo[i]["data_evento1"], novo[i].get("data_evento")
            if d1 and d2 and d1 != d2:
                discord.append((i, d1, d2))
    ep_leg = [i for i in ids if antigo[i]["classe1"] == "evento_proprio"]
    return {"n_comparados": len(ids), "matriz": {"%s->%s" % k: v for k, v in sorted(mat.items())},
            "falsos_negativos_materiais": fn, "materiais_legados": sum(1 for i in ids if antigo[i]["classe1"] in MATERIAL),
            "materiais_em_revisao": pend_mat, "evento_proprio_legado": len(ep_leg),
            "evento_proprio_nao_capturado_como_ep_ou_revisao": [i for i in ep_leg if novo[i]["classe"] in ("nao_evento", "evento_terceiro")],
            "datas_divergentes_em_ep": discord,
            "legado_nao_evento_para_positivo": [i for i in ids if antigo[i]["classe1"] == "nao_evento" and novo[i]["classe"] in MATERIAL + ("evento_terceiro",)],
            "pendentes": sum(1 for i in ids if novo[i]["classe"] == "PENDENTE_REVISAO")}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        print(__doc__)
        return 2
    novo, antigo = carregar(argv[0], argv[1])
    r = comparar(novo, antigo)
    print(json.dumps(r, ensure_ascii=False, indent=1))
    if "--json" in argv:
        json.dump(r, open(argv[argv.index("--json") + 1], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return 1 if r["falsos_negativos_materiais"] else 0


if __name__ == "__main__":
    sys.exit(main())
