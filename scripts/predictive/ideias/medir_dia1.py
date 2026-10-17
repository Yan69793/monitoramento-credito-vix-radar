"""Dia 1: portoes de integridade temporal, disponibilidade historica e independencia de eventos.

Uso: python -I medir_dia1.py  -> grava data/validacao/poc-ideias/dia1/medicoes_dia1.json e imprime resumo.
"""
import collections
import gzip
import json
import os
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comum  # noqa: E402
from comum import EVENTOS_CREDITO, HISTORICO, RAW, SAIDA, digitos, emissores, gravar_json, pdata  # noqa: E402

import dados  # noqa: E402  (ews2)
import eventos as ev2  # noqa: E402  (ews2)

CLASSES_EVENTO = ("CRITICO",)  # premissa: evento de credito = classificacao CRITICO no rotulo


def ultimo_series_full():
    pastas = sorted(p for p in os.listdir(HISTORICO) if os.path.exists(os.path.join(HISTORICO, p, "series_full.json.gz")))
    return os.path.join(HISTORICO, pastas[-1], "series_full.json.gz")


def carregar_series(caminho):
    with gzip.open(caminho, "rt", encoding="utf-8") as fh:
        bruto = json.load(fh)
    out = {}
    for emp, regs in bruto.items():
        pts = sorted((pdata(r["data"]), r) for r in regs if r.get("fonte") == "anbima_publico" and pdata(r.get("data")))
        out[emp] = pts
    return out


def eventos_rotulados(mapa):
    out, sem_cnpj = [], collections.Counter()
    with open(EVENTOS_CREDITO, encoding="utf-8") as fh:
        for linha in fh:
            r = json.loads(linha)
            if (r.get("classificacao") or "").upper() not in CLASSES_EVENTO:
                continue
            c = mapa.get(r.get("empresa"))
            d = pdata(r.get("data_evento"))
            if not c:
                sem_cnpj[r.get("empresa")] += 1
                continue
            if d:
                out.append({"cnpj": c, "data": d, "tipo": ",".join(t for t in (r.get("tags") or []) if t), "empresa": r["empresa"]})
    return out, sem_cnpj


def main():
    mapa = emissores()
    por_cnpj = {c: e for e, c in mapa.items()}
    res = {"versao": "medir_dia1 v1", "gerado_em": date.today().isoformat()}

    # 1. Spread ANBIMA local
    sf = ultimo_series_full()
    series = carregar_series(sf)
    dias = {e: len(p) for e, p in series.items()}
    trocas = {e: sum(1 for a, b in zip(p, p[1:]) if a[1].get("n_papeis") != b[1].get("n_papeis")) for e, p in series.items()}
    todas = sorted({d for p in series.values() for d, _ in p})
    res["spread"] = {"arquivo": sf, "sha256": comum.sha256_arquivo(sf), "emissores": len(series),
                     "inicio": str(todas[0]) if todas else None, "fim": str(todas[-1]) if todas else None,
                     "dias_uteis_total": len(todas), "dias_por_emissor_min_med_max": [min(dias.values()), sorted(dias.values())[len(dias) // 2], max(dias.values())],
                     "emissores_com_120_dias": sum(1 for v in dias.values() if v >= 120),
                     "emissores_com_troca_de_composicao": sum(1 for v in trocas.values() if v > 0),
                     "trocas_de_composicao_mediana": sorted(trocas.values())[len(trocas) // 2],
                     "arquivo_publico_anbima_retencao": "medido 17/10: db260914..db261016 = 200, db260911 e anteriores = 404"}

    # 2. Eventos e episodios (regras do EWS 2.0)
    evs, sem = eventos_rotulados(mapa)
    docs, _ = dados.ler_ipe()
    docs_por = collections.defaultdict(list)
    alvo = set(mapa.values())
    for d in docs:
        c = digitos(d["cnpj"])
        if c in alvo:
            docs_por[c].append(d)
    eps = ev2.marcar_prevalencia(ev2.episodios(evs), docs_por)
    inc = [e for e in eps if not e["prevalente"]]

    def janela(lst, ini, fim):
        return [e for e in lst if ini <= e["inicio"] <= fim]
    ini_sp = todas[0] if todas else date.max
    res["eventos"] = {"fonte": EVENTOS_CREDITO, "sha256": comum.sha256_arquivo(EVENTOS_CREDITO), "classes": CLASSES_EVENTO,
                      "eventos": len(evs), "empresas_sem_cnpj": dict(sem), "episodios": len(eps), "incidentes": len(inc),
                      "data_max_rotulo": str(max(e["data"] for e in evs)),
                      "incidentes_na_janela_spread": [(por_cnpj[e["cnpj"]], str(e["inicio"])) for e in janela(inc, ini_sp, date(2026, 12, 31))],
                      "incidentes_na_janela_cda": [(por_cnpj[e["cnpj"]], str(e["inicio"])) for e in janela(inc, date(2025, 10, 1), date(2026, 12, 31))],
                      "prevalentes_na_janela_cda": [(por_cnpj[e["cnpj"]], str(e["inicio"])) for e in janela([e for e in eps if e["prevalente"]], date(2025, 10, 1), date(2026, 12, 31))]}

    # 3. ITR com DT_RECEB
    itr, meta = dados.ler_dfp(dirs=[os.path.join(RAW, "itr")], itr=True)
    cob = [c for c in alvo if c in {digitos(k) for k in itr}]
    itr_d = {digitos(k): v for k, v in itr.items()}
    sem_receb = sum(1 for v in itr.values() for x in v if not x["dt_receb"])
    res["itr"] = {"anos": meta["anos"], "companhias": len(itr), "emissores_alvo_cobertos": len(cob),
                  "versoes_sem_dt_receb": sem_receb,
                  "trimestres_por_emissor_mediana": sorted(len({x["dt_refer"] for x in itr_d[c]}) for c in cob)[len(cob) // 2] if cob else 0}

    # 4. Escrituras e relatorio de agente fiduciario no IPE local
    esc, af = collections.Counter(), collections.Counter()
    for c, lst in docs_por.items():
        for d in lst:
            if d["data"] < date(2022, 1, 1):
                continue
            txt = " ".join((d["cat_n"], d["tipo_n"], d["especie_n"], d["assunto_n"]))
            if "escritura" in txt:
                esc[por_cnpj[c]] += 1
            if "agente fiduciario" in txt:
                af[por_cnpj[c]] += 1
    res["escrituras"] = {"emissores_com_escritura_desde_2022": len(esc), "docs_escritura": sum(esc.values()),
                         "emissores_com_doc_agente_fiduciario": len(af), "top": esc.most_common(10)}

    gravar_json(os.path.join(SAIDA, "dia1", "medicoes_dia1.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    main()
