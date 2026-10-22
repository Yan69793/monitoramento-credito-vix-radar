"""Piloto local de monitoramento preventivo de divida liquida/EBITDA (automatico, sem revisao humana obrigatoria).

Para cada emissao com escritura e relatorio do agente fiduciario em data/validacao/poc-ideias/dia4/proveniencia_covenant.jsonl:
  1. Extrai o covenant da escritura (covenant.extrair_escritura). Ambiguidade (mais de um limite sem desempate documental,
     forma de gatilho sem confirmacao, limite diferente do agente) => NAO_CALCULAVEL, alerta bloqueado.
  2. Formula: definicao contratual congelada (dia6/definicoes_contratuais_v5.json) quando existe, senao formula padrao.
  3. Em cada data em que um ITR/DFP foi recebido pela CVM (DT_RECEB), recalcula com a versao vigente em T-1 (sem dado futuro).
  4. Confiabilidade so a partir da data de entrega do relatorio do agente: REPRODUZIVEL (>= 3 trimestres dentro de 5% e mesmo
     lado do limite), PARCIAL (sempre acima do agente, teto conservador) ou NAO_CALCULAVEL.
  5. Alertas: atencao, proximo do limite, deterioracao, rompimento ESTIMADO (nunca violacao) e violacao COMPROVADA so quando o
     proprio agente apurou o indice fora do limite. NAO_CALCULAVEL bloqueia o alerta.
Uso: python -I piloto_covenant.py   -> grava data/validacao/poc-ideias/piloto/*
"""
import json
import os
import re
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant as C  # noqa: E402
import covenant_contratual as K  # noqa: E402
import placar  # noqa: E402
from comum import SAIDA, emissores, gravar_json, pdata  # noqa: E402
from gerar_definicoes_v3 import CAIXA, D_BPP, DA, EBIT  # noqa: E402

PASTA = os.path.join(SAIDA, "piloto")
DEF = os.path.join(SAIDA, "dia6", "definicoes_contratuais_v5.json")
PROV = os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl")
IND = "divida_liquida/ebitda"
PRIORIDADE = ("Dasa", "Engie Brasil Energia", "Simpar")
PARAMS = {"tolerancia_pct": 5.0, "min_trimestres_validados": 3, "atencao": 0.25, "alerta": 0.10, "deterioracao_pp": 0.15,
          "inicio_janela": "2025-01-01", "status": "premissas do piloto, a confirmar pelo operador"}
REGRA_PADRAO = {"componentes": {"divida": D_BPP, "caixa": CAIXA, "ebitda": [EBIT, DA]}, "indices": {IND: "(divida - caixa) / ebitda"}}
MESES_FIM = {3: 31, 6: 30, 9: 30, 12: 31}


def viola(op, limite, v):
    return {"<": v >= limite, "<=": v > limite, ">": v <= limite, ">=": v < limite}[op]


def margem(op, limite, v):
    return round((limite - v) / limite if op.startswith("<") else (v - limite) / limite, 4)


# ---------- 1. covenant automatico ----------
def covenant_automatico(texto_esc, linhas_af, esc_meta, af_meta):
    ext = [c for c in C.extrair_escritura(texto_esc)] if texto_esc else []
    ext = [c for c in ext if c["indicador"] == IND]
    af = [t for t in linhas_af if t["apurado"] is not None and re.search(r"d.vida", t["indice"], re.I) and re.search(r"ebitda", t["indice"], re.I)
          and not re.search(r"patrim|ppi|bruta/", t["indice"], re.I)]
    af_lim = sorted({(t["operador"], t["limite"]) for t in af})
    base = {"indicador": IND, "escritura": esc_meta, "relatorio_af": af_meta, "limites_do_agente": af_lim}
    if not ext:
        return {**base, "status": "NAO_CALCULAVEL", "motivo": "nenhum covenant de divida liquida/EBITDA extraido da escritura"}
    candidatos = sorted({c["limite"] for c in ext} | {v for c in ext for _, v in c.get("step_down") or []})
    principal = ext[0]
    direcao = principal["operador"][0]
    if len(af_lim) > 1:
        return {**base, "status": "NAO_CALCULAVEL", "motivo": "o relatorio do agente traz mais de um limite para o indice", "candidatos": candidatos}
    if af_lim:
        op_af, lim_af = af_lim[0]
        if op_af[0] != direcao or lim_af not in candidatos:
            return {**base, "status": "NAO_CALCULAVEL", "motivo": "limite ou sentido da escritura difere do relatorio do agente",
                    "escritura_extraido": [principal["operador"], candidatos], "agente": af_lim[0]}
        precisa_agente = len(candidatos) > 1 or principal["forma_da_clausula"] == "gatilho"
        return {**base, "status": "ATIVO", "operador": op_af, "limite": lim_af, "candidatos_escritura": candidatos,
                "forma_da_clausula": principal["forma_da_clausula"], "linha_escritura": principal["linha"], "trecho": principal["trecho"],
                "confirmado_por_documento": "relatorio do agente fiduciario",
                "ativo_desde": af_meta["data_entrega"] if precisa_agente else esc_meta["data_entrega"],
                "motivo_ativacao": "degrau ou gatilho desempatado pelo agente" if precisa_agente else "limite unico na escritura, igual ao do agente"}
    if len(candidatos) > 1:
        return {**base, "status": "NAO_CALCULAVEL", "motivo": "mais de um limite na escritura e nenhum documento do agente para desempatar", "candidatos": candidatos}
    if principal["forma_da_clausula"] == "gatilho":
        return {**base, "status": "NAO_CALCULAVEL", "motivo": "clausula na forma de gatilho sem confirmacao documental"}
    return {**base, "status": "ATIVO", "operador": principal["operador"], "limite": principal["limite"], "candidatos_escritura": candidatos,
            "forma_da_clausula": principal["forma_da_clausula"], "linha_escritura": principal["linha"], "trecho": principal["trecho"],
            "confirmado_por_documento": None, "ativo_desde": esc_meta["data_entrega"], "motivo_ativacao": "limite unico na escritura, sem relatorio do agente"}


# ---------- 2. dados no tempo ----------
def carregar_versoes(cnpjs_por_base):
    versoes = {}
    for b, cnpjs in cnpjs_por_base.items():
        if cnpjs:
            versoes.update(K.ler_linhas(cnpjs, base=b, todas_versoes=True))
    return versoes


def foto(versoes, cnpj, ate):
    """Base no formato de covenant_contratual: (cnpj, ref) -> versao mais alta com DT_RECEB <= ate."""
    out = {}
    for (c, ref, v), r in versoes.items():
        if c != cnpj or not r["dt_receb"] or r["dt_receb"] > ate:
            continue
        if (c, ref) not in out or v > out[(c, ref)]["versao"]:
            out[(c, ref)] = r
    return out


def dois_trimestres_antes(ref):
    a, m = int(ref[:4]), int(ref[5:7]) - 6
    if m <= 0:
        a, m = a - 1, m + 12
    return "%d-%02d-%02d" % (a, m, MESES_FIM[m])


def ref_do_trimestre(t):
    return "%d-%02d-%02d" % (t["ano"], t["mes"], MESES_FIM[t["mes"]])


# ---------- 3. confiabilidade ----------
def confiabilidade(versoes, cnpj, regra, cov, linhas_af, af_data, as_of):
    """Classe valida em as_of. Usa so o relatorio do agente ja entregue (af_data <= as_of - 1) e a foto dos ITR na data dele."""
    if cov["status"] != "ATIVO":
        return "NAO_CALCULAVEL", cov["motivo"], []
    if not af_data or af_data > as_of - timedelta(days=1):
        return "NAO_CALCULAVEL", "sem relatorio do agente ja publicado para validar o calculo", []
    linhas = [t for t in linhas_af if t["apurado"] is not None and (t["operador"], t["limite"]) == (cov["operador"], cov["limite"])
              and re.search(r"d.vida", t["indice"], re.I) and re.search(r"ebitda", t["indice"], re.I)]
    por_tri = {}
    for t in linhas:
        por_tri.setdefault(ref_do_trimestre(t), set()).add(t["apurado"])
    if any(len(v) > 1 for v in por_tri.values()):
        return "NAO_CALCULAVEL", "relatorio do agente traz valores diferentes para o mesmo trimestre (mais de uma serie)", []
    linhas = list({ref_do_trimestre(t): t for t in linhas}.values())
    f = foto(versoes, cnpj, af_data.isoformat())
    comp = []
    for t in sorted(linhas, key=lambda x: (x["ano"], x["mes"])):
        ref = ref_do_trimestre(t)
        calc, _ = K.calcular(f, cnpj, ref, regra)
        v = calc.get(IND)
        if v is None:
            continue
        dif = 100 * (v - t["apurado"]) / t["apurado"]
        comp.append({"ref": ref, "apurado_agente": t["apurado"], "calculado": v, "dif_pct": round(dif, 1),
                     "mesmo_lado": viola(cov["operador"], cov["limite"], v) == viola(cov["operador"], cov["limite"], t["apurado"])})
    if len(comp) < PARAMS["min_trimestres_validados"]:
        return "NAO_CALCULAVEL", "menos de %d trimestres comparaveis com o agente" % PARAMS["min_trimestres_validados"], comp
    if not all(x["mesmo_lado"] for x in comp):
        return "NAO_CALCULAVEL", "calculo do lado oposto do limite em algum trimestre", comp
    dentro = sum(1 for x in comp if abs(x["dif_pct"]) <= PARAMS["tolerancia_pct"])
    if dentro >= PARAMS["min_trimestres_validados"]:
        return "REPRODUZIVEL", "%d de %d trimestres dentro de %.0f%% do agente" % (dentro, len(comp), PARAMS["tolerancia_pct"]), comp
    conservador = all((x["dif_pct"] >= 0) == cov["operador"].startswith("<") for x in comp)
    if conservador:
        return "PARCIAL", "calculo sempre do lado conservador do agente (%d de %d dentro de %.0f%%)" % (dentro, len(comp), PARAMS["tolerancia_pct"]), comp
    return "NAO_CALCULAVEL", "calculo diverge do agente sem direcao estavel", comp


# ---------- 4. historico e alertas ----------
def alertas_da_linha(linha, anterior2):
    m = linha["margem"]
    out = []
    if m is None:
        return out
    if m < 0 and linha["classe"] == "PARCIAL":
        out.append(("rompimento_possivel", "alerta", "teto conservador ESTIMADO alem do limite; a classe PARCIAL superestima a alavancagem, pode ser alarme falso"))
    elif m < 0:
        out.append(("rompimento_estimado", "critico", "indice ESTIMADO alem do limite; nao e violacao comprovada pelo agente"))
    elif m < PARAMS["alerta"]:
        out.append(("proximo_do_limite", "alerta", "margem estimada abaixo de %.0f%%" % (100 * PARAMS["alerta"])))
    elif m < PARAMS["atencao"]:
        out.append(("atencao", "atencao", "margem estimada abaixo de %.0f%%" % (100 * PARAMS["atencao"])))
    if anterior2 is not None and anterior2 - m >= PARAMS["deterioracao_pp"]:
        out.append(("deterioracao", "alerta", "margem caiu %.0f p.p. em dois trimestres" % (100 * (anterior2 - m))))
    return out


def monitorar(emp, cnpj, regra, formula, cov, versoes, linhas_af, af_meta, hoje):
    af_data = pdata(af_meta.get("data_entrega")) if af_meta else None
    eventos = sorted({(r["dt_receb"], ref, v) for (c, ref, v), r in versoes.items() if c == cnpj and r["dt_receb"] and r["dt_receb"] >= PARAMS["inicio_janela"]})
    historico, alertas = [], []
    margens_por_ref = {}
    for receb, ref, versao in eventos:
        as_of = pdata(receb) + timedelta(days=1)
        if as_of > hoje:
            continue
        f = foto(versoes, cnpj, receb)
        if f.get((cnpj, ref), {}).get("versao") != versao:
            continue  # existe versao mais nova ja recebida no mesmo dia
        calc, comp = K.calcular(f, cnpj, ref, regra) if cov["status"] == "ATIVO" else ({}, {})
        v = calc.get(IND)
        classe, motivo, validacao = confiabilidade(versoes, cnpj, regra, cov, linhas_af, af_data, as_of)
        ativo = cov["status"] == "ATIVO" and as_of > pdata(cov["ativo_desde"])
        if not ativo and cov["status"] == "ATIVO":
            classe, motivo = "NAO_CALCULAVEL", "covenant ainda nao ativo nesta data (%s)" % cov["ativo_desde"]
        m = margem(cov["operador"], cov["limite"], v) if (v is not None and cov["status"] == "ATIVO") else None
        publicavel = classe in ("REPRODUZIVEL", "PARCIAL")
        linha = {"emissor": emp, "emissao": cov["escritura"]["emissao"], "ref": ref, "versao": versao, "dt_receb_cvm": receb, "as_of": as_of.isoformat(),
                 "indicador": IND, "operador": cov.get("operador"), "limite": cov.get("limite"), "formula": formula,
                 "valor_estimado": v if publicavel else None, "margem": m if publicavel else None,
                 "diagnostico_valor_bloqueado": v if not publicavel else None,
                 "classe": classe, "motivo_classe": motivo, "natureza": "ESTIMATIVA do VIX Radar, nao e valor do agente fiduciario"}
        ant2 = None
        if publicavel:  # margem de dois trimestres antes, recalculada so com o que estava publicado nesta data
            calc_ant, _ = K.calcular(f, cnpj, dois_trimestres_antes(ref), regra)
            if calc_ant.get(IND) is not None:
                ant2 = margem(cov["operador"], cov["limite"], calc_ant[IND])
                linha["margem_dois_trimestres_antes"] = ant2
        if publicavel:
            for tipo, nivel, msg in alertas_da_linha(linha, ant2):
                alertas.append({"as_of": linha["as_of"], "emissor": emp, "emissao": linha["emissao"], "ref": ref, "tipo": tipo, "nivel": nivel,
                                "margem": m, "valor_estimado": v, "limite": cov["limite"], "operador": cov["operador"], "classe": classe,
                                "mensagem": msg + ("; PARCIAL: teto conservador" if classe == "PARCIAL" else ""),
                                "fontes": {"itr_dfp": {"ref": ref, "versao": versao, "dt_receb": receb},
                                           "escritura": {k: cov["escritura"].get(k) for k in ("protocolo", "data_entrega")}, "linha_escritura": cov.get("linha_escritura")}})
            margens_por_ref[ref] = m
        else:
            linha["alerta_bloqueado"] = True
        historico.append(linha)
    # violacao comprovada: o proprio agente apurou fora do limite (independe do calculo)
    for t in linhas_af:
        if t["apurado"] is None or not af_data or not re.search(r"d.vida", t["indice"], re.I) or not re.search(r"ebitda", t["indice"], re.I):
            continue
        if viola(t["operador"], t["limite"], t["apurado"]) and af_data + timedelta(days=1) <= hoje:
            alertas.append({"as_of": (af_data + timedelta(days=1)).isoformat(), "emissor": emp, "emissao": af_meta.get("emissao"), "ref": ref_do_trimestre(t),
                            "tipo": "violacao_comprovada_pelo_agente", "nivel": "critico", "apurado_agente": t["apurado"], "limite": t["limite"],
                            "operador": t["operador"], "classe": "DOCUMENTAL", "mensagem": "indice apurado pelo agente fora do limite",
                            "fontes": {"relatorio_af": {k: af_meta.get(k) for k in ("protocolo", "data_entrega", "link")}}})
    return historico, alertas


def main(hoje=None):
    hoje = hoje or date.today()
    regras = json.load(open(DEF, encoding="utf-8"))["emissores"]
    prov = [json.loads(l) for l in open(PROV, encoding="utf-8")]
    mapa = emissores()
    docs = {}
    for p in prov:
        docs.setdefault(p["emissor"], {})[p["papel"]] = p
    emps = [e for e in PRIORIDADE if e in docs] + sorted(e for e in docs if e not in PRIORIDADE)
    base_de = {e: regras.get(e, {}).get("base", "con") for e in emps}
    versoes = carregar_versoes({b: {mapa[e] for e in emps if e in mapa and base_de[e] == b} for b in ("con", "ind")})
    sem_con = [e for e in emps if e in mapa and base_de[e] == "con" and not any(c == mapa[e] and any(r["linhas"].values()) for (c, _, _), r in versoes.items())]
    if sem_con:  # emissor sem demonstrativo consolidado na CVM: usa o individual (fato do dado, registrado)
        versoes.update(K.ler_linhas({mapa[e] for e in sem_con}, base="ind", todas_versoes=True))
        for e in sem_con:
            base_de[e] = "ind (sem consolidado na CVM)"
    covs, hist, alertas = [], [], []
    for emp in emps:
        esc, af = docs[emp].get("escritura", {}), docs[emp].get("relatorio_af", {})
        texto_esc = open(esc["arquivo_txt"], encoding="utf-8", errors="ignore").read() if esc.get("arquivo_txt") else ""
        linhas_af = C.extrair_af(open(af["arquivo_txt"], encoding="utf-8", errors="ignore").read()) if af.get("arquivo_txt") else []
        meta = lambda d: {k: d.get(k) for k in ("protocolo", "link", "data_entrega", "emissao")}
        cov = covenant_automatico(texto_esc, linhas_af, meta(esc), meta(af) if af else {})
        cov["emissor"] = emp
        if emp in regras:
            regra, formula = regras[emp], "contratual congelada (v5)"
        else:
            regra, formula = REGRA_PADRAO, "padrao CVM (sem definicao contratual mapeada)"
        cov["formula"], cov["base"] = formula, base_de.get(emp)
        covs.append(cov)
        if emp not in mapa:
            continue
        h, a = monitorar(emp, mapa[emp], regra, formula, cov, versoes, linhas_af, meta(af) if af else {}, hoje)
        hist += h
        alertas += a
    alertas.sort(key=lambda x: (x["as_of"], x["emissor"], x["tipo"]))
    os.makedirs(PASTA, exist_ok=True)
    gravar_json(os.path.join(PASTA, "covenants.json"), {"parametros": PARAMS, "covenants": covs})
    gravar_json(os.path.join(PASTA, "historico.json"), hist)
    with open(os.path.join(PASTA, "alertas.jsonl"), "w", encoding="utf-8", newline="\n") as fh:
        for a in alertas:
            fh.write(json.dumps(a, ensure_ascii=False, sort_keys=True) + "\n")
    ledger = os.path.join(PASTA, "ledger_alertas.jsonl")
    if os.path.exists(ledger):
        os.remove(ledger)
    _, cabeca = placar.gravar(ledger, [os.path.join(PASTA, "alertas.jsonl")])
    with open(os.path.join(PASTA, "historico.csv"), "w", encoding="utf-8", newline="\n") as fh:
        cols = ["emissor", "emissao", "ref", "versao", "dt_receb_cvm", "as_of", "classe", "operador", "limite", "valor_estimado", "margem", "formula", "motivo_classe"]
        fh.write(";".join(cols) + "\n")
        for h in hist:
            fh.write(";".join("" if h.get(c) is None else str(h.get(c)) for c in cols) + "\n")
    resumo = {"hoje": hoje.isoformat(), "emissoes": len(covs), "ativos": sum(1 for c in covs if c["status"] == "ATIVO"),
              "nao_calculaveis_na_extracao": sum(1 for c in covs if c["status"] != "ATIVO"), "linhas_historico": len(hist),
              "linhas_publicaveis": sum(1 for h in hist if h["classe"] in ("REPRODUZIVEL", "PARCIAL")),
              "alertas": len(alertas), "ledger_cabeca": cabeca}
    gravar_json(os.path.join(PASTA, "resumo.json"), resumo)
    print(json.dumps(resumo, ensure_ascii=False, indent=1))
    return covs, hist, alertas


if __name__ == "__main__":
    main()
