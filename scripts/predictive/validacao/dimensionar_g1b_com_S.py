"""Somente leitura. Custo do G1b se a decisao 4 da nota 116 ampliar G com um terceiro estrato S.

S: documento fora de Fato Relevante e fora da categoria (a), de CNPJ no universo, com abertura explicita
no Assunto (RX_ABRE_ESTRITO de medir_lacunas_nao_fr.py), sem RX_NAO_ABRE, RX_FR_EXCL nem "nao decreta",
a mais de 30 dias de toda chave de E, X, A, F ou W do mesmo CNPJ.
Alfa por estrato = 0,025 / 3 (Bonferroni). Mesma busca em grade de 5 do dimensionar_g1b.py.
"""
import json, math, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402
import medir_lacunas_nao_fr as ML  # noqa: E402

AU, V0, V1 = DG.AU, DG.V0, DG.V1
RX_NAO_DECRETA = r"nao (decreta|declara)"


def estrato_S(F, W):
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
    for c, dd in E | X | A | set(F) | set(W):
        idx.setdefault(c, []).append(dd)
    S = set()
    for d in jan:
        a, cat = d["assunto_n"], d["cat_n"]
        if re.search(V1.RX_CAT_FR, cat) or re.search(V1.RX_CAT_A, cat):
            continue
        if d["cnpj"] in secs or V0.periodo_vigente(cad.get(d["cnpj"], []), d["data"]) is None:
            continue
        if any(abs((d["data"] - x).days) <= 30 for x in idx.get(d["cnpj"], [])):
            continue
        if (re.search(ML.RX_ABRE_ESTRITO, a) and not re.search(V1.RX_NAO_ABRE, a)
                and not re.search(V1.RX_FR_EXCL, a) and not re.search(RX_NAO_DECRETA, a)):
            S.add((d["cnpj"], d["data"]))
    return S


def minimo_3(Ns, mmax, alfa, passo=5):
    tabs = []
    for N in Ns:
        grade = list(range(passo, N, passo)) + [N]
        tabs.append([(n, DG.u_sup(0, n, N, alfa)) for n in grade])
    melhor = None
    for n1, u1 in tabs[0]:
        for n2, u2 in tabs[1]:
            resto = mmax - u1 - u2
            if resto < 0:
                continue
            c = next(((n3, u3) for n3, u3 in tabs[2] if u3 <= resto), None)
            if c and (melhor is None or n1 + n2 + c[0] < melhor[0]):
                melhor = (n1 + n2 + c[0], n1, n2, c[0])
    return melhor


def main():
    F, W = DG.estratos()
    S = estrato_S(F, W)
    out = {"N_F": len(F), "N_W": len(W), "N_S": len(S), "S_cnpjs": len({c for c, _ in S}),
           "alfa_por_estrato": DG.ALFA / 3, "dimensionamento_x0": {}}
    for K in (25, 40, 60, 80, 100, 135, 150, 200):
        mmax = math.floor(K / 9)
        r = minimo_3([len(F), len(S), len(W)], mmax, DG.ALFA / 3)
        r2 = DG.minimo_total(len(F), len(W), mmax)
        out["dimensionamento_x0"][str(K)] = {
            "M_max": mmax,
            "com_S": dict(zip(["n_total", "n_F", "n_S", "n_W"], r)) if r else None,
            "sem_S_nota_116": r2[0] if r2 else None,
        }
    print(json.dumps(out, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
