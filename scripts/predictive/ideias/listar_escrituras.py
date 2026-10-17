"""Dia 4: inventario de escrituras e relatorios de agente fiduciario no IPE local, por emissor (so leitura)."""
import collections
import json
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA, digitos, emissores, gravar_json  # noqa: E402

import dados  # noqa: E402


def classificar(d):
    # categoria e tipo exatos do IPE ("mapa do escriturador" de assembleia NAO e escritura)
    if d["tipo_n"] == "relatorio de agente fiduciario":
        return "relatorio_af"
    if d["cat_n"] == "escrituras e aditamentos de debentures":
        return "aditamento" if "aditamento" in d["assunto_n"] else "escritura"
    return None


def main():
    mapa = emissores()
    por = {c: e for e, c in mapa.items()}
    docs, _ = dados.ler_ipe()
    rot = collections.Counter()
    inv = collections.defaultdict(lambda: collections.defaultdict(list))
    for d in docs:
        c = digitos(d["cnpj"])
        if c not in por or d["data"] < date(2022, 1, 1):
            continue
        k = classificar(d)
        if not k:
            continue
        rot[(k, d["cat_n"], d["tipo_n"], d["especie_n"])] += 1
        inv[por[c]][k].append({"data": str(d["data"]), "protocolo": d["protocolo"], "link": d["link"], "assunto": d["assunto_n"][:160]})
    ambos = sorted(e for e, v in inv.items() if v.get("escritura") and v.get("relatorio_af"))
    res = {"rotulos_ipe": [(list(k), n) for k, n in rot.most_common(15)],
           "emissores_com_escritura_e_relatorio_af": len(ambos), "lista": ambos,
           "inventario": {e: {k: sorted(v, key=lambda x: x["data"])[-6:] for k, v in inv[e].items()} for e in ambos}}
    gravar_json(os.path.join(SAIDA, "dia4", "inventario_escrituras.json"), res)
    print(json.dumps({k: res[k] for k in ("rotulos_ipe", "emissores_com_escritura_e_relatorio_af", "lista")}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
