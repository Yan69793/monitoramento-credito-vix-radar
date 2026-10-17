"""Compara a extracao com rotulos congelados. Uso: python -I avaliar_extracao.py <rotulos.json>"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant as C  # noqa: E402
from comum import SAIDA, gravar_json  # noqa: E402


def main(caminho):
    rot = json.load(open(caminho, encoding="utf-8"))["covenants"]
    prov = [json.loads(l) for l in open(os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl"), encoding="utf-8")]
    tot = {"reais": 0, "achados_certos_indicador": 0, "campos_certos": 0, "campos_conferidos": 0, "falsos_positivos": 0, "perdidos": 0}
    det = []
    for emp, esperado in rot.items():
        esc = [p for p in prov if p["emissor"] == emp and p["papel"] == "escritura"][-1]
        txt = open(esc["arquivo_txt"], encoding="utf-8", errors="ignore").read()
        ext = [(c["indicador"], c["operador"], c["limite"], c["forma_da_clausula"]) for c in C.extrair_escritura(txt)]
        usados = set()
        tot["reais"] += len(esperado)
        for ind, op, lim in esperado:
            cand = [i for i, e in enumerate(ext) if i not in usados and e[0] == ind]
            cand = sorted(cand, key=lambda i: (abs(ext[i][2] - lim), ext[i][1] != op))
            if not cand:
                tot["perdidos"] += 1
                det.append({"emissor": emp, "esperado": [ind, op, lim], "extraido": None})
                continue
            i = cand[0]
            usados.add(i)
            e = ext[i]
            ok = 1 + (e[1] == op) + (abs(e[2] - lim) < 1e-9)
            tot["achados_certos_indicador"] += 1
            tot["campos_certos"] += ok
            tot["campos_conferidos"] += 3
            det.append({"emissor": emp, "esperado": [ind, op, lim], "extraido": list(e), "campos_certos": ok})
        for i, e in enumerate(ext):
            if i not in usados:
                tot["falsos_positivos"] += 1
                det.append({"emissor": emp, "esperado": None, "extraido": list(e), "falso_positivo": True})
    tot["recall"] = round(tot["achados_certos_indicador"] / tot["reais"], 3) if tot["reais"] else None
    tot["acuracia_campos_nos_achados"] = round(tot["campos_certos"] / tot["campos_conferidos"], 3) if tot["campos_conferidos"] else None
    saida = os.path.join(SAIDA, "dia6", "avaliacao_" + os.path.basename(caminho))
    gravar_json(saida, {"totais": tot, "detalhe": det})
    print(json.dumps(tot, ensure_ascii=False))
    for d in det:
        if d.get("falso_positivo") or d.get("extraido") is None or d.get("campos_certos", 3) < 3:
            print(d)


if __name__ == "__main__":
    main(sys.argv[1])
