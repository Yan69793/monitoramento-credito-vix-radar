import collections
import gzip
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import HISTORICO  # noqa: E402

p = os.path.join(HISTORICO, "2026-10-11", "series_full.json.gz")
d = json.load(gzip.open(p, "rt", encoding="utf-8"))
chaves = collections.Counter()
por_mes = collections.defaultdict(collections.Counter)
dif = 0
tot = 0
for emp, regs in d.items():
    for r in regs:
        if r.get("fonte") != "anbima_publico":
            continue
        tot += 1
        chaves[tuple(sorted(k for k in r if r[k] is not None))] += 1
        por_mes[r["data"][:7]]["taxa" if r.get("taxa_indicativa_pct") is not None else "so_spread_bps" if r.get("spread_bps") is not None else "nenhum"] += 1
        if r.get("taxa_indicativa_pct") is not None and r.get("spread_bps") is not None and r["taxa_indicativa_pct"] != r["spread_bps"]:
            dif += 1
print("total", tot, "taxa!=spread_bps", dif)
for k, v in chaves.most_common(4):
    print(v, k)
for m in sorted(por_mes):
    print(m, dict(por_mes[m]))
exemplo = [r for r in d["Oi"] if r.get("fonte") == "anbima_publico"][-1:] + [r for r in d["Oi"] if r.get("fonte") == "anbima_publico"][:1]
print(json.dumps(exemplo, ensure_ascii=False)[:700])
