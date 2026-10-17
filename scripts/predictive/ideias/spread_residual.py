"""PoC 2 (Dia 2): spread residual idiossincratico contra o z_spread do Worker.

Criterios congelados em data/validacao/poc-ideias/dia1/criterios_poc.json.
Variavel: variacao diaria da taxa indicativa do emissor (taxa_indicativa_pct, fonte anbima_publico).
Variacao com troca de composicao de papeis (n_papeis diferente do dia anterior) fica de fora do ajuste e dos alertas.
Fatores do emissor i: mediana das variacoes dos demais (mercado) e dos demais do mesmo setor, nunca o proprio i.
Betas estimados so com datas anteriores a T. Alerta quando |residuo padronizado| >= LIMIAR.
"""
import gzip
import json
import math
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import HISTORICO, REPO, SAIDA, gravar_json, pdata  # noqa: E402

JANELA = 60
N_MIN = 40
LIMIAR = 2.0
MIN_PARES_MERCADO = 10
MIN_PARES_SETOR = 3
MIN_DIAS_Z = 10  # MIN_DIAS de calcularZScoresANBIMA
SETORES = os.path.join(REPO, "data", "cotacoes", "tickers_emissores.json")


def carregar_series(caminho):
    with gzip.open(caminho, "rt", encoding="utf-8") as fh:
        bruto = json.load(fh)
    out = {}
    for emp, regs in bruto.items():
        pts = {}
        for r in regs:
            d = pdata(r.get("data"))
            tx = r.get("taxa_indicativa_pct")
            if tx is None:
                tx = r.get("spread_bps")  # alias deprecado com o MESMO numero (0 divergencias em 8.794 pontos)
            if r.get("fonte") == "anbima_publico" and d and tx is not None:
                pts[d] = (float(tx), r.get("n_papeis"))
        if pts:
            out[emp] = pts
    return out


def carregar_setores():
    with open(SETORES, encoding="utf-8") as fh:
        d = json.load(fh)["emissores"]
    return {k: v.get("setor") for k, v in d.items()}


def mediana(v):
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])


def ols(X, y):
    k = len(X[0])
    A = [[sum(r[i] * r[j] for r in X) for j in range(k)] for i in range(k)]
    b = [sum(r[i] * yy for r, yy in zip(X, y)) for i in range(k)]
    for i in range(k):
        p = max(range(i, k), key=lambda r: abs(A[r][i]))
        if abs(A[p][i]) < 1e-12:
            return None
        A[i], A[p] = A[p], A[i]
        b[i], b[p] = b[p], b[i]
        for r in range(i + 1, k):
            f = A[r][i] / A[i][i]
            for c in range(i, k):
                A[r][c] -= f * A[i][c]
            b[r] -= f * b[i]
    beta = [0.0] * k
    for i in range(k - 1, -1, -1):
        beta[i] = (b[i] - sum(A[i][j] * beta[j] for j in range(i + 1, k))) / A[i][i]
    return beta


def inversa(A):
    k = len(A)
    M = [list(r) + [1.0 if i == j else 0.0 for j in range(k)] for i, r in enumerate(A)]
    for i in range(k):
        p = max(range(i, k), key=lambda r: abs(M[r][i]))
        if abs(M[p][i]) < 1e-12:
            return None
        M[i], M[p] = M[p], M[i]
        piv = M[i][i]
        M[i] = [x / piv for x in M[i]]
        for r in range(k):
            if r != i:
                f = M[r][i]
                M[r] = [x - f * y for x, y in zip(M[r], M[i])]
    return [r[k:] for r in M]


def alavancagem(X, x0):
    """h = x0' (X'X)^-1 x0, usado no intervalo de predicao: var = sd^2 (1 + h)."""
    k = len(X[0])
    A = [[sum(r[i] * r[j] for r in X) for j in range(k)] for i in range(k)]
    inv = inversa(A)
    if inv is None:
        return None
    return sum(x0[i] * inv[i][j] * x0[j] for i in range(k) for j in range(k))


def deltas(series, calendario):
    """{emp: {data: variacao}} so quando o dia anterior do calendario existe e a composicao nao mudou."""
    out = {}
    for emp, pts in series.items():
        dl = {}
        for k in range(1, len(calendario)):
            a, b = calendario[k - 1], calendario[k]
            if a in pts and b in pts and pts[a][1] == pts[b][1]:
                dl[b] = pts[b][0] - pts[a][0]
        out[emp] = dl
    return out


def fatores(dl, setores, calendario):
    """Para cada (emp, data): (mercado, setor) com o proprio emp excluido."""
    f = {}
    for d in calendario:
        vals = [(e, v[d]) for e, v in dl.items() if d in v]
        for e, _ in vals:
            peers = [x for ee, x in vals if ee != e]
            sp = [x for ee, x in vals if ee != e and setores.get(ee) and setores.get(ee) == setores.get(e)]
            m = mediana(peers) if len(peers) >= MIN_PARES_MERCADO else None
            s = mediana(sp) if len(sp) >= MIN_PARES_SETOR else None
            f[(e, d)] = (m, s)
    return f


def ajustar(emp, t, calendario, dl, fat, usar_setor):
    """Ajuste com datas < calendario[t]. Devolve (beta, sd_resid, estavel, n) ou None."""
    janela = calendario[max(0, t - JANELA):t]
    linhas = []
    for d in janela:
        if d not in dl[emp]:
            continue
        m, s = fat.get((emp, d), (None, None))
        if m is None or (usar_setor and s is None):
            continue
        linhas.append((d, dl[emp][d], m, s))
    if len(linhas) < N_MIN:
        return None

    def montar(ls):
        X = [[1.0, m] + ([s] if usar_setor else []) for _, _, m, s in ls]
        return X, [y for _, y, _, _ in ls]
    X, y = montar(linhas)
    beta = ols(X, y)
    if beta is None:
        return None
    res = [yy - sum(b * x for b, x in zip(beta, r)) for r, yy in zip(X, y)]
    gl = max(1, len(y) - len(beta))
    sd = math.sqrt(sum(e * e for e in res) / gl)
    if sd <= 0:
        return None
    meio = len(linhas) // 2
    b1 = ols(*montar(linhas[:meio]))
    b2 = ols(*montar(linhas[meio:]))
    estavel = False
    if b1 and b2 and b1[1] != 0 and b2[1] != 0 and b1[1] * b2[1] > 0:
        r = b1[1] / b2[1]
        estavel = (1 / 3) <= r <= 3
    return beta, sd, estavel, len(y), X


def z_spread(series, emp, d, calendario):
    """Replica calcularZScoresANBIMA no instante d: media e desvio populacional do historico ate d."""
    xs = [series[emp][x][0] for x in calendario if x <= d and x in series[emp]]
    if len(xs) < MIN_DIAS_Z or d not in series[emp]:
        return None
    mean = sum(xs) / len(xs)
    sd = math.sqrt(sum((x - mean) ** 2 for x in xs) / len(xs))
    return (series[emp][d][0] - mean) / sd if sd > 0 else 0.0


def avaliar(series, setores, usar_setor=True):
    calendario = sorted({d for p in series.values() for d in p})
    dl = deltas(series, calendario)
    fat = fatores(dl, setores, calendario)
    alertas, z_alertas = [], []
    possiveis = avaliaveis = nao_estavel = 0
    primeira = None
    chaves_avaliaveis = set()
    for t in range(1, len(calendario)):
        d = calendario[t]
        for emp in series:
            if d not in series[emp]:
                continue
            possiveis += 1
            zs = z_spread(series, emp, d, calendario)
            if zs is not None and abs(zs) >= LIMIAR:
                z_alertas.append({"emp": emp, "data": d, "z": round(zs, 2)})
            if d not in dl[emp]:
                continue
            m, s = fat.get((emp, d), (None, None))
            if m is None or (usar_setor and s is None):
                continue
            aj = ajustar(emp, t, calendario, dl, fat, usar_setor)
            if aj is None:
                continue
            beta, sd, estavel, n, X = aj
            if not estavel:
                nao_estavel += 1
                continue
            x0 = [1.0, m] + ([s] if usar_setor else [])
            h = alavancagem(X, x0)
            if h is None:
                continue
            avaliaveis += 1
            chaves_avaliaveis.add((emp, d))
            primeira = primeira or d
            prev = beta[0] + beta[1] * m + (beta[2] * s if usar_setor else 0.0)
            z = (dl[emp][d] - prev) / (sd * math.sqrt(1.0 + h))
            if abs(z) >= LIMIAR:
                alertas.append({"emp": emp, "data": d, "z_res": round(z, 2), "delta": round(dl[emp][d], 4)})
    return {"calendario": calendario, "alertas": alertas, "z_alertas": z_alertas, "emissor_dias_possiveis": possiveis,
            "emissor_dias_avaliaveis": avaliaveis, "emissor_dias_instaveis": nao_estavel, "primeira_data_avaliavel": primeira,
            "chaves_avaliaveis": chaves_avaliaveis}


def main():
    pastas = sorted(p for p in os.listdir(HISTORICO) if os.path.exists(os.path.join(HISTORICO, p, "series_full.json.gz")))
    arq = os.path.join(HISTORICO, pastas[-1], "series_full.json.gz")
    series = carregar_series(arq)
    setores = carregar_setores()
    sem_setor = sorted(e for e in series if not setores.get(e))
    r = avaliar(series, setores)
    ini = r["primeira_data_avaliavel"]
    z_na_janela = [a for a in r["z_alertas"] if ini and a["data"] >= ini]
    ra = {(a["emp"], a["data"]) for a in r["alertas"]}
    za = {(a["emp"], a["data"]) for a in z_na_janela}
    mes = lambda lst: sorted({k: sum(1 for a in lst if str(a["data"])[:7] == k) for k in {str(a["data"])[:7] for a in lst}}.items())
    saida = {"versao": "spread_residual v1", "arquivo": arq, "emissores": len(series), "emissores_sem_setor": sem_setor,
             "dias": len(r["calendario"]), "primeira_data_avaliavel": str(ini), "ultima": str(r["calendario"][-1]),
             "emissor_dias_possiveis": r["emissor_dias_possiveis"], "emissor_dias_avaliaveis": r["emissor_dias_avaliaveis"],
             "emissor_dias_instaveis": r["emissor_dias_instaveis"],
             "cobertura": round(r["emissor_dias_avaliaveis"] / r["emissor_dias_possiveis"], 3) if r["emissor_dias_possiveis"] else 0,
             "alertas_residual": len(r["alertas"]), "alertas_residual_alta": sum(1 for a in r["alertas"] if a["z_res"] > 0),
             "alertas_z_spread_todos_os_dias": len(r["z_alertas"]), "alertas_z_spread_na_janela_residual": len(z_na_janela),
             "sobreposicao_mesmo_emissor_dia": len(ra & za),
             "alertas_z_spread_nos_mesmos_emissor_dias_avaliaveis": len(za & r["chaves_avaliaveis"]),
             "taxa_alerta_residual": round(len(r["alertas"]) / max(1, r["emissor_dias_avaliaveis"]), 4),
             "taxa_alerta_z_nos_mesmos_emissor_dias": round(len(za & r["chaves_avaliaveis"]) / max(1, r["emissor_dias_avaliaveis"]), 4),
             "residual_por_mes": mes(r["alertas"]), "z_por_mes": mes(z_na_janela)}
    gravar_json(os.path.join(SAIDA, "dia2", "spread_residual_resultado.json"), saida)
    os.makedirs(os.path.join(SAIDA, "dia2"), exist_ok=True)
    with open(os.path.join(SAIDA, "dia2", "alertas_spread_residual.jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        for a in r["alertas"]:
            fh.write(json.dumps({"poc": "spread_residual", "emp": a["emp"], "data": str(a["data"]), "z_res": a["z_res"], "delta": a["delta"]}, ensure_ascii=False, sort_keys=True) + "\n")
    print(json.dumps(saida, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    main()
