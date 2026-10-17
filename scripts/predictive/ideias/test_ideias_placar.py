import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import placar as P  # noqa: E402


class TestePlacar(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.entrada = os.path.join(self.dir, "e.jsonl")
        with open(self.entrada, "w", encoding="utf-8", newline="\n") as fh:
            for i in range(5):
                fh.write(json.dumps({"poc": "t", "emp": "E%d" % i, "z": i * 1.5}) + "\n")
        self.ledger = os.path.join(self.dir, "l.jsonl")
        _, self.cabeca = P.gravar(self.ledger, [self.entrada])

    def linhas(self):
        return open(self.ledger, encoding="utf-8").read().split("\n")[:-1]

    def reescrever(self, linhas):
        open(self.ledger, "w", encoding="utf-8", newline="\n").write("\n".join(linhas) + "\n")

    def test_original_integro(self):
        self.assertTrue(P.verificar(self.ledger)[0])
        self.assertTrue(P.verificar(self.ledger, self.cabeca)[0])

    def test_alterar_um_byte_reprova(self):
        l = self.linhas()
        original = l[2]
        l[2] = original.replace('"z": 3.0', '"z": 3.1')
        self.assertEqual(len(l[2]), len(original))
        self.assertEqual(sum(a != b for a, b in zip(l[2], original)), 1)  # exatamente 1 caractere mudou
        self.reescrever(l)
        ok, msg, _ = P.verificar(self.ledger)
        self.assertFalse(ok)
        self.assertIn("linha 3", msg)

    def test_remover_linha_reprova(self):
        l = self.linhas()
        del l[1]
        self.reescrever(l)
        self.assertFalse(P.verificar(self.ledger)[0])

    def test_reordenar_reprova(self):
        l = self.linhas()
        l[1], l[2] = l[2], l[1]
        self.reescrever(l)
        self.assertFalse(P.verificar(self.ledger)[0])

    def test_acrescentar_pela_via_correta_continua_integro(self):
        P.gravar(self.ledger, [self.entrada])
        self.assertTrue(P.verificar(self.ledger)[0])
        self.assertFalse(P.verificar(self.ledger, self.cabeca)[0])  # ancora antiga nao e a cabeca nova

    def test_reescrever_a_cadeia_inteira_passa_sozinha_mas_falha_na_ancora(self):
        outro = os.path.join(self.dir, "falso.jsonl")
        with open(self.entrada, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps({"poc": "t", "emp": "FORJADO", "z": 9}) + "\n")
        P.gravar(outro, [self.entrada])
        self.assertTrue(P.verificar(outro)[0])  # limite declarado: sem ancora, uma cadeia forjada coerente passa
        self.assertFalse(P.verificar(outro, self.cabeca)[0])  # com ancora externa, falha

    def test_gravar_recusa_ledger_violado(self):
        l = self.linhas()
        l[0] = l[0].replace("E0", "EX")
        self.reescrever(l)
        with self.assertRaises(SystemExit):
            P.gravar(self.ledger, [self.entrada])


if __name__ == "__main__":
    unittest.main()
