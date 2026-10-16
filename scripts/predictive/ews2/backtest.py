"""Backtest cronologico do EWS 2.0 (G0-v1 itens 6 a 10) sobre a base rotulada. Orquestra: eventos -> painel -> features
em T -> G2 por hipotese (teste, uma vez) -> G3 (logit <= 3 sinais aprovados, treino, Platt na validacao) -> relatorio.

Vazamento temporal, por construcao: features em T so leem Data_Entrega/DT_RECEB <= T-1 (features.py); alvo em (T, T+h];
linha usavel so com horizonte fechado dentro da particao; embargo nunca entra; teste avaliado uma vez; conjunto de
formulacao fora das metricas e reportado a parte; nenhum limiar escolhido no teste (H5 e H6 tem corte fixado no bloco).

Modos:
  --sintetico        gera dados com sintetico.py e roda tudo (prova de pipeline; NAO e evidencia de eficacia)
  --real             exige guarda_treino (homologacao da base + autorizacao); sem isso sai com exit 1 sem ler sinal
Saida: JSON com cobertura, contagens, metricas por hipotese, veredito G2/G3 e declaracoes do que nao foi medido.
"""
import argparse
import json
import math
import os
import sys
from collections import defaultdict
from datetime import timedelta

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import calendario as C  # noqa: E402
import eventos as EV  # noqa: E402
import features as F  # noqa: E402
import metricas as M  # noqa: E402
import modelo as MO  # noqa: E402
import painel as P  # noqa: E402

VERSAO_PIPELINE = "ews2-backtest-v0.1 (2026-10-16)"


def montar(dados, rotulos, fim_obs=C.JANELA_FIM):
    docs_por = defaultdict(list)
    for d in dados["docs"]:
        docs_por[d["cnpj"]].append(d)
    for lst in docs_por.values():
        lst.sort(key=lambda d: d["data"])
    evs = EV.eventos_de_rotulos(rotulos)
    eps = EV.marcar_prevalencia(EV.episodios(evs), docs_por)
    eps_por = defaultdict(list)
    for ep in eps:
        eps_por[ep["cnpj"]].append(ep)
    cad = dados["cad"]
    secs = {c for c in set(list(docs_por) + list(cad)) if EV.eh_securitizadora(docs_por.get(c, []), cad.get(c, []))}
    primeira_dfp = {c: min((v["dt_receb"] for v in vs if v["dt_receb"]), default=None) for c, vs in dados["dfp"].items()}
    formulacao = {c for c, lst in docs_por.items() if EV.eh_formulacao({d["nome_n"] for d in lst})}
    cnpjs = sorted(c for c in cad if c in primeira_dfp)
    datas_T = C.datas_observacao(C.JANELA_INI, fim_obs)
    linhas = P.linhas_painel(cnpjs, datas_T, eps_por, cad, primeira_dfp, secs, formulacao)
    # eventos incidentes por setor para H8 (outra empresa do mesmo setor)
    setor_de = {c: (cad[c][0]["setor_ativ"] if cad.get(c) else "") for c in cnpjs}
    ev_setor = defaultdict(list)
    for ep in eps:
        if not ep["prevalente"]:
            ev_setor[setor_de.get(ep["cnpj"], "")].append((ep["inicio"], ep["cnpj"]))
    for lst in ev_setor.values():
        lst.sort()
    datas_por = {c: [d["data"] for d in docs_por[c]] for c in docs_por}
    for l in linhas:
        c, t = l["cnpj"], l["T"]
        evs_outros = {s: [(d, cc) for d, cc in lst if cc != c] for s, lst in ev_setor.items()}
        f = F.features_em_T(c, t, docs_por.get(c, []), datas_por.get(c, []), dados["dfp"].get(c, []), dados.get("itr", {}).get(c, []),
                            dados.get("precos", {}).get(c), dados.get("selic", {}), setor_de.get(c), evs_outros)
        l.update(f)
        l["H5_dd_neg"] = -f["H5_dd"] if f["H5_dd"] is not None else None
        l["setor"] = setor_de.get(c)
    return {"linhas": linhas, "episodios": eps, "securitizadoras": sorted(secs), "formulacao": sorted(formulacao),
            "n_eventos": len(evs), "n_episodios": len(eps), "n_incidentes": sum(1 for e in eps if not e["prevalente"])}


def _clusters(linhas, idx, grupos=None):
    cl = defaultdict(list)
    for i in idx:
        c = linhas[i]["cnpj"]
        cl[(grupos or {}).get(c, c)].append(i)
    return cl


def avaliar_hipotese(nome, linhas, idx_teste, grupos=None):
    """G2 de um sinal binario sobre as linhas de teste usaveis sem formulacao."""
    idx = [i for i in idx_teste if linhas[i].get(nome) is not None and linhas[i].get("B2") is not None]
    if not idx:
        return {"sinal": nome, "n": 0, "estado": "sem_dado"}
    s = [linhas[i][nome] for i in idx]
    y = [linhas[i]["y180"] for i in idx]
    cl = defaultdict(list)
    for j, i in enumerate(idx):
        cl[(grupos or {}).get(linhas[i]["cnpj"], linhas[i]["cnpj"])].append(j)
    rr = M.razao_de_risco(s, y)
    li, ls, nb = M.bootstrap_cluster(cl, lambda ii: M.razao_de_risco([s[k] for k in ii], [y[k] for k in ii]))
    escore = [linhas[i][F.ESCORES_CONTINUOS.get(nome, nome)] if F.ESCORES_CONTINUOS.get(nome) else linhas[i][nome] for i in idx]
    pr_s = M.pr_auc(escore, y)
    pr_b2 = M.pr_auc([linhas[i]["B2"] for i in idx], y)
    pr_b1 = M.pr_auc([linhas[i]["B1"] for i in idx if linhas[i]["B1"] is not None], [y[j] for j, i in enumerate(idx) if linhas[i]["B1"] is not None])
    pr_b3 = M.pr_auc([linhas[i]["B3"] for i in idx], y)
    # B0: ranking aleatorio, 1.000 sorteios, semente 20261015 -> media da PR-AUC
    import random
    rng = random.Random(M.SEMENTE)
    b0 = [M.pr_auc([rng.random() for _ in idx], y) for _ in range(1000)]
    b0 = sum(v for v in b0 if v is not None) / max(1, sum(1 for v in b0 if v is not None))
    ativ = defaultdict(list)
    for i in idx:
        if linhas[i][nome] == 1:
            ativ[linhas[i]["cnpj"]].append(linhas[i]["T"])
    for v in ativ.values():
        v.sort()
    return {"sinal": nome, "n": len(idx), "eventos": sum(y), "ativos": sum(s), "razao_de_risco": rr, "rr_ic95": [li, ls], "rr_boot_validas": nb,
            "pr_auc": pr_s, "pr_auc_b0": b0, "pr_auc_b1": pr_b1, "pr_auc_b2": pr_b2, "pr_auc_b3": pr_b3,
            "falsos_alertas_por_100": M.falsos_alertas_por_100(s, y), "_ativacoes": ativ, "_cl": cl, "_s": s, "_y": y}


def rodar(dados, rotulos, grupos=None, fim_obs=C.JANELA_FIM, origem="sintetico"):
    m = montar(dados, rotulos, fim_obs)
    linhas = m["linhas"]
    usavel = [i for i, l in enumerate(linhas) if l["usavel_180"] and not l["formulacao"]]
    idx = {p: [i for i in usavel if linhas[i]["particao"] == p] for p in ("treino", "validacao", "teste")}
    n_embargo_usado = sum(1 for i in usavel if linhas[i]["particao"] == "embargo" and i in set(sum(idx.values(), [])))
    assert n_embargo_usado == 0, "embargo nunca entra"
    eventos_teste = [(ep["cnpj"], ep["inicio"]) for ep in m["episodios"] if not ep["prevalente"] and C.particao(ep["inicio"]) == "teste"
                     and ep["cnpj"] not in set(m["formulacao"])]
    g1c = {"eventos_janela": m["n_incidentes"], "eventos_teste_sem_formulacao": len(eventos_teste),
           "passa": m["n_incidentes"] >= 25 and len(eventos_teste) >= 10}
    hip = {}
    pvals = {}
    for nome in F.SINAIS_BINARIOS:
        r = avaliar_hipotese(nome, linhas, idx["teste"], grupos)
        if r.get("estado") == "sem_dado":
            hip[nome] = r
            pvals[nome] = None
            continue
        r["antecedencia"] = M.antecedencia(eventos_teste, r.pop("_ativacoes"))
        pvals[nome] = M.p_unilateral_rr(r.pop("_cl"), r.pop("_s"), r.pop("_y"))
        r["p_unilateral"] = pvals[nome]
        hip[nome] = r
    ph = M.holm(pvals)
    aprovados = []
    for nome, r in hip.items():
        if r.get("estado") == "sem_dado":
            r["g2"] = {"passa": False, "motivos": ["sem dado para medir"]}
            continue
        r["p_holm"] = ph.get(nome)
        passa, motivos = M.g2(r["rr_ic95"][0], r["antecedencia"]["mediana"], r["pr_auc"], r["pr_auc_b2"], r["p_holm"])
        r["g2"] = {"passa": passa, "motivos": motivos}
        if passa:
            aprovados.append(nome)
    g3 = {"estado": "nao_calculado", "motivo": "nenhum sinal aprovado em G2"}
    if aprovados:
        g3 = ajustar_g3(linhas, idx, aprovados[:MO.MAX_SINAIS_G3], grupos)
    return {"versao_pipeline": VERSAO_PIPELINE, "origem_dados": origem, "evidencia_de_eficacia": origem != "sintetico",
            "painel": P.resumo(linhas), "n_eventos": m["n_eventos"], "n_episodios": m["n_episodios"], "n_incidentes": m["n_incidentes"],
            "securitizadoras_fora": len(m["securitizadoras"]), "formulacao_fora": m["formulacao"],
            "linhas_por_particao": {p: len(v) for p, v in idx.items()}, "g1c": g1c, "hipoteses": hip, "aprovados_g2": aprovados, "g3": g3,
            "declaracoes": ["IC95 por cluster de CNPJ (sem mapeamento FRE de controle: cada CNPJ e seu proprio cluster)" if not grupos else "IC95 por cluster de controle (FRE)",
                            "H5 depende de COTAHIST e Selic; sem eles sai 'sem_dado'", "H2a/H2b sem ITR usam so DFP",
                            "mapeamento de contas do H6/B1/B2 e proposta (dados.CONTAS), a congelar como G0-v1-anexo-contas antes de metrica real"]}


def ajustar_g3(linhas, idx, sinais, grupos=None):
    def X(ii):
        return [[float(linhas[i][s] or 0) for s in sinais] for i in ii]

    def y(ii):
        return [linhas[i]["y180"] for i in ii]
    tr = [i for i in idx["treino"] if all(linhas[i].get(s) is not None for s in sinais)]
    va = [i for i in idx["validacao"] if all(linhas[i].get(s) is not None for s in sinais)]
    te = [i for i in idx["teste"] if all(linhas[i].get(s) is not None for s in sinais) and linhas[i].get("B2") is not None]
    if len(tr) < 30 or len(va) < 10 or len(te) < 10 or sum(y(tr)) == 0 or sum(y(va)) == 0:
        return {"estado": "insuficiente", "n": {"treino": len(tr), "validacao": len(va), "teste": len(te)}}
    mod = MO.ajustar_logit(X(tr), y(tr))
    ab = MO.platt(MO.prever_logit(mod, X(va)), y(va))
    p = MO.aplicar_platt(ab, MO.prever_logit(mod, X(te)))
    yt = y(te)
    base = sum(y(tr)) / len(tr)
    p0 = [base] * len(te)
    # B2 como probabilidade: logit univariado em treino + Platt na validacao, mesma receita
    m2 = MO.ajustar_logit([[linhas[i]["B2"]] for i in tr if linhas[i]["B2"] is not None], [linhas[i]["y180"] for i in tr if linhas[i]["B2"] is not None])
    ab2 = MO.platt(MO.prever_logit(m2, [[linhas[i]["B2"]] for i in va if linhas[i]["B2"] is not None]), [linhas[i]["y180"] for i in va if linhas[i]["B2"] is not None])
    p2 = MO.aplicar_platt(ab2, MO.prever_logit(m2, [[linhas[i]["B2"]] for i in te]))
    cl = defaultdict(list)
    for j, i in enumerate(te):
        cl[(grupos or {}).get(linhas[i]["cnpj"], linhas[i]["cnpj"])].append(j)
    li, ls, _ = M.bootstrap_cluster(cl, lambda ii: MO.inclinacao_calibracao([p[k] for k in ii], [yt[k] for k in ii]))
    bs0, bs2 = M.brier_skill(p, yt, p0), M.brier_skill(p, yt, p2)
    passa, motivos = M.g3(bs0, bs2, (li, ls))
    # regra de simplicidade: melhor sinal unico
    melhor = None
    for s in sinais:
        ms = MO.ajustar_logit([[float(linhas[i][s] or 0)] for i in tr], y(tr))
        abs_ = MO.platt(MO.prever_logit(ms, [[float(linhas[i][s] or 0)] for i in va]), y(va))
        ps = MO.aplicar_platt(abs_, MO.prever_logit(ms, [[float(linhas[i][s] or 0)] for i in te]))
        b = M.brier(ps, yt)
        if melhor is None or b < melhor[1]:
            melhor = (s, b)
    return {"estado": "calculado", "sinais": sinais, "beta": mod["beta"], "platt": list(ab), "brier": M.brier(p, yt), "brier_b0": M.brier(p0, yt),
            "brier_b2": M.brier(p2, yt), "brier_skill_b0": bs0, "brier_skill_b2": bs2, "inclinacao_ic95": [li, ls],
            "passa": passa, "motivos": motivos, "melhor_sinal_unico": {"sinal": melhor[0], "brier": melhor[1]},
            "n": {"treino": len(tr), "validacao": len(va), "teste": len(te)}}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sintetico", action="store_true")
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--rotulos", help="CSV de rotulos congelado (modo real)")
    ap.add_argument("--saida", help="arquivo JSON de saida")
    a = ap.parse_args(argv)
    if a.sintetico:
        import sintetico
        d = sintetico.gerar()
        r = rodar(d, d["rotulos"], origem="sintetico")
    elif a.real:
        import guarda_treino
        guarda_treino.exigir("backtest real")  # sai com exit 1 sem ler nada se nao homologado
        import dados as D
        docs, _ = D.ler_ipe()
        dfp, _ = D.ler_dfp()
        itr, _ = D.ler_dfp(itr=True)
        precos, _ = D.ler_cotahist()
        selic, _ = D.ler_selic()
        r = rodar({"docs": docs, "cad": D.ler_cad(), "dfp": dfp, "itr": itr, "precos": precos, "selic": selic}, EV.ler_rotulos(a.rotulos), origem="real")
    else:
        ap.print_help()
        return 2
    txt = json.dumps(r, ensure_ascii=False, indent=1, default=str)
    if a.saida:
        with open(a.saida, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(txt)
    print(txt if not a.saida else json.dumps({k: r[k] for k in ("origem_dados", "n_incidentes", "g1c", "aprovados_g2")}, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main())
