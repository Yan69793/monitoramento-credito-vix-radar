"""Somente leitura. Reconcilia a uniao de candidatos da nota 116 (E, X, A, S ultima da cadeia, A2) e os
documentos da primeira etapa. Separa candidato novo de desdobramento pela distancia ao candidato anterior do
mesmo CNPJ (30 dias da regra, 180 dias da leitura, 24 meses do indice). Conta documentos no IPE local, sem
baixar nada e sem sortear: o volume de F e W na primeira etapa sai pela media do estrato, porque a
permutacao so e sorteada depois do congelamento. Saida JSON em stdout.
"""
import json, os, re, sys
from collections import Counter
from datetime import date, timedelta
from statistics import mean

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402
import dimensionar_g1b_com_S as DS  # noqa: E402

AU, V0, V1 = DG.AU, DG.V0, DG.V1
AQUI = os.path.dirname(os.path.abspath(__file__))
PREFIXO_F, PREFIXO_W = 210, 540


def ultima_da_cadeia(S):
    ult, chaves = [], sorted(S)
    for i, (c, d) in enumerate(chaves):
        prox = chaves[i + 1] if i + 1 < len(chaves) else None
        if not (prox and prox[0] == c and (prox[1] - d).days <= 30):
            ult.append((c, d))
    return set(ult)


def faixa(dias):
    if dias is None:
        return "sem_candidato_anterior"
    if dias <= 30:
        return "ate_30"
    if dias <= 180:
        return "31_a_180"
    if dias <= 730:
        return "181_a_730"
    return "mais_de_730"


def main():
    F, W = DG.estratos()
    S = DS.estrato_S(F, W)
    S_ult = ultima_da_cadeia(S)
    inv = json.loads(open(os.path.join(AQUI, "investigacao_S_A2.json"), encoding="utf-8-sig").read())
    A2 = {(r["cnpj"], date.fromisoformat(r["data"])) for r in inv["A2"]["itens"]}

    E = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E |= {(c, d) for c, d, *_ in AU.ler_csv(os.path.join(AU.BASE, "data", "validacao", v))}
    docs, _ = V0.ler_ipe(AU.DIRS)
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

    camadas = {"E": E, "X": X, "A": A, "S": S_ult, "A2": A2}
    uniao = set().union(*camadas.values())
    base = E | X | A
    nomes = list(camadas)
    sobreposicao = {f"{a}&{b}": len(camadas[a] & camadas[b]) for i, a in enumerate(nomes) for b in nomes[i + 1:]
                    if camadas[a] & camadas[b]}
    origem = {}
    for n in nomes:
        for k in camadas[n]:
            origem.setdefault(k, []).append(n)

    # Pares de candidatos do mesmo CNPJ a ate 30 dias (sobrevivem como itens separados, o item 3 funde)
    por_c = {}
    for k in uniao:
        por_c.setdefault(k[0], []).append(k[1])
    pares = Counter()
    n_pares = 0
    for c, ds in por_c.items():
        ds = sorted(ds)
        for a, b in zip(ds, ds[1:]):
            if (b - a).days <= 30:
                n_pares += 1
                pares["+".join(sorted({"/".join(origem[(c, a)]), "/".join(origem[(c, b)])}))] += 1

    # Novo x desdobramento: S e A2 contra o candidato anterior mais proximo do mesmo CNPJ na uniao
    def anterior(k, conjunto):
        prev = [d for c, d in conjunto if c == k[0] and d < k[1]]
        return (k[1] - max(prev)).days if prev else None

    desd = {}
    for n in ("S", "A2"):
        fx = Counter()
        fx_base = Counter()
        for k in camadas[n]:
            fx[faixa(anterior(k, uniao - {k}))] += 1
            fx_base[faixa(anterior(k, base))] += 1
        desd[n] = {"contra_toda_a_uniao": dict(sorted(fx.items())), "contra_E_X_A": dict(sorted(fx_base.items()))}

    # Documentos: no dia da chave e contexto de 180 dias do mesmo CNPJ, pelo indice IPE local
    por_chave, por_cnpj = Counter(), {}
    for d in docs:
        por_chave[(d["cnpj"], d["data"])] += 1
        por_cnpj.setdefault(d["cnpj"], []).append(d["data"])
    for c in por_cnpj:
        por_cnpj[c].sort()

    def ctx180(k):
        ini = k[1] - timedelta(days=180)
        return sum(1 for x in por_cnpj.get(k[0], []) if ini <= x < k[1])

    def resumo(keys):
        dia = [por_chave[k] for k in keys]
        ctx = [ctx180(k) for k in keys]
        return {"chaves": len(keys), "docs_no_dia": sum(dia), "media_docs_no_dia": round(mean(dia), 3),
                "docs_contexto_180d": sum(ctx), "media_contexto_180d": round(mean(ctx), 2)}

    vol = {n: resumo(camadas[n]) for n in nomes}
    vol["uniao"] = resumo(uniao)
    vol["F"] = resumo(set(F))
    vol["W"] = resumo(set(W))
    etapa1_docs = (vol["uniao"]["docs_no_dia"] + PREFIXO_F * vol["F"]["media_docs_no_dia"]
                   + PREFIXO_W * vol["W"]["media_docs_no_dia"])

    # F e W nao podem mudar com S e A2 na uniao
    novos = S_ult | A2
    perto = [k for k in set(F) | set(W) if any(c == k[0] and abs((k[1] - dd).days) <= 30 for c, dd in novos)]

    print(json.dumps({
        "camadas": {n: len(v) for n, v in camadas.items()},
        "S_chaves_brutas": len(S),
        "soma_camadas": sum(len(v) for v in camadas.values()),
        "uniao_distinta": len(uniao), "uniao_E_X_A": len(base),
        "sobreposicao_exata": sobreposicao,
        "pares_ate_30d_na_uniao": {"total": n_pares, "por_origem": dict(sorted(pares.items()))},
        "S_A2_novo_ou_desdobramento": desd,
        "volume": vol,
        "etapa1": {"chaves": len(uniao) + PREFIXO_F + PREFIXO_W,
                   "docs_no_dia_estimados": round(etapa1_docs)},
        "F_W": {"N_F": len(F), "N_W": len(W), "chaves_de_G_a_30d_de_S_ou_A2": len(perto),
                "F_inter_W": len(set(F) & set(W)), "G_inter_uniao": len((set(F) | set(W)) & uniao)},
    }, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    main()
