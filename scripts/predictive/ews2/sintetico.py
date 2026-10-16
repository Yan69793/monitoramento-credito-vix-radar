"""Gerador de dados SINTETICOS para exercitar o pipeline inteiro sem tocar em dado real (G0-v2 item 5). Determinista
por semente. Produz as mesmas estruturas que dados.py devolve: documentos IPE, cadastro, demonstrativos, rotulos.
O sinal H1 e plantado com efeito verdadeiro, o H4 sem efeito, para a prova de duas pontas do G2.
"""
import random
from datetime import date, timedelta


def gerar(semente=7, n_empresas=120, ini=date(2011, 1, 1), fim=date(2026, 9, 30), taxa_evento_ano=0.03):
    rng = random.Random(semente)
    docs, cad, dfp, rotulos = [], {}, {}, []
    setores = ["energia", "varejo", "saude", "transporte"]
    for i in range(n_empresas):
        c = "%02d.%03d.%03d/0001-%02d" % (i // 100, i % 1000, (i * 7) % 1000, i % 97)
        setor = setores[i % len(setores)]
        cad[c] = [{"dt_reg": date(2005, 1, 1), "dt_cancel": None, "motivo_cancel": "", "setor_ativ": setor, "sit_emissor": "ativo",
                   "denom_social": "EMPRESA %d S.A." % i, "denom_comerc": "", "cd_cvm": "%d" % (1000 + i)}]
        # DFP anual: entregue em marco (ou atrasada, 10%)
        versoes = []
        for ano in range(2010, 2026):
            atraso = rng.random() < 0.10
            receb = date(ano + 1, 3, 25) + (timedelta(days=rng.randint(5, 60)) if atraso else timedelta(0))
            at = rng.uniform(1e8, 5e9)
            pc, pnc = at * rng.uniform(0.1, 0.4), at * rng.uniform(0.1, 0.4)
            versoes.append({"cnpj": c, "dt_refer": date(ano, 12, 31), "versao": 1, "dt_receb": receb, "parecer_enfase": rng.random() < 0.05,
                            "parecer_tipo": "relatorio do auditor independente", "acoes": {"integralizadas": 1e8, "tesouraria": 0},
                            "contas": {"1": at, "1.01.01": at * rng.uniform(0.02, 0.15), "1.01.02": at * rng.uniform(0, 0.1), "2": at,
                                       "2.01": pc, "2.02": pnc, "2.01.04": pc * rng.uniform(0.1, 0.9), "6.01": at * rng.uniform(-0.02, 0.1)}})
        dfp[c] = versoes
        # documentos de rotina (silencio ocasional) e eventos
        d = ini
        eventos = []
        while d <= fim:
            if rng.random() < 0.25:
                docs.append({"cnpj": c, "nome_n": "empresa %d sa" % i, "cat_n": rng.choice(["comunicado ao mercado", "fato relevante", "aviso aos acionistas"]),
                             "tipo_n": "", "especie_n": "", "assunto_n": rng.choice(["resultado", "eleicao", "dividendos", "reuniao"]), "data": d, "protocolo": "", "link": ""})
            if rng.random() < taxa_evento_ano / 52 and not any(abs((d - e).days) < 400 for e in eventos):
                eventos.append(d)
            d += timedelta(days=7)
        for k, e in enumerate(eventos):
            # H1 verdadeiro: assembleia de debenturistas 30-150 dias antes do evento em 70% dos casos
            if rng.random() < 0.7:
                da = e - timedelta(days=rng.randint(30, 150))
                docs.append({"cnpj": c, "nome_n": "empresa %d sa" % i, "cat_n": "assembleia", "tipo_n": "agd", "especie_n": "",
                             "assunto_n": "assembleia de debenturistas", "data": da, "protocolo": "", "link": ""})
            docs.append({"cnpj": c, "nome_n": "empresa %d sa" % i, "cat_n": "fato relevante", "tipo_n": "", "especie_n": "",
                         "assunto_n": "pedido de recuperacao judicial", "data": e, "protocolo": "P%d%d" % (i, k), "link": ""})
            rotulos.append({"id": "s%04d_%d" % (i, k), "cnpj": c, "data": e.isoformat(), "origem": "uniao", "classe1": "evento_proprio",
                            "data_evento1": e.isoformat(), "protocolo": "P%d%d" % (i, k), "trecho": "pedido de recuperacao judicial",
                            "sha256_documento": "0" * 64, "data_download": "2026-10-16"})
        # H4 sem efeito: renuncias de CFO aleatorias, independentes de evento
        for _ in range(rng.randint(0, 4)):
            dr = ini + timedelta(days=rng.randint(0, (fim - ini).days))
            docs.append({"cnpj": c, "nome_n": "empresa %d sa" % i, "cat_n": "comunicado ao mercado", "tipo_n": "", "especie_n": "",
                         "assunto_n": "renuncia de diretor financeiro", "data": dr, "protocolo": "", "link": ""})
        # ruido de assembleia sem evento (para RR nao ser infinito)
        for _ in range(rng.randint(0, 3)):
            dr = ini + timedelta(days=rng.randint(0, (fim - ini).days))
            docs.append({"cnpj": c, "nome_n": "empresa %d sa" % i, "cat_n": "assembleia", "tipo_n": "agd", "especie_n": "",
                         "assunto_n": "assembleia de debenturistas", "data": dr, "protocolo": "", "link": ""})
    docs.sort(key=lambda d: (d["cnpj"], d["data"]))
    return {"docs": docs, "cad": cad, "dfp": dfp, "itr": {}, "rotulos": rotulos, "precos": {}, "selic": {}}
