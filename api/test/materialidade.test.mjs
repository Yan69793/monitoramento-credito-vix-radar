import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";
import estadoW31 from "./fixtures/materialidade-estado-2026-W31.json" with { type: "json" };
import estadoW32 from "./fixtures/materialidade-estado-2026-W32.json" with { type: "json" };
import estadoW33 from "./fixtures/materialidade-estado-2026-W33.json" with { type: "json" };
import estadoW34 from "./fixtures/materialidade-estado-2026-W34.json" with { type: "json" };
import estadoW35 from "./fixtures/materialidade-estado-2026-W35.json" with { type: "json" };
import anomalias from "./fixtures/anomalias.json" with { type: "json" };
import rankingBefore from "./fixtures/materialidade-ranking-before.json" with { type: "json" };
import rankingAfter from "./fixtures/materialidade-ranking-after.json" with { type: "json" };
import { rankingCompleto, rankingTopComDedup } from "./_materialidade-common.mjs";
import { enriquecerEvento, MATERIALIDADE_POR_TAG, CRITICIDADE_SETOR } from "../src/worker.js";

// MATERIALSAT1 (auditoria 2026-08-29, Fase 1.2).
//
// O defeito medido: `(baseScore + tagBoost) * setorWeight` estourava 100. Com
// baseScore CRITICO = 80 e boost de rating = 40 (MATERIALIDADE_POR_TAG[rating]
// 90 - 50), a soma chegava a 120 e o setor pesado (Financeiro 0.95, Energia 0.9,
// Petroleo/Transportes 0.85) cortava em 100 no Math.min. Medido no fixture de
// producao (KV real 29/08): 8 eventos travados em 100 no topo do ranking
// (Raizen 2, Cosan 3, Rumo 1, Braskem 2), todos do mesmo valor, top 10 virava
// empate por ordem de insercao. Nenhuma distincao entre "downgrade" e "default"
// sobrevivia.
//
// Correcao: dampiar pela metade o boost de tag SO em evento CRITICO (e so o
// boost positivo; o negativo ja e aplainado em 0 pelo Math.max original).
// RELEVANTE/ECO ficam intactos por construcao. O maximo do dominio inteiro cai
// para 95 (Financeiro/rating) e o topo diferencia: na Energia, rating 90,
// liquidez/juridico 88, alavancagem 86.
//
// Diff before/after do ranking completo (497 eventos, fixture de producao):
//   29 eventos alterados, todos CRITICO, 0 nao-CRITICO tocados,
//   0 inversoes entre pares inalterados, 8 saturados em 100 -> 0.
// O snapshot before/after entra no repo; este teste re-computa o after e exige
// igualdade byte a byte, entao qualquer recalibracao futura quebra aqui e forca
// um diff declarado novo.

const WEEKS = ["2026-W31", "2026-W32", "2026-W33", "2026-W34", "2026-W35"];
const ESTADOS = [estadoW31, estadoW32, estadoW33, estadoW34, estadoW35];
const FIX_KEY = "radar:estado:";

function kvMapDosFixtures() {
  const map = {};
  for (let i = 0; i < WEEKS.length; i++) {
    map[`${FIX_KEY}${WEEKS[i]}`] = JSON.stringify(ESTADOS[i]);
  }
  return map;
}

function chaveEvento(e) {
  return `${e.empresa}|${e.data_evento}|${(e.titulo || "").slice(0, 40)}`;
}

async function mintJWT(secret) {
  const b64url = (buf) => Buffer.from(buf).toString("base64url");
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const agora = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ sub: "test", email: "test@example.com", iat: agora, exp: agora + 3600 }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(sig)}`;
}

describe("MATERIALIDADE — sem saturacao (MATERIALSAT1)", () => {
  let token;

  beforeEach(async () => {
    // RELOGIOTESTE1: os fixtures vivem em W31..W35 e a janela de 5 semanas do
    // Worker nasce do relogio. Congelado em 30/08 (dentro da W35), a janela
    // fecha exatamente sobre eles; solto, a semana corrente anda e o merge
    // perde a ponta velha em silencio (497 -> 447 eventos).
    fixarRelogioDoFixture();
    const map = kvMapDosFixtures();
    for (const [k, v] of Object.entries(map)) await env.RADAR_KV.put(k, v);
    await env.RADAR_KV.put("mercado:anomalias:ativas", JSON.stringify(anomalias));
    token = await mintJWT(env.JWT_SECRET);
  });

  afterEach(() => {
    soltarRelogio();
  });

  it("o ranking completo do harness reproduz o snapshot after byte a byte", async () => {
    const ranking = await rankingCompleto(kvMapDosFixtures());
    expect(ranking).toEqual(rankingAfter);
  });

  it("diff before/after: so CRITICO mudou, 0 inversoes entre pares inalterados", () => {
    const bm = new Map(rankingBefore.map((e) => [chaveEvento(e), e.materialidade]));
    const am = new Map(rankingAfter.map((e) => [chaveEvento(e), e.materialidade]));
    const bIdx = new Map(rankingBefore.map((e, i) => [chaveEvento(e), i]));

    expect(rankingBefore.length).toBe(rankingAfter.length);

    let mudaram = 0;
    let naoCriticoMudou = 0;
    for (const [k, v] of bm) {
      if (am.get(k) !== v) {
        mudaram++;
        if (rankingBefore[bIdx.get(k)].classificacao !== "CRITICO") naoCriticoMudou++;
      }
    }
    // Aceite do plano: alteracoes so em CRITICO, e as 8 saturacao sairam.
    expect(mudaram).toBe(29);
    expect(naoCriticoMudou).toBe(0);
    expect(rankingBefore.filter((e) => e.materialidade >= 100).length).toBe(8);
    expect(rankingAfter.filter((e) => e.materialidade >= 100).length).toBe(0);

    // Inversoes entre pares cujos dois valores NAO mudaram: deviam ser zero.
    let inversoes = 0;
    const keys = [...bm.keys()];
    for (let i = 0; i < keys.length; i++) {
      for (let j = i + 1; j < keys.length; j++) {
        const a = keys[i], b = keys[j];
        const bA = bm.get(a), bB = bm.get(b), aA = am.get(a), aB = am.get(b);
        if (bA === aA && bB === aB && ((bA > bB && aA < aB) || (bA < bB && aA > aB))) inversoes++;
      }
    }
    expect(inversoes).toBe(0);
  });

  it("dominio inteiro (classificacao x tag x setor): maximo 95, nunca satura", () => {
    let max = 0;
    for (const c of ["CRITICO", "RELEVANTE", "ECO"]) {
      for (const t of Object.keys(MATERIALIDADE_POR_TAG)) {
        for (const s of Object.keys(CRITICIDADE_SETOR)) {
          const v = enriquecerEvento({ classificacao: c, tags: [t], impacto_credito: "x" }, s)._enriquecimento.materialidade;
          if (v > max) max = v;
        }
      }
    }
    expect(max).toBe(95); // Financeiro/rating: (80+20)*0.95 = 95, sem Math.min atuando.
  });

  it("topo diferenciado na Energia: rating acima de liquidez e alavancagem", () => {
    const m = (tags) => enriquecerEvento({ classificacao: "CRITICO", tags, impacto_credito: "x" }, "Energia Elétrica")._enriquecimento.materialidade;
    expect(m(["rating"])).toBe(90);
    expect(m(["liquidez"])).toBe(88);
    expect(m(["alavancagem"])).toBe(86);
    expect(m(["rating"])).toBeGreaterThan(m(["liquidez"]));
    expect(m(["liquidez"])).toBeGreaterThan(m(["alavancagem"]));
    // O caso que antes saturava em 100 agora e 90.
    expect(m(["rating"])).toBeLessThan(100);
  });

  it("RELEVANTE e ECO intactos: valores por tag e setor sao os pre-fix", () => {
    const m = (c, tags, s) => enriquecerEvento({ classificacao: c, tags, impacto_credito: "x" }, s)._enriquecimento.materialidade;
    expect(m("RELEVANTE", ["rating"], "Energia Elétrica")).toBe(77); // (45+40)*0.9 = 76.5 -> 77
    expect(m("RELEVANTE", ["rating"], "Financeiro")).toBe(81);       // 85*0.95 = 80.75 -> 81
    expect(m("ECO", ["rating"], "Energia Elétrica")).toBe(54);       // (20+40)*0.9 = 54
    expect(m("RELEVANTE", ["captacao"], "Petróleo, Gás e Combustíveis")).toBe(38); // 45*0.85 = 38.25 -> 38
  });

  it("cross-check: top 10 do briefing real (endpoint) bate com o ranking do harness", async () => {
    // Com o relogio preso em 30/08 o endpoint pede exatamente W35..W31, entao o
    // fixture entra sob a propria semana. Antes do RELOGIOTESTE1 este teste
    // remapeava os fixtures para as semanas correntes, o que mantinha as duas
    // pontas de acordo mas embaralhava a ordem cronologica do merge.
    const r = await SELF.fetch("https://exemplo.invalid/?op=briefing_executivo&escopo=historico", {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(r.status).toBe(200);
    const j = await r.json();
    expect(j.ok).toBe(true);
    const top = j.briefing.top_eventos;
    expect(Array.isArray(top)).toBe(true);
    expect(top.length).toBeGreaterThanOrEqual(10);

    // O endpoint dedup o top_eventos (BRIEFDEDUP1), entao o harness compara com
    // a variante dedup, mesma chave real.
    const meu = await rankingTopComDedup(kvMapDosFixtures());
    expect(meu.length).toBeGreaterThanOrEqual(10);
    for (let i = 0; i < 10; i++) {
      expect({ empresa: top[i].empresa, data: top[i].data_evento, m: top[i].materialidade }).toEqual(meu[i]);
    }
  });
});
