"""Leitura integral fatiada de UM item, braco de comparacao do G1-eq (nota 120, item 4). Executor v0.2.

Todo documento do dia e dos 180 dias e lido por inteiro, em fatias de ate TETO_FATIA caracteres (60.000,
o mesmo teto do nivel 2). Cada fatia vai ao modelo com uma instrucao de extracao: listar, literalmente,
todo fato relevante para credito (ato, titular, instrumento, processo, data, trecho), sem classificar.
Os fatos de todas as fatias sao levados a UMA decisao final com o mesmo guia congelado (item 2 do bloco
G0-v3 + anexo), o indice integral e a ficha do candidato. O rotulo final tem o mesmo esquema do braco
progressivo e passa pela mesma conferencia de trecho contra o texto integral.

v0.2 (16/10/2026, depois dos itens i0001-i0004 do G1-eq):
  - documento do dia ou dos 180 dias SEM texto extraivel (escaneado) e renderizado por pagina e transcrito
    (mesma rotina do braco progressivo), e a transcricao vira fatia; Word antigo sem texto fica declarado;
  - a decisao final pode pedir paginas de qualquer documento do INDICE (inclusive 24 meses, baixado sob pedido),
    em ate RODADAS rodadas, porque o item 2 do guia (v2 e v3) da ao rotulador o direito de abrir documento do
    indice. Sem isso o braco integral ficava sem trecho literal para origem anterior a 180 dias (i0004) e caia
    em `incerto` por limitacao do executor, nao da leitura;
  - cache por fatia em SAIDA_DIR/integral/_cache/<id>/fatia<k>.json: reexecucao nao refaz fatia ja extraida.
A unica diferenca que resta entre os bracos e a que o G1-eq mede: ler o dia e os 180 dias por inteiro contra
ler inicio e ancoras e pedir o resto.

Determinismo: as fatias sao funcao so dos textos (ordem do manifesto: dia, depois 180 dias por data e protocolo),
e cada fatia, cada resposta, cada pedido servido e a decisao final sao registrados com sha256.

Uso: python -I leitura_integral_g0v3.py ETAPA_DIR DOCS_DIR SAIDA_DIR ID [--modelo M] [--dry-run]
"""
import datetime as dt
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import llm_cli as L  # noqa: E402
import recuperar_g0v3 as R  # noqa: E402
import rotular_g0v3 as RO  # noqa: E402

VERSAO_EXECUTOR = "integral-v0.2"
TETO_FATIA = R.TETO_N2  # 60.000
MAX_PAGINAS_RENDER_DOC = 40

SISTEMA_FATIA = (
    "Voce le documentos IPE da CVM de uma companhia aberta e extrai, literalmente e sem interpretar, todo fato "
    "relevante para credito. Nao classifica, nao decide, nao usa conhecimento externo. Responde somente no esquema JSON pedido."
)
ESQUEMA_FATIA = {
    "type": "object",
    "properties": {"fatos": {"type": "array", "items": {"type": "object", "properties": {
        "protocolo": {"type": "string"}, "data_entrega": {"type": "string"},
        "tipo_fato": {"type": "string", "description": "ex. pedido de RJ, deferimento, RE, falencia, vencimento antecipado, default, nao pagamento, prazo de cura, standstill, mediacao, cautelar, waiver, AGD, repactuacao, quitacao, encerramento, incorporacao/sucessao, titularidade (controlada/subsidiaria/requerente), outro"},
        "titular": {"type": "string", "description": "quem pratica ou sofre o ato: a propria companhia, controlada, controladora, terceiro"},
        "instrumento_ou_processo": {"type": "string", "description": "numero do processo, serie de debentures, contrato, plano; ou vazio"},
        "trecho": {"type": "string", "description": "ate 40 palavras literais do documento"},
        "observacao": {"type": "string"}},
        "required": ["protocolo", "data_entrega", "tipo_fato", "titular", "instrumento_ou_processo", "trecho", "observacao"],
        "additionalProperties": False}},
                   "sem_fato_de_credito": {"type": "boolean"}},
    "required": ["fatos", "sem_fato_de_credito"], "additionalProperties": False,
}

INSTRUCAO_FATIA = (
    "Abaixo esta UMA fatia do conjunto de documentos IPE do CNPJ {cnpj} com Data_Entrega ate {data} (candidato em {data}). "
    "Liste TODO fato relevante para credito que apareca nesta fatia: pedido, deferimento, homologacao ou encerramento de "
    "recuperacao judicial ou extrajudicial; falencia ou pedido de falencia (por quem); vencimento antecipado, inadimplemento, "
    "nao pagamento, prazo de cura, default; standstill, mediacao, cautelar, waiver, AGD, repactuacao, renegociacao; quitacao, "
    "pagamento; incorporacao, cisao, sucessao; e toda indicacao de titularidade (quem e requerente, controlada, controladora). "
    "Para cada fato: protocolo e Data_Entrega do documento (estao no cabecalho [protocolo ... | Data_Entrega ...]), tipo, "
    "titular, instrumento ou processo, trecho literal de ate 40 palavras copiado exatamente, observacao curta. Fato de "
    "dividendo, JCP, tributo isolado ou governanca sem credito NAO entra. Se a fatia nao tem fato de credito, "
    "sem_fato_de_credito=true e fatos=[]."
)


def documentos_ordenados(man_item, meta, txt_dir):
    """(protocolo, grupo, texto ou None) na ordem: dia por protocolo, depois 180 dias por (data, protocolo)."""
    out = []
    for p in sorted(man_item["dia"], key=str):
        out.append((p, "dia", R.ler_txt(txt_dir, p)))
    ctx = sorted(man_item["contexto_180d"], key=lambda q: (meta[q]["data_entrega"], str(q)))
    for p in ctx:
        out.append((p, "180d", R.ler_txt(txt_dir, p)))
    return out


def cabecalho(p, meta):
    m = meta[p]
    return "[protocolo %s | Data_Entrega %s | %s | assunto: %s]" % (p, m["data_entrega"], m["categoria"], m["assunto"] or "(vazio)")


def _partir(cab, grupo, txt, teto):
    corpo = R.limpa(txt)
    if len(cab) + len(corpo) + 2 <= teto:
        return [cab + " | %s\n" % grupo + corpo]
    pedacos, atual = [], ""
    for pg in R.paginas(txt):
        pg = R.limpa(pg)
        if not pg:
            continue
        while len(pg) > teto - 200:
            pedacos.append(pg[:teto - 200])
            pg = pg[teto - 200:]
        if atual and len(atual) + len(pg) + 1 > teto - 200:
            pedacos.append(atual)
            atual = ""
        atual = (atual + "\n\f" + pg) if atual else pg
    if atual:
        pedacos.append(atual)
    n = len(pedacos)
    return [cab[:-1] + " | parte %d/%d]" % (k, n) + " | %s\n" % grupo + ped for k, ped in enumerate(pedacos, 1)]


def fatias(man_item, meta, txt_dir, teto=TETO_FATIA, transcritos=None):
    """Lista de fatias (texto). Nenhum caractere de documento com texto fica de fora; documento maior que o teto
    e partido por pagina (e por corte duro se uma pagina sozinha passa do teto), com 'parte k/n' no cabecalho.
    transcritos: {protocolo: texto} de documentos escaneados ja transcritos (entram como texto, marcados)."""
    blocos, sem_texto = [], []
    transcritos = transcritos or {}
    for p, grupo, txt in documentos_ordenados(man_item, meta, txt_dir):
        cab = cabecalho(p, meta)
        if (txt is None or len(txt.strip()) < 80) and p in transcritos:
            blocos += _partir(cab[:-1] + " | TRANSCRICAO DE PAGINAS RENDERIZADAS]", grupo, transcritos[p], teto)
            continue
        if txt is None or len(txt.strip()) < 80:
            sem_texto.append("%s | %s | %s" % (cab, grupo, "NAO BAIXADO" if txt is None else "SEM TEXTO EXTRAIVEL"))
            continue
        blocos += _partir(cab, grupo, txt, teto)
    out, atual = [], ""
    for b in blocos:
        if atual and len(atual) + len(b) + 2 > teto:
            out.append(atual)
            atual = ""
        atual = (atual + "\n\n" + b) if atual else b
    if atual:
        out.append(atual)
    return out, sem_texto


def transcrever_sem_texto(man_item, meta, docs_dir, saida_dir, modelo, registro_path, provider="claude"):
    """Renderiza e transcreve todo PDF do dia/180d sem texto extraivel (ate MAX_PAGINAS_RENDER_DOC paginas, declarado)."""
    txt_dir = os.path.join(docs_dir, "TXT")
    out, log = {}, []
    for p, grupo, txt in documentos_ordenados(man_item, meta, txt_dir):
        if txt is None or len(txt.strip()) >= 80:
            continue
        pdf = os.path.join(docs_dir, "DOCS", "%s.pdf" % p)
        if not os.path.exists(pdf):
            log.append({"protocolo": p, "status": "nao_renderizavel_nao_pdf"})
            continue
        n = RO.n_paginas_pdf(pdf) or 0
        ja = RO.texto_para_verificacao(p, docs_dir)
        if ja and "[PAGINA" not in ja:
            out[p] = ja
            log.append({"protocolo": p, "status": "ja_transcrito"})
            continue
        teto_pag = min(n, MAX_PAGINAS_RENDER_DOC)
        a = 1
        while a <= teto_pag:
            b = min(teto_pag, a + RO.MAX_PAGINAS_RENDER - 1)
            texto, st = RO.renderizar_e_transcrever(p, "%d-%d" % (a, b), docs_dir, saida_dir, modelo, registro_path, provider=provider)
            log.append({"protocolo": p, "paginas": [a, b], "status": st})
            if texto is None:
                break
            out[p] = texto
            a = b + 1
        if n > MAX_PAGINAS_RENDER_DOC:
            log.append({"protocolo": p, "status": "cortado_em_%d_de_%d_paginas" % (MAX_PAGINAS_RENDER_DOC, n)})
    return out, log


def indice_integral(item, man_item, meta, txt_dir, transcritos):
    idx = []
    for grupo, lista in (("dia", man_item["dia"]), ("180d", man_item["contexto_180d"])):
        for p in lista:
            t = R.ler_txt(txt_dir, p)
            est = "lido integralmente"
            if t is None:
                est = "nao baixado"
            elif len(t.strip()) < 80:
                est = "transcrito de paginas renderizadas" if p in transcritos else "sem texto"
            idx.append("%s | %s | %s | %s | protocolo %s | %s" % (grupo, meta[p]["data_entrega"], meta[p]["categoria"], meta[p]["assunto"] or "(vazio)", p, est))
    for x in man_item["indice_24m"]:
        idx.append("24m | %s | %s | %s | protocolo %s | so metadado (paginas sob pedido)" % (x["data"], x["categoria"], x["assunto"] or "(vazio)", x["protocolo_rad"]))
    return "=== CANDIDATO ===\nCNPJ %s | Data_Entrega do candidato %s\n\n=== INDICE INTEGRAL (%d documentos) ===\n%s" % (
        item["cnpj"], item["data"], len(idx), "\n".join(idx))


def prompt_final(item, man_item, meta, txt_dir, fatos, sem_texto, guia, transcritos, servidos, rodada):
    item2, anexo = guia[0], guia[1]
    partes = [
        "Voce rotula UM candidato a evento de credito. Todos os documentos IPE do dia e dos 180 dias anteriores do mesmo CNPJ "
        "foram lidos por inteiro, em fatias, e os fatos de credito extraidos de cada fatia estao listados abaixo, com protocolo, "
        "Data_Entrega e trecho literal. Decida por esses fatos, pelo indice e pelas paginas que pedir. Nao use conhecimento externo e nao suponha o que aconteceu depois.",
        "=== GUIA: ITEM 2 DO PROTOCOLO G0-v3 (congelado) ===\n" + item2,
        "=== GUIA: ANEXO G0-v2 (congelado) ===\n" + anexo,
        indice_integral(item, man_item, meta, txt_dir, transcritos),
        "=== DOCUMENTOS SEM TEXTO (declarados; se o rotulo depender deles, classe incerto, motivo inacessivel) ===\n" + ("\n".join(sem_texto) or "(nenhum)"),
        "=== FATOS DE CREDITO EXTRAIDOS DAS FATIAS (%d) ===\n%s" % (len(fatos), json.dumps(fatos, ensure_ascii=False, indent=0)),
    ]
    if servidos:
        partes.append("=== PAGINAS SERVIDAS SOB PEDIDO (rodadas anteriores) ===\n" + "\n\n".join(servidos))
    partes.append("=== COMO RESPONDER ===\nPercorra a ordem de decisao da secao B do anexo. Se para decidir classe, data, origem, "
                  "titularidade ou continuacao precisar do texto de um documento do indice (inclusive dos 24 meses, so metadado), "
                  "responda acao=\"pedir_paginas\" com protocolo, faixa de paginas e motivo. Quando tiver o suficiente, responda "
                  "acao=\"rotular\". Trecho literal: copie exatamente de um fato listado ou de pagina servida (ate 30 palavras), do "
                  "documento cujo protocolo voce cita.\n"
                  + ("Esta e a ULTIMA rodada: responda acao=\"rotular\". Se faltar documento indispensavel, classe incerto com motivo inacessivel.\n"
                     if R.RODADAS - rodada <= 0 else "Rodadas de pedido restantes depois desta resposta: %d.\n" % (R.RODADAS - rodada)))
    return "\n\n".join(partes)


def _cache_dir(saida_dir, iid):
    d = os.path.join(saida_dir, "integral", "_cache", iid)
    os.makedirs(d, exist_ok=True)
    return d


def rotular_integral(item, man_item, docs_meta, docs_dir, saida_dir, modelo=L.MODELO_PADRAO, dry_run=False, guia=None, provider="claude"):
    guia = guia or RO.guia_v3()
    txt_dir = os.path.join(docs_dir, "TXT")
    meta = RO.meta_de(man_item, docs_meta)
    perm = RO.permitidos(man_item)
    registro_path = os.path.join(saida_dir, "chamadas.jsonl")
    prov_n2 = os.path.join(saida_dir, "proveniencia_nivel2.jsonl")
    os.makedirs(saida_dir, exist_ok=True)
    tokens = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0, "custo_usd": 0.0, "sem_usage_input": 0, "sem_usage_output": 0}
    resultado = {"id": item["id"], "modo": "integral_fatiada", "versao_executor": VERSAO_EXECUTOR, "protocolo_guia": "G0-v3",
                 "sha256_bloco_v3": guia[2]["sha256_v3"], "modelo": modelo, "provider": provider,
                 "inicio_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    transcritos, log_render = ({}, []) if dry_run else transcrever_sem_texto(man_item, meta, docs_dir, saida_dir, modelo, registro_path, provider=provider)
    fts, sem_texto = fatias(man_item, meta, txt_dir, transcritos=transcritos)
    resultado.update({"n_fatias": len(fts), "chars_fatias": sum(len(f) for f in fts), "docs_sem_texto": len(sem_texto),
                      "transcritos": sorted(transcritos), "log_render": log_render, "sha256_fatias": [L.sha256_texto(f) for f in fts]})
    if dry_run:
        resultado["dry_run"] = True
        return resultado
    cache = _cache_dir(saida_dir, item["id"])
    fatos = []
    for k, f in enumerate(fts, 1):
        cf = os.path.join(cache, "fatia%03d.json" % k)
        h = L.sha256_texto(f)
        if os.path.exists(cf):
            try:
                c = json.load(open(cf, encoding="utf-8"))
            except (ValueError, OSError):  # cache truncado por interrupcao: conta como ausente e e refeito
                c = {}
            # cache so vale para o MESMO modelo (cache antigo sem campo = padrao Claude): leitor novo nunca herda fatos de outro
            if c.get("sha256_fatia") == h and c.get("modelo", L.MODELO_PADRAO) == modelo:
                fatos += c["fatos"]
                for kk in tokens:
                    tokens[kk] += 0  # tokens da fatia ja contados na execucao anterior (registro em chamadas.jsonl)
                continue
        prompt = INSTRUCAO_FATIA.format(cnpj=item["cnpj"], data=item["data"]) + "\n\n=== FATIA %d/%d ===\n" % (k, len(fts)) + f
        r = L.chamar(prompt, SISTEMA_FATIA, ESQUEMA_FATIA, provider=provider, modelo=modelo)
        r.update({"finalidade": "fatia_integral", "id": item["id"], "fatia": k, "de": len(fts), "sha256_fatia": h})
        L.registrar(registro_path, r)
        for kk in tokens:
            tokens[kk] += r["usage"].get(kk, 0)
        if not r["ok"]:
            if r.get("classe") in ("limite", "auth"):
                raise L.LimiteDeCota("%s: %s" % (r.get("classe"), r.get("erro")))
            resultado.update({"status": "erro_chamada", "fatia": k, "erro": r.get("erro"), "classe_falha": r.get("classe"), "tokens": tokens})
            return resultado
        novos = []
        for ft in (r["structured"] or {}).get("fatos") or []:
            ft["fatia"] = k
            novos.append(ft)
        tmp = cf + ".tmp"  # gravacao atomica: interrupcao no meio nunca deixa cache truncado no lugar do valido
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            json.dump({"sha256_fatia": h, "modelo": modelo, "provider": provider, "fatos": novos, "tokens": r["usage"]}, fh, ensure_ascii=False)
        os.replace(tmp, cf)
        fatos += novos
    servidos, rodadas = [], []
    for rodada in range(R.RODADAS + 1):
        prompt = prompt_final(item, man_item, meta, txt_dir, fatos, sem_texto, guia, transcritos, servidos, rodada)
        esquema = RO.ESQUEMA if rodada < R.RODADAS else RO.ESQUEMA_SO_ROTULO
        r = L.chamar(prompt, RO.SISTEMA, esquema, provider=provider, modelo=modelo)
        r.update({"finalidade": "rotulo_integral", "id": item["id"], "rodada": rodada, "n_fatos": len(fatos)})
        L.registrar(registro_path, r)
        for kk in tokens:
            tokens[kk] += r["usage"].get(kk, 0)
        if not r["ok"]:
            if r.get("classe") in ("limite", "auth"):
                raise L.LimiteDeCota("%s: %s" % (r.get("classe"), r.get("erro")))
            resultado.update({"status": "erro_chamada", "erro": r.get("erro"), "classe_falha": r.get("classe"), "tokens": tokens})
            return resultado
        s = r["structured"] or {}
        if rodada < R.RODADAS and s.get("acao") == "pedir_paginas" and s.get("pedidos"):
            texto, log, rlog = RO.servir_pedidos(s["pedidos"], perm, meta, docs_dir, saida_dir, modelo, registro_path, prov_n2, provider=provider)
            rodadas.append({"rodada": rodada, "pedidos": s["pedidos"], "servido": log, "render": rlog,
                            "sha256_servido": L.sha256_texto(texto), "chars_servido": len(texto)})
            servidos.append("--- rodada %d ---\n%s" % (rodada + 1, texto or "(nada servido)"))
            continue
        rot = s.get("rotulo") if rodada < R.RODADAS else s
        if not rot:
            rot = {"classe": "incerto", "motivo_incerto": "duvida", "justificativa": "resposta sem rotulo", "adicionais": [],
                   "tipo": None, "data_evento": None, "protocolo_evento": None, "trecho_evento": None, "origem": None}
        falhas = RO.verificar_rotulo(rot, docs_dir)
        resultado.update({"status": "adjudicacao" if falhas else "rotulado", "rotulo": rot, "falhas_trecho": falhas, "n_fatos": len(fatos),
                          "fatos": fatos, "rodadas": rodadas, "n_rodadas_pedido": len(rodadas), "tokens": tokens,
                          "fim_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
        return resultado
    resultado.update({"status": "erro_interno", "tokens": tokens})
    return resultado


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 4:
        print(__doc__)
        return 2
    etapa, docs_dir, saida, iid = argv[:4]

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    itens, man, meta = RO.carregar(etapa)
    r = rotular_integral(itens[iid], man[iid], meta, docs_dir, saida, modelo=opt("--modelo", L.MODELO_PADRAO), dry_run="--dry-run" in argv)
    print(json.dumps(r, ensure_ascii=False, indent=1, default=str))
    return 0 if r.get("status") in ("rotulado", "adjudicacao") or r.get("dry_run") else 1


if __name__ == "__main__":
    sys.exit(main())
