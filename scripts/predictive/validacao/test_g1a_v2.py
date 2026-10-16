"""Testes do G1a (g1a_v2.py), duas pontas em cada regra. Dados sinteticos, nenhum rotulo real.
Rodar: python -I -m unittest discover -s scripts/predictive/validacao -p "test_g1a*.py" -v
"""
import os
import random
import sys
import unittest
from datetime import date, timedelta

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g1a_v2 as A  # noqa: E402

EP, CT, ET, NE, INC = A.EP, A.CT, A.ET, A.ET and A.NE, A.INC
ET = A.ET


def itens_sinteticos(n_uniao=200, n_G=300, semente=1):
    """Primeiro rotulo sintetico: uniao com as 5 classes, G quase todo NE com alguns EP/INC."""
    rng = random.Random(semente)
    base = date(2020, 1, 1)
    out = []
    for i in range(n_uniao):
        c = rng.choices([EP, CT, ET, NE, INC], weights=[40, 20, 20, 18, 2])[0]
        d = base + timedelta(days=rng.randint(0, 2000))
        out.append({"id": "u%03d" % i, "cnpj": "%02d" % rng.randint(0, 60), "data": d, "origem": "uniao",
                    "classe1": c, "data_evento1": d - timedelta(days=rng.randint(0, 5)) if c == EP else None})
    for i in range(n_G):
        c = rng.choices([NE, CT, ET, EP, INC], weights=[85, 5, 5, 4, 1])[0]
        d = base + timedelta(days=rng.randint(0, 2000))
        out.append({"id": "g%03d" % i, "cnpj": "%02d" % rng.randint(0, 60), "data": d, "origem": "G",
                    "classe1": c, "data_evento1": d if c == EP else None})
    return out


def segunda_igual(itens, ids):
    por = {it["id"]: it for it in itens}
    return [{"id": i, "classe2": por[i]["classe1"], "data_evento2": por[i]["data_evento1"]} for i in ids]


class Amostra(unittest.TestCase):
    def test_sessenta_com_cotas_quando_ha_itens(self):
        it = itens_sinteticos()
        ids, det = A.amostra_g1a(it)
        self.assertEqual(len(ids), 60)
        self.assertEqual(len(set(ids)), 60)
        self.assertEqual(det["uniao"], {EP: 16, CT: 8, ET: 8, NE: 8, "nao_preenchido": 0})
        self.assertEqual(det["G"]["ep_ou_incerto"] + det["G"]["outros"], 20)

    def test_determinista_na_semente(self):
        it = itens_sinteticos()
        self.assertEqual(A.amostra_g1a(it, 0)[0], A.amostra_g1a(it, 0)[0])
        self.assertNotEqual(A.amostra_g1a(it, 0)[0], A.amostra_g1a(it, 1)[0])

    def test_ordem_de_entrada_nao_muda_o_sorteio(self):
        it = itens_sinteticos()
        emb = list(it)
        random.Random(9).shuffle(emb)
        self.assertEqual(A.amostra_g1a(it)[0], A.amostra_g1a(emb)[0])

    def test_classe_curta_entra_inteira_e_sobra_vai_para_ep(self):
        it = itens_sinteticos()
        it = [x for x in it if not (x["origem"] == "uniao" and x["classe1"] == CT)][:0] + \
             [x for x in it if not (x["origem"] == "uniao" and x["classe1"] == CT)]
        ct = [x for x in itens_sinteticos() if x["origem"] == "uniao" and x["classe1"] == CT][:3]
        it += ct
        ids, det = A.amostra_g1a(it)
        self.assertEqual(det["uniao"][CT], 3)
        self.assertEqual(det["uniao"][EP], 16 + 5)
        self.assertEqual(len(ids), 60)

    def test_sem_g_suficiente_marca_nao_preenchido(self):
        it = [x for x in itens_sinteticos() if x["origem"] == "uniao"] + \
             [x for x in itens_sinteticos() if x["origem"] == "G"][:7]
        ids, det = A.amostra_g1a(it)
        self.assertEqual(det["G"]["nao_preenchido"], 13)
        self.assertEqual(len(ids), 47)

    def test_g_ep_ou_incerto_limitado_a_dez(self):
        it = itens_sinteticos()
        for x in it:
            if x["origem"] == "G":
                x["classe1"] = EP
        _, det = A.amostra_g1a(it)
        self.assertEqual(det["G"]["ep_ou_incerto"], 10)
        self.assertEqual(det["G"]["outros"], 0)


class Kappa(unittest.TestCase):
    def test_concordancia_total_da_um(self):
        pares = [("a", EP, EP), ("b", NE, NE), ("c", CT, CT), ("d", EP, EP)]
        self.assertAlmostEqual(A.kappa_ponderado(pares, {i: 1.0 for i, _, _ in pares}), 1.0)

    def test_discordancia_sistematica_da_negativo(self):
        pares = [("a", EP, NE), ("b", NE, EP), ("c", EP, NE), ("d", NE, EP)]
        self.assertLess(A.kappa_ponderado(pares, {i: 1.0 for i, _, _ in pares}), 0)

    def test_binario_ignora_troca_entre_classes_do_resto(self):
        pares = [("a", CT, ET), ("b", NE, CT), ("c", EP, EP), ("d", INC, NE), ("e", EP, EP), ("f", NE, NE)]
        w = {i: 1.0 for i, _, _ in pares}
        self.assertAlmostEqual(A.kappa_ponderado(pares, w, binario=True), 1.0)
        self.assertLess(A.kappa_ponderado(pares, w, binario=False), 1.0)

    def test_incerto_conta_como_resto(self):
        pares = [("a", INC, NE), ("b", EP, EP), ("c", NE, NE)]
        self.assertAlmostEqual(A.kappa_ponderado(pares, {i: 1.0 for i, _, _ in pares}), 1.0)

    def test_peso_muda_o_kappa(self):
        pares = [("a", EP, EP), ("b", EP, NE), ("c", NE, NE), ("d", NE, NE)]
        k1 = A.kappa_ponderado(pares, {"a": 1, "b": 1, "c": 1, "d": 1})
        k2 = A.kappa_ponderado(pares, {"a": 1, "b": 10, "c": 1, "d": 1})
        self.assertGreater(k1, k2)

    def test_pesos_estrato_sao_N_sobre_n(self):
        it = itens_sinteticos()
        ids, _ = A.amostra_g1a(it)
        w = A.pesos_estrato(it, ids)
        por = {x["id"]: x for x in it}
        N_ep = sum(1 for x in it if x["origem"] == "uniao" and x["classe1"] == EP)
        n_ep = sum(1 for i in ids if por[i]["origem"] == "uniao" and por[i]["classe1"] == EP)
        i_ep = next(i for i in ids if por[i]["origem"] == "uniao" and por[i]["classe1"] == EP)
        self.assertAlmostEqual(w[i_ep], N_ep / n_ep)
        self.assertEqual(len(w), len(ids))


class Bootstrap(unittest.TestCase):
    def test_determinista_e_contem_o_pontual(self):
        it = itens_sinteticos()
        ids, _ = A.amostra_g1a(it)
        por = {x["id"]: x for x in it}
        rng = random.Random(3)
        pares = [(i, por[i]["classe1"], por[i]["classe1"] if rng.random() < 0.85 else NE) for i in ids]
        w = A.pesos_estrato(it, ids)
        est = {i: (por[i]["origem"], por[i]["classe1"]) for i in ids}
        k = A.kappa_ponderado(pares, w)
        a = A.ic_bootstrap(pares, w, est, 0, 300)
        b = A.ic_bootstrap(pares, w, est, 0, 300)
        self.assertEqual(a, b)
        self.assertLessEqual(a[0], k)
        self.assertGreaterEqual(a[1], k)
        self.assertNotEqual(a, A.ic_bootstrap(pares, w, est, 1, 300))


class CondicoesDataEIncerto(unittest.TestCase):
    def test_data_insuficiente_abaixo_de_12_pares(self):
        d = date(2020, 1, 1)
        r = A.condicao_data([(EP, EP, d, d)] * 11 + [(NE, NE, None, None)] * 20)
        self.assertEqual(r["estado"], "insuficiente")
        self.assertIsNone(r["passa"])

    def test_data_passa_com_90_por_cento_a_7_dias(self):
        d = date(2020, 1, 1)
        bons = [(EP, EP, d, d + timedelta(days=7))] * 18
        ruins = [(EP, EP, d, d + timedelta(days=8))] * 2
        r = A.condicao_data(bons + ruins)
        self.assertEqual(r["estado"], "medido")
        self.assertTrue(r["passa"])
        r2 = A.condicao_data(bons[:17] + ruins + [(EP, EP, d, d + timedelta(days=30))])
        self.assertFalse(r2["passa"])

    def test_data_sem_data_no_par_conta_como_fora(self):
        d = date(2020, 1, 1)
        r = A.condicao_data([(EP, EP, d, None)] * 12)
        self.assertEqual(r["fracao_7d"], 0.0)
        self.assertFalse(r["passa"])

    def test_incerto_teto_de_cinco_por_cento(self):
        it = [{"classe1": NE}] * 95 + [{"classe1": INC}] * 5
        self.assertTrue(A.taxa_incerto(it)["passa"])
        it2 = [{"classe1": NE}] * 94 + [{"classe1": INC}] * 6
        self.assertFalse(A.taxa_incerto(it2)["passa"])

    def test_extensao_data_da_20_ep_fora_da_amostra(self):
        it = itens_sinteticos()
        ids, _ = A.amostra_g1a(it)
        ext = A.extensao_data(it, ids)
        por = {x["id"]: x for x in it}
        self.assertEqual(len(ext), 20)
        self.assertTrue(all(por[i]["classe1"] == EP for i in ext))
        self.assertFalse(set(ext) & set(ids))
        self.assertEqual(ext, A.extensao_data(it, ids))


class G1aCompleto(unittest.TestCase):
    def test_incompleto_sem_segunda_leitura(self):
        it = itens_sinteticos()
        r = A.g1a(it, [])
        self.assertEqual(r["estado"], "incompleto")
        self.assertEqual(len(r["faltam_segunda_leitura"]), 60)

    def test_concordancia_total_passa(self):
        it = itens_sinteticos()
        for x in it:  # incerto abaixo de 5%
            if x["classe1"] == INC:
                x["classe1"] = NE
        ids, _ = A.amostra_g1a(it)
        r = A.g1a(it, segunda_igual(it, ids), n_boot=200)
        self.assertEqual(r["estado"], "calculado")
        self.assertEqual(r["veredito"], "passa")
        self.assertAlmostEqual(r["kappa_binario_ponderado"], 1.0)
        self.assertEqual(r["discordancias"], [])

    def test_segundo_rotulador_aleatorio_reprova(self):
        it = itens_sinteticos()
        for x in it:
            if x["classe1"] == INC:
                x["classe1"] = NE
        ids, _ = A.amostra_g1a(it)
        rng = random.Random(7)
        seg = [{"id": i, "classe2": rng.choice([EP, NE, CT, ET]), "data_evento2": date(2020, 1, 1)} for i in ids]
        r = A.g1a(it, seg, n_boot=200)
        self.assertIn(r["veredito"], ("reprova", "insuficiente_data"))
        self.assertIsNot(r["passa"], True)
        self.assertLess(r["kappa_binario_ponderado"], 0.8)

    def test_incerto_acima_do_teto_reprova_mesmo_com_kappa_um(self):
        it = itens_sinteticos()
        for x in it[:60]:
            x["classe1"] = INC
            x["data_evento1"] = None
        ids, _ = A.amostra_g1a(it)
        r = A.g1a(it, segunda_igual(it, ids), n_boot=200)
        self.assertFalse(r["incerto"]["passa"])
        self.assertIsNot(r["passa"], True)

    def test_poucos_pares_ep_da_insuficiente_e_lista_extensao(self):
        it = itens_sinteticos()
        for x in it:
            if x["classe1"] == INC:
                x["classe1"] = NE
        ids, _ = A.amostra_g1a(it)
        por = {x["id"]: x for x in it}
        seg = []
        n_ep = 0
        for i in ids:
            c = por[i]["classe1"]
            if c == EP:
                n_ep += 1
                c2 = EP if n_ep <= 5 else NE  # so 5 pares EP-EP
            else:
                c2 = c
            seg.append({"id": i, "classe2": c2, "data_evento2": por[i]["data_evento1"]})
        r = A.g1a(it, seg, n_boot=200)
        self.assertEqual(r["veredito"], "insuficiente_data")
        self.assertIsNone(r["passa"])
        self.assertEqual(len(r["extensao_data"]), 20)


if __name__ == "__main__":
    unittest.main()
