"""Testes da e1-v1 (protocolo G0-v1, nota 113). Rodar:
  python -I -m unittest discover -s scripts/predictive/validacao -p "test_*.py" -v

Cada mudanca da G0-v1 tem as duas pontas: o caso que a G0-v0 errava e o caso bom
que nao pode quebrar.
"""
import hashlib
import os
import sys
import unittest
from datetime import date

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import e1_eventos_v1 as E  # noqa: E402

NOTA_113 = os.path.join(AQUI, "..", "..", "..", "Obsidian VIX Radar",
                        "113 - EWS 2.0 Protocolo de Validacao G0-v1 2026-10-15.md")

CAT_A = "Informações de Companhias em Recuperação Judicial ou Extrajudicial"
CAT_FR = "Fato Relevante"
CAT_CM = "Comunicado ao Mercado"


def doc(d, cat, assunto="", nome="EMPRESA TESTE SA", prot=None):
    return {"cnpj": "x", "nome": nome, "nome_n": E.V0.norm(nome), "cat_n": E.V0.norm(cat),
            "assunto": assunto, "assunto_n": E.V0.norm(assunto), "data": d, "link": "",
            "protocolo": prot or d.isoformat()}


def abre(cat, assunto):
    return E.gatilho_abertura(doc(date(2020, 1, 1), cat, assunto))


def bloco_da_nota():
    with open(NOTA_113, encoding="utf-8") as fh:
        t = fh.read().replace("\r\n", "\n")
    i = t.index("<!-- G0-INICIO -->\n") + len("<!-- G0-INICIO -->\n")
    return t[i:t.index("<!-- G0-FIM -->")]


def regex_batem(bloco, mod):
    pares = [("RX_CAT_A", mod.RX_CAT_A), ("RX_CAT_FR", mod.RX_CAT_FR), ("RX_A_ABRE", mod.RX_A_ABRE),
             ("RX_FR_POS", mod.RX_FR_POS), ("RX_FR_EXCL", mod.RX_FR_EXCL), ("RX_NAO_ABRE", mod.RX_NAO_ABRE),
             ("RX_ENCERRA", mod.RX_ENCERRA)]
    return [n for n, rx in pares if "- `%s`: `%s`" % (n, rx) not in bloco]


class GuardaDoProtocolo(unittest.TestCase):
    def test_hash_do_g0_v1_bate(self):
        self.assertEqual(hashlib.sha256(bloco_da_nota().encode("utf-8")).hexdigest(), E.PROTOCOLO_SHA256)

    def test_hash_reprova_bloco_alterado(self):
        b = bloco_da_nota().replace("24 meses", "36 meses", 1)
        self.assertNotEqual(hashlib.sha256(b.encode("utf-8")).hexdigest(), E.PROTOCOLO_SHA256)

    def test_regex_do_codigo_sao_os_do_bloco(self):
        self.assertEqual(regex_batem(bloco_da_nota(), E), [])

    def test_guarda_de_regex_reprova_regex_alterado(self):
        class Falso:
            pass
        f = Falso()
        for n in ("RX_CAT_A", "RX_CAT_FR", "RX_A_ABRE", "RX_FR_POS", "RX_FR_EXCL", "RX_NAO_ABRE", "RX_ENCERRA"):
            setattr(f, n, getattr(E, n))
        f.RX_FR_EXCL = E.RX_FR_EXCL.replace("|dividend", "")
        self.assertEqual(regex_batem(bloco_da_nota(), f), ["RX_FR_EXCL"])

    def test_constantes_do_g1_e_da_censura_estao_no_bloco(self):
        b = bloco_da_nota()
        self.assertIn("semente %d" % E.SEMENTE_G1, b)
        self.assertIn("auditoria manual de %d eventos" % E.N_AMOSTRA_G1, b)
        self.assertIn("com %d ou mais corretos" % E.MIN_CORRETOS_G1, b)
        for m in E.MOTIVOS_CENSURA:
            self.assertIn("`%s`" % m, b)
        self.assertIn("`%s`" % E.RX_SEC_SETOR, b)
        self.assertIn("`%s`" % E.RX_SEC_NOME, b)


class R1Titularidade(unittest.TestCase):
    def test_rj_da_controlada_nao_abre(self):
        self.assertIsNone(abre(CAT_FR, "Aprovação do Plano de Recuperação Judicial da Controlada CELPA"))
        self.assertIsNone(abre(CAT_FR, "Pedido de recuperação judicial de sua investida"))

    def test_rj_da_companhia_e_controladas_abre(self):
        self.assertEqual(abre(CAT_FR, "Pedido de Recuperação Judicial da Companhia e suas controladas"), "b")
        self.assertEqual(abre(CAT_FR, "Pedido de Recuperação Judicial da Companhia e de certas Subsidiárias"), "b")

    def test_devedor_de_lastro_nao_abre(self):
        self.assertIsNone(abre(CAT_FR, "Evento de não pagamento do lastro dos CRAs das séries 50ª e 51ª"))
        self.assertIsNone(abre(CAT_FR, "Recuperação Judicial da Devedora"))

    def test_securitizadora_sai_do_universo(self):
        self.assertTrue(E.eh_securitizadora([doc(date(2016, 1, 1), CAT_FR, nome="HABITASEC SECURITIZADORA SA")], []))
        self.assertTrue(E.eh_securitizadora([], [{"setor_ativ": "Securitização de Recebíveis"}]))

    def test_companhia_comum_fica_no_universo(self):
        self.assertFalse(E.eh_securitizadora([doc(date(2016, 1, 1), CAT_FR, nome="CLARION S/A AGROINDUSTRIAL")],
                                             [{"setor_ativ": "Agricultura (Açúcar, Álcool e Cana)"}]))


class R2Negacao(unittest.TestCase):
    def test_nao_vencimento_e_sustacao_nao_abrem(self):
        self.assertIsNone(abre(CAT_FR, "Aprovação de não vencimento antecipado das Debêntures"))
        self.assertIsNone(abre(CAT_FR, "Sustação definitiva dos efeitos do vencimento antecipado das debêntures"))

    def test_vencimento_antecipado_abre(self):
        self.assertEqual(abre(CAT_FR, "Vencimento Antecipado de Debêntures"), "b")


class R3CaudaDeProcessoAntigo(unittest.TestCase):
    def test_documento_a_de_plano_ou_edital_nao_abre(self):
        self.assertIsNone(abre(CAT_A, "Alteração do Plano de Recuperação Judicial e Aprovação da Proposta"))
        self.assertIsNone(abre(CAT_A, "Edital de Convocação de Credores"))
        self.assertIsNone(abre(CAT_A, "Pedido de aditamento ao plano"))

    def test_documento_a_de_pedido_ou_deferimento_abre(self):
        self.assertEqual(abre(CAT_A, "Deferimento do Processamento da Recuperação Extrajudicial"), "a")
        self.assertEqual(abre(CAT_A, "Petição inicial"), "a")

    def test_documento_a_sem_assunto_nao_abre_mas_renova(self):
        self.assertIsNone(abre(CAT_A, ""))
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_A, "Petição inicial"),
                                          doc(date(2015, 12, 1), CAT_A, ""),
                                          doc(date(2016, 6, 1), CAT_A, "Pedido de novo prazo")])
        self.assertEqual(len(eps), 1)
        self.assertEqual(eps[0]["ultimo"], date(2016, 6, 1))


class R4PrimeiroDocumentoPublico(unittest.TestCase):
    def test_cautelar_e_reestruturacao_abrem(self):
        self.assertEqual(abre(CAT_FR, "Protocolo medida cautelar"), "b")
        self.assertEqual(abre(CAT_FR, "Ajuizamento de cautelar"), "b")
        self.assertEqual(abre(CAT_FR, "Azul recebe todas as aprovações iniciais para seguir  processo de reestruturação"), "b")

    def test_comunicado_generico_nao_abre(self):
        self.assertIsNone(abre(CAT_FR, "Noticia veiculada na mídia - pedido cautelar credores"))
        self.assertIsNone(abre(CAT_FR, "Reestruturação societária"))
        self.assertIsNone(abre(CAT_CM, "Protocolo medida cautelar"))


class R5Encerramento(unittest.TestCase):
    def test_encerramento_isolado_nao_abre(self):
        eps = E.construir_episodios("x", [doc(date(2020, 12, 10), CAT_A, "Sentença de encerramento da RJ"),
                                          doc(date(2020, 12, 10), CAT_FR, "Encerramento da Recuperação Judicial")])
        self.assertEqual(eps, [])

    def test_encerramento_dentro_de_episodio_fecha(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_FR, "Pedido de Recuperação Judicial"),
                                          doc(date(2015, 12, 1), CAT_FR, "Encerramento da Recuperação Judicial")])
        self.assertEqual(len(eps), 1)
        self.assertEqual((eps[0]["fim"], eps[0]["fim_motivo"]), (date(2015, 12, 1), "encerramento"))


class R6Dividendo(unittest.TestCase):
    def test_dividendo_nao_abre(self):
        self.assertIsNone(abre(CAT_FR, "Não pagamento da primeira parcela da remuneração anual ao acionista"))
        self.assertIsNone(abre(CAT_FR, "Suspensão do pagamento dos dividendos declarados"))
        self.assertIsNone(abre(CAT_FR, "Não pagamento de juros sobre capital próprio"))

    def test_nao_pagamento_de_divida_abre(self):
        self.assertEqual(abre(CAT_FR, "Não pagamento da amortização anual das debêntures"), "b")


class R7PrevalenciaSemNome(unittest.TestCase):
    def test_nome_em_recuperacao_nao_torna_prevalente(self):
        nome = "RENOVA ENERGIA S.A. - EM RECUPERAÇÃO JUDICIAL"
        lst = [doc(date(2018, 1, 1), CAT_CM, "Resultado", nome=nome),
               doc(date(2019, 10, 16), CAT_FR, "Pedido de Recuperação Judicial", nome=nome)]
        ep = E.construir_episodios("x", lst)[0]
        self.assertFalse(E.eh_prevalente(ep, lst))

    def test_categoria_a_nos_24_meses_torna_prevalente(self):
        lst = [doc(date(2018, 1, 1), CAT_A, "Relatório mensal do administrador judicial"),
               doc(date(2019, 10, 16), CAT_FR, "Pedido de Recuperação Judicial")]
        ep = E.construir_episodios("x", lst)[0]
        self.assertTrue(E.eh_prevalente(ep, lst))

    def test_categoria_a_antes_dos_24_meses_nao_torna_prevalente(self):
        lst = [doc(date(2016, 1, 1), CAT_A, "Relatório mensal do administrador judicial"),
               doc(date(2019, 10, 16), CAT_FR, "Pedido de Recuperação Judicial")]
        ep = E.construir_episodios("x", lst)[0]
        self.assertFalse(E.eh_prevalente(ep, lst))


class D5MesmoDia(unittest.TestCase):
    def test_dois_gatilhos_no_mesmo_dia_abrem_um_episodio_nas_duas_ordens(self):
        a = doc(date(2023, 1, 19), CAT_A, "Petição inicial", prot="p1")
        b = doc(date(2023, 1, 19), CAT_FR, "Ajuizamento de Recuperação Judicial", prot="p2")
        self.assertEqual(len(E.construir_episodios("x", [a, b])), 1)
        self.assertEqual(len(E.construir_episodios("x", [b, a])), 1)

    def test_abre_fecha_e_reabre_no_mesmo_dia_conta_um(self):
        # caso Sansuy/Eneva da e1-v0.1: documento por documento, o encerramento fecha e o
        # gatilho seguinte do mesmo dia abre episodio novo
        a = doc(date(2020, 12, 10), CAT_A, "Petição inicial", prot="p1")
        enc = doc(date(2020, 12, 10), CAT_FR, "Encerramento da Recuperação Judicial", prot="p2")
        b = doc(date(2020, 12, 10), CAT_FR, "Pedido de Recuperação Judicial", prot="p3")
        self.assertEqual(len(E.construir_episodios("x", [a, enc, b])), 1)
        self.assertEqual(len(E.construir_episodios("x", [b, enc, a])), 1)

    def test_gatilhos_em_dias_diferentes_apos_12_meses_abrem_dois(self):
        eps = E.construir_episodios("x", [doc(date(2015, 1, 9), CAT_FR, "Pedido de Recuperação Judicial"),
                                          doc(date(2016, 3, 1), CAT_FR, "Pedido de Recuperação Judicial")])
        self.assertEqual(len(eps), 2)


class Item4Censura(unittest.TestCase):
    def test_migracao_de_registro_censura(self):
        self.assertEqual(E.motivo_censura("Migração de Registro (Resolução n° 60)"), "migracao de registro")
        self.assertEqual(E.motivo_censura("CANCELAMENTO DE OFÍCIO"), "cancelamento de oficio")

    def test_motivo_fora_da_lista_nao_censura(self):
        self.assertEqual(E.motivo_censura(""), "")
        self.assertEqual(E.motivo_censura("Outro motivo qualquer"), "")


class SorteioG1(unittest.TestCase):
    def ev(self, cnpj, d):
        return {"cnpj": cnpj, "data": d}

    def test_auditado_a_ate_30_dias_sai_da_amostra(self):
        self.assertTrue(E.perto_de_auditado("09.478.309/0001-66", date(2025, 7, 30)))
        self.assertTrue(E.perto_de_auditado("09.305.994/0001-29", date(2025, 10, 17)))

    def test_outra_empresa_ou_data_distante_fica(self):
        self.assertFalse(E.perto_de_auditado("09.478.309/0001-67", date(2025, 7, 30)))
        self.assertFalse(E.perto_de_auditado("09.305.994/0001-29", date(2025, 5, 30)))

    def test_sorteio_e_deterministico(self):
        inc = [self.ev("%02d" % i, date(2015, 1, 1 + i)) for i in range(25)]
        a1, n1 = E.sortear_amostra_g1(inc)
        a2, n2 = E.sortear_amostra_g1(list(reversed(inc)))
        self.assertEqual((n1, [e["cnpj"] for e in a1]), (n2, [e["cnpj"] for e in a2]))
        self.assertEqual(len(a1), 20)


if __name__ == "__main__":
    unittest.main()
