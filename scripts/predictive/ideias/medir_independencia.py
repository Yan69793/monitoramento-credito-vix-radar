"""Dia 1, portao 3: independencia dos episodios. Mede concentracao de datas, tags e pares de contagio mecanico."""
import collections
import json
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import EVENTOS_CREDITO, SAIDA, digitos, emissores, gravar_json, pdata  # noqa: E402

import dados  # noqa: E402
import eventos as ev2  # noqa: E402


def main():
    mapa = emissores()
    por = {c: e for e, c in mapa.items()}
    evs, tags_por = [], {}
    with open(EVENTOS_CREDITO, encoding="utf-8") as fh:
        for linha in fh:
            r = json.loads(linha)
            if (r.get("classificacao") or "").upper() != "CRITICO":
                continue
            c, d = mapa.get(r.get("empresa")), pdata(r.get("data_evento"))
            if c and d:
                evs.append({"cnpj": c, "data": d, "tipo": r.get("titulo", "")})
                tags_por.setdefault((c, d), set()).update(t for t in (r.get("tags") or []) if t)
    docs, _ = dados.ler_ipe()
    alvo = set(mapa.values())
    dp = collections.defaultdict(list)
    for d in docs:
        c = digitos(d["cnpj"])
        if c in alvo:
            dp[c].append(d)
    eps = [e for e in ev2.marcar_prevalencia(ev2.episodios(evs), dp) if not e["prevalente"]]
    for e in eps:
        tg = set()
        for x in e["eventos"]:
            tg |= tags_por.get((x["cnpj"], x["data"]), set())
        e["tags"] = sorted(tg)
    sever = {"recuperacao-judicial-extrajudicial", "fato-relevante-severo", "default", "waiver", "covenant", "downgrade", "inadimplencia", "cross-default", "reestruturacao"}
    por_dia = collections.Counter(e["inicio"] for e in eps)
    por_tag = collections.Counter(t for e in eps for t in e["tags"])
    desde = [e for e in eps if e["inicio"] >= date(2025, 10, 1)]
    dia_pico = por_dia.most_common(6)
    gr = collections.Counter(e["inicio"].isocalendar()[:2] for e in desde)
    res = {"episodios_incidentes_total": len(eps), "desde_2025_10": len(desde),
           "tags_top": por_tag.most_common(12),
           "datas_com_mais_episodios": [(str(d), n) for d, n in dia_pico],
           "semanas_iso_desde_2025_10": sorted((f"{a}-W{b:02d}", n) for (a, b), n in gr.items()),
           "desde_2025_10_com_tag_severa": [(por[e["cnpj"]], str(e["inicio"]), e["tags"][:3]) for e in desde if sever & set(e["tags"])],
           "desde_2025_10_sem_tag_severa": len([e for e in desde if not (sever & set(e["tags"]))])}
    gravar_json(os.path.join(SAIDA, "dia1", "independencia_dia1.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
