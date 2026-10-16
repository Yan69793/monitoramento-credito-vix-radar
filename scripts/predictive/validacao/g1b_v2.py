"""Regra de contagem do G1b da G0-v2 (nota 116), versao de 15/10/2026 noite. Somente leitura, sem IO.

Unidades:
  chave    (CNPJ, Data_Entrega), unidade amostrada de F e W e unidade rotulada da uniao.
  evento   o que o rotulo de uma chave aponta: data do primeiro documento publico (evento_proprio) ou origem (continuacao).
  episodio componente conexo de eventos do mesmo CNPJ cujas datas distam ate 30 dias, em cadeia. K e os x_h contam episodios.

Invariante que sustenta o limite hipergeometrico: cada chave tem UM evento principal. Eventos adicionais da mesma chave
(eventos simultaneos de outro processo) entram em x, o que so aumenta o limite, mas a cobertura nominal e provada para os
episodios alcancados por evento principal de chave de G. Ver test_g1b_validade.py.
"""
import itertools, math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dimensionar_g1b import u_sup, ALFA  # noqa: E402

A = ALFA / 2
DIAS = 30


def episodios(nos):
    """nos: lista de (cnpj, data, rotulo). Devolve lista de episodios, cada um lista de nos. Ligacao simples, ate DIAS."""
    por = {}
    for no in nos:
        por.setdefault(no[0], []).append(no)
    eps = []
    for lista in por.values():
        lista.sort(key=lambda n: n[1])
        atual = [lista[0]]
        for no in lista[1:]:
            if (no[1] - atual[-1][1]).days <= DIAS:
                atual.append(no)
            else:
                eps.append(atual)
                atual = [no]
        eps.append(atual)
    return eps


def eventos_do_item(it):
    """Eventos (data) que o rotulo final de um item aponta, ja na regua de K (universo, janela, registro).

    it: dict com cnpj, classe, data (Data_Entrega da chave), data_evento, no_escopo (do evento_proprio),
        origens [(protocolo, data, no_escopo)], adicionais [(data, no_escopo)], divergente (bool).
    Devolve (principal, adicionais): principal e None ou (data, conta_mesmo_coberto).
    """
    cl = it["classe"]
    adic = [d for d, esc in it.get("adicionais", ()) if esc]
    if cl == "incerto" or (cl == "continuacao" and not it.get("origens")):
        return ("incerto", it["data"]), adic
    if cl == "evento_proprio":
        return (("evento", it["data_evento"]) if it.get("no_escopo", True) else None), adic
    if cl == "continuacao":
        ds = sorted(d for _, d, esc in it["origens"] if esc)
        if not ds:
            return None, adic
        return (("divergente" if it.get("divergente") else "origem", ds)), adic
    return None, adic


def K_v2(itens_uniao):
    """K: episodios distintos da uniao, rotulo final depois da segunda leitura e da adjudicacao.
    evento_proprio e origem de continuacao contam. incerto e divergencia de origem nao resolvida ficam fora de K."""
    nos = []
    for it in itens_uniao:
        p, adic = eventos_do_item(it)
        if p and p[0] == "evento":
            nos.append((it["cnpj"], p[1], "U"))
        elif p and p[0] == "origem" and len(p[1]) == 1:
            nos.append((it["cnpj"], p[1][0], "U"))
        nos += [(it["cnpj"], d, "U") for d in adic]
    return (len(episodios(nos)) if nos else 0), nos


def perdidos_v2(itens_G, nos_uniao):
    """Episodios perdidos alcancados pelos itens rotulados de G. Devolve lista de conjuntos de estratos, um por episodio.

    Cada no de G carrega o estrato. Episodio com no da uniao esta coberto. incerto nunca e coberto (conta sempre).
    Divergencia de origem: um evento so, na menor origem nao coberta, ou coberto se todas estao a ate 30 dias da uniao."""
    nos = list(nos_uniao)
    forcados = []
    for it in itens_G:
        p, adic = eventos_do_item(it)
        h = it["estrato"]
        if p is None:
            pass
        elif p[0] == "incerto":
            forcados.append({h})
        elif p[0] == "evento":
            nos.append((it["cnpj"], p[1], h))
        else:
            descob = [d for d in p[1] if not any(c == it["cnpj"] and abs((d - du).days) <= DIAS
                                                 for c, du, _ in nos_uniao)]
            nos.append((it["cnpj"], (descob or p[1])[0], h))
        nos += [(it["cnpj"], d, h) for d in adic]
    perd = [{r for _, _, r in ep} for ep in episodios(nos) if nos and not any(r == "U" for _, _, r in ep)]
    return perd + forcados


def x_por_estrato_v2(perd, tam):
    """tam: {'F': (N, n), 'W': (N, n)}. Episodio so de um estrato vai a ele. Episodio de F e W: a divisao que da o
    maior U_F + U_W entre TODAS as divisoes possiveis, o que domina a atribuicao fixa 'F se tem chave em F'."""
    xF = sum(1 for s in perd if s == {"F"})
    xW = sum(1 for s in perd if s == {"W"})
    b = sum(1 for s in perd if s == {"F", "W"})

    def U(f, w):
        return u_sup(f, tam["F"][1], tam["F"][0], A) + u_sup(w, tam["W"][1], tam["W"][0], A)

    k = max(range(b + 1), key=lambda k: U(xF + k, xW + b - k))
    return {"F": xF + k, "W": xW + b - k}


def x_por_estrato_guloso(perd, tam):
    """Regra do rascunho anterior (um evento de cada vez, maximo local). Mantida so para contraprova."""
    x = {"F": sum(1 for s in perd if s == {"F"}), "W": sum(1 for s in perd if s == {"W"})}

    def U(xs):
        return sum(u_sup(xs[h], tam[h][1], tam[h][0], A) for h in xs)

    for _ in range(sum(1 for s in perd if s == {"F", "W"})):
        h = max(("F", "W"), key=lambda s: U({**x, s: x[s] + 1}))
        x[h] += 1
    return x


def g1b_v2(K, x, tam):
    mmax = math.floor(K / 9)
    U = sum(u_sup(x[h], tam[h][1], tam[h][0], A) for h in ("F", "W"))
    return U <= mmax, U, (K / (K + U) if K + U else 0.0)
