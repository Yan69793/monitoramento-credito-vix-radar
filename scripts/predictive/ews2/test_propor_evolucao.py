"""Testes do EVOLUCAO2B. Duas pontas: erro real com fonte vira proposta; acerto, erro sem fonte e amostra pequena nao viram."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import conferencia as C  # noqa: E402
import propor_evolucao as P  # noqa: E402

L = "https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=%d"


def linha(cnpj, sev, p2, pa, link=1):
    return {"cnpj": cnpj, "inicio": "2026-11-10", "pacote": "2026-11-02", "sev_ews2": sev, "score_atual": 40,
            "pct_ews2": p2, "pct_atual": pa, "links": [L % link] if link else []}


class Omissao(unittest.TestCase):
    def test_evento_com_ews2_baixa_vira_proposta_com_nome_e_fonte(self):
        p = P.derivar({"eventos": [linha("11.111.111/0001-11", "baixa", 0.3, 0.9)]}, {"11.111.111/0001-11": "Emissor X"})
        self.assertEqual(len(p), 1)
        self.assertEqual(p[0]["tipo"], "ews")
        self.assertIn("Emissor X", p[0]["titulo"])
        self.assertEqual(p[0]["fontes"], [L % 1])

    def test_acerto_do_ews2_nao_vira_proposta(self):
        self.assertEqual(P.derivar({"eventos": [linha("a", "alta", 0.95, 0.4), linha("b", "media", 0.7, 0.5, 2)]}), [])

    def test_sem_link_https_nao_vira_proposta(self):
        sem = linha("a", "baixa", 0.3, 0.9, link=0)
        http = dict(linha("b", "baixa", 0.3, 0.9), links=["http://inseguro/x"])
        self.assertEqual(P.derivar({"eventos": [sem, http]}), [])

    def test_titulo_estavel_entre_rodadas(self):
        a = P.derivar({"eventos": [linha("a", "baixa", 0.3, 0.9)]})[0]["titulo"]
        b = P.derivar({"eventos": [dict(linha("a", "baixa", 0.2, 0.8), inicio="2026-12-01")]})[0]["titulo"]
        self.assertEqual(a, b)


class Ranking(unittest.TestCase):
    def test_atual_melhor_em_3_de_3_propoe(self):
        rel = {"eventos": [linha("a", "media", 0.5, 0.9, 1), linha("b", "media", 0.5, 0.8, 2), linha("c", "alta", 0.6, 0.7, 3)], "decisao": "amostra_insuficiente"}
        tipos = [x["alvo"] for x in P.derivar(rel)]
        self.assertEqual(tipos, ["ews2:ranking"])

    def test_dois_eventos_nao_bastam_e_maioria_do_ews2_nao_propoe(self):
        self.assertEqual(P.derivar({"eventos": [linha("a", "media", 0.5, 0.9), linha("b", "media", 0.5, 0.8, 2)]}), [])
        rel = {"eventos": [linha("a", "alta", 0.9, 0.5), linha("b", "alta", 0.9, 0.4, 2), linha("c", "media", 0.5, 0.8, 3)]}
        self.assertEqual(P.derivar(rel), [])


class Integracao(unittest.TestCase):
    def test_links_atravessam_decidir(self):
        crit = {"versao": "t", "min_eventos": 5, "p_max": 0.1}
        snaps = [{"data_obs": "2026-11-01", "ews2": {"a": "baixa", "b": "alta"}, "atual": {"a": 80, "b": 10}}]
        r = C.decidir(snaps, [{"cnpj": "a", "data": "2026-11-10", "links": [L % 7]}], crit, "2026-11-20")
        self.assertEqual(r["eventos"][0]["links"], [L % 7])
        self.assertEqual(P.derivar(r)[0]["fontes"], [L % 7])

    def test_relatorio_vazio_de_hoje_nao_propoe(self):
        self.assertEqual(P.derivar({"decisao": "amostra_insuficiente", "eventos": []}), [])

    def test_cli_imprime_json(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "r.json")
            with open(f, "w", encoding="utf-8") as fh:
                json.dump({"eventos": [linha("a", "baixa", 0.3, 0.9)]}, fh)
            out = subprocess.run([sys.executable, "-I", os.path.join(AQUI, "propor_evolucao.py"), "--relatorio", f, "--mapa", os.path.join(d, "x.json")],
                                 capture_output=True, text=True, check=True).stdout
            self.assertEqual(len(json.loads(out)["propostas"]), 1)


if __name__ == "__main__":
    unittest.main()
