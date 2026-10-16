"""Gera o bloco G0-v3 (RASCUNHO) a partir do bloco G0-v2 congelado, aplicando substituicoes exatas e
conferidas. Cada substituicao exige que o trecho de origem exista exatamente uma vez; senao, nada e gerado.
Imprime o diff por linha e o sha256 proposto do bloco v3 (mesma regra de hash: entre marcadores, LF, UTF-8).

Uso: python -I gerar_g0v3.py SAIDA.md
"""
import difflib
import hashlib
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import guarda_g0v2 as G  # noqa: E402

MARC_V3 = ("<!-- G0-V3-INICIO -->", "<!-- G0-V3-FIM -->")

TROCAS = [
    ("## G0-v2. Regras propostas (bloco a congelar)",
     "## G0-v3. Regras propostas (bloco a congelar)\n\n"
     "G0-v3 é o bloco G0-v2 (sha256 `5e91fe1104f057266cd0c40f9e5a88b14f44b3afe81526520f0d992cacb3bc7c`) com três "
     "mudanças e nenhuma outra: o que o rotulador recebe e lê (item 2, primeiro parágrafo), o gate G1-eq (item 4) e "
     "o registro da recuperação (item 5). O anexo `G0-v2-anexo-guia` (sha256 "
     "`6d3b0da7912d5ce323235fbac6b3038140bb0dc841f28de4c2828184cac8ac73`) vale sem mudança. Sementes, camadas, "
     "prefixos, classes, critérios de rótulo, G1a, G1b e G1c são os da G0-v2."),
    ("Lê o documento do candidato e todos os documentos IPE do mesmo CNPJ nos 180 dias anteriores. Recebe também o "
     "índice IPE do mesmo CNPJ (data, categoria, assunto e protocolo) dos 24 meses anteriores, e abre qualquer "
     "documento desse índice de que precise para decidir titularidade, continuação ou primeiro documento público.",
     "Recebe, sempre e para todo item, o índice IPE integral do mesmo CNPJ (data, categoria, assunto, protocolo e "
     "número de páginas) do dia do candidato, dos 180 dias anteriores e dos 24 meses anteriores, sem filtro de "
     "categoria nem de assunto. De cada documento do dia recebe o início (12.000 caracteres) e as âncoras do "
     "restante; de cada documento dos 180 dias, o início (1.200 caracteres) e as âncoras do restante. Âncora é a "
     "janela de 350 caracteres em torno de cada ocorrência de termo da lista fixa de `recuperar_g0v3.py`, cujo "
     "sha256 é registrado no congelamento, com teto de 24.000 caracteres por documento do dia e de 2.400 por "
     "documento dos 180 dias, e o corte declarado no pacote. Pede páginas de qualquer documento do índice, em até "
     "3 rodadas de até 60.000 caracteres cada, e pede a íntegra de todo documento em que se apoie para classe, data, "
     "origem, titularidade ou continuação, e de todo documento sem texto extraível que o índice aponte como possível "
     "evento, lido pela página renderizada. O pacote, cada pedido e cada trecho servido ficam registrados com "
     "sha256. Todo trecho literal do rótulo é conferido por comando contra o texto integral do documento citado, e "
     "trecho que não está no documento invalida o rótulo, que vai à adjudicação."),
    ("**G1a, concordância.**",
     "**G1-eq, equivalência da recuperação.** Antes do primeiro rótulo da etapa 1, os 30 primeiros itens da ordem "
     "cega da etapa 1 (semente 20261020) são rotulados duas vezes pelo primeiro rotulador, em sessões separadas: "
     "pela recuperação do item 2 e pela leitura integral fatiada, em que todo documento do dia e dos 180 dias é lido "
     "por inteiro em fatias de até 60.000 caracteres, e os fatos de crédito de cada fatia são levados a uma decisão "
     "final com o mesmo guia. Passa se a classe binária (`evento_proprio` contra o resto) difere em no máximo 1 dos "
     "30 itens e se, entre os pares em que as duas leituras marcam `evento_proprio`, a data difere em no máximo 1. "
     "Se falhar, os parâmetros da recuperação são revistos, ganham versão e sha256 novos, e o G1-eq se repete com "
     "os 30 itens seguintes da mesma ordem. Os rótulos do G1-eq não entram no CSV de rótulos nem no G1a.\n\n"
     "**G1a, concordância.**"),
    ("- Cada documento baixado guarda sha256 e data do download no CSV de rótulos.",
     "- O script de recuperação, os pacotes de cada item, os pedidos de páginas e os trechos servidos são "
     "registrados com sha256 antes do cálculo de qualquer métrica, e qualquer rótulo pode ser refeito a partir "
     "deles e dos originais.\n"
     "- Cada documento baixado guarda sha256 e data do download no CSV de rótulos."),
]


def gerar():
    v2 = G.extrair_bloco(G.ler(G.NOTA_116), G.MARC_G0)
    h2, n2 = G.sha256_texto(v2)
    if h2 != G.PROTOCOLO_G0V2_SHA256 or n2 != G.PROTOCOLO_G0V2_BYTES:
        raise SystemExit("bloco G0-v2 nao bate com o congelado; nada gerado")
    v3 = v2
    for velho, novo in TROCAS:
        if v3.count(velho) != 1:
            raise SystemExit("trecho de origem ausente ou repetido: %r" % velho[:60])
        v3 = v3.replace(velho, novo)
    return v2, v3


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    v2, v3 = gerar()
    h3, n3 = G.sha256_texto(v3)
    diff = [l for l in difflib.unified_diff(v2.splitlines(), v3.splitlines(), "G0-v2", "G0-v3", n=0, lineterm="")
            if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
    linhas_v2 = v2.splitlines()
    removidas = [l[1:] for l in diff if l.startswith("-")]
    resumo = {"sha256_v2": G.PROTOCOLO_G0V2_SHA256, "sha256_v3_proposto": h3, "bytes_v3": n3,
              "linhas_v2": len(linhas_v2), "linhas_removidas": len(removidas),
              "linhas_acrescentadas": sum(1 for l in diff if l.startswith("+")),
              "sha256_recuperar_g0v3": hashlib.sha256(open(os.path.join(AQUI, "recuperar_g0v3.py"), "rb").read()).hexdigest()}
    if argv:
        with open(argv[0], "w", encoding="utf-8", newline="\n") as fh:
            fh.write(MARC_V3[0] + "\n" + v3 + MARC_V3[1] + "\n")
    print(json.dumps(resumo, ensure_ascii=False, indent=1))
    for l in diff:
        print(l[:220])
    return 0


if __name__ == "__main__":
    sys.exit(main())
