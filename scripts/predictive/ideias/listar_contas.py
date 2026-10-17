"""Lista contas (codigo, descricao, valor) de um ITR/DFP consolidado, para mapear componentes contratuais pela descricao.
Nao calcula razao nenhuma. Uso: python -I listar_contas.py <cnpj_digitos> <dt_refer> [ano_zip] [filtro_regex]"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, digitos  # noqa: E402

import dados  # noqa: E402

PREFIXOS = ("1.01", "1.02.01", "2.01.04", "2.02.01", "2.01.05", "2.02.02", "2.01.02", "3.", "6.01.01")


def main(cnpj, ref, ano=None, filtro=None):
    ano = ano or ref[:4]
    tipo = "dfp" if ref.endswith("12-31") else "itr"
    dirs = dados.DIRS_DFP if tipo == "dfp" else [os.path.join(RAW, "itr")]
    z = dados._zips(dirs, "%s_cia_aberta_" % tipo)[ano]
    versao = max(int(r["VERSAO"]) for r in dados._csv_do_zip(z, "%s_cia_aberta_%s.csv" % (tipo, ano))
                 if digitos(r["CNPJ_CIA"]) == cnpj and r["DT_REFER"] == ref)
    for dem in ("BPA_con", "BPP_con", "DRE_con", "DFC_MI_con"):
        for r in dados._csv_do_zip(z, "%s_cia_aberta_%s_%s.csv" % (tipo, dem, ano)):
            if digitos(r["CNPJ_CIA"]) != cnpj or r["DT_REFER"] != ref or int(r["VERSAO"]) != versao:
                continue
            if r.get("ORDEM_EXERC", "").upper() not in ("ÚLTIMO", "ULTIMO"):
                continue
            if dem == "DRE_con" and not r.get("DT_INI_EXERC", "").endswith("-01-01"):
                continue
            cd = r["CD_CONTA"]
            if not cd.startswith(PREFIXOS):
                continue
            if filtro and not re.search(filtro, dados.norm(r["DS_CONTA"])) and cd.count(".") > 2:
                continue
            print("%-9s %-16s %-70s %18s" % (dem[:6], cd, r["DS_CONTA"][:70], r["VL_CONTA"]))


if __name__ == "__main__":
    main(*sys.argv[1:])
