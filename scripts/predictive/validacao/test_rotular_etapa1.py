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
            json.dump({"autorizado": ok, "data": "2026-10-20", "primeiro_rotulador": "claude", "segundo_rotulador": "codex",
                       "modelo_segundo": "modelo-x", "teto_tokens_lote": 2000000}, fh)

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
        # P4 (16/10): congelada aprovada so libera com o bloco estendido aprovado junto
        with open(os.path.join(self.d, "g1eq", "resultado_g1eq.json"), "w", encoding="utf-8") as fh:
            json.dump({"passa": True, "veredito": "passa", "n_completos": 30, "estendido": {"passa": True, "motivos": []}}, fh)
        self._aut()
        p = RE.portoes(self.d, self.aut)
        self.assertEqual(p["ok"], p["P1_guarda_g0v3"]["ok"])
        self.assertTrue(p["P2_g1eq"]["ok"] and p["P3_autorizacao"]["ok"] and p["P4_g1eq_estendido"]["ok"])

    def test_congelada_aprovada_sem_estendido_bloqueia(self):
        self._g1eq(True)
        self._aut()
        p = RE.portoes(self.d, self.aut)
        self.assertTrue(p["P2_g1eq"]["ok"])
        self.assertFalse(p["P4_g1eq_estendido"]["ok"])
        self.assertFalse(p["ok"])

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



class SegundoRotulador(unittest.TestCase):
    """segundo_config: duas pontas para cada provedor. Puro, sem chamada."""
    BASE = {"autorizado": True, "primeiro_rotulador": "claude", "modelo_claude": "claude-sonnet-5-5", "teto_tokens_lote": 2000000}

    def cfg(self, **kw):
        return RE.segundo_config(dict(self.BASE, **kw))

    def test_aceita_codex_gemini_openrouter_e_claude_com_aceite(self):
        for kw in ({"segundo_rotulador": "codex", "modelo_segundo": "gpt-x"},
                   {"segundo_rotulador": "openrouter", "modelo_segundo": "deepseek/x", "openrouter_pago_autorizado": True},
                   {"segundo_rotulador": "claude", "modelo_segundo": "claude-opus-5-5", "aceita_mesmo_fornecedor": True}):
            c, erros = self.cfg(**kw)
            self.assertEqual(erros, [], kw)
            self.assertEqual(c["teto_tokens_lote"], 2000000)

    def test_reprova_configuracoes_ruins(self):
        casos = [({"segundo_rotulador": "codex"}, "modelo_segundo"),  # sem modelo (e sem variavel de usuario no teste)
                 ({"segundo_rotulador": "grok", "modelo_segundo": "x"}, "invalido"),
                 ({"segundo_rotulador": "claude", "modelo_segundo": "claude-opus-5-5"}, "mesmo fornecedor"),
                 ({"segundo_rotulador": "claude", "modelo_segundo": "claude-sonnet-5-5", "aceita_mesmo_fornecedor": True}, "MESMO modelo"),
                 ({"segundo_rotulador": "openrouter", "modelo_segundo": "deepseek/x"}, "pago"),
                 ({"segundo_rotulador": "openrouter", "modelo_segundo": "anthropic/claude-x", "openrouter_pago_autorizado": True}, "mesmo fornecedor"),
                 ({"segundo_rotulador": "codex", "modelo_segundo": "g", "teto_tokens_lote": 0}, "teto"),
                 ({"segundo_rotulador": "gemini", "modelo_segundo": "gemini-x"}, "gemini bloqueado")]
        orig = RE.L.modelo_codex
        RE.L.modelo_codex = lambda: None
        try:
            for kw, trecho in casos:
                base = dict(self.BASE)
                base.update(kw)
                _, erros = RE.segundo_config(base)
                self.assertTrue(any(trecho in e for e in erros), (kw, erros))
        finally:
            RE.L.modelo_codex = orig

class PrimeiroRotulador(unittest.TestCase):
    """16/10: primeiro leitor configuravel (claude|openrouter). G1-eq do Claude nao aprova outro modelo."""
    DS = "deepseek/deepseek-v4.1-flash"

    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.aut = os.path.join(self.d, "autorizacao.json")

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def _aut(self, **kw):
        a = {"autorizado": True, "data": "2026-10-16", "primeiro_rotulador": "openrouter", "modelo_primeiro": self.DS,
             "openrouter_pago_autorizado": True, "segundo_rotulador": "claude", "modelo_segundo": "claude-sonnet-5-5",
             "teto_tokens_lote": 2000000}
        a.update(kw)
        with open(self.aut, "w", encoding="utf-8") as fh:
            json.dump(a, fh)

    def _res(self, pasta, **kw):
        os.makedirs(os.path.join(self.d, pasta), exist_ok=True)
        r = {"passa": True, "veredito": "passa", "n_completos": 30, "estendido": {"passa": True, "motivos": []}}
        r.update(kw)
        with open(os.path.join(self.d, pasta, "resultado_g1eq.json"), "w", encoding="utf-8") as fh:
            json.dump(r, fh)

    def test_g1eq_do_claude_nao_aprova_deepseek(self):
        self._aut()
        self._res("g1eq")  # so o resultado historico do Claude
        p = RE.portoes(self.d, self.aut)
        self.assertFalse(p["P2_g1eq"]["ok"])
        self.assertFalse(p["ok"])

    def test_g1eq_do_deepseek_na_pasta_dele_aprova(self):
        import g1eq as GQ
        self._aut()
        self._res(os.path.basename(GQ.saida_dir(self.d, "openrouter", self.DS)), provider="openrouter", modelo=self.DS)
        p = RE.portoes(self.d, self.aut)
        self.assertTrue(p["P2_g1eq"]["ok"], p["P2_g1eq"])
        self.assertTrue(p["P3_autorizacao"]["ok"], p["P3_autorizacao"])

    def test_resultado_de_outro_modelo_na_pasta_reprova(self):
        import g1eq as GQ
        self._aut()
        self._res(os.path.basename(GQ.saida_dir(self.d, "openrouter", self.DS)), provider="openrouter", modelo="deepseek/outro")
        self.assertFalse(RE.portoes(self.d, self.aut)["P2_g1eq"]["ok"])

    def test_claude_continua_padrao_e_pasta_historica(self):
        import g1eq as GQ
        c, erros = RE.primeiro_config({"primeiro_rotulador": "claude", "modelo_claude": "claude-sonnet-5-5"})
        self.assertEqual(erros, [])
        self.assertEqual(GQ.saida_dir(self.d, c["provider"], c["modelo"]), os.path.join(self.d, "g1eq"))
        self.assertEqual(RE.primeiro_config({})[0]["provider"], "claude")

    def test_primeiro_openrouter_exige_aceite_pago_e_formato(self):
        _, e1 = RE.primeiro_config({"primeiro_rotulador": "openrouter", "modelo_primeiro": self.DS})
        self.assertTrue(any("pago" in e for e in e1))
        _, e2 = RE.primeiro_config({"primeiro_rotulador": "openrouter", "modelo_primeiro": "deepseek", "openrouter_pago_autorizado": True})
        self.assertTrue(any("fornecedor/modelo" in e for e in e2))
        _, e3 = RE.primeiro_config({"primeiro_rotulador": "codex", "modelo_primeiro": "x"})
        self.assertTrue(any("invalido" in e for e in e3))

    def test_segundo_do_mesmo_fornecedor_do_primeiro_novo_reprova(self):
        base = {"primeiro_rotulador": "openrouter", "modelo_primeiro": self.DS, "openrouter_pago_autorizado": True,
                "teto_tokens_lote": 2000000}
        _, ok = RE.segundo_config(dict(base, segundo_rotulador="claude", modelo_segundo="claude-sonnet-5-5"))
        self.assertEqual(ok, [])  # Claude como segundo de um primeiro DeepSeek: outro fornecedor, sem aceite
        _, ruim = RE.segundo_config(dict(base, segundo_rotulador="openrouter", modelo_segundo="deepseek/deepseek-v4-pro"))
        self.assertTrue(any("mesmo fornecedor" in e for e in ruim))


class P2Substituto(unittest.TestCase):
    """16/10, decisao do operador: DeepSeek sem braco integral. P2 e P4 so abrem com as TRES pecas, todas do mesmo leitor."""
    DS = "deepseek/deepseek-v4.1-flash"

    def setUp(self):
        import g1eq as GQ
        self.GQ = GQ
        self.d = tempfile.mkdtemp()
        self.aut = os.path.join(self.d, "autorizacao.json")
        with open(self.aut, "w", encoding="utf-8") as fh:
            json.dump({"autorizado": True, "data": "2026-10-16", "primeiro_rotulador": "openrouter", "modelo_primeiro": self.DS,
                       "openrouter_pago_autorizado": True, "segundo_rotulador": "claude", "modelo_segundo": "claude-sonnet-5-5",
                       "teto_tokens_lote": 2000000}, fh)
        self.pasta = self.GQ.saida_dir(self.d, "openrouter", self.DS)
        os.makedirs(self.pasta)
        os.makedirs(os.path.join(self.d, "g1eq"))

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def _w(self, caminho, obj):
        with open(caminho, "w", encoding="utf-8") as fh:
            json.dump(obj, fh)

    def _claude(self, passa=True, n=30, ext=True):
        self._w(os.path.join(self.d, "g1eq", "resultado_g1eq.json"), {"passa": passa, "n_completos": n, "estendido": {"passa": ext, "motivos": []}})

    def _decisao(self, **kw):
        d = {"autorizado_por_operador": True, "substitui": RE.SUBSTITUI_P2, "provider": "openrouter", "modelo": self.DS}
        d.update(kw)
        self._w(os.path.join(self.pasta, "decisao_p2.json"), d)

    def _qual(self, **kw):
        q = {"passa": True, "completo": True, "modelo": self.DS}
        q.update(kw)
        self._w(os.path.join(self.pasta, "qualidade_independente.json"), q)

    def test_as_tres_pecas_abrem_p2_e_p4(self):
        self._claude(); self._decisao(); self._qual()
        p = RE.portoes(self.d, self.aut)
        self.assertTrue(p["P2_g1eq"]["ok"], p["P2_g1eq"])
        self.assertEqual(p["P2_g1eq"]["via"], "substituto")
        self.assertTrue(p["P4_g1eq_estendido"]["ok"])

    def test_faltando_qualquer_peca_fecha(self):
        casos = {
            "sem decisao": lambda: (self._claude(), self._qual()),
            "sem qualidade": lambda: (self._claude(), self._decisao()),
            "sem g1eq do metodo": lambda: (self._decisao(), self._qual()),
            "g1eq do metodo reprovado": lambda: (self._claude(passa=False), self._decisao(), self._qual()),
            "g1eq do metodo incompleto": lambda: (self._claude(n=29), self._decisao(), self._qual()),
            "g1eq do metodo sem estendido": lambda: (self._claude(ext=False), self._decisao(), self._qual()),
            "qualidade reprovada": lambda: (self._claude(), self._decisao(), self._qual(passa=False)),
            "qualidade incompleta": lambda: (self._claude(), self._decisao(), self._qual(completo=False)),
            "qualidade de outro modelo": lambda: (self._claude(), self._decisao(), self._qual(modelo="deepseek/outro")),
            "decisao de outro modelo": lambda: (self._claude(), self._decisao(modelo="deepseek/outro"), self._qual()),
            "decisao nao autorizada": lambda: (self._claude(), self._decisao(autorizado_por_operador=False), self._qual()),
            "decisao de outra substituicao": lambda: (self._claude(), self._decisao(substitui="outra"), self._qual()),
        }
        for nome, montar in casos.items():
            for f in os.listdir(self.pasta):
                os.remove(os.path.join(self.pasta, f))
            p0 = os.path.join(self.d, "g1eq", "resultado_g1eq.json")
            if os.path.exists(p0):
                os.remove(p0)
            montar()
            p = RE.portoes(self.d, self.aut)
            self.assertFalse(p["P2_g1eq"]["ok"], nome)
            self.assertFalse(p["ok"], nome)

    def test_claude_padrao_nunca_usa_substituto(self):
        with open(self.aut, "w", encoding="utf-8") as fh:
            json.dump({"autorizado": True, "primeiro_rotulador": "claude", "modelo_claude": "claude-sonnet-5-5", "segundo_rotulador": "codex",
                       "modelo_segundo": "m", "teto_tokens_lote": 1}, fh)
        self._claude(passa=False)
        self.assertFalse(RE.portoes(self.d, self.aut)["P2_g1eq"]["ok"])
        self.assertIsNone(RE.portoes(self.d, self.aut)["P2_g1eq"]["motivos_substituto"])


class Orcamento(unittest.TestCase):
    PRECO = {"input": 0.036, "output": 0.6435, "cache_read": 0.0054}

    def test_custo_e_acumulado(self):
        d = tempfile.mkdtemp()
        try:
            p = os.path.join(d, "x", "custos.jsonl")
            orc = {"usd": 1.0, "preco": self.PRECO}
            RE.registrar_custo(p, "i1", {"input": 1_000_000, "output": 100_000, "cache_read": 0}, orc)
            RE.registrar_custo(p, "i2", {"input": 0, "output": 0, "cache_read": 1_000_000}, orc)
            self.assertAlmostEqual(RE.custo_acumulado(p), 0.036 + 0.06435 + 0.0054, places=6)
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_leitura_paga_sem_orcamento_recusa_e_claude_nao_precisa(self):
        with self.assertRaises(RE.L.LimiteDeCota):
            RE.orcamento({"preco_usd_por_milhao": self.PRECO}, "openrouter")
        with self.assertRaises(RE.L.LimiteDeCota):
            RE.orcamento({"orcamento_usd": 5}, "openrouter")
        self.assertEqual(RE.orcamento({"orcamento_usd": 5, "preco_usd_por_milhao": self.PRECO}, "openrouter")["usd"], 5.0)
        self.assertIsNone(RE.orcamento({}, "claude"))


class Transcritor(unittest.TestCase):
    def test_openrouter_transcreve_com_o_proprio_modelo_e_resto_com_claude(self):
        import rotular_g0v3 as RO
        self.assertEqual(RO.transcritor_de("openrouter", "deepseek/x"), ("openrouter", "deepseek/x"))
        self.assertEqual(RO.transcritor_de("claude", "claude-opus-5-5"), ("claude", "claude-opus-5-5"))
        # antes: um leitor codex mandava o modelo gpt ao Claude na transcricao
        self.assertEqual(RO.transcritor_de("codex", "gpt-6.1-sol"), ("claude", RE.L.MODELO_PADRAO))

    def test_imagens_vao_no_corpo_sem_chamar_rede(self):
        d = tempfile.mkdtemp()
        try:
            f = os.path.join(d, "p001.png")
            with open(f, "wb") as fh:
                fh.write(b"\x89PNG\r\n")
            r = RE.L.chamar_openrouter_imagens("t", "s", [f], "deepseek/x", executar=False)
            self.assertEqual(r["classe"], "dry_run")
            self.assertEqual(r["n_imagens"], 1)
            with self.assertRaises(RE.L.LimiteDeCota):
                RE.L.chamar_openrouter_imagens("t", "s", [f], "sem-barra", executar=False)
        finally:
            shutil.rmtree(d, ignore_errors=True)

    def test_texto_livre_aceita_transcricao_e_json_exige_objeto(self):
        corpo = json.dumps({"choices": [{"message": {"content": "=== PAGINA 1 ===\nFato Relevante"}}], "usage": {"prompt_tokens": 10, "completion_tokens": 5}})
        self.assertTrue(RE.L.interpretar_saida_openrouter(corpo, 200, texto_livre=True)["ok"])
        self.assertFalse(RE.L.interpretar_saida_openrouter(corpo, 200)["ok"])
        self.assertEqual(RE.L.interpretar_saida_openrouter("{}", 402)["classe"], "limite")


class RetryOpenRouter(unittest.TestCase):
    def _rodar(self, statuses):
        import io
        import urllib.error
        import urllib.request
        chamadas, esperas = [], []
        seq = list(statuses)

        def falso(req, timeout=None):
            chamadas.append(1)
            st = seq.pop(0)
            corpo = json.dumps({"choices": [{"message": {"content": "{\"a\": 1}"}}], "usage": {}}).encode()
            if st == 200:
                class R(io.BytesIO):
                    status = 200

                    def __enter__(self):
                        return self

                    def __exit__(self, *a):
                        return False
                return R(corpo)
            raise urllib.error.HTTPError(req.full_url, st, "x", {}, io.BytesIO(b"{}"))
        orig_open, orig_var = urllib.request.urlopen, RE.L._var_usuario
        urllib.request.urlopen, RE.L._var_usuario = falso, (lambda n: "chave-de-teste")
        try:
            r = RE.L._post_openrouter({"model": "d/x"}, {}, 5, dormir=esperas.append)
        finally:
            urllib.request.urlopen, RE.L._var_usuario = orig_open, orig_var
        return r, len(chamadas), esperas

    def test_5xx_repete_e_recupera(self):
        r, n, esperas = self._rodar([502, 503, 200])
        self.assertTrue(r["ok"])
        self.assertEqual(n, 3)
        self.assertEqual(len(esperas), 2)

    def test_terceira_tentativa_sai_sem_raciocinio(self):
        import io
        import urllib.request
        corpos = []

        def falso(req, timeout=None):
            corpos.append(json.loads(req.data.decode()))
            if len(corpos) < 3:
                import urllib.error
                raise urllib.error.HTTPError(req.full_url, 503, "x", {}, io.BytesIO(b"{}"))

            class R(io.BytesIO):
                status = 200

                def __enter__(self):
                    return self

                def __exit__(self, *a):
                    return False
            return R(json.dumps({"choices": [{"message": {"content": "{\"a\": 1}"}, "finish_reason": "stop"}], "usage": {}}).encode())
        orig = (urllib.request.urlopen, RE.L._var_usuario)
        urllib.request.urlopen, RE.L._var_usuario = falso, (lambda n: "chave-de-teste")
        try:
            r = RE.L._post_openrouter({"model": "d/x", **RE.L.OPENROUTER_ROTEAMENTO}, {}, 5, dormir=lambda s: None)
        finally:
            urllib.request.urlopen, RE.L._var_usuario = orig
        self.assertTrue(r["ok"])
        self.assertEqual(r["tentativas"], 3)
        self.assertEqual(corpos[0]["reasoning"], {"effort": "low"})
        self.assertEqual(corpos[1]["reasoning"], {"effort": "low"})
        self.assertEqual(corpos[2]["reasoning"], {"enabled": False})
        self.assertLessEqual(corpos[2]["max_tokens"], 16000)
        self.assertTrue(r["ultima_sem_raciocinio"])

    def test_saida_vazia_no_teto_e_truncamento_e_nao_json_ausente(self):
        corpo = json.dumps({"choices": [{"message": {"content": ""}, "finish_reason": "length"}], "usage": {"completion_tokens": 12000}})
        r = RE.L.interpretar_saida_openrouter(corpo, 200)
        self.assertFalse(r["ok"])
        self.assertIn("truncada", r["erro"])
        self.assertEqual(r["finish_reason"], "length")
        ok = json.dumps({"choices": [{"message": {"content": "{\"a\": 1}"}, "finish_reason": "stop"}], "usage": {}})
        self.assertTrue(RE.L.interpretar_saida_openrouter(ok, 200)["ok"])
        # 12000 truncou trecho que precisa de ~12k; 32000 deixa laco de raciocinio passar do prazo: faixa valida 14k a 20k
        self.assertTrue(14000 <= RE.L.OPENROUTER_ROTEAMENTO["max_tokens"] <= 20000)

    def test_truncada_refaz_uma_vez_sem_raciocinio_e_soma_custo(self):
        corpos = []
        respostas = [
            {"ok": False, "classe": "transitoria", "exit": 200, "finish_reason": "length", "result": "", "erro": "truncada", "usage": {"input": 100, "output": 32000, "custo_usd": 0.02}},
            {"ok": True, "finish_reason": "stop", "result": "{\"a\": 1}", "structured": {"a": 1}, "usage": {"input": 100, "output": 50, "custo_usd": 0.001}},
        ]

        def falso(corpo, base, timeout, **k):
            corpos.append(corpo)
            return dict(respostas[len(corpos) - 1])
        orig = RE.L._post_openrouter
        RE.L._post_openrouter = falso
        try:
            r = RE.L.chamar_openrouter("p", "s", None, "deepseek/x", executar=True)
        finally:
            RE.L._post_openrouter = orig
        self.assertTrue(r["ok"])
        self.assertTrue(r["fallback_sem_raciocinio"])
        self.assertEqual(len(corpos), 2)
        self.assertEqual(corpos[0]["reasoning"], {"effort": "low"})
        self.assertEqual(corpos[1]["reasoning"], {"enabled": False})
        self.assertEqual(r["usage"]["output"], 32050)
        self.assertAlmostEqual(r["usage"]["custo_usd"], 0.021)

    def test_texto_sem_json_tambem_refaz_sem_raciocinio_mas_402_e_prazo_nao(self):
        def roda(primeira):
            corpos = []
            respostas = [primeira, {"ok": True, "classe": None, "exit": 200, "result": "{}", "usage": {}}]

            def falso(corpo, base, timeout, **k):
                corpos.append(corpo)
                return dict(respostas[min(len(corpos) - 1, 1)])
            orig = RE.L._post_openrouter
            RE.L._post_openrouter = falso
            try:
                RE.L.chamar_openrouter("p", "s", None, "deepseek/x", executar=True)
            finally:
                RE.L._post_openrouter = orig
            return len(corpos)
        sem_json = {"ok": False, "classe": "transitoria", "exit": 200, "result": "texto livre", "erro": "resposta sem objeto JSON", "usage": {}}
        self.assertEqual(roda(sem_json), 2)
        self.assertEqual(roda({"ok": False, "classe": "limite", "exit": 402, "usage": {}}), 1)  # credito: nunca refaz
        self.assertEqual(roda({"ok": False, "classe": "transitoria", "exit": 0, "usage": {}}), 1)  # transporte: ja tem retry proprio

    def test_resposta_normal_nao_refaz(self):
        chamadas = []

        def falso(corpo, base, timeout, **k):
            chamadas.append(1)
            return {"ok": True, "finish_reason": "stop", "result": "{}", "usage": {}}
        orig = RE.L._post_openrouter
        RE.L._post_openrouter = falso
        try:
            RE.L.chamar_openrouter("p", "s", None, "deepseek/x", executar=True)
        finally:
            RE.L._post_openrouter = orig
        self.assertEqual(len(chamadas), 1)

    def test_custo_real_e_roteamento_pelo_mais_barato(self):
        corpo = json.dumps({"provider": "OpenInference", "choices": [{"message": {"content": "{\"a\": 1}"}}],
                            "usage": {"prompt_tokens": 1000, "completion_tokens": 10, "cost": 0.0000425}})
        r = RE.L.interpretar_saida_openrouter(corpo, 200)
        self.assertAlmostEqual(r["usage"]["custo_usd"], 0.0000425)
        self.assertEqual(r["provedor_roteado"], "OpenInference")
        self.assertEqual(RE.L.OPENROUTER_ROTEAMENTO["provider"]["sort"], "price")
        self.assertAlmostEqual(RE.custo_usd({"input": 10**6, "output": 0, "custo_usd": 0.5}, {"input": 9, "output": 9}), 0.5)
        self.assertAlmostEqual(RE.custo_usd({"input": 10**6, "output": 0}, {"input": 0.036, "output": 1}), 0.036)

    def test_prazo_total_estoura_e_retentativa_pede_o_mais_rapido_com_teto(self):
        import io
        import time
        import urllib.request
        corpos = []

        def falso(req, timeout=None):
            corpos.append(json.loads(req.data.decode()))
            if len(corpos) == 1:
                time.sleep(1.0)  # fornecedor preso: passa do prazo total
            class R(io.BytesIO):
                status = 200

                def __enter__(self):
                    return self

                def __exit__(self, *a):
                    return False
            return R(json.dumps({"choices": [{"message": {"content": "{\"a\": 1}"}}], "usage": {}}).encode())
        orig = (urllib.request.urlopen, RE.L._var_usuario, RE.L.OPENROUTER_PRAZO_S)
        urllib.request.urlopen, RE.L._var_usuario, RE.L.OPENROUTER_PRAZO_S = falso, (lambda n: "chave-de-teste"), 0.2
        try:
            r = RE.L._post_openrouter({"model": "d/x", **RE.L.OPENROUTER_ROTEAMENTO}, {}, 1800, dormir=lambda s: None)
        finally:
            urllib.request.urlopen, RE.L._var_usuario, RE.L.OPENROUTER_PRAZO_S = orig
        self.assertTrue(r["ok"])
        self.assertEqual(r["tentativas"], 2)
        self.assertIn("PrazoTotal", r["falhas_transporte"][0])
        self.assertEqual(corpos[0]["provider"]["sort"], "price")
        self.assertEqual(corpos[1]["provider"]["sort"], "throughput")
        self.assertLessEqual(corpos[1]["provider"]["max_price"]["completion"], 0.65)

    def test_402_nao_repete(self):
        r, n, _ = self._rodar([402])
        self.assertEqual(r["classe"], "limite")
        self.assertEqual(n, 1)


class CustoSemUsage(unittest.TestCase):
    """CUSTOSEMUSAGE1 (17/10): tentativa que estoura o prazo e cobrada sem usage; o orcamento tem de contar."""
    PRECO = {"input": 0.036, "output": 0.6435}

    def _post(self, respostas):
        fila = list(respostas)
        orig = (RE.L._urlopen_com_prazo, RE.L._var_usuario)
        RE.L._urlopen_com_prazo, RE.L._var_usuario = (lambda req, prazo: fila.pop(0)), (lambda n: "chave-de-teste")
        try:
            return RE.L._post_openrouter({"model": "m", "messages": [{"role": "user", "content": "x" * 3000}], "max_tokens": 16000},
                                         {}, 300, dormir=lambda s: None)
        finally:
            RE.L._urlopen_com_prazo, RE.L._var_usuario = orig

    def test_prazo_estourado_entra_no_custo(self):
        ok = json.dumps({"choices": [{"message": {"content": "{}"}}], "usage": {"prompt_tokens": 1000, "completion_tokens": 10, "cost": 0.001}})
        r = self._post([(0, "PrazoTotal"), (200, ok)])
        self.assertGreater(r["usage"]["sem_usage_input"], 1000)
        self.assertEqual(r["usage"]["sem_usage_output"], 16000)
        c = RE.custo_usd(r["usage"], self.PRECO)
        self.assertGreater(c, 0.001 + 16000 * 0.6435 / 1e6 - 1e-9)

    def test_sem_falha_custo_e_o_real(self):
        ok = json.dumps({"choices": [{"message": {"content": "{}"}}], "usage": {"prompt_tokens": 1000, "completion_tokens": 10, "cost": 0.001}})
        r = self._post([(200, ok)])
        self.assertEqual((r["usage"]["sem_usage_input"], r["usage"]["sem_usage_output"]), (0, 0))
        self.assertAlmostEqual(RE.custo_usd(r["usage"], self.PRECO), 0.001)

    def test_http_5xx_nao_estima(self):
        ok = json.dumps({"choices": [{"message": {"content": "{}"}}], "usage": {"prompt_tokens": 1, "completion_tokens": 1, "cost": 0.0001}})
        r = self._post([(502, "bad gateway"), (200, ok)])
        self.assertEqual(r["usage"]["sem_usage_output"], 0)


class CliPortoesSemArgumento(unittest.TestCase):
    def test_sem_etapa_devolve_uso(self):
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(RE.main(["portoes"]), 2)


if __name__ == "__main__":
    unittest.main()
