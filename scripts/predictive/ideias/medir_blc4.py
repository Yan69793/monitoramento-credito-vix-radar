"""Dia 1: debentures no bloco 4 do CDA (ativo codificado, sem CNPJ do emissor). Mede campos, tipos e confidencialidade."""
import collections
import csv
import io
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW


def main(mes):
    z = zipfile.ZipFile(os.path.join(RAW, "cda", f"cda_fi_{mes}.zip"))
    r = csv.DictReader(io.TextIOWrapper(z.open(f"cda_fi_BLC_4_{mes}.csv"), encoding="latin-1"), delimiter=";")
    tipos = collections.Counter()
    deb = collections.Counter()
    conf_deb = 0
    amostra = []
    lag = collections.Counter()
    for row in r:
        t = row.get("TP_ATIVO") or ""
        tipos[t] += 1
        if "deb" in t.lower():
            deb[row.get("CD_ATIVO", "")[:4]] += float((row.get("VL_MERC_POS_FINAL") or "0") or 0)
            if row.get("DT_CONFID_APLIC"):
                conf_deb += 1
                lag[row["DT_CONFID_APLIC"][:7]] += 1
            if len(amostra) < 2:
                amostra.append(row)
    print(json.dumps({"campos": r.fieldnames, "tipos": tipos.most_common(12), "deb_prefixos_top": [(k, round(v / 1e9, 2)) for k, v in deb.most_common(15)],
                      "deb_linhas_confid": conf_deb, "deb_prazo_confid_por_mes": sorted(lag.items()), "amostra": amostra}, ensure_ascii=False, indent=0))


if __name__ == "__main__":
    main(sys.argv[1])
