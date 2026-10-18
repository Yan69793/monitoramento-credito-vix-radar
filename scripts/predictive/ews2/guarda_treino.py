"""Trava do treino e de todo calculo de sinal sobre dado real (G0-v2 item 5: "nenhum sinal e calculado antes do
G1-v2 passar"; G0-v1 item 11). Exit 0 so quando existir o registro de homologacao da base, gravado pelo
operador, com G1a, G1b e G1c aprovados, sha256 do CSV de rotulos congelado batendo e autorizacao explicita.

O registro vive em data/validacao/registro_homologacao_base.json e tem este formato minimo:
  {"g1a_passa": true, "g1b_passa": true, "g1c_passa": true, "sha256_rotulos": "<64 hex>",
   "arquivo_rotulos": "data/validacao/rotulos_etapa1.csv", "autorizado_por_operador": true,
   "autorizado_em": "AAAA-MM-DD", "protocolo": "G0-v3"}
Este script nunca cria esse arquivo. Dado sintetico nao passa por aqui (nao e dado real).

Uso: python -I scripts/predictive/ews2/guarda_treino.py
"""
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
REGISTRO = os.path.join(BASE, "data", "validacao", "registro_homologacao_base.json")
CAMPOS = ("g1a_passa", "g1b_passa", "g1c_passa", "sha256_rotulos", "arquivo_rotulos", "autorizado_por_operador", "autorizado_em", "protocolo")


def sha256_arquivo(p):
    """sha256 com fim de linha normalizado para LF (EWS2PUB1). O CSV de rotulos nasceu com CRLF no Windows e o git guarda LF;
    sem normalizar, o mesmo conteudo dava hashes diferentes no Windows e no runner do GitHub Actions e a guarda barrava."""
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read().replace(b"\r\n", b"\n")).hexdigest()


def _override_valido(registro, sha_nota_real):
    """Liberacao operacional (nota 126): o operador pode liberar o treino com G1 reprovado SE o registro citar a nota de
    decisao e o sha256 dela bater com o arquivo atual. O registro continua gravando os G1 como realmente foram."""
    return (registro.get("override_operador") is True and bool(registro.get("override_motivo"))
            and bool(sha_nota_real) and registro.get("override_nota_sha256") == sha_nota_real)


def avaliar(registro, sha_rotulos_real, sha_nota=None):
    """Puro. Devolve (ok, motivos)."""
    motivos = []
    if registro is None:
        return False, ["registro de homologacao da base ausente: sinal e treino bloqueados (G0-v2 item 5)"]
    for c in CAMPOS:
        if c not in registro:
            motivos.append("campo ausente no registro: %s" % c)
    override = _override_valido(registro, sha_nota)
    for g in ("g1a_passa", "g1b_passa", "g1c_passa"):
        if registro.get(g) is not True and not override:
            motivos.append("%s nao aprovado" % g)
    if registro.get("override_operador") is True and not override:
        motivos.append("override do operador sem nota valida: hash da nota citada nao bate ou motivo ausente")
    if registro.get("autorizado_por_operador") is not True:
        motivos.append("sem autorizacao explicita do operador")
    if not registro.get("sha256_rotulos") or registro.get("sha256_rotulos") != sha_rotulos_real:
        motivos.append("sha256 do CSV de rotulos nao bate com o congelado")
    return (not motivos), motivos


def estado(registro_path=REGISTRO, base=BASE):
    reg = None
    if os.path.isfile(registro_path):
        with open(registro_path, encoding="utf-8-sig") as fh:
            reg = json.load(fh)
    sha = None
    if reg and reg.get("arquivo_rotulos"):
        p = os.path.join(base, reg["arquivo_rotulos"])
        if os.path.isfile(p):
            sha = sha256_arquivo(p)
    sha_nota = None
    if reg and reg.get("override_nota"):
        pn = os.path.join(base, reg["override_nota"])
        if os.path.isfile(pn):
            sha_nota = sha256_arquivo(pn)
    ok, motivos = avaliar(reg, sha, sha_nota)
    return {"ok": ok, "motivos": motivos, "registro": registro_path, "sha256_rotulos_real": sha,
            "override_operador": bool(reg and reg.get("override_operador") is True and not motivos)}


def exigir(finalidade):
    e = estado()
    if not e["ok"]:
        raise SystemExit("BLOQUEADO (%s): %s" % (finalidade, "; ".join(e["motivos"])))
    return e


def main():
    e = estado()
    print(json.dumps(e, ensure_ascii=False, indent=1))
    return 0 if e["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
