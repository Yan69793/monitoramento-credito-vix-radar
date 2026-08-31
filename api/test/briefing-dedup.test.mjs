import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";
import estadoW31 from "./fixtures/materialidade-estado-2026-W31.json" with { type: "json" };
import estadoW32 from "./fixtures/materialidade-estado-2026-W32.json" with { type: "json" };
import estadoW33 from "./fixtures/materialidade-estado-2026-W33.json" with { type: "json" };
import estadoW34 from "./fixtures/materialidade-estado-2026-W34.json" with { type: "json" };
import estadoW35 from "./fixtures/materialidade-estado-2026-W35.json" with { type: "json" };
import anomalias from "./fixtures/anomalias.json" with { type: "json" };
import { _chaveDedupBriefing, carregarEstadoMultiSemana } from "../src/worker.js";
import { rankingTopComDedup } from "./_materialidade-common.mjs";

// BRIEFDEDUP1 (auditoria 2026-08-29, Fase 1.3).
//
// Medido no top 10 do briefing de producao: 6 historias em 10 vagas. Cosan 16/07
// (3 eventos, todos tag rating), Braskem 17/08 (2, o segundo com titulo byte
// identico) e CSN 31/07 (2) ocupavam 4 vagas com o mesmo fato de credito.
//
// O plano mandava dedup por titulo normalizado, e a medicao derrubou a hipotese:
// 7 titulos Cosan de 16/07 normalizam todos DIFERENTES, o dedup por titulo nao
// colapsaria nenhum. A chave implementada e (empresa, data_evento, tag de
// materialidade), com titulo normalizado como fallback para evento sem tag de
// materialidade. So atua no top_eventos do briefing; a lista do emissor fica
// intacta no detalhe.

const WEEKS = ["2026-W31", "2026-W32", "2026-W33", "2026-W34", "2026-W35"];
const ESTADOS = [estadoW31, estadoW32, estadoW33, estadoW34, estadoW35];
const FIX_KEY = "radar:estado:";

async function mintJWT(secret) {
  const b64url = (buf) => Buffer.from(buf).toString("base64url");
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const agora = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ sub: "test", email: "test@example.com", iat: agora, exp: agora + 3600 }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(sig)}`;
}

function kvMapDosFixtures() {
  const map = {};
  for (let i = 0; i < WEEKS.length; i++) {
    map[`${FIX_KEY}${WEEKS[i]}`] = JSON.stringify(ESTADOS[i]);
  }
  return map;
}

async function estadoMesclado() {
  const map = kvMapDosFixtures();
  return carregarEstadoMultiSemana({ RADAR_KV: { get: async (k) => (map[k] !== undefined ? map[k] : null) } }, 5);
}

function eventosDe(estado, nomeEmpresa) {
  const res = estado.results[nomeEmpresa];
  return Array.isArray(res && res.eventos) ? res.eventos : [];
}

describe("BRIEFING — dedup semantico (BRIEFDEDUP1)", () => {
  let estado;

  beforeEach(async () => {
    // RELOGIOTESTE1: `estadoMesclado` e o endpoint derivam a janela de 5 semanas
    // do relogio, e os fixtures estao em W31..W35. Congelado em 30/08 a janela
    // cobre os cinco; solto, a ponta velha cai fora e o top-10 muda sozinho.
    fixarRelogioDoFixture();
    const map = kvMapDosFixtures();
    for (const [k, v] of Object.entries(map)) await env.RADAR_KV.put(k, v);
    await env.RADAR_KV.put("mercado:anomalias:ativas", JSON.stringify(anomalias));
    estado = await estadoMesclado();
  });

  afterEach(() => {
    soltarRelogio();
  });

  it("mecanismo: os 3 eventos Cosan 16/07 com tag rating colapsam na mesma chave", () => {
    const cosan16 = eventosDe(estado, "Cosan").filter((e) => e.data_evento === "2026-07-16");
    expect(cosan16.length).toBeGreaterThan(3);
    const chaves = cosan16.map((e) => _chaveDedupBriefing(e));
    // Pelo menos um colapso entre os eventos do mesmo dia.
    expect(new Set(chaves).size).toBeLessThan(cosan16.length);
    // Todos os que carregam a tag de materialidade rating colapsam em UMA chave.
    const ratingKeys = cosan16.filter((e) => Array.isArray(e.tags) && e.tags.includes("rating")).map((e) => _chaveDedupBriefing(e));
    expect(ratingKeys.length).toBeGreaterThan(1);
    expect(new Set(ratingKeys).size).toBe(1);
  });

  it("mecanismo: fatos com data diferente nao colapsam (Light 18/19, CSN 31/07 e 07/08, Raizen 28/30)", () => {
    const light = eventosDe(estado, "Light").filter((e) => /2026-08-1[89]/.test(e.data_evento));
    expect(light.length).toBeGreaterThanOrEqual(2);
    for (let i = 0; i < light.length; i++) {
      for (let j = i + 1; j < light.length; j++) {
        if (light[i].data_evento !== light[j].data_evento) {
          expect(_chaveDedupBriefing(light[i])).not.toBe(_chaveDedupBriefing(light[j]));
        }
      }
    }
    const csn = eventosDe(estado, "CSN").filter((e) => e.data_evento === "2026-07-31" || e.data_evento === "2026-08-07");
    expect(csn.length).toBeGreaterThanOrEqual(2);
    const csnKeys = new Set(csn.map((e) => _chaveDedupBriefing(e)));
    expect(csnKeys.size).toBeGreaterThan(1); // 31/07 e 07/08 nao colapsam
    const raizen = eventosDe(estado, "Raízen").filter((e) => e.data_evento === "2026-07-28" || e.data_evento === "2026-07-30");
    expect(raizen.length).toBeGreaterThanOrEqual(2);
    expect(new Set(raizen.map((e) => _chaveDedupBriefing(e))).size).toBeGreaterThan(1);
  });

  it("top_eventos: Cosan e Braskem aparecem uma vez cada, Auren ganha vaga", async () => {
    const token = await mintJWT(env.JWT_SECRET);
    const r = await SELF.fetch("https://exemplo.invalid/?op=briefing_executivo", {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(r.status).toBe(200);
    const j = await r.json();
    expect(j.ok).toBe(true);
    const top = j.briefing.top_eventos;
    expect(Array.isArray(top)).toBe(true);
    expect(top.length).toBe(10);

    const cosan = top.filter((e) => e.empresa === "Cosan");
    const braskem = top.filter((e) => e.empresa === "Braskem");
    const csn31 = top.filter((e) => e.empresa === "CSN" && e.data_evento === "2026-07-31");
    const csn07 = top.filter((e) => e.empresa === "CSN" && e.data_evento === "2026-08-07");
    expect(cosan.length).toBe(1);   // era 3
    expect(braskem.length).toBe(1); // era 2 (titulo byte identico)
    expect(csn31.length).toBe(1);   // era 2
    expect(csn07.length).toBe(1);   // fato distinto, sobrevive

    // Auren entra onde antes sobravam 4 vagas de duplicata.
    expect(top.some((e) => e.empresa === "Auren Energia")).toBe(true);

    // Nenhum par (empresa, data_evento) repete no top-10.
    const pares = top.map((e) => `${e.empresa}|${e.data_evento}`);
    expect(new Set(pares).size).toBe(pares.length);
  });

  it("cross-check: top-10 do endpoint bate com o harness dedupado, byte a byte", async () => {
    const token = await mintJWT(env.JWT_SECRET);
    // Com o relogio preso em 30/08 o endpoint pede W35..W31, as chaves onde o
    // beforeEach ja gravou os fixtures. Nao ha mais remapeamento de semana.
    const r = await SELF.fetch("https://exemplo.invalid/?op=briefing_executivo", {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(r.status).toBe(200);
    const j = await r.json();
    const top = j.briefing.top_eventos;
    const meu = await rankingTopComDedup(kvMapDosFixtures());
    expect(meu.length).toBeGreaterThanOrEqual(10);
    for (let i = 0; i < 10; i++) {
      expect({ empresa: top[i].empresa, data: top[i].data_evento, m: top[i].materialidade }).toEqual(meu[i]);
    }
  });
});
