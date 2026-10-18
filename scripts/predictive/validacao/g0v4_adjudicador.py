"""G0-v4: adjudicacao automatica das divergencias (decisao do operador em 18/10/2026: sem olho humano; Luna e Claude fecham).

Camada 1 (este script): Luna com contexto AMPLIADO. Para cada divergencia, o prompt traz o que o revisor viu mais o
G0-v4 (classe, trecho e motivo) e o texto do documento do dia ate 20.000 caracteres e, do contexto de 180 dias, os
documentos com disparo material anterior (ate 3, 3.000 caracteres cada). O adjudicador recebe as DUAS posicoes sem
saber qual e do G0-v4 e qual e do revisor (A e B, ordem sorteada por semente fixa) e decide pelo guia.
Camada 2 (arbitro final, fora deste script): o que a camada 1 deixar incerto ou sem trecho conferido e decidido por
leitura direta e gravado como arbitro:claude; sem evidencia, vale a regra da G0-v3 (incerto).

Saida so-acrescenta: data/validacao/g0v4/adjudicacoes_luna.jsonl. Execucao real exige --executar (mesmas travas do Codex).
Uso: VIXRADAR_ROTULADOR_CODEX_MODELO=gpt-6-luna python -I g0v4_adjudicador.py rodar [--lote 4] [--max-lotes N] [--executar]
"""
import csv
import datetime as dt
import json
import os
import random
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import g0v4_portoes as PT  # noqa: E402
import g0v4_processar as PR  # noqa: E402
import g0v4_regras as RG  # noqa: E402
import g0v4_revisor as RV  # noqa: E402
import llm_cli as L  # noqa: E402
import recuperar_g0v3 as R  # noqa: E402

DIA_MAX, CTX_MAX, CTX_DOCS = 12000, 2500, 3
SEMENTE = 20261026
ESQUEMA = {"type": "object", "properties": {"itens": {"type": "array", "items": {"type": "object", "properties": {
    "id": {"type": "string"}, "classe": {"type": "string", "enum": RV.CLASSES},
    "tipo": {"type": ["string", "null"]}, "data_evento": {"type": ["string", "null"]},
    "protocolo": {"type": ["string", "null"]}, "trecho": {"type": ["string", "null"]},
    "origem_protocolo": {"type": ["string", "null"]}, "origem_data": {"type": ["string", "null"]},
    "posicao_correta": {"type": "string", "enum": ["A", "B", "nenhuma"]},
    "confianca": {"type": "string", "enum": ["alta", "media", "baixa"]}, "justificativa": {"type": "string"}},
    "required": ["id", "classe", "posicao_correta", "confianca", "justificativa"]}}}, "required": ["itens"]}
SISTEMA = ("Voce e adjudicador de divergencias entre duas leituras de um mesmo candidato a evento de credito. Decide pelo guia e "
           "exclusivamente pelos documentos IPE fornecidos, do mesmo CNPJ e com Data_Entrega igual ou anterior a do candidato. "
           "As posicoes A e B nao tem ordem de confianca. Se nenhuma estiver certa, diga nenhuma e decida voce. Trecho citado e copia "
           "literal do documento fornecido, ate 30 palavras. Evidencia insuficiente: incerto. Responde somente no esquema JSON pedido.")


def posicao(classe, tipo, protocolo, trecho, justificativa, origem=None):
    s = "classe: %s" % classe
    if tipo:
        s += " | tipo: %s" % tipo
    if protocolo:
        s += " | protocolo %s" % protocolo
    if trecho:
        s += "\ntrecho: %s" % trecho
    if origem and origem.get("trecho"):
        s += "\norigem: protocolo %s, Data_Entrega %s, trecho: %s" % (origem.get("protocolo"), origem.get("data_entrega"), origem["trecho"])
    if justificativa:
        s += "\njustificativa: %s" % justificativa
    return s


def bloco(div, it, man_item, meta, reg, rev, textos):
    rnd = random.Random(SEMENTE + int(div["id"][1:]))
    pos = [("g0v4", posicao(reg["classe"], reg.get("tipo"), reg.get("protocolo_evento"), reg.get("trecho_evento"), "; ".join(reg["motivos_revisao"])[:300], reg.get("origem"))),
           ("revisor", posicao(rev["classe"], rev.get("tipo"), rev.get("protocolo"), rev.get("trecho"), rev.get("justificativa"),
                               {"protocolo": rev.get("origem_protocolo"), "data_entrega": rev.get("origem_data"), "trecho": None}))]
    rnd.shuffle(pos)
    L_ = ["### ITEM %s | CNPJ %s | Data_Entrega do candidato %s" % (it["id"], it["cnpj"], it["data"]), "POSICAO A:\n" + pos[0][1], "POSICAO B:\n" + pos[1][1]]
    for p in man_item["dia"]:
        t = textos(p)
        m = meta.get(p, {})
        if t and len(t.strip()) >= RG.MIN_TEXTO:
            corpo = R.limpa(t)
            extra = "" if len(corpo) <= DIA_MAX else "\n[CORTADO EM %d DE %d CARACTERES; ancoras do restante]\n%s" % (DIA_MAX, len(corpo), "\n".join(R.ancoras(corpo[DIA_MAX:], 6000)))
            L_.append("[documento do dia %s | %s | %s]\n%s%s" % (p, m.get("categoria"), m.get("assunto") or "(vazio)", corpo[:DIA_MAX], extra))
        else:
            L_.append("[documento do dia %s sem texto extraivel]" % p)
    vistos = []
    for h in sorted(reg.get("disparos_contexto", []), key=lambda h: (h.get("data_entrega") or "", h["pos"][0])):
        if h["protocolo"] in vistos or len(vistos) >= CTX_DOCS:
            continue
        vistos.append(h["protocolo"])
        t = textos(h["protocolo"])
        if t:
            L_.append("[documento anterior %s | Data_Entrega %s | inicio]\n%s" % (h["protocolo"], h.get("data_entrega"), R.limpa(t)[:CTX_MAX]))
    return "\n".join(L_)


def feitos(arq):
    out = set()
    if os.path.exists(arq):
        for ln in open(arq, encoding="utf-8"):
            try:
                out.add(json.loads(ln)["id"])
            except (ValueError, KeyError):
                pass
    return out


def rodar(lote=4, max_lotes=None, executar=False, saida=PR.SAIDA, docs=PR.DOCS, shard=None):
    with open(os.path.join(saida, "divergencias_operador.csv"), encoding="utf-8-sig", newline="") as fh:
        divs = list(csv.DictReader(fh, delimiter=";"))
    arq = os.path.join(saida, "adjudicacoes_luna.jsonl")
    cham = os.path.join(saida, "adjudicacoes_luna_chamadas.jsonl")
    ja = feitos(arq)
    for f in os.listdir(saida):
        if f.startswith("adjudicacoes_luna.shard") and f.endswith(".jsonl"):
            ja |= feitos(os.path.join(saida, f))
    pend = [d for d in divs if d["id"] not in ja]
    if shard:
        k, n = shard
        pend = [d for pos, d in enumerate(pend) if pos % n == k]
        arq = os.path.join(saida, "adjudicacoes_luna.shard%d.jsonl" % k)
        cham = os.path.join(saida, "adjudicacoes_luna_chamadas.shard%d.jsonl" % k)
    regs = PT.regs_oficiais(saida)
    rev = {}
    for ln in open(os.path.join(saida, "revisoes_codex.jsonl"), encoding="utf-8"):
        d = json.loads(ln)
        rev.setdefault(d["id"], d)
    itens, man, meta, _ = PR.carregar()
    por_id = {x["id"]: x for x in itens}
    g = RV.guia()
    modelo = L.modelo_codex()
    textos = PR.Textos(docs)
    print(json.dumps({"divergencias": len(divs), "pendentes": len(pend), "lote": lote, "executar": executar, "modelo": modelo}))
    n_lotes = 0
    for k in range(0, len(pend), lote):
        if max_lotes and n_lotes >= max_lotes:
            break
        grupo = pend[k:k + lote]
        blocos = [bloco(d, por_id[d["id"]], man[d["id"]], meta, regs[d["id"]], rev[d["id"]], textos) for d in grupo]
        prompt = RV.montar_prompt(g, blocos).replace("=== ITENS A DECIDIR (independentes entre si; um rotulo por item) ===",
                                                     "=== ITENS: DUAS POSICOES POR ITEM, DECIDA QUAL ESTA CERTA OU DIGA NENHUMA ===")
        r = L.chamar_codex(prompt, SISTEMA, ESQUEMA, modelo=modelo, executar=executar)
        if not executar:
            print(json.dumps({"dry_run": True, "ids": [d["id"] for d in grupo], "chars_prompt": r["chars_prompt"]}))
            n_lotes += 1
            continue
        with open(cham, "a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps({a: b for a, b in r.items() if a not in ("result", "structured")}, ensure_ascii=False, default=str) + "\n")
        dec = {d.get("id"): d for d in (r.get("structured") or {}).get("itens", []) if isinstance(d, dict)}
        if not r.get("ok") or not dec:
            print(json.dumps({"lote_falhou": [d["id"] for d in grupo], "classe": r.get("classe"), "erro": str(r.get("erro"))[:200]}))
            n_lotes += 1
            continue
        with open(arq, "a", encoding="utf-8", newline="\n") as fh:
            for d in grupo:
                x = dec.get(d["id"])
                if not x:
                    continue
                tr = x.get("trecho")
                ok = None
                if tr:
                    cand = [x.get("protocolo") or ""] + list(man[d["id"]]["dia"]) + [x.get("origem_protocolo") or ""] + \
                           [h["protocolo"] for h in regs[d["id"]].get("disparos_contexto", [])]
                    ok = any(RG.confere(tr, textos(p)) for p in cand if p)
                x.update({"adjudicador": "codex:%s" % modelo, "trecho_confere": ok, "adjudicado_em": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")})
                fh.write(json.dumps(x, ensure_ascii=False) + "\n")
        n_lotes += 1
        print(json.dumps({"lote": n_lotes, "itens": len(grupo)}), flush=True)
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    def opt(f, padrao=None):
        return argv[argv.index(f) + 1] if f in argv else padrao
    if not argv or argv[0] not in ("rodar", "unir"):
        print(__doc__)
        return 2
    if argv[0] == "unir":
        return unir()
    sh = opt("--shard")
    shard = (int(sh.split("/")[0]), int(sh.split("/")[1])) if sh else None
    return rodar(int(opt("--lote", 4)), int(opt("--max-lotes", 0)) or None, "--executar" in argv, shard=shard)


def unir(saida=PR.SAIDA):
    arq = os.path.join(saida, "adjudicacoes_luna.jsonl")
    ja = feitos(arq)
    n = 0
    for f in sorted(os.listdir(saida)):
        if f.startswith("adjudicacoes_luna.shard") and f.endswith(".jsonl"):
            p = os.path.join(saida, f)
            with open(arq, "a", encoding="utf-8", newline="\n") as out:
                for ln in open(p, encoding="utf-8"):
                    try:
                        d = json.loads(ln)
                    except ValueError:
                        continue
                    if d["id"] not in ja:
                        out.write(json.dumps(d, ensure_ascii=False) + "\n")
                        ja.add(d["id"])
                        n += 1
            os.replace(p, p + ".unido")
    print(json.dumps({"unidos": n}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
