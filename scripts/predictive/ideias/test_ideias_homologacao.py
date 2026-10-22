import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import homologacao_covenant as H  # noqa: E402
import piloto_covenant as P  # noqa: E402

TEM_SAIDA = os.path.exists(os.path.join(P.PASTA, "historico.json")) and os.path.exists(H.REGISTRO)


def tabela_dasa(valores, limite="Limite<4,0"):
    cab = "RELATORIO ANUAL DO AGENTE FIDUCIARIO\nEXERCICIO DE 2025\nINDICE           MARCO                JUNHO         SETEMBRO      DEZEMBRO*\n\n"
    l1 = "Divida Liquida/  " + "  ".join("%-18s" % limite for _ in valores) + "\n"
    l2 = "EBITDA           " + "  ".join("%-18s" % ("Apurado=" + str(v).replace(".", ",")) for v in valores) + "\n"
    return cab + l1 + l2


@unittest.skipUnless(TEM_SAIDA, "rodar piloto_covenant.py e homologacao_covenant.py registrar antes")
class TesteConferencia(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hist = json.load(open(os.path.join(P.PASTA, "historico.json"), encoding="utf-8"))

    def test_aprova_quando_bate_com_o_agente(self):
        cod, comp = H.conferir("Dasa", tabela_dasa([3.65, 2.57, 2.38, 2.5]), self.hist, "2026-04-30")
        self.assertEqual(cod, 0)
        self.assertEqual(len(comp), 4)

    def test_reprova_quando_o_agente_diverge(self):
        cod, _ = H.conferir("Dasa", tabela_dasa([3.0, 2.1, 1.9, 2.0]), self.hist, "2026-04-30")
        self.assertEqual(cod, 1)

    def test_reprova_quando_cruza_o_lado_do_limite(self):
        cod, comp = H.conferir("Dasa", tabela_dasa([3.65, 2.57, 2.38, 2.5], "Limite<2,6"), self.hist, "2026-04-30")
        self.assertIn(cod, (1, 2))  # limite diferente do covenant: nada comparavel ou reprovado, nunca aprovado

    def test_sem_trimestres_suficientes(self):
        cod, _ = H.conferir("Dasa", tabela_dasa([3.65]), self.hist, "2026-04-30")
        self.assertEqual(cod, 2)

    def test_nao_usa_estimativa_posterior_a_data_de_corte(self):
        cod, comp = H.conferir("Dasa", tabela_dasa([3.65, 2.57, 2.38, 2.5]), self.hist, "2025-01-01")
        self.assertEqual((cod, comp), (2, []))


@unittest.skipUnless(TEM_SAIDA, "rodar piloto_covenant.py e homologacao_covenant.py registrar antes")
class TesteGuarda(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.orig = H.REGISTRO
        H.REGISTRO = os.path.join(self.dir, "registro.json")
        shutil.copy(self.orig, H.REGISTRO)

    def tearDown(self):
        H.REGISTRO = self.orig
        shutil.rmtree(self.dir)

    def editar(self, f):
        reg = json.load(open(H.REGISTRO, encoding="utf-8"))
        f(reg)
        json.dump(reg, open(H.REGISTRO, "w", encoding="utf-8"))

    def test_pendente_reprova(self):
        self.editar(lambda r: r.update({"aprovacao": None}))
        self.assertEqual(H.verificar()[0], 1)

    def test_aprovado_e_intacto_passa(self):
        self.editar(lambda r: r.update({"aprovacao": {"por": "teste", "em": "x"}, "hashes": H.hashes()}))
        self.assertEqual(H.verificar()[0], 0)

    def test_aprovado_mas_codigo_mudou_reprova(self):
        def f(r):
            r["aprovacao"] = {"por": "teste", "em": "x"}
            r["hashes"] = H.hashes()
            r["hashes"]["codigo/piloto_covenant.py"] = "0" * 64
        self.editar(f)
        cod, msg = H.verificar()
        self.assertEqual(cod, 1)
        self.assertIn("piloto_covenant.py", msg)

    def test_sem_registro_reprova(self):
        os.remove(H.REGISTRO)
        self.assertEqual(H.verificar()[0], 1)


if __name__ == "__main__":
    unittest.main()
