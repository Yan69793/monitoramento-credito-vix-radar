"""Somente leitura. Dimensiona o G1b estratificado da G0-v2. Saida JSON em stdout.

Estratos de G (ja no universo e dentro de periodo de registro):
  F  forte: Assunto casa RX_FORTE
  W  fraco: o resto de G
Limite superior por estrato: hipergeometrico exato, unilateral, alfa = 0,025 / numero de estratos
(Bonferroni, cobertura conjunta de 97,5% unilateral, a mesma do IC95 bilateral original).
Censo de estrato (n = N) tem limite igual ao achado.
"""
import csv, json, math, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auditar_g0v2 as AU  # noqa: E402

V0, V1 = AU.V0, AU.V1
ALFA = 0.025


def lcomb(a, b):
    return math.lgamma(a + 1) - math.lgamma(b + 1) - math.lgamma(a - b + 1)


def cdf_hiper(x, N, M, n):
    lo = max(0, n - (N - M))
    s = 0.0
    den = lcomb(N, n)
    for k in range(lo, min(x, M, n) + 1):
        s += math.exp(lcomb(M, k) + lcomb(N - M, n - k) - den)
    return s


def u_sup(x, n, N, alfa):
    """Maior M com P(X <= x | N, M, n) >= alfa. Censo devolve x."""
    if n >= N:
        return x
    M = x
    while M < N and cdf_hiper(x, N, M + 1, n) >= alfa:
        M += 1
    return M


def estratos():
    E = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E |= {(c, d) for c, d, *_ in AU.ler_csv(os.path.join(AU.BASE, "data", "validacao", v))}
    docs, _ = V0.ler_ipe(AU.DIRS)
    cad = V0.ler_cad(os.path.join(AU.BASE, "data", "cvm", "cad_cia_aberta.csv"))
    por = {}
    for d in docs:
        por.setdefault(d["cnpj"], []).append(d)
    secs = {c for c, l in por.items() if V1.eh_securitizadora(l, cad.get(c, []))}
    jan = [d for d in docs if AU.INI <= d["data"] <= AU.FIM]
    X, cat_a = set(), {}
    for d in jan:
        a = d["assunto_n"]
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(V1.RX_FR_POS, a) and re.search(V1.RX_FR_EXCL, a):
            X.add((d["cnpj"], d["data"]))
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a.setdefault(d["cnpj"], []).append(d["data"])
    cE = {c for c, _ in E}
    A = {(c, min(ds)) for c, ds in cat_a.items() if c not in cE}
    idx = {}
    for c, dd in E | X | A:
        idx.setdefault(c, []).append(dd)
    F, W = {}, {}
    for d in jan:
        k = (d["cnpj"], d["data"])
        if not (re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(AU.RX_LARGO, d["assunto_n"])):
            continue
        if any(abs((d["data"] - x).days) <= 30 for x in idx.get(d["cnpj"], [])):
            continue
        if d["cnpj"] in secs or V0.periodo_vigente(cad.get(d["cnpj"], []), d["data"]) is None:
            continue
        alvo = F if re.search(AU.RX_FORTE, d["assunto_n"]) else W
        alvo.setdefault(k, []).append(d["assunto_n"])
    F = {k: v for k, v in F.items()}
    W = {k: v for k, v in W.items() if k not in F}  # chave com documento forte no dia vai para F
    return F, W


def minimo_total(NF, NW, mmax, xF=0, xW=0, passo=5):
    """Menor nF + nW com u_sup(F) + u_sup(W) <= mmax, alfa/2 em cada estrato."""
    a = ALFA / 2

    def tabela(N, x):
        grade = list(range(passo, N, passo)) + [N]
        return [(n, u_sup(x, n, N, a)) for n in grade]

    tF, tW = tabela(NF, xF), tabela(NW, xW)
    melhor = None
    j = len(tW) - 1
    for nF, uF in tF:
        resto = mmax - uF
        if resto < xW:
            continue
        cand = next(((nW, uW) for nW, uW in tW if uW <= resto), None)
        if cand and (melhor is None or nF + cand[0] < melhor[0]):
            melhor = (nF + cand[0], nF, cand[0], uF, cand[1])
    return melhor


def main():
    F, W = estratos()
    NF, NW = len(F), len(W)
    so_deb = sum(1 for v in W.values() if all(re.fullmatch(r".*debentur.*", a) and not re.search(
        r"recupera|falenc|credor|divida|inadimpl|default|cautelar|reestrutura|mediacao|waiver|repactua|suspensao", a)
        for a in v))
    out = {"N_F": NF, "N_W": NW, "N_G": NF + NW, "W_so_debentur": so_deb, "alfa_por_estrato": ALFA / 2,
           "dimensionamento": {}}
    for K in (25, 40, 60, 80, 100, 135, 150, 200):
        mmax = math.floor(K / 9)  # M/(K+M) <= 0,10  <=>  M <= K/9
        r0 = minimo_total(NF, NW, mmax)
        r1 = minimo_total(NF, NW, mmax, xF=1)
        out["dimensionamento"][str(K)] = {
            "M_max": mmax,
            "x0": dict(zip(["n_total", "n_F", "n_W", "uF", "uW"], r0)) if r0 else None,
            "x1_em_F": dict(zip(["n_total", "n_F", "n_W", "uF", "uW"], r1)) if r1 else None,
        }
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
