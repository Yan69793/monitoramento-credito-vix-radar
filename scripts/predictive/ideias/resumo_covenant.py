"""Dia 4: concordancia do calculo padronizado (contas CVM) com o apurado pelo agente fiduciario. Tolerancia congelada: 5%."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA, gravar_json  # noqa: E402

TOL = 5.0


def main():
    dados = json.load(open(os.path.join(SAIDA, "dia4", "covenant_resultado.json"), encoding="utf-8"))
    linhas, por_emissor = [], {}
    for r in dados:
        for c in r["comparacao"]:
            if c["apurado_af"] is None or c["calculado_cvm"] is None:
                continue
            ok = abs(c["diferenca_pct"]) <= TOL
            sinal_igual = (c["margem_af"] >= 0) == (c["margem_cvm"] >= 0)
            linhas.append({"emissor": r["emissor"], "indicador": c["indicador"], "ref": c["ref"], "dif_pct": c["diferenca_pct"], "dentro_5pct": ok,
                           "mesmo_lado_do_limite": sinal_igual, "limite_escritura_confere": c["limite_confere"]})
            por_emissor.setdefault((r["emissor"], c["indicador"]), []).append(ok)
    n = len(linhas)
    res = {"pares_comparaveis": n, "dentro_de_5pct": sum(1 for x in linhas if x["dentro_5pct"]),
           "concordancia": round(sum(1 for x in linhas if x["dentro_5pct"]) / n, 3) if n else None,
           "mesmo_lado_do_limite": sum(1 for x in linhas if x["mesmo_lado_do_limite"]),
           "limite_da_escritura_igual_ao_do_agente": sum(1 for x in linhas if x["limite_escritura_confere"]),
           "por_emissor_indicador": {"%s | %s" % k: "%d de %d" % (sum(v), len(v)) for k, v in por_emissor.items()},
           "criterio_congelado": {"concordancia_minima": 0.90, "precisao_extracao_minima": 0.95, "escrituras_para_aprovar": 20}}
    gravar_json(os.path.join(SAIDA, "dia4", "covenant_concordancia.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
