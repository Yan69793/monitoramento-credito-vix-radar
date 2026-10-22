import json
import os
import sys
import unittest
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import piloto_covenant as P  # noqa: E402

REGRA = {"componentes": {"divida": [{"s": 1, "dem": "BPP", "cd": "^2\\.02\\.01$"}], "caixa": [{"s": 1, "dem": "BPA", "cd": "^1\\.01\\.01$"}],
                         "ebitda": [{"s": 1, "dem": "DRE", "cd": "^3\\.05$"}]}, "indices": {P.IND: "x"}}


def rec(divida, caixa, ebit, receb, v=1):
    return {"versao": v, "dt_receb": receb, "tipo": "DFP",
            "linhas": {"BPA": [("1.01.01", "caixa", caixa)], "BPP": [("2.02.01", "emprestimos", divida)], "DRE": [("3.05", "ebit", ebit)], "DFC": []}}


def af(ano, apurado, lim=4.0, op="<", indice="Divida Liquida/ EBITDA"):
    return {"indice": indice, "mes": 12, "ano": ano, "operador": op, "limite": lim, "apurado": apurado}


ESC = {"protocolo": "E1", "data_entrega": "2019-01-10", "emissao": 1}
AFM = {"protocolo": "A1", "data_entrega": "2025-04-30", "emissao": 1}
TXT_UNICO = "Divida Liquida pelo EBITDA, que devera ser inferior a 4 (quatro) vezes, apurado trimestralmente"
TXT_DEGRAUS = "Divida Financeira Liquida/EBITDA menor ou igual a: (a) 3,50 (tres inteiros), ate X; (b) 3,75 (tres), ate Y; (c) 4,00 (quatro), depois."
TXT_GATILHO = "vencimento antecipado quando o quociente da Divida Liquida pelo EBITDA for superior a 4,0 (quatro) vezes"


class TesteCovenantAutomatico(unittest.TestCase):
    def test_limite_unico_ativa_na_data_da_escritura(self):
        c = P.covenant_automatico(TXT_UNICO, [], ESC, {})
        self.assertEqual((c["status"], c["operador"], c["limite"], c["ativo_desde"]), ("ATIVO", "<", 4.0, "2019-01-10"))

    def test_degraus_sem_agente_bloqueia(self):
        self.assertEqual(P.covenant_automatico(TXT_DEGRAUS, [], ESC, {})["status"], "NAO_CALCULAVEL")

    def test_degraus_com_agente_ativa_so_na_data_do_agente(self):
        c = P.covenant_automatico(TXT_DEGRAUS, [af(2024, 3.0, 3.75, "<=")], ESC, AFM)
        self.assertEqual((c["status"], c["limite"], c["ativo_desde"]), ("ATIVO", 3.75, "2025-04-30"))

    def test_gatilho_sem_agente_bloqueia(self):
        self.assertEqual(P.covenant_automatico(TXT_GATILHO, [], ESC, {})["status"], "NAO_CALCULAVEL")

    def test_limite_diferente_do_agente_bloqueia(self):
        c = P.covenant_automatico(TXT_UNICO, [af(2024, 3.0, 3.5, "<=")], ESC, AFM)
        self.assertEqual(c["status"], "NAO_CALCULAVEL")
        self.assertIn("difere", c["motivo"])

    def test_sem_covenant_bloqueia(self):
        self.assertEqual(P.covenant_automatico("texto sem indice financeiro", [], ESC, {})["status"], "NAO_CALCULAVEL")


class TesteTempo(unittest.TestCase):
    def test_reapresentacao_so_vale_depois_de_recebida(self):
        v = {("X", "2024-12-31", 1): rec(100, 0, 50, "2025-03-01", 1), ("X", "2024-12-31", 2): rec(100, 0, 25, "2025-06-01", 2)}
        self.assertEqual(P.foto(v, "X", "2025-05-31")[("X", "2024-12-31")]["versao"], 1)
        self.assertEqual(P.foto(v, "X", "2025-06-01")[("X", "2024-12-31")]["versao"], 2)
        self.assertNotIn(("X", "2024-12-31"), P.foto(v, "X", "2025-02-28"))

    def test_confiabilidade_so_depois_do_relatorio_do_agente(self):
        v = {("X", "%d-12-31" % a, 1): rec(300, 0, 100, "%d-03-01" % (a + 1)) for a in range(2021, 2025)}
        cov = {"status": "ATIVO", "operador": "<", "limite": 4.0, "motivo": ""}
        linhas = [af(a, 3.0) for a in range(2021, 2025)]
        antes = P.confiabilidade(v, "X", REGRA, cov, linhas, date(2025, 4, 30), date(2025, 4, 30))
        depois = P.confiabilidade(v, "X", REGRA, cov, linhas, date(2025, 4, 30), date(2025, 5, 1))
        self.assertEqual(antes[0], "NAO_CALCULAVEL")
        self.assertEqual(depois[0], "REPRODUZIVEL")

    def test_series_divergentes_do_agente_bloqueiam(self):
        v = {("X", "%d-12-31" % a, 1): rec(300, 0, 100, "%d-03-01" % (a + 1)) for a in range(2021, 2025)}
        cov = {"status": "ATIVO", "operador": "<", "limite": 4.0, "motivo": ""}
        linhas = [af(a, 3.0) for a in range(2021, 2025)] + [af(2024, 2.5)]
        self.assertEqual(P.confiabilidade(v, "X", REGRA, cov, linhas, date(2025, 4, 30), date(2025, 6, 1))[0], "NAO_CALCULAVEL")

    def test_calculo_conservador_vira_parcial_e_divergente_bloqueia(self):
        v = {("X", "%d-12-31" % a, 1): rec(300, 0, 100, "%d-03-01" % (a + 1)) for a in range(2021, 2025)}
        cov = {"status": "ATIVO", "operador": "<", "limite": 4.0, "motivo": ""}
        parcial = P.confiabilidade(v, "X", REGRA, cov, [af(a, 2.5) for a in range(2021, 2025)], date(2025, 4, 30), date(2025, 6, 1))
        self.assertEqual(parcial[0], "PARCIAL")
        mista = [af(2021, 2.5), af(2022, 3.5), af(2023, 2.5), af(2024, 3.5)]
        self.assertEqual(P.confiabilidade(v, "X", REGRA, cov, mista, date(2025, 4, 30), date(2025, 6, 1))[0], "NAO_CALCULAVEL")


class TesteAlertas(unittest.TestCase):
    def a(self, m, classe="REPRODUZIVEL", ant=None):
        return [t for t, _, _ in P.alertas_da_linha({"margem": m, "classe": classe}, ant)]

    def test_faixas_perto_do_limite(self):
        self.assertEqual(self.a(0.30), [])
        self.assertEqual(self.a(0.24), ["atencao"])
        self.assertEqual(self.a(0.09), ["proximo_do_limite"])

    def test_estimativa_alem_do_limite_nunca_e_violacao(self):
        self.assertEqual(self.a(-0.01), ["rompimento_estimado"])
        self.assertEqual(self.a(-0.01, "PARCIAL"), ["rompimento_possivel"])
        self.assertNotIn("violacao_comprovada_pelo_agente", self.a(-0.5))

    def test_deterioracao(self):
        self.assertIn("deterioracao", self.a(0.15, ant=0.36))
        self.assertNotIn("deterioracao", self.a(0.30, ant=0.40))

    def test_margem_vazia_nao_alerta(self):
        self.assertEqual(self.a(None), [])

    def test_dois_trimestres_antes(self):
        self.assertEqual(P.dois_trimestres_antes("2026-06-30"), "2025-12-31")
        self.assertEqual(P.dois_trimestres_antes("2026-03-31"), "2025-09-30")


PASTA = P.PASTA


@unittest.skipUnless(os.path.exists(os.path.join(PASTA, "historico.json")), "rodar piloto_covenant.py antes")
class TesteSaidaReal(unittest.TestCase):
    """Regressao e integridade sobre a ultima execucao real do piloto."""

    @classmethod
    def setUpClass(cls):
        cls.hist = json.load(open(os.path.join(PASTA, "historico.json"), encoding="utf-8"))
        cls.alertas = [json.loads(l) for l in open(os.path.join(PASTA, "alertas.jsonl"), encoding="utf-8")]
        cls.covs = {c["emissor"]: c for c in json.load(open(os.path.join(PASTA, "covenants.json"), encoding="utf-8"))["covenants"]}

    def test_regressao_dasa_engie_simpar(self):
        esperado = {("Dasa", "2026-06-30"): 3.39, ("Engie Brasil Energia", "2026-06-30"): 3.83, ("Simpar", "2026-06-30"): 2.0}
        for (e, ref), v in esperado.items():
            h = [x for x in self.hist if x["emissor"] == e and x["ref"] == ref]
            self.assertEqual(h[-1]["valor_estimado"], v)
            self.assertEqual(h[-1]["classe"], "REPRODUZIVEL")

    def test_nenhum_alerta_antes_do_dado(self):
        for a in self.alertas:
            fonte = a["fontes"].get("itr_dfp") or {}
            if fonte:
                self.assertGreater(a["as_of"], fonte["dt_receb"])
            else:
                self.assertGreater(a["as_of"], a["fontes"]["relatorio_af"]["data_entrega"])

    def test_nao_calculavel_nunca_alerta_nem_publica_valor(self):
        for h in self.hist:
            if h["classe"] == "NAO_CALCULAVEL":
                self.assertIsNone(h["valor_estimado"])
                self.assertIsNone(h["margem"])
        bloqueados = {c for c, v in self.covs.items() if v["status"] != "ATIVO"}
        for a in self.alertas:
            if a["tipo"] != "violacao_comprovada_pelo_agente":
                self.assertNotIn(a["emissor"], bloqueados)
                self.assertIn(a["classe"], ("REPRODUZIVEL", "PARCIAL"))

    def test_toda_linha_publicada_e_rotulada_como_estimativa(self):
        for h in self.hist:
            if h["valor_estimado"] is not None:
                self.assertIn("ESTIMATIVA", h["natureza"])


if __name__ == "__main__":
    unittest.main()
