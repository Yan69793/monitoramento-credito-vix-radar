import { env } from "cloudflare:test";
import { describe, expect, it, beforeEach } from "vitest";
import {
  _cronDisjuntorBloqueia,
  _RAMOS_CRON_COM_LLM,
  CUSTO_DISJUNTOR_USD_DIA,
  dataCustoBRT,
} from "../src/worker.js";

// DISJUNTORHOUSEKEEP1 (2026-09-01, achado P3-2 da auditoria geral). Ate a v4.9.227 o
// disjuntor de custo diario rodava ANTES do despacho do cron e dava `return` no handler
// inteiro quando o teto estourava, para matinal e noturno. A premissa era que esses dois
// crons gastavam LLM. Desde a delegacao da varredura ao Claude Desktop
// (VARREDURA_CRON_AI_ENABLED=false) ela deixou de valer: o Worker marca a varredura como
// "pulado/delegado_claude_tiered_v2" e o cron vira so housekeeping. O teto, por sua vez,
// e alimentado pelo gasto das rotinas LOCAIS. Resultado: um dia caro la fora abortava
// aqui o sync_cvm e o healthcheck_diario, que sao os dois sinais que o watchdog e o
// frescor leem para avisar que o pipeline parou. O sistema emudecia o alarme exatamente
// no dia ruim, mesmo modo de falha do FIX(N1) da v4.9.163 um nivel acima.
//
// Sobre a prova reversa: contra o codigo pre-correcao estes casos nao tinham como ser
// expressos, porque nao havia decisao por ramo nenhuma, o corte era do cron todo e
// acontecia antes. O que este arquivo trava e a politica nova, nas duas pontas: o
// disjuntor REPROVA o ramo que gasta LLM e ACEITA todo o resto.

const RAMOS_HOUSEKEEPING = [
  "sync_cvm",
  "recalcular_anomalias",
  "sync_anbima",
  "pipeline_preditivo",
  "newsletter",
  "relatorio_diario",
  "verificar_saldo",
  "healthcheck_diario",
];

function envCom(overrides) {
  return { RADAR_KV: env.RADAR_KV, ...overrides };
}

async function estourarTeto() {
  await env.RADAR_KV.put(
    "radar:custo:" + dataCustoBRT(),
    JSON.stringify({ custo_estimado_usd: CUSTO_DISJUNTOR_USD_DIA + 1 })
  );
}

async function zerarCusto() {
  await env.RADAR_KV.put(
    "radar:custo:" + dataCustoBRT(),
    JSON.stringify({ custo_estimado_usd: 0 })
  );
}

describe("DISJUNTORHOUSEKEEP1: teto de custo so barra ramo que gasta LLM", () => {
  beforeEach(async () => {
    await estourarTeto();
  });

  it("com o teto estourado, NENHUM ramo de housekeeping e barrado", async () => {
    // Ponta boa. Esta e a regressao que motivou a correcao: sync_cvm e healthcheck_diario
    // nao podem morrer por causa de custo de LLM que eles nao geram.
    const e = envCom({ VARREDURA_CRON_AI_ENABLED: "true" });
    for (const ramo of RAMOS_HOUSEKEEPING) {
      expect(await _cronDisjuntorBloqueia(e, ramo), ramo).toBe(false);
    }
  });

  it("com o teto estourado e varredura no Worker ligada, o ramo de varredura E barrado", async () => {
    // Ponta ruim. O disjuntor continua existindo e continua cortando o que gasta dinheiro.
    const e = envCom({ VARREDURA_CRON_AI_ENABLED: "true" });
    expect(await _cronDisjuntorBloqueia(e, "varredura_matinal")).toBe(true);
    expect(await _cronDisjuntorBloqueia(e, "varredura_batch")).toBe(true);
  });

  it("com o teto estourado e a varredura delegada (config real de producao), nada e barrado", async () => {
    // VARREDURA_CRON_AI_ENABLED=false e o estado vigente: o Worker nao chama provider
    // nenhum no cron, entao nao ha custo para o disjuntor proteger e o cron inteiro roda.
    const e = envCom({ VARREDURA_CRON_AI_ENABLED: "false" });
    expect(await _cronDisjuntorBloqueia(e, "varredura_matinal")).toBe(false);
    expect(await _cronDisjuntorBloqueia(e, "varredura_batch")).toBe(false);
  });

  it("sem o teto estourado, o ramo de varredura roda normalmente", async () => {
    await zerarCusto();
    const e = envCom({ VARREDURA_CRON_AI_ENABLED: "true" });
    expect(await _cronDisjuntorBloqueia(e, "varredura_matinal")).toBe(false);
  });

  it("leitura de custo quebrada nao vira corte silencioso (fail-open, CUSTOBRAKE1)", async () => {
    const kvQuebrado = {
      get: async () => {
        throw new Error("KV indisponivel (simulado)");
      },
    };
    const e = { RADAR_KV: kvQuebrado, VARREDURA_CRON_AI_ENABLED: "true" };
    expect(await _cronDisjuntorBloqueia(e, "varredura_matinal")).toBe(false);
    expect(await _cronDisjuntorBloqueia(e, "sync_cvm")).toBe(false);
  });

  it("a lista de ramos sob disjuntor nao contem housekeeping", async () => {
    // Guarda contra reintroducao por copiar-colar: se um ramo de housekeeping entrar na
    // lista, isto reprova antes de chegar em producao.
    for (const ramo of RAMOS_HOUSEKEEPING) {
      expect(_RAMOS_CRON_COM_LLM).not.toContain(ramo);
    }
    expect(_RAMOS_CRON_COM_LLM).toEqual(["varredura_matinal", "varredura_batch"]);
  });
});
