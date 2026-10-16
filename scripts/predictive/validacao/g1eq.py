"""G1-eq, equivalencia da recuperacao (nota 120, bloco G0-v3, item 4). Orquestra e julga; nao rotula a etapa 1.

Regra congelada: os 30 primeiros itens da ordem cega da etapa 1 (semente 20261020, ordem de itens_cegos.json)
sao rotulados duas vezes pelo primeiro rotulador, em sessoes separadas: pela recuperacao do item 2
(rotular_g0v3) e pela leitura integral fatiada (leitura_integral_g0v3). Passa se a classe binaria
(evento_proprio contra o resto) difere em no maximo 1 dos 30 e se, entre os pares em que as duas leituras
marcam evento_proprio, a data difere em no maximo 1. Os rotulos do G1-eq NAO entram no CSV de rotulos nem
no G1a: ficam em SAIDA_DIR (data/validacao/etapa1_g0v2/g1eq/).

Prontidao: todo documento do dia e dos 180 dias dos 30 itens precisa constar da proveniencia (baixado,
sem texto ou inacessivel). Item com documento ainda nao tentado nao e rotulado.
Orcamento: --teto-tokens (soma das 4 parcelas) para antes de afetar outra coisa; limite de cota ou credencial
recusada interrompe com exit 87 e preserva o que ja foi feito (reexecucao retoma, item ja feito e pulado).

Uso:
  python -I g1eq.py prontidao ETAPA_DIR DOCS_DIR
  python -I g1eq.py rodar ETAPA_DIR DOCS_DIR [--modelo M] [--teto-tokens N] [--itens 30] [--so progressiva|integral]
  python -I g1eq.py avaliar ETAPA_DIR
"""
import datetime as dt
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
sys.path.insert(1, os.path.join(AQUI, "..", "ews2"))  # eventos.py: regua dos eventos derivados
import guarda_g0v3 as G3  # noqa: E402
import leitura_integral_g0v3 as LI  # noqa: E402
import llm_cli as L  # noqa: E402
import rotular_g0v3 as RO  # noqa: E402

N_ITENS = 30
TOL_CLASSE, TOL_DATA = 1, 1
EP = "evento_proprio"
EXIT_COTA = 87


def saida_dir(etapa):
    return os.path.join(etapa, "g1eq")


def itens_g1eq(etapa, n=N_ITENS):
    it = json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))
    return it[:n]


def proveniencia(etapa):
    prov = {}
    p = os.path.join(etapa, "proveniencia_downloads.jsonl")
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            try:
                j = json.loads(ln)
                prov[j["protocolo_rad"]] = j
            except Exception:  # noqa: BLE001
                pass
    return prov


def prontidao(etapa, n=N_ITENS):
    itens = itens_g1eq(etapa, n)
    man = {m["id"]: m for m in json.load(open(os.path.join(etapa, "manifesto_itens.json"), encoding="utf-8"))}
    prov = proveniencia(etapa)
    out = []
    for x in itens:
        docs = man[x["id"]]["dia"] + man[x["id"]]["contexto_180d"]
        falt = [p for p in docs if p not in prov]
        out.append({"id": x["id"], "docs": len(docs), "faltam": len(falt), "pronto": not falt})
    return {"itens": len(out), "prontos": sum(1 for o in out if o["pronto"]), "detalhe": out,
            "guarda_g0v3": G3.estado()["ok"]}


def _binaria(c):
    return 1 if c == EP else 0


def eventos_derivados(rotulo):
    """Datas de evento que a base de eventos (ews2/eventos.eventos_de_rotulos) criaria a partir deste rotulo.
    Mesma regua do pipeline, importada dele: evento_proprio na data rotulada, continuacao na data de entrega da
    origem, adicionais na data_ou_origem; incerto, nao_evento e evento_terceiro nao criam evento."""
    if not rotulo:
        return []
    import eventos as EV  # ews2/eventos.py, regua unica
    linha = {"cnpj": "x", "id": "x", "classe_final": rotulo.get("classe") or "",
             "data_evento_final": rotulo.get("data_evento") or "",
             "origem_data_entrega": ((rotulo.get("origem") or {}).get("data_entrega") or ""),
             "adicionais_json": json.dumps(rotulo.get("adicionais") or [], ensure_ascii=False)}
    return sorted(e["data"].isoformat() for e in EV.eventos_de_rotulos([linha]))


def avaliar_estendido(pares, completos, tol_eventos=TOL_DATA):
    """Proposta G1-eq-ext (adendo, NAO congelada). Duas lacunas da regra congelada, achadas na auditoria de 16/10:
    (1) ela so compara data entre pares evento_proprio, entao divergencia que muda o evento derivado (incerto contra
    continuacao com origem, origem com data diferente, adicional so de um lado) passa sem contar; (2) ela aceita par
    gerado por versao antiga do executor. Aqui: os eventos derivados de cada braco precisam ser iguais (tolerancia 1),
    e todo par precisa ter as duas versoes atuais do executor. Usado pelo portao P4 de rotular_etapa1 (fail-closed)."""
    dif_eventos = [p["id"] for p in completos if (p.get("eventos_prog") or []) != (p.get("eventos_int") or [])]
    antigos = [p["id"] for p in pares if p.get("versao_progressiva") != RO.VERSAO_EXECUTOR or p.get("versao_integral") != LI.VERSAO_EXECUTOR]
    completo = len(completos) == len(pares) and len(pares) > 0
    passa = completo and not antigos and len(dif_eventos) <= tol_eventos
    motivos = []
    if not completo:
        motivos.append("incompleto: %d de %d pares" % (len(completos), len(pares)))
    if antigos:
        motivos.append("pares com executor antigo: %s" % ",".join(antigos))
    if len(dif_eventos) > tol_eventos:
        motivos.append("eventos derivados divergem em %d pares (tolerancia %d)" % (len(dif_eventos), tol_eventos))
    return {"regra": "G1-eq-ext proposta 2026-10-16 (nao congelada)", "dif_eventos_derivados": dif_eventos,
            "n_dif_eventos": len(dif_eventos), "tolerancia_eventos": tol_eventos, "pares_executor_antigo": antigos,
            "passa": passa if completo else None, "motivos": motivos}


def avaliar_pares(pares, tol_classe=TOL_CLASSE, tol_data=TOL_DATA):
    """Puro. pares: [{id, classe_prog, classe_int, data_prog, data_int, status_prog, status_int}].
    Item com algum braco em erro de chamada nao conta como par e reprova a completude.
    `passa`/`veredito` sao a regra CONGELADA do bloco G0-v3; `estendido` e a proposta de adendo, a parte."""
    completos = [p for p in pares if p.get("classe_prog") and p.get("classe_int")
                 and p.get("status_prog") == "rotulado" and p.get("status_int") == "rotulado"]
    dif_classe = [p["id"] for p in completos if _binaria(p["classe_prog"]) != _binaria(p["classe_int"])]
    epep = [p for p in completos if p["classe_prog"] == EP and p["classe_int"] == EP]
    dif_data = [p["id"] for p in epep if (p.get("data_prog") or "") != (p.get("data_int") or "")]
    completo = len(completos) == len(pares) and len(pares) > 0
    passa = completo and len(dif_classe) <= tol_classe and len(dif_data) <= tol_data
    return {"n_pares": len(pares), "n_completos": len(completos), "completo": completo,
            "dif_classe_binaria": dif_classe, "n_dif_classe": len(dif_classe), "tolerancia_classe": tol_classe,
            "pares_ep_ep": len(epep), "dif_data": dif_data, "n_dif_data": len(dif_data), "tolerancia_data": tol_data,
            "passa": passa if completo else None, "veredito": ("passa" if passa else "reprova") if completo else "incompleto",
            "adjudicacao": [p["id"] for p in pares if "adjudicacao" in (p.get("status_prog"), p.get("status_int"))],
            "estendido": avaliar_estendido(pares, completos)}


def _ler(p):
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None


def coletar(etapa, n=N_ITENS):
    sd = saida_dir(etapa)
    pares, tokens = [], {"progressiva": 0, "integral": 0}
    for x in itens_g1eq(etapa, n):
        a = _ler(os.path.join(sd, "progressiva", "%s.json" % x["id"]))
        b = _ler(os.path.join(sd, "integral", "%s.json" % x["id"]))
        ra = (a or {}).get("rotulo") or {}
        rb = (b or {}).get("rotulo") or {}
        pares.append({"id": x["id"], "classe_prog": ra.get("classe"), "classe_int": rb.get("classe"),
                      "data_prog": ra.get("data_evento"), "data_int": rb.get("data_evento"),
                      "status_prog": (a or {}).get("status"), "status_int": (b or {}).get("status"),
                      "tipo_prog": ra.get("tipo"), "tipo_int": rb.get("tipo"),
                      "tokens_prog": L.total_tokens(a["tokens"]) if a and a.get("tokens") else None,
                      "tokens_int": L.total_tokens(b["tokens"]) if b and b.get("tokens") else None,
                      "n_fatias": (b or {}).get("n_fatias"), "n_rodadas_pedido": (a or {}).get("n_rodadas_pedido"),
                      "versao_integral": (b or {}).get("versao_executor", "integral-v0.1"), "versao_progressiva": (a or {}).get("versao_executor", "progressiva-v0.1"),
                      "rodadas_pedido_int": (b or {}).get("n_rodadas_pedido"),
                      "eventos_prog": eventos_derivados(ra), "eventos_int": eventos_derivados(rb)})
        tokens["progressiva"] += pares[-1]["tokens_prog"] or 0
        tokens["integral"] += pares[-1]["tokens_int"] or 0
    return pares, tokens


def avaliar(etapa, n=N_ITENS):
    pares, tokens = coletar(etapa, n)
    r = avaliar_pares(pares)
    exec_sha = {}
    for nome in ("llm_cli.py", "rotular_g0v3.py", "leitura_integral_g0v3.py", "g1eq.py", "recuperar_g0v3.py"):
        exec_sha[nome] = hashlib.sha256(open(os.path.join(AQUI, nome), "rb").read()).hexdigest()
    r.update({"protocolo": "G0-v3", "gate": "G1-eq", "sha256_bloco_v3": G3.PROTOCOLO_G0V3_SHA256,
              "sha256_recuperar": G3.RECUPERAR_SHA256, "sha256_executor": exec_sha, "modelo": L.MODELO_PADRAO,
              "versoes_executor": {"progressiva": RO.VERSAO_EXECUTOR, "integral": LI.VERSAO_EXECUTOR},
              "tokens": tokens, "pares": pares,
              "avaliado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
    sd = saida_dir(etapa)
    os.makedirs(sd, exist_ok=True)
    with open(os.path.join(sd, "resultado_g1eq.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(r, fh, ensure_ascii=False, indent=1)
    reg = {"arquivos": {}}
    for raiz, _, arqs in os.walk(sd):
        for a in arqs:
            if a.endswith((".json", ".jsonl", ".txt")) and a != "registro_g1eq.json":
                p = os.path.join(raiz, a)
                reg["arquivos"][os.path.relpath(p, sd).replace("\\", "/")] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    reg["gerado_em"] = r["avaliado_em"]
    with open(os.path.join(sd, "registro_g1eq.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=1, sort_keys=True)
    return r


def rodar(etapa, docs_dir, modelo=L.MODELO_PADRAO, teto_tokens=8_000_000, n=N_ITENS, so=None, refazer=()):
    """refazer: ids cujo braco integral deve ser refeito (executor novo); o resultado antigo e preservado em *.v_anterior.json."""
    est = G3.estado()
    if not est["ok"]:
        print(json.dumps({"ok": False, "erro": "guarda G0-v3 reprovou", "motivos": est["motivos"]}))
        return 1
    pront = prontidao(etapa, n)
    sd = saida_dir(etapa)
    itens, man, meta = RO.carregar(etapa)
    guia = RO.guia_v3()
    gasto = 0
    for x in itens_g1eq(etapa, n):
        pr = next(d for d in pront["detalhe"] if d["id"] == x["id"])
        if not pr["pronto"]:
            print(json.dumps({"id": x["id"], "pulado": "documentos ainda nao tentados", "faltam": pr["faltam"]}))
            continue
        for modo, func, pasta in (("progressiva", RO.rotular, "progressiva"), ("integral", LI.rotular_integral, "integral")):
            if so and so != modo:
                continue
            alvo = os.path.join(sd, pasta, "%s.json" % x["id"])
            if os.path.exists(alvo) and (_ler(alvo) or {}).get("status") in ("rotulado", "adjudicacao"):
                versao_atual = LI.VERSAO_EXECUTOR if modo == "integral" else RO.VERSAO_EXECUTOR
                if x["id"] in refazer and (_ler(alvo) or {}).get("versao_executor") != versao_atual:
                    os.replace(alvo, alvo[:-5] + ".v_anterior.json")
                else:
                    continue
            if gasto >= teto_tokens:
                print(json.dumps({"parado": "teto de tokens", "gasto": gasto, "teto": teto_tokens}))
                return EXIT_COTA
            try:
                if modo == "progressiva":
                    r = func(itens[x["id"]], man[x["id"]], meta, docs_dir, sd, modelo=modelo, guia=guia)
                else:
                    r = func(itens[x["id"]], man[x["id"]], meta, docs_dir, sd, modelo=modelo, guia=guia)
            except L.LimiteDeCota as e:
                print(json.dumps({"parado": "limite de cota ou credencial", "detalhe": str(e)[:200], "gasto": gasto}))
                return EXIT_COTA
            os.makedirs(os.path.dirname(alvo), exist_ok=True)
            with open(alvo, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(r, fh, ensure_ascii=False, indent=1, default=str)
            t = L.total_tokens(r["tokens"]) if r.get("tokens") else 0
            gasto += t
            print(json.dumps({"id": x["id"], "modo": modo, "status": r.get("status"), "classe": (r.get("rotulo") or {}).get("classe"),
                              "tokens": t, "acumulado": gasto}), flush=True)
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in ("prontidao", "rodar", "avaliar"):
        print(__doc__)
        return 2

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    n = int(opt("--itens", N_ITENS))
    if argv[0] == "prontidao":
        print(json.dumps(prontidao(argv[1], n), ensure_ascii=False, indent=1))
        return 0
    if argv[0] == "avaliar":
        r = avaliar(argv[1], n)
        print(json.dumps({k: v for k, v in r.items() if k != "pares"}, ensure_ascii=False, indent=1))
        return 0 if r["passa"] else 1
    refazer = tuple(x for x in (opt("--refazer", "") or "").split(",") if x)
    return rodar(argv[1], argv[2], modelo=opt("--modelo", L.MODELO_PADRAO), teto_tokens=int(opt("--teto-tokens", 8_000_000)), n=n, so=opt("--so"), refazer=refazer)


if __name__ == "__main__":
    sys.exit(main())
