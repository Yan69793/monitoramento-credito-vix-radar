"""Dia 3: prova de duas pontas das guardas temporais do Flow-at-Risk.
Versoes com vazamento (ignora confidencialidade; ignora defasagem; usa informe do proprio dia) tem de ser reprovadas
pelos mesmos testes que a versao correta passa."""
import json
import os
import sys
import unittest
from datetime import timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_at_risk as FR  # noqa: E402
import test_ideias_flow as T  # noqa: E402

ORIG_POS = FR.posicoes_em
ORIG_PRESSAO = FR.pressao_por_fundo


def pos_sem_confid(pos, T_, defasagem):
    return ORIG_POS({(f, cp, e, None): v for (f, cp, e, c), v in pos.items()}, T_, defasagem)


def pos_sem_defasagem(pos, T_, defasagem):
    return ORIG_POS(pos, T_, 0)


def pressao_mesmo_dia(inf, cal):
    p = ORIG_PRESSAO(inf, cal)
    return {f: {cal[cal.index(d) - 1] for d in s if cal.index(d) > 0} for f, s in p.items()}  # antecipa 1 dia = usa D em D


def rodar(nome_teste, classe):
    s = unittest.TestSuite([classe(nome_teste)])
    return unittest.TextTestRunner(stream=open(os.devnull, "w")).run(s).wasSuccessful()


def main():
    res = {"correta": {n: rodar(n, c) for n, c in (("test_linha_confidencial_so_entra_depois_do_prazo", T.TesteDisponibilidade),
                                                     ("test_competencia_so_entra_depois_da_defasagem", T.TesteDisponibilidade),
                                                     ("test_pico_de_resgate_vira_pressao_so_no_dia_seguinte", T.TestePressao))}}
    FR.posicoes_em = pos_sem_confid
    res["vazada_sem_confidencialidade_reprovada"] = not rodar("test_linha_confidencial_so_entra_depois_do_prazo", T.TesteDisponibilidade)
    FR.posicoes_em = pos_sem_defasagem
    res["vazada_sem_defasagem_reprovada"] = not rodar("test_competencia_so_entra_depois_da_defasagem", T.TesteDisponibilidade)
    FR.posicoes_em = ORIG_POS
    FR.pressao_por_fundo = pressao_mesmo_dia
    res["vazada_informe_mesmo_dia_reprovada"] = not rodar("test_pico_de_resgate_vira_pressao_so_no_dia_seguinte", T.TestePressao)
    FR.pressao_por_fundo = ORIG_PRESSAO
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
