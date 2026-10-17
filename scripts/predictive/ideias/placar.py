"""PoC 3 (Dia 5): trilha de alertas com hash encadeado.

O que prova: que nenhuma linha foi alterada, removida ou reordenada depois de gravada, desde que se compare a cabeca da cadeia
com uma ancora guardada fora do arquivo. O que NAO prova: imutabilidade (quem reescreve a cadeia inteira gera outra cadeia valida),
nem eficacia preditiva dos alertas.

Uso:
  python -I placar.py gravar  <ledger.jsonl> <entrada.jsonl> [<entrada.jsonl> ...]   (so acrescenta; recusa alterar o existente)
  python -I placar.py verificar <ledger.jsonl> [--ancora <sha256_da_cabeca>]         (EXIT 0 integro, 1 violado)
"""
import hashlib
import json
import os
import sys

GENESIS = "0" * 64


def canonico(payload):
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def hash_linha(seq, anterior, payload):
    return hashlib.sha256(("%d|%s|%s" % (seq, anterior, canonico(payload))).encode("utf-8")).hexdigest()


def ler(caminho):
    if not os.path.exists(caminho):
        return []
    with open(caminho, encoding="utf-8") as fh:
        return [json.loads(l) for l in fh if l.strip()]


def verificar(caminho, ancora=None):
    linhas = ler(caminho)
    anterior = GENESIS
    for i, r in enumerate(linhas):
        if r.get("seq") != i + 1:
            return False, "seq fora de ordem na linha %d" % (i + 1), anterior
        if r.get("anterior") != anterior:
            return False, "encadeamento quebrado na linha %d" % (i + 1), anterior
        if hash_linha(r["seq"], r["anterior"], r["payload"]) != r.get("sha256"):
            return False, "conteudo alterado na linha %d" % (i + 1), anterior
        anterior = r["sha256"]
    if ancora and ancora != anterior:
        return False, "cabeca da cadeia (%s) diferente da ancora" % anterior, anterior
    return True, "integro, %d linhas" % len(linhas), anterior


def gravar(caminho, entradas):
    ok, msg, cabeca = verificar(caminho)
    if not ok:
        raise SystemExit("ledger existente violado, nada gravado: " + msg)
    n = len(ler(caminho))
    novos = []
    for e in entradas:
        with open(e, encoding="utf-8") as fh:
            for l in fh:
                if l.strip():
                    p = json.loads(l)
                    p["_entrada_sha256"] = hashlib.sha256(open(e, "rb").read()).hexdigest()
                    n += 1
                    h = hash_linha(n, cabeca, p)
                    novos.append({"seq": n, "anterior": cabeca, "payload": p, "sha256": h})
                    cabeca = h
    os.makedirs(os.path.dirname(os.path.abspath(caminho)), exist_ok=True)
    with open(caminho, "a", encoding="utf-8", newline="\n") as fh:
        for r in novos:
            fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
    return len(novos), cabeca


def main(argv):
    if len(argv) >= 3 and argv[0] == "gravar":
        n, cabeca = gravar(argv[1], argv[2:])
        print(json.dumps({"gravadas": n, "cabeca": cabeca}))
        return 0
    if len(argv) >= 2 and argv[0] == "verificar":
        ancora = argv[argv.index("--ancora") + 1] if "--ancora" in argv else None
        ok, msg, cabeca = verificar(argv[1], ancora)
        print(json.dumps({"ok": ok, "mensagem": msg, "cabeca": cabeca}, ensure_ascii=False))
        return 0 if ok else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
