"""Dia 2: controles do spread residual.

1. Prova de duas pontas do teste de vazamento: uma versao com vazamento (z_spread com media do historico inteiro)
   precisa ser REPROVADA pelo mesmo teste que a versao correta passa.
2. Sensibilidade declarada (fora dos criterios congelados): so fator de mercado, sem setor.
3. Episodios avaliaveis: incidentes (regras EWS 2.0) com inicio entre a primeira data avaliavel e o ultimo rotulo.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spread_residual as S  # noqa: E402
import test_ideias_spread as T  # noqa: E402
from comum import HISTORICO, SAIDA, gravar_json  # noqa: E402


def z_vazado(series, emp, d, calendario):
    xs = [series[emp][x][0] for x in calendario if x in series[emp]]  # usa o futuro de proposito
    if len(xs) < S.MIN_DIAS_Z or d not in series[emp]:
        return None
    mean = sum(xs) / len(xs)
    sd = math.sqrt(sum((x - mean) ** 2 for x in xs) / len(xs))
    return (series[emp][d][0] - mean) / sd if sd > 0 else 0.0


def teste_vazamento(mod_z):
    base, setores, cal = T.sintetico()
    fut, _, _ = T.sintetico(futuro={"emp": "E05", "depois_de": 90, "valor": 3.0})
    orig = S.z_spread
    S.z_spread = mod_z
    try:
        a, b = S.avaliar(base, setores), S.avaliar(fut, setores)
    finally:
        S.z_spread = orig
    corte = cal[90]
    za = [(x["emp"], x["data"], x["z"]) for x in a["z_alertas"] if x["data"] <= corte]
    zb = [(x["emp"], x["data"], x["z"]) for x in b["z_alertas"] if x["data"] <= corte]
    return za == zb


def main():
    res = {"vazamento_versao_correta_passa": teste_vazamento(S.z_spread),
           "vazamento_versao_vazada_reprovada": not teste_vazamento(z_vazado)}
    pastas = sorted(p for p in os.listdir(HISTORICO) if os.path.exists(os.path.join(HISTORICO, p, "series_full.json.gz")))
    series = S.carregar_series(os.path.join(HISTORICO, pastas[-1], "series_full.json.gz"))
    setores = S.carregar_setores()
    so_mercado = S.avaliar(series, setores, usar_setor=False)
    res["sensibilidade_so_mercado"] = {"emissor_dias_avaliaveis": so_mercado["emissor_dias_avaliaveis"],
                                       "emissor_dias_instaveis": so_mercado["emissor_dias_instaveis"],
                                       "cobertura": round(so_mercado["emissor_dias_avaliaveis"] / so_mercado["emissor_dias_possiveis"], 3),
                                       "alertas": len(so_mercado["alertas"]),
                                       "primeira_data_avaliavel": str(so_mercado["primeira_data_avaliavel"])}
    with open(os.path.join(SAIDA, "dia1", "medicoes_dia1.json"), encoding="utf-8") as fh:
        med = json.load(fh)
    ini = str(so_mercado["primeira_data_avaliavel"])
    fim = med["eventos"]["data_max_rotulo"]
    res["episodios_avaliaveis"] = [e for e in med["eventos"]["incidentes_na_janela_spread"] if ini <= e[1] <= fim]
    res["janela_rotulada_avaliavel"] = [ini, fim]
    gravar_json(os.path.join(SAIDA, "dia2", "controles_spread.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
