import os
import sys
import unittest
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_at_risk as FR  # noqa: E402


def uteis(n, ini=date(2026, 1, 5)):
    out, d = [], ini
    while len(out) < n:
        if d.weekday() < 5:
            out.append(d)
        d += timedelta(days=1)
    return out


class TesteDisponibilidade(unittest.TestCase):
    def setUp(self):
        self.pos = {("F1", date(2026, 1, 31), "X", None): 100.0,
                    ("F1", date(2026, 1, 31), "Y", date(2026, 4, 30)): 50.0,
                    ("F1", date(2025, 12, 31), "X", None): 80.0}

    def test_competencia_so_entra_depois_da_defasagem(self):
        antes = FR.posicoes_em(self.pos, date(2026, 3, 31), 60)  # 31/01 + 60 = 01/04 > 30/03
        self.assertEqual(dict(antes), {("F1", "X"): 80.0})
        depois = FR.posicoes_em(self.pos, date(2026, 4, 2), 60)
        self.assertEqual(depois[("F1", "X")], 100.0)

    def test_linha_confidencial_so_entra_depois_do_prazo(self):
        antes = FR.posicoes_em(self.pos, date(2026, 4, 30), 60)
        self.assertNotIn(("F1", "Y"), antes)
        depois = FR.posicoes_em(self.pos, date(2026, 5, 1), 60)
        self.assertEqual(depois[("F1", "Y")], 50.0)


class TestePressao(unittest.TestCase):
    def serie(self, cal, pico=None, futuro=None):
        s = {}
        for i, d in enumerate(cal):
            resg = 1.0 + (i % 3) * 0.1
            if pico is not None and i == pico:
                resg = 60.0
            if futuro is not None and i > futuro:
                resg = 500.0
            s[d] = [0.0, resg, 1000.0]
        return s

    def test_pico_de_resgate_vira_pressao_so_no_dia_seguinte(self):
        cal = uteis(90)
        p = FR.pressao_por_fundo({"F": self.serie(cal, pico=70)}, cal)["F"]
        self.assertNotIn(cal[70], p)
        self.assertIn(cal[71], p)

    def test_dado_futuro_nao_muda_pressao_passada(self):
        cal = uteis(100)
        a = FR.pressao_por_fundo({"F": self.serie(cal, pico=70)}, cal)["F"]
        b = FR.pressao_por_fundo({"F": self.serie(cal, pico=70, futuro=85)}, cal)["F"]
        corte = cal[85]
        self.assertEqual({d for d in a if d <= corte}, {d for d in b if d <= corte})

    def test_historico_curto_nao_gera_pressao(self):
        cal = uteis(40)
        self.assertEqual(FR.pressao_por_fundo({"F": self.serie(cal, pico=35)}, cal)["F"], set())


if __name__ == "__main__":
    unittest.main()
