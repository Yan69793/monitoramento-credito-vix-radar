"""Prova de duas pontas da regra G1b da nota 116, sobre o mesmo u_sup do dimensionar_g1b.py.

Cada caminho de aprovacao indevida tem um teste que reprova o caso ruim e outro que aceita o bom.
"""
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402

A = DG.ALFA / 2


def g1b(K_candidatos, estratos):
    """estratos: lista de (N, n, x_evento, x_incerto). K so da uniao de candidatos.
    Incerto que a adjudicacao nao decide conta como evento novo. Devolve (passa, U, revocacao)."""
    mmax = math.floor(K_candidatos / 9)
    U = sum(DG.u_sup(x + inc, n, N, A) for N, n, x, inc in estratos)
    return U <= mmax, U, K_candidatos / (K_candidatos + U)


# 1. Censo de G nao aprova por construcao
def test_censo_acima_da_meta_reprova():
    passa, U, rev = g1b(60, [(402, 402, 5, 0), (2505, 2505, 2, 0)])
    assert (passa, U) == (False, 7) and rev < 0.90


def test_censo_dentro_da_meta_aprova():
    passa, U, rev = g1b(60, [(402, 402, 4, 0), (2505, 2505, 2, 0)])
    assert (passa, U) == (True, 6) and rev >= 0.90


# 2. Evento recuperado em G nao infla K
def test_k_inflado_por_recuperado_reprova():
    est = [(402, 402, 7, 0), (2505, 2505, 0, 0)]
    assert g1b(56, est)[0] is False            # K da uniao: M_max 6, perdeu 7
    assert g1b(56 + 7, est)[0] is True         # o mesmo caso passaria se o recuperado entrasse em K


def test_k_legitimo_maior_aprova():
    assert g1b(63, [(402, 402, 7, 0), (2505, 2505, 0, 0)])[0] is True


# 3. Incerto nao vira nao_evento no G1b
def test_incerto_conta_como_evento_reprova():
    assert g1b(60, [(402, 402, 6, 1), (2505, 2505, 0, 0)])[0] is False


def test_sem_incerto_aprova():
    assert g1b(60, [(402, 402, 6, 0), (2505, 2505, 0, 0)])[0] is True


# 4. Amostra de W com evento achado nao aprova sem estender
def test_evento_em_W_amostrado_reprova():
    passa, U, _ = g1b(60, [(402, 400, 0, 0), (2505, 1165, 1, 0)])
    assert passa is False and U > 6


def test_tamanho_da_tabela_com_zero_aprova():
    assert g1b(60, [(402, 400, 0, 0), (2505, 1165, 0, 0)])[0] is True


def test_um_passo_abaixo_da_tabela_reprova():
    assert g1b(60, [(402, 400, 0, 0), (2505, 1160, 0, 0)])[0] is False


# 5. Segunda leitura de G: classe que nao conta no x do primeiro rotulador nao fecha sozinha
NAO_CONTA = ("nao_evento", "continuacao", "evento_terceiro")


def rotulo_final_G(primeiro, segundo=None, operador=None):
    """Rotulo final de item de G para o G1b. nao_evento, continuacao e evento_terceiro do primeiro tem segunda
    leitura obrigatoria. Segunda leitura evento_proprio ou incerto vai ao operador; sem decisao dele, fica incerto."""
    if primeiro not in NAO_CONTA:
        return operador or primeiro
    if segundo is None:
        raise ValueError(f"{primeiro} de G sem segunda leitura")
    if segundo in ("evento_proprio", "incerto"):
        return operador or "incerto"
    return primeiro


def K_final(itens_uniao):
    """K so conta evento_proprio final. Discordancia nao resolvida na uniao vira incerto e fica fora de K."""
    return sum(1 for primeiro, segundo, operador in itens_uniao
               if (operador or (primeiro if segundo in (None, primeiro) else "incerto")) == "evento_proprio")


def x_G(itens):
    finais = [rotulo_final_G(*it) for it in itens]
    return finais.count("evento_proprio"), finais.count("incerto")


def test_sem_segunda_leitura_reprova():
    try:
        rotulo_final_G("nao_evento")
    except ValueError:
        return
    raise AssertionError("nao_evento sem segunda leitura foi aceito")


def test_falso_negativo_pego_pela_segunda_leitura_reprova():
    itens = [("evento_proprio", None, None)] * 6 + [("nao_evento", "evento_proprio", None)]
    x, inc = x_G(itens)
    assert (x, inc) == (6, 1)
    assert g1b(60, [(402, 402, x, inc), (2505, 2505, 0, 0)])[0] is False


def test_operador_confirma_falso_negativo_reprova():
    itens = [("evento_proprio", None, None)] * 6 + [("nao_evento", "incerto", "evento_proprio")]
    assert x_G(itens) == (7, 0)


def test_segunda_leitura_concorda_aprova():
    itens = [("evento_proprio", None, None)] * 6 + [("nao_evento", "nao_evento", None),
                                                    ("nao_evento", "continuacao", None)]
    x, inc = x_G(itens)
    assert (x, inc) == (6, 0)
    assert g1b(60, [(402, 402, x, inc), (2505, 2505, 0, 0)])[0] is True


def test_operador_afasta_discordancia_aprova():
    itens = [("evento_proprio", None, None)] * 6 + [("nao_evento", "evento_proprio", "nao_evento")]
    assert x_G(itens) == (6, 0)


def test_continuacao_e_terceiro_sem_segunda_leitura_reprovam():
    for classe in ("continuacao", "evento_terceiro"):
        try:
            rotulo_final_G(classe)
        except ValueError:
            continue
        raise AssertionError(f"{classe} sem segunda leitura foi aceito")


def test_falso_negativo_em_continuacao_ou_terceiro_reprova():
    for classe in ("continuacao", "evento_terceiro"):
        itens = [("evento_proprio", None, None)] * 6 + [(classe, "evento_proprio", None)]
        x, inc = x_G(itens)
        assert (x, inc) == (6, 1)
        assert g1b(60, [(402, 402, x, inc), (2505, 2505, 0, 0)])[0] is False


def test_troca_entre_classes_que_nao_contam_aprova():
    itens = [("evento_proprio", None, None)] * 6 + [("continuacao", "nao_evento", None),
                                                    ("evento_terceiro", "continuacao", None)]
    x, inc = x_G(itens)
    assert (x, inc) == (6, 0)
    assert g1b(60, [(402, 402, x, inc), (2505, 2505, 0, 0)])[0] is True


# 6. Discordancia nao resolvida nunca aprova: nem sobe x como zero em G, nem infla K na uniao
def test_discordancia_nao_resolvida_em_qualquer_classe_nunca_aprova():
    for classe in NAO_CONTA:
        for segundo in ("evento_proprio", "incerto"):
            itens = [("evento_proprio", None, None)] * 6 + [(classe, segundo, None)]
            assert g1b(60, [(402, 402, *x_G(itens)), (2505, 2505, 0, 0)])[0] is False


def test_discordancia_nao_resolvida_na_uniao_nao_infla_K_reprova():
    uniao = [("evento_proprio", None, None)] * 56 + [("evento_proprio", "nao_evento", None)] * 7
    assert K_final(uniao) == 56
    assert g1b(K_final(uniao), [(402, 402, 7, 0), (2505, 2505, 0, 0)])[0] is False


def test_discordancia_resolvida_pelo_operador_na_uniao_aprova():
    uniao = [("evento_proprio", None, None)] * 56 + [("evento_proprio", "nao_evento", "evento_proprio")] * 7
    assert K_final(uniao) == 63
    assert g1b(K_final(uniao), [(402, 402, 7, 0), (2505, 2505, 0, 0)])[0] is True


# 7. Origem de continuacao descoberta pela uniao e evento perdido, deduplicado por evento real
from datetime import date, timedelta  # noqa: E402

N_n = {"F": (402, 402), "W": (2505, 2505)}


def item(estrato, classe, cnpj, protocolo, data, origens=()):
    """origens: lista de (protocolo, data, no_escopo). Classe e o rotulo final do item de G."""
    return {"estrato": estrato, "classe": classe, "cnpj": cnpj, "protocolo": protocolo, "data": data,
            "origens": list(origens)}


def _coberto(cnpj, d, eventos_uniao):
    return any(c == cnpj and abs((d - e).days) <= 30 for c, e in eventos_uniao)


def eventos_perdidos_G(itens, eventos_uniao):
    """Regra nova. Devolve {(cnpj, protocolo do primeiro documento): conjunto de estratos}."""
    ev = {}
    for it in itens:
        c, cl = it["cnpj"], it["classe"]
        chaves = []
        if cl == "incerto" or (cl == "continuacao" and not it["origens"]):
            chaves = [(c, it["protocolo"])]
        elif cl == "evento_proprio" and not _coberto(c, it["data"], eventos_uniao):
            chaves = [(c, it["protocolo"])]
        elif cl == "continuacao":
            chaves = [(c, p) for p, d, no_escopo in it["origens"] if no_escopo and not _coberto(c, d, eventos_uniao)]
        for k in chaves:
            ev.setdefault(k, set()).add(it["estrato"])
    return ev


def eventos_perdidos_G_antiga(itens, eventos_uniao):
    """Regra antiga: so evento_proprio e incerto de G, continuacao nunca conta."""
    return eventos_perdidos_G([it for it in itens if it["classe"] != "continuacao"], eventos_uniao)


def x_por_estrato(ev, N_n=N_n):
    """Um evento, um estrato. Alcancado por F e W, vai para onde +1 em x_h da o maior U_F + U_W."""
    x = {"F": 0, "W": 0}
    ambos = []
    for estratos in ev.values():
        if len(estratos) == 1:
            x[next(iter(estratos))] += 1
        else:
            ambos.append(estratos)

    def U(xs):
        return sum(DG.u_sup(xs[h], N_n[h][1], N_n[h][0], A) for h in xs)

    for _ in ambos:
        h = max(("F", "W"), key=lambda s: U({**x, s: x[s] + 1}))
        x[h] += 1
    return x


def g1b_itens(K, itens, eventos_uniao, regra=eventos_perdidos_G, N_n=N_n):
    x = x_por_estrato(regra(itens, eventos_uniao), N_n)
    return g1b(K, [(N_n["F"][0], N_n["F"][1], x["F"], 0), (N_n["W"][0], N_n["W"][1], x["W"], 0)])


D0 = date(2024, 3, 1)
UNIAO = [("11", D0)]
SEIS = [item("F", "evento_proprio", f"9{i}", f"P9{i}", D0) for i in range(6)]


def test_origem_descoberta_com_concordancia_reprova_e_antiga_aprovava():
    itens = SEIS + [item("F", "continuacao", "22", "Pc", D0, [("Po", D0 - timedelta(days=200), True)])]
    assert g1b_itens(60, itens, UNIAO)[0] is False
    assert g1b_itens(60, itens, UNIAO, regra=eventos_perdidos_G_antiga)[0] is True  # aprovacao indevida


def test_origem_coberta_pela_uniao_aprova():
    itens = SEIS + [item("F", "continuacao", "11", "Pc", D0 + timedelta(days=90),
                         [("Po", D0 + timedelta(days=20), True)])]
    assert g1b_itens(60, itens, UNIAO)[0] is True


def test_origem_a_31_dias_da_uniao_reprova():
    itens = SEIS + [item("F", "continuacao", "11", "Pc", D0 + timedelta(days=90),
                         [("Po", D0 + timedelta(days=31), True)])]
    assert g1b_itens(60, itens, UNIAO)[0] is False


def test_origem_fora_da_regua_de_K_aprova():
    itens = SEIS + [item("F", "continuacao", "22", "Pc", D0, [("Po", D0 - timedelta(days=900), False)])]
    assert g1b_itens(60, itens, UNIAO)[0] is True


def test_continuacao_sem_origem_reprova():
    itens = SEIS + [item("F", "continuacao", "22", "Pc", D0)]
    assert g1b_itens(60, itens, UNIAO)[0] is False


def test_dedup_por_evento_real_aprova_e_por_documento_reprovaria():
    cinco = SEIS[:5]
    mesma = [item("F", "continuacao", "22", f"Pc{i}", D0 + timedelta(days=60 * i), [("Po", D0, True)])
             for i in range(3)]
    ev = eventos_perdidos_G(cinco + mesma, UNIAO)
    assert len(ev) == 6
    assert g1b_itens(60, cinco + mesma, UNIAO)[0] is True
    assert g1b(60, [(402, 402, 5 + len(mesma), 0), (2505, 2505, 0, 0)])[0] is False  # contagem por documento


def test_origem_igual_ao_evento_proprio_de_G_conta_uma_vez():
    itens = SEIS[:5] + [item("F", "evento_proprio", "22", "Po", D0),
                        item("F", "continuacao", "22", "Pc", D0 + timedelta(days=120), [("Po", D0, True)])]
    assert len(eventos_perdidos_G(itens, UNIAO)) == 6
    assert g1b_itens(60, itens, UNIAO)[0] is True


def test_divergencia_de_origem_sem_decisao_conta_a_descoberta_reprova():
    itens = SEIS + [item("F", "continuacao", "11", "Pc", D0 + timedelta(days=90),
                         [("Pa", D0 + timedelta(days=10), True), ("Pb", D0 - timedelta(days=300), True)])]
    assert g1b_itens(60, itens, UNIAO)[0] is False


def test_evento_em_F_e_W_vai_ao_estrato_conservador():
    nn = {"F": (402, 400), "W": (2505, 1165)}
    itens = [item("F", "continuacao", "22", "Pc", D0, [("Po", D0 - timedelta(days=200), True)]),
             item("W", "continuacao", "22", "Pw", D0 + timedelta(days=40), [("Po", D0 - timedelta(days=200), True)])]
    x = x_por_estrato(eventos_perdidos_G(itens, UNIAO), nn)
    assert sum(x.values()) == 1 and x["W"] == 1
    uF = DG.u_sup(1, 400, 402, A) + DG.u_sup(0, 1165, 2505, A)
    uW = DG.u_sup(0, 400, 402, A) + DG.u_sup(1, 1165, 2505, A)
    assert uW > uF


def test_K_nao_muda_com_origens_de_G():
    itens = SEIS + [item("F", "continuacao", "22", "Pc", D0, [("Po", D0 - timedelta(days=200), True)])]
    _, _, rev = g1b_itens(60, itens, UNIAO)
    assert abs(rev - 60 / (60 + 7)) < 1e-12


if __name__ == "__main__":
    for nome, f in list(globals().items()):
        if nome.startswith("test_"):
            f()
            print("ok", nome)
