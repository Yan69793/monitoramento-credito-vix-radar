"""dia6/definicoes_contratuais_v4.json = v3 (intacta) + Assai, unico emissor do lote 3 com tabela do agente. Classificada antes de calcular."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA  # noqa: E402
from gerar_definicoes_v3 import CAIXA, D_BPP, DA, EBIT  # noqa: E402

P = os.path.join(SAIDA, "dia6")
ASSAI = {
 "reproducibilidade": "parcial",
 "escritura": {"emissao": 10, "clausula": "6.1.4 (i) e (ii), definicoes logo antes de 6.1.5"},
 "componentes": {"divida": D_BPP, "caixa": CAIXA, "ebitda": [EBIT, DA]},
 "indices": {"divida_liquida/ebitda": "(divida - caixa) / ebitda"},
 "fora_do_alcance": ["contas a receber de cartao de credito, vale-alimentacao e multibeneficios, com desagio de 1,5%, deduzidas da divida",
                     "EBITDA so com receitas e despesas recorrentes; a redacao da clausula e ambigua sobre despesas gerais e de vendas"]}


def main():
    v3 = json.load(open(os.path.join(P, "definicoes_contratuais_v3.json"), encoding="utf-8"))
    v3["versao"] = "definicoes_contratuais v4"
    v3["adicao_v4"] = "Assai (lote 3), classificada parcial antes de calcular; demais emissores identicos a v3"
    v3["emissores"]["Assaí Atacadista"] = ASSAI
    destino = os.path.join(P, "definicoes_contratuais_v4.json")
    with open(destino, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(v3, fh, ensure_ascii=False, indent=1)
    print(destino)


if __name__ == "__main__":
    main()
