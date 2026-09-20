import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

// PROFUNDIDADE-NOTURNA1 / D6 (2026-09-19): ROTACAO NAO E ANALISE REAL.
//
// Defeito provado pela revisao Opus. A cauda de rotacao semanal (Get-VixCaudaRotacao,
// run_vixradar_varredura.ps1) sai como DEFERIDO com `_token_cap_deferred=false` DE PROPOSITO,
// porque nao e corte de orcamento, e CHEGA ao Worker carregando o tier analitico intacto
// (`_tier=FULL/LIGHT/AUDIT`, herdado do item do plano). `_carimbarAnaliseReal` so barrava por
// `_token_cap_deferred === true` e depois pelo tier, entao a cauda passava pelos dois gates e
// recebia `_ultima_analise_at` / `_ultimo_tier` / `_ultima_origem` SEM TER SIDO ANALISADA. O
// plano seguinte entao creditava `analisado_hoje_por_noturno` (_creditoAnaliseDia,
// worker.js:12063) para um emissor que a rotacao decidiu NAO aprofundar, que e o oposto do
// objetivo da rotacao.
//
// A correcao e uma linha, e o discriminador e o MOTIVO, nunca a flag (nao generalizar: cap/auth
// continua com `_token_cap_deferred=true` e o caminho DEFERREDREC1 segue intacto). As quatro
// provas abaixo cobrem as duas pontas da guarda e os dois caminhos que ela NAO pode tocar.
//
// Prova reversa: sem a linha nova em worker.js:9909, PONTA A falha em tres asserts
// (_ultima_analise_at vira agora, _ultimo_tier vira FULL, horas_desde_analise cai a ~0).

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const DASA = "Dasa";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}
function agoraBRT() { return new Date(Date.now() - 3 * 60 * 60 * 1e3); }
function chaveEstadoSemanaCorrente() { return `radar:estado:${semanaISO(agoraBRT())}`; }
function chaveEstadoSemanaAnterior() {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() - 7);
  return `radar:estado:${semanaISO(d)}`;
}
function horasAtrasIso(h) { return new Date(Date.now() - h * 60 * 60 * 1e3).toISOString(); }

async function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.77" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body))
  });
}

async function plano(modo, extra = {}) {
  const res = await post(Object.assign({ action: "listar_plano_rotina", modo }, extra));
  expect(res.status).toBe(200);
  return res.json();
}

async function planoDasa(modo) {
  const p = await plano(modo);
  const d = p.emissores.find((e) => e.empresa === DASA);
  expect(d, "Dasa no plano " + modo).toBeDefined();
  return d;
}

async function gravarEstado(results) {
  await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
    week: chaveEstadoSemanaCorrente().replace("radar:estado:", ""),
    updated_at: new Date().toISOString(),
    results
  }));
}

async function lerDasa() {
  const est = await env.RADAR_KV.get(chaveEstadoSemanaCorrente(), "json");
  expect(est && est.results && est.results[DASA], "estado da Dasa no KV").toBeTruthy();
  return est.results[DASA];
}

async function submeterDasa(body) {
  const res = await post(Object.assign({ action: "receber_analise", empresa: DASA, setor: "Saúde" }, body));
  expect(res.status).toBe(200);
  const j = await res.json();
  expect(j.ok).toBe(true);
  return j;
}

async function limpar() {
  for (const k of [chaveEstadoSemanaCorrente(), chaveEstadoSemanaAnterior(), "cvm:documentos", "radar:cvm_vistos:dasa"]) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

// Analise real anterior, FORA da janela de credito de 14h e com tier DIFERENTE do que a rotacao
// vai mandar (LIGHT/matinal contra FULL/noturno). Assim qualquer carimbo novo aparece como
// mudanca visivel: tier, origem E horas mudam de uma vez, nao so o relogio.
const CARIMBO_ANTIGO = horasAtrasIso(30);
function dasaAnalisadaAntes() {
  return {
    _last_scanned_at: CARIMBO_ANTIGO,
    _ultima_analise_at: CARIMBO_ANTIGO,
    _ultimo_tier: "LIGHT",
    _ultima_origem: "matinal",
    _status: "INCONCLUSIVO",
    eventos: [],
    sem_eventos: true
  };
}

// Corpo identico ao que Submit-CapDeferred monta (run_vixradar_varredura.ps1:318-349):
// `_defer_motivo` e `_token_cap_deferred` viajam DENTRO de resultado, e `origem` e o valor de
// -Rotina ('noturno').
function corpoDeferido(tier, motivo, flagCap) {
  return {
    _matinal: false,
    origem: "noturno",
    _tier: tier,
    provedor: "claude-cap-deferred",
    resultado: {
      empresa: DASA,
      setor: "Saúde",
      sem_eventos: true,
      cobertura_nota: "Tier " + tier + ". Causa=" + motivo + ". EWS=10. Priorizar amanha.",
      fontes_consultadas: [{ rodada: "0", query: "token_cap", resultado: "deferred" }],
      eventos: [],
      _tier: tier,
      _rotina_v2: true,
      _token_cap_deferred: flagCap,
      _defer_motivo: motivo
    }
  };
}

beforeEach(async () => {
  await bootstrapIndiceQuarentena(env);
  await limpar();
});
afterEach(limpar);

describe("D6: rotacao_semanal nao pode virar carimbo de analise real", () => {
  it("PONTA A: deferimento por rotacao_semanal NAO carimba, nao vira divida e nao credita no plano seguinte", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaAntes() });
    const antes = await lerDasa();

    await submeterDasa(corpoDeferido("FULL", "rotacao_semanal", false));

    const dep = await lerDasa();
    // Os tres campos de analise real ficam byte a byte como estavam. Sem a guarda nova o
    // submit de rotacao escrevia os tres, e o emissor passava a mentir que foi analisado.
    expect(dep._ultima_analise_at).toBe(antes._ultima_analise_at);
    expect(dep._ultimo_tier).toBe("LIGHT");
    expect(dep._ultima_origem).toBe("matinal");
    // Contra-prova de que a rotacao FOI registrada: o gate e sobre ANALISE, nao sobre
    // atividade. _last_scanned_at e reescrito pelo handler em todo submit bem-sucedido.
    expect(dep._last_scanned_at).not.toBe(antes._last_scanned_at);
    // Rotacao nao e divida por cap: nao liga a bandeira que o DEFERREDREC1 le.
    expect(dep._token_cap_deferred).toBeUndefined();

    const d = await planoDasa("noturno");
    expect(d.ultimo_tier).toBe("LIGHT");
    expect(d.ultima_origem).toBe("matinal");
    expect(d.horas_desde_analise).toBeGreaterThan(14);
    expect(d.motivos).not.toContain("deferred_prioritario");
    expect(d.motivos.some((m) => m.startsWith("analisado_hoje"))).toBe(false);
  });

  it("PONTA B: analise FULL real (sem _defer_motivo) carimba, e o plano seguinte credita analisado_hoje_por_noturno", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaAntes() });

    await submeterDasa({
      _matinal: false,
      origem: "noturno",
      _tier: "FULL",
      provedor: "claude-sonnet-routine",
      resultado: { empresa: DASA, setor: "Saúde", sem_eventos: true, eventos: [], _tier: "FULL", _rotina_v2: true }
    });

    const est = await lerDasa();
    expect(est._ultimo_tier).toBe("FULL");
    expect(est._ultima_origem).toBe("noturno");
    expect(est._ultima_analise_at).not.toBe(CARIMBO_ANTIGO);
    expect(Date.now() - new Date(est._ultima_analise_at).getTime()).toBeLessThan(60000);

    // A outra ponta: o mecanismo de credito continua de pe. A guarda nova nao pode ter
    // desligado o CREDITODIA1, so o caminho da rotacao.
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_noturno");
  });

  it("PONTA C: cap/auth (_token_cap_deferred=true) continua sem carimbo real e continua deferred_prioritario", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaAntes() });

    await submeterDasa(corpoDeferido("LIGHT", "limite_sessao_assinatura", true));

    const est = await lerDasa();
    // Continua sem carimbo: quem barra aqui e a PRIMEIRA linha da guarda
    // (_token_cap_deferred === true), nao a nova. Se a nova tivesse barrado por engano, a
    // bandeira abaixo tambem teria sumido.
    expect(est._ultima_analise_at).toBe(CARIMBO_ANTIGO);
    expect(est._ultimo_tier).toBe("LIGHT");
    expect(est._ultima_origem).toBe("matinal");
    expect(est._token_cap_deferred).toBe(true);

    // DEFERREDREC1 intacto: a divida devolve o emissor como FULL prioritario no plano
    // seguinte. Se a guarda nova tivesse mexido na flag, isto aqui viraria LIGHT.
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("FULL");
    expect(d.motivos).toContain("deferred_prioritario");
  });

  it("SEQUENCIA: a guarda nao e grudenta. Rotacao hoje nao impede o carimbo da analise real de amanha", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaAntes() });

    await submeterDasa(corpoDeferido("FULL", "rotacao_semanal", false));
    expect((await lerDasa())._ultima_analise_at).toBe(CARIMBO_ANTIGO);

    await submeterDasa({
      _matinal: false,
      origem: "noturno",
      _tier: "FULL",
      provedor: "claude-sonnet-routine",
      resultado: { empresa: DASA, setor: "Saúde", sem_eventos: true, eventos: [], _tier: "FULL", _rotina_v2: true }
    });

    const est = await lerDasa();
    expect(est._ultimo_tier).toBe("FULL");
    expect(est._ultima_origem).toBe("noturno");
    expect(est._ultima_analise_at).not.toBe(CARIMBO_ANTIGO);
  });
});
