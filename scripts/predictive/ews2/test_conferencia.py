"""Testes da conferencia automatica (EWS2CONF1). Prova de duas pontas: o caso ruim desliga, o bom e o inconclusivo mantem."""
import json
import os
import sys
import tempfile
import unittest
from datetime import date

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import conferencia as C  # noqa: E402

CRIT = {"versao": "t", "min_eventos": 5, "p_max": 0.10}
EMISSORES = ["c%02d" % i for i in range(20)]


def snap(data_obs, sev_por_cnpj, score_por_cnpj):
    return {"data_obs": data_obs, "ews2": {c: sev_por_cnpj.get(c, "baixa") for c in EMISSORES},
            "atual": {c: score_por_cnpj.get(c, 0) for c in EMISSORES}}


def eventos(*pares):
    return [{"cnpj": c, "data": d} for c, d in pares]


class Percentil(unittest.TestCase):
    def test_empate_pelo_ponto_medio(self):
        self.assertAlmostEqual(C.percentil(0, [0, 0, 0, 0]), 0.5)
        self.assertAlmostEqual(C.percentil(2, [0, 0, 1, 2]), (3 + 0.5) / 4)
        self.assertAlmostEqual(C.percentil(0, [0, 1, 2, 2]), 0.5 / 4)

    def test_sinal_exato(self):
        self.assertAlmostEqual(C.p_sinal_unilateral(5, 5), 1 / 32)
        self.assertAlmostEqual(C.p_sinal_unilateral(4, 5), 6 / 32)
        self.assertEqual(C.p_sinal_unilateral(0, 0), 1.0)


class Decisao(unittest.TestCase):
    def cenario(self, ews2_acerta, atual_acerta, n=6):
        """n emissores com evento; cada sistema 'acerta' (poe o emissor no topo) ou 'erra' (no fundo)."""
        evs = [("c%02d" % i, "2026-11-%02d" % (10 + i)) for i in range(n)]
        sev = {c: "alta" for (c, _), a in zip(evs, ews2_acerta) if a}
        sc = {c: 90 for (c, _), a in zip(evs, atual_acerta) if a}
        # fundo do ranking: emissores sem evento recebem escore alto no sistema que erra
        for (c, _), a in zip(evs, ews2_acerta):
            if not a:
                for o in EMISSORES[10:]:
                    sev[o] = "alta"
        for (c, _), a in zip(evs, atual_acerta):
            if not a:
                for o in EMISSORES[10:]:
                    sc[o] = 90
        return [snap("2026-10-16", sev, sc)], eventos(*evs)

    def test_desliga_quando_atual_ganha_em_todos(self):
        s, e = self.cenario([False] * 6, [True] * 6)
        r = C.decidir(s, e, CRIT, date(2027, 2, 1))
        self.assertEqual(r["eventos_independentes"], 6)
        self.assertEqual(r["decisao"], "desligar")
        self.assertLessEqual(r["p_sinal"], 0.10)
        self.assertGreater(r["pct_medio_atual"], r["pct_medio_ews2"])

    def test_mantem_quando_ews2_ganha(self):
        s, e = self.cenario([True] * 6, [False] * 6)
        self.assertEqual(C.decidir(s, e, CRIT, date(2027, 2, 1))["decisao"], "manter")

    def test_mantem_quando_empata(self):
        s, e = self.cenario([True] * 6, [True] * 6)
        r = C.decidir(s, e, CRIT, date(2027, 2, 1))
        self.assertEqual(r["decisao"], "manter")
        self.assertEqual(r["eventos_com_diferenca"], 0)

    def test_amostra_insuficiente_nunca_desliga(self):
        s, e = self.cenario([False] * 4, [True] * 4, n=4)
        r = C.decidir(s, e, CRIT, date(2027, 2, 1))
        self.assertEqual(r["decisao"], "amostra_insuficiente")
        self.assertEqual(r["eventos_independentes"], 4)

    def test_evidencia_fraca_nao_desliga(self):
        # 4 de 6 a favor do atual: p = 22/64 = 0,34, acima do limite
        s, e = self.cenario([False, False, False, False, True, True], [True, True, True, True, False, False])
        r = C.decidir(s, e, CRIT, date(2027, 2, 1))
        self.assertEqual(r["eventos_atual_melhor"], 4)
        self.assertEqual(r["decisao"], "manter")

    def test_sem_eventos(self):
        r = C.decidir([snap("2026-10-16", {}, {})], [], CRIT, date(2026, 11, 1))
        self.assertEqual(r["decisao"], "amostra_insuficiente")
        self.assertIsNone(r["pct_medio_ews2"])


class Selecao(unittest.TestCase):
    def test_evento_anterior_ao_primeiro_pacote_nao_conta(self):
        s = [snap("2026-10-16", {}, {})]
        r = C.decidir(s, eventos(("c00", "2026-09-01"), ("c01", "2026-10-16"), ("c02", "2026-10-20")), CRIT, date(2026, 12, 1))
        self.assertEqual(r["eventos_independentes"], 1)

    def test_episodio_de_30_dias_vale_um_evento(self):
        s = [snap("2026-10-16", {}, {})]
        r = C.decidir(s, eventos(("c00", "2026-11-01"), ("c00", "2026-11-20")), CRIT, date(2026, 12, 1))
        self.assertEqual(r["eventos_independentes"], 1)

    def test_prevalente_e_excluido(self):
        s = [snap("2026-10-16", {}, {})]
        r = C.decidir(s, eventos(("c00", "2026-06-01"), ("c00", "2026-11-15")), CRIT, date(2026, 12, 1))
        self.assertEqual(r["eventos_independentes"], 0)
        self.assertEqual(r["excluidos"][0]["motivo"], "prevalente")

    def test_emissor_ja_em_rj_re_por_categoria_a_e_excluido(self):
        s = [snap("2026-10-16", {}, {})]
        ev = [{"cnpj": "c00", "data": "2026-11-15", "prev_cat_a": True}, {"cnpj": "c01", "data": "2026-11-15", "prev_cat_a": False}]
        r = C.decidir(s, ev, CRIT, date(2026, 12, 1))
        self.assertEqual(r["eventos_independentes"], 1)
        self.assertEqual(r["excluidos"][0]["motivo"], "prevalente_categoria_a")

    def test_flag_de_categoria_a_vale_so_para_o_dia_que_abre_o_episodio(self):
        eps = C.episodios_de_eventos([{"cnpj": "c00", "data": "2026-11-01", "prev_cat_a": False},
                                      {"cnpj": "c00", "data": "2026-11-20", "prev_cat_a": True}])
        self.assertEqual(len(eps), 1)
        self.assertFalse(eps[0]["prev_cat_a"])

    def test_evento_alem_de_180_dias_do_pacote_nao_conta(self):
        s = [snap("2026-10-16", {}, {})]
        r = C.decidir(s, eventos(("c00", "2027-05-01")), CRIT, date(2027, 6, 1))
        self.assertEqual(r["eventos_independentes"], 0)
        self.assertEqual(r["excluidos"][0]["motivo"], "sem_pacote_no_horizonte")

    def test_usa_o_ultimo_pacote_antes_do_evento(self):
        a = snap("2026-10-16", {"c00": "baixa"}, {"c00": 0})
        b = snap("2026-11-20", {"c00": "alta"}, {"c00": 0})
        r = C.decidir([a, b], eventos(("c00", "2026-12-05")), CRIT, date(2027, 1, 1))
        self.assertEqual(r["eventos"][0]["pacote"], "2026-11-20")
        self.assertEqual(r["eventos"][0]["sev_ews2"], "alta")


class Livro(unittest.TestCase):
    def pacote(self, d, data="2026-10-16", sev="alta"):
        p = {"data_observacao": data, "gerado_em": "2026-10-18T07:52:02+00:00", "sinais_aprovados": ["H1"],
             "emissores": [{"cnpj": "11", "nome": "Alfa", "severidade": sev}, {"cnpj": "22", "nome": "Beta", "severidade": "baixa"}]}
        f = os.path.join(d, "pacote.json")
        json.dump(p, open(f, "w", encoding="utf-8"))
        return f

    def historico(self, d, dia="2026-10-16"):
        os.makedirs(os.path.join(d, "hist", dia))
        j = {"emissores": [{"name": "Alfa", "features": {"ews_score": 61}}, {"name": "Beta", "predictive_v1": {"ews_score": 5}}]}
        json.dump(j, open(os.path.join(d, "hist", dia, "predictive.json"), "w", encoding="utf-8"))
        return os.path.join(d, "hist")

    def test_registra_congela_e_e_idempotente(self):
        with tempfile.TemporaryDirectory() as d:
            h = self.historico(d)
            livro = os.path.join(d, "livro")
            r1 = C.registrar(self.pacote(d), livro, h)
            self.assertTrue(r1["novo"])
            reg = json.load(open(r1["arquivo"], encoding="utf-8"))
            self.assertEqual(reg["ews2"], {"11": "alta", "22": "baixa"})
            self.assertEqual(reg["atual"], {"11": 61, "22": 5})
            self.assertEqual(reg["ews_atual_dia"], "2026-10-16")
            mtime = os.path.getmtime(r1["arquivo"])
            r2 = C.registrar(self.pacote(d), livro, h)
            self.assertFalse(r2["novo"])
            self.assertEqual(os.path.getmtime(r1["arquivo"]), mtime)   # nao reescreveu
            self.assertEqual(len(C.ler_livro(livro)), 1)
            # pacote diferente na mesma data vira outro registro, o primeiro permanece
            C.registrar(self.pacote(d, sev="media"), livro, h)
            self.assertEqual(len(C.ler_livro(livro)), 2)

    def test_dia_sem_export_recua_e_sem_nenhum_marca_ausente(self):
        with tempfile.TemporaryDirectory() as d:
            h = self.historico(d, "2026-10-14")
            reg = json.load(open(C.registrar(self.pacote(d), os.path.join(d, "l1"), h)["arquivo"], encoding="utf-8"))
            self.assertEqual(reg["ews_atual_dia"], "2026-10-14")
            vazio = os.path.join(d, "vazio")
            os.makedirs(vazio)
            reg = json.load(open(C.registrar(self.pacote(d), os.path.join(d, "l2"), vazio)["arquivo"], encoding="utf-8"))
            self.assertIsNone(reg["ews_atual_dia"])
            self.assertEqual(reg["atual_ausentes"], ["11", "22"])


class Criterios(unittest.TestCase):
    def test_criterio_pre_registrado_confere(self):
        crit = C.ler_criterios()
        self.assertEqual((crit["min_eventos"], crit["p_max"]), (6, 0.05))

    def test_criterio_alterado_recusa(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "c.json")
            s = open(C.CRITERIOS, "rb").read().replace(b'"min_eventos": 6', b'"min_eventos": 1')
            open(f, "wb").write(s)
            with self.assertRaises(SystemExit):
                C.ler_criterios(f)

    def test_fim_de_linha_crlf_nao_quebra_o_hash(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "c.json")
            open(f, "wb").write(open(C.CRITERIOS, "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
            self.assertEqual(C.ler_criterios(f)["versao"], "conf-v1")


class Deteccao(unittest.TestCase):
    """Parte pura do detector: o que vira candidato e o que o classificador enxerga."""

    def doc(self, cat, assunto, dia, prot="1", cnpj="11"):
        return {"cnpj": cnpj, "cat_n": cat, "assunto_n": assunto, "data": dia, "protocolo": "X" + prot,
                "link": "https://rad/x?numProtocolo=%s&numSequencia=1" % prot}

    def test_candidato_so_de_comunicado_ao_mercado(self):
        import conferencia_eventos as CE
        d = date(2026, 11, 3)
        docs = [self.doc("assembleia", "vencimento antecipado das debentures", d, "1"),
                self.doc("escrituras e aditamentos de debentures", "evento de inadimplemento", d, "2", cnpj="22"),
                self.doc("fato relevante", "pedido de recuperacao judicial", d, "3", cnpj="33"),
                self.doc("fato relevante", "eleicao de diretor", d, "4", cnpj="44")]
        cand = CE.candidatos(docs, {"11", "22", "33", "44"}, date(2026, 11, 1), date(2026, 11, 30))
        self.assertEqual(sorted(c for c, _ in cand), ["33"])      # assembleia e escritura ficam de fora, assunto neutro tambem

    def test_candidato_respeita_a_janela_e_os_emissores(self):
        import conferencia_eventos as CE
        docs = [self.doc("fato relevante", "recuperacao judicial", date(2026, 10, 30), "5"),
                self.doc("fato relevante", "recuperacao judicial", date(2026, 11, 10), "6", cnpj="99")]
        self.assertEqual(CE.candidatos(docs, {"11"}, date(2026, 11, 1), date(2026, 11, 30)), {})

    def test_id_do_documento_e_o_numprotocolo_do_link(self):
        import conferencia_eventos as CE
        self.assertEqual(CE.pid(self.doc("fato relevante", "", date(2026, 11, 3), "1473614")), "1473614")
        self.assertEqual(CE.pid({"link": "", "protocolo": "027030IPE"}), "027030IPE")

    def test_classificador_nao_le_assembleia_do_dia(self):
        import conferencia_eventos as CE
        d = date(2026, 11, 3)
        lst = [self.doc("assembleia", "alteracao de eventos de inadimplemento", d, "1"),
               self.doc("fato relevante", "pedido de recuperacao judicial", d, "2"),
               self.doc("fato relevante", "comunicado antigo", date(2026, 8, 1), "3"),
               self.doc("assembleia", "outra", date(2026, 8, 2), "4")]
        item, man, meta, baixar = CE.montar("11", d, {"11": lst}, None)
        self.assertEqual(man["dia"], ["2"])
        self.assertEqual(man["contexto_180d"], ["3"])
        self.assertEqual(item["data"], "2026-11-03")


if __name__ == "__main__":
    unittest.main()
