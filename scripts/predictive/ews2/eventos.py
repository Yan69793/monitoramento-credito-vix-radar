"""Base de eventos a partir dos ROTULOS (G0-v2/G0-v3 item 3) e regras herdadas da G0-v1 (itens 1, 3 so prevalencia, 4, 6).

Entrada: CSV de rotulos congelado (colunas de preflight_g1a.COLUNAS_ROTULO mais, quando houver, as colunas de
origem e adicionais), ja depois de segunda leitura e adjudicacao. Evento = evento_proprio na data rotulada,
origem resolvida de continuacao na data dela, evento adicional. Dois candidatos que levam ao mesmo evento viram
um so (mesma chave cnpj+data). Episodio: eventos do mesmo CNPJ a ate 30 dias, em cadeia.

Prevalencia (G0-v1 item 3): episodio cuja empresa teve, nos 24 meses antes da data do evento, documento IPE da
categoria RX_CAT_A fica fora do alvo. Incidente = nao prevalente. Depois do incidente a empresa sai do risco ate
o fim do episodio (ultimo evento do episodio + 12 meses sem evento, regra herdada de expiracao).

Censura (G0-v1 item 4): cancelamento de registro com motivo listado, sem evento nos 180 dias anteriores, censura
em DT_CANCEL; com evento nos 180 dias anteriores, o evento e que conta. Securitizadora fora do universo (item 1).
"""
import csv
import re
from datetime import timedelta

from calendario import JANELA_FIM, JANELA_INI

RX_CAT_A = re.compile(r"informacoes de companhias em recuperacao judicial ou extrajudicial")
RX_SEC_SETOR = re.compile(r"securitiza")
RX_SEC_NOME = re.compile(r"securitiz")
MOTIVOS_CENSURA = ("cancelamento voluntario", "elisao por incorporacao", "elisao por extincao da cia", "cancelamento de oficio", "migracao de registro")
EPISODIO_DIAS = 30
EXPIRA = timedelta(days=365)
LOOKBACK_PREV = timedelta(days=730)
JANELA_EVENTO_CANCEL = timedelta(days=180)
FORMULACAO = [re.compile(p) for p in (r"\bamericanas\b", r"^light\b", r"^oi s\.?\s?a\b|^oi s/a\b", r"\bgol linhas\b|^gol\b",
                                       r"\bcasas bahia\b|^via varejo\b|^via s\.?\s?a\b", r"\bagrogalaxy\b", r"^azul s\.?\s?a\b|^azul linhas\b",
                                       r"\bcompanhia brasileira de distribuicao\b", r"\braizen\b", r"\boncoclinicas\b", r"\bbraskem\b", r"\bmarabraz\b")]


def pdate(s):
    from dados import pdate as _p
    return _p(s)


def ler_rotulos(caminho):
    with open(caminho, encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh, delimiter=";"))


def eventos_de_rotulos(rotulos):
    """Lista de eventos {cnpj, data, fonte_id, tipo}. Deduplicado por (cnpj, data)."""
    ev = {}

    def add(cnpj, d, iid, tipo, fonte):
        d = pdate(d) if isinstance(d, str) else d
        if not cnpj or not d:
            return
        ev.setdefault((cnpj, d), {"cnpj": cnpj, "data": d, "tipo": tipo, "itens": [], "fontes": []})
        ev[(cnpj, d)]["itens"].append(iid)
        ev[(cnpj, d)]["fontes"].append(fonte)
    for r in rotulos:
        c, iid = r["cnpj"].strip(), r["id"]
        cl = (r.get("classe_final") or r.get("classe1") or "").strip()
        if cl == "evento_proprio":
            add(c, r.get("data_evento_final") or r.get("data_evento1"), iid, r.get("tipo") or "", "evento_proprio")
        elif cl == "continuacao":
            add(c, r.get("origem_data_entrega"), iid, r.get("origem_tipo") or "", "origem_continuacao")
        ad = (r.get("adicionais_json") or "").strip()
        if ad:
            import json
            for a in json.loads(ad):
                add(c, a.get("data_ou_origem"), iid, a.get("tipo") or "", "adicional")
    return sorted(ev.values(), key=lambda e: (e["cnpj"], e["data"]))


def episodios(eventos):
    """Cadeias de eventos do mesmo CNPJ a ate EPISODIO_DIAS. Devolve lista de {cnpj, inicio, ultimo, eventos}."""
    out = []
    atual = None
    for e in sorted(eventos, key=lambda x: (x["cnpj"], x["data"])):
        if atual and atual["cnpj"] == e["cnpj"] and (e["data"] - atual["ultimo"]).days <= EPISODIO_DIAS:
            atual["ultimo"] = e["data"]
            atual["eventos"].append(e)
            continue
        atual = {"cnpj": e["cnpj"], "inicio": e["data"], "ultimo": e["data"], "eventos": [e]}
        out.append(atual)
    for ep in out:
        ep["fim"] = ep["ultimo"] + EXPIRA
    return out


def marcar_prevalencia(eps, docs_por_cnpj):
    for ep in eps:
        ini = ep["inicio"] - LOOKBACK_PREV
        ep["prevalente"] = any(ini <= d["data"] < ep["inicio"] and RX_CAT_A.search(d["cat_n"]) for d in docs_por_cnpj.get(ep["cnpj"], []))
    return eps


def eh_securitizadora(docs, periodos):
    return any(RX_SEC_SETOR.search(p["setor_ativ"].lower()) for p in periodos if p.get("setor_ativ")) or \
        any(RX_SEC_NOME.search(d["nome_n"]) for d in docs)


def eh_formulacao(nomes_n):
    return any(rx.search(n) for n in nomes_n for rx in FORMULACAO)


def censuras(periodos, eps_cnpj):
    """Datas de censura por cancelamento de registro (item 4). Devolve lista de (dt_cancel, motivo) validas."""
    out = []
    for p in periodos:
        dc = p.get("dt_cancel")
        if not dc or not (JANELA_INI <= dc <= JANELA_FIM):
            continue
        mot = (p.get("motivo_cancel") or "").lower()
        from dados import norm
        if not any(m in norm(mot) for m in MOTIVOS_CENSURA):
            continue
        if any(dc - JANELA_EVENTO_CANCEL <= ep["inicio"] <= dc for ep in eps_cnpj):
            continue  # evento nos 180 dias anteriores conta como evento, nao censura
        out.append((dc, mot))
    return out
