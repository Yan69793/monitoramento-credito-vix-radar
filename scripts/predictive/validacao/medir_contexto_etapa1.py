"""Somente leitura. Mede a composicao do contexto de 180 dias da etapa 1 por categoria IPE e estima o custo
de cada desenho de recuperacao. Texto medido nos documentos ja baixados; documento nao baixado usa a media
da propria categoria (estimativa declarada). Saida JSON em stdout.
"""
import json
import os
import sys
from collections import Counter, defaultdict
from statistics import mean, median

ETAPA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "data", "validacao", "etapa1_g0v2")
TXT = r"E:\Diretorio\Claude\tmp\operacional\vix-radar\ews-etapa1\TXT"
CH_POR_TOKEN = 3.6
GUIA_CH = 30958


def main():
    man = json.load(open(os.path.join(ETAPA, "manifesto_itens.json"), encoding="utf-8"))
    meta = {d["protocolo_rad"]: d for d in json.load(open(os.path.join(ETAPA, "manifesto_documentos.json"), encoding="utf-8"))}
    tam = {}
    for p in meta:
        f = os.path.join(TXT, "%s.txt" % p)
        if os.path.exists(f):
            tam[p] = len(open(f, encoding="utf-8", errors="ignore").read())
    por_cat = defaultdict(list)
    for p, n in tam.items():
        por_cat[meta[p]["categoria"]].append(n)
    media_cat = {c: mean(v) for c, v in por_cat.items()}
    media_geral = mean(tam.values()) if tam else 0

    def ch(p):
        return tam.get(p, media_cat.get(meta[p]["categoria"], media_geral))

    leituras = Counter()
    ch_cat = Counter()
    for m in man:
        for p in m["contexto_180d"]:
            c = meta[p]["categoria"]
            leituras[c] += 1
            ch_cat[c] += ch(p)
    tot_ch = sum(ch_cat.values())
    linhas = []
    for c, n in leituras.most_common():
        linhas.append({"categoria": c, "leituras": n, "pct_leituras": round(100 * n / sum(leituras.values()), 1),
                       "pct_texto": round(100 * ch_cat[c] / tot_ch, 1), "media_ch_medida": int(media_cat.get(c, 0)),
                       "docs_medidos": len(por_cat.get(c, []))})
    dia_ch = [sum(ch(p) for p in m["dia"]) for m in man]
    idx_ch = [sum(90 + len(x["assunto"] or "") for x in m["indice_24m"]) + sum(90 + len(meta[p]["assunto"] or "") for p in m["contexto_180d"]) for m in man]
    base = [GUIA_CH + a + b for a, b in zip(dia_ch, idx_ch)]
    out = {
        "itens": len(man), "docs_texto_medido": len(tam), "estimativa": "documento nao baixado = media da categoria",
        "contexto_por_categoria": linhas,
        "tokens_literal_media": int(mean(b + sum(ch(p) for p in m["contexto_180d"]) for b, m in zip(base, man)) / CH_POR_TOKEN),
        "tokens_nivel0_media": int(mean(base) / CH_POR_TOKEN),
        "tokens_nivel0_mediana": int(median(base) / CH_POR_TOKEN),
        "tokens_nivel0_max": int(max(base) / CH_POR_TOKEN),
        "nivel0": "guia + texto integral do dia + indice integral (180 dias e 24 meses, so metadados)",
    }
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    sys.exit(main())
