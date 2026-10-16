"""E1 - base de eventos de credito para a validacao independente do EWS 2.0.

Implementa os itens 3, 4 e 6 do protocolo G0-v0 (nota 111 do vault,
sha256 e40eaf36b1aeaa36dea547b493d904ea5cd037bddc341ec607c6cfcd5269b7f9).

Somente leitura: le zips do IPE e da DFP da CVM e o cadastro, escreve apenas o
CSV e o resumo JSON de saida. Nao toca KV, Worker, rotinas nem rotulos.
Sem dependencias fora da biblioteca padrao.

Historico de implementacao (as regras do G0 nao mudaram):
  e1-v0    15/10/2026, gerou eventos_v0.csv. Copia em
           tmp/operacional/vix-radar/e1_eventos_v0.py,
           sha256 0b48a03752deba3fa7dbe8d5f3120e2c64aab0c2a73f9d36d308a3561582cd57
  e1-v0.1  15/10/2026, corrige 4 defeitos de implementacao achados na auditoria G1:
           D1 cadastro com mais de um periodo de registro por CNPJ (34 CNPJs),
              a v0 guardava so a ultima linha
           D2 item 4 (entrada no risco e censura) nao era aplicado na contagem
           D3 documento de encerramento fora de episodio aberto era ignorado
              (interpretacao I1), contra o texto do item 3
           D4 fim_episodio ficava vazio quando o episodio expirava por 12 meses
              sem gatilho posterior

Uso:
  python -I scripts/predictive/validacao/e1_eventos.py \
      --ipe-dir data/cvm --ipe-dir E:/Diretorio/Claude/tmp/operacional/vix-radar/cvm-ipe \
      --dfp-dir E:/Diretorio/Claude/tmp/operacional/vix-radar/cvm-dfp \
      --cad data/cvm/cad_cia_aberta.csv --out data/validacao/eventos_v0_1.csv
"""
import argparse
import csv
import glob
import io
import json
import os
import random
import re
import sys
import unicodedata
import zipfile
from datetime import date, timedelta

PROTOCOLO = "G0-v0"
PROTOCOLO_SHA256 = "e40eaf36b1aeaa36dea547b493d904ea5cd037bddc341ec607c6cfcd5269b7f9"
IMPLEMENTACAO = "e1-v0.1"
SEMENTE = 20261015

JANELA_INI = date(2011, 1, 1)
JANELA_FIM = date(2026, 9, 30)
TREINO_FIM = date(2020, 1, 1)      # treino: data < 2020-01-01
VALID_FIM = date(2022, 1, 1)       # validacao: 2020-01-01 .. 2021-12-31
EMBARGO_FIM = date(2022, 4, 1)     # embargo: 2022-01-01 .. 2022-03-31
# teste: 2022-04-01 .. 2026-09-30

# Textos congelados no G0-v0, item 3 e item 2. test_e1_eventos.py confere que
# estas strings continuam iguais as da nota 111.
RX_CAT_RJ = r"informacoes de companhias em recuperacao judicial ou extrajudicial"
RX_CAT_FR = r"fato relevante"
RX_FR_POS = (r"recuperacao (judicial|extrajudicial)|pedido de falencia|autofalencia|decretacao de falencia"
             r"|vencimento antecipado|inadimpl|\bdefault\b|nao pagamento|suspensao (do |dos )?pagamento"
             r"|standstill|chapter 11")
RX_FR_EXCL = r"nao declara|renuncia|waiver|perdao|resgate antecipado"
RX_ENCERRA = r"encerramento"
RX_NOME_PREV = r"em recuperacao|recuperacao judicial|falid|massa falida"

RE_CAT_RJ = re.compile(RX_CAT_RJ)
RE_CAT_FR = re.compile(RX_CAT_FR)
RE_FR_POS = re.compile(RX_FR_POS)
RE_FR_EXCL = re.compile(RX_FR_EXCL)
RE_ENCERRA = re.compile(RX_ENCERRA)
RE_NOME_PREV = re.compile(RX_NOME_PREV)

FORMULACAO = [
    ("Americanas", r"\bamericanas\b"),
    ("Light", r"^light\b"),
    ("Oi", r"^oi s\.?\s?a\b|^oi s/a\b"),
    ("Gol", r"\bgol linhas\b|^gol\b"),
    ("Casas Bahia", r"\bcasas bahia\b|^via varejo\b|^via s\.?\s?a\b"),
    ("Agrogalaxy", r"\bagrogalaxy\b"),
    ("Azul", r"^azul s\.?\s?a\b|^azul linhas\b"),
    ("GPA", r"\bcompanhia brasileira de distribuicao\b"),
    ("Raizen", r"\braizen\b"),
    ("Oncoclinicas", r"\boncoclinicas\b"),
    ("Braskem", r"\bbraskem\b"),
    ("Marabraz", r"\bmarabraz\b"),
]
FORMULACAO = [(n, re.compile(p)) for n, p in FORMULACAO]

EXPIRA = timedelta(days=365)
LOOKBACK_PREV = timedelta(days=730)


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
    except Exception:
        return None


def _zips_por_ano(dirs, prefixo):
    por_ano = {}
    for d in dirs:
        for z in sorted(glob.glob(os.path.join(d, prefixo + "*.zip"))):
            m = re.search(r"(\d{4})\.zip$", z)
            if m:
                por_ano.setdefault(m.group(1), z)
    return por_ano


def ler_ipe(dirs):
    """Le todos os ipe_cia_aberta_AAAA.zip; o primeiro diretorio que tiver o ano vence."""
    docs = []
    fontes = {}
    for ano, z in sorted(_zips_por_ano(dirs, "ipe_cia_aberta_").items()):
        with zipfile.ZipFile(z) as zf:
            nome = [n for n in zf.namelist() if n.endswith(".csv")][0]
            with zf.open(nome) as fh:
                rd = csv.DictReader(io.TextIOWrapper(fh, encoding="latin-1"), delimiter=";")
                n = 0
                for r in rd:
                    de = pdate(r.get("Data_Entrega", ""))
                    if de is None:
                        continue
                    docs.append(doc_ipe(r, de))
                    n += 1
        fontes[ano] = {"arquivo": os.path.abspath(z), "linhas": n}
    return docs, fontes


def doc_ipe(r, de):
    return {
        "cnpj": r["CNPJ_Companhia"].strip(),
        "nome": r.get("Nome_Companhia", "").strip(),
        "nome_n": norm(r.get("Nome_Companhia", "")),
        "cat_n": norm(r.get("Categoria", "")),
        "assunto": r.get("Assunto", "").strip(),
        "assunto_n": norm(r.get("Assunto", "")),
        "data": de,
        "link": r.get("Link_Download", "").strip(),
        "protocolo": r.get("Protocolo_Entrega", "").strip(),
    }


def ler_dfp_primeira_entrega(dirs):
    """CNPJ -> menor DT_RECEB de DFP (indice dfp_cia_aberta_AAAA.csv de cada zip)."""
    primeira = {}
    fontes = {}
    for ano, z in sorted(_zips_por_ano(dirs, "dfp_cia_aberta_").items()):
        alvo = "dfp_cia_aberta_%s.csv" % ano
        with zipfile.ZipFile(z) as zf:
            if alvo not in zf.namelist():
                continue
            n = 0
            with zf.open(alvo) as fh:
                for r in csv.DictReader(io.TextIOWrapper(fh, encoding="latin-1"), delimiter=";"):
                    dr = pdate(r.get("DT_RECEB", ""))
                    c = r.get("CNPJ_CIA", "").strip()
                    if dr is None or not c:
                        continue
                    if c not in primeira or dr < primeira[c]:
                        primeira[c] = dr
                    n += 1
        fontes[ano] = {"arquivo": os.path.abspath(z), "linhas": n}
    return primeira, fontes


def classifica(doc):
    """Retorna (tipo_gatilho, eh_encerramento) ou (None, False). Itens 2 e 3 do G0."""
    if RE_CAT_RJ.search(doc["cat_n"]):
        return "a_categoria_rj_re", bool(RE_ENCERRA.search(doc["assunto_n"]))
    if RE_CAT_FR.search(doc["cat_n"]) and RE_FR_POS.search(doc["assunto_n"]) and not RE_FR_EXCL.search(doc["assunto_n"]):
        return "b_fato_relevante", False
    return None, False


def construir_episodios(cnpj, lst, cont_ano=None):
    """Item 3 do G0. lst: documentos IPE de um CNPJ ordenados por data."""
    eps = []
    ep = None
    for d in lst:
        tipo, encerra = classifica(d)
        if tipo is None:
            continue
        if cont_ano is not None:
            c = cont_ano.setdefault(str(d["data"].year), {"a": 0, "b": 0})
            c["a" if tipo.startswith("a") else "b"] += 1
        if ep and not ep["fechado"] and d["data"] > ep["ultimo"] + EXPIRA:
            ep["fechado"] = True
            ep["fim"] = ep["ultimo"] + EXPIRA
            ep["fim_motivo"] = "12m_sem_gatilho"
        aberto = ep is not None and not ep["fechado"]
        if aberto:
            ep["ultimo"] = d["data"]
            ep["n_gatilhos"] += 1
            if encerra:
                ep["fechado"] = True
                ep["fim"] = d["data"]
                ep["fim_motivo"] = "encerramento"
            continue
        # D3: "Um gatilho fora de episodio aberto abre episodio novo". O encerramento
        # tambem e gatilho da categoria (a), entao abre e fecha no mesmo documento.
        ep = {
            "cnpj": cnpj, "nome": d["nome"], "data": d["data"], "ultimo": d["data"],
            "tipo": tipo, "assunto": d["assunto"], "link": d["link"], "protocolo": d["protocolo"],
            "n_gatilhos": 1, "fechado": bool(encerra), "fim": d["data"] if encerra else None,
            "fim_motivo": "encerramento" if encerra else "",
        }
        eps.append(ep)
    # D4: episodio que expira sem gatilho posterior tambem tem fim.
    for e in eps:
        if not e["fechado"] and e["ultimo"] + EXPIRA <= JANELA_FIM:
            e["fechado"] = True
            e["fim"] = e["ultimo"] + EXPIRA
            e["fim_motivo"] = "12m_sem_gatilho"
    return eps


def marcar_prevalencia(ep, lst):
    """Item 3 do G0: prevalente se, nos 24 meses antes do inicio, nome casa ou houve gatilho (a)."""
    ini = ep["data"] - LOOKBACK_PREV
    prev_nome = prev_rj = False
    for d in lst:
        if d["data"] >= ep["data"]:
            break
        if d["data"] < ini:
            continue
        if RE_NOME_PREV.search(d["nome_n"]):
            prev_nome = True
        if RE_CAT_RJ.search(d["cat_n"]):
            prev_rj = True
    ep["prevalente"] = prev_nome or prev_rj
    ep["prev_motivo"] = "+".join(x for x, f in (("nome", prev_nome), ("gatilho_a_24m", prev_rj)) if f)


def ler_cad(path):
    """D1: CNPJ -> lista de periodos de registro distintos (DT_REG, DT_CANCEL, ...)."""
    cad = {}
    with open(path, encoding="latin-1", newline="") as fh:
        for r in csv.DictReader(fh, delimiter=";"):
            per = {
                "dt_reg": pdate(r.get("DT_REG", "")), "dt_cancel": pdate(r.get("DT_CANCEL", "")),
                "motivo_cancel": r.get("MOTIVO_CANCEL", "").strip(), "setor_ativ": r.get("SETOR_ATIV", "").strip(),
                "sit_emissor": r.get("SIT_EMISSOR", "").strip(), "denom_social": r.get("DENOM_SOCIAL", "").strip(),
                "denom_comerc": r.get("DENOM_COMERC", "").strip(), "cd_cvm": r.get("CD_CVM", "").strip(),
            }
            lst = cad.setdefault(r["CNPJ_CIA"].strip(), [])
            chave = (per["dt_reg"], per["dt_cancel"], per["cd_cvm"])
            if all((p["dt_reg"], p["dt_cancel"], p["cd_cvm"]) != chave for p in lst):
                lst.append(per)
    for lst in cad.values():
        lst.sort(key=lambda p: p["dt_reg"] or date.min)
    return cad


def periodo_vigente(periodos, d):
    """Periodo cujo registro cobre a data d, ou None. Cancelamento conta ate o proprio dia."""
    for p in periodos:
        if p["dt_reg"] and p["dt_reg"] <= d and (p["dt_cancel"] is None or d <= p["dt_cancel"]):
            return p
    return None


def em_risco(d, periodos, primeira_dfp):
    """Item 4 do G0 aplicado a um evento na data d. Retorna (bool, motivo, periodo)."""
    if not periodos:
        return False, "sem_cadastro", None
    p = periodo_vigente(periodos, d)
    if p is None:
        anteriores = [x for x in periodos if x["dt_reg"] and x["dt_reg"] <= d]
        if anteriores:
            return False, "pos_cancelamento", anteriores[-1]
        return False, "antes_do_registro", periodos[0]
    if primeira_dfp is None or primeira_dfp > d - timedelta(days=1):
        return False, "sem_dfp_previa", p
    return True, "", p


def particao(dt):
    return ("fora_janela" if dt < JANELA_INI or dt > JANELA_FIM else
            "treino" if dt < TREINO_FIM else
            "validacao" if dt < VALID_FIM else
            "embargo" if dt < EMBARGO_FIM else "teste")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipe-dir", action="append", required=True)
    ap.add_argument("--dfp-dir", action="append", required=True)
    ap.add_argument("--cad", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    docs, fontes = ler_ipe(a.ipe_dir)
    primeira_dfp, fontes_dfp = ler_dfp_primeira_entrega(a.dfp_dir)
    cad = ler_cad(a.cad)

    por_cnpj = {}
    for d in docs:
        por_cnpj.setdefault(d["cnpj"], []).append(d)
    for lst in por_cnpj.values():
        lst.sort(key=lambda x: (x["data"], x["protocolo"]))

    cont_ano = {}
    episodios = []
    for cnpj, lst in por_cnpj.items():
        episodios.extend(construir_episodios(cnpj, lst, cont_ano))

    for ep in episodios:
        lst = por_cnpj[ep["cnpj"]]
        marcar_prevalencia(ep, lst)
        periodos = cad.get(ep["cnpj"], [])
        ok, motivo, per = em_risco(ep["data"], periodos, primeira_dfp.get(ep["cnpj"]))
        ep["em_risco"], ep["fora_risco_motivo"] = ok, motivo
        ep["primeira_dfp"] = primeira_dfp.get(ep["cnpj"])
        nomes = {d["nome_n"] for d in lst}
        for p in periodos:
            nomes.add(norm(p["denom_social"]))
            nomes.add(norm(p["denom_comerc"]))
        ep["formulacao"] = next((n for n, rx in FORMULACAO if any(rx.search(x) for x in nomes if x)), "")
        ep["particao"] = particao(ep["data"])
        per = per or {}
        ep["dt_reg"] = per.get("dt_reg")
        ep["dt_cancel"] = per.get("dt_cancel")
        ep["motivo_cancel"] = per.get("motivo_cancel", "")
        ep["setor_ativ"] = per.get("setor_ativ", "")
        ep["sit_emissor_atual"] = per.get("sit_emissor", "")
        ep["n_periodos_cad"] = len(periodos)

    iso = lambda x: x.isoformat() if x else ""
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    campos = ["cnpj", "nome", "data_evento", "particao", "incidente", "prev_motivo", "em_risco",
              "fora_risco_motivo", "formulacao", "tipo_gatilho", "n_gatilhos", "fim_episodio", "fim_motivo",
              "assunto", "link_cvm", "protocolo", "setor_ativ", "dt_reg", "dt_cancel", "motivo_cancel",
              "primeira_dfp", "sit_emissor_atual", "n_periodos_cad"]
    with open(a.out, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter=";", lineterminator="\n")
        w.writerow(campos)
        for ep in sorted(episodios, key=lambda e: (e["data"], e["cnpj"])):
            w.writerow([ep["cnpj"], ep["nome"], iso(ep["data"]), ep["particao"], int(not ep["prevalente"]),
                        ep["prev_motivo"], int(ep["em_risco"]), ep["fora_risco_motivo"], ep["formulacao"],
                        ep["tipo"], ep["n_gatilhos"], iso(ep["fim"]), ep["fim_motivo"], ep["assunto"], ep["link"],
                        ep["protocolo"], ep["setor_ativ"], iso(ep["dt_reg"]), iso(ep["dt_cancel"]),
                        ep["motivo_cancel"], iso(ep["primeira_dfp"]), ep["sit_emissor_atual"], ep["n_periodos_cad"]])

    na_janela = [e for e in episodios if not e["prevalente"] and e["particao"] != "fora_janela"]
    inc = [e for e in na_janela if e["em_risco"]]
    fora = {}
    for e in na_janela:
        if not e["em_risco"]:
            fora[e["fora_risco_motivo"]] = fora.get(e["fora_risco_motivo"], 0) + 1
    por_part = {}
    for e in inc:
        k = e["particao"]
        por_part.setdefault(k, {"total": 0, "sem_formulacao": 0, "por_tipo": {}})
        por_part[k]["total"] += 1
        if not e["formulacao"]:
            por_part[k]["sem_formulacao"] += 1
        por_part[k]["por_tipo"][e["tipo"]] = por_part[k]["por_tipo"].get(e["tipo"], 0) + 1
    teste_sf = por_part.get("teste", {}).get("sem_formulacao", 0)
    g1_ok = len(inc) >= 25 and teste_sf >= 10

    rnd = random.Random(SEMENTE)
    amostra = rnd.sample(sorted(inc, key=lambda e: (e["data"], e["cnpj"])), min(10, len(inc)))

    resumo = {
        "protocolo": PROTOCOLO, "protocolo_sha256": PROTOCOLO_SHA256, "implementacao": IMPLEMENTACAO,
        "fontes_ipe": fontes, "fontes_dfp": fontes_dfp, "documentos_lidos": len(docs), "cnpjs_ipe": len(por_cnpj),
        "cnpjs_cadastro_multiplos_periodos": sum(1 for v in cad.values() if len(v) > 1),
        "gatilhos_por_ano": dict(sorted(cont_ano.items())),
        "episodios_total": len(episodios),
        "episodios_prevalentes": sum(1 for e in episodios if e["prevalente"]),
        "incidentes_na_janela_antes_do_item4": len(na_janela),
        "fora_do_risco_item4": fora,
        "incidentes_na_janela": len(inc),
        "incidentes_por_particao": por_part,
        "incidentes_por_ano": {y: sum(1 for e in inc if e["data"].year == int(y))
                               for y in sorted({str(e["data"].year) for e in inc})},
        "formulacao_casada": sorted({e["formulacao"] for e in episodios if e["formulacao"]}),
        "g1_contagem": {"incidentes_janela": len(inc), "minimo": 25,
                        "teste_sem_formulacao": teste_sf, "minimo_teste": 10,
                        "passa_contagem": g1_ok,
                        "auditoria_manual_10": "ver nota 111, auditoria feita sobre a amostra da e1-v0"},
        "amostra_v0_1_nao_auditada": [{"cnpj": e["cnpj"], "nome": e["nome"], "data_evento": e["data"].isoformat(),
                                       "tipo": e["tipo"], "assunto": e["assunto"]} for e in amostra],
    }
    rpath = os.path.splitext(a.out)[0] + "_resumo.json"
    with open(rpath, "w", encoding="utf-8") as fh:
        json.dump(resumo, fh, ensure_ascii=False, indent=2)
    print(json.dumps({k: resumo[k] for k in ("implementacao", "documentos_lidos", "cnpjs_ipe",
                                              "cnpjs_cadastro_multiplos_periodos", "episodios_total",
                                              "episodios_prevalentes", "incidentes_na_janela_antes_do_item4",
                                              "fora_do_risco_item4", "incidentes_na_janela",
                                              "incidentes_por_particao", "g1_contagem")},
                     ensure_ascii=False, indent=1))
    print("CSV:", os.path.abspath(a.out))
    print("RESUMO:", os.path.abspath(rpath))
    return 0


if __name__ == "__main__":
    sys.exit(main())
