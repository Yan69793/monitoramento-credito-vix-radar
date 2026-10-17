"""Diagnostico: linhas 6.01.01.* (ajustes ao lucro) do DFC consolidado de um emissor, por referencia. Uso: python -I diag_dfc.py <emissor> <ref> [<ref>...]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant_contratual as K  # noqa: E402
from comum import emissores  # noqa: E402


def main(emp, *refs):
    c = emissores()[emp]
    base = K.ler_linhas({c})
    todas = {}
    for ref in refs:
        for cd, ds, v in base[(c, ref)]["linhas"]["DFC"]:
            if cd.startswith("6.01.01.") and cd.count(".") == 3:
                todas.setdefault((cd, ds[:70]), {})[ref] = v / 1e6
    print("%-14s %-70s %s" % ("conta", "descricao", " ".join("%10s" % r[2:] for r in refs)))
    for (cd, ds), d in sorted(todas.items()):
        print("%-14s %-70s %s" % (cd, ds, " ".join("%10.0f" % d.get(r, float("nan")) for r in refs)))


if __name__ == "__main__":
    main(sys.argv[1], *sys.argv[2:])
