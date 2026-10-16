"""Metricas do item 9 e gates G2/G3 do item 10 da G0-v1. Puras, sobre listas; IC95 por bootstrap por cluster
(1.000 reamostras, semente 20261015, percentil). Cluster = componente de controle do FRE quando houver mapeamento;
sem FRE, cada CNPJ e cluster de si mesmo (declarado no relatorio).
"""
import math
import random
from collections import defaultdict

SEMENTE = 20261015
N_BOOT = 1000
RR_LI_MIN = 1.5
ANTECEDENCIA_MIN = 60
ALFA = 0.05
# G3-PRECISAO1 (decisao do operador, 16/10/2026, nota 122 secao 4.2): congelado ANTES de abrir o teste. Largura maxima
# do IC95 da inclinacao de calibracao; acima dela o G3 e "nao informativo", nunca "aprovado". 0.2 e o alvo padrao de
# precisao da inclinacao em Riley et al. (pmvalsampsize, csciwidth=0.2). Sem isso, IC largo contem 1 por falta de dado.
IC_INCLINACAO_LARGURA_MAX = 0.2
# G3-BLOCOS1 (mesma decisao, secao 4.3): sensibilidade de dependencia no tempo. Bootstrap em blocos nao sobrepostos de
# meses consecutivos; 6 meses porque o alvo e de 180 dias e linhas mensais vizinhas compartilham a mesma janela.
BLOCO_MESES = 6


def razao_de_risco(sinal, y):
    a = [yy for s, yy in zip(sinal, y) if s == 1]
    b = [yy for s, yy in zip(sinal, y) if s == 0]
    if not a or not b or sum(b) == 0:
        return None
    return (sum(a) / len(a)) / (sum(b) / len(b))


def pr_auc(escore, y):
    """Average precision (area sob a curva PR por degraus). Empates: ordem estavel por escore decrescente."""
    pares = sorted(zip(escore, y), key=lambda t: -t[0])
    pos = sum(y)
    if pos == 0:
        return None
    tp, ap = 0, 0.0
    for k, (_, yy) in enumerate(pares, 1):
        if yy:
            tp += 1
            ap += tp / k
    return ap / pos


def precision_at_k_mensal(linhas, escore_key, k=10):
    """linhas: dicts com T, y180 e o escore. Media mensal da fracao dos k maiores com evento."""
    por_T = defaultdict(list)
    for l in linhas:
        if l.get(escore_key) is not None:
            por_T[l["T"]].append((l[escore_key], l["y180"]))
    vals = []
    for t, lst in por_T.items():
        if len(lst) < k:
            continue
        top = sorted(lst, key=lambda x: -x[0])[:k]
        vals.append(sum(yy for _, yy in top) / k)
    return (sum(vals) / len(vals)) if vals else None, len(vals)


def falsos_alertas_por_100(sinal, y):
    n = len(sinal)
    if not n:
        return None
    fa = sum(1 for s, yy in zip(sinal, y) if s == 1 and yy == 0)
    return 100.0 * fa / n


def antecedencia(eventos, ativacoes):
    """eventos: lista de (cnpj, data_evento). ativacoes: {cnpj: lista ordenada de datas em que o sinal ficou ativo}.
    Antecedencia = data do evento menos a PRIMEIRA ativacao nos 365 dias anteriores. Mediana e IQR em dias."""
    from datetime import timedelta
    vals = []
    for c, d in eventos:
        prev = [a for a in ativacoes.get(c, []) if d - timedelta(days=365) <= a < d]
        if prev:
            vals.append((d - prev[0]).days)
    if not vals:
        return {"n": 0, "mediana": None, "q1": None, "q3": None}
    vals.sort()
    return {"n": len(vals), "mediana": _pct(vals, 0.5), "q1": _pct(vals, 0.25), "q3": _pct(vals, 0.75)}


def _pct(v, q):
    k = (len(v) - 1) * q
    lo, hi = int(math.floor(k)), int(math.ceil(k))
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def brier(p, y):
    return sum((pi - yi) ** 2 for pi, yi in zip(p, y)) / len(y) if y else None


def brier_skill(p, y, p_ref):
    b, br = brier(p, y), brier(p_ref, y)
    return None if (b is None or not br) else 1 - b / br


def bootstrap_cluster(clusters, estat, n_boot=N_BOOT, semente=SEMENTE):
    """clusters: {id: lista de indices}. estat(indices) -> numero ou None. IC95 percentil, ignorando reamostras None."""
    rng = random.Random(semente)
    ids = sorted(clusters)
    vals = []
    for _ in range(n_boot):
        idx = []
        for _ in ids:
            idx.extend(clusters[rng.choice(ids)])
        v = estat(idx)
        if v is not None and not (isinstance(v, float) and math.isnan(v)):
            vals.append(v)
    if not vals:
        return None, None, 0
    vals.sort()
    return _pct(vals, 0.025), _pct(vals, 0.975), len(vals)


def p_unilateral_rr(clusters, sinal, y, n_boot=N_BOOT, semente=SEMENTE):
    """p-valor unilateral (H1: RR > 1) pela fracao de reamostras bootstrap com RR <= 1."""
    rng = random.Random(semente)
    ids = sorted(clusters)
    tot, le1 = 0, 0
    for _ in range(n_boot):
        idx = []
        for _ in ids:
            idx.extend(clusters[rng.choice(ids)])
        rr = razao_de_risco([sinal[i] for i in idx], [y[i] for i in idx])
        if rr is None:
            continue
        tot += 1
        if rr <= 1:
            le1 += 1
    return ((le1 + 1) / (tot + 1)) if tot else None


def holm(pvals):
    """{nome: p} -> {nome: p_ajustado} (Holm step-down, monotono)."""
    itens = sorted((p, n) for n, p in pvals.items() if p is not None)
    m = len(itens)
    out, acum = {}, 0.0
    for i, (p, n) in enumerate(itens):
        adj = min(1.0, (m - i) * p)
        acum = max(acum, adj)
        out[n] = acum
    for n, p in pvals.items():
        if p is None:
            out[n] = None
    return out


def g2(rr_li, antecedencia_mediana, prauc_sinal, prauc_b2, p_holm):
    """Gate G2 puro. Passa so com as quatro condicoes. Devolve (passa, motivos)."""
    motivos = []
    if rr_li is None or rr_li <= RR_LI_MIN:
        motivos.append("limite inferior do IC95 da razao de risco nao supera %.1f" % RR_LI_MIN)
    if antecedencia_mediana is None or antecedencia_mediana < ANTECEDENCIA_MIN:
        motivos.append("antecedencia mediana abaixo de %d dias" % ANTECEDENCIA_MIN)
    if prauc_sinal is None or prauc_b2 is None or prauc_sinal <= prauc_b2:
        motivos.append("PR-AUC nao supera a de B2")
    if p_holm is None or p_holm >= ALFA:
        motivos.append("p ajustado por Holm nao fica abaixo de %.2f" % ALFA)
    return (not motivos), motivos


def largura_ic(ic):
    return None if (not ic or ic[0] is None or ic[1] is None) else ic[1] - ic[0]


def ic_mais_conservador(*ics):
    """Entre ICs da mesma estatistica, o mais largo (o que menos afirma). IC incompleto vence, porque nada se mediu."""
    validos = [ic for ic in ics if ic is not None]
    if not validos:
        return (None, None)
    for ic in validos:
        if largura_ic(ic) is None:
            return (None, None)
    return max(validos, key=largura_ic)


def g3(bs_b0, bs_b2, incl_ic, largura_max=IC_INCLINACAO_LARGURA_MAX):
    """Gate G3 puro. incl_ic deve ser o IC mais conservador entre cluster de CNPJ e blocos de meses.
    Devolve (passa, motivos). IC largo demais reprova como nao informativo, mesmo contendo 1."""
    motivos = []
    if bs_b0 is None or bs_b0 <= 0:
        motivos.append("Brier skill contra B0 nao e positivo")
    if bs_b2 is None or bs_b2 <= 0:
        motivos.append("Brier skill contra B2 nao e positivo")
    if not incl_ic or incl_ic[0] is None or not (incl_ic[0] <= 1 <= incl_ic[1]):
        motivos.append("IC95 da inclinacao de calibracao nao contem 1")
    w = largura_ic(incl_ic)
    if w is None or w > largura_max + 1e-9:  # tolerancia de ponto flutuante (1.1 - 0.9 = 0.20000000000000007)
        motivos.append("nao informativo: IC95 da inclinacao com largura %s acima do maximo congelado %.2f"
                       % ("indefinida" if w is None else "%.3f" % w, largura_max))
    return (not motivos), motivos


def regime_selic(taxa):
    return "acima_12" if taxa is not None and taxa > 0.12 else "ate_12"
