"""Sinais H1-H8 e benchmarks B1-B3 (G0-v1 itens 5, 7 e 8), calculados em T so com informacao de Data_Entrega ou
DT_RECEB <= T-1 (item 1). Toda funcao recebe T e os dados ja ordenados por data; nada aqui olha o alvo.

Definicoes literais do bloco G0-v1:
  H1  >= 1 documento intermediario (categoria casa 'assembleia' e tipo/especie/assunto casa debentur|titulares de
      valores mobiliarios|titulares de deb) nos 180 dias ate T-1
  H2a DFP com DT_RECEB > 31/03 do ano seguinte ao exercicio, ou ITR > 45 dias apos o fim do trimestre, nos 365 dias ate T-1
  H2b DFP ou ITR com VERSAO >= 2 e DT_RECEB nos 365 dias ate T-1
  H2c parecer 'relatorio do auditor independente' com 'continuidade operacional' no demonstrativo vigente em T
  H3  docs IPE (exceto categoria A) nos 90 dias ate T-1 / media trimestral dos 24 meses anteriores <= 0,5, com media >= 3
  H4  assunto casa (renuncia|desligamento|substituicao|deixa o cargo|destituicao) E (diretor financeiro|\bcfo\b|relacoes com investidores|\bdri\b), 365 dias ate T-1
  H5  DD = [ln((E+F)/F) + (r - 0,5 sigmaV^2)] / sigmaV, sigmaV = (E/(E+F)) sigmaE + (F/(E+F)) (0,05 + 0,25 sigmaE),
      F = PC + 0,5 PNC (BPP vigente), E = fechamento x (acoes integralizadas - tesouraria), precos COTAHIST divididos pelo
      FATCOT e ajustados por desdobramento/grupamento (dados.ajustar_capital, 18/10/2026), sigmaE = desvio do log-retorno
      diario de 252 pregoes ate T-1 anualizado, r = Selic em T-1; so com >= 120 pregoes. Alerta: DD < 1,5
  H6  emprestimos CP (2.01.04) / (caixa 1.01.01 + aplicacoes 1.01.02 + CFO 12m 6.01) >= 1,0
  H8  >= 1 evento incidente em outra empresa do mesmo SETOR_ATIV nos 180 dias ate T-1
  B1  menor ativo total = mais risco (escore = -ativo)   B2 passivo exigivel (2.01+2.02) / ativo total   B3 n FR nos 90 dias ate T-1
"""
import math
import re
from bisect import bisect_left, bisect_right
from datetime import timedelta

from dados import CONTAS, vigente

RX_CAT_A = re.compile(r"informacoes de companhias em recuperacao judicial ou extrajudicial")
RX_CAT_FR = re.compile(r"fato relevante")
RX_ASSEMB = re.compile(r"assembleia")
RX_DEB = re.compile(r"debentur|titulares de valores mobiliarios|titulares de deb")
RX_H4_A = re.compile(r"renuncia|desligamento|substituicao|deixa o cargo|destituicao")
RX_H4_B = re.compile(r"diretor financeiro|\bcfo\b|relacoes com investidores|\bdri\b")
PRECO_MAX_IDADE_DIAS = 10
DD_CORTE = 1.5


def _janela(docs_datas, ini, fim):
    """docs ordenados por data; devolve slice [ini, fim] inclusivo via bisect sobre a lista de datas."""
    return bisect_left(docs_datas, ini), bisect_right(docs_datas, fim)


def h1(docs, datas, t):
    a, b = _janela(datas, t - timedelta(days=180), t - timedelta(days=1))
    return int(any(RX_ASSEMB.search(d["cat_n"]) and (RX_DEB.search(d["tipo_n"]) or RX_DEB.search(d["especie_n"]) or RX_DEB.search(d["assunto_n"]))
                   for d in docs[a:b]))


def h2a(versoes_dfp, versoes_itr, t):
    lim_ini, lim = t - timedelta(days=365), t - timedelta(days=1)
    for v in versoes_dfp:
        if v["dt_receb"] and lim_ini <= v["dt_receb"] <= lim and v["dt_refer"]:
            prazo = v["dt_refer"].replace(year=v["dt_refer"].year + 1, month=3, day=31)
            if v["dt_receb"] > prazo:
                return 1
    for v in versoes_itr or []:
        if v["dt_receb"] and lim_ini <= v["dt_receb"] <= lim and v["dt_refer"] and (v["dt_receb"] - v["dt_refer"]).days > 45:
            return 1
    return 0


def h2b(versoes_dfp, versoes_itr, t):
    lim_ini, lim = t - timedelta(days=365), t - timedelta(days=1)
    return int(any(v["dt_receb"] and lim_ini <= v["dt_receb"] <= lim and v["versao"] >= 2 for v in list(versoes_dfp) + list(versoes_itr or [])))


def h2c(versoes_dfp, t):
    v = vigente(versoes_dfp, t)
    return int(bool(v and v["parecer_enfase"])) if v else None


def h3(docs, datas, t):
    a, b = _janela(datas, t - timedelta(days=90), t - timedelta(days=1))
    rec = sum(1 for d in docs[a:b] if not RX_CAT_A.search(d["cat_n"]))
    a2, b2 = _janela(datas, t - timedelta(days=90 + 730), t - timedelta(days=91))
    base = sum(1 for d in docs[a2:b2] if not RX_CAT_A.search(d["cat_n"])) / 8.0
    if base < 3:
        return None
    return int(rec / base <= 0.5)


def h4(docs, datas, t):
    a, b = _janela(datas, t - timedelta(days=365), t - timedelta(days=1))
    return int(any(RX_H4_A.search(d["assunto_n"]) and RX_H4_B.search(d["assunto_n"]) for d in docs[a:b]))


def h5(precos, versoes_dfp, selic, t):
    """precos: lista ordenada de (data, fechamento) ou (data, fech_ajustado, fech_bruto) de dados.ajustar_capital.
    Volatilidade pelo ajustado; E = ajustado(T-1) x acoes do BPP x (bruto/ajustado na data de referencia do BPP), que
    corrige a quantidade de acoes por desdobramento ou grupamento entre a referencia e T-1. Devolve (dd, alerta)."""
    v = vigente(versoes_dfp, t)
    if not v or not v.get("acoes") or not precos:
        return None, None
    pc, pnc = v["contas"].get(CONTAS["pc"]), v["contas"].get(CONTAS["pnc"])
    if pc is None or pnc is None:
        return None, None
    F = pc + 0.5 * pnc
    lim = t - timedelta(days=1)
    precos = [(x[0], x[1], x[2] if len(x) > 2 else x[1]) for x in precos]
    # Serie parada nao mede nada: acao suspensa ou que saiu da bolsa tinha o H5 calculado com preco de anos atras (Oi, com
    # cotacao so ate 2023, saia como H5=1 em 2026). Ultimo pregao ate T-1 precisa estar a no maximo PRECO_MAX_IDADE_DIAS.
    ult = max((d for d, _, _ in precos if d <= lim), default=None)
    if ult is None or (lim - ult).days > PRECO_MAX_IDADE_DIAS:
        return None, None
    fechos = [p for d, p, _ in precos if d <= lim][-253:]
    if len(fechos) < 121:
        return None, None
    rets = [math.log(fechos[i] / fechos[i - 1]) for i in range(1, len(fechos)) if fechos[i] > 0 and fechos[i - 1] > 0]
    if len(rets) < 120:
        return None, None
    mu = sum(rets) / len(rets)
    sigE = math.sqrt(sum((r - mu) ** 2 for r in rets) / (len(rets) - 1)) * math.sqrt(252)
    n_acoes = v["acoes"]["integralizadas"] - v["acoes"]["tesouraria"]
    ref = [(p, b) for d, p, b in precos if d <= (v.get("dt_refer") or lim)]
    fator = (ref[-1][1] / ref[-1][0]) if ref and ref[-1][0] > 0 else 1.0
    E = fechos[-1] * n_acoes * fator
    if E <= 0 or F <= 0 or sigE <= 0:
        return None, None
    r = _selic_em(selic, lim)
    if r is None:
        return None, None
    w = E / (E + F)
    sigV = w * sigE + (1 - w) * (0.05 + 0.25 * sigE)
    dd = (math.log((E + F) / F) + (r - 0.5 * sigV * sigV)) / sigV
    return dd, int(dd < DD_CORTE)


def _selic_em(selic, d):
    if not selic:
        return None
    ds = sorted(k for k in selic if k <= d)
    return selic[ds[-1]] if ds else None


def h6(versoes_dfp, t):
    v = vigente(versoes_dfp, t)
    if not v:
        return None, None
    c = v["contas"]
    cp, cx, ap, cfo = c.get(CONTAS["emprestimos_cp"]), c.get(CONTAS["caixa"]), c.get(CONTAS["aplicacoes"]), c.get(CONTAS["cfo"])
    if cp is None or cx is None:
        return None, None
    den = cx + (ap or 0.0) + (cfo or 0.0)
    if den <= 0:
        return float("inf"), 1
    razao = cp / den
    return razao, int(razao >= 1.0)


def h8(setor, eventos_setor, t):
    """eventos_setor: {setor: lista ordenada de (data, cnpj) de eventos incidentes}. Outra empresa do mesmo setor."""
    if not setor:
        return None
    lst = eventos_setor.get(setor, [])
    ini, fim = t - timedelta(days=180), t - timedelta(days=1)
    return int(any(ini <= d <= fim for d, _ in lst))


def b1_b2(versoes_dfp, t):
    v = vigente(versoes_dfp, t)
    if not v:
        return None, None
    at = v["contas"].get(CONTAS["ativo_total"])
    pc, pnc = v["contas"].get(CONTAS["pc"]), v["contas"].get(CONTAS["pnc"])
    b1 = -at if at else None
    b2 = ((pc or 0) + (pnc or 0)) / at if at else None
    return b1, b2


def b3(docs, datas, t):
    a, b = _janela(datas, t - timedelta(days=90), t - timedelta(days=1))
    return sum(1 for d in docs[a:b] if RX_CAT_FR.search(d["cat_n"]))


def features_em_T(cnpj, t, docs, datas, dfp, itr, precos, selic, setor, eventos_setor):
    dd, h5a = h5(precos, dfp, selic, t)
    h6r, h6a = h6(dfp, t)
    b1, b2 = b1_b2(dfp, t)
    return {"H1": h1(docs, datas, t), "H2a": h2a(dfp, itr, t), "H2b": h2b(dfp, itr, t), "H2c": h2c(dfp, t), "H3": h3(docs, datas, t),
            "H4": h4(docs, datas, t), "H5_dd": dd, "H5": h5a, "H6_razao": h6r, "H6": h6a, "H8": h8(setor, eventos_setor, t),
            "B1": b1, "B2": b2, "B3": b3(docs, datas, t)}


SINAIS_BINARIOS = ("H1", "H2a", "H2b", "H2c", "H3", "H4", "H5", "H6", "H8")
ESCORES_CONTINUOS = {"H5": "H5_dd_neg", "B1": "B1", "B2": "B2", "B3": "B3"}
