"""Margem de covenant pela definicao CONTRATUAL (regras congeladas em data/validacao/poc-ideias/dia6/definicoes_contratuais.json).

Para cada emissor e trimestre: aplica as regras sobre as contas consolidadas da CVM (ITR/DFP, versao vigente), calcula LTM dos
fluxos, compara com o apurado do agente fiduciario e mede a margem ate o limite com a data em que o dado ficou publico (DT_RECEB).
"""
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, SAIDA, digitos, emissores, gravar_json, pdata  # noqa: E402

import dados  # noqa: E402

DEF = os.path.join(SAIDA, "dia6", "definicoes_contratuais.json")
DEMS = {"BPA": "BPA_con", "BPP": "BPP_con", "DRE": "DRE_con", "DFC": "DFC_MI_con"}
FLUXO = {"DRE", "DFC"}
TOL = 5.0


def ler_linhas(cnpjs, anos=("2023", "2024", "2025", "2026"), base="con", todas_versoes=False):
    """{(cnpj, dt_refer): {"dt_receb", "versao", "tipo", "linhas": {dem: [(cd, ds_norm, valor)]}}}, versao mais alta.
    Com todas_versoes=True a chave vira (cnpj, dt_refer, versao), para escolher a versao vigente em cada data."""
    alvo = set(cnpjs)
    out = {}
    for tipo, pref, dirs in (("ITR", "itr_cia_aberta_", [os.path.join(RAW, "itr")]), ("DFP", "dfp_cia_aberta_", dados.DIRS_DFP)):
        for ano, z in sorted(dados._zips(dirs, pref).items()):
            if ano not in anos:
                continue
            cab = {}
            for r in dados._csv_do_zip(z, "%s%s.csv" % (pref, ano)):
                c = digitos(r["CNPJ_CIA"])
                if c in alvo:
                    k, v = (c, r["DT_REFER"]), int(r["VERSAO"] or 0)
                    if todas_versoes:
                        k = (c, r["DT_REFER"], v)
                        cab[k] = {"versao": v, "dt_receb": r["DT_RECEB"], "tipo": tipo, "linhas": {d: [] for d in DEMS}}
                    elif k not in cab or v > cab[k]["versao"]:
                        cab[k] = {"versao": v, "dt_receb": r["DT_RECEB"], "tipo": tipo, "linhas": {d: [] for d in DEMS}}
            for curto, dem in DEMS.items():
                for r in dados._csv_do_zip(z, "%s%s_%s.csv" % (pref, dem.replace("_con", "_" + base), ano)):
                    c = digitos(r["CNPJ_CIA"])
                    k = (c, r["DT_REFER"], int(r["VERSAO"] or 0)) if todas_versoes else (c, r["DT_REFER"])
                    if k not in cab or int(r["VERSAO"] or 0) != cab[k]["versao"]:
                        continue
                    if r.get("ORDEM_EXERC", "").upper() not in ("ÚLTIMO", "ULTIMO"):
                        continue
                    if curto in FLUXO and not r.get("DT_INI_EXERC", "").endswith("-01-01"):
                        continue
                    esc = 1000.0 if dados.norm(r.get("ESCALA_MOEDA", "")) == "mil" else 1.0
                    try:
                        val = float(r["VL_CONTA"].replace(",", ".")) * esc
                    except ValueError:
                        continue
                    cab[k]["linhas"][curto].append((r["CD_CONTA"], dados.norm(r.get("DS_CONTA", "")), val))
            out.update(cab)
    return out


def termo(linhas, t):
    """Soma das contas que casam o termo, so as mais profundas quando pai e filha casam. Devolve (valor, contas)."""
    cands = [(cd, ds, v) for cd, ds, v in linhas.get(t["dem"], []) if re.search(t["cd"], cd)
             and (not t.get("ds") or re.search(t["ds"], ds)) and not (t.get("nao") and re.search(t["nao"], ds))]
    codigos = {cd for cd, _, _ in cands}
    folhas = [(cd, ds, v) for cd, ds, v in cands if not any(o != cd and o.startswith(cd + ".") for o in codigos)]
    return t["s"] * sum(v for _, _, v in folhas), [cd for cd, _, _ in folhas]


def componente(registro, termos):
    total, contas = 0.0, []
    for t in termos:
        v, cs = termo(registro["linhas"], t)
        total += v
        contas += cs
    return total, contas


def valor_ltm(base, cnpj, ref, termos, dem_fluxo):
    cur = base.get((cnpj, ref))
    if not cur:
        return None
    if not dem_fluxo or ref.endswith("-12-31"):
        return componente(cur, termos)[0]
    a = int(ref[:4])
    fy, ytd = base.get((cnpj, "%d-12-31" % (a - 1))), base.get((cnpj, "%d%s" % (a - 1, ref[4:])))
    if not fy or not ytd:
        return None
    return componente(cur, termos)[0] + componente(fy, termos)[0] - componente(ytd, termos)[0]


def calcular(base, cnpj, ref, regra):
    comp = {}
    for nome, termos in regra["componentes"].items():
        fluxo = all(t["dem"] in FLUXO for t in termos)
        if not fluxo and any(t["dem"] in FLUXO for t in termos):
            raise ValueError("componente %s mistura saldo e fluxo" % nome)
        comp[nome] = valor_ltm(base, cnpj, ref, termos, fluxo)
    out = {}
    if None not in (comp.get("divida"), comp.get("caixa"), comp.get("ebitda")) and comp["ebitda"] > 0:
        out["divida_liquida/ebitda"] = round((comp["divida"] - comp["caixa"]) / comp["ebitda"], 2)
    if "despesa_financeira" in comp and None not in (comp.get("ebitda"), comp.get("despesa_financeira"), comp.get("receita_financeira")):
        dfl = comp["despesa_financeira"] - comp["receita_financeira"]
        if dfl > 0:
            out["ebitda/resultado_financeiro"] = round(comp["ebitda"] / dfl, 2)
    return out, comp


def margem(op, lim, v):
    return None if v is None else round(((lim - v) / lim) if op.startswith("<") else ((v - lim) / lim), 4)


def tabela_escolhida(tabela, regra):
    """Regra pre-registrada: por indicador, a tabela (texto do indice + limite) com mais trimestres distintos; empate pela primeira.
    So indicadores que a regra do emissor sabe calcular."""
    por_ind = {}
    for t in tabela:
        if t["apurado"] is None or not t["ano"]:
            continue
        ind = "divida_liquida/ebitda" if re.search(r"d.vida", t["indice"], re.I) else "ebitda/resultado_financeiro"
        if re.search(r"ppi|bruta/|patrim", t["indice"], re.I) or not re.search(r"ebitda", t["indice"], re.I) or ind not in regra["indices"]:
            continue
        por_ind.setdefault(ind, {}).setdefault((t["indice"], t["operador"], t["limite"]), {})[(t["ano"], t["mes"])] = t
    out = []
    for ind, tabs in por_ind.items():
        melhor = max(tabs.values(), key=lambda d: len(d))
        out += [melhor[k] for k in sorted(melhor)]
    return out


def main(caminho_def=DEF):
    regras = json.load(open(caminho_def, encoding="utf-8"))
    sha = hashlib.sha256(open(caminho_def, "rb").read()).hexdigest()
    sufixo = "" if caminho_def == DEF else "_" + regras["versao"].split()[-1]
    mapa = emissores()
    cov = {r["emissor"]: r for r in json.load(open(os.path.join(SAIDA, "dia4", "covenant_resultado.json"), encoding="utf-8"))}
    base = {}
    for b in ("con", "ind"):
        alvo = {mapa[e] for e, r in regras["emissores"].items() if r.get("base", "con") == b}
        if alvo:
            base.update(ler_linhas(alvo, base=b))
    linhas, serie = [], {}
    for emp, regra in regras["emissores"].items():
        c = mapa[emp]
        af = cov[emp]
        for t in tabela_escolhida(af["tabela_af"], regra):
            ref = "%d-%02d-%02d" % (t["ano"], t["mes"], {3: 31, 6: 30, 9: 30, 12: 31}[t["mes"]])
            ind = "divida_liquida/ebitda" if re.search(r"d.vida", t["indice"], re.I) else "ebitda/resultado_financeiro"
            calc, comp = calcular(base, c, ref, regra)
            v = calc.get(ind)
            reg = base.get((c, ref), {})
            linhas.append({"emissor": emp, "reproducibilidade": regra.get("reproducibilidade", "reproduzivel"), "ref": ref, "indicador": ind, "operador": t["operador"], "limite": t["limite"], "apurado_af": t["apurado"],
                           "contratual_cvm": v, "dif_pct": round(100 * (v - t["apurado"]) / t["apurado"], 1) if (v is not None and t["apurado"]) else None,
                           "margem_af": margem(t["operador"], t["limite"], t["apurado"]), "margem_cvm": margem(t["operador"], t["limite"], v),
                           "dt_receb_cvm": reg.get("dt_receb"), "relatorio_af_entregue": af["relatorio_af"]["data_entrega"],
                           "componentes_rs_mi": {k: (round(x / 1e6, 1) if x is not None else None) for k, x in comp.items()}})
        refs = sorted(k[1] for k in base if k[0] == c)
        serie[emp] = []
        for ref in refs:
            calc, _ = calcular(base, c, ref, regra)
            serie[emp].append({"ref": ref, "dt_receb": base[(c, ref)]["dt_receb"], **calc})
    ok = [x for x in linhas if x["dif_pct"] is not None]
    dentro = [x for x in ok if abs(x["dif_pct"]) <= TOL]
    lado = [x for x in ok if (x["margem_af"] >= 0) == (x["margem_cvm"] >= 0)]
    res = {"versao": "covenant_contratual v1", "definicoes_sha256": sha, "pares": len(ok), "dentro_de_5pct": len(dentro),
           "concordancia": round(len(dentro) / len(ok), 3) if ok else None, "mesmo_lado_do_limite": len(lado),
           "por_emissor_indicador": {}, "comparacao": linhas, "serie_preventiva": serie}
    for x in ok:
        k = "%s | %s" % (x["emissor"], x["indicador"])
        a, b = res["por_emissor_indicador"].get(k, "0 de 0").split(" de ")
        res["por_emissor_indicador"][k] = "%d de %d" % (int(a) + (abs(x["dif_pct"]) <= TOL), int(b) + 1)
    res["por_classe"] = {}
    for cl in ("reproduzivel", "parcial"):
        sub = [x for x in ok if x["reproducibilidade"] == cl]
        for ind in ("divida_liquida/ebitda", "ebitda/resultado_financeiro"):
            s2 = [x for x in sub if x["indicador"] == ind]
            if s2:
                res["por_classe"]["%s | %s" % (cl, ind)] = {"pares": len(s2), "dentro_de_5pct": sum(1 for x in s2 if abs(x["dif_pct"]) <= TOL),
                                                          "mesmo_lado": sum(1 for x in s2 if (x["margem_af"] >= 0) == (x["margem_cvm"] >= 0)),
                                                          "calculo_acima_do_agente": sum(1 for x in s2 if x["dif_pct"] >= 0)}
    res["versao_definicoes"] = regras["versao"]
    gravar_json(os.path.join(SAIDA, "dia6", "covenant_contratual_resultado%s.json" % sufixo), res)
    for x in linhas:
        print("%-7s %s %-28s lim %s%-4s af %-5s cvm %-5s dif%% %-6s margem_af %-7s margem_cvm %-7s receb %s" % (
            x["emissor"], x["ref"], x["indicador"], x["operador"], x["limite"], x["apurado_af"], x["contratual_cvm"], x["dif_pct"],
            x["margem_af"], x["margem_cvm"], x["dt_receb_cvm"]))
    print(json.dumps({k: res[k] for k in ("definicoes_sha256", "pares", "dentro_de_5pct", "concordancia", "mesmo_lado_do_limite", "por_emissor_indicador", "por_classe")},
                     ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else DEF)
