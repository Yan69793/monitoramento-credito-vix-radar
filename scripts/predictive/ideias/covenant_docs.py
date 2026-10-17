"""Dia 4: seleciona por regra e baixa escritura e relatorio de agente fiduciario (mesma emissao) do RAD.

Regra de amostra (criterios congelados): menor Z de Altman (fundamentals_altman_latest.json) entre os emissores
com escritura original e relatorio do agente da MESMA emissao no IPE. Reusa baixar/tipo_por_magia/extrair_texto
de validacao/baixar_etapa1.py. Proveniencia: uma linha JSON por documento (protocolo, link, Data_Entrega, sha256).
"""
import collections
import datetime as dt
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, REPO, SAIDA, digitos, emissores  # noqa: E402

sys.path.insert(0, os.path.join(REPO, "scripts", "predictive", "validacao"))
import baixar_etapa1 as B  # noqa: E402
import dados  # noqa: E402
from listar_escrituras import classificar  # noqa: E402

PASTA = os.path.join(RAW, "covenant")
ALTMAN = os.path.join(REPO, "scripts", "predictive", "fundamentals_altman_latest.json")
RX_EMISSAO = re.compile(r"(\d{1,2})\s*\S{0,3}\s*(?:\([a-z]+\)\s*)?(?:serie\s+da\s+\d+\S{0,3}\s+)?emissao")
N_AMOSTRA = 8


def numero_emissao(assunto):
    m = RX_EMISSAO.search(assunto or "")
    return int(m.group(1)) if m else None


def pares(limite=N_AMOSTRA):
    mapa = emissores()
    por = {c: e for e, c in mapa.items()}
    with open(ALTMAN, encoding="utf-8") as fh:
        alt = json.load(fh)["empresas"]
    z = {por.get(digitos(v.get("cnpj"))): v.get("z_em") for v in alt.values()}
    docs, _ = dados.ler_ipe()
    inv = collections.defaultdict(lambda: collections.defaultdict(list))
    for d in docs:
        c = digitos(d["cnpj"])
        k = classificar(d) if c in por else None
        if k in ("escritura", "relatorio_af"):
            inv[por[c]][k].append(d)
    out = []
    for emp in sorted(inv, key=lambda e: (z.get(e) is None, z.get(e) if z.get(e) is not None else 0)):
        esc = {numero_emissao(d["assunto_n"]): d for d in sorted(inv[emp]["escritura"], key=lambda d: d["data"])}
        afs = sorted(inv[emp]["relatorio_af"], key=lambda d: d["data"], reverse=True)
        for af in afs:
            n = numero_emissao(af["assunto_n"])
            if n and n in esc:
                out.append({"emissor": emp, "z_em": z.get(emp), "emissao": n, "escritura": esc[n], "relatorio_af": af})
                break
        if limite and len(out) >= limite:
            break
    return out


def complementar(extra=2):
    """Emenda declarada no Dia 4: o relatorio da Vortx remete ao site e nao traz tabela no IPE. Completa a amostra
    ate 10 com os proximos emissores na mesma ordem de Z de Altman cujo relatorio do agente tem 'Apurado=' no texto."""
    prov_path = os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl")
    ja = {json.loads(l)["emissor"] for l in open(prov_path, encoding="utf-8")}
    novos = []
    for p in pares(limite=None):
        if p["emissor"] in ja:
            continue
        af = baixar_doc(p["relatorio_af"], "relatorio_af")
        if not af.get("arquivo_txt") or "Apurado=" not in open(af["arquivo_txt"], encoding="utf-8", errors="ignore").read():
            continue
        esc = baixar_doc(p["escritura"], "escritura")
        for r in (esc, af):
            r.update({"emissor": p["emissor"], "emissao": p["emissao"], "z_em": p["z_em"], "selecao": "complemento_dia4_tabela_af"})
            novos.append(r)
        if len(novos) >= 2 * extra:
            break
    with open(prov_path, "a", encoding="utf-8", newline="\n") as fh:
        for r in novos:
            fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
    for r in novos:
        print(r["emissor"], r["emissao"], r["papel"], r["data_entrega"], r["http"], r["tipo"], r["bytes"], r["texto"])


def baixar_doc(d, papel):
    os.makedirs(os.path.join(PASTA, "DOCS"), exist_ok=True)
    os.makedirs(os.path.join(PASTA, "TXT"), exist_ok=True)
    base = re.sub(r"[^0-9A-Za-z_-]", "_", d["protocolo"])
    bruto = os.path.join(PASTA, "DOCS", base + ".bin")
    if not os.path.exists(bruto):
        http, nome, rc = B.baixar(d["link"], bruto)
    else:
        http, nome, rc = 200, None, 0
    b = open(bruto, "rb").read() if os.path.exists(bruto) else b""
    tipo = B.tipo_por_magia(b)
    txt = os.path.join(PASTA, "TXT", base + ".txt")
    st = B.extrair_texto(bruto, tipo, txt) if tipo in ("pdf", "docx", "doc") else "nao_extraido"
    return {"papel": papel, "protocolo": d["protocolo"], "link": d["link"], "data_entrega": str(d["data"]), "assunto": d["assunto_n"],
            "http": http, "tipo": tipo, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest(), "texto": st,
            "arquivo_txt": txt if st == "ok" else None, "baixado_em_utc": dt.datetime.utcnow().isoformat(timespec="seconds")}


def main():
    sel = pares()
    prov = []
    for p in sel:
        for papel in ("escritura", "relatorio_af"):
            r = baixar_doc(p[papel], papel)
            r.update({"emissor": p["emissor"], "emissao": p["emissao"], "z_em": p["z_em"]})
            prov.append(r)
    os.makedirs(os.path.join(SAIDA, "dia4"), exist_ok=True)
    with open(os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        for r in prov:
            fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
    for r in prov:
        print(r["emissor"], r["emissao"], r["papel"], r["data_entrega"], r["http"], r["tipo"], r["bytes"], r["texto"])


def ampliar(com_tabela=10, sem_tabela=4):
    """Amplia a amostra na ordem de Z de Altman, sem escolher pelo resultado. Separa quem tem tabela 'Apurado=' no relatorio do agente
    (comparavel) de quem nao tem (so extracao e margem). Pula emissores ja baixados."""
    prov_path = os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl")
    ja = {json.loads(l)["emissor"] for l in open(prov_path, encoding="utf-8")}
    n_com = n_sem = 0
    novos = []
    for p in pares(limite=None):
        if p["emissor"] in ja or (n_com >= com_tabela and n_sem >= sem_tabela):
            continue
        af = baixar_doc(p["relatorio_af"], "relatorio_af")
        tem = bool(af.get("arquivo_txt")) and "Apurado=" in open(af["arquivo_txt"], encoding="utf-8", errors="ignore").read()
        if (tem and n_com >= com_tabela) or (not tem and n_sem >= sem_tabela):
            continue
        esc = baixar_doc(p["escritura"], "escritura")
        if not esc.get("arquivo_txt"):
            continue
        n_com, n_sem = n_com + tem, n_sem + (not tem)
        for r in (esc, af):
            r.update({"emissor": p["emissor"], "emissao": p["emissao"], "z_em": p["z_em"], "selecao": "ampliacao_dia6", "af_com_tabela": tem})
            novos.append(r)
    with open(prov_path, "a", encoding="utf-8", newline="\n") as fh:
        for r in novos:
            fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
    for r in novos:
        print(r["emissor"], r["emissao"], r["papel"], r["data_entrega"], r["tipo"], r["texto"], "tabela" if r["af_com_tabela"] else "sem tabela")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--ampliar":
        ampliar()
    elif len(sys.argv) > 1 and sys.argv[1] == "--complementar":
        complementar()
    else:
        main()
