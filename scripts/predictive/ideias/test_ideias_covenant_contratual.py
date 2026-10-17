import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant_contratual as K  # noqa: E402


def reg(bp=None, dre=None, dfc=None, receb="2025-05-10"):
    return {"dt_receb": receb, "linhas": {"BPA": bp or [], "BPP": [], "DRE": dre or [], "DFC": dfc or []}}


class TesteTermo(unittest.TestCase):
    def test_so_a_folha_mais_profunda_conta(self):
        r = reg(bp=[("1.01.02", "aplicacoes", 100.0), ("1.01.02.01", "aplicacoes vj", 100.0), ("1.01.02.01.04", "derivativos", 20.0)])
        v, contas = K.termo(r["linhas"], {"s": 1, "dem": "BPA", "cd": "^1\\.01\\.02", "ds": None})
        self.assertEqual((v, contas), (20.0, ["1.01.02.01.04"]))

    def test_codigo_exato_nao_desce(self):
        r = reg(bp=[("1.01.02", "aplicacoes", 100.0), ("1.01.02.01.04", "derivativos", 20.0)])
        self.assertEqual(K.termo(r["linhas"], {"s": 1, "dem": "BPA", "cd": "^1\\.01\\.02$"})[0], 100.0)

    def test_filtro_de_descricao_e_exclusao(self):
        r = reg(dfc=[("6.01.01.02", "depreciacao e amortizacao", 50.0), ("6.01.01.09", "amortizacao de custo de emprestimos", 7.0)])
        t = {"s": 1, "dem": "DFC", "cd": "^6\\.01\\.01\\.", "ds": "deprecia|amortiza", "nao": "emprest"}
        self.assertEqual(K.termo(r["linhas"], t)[0], 50.0)

    def test_sinal_negativo(self):
        r = reg(bp=[("1.01.08.03", "derivativos", 30.0)])
        self.assertEqual(K.termo(r["linhas"], {"s": -1, "dem": "BPA", "cd": "^1\\.0[12]", "ds": "derivativ"})[0], -30.0)


class TesteLTM(unittest.TestCase):
    def test_ltm_de_fluxo_e_saldo_sem_ltm(self):
        base = {("X", "2025-06-30"): reg(dre=[("3.05", "ebit", 60.0)], bp=[("1.01.01", "caixa", 9.0)]),
                ("X", "2024-12-31"): reg(dre=[("3.05", "ebit", 100.0)], bp=[("1.01.01", "caixa", 1.0)]),
                ("X", "2024-06-30"): reg(dre=[("3.05", "ebit", 40.0)], bp=[("1.01.01", "caixa", 2.0)])}
        ebit = [{"s": 1, "dem": "DRE", "cd": "^3\\.05$"}]
        caixa = [{"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$"}]
        self.assertEqual(K.valor_ltm(base, "X", "2025-06-30", ebit, True), 120.0)
        self.assertEqual(K.valor_ltm(base, "X", "2025-06-30", caixa, False), 9.0)

    def test_componente_misto_e_recusado(self):
        regra = {"componentes": {"ruim": [{"s": 1, "dem": "DRE", "cd": "^3\\.05$"}, {"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$"}]}}
        with self.assertRaises(ValueError):
            K.calcular({("X", "2025-12-31"): reg()}, "X", "2025-12-31", regra)

    def test_indices(self):
        base = {("X", "2025-12-31"): reg(bp=[("1.01.01", "caixa", 20.0)], dre=[("3.05", "ebit", 50.0), ("3.06.01", "receitas", 5.0)],
                                          dfc=[("6.01.01.11", "juros e variacoes sobre emprestimos", 30.0)])}
        base[("X", "2025-12-31")]["linhas"]["BPP"] = [("2.02.01", "emprestimos", 120.0)]
        regra = {"componentes": {"divida": [{"s": 1, "dem": "BPP", "cd": "^2\\.02\\.01$"}], "caixa": [{"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$"}],
                                 "ebitda": [{"s": 1, "dem": "DRE", "cd": "^3\\.05$"}],
                                 "despesa_financeira": [{"s": 1, "dem": "DFC", "cd": "^6\\.01\\.01\\.", "ds": "juros"}],
                                 "receita_financeira": [{"s": 1, "dem": "DRE", "cd": "^3\\.06\\.01$"}]}}
        out, _ = K.calcular(base, "X", "2025-12-31", regra)
        self.assertEqual(out, {"divida_liquida/ebitda": 2.0, "ebitda/resultado_financeiro": 2.0})


if __name__ == "__main__":
    unittest.main()
