"""G0-v4 (nota 124): classificacao LOCAL e deterministica de um candidato da etapa 1, sem IA, sem rede.

Puro: recebe o item, os metadados dos documentos e uma funcao que devolve o texto integral de um protocolo
(ou None). Nao le camada, estrato, rotulo legado, EWS nem sinal.

Saida por item (dict):
  classe            evento_proprio | evento_terceiro | continuacao | nao_evento | PENDENTE_REVISAO
  tipo, data_evento, protocolo_evento, trecho_evento        (evento_proprio)
  origem {protocolo, data_entrega, tipo, trecho, completa}  (continuacao)
  adicionais [...]                                          (outro evento proprio de processo distinto)
  revisao_obrigatoria, motivos_revisao                      (nota 124 item 4)
  caminho           rotulo curto do caminho de decisao (estrato da amostra cega dos nao_evento)
  confianca         alta | media | baixa
  disparos          todo gatilho encontrado, com documento, regra, posicao, flags e trecho literal
  entradas          documentos lidos, com chars e se tinham texto

Regra fundamental (nota 124 item 2): sem evidencia suficiente => PENDENTE_REVISAO, nunca nao_evento por padrao.
nao_evento automatico so sai quando TODO documento do dia tem texto integral lido e nenhum gatilho material
nao hipotetico aparece nele nem no metadado do dia. Esses itens vao a amostragem estratificada cega.
"""
import datetime as dt
import re
import unicodedata

VERSAO = "g0v4-local-v4"
MIN_TEXTO = 80
JANELA_MAX = 420
PALAVRAS_TRECHO = 30
DIAS_CONFLITO = 30

# ---------------------------------------------------------------- normalizacao alinhada


_CACHE_LETRA = {}


def _letra(c):
    r = _CACHE_LETRA.get(c)
    if r is None:
        n = unicodedata.normalize("NFD", c)
        b = "".join(x for x in n if unicodedata.category(x) != "Mn")[:1].lower()
        r = _CACHE_LETRA[c] = b if b else " "
    return r


def base_alinhada(txt):
    """Mesmo comprimento do original: cada caractere vira sua letra base minuscula sem acento (ou espaco)."""
    return "".join([_letra(c) for c in txt])


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s or "") if unicodedata.category(c) != "Mn").lower()


def norm_trecho(s):
    return re.sub(r"\s+", " ", sem_acento(s or "")).strip()


# ---------------------------------------------------------------- gatilhos
# (tipo, regra, forca, regex). Texto sem acento e minusculo. \s+ cobre quebra de linha do pdftotext.
S = r"\s+"
GAP = r"[\s\S]{0,%d}?"
TIPOS_ORDEM = ["falencia", "RJ", "RE", "vencimento_antecipado_ou_default", "standstill_mediacao_cautelar"]

GATILHOS = [
    ("falencia", "F1_autofalencia", "forte", r"auto-?\s?falencia"),
    ("falencia", "F2_decretacao", "forte", r"decret\w*" + S + r"(a" + S + r"|da" + S + r"|de" + S + r")?(sua" + S + r")?falencia"
     + r"|falencia" + S + r"(da" + S + r"companhia" + S + r")?(foi" + S + r")?decretada|sentenca" + S + r"(que" + S + r"decret\w*" + S + r")?(de|da)" + S + r"falencia"),
    ("falencia", "F3_convolacao", "forte", r"convola\w*" + GAP % 80 + r"falencia"),
    ("falencia", "FP_pedido_falencia", "fraco", r"pedidos?" + S + r"de" + S + r"falencia|requer\w*" + S + r"(a" + S + r")?(sua" + S + r")?falencia"),
    ("RJ", "RJ1_ajuizamento", "forte", r"(ajuiz\w*|protocol\w*|requer\w*|ingress\w*|distribu\w*|impetr\w*|propos\w*)" + GAP % 100
     + r"(pedido" + S + r"de" + S + r")?recuperacao" + S + r"judicial"),
    ("RJ", "RJ2_pedido", "forte", r"pedido" + S + r"de" + S + r"recuperacao" + S + r"judicial"),
    ("RJ", "RJ3_deferimento", "forte", r"deferi\w*" + GAP % 80 + r"processamento" + GAP % 50 + r"recuperacao" + S + r"judicial"),
    ("RJ", "RJ4_status", "fraco", r"(em|sob)" + S + r"recuperacao" + S + r"judicial|plano" + S + r"de" + S + r"recuperacao" + S + r"judicial|recuperandas?\b"),
    ("RJ", "CH11", "forte", r"chapter" + S + r"11\b|capitulo" + S + r"11\b"),
    ("RE", "RE1_ajuizamento", "forte", r"(ajuiz\w*|protocol\w*|requer\w*|ingress\w*|distribu\w*|propos\w*|inici\w*)" + GAP % 100
     + r"(pedido" + S + r"de" + S + r")?recuperacao" + S + r"extrajudicial"),
    ("RE", "RE2_pedido", "forte", r"pedido" + S + r"de" + S + r"(homologacao" + S + r"d[eo]" + S + r"(plano" + S + r"de" + S + r")?)?recuperacao" + S + r"extrajudicial"),
    ("RE", "RE3_deferimento_homologacao", "forte", r"(deferi\w*|homolog\w*)" + GAP % 80 + r"recuperacao" + S + r"extrajudicial"),
    ("RE", "RE4_status", "fraco", r"(em|sob)" + S + r"recuperacao" + S + r"extrajudicial|plano" + S + r"de" + S + r"recuperacao" + S + r"extrajudicial"),
    ("vencimento_antecipado_ou_default", "VA1_declaracao", "forte", r"(declar\w*|decret\w*|ocorr\w*|configur\w*)" + GAP % 60 + r"vencimento" + S + r"antecipado"),
    ("vencimento_antecipado_ou_default", "VA2_vencidas", "forte", r"vencid[ao]s?" + S + r"antecipadamente|antecipacao" + S + r"do" + S + r"vencimento"),
    ("vencimento_antecipado_ou_default", "VA3_generico", "fraco", r"vencimento" + S + r"antecipado"),
    ("vencimento_antecipado_ou_default", "DF1_nao_pagamento", "forte", r"(nao|deixou" + S + r"de|deixara" + S + r"de|deixaram" + S + r"de)" + S
     + r"(foi" + S + r"|foram" + S + r"|sera" + S + r"|serao" + S + r"|ira" + S + r")?(realiz\w*|efetu\w*|honr\w*|pag\w*|quit\w*|liquid\w*)" + GAP % 80
     + r"(pagamento|amortizacao|juros|remuneracao|parcela|principal|cupom)"),
    ("vencimento_antecipado_ou_default", "DF2_evento_inadimplemento", "forte", r"evento" + S + r"de" + S + r"inadimplemento|inadimplemento" + S
     + r"(financeiro|pecuniario|de" + S + r"obrigac\w*" + S + r"pecuniaria)"),
    ("vencimento_antecipado_ou_default", "DF3_fim_prazo_cura", "forte", r"(termino|fim|encerr\w*|decurso|expir\w*)" + GAP % 30 + r"prazo" + S + r"de" + S + r"cura"),
    ("vencimento_antecipado_ou_default", "DF4_default", "fraco", r"\bdefault\b"),
    ("standstill_mediacao_cautelar", "ST1_standstill", "forte", r"standstill|acordo" + S + r"de" + S + r"espera"),
    ("standstill_mediacao_cautelar", "MD1_mediacao", "forte", r"(pedido|procedimento|instaura\w*|requer\w*|inici\w*)" + GAP % 40 + r"mediacao|mediacao" + S
     + r"(com|junto|perante|antecedente)" + GAP % 40 + r"credores|\b20-?\s?b\b"),
    ("standstill_mediacao_cautelar", "CT1_cautelar", "forte", r"(tutela|medida|acao)" + S + r"(de" + S + r"urgencia" + S + r")?cautelar|cautelar" + S + r"(antecedente|preparatoria)"),
    ("standstill_mediacao_cautelar", "RS1_reestruturacao", "fraco", r"reestrutura\w*|reorganizacao" + S + r"(financeira|de" + S + r"dividas|do" + S + r"passivo)|equaciona\w*" + GAP % 30 + r"(divida|passivo|financeir)"),
    ("standstill_mediacao_cautelar", "RP1_repactuacao", "fraco", r"encargos" + S + r"moratorios|perdao" + GAP % 40 + r"(divida|debito|encargos|juros|multa)|bonus" + S + r"de" + S + r"adimplemento|reperfilamento|reescalonamento|alongamento" + S + r"d[ao]s?" + S + r"(divida|passivo|prazo)|renegocia\w*" + GAP % 40 + r"(divida|passivo|credores|debentur\w*)|carencia" + S + r"(de|do|para)" + GAP % 30 + r"(principal|juros|pagamento)|prorrogacao" + S + r"d[eo]" + S + r"(prazo" + S + r"de" + S + r")?pagamento"),
    ("standstill_mediacao_cautelar", "SU1_suspensao", "fraco", r"suspensao" + S + r"d[ao]s?" + S + r"(exigibilidade|pagamentos?|cobrancas?|execuc\w*)"),
]
RX_GATILHOS = [(t, n, f, re.compile(rx)) for t, n, f, rx in GATILHOS]

# flags de contexto, avaliadas na frase do disparo (excluindo o proprio trecho casado quando indicado)
RX_NEGACAO = re.compile(r"\b(nao|nem|jamais|inexist\w*|nenhum\w*|afast\w*|renunci\w*|waiver|dispens\w*|improceden\w*|indeferi\w*|extint\w*|"
                        r"rejeit\w*|desist\w*|arquivad\w*|elisivo|elidi\w*|quitad\w*|quitacao)\b")
RX_NEG_FALSA = re.compile(r"nao" + S + r"obstante|nao" + S + r"apenas|nao" + S + r"so\b|se" + S + r"nao" + S + r"for")
# Hipotetico tira o disparo do caminho material e e a UNICA via para nao_evento com gatilho forte presente, entao fica
# restrito a modais claros (o lado perigoso e o falso negativo; falso positivo vai a revisao).
RX_HIPOTETICO = re.compile(r"\b(pode|podem|podera|poderao|poderia|poderiam|possa|possam|eventual|eventuais|eventualmente|hipotese|hipoteses|"
                           r"caso" + S + r"(a|o|as|os|haja|ocorra|venha|seja|sejam|nao|exista)|venha\w*" + S + r"a|vier\w*" + S + r"a|"
                           r"sujeit\w*" + S + r"a|clausulas?|covenants?|qualquer|quaisquer|se" + S + r"(houver|ocorrer)|preve|prever|"
                           r"fatores" + S + r"de" + S + r"risco|condicoes" + S + r"de" + S + r"vencimento)\b")
RX_INTENCAO = re.compile(r"\b(estud\w*|avali\w*|alternativas|contrat\w*" + GAP % 30 + r"(assessor|consultor|escritorio)\w*|convoca\w*|edital|"
                         r"propost\w*|pretend\w*|intenc\w*|negocia\w*|tratativas|analis\w*|considera\w*|visando|objetivo" + S + r"de)\b")
RX_TERCEIRO = re.compile(r"\b(controlad[ao]s?|subsidiari[ao]s?|investid[ao]s?|controlador[ao]?|coligad[ao]s?|devedor[ao]?s?|cedentes?|lastro|"
                         r"cri\b|cra\b|clientes?|fornecedor\w*|contraparte\w*|patrocinador\w*|afretador\w*|acionista" + S + r"controlador\w*|"
                         r"holding|empresas?" + S + r"do" + S + r"grupo)")
RX_CONJUNTO = re.compile(r"\be" + S + r"(parte" + S + r"de" + S + r")?(suas|seus|demais|outras)" + S + r"(controladas|subsidiarias|empresas|sociedades)|(companhia|emissora|sociedade)" + GAP % 25 + r"(e|,|juntamente" + S + r"com|em" + S + r"conjunto" + S + r"com)" + S
                         + r"(suas|as|outras|demais)" + GAP % 20 + r"(controladas|subsidiarias|sociedades)|litisconsorcio|requerentes|"
                         r"em" + S + r"conjunto" + S + r"com" + S + r"(a" + S + r")?(companhia|emissora)|inclusive" + S + r"a" + S + r"companhia")
RX_PROPRIA = re.compile(r"\b(a|esta|nossa)" + S + r"(companhia|emissora|sociedade)\b")
RX_CONTINUIDADE = re.compile(r"em" + S + r"continuidade|em" + S + r"complemento|conforme" + GAP % 40 + r"(fatos?" + S + r"relevantes?|comunicados?)"
                             + GAP % 30 + r"(divulgad\w*|publicad\w*|de" + S + r"\d)|no" + S + r"ambito" + S + r"d[ao]" + GAP % 30
                             + r"(processo|recuperacao|plano|mediacao|cautelar|reestruturacao)|processo" + S + r"(n\W|numero)|autos")
RX_CREDORES_GERAL = re.compile(r"credores|dividas|vencimento" + S + r"antecipado" + S + r"d[ao]s" + S + r"(dividas|debentures|contratos)|"
                               r"recuperacao|20-?\s?b|mediacao|execucoes|exigibilidade")
RX_INSUFICIENCIA = re.compile(r"insuficiencia" + S + r"de" + S + r"(caixa|recursos|liquidez)|falta" + S + r"de" + S + r"(caixa|recursos|liquidez)")

# metadado do dia (categoria + assunto) que impede nao_evento automatico
RX_META_FORTE = re.compile(r"recuperacao" + S + r"(judicial|extrajudicial)|falencia|vencimento" + S + r"antecipado|inadimpl|\bdefault\b|standstill|"
                           r"cautelar|mediacao|chapter" + S + r"11|nao" + S + r"pagamento|suspensao" + S + r"(do" + S + r"|dos" + S + r")?pagamento")
RX_META_TIPO = [
    ("falencia", re.compile(r"falencia")),
    ("RJ", re.compile(r"recuperacao" + S + r"judicial|chapter" + S + r"11")),
    ("RE", re.compile(r"recuperacao" + S + r"extrajudicial")),
    ("vencimento_antecipado_ou_default", re.compile(r"vencimento" + S + r"antecipado|inadimpl|\bdefault\b|nao" + S + r"pagamento")),
    ("standstill_mediacao_cautelar", re.compile(r"standstill|cautelar|mediacao")),
]

MESES = {"janeiro": 1, "fevereiro": 2, "marco": 3, "abril": 4, "maio": 5, "junho": 6, "julho": 7, "agosto": 8, "setembro": 9,
         "outubro": 10, "novembro": 11, "dezembro": 12}
RX_DATA = re.compile(r"\b(\d{1,2})(?:o|º)?" + S + r"de" + S + r"(" + "|".join(MESES) + r")" + S + r"de" + S + r"(\d{4})\b|\b(\d{1,2})/(\d{1,2})/(\d{4})\b")


# ---------------------------------------------------------------- utilitarios de janela e trecho


def janela(base, a, b):
    """Frase em torno de [a,b): recua ate fim de frase anterior e avanca ate o proximo, com teto de JANELA_MAX."""
    ini = max(0, a - JANELA_MAX)
    seg = base[ini:a]
    m = None
    for m in re.finditer(r"[.!?;]\s|\n\s*\n", seg):
        pass
    ja = ini + m.end() if m else ini
    seg2 = base[b:b + JANELA_MAX]
    m2 = re.search(r"[.!?;]\s|\n\s*\n", seg2)
    jb = b + m2.start() + 1 if m2 else min(len(base), b + JANELA_MAX)
    return ja, jb


def trecho_literal(txt, a, b):
    """Ate PALAVRAS_TRECHO palavras, fatia CONTIGUA do original (limites em espaco), espacos colapsados."""
    off = max(0, a - JANELA_MAX)
    fim = min(len(txt), b + JANELA_MAX)
    ja, jb = janela(base_alinhada(txt[off:fim]), a - off, b - off)
    ja, jb = ja + off, jb + off
    L = a
    while L > ja and not txt[L - 1].isspace():
        L -= 1
    R = b
    while R < jb and not txt[R].isspace():
        R += 1
    antes = txt[ja:L].split()
    alvo = txt[L:R].split()
    depois = txt[R:jb].split()
    resto = max(0, PALAVRAS_TRECHO - len(alvo))
    nd = min(len(depois), resto // 2)
    na = min(len(antes), resto - nd)
    nd = min(len(depois), resto - na)
    palavras = antes[len(antes) - na:] + alvo + depois[:nd]
    if len(palavras) > PALAVRAS_TRECHO:
        k = palavras.index(alvo[0]) if alvo else 0
        palavras = palavras[max(0, k - (PALAVRAS_TRECHO - len(alvo)) // 2):][:PALAVRAS_TRECHO]
    return " ".join(palavras)


def confere(trecho, txt):
    return bool(trecho) and txt is not None and norm_trecho(trecho) in norm_trecho(txt)


def datas_citadas(s):
    out = []
    for m in RX_DATA.finditer(s):
        try:
            if m.group(1):
                out.append(dt.date(int(m.group(3)), MESES[m.group(2)], int(m.group(1))))
            else:
                out.append(dt.date(int(m.group(6)), int(m.group(5)), int(m.group(4))))
        except ValueError:
            pass
    return out


# ---------------------------------------------------------------- disparos de um documento


RX_PRE = re.compile(r"recupera|falenc|vencimento|inadimpl|default|standstill|acordo" + S + r"de" + S + r"espera|cautelar|mediacao|"
                    r"chapter|capitulo|20-?\s?b|prazo" + S + r"de" + S + r"cura|nao" + S + r"(foi|foram|sera|serao|ira|realiz|efetu|honr|pag|quit|liquid)|"
                    r"deixou|deixara|deixaram|suspensao|convola|recuperanda|reestrutura|reorganizacao|equaciona|moratorio|perdao|bonus|reperfil|reescalon|alongamento|renegoci|carencia|prorrogacao")
_CACHE_DISP = {}


def disparos_doc(p, txt):
    """Todo gatilho no texto integral, com flags da frase. Determinista (ordem do texto, depois ordem da regra).
    Cache por (protocolo, tamanho do texto): o mesmo documento aparece como contexto de varios itens."""
    if txt is None or len(txt.strip()) < MIN_TEXTO:
        return []
    k = (p, len(txt), hash(txt))
    if k not in _CACHE_DISP:
        if len(_CACHE_DISP) > 4000:
            _CACHE_DISP.clear()
        _CACHE_DISP[k] = _disparos_doc(p, txt)
    return [dict(h) for h in _CACHE_DISP[k]]


def _disparos_doc(p, txt):
    base = base_alinhada(txt)
    if not RX_PRE.search(base):
        return []
    out = []
    for tipo, nome, forca, rx in RX_GATILHOS:
        for m in rx.finditer(base):
            a, b = m.start(), m.end()
            ja, jb = janela(base, a, b)
            frase = base[ja:jb]
            fora = base[ja:a] + " " + base[b:jb]          # frase sem o proprio casamento
            neg_txt = RX_NEG_FALSA.sub(" ", fora)
            negado = bool(RX_NEGACAO.search(neg_txt))
            if nome == "DF1_nao_pagamento":
                negado = bool(RX_NEGACAO.search(RX_NEG_FALSA.sub(" ", fora)))
            hip = bool(RX_HIPOTETICO.search(fora))
            inten = bool(RX_INTENCAO.search(fora))
            terc = bool(RX_TERCEIRO.search(frase))
            conj = bool(RX_CONJUNTO.search(frase))
            propria = bool(RX_PROPRIA.search(frase))
            out.append({
                "protocolo": p, "tipo": tipo, "regra": nome, "forca": forca, "pos": [a, b],
                "negado": negado, "hipotetico": hip, "intencao": inten, "terceiro": terc and not conj, "conjunto": conj,
                "propria": propria, "continuidade": bool(RX_CONTINUIDADE.search(frase)),
                "credores_geral": bool(RX_CREDORES_GERAL.search(frase)), "insuficiencia": bool(RX_INSUFICIENCIA.search(frase)),
                "datas": [d.isoformat() for d in datas_citadas(frase)],
                "trecho": trecho_literal(txt, a, b),
            })
    out.sort(key=lambda h: (h["pos"][0], [g[1] for g in GATILHOS].index(h["regra"])))
    return out


def material(h):
    """Disparo que afirma ato consumado da propria companhia (ou pedido conjunto)."""
    return h["forca"] == "forte" and not h["negado"] and not h["hipotetico"] and not h["intencao"] and not h["terceiro"]


def de_terceiro(h):
    return h["forca"] == "forte" and not h["negado"] and not h["hipotetico"] and not h["intencao"] and h["terceiro"]


def ordem_tipo(t):
    return TIPOS_ORDEM.index(t)


# ---------------------------------------------------------------- decisao do item


def classificar(item, man_item, meta, ler_texto):
    """item {id,cnpj,data}; man_item {dia, contexto_180d, indice_24m}; meta {protocolo: {data_entrega, categoria, assunto}};
    ler_texto(p) -> str|None. Devolve o registro do item (sem efeitos colaterais)."""
    data_c = dt.date.fromisoformat(item["data"])
    entradas, motivos, disparos = [], [], []
    textos = {}

    def texto(p):
        if p not in textos:
            textos[p] = ler_texto(p)
        return textos[p]

    # 1. documentos do dia: leitura integral
    dia_legivel, dia_ilegivel = [], []
    for p in man_item["dia"]:
        t = texto(p)
        ok = t is not None and len(t.strip()) >= MIN_TEXTO
        entradas.append({"protocolo": p, "grupo": "dia", "data_entrega": meta.get(p, {}).get("data_entrega"),
                         "categoria": meta.get(p, {}).get("categoria"), "tem_texto": ok, "chars": len(t) if t else 0,
                         "baixado": t is not None})
        (dia_legivel if ok else dia_ilegivel).append(p)
        hs = disparos_doc(p, t) if ok else []
        for h in hs:
            h["grupo"] = "dia"
        disparos += hs

    meta_dia = " || ".join(sem_acento("%s %s" % (meta.get(p, {}).get("categoria", ""), meta.get(p, {}).get("assunto", ""))) for p in man_item["dia"])
    meta_forte = bool(RX_META_FORTE.search(meta_dia))
    meta_tipos = [t for t, rx in RX_META_TIPO if rx.search(meta_dia)]

    # 2. contexto 180d (so para origem/continuidade e registro previo de inadimplemento): disparos materiais anteriores
    ctx_disp, ctx_sem_texto = [], []
    for p in man_item["contexto_180d"]:
        de = meta.get(p, {}).get("data_entrega")
        if not de or de >= item["data"]:
            continue
        t = texto(p)
        ok = t is not None and len(t.strip()) >= MIN_TEXTO
        entradas.append({"protocolo": p, "grupo": "180d", "data_entrega": de, "categoria": meta.get(p, {}).get("categoria"),
                         "tem_texto": ok, "chars": len(t) if t else 0, "baixado": t is not None})
        if not ok:
            ctx_sem_texto.append(p)
            continue
        for h in disparos_doc(p, t):
            if material(h):
                h["grupo"] = "180d"
                h["data_entrega"] = de
                ctx_disp.append(h)
    ctx_completo = not ctx_sem_texto
    textos.clear()

    # metadado do indice (180d sem texto e 24m) que sugere processo anterior
    idx_prev = []
    for p in man_item["contexto_180d"]:
        if p in ctx_sem_texto:
            ms = sem_acento("%s %s" % (meta.get(p, {}).get("categoria", ""), meta.get(p, {}).get("assunto", "")))
            for t, rx in RX_META_TIPO:
                if rx.search(ms):
                    idx_prev.append({"protocolo": p, "data_entrega": meta[p]["data_entrega"], "tipo": t, "fonte": "180d_sem_texto"})
    for x in man_item.get("indice_24m", []):
        if x.get("data", "") >= item["data"]:
            continue
        ms = sem_acento("%s %s" % (x.get("categoria", ""), x.get("assunto", "")))
        for t, rx in RX_META_TIPO:
            if rx.search(ms):
                idx_prev.append({"protocolo": str(x.get("protocolo_rad")), "data_entrega": x["data"], "tipo": t, "fonte": "24m_metadado"})

    reg = {"id": item["id"], "cnpj": item["cnpj"], "data": item["data"], "versao": VERSAO,
           "classe": None, "tipo": None, "data_evento": None, "protocolo_evento": None, "trecho_evento": None,
           "origem": None, "adicionais": [], "revisao_obrigatoria": False, "motivos_revisao": motivos, "caminho": None,
           "confianca": None, "disparos": disparos, "disparos_contexto": ctx_disp[:50], "indice_previo": idx_prev[:50],
           "meta_dia_forte": meta_forte, "meta_dia_tipos": meta_tipos, "contexto_completo": ctx_completo,
           "contexto_sem_texto": len(ctx_sem_texto), "entradas": entradas}

    def fim(classe, caminho, confianca, **kw):
        reg.update(kw)
        reg["classe"], reg["caminho"], reg["confianca"] = classe, caminho, confianca
        reg["revisao_obrigatoria"] = bool(motivos) or classe in ("evento_proprio", "continuacao", "evento_terceiro", "PENDENTE_REVISAO") or confianca == "baixa"
        return reg

    if not dia_legivel:
        motivos.append("ilegivel: nenhum documento do dia com texto extraivel")
        return fim("PENDENTE_REVISAO", "ilegivel_total", "baixa")
    if dia_ilegivel:
        motivos.append("ilegivel_parcial: %d documento(s) do dia sem texto" % len(dia_ilegivel))

    proprios = [h for h in disparos if material(h)]
    terceiros = [h for h in disparos if de_terceiro(h)]
    negados = [h for h in disparos if h["forca"] == "forte" and h["negado"] and not h["hipotetico"]]
    intencoes = [h for h in disparos if h["forca"] == "forte" and h["intencao"] and not h["negado"] and not h["hipotetico"]]
    fracos = [h for h in disparos if h["forca"] == "fraco" and not h["negado"] and not h["hipotetico"] and not h["terceiro"]]

    def origem_previa(tipos):
        """Primeiro documento anterior (180d com texto) com disparo material de um dos tipos, ou metadado do indice."""
        cand = sorted((h for h in ctx_disp if h["tipo"] in tipos), key=lambda h: (h["data_entrega"], h["pos"][0]))
        if cand:
            h = cand[0]
            return {"protocolo": h["protocolo"], "data_entrega": h["data_entrega"], "tipo": h["tipo"], "trecho": h["trecho"],
                    "regra": h["regra"], "completa": True}
        meta_c = sorted((x for x in idx_prev if x["tipo"] in tipos), key=lambda x: x["data_entrega"])
        if meta_c:
            x = meta_c[0]
            return {"protocolo": x["protocolo"], "data_entrega": x["data_entrega"], "tipo": x["tipo"], "trecho": None,
                    "regra": "metadado_indice:" + x["fonte"], "completa": False}
        return None

    def conflito_temporal(hs, origem):
        if origem:
            return False
        for h in hs:
            for d in h["datas"]:
                dd = dt.date.fromisoformat(d)
                if dd < data_c - dt.timedelta(days=DIAS_CONFLITO) and dd > data_c - dt.timedelta(days=3650):
                    return True
        return False

    # 3. evento da propria companhia
    if proprios:
        por_tipo = {}
        for h in proprios:
            por_tipo.setdefault(h["tipo"], []).append(h)
        tipos = sorted(por_tipo, key=ordem_tipo)
        princ_tipo = tipos[0]
        h0 = por_tipo[princ_tipo][0]

        # standstill sem registro de inadimplemento/insuficiencia/VA/RJ/RE/mediacao => nao_evento (item 2)
        so_standstill = princ_tipo == "standstill_mediacao_cautelar" and all(h["regra"] == "ST1_standstill" for h in por_tipo[princ_tipo])
        cautelar_isolada = princ_tipo == "standstill_mediacao_cautelar" and all(h["regra"] == "CT1_cautelar" for h in por_tipo[princ_tipo]) \
            and not any(h["credores_geral"] for h in por_tipo[princ_tipo])
        if so_standstill:
            fato = [h for h in proprios + ctx_disp if h["tipo"] in ("RJ", "RE", "vencimento_antecipado_ou_default") or h["regra"] == "MD1_mediacao"] \
                + [h for h in disparos + ctx_disp if h.get("insuficiencia") and not h["negado"] and not h["hipotetico"]]
            if fato:
                f0 = sorted(fato, key=lambda h: (h.get("data_entrega") or item["data"], h["pos"][0]))[0]
                motivos.append("standstill com registro previo de fato de credito (%s)" % f0["regra"])
                return fim("evento_proprio", "proprio_standstill_com_fato", "media", tipo=f0["tipo"] if f0["tipo"] != "standstill_mediacao_cautelar" else "standstill_mediacao_cautelar",
                           data_evento=f0.get("data_entrega") or item["data"], protocolo_evento=f0["protocolo"], trecho_evento=f0["trecho"])
            if not ctx_completo:
                motivos.append("standstill sem registro previo verificavel: contexto de 180 dias incompleto")
                return fim("PENDENTE_REVISAO", "standstill_contexto_incompleto", "baixa")
            motivos.append("standstill sem inadimplemento registrado (nao_evento pelo item 2), material")
            return fim("nao_evento", "standstill_sem_fato", "media")
        if cautelar_isolada:
            motivos.append("cautelar sem alcance geral de credores verificavel (litigio individual?)")
            return fim("PENDENTE_REVISAO", "cautelar_ambigua", "baixa")

        familia = [princ_tipo] + (["standstill_mediacao_cautelar"] if princ_tipo in ("RJ", "RE") else []) \
            + (["RJ", "RE"] if princ_tipo == "standstill_mediacao_cautelar" else []) + (["RJ"] if princ_tipo == "falencia" else [])
        org = origem_previa(familia)
        marcador = any(h["continuidade"] for h in por_tipo[princ_tipo]) or any(h["regra"] in ("RJ4_status", "RE4_status") for h in fracos)
        adic = []
        for t in tipos[1:]:
            if t in familia:
                continue
            hx = por_tipo[t][0]
            adic.append({"classe": "evento_proprio", "data_ou_origem": item["data"], "protocolo": hx["protocolo"], "trecho": hx["trecho"], "tipo": t})
        if adic:
            motivos.append("evento adicional de tipo distinto (%s)" % ", ".join(a["tipo"] for a in adic))
        if org:
            motivos.append("continuidade: documento anterior do mesmo CNPJ registra fato do mesmo processo")
            if not org["completa"]:
                motivos.append("origem so por metadado do indice, sem texto para trecho literal")
                return fim("PENDENTE_REVISAO", "continuacao_origem_incompleta", "baixa", origem=org, adicionais=adic)
            return fim("continuacao", "continuacao_origem_texto", "media", origem=org, adicionais=adic,
                       tipo=princ_tipo, protocolo_evento=h0["protocolo"], trecho_evento=h0["trecho"])
        if marcador and not ctx_completo:
            motivos.append("texto indica processo em curso e o contexto de 180 dias esta incompleto")
            return fim("PENDENTE_REVISAO", "continuidade_nao_verificavel", "baixa", adicionais=adic)
        if conflito_temporal(por_tipo[princ_tipo], org):
            motivos.append("conflito temporal: ato narrado com data anterior a 30 dias sem documento anterior no contexto")
        motivos.append("positivo material")
        return fim("evento_proprio", "proprio_documento_do_dia", "alta" if not marcador else "media", tipo=princ_tipo,
                   data_evento=item["data"], protocolo_evento=h0["protocolo"], trecho_evento=h0["trecho"], adicionais=adic)

    # 4. fato de credito de terceiro
    if terceiros:
        motivos.append("entidade: ato de credito possivelmente de terceiro (subsidiaria, investida, controladora, devedor de lastro), titularidade exige leitura")
        h = terceiros[0]
        return fim("PENDENTE_REVISAO", "entidade_terceiro", "baixa", tipo=h["tipo"], protocolo_evento=h["protocolo"], trecho_evento=h["trecho"])

    # 5. negacao de fato material: renuncia a vencimento por inadimplemento pecuniario ainda e evento (item 2)
    if negados:
        motivos.append("negacao sobre gatilho material (renuncia, indeferimento, inexistencia): decisao exige leitura")
        return fim("PENDENTE_REVISAO", "negacao", "baixa")

    # 6. sinais fracos nao hipoteticos ou metadado forte: nunca nao_evento automatico
    status = [h for h in fracos if h["regra"] in ("RJ4_status", "RE4_status")]
    if status:
        t = status[0]["tipo"]
        org = origem_previa([t, "standstill_mediacao_cautelar"])
        motivos.append("companhia em processo de recuperacao ja em curso (status no texto)")
        if org and org["completa"]:
            return fim("continuacao", "continuacao_status", "media", origem=org, tipo=t, protocolo_evento=status[0]["protocolo"], trecho_evento=status[0]["trecho"])
        return fim("PENDENTE_REVISAO", "status_recuperacao_sem_origem", "baixa", origem=org)
    if fracos:
        motivos.append("sinal fraco nao hipotetico (%s)" % ", ".join(sorted({h["regra"] for h in fracos})))
        return fim("PENDENTE_REVISAO", "sinal_fraco", "baixa")
    if intencoes:
        motivos.append("intencao contra ato: gatilho material em contexto de estudo, proposta ou negociacao")
        return fim("PENDENTE_REVISAO", "intencao", "baixa")
    if meta_forte:
        motivos.append("metadado do dia com termo forte (%s) sem gatilho material no texto" % ",".join(meta_tipos))
        return fim("PENDENTE_REVISAO", "conflito_metadado", "baixa")
    if dia_ilegivel:
        return fim("PENDENTE_REVISAO", "ilegivel_parcial", "baixa")

    hip = [h for h in disparos if h["forca"] == "forte" and h["hipotetico"]]
    if hip:
        return fim("nao_evento", "so_hipotetico", "media")
    return fim("nao_evento", "sem_gatilho", "alta")
