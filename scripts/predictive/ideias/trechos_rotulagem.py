"""Busca ampla e independente do extrator: trechos com EBITDA e um numero decimal proximos, para rotulagem manual.
Uso: python -I trechos_rotulagem.py <emissor> [<emissor> ...]"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA  # noqa: E402

RX = re.compile(r"ebitda", re.I)
RX_NUM = re.compile(r"\b\d{1,2},\d{1,2}\s*(x|vezes|\()|\b\d{1,2}\s*\(\w+\)\s*vez", re.I)


def main(emps):
    prov = [json.loads(l) for l in open(os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl"), encoding="utf-8")]
    for emp in emps:
        esc = [p for p in prov if p["emissor"] == emp and p["papel"] == "escritura"]
        if not esc or not esc[-1].get("arquivo_txt"):
            print("#### %s: sem texto" % emp)
            continue
        t = re.sub(r"\s+", " ", open(esc[-1]["arquivo_txt"], encoding="utf-8", errors="ignore").read())
        hits, ult = [], -10 ** 9
        for m in RX.finditer(t):
            jan = t[max(0, m.start() - 250):m.end() + 250]
            if RX_NUM.search(jan) and m.start() - ult > 500:
                hits.append(jan)
                ult = m.start()
        print("#### %s | EBITDA=%d | trechos=%d" % (emp, len(RX.findall(t)), len(hits)))
        for h in hits[:3]:
            print("  > " + h[:500])


if __name__ == "__main__":
    main(sys.argv[1:])
