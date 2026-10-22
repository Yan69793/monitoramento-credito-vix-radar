"""Leitores das fontes publicas (so leitura, so biblioteca padrao). Cada leitor devolve dicts simples e declara
disponibilidade; fonte ausente nunca vira zero silencioso.

Fontes e campos usados (G0-v1 itens 1, 4, 7, 8):
  IPE   ipe_cia_aberta_AAAA.zip  -> documentos (cnpj, data_entrega, categoria, tipo, especie, assunto, protocolo)
  CAD   cad_cia_aberta.csv       -> periodos de registro (DT_REG, DT_CANCEL, MOTIVO_CANCEL, SETOR_ATIV)
  DFP   dfp_cia_aberta_AAAA.zip  -> cabecalho (DT_REFER, VERSAO, DT_RECEB), BPA_con, BPP_con, DFC_MI_con, parecer,
                                    composicao_capital
  ITR   itr_cia_aberta_AAAA.zip  -> idem (H2a, H2b); opcional, ausencia declarada
  B3    COTAHIST_AAAAA.ZIP       -> precos de fechamento (H5); opcional, ausencia declarada
  BCB   serie SGS 432 (Selic meta) -> cache local; opcional, ausencia declarada

Contas (proposta de G0-v1-anexo-contas, a congelar antes de qualquer metrica): CD_CONTA do plano padrao CVM.
  1        Ativo Total                      1.01.01  Caixa e Equivalentes de Caixa
  1.01.02  Aplicacoes Financeiras           2        Passivo Total (inclui PL no plano CVM; o passivo exigivel e 2.01+2.02)
  2.01     Passivo Circulante               2.02     Passivo Nao Circulante
  2.01.04  Emprestimos e Financiamentos CP  6.01     Caixa Liquido Atividades Operacionais (DFC)
"""
import csv
import glob
import io
import os
import re
import sys
import unicodedata
import zipfile
from datetime import date

AQUI = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
sys.path.insert(0, os.path.join(AQUI, "..", "validacao"))

# EWS2_DADOS_DIR (GitHub Actions, EWS2PUB1): uma pasta so, fora do repo, com cvm-ipe, cvm-dfp, cvm-itr, cvm-fca, cotahist e cad.
# Sem a variavel valem os caminhos desta maquina, como sempre.
EWS2_DADOS_DIR = os.environ.get("EWS2_DADOS_DIR") or None


def _pasta(nome, padrao):
    return os.path.join(EWS2_DADOS_DIR, nome) if EWS2_DADOS_DIR else padrao


_TMP_VIX = r"E:\Diretorio\Claude\tmp\operacional\vix-radar"
DIRS_IPE = [os.path.join(BASE, "data", "cvm"), _pasta("cvm-ipe", os.path.join(_TMP_VIX, "cvm-ipe"))]
DIRS_DFP = [os.path.join(BASE, "data", "cvm"), _pasta("cvm-dfp", os.path.join(_TMP_VIX, "cvm-dfp"))]
DIRS_ITR = [_pasta("cvm-itr", os.path.join(_TMP_VIX, "cvm-itr"))]
DIRS_COTAHIST = [_pasta("cotahist", os.path.join(_TMP_VIX, "cotahist"))]
CAD = _pasta("cad/cad_cia_aberta.csv", os.path.join(BASE, "data", "cvm", "cad_cia_aberta.csv"))
# selic_sgs_1178_cache.json guarda so o valor do dia (rotinas), nao serie; o H5 precisa da serie historica (Ipeadata
# BM366_TJOVER366, Selic over diaria, baixada em 18/10/2026). Sem o historico, cai no cache e o H5 fica sem dado.
SELIC_HIST = os.path.join(BASE, "data", "cotacoes", "selic_historico_ipea.json")
SELIC_CACHE = SELIC_HIST if os.path.exists(SELIC_HIST) else os.path.join(BASE, "data", "cotacoes", "selic_sgs_1178_cache.json")

CONTAS = {"ativo_total": "1", "caixa": "1.01.01", "aplicacoes": "1.01.02", "passivo_total": "2", "pc": "2.01", "pnc": "2.02",
          "emprestimos_cp": "2.01.04", "cfo": "6.01"}
# Codigo SO vale com a descricao esperada (medido na DFP 2024 consolidada): instituicao financeira e seguradora usam o
# mesmo CD_CONTA para outra coisa (2.01 = "Passivos Financeiros ao Valor Justo", 2.01.04 = "Capitalizacao"). Conta com
# codigo certo e descricao fora do padrao fica ausente, e a feature que depende dela sai None (sem dado), nunca zero.
DESCRICAO_CONTA = {
    "1": r"^ativo total$", "1.01.01": r"^(caixa e equivalentes de caixa|caixa|disponibilidades)$",
    "1.01.02": r"^aplicacoes (financeiras|de liquidez)$", "2": r"^passivo total$", "2.01": r"^passivo circulante$",
    "2.02": r"^passivo nao circulante$", "2.01.04": r"^emprestimos e financiamentos$",
    "6.01": r"^caixa liquido (das )?atividades operacionais$",
}
CONTAS_BPA = {"1", "1.01.01", "1.01.02"}
CONTAS_BPP = {"2", "2.01", "2.02", "2.01.04"}
CONTAS_DFC = {"6.01"}


def norm(s):
    if not s:
        return ""
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", s.lower()).strip()


def pdate(s):
    try:
        y, m, d = s[:10].split("-")
        return date(int(y), int(m), int(d))
    except Exception:  # noqa: BLE001
        return None


def conta_valida(cd, ds):
    rx = DESCRICAO_CONTA.get(cd)
    return bool(rx and re.search(rx, norm(ds)))


def _zips(dirs, prefixo):
    por_ano = {}
    for d in dirs:
        for z in sorted(glob.glob(os.path.join(d, prefixo + "*.zip"))):
            m = re.search(r"(\d{4})\.zip$", z, re.I)
            if m:
                por_ano.setdefault(m.group(1), z)
    return por_ano


def _csv_do_zip(z, nome, enc="latin-1"):
    with zipfile.ZipFile(z) as zf:
        if nome not in zf.namelist():
            return
        with zf.open(nome) as fh:
            for r in csv.DictReader(io.TextIOWrapper(fh, encoding=enc), delimiter=";"):
                yield r


def ler_ipe(dirs=None):
    """Mesma normalizacao e mesmo conjunto de arquivos do leitor congelado da validacao (e1_eventos.ler_ipe), com
    Tipo e Especie a mais, que o item 5 da G0-v1 (intermediario, H1) exige e o leitor da validacao nao guarda."""
    docs, fontes = [], {}
    for ano, z in sorted(_zips(dirs or DIRS_IPE, "ipe_cia_aberta_").items()):
        n = 0
        with zipfile.ZipFile(z) as zf:
            nome = [x for x in zf.namelist() if x.endswith(".csv")][0]
            with zf.open(nome) as fh:
                for r in csv.DictReader(io.TextIOWrapper(fh, encoding="latin-1"), delimiter=";"):
                    de = pdate(r.get("Data_Entrega", ""))
                    if de is None:
                        continue
                    docs.append({"cnpj": r["CNPJ_Companhia"].strip(), "nome_n": norm(r.get("Nome_Companhia", "")),
                                 "cat_n": norm(r.get("Categoria", "")), "tipo_n": norm(r.get("Tipo", "")),
                                 "especie_n": norm(r.get("Especie", "")), "assunto_n": norm(r.get("Assunto", "")),
                                 "data": de, "protocolo": r.get("Protocolo_Entrega", "").strip(), "link": r.get("Link_Download", "").strip()})
                    n += 1
        fontes[ano] = {"arquivo": os.path.abspath(z), "linhas": n}
    return docs, fontes


def ler_cad(caminho=CAD):
    import e1_eventos as V0  # noqa: WPS433
    return V0.ler_cad(caminho) if os.path.exists(caminho) else {}


def ler_dfp(dirs=None, anos=None, itr=False):
    """Demonstrativos por (cnpj) -> lista de versoes {dt_refer, versao, dt_receb, contas{cd: valor}, parecer_enfase: bool,
    acoes{...}}. Valores em unidade da ESCALA_MOEDA (convertidos para reais). Le so as contas de CONTAS_*."""
    prefixo = "itr_cia_aberta_" if itr else "dfp_cia_aberta_"
    zips = _zips(dirs or (DIRS_ITR if itr else DIRS_DFP), prefixo)
    out = {}
    disponivel = sorted(zips)
    for ano, z in sorted(zips.items()):
        if anos and ano not in anos:
            continue
        cab = {}
        for r in _csv_do_zip(z, "%s%s.csv" % (prefixo, ano)):
            k = (r["CNPJ_CIA"], r["DT_REFER"], r["VERSAO"])
            cab[k] = {"cnpj": r["CNPJ_CIA"], "dt_refer": pdate(r["DT_REFER"]), "versao": int(r["VERSAO"] or 0),
                      "dt_receb": pdate(r["DT_RECEB"]), "contas": {}, "parecer_enfase": False, "parecer_tipo": None, "acoes": None}
        for dem, contas in (("BPA_con", CONTAS_BPA), ("BPP_con", CONTAS_BPP), ("DFC_MI_con", CONTAS_DFC)):
            for r in _csv_do_zip(z, "%s%s_%s.csv" % (prefixo, dem, ano)):
                if r["CD_CONTA"] not in contas or r.get("ORDEM_EXERC", "ÚLTIMO") not in ("ÚLTIMO", "ULTIMO"):
                    continue
                if not conta_valida(r["CD_CONTA"], r.get("DS_CONTA", "")):
                    continue
                k = (r["CNPJ_CIA"], r["DT_REFER"], r["VERSAO"])
                if k not in cab:
                    continue
                esc = 1000.0 if norm(r.get("ESCALA_MOEDA", "")) == "mil" else 1.0
                try:
                    cab[k]["contas"][r["CD_CONTA"]] = float(r["VL_CONTA"].replace(",", ".")) * esc
                except Exception:  # noqa: BLE001
                    pass
        for r in _csv_do_zip(z, "%sparecer_%s.csv" % (prefixo, ano)):
            k = (r["CNPJ_CIA"], r["DT_REFER"], r["VERSAO"])
            if k in cab:
                tp, tx = norm(r.get("TP_PARECER_DECL", "")), norm(r.get("TXT_PARECER_DECL", ""))
                cab[k]["parecer_tipo"] = cab[k]["parecer_tipo"] or tp
                if "relatorio do auditor independente" in tp and "continuidade operacional" in tx:
                    cab[k]["parecer_enfase"] = True
        for r in _csv_do_zip(z, "%scomposicao_capital_%s.csv" % (prefixo, ano)):
            k = (r["CNPJ_CIA"], r["DT_REFER"], r["VERSAO"])
            if k in cab:
                try:
                    cab[k]["acoes"] = {"integralizadas": float(r.get("QT_ACAO_TOTAL_CAP_INTEGR", "0") or 0),
                                       "tesouraria": float(r.get("QT_ACAO_TOTAL_TESOURO", "0") or 0)}
                except Exception:  # noqa: BLE001
                    pass
        for v in cab.values():
            out.setdefault(v["cnpj"], []).append(v)
    for lst in out.values():
        lst.sort(key=lambda v: (v["dt_receb"] or date.min, v["versao"]))
    return out, {"anos": disponivel, "tipo": "ITR" if itr else "DFP", "disponivel": bool(disponivel)}


def vigente(versoes, t):
    """Demonstrativo vigente em T: maior VERSAO entre os com DT_RECEB <= T-1; empate pelo DT_REFER mais recente
    (G0-v1 item 1). None se nenhum."""
    from datetime import timedelta
    lim = t - timedelta(days=1)
    cands = [v for v in versoes if v["dt_receb"] and v["dt_receb"] <= lim]
    if not cands:
        return None
    ref = max(v["dt_refer"] for v in cands if v["dt_refer"])
    cands = [v for v in cands if v["dt_refer"] == ref]
    return max(cands, key=lambda v: v["versao"])


def ler_cotahist(dirs=None):
    """COTAHIST da B3 (registro 01, posicao fixa): {codigo_negociacao: [(data, fechamento)]}. Opcional."""
    zips = {}
    for d in (dirs or DIRS_COTAHIST):
        for z in glob.glob(os.path.join(d, "COTAHIST_A*.ZIP")) + glob.glob(os.path.join(d, "COTAHIST_A*.zip")):
            zips[os.path.basename(z)] = z
    out = {}
    for z in sorted(zips.values()):
        with zipfile.ZipFile(z) as zf:
            for n in zf.namelist():
                with zf.open(n) as fh:
                    for ln in io.TextIOWrapper(fh, encoding="latin-1"):
                        # layout B3: CODBDI nas posicoes 11-12 ("02" = lote padrao) e TPMERC em 25-27 ("010" = a vista).
                        # Ate 18/10/2026 o filtro lia ln[16:18] (meio do CODNEG) e descartava quase tudo.
                        if ln[:2] != "01" or ln[10:12] != "02" or ln[24:27] != "010":
                            continue
                        d = pdate("%s-%s-%s" % (ln[2:6], ln[6:8], ln[8:10]))
                        try:
                            # FATCOT (posicoes 211-217): preco cotado por lote de 1, 10, 100, 1000 ou 1000000 acoes.
                            # Ate 18/10/2026 era ignorado e o preco por lote de mil entrava como unitario.
                            fech = int(ln[108:121]) / 100.0 / max(1, int(ln[210:217] or 1))
                        except Exception:  # noqa: BLE001
                            continue
                        out.setdefault(ln[12:24].strip(), []).append((d, fech))
    for v in out.values():
        v.sort()
    return out, {"arquivos": sorted(zips), "disponivel": bool(zips)}


DIRS_FCA = [_pasta("cvm-fca", os.path.join(_TMP_VIX, "cvm-fca"))]


def ler_tickers_fca(dirs=None):
    """FCA da CVM (valor_mobiliario): {cnpj: set(codigos de negociacao)} de acoes e units, todos os anos."""
    out = {}
    for ano, z in sorted(_zips(dirs or DIRS_FCA, "fca_cia_aberta_").items()):
        for r in _csv_do_zip(z, "fca_cia_aberta_valor_mobiliario_%s.csv" % ano):
            cod = (r.get("Codigo_Negociacao") or "").strip().upper()
            tipo = norm(r.get("Valor_Mobiliario") or "")
            if cod and ("acao" in tipo or "acoes" in tipo or "unit" in tipo or "certificado de deposito" in tipo):
                out.setdefault((r.get("CNPJ_Companhia") or "").strip(), set()).add(cod)
    return out


SALTO_MIN, SALTO_TOL, SALTO_PERSISTE = 1.8, 0.04, 5


def eventos_de_capital(serie):
    """Desdobramento e grupamento no COTAHIST, que nao e ajustado. Salto de um pregao para o outro com razao >= SALTO_MIN
    (ou <= 1/SALTO_MIN) cujo fator fica a SALTO_TOL de um inteiro >= 2 e que persiste nos SALTO_PERSISTE pregoes seguintes.
    Queda de mercado real raramente cai num inteiro exato (Americanas em 12/01/2023: fator 4,42, fica fora).
    Devolve [(indice, m)], m = multiplicador de preco do evento (desdobramento 5:1 -> m = 0,2)."""
    ev = []
    for i in range(1, len(serie)):
        a, b = serie[i - 1][1], serie[i][1]
        if a <= 0 or b <= 0:
            continue
        q = b / a
        k = 1 / q if q < 1 else q
        if k < SALTO_MIN:
            continue
        n = round(k)
        if n < 2 or abs(k - n) / n > SALTO_TOL:
            continue
        seg = [p for _, p in serie[i:i + SALTO_PERSISTE] if p > 0]
        if len(seg) < SALTO_PERSISTE:
            continue
        med = sorted(seg)[len(seg) // 2]
        r = med / a
        if (q < 1 and r > 1 / (1 + (n - 1) / 2)) or (q > 1 and r < 1 + (n - 1) / 2):
            continue  # voltou ao nivel anterior: erro de cotacao, nao evento de capital
        ev.append((i, (1.0 / n) if q < 1 else float(n)))
    return ev


def ajustar_capital(serie):
    """[(data, fech)] -> [(data, fech_ajustado, fech_bruto)], ajuste retroativo pelos eventos de capital. Retornos do
    ajustado nao tem o salto artificial; bruto/ajustado em d e o fator acumulado dos eventos posteriores a d (o H5 usa a
    razao entre dois pontos, entao nao ha olhar para frente)."""
    ev = eventos_de_capital(serie)
    mult = [1.0] * len(serie)
    acc = 1.0
    j = len(ev) - 1
    for i in range(len(serie) - 1, -1, -1):
        mult[i] = acc
        while j >= 0 and ev[j][0] == i:
            acc *= ev[j][1]
            j -= 1
    return [(d, p * mult[i], p) for i, (d, p) in enumerate(serie)]


def precos_por_cnpj(precos_ticker, tickers_cnpj):
    """COTAHIST e indexado por ticker; o pipeline consulta por CNPJ. Para cada CNPJ, TODAS as series dos tickers declarados
    no FCA, ajustadas por eventos de capital, da mais longa para a mais curta; features.h5 escolhe a vigente em cada T
    (troca de ticker, como ELET6 para AXIA3, nao pode deixar o emissor sem preco nem preso a um ticker parado).
    Devolve ({cnpj: [serie]}, {cnpj: [tickers]}); serie = [(data, fech_ajustado, fech_bruto)]."""
    out, escolha = {}, {}
    for c, cods in tickers_cnpj.items():
        cand = sorted(((len(precos_ticker[k]), k) for k in cods if k in precos_ticker), reverse=True)
        if cand:
            out[c] = [ajustar_capital(precos_ticker[k]) for _, k in cand]
            escolha[c] = [k for _, k in cand]
    return out, escolha


def ler_selic(caminho=SELIC_CACHE):
    """Serie Selic do cache local, {data: taxa_anual_decimal}. O G0-v1 pede a meta (SGS 432); o cache existente e a
    1178 (anualizada base 252), e a diferenca e declarada no relatorio quando este cache for o usado."""
    import json
    if not os.path.exists(caminho):
        return {}, {"disponivel": False, "fonte": None}
    with open(caminho, encoding="utf-8-sig") as fh:
        j = json.load(fh)
    serie = {}
    itens = j if isinstance(j, list) else (j.get("serie") or j.get("valores") or j.get("dados") or [])
    for it in itens:
        d = pdate(str(it.get("data") or it.get("date") or ""))
        v = it.get("valor") if "valor" in it else it.get("value")
        if d and v is not None:
            try:
                x = float(str(v).replace(",", "."))
                serie[d] = x / 100.0 if x > 1.0 else x
            except Exception:  # noqa: BLE001
                pass
    return serie, {"disponivel": bool(serie), "fonte": "SGS 1178 (cache local), nao a 432 pedida pelo G0-v1", "n": len(serie)}


def disponibilidade():
    """Inventario das fontes, sem ler conteudo pesado."""
    return {
        "ipe_anos": sorted(_zips(DIRS_IPE, "ipe_cia_aberta_")),
        "dfp_anos": sorted(_zips(DIRS_DFP, "dfp_cia_aberta_")),
        "itr_anos": sorted(_zips(DIRS_ITR, "itr_cia_aberta_")),
        "cotahist": sorted(os.path.basename(z) for d in DIRS_COTAHIST for z in glob.glob(os.path.join(d, "COTAHIST_A*"))),
        "cadastro": os.path.exists(CAD),
        "selic_cache": os.path.exists(SELIC_CACHE),
        "fre_grupos": False,
    }


if __name__ == "__main__":
    import json
    print(json.dumps(disponibilidade(), ensure_ascii=False, indent=1))
