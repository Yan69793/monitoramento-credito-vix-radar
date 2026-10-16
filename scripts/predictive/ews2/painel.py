"""Painel empresa-mes (G0-v1 item 1): uma linha por (CNPJ, T) com a empresa em risco em T, alvo y180 e y365, particao
e flags de uso. Toda regra de "quem esta em risco em T" e de "o que e alvo" vive aqui, separada das features.

Em risco em T: registro vigente em T (periodo do cadastro), nao securitizadora, ja com 1 DFP recebida ate T-1
(item 4), fora de episodio em curso (depois de um incidente a empresa sai do risco ate o fim do episodio), e sem
censura anterior a T no mesmo periodo de registro.
Alvo y_h: existe evento INCIDENTE do CNPJ em (T, T+h]. Linha usavel para metrica so com horizonte fechado dentro
da propria particao e antes do fim da observacao (calendario.horizonte_fechado); as demais ficam marcadas e contadas.
"""
from datetime import timedelta

import calendario as C
import eventos as EV


def linhas_painel(cnpjs, datas_T, eps_por_cnpj, cad, primeira_dfp, securitizadoras, formulacao):
    """Gera dicts {cnpj, T, y180, y365, particao, usavel_180, usavel_365, formulacao, em_risco}."""
    out = []
    for c in cnpjs:
        if c in securitizadoras:
            continue
        periodos = cad.get(c, [])
        eps = eps_por_cnpj.get(c, [])
        incid = [ep for ep in eps if not ep.get("prevalente")]
        cens = EV.censuras(periodos, eps)
        for t in datas_T:
            per = _periodo(periodos, t)
            if per is None:
                continue
            if primeira_dfp.get(c) is None or primeira_dfp[c] > t - timedelta(days=1):
                continue
            if any(per["dt_reg"] <= dc < t for dc, _ in cens if per["dt_reg"]):
                continue
            if any(ep["inicio"] <= t < ep["fim"] for ep in eps):
                continue  # dentro de episodio (prevalente ou incidente): fora do risco
            y180 = any(t < ep["inicio"] <= t + timedelta(days=C.HORIZONTE_1) for ep in incid)
            y365 = any(t < ep["inicio"] <= t + timedelta(days=C.HORIZONTE_2) for ep in incid)
            out.append({"cnpj": c, "T": t, "y180": int(y180), "y365": int(y365), "particao": C.particao(t),
                        "usavel_180": C.horizonte_fechado(t, C.HORIZONTE_1), "usavel_365": C.horizonte_fechado(t, C.HORIZONTE_2),
                        "formulacao": c in formulacao})
    return out


def _periodo(periodos, d):
    for p in periodos:
        if p.get("dt_reg") and p["dt_reg"] <= d and (p.get("dt_cancel") is None or d <= p["dt_cancel"]):
            return p
    return None


def resumo(linhas):
    from collections import Counter
    c = Counter((l["particao"], l["y180"]) for l in linhas if l["usavel_180"] and not l["formulacao"])
    return {"linhas": len(linhas), "usaveis_180_sem_formulacao": sum(c.values()),
            "por_particao": {p: {"n": c[(p, 0)] + c[(p, 1)], "eventos": c[(p, 1)]} for p in ("treino", "validacao", "embargo", "teste")},
            "embargo_usado": 0}
