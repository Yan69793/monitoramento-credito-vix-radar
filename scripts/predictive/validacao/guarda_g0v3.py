"""Trava da rotulagem pela G0-v3 (nota 120). Enquanto PROTOCOLO_G0V3_SHA256 estiver vazio, rotulagem_liberada()
devolve False e todo executor de rotulo tem que sair sem chamar modelo. Exit 0 so com G0-v3 congelada, bloco
batendo, guarda G0-v2 (anexo) batendo e script de recuperacao igual ao registrado.

Uso: python -I scripts/predictive/validacao/guarda_g0v3.py
"""
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v2 as G  # noqa: E402

NOTA_120 = os.path.join(G.VAULT, "120 - EWS 2.0 Protocolo G0-v3 Recuperacao Progressiva RASCUNHO 2026-10-16.md")
MARC_V3 = ("<!-- G0-V3-INICIO -->", "<!-- G0-V3-FIM -->")
RECUPERAR = os.path.join(AQUI, "recuperar_g0v3.py")

# Congelado em 2026-10-16 por aprovacao controlada do operador (nota 120). Bloco gerado por gerar_g0v3.py a
# partir do G0-v2 congelado; hash conferido pela guarda e pelo gerador antes do registro.
PROTOCOLO_G0V3_SHA256 = "0f1b0af52d5a192a610e6c274710ceaea05584d8f59197b4f3031b2a261735fa"
PROTOCOLO_G0V3_BYTES = 27326
RECUPERAR_SHA256 = "f0b7e40374ebac18ed13dc8d1adc8dd38f68306c8ee80065f48585f3056ce244"


_PADRAO = object()


def estado(texto=None, esperado=_PADRAO, esperado_bytes=_PADRAO, rec_esperado=_PADRAO):
    """Sem argumento usa as constantes congeladas. 'esperado' explicito (inclusive None) nao herda os bytes
    congelados, mesma licao da guarda_g0v2 em 16/10."""
    if esperado is _PADRAO:
        esp, esp_n = PROTOCOLO_G0V3_SHA256, (PROTOCOLO_G0V3_BYTES if esperado_bytes is _PADRAO else esperado_bytes)
    else:
        esp, esp_n = esperado, (None if esperado_bytes is _PADRAO else esperado_bytes)
    rec = RECUPERAR_SHA256 if rec_esperado is _PADRAO else rec_esperado
    t = G.ler(NOTA_120) if texto is None else texto
    h, n = G.sha256_texto(G.extrair_bloco(t, MARC_V3))
    with open(RECUPERAR, "rb") as fh:
        hr = hashlib.sha256(fh.read()).hexdigest()
    motivos = []
    if esp is None:
        motivos.append("G0-v3 nao congelada: rotulagem bloqueada ate aprovacao do operador")
    elif h != esp or (esp_n is not None and n != esp_n):
        motivos.append("bloco G0-v3 alterado depois do congelamento")
    if esp is not None and rec != hr:
        motivos.append("recuperar_g0v3.py difere do registrado")
    g2 = G.avaliar(G.verificar_protocolo(), G.verificar_anexo(), G.verificar_manifesto())
    if not g2[0]:
        motivos += g2[1]
    return {"ok": not motivos, "motivos": motivos, "sha256_v3": h, "bytes_v3": n, "sha256_recuperar": hr}


def rotulagem_liberada():
    return estado()["ok"]


def main():
    r = estado()
    print(json.dumps(r, ensure_ascii=False, indent=1, sort_keys=True))
    return 0 if r["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
