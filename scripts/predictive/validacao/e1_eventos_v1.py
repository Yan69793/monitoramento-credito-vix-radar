"""E1-v1 - base de eventos de credito pelo protocolo G0-v1.

Implementa os itens 1 (universo), 3 (evento e prevalencia), 4 (entrada no risco e
motivo de censura), 6 (particao) e o sorteio do G1 do item 10 do protocolo G0-v1
(nota 113 do vault, sha256 6b9ad652f6b423efd6e80f253a2972dbcdc99410223c9a7313560d158a021fff).

A e1_eventos.py (e1-v0.1, protocolo G0-v0) continua intacta. Daqui so se reaproveitam
os leitores de arquivo e as regras que a G0-v1 nao mudou (cadastro, DFP, item 4, particao,
conjunto de formulacao).

Somente leitura: le zips do IPE e da DFP da CVM e o cadastro, escreve apenas o CSV e o
resumo JSON de saida. Nao toca KV, Worker, rotinas nem rotulos. So biblioteca padrao.

Uso:
  python -I scripts/predictive/validacao/e1_eventos_v1.py \
      --ipe-dir data/cvm --ipe-dir E:/Diretorio/Claude/tmp/operacional/vix-radar/cvm-ipe \
      --dfp-dir E:/Diretorio/Claude/tmp/operacional/vix-radar/cvm-dfp \
      --cad data/cvm/cad_cia_aberta.csv --out data/validacao/eventos_v1.csv
"""
import argparse
import csv
import json
import os
import random
import re
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e1_eventos as V0  # noqa: E402  leitores e regras que a G0-v1 nao mudou

PROTOCOLO = "G0-v1"
PROTOCOLO_SHA256 = "6b9ad652f6b423efd6e80f253a2972dbcdc99410223c9a7313560d158a021fff"
IMPLEMENTACAO = "e1-v1"
SEMENTE_G1 = 20261016
N_AMOSTRA_G1 = 20
MIN_CORRETOS_G1 = 18

JANELA_INI = V0.JANELA_INI
JANELA_FIM = V0.JANELA_FIM
EXPIRA = timedelta(days=365)
LOOKBACK_PREV = timedelta(days=730)
DIST_AUDITADO = timedelta(days=30)

# Textos congelados no G0-v1, itens 1, 3 e 4. test_e1_eventos_v1.py confere que cada
# string aparece literalmente no bloco da nota 113.
RX_CAT_A = r"informacoes de companhias em recuperacao judicial ou extrajudicial"
RX_CAT_FR = r"fato relevante"
RX_A_ABRE = r"pedido|ajuiz|peticao inicial|deferi|processamento|requer|distribu"
RX_FR_POS = (r"recuperacao (judicial|extrajudicial)|pedido de falencia|autofalencia|decretacao de falencia"
             r"|vencimento antecipado|inadimpl|\bdefault\b|nao pagamento|suspensao (do |dos )?pagamento"
             r"|standstill|chapter 11|(tutela|medida|acao) cautelar|cautelar (antecedente|preparatoria)"
             r"|ajuizamento de cautelar|processo de reestruturacao"
             r"|reestruturacao (financeira|pre-acordada|de (suas )?dividas)|mediacao com (os |seus )?credores")
RX_FR_EXCL = (r"nao declara|renuncia|waiver|perdao|resgate antecipado|nao vencimento|sustacao|dividend"
              r"|remuneracao (anual )?(ao|aos) acionista|juros sobre (o )?capital|\bjcp\b"
              r"|(da|de sua|das|de suas) (controlad|investid|coligad)|devedor|lastro|\bcri\b|\bcra\b|\bccb\b|cedente")
RX_NAO_ABRE = (r"encerramento|aditamento|aditivo|alteracao do plano|aprovacao do plano|homologa|edital"
               r"|relatorio|cumprimento|convocacao|pagamento (a|aos|de|dos) credores")
RX_ENCERRA = r"encerramento"
RX_SEC_SETOR = r"securitiza"
RX_SEC_NOME = r"securitiz"
MOTIVOS_CENSURA = ("cancelamento voluntario", "elisao por incorporacao", "elisao por extincao da cia",
                   "cancelamento de oficio", "migracao de registro")

RE_CAT_A = re.compile(RX_CAT_A)
RE_CAT_FR = re.compile(RX_CAT_FR)
RE_A_ABRE = re.compile(RX_A_ABRE)
RE_FR_POS = re.compile(RX_FR_POS)
RE_FR_EXCL = re.compile(RX_FR_EXCL)
RE_NAO_ABRE = re.compile(RX_NAO_ABRE)
RE_ENCERRA = re.compile(RX_ENCERRA)
RE_SEC_SETOR = re.compile(RX_SEC_SETOR)
RE_SEC_NOME = re.compile(RX_SEC_NOME)

# Os 17 eventos ja auditados nas notas 111 e 112 (amostras da e1-v0 e da e1-v0.1).
AUDITADOS = [
    ("00.974.211/0001-25", date(2025, 6, 17)), ("03.847.461/0001-92", date(2019, 10, 31)),
    ("07.587.384/0001-30", date(2019, 5, 28)), ("08.903.116/0001-42", date(2019, 6, 18)),
    ("09.304.427/0001-58", date(2016, 6, 28)), ("09.305.994/0001-29", date(2025, 9, 17)),
    ("09.478.309/0001-66", date(2025, 7, 31)), ("10.647.979/0001-48", date(2016, 5, 30)),
    ("10.753.164/0001-43", date(2016, 6, 6)), ("12.104.241/0004-02", date(2026, 7, 14)),
    ("13.270.520/0001-66", date(2026, 5, 5)), ("24.956.666/0001-86", date(2013, 6, 6)),
    ("40.480.481/0001-02", date(2025, 7, 15)), ("61.584.140/0001-49", date(2012, 9, 3)),
    ("82.981.812/0001-20", date(2011, 5, 5)), ("91.333.666/0001-17", date(2016, 7, 19)),
    ("91.333.666/0001-17", date(2019, 5, 14)),
]


def eh_cat_a(doc):
    return bool(RE_CAT_A.search(doc["cat_n"]))


def eh_fr_positivo(doc):
    """(b) sem olhar RX_NAO_ABRE."""
    return (bool(RE_CAT_FR.search(doc["cat_n"])) and bool(RE_FR_POS.search(doc["assunto_n"]))
            and not RE_FR_EXCL.search(doc["assunto_n"]))


def gatilho_abertura(doc):
    """Item 3: retorna 'a', 'b' ou None."""
    a = doc["assunto_n"]
    if RE_NAO_ABRE.search(a):
        return None
    if eh_cat_a(doc) and RE_A_ABRE.search(a):
        return "a"
    if eh_fr_positivo(doc):
        return "b"
    return None


def doc_de_episodio(doc):
    return eh_cat_a(doc) or eh_fr_positivo(doc)


def eh_encerramento(doc):
    return doc_de_episodio(doc) and bool(RE_ENCERRA.search(doc["assunto_n"]))


def blocos_por_dia(lst):
    """D5: documentos do mesmo dia formam um bloco. lst ordenada por data."""
    blocos = []
    for d in lst:
        if blocos and blocos[-1][0] == d["data"]:
            blocos[-1][1].append(d)
        else:
            blocos.append((d["data"], [d]))
    return blocos


def construir_episodios(cnpj, lst, cont_ano=None):
    """Item 3 do G0-v1. lst: documentos IPE de um CNPJ ordenados por data."""
    eps = []
    ep = None
    for dia, bloco in blocos_por_dia(lst):
        if ep and not ep["fechado"] and dia > ep["ultimo"] + EXPIRA:
            ep["fechado"], ep["fim"], ep["fim_motivo"] = True, ep["ultimo"] + EXPIRA, "12m_sem_gatilho"
        aberturas = [(d, gatilho_abertura(d)) for d in bloco]
        aberturas = [(d, t) for d, t in aberturas if t]
        if cont_ano is not None:
            for _, t in aberturas:
                c = cont_ano.setdefault(str(dia.year), {"a": 0, "b": 0})
                c[t] += 1
        if (ep is None or ep["fechado"]) and aberturas:
            d0, t0 = aberturas[0]
            ep = {"cnpj": cnpj, "nome": d0["nome"], "data": dia, "ultimo": dia, "tipo": t0,
                  "assunto": d0["assunto"], "link": d0["link"], "protocolo": d0["protocolo"],
                  "n_docs": 0, "fechado": False, "fim": None, "fim_motivo": ""}
            eps.append(ep)
        if ep is None or ep["fechado"]:
            continue
        do_ep = [d for d in bloco if doc_de_episodio(d)]
        if do_ep:
            ep["ultimo"] = dia
            ep["n_docs"] += len(do_ep)
        if any(eh_encerramento(d) for d in bloco):
            ep["fechado"], ep["fim"], ep["fim_motivo"] = True, dia, "encerramento"
    for e in eps:
        if not e["fechado"] and e["ultimo"] + EXPIRA <= JANELA_FIM:
            e["fechado"], e["fim"], e["fim_motivo"] = True, e["ultimo"] + EXPIRA, "12m_sem_gatilho"
    return eps


def eh_prevalente(ep, lst):
    """Item 3: documento da categoria (a), qualquer assunto, nos 24 meses antes da data do evento.
    R7: Nome_Companhia nao entra."""
    ini = ep["data"] - LOOKBACK_PREV
    return any(ini <= d["data"] < ep["data"] and eh_cat_a(d) for d in lst)


def eh_securitizadora(lst, periodos):
    """Item 1: SETOR_ATIV casa securitiza, ou algum Nome_Companhia do IPE casa securitiz."""
    if any(RE_SEC_SETOR.search(V0.norm(p.get("setor_ativ", ""))) for p in periodos):
        return True
    return any(RE_SEC_NOME.search(d["nome_n"]) for d in lst)


def motivo_censura(motivo_cancel):
    """Item 4: devolve o motivo normalizado se ele censura, senao ''."""
    m = V0.norm(motivo_cancel)
    return next((x for x in MOTIVOS_CENSURA if m.startswith(x)), "")


def perto_de_auditado(cnpj, d):
    return any(c == cnpj and abs(d - da) <= DIST_AUDITADO for c, da in AUDITADOS)


def sortear_amostra_g1(incidentes):
    elegiveis = sorted((e for e in incidentes if not perto_de_auditado(e["cnpj"], e["data"])),
                       key=lambda e: (e["data"], e["cnpj"]))
    rnd = random.Random(SEMENTE_G1)
    return rnd.sample(elegiveis, min(N_AMOSTRA_G1, len(elegiveis))), len(elegiveis)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipe-dir", action="append", required=True)
    ap.add_argument("--dfp-dir", action="append", required=True)
    ap.add_argument("--cad", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    docs, fontes = V0.ler_ipe(a.ipe_dir)
    primeira_dfp, fontes_dfp = V0.ler_dfp_primeira_entrega(a.dfp_dir)
    cad = V0.ler_cad(a.cad)

    por_cnpj = {}
    for d in docs:
        por_cnpj.setdefault(d["cnpj"], []).append(d)
    for lst in por_cnpj.values():
        lst.sort(key=lambda x: (x["data"], x["protocolo"]))

    cont_ano = {}
    episodios = []
    securitizadoras = set()
    a_sem_episodio = 0
    for cnpj, lst in por_cnpj.items():
        periodos = cad.get(cnpj, [])
        sec = eh_securitizadora(lst, periodos)
        if sec:
            securitizadoras.add(cnpj)
        eps = construir_episodios(cnpj, lst, None if sec else cont_ano)
        for e in eps:
            e["universo"] = not sec
        episodios.extend(eps)
        if not sec and not eps and any(eh_cat_a(d) and JANELA_INI <= d["data"] <= JANELA_FIM for d in lst):
            a_sem_episodio += 1

    for ep in episodios:
        lst = por_cnpj[ep["cnpj"]]
        ep["prevalente"] = eh_prevalente(ep, lst)
        periodos = cad.get(ep["cnpj"], [])
        ok, motivo, per = V0.em_risco(ep["data"], periodos, primeira_dfp.get(ep["cnpj"]))
        ep["em_risco"], ep["fora_risco_motivo"] = ok, motivo
        ep["primeira_dfp"] = primeira_dfp.get(ep["cnpj"])
        nomes = {d["nome_n"] for d in lst}
        for p in periodos:
            nomes.add(V0.norm(p["denom_social"]))
            nomes.add(V0.norm(p["denom_comerc"]))
        ep["formulacao"] = next((n for n, rx in V0.FORMULACAO if any(rx.search(x) for x in nomes if x)), "")
        ep["particao"] = V0.particao(ep["data"])
        per = per or {}
        ep["dt_reg"], ep["dt_cancel"] = per.get("dt_reg"), per.get("dt_cancel")
        ep["motivo_cancel"] = per.get("motivo_cancel", "")
        ep["censura_motivo"] = motivo_censura(ep["motivo_cancel"])
        ep["setor_ativ"] = per.get("setor_ativ", "")
        ep["n_periodos_cad"] = len(periodos)

    iso = lambda x: x.isoformat() if x else ""
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    campos = ["cnpj", "nome", "data_evento", "particao", "universo", "incidente", "em_risco", "fora_risco_motivo",
              "formulacao", "tipo_gatilho", "n_docs_episodio", "fim_episodio", "fim_motivo", "assunto", "link_cvm",
              "protocolo", "setor_ativ", "dt_reg", "dt_cancel", "motivo_cancel", "censura_motivo", "primeira_dfp",
              "n_periodos_cad"]
    with open(a.out, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter=";", lineterminator="\n")
        w.writerow(campos)
        for ep in sorted(episodios, key=lambda e: (e["data"], e["cnpj"])):
            w.writerow([ep["cnpj"], ep["nome"], iso(ep["data"]), ep["particao"], int(ep["universo"]),
                        int(not ep["prevalente"]), int(ep["em_risco"]), ep["fora_risco_motivo"], ep["formulacao"],
                        ep["tipo"], ep["n_docs"], iso(ep["fim"]), ep["fim_motivo"], ep["assunto"], ep["link"],
                        ep["protocolo"], ep["setor_ativ"], iso(ep["dt_reg"]), iso(ep["dt_cancel"]),
                        ep["motivo_cancel"], ep["censura_motivo"], iso(ep["primeira_dfp"]), ep["n_periodos_cad"]])

    no_univ = [e for e in episodios if e["universo"]]
    na_janela = [e for e in no_univ if not e["prevalente"] and e["particao"] != "fora_janela"]
    inc = [e for e in na_janela if e["em_risco"]]
    chaves = [(e["cnpj"], e["data"]) for e in inc]
    fora = {}
    for e in na_janela:
        if not e["em_risco"]:
            fora[e["fora_risco_motivo"]] = fora.get(e["fora_risco_motivo"], 0) + 1
    por_part = {}
    for e in inc:
        k = por_part.setdefault(e["particao"], {"total": 0, "sem_formulacao": 0, "por_tipo": {}})
        k["total"] += 1
        k["sem_formulacao"] += 0 if e["formulacao"] else 1
        k["por_tipo"][e["tipo"]] = k["por_tipo"].get(e["tipo"], 0) + 1
    teste_sf = por_part.get("teste", {}).get("sem_formulacao", 0)
    passa_contagem = len(inc) >= 25 and teste_sf >= 10
    amostra, n_eleg = sortear_amostra_g1(inc)

    resumo = {
        "protocolo": PROTOCOLO, "protocolo_sha256": PROTOCOLO_SHA256, "implementacao": IMPLEMENTACAO,
        "fontes_ipe": fontes, "fontes_dfp": fontes_dfp, "documentos_lidos": len(docs), "cnpjs_ipe": len(por_cnpj),
        "cnpjs_securitizadoras_fora_do_universo": len(securitizadoras),
        "episodios_securitizadoras_descartados": sum(1 for e in episodios if not e["universo"]),
        "cnpjs_com_categoria_a_na_janela_sem_episodio": a_sem_episodio,
        "gatilhos_abertura_por_ano": dict(sorted(cont_ano.items())),
        "episodios_no_universo": len(no_univ),
        "episodios_prevalentes": sum(1 for e in no_univ if e["prevalente"]),
        "incidentes_na_janela_antes_do_item4": len(na_janela),
        "fora_do_risco_item4": fora,
        "incidentes_na_janela": len(inc),
        "chaves_cnpj_data_duplicadas": len(chaves) - len(set(chaves)),
        "incidentes_por_particao": por_part,
        "incidentes_por_ano": {y: sum(1 for e in inc if e["data"].year == int(y))
                               for y in sorted({str(e["data"].year) for e in inc})},
        "incidentes_com_censura_posterior": {m: sum(1 for e in inc if e["censura_motivo"] == m)
                                             for m in MOTIVOS_CENSURA},
        "g1_contagem": {"incidentes_janela": len(inc), "minimo": 25, "teste_sem_formulacao": teste_sf,
                        "minimo_teste": 10, "passa_contagem": passa_contagem},
        "g1_auditoria": {"semente": SEMENTE_G1, "n": N_AMOSTRA_G1, "minimo_corretos": MIN_CORRETOS_G1,
                         "elegiveis_apos_excluir_auditados": n_eleg, "estado": "PENDENTE"},
        "amostra_g1": [{"ordem": i + 1, "cnpj": e["cnpj"], "nome": e["nome"], "data_evento": e["data"].isoformat(),
                        "particao": e["particao"], "formulacao": e["formulacao"], "tipo": e["tipo"],
                        "assunto": e["assunto"], "link": e["link"], "protocolo": e["protocolo"]}
                       for i, e in enumerate(amostra)],
    }
    rpath = os.path.splitext(a.out)[0] + "_resumo.json"
    with open(rpath, "w", encoding="utf-8") as fh:
        json.dump(resumo, fh, ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in resumo.items() if k not in ("fontes_ipe", "fontes_dfp", "amostra_g1",
                                                                  "gatilhos_abertura_por_ano")},
                     ensure_ascii=False, indent=1))
    print("CSV:", os.path.abspath(a.out))
    print("RESUMO:", os.path.abspath(rpath))
    return 0


if __name__ == "__main__":
    sys.exit(main())
