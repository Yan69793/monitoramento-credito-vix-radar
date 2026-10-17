"""Dia 1: cobertura do CDA para os 104 emissores, por bloco e por mes. Saida JSON em stdout."""
import collections
import csv
import io
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, digitos, emissores


def medir_zip(caminho, alvo):
    z = zipfile.ZipFile(caminho)
    out = {}
    for nome in z.namelist():
        if "_BLC_" not in nome:
            continue
        blc = nome.split("_BLC_")[1].split("_")[0]
        r = csv.DictReader(io.TextIOWrapper(z.open(nome), encoding="latin-1"), delimiter=";")
        n = com_cnpj = confid = 0
        tipos = collections.Counter()
        val = collections.Counter()
        fundos = collections.defaultdict(set)
        for row in r:
            n += 1
            c = digitos(row.get("CPF_CNPJ_EMISSOR"))
            if c:
                com_cnpj += 1
            if row.get("DT_CONFID_APLIC"):
                confid += 1
            if c in alvo:
                tipos[row.get("TP_ATIVO") or row.get("TP_APLIC") or ""] += 1
                val[alvo[c]] += float((row.get("VL_MERC_POS_FINAL") or "0").replace(",", ".") or 0)
                fundos[alvo[c]].add(row.get("CNPJ_FUNDO_CLASSE"))
        out[blc] = {"linhas": n, "com_cnpj_emissor": com_cnpj, "com_prazo_confid": confid,
                    "emissores_alvo": len(val), "valor_alvo_rs_bi": round(sum(val.values()) / 1e9, 2),
                    "tipos_alvo": tipos.most_common(6), "top5": [(k, round(v / 1e9, 2), len(fundos[k])) for k, v in val.most_common(5)]}
    return out


def main():
    alvo = {c: e for e, c in emissores().items()}
    pasta = os.path.join(RAW, "cda")
    res = {}
    for nome in sorted(os.listdir(pasta)):
        if nome.startswith("cda_fi_2") and nome.endswith(".zip"):
            res[nome[7:13]] = medir_zip(os.path.join(pasta, nome), alvo)
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
