"""Duas pontas do executor do G1-eq: gate puro, fatiamento, camada de CLI (sem rede), isolamento do prompt e guarda.
Rodar: python -I -m unittest discover -s scripts/predictive/validacao -p "test_g1eq*.py" -v
"""
import json
import os
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g1eq as GQ  # noqa: E402
import leitura_integral_g0v3 as LI  # noqa: E402
import llm_cli as L  # noqa: E402
import rotular_g0v3 as RO  # noqa: E402
import guarda_g0v3 as G3  # noqa: E402


def par(i, a, b, da=None, db=None, sa="rotulado", sb="rotulado"):
    return {"id": "i%04d" % i, "classe_prog": a, "classe_int": b, "data_prog": da, "data_int": db, "status_prog": sa, "status_int": sb}


class GatePuro(unittest.TestCase):
    def test_concordancia_total_passa(self):
        pares = [par(i, "nao_evento", "nao_evento") for i in range(1, 29)] + [par(29, "evento_proprio", "evento_proprio", "2020-01-01", "2020-01-01"),
                                                                           par(30, "continuacao", "continuacao")]
        r = GQ.avaliar_pares(pares)
        self.assertTrue(r["passa"])
        self.assertEqual(r["veredito"], "passa")

    def test_uma_discordancia_binaria_passa_duas_reprovam(self):
        base = [par(i, "nao_evento", "nao_evento") for i in range(1, 29)]
        um = base + [par(29, "evento_proprio", "nao_evento"), par(30, "nao_evento", "nao_evento")]
        self.assertTrue(GQ.avaliar_pares(um)["passa"])
        dois = base + [par(29, "evento_proprio", "nao_evento"), par(30, "continuacao", "evento_proprio")]
        r = GQ.avaliar_pares(dois)
        self.assertFalse(r["passa"])
        self.assertEqual(r["n_dif_classe"], 2)

    def test_troca_entre_classes_do_resto_nao_conta(self):
        pares = [par(i, "continuacao", "nao_evento") for i in range(1, 31)]
        self.assertTrue(GQ.avaliar_pares(pares)["passa"])

    def test_data_uma_diferenca_passa_duas_reprovam(self):
        base = [par(i, "nao_evento", "nao_evento") for i in range(1, 28)]
        um = base + [par(28, "evento_proprio", "evento_proprio", "2020-01-01", "2020-01-02"),
                     par(29, "evento_proprio", "evento_proprio", "2021-05-05", "2021-05-05"),
                     par(30, "evento_proprio", "evento_proprio", "2022-01-01", "2022-01-01")]
        self.assertTrue(GQ.avaliar_pares(um)["passa"])
        dois = base + [par(28, "evento_proprio", "evento_proprio", "2020-01-01", "2020-01-02"),
                       par(29, "evento_proprio", "evento_proprio", "2021-05-05", "2021-05-06"),
                       par(30, "evento_proprio", "evento_proprio", "2022-01-01", "2022-01-01")]
        r = GQ.avaliar_pares(dois)
        self.assertFalse(r["passa"])
        self.assertEqual(r["n_dif_data"], 2)

    def test_incompleto_nao_decide(self):
        pares = [par(i, "nao_evento", "nao_evento") for i in range(1, 30)] + [par(30, "nao_evento", None, sb="erro_chamada")]
        r = GQ.avaliar_pares(pares)
        self.assertIsNone(r["passa"])
        self.assertEqual(r["veredito"], "incompleto")

    def test_vazio_nao_passa(self):
        self.assertIsNone(GQ.avaliar_pares([])["passa"])

    def test_adjudicacao_listada(self):
        pares = [par(i, "nao_evento", "nao_evento") for i in range(1, 30)] + [par(30, "evento_proprio", "evento_proprio", "2020-01-01", "2020-01-01", sa="adjudicacao")]
        self.assertEqual(GQ.avaliar_pares(pares)["adjudicacao"], ["i0030"])


class Fatiamento(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.meta = {}

        def doc(p, data, txt):
            self.meta[p] = {"data_entrega": data, "categoria": "fato relevante", "assunto": "x"}
            with open(os.path.join(self.d, "%s.txt" % p), "w", encoding="utf-8") as fh:
                fh.write(txt)
        doc("1", "2020-01-10", "documento do dia com texto suficiente para passar do minimo " * 3)
        doc("2", "2019-12-01", ("pagina um " * 3000) + "\f" + ("pagina dois " * 3000) + "\f" + ("pagina tres " * 3000))  # ~100k
        doc("3", "2019-11-01", "curto " * 20)
        self.meta["4"] = {"data_entrega": "2019-10-01", "categoria": "comunicado", "assunto": "y"}  # nao baixado
        self.man = {"dia": ["1"], "contexto_180d": ["4", "2", "3"], "indice_24m": []}

    def test_nenhum_caractere_perdido_e_teto_respeitado(self):
        fts, sem = LI.fatias(self.man, self.meta, self.d, teto=60000)
        self.assertTrue(all(len(f) <= 60000 for f in fts))
        corpo = "".join(fts)
        for p in ("1", "2", "3"):
            txt = LI.R.limpa(open(os.path.join(self.d, "%s.txt" % p), encoding="utf-8").read())
            # cada pagina do documento longo aparece inteira em alguma fatia
            for pg in txt.split("\f"):
                self.assertIn(pg.strip()[:200], corpo)
        self.assertEqual(len(sem), 1)
        self.assertIn("NAO BAIXADO", sem[0])

    def test_documento_longo_e_partido_por_pagina_com_rotulo_de_parte(self):
        fts, _ = LI.fatias(self.man, self.meta, self.d, teto=60000)
        partes = [f for f in fts if "parte " in f and "protocolo 2 " in f]
        self.assertGreaterEqual(len(partes), 2)
        self.assertIn("parte 1/", "".join(fts))

    def test_ordem_dia_depois_contexto_por_data(self):
        fts, _ = LI.fatias(self.man, self.meta, self.d, teto=10 ** 7)
        texto = "\n".join(fts)
        self.assertLess(texto.index("protocolo 1 "), texto.index("protocolo 3 "))
        self.assertLess(texto.index("protocolo 3 "), texto.index("protocolo 2 "))  # 3 (2019-11) antes de 2 (2019-12)

    def test_deterministico(self):
        a, _ = LI.fatias(self.man, self.meta, self.d)
        b, _ = LI.fatias(self.man, self.meta, self.d)
        self.assertEqual(a, b)


class CamadaCli(unittest.TestCase):
    def test_argv_claude_sem_token_e_isolado(self):
        a = L.argv_claude("claude-sonnet-5-5", "S", {"type": "object"})
        self.assertNotIn("sk-ant", " ".join(a))
        self.assertIn("--setting-sources", a)
        self.assertEqual(a[a.index("--setting-sources") + 1], "")
        self.assertEqual(a[a.index("--tools") + 1], "")
        self.assertIn("--no-session-persistence", a)
        self.assertIn("--json-schema", a)

    def test_ambiente_claude_coloca_token_e_limpa_chave_paga(self):
        os.environ["ANTHROPIC_API_KEY"] = "x"
        try:
            env = L.ambiente_claude(token="TOKENTESTE")
        finally:
            os.environ.pop("ANTHROPIC_API_KEY", None)
        self.assertEqual(env.get("CLAUDE_CODE_OAUTH_TOKEN"), "TOKENTESTE")
        self.assertNotIn("ANTHROPIC_API_KEY", env)
        self.assertNotIn("CLAUDECODE", env)
        self.assertEqual(env["ANTHROPIC_BASE_URL"], "https://api.anthropic.com")

    def test_argv_codex_read_only_sem_busca(self):
        a = L.argv_codex("m", "out.txt")
        self.assertIn("read-only", a)
        self.assertNotIn("--search", a)
        self.assertIn("--ephemeral", a)

    def test_interpretacao_ok(self):
        out = json.dumps({"is_error": False, "result": "{}", "structured_output": {"a": 1}, "usage": {"input_tokens": 10, "output_tokens": 2,
                          "cache_read_input_tokens": 3, "cache_creation_input_tokens": 4}, "modelUsage": {"claude-sonnet-5-5": {}}})
        r = L.interpretar_saida_claude(out, "", 0)
        self.assertTrue(r["ok"])
        self.assertEqual(r["structured"], {"a": 1})
        self.assertEqual(L.total_tokens(r["usage"]), 19)
        self.assertEqual(r["modelos"], ["claude-sonnet-5-5"])

    def test_interpretacao_limite_e_auth(self):
        lim = json.dumps({"is_error": True, "result": "You've hit your session limit - resets 9pm", "api_error_status": 429, "usage": {}})
        self.assertEqual(L.interpretar_saida_claude(lim, "", 1)["classe"], "limite")
        au = json.dumps({"is_error": True, "result": "Failed to authenticate: OAuth session expired", "usage": {}})
        self.assertEqual(L.interpretar_saida_claude(au, "", 1)["classe"], "auth")
        self.assertEqual(L.interpretar_saida_claude("", "timeout", 124)["classe"], "transitoria")

    def test_codex_dry_run_nao_executa(self):
        r = L.chamar_codex("p", "s", {"type": "object"}, executar=False)
        self.assertEqual(r["classe"], "dry_run")
        self.assertIn("codex", r["argv"][0])

    def test_interpretacao_codex_soma_usage(self):
        jl = '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":5}}\n{"x":1}\n'
        r = L.interpretar_saida_codex(jl, 'texto {"classe":"nao_evento"} fim')
        self.assertTrue(r["ok"])
        self.assertEqual(r["usage"]["input"], 100)
        self.assertEqual(r["usage"]["cache_read"], 40)
        self.assertEqual(r["structured"]["classe"], "nao_evento")


class IsolamentoEGuarda(unittest.TestCase):
    def test_guia_v3_vem_do_bloco_congelado(self):
        item2, anexo, est = RO.guia_v3()
        self.assertTrue(est["ok"])
        self.assertTrue(item2.startswith("### 2. Rótulo, por candidato"))
        self.assertIn("12.000 caracteres", item2)  # G0-v3, nao G0-v2
        self.assertIn("G0-v2-anexo-guia", anexo)
        self.assertNotIn("### 3.", item2)

    def test_guia_v3_recusa_com_guarda_reprovando(self):
        orig = G3.estado
        G3.estado = lambda *a, **k: {"ok": False, "motivos": ["teste"], "sha256_v3": "", "sha256_recuperar": ""}
        try:
            with self.assertRaises(SystemExit):
                RO.guia_v3()
        finally:
            G3.estado = orig

    def test_prompt_so_recebe_item_manifesto_meta_textos(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "9.txt"), "w", encoding="utf-8") as fh:
            fh.write("a companhia informa o ajuizamento de pedido de recuperacao judicial " * 5)
        item = {"id": "i0001", "cnpj": "00.000.000/0001-00", "data": "2020-01-10"}
        man = {"dia": ["9"], "contexto_180d": [], "indice_24m": [{"data": "2019-01-01", "categoria": "c", "assunto": "s", "protocolo_rad": "8"}]}
        meta = {"9": {"data_entrega": "2020-01-10", "categoria": "fato relevante", "assunto": "x", "link": None}}
        guia = ("### 2. guia de teste", "anexo de teste", {"sha256_v3": "", "sha256_recuperar": ""})
        p, reg = RO.montar_prompt(item, man, meta, d, [], 0, guia)
        self.assertIn("CNPJ 00.000.000/0001-00", p)
        self.assertIn("protocolo 9", p)
        self.assertIn("so metadado", p)
        for proibido in ("mapa_camadas", "EWS", "estrato", "sinal", "rotulo do"):
            self.assertNotIn(proibido, p)
        self.assertEqual(reg["docs_indice"], 2)
        self.assertIn("ULTIMA rodada", RO.montar_prompt(item, man, meta, d, [], 3, guia)[0])

    def test_verificar_rotulo_duas_pontas(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "TXT"))
        with open(os.path.join(d, "TXT", "7.txt"), "w", encoding="utf-8") as fh:
            fh.write("A Companhia informa que ajuizou pedido de recuperação judicial nesta data, com mais texto para o minimo de oitenta caracteres.")
        bom = {"classe": "evento_proprio", "protocolo_evento": "7", "trecho_evento": "ajuizou pedido de recuperacao judicial", "adicionais": []}
        self.assertEqual(RO.verificar_rotulo(bom, d), [])
        ruim = {"classe": "evento_proprio", "protocolo_evento": "7", "trecho_evento": "decretada a falencia", "adicionais": []}
        self.assertTrue(RO.verificar_rotulo(ruim, d))
        sem_doc = {"classe": "continuacao", "origem": {"protocolo": "99", "trecho": "x"}, "adicionais": []}
        self.assertTrue(RO.verificar_rotulo(sem_doc, d))
        ne = {"classe": "nao_evento", "adicionais": []}
        self.assertEqual(RO.verificar_rotulo(ne, d), [])

    def test_esquema_exige_rotulo_completo(self):
        self.assertEqual(set(RO.ESQUEMA_SO_ROTULO["required"]), set(RO.ROTULO_PROPS))
        self.assertIn("pedir_paginas", RO.ESQUEMA["properties"]["acao"]["enum"])

    def test_itens_g1eq_sao_os_30_primeiros_da_ordem_cega(self):
        etapa = os.path.join(AQUI, "..", "..", "..", "data", "validacao", "etapa1_g0v2")
        if not os.path.exists(os.path.join(etapa, "itens_cegos.json")):
            self.skipTest("etapa 1 ausente")
        it = GQ.itens_g1eq(etapa)
        self.assertEqual([x["id"] for x in it], ["i%04d" % i for i in range(1, 31)])


if __name__ == "__main__":
    unittest.main()
