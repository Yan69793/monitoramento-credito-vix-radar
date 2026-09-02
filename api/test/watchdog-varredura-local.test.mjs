import { SELF, env, createScheduledController, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/worker.js";

// WATCHDOG-AGENTEMORTO1 (2026-09-02, auditoria de rotinas de 01/09, nota 99).
//
// O e-mail "[VixRadar] Health" das 22h BRT veio ALERTA em 8 de 8 dias (24 a 31/08)
// pelo mesmo motivo, "cascade_analise (nunca_bateu)". Esse heartbeat so e batido
// dentro da cascata de analise do proprio Worker (rota paga consulta_empresa, o
// botao do app), que nao roda desde que a varredura foi delegada as rotinas locais
// (VARREDURA_CRON_AI_ENABLED=false). O watchdog esperava um agente morto, e um
// alarme que dispara todo dia com motivo identico e defeito de configuracao, nao
// incidente: enquanto ele estiver vermelho, um alerta verdadeiro chega com a mesma
// cara. Ao mesmo tempo, nenhuma das tres rotinas locais deixava sinal de entrega
// no watchdog, porque receber_analise nao batia heartbeat nenhum.
//
// Correcao: receber_analise bate `varredura_local` DEPOIS da persistencia e da
// marcacao de cvm_vistos (mede entrega, nao inicio de rotina), com a origem
// (matinal, noturno, pontual) nos extras; expectedAgents troca cascade_analise,
// varredura_batch e varredura_matinal (os dois ultimos so carimbam "pulado" desde a
// delegacao) por varredura_local, com limite de 26h (matinal diaria 10h06, watchdog
// 22h: um dia inteiro sem submissao alarma, um dia normal nao).
//
// Prova reversa (regra 5 do CLAUDE.md): ver o bloco "MEDIDO CONTRA v4.9.232" no fim
// deste arquivo, colado da execucao real antes da correcao.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const DASA = "Dasa";
const AGENTES_VIVOS_ALEM_DA_VARREDURA = ["sync_cvm", "newsletter", "healthcheck_diario", "verificacao_async"];

async function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.77" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body))
  });
}

async function semearHeartbeat(agente, tsIso) {
  await env.RADAR_KV.put("heartbeat:" + agente, JSON.stringify({ agente, status: "ok", ts: tsIso, versao: "test", extras: {} }));
}

// Semeia tudo que o watchdog espera ALEM da varredura, mais os dois heartbeats de
// cron que o Worker segue escrevendo com status "pulado". Assim a unica variavel
// sob teste e a varredura: contra o codigo anterior o unico stale que sobra e
// exatamente o cascade_analise da producao.
async function semearVivos() {
  const agora = new Date().toISOString();
  for (const a of AGENTES_VIVOS_ALEM_DA_VARREDURA) await semearHeartbeat(a, agora);
  await semearHeartbeat("varredura_batch", agora);
  await semearHeartbeat("varredura_matinal", agora);
}

async function rodarWatchdog() {
  const ctrl = createScheduledController({ scheduledTime: new Date(), cron: "0 1 * * *" });
  const ctx = createExecutionContext();
  await worker.scheduled(ctrl, env, ctx);
  await waitOnExecutionContext(ctx);
  return env.RADAR_KV.get("watchdog:ultimo", "json");
}

async function submeter(extra) {
  const res = await post(Object.assign({
    action: "receber_analise",
    empresa: DASA,
    setor: "Saúde",
    resultado: { sem_eventos: true, eventos: [], fontes_consultadas: [] }
  }, extra || {}));
  expect(res.status).toBe(200);
  const j = await res.json();
  expect(j.ok).toBe(true);
  return j;
}

async function limpar() {
  const lista = await env.RADAR_KV.list({ prefix: "heartbeat:" });
  for (const k of lista.keys) {
    try { await env.RADAR_KV.delete(k.name); } catch (_) { }
  }
  try { await env.RADAR_KV.delete("watchdog:ultimo"); } catch (_) { }
}

beforeEach(limpar);
afterEach(limpar);

describe("WATCHDOG-AGENTEMORTO1: o watchdog espera quem entrega, nao quem morreu", () => {
  it("PONTA BOA (prova reversa): depois de um receber_analise o watchdog nao acusa agente nenhum", async () => {
    await semearVivos();
    await submeter();
    const w = await rodarWatchdog();
    expect(w).toBeTruthy();
    // Contra v4.9.232 isto falha com [{ agente: "cascade_analise", motivo: "nunca_bateu" }],
    // que e literalmente a linha do e-mail ALERTA dos 8 dias.
    expect(w.stale_agents).toEqual([]);
    expect(w.stale_agents.map((s) => s.agente)).not.toContain("cascade_analise");
    const hb = await env.RADAR_KV.get("heartbeat:varredura_local", "json");
    expect(hb).toBeTruthy();
    expect(hb.status).toBe("ok");
    expect(hb.extras.origem).toBe("noturno");
    expect(hb.extras.empresa).toBe(DASA);
  });

  it("PONTA RUIM: sem submissao nenhuma, o watchdog acusa varredura_local como nunca_bateu", async () => {
    await semearVivos();
    const w = await rodarWatchdog();
    expect(w.stale_agents).toEqual([{ agente: "varredura_local", motivo: "nunca_bateu" }]);
  });

  it("PONTA RUIM: ultima entrega ha 27h alarma (stale_27h); ha 20h nao alarma", async () => {
    await semearVivos();
    await semearHeartbeat("varredura_local", new Date(Date.now() - (27 * 60 + 1) * 60 * 1e3).toISOString());
    let w = await rodarWatchdog();
    expect(w.stale_agents.length).toBe(1);
    expect(w.stale_agents[0].agente).toBe("varredura_local");
    expect(w.stale_agents[0].motivo).toBe("stale_27h");

    await semearHeartbeat("varredura_local", new Date(Date.now() - 20 * 60 * 60 * 1e3).toISOString());
    w = await rodarWatchdog();
    expect(w.stale_agents).toEqual([]);
  });

  it("origem do heartbeat: _matinal vira matinal, provedor da sentinela vira pontual, origem explicita prevalece", async () => {
    await submeter({ _matinal: true });
    let hb = await env.RADAR_KV.get("heartbeat:varredura_local", "json");
    expect(hb.extras.origem).toBe("matinal");

    await submeter({ provedor: "claude-sentinela-claude-haiku-4-5-20251001" });
    hb = await env.RADAR_KV.get("heartbeat:varredura_local", "json");
    expect(hb.extras.origem).toBe("pontual");

    await submeter({ origem: "noturno", _matinal: true });
    hb = await env.RADAR_KV.get("heartbeat:varredura_local", "json");
    expect(hb.extras.origem).toBe("noturno");
  });

  it("submissao recusada (empresa fora da lista) NAO bate heartbeat: o sinal mede entrega", async () => {
    const res = await post({ action: "receber_analise", empresa: "Empresa Inexistente XYZ", setor: "Outros", resultado: { sem_eventos: true, eventos: [] } });
    expect(res.status).toBe(400);
    const hb = await env.RADAR_KV.get("heartbeat:varredura_local", "json");
    expect(hb).toBeNull();
  });
});

// MEDIDO CONTRA v4.9.232 (02/09/2026 02:07 BRT, antes da correcao), saida crua do vitest:
//   Tests  4 failed | 1 passed (5)
//   FAIL PONTA BOA (prova reversa): AssertionError: expected [ { agente: 'cascade_analise', ... } ] to deeply equal []
//   FAIL PONTA RUIM sem submissao: expected [ { agente: 'cascade_analise', motivo: 'nunca_bateu' } ]
//        to deeply equal [ { agente: 'varredura_local', motivo: 'nunca_bateu' } ]
//   FAIL PONTA RUIM 27h: expected 'cascade_analise' to be 'varredura_local'
//   FAIL origem do heartbeat: TypeError: Cannot read properties of null (reading 'extras')
//        (heartbeat:varredura_local nao existia, receber_analise nao batia nada)
//   PASS submissao recusada nao bate heartbeat (vale nas duas versoes, e a guarda de que o sinal mede entrega)
// O unico stale que o codigo antigo acusava e exatamente a linha do e-mail ALERTA de 8 dias.
