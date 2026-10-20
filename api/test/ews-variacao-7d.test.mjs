import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";
import { EMAIL_FIXTURE, tokenFixture } from "./_auth-fixture.mjs";
import { persistirHistEwsBatch, referenciaEws7d, EWS_HIST_RESUMO_KEY } from "../src/worker.js";
import estadoW35 from "./fixtures/estado-2026-W35.json" with { type: "json" };
import anomalias from "./fixtures/anomalias.json" with { type: "json" };

// EWSVAR7D1 (2026-10-20): op=ews ganha score_anterior_7d e delta_7d por item, lidos de um
// resumo unico (1 leitura de KV por request), gravado pelo pipeline preditivo junto com as
// series ews:hist:{empresa}. Duas pontas: com ponto na janela de 7 dias devolve delta, sem
// historico (ou so com ponto fora da janela) devolve null, nunca estima.
// Relogio fixo em 2026-08-30 BRT, entao a janela de referencia e 2026-08-20..2026-08-23.

let token;
beforeEach(async () => {
  await bootstrapIndiceQuarentena(env);
  fixarRelogioDoFixture();
  await env.RADAR_KV.put("radar:estado:2026-W35", JSON.stringify(estadoW35));
  await env.RADAR_KV.put("mercado:anomalias:ativas", JSON.stringify(anomalias));
  token = await tokenFixture(EMAIL_FIXTURE);
});
afterEach(async () => {
  soltarRelogio();
  await env.RADAR_KV.delete(EWS_HIST_RESUMO_KEY);
});

async function ews(empresa) {
  const q = empresa ? `&empresa=${encodeURIComponent(empresa)}` : "";
  const r = await SELF.fetch(`https://exemplo.invalid/?op=ews${q}`, { headers: { Authorization: `Bearer ${token}` } });
  expect(r.status).toBe(200);
  return r.json();
}

describe("EWSVAR7D1: variacao de 7 dias no op=ews", () => {
  it("sem resumo no KV todo item vem com os campos em null", async () => {
    const j = await ews();
    expect(j.ranking.length).toBeGreaterThan(0);
    for (const it of j.ranking) {
      expect(it.score_anterior_7d).toBeNull();
      expect(it.delta_7d).toBeNull();
    }
  });

  it("com historico de 7 dias o ranking devolve score anterior e delta", async () => {
    const base = await ews();
    const alvo = base.ranking[0];
    // A chave do resumo e gravada em minusculo, o ranking usa o nome original.
    await persistirHistEwsBatch(env, [{ empresa: alvo.empresa, hist: [
      { data: "2026-08-30", score: alvo.score },
      { data: "2026-08-25", score: 1 },          // 5 dias: fora da janela
      { data: "2026-08-22", score: alvo.score - 7.5 }, // 8 dias: referencia
      { data: "2026-08-21", score: 0 },          // 9 dias: mais antigo, perde para 22/08
    ] }]);
    const j = await ews();
    const it = j.ranking.find((x) => x.empresa === alvo.empresa);
    expect(it.score_anterior_7d).toBe(alvo.score - 7.5);
    expect(it.delta_7d).toBe(7.5);
    expect(it.data_anterior_7d).toBe("2026-08-22");
    expect(j.ranking.filter((x) => x.delta_7d !== null).length).toBe(1);
  });

  it("consulta por empresa tambem recebe a variacao", async () => {
    const alvo = (await ews()).ranking[0];
    await persistirHistEwsBatch(env, [{ empresa: alvo.empresa, hist: [{ data: "2026-08-23", score: alvo.score + 2 }] }]);
    const e = (await ews(alvo.empresa)).ews;
    expect(e.score_anterior_7d).toBe(alvo.score + 2);
    expect(e.delta_7d).toBe(-2);
  });

  it("historico so com ponto recente ou antigo demais devolve null, nao cai para o mais velho", async () => {
    const alvo = (await ews()).ranking[0];
    await persistirHistEwsBatch(env, [{ empresa: alvo.empresa, hist: [
      { data: "2026-08-29", score: 10 },
      { data: "2026-08-15", score: 90 },
    ] }]);
    const it = (await ews()).ranking.find((x) => x.empresa === alvo.empresa);
    expect(it.score_anterior_7d).toBeNull();
    expect(it.delta_7d).toBeNull();
  });

  it("resumo corrompido no KV nao derruba o endpoint", async () => {
    await env.RADAR_KV.put(EWS_HIST_RESUMO_KEY, "{nao e json");
    const j = await ews();
    expect(j.ok).toBe(true);
    expect(j.ranking.every((x) => x.delta_7d === null)).toBe(true);
  });
});

describe("referenciaEws7d (pura)", () => {
  it("escolhe o ponto mais recente entre 7 e 10 dias", () => {
    const s = [{ data: "2026-10-13", score: 40 }, { data: "2026-10-11", score: 30 }, { data: "2026-10-19", score: 50 }];
    expect(referenciaEws7d(s, "2026-10-20")).toEqual({ data: "2026-10-13", score: 40 });
  });
  it("sem ponto na janela devolve null", () => {
    expect(referenciaEws7d([{ data: "2026-10-18", score: 1 }, { data: "2026-10-01", score: 2 }], "2026-10-20")).toBeNull();
    expect(referenciaEws7d([], "2026-10-20")).toBeNull();
    expect(referenciaEws7d(null, "2026-10-20")).toBeNull();
  });
});
