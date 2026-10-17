"""Gera dia6/definicoes_contratuais_v3.json = v2 (intacta) + 5 emissores novos, mapeados das escrituras ANTES de ver qualquer razao.
Cada regra cita a clausula. 'reproducibilidade' e pre-registrada: reproduzivel (a definicao inteira cabe nas contas CVM) ou parcial
(a definicao exige itens que as contas padrao nao mostram, listados em 'fora_do_alcance')."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA  # noqa: E402

P = os.path.join(SAIDA, "dia6")
D_BPP = [{"s": 1, "dem": "BPP", "cd": "^2\\.01\\.04$", "porque": "emprestimos, financiamentos e debentures, curto prazo"},
         {"s": 1, "dem": "BPP", "cd": "^2\\.02\\.01$", "porque": "idem, longo prazo"}]
DERIV_PASSIVO = {"s": 1, "dem": "BPP", "cd": "^2\\.0[12]\\.0[25]", "ds": "derivativ", "porque": "saldo liquido de derivativos, passivo"}
DERIV_ATIVO = {"s": -1, "dem": "BPA", "cd": "^1\\.0[12]", "ds": "derivativ", "porque": "saldo liquido de derivativos, ativo"}
CAIXA = [{"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$", "porque": "caixa e equivalentes"},
         {"s": 1, "dem": "BPA", "cd": "^1\\.01\\.02$", "porque": "aplicacoes financeiras"}]
EBIT = {"s": 1, "dem": "DRE", "cd": "^3\\.05$", "porque": "resultado antes do resultado financeiro e dos tributos"}
DA = {"s": 1, "dem": "DFC", "cd": "^6\\.01\\.01\\.", "ds": "deprecia|amortiza", "nao": "juros|emprest|empres|financiament|debent", "porque": "depreciacao e amortizacao"}

NOVOS = {
 "Engie Brasil Energia": {
  "reproducibilidade": "reproduzivel",
  "escritura": {"emissao": 6, "linhas": {"ebitda_consolidado": 1066, "divida_total_consolidada": 1072, "despesas_financeiras_consolidadas": 1089}},
  "componentes": {
   "divida": D_BPP, "caixa": [],
   "ebitda": [EBIT, DA],
   "despesa_financeira": [{"s": -1, "dem": "DRE", "cd": "^3\\.06\\.02$", "porque": "Despesas Financeiras Consolidadas, bruta"}],
   "receita_financeira": []},
  "indices": {"divida_liquida/ebitda": "divida total consolidada (BRUTA, sem caixa) / ebitda", "ebitda/resultado_financeiro": "ebitda / despesas financeiras brutas"},
  "fora_do_alcance": []},
 "Sanepar": {
  "reproducibilidade": "reproduzivel", "base": "ind",
  "escritura": {"emissao": 14, "linhas": {"divida_liquida": 1715, "despesa_financeira_liquida": 1722, "ebitda": 1727}},
  "componentes": {
   "divida": D_BPP,
   "caixa": [{"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$", "porque": "so caixa e equivalentes de caixa"}],
   "ebitda": [{"s": 1, "dem": "DRE", "cd": "^3\\.07$", "porque": "resultado antes de IR e CS"},
              {"s": -1, "dem": "DRE", "cd": "^3\\.06$", "porque": "acrescido das despesas financeiras liquidas das receitas financeiras"},
              DA,
              {"s": 1, "dem": "DFC", "cd": "^6\\.01\\.01\\.", "ds": "contingenc|aposentadoria|previdenc|assistencia medica|plano de saude", "porque": "provisoes para contingencias e planos de aposentadoria e assistencia medica sem efeito caixa"}],
   "despesa_financeira": [{"s": -1, "dem": "DRE", "cd": "^3\\.06\\.02$", "porque": "despesa financeira bruta"}],
   "receita_financeira": [{"s": 1, "dem": "DRE", "cd": "^3\\.06\\.01$", "porque": "receita financeira bruta"}]},
  "indices": {"divida_liquida/ebitda": "(divida - caixa) / ebitda, base INDIVIDUAL como escrito na clausula", "ebitda/resultado_financeiro": "ebitda / (despesa - receita financeira)"},
  "fora_do_alcance": ["a escritura diz despesa financeira 'consolidada' mas EBITDA 'individual'; usei individual nas duas"]},
 "Localiza": {
  "reproducibilidade": "parcial",
  "escritura": {"emissao": 14, "linhas": {"indice_i": 919, "divida_liquida": 931, "ebitda": 941}},
  "componentes": {
   "divida": D_BPP + [DERIV_PASSIVO, DERIV_ATIVO],
   "caixa": CAIXA, "ebitda": [EBIT, DA]},
  "indices": {"divida_liquida/ebitda": "(divida - caixa) / ebitda"},
  "fora_do_alcance": ["contas a receber de cartao de credito deduzidas da divida", "leasing operacional somado a divida", "mutuos com partes relacionadas", "EBITDA soma de volta custo de stock option, despesas nao recorrentes e impairment"]},
 "Energisa": {
  "reproducibilidade": "parcial",
  "escritura": {"emissao": 9, "linhas": {"divida_financeira_liquida": 2150, "ebitda": 2168}},
  "componentes": {
   "divida": D_BPP + [DERIV_PASSIVO, DERIV_ATIVO],
   "caixa": CAIXA, "ebitda": [EBIT, DA]},
  "indices": {"divida_liquida/ebitda": "(divida - caixa) / ebitda"},
  "fora_do_alcance": ["deficit de planos de previdencia e parcelamentos de impostos somados a divida", "recursos a receber da Eletrobras (baixa renda e Luz para Todos), CCC e CDE deduzidos", "EBITDA exclui participacao em coligadas e inclui acrescimo moratorio e subvencao"]},
 "Equatorial Energia": {
  "reproducibilidade": "parcial",
  "escritura": {"emissao": 7, "linhas": {"indice": 1128, "ebitda_ajustado": 1195}},
  "componentes": {
   "divida": D_BPP + [DERIV_PASSIVO, DERIV_ATIVO],
   "caixa": CAIXA + [{"s": 1, "dem": "BPA", "cd": "^1\\.0[12]", "ds": "vinculad|caucao|garantia", "porque": "(e) valores mantidos em garantia por caucao"}],
   "ebitda": [EBIT, DA]},
  "indices": {"divida_liquida/ebitda": "(divida - caixa) / ebitda"},
  "fora_do_alcance": ["valor presente da recuperacao judicial da Equatorial Para somado a divida", "ativos regulatorios liquidos, subvencao baixa renda, depositos judiciais e sub-rogacao da CCC deduzidos", "EBITDA ajustado com itens nao recorrentes"]},
}


def main():
    v2 = json.load(open(os.path.join(P, "definicoes_contratuais_v2.json"), encoding="utf-8"))
    v2["versao"] = "definicoes_contratuais v3"
    v2["adicao_v3"] = "5 emissores novos mapeados das escrituras antes de ver qualquer razao; Dasa, Simpar e Eneva ficam identicos a v2. Regra de selecao de tabela do agente: por emissor e indicador, a tabela com mais trimestres"
    for emp, r in v2["emissores"].items():
        r.setdefault("reproducibilidade", "reproduzivel")
    v2["emissores"].update(NOVOS)
    destino = os.path.join(P, "definicoes_contratuais_v3.json")
    with open(destino, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(v2, fh, ensure_ascii=False, indent=1)
    print(destino)


if __name__ == "__main__":
    main()
