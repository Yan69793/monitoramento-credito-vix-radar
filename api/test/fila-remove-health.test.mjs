import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  chaveFilaVerificacao,
  chaveTentativaVerificacao,
  _definirFalhaInjetadaTeste,
  _limparFalhasInjetadasTeste,
} from "../src/worker.js";
import { bootstrapIndiceQuarentena, resetIndiceQuarentena } from "./_quarentena-idx.mjs";

// =============================================================================
// FILAREMOVE1 (2026-10-17). Em 16/10 01:36Z a rotina aplicou REPROVADO nao-conclusivo
// em dois eventos da Minerva na mesma chave diaria, com 1s de intervalo. O de 10-09 saiu
// da fila, o de 10-08 ficou: o veredicto foi aplicado (attempt n=1, backoff ate 17/10
// 01:36Z) mas a remocao nao persistiu, e o retorno de removerDaFilaVerificacao era
// ignorado. A copia ficou escondida pelo backoff e voltou 24h depois; o health contou a
// idade desde o criado_em original (28h) e derrubou verificador_ok com o item elegivel
// ha 1h.
//
// Contrato, sempre de duas pontas:
//   H1  item antigo SEM tentativa continua atrasado (gate nao afrouxou)
//   H2  item antigo cujo backoff venceu ha pouco NAO esta atrasado (idade = desde elegivel)
//   H3  item cujo backoff venceu ha mais de 20h continua atrasado
//   C1  remocao que falha apos o veredicto aparece em fila_remocao_falhas
//   C2  remocao que funciona nao gera falha nenhuma
// =============================================================================

const H = 36e5;
const hoje = () => new Date().toISOString().slice(0, 10);
const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const EMPRESA = "Minerva Foods";
const SEMANA = "2026-W42";
const FONTE = "https://neofeed.com.br/negocios/exclusivo-minerva";
const ID = "2026-10-08|minerva foods|neofeed.com.br/negocios/exclusivo-minerva";

function evento() {
  return {
    empresa: EMPRESA, classificacao: "ATENCAO", titulo: "Minerva estuda fechar capital",
    evento: "Minerva volta a se movimentar para fechar o capital.", impacto_credito: "Relevante.",
    fonte_primaria: FONTE, fonte_tipo: "Imprensa", data_evento: "2026-10-08", tags: ["governanca"],
  };
}
function itemFila(idadeH) {
  return { id: ID, empresa: EMPRESA, semana: SEMANA, setor: "Alimentos", evento: evento(), criado_em: new Date(Date.now() - idadeH * H).toISOString() };
}
async function semearFila(itens) {
  await env.RADAR_KV.put(chaveFilaVerificacao(hoje()), JSON.stringify(itens), { expirationTtl: 60 * 60 * 24 * 7 });
}
async function semearTentativa(proximaHAtras) {
  const proxima = new Date(Date.now() - proximaHAtras * H).toISOString();
  const ultima = new Date(Date.now() - (proximaHAtras + 24) * H).toISOString();
  await env.RADAR_KV.put(chaveTentativaVerificacao(ID), JSON.stringify({ id: ID, n: 1, ultima_em: ultima, atualizado_em: ultima, empresa: EMPRESA, semana: SEMANA, proxima_em: proxima }));
}
const health = () => SELF.fetch("https://example.com/").then((r) => r.json());
async function confirmarReprovado() {
  const r = await SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      action: "confirmar_verificacao", routine_key: ROUTINE_KEY,
      itens: [{ id: ID, empresa: EMPRESA, semana: SEMANA, data_fila: hoje(), setor: "Alimentos", evento: evento(),
        veredicto: { veredicto: "REPROVADO", confianca: 0.6, motivo: "fonte inacessivel, nao provado falso" } }],
    }),
  });
  return r.json();
}

beforeEach(async () => {
  _limparFalhasInjetadasTeste();
  await resetIndiceQuarentena();
  await bootstrapIndiceQuarentena(env);
  await env.RADAR_KV.delete(chaveFilaVerificacao(hoje()));
  await env.RADAR_KV.delete(chaveTentativaVerificacao(ID));
});
afterEach(() => _limparFalhasInjetadasTeste());

describe("FILAREMOVE1 - idade da fila conta desde que o item ficou elegivel", () => {
  it("H1. item com 30h e sem tentativa continua atrasado", async () => {
    await semearFila([itemFila(30)]);
    const b = await health();
    expect(b.verif_fila_atrasada).toBe(true);
    expect(b.verif_fila_mais_antiga_h).toBeGreaterThanOrEqual(29);
    expect(b.verificador_ok).toBe(false);
  });

  it("H2. item com 30h cujo backoff venceu ha 1h nao esta atrasado (caso Minerva 17/10)", async () => {
    await semearFila([itemFila(30)]);
    await semearTentativa(1);
    const b = await health();
    expect(b.verif_fila_pendentes).toBe(1);
    expect(b.verif_fila_atrasada).toBe(false);
    expect(b.verif_fila_mais_antiga_h).toBeLessThanOrEqual(2);
  });

  it("H3. backoff vencido ha 22h e item nao processado continua atrasado", async () => {
    await semearFila([itemFila(50)]);
    await semearTentativa(22);
    const b = await health();
    expect(b.verif_fila_atrasada).toBe(true);
    expect(b.verif_fila_mais_antiga_h).toBeGreaterThanOrEqual(21);
  });
});

describe("FILAREMOVE1 - remocao que falha apos o veredicto nao some em silencio", () => {
  it("C1. falha de escrita na remocao aparece em fila_remocao_falhas e o item fica", async () => {
    await semearFila([itemFila(2)]);
    _definirFalhaInjetadaTeste("fila_remover_put");
    const r = await confirmarReprovado();
    expect(r.ok).toBe(true);
    expect(r.resultado.rejeitados).toBe(1);
    expect(r.resultado.fila_remocao_falhas).toBe(1);
    const fila = await env.RADAR_KV.get(chaveFilaVerificacao(hoje()), "json");
    expect(fila).toHaveLength(1);
  });

  it("C2. remocao normal nao gera falha e a fila esvazia", async () => {
    await semearFila([itemFila(2)]);
    const r = await confirmarReprovado();
    expect(r.ok).toBe(true);
    expect(r.resultado.rejeitados).toBe(1);
    expect(r.resultado.fila_remocao_falhas).toBeUndefined();
    expect(await env.RADAR_KV.get(chaveFilaVerificacao(hoje()), "json")).toBeNull();
  });
});
