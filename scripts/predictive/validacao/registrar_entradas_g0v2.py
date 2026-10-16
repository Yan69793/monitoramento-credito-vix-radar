"""Registro das entradas do congelamento G0-v2 (nota 116, item 5). Somente leitura do IPE local, nao sorteia.

Grava: sha256 de cada zip IPE e do cadastro usados, versao do Python, sha256 das listas ordenadas de F e W
(ordem (Data_Entrega, CNPJ), a mesma sobre a qual a permutacao sera sorteada) e as contagens das camadas.
As duas permutacoes (Random(20261017) em F, Random(20261019) em W) NAO sao calculadas aqui: sortear e
etapa separada, que exige autorizacao. Os campos delas saem None.

Uso:
  python -I scripts/predictive/validacao/registrar_entradas_g0v2.py SAIDA.json
  python -I scripts/predictive/validacao/registrar_entradas_g0v2.py --conferir REGISTRO.json   # exit 1 se divergir
"""
import hashlib
import json
import os
import platform
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import dimensionar_g1b as DG  # noqa: E402
import guarda_g0v2 as GU  # noqa: E402

AU, V0 = DG.AU, DG.V0


def sha_arquivo(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def lista_ordenada(chaves):
    """Linha 'AAAA-MM-DD;CNPJ\\n' por chave, ordem (Data_Entrega, CNPJ). Texto exato que o hash cobre."""
    return "".join("%s;%s\n" % (d.isoformat(), c) for c, d in sorted(chaves, key=lambda k: (k[1], k[0])))


def montar():
    F, W = DG.estratos()
    _, fontes = V0.ler_ipe(AU.DIRS)
    cad = os.path.join(AU.BASE, "data", "cvm", "cad_cia_aberta.csv")
    lf, lw = lista_ordenada(F), lista_ordenada(W)
    prot = GU.verificar_protocolo()
    anexo = GU.verificar_anexo()
    return {
        "protocolo": "G0-v2",
        "bloco_g0v2_sha256": prot["sha256"], "bloco_g0v2_ok": prot["ok"],
        "anexo_sha256": anexo["sha256"], "anexo_estado": anexo["estado"],
        "python": platform.python_version(),
        "ipe": {ano: {"arquivo": os.path.basename(f["arquivo"]), "linhas": f["linhas"],
                      "sha256": sha_arquivo(f["arquivo"])} for ano, f in sorted(fontes.items())},
        "cadastro": {"arquivo": os.path.basename(cad), "sha256": sha_arquivo(cad)},
        "N_F": len(F), "N_W": len(W),
        "sha256_lista_F": hashlib.sha256(lf.encode("utf-8")).hexdigest(),
        "sha256_lista_W": hashlib.sha256(lw.encode("utf-8")).hexdigest(),
        "formato_lista": "AAAA-MM-DD;CNPJ\\n, ordem (Data_Entrega, CNPJ), UTF-8",
        "sha256_perm_F": None, "sha256_perm_W": None,
        "perm_nota": "nao sorteadas; exige autorizacao (semente F 20261017, W 20261019)",
        "sha256_rotulos": None,
    }


def comparar(reg, atual):
    chaves = ["bloco_g0v2_sha256", "anexo_sha256", "python", "ipe", "cadastro", "N_F", "N_W",
              "sha256_lista_F", "sha256_lista_W"]
    return [k for k in chaves if reg.get(k) != atual.get(k)]


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        print(__doc__)
        return 2
    atual = montar()
    if argv[0] == "--conferir":
        with open(argv[1], encoding="utf-8") as fh:
            reg = json.load(fh)
        dif = comparar(reg, atual)
        print(json.dumps({"ok": not dif, "divergem": dif}, ensure_ascii=False))
        return 0 if not dif else 1
    if os.path.exists(argv[0]):
        print("recusado: %s ja existe, registro so recebe arquivo novo" % argv[0])
        return 1
    with open(argv[0], "w", encoding="utf-8", newline="\n") as fh:
        json.dump(atual, fh, ensure_ascii=False, indent=1, sort_keys=True)
        fh.write("\n")
    print(json.dumps({"gravado": argv[0], "N_F": atual["N_F"], "N_W": atual["N_W"],
                      "sha256_lista_F": atual["sha256_lista_F"], "sha256_lista_W": atual["sha256_lista_W"]},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
