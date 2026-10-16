"""Somente leitura. Mede o universo de candidatos da G0-v2 (rotulagem manual), sem sinal algum.

Camadas (cada uma reportada separada, uniao por (cnpj, data_entrega)):
  E   episodios das e1-v0, e1-v0.1 e e1-v1 na janela (CSV ja gerados)
  X   FR na janela cujo Assunto casa RX_FR_POS e foi derrubado SO por RX_FR_EXCL
  A   primeiro documento categoria (a) por CNPJ na janela que nunca virou episodio
  G   rede de revocacao: FR na janela com termo de credito largo, nao coberto por E/X/A
      a ate 30 dias do mesmo CNPJ (mede o tamanho do que a regra nunca viu)
Saida: JSON em stdout.
"""
import csv, json, os, re, sys
from datetime import date, timedelta

VAL = r"E:\Diretorio\Claude\Monitoramento de Credito\scripts\predictive\validacao"
sys.path.insert(0, VAL)
import e1_eventos as V0  # noqa: E402
import e1_eventos_v1 as V1  # noqa: E402

BASE = r"E:\Diretorio\Claude\Monitoramento de Credito"
DIRS = [os.path.join(BASE, "data", "cvm"), r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cvm-ipe"]
INI, FIM = V1.JANELA_INI, V1.JANELA_FIM
RX_LARGO = (r"recupera|falenc|credor|divida|debentur|vencimento antecipado|inadimpl|default|standstill|"
            r"cautelar|reestrutura|mediacao|chapter 11|waiver|repactua|nao pagamento|suspensao")


def ler_csv(p):
    out = []
    with open(p, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter=";"):
            d = date.fromisoformat(r["data_evento"])
            if INI <= d <= FIM:
                out.append((r["cnpj"].strip(), d))
    return out


def main():
    E = {}
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        rows = ler_csv(os.path.join(BASE, "data", "validacao", v))
        E[v] = set(rows)
    uni_E = set().union(*E.values())

    docs, _ = V0.ler_ipe(DIRS)
    jan = [d for d in docs if INI <= d["data"] <= FIM]
    X, A, G = set(), set(), set()
    cat_a_por_cnpj = {}
    for d in jan:
        a = d["assunto_n"]
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(V1.RX_FR_POS, a) and re.search(V1.RX_FR_EXCL, a):
            X.add((d["cnpj"], d["data"]))
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a_por_cnpj.setdefault(d["cnpj"], []).append(d["data"])
    cnpj_E = {c for c, _ in uni_E}
    for c, ds in cat_a_por_cnpj.items():
        if c not in cnpj_E:
            A.add((c, min(ds)))
    cobertos = uni_E | X | A
    idx = {}
    for c, dd in cobertos:
        idx.setdefault(c, []).append(dd)
    for d in jan:
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(RX_LARGO, d["assunto_n"]):
            perto = any(abs((d["data"] - x).days) <= 30 for x in idx.get(d["cnpj"], []))
            if not perto:
                G.add((d["cnpj"], d["data"]))
    ante = sum(1 for (c, dd) in X if any(re.search(r"antecedente", x["assunto_n"]) for x in jan
                                          if x["cnpj"] == c and x["data"] == dd))
    print(json.dumps({
        "janela": [INI.isoformat(), FIM.isoformat()],
        "docs_ipe_janela": len(jan),
        "E_por_versao": {k: len(v) for k, v in E.items()},
        "E_uniao": len(uni_E), "E_cnpjs": len(cnpj_E),
        "X_fr_derrubado_so_por_exclusao": len(X), "X_com_antecedente": ante,
        "A_cat_a_sem_episodio_cnpjs": len(A),
        "uniao_E_X_A": len(cobertos), "uniao_E_X_A_cnpjs": len({c for c, _ in cobertos}),
        "G_rede_revocacao_fr_largo_fora_30d": len(G), "G_cnpjs": len({c for c, _ in G}),
    }, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
