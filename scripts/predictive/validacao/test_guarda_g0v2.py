"""Testes da guarda do G0-v2. Rodar a partir da raiz do repo:
  python -I -m unittest discover -s scripts/predictive/validacao -p "test_guarda*.py" -v
  (a forma "python -m unittest scripts/predictive/validacao/test_guarda_g0v2.py" falha com -I,
  porque "scripts" nao e pacote; a docstring antiga mandava essa forma e ela dava ImportError)

Cada guarda tem as duas pontas: o caso que ela precisa reprovar e o caso bom que ela precisa aceitar.
"""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v2 as G  # noqa: E402


def nota():
    return G.ler(G.NOTA_116)


class ProtocoloG0v2(unittest.TestCase):
    # ponta boa
    def test_hash_do_bloco_congelado_bate(self):
        r = G.verificar_protocolo()
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["sha256"], G.PROTOCOLO_G0V2_SHA256)
        self.assertEqual(r["bytes"], 24777)

    def test_crlf_nao_muda_o_hash(self):
        self.assertTrue(G.verificar_protocolo(nota().replace("\n", "\r\n"))["ok"])

    def test_texto_fora_do_bloco_pode_mudar(self):
        t = nota().replace("status: congelado", "status: STATUS ALTERADO FORA DO BLOCO", 1)
        self.assertNotEqual(t, nota())
        self.assertTrue(G.verificar_protocolo(t)["ok"])

    # ponta ruim
    def test_parametro_alterado_dentro_do_bloco_reprova(self):
        t = nota().replace("kappa binário ponderado | 0,8 ou mais", "kappa binário ponderado | 0,7 ou mais", 1)
        self.assertNotEqual(t, nota())
        self.assertFalse(G.verificar_protocolo(t)["ok"])

    def test_um_caractere_dentro_do_bloco_reprova(self):
        t = nota().replace("1. Universo de candidatos", "1. Universo de candidato", 1)
        self.assertNotEqual(t, nota())
        self.assertFalse(G.verificar_protocolo(t)["ok"])

    def test_semente_alterada_reprova(self):
        t = nota().replace("20261017", "20261018", 1)
        self.assertNotEqual(t, nota())
        self.assertFalse(G.verificar_protocolo(t)["ok"])

    def test_marcador_ausente_levanta(self):
        with self.assertRaises(ValueError):
            G.verificar_protocolo(nota().replace("<!-- G0-V2-FIM -->", "", 1))

    def test_marcador_repetido_levanta(self):
        with self.assertRaises(ValueError):
            G.verificar_protocolo(nota() + "\n<!-- G0-V2-INICIO -->\n")

    def test_regra_ingenua_do_marcador_da_outro_hash(self):
        """Documenta o erro que a guarda evita: incluir o LF depois do marcador."""
        t = nota().replace("\r\n", "\n")
        i = t.index(G.MARC_G0[0]) + len(G.MARC_G0[0])
        ingenuo, n = G.sha256_texto(t[i:t.index(G.MARC_G0[1])])
        self.assertEqual(n, 24778)
        self.assertNotEqual(ingenuo, G.PROTOCOLO_G0V2_SHA256)


class AnexoGuia(unittest.TestCase):
    TXT = "cabecalho\n<!-- G0-V2-ANEXO-INICIO -->\nregra A\nregra B\n<!-- G0-V2-ANEXO-FIM -->\nrodape\n"

    def test_sem_hash_registrado_e_nao_congelado(self):
        self.assertEqual(G.verificar_anexo(self.TXT, esperado=None)["estado"], "nao_congelado")

    def test_hash_registrado_bate(self):
        h = G.sha256_texto(G.extrair_bloco(self.TXT, G.MARC_ANEXO))[0]
        self.assertEqual(G.verificar_anexo(self.TXT, esperado=h)["estado"], "ok")

    def test_hash_e_bytes_registrados_batem(self):
        h, n = G.sha256_texto(G.extrair_bloco(self.TXT, G.MARC_ANEXO))
        self.assertEqual(G.verificar_anexo(self.TXT, esperado=h, esperado_bytes=n)["estado"], "ok")

    def test_bytes_registrados_errados_reprovam(self):
        h, n = G.sha256_texto(G.extrair_bloco(self.TXT, G.MARC_ANEXO))
        self.assertEqual(G.verificar_anexo(self.TXT, esperado=h, esperado_bytes=n + 1)["estado"], "divergente")

    def test_anexo_alterado_depois_do_congelamento_reprova(self):
        h = G.sha256_texto(G.extrair_bloco(self.TXT, G.MARC_ANEXO))[0]
        t = self.TXT.replace("regra A", "regra A2")
        self.assertEqual(G.verificar_anexo(t, esperado=h)["estado"], "divergente")

    def test_texto_fora_do_bloco_do_anexo_nao_conta(self):
        h = G.sha256_texto(G.extrair_bloco(self.TXT, G.MARC_ANEXO))[0]
        self.assertEqual(G.verificar_anexo(self.TXT.replace("rodape", "outro rodape"), esperado=h)["estado"], "ok")

    def test_anexo_real_tem_marcadores_unicos(self):
        r = G.verificar_anexo()
        self.assertIn(r["estado"], ("nao_congelado", "ok"), r)

    def test_constante_so_e_preenchida_com_anexo_que_bate(self):
        if G.ANEXO_SHA256 is not None:
            self.assertEqual(G.verificar_anexo()["estado"], "ok")


class AnexoRealCongelado(unittest.TestCase):
    """Duas pontas sobre a nota 117 real, com as constantes congeladas em 16/10/2026."""

    def setUp(self):
        self.t = G.ler(G.NOTA_ANEXO)

    # ponta boa
    def test_constantes_congeladas(self):
        self.assertEqual(G.ANEXO_SHA256, "6d3b0da7912d5ce323235fbac6b3038140bb0dc841f28de4c2828184cac8ac73")
        self.assertEqual(G.ANEXO_BYTES, 20866)

    def test_anexo_real_bate(self):
        r = G.verificar_anexo()
        self.assertEqual(r["estado"], "ok", r)
        self.assertEqual(r["bytes"], 20866)

    def test_crlf_nao_muda_o_anexo(self):
        self.assertEqual(G.verificar_anexo(self.t.replace("\n", "\r\n"))["estado"], "ok")

    def test_texto_fora_do_bloco_do_anexo_real_pode_mudar(self):
        t = self.t.replace("## Registro do hash", "## Registro do hash (editado fora do bloco)", 1)
        self.assertNotEqual(t, self.t)
        self.assertEqual(G.verificar_anexo(t)["estado"], "ok")

    # ponta ruim
    def test_prova_retirada_da_lista_fechada_reprova(self):
        t = self.t.replace("- P5. Protesto ou execução", "- P5. Protesto", 1)
        self.assertNotEqual(t, self.t)
        self.assertEqual(G.verificar_anexo(t)["estado"], "divergente")

    def test_leitura_de_caso_alterada_reprova(self):
        t = self.t.replace("| 111-2 Habitasec, cand. 28/06/2016 | FR 521877, RJ da Deltaville, devedora do CRI da 39ª série | ET |",
                           "| 111-2 Habitasec, cand. 28/06/2016 | FR 521877, RJ da Deltaville, devedora do CRI da 39ª série | EP |", 1)
        self.assertNotEqual(t, self.t)
        self.assertEqual(G.verificar_anexo(t)["estado"], "divergente")

    def test_um_caractere_no_bloco_do_anexo_reprova(self):
        t = self.t.replace("**D2. Chapter 11.**", "**D2. Chapter 11**", 1)
        self.assertNotEqual(t, self.t)
        self.assertEqual(G.verificar_anexo(t)["estado"], "divergente")

    def test_bloco_do_anexo_estendido_reprova(self):
        t = self.t.replace("\n<!-- G0-V2-ANEXO-FIM -->", "\nRegra nova acrescentada.\n<!-- G0-V2-ANEXO-FIM -->", 1)
        self.assertEqual(G.verificar_anexo(t)["estado"], "divergente")


class VereditoGlobal(unittest.TestCase):
    """Risco fechado em 16/10/2026: antes, main() devolvia ok:true com o anexo 'nao_congelado'."""
    OK_P = {"ok": True}
    OK_M = {"ok": True}

    # ponta ruim
    def test_anexo_nao_congelado_reprova_o_global(self):
        ok, motivos = G.avaliar(self.OK_P, {"estado": "nao_congelado"}, self.OK_M)
        self.assertFalse(ok)
        self.assertTrue(any("nao congelado" in m for m in motivos), motivos)

    def test_anexo_divergente_reprova_o_global(self):
        ok, motivos = G.avaliar(self.OK_P, {"estado": "divergente"}, self.OK_M)
        self.assertFalse(ok)
        self.assertTrue(any("alterado" in m for m in motivos), motivos)

    def test_anexo_ausente_reprova_o_global(self):
        ok, _ = G.avaliar(self.OK_P, {"estado": "ausente"}, self.OK_M)
        self.assertFalse(ok)

    def test_protocolo_ruim_reprova_mesmo_com_anexo_ok(self):
        ok, motivos = G.avaliar({"ok": False}, {"estado": "ok"}, self.OK_M)
        self.assertFalse(ok)
        self.assertEqual(len(motivos), 1)

    def test_manifesto_ruim_reprova_mesmo_com_anexo_ok(self):
        ok, _ = G.avaliar(self.OK_P, {"estado": "ok"}, {"ok": False})
        self.assertFalse(ok)

    def test_tres_falhas_dao_tres_motivos(self):
        ok, motivos = G.avaliar({"ok": False}, {"estado": "divergente"}, {"ok": False})
        self.assertFalse(ok)
        self.assertEqual(len(motivos), 3)

    # ponta boa
    def test_tudo_ok_aprova_sem_motivos(self):
        ok, motivos = G.avaliar(self.OK_P, {"estado": "ok"}, self.OK_M)
        self.assertTrue(ok)
        self.assertEqual(motivos, [])

    def test_main_aprova_estado_real_congelado(self):
        """Estado real do repo depois de 16/10: protocolo, anexo e manifesto batem, exit 0."""
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = G.main([])
        saida = json.loads(buf.getvalue())
        self.assertEqual(rc, 0, saida)
        self.assertTrue(saida["ok"])
        self.assertEqual(saida["motivos"], [])
        self.assertEqual(saida["anexo"]["estado"], "ok")

    def test_main_reprova_se_o_anexo_voltar_a_nao_congelado(self):
        """A regressao fechada em 16/10: constante vazia nao pode mais dar ok:true."""
        antigo = (G.ANEXO_SHA256, G.ANEXO_BYTES)
        try:
            G.ANEXO_SHA256, G.ANEXO_BYTES = None, None
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = G.main([])
            saida = json.loads(buf.getvalue())
            self.assertEqual(rc, 1)
            self.assertFalse(saida["ok"])
            self.assertEqual(saida["anexo"]["estado"], "nao_congelado")
        finally:
            G.ANEXO_SHA256, G.ANEXO_BYTES = antigo

    def test_main_reprova_com_bytes_congelados_errados(self):
        antigo = G.ANEXO_BYTES
        try:
            G.ANEXO_BYTES = 20867
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = G.main([])
            self.assertEqual(rc, 1)
            self.assertEqual(json.loads(buf.getvalue())["anexo"]["estado"], "divergente")
        finally:
            G.ANEXO_BYTES = antigo

    def test_main_aprova_com_hash_do_anexo_real_injetado(self):
        """Simula o congelamento: a constante recebe o hash que o anexo atual tem, e o global vira ok."""
        real = G.verificar_anexo(esperado="x")  # so para obter sha256 e bytes atuais
        antigo = (G.ANEXO_SHA256, G.ANEXO_BYTES)
        try:
            G.ANEXO_SHA256, G.ANEXO_BYTES = real["sha256"], real["bytes"]
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = G.main([])
            saida = json.loads(buf.getvalue())
            self.assertEqual(rc, 0)
            self.assertTrue(saida["ok"])
            self.assertEqual(saida["anexo"]["estado"], "ok")
            # e com hash errado injetado, divergente e exit 1
            G.ANEXO_SHA256 = "0" * 64
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = G.main([])
            self.assertEqual(rc, 1)
            self.assertEqual(json.loads(buf.getvalue())["anexo"]["estado"], "divergente")
        finally:
            G.ANEXO_SHA256, G.ANEXO_BYTES = antigo

    def test_hash_anexo_imprime_e_nao_julga(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = G.main(["--hash-anexo"])
        saida = json.loads(buf.getvalue())
        self.assertEqual(rc, 0)
        self.assertEqual(len(saida["anexo"]["sha256"]), 64)
        self.assertEqual(saida["anexo"]["sha256"], G.verificar_anexo(esperado="x")["sha256"])


class ManifestoDaMigracao(unittest.TestCase):
    def test_arquivos_migrados_batem_com_o_manifesto(self):
        r = G.verificar_manifesto()
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["arquivos"], 16)

    def test_doze_scripts_pedidos_estao_no_manifesto(self):
        with open(G.MANIFESTO, encoding="utf-8") as fh:
            m = json.load(fh)
        scripts = [a["arquivo"] for a in m["arquivos"] if a["tipo"] == "script"]
        self.assertEqual(len(scripts), 12)

    def test_arquivo_alterado_reprova(self):
        with tempfile.TemporaryDirectory() as d:
            with open(G.MANIFESTO, encoding="utf-8") as fh:
                arquivos = json.load(fh)["arquivos"]
            for a in arquivos:
                shutil.copy(os.path.join(AQUI, a["arquivo"]), os.path.join(d, a["arquivo"]))
            alvo = os.path.join(d, "g1b_v2.py")
            with open(alvo, "ab") as fh:
                fh.write(b"\n# adulterado\n")
            r = G.verificar_manifesto(pasta=d)
            self.assertFalse(r["ok"])
            self.assertEqual([e["arquivo"] for e in r["erros"]], ["g1b_v2.py"])

    def test_arquivo_ausente_reprova(self):
        with tempfile.TemporaryDirectory() as d:
            r = G.verificar_manifesto(pasta=d)
            self.assertFalse(r["ok"])
            self.assertEqual(len(r["erros"]), 16)


if __name__ == "__main__":
    unittest.main()
