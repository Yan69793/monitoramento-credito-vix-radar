"""Verificacao documental da base baixada (G0-v2 item 5): para cada linha da proveniencia, o original existe em DOCS/,
o sha256 do arquivo bate com o registrado, o texto existe em TXT/ quando o status diz 'ok', e nenhum protocolo tem
registros contraditorios. Somente leitura. Saida JSON em stdout, exit 0 so sem divergencia de integridade.

Uso: python -I scripts/predictive/validacao/verificar_proveniencia.py ETAPA_DIR DOCS_DIR [--completo]
  sem --completo, confere o sha256 de uma amostra determinista (semente 20261016) de ate 300 arquivos mais todos os
  pedidos no nivel 2; com --completo, confere todos (1,3 GB em 16/10, alguns minutos).
"""
import hashlib
import json
import os
import random
import sys
from collections import Counter


def ler_jsonl(p):
    out = []
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8"):
            ln = ln.strip()
            if ln:
                try:
                    out.append(json.loads(ln))
                except Exception:  # noqa: BLE001
                    out.append({"_linha_invalida": ln[:120]})
    return out


def sha256_arquivo(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for b in iter(lambda: fh.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def verificar(etapa, docs_dir, completo=False, amostra=300, semente=20261016):
    prov = ler_jsonl(os.path.join(etapa, "proveniencia_downloads.jsonl"))
    prov2 = ler_jsonl(os.path.join(etapa, "g1eq", "proveniencia_nivel2.jsonl"))
    todos = prov + prov2
    invalidas = [p for p in todos if "_linha_invalida" in p]
    todos = [p for p in todos if "_linha_invalida" not in p]
    por = {}
    for p in todos:
        por.setdefault(p["protocolo_rad"], []).append(p)
    contrad = {k: [x["status"] for x in v] for k, v in por.items() if len({x["status"] for x in v if x["status"].startswith("ok")}) > 1
               or any(a["sha256"] != b["sha256"] for a in v for b in v if a.get("sha256") and b.get("sha256"))}
    ok_regs = [p for p in todos if p["status"].startswith("ok")]
    faltam_doc, faltam_txt, sha_dif, conferidos = [], [], [], 0
    rng = random.Random(semente)
    alvo_sha = set(p["protocolo_rad"] for p in prov2) if not completo else set(p["protocolo_rad"] for p in ok_regs)
    if not completo:
        cands = sorted(set(p["protocolo_rad"] for p in ok_regs) - alvo_sha)
        alvo_sha |= set(rng.sample(cands, min(amostra, len(cands))))
    for p in ok_regs:
        f = os.path.join(docs_dir, "DOCS", "%s.%s" % (p["protocolo_rad"], p["tipo"]))
        if not os.path.exists(f):
            faltam_doc.append(p["protocolo_rad"])
            continue
        if p["status"] == "ok" and not os.path.exists(os.path.join(docs_dir, "TXT", "%s.txt" % p["protocolo_rad"])):
            faltam_txt.append(p["protocolo_rad"])
        if p["protocolo_rad"] in alvo_sha:
            conferidos += 1
            if sha256_arquivo(f) != p.get("sha256"):
                sha_dif.append(p["protocolo_rad"])
    status = Counter(p["status"] for p in todos)
    texto = Counter(p.get("texto") for p in todos if p["status"].startswith("ok"))
    r = {"registros": len(todos), "nivel2": len(prov2), "linhas_invalidas": len(invalidas), "protocolos_unicos": len(por),
         "status": dict(status), "texto": {str(k): v for k, v in texto.items()}, "contraditorios": contrad,
         "originais_ausentes": faltam_doc, "textos_ausentes": faltam_txt, "sha256_conferidos": conferidos, "sha256_divergentes": sha_dif,
         "modo": "completo" if completo else "amostra_%d_mais_nivel2" % amostra,
         "bytes_docs": sum(p.get("bytes", 0) for p in ok_regs)}
    r["ok"] = not (invalidas or contrad or faltam_doc or faltam_txt or sha_dif)
    return r


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2:
        print(__doc__)
        return 2
    r = verificar(argv[0], argv[1], completo="--completo" in argv)
    print(json.dumps(r, ensure_ascii=False, indent=1))
    return 0 if r["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
