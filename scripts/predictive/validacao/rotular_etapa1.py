"""Rotulagem da ETAPA 1 (os 1.261 itens cegos), primeiro rotulador Claude e segundo rotulador configuravel, pela G0-v3.
PREPARADO, NAO EXECUTAVEL ate os quatro portoes abaixo abrirem. Nenhum rotulo e gravado sem eles.

Portoes (medidos, nunca presumidos):
  P1  guarda_g0v3.estado()["ok"]  (bloco G0-v3, recuperar_g0v3.py, G0-v2 e anexo congelados e intactos)
  P2  g1eq/resultado_g1eq.json com "passa": true  (G1-eq aprovado, item 4 do bloco)
  P3  data/validacao/autorizacao_rotulagem_etapa1.json gravado pelo operador e valido (segundo_config):
      {"autorizado": true, "data": "AAAA-MM-DD", "primeiro_rotulador": "claude", "modelo_claude": "...",
       "segundo_rotulador": "codex|gemini|openrouter|claude", "modelo_segundo": "...", "teto_tokens_lote": N,
       "aceita_mesmo_fornecedor": bool (so se o segundo for do fornecedor do primeiro), "openrouter_pago_autorizado": bool}
      Este script nunca cria esse arquivo.
  P4  bloco `estendido` do G1-eq aprovado (proposta G1-eq-ext, nota 122)

Saida (item 5 do bloco): CSV so-acrescenta data/validacao/rotulos_etapa1.csv com as colunas de preflight_g1a
(id;cnpj;data;origem;classe1;data_evento1;protocolo;trecho;sha256_documento;data_download) mais origem_* e adicionais_json.
A coluna `origem` (uniao/G) sai do mapa_camadas PRIVADO so na gravacao, depois do rotulo, e nunca entra no prompt.
Rotulo refeito entra como linha nova com referencia a anterior (coluna refaz_de). Registro de cada chamada em
rotulos_etapa1_chamadas.jsonl. Segunda leitura (Codex, G1a e itens de G/uniao do item 4) em rotulos_etapa1_segunda.csv.

Uso:
  python -I rotular_etapa1.py portoes ETAPA_DIR
  python -I rotular_etapa1.py rodar ETAPA_DIR DOCS_DIR [--teto-tokens N] [--max-itens N] [--dry-run]
  python -I rotular_etapa1.py segunda ETAPA_DIR DOCS_DIR --ids CSV_DE_IDS [--dry-run]   # Codex, so com P1-P3 e CSV do primeiro completo
"""
import csv
import datetime as dt
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v3 as G3  # noqa: E402
import llm_cli as L  # noqa: E402
import rotular_g0v3 as RO  # noqa: E402

BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
AUTORIZACAO = os.path.join(BASE, "data", "validacao", "autorizacao_rotulagem_etapa1.json")
COLUNAS = ("id", "cnpj", "data", "origem", "classe1", "data_evento1", "protocolo", "trecho", "sha256_documento", "data_download",
           "tipo", "origem_protocolo", "origem_data_entrega", "origem_tipo", "origem_trecho", "adicionais_json", "motivo_incerto",
           "status", "falhas_trecho", "modelo", "versao_executor", "sha256_bloco_v3", "refaz_de", "rotulado_em")
COLUNAS_SEGUNDA = ("id", "classe2", "data_evento2", "protocolo", "trecho", "tipo", "origem_json", "adicionais_json", "motivo_incerto",
                   "status", "falhas_trecho", "provider", "modelo", "rotulado_em")
EXIT_BLOQUEADO = 86
EXIT_COTA = 87


PROVEDORES_PRIMEIRO = ("claude", "openrouter")


def primeiro_config(aut):
    """Puro. Primeiro rotulador gravado pelo operador: primeiro_rotulador (claude|openrouter) e modelo_primeiro
    (fallback modelo_claude, depois o padrao Claude). Devolve (cfg, erros)."""
    aut = aut or {}
    prov = str(aut.get("primeiro_rotulador") or "claude").strip().lower()
    modelo = str(aut.get("modelo_primeiro") or (aut.get("modelo_claude") if prov == "claude" else "") or
                 (L.MODELO_PADRAO if prov == "claude" else "")).strip()
    erros = []
    if prov not in PROVEDORES_PRIMEIRO:
        erros.append("primeiro_rotulador invalido: %r (opcoes %s)" % (prov, ", ".join(PROVEDORES_PRIMEIRO)))
    if not modelo:
        erros.append("modelo_primeiro ausente")
    if prov == "openrouter" and "/" not in modelo:
        erros.append("modelo_primeiro do OpenRouter precisa do formato fornecedor/modelo")
    if prov == "openrouter" and aut.get("openrouter_pago_autorizado") is not True:
        erros.append("openrouter e pago por token: exige openrouter_pago_autorizado=true")
    return {"provider": prov, "modelo": modelo, "fornecedor": L.fornecedor(prov, modelo) if modelo else None}, erros


SUBSTITUI_P2 = "g1eq_metodo_claude_mais_qualidade"


def _json_ou_none(caminho):
    try:
        return json.load(open(caminho, encoding="utf-8-sig")) if os.path.exists(caminho) else None
    except (ValueError, OSError):
        return None


def p2_substituto(etapa, pcfg):
    """Puro sobre arquivos. Primeiro leitor que NAO e o Claude padrao e que nao tem o braco integral do G1-eq (decisao do
    operador em 16/10): o P2 vale se, e so se, as TRES pecas existirem e baterem com o leitor configurado:
      (a) G1-eq do METODO aprovado (Claude, g1eq/resultado_g1eq.json, congelada e estendida, 30/30);
      (b) decisao do operador gravada em <g1eq do leitor>/decisao_p2.json, para este provider e modelo;
      (c) verificacao de qualidade independente deste modelo (qualidade_independente.json) aprovada e completa.
    Devolve {ok, motivos, claude}."""
    import g1eq as GQ
    motivos = []
    claude = _json_ou_none(os.path.join(GQ.saida_dir(etapa), "resultado_g1eq.json")) or {}
    if not (claude.get("passa") is True and claude.get("n_completos") == GQ.N_ITENS and (claude.get("estendido") or {}).get("passa") is True):
        motivos.append("G1-eq do metodo (Claude) nao esta aprovado na regra congelada e na estendida")
    pasta = GQ.saida_dir(etapa, pcfg["provider"], pcfg["modelo"])
    dec = _json_ou_none(os.path.join(pasta, "decisao_p2.json")) or {}
    if not (dec.get("autorizado_por_operador") is True and dec.get("substitui") == SUBSTITUI_P2
            and dec.get("provider") == pcfg["provider"] and dec.get("modelo") == pcfg["modelo"]):
        motivos.append("decisao do operador ausente ou de outro leitor (decisao_p2.json)")
    q = _json_ou_none(os.path.join(pasta, "qualidade_independente.json")) or {}
    if not (q.get("passa") is True and q.get("completo") is True and q.get("modelo") == pcfg["modelo"]):
        motivos.append("qualidade independente ausente, incompleta, reprovada ou de outro modelo")
    return {"ok": not motivos, "motivos": motivos, "claude": claude}


def portoes(etapa, autorizacao=AUTORIZACAO):
    est = G3.estado()
    aut = json.load(open(autorizacao, encoding="utf-8-sig")) if os.path.exists(autorizacao) else None
    pcfg, perros = primeiro_config(aut)
    # P2 le o G1-eq DO PRIMEIRO LEITOR configurado e exige que o resultado seja daquele provider/modelo: aprovar o
    # Claude nao aprova outro modelo (16/10, troca do primeiro leitor para OpenRouter).
    import g1eq as GQ
    g1 = os.path.join(GQ.saida_dir(etapa, pcfg["provider"], pcfg["modelo"]), "resultado_g1eq.json")
    g1r = json.load(open(g1, encoding="utf-8")) if os.path.exists(g1) else None
    mesmo_leitor = bool(g1r) and g1r.get("modelo", L.MODELO_PADRAO) == pcfg["modelo"] and g1r.get("provider", "claude") == pcfg["provider"]
    proprio_ok = bool(g1r and g1r.get("passa") is True and mesmo_leitor)
    nao_claude = not (pcfg["provider"] == "claude" and pcfg["modelo"] == L.MODELO_PADRAO)
    subst = p2_substituto(etapa, pcfg) if (nao_claude and not proprio_ok) else None
    p = {"P1_guarda_g0v3": {"ok": est["ok"], "motivos": est["motivos"]},
         "P2_g1eq": {"ok": proprio_ok or bool(subst and subst["ok"]), "veredito": (g1r or {}).get("veredito", "ausente"),
                     "n_completos": (g1r or {}).get("n_completos"), "arquivo": g1, "leitor": pcfg,
                     "mesmo_leitor": mesmo_leitor, "via": "proprio" if proprio_ok else ("substituto" if subst and subst["ok"] else None),
                     "motivos_substituto": (subst or {}).get("motivos")},
         "P3_autorizacao": {"ok": bool(aut and aut.get("autorizado") is True and aut.get("primeiro_rotulador") and aut.get("segundo_rotulador")),
                            "arquivo": autorizacao, "presente": aut is not None}}
    if aut is not None:
        cfg, erros = segundo_config(aut)
        erros = perros + erros
        p["P3_autorizacao"].update({"primeiro": pcfg, "segundo": cfg, "erros": erros})
        p["P3_autorizacao"]["ok"] = p["P3_autorizacao"]["ok"] and not erros
    # P4 (adendo de 16/10, fail-closed ate o operador decidir): a regra congelada do G1-eq nao compara o evento que
    # cada braco cria (continuacao/origem, adicionais, incerto contra continuacao) e aceita par de executor antigo.
    # Sem o bloco `estendido` aprovado no resultado, a rotulagem nao comeca. Relaxar so por decisao registrada.
    ext = (subst["claude"].get("estendido") if subst and subst["ok"] else (g1r or {}).get("estendido")) or {}
    p["P4_g1eq_estendido"] = {"ok": ext.get("passa") is True, "motivos": ext.get("motivos", ["resultado sem bloco estendido: reavaliar com g1eq.py avaliar"])}
    p["ok"] = all(v["ok"] for k, v in p.items() if k.startswith("P"))
    return p


TETO_LOTE_PADRAO = 2_000_000


def segundo_config(aut):
    """Puro. Le e valida a escolha do segundo rotulador gravada pelo operador na autorizacao. Devolve (cfg, erros).
    Campos: segundo_rotulador (codex|gemini|openrouter|claude), modelo_segundo, teto_tokens_lote,
    aceita_mesmo_fornecedor (obrigatorio quando o fornecedor do segundo e o do primeiro), openrouter_pago_autorizado."""
    aut = aut or {}
    prov = str(aut.get("segundo_rotulador") or "").strip().lower()
    modelo = str(aut.get("modelo_segundo") or "").strip() or (L.modelo_codex() if prov == "codex" else None)
    erros = []
    if prov not in L.PROVEDORES_SEGUNDO:
        erros.append("segundo_rotulador invalido: %r (opcoes %s)" % (prov, ", ".join(L.PROVEDORES_SEGUNDO)))
    if not modelo:
        erros.append("modelo_segundo ausente")
    pcfg = primeiro_config(aut)[0]
    primeiro = pcfg["fornecedor"]
    if prov in L.PROVEDORES_SEGUNDO and modelo and L.fornecedor(prov, modelo) == primeiro and aut.get("aceita_mesmo_fornecedor") is not True:
        erros.append("segundo rotulador do mesmo fornecedor do primeiro (%s): exige aceita_mesmo_fornecedor=true, G0-v2 item 4" % primeiro)
    if modelo and modelo == pcfg["modelo"]:
        erros.append("segundo rotulador com o MESMO modelo do primeiro nao mede nada: use outro modelo")
    if prov == "gemini":
        # medido 16/10 11:44: sem OAuth headless (exit 130) e o CLI carrega skills de ~/.agents/skills e ~/.gemini/skills
        # no contexto, o que quebra a leitura cega. Bloqueado ate isolamento comprovado (nota 122, secao 3.1).
        erros.append("gemini bloqueado: sem login headless e carrega skills do usuario no contexto (leitura cega nao garantida)")
    if prov == "openrouter" and aut.get("openrouter_pago_autorizado") is not True:
        erros.append("openrouter e pago por token: exige openrouter_pago_autorizado=true")
    teto = aut.get("teto_tokens_lote")
    if not isinstance(teto, int) or teto <= 0:
        erros.append("teto_tokens_lote ausente ou invalido")
    return {"provider": prov, "modelo": modelo, "teto_tokens_lote": teto if isinstance(teto, int) and teto > 0 else None,
            "fornecedor": L.fornecedor(prov, modelo) if prov else None}, erros


def _ler_csv(p):
    if not os.path.exists(p):
        return []
    with open(p, encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh, delimiter=";"))


def _acrescentar(p, colunas, linha):
    novo = not os.path.exists(p)
    with open(p, "a", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=colunas, delimiter=";", extrasaction="ignore")
        if novo:
            w.writeheader()
        w.writerow({c: ("" if linha.get(c) is None else linha.get(c)) for c in colunas})


def linha_de_resultado(item, mapa, r, prov, refaz_de=""):
    rot = r.get("rotulo") or {}
    orig = rot.get("origem") or {}
    prot = rot.get("protocolo_evento") or orig.get("protocolo") or ""
    pv = prov.get(str(prot), {}) if prot else {}
    return {"id": item["id"], "cnpj": item["cnpj"], "data": item["data"], "origem": mapa[item["id"]]["origem"],
            "classe1": rot.get("classe"), "data_evento1": rot.get("data_evento") or "", "protocolo": prot,
            "trecho": rot.get("trecho_evento") or orig.get("trecho") or "", "sha256_documento": pv.get("sha256", ""),
            "data_download": pv.get("baixado_em", ""), "tipo": rot.get("tipo") or "", "origem_protocolo": orig.get("protocolo", ""),
            "origem_data_entrega": orig.get("data_entrega", ""), "origem_tipo": orig.get("tipo", ""), "origem_trecho": orig.get("trecho", ""),
            "adicionais_json": json.dumps(rot.get("adicionais") or [], ensure_ascii=False), "motivo_incerto": rot.get("motivo_incerto") or "",
            "status": r.get("status"), "falhas_trecho": " | ".join(r.get("falhas_trecho") or []), "modelo": r.get("modelo"),
            "versao_executor": r.get("versao_executor"), "sha256_bloco_v3": r.get("sha256_bloco_v3"), "refaz_de": refaz_de,
            "rotulado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}


def rodar(etapa, docs_dir, teto_tokens=2_000_000, max_itens=None, dry_run=False, autorizacao=AUTORIZACAO):
    p = portoes(etapa, autorizacao)
    if not p["ok"]:
        print(json.dumps({"ok": False, "bloqueado": "portoes fechados", "portoes": p}, ensure_ascii=False, indent=1))
        return EXIT_BLOQUEADO
    aut = json.load(open(autorizacao, encoding="utf-8-sig"))
    pcfg = primeiro_config(aut)[0]
    provider, modelo = pcfg["provider"], pcfg["modelo"]
    teto_tokens = min(teto_tokens, segundo_config(aut)[0]["teto_tokens_lote"])  # teto do lote vem da autorizacao
    itens, man, meta = RO.carregar(etapa)
    mapa = json.load(open(os.path.join(etapa, "mapa_camadas.json"), encoding="utf-8"))
    import g1eq as GQ
    prov = GQ.proveniencia(etapa)
    csv_p = os.path.join(etapa, "..", "rotulos_etapa1.csv")
    # idempotencia POR MODELO: rotulo de outro leitor (ex.: os 19 do Claude de 16/10) nunca conta como feito deste
    feitos = {r["id"] for r in _ler_csv(csv_p) if r.get("status") in ("rotulado", "adjudicacao") and r.get("modelo") == modelo}
    saida = os.path.join(etapa, "etapa1_execucao" + GQ.slug_leitor(provider, modelo))
    custos_p = os.path.join(saida, "custos.jsonl")
    orc = orcamento(aut, provider)
    guia = RO.guia_v3()
    gasto, n = 0, 0
    for it in json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8")):
        if it["id"] in feitos:
            continue
        if max_itens and n >= max_itens:
            break
        docs = man[it["id"]]["dia"] + man[it["id"]]["contexto_180d"]
        if any(d not in prov for d in docs):
            print(json.dumps({"id": it["id"], "pulado": "documentos ainda nao tentados"}))
            continue
        if gasto >= teto_tokens:
            print(json.dumps({"parado": "teto de tokens", "gasto": gasto}))
            return EXIT_COTA
        if orc and custo_acumulado(custos_p) >= orc["usd"]:
            print(json.dumps({"parado": "orcamento USD", "acumulado_usd": round(custo_acumulado(custos_p), 4), "orcamento_usd": orc["usd"]}))
            return EXIT_ORCAMENTO
        if dry_run:
            r = RO.rotular(itens[it["id"]], man[it["id"]], meta, docs_dir, saida, modelo=modelo, provider=provider, dry_run=True, guia=guia)
            print(json.dumps({"id": it["id"], "dry_run": True, "chars_prompt": r["chars_prompt"]}))
            n += 1
            continue
        try:
            r = RO.rotular(itens[it["id"]], man[it["id"]], meta, docs_dir, saida, modelo=modelo, provider=provider, guia=guia)
        except L.LimiteDeCota as e:
            print(json.dumps({"parado": "limite de cota ou credencial", "detalhe": str(e)[:200], "gasto": gasto}))
            return EXIT_COTA
        if orc and r.get("tokens"):
            registrar_custo(custos_p, it["id"], r["tokens"], orc)
        if r.get("status") not in ("rotulado", "adjudicacao"):
            print(json.dumps({"id": it["id"], "erro": r.get("erro"), "classe": r.get("classe_falha")}))
            continue
        _acrescentar(csv_p, COLUNAS, linha_de_resultado(itens[it["id"]], mapa, r, prov))
        gasto += L.total_tokens(r["tokens"])
        n += 1
        print(json.dumps({"id": it["id"], "status": r["status"], "classe": r["rotulo"]["classe"], "acumulado": gasto,
                          "custo_usd": round(custo_acumulado(custos_p), 4) if orc else None}), flush=True)
    return 0


EXIT_ORCAMENTO = 88


def orcamento(aut, provider):
    """Leitor pago (OpenRouter): orcamento_usd e preco_usd_por_milhao {input, output, cache_read} gravados na autorizacao.
    Sem os dois, nao ha leitura paga. Assinatura (Claude): sem orcamento em dolar, vale o teto de tokens."""
    if provider != "openrouter":
        return None
    preco = aut.get("preco_usd_por_milhao") or {}
    usd = aut.get("orcamento_usd")
    if not isinstance(usd, (int, float)) or usd <= 0 or not all(isinstance(preco.get(k), (int, float)) for k in ("input", "output")):
        raise L.LimiteDeCota("leitura paga sem orcamento_usd e preco_usd_por_milhao{input,output} na autorizacao")
    return {"usd": float(usd), "preco": preco}


def custo_usd(tokens, preco):
    """Custo real cobrado quando o OpenRouter devolve (usage.include); senao, estimativa pelo preco da autorizacao."""
    t = tokens or {}
    # tentativas que estouraram o prazo sem usage (CUSTOSEMUSAGE1) somam sempre, mesmo com custo real presente
    sem = (t.get("sem_usage_input", 0) * preco["input"] + t.get("sem_usage_output", 0) * preco["output"]) / 1e6
    if t.get("custo_usd"):
        return float(t["custo_usd"]) + sem
    return (t.get("input", 0) * preco["input"] + t.get("output", 0) * preco["output"]
            + t.get("cache_read", 0) * preco.get("cache_read", preco["input"])) / 1e6 + sem


def registrar_custo(caminho, iid, tokens, orc):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps({"id": iid, "tokens": tokens, "usd": custo_usd(tokens, orc["preco"]),
                             "em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}) + "\n")


def custo_acumulado(caminho):
    if not os.path.exists(caminho):
        return 0.0
    tot = 0.0
    for ln in open(caminho, encoding="utf-8"):
        try:
            tot += float(json.loads(ln)["usd"])
        except Exception:  # noqa: BLE001
            pass
    return tot


def segunda(etapa, docs_dir, ids, dry_run=False, autorizacao=AUTORIZACAO):
    """Segunda leitura pelo Codex (outro fornecedor), cega: mesmo guia, mesmos documentos, sem o primeiro rotulo nem a camada."""
    p = portoes(etapa, autorizacao)
    if not p["ok"]:
        print(json.dumps({"ok": False, "bloqueado": "portoes fechados", "portoes": p}, ensure_ascii=False, indent=1))
        return EXIT_BLOQUEADO
    cfg, _ = segundo_config(json.load(open(autorizacao, encoding="utf-8-sig")))
    if cfg["provider"] in ("gemini", "openrouter"):
        os.environ[L.VAR_MODELO_SEGUNDO] = cfg["modelo"]
    itens, man, meta = RO.carregar(etapa)
    csv_p = os.path.join(etapa, "..", "rotulos_etapa1_segunda.csv")
    feitos = {r["id"] for r in _ler_csv(csv_p)}
    saida = os.path.join(etapa, "etapa1_execucao_segunda")
    guia = RO.guia_v3()
    gasto = 0
    for iid in ids:
        if iid in feitos:
            continue
        if gasto >= cfg["teto_tokens_lote"]:
            print(json.dumps({"parado": "teto de tokens do lote", "gasto": gasto, "teto": cfg["teto_tokens_lote"]}))
            return EXIT_COTA
        try:
            # modelo explicito: sem ele, rotular() herdaria o padrao Claude e mandaria `-m claude-...` a outro fornecedor
            r = RO.rotular(itens[iid], man[iid], meta, docs_dir, saida, modelo=cfg["modelo"], provider=cfg["provider"], dry_run=dry_run, guia=guia)
        except L.LimiteDeCota as e:
            print(json.dumps({"parado": "limite, janela, credencial ou modelo do segundo rotulador", "provider": cfg["provider"], "detalhe": str(e)[:200]}))
            return EXIT_COTA
        if not dry_run and r.get("tokens"):
            gasto += L.total_tokens(r["tokens"])
        if dry_run:
            print(json.dumps({"id": iid, "dry_run": True, "provider": cfg["provider"], "argv0": (r.get("codex_argv") or ["?"])[0]}))
            continue
        rot = r.get("rotulo") or {}
        orig = rot.get("origem") or {}
        _acrescentar(csv_p, COLUNAS_SEGUNDA, {"id": iid, "classe2": rot.get("classe"), "data_evento2": rot.get("data_evento") or "",
                                             "protocolo": rot.get("protocolo_evento") or orig.get("protocolo") or "",
                                             "trecho": rot.get("trecho_evento") or orig.get("trecho") or "", "tipo": rot.get("tipo") or "",
                                             "origem_json": json.dumps(orig, ensure_ascii=False), "adicionais_json": json.dumps(rot.get("adicionais") or [], ensure_ascii=False),
                                             "motivo_incerto": rot.get("motivo_incerto") or "", "status": r.get("status"),
                                             "falhas_trecho": " | ".join(r.get("falhas_trecho") or []), "provider": cfg["provider"], "modelo": cfg["modelo"],
                                             "rotulado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
        print(json.dumps({"id": iid, "status": r.get("status"), "classe2": rot.get("classe")}), flush=True)
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in ("portoes", "rodar", "segunda"):
        print(__doc__)
        return 2

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    if argv[0] == "portoes":
        if len(argv) < 2:  # sem ETAPA_DIR caia em IndexError com EXIT=1, lido como falha do portao
            print(__doc__)
            return 2
        p = portoes(argv[1])
        print(json.dumps(p, ensure_ascii=False, indent=1))
        return 0 if p["ok"] else EXIT_BLOQUEADO
    if argv[0] == "rodar":
        return rodar(argv[1], argv[2], teto_tokens=int(opt("--teto-tokens", 2_000_000)), max_itens=int(opt("--max-itens", 0)) or None, dry_run="--dry-run" in argv)
    ids = [x.strip() for x in open(opt("--ids"), encoding="utf-8-sig").read().replace("\n", ",").split(",") if x.strip()]
    return segunda(argv[1], argv[2], ids, dry_run="--dry-run" in argv)


if __name__ == "__main__":
    sys.exit(main())
