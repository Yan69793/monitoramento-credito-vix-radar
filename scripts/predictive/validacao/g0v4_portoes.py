"""G0-v4 / G1-v4 (nota 124): pre-registro, amostra cega, avaliacao contra referencia independente e portoes fail-closed.

Nada aqui altera G0-v3, o CSV legado, os executores antigos (rotular_etapa1.portoes continua fail-closed) ou producao.

Subcomandos:
  preregistrar   grava data/validacao/g0v4/preregistro_g0v4.json (recusa se ja existir ou se ja houver classificacao
                 oficial). Fixa versao e sha256 das regras, plano amostral, limiares e politica de adjudicacao.
  amostra        gera fila_revisao.csv (revisao obrigatoria) e amostra_cega.csv (nao_evento automatico, estratificada,
                 semente do pre-registro). A amostra cega NAO leva a classe G0-v4 nem a camada.
  avaliar        cobertura, rastreabilidade, integridade dos 150 legados, falsos negativos contra (a) eventos_v0/v0_1/v1
                 (referencia independente, pre-registrada) e (b) 150 legados (in-sample, declarado), grava relatorio.
  portoes        P1..P7; sai 0 so se G1-v4 aprova, senao 86.
"""
import collections
import csv
import datetime as dt
import hashlib
import json
import math
import os
import random
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_processar as PR  # noqa: E402
import g0v4_regras as RG  # noqa: E402

BASE = PR.BASE
VAL = os.path.join(BASE, "data", "validacao")
SAIDA = PR.SAIDA
PREREG = os.path.join(SAIDA, "preregistro_g0v4.json")
LEGADO = os.path.join(VAL, "rotulos_etapa1.csv")
EVENTOS_REF = [os.path.join(VAL, f) for f in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv")]
N_ITENS = 1261
EXIT_BLOQUEADO = 86

# hashes de 18/10/2026 01:11 (backup g0v4-pre-20261018-011151), conferidos por Get-FileHash
PRESERVADOS = {
    "data/validacao/rotulos_etapa1.csv": "e0cc7c63670b1817de0d6eac89bbd6ad201f4ddac56845d80b65953b68d6d22b",
    "data/validacao/rotulos_etapa1.claude-sonnet-5-5.parcial-20261016.csv": "c2e2795c3b9a9366862088182bb3eca01a2107f86642e5cb19d8ab167b892ac6",
    "scripts/predictive/validacao/guarda_g0v3.py": "fb6b3c8eabeeb738e68b62fbbfadc19525fff9617ca57bb9e9658e2465ddfc65",
    "scripts/predictive/validacao/recuperar_g0v3.py": "f0b7e40374ebac18ed13dc8d1adc8dd38f68306c8ee80065f48585f3056ce244",
    "scripts/predictive/validacao/rotular_etapa1.py": "cf8452403ebfd0c5d71770ffd7b1661d0327659889f7e7dfb7a549041b0b7b2c",
    "scripts/predictive/validacao/rotular_g0v3.py": "3e8f5a3da3b7d2e10db7f6a743a68e1c7f5b78ac4403544d1c30e916347e3205",
    "data/validacao/etapa1_g0v2/itens_cegos.json": "e0a8dec28af9b36720af7a63e4a4f35a149e86f2727c15f911f39864669aa813",
    "data/validacao/etapa1_g0v2/mapa_camadas.json": "4ef9b12624254277b8584e5be2acabef6305bb22b13a5f30a74544a592ba5a77",
}
N_LEGADOS = 150

PLANO = {
    "semente_amostra": 20261024,
    "estratos": "caminho de decisao do nao_evento automatico (sem_gatilho, so_hipotetico, standstill_sem_fato) x origem (uniao, F, W); "
                "a origem vem do mapa privado e so o amostrador a usa, nunca o classificador nem o revisor",
    "tamanho_por_estrato": "n_h = min(N_h, max(20, ceil(0.15 * N_h)))",
    "revisao_obrigatoria": "todo evento_proprio, continuacao, evento_terceiro, PENDENTE_REVISAO e todo nao_evento com motivo de revisao",
    "cegueira": "amostra_cega.csv leva so id, CNPJ e data; o revisor nao ve classe G0-v4, rotulo legado nem camada",
    "adjudicacao": "revisor independente (humano ou fornecedor autorizado pelo operador) decide pelo item 2 da G0-v3 e anexo G0-v2; "
                   "divergencia com o G0-v4 vai ao operador, cujo rotulo e final",
    "limiares": {
        "fn_material_referencia_independente": 0,
        "fn_material_amostra_cega_observado": 0,
        "fn_projetado_sup_975": "U (hipergeometrica, alfa 0,025 unilateral) de falsos negativos na populacao de nao_evento automatico <= piso(K/9), K do G1b com rotulo final",
        "erro_data_ep": "entre evento_proprio confirmados, >= 90% com data a ate 7 dias",
        "erro_entidade": "<= 10% dos positivos confirmados com titularidade trocada",
        "cobertura": 1.0, "rastreabilidade_material": 1.0,
    },
    "recall": "recall_auto = 1 - (FN ponderado N_h/n_h) / (positivos confirmados + FN ponderado); revocacao da uniao pelo G1b (g1b_v2) com rotulo final",
    "referencia_independente": "episodios de eventos_v0.csv, eventos_v0_1.csv e eventos_v1.csv (metodo e1, anterior ao G0-v4) cujo (CNPJ, data_evento) "
                               "coincide com (CNPJ, data) de um item: o G0-v4 nao pode deixar nenhum deles em nao_evento automatico",
    "ressalva_in_sample": "as regras v2 foram ajustadas depois de ver os 150 rotulos legados (v1 errava i0034 e i0065); a comparacao com os 150 "
                          "e in-sample e NAO conta como medida independente de falso negativo",
}


def sha256_arquivo(p):
    return PR.sha256_arquivo(p)


def regs_oficiais(saida=SAIDA):
    shar = PR.sha_regras()
    return {k[0]: r for k, r in PR.ler_feitos(os.path.join(saida, "classificacoes.jsonl")).items() if k[1] == RG.VERSAO and k[2] == shar}


def preregistrar(saida=SAIDA):
    os.makedirs(saida, exist_ok=True)
    p = os.path.join(saida, "preregistro_g0v4.json")
    if os.path.exists(p):
        print(json.dumps({"recusado": "pre-registro ja existe", "arquivo": p}))
        return 1
    if os.path.exists(os.path.join(saida, "classificacoes.jsonl")):
        print(json.dumps({"recusado": "ja ha classificacao oficial: pre-registro tem que vir antes"}))
        return 1
    reg = {"protocolo": "G0-v4", "versao_regras": RG.VERSAO, "sha256_regras": PR.sha_regras(),
           "sha256_processar": sha256_arquivo(os.path.join(AQUI, "g0v4_processar.py")),
           "registrado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "plano": PLANO,
           "preservados": PRESERVADOS, "estado": "rascunho tecnico, NAO homologado; homologacao e decisao do operador"}
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=1)
    print(json.dumps({"ok": True, "arquivo": p, "sha256": sha256_arquivo(p)}))
    return 0


def tam_estrato(N):
    return min(N, max(20, math.ceil(0.15 * N)))


def amostra(saida=SAIDA, etapa=PR.ETAPA):
    pre = json.load(open(os.path.join(saida, "preregistro_g0v4.json"), encoding="utf-8"))
    regs = regs_oficiais(saida)
    mapa = json.load(open(os.path.join(etapa, "mapa_camadas.json"), encoding="utf-8"))
    obrig = sorted(i for i, r in regs.items() if r["revisao_obrigatoria"])
    auto = [i for i, r in regs.items() if r["classe"] == "nao_evento" and not r["revisao_obrigatoria"]]
    estr = collections.defaultdict(list)
    for i in auto:
        o = mapa[i]["estrato"] or "uniao"
        estr[(regs[i]["caminho"], o)].append(i)
    rnd = random.Random(pre["plano"]["semente_amostra"])
    sorteio, desenho = [], []
    for k in sorted(estr):
        ids = sorted(estr[k])
        n = tam_estrato(len(ids))
        sel = sorted(rnd.sample(ids, n))
        sorteio += sel
        desenho.append({"caminho": k[0], "origem": k[1], "N": len(ids), "n": n})
    # itens que a referencia independente marca e o G0-v4 deixou em nao_evento automatico vao sempre a amostra cega
    itens_ref = json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))
    ref = referencia_independente()
    extra = [it["id"] for it in itens_ref if (it["cnpj"], it["data"]) in ref and it["id"] in auto and it["id"] not in sorteio]
    sorteio += extra
    desenho.append({"caminho": "referencia_independente", "origem": "qualquer", "N": len(extra), "n": len(extra)})
    with open(os.path.join(saida, "fila_revisao.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["id", "cnpj", "data", "classe_g0v4", "caminho", "motivos", "protocolo_evento", "trecho_evento", "origem_protocolo", "origem_trecho",
                    "decisao_revisor", "classe_final", "data_evento_final", "revisor", "revisado_em"])
        for i in obrig:
            r = regs[i]
            o = r.get("origem") or {}
            w.writerow([i, r["cnpj"], r["data"], r["classe"], r["caminho"], " | ".join(r["motivos_revisao"]), r.get("protocolo_evento") or "",
                        r.get("trecho_evento") or "", o.get("protocolo") or "", o.get("trecho") or "", "", "", "", "", ""])
    with open(os.path.join(saida, "amostra_cega.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter=";")
        w.writerow(["id", "cnpj", "data", "classe_final", "data_evento_final", "protocolo", "trecho", "revisor", "revisado_em"])
        for i in sorted(sorteio, key=lambda x: hashlib.sha256((x + "cego").encode()).hexdigest()):
            w.writerow([i, regs[i]["cnpj"], regs[i]["data"], "", "", "", "", "", ""])
    with open(os.path.join(saida, "desenho_amostral.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"estratos": desenho, "n_amostra": len(sorteio), "n_obrigatoria": len(obrig), "semente": pre["plano"]["semente_amostra"]}, fh, indent=1)
    print(json.dumps({"obrigatoria": len(obrig), "amostra_cega": len(sorteio), "estratos": desenho}, ensure_ascii=False))
    return 0


def referencia_independente():
    """(cnpj, data) de episodios dos metodos e1 (anteriores ao G0-v4)."""
    ref = {}
    for f in EVENTOS_REF:
        if not os.path.exists(f):
            continue
        with open(f, encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh, delimiter=";"):
                if r.get("cnpj") and r.get("data_evento"):
                    ref.setdefault((r["cnpj"], r["data_evento"]), []).append(os.path.basename(f))
    return ref


def legados():
    with open(LEGADO, encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh, delimiter=";"))


def avaliar(saida=SAIDA, etapa=PR.ETAPA):
    regs = regs_oficiais(saida)
    itens = json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))
    ids = [it["id"] for it in itens]
    integ = {k: sha256_arquivo(os.path.join(BASE, k)) == v for k, v in PRESERVADOS.items()}
    leg = legados()
    ref = referencia_independente()
    alvo_ref = [it for it in itens if (it["cnpj"], it["data"]) in ref]
    fn_ref = [it["id"] for it in alvo_ref if it["id"] in regs and regs[it["id"]]["classe"] == "nao_evento" and not regs[it["id"]]["revisao_obrigatoria"]]
    cobertura_ref = collections.Counter(regs[it["id"]]["classe"] for it in alvo_ref if it["id"] in regs)
    import g0v4_comparar as CP
    novo = {i: r for i, r in regs.items()}
    antigo = {r["id"]: r for r in leg}
    comp = CP.comparar(novo, antigo)
    material = [r for r in regs.values() if r["classe"] in ("evento_proprio", "continuacao", "evento_terceiro")]
    rel = {
        "gerado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "versao": RG.VERSAO, "sha256_regras": PR.sha_regras(),
        "sha256_preregistro": sha256_arquivo(os.path.join(saida, "preregistro_g0v4.json")) if os.path.exists(os.path.join(saida, "preregistro_g0v4.json")) else None,
        "sha256_classificacoes": sha256_arquivo(os.path.join(saida, "classificacoes.jsonl")) if os.path.exists(os.path.join(saida, "classificacoes.jsonl")) else None,
        "cobertura": {"itens_manifesto": len(ids), "classificados": sum(1 for i in ids if i in regs), "faltam": [i for i in ids if i not in regs][:50],
                      "pendentes_g0v3": sum(1 for i in ids if i not in antigo), "com_rotulo_legado": sum(1 for i in ids if i in antigo)},
        "classes": dict(collections.Counter(r["classe"] for r in regs.values())),
        "caminhos": dict(collections.Counter(r["caminho"] for r in regs.values())),
        "revisao_obrigatoria": sum(1 for r in regs.values() if r["revisao_obrigatoria"]),
        "nao_evento_automatico": sum(1 for r in regs.values() if r["classe"] == "nao_evento" and not r["revisao_obrigatoria"]),
        "rastreabilidade_material": {"n": len(material), "conferida": sum(1 for r in material if r["rastreabilidade"]["conferida"])},
        "eventos_identificados": {"evento_proprio": sum(1 for r in regs.values() if r["classe"] == "evento_proprio"),
                                  "continuacao": sum(1 for r in regs.values() if r["classe"] == "continuacao"),
                                  "adicionais": sum(len(r.get("adicionais") or []) for r in regs.values())},
        "integridade_preservados": integ, "legados": {"linhas": len(leg), "ids_unicos": len(antigo)},
        "referencia_independente": {"itens_com_episodio_e1": len(alvo_ref), "classes_g0v4": dict(cobertura_ref), "falsos_negativos": fn_ref},
        "legado_150_in_sample": comp,
    }
    with open(os.path.join(saida, "relatorio_g0v4.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(rel, fh, ensure_ascii=False, indent=1)
    print(json.dumps(rel, ensure_ascii=False, indent=1))
    return 0


def portoes(saida=SAIDA, etapa=PR.ETAPA):
    regs = regs_oficiais(saida)
    itens = json.load(open(os.path.join(etapa, "itens_cegos.json"), encoding="utf-8"))
    p = {}
    integ = {k: sha256_arquivo(os.path.join(BASE, k)) == v for k, v in PRESERVADOS.items()}
    leg = legados()
    p["P1_preservacao_g0v3"] = {"ok": all(integ.values()) and len(leg) == N_LEGADOS and len({r["id"] for r in leg}) == N_LEGADOS, "arquivos": integ}
    pre_p = os.path.join(saida, "preregistro_g0v4.json")
    pre = json.load(open(pre_p, encoding="utf-8")) if os.path.exists(pre_p) else None
    primeiro = min((r["processado_em"] for r in regs.values()), default=None)
    p["P2_preregistro"] = {"ok": bool(pre) and pre.get("sha256_regras") == PR.sha_regras() and bool(primeiro) and pre["registrado_em"] <= primeiro,
                           "registrado_em": (pre or {}).get("registrado_em"), "primeira_classificacao": primeiro}
    falt = [it["id"] for it in itens if it["id"] not in regs]
    p["P3_cobertura"] = {"ok": not falt and len(itens) == N_ITENS, "classificados": len(itens) - len(falt), "faltam": len(falt)}
    mat = [r for r in regs.values() if r["classe"] in ("evento_proprio", "continuacao", "evento_terceiro")]
    sem = [r["id"] for r in mat if not r["rastreabilidade"]["conferida"]]
    p["P4_rastreabilidade"] = {"ok": not sem, "materiais": len(mat), "sem_trecho_conferido": sem}
    fila = os.path.join(saida, "fila_revisao.csv")
    amo = os.path.join(saida, "amostra_cega.csv")

    def completos(f, col):
        if not os.path.exists(f):
            return None, None
        with open(f, encoding="utf-8-sig", newline="") as fh:
            rs = list(csv.DictReader(fh, delimiter=";"))
        return len(rs), sum(1 for r in rs if (r.get(col) or "").strip())
    nf, cf = completos(fila, "classe_final")
    na, ca = completos(amo, "classe_final")
    red = alvo_reduzido(saida)
    if red is None:
        p["P5_revisoes"] = {"ok": nf is not None and na is not None and nf == cf and na == ca, "obrigatorias": [nf, cf], "amostra_cega": [na, ca],
                            "motivo": "revisao independente obrigatoria e amostra cega ainda sem decisao" if not (nf == cf and na == ca) else None}
    else:
        feitos_rev = set()
        rp = os.path.join(saida, "revisoes_codex.jsonl")
        if os.path.exists(rp):
            for ln in open(rp, encoding="utf-8"):
                try:
                    feitos_rev.add(json.loads(ln)["id"])
                except (ValueError, KeyError):
                    pass
        faltam = [i for i in red if i not in feitos_rev]
        fp = os.path.join(saida, "rotulo_final_provisorio.csv")
        pend_op = None
        if os.path.exists(fp):
            with open(fp, encoding="utf-8-sig", newline="") as fh:
                pend_op = sum(1 for r in csv.DictReader(fh, delimiter=";") if not (r.get("classe_final") or "").strip())
        p["P5_revisoes"] = {"ok": not faltam and pend_op == 0, "modo": "reduzido (adendo do operador)", "alvo": len(red),
                            "sem_revisor": len(faltam), "itens_sem_classe_final": pend_op}
    ref = referencia_independente()
    fn_ref = [it["id"] for it in itens if (it["cnpj"], it["data"]) in ref and it["id"] in regs and regs[it["id"]]["classe"] == "nao_evento"
              and not regs[it["id"]]["revisao_obrigatoria"]]
    decid = {}
    if os.path.exists(amo):
        with open(amo, encoding="utf-8-sig", newline="") as fh:
            decid = {r["id"]: (r.get("classe_final") or "").strip() for r in csv.DictReader(fh, delimiter=";")}
    pend_ref = [i for i in fn_ref if i not in decid or not decid[i]]
    mat_ref = [i for i in fn_ref if decid.get(i) in ("evento_proprio", "continuacao")]
    p["P6_fn_referencia_independente"] = {"ok": not pend_ref and not mat_ref, "itens_marcados_pela_referencia": fn_ref,
                                          "sem_decisao_independente": pend_ref, "confirmados_como_falso_negativo": mat_ref}
    p["P7_limiares_pos_revisao"] = {"ok": False, "motivo": "dependem de P5 (FN da amostra, erro de data e de entidade, U <= piso(K/9))"} if not p["P5_revisoes"]["ok"] \
        else {"ok": False, "motivo": "calculo pos-revisao ainda nao implementado: exige fila e amostra adjudicadas"}
    p["G1_v4"] = {"ok": all(v["ok"] for k, v in p.items() if k.startswith("P")), "homologacao": "decisao do operador, nunca automatica"}
    print(json.dumps(p, ensure_ascii=False, indent=1))
    return 0 if p["G1_v4"]["ok"] else EXIT_BLOQUEADO


ADENDO = "adendo_reduzido_g0v4.json"
SEMENTE_POSITIVOS = 20261025


def adendo(saida=SAIDA, etapa=PR.ETAPA):
    """Decisao do operador em 18/10/2026: revisao 100% so do que o G0-v4 nao decidiu (PENDENTE_REVISAO e nao_evento com
    motivo de revisao); evento_proprio e continuacao com trecho conferido passam a amostra estratificada (relaxa o item 4
    da nota 124). Sorteio por semente, independente de qualquer resultado de revisao. Recusa se ja existir."""
    p = os.path.join(saida, ADENDO)
    if os.path.exists(p):
        print(json.dumps({"recusado": "adendo ja existe", "arquivo": p}))
        return 1
    regs = regs_oficiais(saida)
    pos = [i for i, r in regs.items() if r["classe"] in ("evento_proprio", "continuacao") and r["rastreabilidade"]["conferida"]]
    estr = collections.defaultdict(list)
    for i in pos:
        estr[(regs[i]["classe"], regs[i]["caminho"])].append(i)
    rnd = random.Random(SEMENTE_POSITIVOS)
    sel, desenho = [], []
    for k in sorted(estr):
        ids = sorted(estr[k])
        n = tam_estrato(len(ids))
        s = sorted(rnd.sample(ids, n))
        sel += s
        desenho.append({"classe": k[0], "caminho": k[1], "N": len(ids), "n": n})
    obrig = sorted(i for i, r in regs.items() if r["classe"] == "PENDENTE_REVISAO" or (r["classe"] == "nao_evento" and r["revisao_obrigatoria"]))
    ja = 0
    rp = os.path.join(saida, "revisoes_codex.jsonl")
    if os.path.exists(rp):
        ja = sum(1 for _ in open(rp, encoding="utf-8"))
    reg = {"decisao": "operador 18/10/2026: revisao reduzida. 100% de PENDENTE_REVISAO e nao_evento com motivo de revisao; amostra estratificada "
                      "de evento_proprio e continuacao com trecho conferido; amostra cega de nao_evento automatico mantida. Relaxa o item 4 da nota 124.",
           "registrado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "semente_positivos": SEMENTE_POSITIVOS,
           "tamanho_por_estrato": "n_h = min(N_h, max(20, ceil(0.15 * N_h)))", "estratos_positivos": desenho, "amostra_positivos": sel,
           "revisao_100pct": obrig, "n_revisao_100pct": len(obrig), "n_amostra_positivos": len(sel),
           "revisoes_ja_existentes_antes_do_adendo": ja,
           "consolidacao": "positivo nao sorteado fica com a classe do G0-v4 (fonte g0v4_positivo_nao_amostrado); a taxa de erro medida na amostra "
                           "de positivos e reportada por estrato e projetada com limite hipergeometrico",
           "sha256_preregistro_original": sha256_arquivo(os.path.join(saida, "preregistro_g0v4.json"))}
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=1)
    print(json.dumps({"ok": True, "n_revisao_100pct": len(obrig), "n_amostra_positivos": len(sel), "estratos": desenho, "sha256": sha256_arquivo(p)}, ensure_ascii=False))
    return 0


ADENDO2 = "adendo2_positivos_100pct.json"


def adendo2(saida=SAIDA, etapa=PR.ETAPA):
    """Decisao do operador em 18/10/2026 02:4x: depois da amostra de positivos reprovar (G0-v4 marca evento demais), todo
    evento_proprio e continuacao restante vai ao revisor. Recusa se ja existir."""
    p = os.path.join(saida, ADENDO2)
    if os.path.exists(p):
        print(json.dumps({"recusado": "adendo2 ja existe"}))
        return 1
    regs = regs_oficiais(saida)
    a = json.load(open(os.path.join(saida, ADENDO), encoding="utf-8"))
    ja = set(a["revisao_100pct"]) | set(a["amostra_positivos"])
    rest = sorted(i for i, r in regs.items() if r["classe"] in ("evento_proprio", "continuacao") and i not in ja)
    reg = {"decisao": "operador 18/10/2026: amostra de positivos reprovou (kappa 0,08; EP do documento do dia 17/20 discordantes); "
                      "revisao 100% dos positivos restantes pelo mesmo revisor (gpt-6-luna)",
           "registrado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "positivos_restantes": rest, "n": len(rest),
           "sha256_adendo1": sha256_arquivo(os.path.join(saida, ADENDO))}
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=1)
    print(json.dumps({"ok": True, "n": len(rest), "sha256": sha256_arquivo(p)}))
    return 0


def alvo_reduzido(saida=SAIDA):
    """Ids que o adendo manda revisar (100% + amostra de positivos) mais a amostra cega. None sem adendo."""
    p = os.path.join(saida, ADENDO)
    if not os.path.exists(p):
        return None
    a = json.load(open(p, encoding="utf-8"))
    ids = list(a["revisao_100pct"]) + list(a["amostra_positivos"])
    p2 = os.path.join(saida, ADENDO2)
    if os.path.exists(p2):
        ids += list(json.load(open(p2, encoding="utf-8"))["positivos_restantes"])
    amo = os.path.join(saida, "amostra_cega.csv")
    if os.path.exists(amo):
        with open(amo, encoding="utf-8-sig", newline="") as fh:
            ids += [r["id"] for r in csv.DictReader(fh, delimiter=";")]
    out, seen = [], set()
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    cmds = {"preregistrar": preregistrar, "amostra": amostra, "avaliar": avaliar, "portoes": portoes, "adendo": adendo, "adendo2": adendo2}
    if not argv or argv[0] not in cmds:
        print(__doc__)
        return 2
    saida = argv[argv.index("--saida") + 1] if "--saida" in argv else SAIDA
    return cmds[argv[0]](saida)


if __name__ == "__main__":
    sys.exit(main())
