import { SELF, env } from "cloudflare:test";
import { describe, expect, it, afterEach } from "vitest";

// ANOMSCHEMA1 (2026-08-21): o detector de anomalia de taxa indicativa estava
// morto por unidade. A fonte atual (anbima_publico) grava taxa em percentual ao
// ano, mas o detector dividia o delta por 100, herdado do provedor legado que
// gravava ponto-base. Um salto de 2,75 p.p. virava 0,0275 e nunca batia no
// limiar de 1. Estes testes semeiam a serie no formato REAL da fonte e exigem
// que o salto dispare. Contra o codigo antigo, o primeiro teste falha: o delta
// dividido por 100 fica abaixo do limiar e anomalias_encontradas volta 0.

const SENHA = "test-admin-password-nao-usar-em-producao";
const CHAVES = ["mercado:serie:aegea%20saneamento", "mercado:serie:copasa"];

function serie(empresa, dias, taxaBase, taxaUltima) {
  const registros = [];
  for (let i = 0; i < dias; i++) {
    const d = new Date(2026, 6, 1 + i); // jul/2026, sequencial
    const data = d.toISOString().slice(0, 10);
    registros.push({
      data,
      taxa_indicativa_pct: i === dias - 1 && taxaUltima != null ? taxaUltima : taxaBase,
      spread_bps: i === dias - 1 && taxaUltima != null ? taxaUltima : taxaBase,
      fonte: "anbima_publico",
      volume: null,
      negocios: null,
      maior_negocio: null
    });
  }
  return { registros, updated_at: "2026-07-26T00:00:00.000Z" };
}

function postRecalcular() {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.90" },
    body: JSON.stringify({ action: "admin_recalcular_anomalias", admin_senha: SENHA })
  });
}

afterEach(async () => {
  for (const k of CHAVES) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
});

describe("ANOMSCHEMA1: detector de anomalia alinhado ao schema anbima_publico", () => {
  it("salto de 2,75 p.p. na taxa indicativa dispara anomalia de spread", async () => {
    // Aegea Saneamento pertence a EMISSORES_LISTA do worker.
    await env.RADAR_KV.put(
      "mercado:serie:aegea%20saneamento",
      JSON.stringify(serie("Aegea Saneamento", 25, 9.75, 12.5))
    );

    const res = await postRecalcular();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.anomalias_encontradas).toBeGreaterThanOrEqual(1);
    const aegea = (body.detalhes || []).find((d) => d.empresa === "Aegea Saneamento");
    expect(aegea).toBeDefined();
    expect(aegea.tipos).toContain("spread");
  });

  it("serie plana nao dispara anomalia nenhuma", async () => {
    await env.RADAR_KV.put(
      "mercado:serie:copasa",
      JSON.stringify(serie("Copasa", 25, 10.0, 10.0))
    );

    const res = await postRecalcular();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    const copasa = (body.detalhes || []).find((d) => d.empresa === "Copasa");
    expect(copasa).toBeUndefined();
  });
});
