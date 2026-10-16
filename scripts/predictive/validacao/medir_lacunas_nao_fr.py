"""Somente leitura. Mede as duas lacunas da decisao 4 da nota 116 contra TODAS as camadas (E, X, A e G).

L1  documento fora de Fato Relevante e fora da categoria (a), com termo de abertura de evento
    (RX_ABRE_EVENTO, mais estreito que RX_FORTE), de CNPJ no universo, a mais de 30 dias de
    qualquer chave de E, X, A ou G do mesmo CNPJ. E o que nenhum item rotulado alcanca.
L1z subconjunto de L1 em CNPJ sem nenhuma chave em E, X, A ou G na janela (companhia invisivel).
PF  categoria IPE "Pedidos de falencia", inteira, com a distancia ate o candidato mais proximo.
L2  categoria (a) de CNPJ que ja tem episodio, a mais de 30 dias de qualquer chave de E, X, A ou G,
    com Assunto de abertura (RX_A_ABRE sem RX_NAO_ABRE) ou Assunto vazio, separados por distancia
    ate o episodio anterior mais proximo (> 365 dias = possivel novo pedido).
Saida: JSON em stdout. Nao baixa documento, nao le sinal.
"""
import json, os, re, sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402

AU, V0, V1 = DG.AU, DG.V0, DG.V1
RX_ABRE_EVENTO = (r"recuperacao (judicial|extrajudicial)|pedido de falencia|autofalencia|decretacao de falencia"
                  r"|falencia|vencimento antecipado|inadimpl|\bdefault\b|nao pagamento"
                  r"|suspensao (do |dos )?pagamento|standstill|chapter 11|cautelar|mediacao")
# L1s: abertura explicita no Assunto, sem os termos de desfecho/rotina de RX_NAO_ABRE e RX_FR_EXCL.
RX_ABRE_ESTRITO = (r"(pedido|ajuizamento|requerimento|ingresso|distribuicao)( de| do)?( pedido de)?"
                   r" (recuperacao (judicial|extrajudicial)|falencia|autofalencia)|autofalencia"
                   r"|decretacao (de|da) falencia|sentenca de falencia|vencimento antecipado|chapter 11"
                   r"|(tutela|medida|acao) cautelar|standstill|mediacao com")


def main():
    F, W = DG.estratos()
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
    todas = E | X | A | set(F) | set(W)
    idx = {}
    for c, dd in todas:
        idx.setdefault(c, []).append(dd)
    idxE = {}
    for c, dd in E:
        idxE.setdefault(c, []).append(dd)

    def dist(c, dd):
        xs = idx.get(c, [])
        return min((abs((dd - x).days) for x in xs), default=None)

    def no_univ(d):
        return d["cnpj"] not in secs and V0.periodo_vigente(cad.get(d["cnpj"], []), d["data"]) is not None

    L1, L1_cat, PF, L2_abre, L2_vazio, L1s = set(), Counter(), [], [], [], {}
    cat_a_todas = {}
    for d in docs:
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a_todas.setdefault(d["cnpj"], []).append(d["data"])
    for d in jan:
        k = (d["cnpj"], d["data"])
        cat, a = d["cat_n"], d["assunto_n"]
        eh_fr, eh_a = re.search(V1.RX_CAT_FR, cat), re.search(V1.RX_CAT_A, cat)
        ds = dist(*k)
        longe = ds is None or ds > 30
        if "pedidos de falencia" in cat:
            PF.append({"cnpj": d["cnpj"], "data": d["data"].isoformat(), "assunto": d["assunto"][:120],
                       "dist_candidato_dias": ds, "no_universo": no_univ(d), "protocolo": d["protocolo"]})
        if not eh_fr and not eh_a and longe and no_univ(d) and re.search(RX_ABRE_EVENTO, a):
            L1.add(k)
            L1_cat[cat] += 1
            if (re.search(RX_ABRE_ESTRITO, a) and not re.search(V1.RX_NAO_ABRE, a)
                    and not re.search(V1.RX_FR_EXCL, a)):
                L1s.setdefault(k, []).append({"cat": cat, "assunto": d["assunto"][:140], "prot": d["protocolo"]})
        if eh_a and d["cnpj"] in cE and longe and no_univ(d):
            ant = [x for x in idxE.get(d["cnpj"], []) if x < d["data"]]
            gap = (d["data"] - max(ant)).days if ant else None
            reg = {"cnpj": d["cnpj"], "data": d["data"].isoformat(), "assunto": d["assunto"][:120],
                   "dias_desde_episodio_anterior": gap, "protocolo": d["protocolo"],
                   "silencio_cat_a_dias": min(((d["data"] - x).days for x in cat_a_todas.get(d["cnpj"], [])
                                               if x < d["data"]), default=None)}
            if not a.strip():
                L2_vazio.append(reg)
            elif re.search(V1.RX_A_ABRE, a) and not re.search(V1.RX_NAO_ABRE, a):
                L2_abre.append(reg)
    L1z = {k for k in L1 if k[0] not in idx}
    retomada = [r for r in L2_abre + L2_vazio if r["silencio_cat_a_dias"] is None or r["silencio_cat_a_dias"] > 365]

    def faixa(lst):
        return {"total": len(lst), "cnpjs": len({r["cnpj"] for r in lst}),
                "gap_maior_365": sum(1 for r in lst if r["dias_desde_episodio_anterior"] is None
                                     or r["dias_desde_episodio_anterior"] > 365),
                "gap_maior_365_cnpjs": len({r["cnpj"] for r in lst if r["dias_desde_episodio_anterior"] is None
                                            or r["dias_desde_episodio_anterior"] > 365})}

    # primeira chave de L2 com gap > 365 por CNPJ: e o unico candidato a novo pedido que importa por CNPJ
    novos = {}
    for r in sorted(L2_abre + L2_vazio, key=lambda r: r["data"]):
        g = r["dias_desde_episodio_anterior"]
        if (g is None or g > 365) and r["cnpj"] not in novos:
            novos[r["cnpj"]] = r
    print(json.dumps({
        "camadas": {"E": len(E), "X": len(X), "A": len(A), "F": len(F), "W": len(W), "uniao": len(todas)},
        "L1_nao_fr_abertura_longe_de_tudo": {"chaves": len(L1), "cnpjs": len({c for c, _ in L1}),
                                             "por_categoria": dict(L1_cat.most_common(10))},
        "L1z_cnpj_sem_candidato_algum": {"chaves": len(L1z), "cnpjs": len({c for c, _ in L1z})},
        "PF_pedidos_de_falencia": {"total": len(PF), "no_universo": sum(1 for r in PF if r["no_universo"]),
                                   "longe_30d_de_tudo": sum(1 for r in PF if r["dist_candidato_dias"] is None
                                                            or r["dist_candidato_dias"] > 30),
                                   "itens": PF},
        "L2_cat_a_longe_de_tudo": {"abertura": faixa(L2_abre), "assunto_vazio": faixa(L2_vazio)},
        "L2_primeiro_por_cnpj_gap_maior_365": list(novos.values()),
        "L2_retomada_apos_silencio_cat_a_maior_365": retomada,
        "L1s_abertura_estrita": {"chaves": len(L1s), "cnpjs": len({c for c, _ in L1s}),
                                 "em_cnpj_sem_candidato": sum(1 for k in L1s if k[0] not in idx),
                                 "itens": [{"cnpj": k[0], "data": k[1].isoformat(), "sem_candidato": k[0] not in idx,
                                            "docs": v} for k, v in sorted(L1s.items(), key=lambda kv: kv[0][1])]},
    }, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
