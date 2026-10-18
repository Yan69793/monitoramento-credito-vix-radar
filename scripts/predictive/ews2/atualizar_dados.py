"""Renova os arquivos do ano corrente que o pacote EWS 2.0 le e mede o frescor de cada fonte. Chamado pela rotina
semanal (scripts/run_vixradar_ews2_pacote.ps1) antes do gerar_payload.

Fontes (todas publicas e gratuitas, sem credencial):
  CVM  ITR do ano corrente, DFP do ano anterior, FCA do ano corrente  dados.cvm.gov.br/dados/CIA_ABERTA/DOC/...
  B3   COTAHIST_A<ano>.ZIP do ano corrente                             bvmf.bmfbovespa.com.br/InstDados/SerHist
  Ipea Selic over diaria BM366_TJOVER366, serie inteira                ipeadata.gov.br/api/odata4
Cada arquivo baixa para <destino>.parcial, e validado (zip integro, JSON com serie) e so entao substitui o atual.
Download que falha mantem o arquivo anterior; quem decide se o dado velho serve e o frescor medido (--T).

Saida: uma linha JSON {ok, fontes{nome: {baixado, erro, ...}}, frescor{cotahist_max, selic_max}, motivo}.
ok = false quando a ultima cotacao ou a ultima Selic ficam mais de --folga-dias corridos antes de --T, ou o IPE mais de --folga-ipe-dias.
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
import time
import urllib.request
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import dados as D  # noqa: E402

CVM = "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/%s/DADOS/%s"
CVM_CAD = "https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv"
B3 = "https://bvmf.bmfbovespa.com.br/InstDados/SerHist/COTAHIST_A%d.ZIP"
IPEA = "http://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='BM366_TJOVER366')"
UA = {"User-Agent": "Mozilla/5.0 (vixradar-ews2-pacote)"}
TIMEOUT = 300


def baixar(url, destino, validar, tentativas=3, espera=20):
    """Baixa para .parcial, valida e so entao substitui. Ate `tentativas` tentativas (a B3 corta conexao de vez em quando).
    Em falha, o erro leva os primeiros bytes recebidos: pagina de bloqueio e arquivo truncado se distinguem pelo texto."""
    tmp = destino + ".parcial"
    erro = None
    for t in range(1, tentativas + 1):
        amostra = b""
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=TIMEOUT) as r, open(tmp, "wb") as fh:
                status = getattr(r, "status", None)
                tipo = r.headers.get("Content-Type")
                while True:
                    b = r.read(1 << 20)
                    if not b:
                        break
                    if len(amostra) < 160:
                        amostra += b[:160]
                    fh.write(b)
            info = validar(tmp)
            os.replace(tmp, destino)
            return dict(baixado=True, bytes=os.path.getsize(destino), tentativas=t, **(info or {}))
        except Exception as e:  # noqa: BLE001
            erro = "%s: %s" % (type(e).__name__, str(e)[:160])
            if amostra:
                erro += " | recebido: %r" % amostra[:120]
            try:
                tam = os.path.getsize(tmp)
                erro += " | bytes=%d" % tam
            except OSError:
                pass
            try:
                os.remove(tmp)
            except OSError:
                pass
            if t < tentativas:
                time.sleep(espera)
    return {"baixado": False, "erro": erro, "tentativas": tentativas}


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


def csv_integro(p):
    with open(p, "rb") as fh:
        cab = fh.read(4096)
    if b";" not in cab or b"CNPJ" not in cab.upper():
        raise ValueError("csv sem cabecalho esperado")
    return None


def ipe_max_entrega():
    """Maior Data_Entrega nos zips do IPE lidos pelo pipeline (frescor da fonte)."""
    docs, _ = D.ler_ipe()
    return max((d["data"] for d in docs), default=None)


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
    ap.add_argument("--folga-ipe-dias", type=int, default=14, help="o IPE em lote atrasa dias com a CVM; acima disso e fonte parada")
    a = ap.parse_args(argv)
    try:
        t = dt.date.fromisoformat(a.T)
    except ValueError:
        print(json.dumps({"ok": False, "motivo": "T invalido"}))
        return 2
    ano = t.year
    fontes = {}
    if not a.sem_download:
        # `anos_largos` baixa tambem os anos anteriores que ainda nao estao na pasta (primeira rodada de um runner limpo);
        # com a pasta preenchida (cache) so o ano corrente e renovado.
        def anos(dirs, prefixo, ext, ultimos):
            tem = lambda y: any(os.path.exists(os.path.join(d, "%s%d.%s" % (prefixo, y, ext))) for d in dirs)  # noqa: E731
            return [y for y in range(ano - ultimos, ano + 1) if y == ano or not tem(y)]
        os.makedirs(D.DIRS_ITR[0], exist_ok=True)
        os.makedirs(D.DIRS_COTAHIST[0], exist_ok=True)
        os.makedirs(D.DIRS_FCA[0], exist_ok=True)
        os.makedirs(D.DIRS_DFP[-1], exist_ok=True)
        os.makedirs(D.DIRS_IPE[-1], exist_ok=True)
        os.makedirs(os.path.dirname(D.CAD), exist_ok=True)
        for y in anos(D.DIRS_IPE, "ipe_cia_aberta_", "zip", 3):
            fontes["ipe_%d" % y] = baixar(CVM % ("IPE", "ipe_cia_aberta_%d.zip" % y), destino_zip(D.DIRS_IPE, "ipe_cia_aberta_", y), zip_integro)
        for y in anos(D.DIRS_ITR, "itr_cia_aberta_", "zip", 1):
            fontes["itr_%d" % y] = baixar(CVM % ("ITR", "itr_cia_aberta_%d.zip" % y), destino_zip(D.DIRS_ITR, "itr_cia_aberta_", y), zip_integro)
        for y in anos(D.DIRS_DFP, "dfp_cia_aberta_", "zip", 2):
            fontes["dfp_%d" % y] = baixar(CVM % ("DFP", "dfp_cia_aberta_%d.zip" % y), destino_zip(D.DIRS_DFP, "dfp_cia_aberta_", y), zip_integro)
        for y in anos(D.DIRS_FCA, "fca_cia_aberta_", "zip", 1):
            fontes["fca_%d" % y] = baixar(CVM % ("FCA", "fca_cia_aberta_%d.zip" % y), destino_zip(D.DIRS_FCA, "fca_cia_aberta_", y), zip_integro)
        for y in anos(D.DIRS_COTAHIST, "COTAHIST_A", "ZIP", 2):
            fontes["cotahist_%d" % y] = baixar(B3 % y, os.path.join(D.DIRS_COTAHIST[0], "COTAHIST_A%d.ZIP" % y), zip_integro)
        fontes["cad"] = baixar(CVM_CAD, D.CAD, csv_integro)
        fontes["selic"] = baixar(IPEA, D.SELIC_HIST, selic_de_ipea)
    for p in glob.glob(os.path.join(D.DIRS_COTAHIST[0], "*.parcial")):
        os.remove(p)
    ipe = ipe_max_entrega()
    fr = {"cotahist_max": cotahist_max(ano), "selic_max": selic_max(), "ipe_max_entrega": ipe.isoformat() if ipe else None}
    limite = (t - dt.timedelta(days=a.folga_dias)).isoformat()
    limite_ipe = (t - dt.timedelta(days=a.folga_ipe_dias)).isoformat()
    velhos = [k for k, v in fr.items() if not v or v < (limite_ipe if k == "ipe_max_entrega" else limite)]
    out = {"ok": not velhos, "T": a.T, "limite": limite, "fontes": fontes, "frescor": fr,
           "motivo": ("fonte velha ou ausente: " + ",".join(velhos)) if velhos else None}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if not velhos else 1


if __name__ == "__main__":
    sys.exit(main())
