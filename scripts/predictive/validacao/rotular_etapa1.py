"""Rotulagem da ETAPA 1 (os 1.261 itens cegos), primeiro rotulador Claude e segundo rotulador Codex, pela G0-v3.
PREPARADO, NAO EXECUTAVEL ate os tres portoes abaixo abrirem. Nenhum rotulo e gravado sem eles.

Portoes (medidos, nunca presumidos):
  P1  guarda_g0v3.estado()["ok"]  (bloco G0-v3, recuperar_g0v3.py, G0-v2 e anexo congelados e intactos)
  P2  g1eq/resultado_g1eq.json com "passa": true  (G1-eq aprovado, item 4 do bloco)
  P3  data/validacao/autorizacao_rotulagem_etapa1.json gravado pelo operador:
      {"autorizado": true, "data": "AAAA-MM-DD", "primeiro_rotulador": "claude", "segundo_rotulador": "codex", "modelo_claude": "..."}
      Este script nunca cria esse arquivo.

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


def portoes(etapa, autorizacao=AUTORIZACAO):
    est = G3.estado()
    g1 = os.path.join(etapa, "g1eq", "resultado_g1eq.json")
    g1r = json.load(open(g1, encoding="utf-8")) if os.path.exists(g1) else None
    aut = json.load(open(autorizacao, encoding="utf-8-sig")) if os.path.exists(autorizacao) else None
    p = {"P1_guarda_g0v3": {"ok": est["ok"], "motivos": est["motivos"]},
         "P2_g1eq": {"ok": bool(g1r and g1r.get("passa") is True), "veredito": (g1r or {}).get("veredito", "ausente"),
                     "n_completos": (g1r or {}).get("n_completos")},
         "P3_autorizacao": {"ok": bool(aut and aut.get("autorizado") is True and aut.get("primeiro_rotulador") and aut.get("segundo_rotulador")),
                            "arquivo": autorizacao, "presente": aut is not None}}
    p["ok"] = all(v["ok"] for k, v in p.items() if k.startswith("P"))
    return p


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
    modelo = aut.get("modelo_claude") or L.MODELO_PADRAO
    itens, man, meta = RO.carregar(etapa)
    mapa = json.load(open(os.path.join(etapa, "mapa_camadas.json"), encoding="utf-8"))
    import g1eq as GQ
    prov = GQ.proveniencia(etapa)
    csv_p = os.path.join(etapa, "..", "rotulos_etapa1.csv")
    feitos = {r["id"] for r in _ler_csv(csv_p) if r.get("status") in ("rotulado", "adjudicacao")}
    saida = os.path.join(etapa, "etapa1_execucao")
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
        if dry_run:
            r = RO.rotular(itens[it["id"]], man[it["id"]], meta, docs_dir, saida, modelo=modelo, dry_run=True, guia=guia)
            print(json.dumps({"id": it["id"], "dry_run": True, "chars_prompt": r["chars_prompt"]}))
            n += 1
            continue
        try:
            r = RO.rotular(itens[it["id"]], man[it["id"]], meta, docs_dir, saida, modelo=modelo, guia=guia)
        except L.LimiteDeCota as e:
            print(json.dumps({"parado": "limite de cota ou credencial", "detalhe": str(e)[:200], "gasto": gasto}))
            return EXIT_COTA
        if r.get("status") not in ("rotulado", "adjudicacao"):
            print(json.dumps({"id": it["id"], "erro": r.get("erro"), "classe": r.get("classe_falha")}))
            continue
        _acrescentar(csv_p, COLUNAS, linha_de_resultado(itens[it["id"]], mapa, r, prov))
        gasto += L.total_tokens(r["tokens"])
        n += 1
        print(json.dumps({"id": it["id"], "status": r["status"], "classe": r["rotulo"]["classe"], "acumulado": gasto}), flush=True)
    return 0


def segunda(etapa, docs_dir, ids, dry_run=False, autorizacao=AUTORIZACAO):
    """Segunda leitura pelo Codex (outro fornecedor), cega: mesmo guia, mesmos documentos, sem o primeiro rotulo nem a camada."""
    p = portoes(etapa, autorizacao)
    if not p["ok"]:
        print(json.dumps({"ok": False, "bloqueado": "portoes fechados", "portoes": p}, ensure_ascii=False, indent=1))
        return EXIT_BLOQUEADO
    itens, man, meta = RO.carregar(etapa)
    csv_p = os.path.join(etapa, "..", "rotulos_etapa1_segunda.csv")
    feitos = {r["id"] for r in _ler_csv(csv_p)}
    saida = os.path.join(etapa, "etapa1_execucao_segunda")
    guia = RO.guia_v3()
    for iid in ids:
        if iid in feitos:
            continue
        r = RO.rotular(itens[iid], man[iid], meta, docs_dir, saida, provider="codex", dry_run=dry_run, guia=guia)
        if dry_run:
            print(json.dumps({"id": iid, "dry_run": True, "argv0": (r.get("codex_argv") or ["?"])[0]}))
            continue
        rot = r.get("rotulo") or {}
        orig = rot.get("origem") or {}
        _acrescentar(csv_p, COLUNAS_SEGUNDA, {"id": iid, "classe2": rot.get("classe"), "data_evento2": rot.get("data_evento") or "",
                                             "protocolo": rot.get("protocolo_evento") or orig.get("protocolo") or "",
                                             "trecho": rot.get("trecho_evento") or orig.get("trecho") or "", "tipo": rot.get("tipo") or "",
                                             "origem_json": json.dumps(orig, ensure_ascii=False), "adicionais_json": json.dumps(rot.get("adicionais") or [], ensure_ascii=False),
                                             "motivo_incerto": rot.get("motivo_incerto") or "", "status": r.get("status"),
                                             "falhas_trecho": " | ".join(r.get("falhas_trecho") or []), "provider": "codex", "modelo": r.get("modelo"),
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
        p = portoes(argv[1])
        print(json.dumps(p, ensure_ascii=False, indent=1))
        return 0 if p["ok"] else EXIT_BLOQUEADO
    if argv[0] == "rodar":
        return rodar(argv[1], argv[2], teto_tokens=int(opt("--teto-tokens", 2_000_000)), max_itens=int(opt("--max-itens", 0)) or None, dry_run="--dry-run" in argv)
    ids = [x.strip() for x in open(opt("--ids"), encoding="utf-8-sig").read().replace("\n", ",").split(",") if x.strip()]
    return segunda(argv[1], argv[2], ids, dry_run="--dry-run" in argv)


if __name__ == "__main__":
    sys.exit(main())
