"""Somente leitura. Volume da segunda leitura dos itens de G marcados nao_evento, continuacao ou evento_terceiro
(nota 116, decisoes de 15/10).

Teto: todo item rotulado de G cai numa das tres classes no primeiro rotulo (G e quase todo ruido). O teto
nao muda com a extensao de nao_evento para as tres classes, porque ja supunha todo item fora de evento_proprio.
Documentos pela media por chave medida em reconciliacao_511.json, n_F e n_W pela tabela de
dimensionamento_g1b.json. Contexto de 180 dias e soma por item, nao documento unico, e ja foi baixado
para o primeiro rotulo, entao nao gera download novo. Saida JSON em stdout.
"""
import json, os

AQUI = os.path.dirname(os.path.abspath(__file__))


def ler(n):
    return json.loads(open(os.path.join(AQUI, n), encoding="utf-8-sig").read())


def main():
    rec, dim = ler("reconciliacao_511.json"), ler("dimensionamento_g1b.json")
    vF, vW, vU = rec["volume"]["F"], rec["volume"]["W"], rec["volume"]["uniao"]

    def custo(nF, nW):
        return {"itens": nF + nW,
                "docs_no_dia": round(nF * vF["media_docs_no_dia"] + nW * vW["media_docs_no_dia"]),
                "leituras_contexto_180d": round(nF * vF["media_contexto_180d"] + nW * vW["media_contexto_180d"])}

    etapa1 = custo(210, 540)
    primeira_etapa1 = {"itens": vU["chaves"] + 750,
                       "leituras_contexto_180d": vU["docs_contexto_180d"] + etapa1["leituras_contexto_180d"]}
    por_K = {K: dict(custo(r["x0"]["n_F"], r["x0"]["n_W"]), n_F=r["x0"]["n_F"], n_W=r["x0"]["n_W"])
             for K, r in dim["dimensionamento"].items()}
    print(json.dumps({
        "etapa1_segunda_leitura_teto": etapa1,
        "etapa1_primeira_leitura_total": primeira_etapa1,
        "acrescimo_etapa1_pct_itens": round(100 * etapa1["itens"] / primeira_etapa1["itens"], 1),
        "acrescimo_etapa1_pct_contexto": round(100 * etapa1["leituras_contexto_180d"]
                                               / primeira_etapa1["leituras_contexto_180d"], 1),
        "total_por_K_x0": por_K,
    }, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
