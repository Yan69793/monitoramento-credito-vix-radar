import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as W from "../src/worker.js";

// REPROVADO-FAILCLOSED1 (2026-09-06): gates sao fail-closed; indice ausente = erro.
beforeEach(async () => { await bootstrapIndiceQuarentena(env); });

// EMISSORSTALE2 (2026-09-19, auditoria dos relatorios 103 e 104).
//
// A guarda EMISSORSTALE1 do frescor-check lia `horas_stale` do listar_plano_rotina, e o
// campo saia de `_last_scanned_at`. SKIP e deferido renovam esse carimbo nos seis
// caminhos de escrita de persistirResultadoCompartilhadoInterno, entao a guarda media
// VARREDURA e nao ANALISE. Em 18/09 a noturna deferiu 78 e pulou 26 com 0 analises, e a
// guarda mediu 0/104 stale. O carimbo certo (`_ultima_analise_at`, gravado so por
// _carimbarAnaliseReal) ja existia desde a CREDITODIA1.
//
// Medido em producao em 19/09 19:53Z (v4.9.258), no denominador do gate (104 emissores, os
// 17 inconclusivos contados a parte): relogio de varredura 0 de 104 acima de 24h, maximo
// 22,8h. Relogio de analise 68 de 104, maximo 127,3h. As 20:34Z ja eram 73 de 104.
//
// Decisoes do operador em 19/09, travadas aqui:
//   1. horas_stale passa a medir a ultima analise real. O TIERING continua no relogio de
//      varredura (horas_desde_varredura), porque mudar isso muda gasto e anda junto do P0
//      de orcamento. O teste "tiering inalterado" passa antes e depois da mudanca.
//   2. Falta de carimbo falha fechado, com sentinela nomeado (HORAS_SEM_REGISTRO), base
//      propria e contagem propria. Carimbo que so existe nas semanas retidas alem da mescla
//      de 3 semanas tem rotulo diferente (ultima_analise_fora_da_mescla) e horas reais.
//   3. horas_desde_analise deriva da mesma funcao, para nao existirem dois relogios de
//      analise divergentes no mesmo item.
//
// Prova reversa: ver o bloco "MEDIDO CONTRA v4.9.258" no fim do arquivo.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const KEY_DOCS = "cvm:documentos";
const DASA = "Dasa";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}
function agoraBRT() { return new Date(Date.now() - 3 * 60 * 60 * 1e3); }
// Mesma conta de carregarEstadoMultiSemana: semana ISO de (agora BRT - n semanas).
function chaveEstadoSemanasAtras(n) { return `radar:estado:${semanaISO(new Date(agoraBRT().getTime() - n * 7 * 864e5))}`; }
function horasAtrasIso(h) { return new Date(Date.now() - h * 60 * 60 * 1e3).toISOString(); }

async function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.78" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body))
  });
}

async function plano(modo, extra = {}) {
  const res = await post(Object.assign({ action: "listar_plano_rotina", modo }, extra));
  expect(res.status).toBe(200);
  return res.json();
}

async function planoDasa(modo, extra = {}) {
  const p = await plano(modo, extra);
  const d = p.emissores.find((e) => e.empresa === DASA);
  expect(d, "Dasa no plano " + modo).toBeDefined();
  return { p, d };
}

async function gravarEstado(results, chave) {
  chave = chave || chaveEstadoSemanasAtras(0);
  await env.RADAR_KV.put(chave, JSON.stringify({ week: chave.replace("radar:estado:", ""), updated_at: new Date().toISOString(), results }));
}

async function limpar() {
  const chaves = [0, 1, 2, 3, 4].map(chaveEstadoSemanasAtras).concat([KEY_DOCS, "radar:cvm_vistos:dasa", "radar:cvm_vistos:rumo"]);
  for (const k of chaves) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

beforeEach(limpar);
afterEach(limpar);

// Emissor quieto: sem evento, sem documento CVM, EWS zero. Varrido ha 1h (SKIP ou deferido
// renovaram a varredura) e analisado de verdade ha 100h. E o retrato de 18/09.
function dasaVarridaAnalisadaHa(hVarredura, hAnalise, extra) {
  return Object.assign({
    _last_scanned_at: horasAtrasIso(hVarredura),
    _ultima_analise_at: horasAtrasIso(hAnalise),
    _ultimo_tier: "LIGHT",
    _ultima_origem: "noturno",
    _status: "OK",
    eventos: [],
    sem_eventos: true
  }, extra || {});
}

describe("EMISSORSTALE2: horas_stale mede a ultima analise real, nao a varredura", () => {
  it("PONTA RUIM (18/09): deferido varrido ha 1h com analise real ha 100h reporta ~100h", async () => {
    const estado = dasaVarridaAnalisadaHa(1, 100, { _token_cap_deferred: true });
    await gravarEstado({ [DASA]: estado });
    const { d } = await planoDasa("noturno");
    // Contra v4.9.258 horas_stale sai ~1, que e a varredura. Era exatamente a cegueira.
    expect(d.horas_stale_base).toBe("ultima_analise");
    expect(d.horas_stale).toBeGreaterThan(99);
    expect(d.horas_stale).toBeLessThan(101);
    expect(d.horas_desde_varredura).toBeLessThan(2);
    // Um relogio de analise so no item: horas_desde_analise sai da mesma funcao.
    expect(d.horas_desde_analise).toBe(d.horas_stale);
    // O rotulo "Ultima analise" mostra a analise, nunca a varredura.
    expect(d.contexto_historico).toContain("Ultima analise: " + estado._ultima_analise_at.slice(0, 16));
    expect(d.contexto_historico).not.toContain(estado._last_scanned_at.slice(0, 16));
  });

  it("PONTA BOA: analise real ha 2h reporta horas_stale abaixo de 3", async () => {
    await gravarEstado({ [DASA]: dasaVarridaAnalisadaHa(2, 2, { _ultimo_tier: "FULL", _ultima_origem: "matinal" }) });
    const { d } = await planoDasa("noturno");
    expect(d.horas_stale_base).toBe("ultima_analise");
    expect(d.horas_stale).toBeGreaterThan(1);
    expect(d.horas_stale).toBeLessThan(3);
  });

  it("ponta a ponta: submissao deferida via receber_analise renova so a varredura", async () => {
    await gravarEstado({ [DASA]: dasaVarridaAnalisadaHa(100, 100) });
    const r = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde", _token_cap_deferred: true,
      resultado: { _tier: "LIGHT", sem_eventos: true, eventos: [], fontes_consultadas: ["a", "b", "c"], _token_cap_deferred: true }
    });
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
    const { d } = await planoDasa("noturno");
    // A escrita do deferido renova _last_scanned_at e preserva _ultima_analise_at.
    expect(d.horas_desde_varredura).toBeLessThan(0.5);
    expect(d.horas_stale).toBeGreaterThan(99);
    expect(d.horas_stale_base).toBe("ultima_analise");
    expect(d.deferido).toBe(true);
  });

  it("SEM REGISTRO: varrido sem carimbo em nenhuma semana retida vira o sentinela nomeado, com contagem e rotulo proprios", async () => {
    const varredura = horasAtrasIso(1);
    await gravarEstado({ [DASA]: { _last_scanned_at: varredura, _status: "OK", eventos: [], sem_eventos: true } });
    const { p, d } = await planoDasa("noturno");
    expect(W.HORAS_SEM_REGISTRO).toBe(9999);
    expect(d.horas_stale_base).toBe("sem_analise_registrada");
    expect(d.horas_stale).toBe(W.HORAS_SEM_REGISTRO);
    expect(d.horas_desde_analise).toBeNull();
    expect(d.horas_desde_varredura).toBeLessThan(2);
    expect(p.horas_stale_sem_registro).toBeGreaterThanOrEqual(1);
    expect(d.contexto_historico).toContain("Sem analise registrada. Ultima varredura: " + varredura.slice(0, 16));
    expect(d.contexto_historico).not.toContain("Ultima analise: ");
  });

  it("FORA DA MESCLA: carimbo so na semana retida alem da mescla de 3 semanas vira base propria com as horas reais", async () => {
    const antigo = horasAtrasIso(22 * 24);
    await gravarEstado({ [DASA]: { _last_scanned_at: antigo, _ultima_analise_at: antigo, _ultimo_tier: "FULL", _ultima_origem: "noturno", _status: "OK", eventos: [], sem_eventos: true } }, chaveEstadoSemanasAtras(3));
    await gravarEstado({ [DASA]: { _last_scanned_at: horasAtrasIso(1), _status: "OK", eventos: [], sem_eventos: true } });
    const { p, d } = await planoDasa("noturno");
    expect(d.horas_stale_base).toBe("ultima_analise_fora_da_mescla");
    expect(d.horas_stale).toBeGreaterThan(22 * 24 - 1);
    expect(d.horas_stale).toBeLessThan(22 * 24 + 1);
    expect(d.horas_desde_analise).toBe(d.horas_stale);
    expect(p.horas_stale_fora_da_mescla).toBe(1);
    expect(d.contexto_historico).toContain("Ultima analise: " + antigo.slice(0, 16));
  });

  it("log agregado: uma linha nomeando sem registro e fora da mescla quando algum existe", async () => {
    const antigo = horasAtrasIso(22 * 24);
    await gravarEstado({ [DASA]: { _last_scanned_at: antigo, _ultima_analise_at: antigo, _ultimo_tier: "FULL", _status: "OK", eventos: [], sem_eventos: true } }, chaveEstadoSemanasAtras(3));
    await gravarEstado({ [DASA]: { _last_scanned_at: horasAtrasIso(1), _status: "OK", eventos: [], sem_eventos: true } });
    expect(typeof W.montarPlanoRotina).toBe("function");
    const spy = vi.spyOn(console, "log").mockImplementation(() => { });
    try {
      const pl = await W.montarPlanoRotina(env, { modo: "noturno" });
      const linhas = spy.mock.calls.map((c) => String(c[0])).filter((l) => l.includes("[montarPlanoRotina][HORAS_STALE]"));
      expect(linhas.length).toBe(1);
      expect(linhas[0]).toContain("fora_da_mescla=1");
      expect(linhas[0]).toContain(DASA);
      expect(linhas[0]).toMatch(/sem_analise_registrada=\d+/);
      expect(pl.horas_stale_fora_da_mescla).toBe(1);
    } finally {
      spy.mockRestore();
    }
  });

  it("log agregado: silencio quando todos os 104 tem carimbo na mescla (nao vira ruido diario)", async () => {
    const results = {};
    for (const emp of W.EMISSORES_LISTA) results[emp] = dasaVarridaAnalisadaHa(2, 2);
    await gravarEstado(results);
    expect(typeof W.montarPlanoRotina).toBe("function");
    const spy = vi.spyOn(console, "log").mockImplementation(() => { });
    try {
      const pl = await W.montarPlanoRotina(env, { modo: "noturno" });
      const linhas = spy.mock.calls.map((c) => String(c[0])).filter((l) => l.includes("[montarPlanoRotina][HORAS_STALE]"));
      expect(linhas.length).toBe(0);
      expect(pl.horas_stale_sem_registro).toBe(0);
      expect(pl.horas_stale_fora_da_mescla).toBe(0);
    } finally {
      spy.mockRestore();
    }
  });

  it("_horasStaleAnalise: tres bases, data invalida e varredura que nunca vira analise", () => {
    const H = W._horasStaleAnalise;
    expect(typeof H).toBe("function");
    expect(H(null, null)).toEqual({ horas: W.HORAS_SEM_REGISTRO, base: "sem_analise_registrada", carimbo: null });
    const recente = horasAtrasIso(5);
    const r1 = H({ _ultima_analise_at: recente }, null);
    expect(r1.base).toBe("ultima_analise");
    expect(r1.carimbo).toBe(recente);
    expect(r1.horas).toBeGreaterThan(4.9);
    expect(r1.horas).toBeLessThan(5.1);
    const velho = horasAtrasIso(600);
    const r2 = H({ _last_scanned_at: horasAtrasIso(1) }, velho);
    expect(r2.base).toBe("ultima_analise_fora_da_mescla");
    expect(r2.carimbo).toBe(velho);
    // O carimbo da mescla vence o de fora dela.
    expect(H({ _ultima_analise_at: recente }, velho).carimbo).toBe(recente);
    // Data ilegivel conta como ausente, fail-closed.
    expect(H({ _ultima_analise_at: "nao-e-data" }, null).base).toBe("sem_analise_registrada");
    // Varredura nunca e promovida a analise.
    expect(H({ _last_scanned_at: horasAtrasIso(1) }, null).base).toBe("sem_analise_registrada");
  });

  it("dados_para_analise: o rotulo mostra a analise real, e a varredura so com o aviso de que nao houve analise", async () => {
    const estado = dasaVarridaAnalisadaHa(1, 100);
    await gravarEstado({ [DASA]: estado });
    let r = await post({ action: "dados_para_analise", empresa: DASA, setor: "Saúde" });
    expect(r.status).toBe(200);
    let j = await r.json();
    expect(j.contexto_historico).toContain("Última análise: " + estado._ultima_analise_at.slice(0, 10));

    await gravarEstado({ [DASA]: { _last_scanned_at: estado._last_scanned_at, _status: "OK", eventos: [], sem_eventos: true } });
    r = await post({ action: "dados_para_analise", empresa: DASA, setor: "Saúde" });
    j = await r.json();
    expect(j.contexto_historico).toContain("Sem análise registrada na janela. Última varredura: " + estado._last_scanned_at.slice(0, 10));
    expect(j.contexto_historico).not.toContain("Última análise: ");
  });
});

describe("TIERING INALTERADO (decisao do operador de 19/09): o tier continua no relogio de varredura", () => {
  // Passa na v4.9.258 e passa depois da mudanca, e e essa a prova de que o EMISSORSTALE2
  // nao mexe em custo. Mudar o relogio do tiering e decisao junto do P0 de orcamento; quando
  // ela vier, este teste muda junto e de proposito.
  // Rumo e nao Dasa: a Dasa tem piso estrutural de EWS 38 (worker.js, tabela do _rjLookup),
  // acima do ROTINA_EWS_LIGHT de 30, entao nunca cai no SKIP por frescor. Medido na primeira
  // rodada deste arquivo: com a Dasa o noturno saiu ews_medio_ou_stale_2d nas duas versoes.
  // Rumo nao tem piso, nao e Financeiro e nao e audit forcado, entao o EWS dela e zero aqui.
  // materialidade_max 1 existe so para a Rumo entrar no top N da matinal: sem sinal nenhum o
  // score_combinado dela e 0 (o bonus de atraso de selecionarEmissoresPrioritarios tambem sai
  // do relogio de varredura, 1h) e o corte de MATINAL_EWS_MINIMO a remove. 1 fica longe dos
  // limiares de tier por materialidade (60 na matinal, 65 no noturno) e nao entra no EWS.
  it("emissor quieto varrido ha 1h e analisado ha 100h: noturno sem_delta_30h, matinal SKIP scan_recente_sem_delta", async () => {
    const RUMO = "Rumo";
    await gravarEstado({ [RUMO]: dasaVarridaAnalisadaHa(1, 100, { _qualidade_sinal: { materialidade_max: 1 } }) });
    const pn = await plano("noturno");
    const noturno = pn.emissores.find((e) => e.empresa === RUMO);
    expect(noturno.ews_score).toBeLessThan(30);
    expect(noturno.motivos).toContain("sem_delta_30h");
    const pm = await plano("matinal", { top_n: 104 });
    const matinal = pm.emissores.find((e) => e.empresa === RUMO);
    expect(matinal.tier).toBe("SKIP");
    expect(matinal.motivos[0]).toBe("scan_recente_sem_delta");
  });
});

// MEDIDO CONTRA v4.9.258 (19/09/2026, antes da correcao), saida crua do vitest com este
// arquivo e relogio-varredura.test.mjs:
//   Tests  12 failed | 1 passed (13)
//   FAIL PONTA RUIM e PONTA BOA: expected undefined to be 'ultima_analise'
//   FAIL ponta a ponta: actual value must be number or bigint, received "undefined"
//   FAIL SEM REGISTRO: expected undefined to be 9999
//   FAIL FORA DA MESCLA: expected undefined to be 'ultima_analise_fora_da_mescla'
//   FAIL log agregado (as duas pontas) e _horasStaleAnalise: expected 'undefined' to be 'function'
//   FAIL dados_para_analise: expected 'Última análise: 2026-09-19' to contain 'Última análise: 2026-09-15'
//        (o rotulo mostrava a varredura de hoje no lugar da analise de 4 dias antes)
//   FAIL relogio-varredura, os 3: horas_desde_varredura nao existia
//   PASS tiering inalterado (vale nas duas versoes, e essa e a prova de custo neutro)
// Depois da correcao: Tests 13 passed (13).
// Primeira rodada do teste de tiering usava a Dasa e falhou nas DUAS versoes com
// ews_medio_ou_stale_2d, porque a Dasa tem piso estrutural de EWS 38. Trocado para a Rumo.