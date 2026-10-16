"""Guarda de hash do protocolo G0-v2 (nota 116) e do anexo-guia (nota 117), mais integridade da migracao.

Regra do hash, a mesma das notas 111 e 113: texto depois da linha do marcador de inicio ate o
marcador de fim (exclusive), UTF-8, quebra de linha LF. A linha do marcador de inicio nao entra,
o "\\n" que a termina tambem nao. Errar isso da 24.778 bytes e outro hash.

Veredito global (campo "ok", exit code): so e verdadeiro quando o bloco G0-v2 bate, o manifesto bate
E o anexo-guia esta congelado e bate. Anexo "nao_congelado" ou "divergente" reprova o global, porque
o item 2 do bloco diz que nenhum rotulo e feito antes do congelamento do anexo. Os diagnosticos
("protocolo", "anexo", "manifesto") continuam separados no JSON, e "motivos" diz por que reprovou.

Uso (exit 0 = pronto para rotular, 1 = algo impede):
  python -I scripts/predictive/validacao/guarda_g0v2.py
  python -I scripts/predictive/validacao/guarda_g0v2.py --hash-anexo   # so imprime sha256 e bytes do
                                                                        # bloco do anexo, para o registro
                                                                        # do congelamento (exit 0 sempre)
"""
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
VAULT = os.path.join(AQUI, "..", "..", "..", "Obsidian VIX Radar")
NOTA_116 = os.path.join(VAULT, "116 - EWS 2.0 Protocolo de Validacao G0-v2 RASCUNHO 2026-10-15.md")
NOTA_ANEXO = os.path.join(VAULT, "117 - EWS 2.0 G0-v2 Anexo-Guia RASCUNHO 2026-10-15.md")
MANIFESTO = os.path.join(AQUI, "MANIFESTO_G0V2.json")

MARC_G0 = ("<!-- G0-V2-INICIO -->", "<!-- G0-V2-FIM -->")
MARC_ANEXO = ("<!-- G0-V2-ANEXO-INICIO -->", "<!-- G0-V2-ANEXO-FIM -->")

# Congelado em 2026-10-15 (nota 116, secao "Congelamento do bloco G0-v2").
PROTOCOLO_G0V2_SHA256 = "5e91fe1104f057266cd0c40f9e5a88b14f44b3afe81526520f0d992cacb3bc7c"
PROTOCOLO_G0V2_BYTES = 24777
# Congelado em 2026-10-16 por aprovacao do operador das decisoes 1 a 3 da nota 117 (P1-P5, D1, D2).
# Hash conferido por dois metodos independentes (esta guarda e SHA256 do .NET). Mudanca no bloco do
# anexo a partir daqui exige versao nova do guia com sha256 proprio (item 4 da G0-v2).
ANEXO_SHA256 = "6d3b0da7912d5ce323235fbac6b3038140bb0dc841f28de4c2828184cac8ac73"
ANEXO_BYTES = 20866


def extrair_bloco(texto, marcadores):
    """Bloco entre marcadores, LF, sem a linha do marcador de inicio. ValueError se faltar
    marcador ou se algum aparecer mais de uma vez (marcador citado em prosa mudaria o bloco)."""
    ini, fim = marcadores
    t = "\n" + texto.replace("\r\n", "\n")
    # Marcador vale so em linha propria. A nota 116 cita os marcadores em prosa, entre crases,
    # depois do bloco, e essas citacoes nao podem contar.
    li, lf = "\n" + ini + "\n", "\n" + fim + "\n"
    if t.count(li) != 1 or t.count(lf) != 1:
        raise ValueError("marcador ausente ou repetido em linha propria: %s / %s" % (ini, fim))
    i = t.index(li) + len(li)
    f = t.index(lf) + 1
    if f < i:
        raise ValueError("marcador de fim antes do inicio")
    return t[i:f]


def sha256_texto(bloco):
    b = bloco.encode("utf-8")
    return hashlib.sha256(b).hexdigest(), len(b)


def ler(caminho):
    with open(caminho, encoding="utf-8-sig") as fh:
        return fh.read()


def verificar_protocolo(texto=None):
    t = ler(NOTA_116) if texto is None else texto
    h, n = sha256_texto(extrair_bloco(t, MARC_G0))
    return {"ok": h == PROTOCOLO_G0V2_SHA256 and n == PROTOCOLO_G0V2_BYTES, "sha256": h, "bytes": n}


_PADRAO = object()


def verificar_anexo(texto=None, esperado=_PADRAO, esperado_bytes=_PADRAO):
    """Estados: nao_congelado (hash esperado vazio), ok, divergente. So 'ok' libera rotulagem.
    Quando ha bytes esperados registrados, eles tambem precisam bater (mesma regra do protocolo).

    Sem argumento, usa as constantes congeladas. Com 'esperado' explicito (None = nao congelado), os bytes
    esperados NAO herdam ANEXO_BYTES: herdar faria um hash explicito de outro texto reprovar pelo tamanho
    do anexo real (defeito medido em 16/10, logo depois do congelamento)."""
    if esperado is _PADRAO:
        esp = ANEXO_SHA256
        esp_n = ANEXO_BYTES if esperado_bytes is _PADRAO else esperado_bytes
    else:
        esp = esperado
        esp_n = None if esperado_bytes is _PADRAO else esperado_bytes
    t = ler(NOTA_ANEXO) if texto is None else texto
    h, n = sha256_texto(extrair_bloco(t, MARC_ANEXO))
    if esp is None:
        return {"estado": "nao_congelado", "sha256": h, "bytes": n}
    bate = h == esp and (esp_n is None or n == esp_n)
    return {"estado": "ok" if bate else "divergente", "sha256": h, "bytes": n}


def verificar_manifesto(pasta=AQUI, manifesto=MANIFESTO):
    with open(manifesto, encoding="utf-8") as fh:
        m = json.load(fh)
    erros = []
    for it in m["arquivos"]:
        p = os.path.join(pasta, it["arquivo"])
        if not os.path.isfile(p):
            erros.append({"arquivo": it["arquivo"], "erro": "ausente"})
            continue
        with open(p, "rb") as fh:
            h = hashlib.sha256(fh.read()).hexdigest()
        if h != it["sha256"]:
            erros.append({"arquivo": it["arquivo"], "erro": "hash difere", "esperado": it["sha256"], "obtido": h})
    return {"ok": not erros, "arquivos": len(m["arquivos"]), "erros": erros}


def avaliar(prot, anexo, man):
    """Veredito global puro. Devolve (ok, motivos). Anexo so libera no estado 'ok'."""
    motivos = []
    if not prot.get("ok"):
        motivos.append("bloco G0-v2 nao bate com o hash congelado")
    if not man.get("ok"):
        motivos.append("manifesto da migracao nao bate")
    estado = anexo.get("estado")
    if estado == "nao_congelado":
        motivos.append("anexo-guia nao congelado (ANEXO_SHA256 vazio): rotulagem bloqueada pelo item 2")
    elif estado == "divergente":
        motivos.append("anexo-guia alterado depois do congelamento")
    elif estado != "ok":
        motivos.append("anexo-guia %s" % (estado or "sem estado"))
    return (not motivos), motivos


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--hash-anexo" in argv:
        h, n = sha256_texto(extrair_bloco(ler(NOTA_ANEXO), MARC_ANEXO))
        print(json.dumps({"anexo": {"sha256": h, "bytes": n}, "regra": "entre marcadores, exclusive, UTF-8, LF"},
                         ensure_ascii=False, indent=1, sort_keys=True))
        return 0
    prot = verificar_protocolo()
    try:
        anexo = verificar_anexo()
    except FileNotFoundError:
        anexo = {"estado": "ausente"}
    man = verificar_manifesto()
    ok, motivos = avaliar(prot, anexo, man)
    print(json.dumps({"ok": ok, "motivos": motivos, "protocolo": prot, "anexo": anexo, "manifesto": man},
                     ensure_ascii=False, indent=1, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
