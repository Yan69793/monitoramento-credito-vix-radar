"""Duas pontas do pipeline EWS 2.0 (sem dado real). Rodar:
python -I -m unittest discover -s scripts/predictive/ews2 -p "test_ews2*.py" -v
"""
import math
import os
import random
import sys
import tempfile
import unittest
from unittest.mock import patch
from datetime import date, timedelta

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import backtest as BT  # noqa: E402
import calendario as C  # noqa: E402
import dados as D  # noqa: E402
import eventos as EV  # noqa: E402
import features as F  # noqa: E402
import guarda_treino as GT  # noqa: E402
import metricas as M  # noqa: E402
import modelo as MO  # noqa: E402
import painel as P  # noqa: E402
import sintetico as S  # noqa: E402


class Calendario(unittest.TestCase):
    def test_ultimo_dia_util(self):
        self.assertEqual(C.ultimo_dia_util_do_mes(2026, 5), date(2026, 5, 29))  # 31/05/2026 e domingo
        self.assertEqual(C.ultimo_dia_util_do_mes(2024, 12), date(2024, 12, 31))
        self.assertEqual(C.ultimo_dia_util_do_mes(2023, 12), date(2023, 12, 29))  # 31/12/2023 domingo
        self.assertEqual(C.pascoa(2026), date(2026, 4, 5))

    def test_particao_e_embargo(self):
        self.assertEqual(C.particao(date(2019, 12, 31)), "treino")
        self.assertEqual(C.particao(date(2020, 1, 1)), "validacao")
        self.assertEqual(C.particao(date(2022, 2, 1)), "embargo")
        self.assertEqual(C.particao(date(2022, 4, 1)), "teste")
        self.assertTrue(C.horizonte_fechado(date(2019, 6, 28)))
        self.assertFalse(C.horizonte_fechado(date(2019, 9, 30)))   # cruza para a validacao
        self.assertFalse(C.horizonte_fechado(date(2026, 6, 30)))   # alem de 30/09/2026

    def test_datas_observacao_mensais(self):
        ds = C.datas_observacao(date(2011, 1, 1), date(2011, 12, 31))
        self.assertEqual(len(ds), 12)
        self.assertTrue(all(C.dia_util(d) for d in ds))


class Vigencia(unittest.TestCase):
    def test_vigente_usa_so_ate_T_menos_1_e_maior_versao(self):
        vs = [{"dt_refer": date(2019, 12, 31), "versao": 1, "dt_receb": date(2020, 3, 20)},
              {"dt_refer": date(2019, 12, 31), "versao": 2, "dt_receb": date(2020, 5, 10)},
              {"dt_refer": date(2020, 12, 31), "versao": 1, "dt_receb": date(2021, 3, 30)}]
        self.assertEqual(D.vigente(vs, date(2020, 3, 21))["versao"], 1)
        self.assertIsNone(D.vigente(vs, date(2020, 3, 20)))            # recebido em T nao vale (T-1)
        self.assertEqual(D.vigente(vs, date(2020, 6, 1))["versao"], 2)
        self.assertEqual(D.vigente(vs, date(2021, 4, 1))["dt_refer"], date(2020, 12, 31))


class Contas(unittest.TestCase):
    def test_codigo_so_vale_com_descricao(self):
        self.assertTrue(D.conta_valida("2.01.04", "Empréstimos e Financiamentos"))
        self.assertFalse(D.conta_valida("2.01.04", "Capitalização"))
        self.assertTrue(D.conta_valida("2.01", "Passivo Circulante"))
        self.assertFalse(D.conta_valida("2.01", "Passivos Financeiros ao Valor Justo através do Resultado"))
        self.assertTrue(D.conta_valida("6.01", "Caixa Líquido das Atividades Operacionais"))
        self.assertFalse(D.conta_valida("6.01", "Caixa Líquido Atividades Seguradora/Resseguradora"))
        self.assertFalse(D.conta_valida("9.99", "Ativo Total"))


class Features(unittest.TestCase):
    def doc(self, d, cat="comunicado ao mercado", assunto="x", tipo="", esp=""):
        return {"cnpj": "c", "nome_n": "n", "cat_n": cat, "tipo_n": tipo, "especie_n": esp, "assunto_n": assunto, "data": d, "protocolo": "", "link": ""}

    def test_h1_respeita_T_menos_1(self):
        t = date(2020, 6, 30)
        em_T = [self.doc(t, "assembleia", "agd", tipo="debenturistas")]
        em_T1 = [self.doc(t - timedelta(days=1), "assembleia", "agd", tipo="debenturistas")]
        antigo = [self.doc(t - timedelta(days=181), "assembleia", "agd", tipo="debenturistas")]
        for docs, esperado in ((em_T, 0), (em_T1, 1), (antigo, 0)):
            self.assertEqual(F.h1(docs, [d["data"] for d in docs], t), esperado)

    def test_h4_exige_as_duas_familias(self):
        t = date(2020, 6, 30)
        a = [self.doc(t - timedelta(days=10), assunto="renuncia de diretor financeiro")]
        b = [self.doc(t - timedelta(days=10), assunto="renuncia de conselheiro")]
        self.assertEqual(F.h4(a, [a[0]["data"]], t), 1)
        self.assertEqual(F.h4(b, [b[0]["data"]], t), 0)

    def test_h3_silencio_duas_pontas(self):
        t = date(2020, 6, 30)
        base = [self.doc(t - timedelta(days=100 + 7 * k)) for k in range(100)]  # ~100 docs em 2 anos => media 12,5/tri
        self.assertEqual(F.h3(base, [d["data"] for d in base], t), 1)       # 0 nos 90 dias
        cheio = base + [self.doc(t - timedelta(days=k)) for k in range(1, 40)]
        cheio.sort(key=lambda d: d["data"])
        self.assertEqual(F.h3(cheio, [d["data"] for d in cheio], t), 0)
        self.assertIsNone(F.h3(base[:5], [d["data"] for d in base[:5]], t))  # media < 3: sem sinal

    def test_h6_e_b1_b2(self):
        vs = [{"dt_refer": date(2019, 12, 31), "versao": 1, "dt_receb": date(2020, 3, 1), "parecer_enfase": False, "acoes": None,
               "contas": {"1": 1000.0, "1.01.01": 50.0, "1.01.02": 50.0, "2": 1000.0, "2.01": 300.0, "2.02": 200.0, "2.01.04": 150.0, "6.01": 50.0}}]
        razao, alerta = F.h6(vs, date(2020, 6, 30))
        self.assertAlmostEqual(razao, 1.0)
        self.assertEqual(alerta, 1)
        vs[0]["contas"]["2.01.04"] = 149.0
        self.assertEqual(F.h6(vs, date(2020, 6, 30))[1], 0)
        b1, b2 = F.b1_b2(vs, date(2020, 6, 30))
        self.assertEqual(b1, -1000.0)
        self.assertAlmostEqual(b2, 0.5)
        self.assertEqual(F.h6(vs, date(2020, 2, 1)), (None, None))  # antes de receber: sem demonstrativo

    def test_h2a_atraso(self):
        t = date(2021, 6, 30)
        ok = [{"dt_refer": date(2020, 12, 31), "versao": 1, "dt_receb": date(2021, 3, 31)}]
        atr = [{"dt_refer": date(2020, 12, 31), "versao": 1, "dt_receb": date(2021, 4, 1)}]
        self.assertEqual(F.h2a(ok, [], t), 0)
        self.assertEqual(F.h2a(atr, [], t), 1)
        self.assertEqual(F.h2b([{"dt_refer": date(2020, 12, 31), "versao": 2, "dt_receb": date(2021, 4, 1)}], [], t), 1)

    def test_h5_merton_ingenuo(self):
        t = date(2021, 6, 30)
        precos = [(t - timedelta(days=400) + timedelta(days=k), 10.0 * math.exp(0.001 * k + 0.02 * math.sin(k))) for k in range(400)]
        vs = [{"dt_refer": date(2020, 12, 31), "versao": 1, "dt_receb": date(2021, 3, 1), "parecer_enfase": False,
               "acoes": {"integralizadas": 1e6, "tesouraria": 0}, "contas": {"2.01": 2e6, "2.02": 2e6}}]
        dd, alerta = F.h5(precos, vs, {date(2021, 1, 1): 0.1}, t)
        self.assertIsNotNone(dd)
        self.assertIn(alerta, (0, 1))
        self.assertEqual(F.h5(precos[:50], vs, {date(2021, 1, 1): 0.1}, t), (None, None))  # < 120 pregoes

    def test_h5_serie_parada_nao_mede(self):
        """Duas pontas: a mesma serie e usada com T logo depois do ultimo pregao (mede) e 400 dias depois (None)."""
        fim = date(2023, 6, 30)
        precos = [(fim - timedelta(days=400) + timedelta(days=k), 10.0 * math.exp(0.001 * k + 0.02 * math.sin(k))) for k in range(400)]
        vs = [{"dt_refer": date(2022, 12, 31), "versao": 1, "dt_receb": date(2023, 3, 1), "parecer_enfase": False,
               "acoes": {"integralizadas": 1e6, "tesouraria": 0}, "contas": {"2.01": 2e6, "2.02": 2e6}}]
        sel = {date(2021, 1, 1): 0.1}
        dd, _ = F.h5(precos, vs, sel, fim + timedelta(days=5))
        self.assertIsNotNone(dd)
        self.assertEqual(F.h5(precos, vs, sel, fim + timedelta(days=400)), (None, None))

    def test_h5_escolhe_o_ticker_vigente_em_cada_T(self):
        """Duas series do mesmo emissor: a antiga (mais longa, parou) e a nova (curta, em dia). Antes da troca vale a antiga,
        depois da troca vale a nova; sem nenhuma em dia, None."""
        troca = date(2025, 11, 7)
        antiga = [(troca - timedelta(days=500) + timedelta(days=k), 10.0 * math.exp(0.001 * k + 0.02 * math.sin(k))) for k in range(500)]
        nova = [(troca + timedelta(days=1 + k), 12.0 * math.exp(0.0005 * k + 0.02 * math.cos(k))) for k in range(300)]
        vs = [{"dt_refer": date(2024, 12, 31), "versao": 1, "dt_receb": date(2025, 3, 1), "parecer_enfase": False,
               "acoes": {"integralizadas": 1e6, "tesouraria": 0}, "contas": {"2.01": 2e6, "2.02": 2e6}}]
        sel = {date(2021, 1, 1): 0.1}
        antes, depois = date(2025, 11, 10), date(2026, 8, 1)
        self.assertIsNotNone(F.h5([antiga, nova], vs, sel, antes)[0])           # ticker antigo em dia
        self.assertIsNone(F.h5([nova], vs, sel, antes)[0])                      # so a nova: ainda nao existia
        self.assertIsNotNone(F.h5([antiga, nova], vs, sel, depois)[0])          # a nova assume
        self.assertIsNone(F.h5([antiga], vs, sel, depois)[0])                   # so a antiga: parada, nao mede
        self.assertEqual(F.h5([antiga, nova], vs, sel, depois), F.h5(nova, vs, sel, depois))  # = usar a nova sozinha

    def test_h5_desdobramento_nao_gera_alerta(self):
        """Desdobramento 5:1 depois da referencia do BPP: DD igual ao da serie sem evento (duas pontas: sem ajuste, cai)."""
        t = date(2021, 6, 30)
        base = [(t - timedelta(days=400) + timedelta(days=k), 10.0 * math.exp(0.001 * k + 0.02 * math.sin(k))) for k in range(400)]
        corte = 300  # dia 300 cai depois de 31/12/2020
        split = [(d, p / 5 if k >= corte else p) for k, (d, p) in enumerate(base)]
        vs = [{"dt_refer": date(2020, 12, 31), "versao": 1, "dt_receb": date(2021, 3, 1), "parecer_enfase": False,
               "acoes": {"integralizadas": 1e6, "tesouraria": 0}, "contas": {"2.01": 2e6, "2.02": 2e6}}]
        sel = {date(2021, 1, 1): 0.1}
        dd_base, _ = F.h5(base, vs, sel, t)
        self.assertEqual(D.eventos_de_capital(split), [(corte, 0.2)])
        dd_aj, _ = F.h5(D.ajustar_capital(split), vs, sel, t)
        self.assertAlmostEqual(dd_aj, dd_base, places=6)
        dd_cru, _ = F.h5(split, vs, sel, t)
        self.assertLess(dd_cru, dd_base - 1)  # sem o ajuste o mesmo emissor parece muito mais arriscado

    def test_eventos_de_capital_ignora_queda_real_e_erro_de_cotacao(self):
        d0 = date(2023, 1, 2)
        serie = lambda ps: [(d0 + timedelta(days=k), p) for k, p in enumerate(ps)]  # noqa: E731
        self.assertEqual(D.eventos_de_capital(serie([10, 10, 2.26, 2.2, 2.1, 2.0, 2.0])), [])  # fator 4,42: queda real
        self.assertEqual(D.eventos_de_capital(serie([10, 10, 5, 10, 10, 10, 10])), [])  # voltou: erro de cotacao
        self.assertEqual(D.eventos_de_capital(serie([1, 1, 10, 10.1, 9.9, 10, 10])), [(2, 10.0)])  # grupamento 10:1


class Eventos(unittest.TestCase):
    def test_episodios_30_dias_e_dedup(self):
        rot = [{"id": "a", "cnpj": "c", "classe1": "evento_proprio", "data_evento1": "2020-01-10"},
               {"id": "b", "cnpj": "c", "classe1": "evento_proprio", "data_evento1": "2020-01-10"},
               {"id": "d", "cnpj": "c", "classe1": "continuacao", "origem_data_entrega": "2020-02-05"},
               {"id": "e", "cnpj": "c", "classe1": "evento_proprio", "data_evento1": "2020-06-01"},
               {"id": "f", "cnpj": "c", "classe1": "nao_evento"}]
        evs = EV.eventos_de_rotulos(rot)
        self.assertEqual(len(evs), 3)
        eps = EV.episodios(evs)
        self.assertEqual(len(eps), 2)
        self.assertEqual(len(eps[0]["eventos"]), 2)

    def test_prevalencia_24m(self):
        eps = EV.episodios(EV.eventos_de_rotulos([{"id": "a", "cnpj": "c", "classe1": "evento_proprio", "data_evento1": "2020-01-10"}]))
        docs = {"c": [{"data": date(2018, 6, 1), "cat_n": "informacoes de companhias em recuperacao judicial ou extrajudicial"}]}
        self.assertTrue(EV.marcar_prevalencia(eps, docs)[0]["prevalente"])
        docs = {"c": [{"data": date(2017, 6, 1), "cat_n": "informacoes de companhias em recuperacao judicial ou extrajudicial"}]}
        self.assertFalse(EV.marcar_prevalencia(eps, docs)[0]["prevalente"])

    def test_censura_item4(self):
        per = [{"dt_reg": date(2010, 1, 1), "dt_cancel": date(2018, 5, 5), "motivo_cancel": "Cancelamento Voluntário"}]
        self.assertEqual(len(EV.censuras(per, [])), 1)
        self.assertEqual(len(EV.censuras(per, [{"inicio": date(2018, 3, 1)}])), 0)  # evento 180d antes: conta como evento


class Painel(unittest.TestCase):
    def test_sai_do_risco_no_episodio_e_alvo_no_horizonte(self):
        cad = {"c": [{"dt_reg": date(2010, 1, 1), "dt_cancel": None, "motivo_cancel": "", "setor_ativ": "s"}]}
        eps = {"c": [{"cnpj": "c", "inicio": date(2015, 6, 15), "ultimo": date(2015, 6, 15), "fim": date(2016, 6, 14), "prevalente": False}]}
        datas = [date(2015, 1, 30), date(2015, 3, 31), date(2015, 8, 31), date(2016, 7, 29)]
        ls = P.linhas_painel(["c"], datas, eps, cad, {"c": date(2011, 3, 1)}, set(), set())
        por = {l["T"]: l for l in ls}
        self.assertEqual(por[date(2015, 1, 30)]["y180"], 1)
        self.assertEqual(por[date(2015, 3, 31)]["y180"], 1)
        self.assertNotIn(date(2015, 8, 31), por)   # dentro do episodio: fora do risco
        self.assertEqual(por[date(2016, 7, 29)]["y180"], 0)
        self.assertEqual(P.linhas_painel(["c"], datas, eps, cad, {"c": date(2015, 2, 1)}, set(), set())[0]["T"], date(2015, 3, 31))


class Modelo(unittest.TestCase):
    def test_logit_recupera_coeficientes(self):
        rng = random.Random(1)
        X, y = [], []
        for _ in range(4000):
            x = rng.gauss(0, 1)
            p = 1 / (1 + math.exp(-(-1.0 + 1.5 * x)))
            X.append([x])
            y.append(1 if rng.random() < p else 0)
        m = MO.ajustar_logit(X, y)
        self.assertTrue(m["convergiu"])
        self.assertAlmostEqual(m["beta"][0], -1.0, delta=0.15)
        self.assertAlmostEqual(m["beta"][1], 1.5, delta=0.15)

    def test_platt_e_inclinacao(self):
        p = [0.1, 0.2, 0.8, 0.9] * 50
        y = [0, 0, 1, 1] * 50
        a, b = MO.platt(p, y)
        self.assertGreater(b, 0)
        self.assertGreater(MO.inclinacao_calibracao(p, y), 0)


class Metricas(unittest.TestCase):
    def test_pr_auc_duas_pontas(self):
        y = [1, 0, 1, 0, 0, 0, 1, 0]
        self.assertAlmostEqual(M.pr_auc([1, 0, 1, 0, 0, 0, 1, 0], y), 1.0)
        self.assertLess(M.pr_auc([0, 1, 0, 1, 1, 1, 0, 1], y), 0.5)
        self.assertIsNone(M.pr_auc([1, 2], [0, 0]))

    def test_razao_de_risco_e_falsos(self):
        s = [1, 1, 1, 1, 0, 0, 0, 0]
        y = [1, 1, 0, 0, 1, 0, 0, 0]
        self.assertAlmostEqual(M.razao_de_risco(s, y), 2.0)
        self.assertAlmostEqual(M.falsos_alertas_por_100(s, y), 25.0)

    def test_holm(self):
        adj = M.holm({"a": 0.01, "b": 0.04, "c": 0.03, "d": None})
        self.assertAlmostEqual(adj["a"], 0.03)
        self.assertAlmostEqual(adj["c"], 0.06)
        self.assertAlmostEqual(adj["b"], 0.06)
        self.assertIsNone(adj["d"])

    def test_g2_duas_pontas(self):
        self.assertTrue(M.g2(1.6, 70, 0.3, 0.1, 0.01)[0])
        self.assertFalse(M.g2(1.4, 70, 0.3, 0.1, 0.01)[0])
        self.assertFalse(M.g2(1.6, 59, 0.3, 0.1, 0.01)[0])
        self.assertFalse(M.g2(1.6, 70, 0.1, 0.3, 0.01)[0])
        self.assertFalse(M.g2(1.6, 70, 0.3, 0.1, 0.05)[0])

    def test_bootstrap_cluster_deterministico(self):
        cl = {i: [i] for i in range(40)}
        v = [float(i) for i in range(40)]
        a = M.bootstrap_cluster(cl, lambda ii: sum(v[k] for k in ii) / len(ii), n_boot=200)
        b = M.bootstrap_cluster(cl, lambda ii: sum(v[k] for k in ii) / len(ii), n_boot=200)
        self.assertEqual(a, b)
        self.assertLess(a[0], 19.5)
        self.assertGreater(a[1], 19.5)

    def test_antecedencia(self):
        r = M.antecedencia([("c", date(2020, 6, 1))], {"c": [date(2019, 1, 1), date(2020, 1, 1), date(2020, 3, 1)]})
        self.assertEqual(r["mediana"], 152)


class Guarda(unittest.TestCase):
    def test_sha256_ignora_fim_de_linha(self):
        """CRLF do Windows e LF do git/Linux sao o mesmo conteudo (EWS2PUB1): o hash tem que ser um so."""
        with tempfile.TemporaryDirectory() as d:
            a, b = os.path.join(d, "lf.csv"), os.path.join(d, "crlf.csv")
            with open(a, "wb") as fh:
                fh.write(b"id;x\n1;a\n2;b\n")
            with open(b, "wb") as fh:
                fh.write(b"id;x\r\n1;a\r\n2;b\r\n")
            self.assertEqual(GT.sha256_arquivo(a), GT.sha256_arquivo(b))
            with open(b, "wb") as fh:                      # conteudo diferente continua diferente
                fh.write(b"id;x\r\n1;a\r\n2;c\r\n")
            self.assertNotEqual(GT.sha256_arquivo(a), GT.sha256_arquivo(b))

    def test_sem_registro_bloqueia(self):
        ok, mot = GT.avaliar(None, "x")
        self.assertFalse(ok)
        self.assertIn("ausente", mot[0])

    def test_registro_completo_libera_e_sha_errado_bloqueia(self):
        reg = {"g1a_passa": True, "g1b_passa": True, "g1c_passa": True, "sha256_rotulos": "a" * 64, "arquivo_rotulos": "x.csv",
               "autorizado_por_operador": True, "autorizado_em": "2026-10-20", "protocolo": "G0-v3"}
        self.assertTrue(GT.avaliar(reg, "a" * 64)[0])
        self.assertFalse(GT.avaliar(reg, "b" * 64)[0])
        reg2 = dict(reg, g1b_passa=False)
        self.assertFalse(GT.avaliar(reg2, "a" * 64)[0])
        reg3 = dict(reg, autorizado_por_operador=False)
        self.assertFalse(GT.avaliar(reg3, "a" * 64)[0])

    # Ate 18/10/2026 estes dois testes liam o estado real do disco. Desde a liberacao operacional (nota 126) o registro
    # real libera por override; o bloqueio passa a ser provado com registro ausente, independente do disco.
    def test_registro_ausente_bloqueia(self):
        self.assertFalse(GT.estado(registro_path=os.path.join(os.path.dirname(GT.REGISTRO), "nao_existe_registro.json"))["ok"])

    def test_backtest_real_sem_homologacao_sai_sem_ler(self):
        orig = GT.estado
        GT.estado = lambda *a, **k: {"ok": False, "motivos": ["registro de homologacao da base ausente"]}
        try:
            with self.assertRaises(SystemExit):
                BT.main(["--real", "--rotulos", "inexistente.csv"])
        finally:
            GT.estado = orig

    def test_override_exige_nota_por_hash(self):
        reg = {"g1a_passa": False, "g1b_passa": False, "g1c_passa": False, "sha256_rotulos": "a" * 64, "arquivo_rotulos": "x.csv",
               "autorizado_por_operador": True, "autorizado_em": "2026-10-18", "protocolo": "G0-v4",
               "override_operador": True, "override_motivo": "nota 126", "override_nota_sha256": "n" * 64}
        self.assertTrue(GT.avaliar(reg, "a" * 64, "n" * 64)[0])
        self.assertFalse(GT.avaliar(reg, "a" * 64, "m" * 64)[0])          # nota alterada
        self.assertFalse(GT.avaliar(reg, "a" * 64, None)[0])              # nota ausente
        self.assertFalse(GT.avaliar(dict(reg, override_motivo=""), "a" * 64, "n" * 64)[0])
        self.assertFalse(GT.avaliar(dict(reg, override_operador=False), "a" * 64, "n" * 64)[0])
        self.assertFalse(GT.avaliar(reg, "b" * 64, "n" * 64)[0])          # rotulos alterados


class SelecaoSemVazamento(unittest.TestCase):
    def test_melhor_sinal_escolhido_na_validacao_mesmo_se_pior_no_teste(self):
        linhas, idx = [], {"treino": [], "validacao": [], "teste": []}
        for parte, n in (("treino", 40), ("validacao", 20), ("teste", 20)):
            for j in range(n):
                y = j % 2
                h1 = 1 - y if parte == "teste" else y
                h4 = 1 - y if parte == "validacao" else y
                idx[parte].append(len(linhas))
                linhas.append({"cnpj": "c%02d" % j, "T": date(2023, 1 + j % 12, 28), "y180": y, "B2": 0.5, "H1": h1, "H4": h4})
        def prever(_modelo, xx):
            return [0.9 if row[0] >= 0.5 else 0.1 for row in xx]
        with patch.object(MO, "ajustar_logit", return_value={"beta": [0, 1]}), \
             patch.object(MO, "prever_logit", side_effect=prever), \
             patch.object(MO, "platt", return_value=(0, 1)), \
             patch.object(MO, "aplicar_platt", side_effect=lambda _, ps: ps), \
             patch.object(M, "bootstrap_cluster", return_value=(0.5, 1.5, 100)):
            resultado = BT.ajustar_g3(linhas, idx, ["H1", "H4"])
        self.assertEqual(resultado["melhor_sinal_unico"]["sinal"], "H1")
        self.assertAlmostEqual(resultado["melhor_sinal_unico"]["brier_validacao"], 0.01)
        self.assertAlmostEqual(resultado["melhor_sinal_unico"]["brier"], 0.81)


class G3Precisao(unittest.TestCase):
    """G3-PRECISAO1 e G3-BLOCOS1: o gate so passa com IC estreito, e o IC do gate e o mais largo dos dois bootstraps."""

    def test_ic_estreito_contendo_1_passa(self):
        self.assertTrue(M.g3(0.1, 0.05, (0.92, 1.08))[0])

    def test_ic_largo_contendo_1_reprova_como_nao_informativo(self):
        # caso ruim: na regra antiga passava, porque (0.4, 1.6) contem 1 e o skill e positivo
        passa, motivos = M.g3(0.1, 0.05, (0.4, 1.6))
        self.assertFalse(passa)
        self.assertEqual(len(motivos), 1)
        self.assertIn("nao informativo", motivos[0])

    def test_limite_exato_da_largura(self):
        self.assertTrue(M.g3(0.1, 0.05, (0.9, 1.1))[0])
        self.assertFalse(M.g3(0.1, 0.05, (0.9, 1.11))[0])

    def test_ic_indefinido_reprova(self):
        self.assertFalse(M.g3(0.1, 0.05, (None, None))[0])

    def test_conservador_escolhe_o_mais_largo_e_indefinido_vence(self):
        self.assertEqual(M.ic_mais_conservador((0.95, 1.05), (0.8, 1.3)), (0.8, 1.3))
        self.assertEqual(M.ic_mais_conservador((0.8, 1.3), (0.95, 1.05)), (0.8, 1.3))
        self.assertEqual(M.ic_mais_conservador((0.95, 1.05), (None, None)), (None, None))

    def test_blocos_de_6_meses(self):
        linhas = [{"T": date(2023, m, 28)} for m in range(1, 13)] + [{"T": date(2024, 1, 31)}]
        bl = BT._blocos_de_meses(linhas, list(range(len(linhas))))
        self.assertEqual(sorted(len(v) for v in bl.values()), [1, 6, 6])

    def _ajustar(self, ic_cnpj, ic_blocos):
        linhas, idx = [], {"treino": [], "validacao": [], "teste": []}
        for parte, n in (("treino", 40), ("validacao", 20), ("teste", 24)):
            for j in range(n):
                idx[parte].append(len(linhas))
                linhas.append({"cnpj": "c%02d" % j, "T": date(2023 + j // 12, 1 + j % 12, 28), "y180": j % 2, "B2": 0.5, "H1": j % 2})
        with patch.object(MO, "ajustar_logit", return_value={"beta": [0, 1]}), \
             patch.object(MO, "prever_logit", side_effect=lambda _m, xx: [0.9 if r[0] >= 0.5 else 0.1 for r in xx]), \
             patch.object(MO, "platt", return_value=(0, 1)), \
             patch.object(MO, "aplicar_platt", side_effect=lambda _, ps: ps), \
             patch.object(M, "brier_skill", return_value=0.3), \
             patch.object(M, "bootstrap_cluster", side_effect=[ic_cnpj + (100,), ic_blocos + (100,)]):
            return BT.ajustar_g3(linhas, idx, ["H1"])

    def test_gate_usa_blocos_quando_mais_largos(self):
        r = self._ajustar((0.95, 1.05), (0.6, 1.4))
        self.assertEqual(r["inclinacao_ic95_gate"], [0.6, 1.4])
        self.assertFalse(r["passa"])
        self.assertEqual(r["n_blocos"], 4)
        self.assertFalse(r["libera_probabilidade"])

    def test_gate_passa_quando_os_dois_estreitos(self):
        r = self._ajustar((0.95, 1.05), (0.93, 1.06))
        self.assertTrue(r["passa"])
        self.assertEqual(r["inclinacao_ic95_gate"], [0.93, 1.06])
        # mesmo aprovado, G3 e condicional e nao libera probabilidade
        self.assertTrue(r["condicional_a_selecao"])
        self.assertFalse(r["libera_probabilidade"])


class PipelineSintetico(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # mesma configuracao da prova de pipeline registrada (semente 7, 120 empresas): determinista, ~80 s
        d = S.gerar(semente=7, n_empresas=120)
        cls.r = BT.rodar(d, d["rotulos"], origem="sintetico")

    def test_sinal_plantado_passa_e_sinal_nulo_nao(self):
        self.assertIn("H1", self.r["aprovados_g2"])
        self.assertFalse(self.r["hipoteses"]["H4"]["g2"]["passa"])
        self.assertFalse(self.r["evidencia_de_eficacia"])

    def test_g3_nunca_libera_probabilidade(self):
        self.assertFalse(self.r["exibir_probabilidade"])
        self.assertFalse(self.r["g3"]["libera_probabilidade"])
        self.assertTrue(self.r["g3"]["condicional_a_selecao"])

    def test_embargo_nunca_entra_e_formulacao_fora(self):
        self.assertEqual(self.r["painel"]["por_particao"]["embargo"]["n"], 0)
        self.assertNotIn("embargo", self.r["linhas_por_particao"])

    def test_vazamento_temporal_horizonte_fechado(self):
        # nenhuma linha usavel de treino tem T + 180 cruzando 01/01/2020
        d = S.gerar(semente=3, n_empresas=20)
        m = BT.montar(d, d["rotulos"])
        for l in m["linhas"]:
            if l["usavel_180"] and l["particao"] == "treino":
                self.assertLess(l["T"] + timedelta(days=180), C.TREINO_FIM)


if __name__ == "__main__":
    unittest.main()
