"""Utilitarios comuns das PoCs de inovacao (out/2026). Stdlib apenas, rodar com python -I.

Reusa o EWS 2.0 por import (scripts/predictive/ews2), nunca por copia.
"""
import hashlib
import json
import os
import re
import sys
from datetime import date, datetime

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
EWS2 = os.path.join(REPO, "scripts", "predictive", "ews2")
if EWS2 not in sys.path:
    sys.path.insert(0, EWS2)
try:
    sys.stdout.reconfigure(encoding="utf-8")  # -I ignora PYTHONIOENCODING
except Exception:  # noqa: BLE001
    pass

RAW = os.path.abspath(os.path.join(REPO, "..", "tmp", "operacional", "vix-radar", "poc-ideias", "raw"))
SAIDA = os.path.join(REPO, "data", "validacao", "poc-ideias")
CNPJ_EMISSORES = os.path.join(REPO, "scripts", "predictive", "cnpj_emissores.json")
EVENTOS_CREDITO = os.path.join(REPO, "data", "labels", "eventos_credito.jsonl")
HISTORICO = os.path.join(REPO, "data", "historico")


def digitos(s):
    return re.sub(r"\D", "", s or "")


def pdata(s):
    if not s:
        return None
    if isinstance(s, date):
        return s
    s = s.strip()[:10]
    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    return None


def emissores():
    """{empresa: cnpj_digitos} dos 104 emissores."""
    with open(CNPJ_EMISSORES, encoding="utf-8") as fh:
        d = json.load(fh)
    return {k: digitos(v.get("cnpj")) for k, v in d.items() if digitos(v.get("cnpj"))}


def sha256_arquivo(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def gravar_json(caminho, obj):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(obj, fh, ensure_ascii=False, indent=1, sort_keys=True, default=str)
