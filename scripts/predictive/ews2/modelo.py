"""Modelo exibivel (G0-v1 item 10, G3): logit com no maximo 3 sinais aprovados em G2, ajustado so em treino, com
recalibracao de Platt na validacao. Implementacao propria (Newton/IRLS com ridge minimo), sem dependencia externa,
determinista. Nada aqui escolhe sinal nem olha o teste: quem decide quais colunas entram e o backtest, pelas regras.
"""
import math

RIDGE = 1e-6
MAX_SINAIS_G3 = 3


def _sigmoid(z):
    if z >= 0:
        e = math.exp(-z)
        return 1.0 / (1.0 + e)
    e = math.exp(z)
    return e / (1.0 + e)


def _solve(A, b):
    """Gauss com pivo parcial. A: lista de listas n x n, b: lista n."""
    n = len(b)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(M[r][c]))
        if abs(M[p][c]) < 1e-14:
            raise ValueError("matriz singular")
        M[c], M[p] = M[p], M[c]
        for r in range(n):
            if r != c:
                f = M[r][c] / M[c][c]
                if f:
                    M[r] = [x - f * y for x, y in zip(M[r], M[c])]
    return [M[i][n] / M[i][i] for i in range(n)]


def ajustar_logit(X, y, max_iter=50, tol=1e-9, ridge=RIDGE):
    """X: lista de linhas (sem intercepto), y: 0/1. Devolve {"beta": [b0, b1..], "iter", "convergiu", "loglik"}."""
    n, p = len(X), (len(X[0]) if X else 0)
    beta = [0.0] * (p + 1)
    Xa = [[1.0] + list(map(float, row)) for row in X]
    convergiu = False
    ll_ant = None
    for it in range(1, max_iter + 1):
        z = [sum(b * x for b, x in zip(beta, row)) for row in Xa]
        pr = [_sigmoid(v) for v in z]
        grad = [0.0] * (p + 1)
        H = [[0.0] * (p + 1) for _ in range(p + 1)]
        for row, pi, yi in zip(Xa, pr, y):
            w = pi * (1 - pi)
            for i in range(p + 1):
                grad[i] += (yi - pi) * row[i]
                for j in range(p + 1):
                    H[i][j] += w * row[i] * row[j]
        for i in range(1, p + 1):
            grad[i] -= ridge * beta[i]
            H[i][i] += ridge
        try:
            passo = _solve(H, grad)
        except ValueError:
            break
        beta = [b + s for b, s in zip(beta, passo)]
        ll = sum(math.log(max(pi, 1e-12)) if yi else math.log(max(1 - pi, 1e-12)) for pi, yi in zip(pr, y))
        if ll_ant is not None and abs(ll - ll_ant) < tol:
            convergiu = True
            break
        ll_ant = ll
    return {"beta": beta, "iter": it, "convergiu": convergiu, "loglik": ll_ant}


def prever_logit(modelo, X):
    return [_sigmoid(modelo["beta"][0] + sum(b * x for b, x in zip(modelo["beta"][1:], row))) for row in X]


def platt(p_valid, y_valid):
    """Recalibracao de Platt: logit(y) = a + b * logit(p), ajustado na validacao. Devolve (a, b)."""
    Z = [[_logit(p)] for p in p_valid]
    m = ajustar_logit(Z, y_valid)
    return m["beta"][0], m["beta"][1]


def aplicar_platt(ab, p):
    a, b = ab
    return [_sigmoid(a + b * _logit(x)) for x in p]


def _logit(p):
    p = min(max(p, 1e-9), 1 - 1e-9)
    return math.log(p / (1 - p))


def inclinacao_calibracao(p, y):
    """Inclinacao da regressao logit(y) ~ a + b logit(p): b = 1 e calibracao perfeita."""
    if len(set(y)) < 2:
        return None
    m = ajustar_logit([[_logit(x)] for x in p], y)
    return m["beta"][1]
