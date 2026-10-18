"""Baixa do RAD da CVM (leitura publica, sem login, sem CAPTCHA) os documentos do manifesto da etapa 1.

Integridade: PDF so vale com '%PDF-' no inicio e '%%EOF' no fim; Word antigo pela assinatura OLE; docx/zip
por 'PK'. Resposta HTML, vazia ou com 'captcha' e falha, nunca contornada: o documento fica 'inacessivel'.
Proveniencia: uma linha JSON por tentativa final em proveniencia_downloads.jsonl (so acrescenta), com
protocolo, URL, data/hora UTC do download, bytes, sha256, tipo, nome do anexo e status HTTP. O original fica
intacto em DOCS/<protocolo>.<ext>; o texto extraido vai para TXT/<protocolo>.txt (pdftotext -layout, docx,
ou texto do binario OLE), sem tocar no original.

Uso:
  python -I baixar_etapa1.py ETAPA_DIR DOCS_DIR [--itens i0001-i0020] [--protocolos 1515448,581005] [--pausa 0.25]
                             [--so-dia]   # so os documentos do dia do candidato, sem o contexto de 180 dias
"""
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import time

BASE = "https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?Tela=ext&descTipo=IPE&CodigoInstituicao=1"


def tipo_por_magia(b):
    if b[:5] == b"%PDF-":
        return "pdf" if b"%%EOF" in b[-2048:] else "pdf_truncado"
    if b[:8] == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        return "doc"
    if b[:2] == b"PK":
        return "docx"
    if b"captcha" in b[:20000].lower():
        return "captcha"
    if b[:1] == b"<" or b[:15].lower().startswith(b"<!doctype"):
        return "html"
    return "desconhecido" if b else "vazio"


def extrair_texto(caminho, tipo, destino):
    try:
        if tipo == "pdf":
            subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", caminho, destino], timeout=120,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif tipo == "docx":
            import docx
            d = docx.Document(caminho)
            open(destino, "w", encoding="utf-8").write("\n".join(p.text for p in d.paragraphs))
        elif tipo == "doc":
            import olefile
            ole = olefile.OleFileIO(caminho)
            raw = ole.openstream("WordDocument").read() if ole.exists("WordDocument") else open(caminho, "rb").read()
            u16 = re.findall(rb"(?:[\x20-\x7e\xc0-\xff]\x00){4,}", raw)
            txt = "\n".join(s.decode("utf-16le", "ignore") for s in u16)
            if len(txt) < 200:
                txt = "\n".join(s.decode("latin-1") for s in re.findall(rb"[\x20-\x7e\xc0-\xff]{6,}", raw))
            open(destino, "w", encoding="utf-8").write(txt)
    except Exception as e:  # noqa: BLE001
        return "erro_extracao: %s" % type(e).__name__
    if not os.path.exists(destino):
        return "sem_texto"
    n = len(open(destino, encoding="utf-8", errors="ignore").read().strip())
    return "ok" if n >= 80 else "sem_texto"


def baixar(url, saida):
    r = subprocess.run(["curl.exe" if os.name == "nt" else "curl", "-s", "--compressed", "--http1.1", "--max-time", "120", "-D", "-", "-o", saida,
                        "-w", "\n__HTTP=%{http_code}", url], capture_output=True, timeout=180)
    out = r.stdout.decode("latin-1", "ignore")
    m = re.search(r"__HTTP=(\d+)", out)
    fn = re.search(r"filename=([^\r\n;]+)", out, re.I)
    return (int(m.group(1)) if m else None), (fn.group(1).strip() if fn else None), r.returncode


def ja_baixados(prov):
    feitos = {}
    if os.path.exists(prov):
        for ln in open(prov, encoding="utf-8"):
            try:
                j = json.loads(ln)
                feitos[j["protocolo_rad"]] = j
            except Exception:  # noqa: BLE001
                pass
    return feitos


def alvos(etapa, itens_faixa, protocolos, so_dia=False):
    docs = {d["protocolo_rad"]: d for d in json.load(open(os.path.join(etapa, "manifesto_documentos.json"), encoding="utf-8"))}
    if protocolos:
        extra_f = os.path.join(etapa, "manifesto_extra_ressalvas.json")
        if os.path.exists(extra_f):
            docs.update({d["protocolo_rad"]: d for d in json.load(open(extra_f, encoding="utf-8"))})
        return [docs.get(p, {"protocolo_rad": p, "link": None}) for p in protocolos]
    man = json.load(open(os.path.join(etapa, "manifesto_itens.json"), encoding="utf-8"))
    if itens_faixa:
        a, b = itens_faixa.split("-")
        man = [m for m in man if a <= m["id"] <= b]
    man.sort(key=lambda m: m["id"])
    ordem, vistos = [], set()
    for m in man:
        for p in (m["dia"] if so_dia else m["dia"] + m["contexto_180d"]):
            if p not in vistos:
                vistos.add(p)
                ordem.append(docs[p])
    return ordem


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        print(__doc__)
        return 2
    etapa, dd = argv[0], argv[1]

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    pausa = float(opt("--pausa", "0.25"))
    prots = opt("--protocolos")
    lista = alvos(etapa, opt("--itens"), prots.split(",") if prots else None, "--so-dia" in argv)
    os.makedirs(os.path.join(dd, "DOCS"), exist_ok=True)
    os.makedirs(os.path.join(dd, "TXT"), exist_ok=True)
    prov = os.path.join(etapa, "proveniencia_downloads.jsonl")
    feitos = ja_baixados(prov)
    cont = {"ok": 0, "pulado": 0, "falha": 0}
    for d in lista:
        p = d["protocolo_rad"]
        if p in feitos and feitos[p]["status"] in ("ok", "ok_sem_texto"):
            cont["pulado"] += 1
            continue
        url = d.get("link")
        if not url:
            cont["falha"] += 1
            continue
        tmp = os.path.join(dd, "DOCS", "%s.part" % p)
        reg = None
        for tent in range(1, 4):
            http, nome, rc = baixar(url, tmp)
            b = open(tmp, "rb").read() if os.path.exists(tmp) else b""
            tp = tipo_por_magia(b)
            if http == 200 and tp in ("pdf", "doc", "docx"):
                final = os.path.join(dd, "DOCS", "%s.%s" % (p, tp))
                os.replace(tmp, final)
                txt = os.path.join(dd, "TXT", "%s.txt" % p)
                st = extrair_texto(final, tp, txt)
                reg = {"protocolo_rad": p, "url": url, "status": "ok" if st == "ok" else "ok_sem_texto",
                       "texto": st, "tipo": tp, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest(),
                       "anexo": nome, "http": http, "tentativas": tent}
                break
            reg = {"protocolo_rad": p, "url": url, "status": "inacessivel", "tipo": tp, "bytes": len(b),
                   "http": http, "curl_rc": rc, "tentativas": tent}
            if tp == "captcha":
                break  # nunca contornar
            time.sleep(2 * tent)
        if os.path.exists(tmp):
            os.remove(tmp)
        reg.update({"cnpj": d.get("cnpj"), "data_entrega": d.get("data_entrega"),
                    "baixado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
        with open(prov, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(reg, ensure_ascii=False) + "\n")
        cont["ok" if reg["status"].startswith("ok") else "falha"] += 1
        time.sleep(pausa)
    print(json.dumps({"alvos": len(lista), **cont}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
