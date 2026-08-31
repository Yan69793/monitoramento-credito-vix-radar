import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// VERIFCACHE-ROUNDTRIP1 (auditoria 2026-08-27, fix 2026-08-31).
//
// O Worker gravava no cache de verificacao um veredicto que ele proprio nao
// conseguia reler. `aplicarCorrecaoVerificador` (worker.js:12141-12142) aplica
// a correcao e renomeia o campo no proprio objeto: `veredicto_original =
// "CORRIGIR"`, `veredicto = "APROVADO_CORRIGIDO"`. No fluxo async
// (`confirmar_verificacao`), o objeto ja mutado e o que vai para o cache
// (`setCachedVerification`, worker.js:18823, DEPOIS da mutacao). No ciclo
// seguinte a rotina reenvia o objeto literal do cache e encontra duas portas
// fechadas em sequencia (worker.js:18809):
//   - `veredicto === "APROVADO"` falha, o valor e "APROVADO_CORRIGIDO";
//   - o guard de entrada de `aplicarCorrecaoVerificador` (worker.js:12112)
//     exigia `veredicto !== "CORRIGIR" -> false`, condicao que o proprio Worker
//     destruiu ao renomear o campo antes de gravar.
// Resultado: o evento aprovado com correcao era retratado do painel do emissor
// na execucao seguinte (medido em producao 27/08: Simpar, `rejeitados:2`,
// `retratados:2` num lote que so tinha uma rejeicao de merito).
//
// Prova de DUAS PONTAS (regra 5 do CLAUDE.md):
//   - ponta ruim: round-trip de veredicto CORRIGIR com correcoes validas ->
//     cache devolve APROVADO_CORRIGIDO e o reenvio literal do cache aprova
//     (aprovados:1, rejeitados:0, retratados:0). Contra o codigo pre-fix esse
//     reenvio caia em rejeitados:1/retratados:1.
//   - ponta boa: o mesmo round-trip com veredicto APROVADO puro continua
//     aprovando, garantindo que a instrumentacao nao quebrou o caminho feliz.
//
// O `id` do item e o proprio hash usado como chave de cache (`radar:verif:{id}`,
// VERIFCACHE1), entao a leitura de volta via `env.RADAR_KV` replica exatamente o
// que a rotina recebe em `cache_hits` e reenvia em `it.veredicto`.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const EMPRESA = "Simpar";
const SEMANA = "2026-W33";
const DATA_FILA = "2026-08-13";
const FONTE = "https://example.com/fato-simpar";
const ID_CORRIGIR = `2026-08-13|${EMPRESA.toLowerCase()}|roundtrip-corrigir`;
const ID_APROVADO = `2026-08-14|aegea|roundtrip-aprovado`;

function item(id, veredicto) {
  return {
    id,
    empresa: EMPRESA,
    semana: SEMANA,
    data_fila: DATA_FILA,
    setor: "Transportes",
    evento: {
      empresa: EMPRESA,
      classificacao: "RELEVANTE",
      titulo: "Evento original antes da correcao",
      evento: "Simpar divulgou resultado do trimestre.",
      impacto_credito: "Aumento da divida.",
      fonte_primaria: FONTE,
      fonte_tipo: "IMPRENSA",
      data_evento: "2026-08-13",
      tags: ["resultados"],
    },
    veredicto,
  };
}

function confirmar(itens) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "confirmar_verificacao", routine_key: ROUTINE_KEY, itens }),
  });
}

describe("VERIFCACHE-ROUNDTRIP1: veredicto corrigido em cache nao pode virar rejeicao no reenvio", () => {
  it("ponta ruim: reenvio literal do cache de CORRIGIR com correcoes aprova, nao retrata", async () => {
    const vCorrigir = {
      veredicto: "CORRIGIR",
      confianca: 0.9,
      motivo: "titulo impreciso",
      correcoes: { titulo: "Alavancagem cai para 2,8 vezes, menor nivel desde o IPO de 2010" },
      fontes_validas: [FONTE],
    };

    // 1a passada: rotina devolve CORRIGIR com correcoes validas.
    const r1 = await confirmar([item(ID_CORRIGIR, vCorrigir)]);
    expect(r1.status).toBe(200);
    const b1 = await r1.json();
    expect(b1).toMatchObject({ ok: true, resultado: { processados: 1, aprovados: 1, rejeitados: 0, retratados: 0, erros: 0 } });

    // O cache guarda o objeto JA mutado pela funcao (APROVADO_CORRIGIDO +
    // veredicto_original CORRIGIR) — exatamente o que a rotina relê e reenvia.
    const cached = await env.RADAR_KV.get("radar:verif:" + ID_CORRIGIR, "json");
    expect(cached).not.toBeNull();
    expect(cached.veredicto).toBe("APROVADO_CORRIGIDO");
    expect(cached.veredicto_original).toBe("CORRIGIR");

    // 2a passada (ciclo seguinte): rotina reenvia o objeto literal do cache.
    const r2 = await confirmar([item(ID_CORRIGIR, cached)]);
    expect(r2.status).toBe(200);
    const b2 = await r2.json();
    expect(b2).toMatchObject({ ok: true, resultado: { processados: 1, aprovados: 1, rejeitados: 0, retratados: 0, erros: 0 } });
  });

  it("ponta boa: round-trip de veredicto APROVADO puro continua aprovando", async () => {
    const vAprovado = {
      veredicto: "APROVADO",
      confianca: 0.95,
      motivo: "fontes consistentes",
      fontes_validas: [FONTE],
    };

    const r1 = await confirmar([item(ID_APROVADO, vAprovado)]);
    expect(r1.status).toBe(200);
    const b1 = await r1.json();
    expect(b1).toMatchObject({ resultado: { processados: 1, aprovados: 1, rejeitados: 0, retratados: 0, erros: 0 } });

    const cached = await env.RADAR_KV.get("radar:verif:" + ID_APROVADO, "json");
    expect(cached.veredicto).toBe("APROVADO");

    const r2 = await confirmar([item(ID_APROVADO, cached)]);
    expect(r2.status).toBe(200);
    const b2 = await r2.json();
    expect(b2).toMatchObject({ resultado: { processados: 1, aprovados: 1, rejeitados: 0, retratados: 0, erros: 0 } });
  });
});
