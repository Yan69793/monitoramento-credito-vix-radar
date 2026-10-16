"""Testes da recuperacao progressiva (proposta G0-v3). Duas pontas, documentos reais ja baixados.
Rodar: python -I -m unittest discover -s scripts/predictive/validacao -p "test_recuperar*.py" -v
Testes que dependem de documento baixado sao pulados se o arquivo nao existir.
"""
import os
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import recuperar_g0v3 as R  # noqa: E402

TXT = r"E:\Diretorio\Claude\tmp\operacional\vix-radar\ews-etapa1\TXT"


def tem(p):
    return os.path.exists(os.path.join(TXT, "%s.txt" % p))


META = lambda p: {p: {"data_entrega": "2026-01-01", "categoria": "fato relevante", "assunto": ""}}  # noqa: E731


class Ancoras(unittest.TestCase):
    def test_termo_de_credito_vira_ancora(self):
        txt = "x" * 2000 + " a companhia ajuizou pedido de recuperação judicial " + "y" * 2000
        a = R.ancoras(txt, 5000)
        self.assertEqual(len(a), 1)
        self.assertIn("recuperação judicial", a[0])

    def test_texto_sem_termo_nao_gera_ancora(self):
        self.assertEqual(R.ancoras("eleicao de membros do conselho, aprovacao de contas " * 50, 5000), [])

    def test_janelas_sobrepostas_fundem(self):
        txt = "z" * 1000 + " credores " + "w" * 100 + " standstill " + "z" * 1000
        self.assertEqual(len(R.ancoras(txt, 5000)), 1)

    def test_teto_corta_e_declara(self):
        txt = (" debentures " + "q" * 900) * 40
        a = R.ancoras(txt, 3000)
        self.assertTrue(a[-1].startswith("[ANCORAS CORTADAS"))

    def test_acento_nao_desalinha(self):
        txt = "ção" * 300 + " vencimento antecipado das debêntures " + "ção" * 300
        a = R.ancoras(txt, 5000)
        self.assertIn("vencimento antecipado das debêntures", a[0])

    def test_deterministico(self):
        txt = ("bla " * 300 + " inadimplemento ") * 10
        self.assertEqual(R.ancoras(txt, 4000), R.ancoras(txt, 4000))


class DocumentosReais(unittest.TestCase):
    """Os documentos das ressalvas da nota 117 tem a prova no corpo. A ancora tem que alcanca-la mesmo fora do
    cabecalho; isto mede o risco que o G0-v3 introduz."""

    def _fora_do_cabecalho(self, p, frase, cab=300):
        if not tem(p):
            self.skipTest("documento %s nao baixado" % p)
        txt = R.ler_txt(TXT, p)
        self.assertIn(R.norm_trecho(frase), R.norm_trecho(txt), "frase nao esta no documento")
        self.assertNotIn(R.norm_trecho(frase), R.norm_trecho(R.limpa(txt)[:cab]) if len(R.limpa(txt)) > cab else "",
                         "frase ja esta no cabecalho; o teste nao mede ancora")
        bloco = R.bloco_doc(p, META(p), R.ler_txt(TXT, p), cab, R.TETO_ANCORA_CTX)
        self.assertIn(R.norm_trecho(frase), R.norm_trecho(bloco))

    def test_ambipar_cautelar_suspende_vencimento(self):
        self._fora_do_cabecalho("1426531", "vencimento antecipado das dívidas do Grupo Ambipar")

    def test_liq_fim_do_prazo_de_cura(self):
        self._fora_do_cabecalho("676028", "encerrou-se o prazo de cura")

    def test_cvlb_mediacao_20b(self):
        self._fora_do_cabecalho("1467290", "artigo 20-B")

    def test_kora_deferimento(self):
        self._fora_do_cabecalho("1515448", "deferiu o processamento da recuperação extrajudicial")

    def test_escaneado_e_declarado_sem_texto(self):
        if not tem("569477"):
            self.skipTest("569477 nao baixado")
        b = R.bloco_doc("569477", META("569477"), R.ler_txt(TXT, "569477"), R.CAB_CTX, R.TETO_ANCORA_CTX)
        self.assertIn("SEM TEXTO EXTRAIVEL", b)


class Nivel2(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        with open(os.path.join(self.d, "111.txt"), "w", encoding="utf-8") as fh:
            fh.write("pagina um com bastante texto para passar do minimo de oitenta caracteres do extrator\fpagina dois\fpagina tres")

    def test_serve_faixa_de_paginas(self):
        t, log = R.servir_nivel2([{"protocolo": "111", "paginas": "2-3"}], {"111"}, self.d)
        self.assertIn("pagina dois", t)
        self.assertNotIn("pagina um", t)
        self.assertEqual(log[0]["status"], "servido")

    def test_recusa_fora_do_indice(self):
        t, log = R.servir_nivel2([{"protocolo": "999", "paginas": "1"}], {"111"}, self.d)
        self.assertEqual(log[0]["status"], "recusado_fora_do_indice")
        self.assertEqual(t, "")

    def test_nao_baixado_declarado(self):
        _, log = R.servir_nivel2([{"protocolo": "222"}], {"222"}, self.d)
        self.assertEqual(log[0]["status"], "nao_baixado")


class Evidencia(unittest.TestCase):
    def test_trecho_literal_aceito(self):
        if not tem("676028"):
            self.skipTest("676028 nao baixado")
        self.assertTrue(R.verificar_trecho("encerrou-se o prazo de cura de 10 (dez) dias úteis", "676028", TXT))

    def test_trecho_inventado_recusado(self):
        if not tem("676028"):
            self.skipTest("676028 nao baixado")
        self.assertFalse(R.verificar_trecho("a companhia pediu recuperação judicial", "676028", TXT))

    def test_trecho_em_documento_errado_recusado(self):
        if not (tem("676028") and tem("1467290")):
            self.skipTest("documentos nao baixados")
        self.assertFalse(R.verificar_trecho("encerrou-se o prazo de cura", "1467290", TXT))


if __name__ == "__main__":
    unittest.main()
