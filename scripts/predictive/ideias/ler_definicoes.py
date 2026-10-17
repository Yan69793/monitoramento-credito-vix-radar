"""Mostra, com numero de linha, as definicoes contratuais (Divida Liquida, EBITDA, Despesa/Resultado Financeiro) de uma escritura.
Uso: python -I ler_definicoes.py <emissor>"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import SAIDA  # noqa: E402

RX = re.compile(r"^.{0,12}[\"“”']?\s*(D.vida\s+(Financeira\s+)?L.quida|EBITDA|Despesas?\s+(Financeira|L.quida)|Resultado\s+Financeiro)[^\n]{0,40}[\"“”']?\s*(significa|signif|corresponde|ser.\s+o|ser.\s+a|:|tem\s+o\s+significado)", re.I)


def main(emp):
    prov = [json.loads(l) for l in open(os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl"), encoding="utf-8")]
    esc = [p for p in prov if p["emissor"] == emp and p["papel"] == "escritura"][0]
    linhas = open(esc["arquivo_txt"], encoding="utf-8", errors="ignore").read().replace("\r", "").split("\n")
    amplo = re.compile(r"(d.vida\s+(financeira\s+|total\s+|bruta\s+)?(l.quida|consolidada)?|ebitda|despesas?\s+financeiras?)[^\n]{0,60}(significa|signif|entende-se|corresponde|definid|:|=)", re.I)
    vistos = 0
    for i, ln in enumerate(linhas):
        if RX.search(ln) or amplo.search(ln) or re.search(r"(significa|entende-se por|definido como).{0,80}(d.vida l.quida|ebitda|despesa financeira)", ln, re.I):
            bloco = " ".join(x.strip() for x in linhas[i:i + 14])
            if vistos < 6:
                print("L%d: %s\n" % (i + 1, re.sub(r"\s+", " ", bloco)[:int(os.environ.get("LIM", "1400"))]))
            vistos += 1


if __name__ == "__main__":
    main(sys.argv[1])
