"""Leitores do CDA (blocos 4 e 6) e do informe diario de fundos, com mapa de debenture para emissor.

Mapa codigo para emissor, sem substring solta (licao SUBSTRINGDONO1):
  1. bloco 6 traz CPF_CNPJ_EMISSOR, casa por CNPJ exato com cnpj_emissores.json
  2. bloco 4: codigo de emissor do ISIN (posicoes 3 a 6) igual ao prefixo do ticker B3 do emissor (tickers_emissores.json)
  3. bloco 4: nome do arquivo ANBIMA (codigo@nome) normalizado IGUAL a denominacao normalizada do cadastro
"""
import collections
import csv
import io
import json
import os
import re
import sys
import unicodedata
import zipfile
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import CNPJ_EMISSORES, RAW, REPO, digitos, emissores, pdata  # noqa: E402

TICKERS = os.path.join(REPO, "data", "cotacoes", "tickers_emissores.json")
ANBIMA_DB = os.path.join(RAW, "db261016.txt")
RX_SUFIXO = re.compile(r"\b(s\.?\s?a\.?|s/a|ltda|cia|companhia)\b")


def norm_nome(s):
    s = unicodedata.normalize("NFD", s or "")
    s = "".join(c for c in s if unicodedata.category(c) != "Mn").lower().replace("(*)", " ")
    s = RX_SUFIXO.sub(" ", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def num(v):
    try:
        return float((v or "0").replace(",", ".") or 0)
    except ValueError:
        return 0.0


def mapa_codigos():
    """Devolve (prefixo_isin -> emissor, codigo_anbima -> emissor, cnpj -> emissor, diagnostico)."""
    cnpj = {c: e for e, c in emissores().items()}
    with open(TICKERS, encoding="utf-8") as fh:
        tk = json.load(fh)["emissores"]
    pref = {}
    for emp, v in tk.items():
        m = re.match(r"([A-Z]{4})\d", v.get("ticker") or "")
        if m and v.get("tipo") in ("propria", None):
            pref.setdefault(m.group(1), emp)
    with open(CNPJ_EMISSORES, encoding="utf-8") as fh:
        cad = json.load(fh)
    denom = {}
    for emp, v in cad.items():
        n = norm_nome(v.get("denom"))
        if n:
            denom.setdefault(n, set()).add(emp)
    cod = {}
    if os.path.exists(ANBIMA_DB):
        with open(ANBIMA_DB, encoding="latin-1") as fh:
            for linha in fh:
                p = linha.split("@")
                if len(p) > 3 and re.match(r"^[A-Z0-9]{5,8}$", p[0]):
                    alvo = denom.get(norm_nome(p[1]))
                    if alvo and len(alvo) == 1:
                        cod[p[0]] = next(iter(alvo))
    return pref, cod, cnpj, {"prefixos_ticker": len(pref), "codigos_anbima_casados": len(cod)}


def emissor_da_linha(row, pref, cod, cnpj):
    c = digitos(row.get("CPF_CNPJ_EMISSOR"))
    if c and c in cnpj:
        return cnpj[c], "cnpj"
    ca = (row.get("CD_ATIVO") or "").strip()
    if ca in cod:
        return cod[ca], "anbima"
    isin = (row.get("CD_ISIN") or "").strip()
    if len(isin) >= 6 and isin[2:6] in pref:
        return pref[isin[2:6]], "isin"
    return None, None


def eh_debenture(row):
    t = unicodedata.normalize("NFD", (row.get("TP_ATIVO") or "") + " " + (row.get("TP_APLIC") or "")).lower()
    return "deb" in t or "nota promiss" in t or "commercial paper" in t


def ler_cda(meses):
    """Agrega por (fundo, competencia, emissor, prazo_confid) a posicao e as vendas do mes.
    Tambem devolve totais por (fundo, competencia) de toda debenture (mapeada ou nao), para a taxa de venda do fundo."""
    pref, cod, cnpj, diag = mapa_codigos()
    pos = collections.defaultdict(float)
    venda_emis = collections.defaultdict(float)
    tot_fundo = collections.defaultdict(lambda: [0.0, 0.0, 0.0])  # pos, venda, aquisicao
    cobertura = collections.Counter()
    for mes in meses:
        caminho = os.path.join(RAW, "cda", "cda_fi_%s.zip" % mes)
        with zipfile.ZipFile(caminho) as z:
            for blc in ("4", "6"):
                nome = "cda_fi_BLC_%s_%s.csv" % (blc, mes)
                if nome not in z.namelist():
                    continue
                with z.open(nome) as fh:
                    for row in csv.DictReader(io.TextIOWrapper(fh, encoding="latin-1"), delimiter=";"):
                        if not eh_debenture(row):
                            continue
                        f = digitos(row.get("CNPJ_FUNDO_CLASSE"))
                        cp = pdata(row.get("DT_COMPTC"))
                        v, vv, va = num(row.get("VL_MERC_POS_FINAL")), num(row.get("VL_VENDA_NEGOC")), num(row.get("VL_AQUIS_NEGOC"))
                        t = tot_fundo[(f, cp)]
                        t[0] += v
                        t[1] += vv
                        t[2] += va
                        emp, via = emissor_da_linha(row, pref, cod, cnpj)
                        cobertura["valor_total"] += v
                        if not emp:
                            continue
                        cobertura["valor_mapeado"] += v
                        cobertura["via_" + via] += v
                        conf = pdata(row.get("DT_CONFID_APLIC"))
                        pos[(f, cp, emp, conf)] += v
                        venda_emis[(f, cp, emp)] += vv
    diag.update({k: round(v / 1e9, 2) for k, v in cobertura.items()})
    return pos, venda_emis, tot_fundo, diag


def ler_inf_diario(meses, fundos=None):
    """{fundo: {data: [captacao, resgate, pl]}} somando subclasses."""
    out = collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0.0, 0.0]))
    for mes in meses:
        caminho = os.path.join(RAW, "infd", "inf_diario_fi_%s.zip" % mes)
        with zipfile.ZipFile(caminho) as z:
            for nome in z.namelist():
                if not nome.endswith(".csv"):
                    continue
                with z.open(nome) as fh:
                    for row in csv.DictReader(io.TextIOWrapper(fh, encoding="latin-1"), delimiter=";"):
                        f = digitos(row.get("CNPJ_FUNDO_CLASSE") or row.get("CNPJ_FUNDO"))
                        if fundos is not None and f not in fundos:
                            continue
                        d = pdata(row.get("DT_COMPTC"))
                        if not d:
                            continue
                        x = out[f][d]
                        x[0] += num(row.get("CAPTC_DIA"))
                        x[1] += num(row.get("RESG_DIA"))
                        x[2] += num(row.get("VL_PATRIM_LIQ"))
    return out
