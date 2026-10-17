"""Diagnostico: componentes YTD e LTM por trimestre de um emissor, com as contas casadas. Nao altera definicoes.
Uso: python -I diag_componentes.py <emissor> [definicoes.json]"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant_contratual as K  # noqa: E402
from comum import SAIDA, emissores  # noqa: E402


def main(emp, caminho=os.path.join(SAIDA, "dia6", "definicoes_contratuais_v2.json")):
    regra = json.load(open(caminho, encoding="utf-8"))["emissores"][emp]
    c = emissores()[emp]
    base = K.ler_linhas({c}, base=regra.get("base", "con"))
    for ref in sorted(k[1] for k in base if k[0] == c):
        reg = base[(c, ref)]
        partes = []
        for nome, termos in regra["componentes"].items():
            v, cs = K.componente(reg, termos)
            fluxo = all(t["dem"] in K.FLUXO for t in termos)
            ltm = K.valor_ltm(base, c, ref, termos, fluxo) if fluxo else None
            partes.append("%s=%.0f%s" % (nome, v / 1e6, (" (ltm %.0f)" % (ltm / 1e6)) if ltm is not None else ""))
        calc, _ = K.calcular(base, c, ref, regra)
        print(ref, reg["tipo"], "v%s" % reg["versao"], reg["dt_receb"], "|", "  ".join(partes), "|", calc)


if __name__ == "__main__":
    main(*sys.argv[1:])
