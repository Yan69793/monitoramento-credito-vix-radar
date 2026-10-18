"""Testes G0-v4: regras locais (duas pontas), trecho literal, idempotencia/retomada e portoes. Sem rede, sem modelo."""
import json
import os
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_comparar as CP  # noqa: E402
import g0v4_portoes as PT  # noqa: E402
import g0v4_processar as PR  # noqa: E402
import g0v4_regras as RG  # noqa: E402

LONGO = " Texto de enchimento sobre a administracao da companhia e seus resultados trimestrais. " * 3


def cls(dia_txt, ctx=None, meta_dia=("fato relevante", ""), data="2020-06-10"):
    textos = {"d1": dia_txt}
    meta = {"d1": {"data_entrega": data, "categoria": meta_dia[0], "assunto": meta_dia[1]}}
    man = {"dia": ["d1"], "contexto_180d": [], "indice_24m": []}
    for k, (de, t) in enumerate((ctx or {}).items()):
        p = "c%d" % k
        textos[p] = t
        meta[p] = {"data_entrega": de, "categoria": "fato relevante", "assunto": ""}
        man["contexto_180d"].append(p)
    return RG.classificar({"id": "t", "cnpj": "00.000.000/0001-00", "data": data}, man, meta, textos.get)


class TestRegras(unittest.TestCase):
    def test_rj_propria_e_evento_proprio(self):
        r = cls(LONGO + "A Companhia ajuizou pedido de recuperação judicial perante a Vara Empresarial na data de hoje." + LONGO)
        self.assertEqual(r["classe"], "evento_proprio")
        self.assertEqual(r["tipo"], "RJ")
        self.assertTrue(r["revisao_obrigatoria"])
        self.assertTrue(RG.confere(r["trecho_evento"], LONGO + "A Companhia ajuizou pedido de recuperação judicial perante a Vara Empresarial na data de hoje." + LONGO))

    def test_texto_limpo_e_nao_evento_automatico(self):
        r = cls(LONGO * 2)
        self.assertEqual(r["classe"], "nao_evento")
        self.assertFalse(r["revisao_obrigatoria"])

    def test_sem_texto_nunca_vira_nao_evento(self):
        r = cls("")
        self.assertEqual(r["classe"], "PENDENTE_REVISAO")
        self.assertIn("ilegivel", r["motivos_revisao"][0])

    def test_negacao_vai_a_revisao_nao_a_nao_evento(self):
        r = cls(LONGO + "A Companhia informa que não ajuizou pedido de recuperação judicial e que o pedido foi indeferido." + LONGO)
        self.assertEqual(r["classe"], "PENDENTE_REVISAO")

    def test_terceiro_vai_a_revisao(self):
        r = cls(LONGO + "A controlada Alfa Ltda. ajuizou pedido de recuperação judicial na Comarca de Sao Paulo." + LONGO)
        self.assertNotEqual(r["classe"], "nao_evento")
        self.assertTrue(r["revisao_obrigatoria"])

    def test_conjunto_com_controladas_e_proprio(self):
        r = cls(LONGO + "A GPC Participações e parte de suas controladas ingressaram com pedidos de recuperação judicial." + LONGO)
        self.assertEqual(r["classe"], "evento_proprio")

    def test_hipotetico_clausula_nao_e_evento(self):
        r = cls(LONGO + "A escritura preve que poderá ocorrer vencimento antecipado das debêntures caso haja inadimplemento." + LONGO)
        self.assertEqual(r["classe"], "nao_evento")
        self.assertEqual(r["caminho"], "so_hipotetico")

    def test_repactuacao_sem_gatilho_vai_a_revisao(self):
        r = cls(LONGO + "Foi concedido o perdão dos encargos moratórios mediante bônus de adimplemento aos credores." + LONGO)
        self.assertEqual(r["classe"], "PENDENTE_REVISAO")

    def test_continuacao_com_origem_no_contexto(self):
        ctx = {"2020-03-01": LONGO + "A Companhia ajuizou pedido de recuperação judicial em 01 de março de 2020." + LONGO}
        r = cls(LONGO + "A Companhia comunica, em continuidade ao fato relevante, o deferimento do processamento da recuperação judicial." + LONGO, ctx)
        self.assertEqual(r["classe"], "continuacao")
        self.assertTrue(r["origem"]["completa"])
        self.assertEqual(r["origem"]["data_entrega"], "2020-03-01")

    def test_metadado_forte_sem_gatilho_no_texto_nao_e_nao_evento(self):
        r = cls(LONGO * 2, meta_dia=("fato relevante", "Pedido de Recuperação Judicial"))
        self.assertEqual(r["classe"], "PENDENTE_REVISAO")

    def test_determinismo(self):
        t = LONGO + "A Companhia ajuizou pedido de recuperação judicial." + LONGO
        a, b = cls(t), cls(t)
        self.assertEqual(json.dumps(a, sort_keys=True, default=str), json.dumps(b, sort_keys=True, default=str))

    def test_trecho_inventado_nao_confere(self):
        self.assertFalse(RG.confere("trecho que nao existe no documento", LONGO))


class TestProcessar(unittest.TestCase):
    def test_idempotencia_e_retomada(self):
        with tempfile.TemporaryDirectory() as d:
            saida = os.path.join(d, "s")
            os.makedirs(saida)
            r1 = PR.rodar({"i0001", "i0002"}, saida=saida)
            self.assertEqual(r1, 0)
            n1 = sum(1 for _ in open(os.path.join(saida, "classificacoes.jsonl"), encoding="utf-8"))
            # linha corrompida no fim (queda no meio da escrita): ignorada, item refeito
            with open(os.path.join(saida, "classificacoes.jsonl"), "a", encoding="utf-8") as fh:
                fh.write('{"id": "i0003", "versao": ')
            r2 = PR.rodar({"i0001", "i0002", "i0003"}, saida=saida)
            self.assertEqual(r2, 0)
            ids = [json.loads(ln)["id"] for ln in open(os.path.join(saida, "classificacoes.jsonl"), encoding="utf-8") if ln.strip().endswith("}")]
            self.assertEqual(ids.count("i0001"), 1)
            self.assertEqual(ids.count("i0003"), 1)
            self.assertEqual(n1, 2)

    def test_lock_impede_execucao_dupla(self):
        with tempfile.TemporaryDirectory() as d:
            open(os.path.join(d, "execucao.lock"), "w").write("1")
            self.assertEqual(PR.rodar({"i0001"}, saida=d), 3)


class TestPortoes(unittest.TestCase):
    def test_preservados_conferem_hash(self):
        for k, v in PT.PRESERVADOS.items():
            self.assertEqual(PR.sha256_arquivo(os.path.join(PT.BASE, k)), v, k)

    def test_g1v4_reprova_sem_revisao(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(PT.portoes(d), PT.EXIT_BLOQUEADO)

    def test_comparador_detecta_falso_negativo_e_aceita_revisao(self):
        antigo = {"a": {"classe1": "evento_proprio", "data_evento1": "2020-01-01"}, "b": {"classe1": "evento_proprio", "data_evento1": "2020-01-01"}}
        novo = {"a": {"classe": "nao_evento"}, "b": {"classe": "PENDENTE_REVISAO"}}
        r = CP.comparar(novo, antigo)
        self.assertEqual(r["falsos_negativos_materiais"], ["a"])
        self.assertEqual(r["materiais_em_revisao"], ["b"])


if __name__ == "__main__":
    unittest.main()
