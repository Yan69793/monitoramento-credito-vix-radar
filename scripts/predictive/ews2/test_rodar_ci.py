"""Testes do orquestrador do GitHub Actions (rodar_ci.py). Mesmas duas pontas da rotina do Windows, sem rede: o POST ao Worker
e injetado e registra o que receberia."""
import argparse
import datetime as dt
import json
import os
import sys
import tempfile
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import conferencia as C  # noqa: E402
import rodar_ci as R  # noqa: E402

NOTA = "950c7b0404ff900877f161840ea0a601711860ba67baa4ae09f6e554900138c5"
HOJE = dt.date.today()
T = (HOJE - dt.timedelta(days=3)).isoformat()


def emissores(n=104):
    return [{"cnpj": "00.000.000/%04d-00" % i, "nome": "E%d" % i, "sinais": {"H1": i % 2, "H5": None, "H6": 0}, "prob_180d": None,
             "severidade": ["alta", "media", "baixa"][i % 3]} for i in range(n)]


def pacote(**extra):
    p = {"schema": "ews2/1", "protocolo": "G0-v4", "gerado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
         "data_observacao": T, "sha256_rotulos": "c" * 64, "homologacao": {"g1a": False, "g1b": False, "g1c": True, "g2": True, "g3": False},
         "liberacao": {"modo": "operacional_por_decisao_do_operador", "nota_sha256": NOTA}, "sinais_aprovados": ["H1", "H5", "H6"],
         "exibir_probabilidade": False, "emissores": emissores()}
    p.update(extra)
    return p


PADRAO = object()


class Falso:
    """Worker de mentira: registra os POSTs e responde como o real responderia."""

    def __init__(self, http=200, corpo=PADRAO):
        self.chamadas, self.http, self.corpo = [], http, corpo

    def __call__(self, url, corpo):
        self.chamadas.append((url, corpo))
        if self.corpo is not PADRAO:
            return self.http, self.corpo
        if corpo["action"] == "ews2_publicar":
            p = corpo["pacote"]
            return 200, {"ok": True, "gravado": True, "releitura_confere": True, "gerado_em": p["gerado_em"], "data_observacao": p["data_observacao"],
                         "emissores": len(p["emissores"]), "anterior": None}
        if corpo["action"] == "ews2_flag_desligar":
            return 200, {"ok": True, "flag": {"ativo": False}, "anterior": {"ativo": True}}
        return 404, None


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.livro = os.path.join(self.d, "livro")
        self.hist = os.path.join(self.d, "hist")
        os.makedirs(os.path.join(self.hist, T))
        self.addCleanup(self.tmp.cleanup)

    def escrever(self, nome, obj):
        f = os.path.join(self.d, nome)
        with open(f, "w", encoding="utf-8") as fh:
            json.dump(obj, fh)
        return f

    def args(self, pacote_arq, **kw):
        base = dict(publicar=False, T=T, api="https://api.exemplo.invalid", saida_dir=os.path.join(self.d, "saida"), backtest="x", backtest_sha256="x",
                    livro=self.livro, historico=self.hist, estado=os.path.join(self.d, "estado.json"), sem_download=True, sem_conferencia=True,
                    confirmacao_min_dias=0, dados_timeout=60, gerar_timeout=60, pacote_pronto=pacote_arq, eventos_json=None, hoje_conferencia=None)
        base.update(kw)
        return argparse.Namespace(**base)

    def historico(self, p, altos=()):
        """ews_score do EWS atual: 90 para os emissores dados, 0 para os demais."""
        j = {"emissores": [{"name": e["nome"], "features": {"ews_score": 90 if e["nome"] in altos else 0}} for e in p["emissores"]]}
        with open(os.path.join(self.hist, T, "predictive.json"), "w", encoding="utf-8") as fh:
            json.dump(j, fh)


class Portao(Base):
    def test_pacotes_ruins_saem_com_4_e_nada_e_enviado(self):
        ruins = {"nota errada": pacote(liberacao={"modo": "operacional_por_decisao_do_operador", "nota_sha256": "0" * 64}),
                 "schema errado": pacote(schema="ews2/0"), "103 emissores": pacote(emissores=emissores(103)),
                 "probabilidade": pacote(exibir_probabilidade=True),
                 "sinal fora do dominio": pacote(emissores=[dict(e, sinais={"H1": 2, "H5": None, "H6": 0}) if i == 0 else e for i, e in enumerate(emissores())]),
                 "data diferente de T": pacote(data_observacao=(HOJE - dt.timedelta(days=9)).isoformat())}
        for nome, p in ruins.items():
            post = Falso()
            cod, res = R.executar(self.args(self.escrever("p.json", p), publicar=True), post=post)
            self.assertEqual(cod, 4, nome + " " + str(res.get("motivo")))
            self.assertEqual(post.chamadas, [], nome)
        self.assertEqual(C.ler_livro(self.livro), [])

    def test_dry_run_valido_nao_envia_nem_registra(self):
        post = Falso()
        cod, res = R.executar(self.args(self.escrever("p.json", pacote())), post=post)
        self.assertEqual(cod, 0, res.get("motivo"))
        self.assertEqual(post.chamadas, [])
        self.assertEqual(C.ler_livro(self.livro), [])

    def test_publicar_valido_envia_uma_vez_e_registra_no_livro(self):
        p = pacote()
        self.historico(p)
        post = Falso()
        cod, res = R.executar(self.args(self.escrever("p.json", p), publicar=True), post=post)
        self.assertEqual(cod, 0, res.get("motivo"))
        self.assertEqual([c[1]["action"] for c in post.chamadas], ["ews2_publicar"])
        self.assertEqual(post.chamadas[0][1]["pacote"], p)
        self.assertNotIn("routine_key", post.chamadas[0][1])        # a chave e posta so dentro do curl, nunca montada aqui
        self.assertEqual(len(C.ler_livro(self.livro)), 1)

    def test_falhas_do_worker(self):
        p = pacote()
        arq = self.escrever("p.json", p)
        for post, esperado in ((Falso(400, {"ok": False, "erro": "pacote reprovado", "erros": ["x"]}), 5), (Falso(403, {"ok": False}), 5),
                               (Falso(200, {"ok": True, "releitura_confere": False}), 6), (Falso(200, None), 5)):
            cod, res = R.executar(self.args(arq, publicar=True), post=post)
            self.assertEqual(cod, esperado, str(res.get("motivo")))
        self.assertEqual(C.ler_livro(self.livro), [])               # pacote nao confirmado nao entra no livro

    def test_sem_chave_no_ambiente_recusa(self):
        antes = os.environ.pop("ROUTINE_API_KEY", None)
        try:
            cod, res = R.executar(self.args(self.escrever("p.json", pacote()), publicar=True))
            self.assertEqual(cod, 2)
        finally:
            if antes is not None:
                os.environ["ROUTINE_API_KEY"] = antes

    def test_backtest_com_hash_diferente_recusa(self):
        bt = self.escrever("bt.json", {"a": 1})
        cod, res = R.executar(self.args(None, backtest=bt, backtest_sha256="0" * 64, pacote_pronto=None), post=Falso())
        self.assertEqual(cod, 2)
        self.assertIn("sha256 do backtest", res["motivo"])


class Conferencia(Base):
    def rodar(self, p, eventos, post, **kw):
        ev = self.escrever("ev.json", eventos)
        return R.executar(self.args(self.escrever("p.json", p), publicar=True, sem_conferencia=False, eventos_json=ev,
                                    hoje_conferencia=(HOJE + dt.timedelta(days=300)).isoformat(), **kw), post=post)

    def eventos(self, emissores_):
        return [{"cnpj": e["cnpj"], "data": (dt.date.fromisoformat(T) + dt.timedelta(days=10 + 3 * i)).isoformat()} for i, e in enumerate(emissores_)]

    def test_desligar_exige_duas_rodadas_e_so_entao_posta_a_flag(self):
        p = pacote()
        baixas = [e for e in p["emissores"] if e["severidade"] == "baixa"][:6]
        self.historico(p, altos={e["nome"] for e in baixas})
        ev = self.eventos(baixas)
        post = Falso()
        cod, res = self.rodar(p, ev, post)
        self.assertEqual(cod, 14, res.get("motivo"))                 # 1a rodada so avisa
        self.assertEqual([c[1]["action"] for c in post.chamadas], ["ews2_publicar"])
        post2 = Falso()
        cod, res = self.rodar(p, ev, post2)
        self.assertEqual(cod, 9, res.get("motivo"))                  # 2a confirma e desliga
        self.assertEqual([c[1]["action"] for c in post2.chamadas], ["ews2_publicar", "ews2_flag_desligar"])
        self.assertTrue(res["flag_desligada"])
        self.assertNotIn("ativo", post2.chamadas[1][1])              # nao existe parametro para ligar

    def test_confirmacao_exige_tempo(self):
        p = pacote()
        baixas = [e for e in p["emissores"] if e["severidade"] == "baixa"][:6]
        self.historico(p, altos={e["nome"] for e in baixas})
        ev = self.eventos(baixas)
        for _ in range(2):
            post = Falso()
            cod, _res = self.rodar(p, ev, post, confirmacao_min_dias=30)
            self.assertEqual(cod, 14)
            self.assertNotIn("ews2_flag_desligar", [c[1]["action"] for c in post.chamadas])

    def test_ews2_melhor_mantem_e_amostra_pequena_nao_decide(self):
        p = pacote()
        altas = [e for e in p["emissores"] if e["severidade"] == "alta"][:6]
        self.historico(p)                                            # EWS atual zerado
        post = Falso()
        cod, res = self.rodar(p, self.eventos(altas), post)
        self.assertEqual((cod, res["conferencia"]["decisao"]), (0, "manter"))
        baixas = [e for e in p["emissores"] if e["severidade"] == "baixa"][:3]
        self.historico(p, altos={e["nome"] for e in baixas})
        post = Falso()
        cod, res = self.rodar(p, self.eventos(baixas), post)
        self.assertEqual((cod, res["conferencia"]["decisao"]), (0, "amostra_insuficiente"))
        self.assertNotIn("ews2_flag_desligar", [c[1]["action"] for c in post.chamadas])

    def test_veredito_desligar_em_dry_run_nao_envia_nada(self):
        p = pacote()
        baixas = [e for e in p["emissores"] if e["severidade"] == "baixa"][:6]
        self.historico(p, altos={e["nome"] for e in baixas})
        C.registrar(self.escrever("pp.json", p), self.livro, self.hist)       # livro ja tem o pacote de uma rodada publicada antes
        ev = self.escrever("ev.json", self.eventos(baixas))
        post = Falso()
        cod, res = R.executar(self.args(self.escrever("p.json", p), publicar=False, sem_conferencia=False, eventos_json=ev,
                                        hoje_conferencia=(HOJE + dt.timedelta(days=300)).isoformat()), post=post)
        self.assertEqual(cod, 0)
        self.assertEqual(post.chamadas, [])
        self.assertEqual(res["conferencia"]["decisao"], "desligar")

    def test_flag_que_nao_desliga_vira_13(self):
        p = pacote()
        baixas = [e for e in p["emissores"] if e["severidade"] == "baixa"][:6]
        self.historico(p, altos={e["nome"] for e in baixas})
        ev = self.eventos(baixas)
        self.rodar(p, ev, Falso())                                   # 1a rodada
        class Quebra(Falso):
            def __call__(self, url, corpo):
                if corpo["action"] == "ews2_flag_desligar":
                    return 500, {"ok": False}
                return super().__call__(url, corpo)
        cod, res = self.rodar(p, ev, Quebra())
        self.assertEqual(cod, 13)


class Curl(unittest.TestCase):
    def test_json_da_saida_pega_a_ultima_linha_json(self):
        self.assertEqual(R.json_da_saida("ruido\n{\"a\": 1}\nfim"), {"a": 1})
        self.assertIsNone(R.json_da_saida("sem json"))

    def test_corpo_do_curl_vai_por_arquivo_e_nao_na_linha_de_comando(self):
        vistos = {}

        def falso(argv, timeout, cwd=None):
            vistos["argv"] = argv
            arq = argv[argv.index("--data-binary") + 1][1:]
            vistos["corpo"] = json.load(open(arq, encoding="utf-8"))
            return 0, '{"ok": true}\n__HTTP=200', ""
        original = R.comando
        R.comando = falso
        try:
            http, j = R.postar_curl("https://x.invalid/", {"action": "ews2_estado"}, "SEGREDO-123")
        finally:
            R.comando = original
        self.assertEqual((http, j), (200, {"ok": True}))
        self.assertEqual(vistos["corpo"]["routine_key"], "SEGREDO-123")
        self.assertFalse(any("SEGREDO-123" in a for a in vistos["argv"]))


if __name__ == "__main__":
    unittest.main()
