"""Homologacao restrita do piloto de margem de covenant (Dasa, Engie, Simpar).

  registrar   grava piloto/homologacao/registro.json: escopo, covenants com fonte, sha256 do codigo, das definicoes e do historico,
              cabeca do ledger, limiares e criterios. Status PENDENTE ate o aval do operador. Recusa sobrescrever registro aprovado.
  aprovar     SO o operador roda: --por "<nome>" registra o aval aos limiares e ao escopo, com data e hora medidas.
  verificar   guarda: EXIT 0 so com aval registrado e sem mudanca em codigo, definicoes ou historico desde o registro; EXIT 1 senao.
  conferir    compara as estimativas do piloto com a tabela de um relatorio do agente (texto do PDF):
              --emissor X --relatorio <txt> [--ate AAAA-MM-DD]. Criterio: >= 3 trimestres dentro de 5% e nenhum do lado oposto
              do limite. EXIT 0 aprovado, 1 reprovado, 2 sem dado comparavel.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import covenant as C  # noqa: E402
import piloto_covenant as P  # noqa: E402
from comum import AQUI, SAIDA, gravar_json  # noqa: E402

PASTA = os.path.join(P.PASTA, "homologacao")
REGISTRO = os.path.join(PASTA, "registro.json")
ESCOPO = ("Dasa", "Engie Brasil Energia", "Simpar")
CODIGO = ("piloto_covenant.py", "covenant.py", "covenant_contratual.py", "gerar_definicoes_v3.py", "placar.py", "comum.py")
CRITERIOS = {
 "C1_suite": "python -I -m unittest discover -s scripts/predictive/ideias -p \"test_ideias*.py\" com EXIT 0",
 "C2_determinismo": "duas execucoes do piloto geram historico e ledger identicos",
 "C3_rastreabilidade": "todo alerta traz ITR/DFP (ref, versao, dt_receb), protocolo e data da escritura e linha da clausula",
 "C4_sem_dado_futuro": "todo alerta posterior ao dado que o gerou (teste sobre a saida real)",
 "C5_conferencia_2027": "relatorio anual do agente de 2027 (exercicio 2026): para cada emissor do escopo, >= 3 de 4 trimestres "
                        "dentro de 5% do apurado e nenhum do lado oposto do limite (conferir com EXIT 0)",
 "C6_escopo": "so Dasa, Engie e Simpar; outros emissores seguem sem alerta homologado",
}


def sha(caminho):
    return hashlib.sha256(open(caminho, "rb").read()).hexdigest()


def hashes():
    h = {"codigo/" + n: sha(os.path.join(AQUI, n)) for n in CODIGO}
    h["definicoes_v5"] = sha(P.DEF)
    h["historico"] = sha(os.path.join(P.PASTA, "historico.json"))
    h["alertas"] = sha(os.path.join(P.PASTA, "alertas.jsonl"))
    return h


def registrar():
    if os.path.exists(REGISTRO) and json.load(open(REGISTRO, encoding="utf-8")).get("aprovacao"):
        raise SystemExit("registro ja aprovado; nao sobrescrevo (apague conscientemente para refazer)")
    covs = {c["emissor"]: c for c in json.load(open(os.path.join(P.PASTA, "covenants.json"), encoding="utf-8"))["covenants"]}
    hist = json.load(open(os.path.join(P.PASTA, "historico.json"), encoding="utf-8"))
    resumo = json.load(open(os.path.join(P.PASTA, "resumo.json"), encoding="utf-8"))
    escopo = {}
    for e in ESCOPO:
        c = covs[e]
        ult = [h for h in hist if h["emissor"] == e and h["classe"] == "REPRODUZIVEL"]
        escopo[e] = {"status_covenant": c["status"], "operador": c.get("operador"), "limite": c.get("limite"), "formula": c.get("formula"),
                     "escritura": c["escritura"], "linha_escritura": c.get("linha_escritura"), "relatorio_af": c["relatorio_af"],
                     "classe_atual": ult[-1]["classe"] if ult else None, "validacao": ult[-1]["motivo_classe"] if ult else None,
                     "ultima_margem": {"ref": ult[-1]["ref"], "margem": ult[-1]["margem"]} if ult else None}
        if c["status"] != "ATIVO" or not ult:
            raise SystemExit("%s nao esta ATIVO e REPRODUZIVEL; escopo de homologacao invalido" % e)
    reg = {"versao": "homologacao_covenant v1", "registrado_em": datetime.now().strftime("%Y-%m-%d %H:%M"), "status": "PENDENTE_AVAL_OPERADOR",
           "escopo": escopo, "limiares_propostos": {k: v for k, v in P.PARAMS.items() if k != "status"},
           "criterios_de_aceite": CRITERIOS, "hashes": hashes(), "ledger_cabeca": resumo["ledger_cabeca"], "aprovacao": None}
    gravar_json(REGISTRO, reg)
    print(json.dumps({"registro": REGISTRO, "status": reg["status"]}, ensure_ascii=False))


def aprovar(por):
    reg = json.load(open(REGISTRO, encoding="utf-8"))
    if reg.get("aprovacao"):
        raise SystemExit("ja aprovado por %s" % reg["aprovacao"]["por"])
    if hashes() != reg["hashes"]:
        raise SystemExit("codigo, definicoes ou historico mudaram desde o registro; registrar de novo antes de aprovar")
    reg["aprovacao"] = {"por": por, "em": datetime.now().strftime("%Y-%m-%d %H:%M"), "aprova": "escopo, limiares propostos e criterios C1 a C6"}
    reg["status"] = "APROVADO_PARA_HOMOLOGACAO_RESTRITA"
    gravar_json(REGISTRO, reg)
    print(json.dumps({"status": reg["status"], "por": por}, ensure_ascii=False))


def verificar():
    if not os.path.exists(REGISTRO):
        return 1, "sem registro de homologacao"
    reg = json.load(open(REGISTRO, encoding="utf-8"))
    if not reg.get("aprovacao"):
        return 1, "registro PENDENTE: falta o aval do operador (homologacao_covenant.py aprovar --por <nome>)"
    atual = hashes()
    mud = sorted(k for k in reg["hashes"] if atual.get(k) != reg["hashes"][k])
    if mud:
        return 1, "mudou desde o registro: " + ", ".join(mud)
    return 0, "aprovado por %s em %s, sem mudanca desde o registro" % (reg["aprovacao"]["por"], reg["aprovacao"]["em"])


def conferir(emissor, texto_af, historico, ate=None):
    """Compara a ultima estimativa do piloto de cada trimestre (publicada ou bloqueada, ate a data 'ate') com o apurado do agente."""
    cov = {c["emissor"]: c for c in json.load(open(os.path.join(P.PASTA, "covenants.json"), encoding="utf-8"))["covenants"]}[emissor]
    linhas = [t for t in C.extrair_af(texto_af) if t["apurado"] is not None and t["ano"] and re.search(r"d.vida", t["indice"], re.I)
              and re.search(r"ebitda", t["indice"], re.I) and (t["operador"], t["limite"]) == (cov["operador"], cov["limite"])]
    comp = []
    for t in sorted({P.ref_do_trimestre(x): x for x in linhas}.values(), key=lambda x: (x["ano"], x["mes"])):
        ref = P.ref_do_trimestre(t)
        hs = [h for h in historico if h["emissor"] == emissor and h["ref"] == ref and (ate is None or h["as_of"] <= ate)]
        if not hs:
            continue
        h = hs[-1]
        v = h["valor_estimado"] if h["valor_estimado"] is not None else h.get("diagnostico_valor_bloqueado")
        if v is None:
            continue
        dif = 100 * (v - t["apurado"]) / t["apurado"]
        comp.append({"ref": ref, "estimativa": v, "classe_na_epoca": h["classe"], "apurado_agente": t["apurado"], "dif_pct": round(dif, 1),
                     "mesmo_lado": P.viola(cov["operador"], cov["limite"], v) == P.viola(cov["operador"], cov["limite"], t["apurado"])})
    if len(comp) < P.PARAMS["min_trimestres_validados"]:
        return 2, comp
    dentro = sum(1 for x in comp if abs(x["dif_pct"]) <= P.PARAMS["tolerancia_pct"])
    ok = dentro >= P.PARAMS["min_trimestres_validados"] and all(x["mesmo_lado"] for x in comp)
    return (0 if ok else 1), comp


def main(argv=None):
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("registrar")
    a = sub.add_parser("aprovar")
    a.add_argument("--por", required=True)
    sub.add_parser("verificar")
    c = sub.add_parser("conferir")
    c.add_argument("--emissor", required=True)
    c.add_argument("--relatorio", required=True)
    c.add_argument("--ate")
    ns = ap.parse_args(argv)
    if ns.cmd == "registrar":
        registrar()
        return 0
    if ns.cmd == "aprovar":
        aprovar(ns.por)
        return 0
    if ns.cmd == "verificar":
        cod, msg = verificar()
        print(json.dumps({"ok": cod == 0, "mensagem": msg}, ensure_ascii=False))
        return cod
    hist = json.load(open(os.path.join(P.PASTA, "historico.json"), encoding="utf-8"))
    cod, comp = conferir(ns.emissor, open(ns.relatorio, encoding="utf-8", errors="ignore").read(), hist, ns.ate)
    print(json.dumps({"emissor": ns.emissor, "resultado": {0: "APROVADO", 1: "REPROVADO", 2: "SEM_DADO_COMPARAVEL"}[cod], "trimestres": comp},
                     ensure_ascii=False, indent=1))
    return cod


if __name__ == "__main__":
    sys.exit(main())
