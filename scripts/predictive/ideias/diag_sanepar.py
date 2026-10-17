"""Hipotese Sanepar: o precatorio (Fato Relevante 24/04/2025) entrou como receita financeira em 2025. A definicao contratual tira
a receita financeira do EBITDA; se o numero apurado pelo agente a manteve, o EBITDA implicito do agente fica acima do meu
na mesma ordem da receita financeira extraordinaria. Teste: comparar (EBITDA implicito do agente - meu EBITDA) com
(receita financeira LTM - receita financeira normal de 2024). So diagnostico, nao muda definicao."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant_contratual as K  # noqa: E402
from comum import SAIDA, emissores, gravar_json  # noqa: E402


def main():
    regra = json.load(open(os.path.join(SAIDA, "dia6", "definicoes_contratuais_v3.json"), encoding="utf-8"))["emissores"]["Sanepar"]
    c = emissores()["Sanepar"]
    base = K.ler_linhas({c}, base="ind")
    agente = {"2025-03-31": 1.1, "2025-06-30": 1.2, "2025-09-30": 0.3, "2025-12-31": 0.4}
    rec_2024 = K.valor_ltm(base, c, "2024-12-31", regra["componentes"]["receita_financeira"], True)
    out = []
    for ref, dl_ag in agente.items():
        _, comp = K.calcular(base, c, ref, regra)
        dl = comp["divida"] - comp["caixa"]
        ebitda_ag = dl / dl_ag
        rec = comp["receita_financeira"]
        out.append({"ref": ref, "divida_liquida_mi": round(dl / 1e6), "meu_ebitda_mi": round(comp["ebitda"] / 1e6),
                    "ebitda_implicito_agente_mi": round(ebitda_ag / 1e6), "gap_ebitda_mi": round((ebitda_ag - comp["ebitda"]) / 1e6),
                    "receita_financeira_ltm_mi": round(rec / 1e6), "receita_financeira_acima_de_2024_mi": round((rec - rec_2024) / 1e6)})
    res = {"receita_financeira_2024_mi": round(rec_2024 / 1e6), "trimestres": out,
           "ressalva": "o agente arredonda a 1 casa (0,3 e 0,4 tem erro de ate 17%), entao o gap dos dois ultimos trimestres e impreciso"}
    gravar_json(os.path.join(SAIDA, "dia6", "sanepar_diagnostico.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
