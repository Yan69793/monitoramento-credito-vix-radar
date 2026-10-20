"""EVOLUCAO2B (VIX Intelligence Evolution, marco 2b): aprende com acertos e erros do EWS 2.0.

Le o relatorio da conferencia (conferencia.py conferir --relatorio) e deriva propostas para o livro de evolucao do Worker
(action evolucao_propor). Funcao pura, sem rede: quem envia e a rotina run_vixradar_ews2_pacote.ps1, e so com
VIXRADAR_EVOLUCAO_ENVIAR=1. Nenhuma proposta altera o EWS: todas nascem `proposta` e esperam aprovacao humana.

Regras (erro real, nunca palpite):
  omissao      evento independente em emissor que o EWS 2.0 marcava `baixa` no ultimo pacote antes do evento.
  ranking      3 ou mais eventos com diferenca de percentil e o EWS atual melhor na maioria: o EWS 2.0 ranqueou eventos
               reais abaixo do EWS atual. Complementa (nao substitui) o veredito desligar, que exige min_eventos e p_max.
Sem link https oficial do evento, nao ha proposta (o livro exige fonte).

Uso: python -I propor_evolucao.py --relatorio R.json [--mapa cnpj_emissores.json]   -> JSON {propostas: [...]}
"""
import argparse
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
MAPA = os.path.abspath(os.path.join(AQUI, "..", "cnpj_emissores.json"))
RANKING_MIN = 3


def nomes_por_cnpj(mapa):
    return {v.get("cnpj"): nome for nome, v in (mapa or {}).items() if isinstance(v, dict) and v.get("cnpj")}


def _links(linha):
    return [u for u in (linha.get("links") or []) if isinstance(u, str) and u.startswith("https://")][:5]


def derivar(relatorio, nomes=None):
    nomes = nomes or {}
    linhas = relatorio.get("eventos") or []
    out = []
    for l in sorted(linhas, key=lambda x: (x.get("inicio") or "", x.get("cnpj") or "")):
        if l.get("sev_ews2") != "baixa" or not _links(l):
            continue
        cnpj = l["cnpj"]
        nome = nomes.get(cnpj, cnpj)
        out.append({"tipo": "ews", "alvo": "ews2:" + cnpj,
                    "titulo": "EWS 2.0 sem alerta antes de evento de credito de %s" % nome,
                    "descricao": ("Evento independente em %s (%s) com inicio em %s; o pacote EWS 2.0 de %s classificava o emissor como baixa "
                                  "(percentil %.2f) e o EWS atual o colocava no percentil %.2f. Avaliar sinal ausente para este caso.")
                                 % (nome, cnpj, l.get("inicio"), l.get("pacote"), l.get("pct_ews2") or 0, l.get("pct_atual") or 0),
                    "fontes": _links(l)})
    com_dif = [l for l in linhas if abs((l.get("pct_atual") or 0) - (l.get("pct_ews2") or 0)) > 1e-9]
    atual_melhor = [l for l in com_dif if (l.get("pct_atual") or 0) > (l.get("pct_ews2") or 0)]
    fontes = []
    for l in atual_melhor:
        fontes.extend(u for u in _links(l) if u not in fontes)
    if len(com_dif) >= RANKING_MIN and len(atual_melhor) * 2 > len(com_dif) and fontes:
        out.append({"tipo": "ews", "alvo": "ews2:ranking",
                    "titulo": "EWS 2.0 ranqueou eventos reais abaixo do EWS atual",
                    "descricao": ("Em %d de %d eventos com diferenca, o EWS atual colocou o emissor acima do EWS 2.0 (percentil medio %s contra %s, "
                                  "p de sinal %s, veredito da conferencia: %s). Avaliar recalibracao dos sinais do EWS 2.0.")
                                 % (len(atual_melhor), len(com_dif), relatorio.get("pct_medio_atual"), relatorio.get("pct_medio_ews2"),
                                    relatorio.get("p_sinal"), relatorio.get("decisao")),
                    "fontes": fontes[:5]})
    return out


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--relatorio", required=True)
    ap.add_argument("--mapa", default=MAPA)
    a = ap.parse_args(argv)
    with open(a.relatorio, encoding="utf-8-sig") as fh:
        rel = json.load(fh)
    mapa = {}
    if os.path.exists(a.mapa):
        with open(a.mapa, encoding="utf-8-sig") as fh:
            mapa = json.load(fh)
    props = derivar(rel, nomes_por_cnpj(mapa))
    sys.stdout.write(json.dumps({"ok": True, "propostas": props}, ensure_ascii=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
