"""Renova os arquivos do ano corrente que o pacote EWS 2.0 le e mede o frescor de cada fonte. Chamado pela rotina
semanal (scripts/run_vixradar_ews2_pacote.ps1) antes do gerar_payload.

Fontes (todas publicas e gratuitas, sem credencial):
  CVM  ITR do ano corrente, DFP do ano anterior, FCA do ano corrente  dados.cvm.gov.br/dados/CIA_ABERTA/DOC/...
  B3   COTAHIST_A<ano>.ZIP do ano corrente                             bvmf.bmfbovespa.com.br/InstDados/SerHist
  Ipea Selic over diaria BM366_TJOVER366, serie inteira                ipeadata.gov.br/api/odata4
Cada arquivo baixa para <destino>.parcial, e validado (zip integro, JSON com serie) e so entao substitui o atual.
Download que falha mantem o arquivo anterior; quem decide se o dado velho serve e o frescor medido (--T).

Saida: uma linha JSON {ok, fontes{nome: {baixado, erro, ...}}, frescor{cotahist_max, selic_max}, motivo}.
ok = false quando a ultima cotacao ou a ultima Selic ficam mais de --folga-dias corridos antes de --T.
Exit 0 ok | 1 frescor reprovado | 2 argumento invalido.

Uso: python -I atualizar_dados.py --T AAAA-MM-DD [--sem-download] [--folga-dias 5]
"""
import argparse
import datetime as dt
import glob
import io
import json
import os
import sys
import urllib.request
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import dados as D  # noqa: E402

CVM = "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/%s/DADOS/%s"
B3 = "https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A%d.ZIP"
IPEA = "http://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='BM366_TJOVER366')"
UA = {"User-Agent": "Mozilla/5.0 (vixradar-ews2-pacote)"}
TIMEOUT = 300


def baixar(url, destino, validar):
    tmp = destino + ".parcial"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=TIMEOUT) as r, open(tmp, "wb") as fh:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                fh.write(b)
        info = validar(tmp)
        os.replace(tmp, destino)
        return dict(baixado=True, bytes=os.path.getsize(destino), **(info or {}))
    except Exception as e:  # noqa: BLE001
        try:
            os.remove(tmp)
        except OSError:
            pass
        return {"baixado": False, "erro": "%s: %s" % (type(e).__name__, str(e)[:200])}


def zip_integro(p):
    with zipfile.ZipFile(p) as z:
        ruim = z.testzip()
        if ruim:
            raise ValueError("zip corrompido em " + ruim)
        if not z.namelist():
            raise ValueError("zip vazio")
    return None


def selic_de_ipea(tmp):
    """Converte a resposta OData em [{data, valor, fonte}] (formato de data/cotacoes/selic_historico_ipea.json)."""
    j = json.load(open(tmp, encoding="utf-8-sig"))
    serie = [{"data": v["VALDATA"][:10], "valor": float(v["VALVALOR"]), "fonte": "Ipeadata BM366_TJOVER366 (Selic over, % a.a.)"}
             for v in j.get("value", []) if v.get("VALVALOR") is not None]
    if len(serie) < 1000:
        raise ValueError("serie Selic curta demais: %d pontos" % len(serie))
    serie.sort(key=lambda x: x["data"])
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(serie, fh, ensure_ascii=False)
    return {"ultimo": serie[-1]["data"]}


def destino_zip(dirs, prefixo, ano):
    """Atualiza o arquivo que o dados.py de fato le para aquele ano (primeiro diretorio que o tem), senao o ultimo."""
    for d in dirs:
        p = os.path.join(d, "%s%d.zip" % (prefixo, ano))
        if os.path.exists(p):
            return p
    return os.path.join(dirs[-1], "%s%d.zip" % (prefixo, ano))


def cotahist_max(ano):
    p = os.path.join(D.DIRS_COTAHIST[0], "COTAHIST_A%d.ZIP" % ano)
    if not os.path.exists(p):
        return None
    ult = None
    with zipfile.ZipFile(p) as z:
        for n in z.namelist():
            for ln in io.TextIOWrapper(z.open(n), encoding="latin-1"):
                if ln[:2] == "01":
                    ult = max(ult or "", ln[2:10])
    return None if not ult else "%s-%s-%s" % (ult[:4], ult[4:6], ult[6:8])


def selic_max():
    s, _ = D.ler_selic(D.SELIC_HIST)
    return max(s).isoformat() if s else None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--T", required=True)
    ap.add_argument("--sem-download", action="store_true")
    ap.add_argument("--folga-dias", type=int, default=5)
    a = ap.parse_args(argv)
    try:
        t = dt.date.fromisoformat(a.T)
    except ValueError:
        print(json.dumps({"ok": False, "motivo": "T invalido"}))
        return 2
    ano = t.year
    fontes = {}
    if not a.sem_download:
        fontes["itr"] = baixar(CVM % ("ITR", "itr_cia_aberta_%d.zip" % ano), destino_zip(D.DIRS_ITR, "itr_cia_aberta_", ano), zip_integro)
        fontes["dfp"] = baixar(CVM % ("DFP", "dfp_cia_aberta_%d.zip" % (ano - 1)), destino_zip(D.DIRS_DFP, "dfp_cia_aberta_", ano - 1), zip_integro)
        fontes["fca"] = baixar(CVM % ("FCA", "fca_cia_aberta_%d.zip" % ano), destino_zip(D.DIRS_FCA, "fca_cia_aberta_", ano), zip_integro)
        fontes["cotahist"] = baixar(B3 % ano, os.path.join(D.DIRS_COTAHIST[0], "COTAHIST_A%d.ZIP" % ano), zip_integro)
        fontes["selic"] = baixar(IPEA, D.SELIC_HIST, selic_de_ipea)
    for p in glob.glob(os.path.join(D.DIRS_COTAHIST[0], "*.parcial")):
        os.remove(p)
    fr = {"cotahist_max": cotahist_max(ano), "selic_max": selic_max()}
    limite = (t - dt.timedelta(days=a.folga_dias)).isoformat()
    velhos = [k for k, v in fr.items() if not v or v < limite]
    out = {"ok": not velhos, "T": a.T, "limite": limite, "fontes": fontes, "frescor": fr,
           "motivo": ("fonte velha ou ausente: " + ",".join(velhos)) if velhos else None}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if not velhos else 1


if __name__ == "__main__":
    sys.exit(main())
