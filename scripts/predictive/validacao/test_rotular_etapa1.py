"""Portoes da rotulagem da etapa 1, duas pontas, sem chamar modelo.
Rodar: python -I -m unittest discover -s scripts/predictive/validacao -p "test_rotular_etapa1*.py" -v
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import rotular_etapa1 as RE  # noqa: E402


class Portoes(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.d, "g1eq"))
        self.aut = os.path.join(self.d, "autorizacao.json")

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def _g1eq(self, passa):
        with open(os.path.join(self.d, "g1eq", "resultado_g1eq.json"), "w", encoding="utf-8") as fh:
            json.dump({"passa": passa, "veredito": "passa" if passa else "reprova", "n_completos": 30}, fh)

    def _aut(self, ok=True):
        with open(self.aut, "w", encoding="utf-8") as fh:
            json.dump({"autorizado": ok, "data": "2026-10-20", "primeiro_rotulador": "claude", "segundo_rotulador": "codex"}, fh)

    def test_g1eq_incompleto_bloqueia_mesmo_autorizado(self):
        self._aut()
        with open(os.path.join(self.d, "g1eq", "resultado_g1eq.json"), "w", encoding="utf-8") as fh:
            json.dump({"passa": None, "veredito": "incompleto", "n_completos": 17}, fh)
        p = RE.portoes(self.d, self.aut)
        self.assertTrue(p["P3_autorizacao"]["ok"])
        self.assertFalse(p["P2_g1eq"]["ok"])
        self.assertFalse(p["ok"])

    def test_sem_g1eq_bloqueia(self):
        self._aut()
        p = RE.portoes(self.d, self.aut)
        self.assertFalse(p["P2_g1eq"]["ok"])
        self.assertFalse(p["ok"])

    def test_g1eq_reprovado_bloqueia(self):
        self._g1eq(False)
        self._aut()
        self.assertFalse(RE.portoes(self.d, self.aut)["ok"])

    def test_sem_autorizacao_bloqueia_mesmo_com_g1eq(self):
        self._g1eq(True)
        p = RE.portoes(self.d, self.aut)
        self.assertTrue(p["P2_g1eq"]["ok"])
        self.assertFalse(p["ok"])

    def test_autorizacao_falsa_bloqueia(self):
        self._g1eq(True)
        self._aut(ok=False)
        self.assertFalse(RE.portoes(self.d, self.aut)["ok"])

    def test_tudo_aberto_libera_so_se_guarda_g0v3_ok(self):
        self._g1eq(True)
        self._aut()
        p = RE.portoes(self.d, self.aut)
        self.assertEqual(p["ok"], p["P1_guarda_g0v3"]["ok"])
        self.assertTrue(p["P2_g1eq"]["ok"] and p["P3_autorizacao"]["ok"])

    def test_rodar_bloqueado_nao_grava_nada(self):
        rc = RE.rodar(self.d, self.d, dry_run=True, autorizacao=self.aut)
        self.assertEqual(rc, RE.EXIT_BLOQUEADO)
        self.assertFalse(os.path.exists(os.path.join(self.d, "..", "rotulos_etapa1.csv")))

    def test_linha_de_resultado_traz_origem_so_na_gravacao(self):
        item = {"id": "i0001", "cnpj": "c", "data": "2020-01-01"}
        r = {"rotulo": {"classe": "continuacao", "origem": {"protocolo": "9", "data_entrega": "2019-01-01", "tipo": "RJ", "trecho": "x"}, "adicionais": []},
             "status": "rotulado", "falhas_trecho": [], "modelo": "m", "versao_executor": "v", "sha256_bloco_v3": "h"}
        l = RE.linha_de_resultado(item, {"i0001": {"origem": "G"}}, r, {"9": {"sha256": "s", "baixado_em": "d"}})
        self.assertEqual(l["origem"], "G")
        self.assertEqual(l["protocolo"], "9")
        self.assertEqual(l["sha256_documento"], "s")
        self.assertEqual(l["classe1"], "continuacao")


if __name__ == "__main__":
    unittest.main()
