"""Detecta eventos novos dos 104 emissores para a conferencia do EWS 2.0 (EWS2CONF1).

Fonte: IPE da CVM (data/cvm/ipe_cia_aberta_<ano>.zip, renovado semanalmente pela VIXRadar-Reconciliacao-CVM). Candidato =
dia de um emissor com algum documento de categoria/assunto de gatilho forte (RX_META_FORTE da g0v4_regras). Para cada
candidato baixa do RAD (leitura publica, sem login, nunca contorna CAPTCHA) os documentos do dia e do contexto de 180 dias,
extrai o texto e aplica o mesmo classificador local do G0-v4 (g0v4_regras.classificar). Evento = classe evento_proprio.
Sem LLM, sem API paga. Subestima eventos (revocacao do G0-v4 entre 23% e 67%, nota 125): o vies vale para os dois sistemas.

Cache so-acrescenta em data/ews2-conferencia/classificacoes.jsonl (chave: emissor, dia, documentos do dia, versao e hash das
regras). Textos e originais em E:\\Diretorio\\Claude\\tmp\\operacional\\vix-radar\\ews2-conferencia (fora do repo).

Uso (alem de importado pela conferencia.py):
  python -I conferencia_eventos.py replay --de AAAA-MM-DD --ate AAAA-MM-DD [--sem-rede]   mede o detector contra os rotulos
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
VAL = os.path.abspath(os.path.join(AQUI, "..", "validacao"))
sys.path.insert(0, VAL)
import dados as D  # noqa: E402
import eventos as EV  # noqa: E402
import baixar_etapa1 as BX  # noqa: E402
import g0v4_regras as RG  # noqa: E402

BASE = D.BASE
ROTULOS = os.path.join(BASE, "data", "validacao", "g0v4", "rotulos_g0v4_final.csv")
CACHE_DIR = os.path.join(BASE, "data", "ews2-conferencia")
CACHE = os.path.join(CACHE_DIR, "classificacoes.jsonl")
DOCS_DIR = r"E:\Diretorio\Claude\tmp\operacional\vix-radar\ews2-conferencia"
MAPA = os.path.join(BASE, "scripts", "predictive", "cnpj_emissores.json")
ROTULOS_ATE = dt.date(2026, 9, 30)      # os rotulos cobrem a janela da regua de K ate esta data
# textos ja extraidos na etapa 1 (mesmo numProtocolo): lidos antes de baixar, nunca alterados
TEXTOS_ETAPA1 = [os.path.join(os.path.dirname(BASE), "tmp", "operacional", "vix-radar", "ews-etapa1", x) for x in ("TXT", "TXT_RENDER")]
CONTEXTO_DIAS = 180
INDICE_MESES = 24
# So comunicacao da companhia ao mercado gera evento. Assembleia, escritura/aditamento de debenture e demonstracao
# financeira trazem clausula de vencimento antecipado como texto padrao (medido no replay de 2026: Eneva e Sabesp saiam
# como falencia por clausula de escritura), entao ficam fora do dia e do contexto lidos pelo classificador.
CATS_EVENTO = ("fato relevante", "comunicado ao mercado", "aviso aos debenturistas",
               "informacoes de companhias em recuperacao judicial ou extrajudicial")
DETECCAO_V = "cat-v1"
# Evento = DIA MATERIAL: comunicado do emissor com ato proprio de credito (RJ, RE, falencia, vencimento antecipado,
# inadimplemento, cautelar contra credores). O classificador separa "evento_proprio" de "continuacao" olhando 180 dias de
# contexto, e no ensaio de 2026 isso errou o dia do evento em 5 de 5 casos (o contexto trazia negociacao anterior do mesmo
# tipo). Quem decide se o dia abre um episodio novo e a conferencia (episodio de 30 dias, categoria A em 730 dias, episodio
# anterior em 365 dias), que e o mesmo criterio do backtest. Medido em data/validacao/ews2_detector_validacao.json.
CLASSES_MATERIAIS = ("evento_proprio", "continuacao")
CAT_A_DIAS = 730
WARMUP_INICIO = dt.date(2025, 7, 1)
RETENTAR_DIAS = 7
PAUSA = 0.25


def pid(d):
    """Identificador do documento no RAD (numProtocolo do link), o mesmo da etapa 1; Protocolo_Entrega do IPE e outro."""
    m = re.search(r"numProtocolo=(\d+)", d.get("link") or "")
    return m.group(1) if m else d["protocolo"]


def sha_regras():
    return hashlib.sha256(open(os.path.join(VAL, "g0v4_regras.py"), "rb").read().replace(b"\r\n", b"\n")).hexdigest()


# ---------------------------------------------------------------- texto
class Textos:
    def __init__(self, docs_dir, rede, hoje):
        self.dir, self.rede, self.hoje = docs_dir, rede, hoje
        self.falhas = {}
        self.baixados = 0
        os.makedirs(os.path.join(docs_dir, "DOCS"), exist_ok=True)
        os.makedirs(os.path.join(docs_dir, "TXT"), exist_ok=True)
        self.prov = os.path.join(docs_dir, "proveniencia.jsonl")
        if os.path.exists(self.prov):
            for ln in open(self.prov, encoding="utf-8"):
                try:
                    j = json.loads(ln)
                except ValueError:
                    continue
                if not j.get("status", "").startswith("ok"):
                    self.falhas[j["protocolo"]] = j["data"]

    def _txt(self, p):
        proprio = os.path.join(self.dir, "TXT", "%s.txt" % p)
        if os.path.exists(proprio):
            return proprio
        for d in TEXTOS_ETAPA1:
            f = os.path.join(d, "%s.txt" % p)
            if os.path.exists(f) and len(open(f, encoding="utf-8", errors="ignore").read().strip()) >= RG.MIN_TEXTO:
                return f
        return proprio

    def garantir(self, p, url):
        if os.path.exists(self._txt(p)):
            return True
        if not self.rede or not url:
            return False
        ultima = self.falhas.get(p)
        if ultima and (self.hoje - dt.date.fromisoformat(ultima)).days < RETENTAR_DIAS:
            return False
        tmp = os.path.join(self.dir, "DOCS", "%s.part" % p)
        reg = None
        for tent in range(1, 4):
            http, nome, rc = BX.baixar(url, tmp)
            b = open(tmp, "rb").read() if os.path.exists(tmp) else b""
            tp = BX.tipo_por_magia(b)
            if http == 200 and tp in ("pdf", "doc", "docx"):
                final = os.path.join(self.dir, "DOCS", "%s.%s" % (p, tp))
                os.replace(tmp, final)
                st = BX.extrair_texto(final, tp, os.path.join(self.dir, "TXT", "%s.txt" % p))
                reg = {"protocolo": p, "status": "ok" if st == "ok" else "ok_sem_texto", "tipo": tp, "bytes": len(b),
                       "sha256": hashlib.sha256(b).hexdigest()}
                break
            reg = {"protocolo": p, "status": "inacessivel", "tipo": tp, "http": http, "bytes": len(b)}
            if tp == "captcha":
                break
            time.sleep(2 * tent)
        if os.path.exists(tmp):
            os.remove(tmp)
        reg.update({"url": url, "data": self.hoje.isoformat(), "baixado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
        with open(self.prov, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(reg, ensure_ascii=False) + "\n")
        self.baixados += 1
        time.sleep(PAUSA)
        if not reg["status"].startswith("ok"):
            self.falhas[p] = self.hoje.isoformat()
        return os.path.exists(self._txt(p))

    def ler(self, p):
        f = self._txt(p)
        if not os.path.exists(f):
            return None
        return open(f, encoding="utf-8", errors="ignore").read()


# ---------------------------------------------------------------- candidatos
def meta_texto(d):
    return RG.sem_acento("%s %s" % (d["cat_n"], d["assunto_n"]))


def candidatos(docs, cnpjs, de, ate):
    """Dias (emissor, data) em [de, ate] com algum documento de gatilho forte. Devolve {(cnpj, data): [docs do dia]}."""
    por_dia = {}
    for d in docs:
        if d["cnpj"] in cnpjs and de <= d["data"] <= ate and d["cat_n"] in CATS_EVENTO:
            por_dia.setdefault((d["cnpj"], d["data"]), []).append(d)
    return {k: v for k, v in por_dia.items() if any(RG.RX_META_FORTE.search(meta_texto(d)) for d in v)}


def montar(cnpj, dia, docs_por, textos):
    """item, man_item e meta no formato que o classificador espera. O contexto de 180 dias baixa so categorias de
    comunicacao ao mercado; o resto entra pelo indice de metadado, como no indice de 24 meses da etapa 1."""
    lst = docs_por.get(cnpj, [])
    dia_docs = [d for d in lst if d["data"] == dia and d["cat_n"] in CATS_EVENTO]
    ctx = [d for d in lst if dia - dt.timedelta(days=CONTEXTO_DIAS) <= d["data"] < dia]
    ctx_baixar = [d for d in ctx if d["cat_n"] in CATS_EVENTO]
    idx = [d for d in lst if dia - dt.timedelta(days=INDICE_MESES * 31) <= d["data"] < dia - dt.timedelta(days=CONTEXTO_DIAS)]
    meta = {pid(d): {"data_entrega": d["data"].isoformat(), "categoria": d["cat_n"], "assunto": d["assunto_n"]} for d in dia_docs + ctx}
    man = {"dia": [pid(d) for d in dia_docs], "contexto_180d": [pid(d) for d in ctx_baixar],
           "indice_24m": [{"data": d["data"].isoformat(), "categoria": d["cat_n"], "assunto": d["assunto_n"], "protocolo_rad": pid(d), "link": d["link"]} for d in idx]}
    return {"id": "%s@%s" % (cnpj, dia.isoformat()), "cnpj": cnpj, "data": dia.isoformat()}, man, meta, dia_docs + ctx_baixar


# ---------------------------------------------------------------- cache
def ler_cache():
    out = {}
    if os.path.exists(CACHE):
        for ln in open(CACHE, encoding="utf-8"):
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            out[r["chave"]] = r
    return out


def classificar_dia(cnpj, dia, docs_por, textos, cache, sha):
    item, man, meta, baixar = montar(cnpj, dia, docs_por, textos)
    chave = "%s|%s|%s|%s|%s|%s" % (cnpj, dia.isoformat(), ",".join(sorted(man["dia"])), DETECCAO_V, RG.VERSAO, sha[:16])
    if chave in cache:
        return cache[chave], False
    faltam = 0
    for d in baixar:
        if not textos.garantir(pid(d), d["link"]):
            faltam += 1
    if faltam and not textos.rede:
        return None, False          # sem rede e sem cache: nao classificado
    reg = RG.classificar(item, man, meta, textos.ler)
    r = {"chave": chave, "cnpj": cnpj, "data": dia.isoformat(), "classe": reg["classe"], "tipo": reg.get("tipo"),
         "data_evento": reg.get("data_evento"), "protocolo_evento": reg.get("protocolo_evento"), "caminho": reg.get("caminho"),
         "confianca": reg.get("confianca"), "docs_sem_texto": faltam, "versao": RG.VERSAO, "deteccao": DETECCAO_V, "sha_regras": sha,
         "classificado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(CACHE, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    cache[chave] = r
    return r, True


def detectar(docs, cnpjs, de, ate, sem_rede, hoje, docs_dir=DOCS_DIR):
    docs_por = {}
    for d in docs:
        if d["cnpj"] in cnpjs:
            docs_por.setdefault(d["cnpj"], []).append(d)
    for v in docs_por.values():
        v.sort(key=lambda x: x["data"])
    cand = candidatos(docs, cnpjs, de, ate)
    textos = Textos(docs_dir, not sem_rede, hoje)
    cache, sha = ler_cache(), sha_regras()
    cata = cat_a_por_cnpj(docs)
    ev, cont = [], {"candidatos": len(cand), "evento_proprio": 0, "continuacao": 0, "pendente": 0, "outras_classes": 0, "nao_classificados": 0, "novos": 0}
    for (cnpj, dia) in sorted(cand, key=lambda k: (k[1], k[0])):
        r, novo = classificar_dia(cnpj, dia, docs_por, textos, cache, sha)
        cont["novos"] += int(novo)
        if r is None:
            cont["nao_classificados"] += 1
        elif r["classe"] in CLASSES_MATERIAIS:
            cont[r["classe"]] = cont.get(r["classe"], 0) + 1
            ev.append({"cnpj": cnpj, "data": dia.isoformat(), "fonte": "ipe+regras", "tipo": r.get("tipo"), "classe": r["classe"],
                       "prev_cat_a": any(dia - dt.timedelta(days=CAT_A_DIAS) <= x < dia for x in cata.get(cnpj, [])), "dia_documento": dia.isoformat()})
        elif r["classe"] == "PENDENTE_REVISAO":
            cont["pendente"] += 1
        else:
            cont["outras_classes"] += 1
    cont["documentos_baixados"] = textos.baixados
    return ev, cont


def cat_a_por_cnpj(docs):
    out = {}
    for d in docs:
        if EV.RX_CAT_A.search(d["cat_n"]):
            out.setdefault(d["cnpj"], []).append(d["data"])
    return out


def cnpjs_emissores():
    return {v["cnpj"] for v in json.load(open(MAPA, encoding="utf-8")).values()}


def eventos(hoje, sem_rede=False, primeiro_pacote=None):
    """Eventos para a conferencia: rotulos finais (so para prevalencia) mais os dias materiais detectados desde o aquecimento
    (WARMUP_INICIO, um ano antes do primeiro pacote, para saber quem ja estava em RJ/RE)."""
    rot = EV.ler_rotulos(ROTULOS)
    evs = [{"cnpj": e["cnpj"], "data": e["data"], "fonte": "rotulo"} for e in EV.eventos_de_rotulos(rot)]
    docs, _ = D.ler_ipe()
    det_ev, cont = detectar(docs, cnpjs_emissores(), WARMUP_INICIO, hoje, sem_rede, hoje)
    cont["rotulos_eventos"] = len(evs)
    cont["ipe_max_entrega"] = max((d["data"] for d in docs), default=None).isoformat() if docs else None
    return evs + det_ev, cont


# ---------------------------------------------------------------- replay: mede o detector contra os rotulos
def replay(de, ate, sem_rede, hoje):
    rot = EV.ler_rotulos(ROTULOS)
    nossos = cnpjs_emissores()
    verdade = {(r["cnpj"].strip(), r["data"]) for r in rot if (r.get("classe_final") or "") in CLASSES_MATERIAIS and de.isoformat() <= r["data"] <= ate.isoformat() and r["cnpj"].strip() in nossos}
    itens = {(r["cnpj"].strip(), r["data"]) for r in rot if de.isoformat() <= r["data"] <= ate.isoformat() and r["cnpj"].strip() in nossos}
    docs, _ = D.ler_ipe()
    ev, cont = detectar(docs, cnpjs_emissores(), de, ate, sem_rede, hoje)
    achados = {(e["cnpj"], e["dia_documento"]) for e in ev}
    cand = set(candidatos(docs, cnpjs_emissores(), de, ate))
    cand_s = {(c, d.isoformat()) for c, d in cand}
    tp = len(achados & verdade)
    return {"janela": [de.isoformat(), ate.isoformat()], "itens_rotulados": len(itens), "eventos_rotulados": len(verdade), "detectados": len(achados),
            "acertos": tp, "so_detectados": sorted(achados - verdade), "so_rotulados": sorted(verdade - achados),
            "rotulados_fora_dos_candidatos": sorted(verdade - cand_s), "precisao": round(tp / len(achados), 3) if achados else None,
            "revocacao": round(tp / len(verdade), 3) if verdade else None, "deteccao": cont}


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("replay")
    r.add_argument("--de", required=True)
    r.add_argument("--ate", required=True)
    r.add_argument("--sem-rede", action="store_true")
    a = ap.parse_args(argv)
    out = replay(dt.date.fromisoformat(a.de), dt.date.fromisoformat(a.ate), a.sem_rede, dt.date.today())
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
