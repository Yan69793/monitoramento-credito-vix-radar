"""Monta o prompt de rotulagem de UM item da etapa 1, identico para o primeiro (Claude) e o segundo (Codex)
rotulador. Garante isolamento: o prompt tem so o guia congelado (item 2 do bloco G0-v2 + anexo), os documentos
do proprio item e o indice. Nunca camada, estrato, EWS, sinal, rotulo do outro avaliador, nem resultado.

Guia = item 2 do bloco (nota 116, sha256 5e91fe11...) + bloco do anexo (nota 117, sha256 6d3b0da7...), extraidos
byte a byte e conferidos contra a guarda antes de montar. Se a guarda reprovar, nada e montado.

Saida do rotulador: um unico JSON (esquema abaixo). Uma chamada por item, ambiente limpo, sem memoria.
"""
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v2 as G  # noqa: E402

LIM_DOC = 60000          # caracteres por documento; acima disso o texto e cortado e o corte e declarado
ESQUEMA = """Responda com UM unico objeto JSON, sem texto fora dele:
{"classe": "evento_proprio|evento_terceiro|continuacao|nao_evento|incerto",
 "tipo": "RJ|RE|falencia|vencimento_antecipado_ou_default|standstill_mediacao_cautelar|null",
 "data_evento": "AAAA-MM-DD ou null (Data_Entrega do primeiro documento que registra o ato consumado)",
 "protocolo_evento": "numProtocolo RAD do documento que fixa a data, ou null",
 "trecho_evento": "ate 30 palavras literais desse documento, ou null",
 "origem": null ou {"protocolo": "...", "data_entrega": "AAAA-MM-DD", "tipo": "...", "trecho": "ate 30 palavras literais"},
 "adicionais": [{"classe": "evento_proprio|continuacao", "data_ou_origem": "...", "protocolo": "...", "trecho": "..."}],
 "motivo_incerto": "inacessivel|sem_protocolo|duvida|null",
 "justificativa": "ate 60 palavras, sem conhecimento externo ao IPE"}"""


def guia():
    if not G.avaliar(G.verificar_protocolo(), G.verificar_anexo(), G.verificar_manifesto())[0]:
        raise SystemExit("guarda reprovou: guia nao e o congelado, nada e montado")
    bloco = G.extrair_bloco(G.ler(G.NOTA_116), G.MARC_G0)
    i = bloco.index("### 2. Rótulo, por candidato")
    j = bloco.index("### 3. Base de eventos")
    item2 = bloco[i:j]
    anexo = G.extrair_bloco(G.ler(G.NOTA_ANEXO), G.MARC_ANEXO)
    return item2.strip(), anexo.strip()


def corta(txt):
    txt = re.sub(r"[ \t]+\n", "\n", txt)
    txt = re.sub(r"\n{3,}", "\n\n", txt).strip()
    if len(txt) > LIM_DOC:
        return txt[:LIM_DOC] + "\n[TEXTO CORTADO: %d de %d caracteres]" % (LIM_DOC, len(txt))
    return txt


def montar(item, man_item, docs_meta, txt_dir):
    """item: {id,cnpj,data}. man_item: entrada do manifesto. docs_meta: {protocolo_rad: meta}. txt_dir: pasta TXT."""
    item2, anexo = guia()

    def doc(p, cheio=True):
        m = docs_meta[p]
        cab = "[protocolo %s | Data_Entrega %s | %s | assunto: %s]" % (p, m["data_entrega"], m["categoria"], m["assunto"] or "(vazio)")
        f = os.path.join(txt_dir, "%s.txt" % p)
        if cheio and os.path.exists(f):
            return cab + "\n" + corta(open(f, encoding="utf-8", errors="ignore").read())
        return cab + ("\n[SEM TEXTO EXTRAIDO OU NAO BAIXADO]" if cheio else "")
    partes = [
        "Voce rotula um candidato a evento de credito segundo o guia abaixo. Use SOMENTE os documentos IPE do mesmo CNPJ "
        "fornecidos aqui, com Data_Entrega igual ou anterior a do candidato. Nao use conhecimento externo, nao busque "
        "nada, nao suponha o que aconteceu depois. Se faltar documento para decidir, a classe e incerto com o motivo.",
        "=== GUIA: ITEM 2 DO PROTOCOLO G0-v2 (congelado) ===\n" + item2,
        "=== GUIA: ANEXO G0-v2 (congelado) ===\n" + anexo,
        "=== CANDIDATO ===\nCNPJ %s | Data_Entrega do candidato %s" % (item["cnpj"], item["data"]),
        "=== DOCUMENTOS DO DIA DO CANDIDATO ===\n" + ("\n\n".join(doc(p) for p in man_item["dia"]) or "(nenhum)"),
        "=== DOCUMENTOS DOS 180 DIAS ANTERIORES ===\n" + ("\n\n".join(doc(p) for p in man_item["contexto_180d"]) or "(nenhum)"),
        "=== INDICE DE 24 MESES (somente metadados; o texto nao foi fornecido) ===\n" + (
            "\n".join("%s | %s | %s | protocolo %s" % (x["data"], x["categoria"], x["assunto"] or "(vazio)", x["protocolo_rad"])
                      for x in man_item["indice_24m"]) or "(vazio)"),
        "=== FORMATO ===\n" + ESQUEMA,
    ]
    return "\n\n".join(partes)


if __name__ == "__main__":
    a, b = guia()
    print(json.dumps({"item2_chars": len(a), "anexo_chars": len(b)}))
