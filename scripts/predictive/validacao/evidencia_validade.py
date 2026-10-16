"""Somente leitura. Numeros citados na nota 116 (secao de validade do G1b). Saida JSON em stdout."""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_g1b_validade as T  # noqa: E402
import g1b_v2 as V2  # noqa: E402

out = {"cobertura_exata_min": {}, "simulacao_aprovacao_indevida": {}, "guloso_abaixo_da_regra_fixa": []}
for N, n in ((402, 210), (402, 400), (2505, 540), (2505, 1165)):
    out["cobertura_exata_min"][f"{N}/{n}"] = round(min(T.cobertura_exata(N, n, M) for M in range(41)), 6)
casos = {"7 em W, uma chave": [(0, 1)] * 7, "7 em W, tres chaves": [(0, 3)] * 7, "3 em F e 4 em W": [(1, 0)] * 3 + [(0, 1)] * 4,
         "7 em F e W": [(1, 2)] * 7, "2 em F, 5 em W com 2 chaves": [(1, 0)] * 2 + [(0, 2)] * 5}
for nome, cfg in casos.items():
    out["simulacao_aprovacao_indevida"][nome] = {
        "exaustiva": T.simula(cfg, 60, T.TAM60, 3000, 7110),
        "gulosa": T.simula(cfg, 60, T.TAM60, 3000, 7110, atrib=V2.x_por_estrato_guloso)}
grades = [T.TAM60, {"F": (402, 210), "W": (2505, 540)}, {"F": (402, 300), "W": (2505, 765)},
          {"F": (402, 400), "W": (2505, 1465)}, {"F": (402, 270), "W": (2505, 675)}]
for tam in grades:
    for a in range(4):
        for b in range(4):
            for c in range(1, 7):
                perd = [{"F"}] * a + [{"W"}] * b + [{"F", "W"}] * c
                tot = lambda x: sum(T.U(x[h], tam[h][1], tam[h][0]) for h in x)  # noqa: E731
                g, f = tot(V2.x_por_estrato_guloso(perd, tam)), tot({"F": a + c, "W": b})
                if g < f:
                    out["guloso_abaixo_da_regra_fixa"].append({"tam": tam, "a": a, "b": b, "c": c, "guloso": g, "fixo": f})
out["n_casos_guloso_abaixo"] = len(out["guloso_abaixo_da_regra_fixa"])
out["guloso_abaixo_da_regra_fixa"] = out["guloso_abaixo_da_regra_fixa"][:5]
out["dois_episodios_numa_chave"] = {"N": 2505, "n": 2300, "U0": T.U(0, 2300, 2505), "falha": round(1 - 2300 / 2505, 4),
                                    "alfa_estrato": T.A}
print(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True))
