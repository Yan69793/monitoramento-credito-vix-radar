import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant as C  # noqa: E402

DASA = ("relativas a 30 de setembro de 2020: (a) indice financeiro decorrente do quociente da divisao da Divida Liquida pelo "
        "EBITDA, que devera ser inferior a 4 (quatro) vezes; e (b) indice financeiro decorrente do quociente da divisao do "
        "EBITDA pelo Resultado Financeiro, que devera ser superior a 1,5 (um inteiro e cinquenta centesimos) vez.")
MOVIDA = ("apurados trimestralmente com base na Demonstracao Financeira Consolidada: Divida Financeira Liquida/EBITDA menor ou "
          "igual a: (a) 3,50 (tres inteiros e cinquenta centesimos), entre o periodo X; (b) 3,75 (tres inteiros), entre Y; "
          "(c) 4,00 (quatro inteiros), a partir de Z.")
SEM_INDICE = "a taxa de juros remuneratorios nao podera ser superior a 2,5 (dois inteiros) ao ano sobre o valor nominal."

AF = """RELATORIO ANUAL DO AGENTE FIDUCIARIO
EXERCICIO DE 2025
INDICE              MARCO             JUNHO                   SETEMBRO          DEZEMBRO*

Divida Liquida/ N/A                   N/A                     N/A               Limite<=3,5
EBITDA Ajustado                                                                 Apurado=4,27
"""
AF_CHEIA = """EXERCICIO DE 2025
INDICE           MARCO                JUNHO         SETEMBRO      DEZEMBRO*
Divida Liquida/  Limite<4,0           Limite<4,0    Limite<4,0    Limite<4,0
EBITDA           Apurado=3,65         Apurado=2,57  Apurado=2,38  Apurado=2,5
"""


class TesteEscritura(unittest.TestCase):
    def test_extrai_os_dois_covenants_da_dasa(self):
        r = {(c["indicador"], c["operador"], c["limite"]) for c in C.extrair_escritura(DASA)}
        self.assertEqual(r, {("divida_liquida/ebitda", "<", 4.0), ("ebitda/resultado_financeiro", ">", 1.5)})

    def test_step_down_e_periodicidade(self):
        c = C.extrair_escritura(MOVIDA)
        self.assertEqual(len(c), 1)
        self.assertEqual((c[0]["operador"], c[0]["limite"]), ("<=", 3.5))
        self.assertEqual(c[0]["step_down"], [("b", 3.75), ("c", 4.0)])
        self.assertEqual(c[0]["periodicidade"], "trimestral")
        self.assertTrue(c[0]["base_consolidada"])

    def test_limite_sem_indicador_financeiro_nao_vira_covenant(self):
        self.assertEqual(C.extrair_escritura(SEM_INDICE), [])


ENEVA = ("(xii) nao observancia do quociente da divisao da Divida Liquida pelo EBITDA, que devera ser igual ou inferior a "
         "4,5 (quatro inteiros e cinco decimos) durante toda a vigencia")
AF_SIMPAR = """EXERCICIO DE 2025
INDICE              MARCO             JUNHO                   SETEMBRO           DEZEMBRO*

Divida Financeira Limite<=3,5         Limite<=3,5             Limite<=3,5        Limite<=3,5

Liquida/ EBITDA     Apurado=2,3 Apurado=2,3                   Apurado=2,2        Apurado=2,0
"""


class TesteRegressaoDia4(unittest.TestCase):
    def test_igual_ou_inferior_vira_menor_ou_igual(self):
        c = C.extrair_escritura(ENEVA)
        self.assertEqual([(x["operador"], x["limite"]) for x in c], [("<=", 4.5)])

    def test_apurado_com_tres_digitos(self):
        txt = ("EXERCICIO DE 2025\nINDICE              MARCO             JUNHO                   SETEMBRO      DEZEMBRO**\n"
               "EBITDA/ Despesa     Limite>=1,5       Limite>=1,5             Limite>=1,5   Limite>=1,5\n"
               "Financeira Liquida  Apurado=122,4     Apurado=27,2            Apurado=69,4  Apurado=128,7\n")
        self.assertEqual([x["apurado"] for x in C.extrair_af(txt)], [122.4, 27.2, 69.4, 128.7])

    def test_apurado_depois_de_linha_em_branco(self):
        r = C.extrair_af(AF_SIMPAR)
        self.assertEqual([x["apurado"] for x in r], [2.3, 2.3, 2.2, 2.0])


ENGIE = ('(a) na data de cada balanco consolidado trimestral da Emissora, a relacao entre o somatorio do EBITDA Consolidado dos ultimos 4 '
         '(quatro) trimestres e o somatorio das Despesas Financeiras Consolidadas no mesmo periodo nao podera ser inferior a 2,0; e (b) '
         'na data de cada balanco, a relacao entre a Divida Total Consolidada e o somatorio do EBITDA Consolidado dos ultimos 4 (quatro) '
         'trimestres da Emissora nao podera ser superior a 4,5.')
LOCALIZA = ('(i) indice obtido da divisao da Divida Liquida (conforme abaixo definida) pelo EBITDA (conforme abaixo definido) nao superior a 4,00, '
            'onde: (ii) indice obtido da divisao entre EBITDA pelas Despesas Financeiras Liquidas nao devera ser inferior a 1,50')
EQUATORIAL = ('Divida Liquida da Emissora pelo EBITDA Ajustado da Emissora, que nao devera ser maior do que 4,5x, em apuracoes trimestrais')
GATILHO = 'ocorrera o vencimento antecipado quando o quociente da divisao da Divida Liquida pelo EBITDA for superior a 3,5 (tres inteiros e cinco decimos).'


SIMBOLO_TXT = 'durante toda a vigencia ("Indice Financeiro"): Indice de Alavancagem: Divida Financeira Liquida / EBITDA ≤ 3,5x. Considera-se como: "Divida Financeira Liquida"'
SIMBOLO_MAIOR = 'Indice de Cobertura: EBITDA / Resultado Financeiro Liquido >= 2,0x durante a vigencia'


class TesteSimbolo(unittest.TestCase):
    def test_simbolo_menor_ou_igual(self):
        c = C.extrair_escritura(SIMBOLO_TXT)
        self.assertEqual([(x["indicador"], x["operador"], x["limite"]) for x in c], [("divida_liquida/ebitda", "<=", 3.5)])

    def test_simbolo_maior_ou_igual_com_ascii(self):
        c = C.extrair_escritura(SIMBOLO_MAIOR)
        self.assertEqual([(x["indicador"], x["operador"], x["limite"]) for x in c], [("ebitda/resultado_financeiro", ">=", 2.0)])


class TesteOperadorPeloContexto(unittest.TestCase):
    def ops(self, texto):
        return {(c["indicador"], c["operador"], c["limite"]) for c in C.extrair_escritura(texto)}

    def test_negacao_inverte_e_gera_limite_mantido(self):
        self.assertEqual(self.ops(ENGIE), {("ebitda/resultado_financeiro", ">=", 2.0), ("divida_liquida/ebitda", "<=", 4.5)})

    def test_nao_superior_e_nao_inferior(self):
        self.assertEqual(self.ops(LOCALIZA), {("divida_liquida/ebitda", "<=", 4.0), ("ebitda/resultado_financeiro", ">=", 1.5)})

    def test_nao_devera_ser_maior_do_que(self):
        self.assertEqual(self.ops(EQUATORIAL), {("divida_liquida/ebitda", "<=", 4.5)})

    def test_gatilho_de_vencimento_vira_limite_mantido(self):
        self.assertEqual(self.ops(GATILHO), {("divida_liquida/ebitda", "<=", 3.5)})

    def test_forma_literal_continua_literal(self):
        self.assertEqual(self.ops(DASA), {("divida_liquida/ebitda", "<", 4.0), ("ebitda/resultado_financeiro", ">", 1.5)})
        self.assertEqual(self.ops(ENEVA), {("divida_liquida/ebitda", "<=", 4.5)})


class TesteRelatorioAgente(unittest.TestCase):
    def test_coluna_na_alinha_dezembro(self):
        r = C.extrair_af(AF)
        self.assertEqual(len(r), 1)
        self.assertEqual((r[0]["mes"], r[0]["ano"], r[0]["operador"], r[0]["limite"], r[0]["apurado"]), (12, 2025, "<=", 3.5, 4.27))

    def test_quatro_trimestres(self):
        r = C.extrair_af(AF_CHEIA)
        self.assertEqual([(x["mes"], x["apurado"]) for x in r], [(3, 3.65), (6, 2.57), (9, 2.38), (12, 2.5)])


class TesteLTM(unittest.TestCase):
    def test_ltm_trimestre(self):
        cont = {("X", "2025-06-30"): {"ebit": 60.0}, ("X", "2024-12-31"): {"ebit": 100.0}, ("X", "2024-06-30"): {"ebit": 40.0}}
        self.assertEqual(C.ltm(cont, "X", "2025-06-30", "ebit"), 120.0)

    def test_ltm_sem_ano_anterior_e_none(self):
        self.assertIsNone(C.ltm({("X", "2025-06-30"): {"ebit": 60.0}}, "X", "2025-06-30", "ebit"))

    def test_margem(self):
        self.assertEqual(C.margem("<", 4.0, 3.0), 0.25)
        self.assertEqual(C.margem(">", 1.5, 1.2), -0.2)


if __name__ == "__main__":
    unittest.main()
