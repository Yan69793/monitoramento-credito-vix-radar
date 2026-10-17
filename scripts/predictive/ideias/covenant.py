"""PoC 5 (Dia 4, escopo ajustado pelo operador em 17/10): margem de seguranca ate o limite contratual.

1. Escritura: extracao deterministica (regex) de indicador, limite, operador, step-down, periodicidade, base
   consolidada e tipo de vencimento antecipado, com offset e linha de origem.
2. Relatorio do agente fiduciario: tabela de limite e apurado por trimestre (formato Pentagono). Outros formatos sao
   registrados como "sem tabela no IPE".
3. Calculo padronizado com ITR/DFP da CVM (contas fixas), LTM, com DT_RECEB de cada demonstrativo.
4. Comparacao: calculado x apurado do agente, limite da escritura x limite do agente, e antecedencia
   (data do relatorio do agente - DT_RECEB do ITR que ja permitia medir a margem).
Nao classifica evento, nao detecta violacao nem waiver (isso ja existe no VIX Radar).
"""
import collections
import json
import os
import re
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comum import RAW, SAIDA, digitos, emissores, gravar_json, pdata  # noqa: E402

import dados  # noqa: E402

PROV = os.path.join(SAIDA, "dia4", "proveniencia_covenant.jsonl")
NUM = r"(\d{1,2}(?:,\d{1,2})?)"
RX_LIMITE = re.compile(r"(igual\s+ou\s+)?(menor|inferior|maior|superior)(\s+ou\s+igual)?\s+(?:a|do\s+que|que)\s*:?\s*(?:\(a\)\s*)?" + NUM + r"\s*(?:\(([^)]{0,60})\))?\s*(vezes|vez|x)?", re.I)
RX_DIV = re.compile(r"d.vida\s+(?:(?:financeira|total|bruta)\s+)?(?:l.quida|consolidada)", re.I)
RX_NEGACAO = re.compile(r"n[aã]o\s+(?:\w+\s+){0,2}$", re.I)
RX_GATILHO = re.compile(r"\b(quando|caso|na\s+hip[oó]tese|ocorr[eê]ncia|for|seja|vier\s+a\s+ser)\b[^.;]{0,140}$", re.I)
INVERSO = {"<": ">=", "<=": ">", ">": "<=", ">=": "<"}


def operador_pelo_contexto(plano, inicio, literal):
    """A escritura ora diz o limite mantido ('deve ser inferior a 4', 'nao podera ser superior a 4,5') ora o gatilho do vencimento
    ('quando o indice for superior a 4'). O limite mantido e o inverso do gatilho e o inverso da forma negada. Devolve (operador, motivo)."""
    antes = plano[max(0, inicio - 160):inicio]
    if RX_NEGACAO.search(antes):
        return INVERSO[literal], "negacao"
    if RX_GATILHO.search(antes):
        return INVERSO[literal], "gatilho"
    return literal, "literal"
RX_EBITDA = re.compile(r"ebitda", re.I)
RX_FIN = re.compile(r"(resultado|despesa)s?\s+financeir[oa]s?(\s+l.quid[oa])?", re.I)
RX_STEP = re.compile(r"\(([b-h])\)\s*" + NUM + r"\s*\(", re.I)


def linha_de(texto, pos):
    return texto.count("\n", 0, pos) + 1


RX_SIMBOLO = re.compile(r"(≤|≥|<=|>=)\s*" + NUM + r"\s*(?:x|vezes|vez)?", re.I)
SIMBOLO = {"≤": "<=", "≥": ">=", "<=": "<=", ">=": ">="}


class Achado:
    def __init__(self, inicio, fim, literal, limite):
        self.inicio, self.fim, self.literal, self.limite = inicio, fim, literal, limite

    def start(self):
        return self.inicio

    def end(self):
        return self.fim


def achados_de_limite(plano):
    """Limites por extenso ('menor ou igual a 3,5') e por simbolo ('<= 3,5'). Cada um com o operador literal."""
    out = []
    for m in RX_LIMITE.finditer(plano):
        lit = {"menor": "<", "inferior": "<", "maior": ">", "superior": ">"}[m.group(2).lower()] + ("=" if (m.group(1) or m.group(3)) else "")
        out.append(Achado(m.start(), m.end(), lit, m.group(4)))
    for m in RX_SIMBOLO.finditer(plano):
        out.append(Achado(m.start(), m.end(), SIMBOLO[m.group(1)], m.group(2)))
    return sorted(out, key=lambda a: a.inicio)


def extrair_escritura(texto):
    plano = texto.replace("\r", "")
    out = []
    vistos = set()
    for m in achados_de_limite(plano):
        ini = max(0, m.start() - 350)
        antes = plano[ini:m.start()]
        dv = list(RX_DIV.finditer(antes))
        eb = list(RX_EBITDA.finditer(antes))
        fi = list(RX_FIN.finditer(antes))
        if not eb:
            continue
        ult_dv = dv[-1].end() if dv else -1
        ult_fi = fi[-1].end() if fi else -1
        if ult_dv >= 0 and ult_dv > ult_fi:
            ind = "divida_liquida/ebitda"
        elif ult_fi >= 0:
            ind = "ebitda/resultado_financeiro"
        else:
            continue
        op, forma = operador_pelo_contexto(plano, m.start(), m.literal)
        lim = float(m.limite.replace(",", "."))
        if not (0.2 <= lim <= 20):
            continue
        chave = (ind, op, lim)
        if chave in vistos:
            continue
        vistos.add(chave)
        janela_dep = plano[m.end():m.end() + 900]
        step = [(s.group(1), float(s.group(2).replace(",", "."))) for s in RX_STEP.finditer(janela_dep)][:6]
        contexto = plano[max(0, m.start() - 1500):m.end() + 300].lower()
        per = "trimestral" if re.search(r"trimestr", contexto) else ("anual" if re.search(r"anual|exerc.cio social", contexto) else None)
        consol = bool(re.search(r"consolidad", contexto))
        bloco = plano[max(0, m.start() - 25000):m.start()].lower()
        pna = max(bloco.rfind("nao automatic"), bloco.rfind("não automátic"), bloco.rfind("não automatic"))
        pa = max(bloco.rfind("automaticamente"), bloco.rfind("vencimento antecipado automátic"), bloco.rfind("eventos de vencimento antecipado automatico"))
        venc = "nao_automatico" if pna > pa else ("automatico" if pa >= 0 else None)
        out.append({"indicador": ind, "operador": op, "forma_da_clausula": forma, "limite": lim, "step_down": step, "periodicidade": per,
                    "base_consolidada": consol, "vencimento_antecipado": venc, "offset": m.start(), "linha": linha_de(plano, m.start()),
                    "trecho": re.sub(r"\s+", " ", plano[max(0, m.start() - 220):m.end() + 60])})
    return out


MESES = {"marco": 3, "março": 3, "junho": 6, "setembro": 9, "dezembro": 12}


def extrair_af(texto):
    """Tabela Pentagono: linha 'INDICE MARCO JUNHO SETEMBRO DEZEMBRO', depois linhas com Limite e Apurado."""
    linhas = texto.replace("\r", "").split("\n")
    ano = None
    m = re.search(r"EXERC.CIO DE (\d{4})", texto)
    if m:
        ano = int(m.group(1))
    cab = None
    out = []
    for i, ln in enumerate(linhas):
        if re.search(r"\bMAR.O\b.*\bJUNHO\b.*\bSETEMBRO\b.*\bDEZEMBRO", ln, re.I):
            cab = [MESES[x.lower().replace("ç", "c") if x.lower() != "março" else "março"] for x in re.findall(r"MAR.O|JUNHO|SETEMBRO|DEZEMBRO", ln, re.I)]
            continue
        if cab and "Limite" in ln:
            toks = list(re.finditer(r"Limite\s*(?:<=|>=|<|>)\s*[\d,]+|N/A", ln))
            nome = ln[:toks[0].start()].strip() if toks else ""
            cols = [t.group(0) for t in toks]
            prox = next((x for x in linhas[i + 1:i + 4] if x.strip()), "")  # Apurado na proxima linha nao vazia
            ap = re.findall(r"Apurado=\s*(\d{1,4}(?:,\d{1,2})?)", prox)  # aceita 122,4 (o NUM da escritura corta em 2 digitos)
            nome2 = re.split(r"\s{2,}|Apurado", prox.strip())[0].strip()
            ativos = [k for k, c in enumerate(cols) if c.startswith("Limite")]
            for j, k in enumerate(ativos):
                lm = re.match(r"Limite\s*(<=|>=|<|>)\s*" + NUM, cols[k])
                if not lm or k >= len(cab):
                    continue
                out.append({"indice": (nome + " " + nome2).strip(), "mes": cab[k], "ano": ano, "operador": lm.group(1),
                            "limite": float(lm.group(2).replace(",", ".")),
                            "apurado": float(ap[j].replace(",", ".")) if j < len(ap) else None, "linha": i + 1})
    return out


# ---------- calculo padronizado com contas CVM ----------
CONTAS = {"1.01.01": "caixa", "1.01.02": "aplicacoes", "2.01.04": "emprest_cp", "2.02.01": "emprest_lp", "3.05": "ebit", "3.06": "res_fin"}


def ler_contabil(cnpjs, anos=("2023", "2024", "2025", "2026")):
    """{(cnpj, dt_refer): {'dt_receb', 'versao', 'tipo', contas fixas YTD/saldo, 'da' (depreciacao+amortizacao YTD)}}"""
    alvo = set(cnpjs)
    out = {}
    fontes = [("ITR", "itr_cia_aberta_", [os.path.join(RAW, "itr")]), ("DFP", "dfp_cia_aberta_", dados.DIRS_DFP)]
    for tipo, pref, dirs in fontes:
        for ano, z in sorted(dados._zips(dirs, pref).items()):
            if ano not in anos:
                continue
            cab = {}
            for r in dados._csv_do_zip(z, "%s%s.csv" % (pref, ano)):
                c = digitos(r["CNPJ_CIA"])
                if c in alvo:
                    k = (c, r["DT_REFER"])
                    v = int(r["VERSAO"] or 0)
                    if k not in cab or v > cab[k]["versao"]:
                        cab[k] = {"versao": v, "dt_receb": r["DT_RECEB"], "tipo": tipo}
            for dem in ("BPA_con", "BPP_con", "DRE_con", "DFC_MI_con"):
                for r in dados._csv_do_zip(z, "%s%s_%s.csv" % (pref, dem, ano)):
                    c = digitos(r["CNPJ_CIA"])
                    k = (c, r["DT_REFER"])
                    if k not in cab or int(r["VERSAO"] or 0) != cab[k]["versao"]:
                        continue
                    if r.get("ORDEM_EXERC", "").upper() not in ("ÚLTIMO", "ULTIMO"):
                        continue
                    cd = r["CD_CONTA"]
                    esc = 1000.0 if dados.norm(r.get("ESCALA_MOEDA", "")) == "mil" else 1.0
                    try:
                        val = float(r["VL_CONTA"].replace(",", ".")) * esc
                    except ValueError:
                        continue
                    reg = out.setdefault(k, dict(cab[k]))
                    if dem in ("DRE_con",):
                        ini = r.get("DT_INI_EXERC", "")
                        if not ini.endswith("-01-01"):
                            continue  # so acumulado do ano
                    if cd in CONTAS and dem != "DFC_MI_con":
                        reg[CONTAS[cd]] = val
                    if dem == "DFC_MI_con" and cd.startswith("6.01.01.") and re.search(r"deprecia|amortiza", dados.norm(r.get("DS_CONTA", ""))) \
                            and not re.search(r"emprest|juros|financiamento|debentur|custo de transacao", dados.norm(r.get("DS_CONTA", ""))):
                        reg["da"] = reg.get("da", 0.0) + val
    return out


def ltm(contabil, cnpj, ref, campo):
    """Fluxo dos ultimos 12 meses: YTD(ref) + ano anterior cheio - YTD(mesmo trimestre do ano anterior)."""
    cur = contabil.get((cnpj, ref))
    if not cur or campo not in cur:
        return None
    if ref.endswith("-12-31"):
        return cur[campo]
    a = int(ref[:4])
    prev_fy = contabil.get((cnpj, "%d-12-31" % (a - 1)))
    prev_ytd = contabil.get((cnpj, "%d%s" % (a - 1, ref[4:])))
    if not prev_fy or not prev_ytd or campo not in prev_fy or campo not in prev_ytd:
        return None
    return cur[campo] + prev_fy[campo] - prev_ytd[campo]


def calcular(contabil, cnpj, ref):
    cur = contabil.get((cnpj, ref))
    if not cur:
        return None
    ebit, da, rf = ltm(contabil, cnpj, ref, "ebit"), ltm(contabil, cnpj, ref, "da"), ltm(contabil, cnpj, ref, "res_fin")
    dl = cur.get("emprest_cp", 0) + cur.get("emprest_lp", 0) - cur.get("caixa", 0) - cur.get("aplicacoes", 0)
    ebitda = (ebit + abs(da)) if (ebit is not None and da is not None) else None
    return {"dt_refer": ref, "dt_receb": cur["dt_receb"], "tipo": cur["tipo"], "divida_liquida": dl, "ebitda_ltm": ebitda,
            "dl_ebitda": round(dl / ebitda, 2) if ebitda and ebitda > 0 else None,
            "ebitda_res_fin": round(ebitda / -rf, 2) if (ebitda and rf and rf < 0) else None}


def margem(op, limite, valor):
    if valor is None:
        return None
    return round(((limite - valor) / limite) if op.startswith("<") else ((valor - limite) / limite), 4)


def main():
    prov = [json.loads(l) for l in open(PROV, encoding="utf-8")]
    mapa = emissores()
    docs = collections.defaultdict(dict)
    for p in prov:
        docs[p["emissor"]][p["papel"]] = p
    contabil = ler_contabil({mapa[e] for e in docs if e in mapa})
    res = []
    for emp, d in docs.items():
        esc, af = d.get("escritura", {}), d.get("relatorio_af", {})
        r = {"emissor": emp, "emissao": esc.get("emissao") or af.get("emissao"),
             "escritura": {k: esc.get(k) for k in ("protocolo", "link", "data_entrega", "texto")},
             "relatorio_af": {k: af.get(k) for k in ("protocolo", "link", "data_entrega", "texto")}}
        r["covenants_escritura"] = extrair_escritura(open(esc["arquivo_txt"], encoding="utf-8", errors="ignore").read()) if esc.get("arquivo_txt") else []
        r["tabela_af"] = extrair_af(open(af["arquivo_txt"], encoding="utf-8", errors="ignore").read()) if af.get("arquivo_txt") else []
        cmp_ = []
        for t in r["tabela_af"]:
            ref = "%d-%02d-%02d" % (t["ano"], t["mes"], {3: 31, 6: 30, 9: 30, 12: 31}[t["mes"]]) if t["ano"] else None
            calc = calcular(contabil, mapa.get(emp), ref) if ref else None
            ind = "divida_liquida/ebitda" if re.search(r"d.vida", t["indice"], re.I) else "ebitda/resultado_financeiro"
            v_calc = calc and (calc["dl_ebitda"] if ind.startswith("divida") else calc["ebitda_res_fin"])
            lim_esc = [c for c in r["covenants_escritura"] if c["indicador"] == ind]
            ant = (pdata(af.get("data_entrega")) - pdata(calc["dt_receb"])).days if (calc and af.get("data_entrega")) else None
            cmp_.append({"indice_af": t["indice"], "indicador": ind, "ref": ref, "limite_af": t["limite"], "operador_af": t["operador"],
                         "apurado_af": t["apurado"], "limite_escritura": [(c["operador"], c["limite"]) for c in lim_esc],
                         "limite_confere": any(abs(c["limite"] - t["limite"]) < 1e-9 for c in lim_esc) if lim_esc else None,
                         "calculado_cvm": v_calc, "dt_receb_cvm": calc and calc["dt_receb"],
                         "diferenca_pct": round(100 * (v_calc - t["apurado"]) / t["apurado"], 1) if (v_calc is not None and t["apurado"]) else None,
                         "margem_af": margem(t["operador"], t["limite"], t["apurado"]), "margem_cvm": margem(t["operador"], t["limite"], v_calc),
                         "dias_de_antecedencia_vs_relatorio_af": ant})
        r["comparacao"] = cmp_
        # margem preventiva com o ultimo ITR publicado, para todo covenant extraido da escritura
        refs = sorted(k[1] for k in contabil if k[0] == mapa.get(emp))
        ult = calcular(contabil, mapa.get(emp), refs[-1]) if refs else None
        r["margem_ultimo_itr"] = []
        for c in r["covenants_escritura"]:
            v = ult and (ult["dl_ebitda"] if c["indicador"].startswith("divida") else ult["ebitda_res_fin"])
            r["margem_ultimo_itr"].append({"indicador": c["indicador"], "limite": c["limite"], "operador": c["operador"], "ref": ult and ult["dt_refer"],
                                           "dt_receb": ult and ult["dt_receb"], "valor_cvm_padronizado": v, "margem": margem(c["operador"], c["limite"], v)})
        res.append(r)
    gravar_json(os.path.join(SAIDA, "dia4", "covenant_resultado.json"), res)
    for r in res:
        print("==", r["emissor"], "emissao", r["emissao"], "| escritura:", len(r["covenants_escritura"]), "covenants | af:", len(r["tabela_af"]), "linhas")
        for c in r["covenants_escritura"]:
            print("   ESC", c["indicador"], c["operador"], c["limite"], "step", c["step_down"], c["periodicidade"], "consol" if c["base_consolidada"] else "", c["vencimento_antecipado"], "L%d" % c["linha"])
        for c in r["comparacao"]:
            print("   CMP", c["ref"], c["indicador"], c["operador_af"], c["limite_af"], "apurado", c["apurado_af"], "calc", c["calculado_cvm"], "dif%", c["diferenca_pct"],
                  "lim_esc_confere", c["limite_confere"], "margem_af", c["margem_af"], "antec_dias", c["dias_de_antecedencia_vs_relatorio_af"])
        for c in r["margem_ultimo_itr"]:
            print("   ULT", c["ref"], c["dt_receb"], c["indicador"], c["operador"], c["limite"], "valor", c["valor_cvm_padronizado"], "margem", c["margem"])


if __name__ == "__main__":
    main()
