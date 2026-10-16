"""Primeira etapa de rotulagem da G0-v2 (nota 116, item 1). Sem rede, sem rotulo.

Subcomandos:
  lista   SAIDA_DIR   gera a uniao (E, X, A, S ultima da cadeia, A2), sorteia as permutacoes de F e W com as
                      sementes congeladas (so se as listas ordenadas baterem com o registro de entradas),
                      toma os prefixos 210 e 540, embaralha os 1.261 itens para o rotulador nao saber a camada
                      e grava: itens_cegos.json (id opaco, cnpj, data), mapa_camadas.json (privado, nunca vai ao
                      rotulador), registro_sorteio.json (hashes). Recusa se SAIDA_DIR ja tiver esses arquivos.
  manifesto SAIDA_DIR monta, para cada item, os documentos do dia, os dos 180 dias anteriores e o indice de
                      24 meses (recuado ate chave anterior da uniao), e a lista unica de documentos a baixar.

Semente do embaralhamento cego: 20261020. Fica fora do bloco (o bloco so exige que o rotulador nao saiba a
camada) e e registrada aqui e no registro_sorteio.json antes do primeiro rotulo.
"""
import hashlib
import json
import os
import random
import re
import sys
from datetime import date, timedelta

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import dimensionar_g1b as DG  # noqa: E402
import dimensionar_g1b_com_S as DS  # noqa: E402
import reconciliar_511 as RC  # noqa: E402
import registrar_entradas_g0v2 as RE_  # noqa: E402

AU, V0, V1 = DG.AU, DG.V0, DG.V1
SEMENTE_F, SEMENTE_W, SEMENTE_CEGO = 20261017, 20261019, 20261020
PREFIXO_F, PREFIXO_W = 210, 540
REGISTRO = os.path.join(AU.BASE, "data", "validacao", "registro_entradas_g0v2_20261016.json")
CONTEXTO_DIAS = 180
INDICE_MESES = 24


def sha(txt):
    return hashlib.sha256(txt.encode("utf-8")).hexdigest()


def texto_chaves(chaves):
    return "".join("%s;%s\n" % (d.isoformat(), c) for c, d in chaves)


def camadas():
    F, W = DG.estratos()
    S_ult = RC.ultima_da_cadeia(DS.estrato_S(F, W))
    inv = json.load(open(os.path.join(AQUI, "investigacao_S_A2.json"), encoding="utf-8-sig"))
    A2 = {(r["cnpj"], date.fromisoformat(r["data"])) for r in inv["A2"]["itens"]}
    E = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E |= {(c, d) for c, d, *_ in AU.ler_csv(os.path.join(AU.BASE, "data", "validacao", v))}
    docs, _ = V0.ler_ipe(AU.DIRS)
    jan = [d for d in docs if AU.INI <= d["data"] <= AU.FIM]
    X, cat_a = set(), {}
    for d in jan:
        a = d["assunto_n"]
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(V1.RX_FR_POS, a) and re.search(V1.RX_FR_EXCL, a):
            X.add((d["cnpj"], d["data"]))
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a.setdefault(d["cnpj"], []).append(d["data"])
    cE = {c for c, _ in E}
    A = {(c, min(ds)) for c, ds in cat_a.items() if c not in cE}
    return {"E": E, "X": X, "A": A, "S": S_ult, "A2": A2}, F, W, docs


def cmd_lista(saida):
    os.makedirs(saida, exist_ok=True)
    alvos = [os.path.join(saida, n) for n in ("itens_cegos.json", "mapa_camadas.json", "registro_sorteio.json")]
    if any(os.path.exists(p) for p in alvos):
        print(json.dumps({"ok": False, "erro": "saida ja existe, sorteio nao se refaz"}))
        return 1
    reg = json.load(open(REGISTRO, encoding="utf-8"))
    cam, F, W, _ = camadas()
    lf, lw = RE_.lista_ordenada(F), RE_.lista_ordenada(W)
    if sha(lf) != reg["sha256_lista_F"] or sha(lw) != reg["sha256_lista_W"]:
        print(json.dumps({"ok": False, "erro": "lista regerada nao bate com o registro, nada e sorteado (item 5)"}))
        return 1
    uniao = set().union(*cam.values())
    contagem = {k: len(v) for k, v in cam.items()}
    contagem["uniao"] = len(uniao)
    esperado = {"E": 269, "X": 47, "A": 2, "S": 207, "A2": 11, "uniao": 511}
    if contagem != esperado:
        print(json.dumps({"ok": False, "erro": "contagem difere da nota 116", "obtido": contagem}))
        return 1
    ordF = sorted(F, key=lambda k: (k[1], k[0]))
    ordW = sorted(W, key=lambda k: (k[1], k[0]))
    permF, permW = list(ordF), list(ordW)
    random.Random(SEMENTE_F).shuffle(permF)
    random.Random(SEMENTE_W).shuffle(permW)
    prefF, prefW = permF[:PREFIXO_F], permW[:PREFIXO_W]
    origem = {}
    for nome, conj in cam.items():
        for k in conj:
            origem.setdefault(k, []).append(nome)
    for k in prefF:
        origem.setdefault(k, []).append("F")
    for k in prefW:
        origem.setdefault(k, []).append("W")
    if len(origem) != 511 + PREFIXO_F + PREFIXO_W:
        print(json.dumps({"ok": False, "erro": "prefixo de G cruza a uniao", "n": len(origem)}))
        return 1
    chaves = sorted(origem, key=lambda k: (k[1], k[0]))
    random.Random(SEMENTE_CEGO).shuffle(chaves)
    itens, mapa = [], {}
    for i, (c, d) in enumerate(chaves, 1):
        iid = "i%04d" % i
        itens.append({"id": iid, "cnpj": c, "data": d.isoformat()})
        camada = origem[(c, d)]
        mapa[iid] = {"camadas": camada, "origem": "G" if camada[0] in ("F", "W") else "uniao",
                     "estrato": camada[0] if camada[0] in ("F", "W") else None}
    registro = {
        "protocolo": "G0-v2", "etapa": 1, "registro_entradas": os.path.basename(REGISTRO),
        "sha256_lista_F": reg["sha256_lista_F"], "sha256_lista_W": reg["sha256_lista_W"],
        "semente_F": SEMENTE_F, "semente_W": SEMENTE_W, "semente_cego": SEMENTE_CEGO,
        "sha256_perm_F": sha(texto_chaves(permF)), "sha256_perm_W": sha(texto_chaves(permW)),
        "prefixo_F": PREFIXO_F, "prefixo_W": PREFIXO_W,
        "sha256_prefixo_F": sha(texto_chaves(prefF)), "sha256_prefixo_W": sha(texto_chaves(prefW)),
        "contagem": contagem, "n_itens": len(itens),
        "sha256_itens_cegos": sha(json.dumps(itens, ensure_ascii=False, sort_keys=True)),
        "sha256_mapa_camadas": sha(json.dumps(mapa, ensure_ascii=False, sort_keys=True)),
    }
    for p, obj in zip(alvos, (itens, mapa, registro)):
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=1, sort_keys=True)
            fh.write("\n")
    print(json.dumps({"ok": True, **{k: registro[k] for k in ("n_itens", "contagem", "sha256_perm_F", "sha256_perm_W")}},
                     ensure_ascii=False))
    return 0


def protocolo_rad(link):
    m = re.search(r"numProtocolo=(\d+)", link or "")
    return m.group(1) if m else None


def cmd_manifesto(saida):
    itens = json.load(open(os.path.join(saida, "itens_cegos.json"), encoding="utf-8"))
    _, _, _, docs = camadas()
    mapa = json.load(open(os.path.join(saida, "mapa_camadas.json"), encoding="utf-8"))
    uniao_por_cnpj = {}
    for it in itens:
        if mapa[it["id"]]["origem"] == "uniao":
            uniao_por_cnpj.setdefault(it["cnpj"], []).append(date.fromisoformat(it["data"]))
    por = {}
    for d in docs:
        por.setdefault(d["cnpj"], []).append(d)
    unicos = {}
    man = []
    for it in itens:
        c, dt = it["cnpj"], date.fromisoformat(it["data"])
        lst = por.get(c, [])
        ini_idx = dt - timedelta(days=int(INDICE_MESES * 30.4375))
        ant = [x for x in uniao_por_cnpj.get(c, []) if x < ini_idx]
        if ant:
            ini_idx = min(ini_idx, max(ant))
        dia = [x for x in lst if x["data"] == dt]
        ctx = [x for x in lst if dt - timedelta(days=CONTEXTO_DIAS) <= x["data"] < dt]
        idx = [x for x in lst if ini_idx <= x["data"] < dt - timedelta(days=CONTEXTO_DIAS)]

        def ref(x):
            p = protocolo_rad(x["link"])
            unicos.setdefault(p, {"protocolo_rad": p, "protocolo_entrega": x["protocolo"], "cnpj": x["cnpj"],
                                  "data_entrega": x["data"].isoformat(), "categoria": x["cat_n"],
                                  "assunto": x["assunto"], "link": x["link"]})
            return p
        man.append({"id": it["id"], "cnpj": c, "data": it["data"],
                    "dia": [ref(x) for x in dia], "contexto_180d": [ref(x) for x in ctx],
                    "indice_24m": [{"data": x["data"].isoformat(), "categoria": x["cat_n"], "assunto": x["assunto"],
                                    "protocolo_rad": protocolo_rad(x["link"]), "link": x["link"]} for x in idx],
                    "indice_inicio": ini_idx.isoformat()})
    sem_link = sum(1 for k in unicos if k is None)
    with open(os.path.join(saida, "manifesto_itens.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(man, fh, ensure_ascii=False, indent=0)
    with open(os.path.join(saida, "manifesto_documentos.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(sorted(unicos.values(), key=lambda u: (u["data_entrega"], u["cnpj"], str(u["protocolo_rad"]))),
                  fh, ensure_ascii=False, indent=0)
    print(json.dumps({"itens": len(man), "docs_unicos": len(unicos), "sem_link": sem_link,
                      "docs_dia": sum(len(m["dia"]) for m in man),
                      "leituras_contexto": sum(len(m["contexto_180d"]) for m in man),
                      "itens_sem_doc_no_dia": sum(1 for m in man if not m["dia"])}, ensure_ascii=False))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2 or argv[0] not in ("lista", "manifesto"):
        print(__doc__)
        return 2
    return cmd_lista(argv[1]) if argv[0] == "lista" else cmd_manifesto(argv[1])


if __name__ == "__main__":
    sys.exit(main())
