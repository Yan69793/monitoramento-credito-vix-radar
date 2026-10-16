"""Datas de observacao (G0-v1 item 1: ultimo dia util de cada mes T) e janelas de horizonte e particao (item 6).
Dia util = segunda a sexta fora dos feriados nacionais fixos e moveis listados abaixo. A lista e declarada e
determinista; feriado municipal nao entra (a observacao e nacional, e um dia de desvio nao muda o que esta
disponivel ate T menos 1 porque a regra de disponibilidade usa a data de entrega, nao a de pregao).
"""
from datetime import date, timedelta

JANELA_INI = date(2011, 1, 1)
JANELA_FIM = date(2026, 9, 30)
TREINO_FIM = date(2020, 1, 1)       # treino: < 2020-01-01
VALID_FIM = date(2022, 1, 1)        # validacao: 2020-01-01 .. 2021-12-31
EMBARGO_FIM = date(2022, 4, 1)      # embargo: 2022-01-01 .. 2022-03-31; teste: 2022-04-01 .. 2026-09-30
HORIZONTE_1, HORIZONTE_2 = 180, 365

FERIADOS_FIXOS = ((1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2), (11, 15), (12, 25))


def pascoa(ano):
    a, b, c = ano % 19, ano // 100, ano % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7  # noqa: E741
    m = (a + 11 * h + 22 * l) // 451
    mes = (h + l - 7 * m + 114) // 31
    dia = ((h + l - 7 * m + 114) % 31) + 1
    return date(ano, mes, dia)


def feriados(ano):
    p = pascoa(ano)
    f = {date(ano, m, d) for m, d in FERIADOS_FIXOS}
    f |= {p - timedelta(days=48), p - timedelta(days=47), p - timedelta(days=2), p + timedelta(days=60)}
    if ano >= 2024:
        f.add(date(ano, 11, 20))
    return f


def dia_util(d):
    return d.weekday() < 5 and d not in feriados(d.year)


def ultimo_dia_util_do_mes(ano, mes):
    d = (date(ano + 1, 1, 1) if mes == 12 else date(ano, mes + 1, 1)) - timedelta(days=1)
    while not dia_util(d):
        d -= timedelta(days=1)
    return d


def datas_observacao(ini=JANELA_INI, fim=JANELA_FIM):
    out = []
    a, m = ini.year, ini.month
    while True:
        t = ultimo_dia_util_do_mes(a, m)
        if t > fim:
            break
        if t >= ini:
            out.append(t)
        a, m = (a + 1, 1) if m == 12 else (a, m + 1)
    return out


def particao(d):
    if d < TREINO_FIM:
        return "treino"
    if d < VALID_FIM:
        return "validacao"
    if d < EMBARGO_FIM:
        return "embargo"
    return "teste"


def fim_particao(nome):
    return {"treino": TREINO_FIM, "validacao": VALID_FIM, "embargo": EMBARGO_FIM, "teste": JANELA_FIM + timedelta(days=1)}[nome]


def horizonte_fechado(t, horizonte=HORIZONTE_1, fim_obs=JANELA_FIM):
    """O horizonte (T, T+h] esta inteiramente observado e nao cruza para a particao seguinte."""
    fim = t + timedelta(days=horizonte)
    return fim <= fim_obs and fim < fim_particao(particao(t))
