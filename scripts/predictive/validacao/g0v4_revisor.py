"""G0-v4: revisor independente por lote (Codex, fornecedor distinto do autor das regras), nota 124 item 4.

Cego a classe do G0-v4: o prompt traz so metadado do dia e trechos de evidencia (selecionados pelas regras locais, ou pelas
ancoras da G0-v3 quando o item nao tem disparo). Nao traz classe, caminho, motivo de revisao, camada nem rotulo legado.
Limitacao declarada: a selecao de trechos e do extrator, entao o revisor nao audita o que o extrator nao mostrou; por isso
o item sem disparo recebe cabecalho e ancoras independentes (recuperar_g0v3), e a amostra cega mede esse ponto.

Guia: item 2 do bloco G0-v3 congelado + secoes A a D do anexo G0-v2 (sem a tabela de casos). Guarda G0-v3 tem que passar.
Execucao real exige: --executar, modelo do Codex fixado (VIXRADAR_ROTULADOR_CODEX_MODELO), janela livre 00h30-08h30 BRT sem
rotina VIXRadar rodando (llm_cli.chamar_codex). Sem --executar e dry-run (nenhum dado sai da maquina).

Saida so-acrescenta: data/validacao/g0v4/revisoes_codex.jsonl (um objeto por item), chamadas em revisoes_codex_chamadas.jsonl.
Uso:
  python -I g0v4_revisor.py rodar [--alvo fila|amostra|todos] [--lote 6] [--max-lotes N] [--executar]
  python -I g0v4_revisor.py aplicar     # copia decisoes para fila_revisao.csv e amostra_cega.csv (revisor = codex:<modelo>)
"""
import csv
import datetime as dt
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_portoes as PT  # noqa: E402
import g0v4_processar as PR  # noqa: E402
import g0v4_regras as RG  # noqa: E402
import llm_cli as L  # noqa: E402
import recuperar_g0v3 as R  # noqa: E402
import rotular_g0v3 as RO  # noqa: E402

CLASSES = ["evento_proprio", "evento_terceiro", "continuacao", "nao_evento", "incerto"]
CTX_ENTORNO = 700
CAB_SEM_DISPARO, ANC_SEM_DISPARO = 2500, 6000
MAX_TRECHOS = 5
SISTEMA = ("Voce e um revisor independente de eventos de credito de companhias abertas brasileiras. Decide cada item exclusivamente "
           "pelos trechos de documentos IPE da CVM fornecidos, do mesmo CNPJ, aplicando literalmente o guia. Nao usa conhecimento "
           "externo e nao supoe desfecho posterior. Quando o trecho nao basta para decidir, responde incerto e diz o que falta. "
           "Todo trecho citado e copia literal do que foi fornecido, ate 30 palavras. Responde somente no esquema JSON pedido.")
ESQUEMA = {"type": "object", "properties": {"itens": {"type": "array", "items": {"type": "object", "properties": {
    "id": {"type": "string"}, "classe": {"type": "string", "enum": CLASSES},
    "tipo": {"type": ["string", "null"]}, "data_evento": {"type": ["string", "null"]},
    "protocolo": {"type": ["string", "null"]}, "trecho": {"type": ["string", "null"]},
    "origem_protocolo": {"type": ["string", "null"]}, "origem_data": {"type": ["string", "null"]},
    "confianca": {"type": "string", "enum": ["alta", "media", "baixa"]}, "justificativa": {"type": "string"}},
    "required": ["id", "classe", "confianca", "justificativa"]}}}, "required": ["itens"]}


def guia():
    item2, anexo, est = RO.guia_v3()
    cut = anexo.find("### E.")
    return item2, (anexo[:cut] if cut > 0 else anexo), est


def contexto(txt, a, b):
    ini, fim = max(0, a - CTX_ENTORNO), min(len(txt), b + CTX_ENTORNO)
    return RG.re.sub(r"\s+", " ", txt[ini:fim]).strip()


def bloco_item(it, man_item, meta, reg, textos):
    """Evidencia do item sem classe nem caminho do G0-v4."""
    linhas = ["### ITEM %s | CNPJ %s | Data_Entrega do candidato %s" % (it["id"], it["cnpj"], it["data"])]
    for p in man_item["dia"]:
        m = meta.get(p, {})
        linhas.append("documento do dia: protocolo %s | %s | assunto: %s" % (p, m.get("categoria"), m.get("assunto") or "(vazio)"))
    usados, n = set(), 0
    for h in reg["disparos"]:
        if n >= MAX_TRECHOS:
            break
        if h["grupo"] != "dia" or (h["protocolo"], h["pos"][0] // 600) in usados:
            continue
        usados.add((h["protocolo"], h["pos"][0] // 600))
        t = textos(h["protocolo"])
        if t:
            linhas.append("[trecho do dia, protocolo %s]\n%s" % (h["protocolo"], contexto(t, h["pos"][0], h["pos"][1])))
            n += 1
    o = reg.get("origem") or {}
    if o.get("trecho"):
        linhas.append("[trecho de documento anterior, protocolo %s, Data_Entrega %s]\n%s" % (o["protocolo"], o["data_entrega"], o["trecho"]))
    for h in reg.get("disparos_contexto", [])[:2]:
        if not o.get("trecho"):
            linhas.append("[trecho de documento anterior, protocolo %s, Data_Entrega %s]\n%s" % (h["protocolo"], h.get("data_entrega"), h["trecho"]))
    if n == 0:
        for p in man_item["dia"][:3]:
            t = textos(p)
            if t and len(t.strip()) >= RG.MIN_TEXTO:
                corpo = R.limpa(t)
                anc = R.ancoras(corpo[CAB_SEM_DISPARO:], ANC_SEM_DISPARO)
                linhas.append("[inicio do documento %s]\n%s\n[ancoras do restante]\n%s" % (p, corpo[:CAB_SEM_DISPARO], "\n".join(anc) or "(nenhuma)"))
            else:
                linhas.append("[documento %s sem texto extraivel]" % p)
    return "\n".join(linhas)


def montar_prompt(g, blocos):
    return ("=== GUIA: ITEM 2 DO PROTOCOLO G0-v3 (congelado) ===\n" + g[0] + "\n\n=== GUIA: ANEXO G0-v2, SECOES A A D (congelado) ===\n" + g[1]
            + "\n\n=== ITENS A DECIDIR (independentes entre si; um rotulo por item) ===\n" + "\n\n".join(blocos)
            + "\n\nResponda {\"itens\": [...]} com um objeto por item. classe pela ordem de decisao da secao B. data_evento e a Data_Entrega do primeiro "
              "documento que registra o ato consumado (use a do candidato se o trecho for dele). Se for continuacao informe origem_protocolo e origem_data. "
              "Trecho: copia literal do fornecido, ate 30 palavras. Evidencia insuficiente: incerto.")


def feitos(arq):
    out = set()
    if os.path.exists(arq):
        for ln in open(arq, encoding="utf-8"):
            try:
                out.add(json.loads(ln)["id"])
            except (ValueError, KeyError):
                pass
    return out


def alvo_ids(saida, alvo):
    regs = PT.regs_oficiais(saida)
    ids = []
    if alvo == "reduzido":
        red = PT.alvo_reduzido(saida)
        if red is None:
            raise SystemExit("sem adendo_reduzido_g0v4.json: rode g0v4_portoes.py adendo")
        return red, regs
    if alvo in ("fila", "todos"):
        ids += sorted(i for i, r in regs.items() if r["revisao_obrigatoria"])
    if alvo in ("amostra", "todos"):
        p = os.path.join(saida, "amostra_cega.csv")
        if os.path.exists(p):
            with open(p, encoding="utf-8-sig", newline="") as fh:
                ids += [r["id"] for r in csv.DictReader(fh, delimiter=";")]
    seen, out = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out, regs


def rodar(alvo="todos", lote=6, max_lotes=None, executar=False, saida=PR.SAIDA, docs=PR.DOCS, shard=None):
    ids, regs = alvo_ids(saida, alvo)
    arq = os.path.join(saida, "revisoes_codex.jsonl")
    cham = os.path.join(saida, "revisoes_codex_chamadas.jsonl")
    ja = feitos(arq)
    for f in os.listdir(saida):  # saidas de processos paralelos ainda nao unidas
        if f.startswith("revisoes_codex.shard") and f.endswith(".jsonl"):
            ja |= feitos(os.path.join(saida, f))
    pend = [i for i in ids if i not in ja]
    if shard:
        k, n = shard
        pend = [i for pos, i in enumerate(pend) if pos % n == k]
        arq = os.path.join(saida, "revisoes_codex.shard%d.jsonl" % k)
        cham = os.path.join(saida, "revisoes_codex_chamadas.shard%d.jsonl" % k)
    itens, man, meta, _ = PR.carregar()
    por_id = {x["id"]: x for x in itens}
    g = guia()
    modelo = L.modelo_codex()
    textos = PR.Textos(docs)
    n_lotes, tokens = 0, 0
    print(json.dumps({"alvo": alvo, "total": len(ids), "pendentes": len(pend), "lote": lote, "executar": executar, "modelo": modelo}))
    for k in range(0, len(pend), lote):
        if max_lotes and n_lotes >= max_lotes:
            break
        grupo = pend[k:k + lote]
        blocos = [bloco_item(por_id[i], man[i], meta, regs[i], textos) for i in grupo]
        prompt = montar_prompt(g, blocos)
        r = L.chamar_codex(prompt, SISTEMA, ESQUEMA, modelo=modelo, executar=executar)
        if not executar:
            print(json.dumps({"dry_run": True, "ids": grupo, "chars_prompt": r["chars_prompt"], "sha256_prompt": r["sha256_prompt"]}))
            n_lotes += 1
            continue
        with open(cham, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps({k2: v for k2, v in r.items() if k2 not in ("result", "structured")}, ensure_ascii=False, default=str) + "\n")
        s = r.get("structured") or {}
        dec = {d.get("id"): d for d in s.get("itens", []) if isinstance(d, dict)}
        if not r.get("ok") or not dec:
            print(json.dumps({"lote_falhou": grupo, "classe": r.get("classe"), "erro": str(r.get("erro"))[:200]}))
            n_lotes += 1
            continue
        with open(arq, "a", encoding="utf-8", newline="\n") as fh:
            for i in grupo:
                d = dec.get(i)
                if not d:
                    continue
                tr = d.get("trecho")
                ok_tr = None
                if tr:
                    prot = d.get("protocolo") or ""
                    ok_tr = any(RG.confere(tr, textos(p)) for p in ([prot] if prot else []) + list(man[i]["dia"]) + [d.get("origem_protocolo") or ""]
                                if p)
                d.update({"revisor": "codex:%s" % modelo, "trecho_confere": ok_tr, "revisado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
                fh.write(json.dumps(d, ensure_ascii=False) + "\n")
        n_lotes += 1
        tokens += L.total_tokens(r.get("usage", {})) if hasattr(L, "total_tokens") and r.get("usage") else 0
        print(json.dumps({"lote": n_lotes, "itens": len(grupo), "acumulado_tokens": tokens}), flush=True)
    return 0


def unir(saida=PR.SAIDA):
    """Junta as saidas dos processos paralelos em revisoes_codex.jsonl (so-acrescenta, sem duplicar id)."""
    arq = os.path.join(saida, "revisoes_codex.jsonl")
    ja = feitos(arq)
    n = 0
    for f in sorted(os.listdir(saida)):
        if f.startswith("revisoes_codex.shard") and f.endswith(".jsonl"):
            p = os.path.join(saida, f)
            with open(arq, "a", encoding="utf-8", newline="\n") as out:
                for ln in open(p, encoding="utf-8"):
                    try:
                        d = json.loads(ln)
                    except ValueError:
                        continue
                    if d["id"] not in ja:
                        out.write(json.dumps(d, ensure_ascii=False) + "\n")
                        ja.add(d["id"])
                        n += 1
            os.replace(p, p + ".unido")
    print(json.dumps({"unidos": n}))
    return 0


def aplicar(saida=PR.SAIDA):
    dec = {}
    p = os.path.join(saida, "revisoes_codex.jsonl")
    for ln in open(p, encoding="utf-8"):
        d = json.loads(ln)
        dec[d["id"]] = d
    resumo = {}
    for nome in ("fila_revisao.csv", "amostra_cega.csv"):
        f = os.path.join(saida, nome)
        with open(f, encoding="utf-8-sig", newline="") as fh:
            rd = csv.DictReader(fh, delimiter=";")
            cols, rows = rd.fieldnames, list(rd)
        n = 0
        for r in rows:
            d = dec.get(r["id"])
            if d and not r.get("classe_final"):
                r["classe_final"], r["data_evento_final"] = d["classe"], d.get("data_evento") or ""
                r["revisor"], r["revisado_em"] = d["revisor"], d["revisado_em"]
                if "decisao_revisor" in r:
                    r["decisao_revisor"] = d["justificativa"][:300]
                if nome == "amostra_cega.csv":
                    r["protocolo"], r["trecho"] = d.get("protocolo") or "", d.get("trecho") or ""
                n += 1
        with open(f, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=cols, delimiter=";")
            w.writeheader()
            w.writerows(rows)
        resumo[nome] = {"linhas": len(rows), "preenchidas_agora": n}
    print(json.dumps(resumo))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    if not argv or argv[0] not in ("rodar", "aplicar", "unir"):
        print(__doc__)
        return 2
    if argv[0] == "aplicar":
        return aplicar()
    if argv[0] == "unir":
        return unir()
    sh = opt("--shard")
    shard = (int(sh.split("/")[0]), int(sh.split("/")[1])) if sh else None
    return rodar(opt("--alvo", "todos"), int(opt("--lote", 6)), int(opt("--max-lotes", 0)) or None, "--executar" in argv, shard=shard)


if __name__ == "__main__":
    sys.exit(main())
