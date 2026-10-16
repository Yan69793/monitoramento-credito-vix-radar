"""Criterios objetivos de entrada do G1a (nota 116, itens 2, 4 e 5). Somente leitura. Exit 0 = pode calcular.

Cada criterio e medido, nunca presumido. Os que dependem de artefato que ainda nao existe saem como
"ausente" e reprovam. O script nao rotula, nao sorteia e nao calcula kappa: isso e do g1a_v2.py, e so
depois de este preflight sair 0.

Uso:
  python -I scripts/predictive/validacao/preflight_g1a.py [--rotulos CSV] [--segunda CSV] [--registro JSON]
"""
import csv
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v2 as G  # noqa: E402

COLUNAS_ROTULO = ("id", "cnpj", "data", "origem", "classe1", "data_evento1", "protocolo", "trecho",
                  "sha256_documento", "data_download")
COLUNAS_SEGUNDA = ("id", "classe2", "data_evento2", "protocolo", "trecho")
CLASSES = ("evento_proprio", "continuacao", "evento_terceiro", "nao_evento", "incerto")


def sha256_arquivo(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def criterio_guarda():
    prot = G.verificar_protocolo()
    try:
        anexo = G.verificar_anexo()
    except FileNotFoundError:
        anexo = {"estado": "ausente"}
    man = G.verificar_manifesto()
    ok, motivos = G.avaliar(prot, anexo, man)
    return {"ok": ok, "motivos": motivos, "anexo": anexo.get("estado")}


def criterio_csv(caminho, colunas, nome):
    if not caminho or not os.path.isfile(caminho):
        return {"ok": False, "motivo": "%s ausente" % nome, "linhas": 0}
    with open(caminho, encoding="utf-8-sig", newline="") as fh:
        rd = csv.DictReader(fh, delimiter=";")
        faltam = [c for c in colunas if c not in (rd.fieldnames or [])]
        if faltam:
            return {"ok": False, "motivo": "colunas ausentes em %s: %s" % (nome, faltam), "linhas": 0}
        linhas = list(rd)
    erros = []
    for i, r in enumerate(linhas, 1):
        cl = r.get("classe1") or r.get("classe2")
        if cl not in CLASSES:
            erros.append("linha %d classe invalida: %r" % (i, cl))
        if cl in ("evento_proprio", "continuacao") and not (r.get("protocolo") and r.get("trecho")):
            erros.append("linha %d sem protocolo ou trecho literal" % i)
    return {"ok": not erros and len(linhas) > 0, "linhas": len(linhas), "erros": erros[:20],
            "sha256": sha256_arquivo(caminho)}


def criterio_registro(caminho, sha_rotulos):
    """O CSV de rotulos tem que estar congelado com sha256 registrado ANTES de qualquer calculo (item 5)."""
    if not caminho or not os.path.isfile(caminho):
        return {"ok": False, "motivo": "registro de congelamento do CSV ausente"}
    with open(caminho, encoding="utf-8-sig") as fh:
        reg = json.load(fh)
    esperado = reg.get("sha256_rotulos")
    return {"ok": bool(esperado) and esperado == sha_rotulos, "registrado": esperado, "obtido": sha_rotulos,
            "listas_e_permutacoes": all(reg.get(k) for k in ("sha256_lista_F", "sha256_lista_W",
                                                              "sha256_perm_F", "sha256_perm_W"))}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    def arg(flag):
        return argv[argv.index(flag) + 1] if flag in argv and argv.index(flag) + 1 < len(argv) else None
    rot, seg, regp = arg("--rotulos"), arg("--segunda"), arg("--registro")
    r = {"guarda": criterio_guarda()}
    r["rotulos_primeiro"] = criterio_csv(rot, COLUNAS_ROTULO, "CSV do primeiro rotulador")
    r["rotulos_segundo"] = criterio_csv(seg, COLUNAS_SEGUNDA, "CSV do segundo rotulador")
    r["registro_congelamento"] = criterio_registro(regp, r["rotulos_primeiro"].get("sha256"))
    r["declaracoes_nao_mediveis"] = [
        "nenhum rotulador olhou sinal, benchmark, EWS ou resultado de rotina (item 2)",
        "o segundo rotulador e de outro fornecedor ou humano e nao viu o primeiro rotulo nem a camada (item 4)",
    ]
    r["ok"] = all(r[k]["ok"] for k in ("guarda", "rotulos_primeiro", "rotulos_segundo", "registro_congelamento"))
    print(json.dumps(r, ensure_ascii=False, indent=1, sort_keys=True))
    return 0 if r["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
