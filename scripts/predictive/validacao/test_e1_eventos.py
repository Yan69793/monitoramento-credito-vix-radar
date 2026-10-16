"""Testes do E1 (stdlib unittest). Rodar:
  python -I -m unittest discover -s scripts/predictive/validacao -p "test_*.py" -v

Cada teste de defeito tem as duas pontas: o caso que a v0 errava e o caso bom.
"""
import hashlib
import os
import re
import sys
import unittest
from datetime import date

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import e1_eventos as E  # noqa: E402

NOTA_111 = os.path.join(AQUI, "..", "..", "..", "Obsidian VIX Radar",
                        "111 - EWS 2.0 Protocolo de Validacao G0 2026-10-15.md")


def doc(d, cat, assunto="", nome="EMPRESA TESTE SA"):
    return {"cnpj": "00.000.000/0001-00", "nome": nome, "nome_n": E.norm(nome), "cat_n": E.norm(cat),
            "assunto": assunto, "assunto_n": E.norm(assunto), "data": d, "link": "", "protocolo": d.isoformat()}


CAT_A = "Informações de Companhias em Recuperação Judicial ou Extrajudicial"
CAT_FR = "Fato Relevante"


class ProtocoloCongelado(unittest.TestCase):
    def bloco(self):
        with open(NOTA_111, encoding="utf-8") as fh:
            t = fh.read().replace("\r\n", "\n")
        i = t.index("<!-- G0-INICIO -->\n") + len("<!-- G0-INICIO -->\n")
        return t[i:t.index("<!-- G0-FIM -->")]

    def test_hash_do_g0_nao_mudou(self):
        h = hashlib.sha256(self.bloco().encode("utf-8")).hexdigest()
        self.assertEqual(h, E.PROTOCOLO_SHA256)

    def test_regex_do_codigo_e_o_texto_congelado(self):
        b = self.bloco()
        for rx in (E.RX_CAT_RJ, E.RX_FR_POS, E.RX_FR_EXCL, E.RX_NOME_PREV):
            self.assertIn("`%s`" % rx, b, rx)
        self.assertIn("casa `encerramento`", b)


class ClassificacaoItem3(unittest.TestCase):
    def test_fr_de_rj_proprio_e_gatilho(self):
        self.assertEqual(E.classifica(doc(date(2013, 6, 6), CAT_FR, "Recuperação Judicial - RJ"))[0], "b_fato_relevante")

    def test_fr_com_exclusao_nao_e_gatilho(self):
        self.assertIsNone(E.classifica(doc(date(2016, 3, 18), CAT_FR, "Não declaração de vencimento antecipado"))[0])


class D3EncerramentoForaDeEpisodio(unittest.TestCase):
    def test_encerramento_isolado_abre_e_fecha_no_mesmo_documento(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_A, "Sentença de encerramento da RJ")])
        self.assertEqual(len(eps), 1)  # a v0 devolvia 0 (interpretacao I1)
        self.assertEqual(eps[0]["fim"], date(2015, 1, 9))
        self.assertEqual(eps[0]["fim_motivo"], "encerramento")

    def test_encerramento_dentro_de_episodio_fecha_sem_abrir_outro(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_A, "Petição inicial"),
                                          doc(date(2015, 6, 1), CAT_A, "Sentença de encerramento")])
        self.assertEqual(len(eps), 1)
        self.assertEqual(eps[0]["fim"], date(2015, 6, 1))


class D4FimPorExpiracao(unittest.TestCase):
    def test_episodio_sem_gatilho_posterior_tem_fim(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_A, "Petição inicial")])
        self.assertEqual(eps[0]["fim"], date(2016, 1, 9))  # a v0 deixava vazio
        self.assertEqual(eps[0]["fim_motivo"], "12m_sem_gatilho")

    def test_episodio_que_expira_depois_da_janela_fica_aberto(self):
        eps = E.construir_episodios("x", [doc(date(2026, 5, 1), CAT_A, "Petição inicial")])
        self.assertIsNone(eps[0]["fim"])

    def test_gatilho_depois_de_12_meses_abre_novo_episodio(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_A, "Petição"),
                                          doc(date(2016, 3, 1), CAT_A, "Edital")])
        self.assertEqual(len(eps), 2)


class Prevalencia(unittest.TestCase):
    def test_gatilho_a_nos_24_meses_torna_prevalente(self):
        lst = [doc(date(2015, 1, 9), CAT_A, "Petição"), doc(date(2016, 3, 1), CAT_A, "Edital")]
        eps = E.construir_episodios("x", lst)
        for e in eps:
            E.marcar_prevalencia(e, lst)
        self.assertFalse(eps[0]["prevalente"])
        self.assertTrue(eps[1]["prevalente"])

    def test_nome_em_recuperacao_torna_prevalente(self):
        lst = [doc(date(2014, 1, 1), "Comunicado ao Mercado", nome="X SA - EM RECUPERAÇÃO JUDICIAL"),
               doc(date(2015, 1, 9), CAT_FR, "Pedido de recuperação judicial")]
        ep = E.construir_episodios("x", lst)[0]
        E.marcar_prevalencia(ep, lst)
        self.assertTrue(ep["prevalente"])


class D1D2RegistroEEntradaNoRisco(unittest.TestCase):
    # Caso real da PRIO Forte (ex-Dommo Energia), CNPJ 08.926.302/0001-05:
    # registro 2014-09-17 a 2023-03-09 e novo registro em 2024-12-19.
    PER = [{"dt_reg": date(2014, 9, 17), "dt_cancel": date(2023, 3, 9)},
           {"dt_reg": date(2024, 12, 19), "dt_cancel": None}]

    def test_evento_coberto_pelo_primeiro_periodo(self):
        # a v0 lia so a ultima linha (2024) e trataria 2017 como anterior ao registro
        self.assertIs(E.periodo_vigente(self.PER, date(2017, 2, 7)), self.PER[0])

    def test_evento_entre_periodos_esta_fora_do_risco(self):
        ok, motivo, _ = E.em_risco(date(2024, 1, 1), self.PER, date(2015, 3, 30))
        self.assertFalse(ok)
        self.assertEqual(motivo, "pos_cancelamento")

    def test_evento_antes_do_primeiro_registro(self):
        ok, motivo, _ = E.em_risco(date(2013, 1, 1), self.PER, date(2015, 3, 30))
        self.assertEqual((ok, motivo), (False, "antes_do_registro"))

    def test_evento_sem_dfp_previa(self):
        ok, motivo, _ = E.em_risco(date(2015, 1, 1), self.PER, date(2015, 3, 30))
        self.assertEqual((ok, motivo), (False, "sem_dfp_previa"))

    def test_evento_no_dia_seguinte_a_dfp_entra(self):
        ok, motivo, _ = E.em_risco(date(2015, 3, 31), self.PER, date(2015, 3, 30))
        self.assertEqual((ok, motivo), (True, ""))

    def test_dfp_no_mesmo_dia_ainda_nao_conta(self):
        ok, _, _ = E.em_risco(date(2015, 3, 30), self.PER, date(2015, 3, 30))
        self.assertFalse(ok)

    def test_sem_cadastro(self):
        self.assertEqual(E.em_risco(date(2019, 5, 27), [], None)[:2], (False, "sem_cadastro"))


if __name__ == "__main__":
    unittest.main()
