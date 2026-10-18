"""Valida o detector de eventos da conferencia (conferencia_eventos.py) contra rotulos.

Duas validacoes, ambas offline (textos ja extraidos; nenhum download):
  rotulos   roda o MESMO caminho do detector (comunicados ao mercado + gatilho forte no metadado + regras locais) sobre
            cada item rotulado do G0-v4 (1.261) e compara com a classe final. Dia material = classe final evento_proprio
            ou continuacao (ato proprio de credito no dia). Os rotulos finais passaram por revisor e adjudicador (Luna),
            entao NAO sao independentes das regras: medem regras isoladas contra regras mais revisao.
  amostra   compara com o CSV de rotulos cegos de 2026 (lidos por outro leitor sem ver a classe das regras) e avalia no
            nivel de EPISODIO, que e o que a conferencia usa (episodio de 30 dias, prevalencia por categoria A em 730 dias
            e por episodio anterior em 365 dias).

Saida: JSON com contagens, precisao e revocacao com IC95 de Wilson, e a lista de erros.

Uso:
  python -I validar_detector.py rotulos [--de AAAA-MM-DD] [--ate AAAA-MM-DD] [--saida ARQ.json]
  python -I validar_detector.py amostra --csv ARQ.csv [--saida ARQ.json]
"""
import argparse
import csv
import datetime as dt
import json
import math
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import conferencia as C  # noqa: E402
import conferencia_eventos as CE  # noqa: E402
import dados as D  # noqa: E402
import eventos as EV  # noqa: E402

RG = CE.RG


def wilson(k, n, z=1.96):
    if n == 0:
        return [None, None]
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(max(0.0, c - h), 3), round(min(1.0, c + h), 3)]


def metricas(tp, fp, fn):
    det, ver = tp + fp, tp + fn
    return {"detectados": det, "verdadeiros": ver, "acertos": tp, "falsos_positivos": fp, "perdidos": fn,
            "precisao": None if not det else round(tp / det, 3), "precisao_ic95": wilson(tp, det),
            "revocacao": None if not ver else round(tp / ver, 3), "revocacao_ic95": wilson(tp, ver)}


def carregar():
    docs, _ = D.ler_ipe()
    docs_por = {}
    for d in docs:
        docs_por.setdefault(d["cnpj"], []).append(d)
    for v in docs_por.values():
        v.sort(key=lambda x: x["data"])
    return docs, docs_por


def prever(cnpj, dia, docs_por, textos):
    """Mesmo caminho do detector: (previsao, classe). previsao em {material, nao_material, pendente, fora_do_alcance, sem_texto}."""
    lst = docs_por.get(cnpj, [])
    do_dia = [d for d in lst if d["data"] == dia and d["cat_n"] in CE.CATS_EVENTO]
    if not do_dia:
        return "fora_do_alcance", "sem comunicado ao mercado no dia"
    if not any(RG.RX_META_FORTE.search(CE.meta_texto(d)) for d in do_dia):
        return "fora_do_alcance", "comunicado sem gatilho forte no metadado"
    item, man, meta, baixar = CE.montar(cnpj, dia, docs_por, textos)
    if any(textos.ler(CE.pid(d)) is None for d in baixar if CE.pid(d) in man["dia"]):
        return "sem_texto", "texto do dia nao disponivel localmente"
    reg = RG.classificar(item, man, meta, textos.ler)
    c = reg["classe"]
    if c in CE.CLASSES_MATERIAIS:
        return "material", c
    if c == "PENDENTE_REVISAO":
        return "pendente", reg.get("caminho") or ""
    return "nao_material", c


def rotulos(de, ate, saida):
    rot = EV.ler_rotulos(CE.ROTULOS)
    _, docs_por = carregar()
    textos = CE.Textos(CE.DOCS_DIR, False, dt.date.today())
    sel = [r for r in rot if de.isoformat() <= r["data"] <= ate.isoformat()]
    linhas = []
    for i, r in enumerate(sel):
        cnpj, dia = r["cnpj"].strip(), dt.date.fromisoformat(r["data"])
        verdade = (r.get("classe_final") or "") in ("evento_proprio", "continuacao")
        prev, classe = prever(cnpj, dia, docs_por, textos)
        linhas.append({"id": r["id"], "cnpj": cnpj, "data": r["data"], "verdade": verdade, "classe_final": r.get("classe_final"),
                       "previsao": prev, "classe_regras": classe, "fonte_rotulo": r.get("fonte")})
        if (i + 1) % 100 == 0:
            print("%d/%d" % (i + 1, len(sel)), file=sys.stderr, flush=True)
    tp = sum(1 for l in linhas if l["verdade"] and l["previsao"] == "material")
    fp = sum(1 for l in linhas if not l["verdade"] and l["previsao"] == "material")
    fn = sum(1 for l in linhas if l["verdade"] and l["previsao"] != "material")
    perdidos = {}
    for l in linhas:
        if l["verdade"] and l["previsao"] != "material":
            perdidos[l["previsao"]] = perdidos.get(l["previsao"], 0) + 1
    res = {"janela": [de.isoformat(), ate.isoformat()], "itens": len(linhas), "definicao": "dia material = evento_proprio ou continuacao",
           "dia": metricas(tp, fp, fn), "perdidos_por_causa": perdidos,
           "falsos_positivos": [l for l in linhas if not l["verdade"] and l["previsao"] == "material"],
           "perdidos": [l for l in linhas if l["verdade"] and l["previsao"] != "material"]}
    if saida:
        with open(saida, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
    return res


def episodios_nao_prevalentes(dias, docs_por):
    """[(cnpj, data)] -> inicios de episodio sem categoria A em 730 dias e sem episodio anterior em 365 dias."""
    cata = {}
    for c, lst in docs_por.items():
        for d in lst:
            if EV.RX_CAT_A.search(d["cat_n"]):
                cata.setdefault(c, []).append(d["data"])
    eps = C.episodios_de_eventos([{"cnpj": c, "data": d} for c, d in dias])
    out = []
    for e in eps:
        if any(e["inicio"] - dt.timedelta(days=CE.CAT_A_DIAS) <= x < e["inicio"] for x in cata.get(e["cnpj"], [])):
            continue
        if any(o["cnpj"] == e["cnpj"] and o is not e and 0 < (e["inicio"] - o["ultimo"]).days <= C.PREVALENCIA_DIAS for o in eps):
            continue
        out.append((e["cnpj"], e["inicio"].isoformat()))
    return out


def amostra(caminho, saida):
    _, docs_por = carregar()
    with open(caminho, encoding="utf-8") as fh:
        rot = list(csv.DictReader(fh, delimiter=";"))
    de = min(r["data"] for r in rot)
    ate = max(r["data"] for r in rot)
    cache = CE.ler_cache()
    sha = CE.sha_regras()
    pred = {}
    for r in cache.values():
        if r.get("deteccao") == CE.DETECCAO_V:
            pred[(r["cnpj"], r["data"])] = r
    det_todos = [(c, dt.date.fromisoformat(d)) for (c, d), p in pred.items() if p["classe"] in CE.CLASSES_MATERIAIS]
    det = [x for x in det_todos if de <= x[1].isoformat() <= ate]
    aquecimento = [x for x in det_todos if x[1].isoformat() < de]     # dias materiais anteriores a janela: so contexto de prevalencia
    ver = [(r["cnpj"], dt.date.fromisoformat(r["data"])) for r in rot if r["rotulo"] in ("E", "C")]
    sd, sv = set(det), set(ver)

    def na_janela(eps):
        return {e for e in eps if de <= e[1] <= ate}
    ed = na_janela(episodios_nao_prevalentes(det + aquecimento, docs_por))
    ev = na_janela(episodios_nao_prevalentes(ver + aquecimento, docs_por))
    res = {"janela": [de, ate], "dias_candidatos": len(rot), "dias_de_aquecimento": len(aquecimento), "sha_regras": sha,
           "dia": metricas(len(sd & sv), len(sd - sv), len(sv - sd)),
           "episodio": metricas(len(ed & ev), len(ed - ev), len(ev - ed)),
           "episodios_verdadeiros": sorted(ev), "episodios_detectados": sorted(ed),
           "episodios_falsos": sorted(ed - ev), "episodios_perdidos": sorted(ev - ed)}
    if saida:
        with open(saida, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
    return res


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rotulos")
    r.add_argument("--de", default="2011-01-01")
    r.add_argument("--ate", default="2026-09-30")
    r.add_argument("--saida")
    m = sub.add_parser("amostra")
    m.add_argument("--csv", required=True)
    m.add_argument("--saida")
    a = ap.parse_args(argv)
    if a.cmd == "rotulos":
        res = rotulos(dt.date.fromisoformat(a.de), dt.date.fromisoformat(a.ate), a.saida)
        print(json.dumps({k: v for k, v in res.items() if k not in ("falsos_positivos", "perdidos")}, ensure_ascii=False, indent=1))
    else:
        print(json.dumps(amostra(a.csv, a.saida), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
