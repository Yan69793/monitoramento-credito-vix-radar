"""PoC 1 (Dia 3): Flow-at-Risk. Pressao potencial (fundos detentores sob resgate anormal) separada de venda efetiva.

Disponibilidade em T (criterios congelados):
  - CDA de competencia M: so se M + DEFASAGEM_CDA dias <= T-1, e linha confidencial so depois de DT_CONFID_APLIC
  - informe diario: valor de D usado a partir de D+1
Pressao do fundo em T: resgate liquido de 5 dias (ate T-1) / PL acima do p90 do proprio fundo nos 60 dias uteis
anteriores (ate T-2) e positivo. Venda efetiva: VL_VENDA_NEGOC do CDA, so observavel depois de publicado.
"""
import bisect
import collections
import json
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fontes_cvm_fundos as F  # noqa: E402
from comum import SAIDA, gravar_json  # noqa: E402

DEFASAGEM_CDA = 60
JANELA = 60
JANELA_RESG = 5
MESES_CDA = ["2025%02d" % m for m in range(9, 13)] + ["2026%02d" % m for m in range(1, 9)]
MESES_INF = ["2025%02d" % m for m in range(9, 13)] + ["2026%02d" % m for m in range(1, 11)]
CLUSTERS = [("Raízen", date(2026, 3, 11)), ("Pão de Açúcar (GPA)", date(2026, 3, 10)), ("Oncoclínicas", date(2026, 3, 27)),
            ("Kora Saúde", date(2026, 4, 2)), ("Rede D'Or", date(2026, 4, 22)), ("Aegea Saneamento", date(2026, 6, 9))]
GRUPO = {"Cosan": "Raízen"}  # mesmo grupo economico conta no mesmo cluster


def p90(v):
    v = sorted(v)
    return v[min(len(v) - 1, int(0.9 * (len(v) - 1) + 0.5))]


def pressao_por_fundo(inf, calendario):
    """{fundo: set(datas T em pressao)} com dado do informe ate T-1."""
    out = {}
    for f, serie in inf.items():
        net = {}
        dias = [d for d in calendario if d in serie]
        for k in range(JANELA_RESG, len(dias)):
            ult = dias[k - JANELA_RESG + 1:k + 1]
            pl = serie[dias[k - JANELA_RESG]][2]
            if pl > 0:
                net[dias[k]] = sum(serie[d][1] - serie[d][0] for d in ult) / pl
        datas_net = sorted(net)
        em = set()
        for i, d in enumerate(calendario):
            if i < 1:
                continue
            ontem = calendario[i - 1]
            if ontem not in net:
                continue
            j = bisect.bisect_left(datas_net, ontem)
            hist = [net[x] for x in datas_net[max(0, j - JANELA):j]]
            if len(hist) >= 40 and net[ontem] > 0 and net[ontem] > p90(hist):
                em.add(d)
        out[f] = em
    return out


def posicoes_em(pos, T, defasagem):
    """{(fundo, emissor): valor} da competencia mais recente publicada em T por fundo."""
    lim = T - timedelta(days=1)
    melhor = {}
    for (f, cp, emp, conf), v in pos.items():
        if cp + timedelta(days=defasagem) > lim:
            continue
        if conf and conf > lim:
            continue
        if f not in melhor or cp > melhor[f]:
            melhor[f] = cp
    out = collections.defaultdict(float)
    for (f, cp, emp, conf), v in pos.items():
        if melhor.get(f) == cp and cp + timedelta(days=defasagem) <= lim and not (conf and conf > lim):
            out[(f, emp)] += v
    return out


def indice(pos, pressao, calendario, defasagem, datas=None):
    """{emissor: {T: (pressao_rs, estoque_rs)}}."""
    out = collections.defaultdict(dict)
    cache_pos = {}
    for T in (datas or calendario):
        chave = T.isoformat()[:7]
        # posicoes mudam pouco dentro do mes; recalcula por data para respeitar confidencialidade exata
        p = posicoes_em(pos, T, defasagem)
        est = collections.defaultdict(float)
        pr = collections.defaultdict(float)
        for (f, emp), v in p.items():
            est[emp] += v
            if T in pressao.get(f, ()):
                pr[emp] += v
        for emp in est:
            out[emp][T] = (pr[emp], est[emp])
    return out


def media_frac(serie, ds):
    v = [serie[d][0] / serie[d][1] for d in ds if d in serie and serie[d][1] > 0]
    return sum(v) / len(v) if v else None


def avaliar_clusters(idx, calendario, eventos_todos):
    res = []
    controles = [e for e in idx if not any(e == c or GRUPO.get(e) == c for c, _ in CLUSTERS)]
    for emp, d0 in CLUSTERS:
        if emp not in idx:
            res.append({"emissor": emp, "evento": str(d0), "status": "sem posicao visivel em fundos"})
            continue
        k = bisect.bisect_left(calendario, d0)
        pre = calendario[max(0, k - 20):k]
        base = calendario[max(0, k - 80):max(0, k - 20)]
        pos_ = calendario[k:k + 20]
        fp, fb, fq = media_frac(idx[emp], pre), media_frac(idx[emp], base), media_frac(idx[emp], pos_)
        razoes_ctrl = []
        for c in controles:
            a, b = media_frac(idx[c], pre), media_frac(idx[c], base)
            if a is not None and b:
                razoes_ctrl.append(a / b)
        r = (fp / fb) if (fp is not None and fb) else None
        pct = (sum(1 for x in razoes_ctrl if x < r) / len(razoes_ctrl)) if (r is not None and razoes_ctrl) else None
        est = idx[emp].get(pre[-1], (0, 0))[1] if pre else 0
        res.append({"emissor": emp, "evento": str(d0), "estoque_visivel_rs_mi": round(est / 1e6, 1),
                    "frac_base": fb and round(fb, 4), "frac_pre20": fp and round(fp, 4), "frac_pos20": fq and round(fq, 4),
                    "razao_pre_base": r and round(r, 2), "percentil_vs_controles": pct and round(pct, 2), "n_controles": len(razoes_ctrl),
                    "base_ate": str(base[-1]) if base else None})
    return res


def mecanismo(pressao, tot_fundo, calendario):
    """Venda efetiva ex post: taxa de venda do fundo no mes (VL_VENDA_NEGOC / posicao do mes anterior) por grupo de pressao."""
    grupos = {"sem_pressao": [], "pressao_1_a_24pct_dias": [], "pressao_25pct_dias_ou_mais": []}
    por_mes = collections.defaultdict(list)
    for d in calendario:
        por_mes[(d.year, d.month)].append(d)
    for (f, cp), (posv, venda, aq) in tot_fundo.items():
        ant = (cp.replace(day=1) - timedelta(days=1))
        prev = tot_fundo.get((f, ant))
        if not prev or prev[0] <= 1e6:
            continue
        dias = por_mes.get((cp.year, cp.month), [])
        if not dias or f not in pressao:
            continue
        share = sum(1 for d in dias if d in pressao[f]) / len(dias)
        taxa = venda / prev[0]
        g = "sem_pressao" if share == 0 else ("pressao_25pct_dias_ou_mais" if share >= 0.25 else "pressao_1_a_24pct_dias")
        grupos[g].append(min(taxa, 5.0))
    out = {}
    for g, v in grupos.items():
        v.sort()
        out[g] = {"fundo_meses": len(v), "taxa_venda_media": round(sum(v) / len(v), 4) if v else None,
                  "taxa_venda_mediana": round(v[len(v) // 2], 4) if v else None,
                  "frac_com_venda": round(sum(1 for x in v if x > 0) / len(v), 3) if v else None}
    return out


def main():
    pos, venda_emis, tot_fundo, diag = F.ler_cda(MESES_CDA)
    fundos = {f for (f, _, _, _) in pos} | {f for (f, _) in tot_fundo}
    inf = F.ler_inf_diario(MESES_INF, fundos)
    calendario = sorted({d for s in inf.values() for d in s})
    pressao = pressao_por_fundo(inf, calendario)
    datas = [d for d in calendario if date(2026, 1, 1) <= d <= date(2026, 7, 31)]
    res = {"versao": "flow_at_risk v1", "mapa_e_cobertura_rs_bi": diag, "fundos_com_debenture": len(fundos),
           "fundos_no_informe": len(inf), "calendario": [str(calendario[0]), str(calendario[-1])],
           "fundos_com_algum_dia_de_pressao": sum(1 for v in pressao.values() if v),
           "denominador_volume": "indisponivel, indice em fracao do estoque em fundos, NAO VALIDADO ECONOMICAMENTE"}
    for lag in (DEFASAGEM_CDA, 30, 90):
        idx = indice(pos, pressao, calendario, lag, datas)
        res["clusters_defasagem_%d" % lag] = avaliar_clusters(idx, datas, None)
    res["mecanismo_venda_efetiva_ex_post"] = mecanismo(pressao, tot_fundo, calendario)
    gravar_json(os.path.join(SAIDA, "dia3", "flow_at_risk_resultado.json"), res)
    print(json.dumps(res, ensure_ascii=False, indent=1, default=str))


if __name__ == "__main__":
    main()
