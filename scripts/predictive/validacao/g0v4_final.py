"""G0-v4: consolida G0-v4 + revisor (Codex) em rotulo final PROVISORIO, lista divergencias para o operador e calcula as
metricas do P7 (nota 124 item 6) sobre o que ja tem decisao. Nada aqui e homologacao.

Regra de consolidacao (decisao do operador em 18/10: "divergencias vao para mim"):
  G0-v4 decidiu e revisor concorda               -> final = classe, fonte "concordancia"
  G0-v4 PENDENTE_REVISAO e revisor decidiu         -> final = revisor, fonte "revisor" (G0-v4 nao tinha decisao)
  revisor incerto, ou trecho do revisor nao confere -> OPERADOR
  G0-v4 decidiu e revisor discorda                 -> OPERADOR
  item da amostra cega (nao_evento automatico)     -> revisor nao_evento/evento_terceiro: concorda; material: FALSO NEGATIVO, OPERADOR
Saidas em data/validacao/g0v4/: rotulo_final_provisorio.csv, divergencias_operador.csv, metricas_p7.json.
Uso: python -I g0v4_final.py
"""
import collections
import csv
import datetime as dt
import json
import math
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_portoes as PT  # noqa: E402
import g0v4_processar as PR  # noqa: E402
from dimensionar_g1b import u_sup  # noqa: E402

MATERIAL = ("evento_proprio", "continuacao")
N_F, N_W, n_F, n_W = 402, 2505, 210, 540  # registro_entradas_g0v2_20261016.json e registro_sorteio.json
ALFA_ESTRATO = 0.0125


def data_valida(s):
    try:
        dt.date.fromisoformat(str(s)[:10])
        return len(str(s)) >= 10
    except (ValueError, TypeError):
        return False


def revisoes(saida):
    out = {}
    p = os.path.join(saida, "revisoes_codex.jsonl")
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            out.setdefault(d["id"], d)
    return out


def carregar_jsonl(p):
    out = {}
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            out.setdefault(d["id"], d)
    return out


MATERIAL_ADJ = ("evento_proprio", "continuacao")


def adj_valida(a, man_dia):
    """Adjudicacao do Luna que fecha o item: classe decidida, trecho (se houver) conferido, data utilizavel nos materiais."""
    if not a or a["classe"] == "incerto" or a.get("trecho_confere") is False:
        return None
    data = a.get("origem_data") if a["classe"] == "continuacao" else a.get("data_evento")
    if a["classe"] in MATERIAL_ADJ and not data_valida(data):
        if a["classe"] == "evento_proprio" and (a.get("protocolo") in man_dia):
            return {"classe": a["classe"], "data": "candidato"}
        return None
    return {"classe": a["classe"], "data": data}


def consolidar(regs, rev, amostra, reduzido=None, adj=None, arb=None, man=None):
    linhas, div = [], []
    for i in sorted(regs):
        r, d = regs[i], rev.get(i)
        g = r["classe"]
        alvo = (r["revisao_obrigatoria"] or i in amostra) if reduzido is None else (i in reduzido)
        if not alvo:
            fonte0 = "g0v4_positivo_nao_amostrado" if g in MATERIAL else "g0v4_automatico_nao_amostrado"
            linhas.append({"id": i, "classe_g0v4": g, "classe_revisor": "", "classe_final": g, "fonte": fonte0, "data_evento_final": r.get("data_evento") or ""})
            continue
        if not d:
            linhas.append({"id": i, "classe_g0v4": g, "classe_revisor": "", "classe_final": "", "fonte": "aguardando_revisor", "data_evento_final": ""})
            continue
        c = d["classe"]
        motivo = None
        if c == "incerto":
            motivo = "revisor incerto"
        elif d.get("trecho") and d.get("trecho_confere") is False:
            motivo = "trecho do revisor nao confere no documento"
        elif c in MATERIAL and g == "PENDENTE_REVISAO" and not data_valida(d.get("origem_data") if c == "continuacao" else d.get("data_evento")):
            motivo = "revisor marcou evento sem data AAAA-MM-DD valida (%r)" % d.get("data_evento")
        elif g == "PENDENTE_REVISAO":
            pass
        elif i in amostra and not r["revisao_obrigatoria"]:
            if c in MATERIAL:
                motivo = "FALSO NEGATIVO na amostra cega: G0-v4 nao_evento automatico, revisor %s" % c
        elif c != g:
            motivo = "G0-v4 %s, revisor %s" % (g, c)
        if motivo and adj is not None:
            arbd = (arb or {}).get(i)
            ajv = adj_valida(adj.get(i), man[i]["dia"]) if man else None
            if ajv:
                data_f = r["data"] if ajv["data"] == "candidato" else (ajv["data"] or "")
                linhas.append({"id": i, "classe_g0v4": g, "classe_revisor": c, "classe_final": ajv["classe"], "fonte": "adjudicacao_luna", "data_evento_final": data_f})
                continue
            if arbd:
                linhas.append({"id": i, "classe_g0v4": g, "classe_revisor": c, "classe_final": arbd["classe"], "fonte": arbd["fonte"], "data_evento_final": arbd.get("data") or ""})
                continue
            motivo = motivo + " | adjudicacao: " + ((adj.get(i) or {}).get("classe") or "ausente")
        if motivo:
            final, fonte = "", "OPERADOR"
            div.append({"id": i, "cnpj": r["cnpj"], "data": r["data"], "classe_g0v4": g, "classe_revisor": c, "motivo": motivo,
                        "g0v4_protocolo": r.get("protocolo_evento") or "", "g0v4_trecho": r.get("trecho_evento") or "",
                        "g0v4_origem": json.dumps(r.get("origem") or {}, ensure_ascii=False), "revisor_protocolo": d.get("protocolo") or "",
                        "revisor_trecho": d.get("trecho") or "", "revisor_justificativa": d.get("justificativa") or "",
                        "decisao_operador": "", "classe_final_operador": ""})
        else:
            final = c if g == "PENDENTE_REVISAO" or (i in amostra and not r["revisao_obrigatoria"]) else g
            fonte = "revisor" if g == "PENDENTE_REVISAO" else "concordancia"
        de = ((d.get("origem_data") if c == "continuacao" else d.get("data_evento")) if fonte == "revisor" else (((r.get("origem") or {}).get("data_entrega")) if g == "continuacao" else r.get("data_evento"))) or ""
        linhas.append({"id": i, "classe_g0v4": g, "classe_revisor": c, "classe_final": final, "fonte": fonte, "data_evento_final": de})
    return linhas, div


def metricas(regs, rev, amostra, linhas):
    # concordancia binaria (evento_proprio contra o resto) onde o G0-v4 decidiu
    pares = [(regs[i]["classe"], rev[i]["classe"]) for i in rev if i in regs and regs[i]["classe"] != "PENDENTE_REVISAO"]
    a = sum(1 for g, c in pares if (g == "evento_proprio") == (c == "evento_proprio"))
    po = a / len(pares) if pares else None
    pg = sum(1 for g, _ in pares if g == "evento_proprio") / len(pares) if pares else 0
    pc = sum(1 for _, c in pares if c == "evento_proprio") / len(pares) if pares else 0
    pe = pg * pc + (1 - pg) * (1 - pc)
    kappa = (po - pe) / (1 - pe) if pares and pe < 1 else None
    # datas entre evento_proprio confirmados pelos dois
    dd = []
    for i in rev:
        if i in regs and regs[i]["classe"] == "evento_proprio" and rev[i]["classe"] == "evento_proprio" and rev[i].get("data_evento") and regs[i].get("data_evento"):
            try:
                dd.append(abs((dt.date.fromisoformat(rev[i]["data_evento"]) - dt.date.fromisoformat(regs[i]["data_evento"])).days))
            except ValueError:
                pass
    ent = sum(1 for i in rev if i in regs and regs[i]["classe"] in MATERIAL and rev[i]["classe"] == "evento_terceiro")
    pos = sum(1 for i in rev if i in regs and regs[i]["classe"] in MATERIAL)
    # falso negativo na amostra cega e limite projetado na populacao de nao_evento automatico
    auto = [i for i, r in regs.items() if r["classe"] == "nao_evento" and not r["revisao_obrigatoria"]]
    am = [i for i in amostra if i in rev and i in auto]
    fn = [i for i in am if rev[i]["classe"] in MATERIAL]
    u_fn = u_sup(len(fn), len(am), len(auto), 0.025) if am else None
    # K provisorio: episodios da uniao com rotulo final material (escopo da regua de K NAO aplicado: K superestimado)
    mapa = json.load(open(os.path.join(PR.ETAPA, "mapa_camadas.json"), encoding="utf-8"))
    fin = {x["id"]: x for x in linhas}
    uni = [(regs[i]["cnpj"], fin[i]["data_evento_final"] if data_valida(fin[i]["data_evento_final"]) else regs[i]["data"]) for i in regs
           if mapa[i]["origem"] == "uniao" and fin[i]["classe_final"] in MATERIAL]
    por = collections.defaultdict(list)
    for c, d in uni:
        por[c].append(dt.date.fromisoformat(d[:10]))
    K = 0
    for c, ds in por.items():
        ds.sort()
        K += 1 + sum(1 for x, y in zip(ds, ds[1:]) if (y - x).days > 30)
    return {"pares_g0v4_decidiu": len(pares), "concordancia_binaria": po, "kappa_binario": kappa,
            "datas_ep_pares": len(dd), "datas_ep_ate_7_dias": (sum(1 for x in dd if x <= 7) / len(dd)) if dd else None,
            "erro_entidade": {"materiais_g0v4_revisados": pos, "revisor_diz_terceiro": ent, "taxa": (ent / pos) if pos else None},
            "amostra_cega": {"populacao_auto": len(auto), "revisados": len(am), "falsos_negativos": fn, "U_fn_sup_975": u_fn},
            "K_provisorio_sem_regua": K, "M_max_provisorio": math.floor(K / 9),
            "limites": {"fn_amostra": len(fn) == 0, "U_fn_le_Mmax": (u_fn is not None and u_fn <= math.floor(K / 9)),
                        "datas_90pct": (dd and sum(1 for x in dd if x <= 7) / len(dd) >= 0.9) or False,
                        "entidade_le_10pct": (pos and ent / pos <= 0.10) or False}}


def aplicar_regra_incerto(linhas):
    """Regra da G0-v3 item 2: o que a adjudicacao nao decide fica incerto (nao_evento na analise primaria, evento_proprio na de
    sensibilidade). Marca a fonte; nao inventa evidencia."""
    for x in linhas:
        if x["fonte"] == "OPERADOR" or (not x["classe_final"] and x["fonte"] == "aguardando_revisor"):
            x["classe_final"], x["fonte"] = "incerto", "regra_g0v3_incerto"
    return linhas


def g1b_provisorio(regs, rev, linhas, mapa, adj, man):
    """G1b provisorio com g1b_v2. SEM a regua de K (universo, janela, registro): todo evento conta, o que so aumenta K e
    tambem os perdidos. Item de G incerto conta como perdido. Nao e o G1b do protocolo."""
    import g1b_v2 as GB
    fin = {x["id"]: x for x in linhas}

    def item(i):
        c = fin[i]["classe_final"]
        r = regs[i]
        d = fin[i]["data_evento_final"]
        dd = dt.date.fromisoformat(d[:10]) if data_valida(d) else dt.date.fromisoformat(r["data"])
        it = {"cnpj": r["cnpj"], "classe": c if c != "evento_terceiro" else "nao_evento", "data": dt.date.fromisoformat(r["data"]),
              "data_evento": dd, "no_escopo": True, "adicionais": [], "divergente": False, "estrato": mapa[i]["estrato"]}
        if c == "continuacao":
            it["origens"] = [(None, dd, True)] if data_valida(d) else []
        return it
    uni = [item(i) for i in regs if mapa[i]["origem"] == "uniao"]
    G = [item(i) for i in regs if mapa[i]["origem"] == "G"]
    K, nos = GB.K_v2(uni)
    perd = GB.perdidos_v2(G, nos)
    tam = {"F": (402, 210), "W": (2505, 540)}
    x = GB.x_por_estrato_v2(perd, tam)
    ok, U, rev_ = GB.g1b_v2(K, x, tam)
    return {"K": K, "M_max": K // 9, "x_F": x["F"], "x_W": x["W"], "U_F_mais_U_W": U, "passa_provisorio": ok, "revocacao_uniao": rev_,
            "nota": "provisorio, sem regua de K; incerto de G conta como perdido; nao substitui o G1b do protocolo",
            "G_incertos": sum(1 for it in G if it["classe"] == "incerto"),
            "G_eventos": sum(1 for it in G if it["classe"] in ("evento_proprio", "continuacao"))}


def main(saida=PR.SAIDA):
    regs = PT.regs_oficiais(saida)
    rev = revisoes(saida)
    with open(os.path.join(saida, "amostra_cega.csv"), encoding="utf-8-sig", newline="") as fh:
        amostra = {r["id"] for r in csv.DictReader(fh, delimiter=";")}
    reduzido = PT.alvo_reduzido(saida)
    reduzido = set(reduzido) if reduzido is not None else None
    adj = carregar_jsonl(os.path.join(saida, "adjudicacoes_luna.jsonl"))
    arb = carregar_jsonl(os.path.join(saida, "arbitragem_claude.jsonl"))
    _itens, man, _meta, _prov = PR.carregar()
    linhas, div = consolidar(regs, rev, amostra, reduzido, adj if adj else None, arb, man)
    linhas = aplicar_regra_incerto(linhas)
    for nome, rows in (("rotulo_final_provisorio.csv", linhas), ("divergencias_operador.csv", div)):
        with open(os.path.join(saida, nome), "w", encoding="utf-8", newline="") as fh:
            if rows:
                w = csv.DictWriter(fh, fieldnames=list(rows[0]), delimiter=";")
                w.writeheader()
                w.writerows(rows)
    m = metricas(regs, rev, amostra, linhas)
    mapa = json.load(open(os.path.join(PR.ETAPA, "mapa_camadas.json"), encoding="utf-8"))
    try:
        m["g1b_provisorio"] = g1b_provisorio(regs, rev, linhas, mapa, adj, man)
    except Exception as e:  # noqa: BLE001
        m["g1b_provisorio"] = {"erro": "%s: %s" % (type(e).__name__, e)}
    ad = os.path.join(saida, PT.ADENDO)
    if os.path.exists(ad):
        a = json.load(open(ad, encoding="utf-8"))
        porest = []
        for e in a["estratos_positivos"]:
            ids = [i for i in a["amostra_positivos"] if regs[i]["classe"] == e["classe"] and regs[i]["caminho"] == e["caminho"]]
            rv = [i for i in ids if i in rev]
            err = [i for i in rv if rev[i]["classe"] != regs[i]["classe"] and rev[i]["classe"] != "incerto"]
            inc = [i for i in rv if rev[i]["classe"] == "incerto"]
            porest.append({**e, "revisados": len(rv), "discordam": len(err), "incertos": len(inc),
                           "U_erro_sup_975": u_sup(len(err) + len(inc), len(rv), e["N"], 0.025) if rv else None})
        m["amostra_positivos"] = porest
    m["fontes"] = dict(collections.Counter(x["fonte"] for x in linhas))
    m["classes_finais"] = dict(collections.Counter(x["classe_final"] or "(pendente)" for x in linhas))
    m["divergencias_por_motivo"] = dict(collections.Counter(d["motivo"].split(":")[0] if d["motivo"].startswith("FALSO") else
                                                            ("G0-v4 x revisor" if d["motivo"].startswith("G0-v4") else d["motivo"]) for d in div))
    m["gerado_em"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    json.dump(m, open(os.path.join(saida, "metricas_p7.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(m, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
