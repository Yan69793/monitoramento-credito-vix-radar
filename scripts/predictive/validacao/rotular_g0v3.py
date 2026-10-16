"""Rotulador de UM item pela recuperacao progressiva da G0-v3 (nota 120, item 2). Primeiro rotulador.

Fluxo (sem estado entre chamadas; cada rodada e um processo novo que recebe tudo de novo):
  rodada 0  guia congelado (item 2 do bloco G0-v3 + anexo G0-v2) + pacote niveis 0 e 1 (recuperar_g0v3.pacote)
  rodada n  o mesmo, mais as paginas ja servidas no nivel 2 (ate RODADAS rodadas, TETO_N2 chars cada)
  O modelo responde ou com pedidos de paginas (acao "pedir_paginas") ou com o rotulo (acao "rotular").
  Depois do rotulo, todo trecho literal e conferido contra o texto integral (verificar_trecho). Trecho que
  nao esta no documento invalida o rotulo (status "adjudicacao"), nunca e corrigido aqui.

Trava: guarda_g0v3.estado()["ok"] tem que ser True; senao sai sem chamar modelo (exit 1).
Isolamento: o prompt nao recebe camada, estrato, EWS, sinal, rotulo de outro avaliador nem resultado de
rotina. A funcao montar_prompt so enxerga (item, manifesto do item, metadados dos documentos, textos).
Documento nao baixado pedido no nivel 2 e baixado na hora com a mesma integridade do baixar_etapa1, com
proveniencia propria (proveniencia_nivel2.jsonl) para nao concorrer com o baixador em segundo plano.
Documento sem texto extraivel pedido no nivel 2 e renderizado por pagina (PyMuPDF) e transcrito pelo modelo
com a ferramenta Read restrita ao diretorio da renderizacao; a transcricao e registrada e serve como texto.

Uso: python -I rotular_g0v3.py ETAPA_DIR DOCS_DIR SAIDA_DIR ID [--modelo M] [--provider claude|codex] [--dry-run]
"""
import datetime as dt
import hashlib
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import baixar_etapa1 as B  # noqa: E402
import guarda_g0v2 as G2  # noqa: E402
import guarda_g0v3 as G3  # noqa: E402
import llm_cli as L  # noqa: E402
import recuperar_g0v3 as R  # noqa: E402

VERSAO_EXECUTOR = "progressiva-v0.2"  # v0.2: renderizacao com caminho absoluto e transcricao por pagina acumulada
CLASSES = ["evento_proprio", "evento_terceiro", "continuacao", "nao_evento", "incerto"]
TIPOS = ["RJ", "RE", "falencia", "vencimento_antecipado_ou_default", "standstill_mediacao_cautelar"]
MAX_PAGINAS_RENDER = 8

SISTEMA = (
    "Voce e um rotulador de eventos de credito de companhias abertas brasileiras. Decide exclusivamente pelos "
    "documentos IPE da CVM fornecidos no prompt, do mesmo CNPJ e com Data_Entrega igual ou anterior a do "
    "candidato, aplicando literalmente o guia congelado que o prompt traz. Nao usa conhecimento externo, nao "
    "supoe desfecho posterior, nao busca nada. Todo trecho citado e copia literal do documento indicado, e sera "
    "conferido por comando. Responde somente no esquema JSON pedido."
)

ROTULO_PROPS = {
    "classe": {"type": "string", "enum": CLASSES},
    "tipo": {"type": ["string", "null"], "enum": TIPOS + [None]},
    "data_evento": {"type": ["string", "null"], "description": "AAAA-MM-DD, Data_Entrega do primeiro documento que registra o ato consumado"},
    "protocolo_evento": {"type": ["string", "null"]},
    "trecho_evento": {"type": ["string", "null"], "description": "ate 30 palavras literais do documento do protocolo_evento"},
    "origem": {"type": ["object", "null"], "properties": {
        "protocolo": {"type": "string"}, "data_entrega": {"type": "string"}, "tipo": {"type": "string"},
        "trecho": {"type": "string"}}, "required": ["protocolo", "data_entrega", "tipo", "trecho"], "additionalProperties": False},
    "adicionais": {"type": "array", "items": {"type": "object", "properties": {
        "classe": {"type": "string", "enum": ["evento_proprio", "continuacao"]},
        "data_ou_origem": {"type": "string"}, "protocolo": {"type": "string"}, "trecho": {"type": "string"}},
        "required": ["classe", "data_ou_origem", "protocolo", "trecho"], "additionalProperties": False}},
    "motivo_incerto": {"type": ["string", "null"], "enum": ["inacessivel", "sem_protocolo", "duvida", None]},
    "justificativa": {"type": "string", "description": "ate 60 palavras, sem conhecimento externo ao IPE"},
}
ESQUEMA = {
    "type": "object",
    "properties": {
        "acao": {"type": "string", "enum": ["rotular", "pedir_paginas"]},
        "pedidos": {"type": "array", "items": {"type": "object", "properties": {
            "protocolo": {"type": "string"}, "paginas": {"type": "string", "description": "ex. 1-4"},
            "motivo": {"type": "string"}}, "required": ["protocolo", "paginas", "motivo"], "additionalProperties": False}},
        "rotulo": {"type": ["object", "null"], "properties": ROTULO_PROPS,
                   "required": ["classe", "tipo", "data_evento", "protocolo_evento", "trecho_evento", "origem",
                                "adicionais", "motivo_incerto", "justificativa"], "additionalProperties": False},
    },
    "required": ["acao", "pedidos", "rotulo"], "additionalProperties": False,
}
ESQUEMA_SO_ROTULO = {"type": "object", "properties": ROTULO_PROPS, "required": list(ROTULO_PROPS), "additionalProperties": False}


def guia_v3():
    """Item 2 do bloco G0-v3 congelado (nota 120) + anexo G0-v2 congelado (nota 117). Guarda tem que passar."""
    est = G3.estado()
    if not est["ok"]:
        raise SystemExit("guarda G0-v3 reprovou: %s" % est["motivos"])
    bloco = G2.extrair_bloco(G2.ler(G3.NOTA_120), G3.MARC_V3)
    i = bloco.index("### 2. Rótulo, por candidato")
    j = bloco.index("### 3. Base de eventos")
    anexo = G2.extrair_bloco(G2.ler(G2.NOTA_ANEXO), G2.MARC_ANEXO)
    return bloco[i:j].strip(), anexo.strip(), est


def instrucoes_resposta(rodada, rodadas_restantes):
    txt = ("=== COMO RESPONDER ===\n"
           "Percorra a ordem de decisao da secao B do anexo. Se para decidir classe, data, origem, titularidade ou "
           "continuacao voce precisar do texto de um documento alem do que foi servido (inicio e ancoras), ou de documento "
           "do indice sem texto servido, responda acao=\"pedir_paginas\" listando protocolo, faixa de paginas e motivo. "
           "Peca a integra de todo documento em que o rotulo vai se apoiar. Documento sem texto extraivel pode ser pedido: "
           "ele sera renderizado e transcrito. Quando tiver o suficiente, responda acao=\"rotular\" com o rotulo completo. "
           "Trecho literal: copie exatamente do texto servido, ate 30 palavras, sem reticencias no meio.\n")
    if rodadas_restantes <= 0:
        txt += "Esta e a ULTIMA rodada: nao ha mais pedidos possiveis, responda acao=\"rotular\". Se faltar documento indispensavel, classe incerto com motivo inacessivel.\n"
    else:
        txt += "Rodadas de pedido restantes depois desta resposta: %d (teto de %d caracteres servidos por rodada).\n" % (rodadas_restantes, R.TETO_N2)
    return txt


def montar_prompt(item, man_item, meta, txt_dir, servidos, rodada, guia):
    """So (item, manifesto do item, metadados, textos, paginas ja servidas). Nunca camada, estrato ou sinal."""
    item2, anexo = guia[0], guia[1]
    pac, reg = R.pacote(item, man_item, meta, txt_dir)
    partes = [
        "Voce rotula UM candidato a evento de credito. Use SOMENTE os documentos IPE do mesmo CNPJ fornecidos aqui, "
        "com Data_Entrega igual ou anterior a do candidato. Nao use conhecimento externo e nao suponha o que aconteceu depois.",
        "=== GUIA: ITEM 2 DO PROTOCOLO G0-v3 (congelado) ===\n" + item2,
        "=== GUIA: ANEXO G0-v2 (congelado) ===\n" + anexo,
        pac,
    ]
    if servidos:
        partes.append("=== PAGINAS SERVIDAS NO NIVEL 2 (rodadas anteriores) ===\n" + "\n\n".join(servidos))
    partes.append(instrucoes_resposta(rodada, R.RODADAS - rodada))
    return "\n\n".join(partes), reg


def permitidos(man_item):
    s = set(man_item["dia"]) | set(man_item["contexto_180d"])
    s |= {str(x["protocolo_rad"]) for x in man_item["indice_24m"] if x.get("protocolo_rad")}
    return s


def meta_de(man_item, docs_meta):
    """Metadados dos documentos do item, inclusive os do indice de 24 meses (que o manifesto global pode nao ter)."""
    m = {}
    for p in man_item["dia"] + man_item["contexto_180d"]:
        m[p] = docs_meta[p]
    for x in man_item["indice_24m"]:
        p = str(x.get("protocolo_rad"))
        if p and p not in m:
            m[p] = {"protocolo_rad": p, "data_entrega": x["data"], "categoria": x["categoria"], "assunto": x["assunto"], "link": x.get("link")}
    return m


def baixar_sob_pedido(p, meta_p, docs_dir, prov_path):
    """Mesma integridade do baixar_etapa1; proveniencia propria do nivel 2. Nunca contorna captcha."""
    url = meta_p.get("link")
    if not url:
        return {"protocolo_rad": p, "status": "inacessivel", "motivo": "sem_link"}
    tmp = os.path.join(docs_dir, "DOCS", "%s.part" % p)
    reg = None
    for tent in range(1, 4):
        http, nome, rc = B.baixar(url, tmp)
        b = open(tmp, "rb").read() if os.path.exists(tmp) else b""
        tp = B.tipo_por_magia(b)
        if http == 200 and tp in ("pdf", "doc", "docx"):
            final = os.path.join(docs_dir, "DOCS", "%s.%s" % (p, tp))
            os.replace(tmp, final)
            st = B.extrair_texto(final, tp, os.path.join(docs_dir, "TXT", "%s.txt" % p))
            reg = {"protocolo_rad": p, "url": url, "status": "ok" if st == "ok" else "ok_sem_texto", "texto": st, "tipo": tp,
                   "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest(), "anexo": nome, "http": http, "tentativas": tent}
            break
        reg = {"protocolo_rad": p, "url": url, "status": "inacessivel", "tipo": tp, "bytes": len(b), "http": http, "tentativas": tent}
        if tp == "captcha":
            break
    if os.path.exists(tmp):
        os.remove(tmp)
    reg.update({"origem": "nivel2", "baixado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
    with open(prov_path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(reg, ensure_ascii=False) + "\n")
    return reg


def renderizar_e_transcrever(p, paginas, docs_dir, saida_dir, modelo, registro_path):
    """Documento sem texto extraivel: renderiza as paginas pedidas (PyMuPDF) e pede transcricao literal ao modelo
    com Read restrito ao diretorio. Devolve o texto transcrito (ou None) e grava TXT_RENDER/<p>.txt."""
    pdf = os.path.join(docs_dir, "DOCS", "%s.pdf" % p)
    if not os.path.exists(pdf):
        return None, "nao_renderizavel_nao_pdf"
    try:
        import fitz  # noqa: WPS433
    except Exception:  # noqa: BLE001
        return None, "pymupdf_ausente"
    rdir = os.path.abspath(os.path.join(saida_dir, "render", p))
    os.makedirs(rdir, exist_ok=True)
    doc = fitz.open(pdf)
    m = re.fullmatch(r"(\d+)(?:-(\d+))?", (paginas or "1").strip())
    a, b = (int(m.group(1)), int(m.group(2) or m.group(1))) if m else (1, 1)
    a, b = max(1, a), min(len(doc), b, a + MAX_PAGINAS_RENDER - 1)
    if a > len(doc):
        return None, "pagina_alem_do_fim"
    tdir = os.path.join(docs_dir, "TXT_RENDER")
    alvo = os.path.join(tdir, "%s.txt" % p)
    ja = _ler_paginas_render(alvo)
    faltam = [k for k in range(a, b + 1) if k not in ja]
    if not faltam:
        return open(alvo, encoding="utf-8", errors="ignore").read(), "ok"
    arquivos = []
    for k in faltam:
        f = os.path.join(rdir, "p%03d.png" % k)
        if not os.path.exists(f):
            doc[k - 1].get_pixmap(dpi=130).save(f)
        arquivos.append(f)
    a, b = faltam[0], faltam[-1]
    prompt = ("Transcreva LITERALMENTE, pagina a pagina, o texto das imagens abaixo (documento escaneado da CVM), abrindo cada "
              "arquivo pelo caminho ABSOLUTO indicado com a ferramenta Read. Nao resuma, nao interprete, nao complete palavras "
              "ilegiveis (marque [ilegivel]). Comece cada pagina com uma linha '=== PAGINA n ===' (n = numero da pagina no documento).\n"
              + "\n".join("pagina %d: %s" % (k, f) for k, f in zip(faltam, arquivos)))
    r = L.chamar_claude(prompt, "Voce transcreve documentos escaneados literalmente. Use a ferramenta Read para abrir cada imagem pelo caminho absoluto listado.",
                        None, modelo, ferramentas="Read", add_dir=rdir)
    r.update({"finalidade": "transcricao_renderizada", "protocolo": p, "paginas": [a, b]})
    L.registrar(registro_path, r)
    txt = r.get("result") or ""
    if not r["ok"] or "=== PAGINA" not in txt:
        return None, "transcricao_falhou:%s" % (r.get("classe") or "sem_marcador_de_pagina")
    os.makedirs(tdir, exist_ok=True)
    # transcricao por pagina, acumulada no arquivo (paginas ja transcritas em pedidos anteriores sao preservadas)
    paginas_txt = _ler_paginas_render(alvo)
    for m2 in re.finditer(r"=== PAGINA (\d+) ===\s*(.*?)(?==== PAGINA \d+ ===|\Z)", txt, re.S):
        paginas_txt[int(m2.group(1))] = m2.group(2).strip()
    n_pag = max(len(doc), max(paginas_txt) if paginas_txt else 0)
    texto = "\f".join(paginas_txt.get(k, "[PAGINA %d NAO TRANSCRITA]" % k) for k in range(1, n_pag + 1))
    with open(alvo, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(texto)
    return texto, "ok"


def _ler_paginas_render(alvo):
    out = {}
    if os.path.exists(alvo):
        for k, pg in enumerate(open(alvo, encoding="utf-8", errors="ignore").read().split("\f"), 1):
            if pg.strip() and not pg.startswith("[PAGINA"):
                out[k] = pg.strip()
    return out


def n_paginas_pdf(pdf):
    try:
        import fitz  # noqa: WPS433
        return len(fitz.open(pdf))
    except Exception:  # noqa: BLE001
        return None


def texto_para_verificacao(p, docs_dir):
    """Texto integral do documento: extraido, ou transcricao renderizada quando o extraido nao existe."""
    for sub in ("TXT", "TXT_RENDER"):
        f = os.path.join(docs_dir, sub, "%s.txt" % p)
        if os.path.exists(f):
            t = open(f, encoding="utf-8", errors="ignore").read()
            if len(t.strip()) >= 80:
                return t
    return None


def verificar_rotulo(rot, docs_dir):
    """Confere cada trecho citado contra o texto integral. Devolve lista de falhas (vazia = valido)."""
    falhas = []

    def conf(trecho, p, onde):
        if not trecho or not p:
            falhas.append("%s sem trecho ou sem protocolo" % onde)
            return
        t = texto_para_verificacao(str(p), docs_dir)
        if t is None:
            falhas.append("%s: documento %s sem texto para conferir" % (onde, p))
        elif R.norm_trecho(trecho) not in R.norm_trecho(t):
            falhas.append("%s: trecho nao esta no documento %s" % (onde, p))
    if rot.get("classe") == "evento_proprio":
        conf(rot.get("trecho_evento"), rot.get("protocolo_evento"), "evento")
    if rot.get("classe") == "continuacao":
        o = rot.get("origem") or {}
        conf(o.get("trecho"), o.get("protocolo"), "origem")
    for k, ad in enumerate(rot.get("adicionais") or []):
        conf(ad.get("trecho"), ad.get("protocolo"), "adicional_%d" % k)
    return falhas


def servir_pedidos(pedidos, perm, meta, docs_dir, saida_dir, modelo, registro_path, prov_n2):
    """Nivel 2: paginas de documentos do indice. Baixa sob pedido e renderiza/transcreve o que nao tem texto."""
    txt_dir = os.path.join(docs_dir, "TXT")
    render_log = []
    for ped in pedidos:
        p = str(ped.get("protocolo"))
        if p not in perm:
            continue
        if R.ler_txt(txt_dir, p) is None and p in meta:
            baixar_sob_pedido(p, meta[p], docs_dir, prov_n2)
        t = R.ler_txt(txt_dir, p)
        if t is not None and len(t.strip()) < 80:
            _, st = renderizar_e_transcrever(p, ped.get("paginas"), docs_dir, saida_dir, modelo, registro_path)
            render_log.append({"protocolo": p, "paginas": ped.get("paginas"), "status": st})
    # TXT e o texto extraido e nao e sobrescrito. Transcricao renderizada vive em TXT_RENDER e e servida
    # numa segunda passagem, so para os pedidos que o TXT devolveu como sem_texto.
    texto, log = R.servir_nivel2(pedidos, perm, txt_dir)
    rdir = os.path.join(docs_dir, "TXT_RENDER")
    if os.path.isdir(rdir):
        faltam = [pd for pd, lg in zip(pedidos, log) if lg.get("status") in ("sem_texto",) and os.path.exists(os.path.join(rdir, "%s.txt" % pd.get("protocolo")))]
        if faltam:
            t2, log2 = R.servir_nivel2(faltam, perm, rdir)
            texto = (texto + "\n\n" if texto else "") + "[TRANSCRICOES DE PAGINAS RENDERIZADAS]\n" + t2
            for lg in log2:
                lg["status"] = "servido_transcricao" if lg.get("status") == "servido" else lg.get("status")
            log += log2
    return texto, log, render_log


def rotular(item, man_item, docs_meta, docs_dir, saida_dir, modelo=L.MODELO_PADRAO, provider="claude", dry_run=False, guia=None):
    guia = guia or guia_v3()
    txt_dir = os.path.join(docs_dir, "TXT")
    meta = meta_de(man_item, docs_meta)
    perm = permitidos(man_item)
    registro_path = os.path.join(saida_dir, "chamadas.jsonl")
    prov_n2 = os.path.join(saida_dir, "proveniencia_nivel2.jsonl")
    os.makedirs(saida_dir, exist_ok=True)
    servidos, rodadas, tokens = [], [], {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
    resultado = {"id": item["id"], "modo": "progressiva", "versao_executor": VERSAO_EXECUTOR, "protocolo_guia": "G0-v3", "sha256_bloco_v3": guia[2]["sha256_v3"],
                 "sha256_recuperar": guia[2]["sha256_recuperar"], "modelo": modelo, "provider": provider,
                 "inicio_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    for rodada in range(R.RODADAS + 1):
        prompt, reg_pac = montar_prompt(item, man_item, meta, txt_dir, servidos, rodada, guia)
        if dry_run:
            resultado.update({"dry_run": True, "chars_prompt": len(prompt), "sha256_prompt": L.sha256_texto(prompt), "pacote": reg_pac})
            if provider == "codex":
                resultado["codex_argv"] = L.chamar_codex(prompt, SISTEMA, ESQUEMA, executar=False)["argv"]
            return resultado
        esquema = ESQUEMA if rodada < R.RODADAS else ESQUEMA_SO_ROTULO
        r = L.chamar(prompt, SISTEMA, esquema, provider=provider, modelo=modelo, executar=True) if provider == "codex" \
            else L.chamar(prompt, SISTEMA, esquema, provider=provider, modelo=modelo)
        r.update({"finalidade": "rotulo_progressiva", "id": item["id"], "rodada": rodada, "pacote": reg_pac})
        L.registrar(registro_path, r)
        for k in tokens:
            tokens[k] += r["usage"].get(k, 0)
        if not r["ok"]:
            if r.get("classe") in ("limite", "auth"):
                raise L.LimiteDeCota("%s: %s" % (r.get("classe"), r.get("erro")))
            resultado.update({"status": "erro_chamada", "erro": r.get("erro"), "classe_falha": r.get("classe"), "rodadas": rodadas, "tokens": tokens})
            return resultado
        s = r["structured"] or {}
        if rodada < R.RODADAS and s.get("acao") == "pedir_paginas" and s.get("pedidos"):
            texto, log, rlog = servir_pedidos(s["pedidos"], perm, meta, docs_dir, saida_dir, modelo, registro_path, prov_n2)
            rodadas.append({"rodada": rodada, "pedidos": s["pedidos"], "servido": log, "render": rlog,
                            "sha256_servido": L.sha256_texto(texto), "chars_servido": len(texto)})
            servidos.append("--- rodada %d ---\n%s" % (rodada + 1, texto or "(nada servido)"))
            continue
        rot = s.get("rotulo") if rodada < R.RODADAS else s
        if not rot:
            rot = {"classe": "incerto", "motivo_incerto": "duvida", "justificativa": "resposta sem rotulo", "adicionais": [],
                   "tipo": None, "data_evento": None, "protocolo_evento": None, "trecho_evento": None, "origem": None}
        falhas = verificar_rotulo(rot, docs_dir)
        resultado.update({"status": "adjudicacao" if falhas else "rotulado", "rotulo": rot, "falhas_trecho": falhas,
                          "rodadas": rodadas, "n_rodadas_pedido": len(rodadas), "tokens": tokens,
                          "fim_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
        return resultado
    resultado.update({"status": "erro_interno", "rodadas": rodadas, "tokens": tokens})
    return resultado


def carregar(etapa):
    itens = {x["id"]: x for x in json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))}
    man = {m["id"]: m for m in json.load(open(os.path.join(etapa, "manifesto_itens.json"), encoding="utf-8"))}
    meta = {d["protocolo_rad"]: d for d in json.load(open(os.path.join(etapa, "manifesto_documentos.json"), encoding="utf-8"))}
    return itens, man, meta


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 4:
        print(__doc__)
        return 2
    etapa, docs_dir, saida, iid = argv[:4]

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    itens, man, meta = carregar(etapa)
    r = rotular(itens[iid], man[iid], meta, docs_dir, saida, modelo=opt("--modelo", L.MODELO_PADRAO),
                provider=opt("--provider", "claude"), dry_run="--dry-run" in argv)
    print(json.dumps(r, ensure_ascii=False, indent=1, default=str))
    return 0 if r.get("status") in ("rotulado", "adjudicacao") or r.get("dry_run") else 1


if __name__ == "__main__":
    sys.exit(main())
