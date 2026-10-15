import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

// JANELADELTA1 (2026-10-15). `janela_delta_inicio` e o inicio da busca de fato novo que o plano
// entrega ao prompt da rotina e a triagem deterministica do motor. O comentario do proprio plano
// diz "ultima analise menos 2 dias de folga", e o codigo usava `_last_scanned_at`, o relogio de
// VARREDURA, que SKIP e deferimento (inclusive a cauda de rotacao semanal) renovam toda noite sem
// analisar nada. Efeito: emissor deferido N noites seguidas, quando finalmente analisado, buscava
// so desde (ultimo deferimento - 2 dias), e o que saiu entre a ultima analise real e esse ponto
// ficava fora da janela, do prompt e da triagem. Mesma familia do EMISSORSTALE2 (rotulo prometia
// analise e entregava varredura).
//
// Fora de escopo de proposito: o TIERING (SKIP sem_delta_30h) continua no relogio de varredura,
// decisao do operador de 19/09 (EMISSORSTALE2, item 1). O teste "tiering inalterado" trava isso.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const DASA = "Dasa";

beforeEach(async () => { await bootstrapIndiceQuarentena(env); });

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}
function agoraBRT() { return new Date(Date.now() - 3 * 60 * 60 * 1e3); }
function chaveEstadoSemanasAtras(n) { return `radar:estado:${semanaISO(new Date(agoraBRT().getTime() - n * 7 * 864e5))}`; }
function horasAtrasIso(h) { return new Date(Date.now() - h * 60 * 60 * 1e3).toISOString(); }
function menos2Dias(iso) { return new Date(new Date(iso).getTime() - 2 * 864e5).toISOString().split("T")[0]; }

async function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.79" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body))
  });
}
async function planoDasa(modo) {
  const res = await post({ action: "listar_plano_rotina", modo });
  expect(res.status).toBe(200);
  const p = await res.json();
  const d = p.emissores.find((e) => e.empresa === DASA);
  expect(d, "Dasa no plano " + modo).toBeDefined();
  return d;
}
async function gravarEstado(results, chave) {
  chave = chave || chaveEstadoSemanasAtras(0);
  await env.RADAR_KV.put(chave, JSON.stringify({ week: chave.replace("radar:estado:", ""), updated_at: new Date().toISOString(), results }));
}
async function limpar() {
  const chaves = [0, 1, 2, 3, 4].map(chaveEstadoSemanasAtras).concat(["cvm:documentos", "radar:cvm_vistos:dasa", "radar:cvm_vistos:rumo"]);
  for (const k of chaves) { try { await env.RADAR_KV.delete(k); } catch (_) { } }
}
beforeEach(limpar);
afterEach(limpar);

// Quieto: sem evento, sem CVM, EWS zero. Varrido ha hV horas e analisado de verdade ha hA horas.
function dasa(hV, hA, extra) {
  const r = Object.assign({ _last_scanned_at: horasAtrasIso(hV), _status: "OK", eventos: [], sem_eventos: true }, extra || {});
  if (hA != null) Object.assign(r, { _ultima_analise_at: horasAtrasIso(hA), _ultimo_tier: "LIGHT", _ultima_origem: "noturno" });
  return r;
}

describe("JANELADELTA1: janela_delta_inicio parte da ultima ANALISE real, nunca da varredura", () => {
  it("PONTA RUIM: deferido por rotacao ha 1h com analise real ha 120h busca desde a analise - 2d", async () => {
    const e = dasa(1, 120);
    await gravarEstado({ [DASA]: e });
    const d = await planoDasa("noturno");
    // Contra o codigo anterior sai menos2Dias(varredura) = ontem, e os 4 dias entre a analise e o
    // primeiro deferimento somem da busca.
    expect(d.janela_delta_inicio).toBe(menos2Dias(e._ultima_analise_at));
    expect(d.janela_delta_inicio < menos2Dias(e._last_scanned_at)).toBe(true);
  });

  it("ponta a ponta: deferimento de rotacao via receber_analise NAO avanca a janela", async () => {
    const e = dasa(120, 120);
    await gravarEstado({ [DASA]: e });
    const r = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde",
      resultado: { _tier: "FULL", sem_eventos: true, eventos: [], fontes_consultadas: [{ rodada: "0", query: "token_cap", resultado: "deferred" }], _token_cap_deferred: false, _defer_motivo: "rotacao_semanal" }
    });
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
    const d = await planoDasa("noturno");
    expect(d.horas_desde_varredura).toBeLessThan(0.5);
    expect(d.janela_delta_inicio).toBe(menos2Dias(e._ultima_analise_at));
  });

  it("PONTA BOA: analisado e varrido ha 5h mantem a janela de sempre (analise - 2d)", async () => {
    const e = dasa(5, 5);
    await gravarEstado({ [DASA]: e });
    const d = await planoDasa("noturno");
    expect(d.janela_delta_inicio).toBe(menos2Dias(e._ultima_analise_at));
  });

  it("SEM REGISTRO de analise: falha fechado na janela externa inteira, nunca na varredura", async () => {
    await gravarEstado({ [DASA]: dasa(1, null) });
    const d = await planoDasa("noturno");
    expect(d.janela_delta_inicio).toBe(d.janela_inicio);
  });

  it("analise mais antiga que a janela externa: limitada ao janela_inicio", async () => {
    const antigo = horasAtrasIso(40 * 24);
    await gravarEstado({ [DASA]: dasa(1, null, { _ultima_analise_at: antigo, _ultimo_tier: "FULL", _ultima_origem: "noturno" }) });
    const d = await planoDasa("noturno");
    expect(d.janela_delta_inicio).toBe(d.janela_inicio);
  });

  // Rumo e nao Dasa: a Dasa tem piso estrutural de EWS 38 e nunca cai em SKIP (mesma nota do
  // emissor-stale-analise.test.mjs). So `motivos` e conferido porque a amostra de auditoria pode
  // promover o SKIP a AUDIT sem tirar o motivo.
  it("tiering inalterado: o SKIP sem_delta_30h continua no relogio de varredura (decisao 19/09)", async () => {
    const RUMO = "Rumo";
    const e = dasa(1, 120, { _qualidade_sinal: { materialidade_max: 1 } });
    await gravarEstado({ [RUMO]: e });
    const res = await post({ action: "listar_plano_rotina", modo: "noturno" });
    const r = (await res.json()).emissores.find((x) => x.empresa === RUMO);
    expect(r.motivos).toContain("sem_delta_30h");
    expect(r.janela_delta_inicio).toBe(menos2Dias(e._ultima_analise_at));
  });
});
