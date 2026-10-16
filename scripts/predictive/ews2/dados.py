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

DIRS_IPE = [os.path.join(BASE, "data", "cvm"), r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cvm-ipe"]
DIRS_DFP = [os.path.join(BASE, "data", "cvm"), r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cvm-dfp"]
DIRS_ITR = [r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cvm-itr"]
DIRS_COTAHIST = [r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cotahist"]
CAD = os.path.join(BASE, "data", "cvm", "cad_cia_aberta.csv")
SELIC_CACHE = os.path.join(BASE, "data", "cotacoes", "selic_sgs_1178_cache.json")

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
                        if ln[:2] != "01" or ln[16:18].strip() != "10":  # 10 = lote padrao, a vista
                            continue
                        d = pdate("%s-%s-%s" % (ln[2:6], ln[6:8], ln[8:10]))
                        try:
                            fech = int(ln[108:121]) / 100.0
                        except Exception:  # noqa: BLE001
                            continue
                        out.setdefault(ln[12:24].strip(), []).append((d, fech))
    for v in out.values():
        v.sort()
    return out, {"arquivos": sorted(zips), "disponivel": bool(zips)}


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
