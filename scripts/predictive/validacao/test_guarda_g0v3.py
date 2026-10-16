"""Trava da rotulagem G0-v3, duas pontas.
Rodar: python -I -m unittest discover -s scripts/predictive/validacao -p "test_guarda_g0v3*.py" -v
"""
import os
import sys
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import gerar_g0v3 as GV  # noqa: E402
import guarda_g0v3 as G3  # noqa: E402
import guarda_g0v2 as G2  # noqa: E402


class TravaG0v3(unittest.TestCase):
    def setUp(self):
        self.t = G2.ler(G3.NOTA_120)
        self.r = G3.estado()

    # ponta ruim
    def test_sem_congelamento_rotulagem_bloqueada(self):
        if G3.PROTOCOLO_G0V3_SHA256 is None:
            self.assertFalse(G3.rotulagem_liberada())
            self.assertIn("G0-v3 nao congelada: rotulagem bloqueada ate aprovacao do operador", self.r["motivos"])

    def test_bloco_alterado_depois_de_congelar_reprova(self):
        t = self.t.replace("12.000 caracteres", "15.000 caracteres", 1)
        self.assertNotEqual(t, self.t)
        r = G3.estado(t, esperado=self.r["sha256_v3"], esperado_bytes=self.r["bytes_v3"],
                      rec_esperado=self.r["sha256_recuperar"])
        self.assertFalse(r["ok"])
        self.assertIn("bloco G0-v3 alterado depois do congelamento", r["motivos"])

    def test_script_de_recuperacao_trocado_reprova(self):
        r = G3.estado(esperado=self.r["sha256_v3"], esperado_bytes=self.r["bytes_v3"], rec_esperado="0" * 64)
        self.assertFalse(r["ok"])
        self.assertIn("recuperar_g0v3.py difere do registrado", r["motivos"])

    # ponta boa
    def test_congelamento_simulado_libera(self):
        r = G3.estado(esperado=self.r["sha256_v3"], esperado_bytes=self.r["bytes_v3"],
                      rec_esperado=self.r["sha256_recuperar"])
        self.assertTrue(r["ok"], r)

    def test_texto_fora_do_bloco_nao_conta(self):
        t = self.t.replace("## Decisões do operador", "## Decisões do operador (editado)", 1)
        r = G3.estado(t, esperado=self.r["sha256_v3"], esperado_bytes=self.r["bytes_v3"],
                      rec_esperado=self.r["sha256_recuperar"])
        self.assertTrue(r["ok"], r)

    # o bloco da nota e exatamente o que o gerador produz a partir do v2 congelado
    def test_bloco_da_nota_e_o_gerado(self):
        _, v3 = GV.gerar()
        self.assertEqual(G2.extrair_bloco(self.t, G3.MARC_V3), v3)

    # estado real depois do congelamento de 16/10
    def test_estado_real_congelado_libera(self):
        self.assertEqual(G3.PROTOCOLO_G0V3_SHA256, "0f1b0af52d5a192a610e6c274710ceaea05584d8f59197b4f3031b2a261735fa")
        self.assertEqual(G3.PROTOCOLO_G0V3_BYTES, 27326)
        self.assertTrue(self.r["ok"], self.r)
        self.assertTrue(G3.rotulagem_liberada())

    def test_estado_real_com_constante_vazia_volta_a_bloquear(self):
        r = G3.estado(esperado=None)
        self.assertFalse(r["ok"])
        self.assertIn("G0-v3 nao congelada: rotulagem bloqueada ate aprovacao do operador", r["motivos"])

    def test_estado_real_com_bytes_errados_reprova(self):
        r = G3.estado(esperado_bytes=27327)
        self.assertFalse(r["ok"])
        self.assertIn("bloco G0-v3 alterado depois do congelamento", r["motivos"])

    def test_v2_continua_intacto(self):
        self.assertTrue(G2.verificar_protocolo()["ok"])
        self.assertEqual(G2.verificar_anexo()["estado"], "ok")


if __name__ == "__main__":
    unittest.main()
