"""Somente leitura. Investiga as 331 chaves de S e os 11 casos de A2 da nota 116 antes de incorporar.

Para cada chave: duplicidade (mesmo CNPJ, cadeia de chaves a ate 30 dias, e chave com varios documentos),
relevancia pelo Assunto (classes deterministicas abaixo, so para triagem, nunca rotulo), prevalencia
(categoria (a) nos 24 meses antes, regra do item 3 da G0-v1) e distancia ate o episodio de E mais proximo.
Confere tambem que F e W nao mudam quando S e A2 entram na uniao de candidatos.
"""
import json, os, re, sys
from collections import Counter
from datetime import timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensionar_g1b as DG  # noqa: E402
import dimensionar_g1b_com_S as DS  # noqa: E402

AU, V0, V1 = DG.AU, DG.V0, DG.V1
# Classes de triagem, em ordem de precedencia. Nao substituem o rotulo do item 2.
CLASSES = [
    ("terceiro", r"\b(da|de sua|das) (controlad|subsidiari|investid|spe)\b|republic airways|athenabanco"
                 r"|da leader|da oi s\.?a|da light s\.?a|ciencia do pedido|nota da"),
    ("regulatorio", r"anatel|cade|procade|mapa\)|sinditelebrasil|fazenda publica|tutela de urgencia requerido"),
    ("clausula", r"alteracao (d[ae]|da redacao)|ajuste em clausula|clausula de vencimento antecipado|hipotese"
                 r"|consentimento previo|quorum|mudanca de controle|alteracao de controle|incorporacao|cisao"
                 r"|evento de vencimento antecipado|nao seja caracterizad"),
    ("abertura_propria", r"pedido de (recuperacao|autofalencia)|autofalencia|decretacao da falencia da companhia"
                         r"|sentenca (concessiva|de falencia)|ratificacao (do pedido|da decisao).{0,40}recuperacao"
                         r"|declaracao de inadimplemento|suspensao (do |dos )?pagamento"
                         r"|suspensao temporaria dos efeitos do vencimento antecipado|standstill"),
    ("falencia_requerida", r"(pedido|requerimento) de falencia|esclarecimento sobre.{0,30}falencia"),
    ("agd_vencimento", r"vencimento antecipado"),
]


def classe(textos):
    t = " || ".join(textos)
    for nome, rx in CLASSES:
        if re.search(rx, t):
            return nome
    return "outro"


def cadeias(chaves):
    """Agrupa chaves do mesmo CNPJ ligadas por intervalos de ate 30 dias."""
    por = {}
    for c, d in sorted(chaves, key=lambda k: (k[0], k[1])):
        por.setdefault(c, []).append(d)
    n = 0
    tam = Counter()
    for c, ds in por.items():
        g = 1
        for a, b in zip(ds, ds[1:]):
            if (b - a).days <= 30:
                g += 1
            else:
                tam[g] += 1
                n += 1
                g = 1
        tam[g] += 1
        n += 1
    return n, dict(sorted(tam.items()))


def main():
    F, W = DG.estratos()
    S = DS.estrato_S(F, W)
    E = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E |= {(c, d) for c, d, *_ in AU.ler_csv(os.path.join(AU.BASE, "data", "validacao", v))}
    docs, _ = V0.ler_ipe(AU.DIRS)
    cat_a_todas, por_chave = {}, {}
    for d in docs:
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a_todas.setdefault(d["cnpj"], []).append(d["data"])
        por_chave.setdefault((d["cnpj"], d["data"]), []).append(d)
    idxE = {}
    for c, dd in E:
        idxE.setdefault(c, []).append(dd)

    def prevalente(c, dd):
        return any(dd - timedelta(days=730) <= x < dd for x in cat_a_todas.get(c, []))

    def dist_E(c, dd):
        return min((abs((dd - x).days) for x in idxE.get(c, [])), default=None)

    def docs_alvo(k, so_a=False):
        return [x for x in por_chave.get(k, []) if (re.search(V1.RX_CAT_A, x["cat_n"]) if so_a else
                (not re.search(V1.RX_CAT_FR, x["cat_n"]) and not re.search(V1.RX_CAT_A, x["cat_n"])))]

    linhas = []
    for k in sorted(S, key=lambda k: k[1]):
        ds = docs_alvo(k)
        linhas.append({"cnpj": k[0], "data": k[1].isoformat(), "n_docs": len(ds),
                       "classe": classe([x["assunto_n"] for x in ds]),
                       "prevalente": prevalente(*k), "cnpj_com_E": k[0] in idxE, "dist_E": dist_E(*k),
                       "assunto": ds[0]["assunto"][:110] if ds else ""})
    n_cad, tam_cad = cadeias(S)
    cls = Counter(r["classe"] for r in linhas)
    cls_util = Counter(r["classe"] for r in linhas if not r["prevalente"])

    # A2: os 11 casos (9 documentos de abertura e 2 retomadas) recalculados aqui
    ML = DS.ML
    lac = json.loads(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "lacunas_nao_fr.json"),
                          "rb").read().decode("utf-8", "replace"))
    a2 = []
    retomada = {(r["cnpj"], r["data"]) for r in lac["L2_retomada_apos_silencio_cat_a_maior_365"]}
    # documentos de abertura da categoria (a) longe de tudo: refaz a selecao do medir_lacunas_nao_fr.py
    jan = [d for d in docs if AU.INI <= d["data"] <= AU.FIM]
    X, cat_a = set(), {}
    for d in jan:
        a = d["assunto_n"]
        if re.search(V1.RX_CAT_FR, d["cat_n"]) and re.search(V1.RX_FR_POS, a) and re.search(V1.RX_FR_EXCL, a):
            X.add((d["cnpj"], d["data"]))
        if re.search(V1.RX_CAT_A, d["cat_n"]):
            cat_a.setdefault(d["cnpj"], []).append(d["data"])
    cE = {c for c, _ in E}
    A1 = {(c, min(ds)) for c, ds in cat_a.items() if c not in cE}
    idx = {}
    for c, dd in E | X | A1 | set(F) | set(W):
        idx.setdefault(c, []).append(dd)
    cad = V0.ler_cad(os.path.join(AU.BASE, "data", "cvm", "cad_cia_aberta.csv"))
    abre = set()
    for d in jan:
        if not re.search(V1.RX_CAT_A, d["cat_n"]) or d["cnpj"] not in cE:
            continue
        if V0.periodo_vigente(cad.get(d["cnpj"], []), d["data"]) is None:
            continue
        if any(abs((d["data"] - x).days) <= 30 for x in idx.get(d["cnpj"], [])):
            continue
        a = d["assunto_n"]
        if a.strip() and re.search(V1.RX_A_ABRE, a) and not re.search(V1.RX_NAO_ABRE, a):
            abre.add((d["cnpj"], d["data"]))
    chaves_a2 = abre | {(c, V0.pdate(dd) if not hasattr(dd, "year") else dd) for c, dd in
                        ((c, __import__("datetime").date.fromisoformat(dd)) for c, dd in retomada)}
    for k in sorted(chaves_a2, key=lambda k: k[1]):
        ds = docs_alvo(k, so_a=True)
        antes = [x for x in idxE.get(k[0], []) if x <= k[1]]
        a2.append({"cnpj": k[0], "data": k[1].isoformat(), "n_docs_cat_a": len(ds),
                   "origem": "retomada" if (k[0], k[1].isoformat()) in retomada else "abertura",
                   "dias_desde_E_anterior": (k[1] - max(antes)).days if antes else None,
                   "prevalente": prevalente(*k), "assunto": ds[0]["assunto"][:110] if ds else ""})

    # F e W com S e A2 na uniao: recalcula a distancia de 30 dias
    novos = S | chaves_a2
    perto = [k for k in set(F) | set(W)
             if any(c == k[0] and abs((k[1] - dd).days) <= 30 for c, dd in novos)]
    print(json.dumps({
        "S": {"chaves": len(S), "cnpjs": len({c for c, _ in S}), "chaves_multi_doc": sum(1 for r in linhas if r["n_docs"] > 1),
              "cadeias_30d": n_cad, "tamanho_cadeias": tam_cad,
              "classes": dict(cls.most_common()), "classes_nao_prevalentes": dict(cls_util.most_common()),
              "prevalentes": sum(1 for r in linhas if r["prevalente"]),
              "cnpj_com_E": sum(1 for r in linhas if r["cnpj_com_E"]),
              "itens": linhas},
        "A2": {"chaves": len(chaves_a2), "itens": a2},
        "F_W_com_S_A2_na_uniao": {"chaves_de_G_a_30d_de_S_ou_A2": len(perto), "N_F": len(F), "N_W": len(W)},
    }, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    main()


def alcance():
    """Cadeias de S (span e ultima chave) e alcance: candidato de E, X, A ou F do mesmo CNPJ nos 180 dias
    seguintes (o rotulador desse candidato le os 180 dias anteriores inteiros)."""
    F, W = DG.estratos()
    S = DS.estrato_S(F, W)
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
    A1 = {(c, min(ds)) for c, ds in cat_a.items() if c not in cE}
    fortes = {}
    for c, dd in E | X | A1 | set(F):
        fortes.setdefault(c, []).append(dd)
    por = {}
    for c, d in sorted(S):
        por.setdefault(c, []).append(d)
    cad = []
    for c, ds in por.items():
        atual = [ds[0]]
        for b in ds[1:]:
            if (b - atual[-1]).days <= 30:
                atual.append(b)
            else:
                cad.append((c, atual))
                atual = [b]
        cad.append((c, atual))
    spans = [(ds[-1] - ds[0]).days for _, ds in cad]
    alc = sum(1 for c, ds in cad if any(0 < (x - ds[-1]).days <= 180 for x in fortes.get(c, [])))
    return {"cadeias": len(cad), "span_max_dias": max(spans), "cadeias_span_maior_180": sum(1 for s in spans if s > 180),
            "cadeias_alcancadas_por_candidato_em_180d": alc, "cadeias_sem_alcance": len(cad) - alc,
            "cnpjs_sem_alcance": len({c for c, ds in cad if not any(0 < (x - ds[-1]).days <= 180
                                                                      for x in fortes.get(c, []))})}



def uniao_candidatos():
    """Conta a uniao do item 1 revisado: E, X, A, ultima chave de cada cadeia de S, e A2."""
    j = json.loads(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "investigacao_S_A2.json"),
                        encoding="utf-8-sig").read())
    from datetime import date
    S = sorted((r["cnpj"], date.fromisoformat(r["data"])) for r in j["S"]["itens"])
    ult = []
    for i, (c, d) in enumerate(S):
        prox = S[i + 1] if i + 1 < len(S) else None
        if not (prox and prox[0] == c and (prox[1] - d).days <= 30):
            ult.append((c, d))
    A2 = {(r["cnpj"], date.fromisoformat(r["data"])) for r in j["A2"]["itens"]}
    E = set()
    for v in ("eventos_v0.csv", "eventos_v0_1.csv", "eventos_v1.csv"):
        E |= {(c, d) for c, d, *_ in AU.ler_csv(os.path.join(AU.BASE, "data", "validacao", v))}
    base = 293  # E, X e A, conferido em auditoria_g0v2.json (uniao)
    tudo = set(ult) | A2
    return {"S_ultima_da_cadeia": len(ult), "A2": len(A2), "S_A2_sobrepostos": len(set(ult) & A2),
            "S_A2_em_chave_de_E": len(tudo & E), "uniao_total": base + len(tudo)}
