"""Validade estatistica e contagem de eventos do G1b (nota 116), com contraprova contra a regra anterior.

Parte I   cobertura exata do limite hipergeometrico (derivacao numerica, sem simulacao).
Parte II  documento amostrado x episodio estimado: acoplamento e simulacao deterministica.
Parte III procedimento inteiro (amostra, censo de recurso, Bonferroni), simulacao deterministica.
Parte IV  contagem de K e de perdidos: cada defeito da regra anterior reprova la e passa aqui, e vice-versa.
Sementes 7101 a 7199 sao so de teste, nao sao sementes do protocolo.
"""
import functools, math, os, random, sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402
import g1b_v2 as V2  # noqa: E402
import test_g1b_regra as ANT  # noqa: E402  regra anterior, intocada

A = V2.A
TAM60 = {"F": (402, 400), "W": (2505, 1165)}  # tabela da nota 116, K = 60


@functools.lru_cache(maxsize=None)
def U(x, n, N):
    return DG.u_sup(x, n, N, A)


def pmf_hiper(k, N, M, n):
    return math.exp(DG.lcomb(M, k) + DG.lcomb(N - M, n - k) - DG.lcomb(N, n))


# ---------------- Parte I ----------------
def cobertura_exata(N, n, M):
    lo, hi = max(0, n - (N - M)), min(M, n)
    return sum(pmf_hiper(k, N, M, n) for k in range(lo, hi + 1) if U(k, n, N) >= M)


def test_cobertura_exata_do_limite_por_estrato():
    for N, n in ((402, 210), (402, 400), (2505, 540), (2505, 1165)):
        pior = min(cobertura_exata(N, n, M) for M in range(0, 41))
        assert pior >= 1 - A - 1e-12, (N, n, pior)


def test_limite_e_monotono_em_x():
    for N, n in ((402, 210), (2505, 540)):
        us = [U(x, n, N) for x in range(15)]
        assert us == sorted(us)


# ---------------- Parte II ----------------
def cobertura_mc(N, n, mult, reps, seed):
    """mult: numero de chaves de cada episodio, chaves disjuntas. d = episodios com alguma chave sorteada."""
    rng = random.Random(seed)
    dono, i = {}, 0
    for e, m in enumerate(mult):
        for _ in range(m):
            dono[i] = e
            i += 1
    D, ok = len(mult), 0
    for _ in range(reps):
        d = len({dono[k] for k in rng.sample(range(N), n) if k in dono})
        ok += U(d, n, N) >= D
    return ok / reps


def test_multiplicidade_documental_nao_quebra_cobertura():
    # episodios com 1 a 6 chaves: d e estocasticamente maior que a hipergeometrica dos representantes
    for mult in ([1] * 8, [3] * 8, [1, 2, 3, 4, 5, 6, 1, 1], [6] * 12):
        cob = cobertura_mc(2505, 540, mult, 4000, 7101)
        assert cob >= 1 - A - 3 * math.sqrt(A * (1 - A) / 4000), (mult, cob)


def test_dois_episodios_numa_chave_so_quebram_cobertura():
    # contraprova da invariante "um evento principal por chave": 2 episodios cuja unica chave e a mesma
    N, n = 2505, 2300
    assert U(0, n, N) == 1
    falha = 1 - n / N  # P(chave nao sorteada) = P(d = 0) e U(0) = 1 < 2
    assert falha > 6 * A


def test_rotulo_tem_um_evento_principal_por_chave():
    it = {"cnpj": "1", "classe": "continuacao", "data": date(2024, 6, 1), "divergente": True,
          "origens": [("Pa", date(2023, 1, 1), True), ("Pb", date(2023, 9, 1), True)]}
    p, _ = V2.eventos_do_item(it)
    assert p[0] == "divergente" and len(V2.perdidos_v2([{**it, "estrato": "F"}], [])) == 1


# ---------------- Parte III ----------------
def decide(sF, sW, popF, popW, K, tam, atrib):
    """Procedimento do item 4: amostra; se falha, censo do estrato com evento novo; se falha, censo do outro.
    Censo de h: x_h vira a contagem exata dos episodios com chave em h, e o outro estrato conta so o que h nao tem."""
    perd = [({"F"} if e in sF else set()) | ({"W"} if e in sW else set()) for e in sF | sW]
    x = atrib(perd, tam)
    if V2.g1b_v2(K, x, tam)[0]:
        return True
    ordem = [h for h in ("F", "W") if x[h] > 0] + [h for h in ("F", "W") if x[h] == 0]
    censo = set()
    for h in ordem:
        censo.add(h)
        t = {g: ((tam[g][0], tam[g][0]) if g in censo else tam[g]) for g in tam}
        if censo == {"F", "W"}:
            x = {"F": len(popF), "W": len(popW - popF)}
        elif h == "F":
            x = {"F": len(popF), "W": len(sW - popF)}
        else:
            x = {"F": len(sF - popW), "W": len(popW)}
        if V2.g1b_v2(K, x, t)[0]:
            return True
    return False


def simula(config, K, tam, reps, seed, atrib=V2.x_por_estrato_v2):
    """config: lista de episodios, cada um (chaves_em_F, chaves_em_W). Devolve taxa de aprovacao."""
    rng = random.Random(seed)
    NF, NW = tam["F"][0], tam["W"][0]
    dono_F, dono_W, iF, iW = {}, {}, 0, 0
    for e, (cf, cw) in enumerate(config):
        for _ in range(cf):
            dono_F[iF] = e
            iF += 1
        for _ in range(cw):
            dono_W[iW] = e
            iW += 1
    D = len(config)
    popF, popW = set(dono_F.values()), set(dono_W.values())
    aprov = 0
    for _ in range(reps):
        sF = {dono_F[k] for k in rng.sample(range(NF), tam["F"][1]) if k in dono_F}
        sW = {dono_W[k] for k in rng.sample(range(NW), tam["W"][1]) if k in dono_W}
        aprov += decide(sF, sW, popF, popW, K, tam, atrib) and D > math.floor(K / 9)
    return aprov / reps


def test_procedimento_inteiro_controla_aprovacao_indevida():
    tol = 3 * math.sqrt(0.025 * 0.975 / 3000)
    casos = {
        "7 em W, uma chave": [(0, 1)] * 7,
        "7 em W, tres chaves": [(0, 3)] * 7,
        "3 em F e 4 em W": [(1, 0)] * 3 + [(0, 1)] * 4,
        "7 em F e W": [(1, 2)] * 7,
        "2 em F, 5 em W com 2 chaves": [(1, 0)] * 2 + [(0, 2)] * 5,
    }
    for nome, cfg in casos.items():
        taxa = simula(cfg, 60, TAM60, 3000, 7110)
        assert taxa <= 0.025 + tol, (nome, taxa)


def aprovacao(config, K, tam, reps, seed):
    rng = random.Random(seed)
    dF = {i: e for e, (cf, _) in enumerate(config) for i in [e] if cf}
    dW = {i: e for e, (_, cw) in enumerate(config) for i in [e] if cw}
    ok = 0
    for _ in range(reps):
        sF = {dF[k] for k in rng.sample(range(tam["F"][0]), tam["F"][1]) if k in dF}
        sW = {dW[k] for k in rng.sample(range(tam["W"][0]), tam["W"][1]) if k in dW}
        ok += decide(sF, sW, set(dF.values()), set(dW.values()), K, tam, V2.x_por_estrato_v2)
    return ok / reps


def test_procedimento_aprova_quando_deve():
    # outra ponta: com D <= M_max o procedimento inteiro (amostra e censo de recurso) nunca reprova
    for cfg in ([], [(1, 0)] * 6, [(0, 1)] * 6, [(1, 0)] * 3 + [(0, 1)] * 3):
        assert aprovacao(cfg, 60, TAM60, 300, 7112) == 1.0, cfg


def test_atribuicao_exaustiva_domina_regra_fixa_e_gulosa():
    # a prova de cobertura usa o representante fixo "F se o episodio tem chave em F"; a regra tem de dar U >= o dele
    for tam in (TAM60, {"F": (402, 210), "W": (2505, 540)}, {"F": (402, 300), "W": (2505, 765)}):
        for a, b, c in ((0, 0, 3), (1, 0, 2), (0, 2, 4), (2, 3, 5)):
            perd = [{"F"}] * a + [{"W"}] * b + [{"F", "W"}] * c
            def tot(x):
                return sum(U(x[h], tam[h][1], tam[h][0]) for h in x)
            fixo = tot({"F": a + c, "W": b})
            assert tot(V2.x_por_estrato_v2(perd, tam)) >= fixo
            assert tot(V2.x_por_estrato_v2(perd, tam)) >= tot(V2.x_por_estrato_guloso(perd, tam))


# ---------------- Parte IV ----------------
D0 = date(2024, 3, 1)


def ev(cnpj, data, estrato="F", **kw):
    return {"cnpj": cnpj, "classe": "evento_proprio", "data": data, "data_evento": data, "estrato": estrato, **kw}


def cont(cnpj, data, origens, estrato="F", **kw):
    return {"cnpj": cnpj, "classe": "continuacao", "data": data, "origens": origens, "estrato": estrato, **kw}


SEIS_G = [ev(f"9{i}", D0) for i in range(6)]


def x_antigo(itens_G, uniao_ep_datas):
    """Regra anterior de test_g1b_regra: chave (cnpj, protocolo), sem escopo do evento_proprio, sem episodio."""
    conv = []
    for i, it in enumerate(itens_G):
        orig = [(p, d, esc) for p, d, esc in it.get("origens", [])]
        conv.append(ANT.item(it["estrato"], it["classe"], it["cnpj"], it.get("protocolo", f"P{i}"),
                             it.get("data_evento", it["data"]), orig))
    return ANT.x_por_estrato(ANT.eventos_perdidos_G(conv, uniao_ep_datas), {"F": (402, 402), "W": (2505, 2505)})


def g1b_novo(K_itens_uniao, itens_G, tam={"F": (402, 402), "W": (2505, 2505)}):
    K, nos = V2.K_v2(K_itens_uniao)
    return V2.g1b_v2(K, V2.x_por_estrato_v2(V2.perdidos_v2(itens_G, nos), tam), tam)


UNIAO60 = [ev(f"U{i}", D0 + timedelta(days=i)) for i in range(60)]


def test_evento_de_G_fora_da_janela_nao_conta_e_antigo_contava():
    fora = ev("22", date(2010, 6, 1), no_escopo=False)  # primeiro documento publico antes da janela
    x_old = x_antigo(SEIS_G + [fora], [(it["cnpj"], it["data"]) for it in UNIAO60])
    assert ANT.g1b(60, [(402, 402, x_old["F"], 0), (2505, 2505, x_old["W"], 0)])[0] is False  # reprovacao indevida
    assert g1b_novo(UNIAO60, SEIS_G + [fora])[0] is True
    dentro = ev("22", date(2015, 6, 1))
    assert g1b_novo(UNIAO60, SEIS_G + [dentro])[0] is False


def test_origem_de_continuacao_da_uniao_entra_em_K_e_cobre_G():
    # a uniao viu o processo pela continuacao; o primeiro documento (D0) caiu em G
    uniao = UNIAO60[:59] + [cont("22", D0 + timedelta(days=200), [("Po", D0, True)])]
    g = SEIS_G + [ev("22", D0)]
    K_old = sum(1 for it in uniao if it["classe"] == "evento_proprio")
    x_old = x_antigo(g, [(it["cnpj"], it["data"]) for it in uniao if it["classe"] == "evento_proprio"])
    assert (K_old, x_old["F"]) == (59, 7)
    assert ANT.g1b(K_old, [(402, 402, 7, 0), (2505, 2505, 0, 0)])[0] is False  # reprovacao indevida
    assert V2.K_v2(uniao)[0] == 60 and g1b_novo(uniao, g)[0] is True


def test_origem_da_uniao_nao_resolvida_fica_fora_de_K():
    uniao = UNIAO60[:59] + [cont("22", D0 + timedelta(days=200), [("Pa", D0, True), ("Pb", D0 - timedelta(days=90), True)],
                                 divergente=True)]
    assert V2.K_v2(uniao)[0] == 59
    assert g1b_novo(uniao, SEIS_G + [ev("22", D0)])[0] is False  # nao cobre, nem infla K


def test_duas_continuacoes_da_uniao_do_mesmo_processo_nao_inflam_K():
    a = cont("22", D0 + timedelta(days=200), [("Po", D0, True)])
    b = cont("22", D0 + timedelta(days=400), [("Po2", D0 + timedelta(days=1), True)])  # protocolo errado, mesmo dia +1
    assert V2.K_v2(UNIAO60[:58] + [a, b])[0] == 59


def test_mesmo_evento_com_protocolos_diferentes_conta_uma_vez():
    g = SEIS_G[:5] + [ev("22", D0, protocolo="Pa"), ev("22", D0 + timedelta(days=1), protocolo="Pb")]
    x_old = x_antigo(g, [(it["cnpj"], it["data"]) for it in UNIAO60])
    assert x_old["F"] == 7  # antiga: dois eventos
    assert g1b_novo(UNIAO60, g)[0] is True and V2.x_por_estrato_v2(V2.perdidos_v2(g, V2.K_v2(UNIAO60)[1]),
                                                                      {"F": (402, 402), "W": (2505, 2505)})["F"] == 6


def test_divergencia_de_origem_conta_um_evento_nao_dois():
    g = SEIS_G[:5] + [cont("22", D0, [("Pa", D0 - timedelta(days=100), True), ("Pb", D0 - timedelta(days=300), True)],
                           divergente=True)]
    x_old = x_antigo(g, [(it["cnpj"], it["data"]) for it in UNIAO60])
    assert x_old["F"] == 7
    assert g1b_novo(UNIAO60, g)[0] is True


def test_divergencia_com_uma_origem_coberta_continua_contando_a_descoberta():
    uniao = UNIAO60[:59] + [ev("22", D0)]
    g = SEIS_G + [cont("22", D0 + timedelta(days=400), [("Pa", D0 + timedelta(days=10), True),
                                                       ("Pb", D0 + timedelta(days=300), True)], divergente=True)]
    assert g1b_novo(uniao, g)[0] is False


def test_evento_simultaneo_adicional_conta_e_nao_se_perde():
    g = SEIS_G[:5] + [ev("22", D0, adicionais=[(D0 - timedelta(days=200), True)])]
    assert g1b_novo(UNIAO60, g)[0] is False
    assert g1b_novo(UNIAO60, SEIS_G[:5] + [ev("22", D0)])[0] is True


def test_episodio_a_ate_30_dias_da_uniao_esta_coberto_e_a_31_nao():
    uniao = UNIAO60[:59] + [ev("22", D0)]
    assert g1b_novo(uniao, SEIS_G + [ev("22", D0 + timedelta(days=30))])[0] is True
    assert g1b_novo(uniao, SEIS_G + [ev("22", D0 + timedelta(days=31))])[0] is False


def test_incerto_de_G_conta_mesmo_perto_da_uniao():
    uniao = UNIAO60[:59] + [ev("22", D0)]
    inc = {"cnpj": "22", "classe": "incerto", "data": D0 + timedelta(days=5), "estrato": "W"}
    assert g1b_novo(uniao, SEIS_G + [inc])[0] is False


# segunda leitura da uniao: so os itens que entram em K
def rotulo_final_uniao(primeiro, segundo=None, operador=None):
    """evento_proprio e continuacao da uniao entram em K e exigem segunda leitura. Discordancia sobre a classe que
    entra em K, sem decisao do operador, vira incerto e sai de K. As outras classes valem como estao."""
    if primeiro not in ("evento_proprio", "continuacao"):
        return operador or primeiro
    if segundo is None:
        raise ValueError(f"{primeiro} da uniao sem segunda leitura")
    if segundo != primeiro:
        return operador or "incerto"
    return primeiro


def test_falso_positivo_da_uniao_inflava_K_e_aprovava():
    # 50 eventos reais e 10 falsos positivos de leitura unica: K antigo 60 (M_max 6) aprova 6 perdidos; real 50 (M_max 5), revocacao 89%
    leituras = [("evento_proprio", "evento_proprio", None)] * 50 + [("evento_proprio", "nao_evento", None)] * 10
    K_old = ANT.K_final([(p, None, o) for p, s, o in leituras])  # antiga: so os 60 do G1a tinham segunda leitura
    K_new = sum(1 for l in leituras if rotulo_final_uniao(*l) == "evento_proprio")
    assert (K_old, K_new) == (60, 50)
    g = [(402, 402, 6, 0), (2505, 2505, 0, 0)]
    assert ANT.g1b(K_old, g)[0] is True and ANT.g1b(K_new, g)[0] is False


def test_K_da_uniao_sem_segunda_leitura_e_recusado_e_concordante_passa():
    try:
        rotulo_final_uniao("evento_proprio")
    except ValueError:
        pass
    else:
        raise AssertionError("evento_proprio da uniao sem segunda leitura foi aceito")
    assert rotulo_final_uniao("continuacao", "continuacao") == "continuacao"
    assert rotulo_final_uniao("evento_proprio", "nao_evento", "evento_proprio") == "evento_proprio"
    assert rotulo_final_uniao("nao_evento") == "nao_evento"


if __name__ == "__main__":
    n = 0
    for nome, f in list(globals().items()):
        if nome.startswith("test_"):
            f()
            n += 1
            print("ok", nome)
    print("total", n)
