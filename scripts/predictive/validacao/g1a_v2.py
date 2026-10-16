"""G1a da G0-v2 (nota 116, item 4): amostra de concordancia, kappa binario ponderado, IC95 bootstrap,
condicao de data e teto de `incerto`. Somente calculo, sem IO de rede e sem sinal. Nada aqui rotula.

Entradas (listas de dicts, uma por item rotulado):
  item: {"id", "cnpj", "data" (date, Data_Entrega da chave), "origem" ("uniao" ou "G"),
         "classe1", "data_evento1" (date ou None)}            primeiro rotulador, todos os itens
  segunda: {"id", "classe2", "data_evento2" (date ou None)}    segundo rotulador, so os sorteados

Regras fixadas pelo bloco congelado (sha256 5e91fe11...):
  amostra   60 itens, semente 20261018 + r (r = rodada, 0 na primeira): 40 da uniao por classe do primeiro
            rotulo (16 EP, 8 CT, 8 ET, 8 NE; classe com menos itens entra inteira, sobra vai para EP e depois
            NE) e 20 de G (todo EP ou incerto de G ate 10, sorteados se houver mais, resto sorteado entre os
            outros rotulados de G).
  kappa     binario, EP contra o resto (incerto = resto), peso N_s / n_s por estrato s = (origem, classe1).
  IC95      bootstrap estratificado, 1.000 reamostras, mesma semente, percentil 2,5 e 97,5.
  passa se  kappa >= 0,8 e limite inferior >= 0,6; data: entre os pares EP-EP, >= 90% a ate 7 dias, com menos
            de 12 pares "insuficiente" (entram mais 20 EP do primeiro rotulo, os seguintes na permutacao);
            incerto <= 5% dos rotulos do primeiro rotulador (todos, nao so a amostra).
Procedimento de sorteio (fixado aqui, fora do bloco, para a semente reproduzir): os itens de cada grupo sao
ordenados por (data, cnpj, id) antes de random.Random(semente).sample.
"""
import json
import random
from collections import Counter

EP, CT, ET, NE, INC = "evento_proprio", "continuacao", "evento_terceiro", "nao_evento", "incerto"
CLASSES = (EP, CT, ET, NE, INC)
COTAS = {EP: 16, CT: 8, ET: 8, NE: 8}
SEMENTE = 20261018
N_G = 20
N_G_EP_INC = 10
N_BOOT = 1000
KAPPA_MIN, KAPPA_LI_MIN = 0.8, 0.6
DATA_TOL_DIAS, DATA_FRAC_MIN, DATA_PARES_MIN, DATA_EXTENSAO = 7, 0.9, 12, 20
INCERTO_MAX = 0.05


def _ord(itens):
    return sorted(itens, key=lambda it: (it["data"], it["cnpj"], it["id"]))


def semente_rodada(r=0):
    return SEMENTE + r


def amostra_g1a(itens, rodada=0):
    """Devolve (ids_sorteados, detalhe). Determinista para (itens, rodada)."""
    rng = random.Random(semente_rodada(rodada))
    uniao = [it for it in itens if it["origem"] == "uniao"]
    G = [it for it in itens if it["origem"] == "G"]
    esc = []
    detalhe = {"uniao": {}, "G": {}}
    # 40 da uniao por cota de classe; classe curta entra inteira; sobra vai para EP, depois NE
    por = {c: _ord([it for it in uniao if it["classe1"] == c]) for c in COTAS}
    sobra = 0
    tomados = {}
    for c in (EP, CT, ET, NE):
        n = min(COTAS[c], len(por[c]))
        sobra += COTAS[c] - n
        tomados[c] = rng.sample(por[c], n) if n < len(por[c]) else list(por[c])
    for c in (EP, NE):
        if sobra <= 0:
            break
        resto = [it for it in por[c] if it not in tomados[c]]
        n = min(sobra, len(resto))
        if n:
            tomados[c] += rng.sample(resto, n) if n < len(resto) else resto
        sobra -= n
    for c in tomados:
        detalhe["uniao"][c] = len(tomados[c])
        esc += tomados[c]
    detalhe["uniao"]["nao_preenchido"] = sobra
    # 20 de G: EP ou incerto ate 10, resto sorteado entre os outros rotulados de G
    g_ep_inc = _ord([it for it in G if it["classe1"] in (EP, INC)])
    g_outros = _ord([it for it in G if it["classe1"] not in (EP, INC)])
    n1 = min(N_G_EP_INC, len(g_ep_inc))
    t1 = rng.sample(g_ep_inc, n1) if n1 < len(g_ep_inc) else list(g_ep_inc)
    n2 = min(N_G - n1, len(g_outros))
    t2 = rng.sample(g_outros, n2) if n2 < len(g_outros) else list(g_outros)
    detalhe["G"] = {"ep_ou_incerto": n1, "outros": n2, "nao_preenchido": N_G - n1 - n2}
    esc += t1 + t2
    return [it["id"] for it in esc], detalhe


def extensao_data(itens, ids_amostra, rodada=0):
    """Mais 20 EP do primeiro rotulo (uniao e G), os seguintes na mesma permutacao da semente, fora da amostra."""
    rng = random.Random(semente_rodada(rodada))
    ep = _ord([it for it in itens if it["classe1"] == EP])
    perm = list(ep)
    rng.shuffle(perm)
    ja = set(ids_amostra)
    return [it["id"] for it in perm if it["id"] not in ja][:DATA_EXTENSAO]


def pesos_estrato(itens, ids_amostra):
    """Peso N_s / n_s por estrato (origem, classe1). Devolve {id: peso}."""
    N = Counter((it["origem"], it["classe1"]) for it in itens)
    am = {it["id"]: it for it in itens if it["id"] in set(ids_amostra)}
    n = Counter((it["origem"], it["classe1"]) for it in am.values())
    return {i: N[(it["origem"], it["classe1"])] / n[(it["origem"], it["classe1"])] for i, it in am.items()}


def _bin(c):
    return 1 if c == EP else 0


def kappa_ponderado(pares, pesos, binario=True):
    """pares: lista de (id, classe1, classe2). Kappa de Cohen com peso por item (N_s/n_s)."""
    W = sum(pesos[i] for i, _, _ in pares)
    if W == 0:
        return float("nan")
    f = _bin if binario else (lambda c: c)
    po = sum(pesos[i] for i, a, b in pares if f(a) == f(b)) / W
    m1, m2 = Counter(), Counter()
    for i, a, b in pares:
        m1[f(a)] += pesos[i]
        m2[f(b)] += pesos[i]
    pe = sum(m1[c] * m2[c] for c in set(m1) | set(m2)) / (W * W)
    if pe == 1.0:
        return 1.0 if po == 1.0 else 0.0
    return (po - pe) / (1 - pe)


def ic_bootstrap(pares, pesos, estrato_de, rodada=0, n_boot=N_BOOT):
    """Reamostra com reposicao dentro de cada estrato, n_boot vezes. Percentil 2,5 e 97,5."""
    rng = random.Random(semente_rodada(rodada))
    por = {}
    for p in pares:
        por.setdefault(estrato_de[p[0]], []).append(p)
    ks = []
    for _ in range(n_boot):
        amostra = []
        for lista in por.values():
            amostra += [rng.choice(lista) for _ in lista]
        ks.append(kappa_ponderado(amostra, pesos))
    ks.sort()

    def pct(q):
        k = (len(ks) - 1) * q
        lo, hi = int(k), min(int(k) + 1, len(ks) - 1)
        return ks[lo] + (ks[hi] - ks[lo]) * (k - lo)
    return pct(0.025), pct(0.975)


def condicao_data(pares_data):
    """pares_data: lista de (classe1, classe2, data1, data2). So pares EP-EP contam."""
    epep = [(d1, d2) for a, b, d1, d2 in pares_data if a == EP and b == EP]
    n = len(epep)
    if n < DATA_PARES_MIN:
        return {"estado": "insuficiente", "pares": n, "fracao_7d": None, "passa": None,
                "acao": "acrescentar %d itens evento_proprio pela permutacao da semente" % DATA_EXTENSAO}
    ok = sum(1 for d1, d2 in epep if d1 is not None and d2 is not None and abs((d1 - d2).days) <= DATA_TOL_DIAS)
    fr = ok / n
    return {"estado": "medido", "pares": n, "fracao_7d": fr, "passa": fr >= DATA_FRAC_MIN}


def taxa_incerto(itens):
    n = len(itens)
    k = sum(1 for it in itens if it["classe1"] == INC)
    return {"incertos": k, "total": n, "taxa": (k / n if n else None), "passa": (k / n <= INCERTO_MAX) if n else None}


def matriz_confusao(pares):
    m = {a: {b: 0 for b in CLASSES} for a in CLASSES}
    for _, a, b in pares:
        m[a][b] += 1
    return m


def g1a(itens, segunda, rodada=0, n_boot=N_BOOT):
    """Calcula o G1a completo. Exige segunda leitura de todo item sorteado; senao devolve estado 'incompleto'."""
    ids, detalhe = amostra_g1a(itens, rodada)
    seg = {s["id"]: s for s in segunda}
    faltam = [i for i in ids if i not in seg]
    if faltam:
        return {"estado": "incompleto", "faltam_segunda_leitura": faltam, "amostra": ids, "detalhe_amostra": detalhe}
    por_id = {it["id"]: it for it in itens}
    pares = [(i, por_id[i]["classe1"], seg[i]["classe2"]) for i in ids]
    pesos = pesos_estrato(itens, ids)
    estrato_de = {i: (por_id[i]["origem"], por_id[i]["classe1"]) for i in ids}
    k = kappa_ponderado(pares, pesos)
    li, ls = ic_bootstrap(pares, pesos, estrato_de, rodada, n_boot)
    k4 = kappa_ponderado(pares, pesos, binario=False)
    data = condicao_data([(por_id[i]["classe1"], seg[i]["classe2"], por_id[i].get("data_evento1"),
                           seg[i].get("data_evento2")) for i in ids])
    inc = taxa_incerto(itens)
    cond_kappa = (k >= KAPPA_MIN) and (li >= KAPPA_LI_MIN)
    if data["estado"] == "insuficiente":
        veredito = "insuficiente_data"
        passa = None
    else:
        passa = bool(cond_kappa and data["passa"] and inc["passa"])
        veredito = "passa" if passa else "reprova"
    return {
        "estado": "calculado", "veredito": veredito, "passa": passa, "rodada": rodada, "semente": semente_rodada(rodada),
        "amostra": ids, "detalhe_amostra": detalhe, "n_amostra": len(ids),
        "kappa_binario_ponderado": k, "ic95": [li, ls], "condicao_kappa": cond_kappa,
        "kappa_4_classes": k4, "matriz_confusao": matriz_confusao(pares),
        "data": data, "incerto": inc,
        "discordancias": [i for i, a, b in pares if a != b],
        "extensao_data": extensao_data(itens, ids, rodada) if data["estado"] == "insuficiente" else [],
    }


def main(argv=None):
    """Uso: python -I g1a_v2.py primeiro.json segunda.json [rodada]. JSON com datas ISO. Sem argumento, so ajuda."""
    import sys
    from datetime import date
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        print(__doc__)
        return 2

    def d(s):
        return date.fromisoformat(s) if s else None
    with open(argv[0], encoding="utf-8-sig") as fh:
        itens = json.load(fh)
    with open(argv[1], encoding="utf-8-sig") as fh:
        segunda = json.load(fh)
    for it in itens:
        it["data"] = d(it["data"])
        it["data_evento1"] = d(it.get("data_evento1"))
    for s in segunda:
        s["data_evento2"] = d(s.get("data_evento2"))
    r = g1a(itens, segunda, int(argv[2]) if len(argv) > 2 else 0)
    print(json.dumps(r, ensure_ascii=False, indent=1, default=str))
    return 0 if r.get("passa") else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
