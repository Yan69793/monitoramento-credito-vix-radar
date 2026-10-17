"""Dia 4 (diff de notas): baixa o documento ITR/DFP completo do RAD (ZIP) e extrai o texto das notas explicativas.

Reusa baixar() de validacao/baixar_etapa1.py. Proveniencia: protocolo (ID_DOC), DT_REFER, VERSAO, DT_RECEB, sha256.
Uso: python -I notas_docs.py <ID_DOC> [<ID_DOC> ...]
"""
import hashlib
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, REPO  # noqa: E402

sys.path.insert(0, os.path.join(REPO, "scripts", "predictive", "validacao"))
import baixar_etapa1 as B  # noqa: E402

PASTA = os.path.join(RAW, "notas")
URL = "https://www.rad.cvm.gov.br/ENETCONSULTA/frmDownloadDocumento.aspx?CodigoInstituicao=1&NumeroSequencialDocumento=%s"


def baixar_itr(id_doc, tentativas=3):
    os.makedirs(PASTA, exist_ok=True)
    saida = os.path.join(PASTA, "%s.zip" % id_doc)
    for _ in range(tentativas):
        if os.path.exists(saida) and zipfile.is_zipfile(saida):
            break
        B.baixar(URL % id_doc, saida)
    ok = os.path.exists(saida) and zipfile.is_zipfile(saida)
    b = open(saida, "rb").read() if os.path.exists(saida) else b""
    conteudo = []
    if ok:
        with zipfile.ZipFile(saida) as z:
            conteudo = [(i.filename, i.file_size) for i in z.infolist()]
    return {"id_doc": id_doc, "zip_ok": ok, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest(), "conteudo": conteudo[:40]}


def anexos_pdf(id_doc):
    """Extrai os PDFs em base64 do XML do ITR (o PDF solto do ZIP vem truncado em 8 MiB). Devolve [(nome, tipo, txt)]."""
    import base64
    import re
    saida = os.path.join(PASTA, "%s.zip" % id_doc)
    out = []
    with zipfile.ZipFile(saida) as z:
        nome_xml = [n for n in z.namelist() if re.search(r"ITR|DFP", n) and n.endswith(".xml") and not n.startswith("Formulario")][0]
        x = z.read(nome_xml).decode("utf-8", "ignore")
    for k, bloco in enumerate(re.findall(r"<AnexosDocumento>(.*?)</AnexosDocumento>|<Documento>(.*?)</Documento>", x, re.S)):
        b = bloco[0] or bloco[1]
        pdf = re.search(r"<ImagemObjetoArquivoPdf>(.*?)</ImagemObjetoArquivoPdf>", b, re.S)
        if not pdf:
            continue
        nome = (re.search(r"<NomeArquivoPdf>(.*?)</NomeArquivoPdf>", b, re.S) or [None, ""])[1]
        tipo = (re.search(r"<TipoDocumento>(.*?)</TipoDocumento>", b, re.S) or [None, ""])[1]
        arq = os.path.join(PASTA, "%s_anexo%02d.pdf" % (id_doc, k))
        with open(arq, "wb") as fh:
            fh.write(base64.b64decode(pdf.group(1)))
        txt = arq[:-4] + ".txt"
        st = B.extrair_texto(arq, "pdf", txt)
        out.append({"nome": nome, "tipo": tipo, "pdf": arq, "txt": txt if st == "ok" else None, "chars": os.path.getsize(txt) if st == "ok" else 0})
    return out


if __name__ == "__main__":
    for i in sys.argv[1:]:
        r = baixar_itr(i)
        if r["zip_ok"]:
            r["anexos"] = anexos_pdf(i)
        r.pop("conteudo", None)
        print(json.dumps(r, ensure_ascii=False))
