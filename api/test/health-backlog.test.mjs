import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { chaveFilaVerificacao } from "../src/worker.js";
import { bootstrapIndiceQuarentena, resetIndiceQuarentena } from "./_quarentena-idx.mjs";

// HEALTHBACKLOG1 (2026-10-09). O backlog da fila de verificacao era DOBRADO num booleano
// (`verificador_ok`). Com `verificador_ok:true` nao dava para saber se havia 1 ou 500 itens
// esperando, nem ha quanto tempo - o numero era calculado e descartado. Estes testes travam
// a exposicao aditiva (nada mudou em `ok` nem em `verificador_ok`).

function hojeISO() { return new Date().toISOString().slice(0, 10); }
async function health() {
  const r = await SELF.fetch("https://example.com/");
  expect(r.status).toBe(200);
  return r.json();
}
async function seedFila(itens, dia) {
  await env.RADAR_KV.put(chaveFilaVerificacao(dia || hojeISO()), JSON.stringify(itens));
}
function item(id, horasAtras) {
  return {
    id,
    empresa: "Petrobras",
    semana: "2026-W36",
    setor: "Energia Eletrica",
    criado_em: new Date(Date.now() - horasAtras * 36e5).toISOString(),
    eventos: [{ id: id + "-ev" }]
  };
}

describe("HEALTHBACKLOG1 - backlog da fila visivel no health (nao dobrado num booleano)", () => {
  beforeEach(async () => {
    await resetIndiceQuarentena();
    await bootstrapIndiceQuarentena(env);
    await env.RADAR_KV.delete(chaveFilaVerificacao(hojeISO()));
  });

  it("fila com 1 item atrasado (30h) e 1 recente: contagem, idade e atraso expostos", async () => {
    await seedFila([item("a", 30), item("b", 1)]);
    const b = await health();
    expect(b.verif_fila_pendentes).toBe(2);
    expect(b.verif_fila_mais_antiga_h).toBeGreaterThanOrEqual(29);
    expect(b.verif_fila_atrasada).toBe(true);
    // O gate existente continua valendo (item >= 20h derruba o verificador).
    expect(b.verificador_ok).toBe(false);
    expect(b.api_disponivel).toBe(true);
  });

  it("fila com itens recentes: sem atraso, contagem > 0 (distingue 'nada' de 'pouco')", async () => {
    await seedFila([item("c", 1), item("d", 2)]);
    const b = await health();
    expect(b.verif_fila_pendentes).toBe(2);
    expect(b.verif_fila_atrasada).toBe(false);
    expect(b.verif_fila_mais_antiga_h).toBeLessThan(20);
  });

  it("fila vazia: zero itens, zero atraso (nunca null quando mensuravel)", async () => {
    const b = await health();
    expect(b.verif_fila_pendentes).toBe(0);
    expect(b.verif_fila_mais_antiga_h).toBe(0);
    expect(b.verif_fila_atrasada).toBe(false);
  });
});
