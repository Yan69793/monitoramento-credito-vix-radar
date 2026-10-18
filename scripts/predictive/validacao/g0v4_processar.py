"""G0-v4: processa localmente os itens da etapa 1 com g0v4_regras, com checkpoint, idempotencia e retomada.

Isolamento: so le itens_cegos.json, manifesto_itens.json, manifesto_documentos.json, proveniencia_downloads.jsonl e os
textos locais (TXT, TXT_RENDER). NUNCA le mapa_camadas.json nem rotulos legados. Sem rede, sem modelo.
Escreve somente em SAIDA_DIR (padrao data/validacao/g0v4/):
  classificacoes.jsonl   so-acrescenta, uma linha por item e versao (sha256 do registro sem carimbo de tempo)
  execucao.lock          trava contra duas execucoes simultaneas
  execucao.log.jsonl     inicio, fim e contagens de cada rodada

Retomada: item ja presente com a mesma versao e o mesmo sha256 das regras e pulado. Linha corrompida no fim do
arquivo (queda no meio da escrita) e ignorada na leitura e o item e refeito.

Uso:
  python -I g0v4_processar.py rodar [--ids i0151,i0152 | --de N --ate M] [--saida DIR] [--docs DIR]
  python -I g0v4_processar.py status [--saida DIR]
"""
import datetime as dt
import hashlib
import json
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_regras as RG  # noqa: E402

BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
ETAPA = os.path.join(BASE, "data", "validacao", "etapa1_g0v2")
SAIDA = os.path.join(BASE, "data", "validacao", "g0v4")
DOCS = os.path.abspath(os.path.join(BASE, "..", "tmp", "operacional", "vix-radar", "ews-etapa1"))


def sha256_arquivo(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def sha_regras():
    return sha256_arquivo(os.path.join(AQUI, "g0v4_regras.py"))


class Textos:
    """Texto integral local: TXT (extraido) e, se vazio, TXT_RENDER (transcricao de pagina renderizada)."""

    def __init__(self, docs):
        self.docs = docs
        self.fonte = {}

    def caminho(self, p):
        achado = (None, None, None)
        for sub in ("TXT", "TXT_RENDER"):
            f = os.path.join(self.docs, sub, "%s.txt" % p)
            if os.path.exists(f):
                with open(f, encoding="utf-8", errors="ignore") as fh:
                    t = fh.read()
                if len(t.strip()) >= RG.MIN_TEXTO:
                    return f, t, sub
                if achado[0] is None:
                    achado = (f, t, sub)
        return achado

    def __call__(self, p):
        f, t, sub = self.caminho(p)
        self.fonte[p] = (f, sub)
        return t


def carregar(etapa=ETAPA):
    itens = json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))
    man = {m["id"]: m for m in json.load(open(os.path.join(etapa, "manifesto_itens.json"), encoding="utf-8"))}
    meta = {d["protocolo_rad"]: d for d in json.load(open(os.path.join(etapa, "manifesto_documentos.json"), encoding="utf-8"))}
    prov = {}
    pp = os.path.join(etapa, "proveniencia_downloads.jsonl")
    if os.path.exists(pp):
        for ln in open(pp, encoding="utf-8"):
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            prov[str(r.get("protocolo_rad"))] = {"sha256": r.get("sha256"), "baixado_em": r.get("baixado_em"), "status": r.get("status")}
    return itens, man, meta, prov


def ler_feitos(arq):
    feitos = {}
    if not os.path.exists(arq):
        return feitos
    with open(arq, encoding="utf-8") as fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            feitos[(r["id"], r["versao"], r["sha256_regras"])] = r
    return feitos


def citados(reg):
    ps = [reg.get("protocolo_evento")] + [(reg.get("origem") or {}).get("protocolo")] + [a.get("protocolo") for a in reg.get("adicionais") or []]
    return [p for p in ps if p]


def rastreabilidade(reg, textos, prov):
    """Todo trecho afirmado e conferido contra o texto integral; cada documento citado leva sha256 do texto e do original."""
    falhas, docs = [], {}
    pares = []
    if reg.get("trecho_evento"):
        pares.append(("evento", reg.get("protocolo_evento"), reg["trecho_evento"]))
    o = reg.get("origem") or {}
    if o.get("trecho"):
        pares.append(("origem", o.get("protocolo"), o["trecho"]))
    for k, a in enumerate(reg.get("adicionais") or []):
        pares.append(("adicional_%d" % k, a.get("protocolo"), a.get("trecho")))
    for onde, p, tr in pares:
        t = textos(p)
        if not RG.confere(tr, t):
            falhas.append("%s: trecho nao confere no documento %s" % (onde, p))
    for p in sorted(set(citados(reg)) | {e["protocolo"] for e in reg["entradas"] if e["grupo"] == "dia"}):
        textos(p)
        f, sub = textos.fonte.get(p, (None, None))
        docs[p] = {"texto_fonte": sub, "sha256_texto": sha256_arquivo(f) if f else None,
                   "sha256_original": (prov.get(p) or {}).get("sha256"), "baixado_em": (prov.get(p) or {}).get("baixado_em")}
    material = reg["classe"] in ("evento_proprio", "continuacao", "evento_terceiro")
    completa = not falhas and (not material or bool(pares))
    if reg["classe"] == "continuacao" and not (o.get("completa") and o.get("trecho")):
        completa = False
        falhas.append("continuacao sem origem completa")
    return {"conferida": completa, "falhas": falhas, "documentos": docs}


def processar_item(it, man, meta, prov, textos, shar):
    reg = RG.classificar(it, man[it["id"]], meta, textos)
    reg["rastreabilidade"] = rastreabilidade(reg, textos, prov)
    if not reg["rastreabilidade"]["conferida"] and reg["classe"] != "PENDENTE_REVISAO":
        # afirmacao material sem trecho conferido nao pode ficar de pe
        reg["motivos_revisao"].append("rastreabilidade: " + "; ".join(reg["rastreabilidade"]["falhas"]))
        reg["classe_antes_rastreio"] = reg["classe"]
        reg["classe"], reg["caminho"], reg["confianca"], reg["revisao_obrigatoria"] = "PENDENTE_REVISAO", "rastreio_falhou", "baixa", True
    reg["sha256_regras"] = shar
    corpo = json.dumps(reg, ensure_ascii=False, sort_keys=True)
    reg["sha256_registro"] = hashlib.sha256(corpo.encode("utf-8")).hexdigest()
    reg["processado_em"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    return reg


def rodar(ids=None, saida=SAIDA, docs=DOCS, etapa=ETAPA):
    os.makedirs(saida, exist_ok=True)
    lock = os.path.join(saida, "execucao.lock")
    if os.path.exists(lock):
        print(json.dumps({"bloqueado": "execucao.lock presente (outra execucao em curso ou queda anterior)", "lock": lock}))
        return 3
    with open(lock, "w", encoding="utf-8") as fh:
        fh.write(str(os.getpid()))
    try:
        shar = sha_regras()
        itens, man, meta, prov = carregar(etapa)
        alvo = [it for it in itens if (ids is None or it["id"] in ids)]
        arq = os.path.join(saida, "classificacoes.jsonl")
        feitos = ler_feitos(arq)
        if os.path.exists(arq) and os.path.getsize(arq) > 0:
            with open(arq, "rb") as fh:
                fh.seek(-1, 2)
                termina = fh.read(1) == b"\n"
            if not termina:  # queda no meio da escrita: isola a linha parcial para o proximo registro nao colar nela
                with open(arq, "a", encoding="utf-8", newline="\n") as fh:
                    fh.write("\n")
        log = os.path.join(saida, "execucao.log.jsonl")
        t0 = time.time()
        novos, pulados = 0, 0
        with open(log, "a", encoding="utf-8", newline="\n") as lg:
            lg.write(json.dumps({"evento": "inicio", "em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "versao": RG.VERSAO,
                                 "sha256_regras": shar, "n_alvo": len(alvo), "docs": docs}) + "\n")
        for it in alvo:
            if (it["id"], RG.VERSAO, shar) in feitos:
                pulados += 1
                continue
            textos = Textos(docs)
            reg = processar_item(it, man, meta, prov, textos, shar)
            with open(arq, "a", encoding="utf-8", newline="\n") as fh:
                fh.write(json.dumps(reg, ensure_ascii=False) + "\n")
                fh.flush()
                os.fsync(fh.fileno())
            novos += 1
            if novos % 50 == 0:
                print(json.dumps({"progresso": novos, "pulados": pulados, "seg": round(time.time() - t0, 1)}), flush=True)
        with open(log, "a", encoding="utf-8", newline="\n") as lg:
            lg.write(json.dumps({"evento": "fim", "em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "novos": novos,
                                 "pulados": pulados, "seg": round(time.time() - t0, 1)}) + "\n")
        print(json.dumps({"ok": True, "novos": novos, "pulados": pulados, "seg": round(time.time() - t0, 1), "sha256_regras": shar}))
        return 0
    finally:
        os.remove(lock)


def status(saida=SAIDA):
    import collections
    arq = os.path.join(saida, "classificacoes.jsonl")
    shar = sha_regras()
    regs = [r for k, r in ler_feitos(arq).items() if k[1] == RG.VERSAO and k[2] == shar]
    c = collections.Counter(r["classe"] for r in regs)
    cam = collections.Counter(r["caminho"] for r in regs)
    out = {"versao": RG.VERSAO, "sha256_regras": shar, "n": len(regs), "ids_unicos": len({r["id"] for r in regs}),
           "classes": dict(c), "caminhos": dict(cam), "revisao_obrigatoria": sum(r["revisao_obrigatoria"] for r in regs)}
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    if not argv or argv[0] not in ("rodar", "status"):
        print(__doc__)
        return 2
    saida = opt("--saida", SAIDA)
    if argv[0] == "status":
        return status(saida)
    ids = None
    if opt("--ids"):
        ids = set(x.strip() for x in opt("--ids").split(",") if x.strip())
    elif opt("--de"):
        ids = {"i%04d" % k for k in range(int(opt("--de")), int(opt("--ate")) + 1)}
    return rodar(ids, saida=saida, docs=opt("--docs", DOCS))


if __name__ == "__main__":
    sys.exit(main())
