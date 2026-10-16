"""Recuperacao progressiva e deterministica de documentos para a rotulagem (proposta G0-v3, nao congelada).

Nada aqui filtra documento por categoria nem por RX_LARGO: TODO documento do indice entra no pacote. O que
muda em relacao a G0-v2 e QUANTO texto de cada documento entra sem pedido:

  Nivel 0  guia congelado, ficha do candidato e INDICE INTEGRAL (dia, 180 dias, 24 meses: data, categoria,
           assunto, protocolo, n de paginas, se tem texto). Sempre.
  Nivel 1  documentos do dia: cabecalho (primeiros CAB_DIA caracteres) + ancoras; documentos dos 180 dias:
           cabecalho (CAB_CTX) + ancoras. Ancora = janela de +-JANELA caracteres em torno de cada ocorrencia
           de um termo da lista ANCORAS (fixa, maior que RX_LARGO, inclui titularidade, prazo e pagamento),
           janelas sobrepostas fundidas, ordem do texto, teto por documento. Sempre.
  Nivel 2  sob pedido do rotulador: paginas de qualquer documento do indice (inclusive dos 24 meses), por
           protocolo e faixa de paginas, ate RODADAS rodadas e TETO_N2 caracteres por rodada. Documento nao
           baixado e baixado na hora pelo baixar_etapa1 (mesma proveniencia). Todo pedido e todo trecho
           servido ficam registrados com sha256.

Recuperacao de evidencia: todo trecho literal citado no rotulo e conferido contra o texto INTEGRAL do documento
citado (verificar_trecho). Trecho que nao esta no documento invalida o rotulo (vai a adjudicacao).
Determinismo: mesmo indice e mesmos textos => mesmo pacote byte a byte (sha256 no registro).
"""
import hashlib
import json
import os
import re
import unicodedata

CAB_DIA, CAB_CTX = 12000, 1200
JANELA = 350
TETO_ANCORA_DIA, TETO_ANCORA_CTX = 24000, 2400
RODADAS, TETO_N2 = 3, 60000
ANCORAS = (
    r"recupera\w* (judicial|extrajudicial)", r"falenc\w*", r"autofalenc\w*", r"credor\w*", r"divida\w*",
    r"debentur\w*", r"vencimento antecipado", r"inadimpl\w*", r"\bdefault\b", r"standstill", r"cautelar\w*",
    r"tutela", r"20-b", r"reestrutura\w*", r"mediacao", r"chapter 11", r"waiver", r"repactua\w*",
    r"nao pagamento", r"suspensao", r"prazo de cura", r"\bcura\b", r"remuneracao das debentures", r"juros",
    r"amortizac\w*", r"assembleia geral de debenturistas", r"\bagd\b", r"agente fiduciario", r"ajuiza\w*",
    r"deferi\w*", r"homolog\w*", r"plano de recuperacao", r"protesto\w*", r"execuc\w*", r"quitac\w*",
    r"deposito elisivo", r"requerente\w*", r"controlad[ao]\w*", r"subsidiari\w*", r"consolidacao substancial",
    r"novacao", r"insuficiencia de caixa", r"liquidez", r"\bstay\b", r"em continuidade", r"em complemento",
    r"processo n", r"autos", r"acordo com (os |seus )?credores", r"credores financeiros",
)
RX_ANCORA = re.compile("|".join("(?:%s)" % a for a in ANCORAS))


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn").lower()


def limpa(txt):
    txt = txt.replace("\r\n", "\n")
    txt = re.sub(r"[ \t]+", " ", txt)
    return re.sub(r"\n{3,}", "\n\n", txt).strip()


def paginas(txt):
    """pdftotext separa pagina por form feed. Sem form feed, uma pagina so."""
    return [p for p in txt.split("\f")] if "\f" in txt else [txt]


def ancoras(txt, teto):
    """Janelas deterministicas em torno dos termos. O casamento e feito no texto sem acento, que tem o mesmo
    comprimento do original quando a normalizacao so remove diacriticos combinantes de letras pre-compostas;
    para garantir alinhamento, a busca roda sobre a versao sem acento caractere a caractere."""
    base = "".join(sem_acento(c)[:1] or " " for c in txt)
    spans = []
    for m in RX_ANCORA.finditer(base):
        a, b = max(0, m.start() - JANELA), min(len(txt), m.end() + JANELA)
        if spans and a <= spans[-1][1]:
            spans[-1][1] = max(spans[-1][1], b)
        else:
            spans.append([a, b])
    out, tam = [], 0
    for a, b in spans:
        pedaco = "[...%d] %s" % (a, limpa(txt[a:b]))
        if tam + len(pedaco) > teto:
            out.append("[ANCORAS CORTADAS NO TETO DE %d CARACTERES; pedir paginas no nivel 2]" % teto)
            break
        out.append(pedaco)
        tam += len(pedaco)
    return out


def ler_txt(txt_dir, p):
    f = os.path.join(txt_dir, "%s.txt" % p)
    if not os.path.exists(f):
        return None
    with open(f, encoding="utf-8", errors="ignore") as fh:
        return fh.read()


def bloco_doc(p, meta, txt, cab, teto):
    m = meta[p]
    cabecalho = "[protocolo %s | Data_Entrega %s | %s | assunto: %s" % (p, m["data_entrega"], m["categoria"], m["assunto"] or "(vazio)")
    if txt is None:
        return cabecalho + " | NAO BAIXADO: pedir no nivel 2]"
    if len(txt.strip()) < 80:
        return cabecalho + " | SEM TEXTO EXTRAIVEL (escaneado ou Word antigo): pedir pagina renderizada no nivel 2]"
    pg = paginas(txt)
    corpo = limpa(txt)
    partes = [cabecalho + " | %d paginas | %d caracteres]" % (len(pg), len(corpo))]
    if len(corpo) <= cab:
        partes.append(corpo)
        return "\n".join(partes)
    partes.append("CABECALHO:\n" + corpo[:cab])
    anc = ancoras(corpo[cab:], teto)
    partes.append("ANCORAS DO RESTANTE (%d):\n" % len(anc) + ("\n".join(anc) if anc else "(nenhuma)"))
    return "\n".join(partes)


def pacote(item, man_item, meta, txt_dir):
    """Niveis 0 e 1 de um item. Devolve (texto, registro) com sha256 do pacote."""
    idx = []
    for grupo, lista in (("dia", man_item["dia"]), ("180d", man_item["contexto_180d"])):
        for p in lista:
            t = ler_txt(txt_dir, p)
            idx.append("%s | %s | %s | %s | protocolo %s | %s" % (
                grupo, meta[p]["data_entrega"], meta[p]["categoria"], meta[p]["assunto"] or "(vazio)", p,
                "sem texto" if (t is not None and len(t.strip()) < 80) else ("nao baixado" if t is None else "%d pag" % len(paginas(t)))))
    for x in man_item["indice_24m"]:
        idx.append("24m | %s | %s | %s | protocolo %s | so metadado" % (x["data"], x["categoria"], x["assunto"] or "(vazio)", x["protocolo_rad"]))
    partes = [
        "=== CANDIDATO ===\nCNPJ %s | Data_Entrega do candidato %s" % (item["cnpj"], item["data"]),
        "=== INDICE INTEGRAL (%d documentos) ===\n%s" % (len(idx), "\n".join(idx)),
        "=== DOCUMENTOS DO DIA (cabecalho e ancoras) ===\n" + "\n\n".join(
            bloco_doc(p, meta, ler_txt(txt_dir, p), CAB_DIA, TETO_ANCORA_DIA) for p in man_item["dia"]),
        "=== DOCUMENTOS DOS 180 DIAS ANTERIORES (cabecalho e ancoras) ===\n" + ("\n\n".join(
            bloco_doc(p, meta, ler_txt(txt_dir, p), CAB_CTX, TETO_ANCORA_CTX) for p in man_item["contexto_180d"]) or "(nenhum)"),
    ]
    texto = "\n\n".join(partes)
    return texto, {"id": item["id"], "sha256_pacote": hashlib.sha256(texto.encode("utf-8")).hexdigest(),
                   "chars": len(texto), "docs_indice": len(idx),
                   "nao_baixados": sum(1 for p in man_item["dia"] + man_item["contexto_180d"] if ler_txt(txt_dir, p) is None)}


def servir_nivel2(pedidos, permitidos, txt_dir):
    """pedidos: [{"protocolo": "...", "paginas": "3-7"}]. So protocolos do indice do item (permitidos).
    Devolve (texto, log). Fora do indice e recusado e registrado."""
    out, log, tam = [], [], 0
    for ped in pedidos:
        p = str(ped.get("protocolo"))
        if p not in permitidos:
            log.append({"protocolo": p, "status": "recusado_fora_do_indice"})
            continue
        t = ler_txt(txt_dir, p)
        if t is None or len(t.strip()) < 80:
            log.append({"protocolo": p, "status": "sem_texto" if t is not None else "nao_baixado"})
            out.append("[protocolo %s: %s]" % (p, "sem texto extraivel" if t is not None else "nao baixado"))
            continue
        pg = paginas(t)
        m = re.fullmatch(r"(\d+)(?:-(\d+))?", str(ped.get("paginas", "1")).strip())
        a, b = (int(m.group(1)), int(m.group(2) or m.group(1))) if m else (1, 1)
        a, b = max(1, a), min(len(pg), b)
        trecho = limpa("\f".join(pg[a - 1:b]))
        if tam + len(trecho) > TETO_N2:
            trecho = trecho[:max(0, TETO_N2 - tam)] + "\n[CORTADO NO TETO DO NIVEL 2]"
        tam += len(trecho)
        out.append("[protocolo %s | paginas %d-%d de %d]\n%s" % (p, a, b, len(pg), trecho))
        log.append({"protocolo": p, "paginas": [a, b], "chars": len(trecho),
                    "sha256": hashlib.sha256(trecho.encode("utf-8")).hexdigest(), "status": "servido"})
        if tam >= TETO_N2:
            break
    return "\n\n".join(out), log


def norm_trecho(s):
    return re.sub(r"\s+", " ", sem_acento(s or "")).strip()


def verificar_trecho(trecho, protocolo, txt_dir):
    """True se o trecho citado esta literalmente (espacos e acentos normalizados) no texto integral do documento."""
    t = ler_txt(txt_dir, str(protocolo))
    if not trecho or t is None:
        return False
    return norm_trecho(trecho) in norm_trecho(t)
