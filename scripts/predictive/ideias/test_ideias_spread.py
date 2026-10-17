import os
import random
import sys
import unittest
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spread_residual as S  # noqa: E402


def dias_uteis(n, ini=date(2026, 1, 5)):
    out, d = [], ini
    while len(out) < n:
        if d.weekday() < 5:
            out.append(d)
        d += timedelta(days=1)
    return out


def sintetico(n=110, emissores=14, semente=7, choque=None, choque_mercado=None, futuro=None):
    """Spread = passeio aleatorio de mercado (beta 1) + ruido proprio pequeno. choque={emp, indice, valor} soma salto so naquele emissor."""
    rnd = random.Random(semente)
    cal = dias_uteis(n)
    mercado = [0.0]
    for _ in range(n - 1):
        mercado.append(mercado[-1] + rnd.gauss(0, 0.05))
    series, setores = {}, {}
    for i in range(emissores):
        emp = "E%02d" % i
        setores[emp] = "S%d" % (i % 2)
        nivel, pts = 10.0 + i * 0.1, {}
        for k, d in enumerate(cal):
            ruido = rnd.gauss(0, 0.01)
            nivel_k = 10.0 + i * 0.1 + mercado[k] + ruido
            if choque and emp == choque["emp"] and k >= choque["indice"]:
                nivel_k += choque["valor"]
            if choque_mercado and k >= choque_mercado["indice"]:
                nivel_k += choque_mercado["valor"]
            if futuro and emp == futuro["emp"] and k > futuro["depois_de"]:
                nivel_k += futuro["valor"]
            pts[d] = (nivel_k, 3)
        series[emp] = pts
    return series, setores, cal


class TesteSpreadResidual(unittest.TestCase):
    def test_choque_idiossincratico_gera_alerta_so_no_emissor(self):
        series, setores, cal = sintetico(choque={"emp": "E03", "indice": 80, "valor": 0.5})
        r = S.avaliar(series, setores)
        a = [x for x in r["alertas"] if x["data"] == cal[80] and x["emp"] == "E03"]
        self.assertEqual(len(a), 1)
        self.assertGreater(a[0]["z_res"], 2)
        # falso positivo por acaso dos demais fica perto do nominal (2 sigma bicaudal ~5%)
        outros = [x for x in r["alertas"] if x["emp"] != "E03"]
        avaliados = r["emissor_dias_avaliaveis"]
        self.assertLess(len(outros) / max(1, avaliados), 0.08)

    def test_choque_de_mercado_nao_gera_alerta_residual_mas_gera_z_spread(self):
        series, setores, cal = sintetico(choque_mercado={"indice": 80, "valor": 0.6})
        r = S.avaliar(series, setores)
        self.assertLessEqual(len([x for x in r["alertas"] if x["data"] == cal[80]]), 2)
        self.assertGreaterEqual(len([x for x in r["z_alertas"] if x["data"] >= cal[80]]), 10)

    def test_sem_vazamento_dado_futuro_nao_muda_alertas_ate_T(self):
        base, setores, cal = sintetico()
        com_futuro, _, _ = sintetico(futuro={"emp": "E05", "depois_de": 90, "valor": 3.0})
        a = S.avaliar(base, setores)
        b = S.avaliar(com_futuro, setores)
        corte = cal[90]
        fa = [(x["emp"], x["data"], x["z_res"]) for x in a["alertas"] if x["data"] <= corte]
        fb = [(x["emp"], x["data"], x["z_res"]) for x in b["alertas"] if x["data"] <= corte]
        self.assertEqual(fa, fb)
        za = [(x["emp"], x["data"], x["z"]) for x in a["z_alertas"] if x["data"] <= corte]
        zb = [(x["emp"], x["data"], x["z"]) for x in b["z_alertas"] if x["data"] <= corte]
        self.assertEqual(za, zb)

    def test_fator_exclui_o_proprio_emissor(self):
        series, setores, cal = sintetico()
        dl = S.deltas(series, cal)
        f1 = S.fatores(dl, setores, cal)
        alt = {e: dict(p) for e, p in series.items()}
        for d in cal:
            alt["E01"][d] = (alt["E01"][d][0] + 5.0 * (d.toordinal() % 3), 3)
        f2 = S.fatores(S.deltas(alt, cal), setores, cal)
        for d in cal[1:]:
            self.assertEqual(f1[("E01", d)], f2[("E01", d)])

    def test_troca_de_composicao_fica_fora(self):
        series, setores, cal = sintetico()
        series["E02"][cal[70]] = (series["E02"][cal[70]][0] + 4.0, 5)  # salto com n_papeis diferente
        dl = S.deltas(series, cal)
        self.assertNotIn(cal[70], dl["E02"])
        r = S.avaliar(series, setores)
        self.assertEqual([x for x in r["alertas"] if x["emp"] == "E02" and x["data"] == cal[70]], [])

    def test_amostra_curta_nao_avalia(self):
        series, setores, cal = sintetico(n=30)
        r = S.avaliar(series, setores)
        self.assertEqual(r["emissor_dias_avaliaveis"], 0)


if __name__ == "__main__":
    unittest.main()
