"""Somente leitura. Audita a composicao das camadas da G0-v2 e a potencia do G1b. Saida JSON."""
import csv, json, math, os, re, sys
from datetime import timedelta

VAL = r"E:\Diretorio\Claude\Monitoramento de Credito\scripts\predictive\validacao"
sys.path.insert(0, VAL)
import e1_eventos as V0  # noqa: E402
import e1_eventos_v1 as V1  # noqa: E402

BASE = r"E:\Diretorio\Claude\Monitoramento de Credito"
DIRS = [os.path.join(BASE, "data", "cvm"), r"E:\Diretorio\Claude\tmp\operacional\vix-radar\cvm-ipe"]
INI, FIM = V1.JANELA_INI, V1.JANELA_FIM
RX_LARGO = (r"recupera|falenc|credor|divida|debentur|vencimento antecipado|inadimpl|default|standstill|"
            r"cautelar|reestrutura|mediacao|chapter 11|waiver|repactua|nao pagamento|suspensao")
RX_FORTE = (r"recuperacao (judicial|extrajudicial)|falencia|vencimento antecipado|inadimpl|\bdefault\b|"
            r"standstill|cautelar|mediacao|chapter 11|nao pagamento|suspensao (do |dos )?pagamento")


def ler_csv(p):
    out = set()
    with open(p, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter=";"):
            d = V0.pdate(r["data_evento"])
            if INI <= d <= FIM:
                out.add((r["cnpj"].strip(), d, r.get("universo", ""), r.get("incidente", ""), r.get("em_risco", "")))
    return out


def wilson_sup(x, n, z=1.959964):
    p = x / n
    c = z * z / n
    return (p + c / 2 + z * math.sqrt(p * (1 - p) / n + c / (4 * n))) / (1 + c)


def hiper_sup_zero(N, n, alfa=0.025):
    """Maior M tal que P(0 acertos em n de N | M) >= alfa (limite superior exato com x=0)."""
    M = 0
    while True:
        p0 = 1.0
        for i in range(n):
            p0 *= (N - (M + 1) - i) / (N - i)
            if p0 < alfa:
                break
        if p0 < alfa:
            return M
        M += 1


def main():
    E_rows = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E_rows |= ler_csv(os.path.join(BASE, "data", "validacao", v))
    uni_E = {(c, d) for c, d, *_ in E_rows}
    E_univ0 = {(c, d) for c, d, u, *_ in E_rows if u == "0"}

    docs, _ = V0.ler_ipe(DIRS)
    cad = V0.ler_cad(os.path.join(BASE, "data", "cvm", "cad_cia_aberta.csv")) if os.path.exists(
        os.path.join(BASE, "data", "cvm", "cad_cia_aberta.csv")) else {}
    por_cnpj = {}
    for d in docs:
        por_cnpj.setdefault(d["cnpj"], []).append(d)
    secs = {c for c, lst in por_cnpj.items() if V1.eh_securitizadora(lst, cad.get(c, []))}
    jan = [d for d in docs if INI <= d["data"] <= FIM]

    X, A, cat_a = set(), set(), {}
    ante = []
    for d in jan:
        a = d["assunto_n"]
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(V1.RX_FR_POS, a) and re.search(V1.RX_FR_EXCL, a):
            X.add((d["cnpj"], d["data"]))
            if "antecedente" in a:
                ante.append([d["nome"], d["data"].isoformat()])
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a.setdefault(d["cnpj"], []).append(d["data"])
    cnpj_E = {c for c, _ in uni_E}
    for c, ds in cat_a.items():
        if c not in cnpj_E:
            A.add((c, min(ds)))
    cob = uni_E | X | A
    idx = {}
    for c, dd in cob:
        idx.setdefault(c, []).append(dd)

    def longe(c, dd):
        return not any(abs((dd - x).days) <= 30 for x in idx.get(c, []))

    G, G_forte, G_sec, G_fora_reg = set(), set(), set(), set()
    nfr_forte = set()
    cat_a_longe = set()
    for d in jan:
        k = (d["cnpj"], d["data"])
        fr = re.search(V1.RX_CAT_FR, d["cat_n"])
        if fr and re.search(RX_LARGO, d["assunto_n"]) and longe(*k):
            G.add(k)
            if re.search(RX_FORTE, d["assunto_n"]):
                G_forte.add(k)
            if d["cnpj"] in secs:
                G_sec.add(k)
            if cad and V0.periodo_vigente(cad.get(d["cnpj"], []), d["data"]) is None:
                G_fora_reg.add(k)
        if (not fr and not re.search(V1.RX_CAT_A, d["cat_n"]) and re.search(RX_FORTE, d["assunto_n"])
                and d["cnpj"] not in secs and longe(*k)):
            nfr_forte.add((k, d["cat_n"]))
        if re.search(V1.RX_CAT_A, d["cat_n"]) and d["cnpj"] in cnpj_E and longe(*k):
            cat_a_longe.add(k)
    nfr_cat = {}
    for (_, cat) in nfr_forte:
        nfr_cat[cat] = nfr_cat.get(cat, 0) + 1
    nfr_keys = {k for k, _ in nfr_forte}

    G_util = {k for k in G if k not in G_sec and k not in G_fora_reg}
    N = len(G)
    poder = {}
    for K in (60, 100, 150, 200):
        mlim = 0.10 * K / 0.90
        w = wilson_sup(0, 150)
        m_w = N * w
        poder[str(K)] = {
            "M_max_para_passar": round(mlim, 1),
            "x0_n150_wilson_p_sup": round(w, 5), "x0_n150_M_sup": round(m_w, 1),
            "x0_n150_fracao_perdida_sup": round(m_w / (K + m_w), 3),
            "n_minimo_x0_hipergeometrico": next(n for n in range(10, N + 1, 5) if hiper_sup_zero(N, n) <= mlim),
            "n_minimo_x0_so_estrato_forte": next(n for n in range(5, len(G_forte) + 1, 5)
                                                 if hiper_sup_zero(len(G_forte), n) <= mlim),
        }
    print(json.dumps({
        "conferencia_116": {"E_uniao": len(uni_E), "E_univ0_securitizadora": len(E_univ0), "X": len(X),
                            "A": len(A), "uniao": len(cob), "G": N, "G_cnpjs": len({c for c, _ in G})},
        "X_antecedente": sorted(ante, key=lambda r: r[1]),
        "G_composicao": {"securitizadora": len(G_sec), "fora_periodo_registro": len(G_fora_reg),
                         "no_universo": len(G_util), "estrato_forte": len(G_forte),
                         "estrato_forte_no_universo": len(G_forte & G_util),
                         "so_termo_fraco": N - len(G_forte)},
        "lacunas_fora_de_G": {"nao_FR_com_termo_forte_longe_de_candidato": len(nfr_keys),
                              "por_categoria": dict(sorted(nfr_cat.items(), key=lambda x: -x[1])[:8]),
                              "cat_a_de_cnpj_de_E_longe_de_candidato": len(cat_a_longe),
                              "cat_a_longe_cnpjs": len({c for c, _ in cat_a_longe})},
        "potencia_G1b_por_K_eventos_base": poder,
        "cad_lido": bool(cad),
    }, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
