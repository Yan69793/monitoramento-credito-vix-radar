"""PoC 6 (Dia 4): diff de notas explicativas entre dois ITR do mesmo emissor.

Texto: PDF completo do documento ITR no RAD (notas_docs.py). Notas separadas pelo titulo numerado; numeros mascarados
para que a troca de saldo trimestral nao conte como mudanca. Mudanca = frase nova ou removida dentro da mesma nota.
Sinal = frase nova com termo de credito ou contabil (lista fixa abaixo). Benchmark: H2b (reapresentacao, VERSAO>=2)
e H4 (troca de CFO/DRI) do ews2/features.py, que olham so metadado.
"""
import csv
import io
import json
import os
import re
import sys
import unicodedata
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, SAIDA, digitos, emissores, gravar_json  # noqa: E402
import notas_docs as ND  # noqa: E402

TERMOS = r"covenant|clausulas? restritiva|indice financeiro|vencimento antecipado|waiver|anuencia|renuncia previa|continuidade operacional|" \
         r"incerteza relevante|reclassifica|reapresenta|mudanca de (politica|estimativa)|risco sacado|fornecedores? convenio|cessao de credito|" \
         r"recuperacao (judicial|extrajudicial)|repactua|reperfilamento|descumpr|inadimpl|cross.?default|garantia|aval|fianca|" \
         r"auditor|novo pronunciamento|impairment|reducao ao valor recuperavel"
RX_TERMOS = re.compile(TERMOS)
RX_TITULO = re.compile(r"^\s{0,6}(\d{1,2})\.\s{1,4}([A-ZÁÉÍÓÚÂÊÔÃÕÇ][A-Za-zÁÉÍÓÚÂÊÔÃÕÇáéíóúâêôãõç ,\-–/()]{3,90})\s*$", re.M)
RX_CABECALHO = re.compile(r"PÁGINA:\s*\d+\s*de\s*\d+|Notas Explicativas\s*$", re.M)
CASOS = [("Dasa", "2025-03-31", 1, "2025-03-31", 2, "reapresentacao v1 x v2"),
         ("Dasa", "2025-06-30", 1, "2025-09-30", 1, "trimestres consecutivos"),
         ("Simpar", "2025-06-30", 1, "2025-09-30", 1, "trimestres consecutivos"),
         ("Eneva", "2025-06-30", 1, "2025-09-30", 1, "trimestres consecutivos"),
         ("Movida", "2025-06-30", 1, "2025-09-30", 1, "trimestres consecutivos"),
         ("Pão de Açúcar (GPA)", "2025-09-30", 1, "2026-03-31", 1, "antes e depois da recuperacao extrajudicial (pula a DFP)")]


def norm(s):
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower()


def indice_itr():
    out = {}
    for ano in ("2025", "2026"):
        with zipfile.ZipFile(os.path.join(RAW, "itr", "itr_cia_aberta_%s.zip" % ano)) as z:
            for r in csv.DictReader(io.TextIOWrapper(z.open("itr_cia_aberta_%s.csv" % ano), encoding="latin-1"), delimiter=";"):
                out[(digitos(r["CNPJ_CIA"]), r["DT_REFER"], int(r["VERSAO"]))] = {"id_doc": r["ID_DOC"], "dt_receb": r["DT_RECEB"]}
    return out


def texto_itr(id_doc):
    ND.baixar_itr(id_doc)
    zp = os.path.join(ND.PASTA, "%s.zip" % id_doc)
    pdf = os.path.join(ND.PASTA, "%s_doc.pdf" % id_doc)
    with zipfile.ZipFile(zp) as z:
        nome = [n for n in z.namelist() if n.endswith(".pdf")][0]
        open(pdf, "wb").write(z.read(nome))
    txt = pdf + ".txt"
    if not os.path.exists(txt):
        import subprocess
        subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", pdf, txt], timeout=300, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t = open(txt, encoding="utf-8", errors="ignore").read()
    m = re.findall(r"PÁGINA:\s*(\d+)\s*de\s*(\d+)", t)
    completo = bool(m) and m[-1][0] == m[-1][1]
    return t, completo


def separar_notas(t):
    t = RX_CABECALHO.sub(" ", t)
    ini = norm(t).find("notas explicativas")
    corpo = t[ini:] if ini >= 0 else t
    tit = list(RX_TITULO.finditer(corpo))
    notas = {}
    for k, m in enumerate(tit):
        fim = tit[k + 1].start() if k + 1 < len(tit) else len(corpo)
        chave = re.sub(r"[^a-z ]", "", norm(m.group(2))).strip()[:60]
        if len(chave) < 4:
            continue
        notas.setdefault(chave, "")
        notas[chave] += corpo[m.end():fim]
    return notas


def frases(txt):
    txt = re.sub(r"\s+", " ", txt)
    out = set()
    for f in re.split(r"(?<=[.;:])\s+(?=[A-ZÁÉÍÓÚ(])", txt):
        f = f.strip()
        if len(f) < 60:
            continue
        g = re.sub(r"\d[\d.,]*", "#", norm(f))
        out.add((g, f))
    return out


def diff(a, b):
    na, nb = separar_notas(a), separar_notas(b)
    res = {"notas_a": len(na), "notas_b": len(nb), "novas_notas": sorted(set(nb) - set(na)), "notas_removidas": sorted(set(na) - set(nb)), "mudancas": []}
    for k in sorted(set(na) & set(nb)):
        fa, fb = frases(na[k]), frases(nb[k])
        ga, gb = {g for g, _ in fa}, {g for g, _ in fb}
        novas = [f for g, f in fb if g not in ga]
        rem = [f for g, f in fa if g not in gb]
        sinal = [f for f in novas if RX_TERMOS.search(norm(f))]
        if novas or rem:
            res["mudancas"].append({"nota": k, "frases_novas": len(novas), "frases_removidas": len(rem), "sinalizadas": sinal[:8]})
    for k in res["novas_notas"]:
        sinal = [f for _, f in frases(nb[k]) if RX_TERMOS.search(norm(f))]
        res["mudancas"].append({"nota": k, "nota_nova": True, "frases_novas": len(frases(nb[k])), "frases_removidas": 0, "sinalizadas": sinal[:8]})
    res["total_sinalizadas"] = sum(len(m["sinalizadas"]) for m in res["mudancas"])
    return res


def main():
    mapa = emissores()
    idx = indice_itr()
    saida = []
    for emp, ra, va, rb, vb, rot in CASOS:
        c = mapa[emp]
        da, db = idx.get((c, ra, va)), idx.get((c, rb, vb))
        if not da or not db:
            saida.append({"emissor": emp, "caso": rot, "status": "documento ausente no indice ITR"})
            continue
        ta, ca = texto_itr(da["id_doc"])
        tb, cb = texto_itr(db["id_doc"])
        d = diff(ta, tb)
        d.update({"emissor": emp, "caso": rot, "a": {"ref": ra, "versao": va, **da, "texto_completo": ca}, "b": {"ref": rb, "versao": vb, **db, "texto_completo": cb},
                  "benchmark_H2b_reapresentacao": vb >= 2})
        saida.append(d)
        print(emp, rot, "| notas", d["notas_a"], d["notas_b"], "| com mudanca", len(d["mudancas"]), "| sinalizadas", d["total_sinalizadas"],
              "| completo", ca, cb, "| novas", d["novas_notas"][:4])
    gravar_json(os.path.join(SAIDA, "dia4", "notas_diff_resultado.json"), saida)


if __name__ == "__main__":
    main()
