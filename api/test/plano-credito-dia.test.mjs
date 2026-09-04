import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

// CREDITODIA1 + TIERNULO1 + PONTUALFATO1 (2026-09-02, auditoria de rotinas de 01/09).
//
// Medido em 01/09: 12 emissores analisados DUAS vezes no mesmo dia (matinal 18h13 e
// fila aprofundada da noturna 10h49), enquanto 69 ficavam deferidos por orcamento.
// Tres defeitos empilhados, cada um provado aqui nas duas pontas (regra 5):
//
// 1. TIERNULO1: receber_analise lia body._tier, mas as rotinas mandam _tier DENTRO de
//    resultado. Chegava nulo em persistirResultadoCompartilhadoInterno, o gate de
//    cobertura caia no else de 7 fontes e TODA analise com menos de 7 fontes virava
//    _status INCONCLUSIVO, inclusive LIGHT com 3 fontes, que o proprio gate declara
//    completa (FIN2).
// 2. CREDITODIA1: o plano nao sabia quem analisou nem quando. O SKIP por frescor
//    (horasStale < 30) vinha DEPOIS do ramo FULL e exigia _status !== INCONCLUSIVO,
//    que o defeito 1 tornava impossivel. Agora a persistencia grava _ultimo_tier,
//    _ultima_origem e _ultima_analise_at so quando houve analise real (tier
//    LIGHT/FULL/AUDIT e nao deferido), e o plano credita qualquer analise valida das
//    ultimas 14h, de qualquer rotina, salvo documento novo da CVM ou divida por teto.
// 3. PONTUALFATO1: a varredura pontual (sentinela) deixa de usar "deferido" como
//    gatilho. Decisao do operador (02/09): sentinela somente para fato novo. A cauda
//    deferida agora e trabalho da noturna, que gasta o cap inteiro em LIGHT.
//
// Prova reversa: ver o bloco "MEDIDO CONTRA v4.9.233" no fim do arquivo.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const KEY_DOCS = "cvm:documentos";
const DASA_RAZAO = "DIAGNOSTICOS DA AMERICA SA";
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
function hojeBRT() { return agoraBRT().toISOString().slice(0, 10); }
function diasAtras(n) { const d = agoraBRT(); d.setUTCDate(d.getUTCDate() - n); return d.toISOString().slice(0, 10); }
function horasAtrasIso(h) { return new Date(Date.now() - h * 60 * 60 * 1e3).toISOString(); }

function doc(razaoSocial, protocolo, dataEntrega, categoria = "Fato Relevante") {
  return {
    e: razaoSocial, d: dataEntrega, de: dataEntrega, c: categoria, a: "assunto de teste",
    l: `https://www.rad.cvm.gov.br/ENET/frmExibirArquivoIPEExterno.aspx?NumeroProtocoloEntrega=${protocolo}&numProtocolo=${protocolo}`
  };
}

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

async function planoDasa(modo, extra = {}) {
  const p = await plano(modo, extra);
  const d = p.emissores.find((e) => e.empresa === DASA);
  expect(d, "Dasa no plano " + modo).toBeDefined();
  return d;
}

async function gravarEstado(results, chave) {
  chave = chave || chaveEstadoSemanaCorrente();
  await env.RADAR_KV.put(chave, JSON.stringify({ week: chave.replace("radar:estado:", ""), updated_at: new Date().toISOString(), results }));
}

// Estado de quem a matinal analisou FULL ha 2h com 3 fontes: INCONCLUSIVO pelo gate
// de 7, mas analise real, com os tres campos operacionais gravados.
function dasaAnalisadaHaPouco(extra) {
  return Object.assign({
    _last_scanned_at: horasAtrasIso(2),
    _ultima_analise_at: horasAtrasIso(2),
    _ultimo_tier: "FULL",
    _ultima_origem: "matinal",
    _status: "INCONCLUSIVO",
    eventos: [],
    sem_eventos: true
  }, extra || {});
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
  for (const k of [chaveEstadoSemanaCorrente(), chaveEstadoSemanaAnterior(), KEY_DOCS, "radar:cvm_vistos:dasa"]) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

beforeEach(limpar);
afterEach(limpar);

describe("CREDITODIA1: analise valida do dia e creditada por qualquer rotina", () => {
  it("PONTA BOA (prova reversa): FULL da matinal ha 2h vira SKIP analisado_hoje_por_matinal no plano noturno", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco() });
    const d = await planoDasa("noturno");
    // Contra v4.9.233 isto sai tier LIGHT / cobertura_padrao: o SKIP por frescor exige
    // _status !== INCONCLUSIVO e o plano nao conhece _ultima_analise_at.
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_matinal");
    expect(d.motivos[1]).toMatch(/^credito_FULL_\d+h$/);
    expect(d.rodadas).toEqual([]);
    expect(d.ultimo_tier).toBe("FULL");
    expect(d.ultima_origem).toBe("matinal");
    expect(d.horas_desde_analise).toBeLessThan(14);
  });

  it("PONTA RUIM: documento novo da CVM vence o credito (fato novo sempre analisa)", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco() });
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9100001", hojeBRT())]));
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("FULL");
    expect(d.motivos).toContain("cvm_delta_1");
    expect(d.motivos.some((m) => m.startsWith("analisado_hoje"))).toBe(false);
  });

  it("PONTA RUIM: LIGHT INCONCLUSIVO ha 8h NAO credita; ha 4h credita", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco({ _ultimo_tier: "LIGHT", _ultima_analise_at: horasAtrasIso(8), _last_scanned_at: horasAtrasIso(8) }) });
    let d = await planoDasa("noturno");
    expect(d.tier).not.toBe("SKIP");
    expect(d.motivos.some((m) => m.startsWith("analisado_hoje"))).toBe(false);

    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco({ _ultimo_tier: "LIGHT", _ultima_analise_at: horasAtrasIso(4), _last_scanned_at: horasAtrasIso(4) }) });
    d = await planoDasa("noturno");
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_matinal");
  });

  it("PONTA RUIM: analise ha 16h esta fora da janela de 14h e NAO credita", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco({ _ultima_analise_at: horasAtrasIso(16), _last_scanned_at: horasAtrasIso(16) }) });
    const d = await planoDasa("noturno");
    expect(d.tier).not.toBe("SKIP");
    expect(d.motivos.some((m) => m.startsWith("analisado_hoje"))).toBe(false);
  });

  it("PONTA RUIM: divida por teto (_token_cap_deferred) vence o credito", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco({ _token_cap_deferred: true }) });
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("FULL");
    expect(d.motivos).toContain("deferred_prioritario");
  });

  it("estado legado sem os campos novos se comporta como antes (rollout seguro)", async () => {
    await gravarEstado({ [DASA]: { _last_scanned_at: horasAtrasIso(2), _status: "INCONCLUSIVO", eventos: [], sem_eventos: true } });
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("LIGHT");
    expect(d.motivos.some((m) => m.startsWith("analisado_hoje"))).toBe(false);
    expect(d.ultimo_tier).toBeNull();
  });

  it("o credito vale tambem no plano matinal (noturna de ontem 18h ainda cobre a matinal? nao: 16h; mas 2h sim)", async () => {
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco({ _ultima_origem: "noturno" }) });
    const d = await planoDasa("matinal", { top_n: 103 });
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_noturno");
  });

  it("ponta a ponta: receber_analise grava os 3 campos, o plano credita, SKIP e deferido preservam", async () => {
    await submeterDasa({ _matinal: true, resultado: { _tier: "FULL", sem_eventos: true, eventos: [], fontes_consultadas: ["a", "b", "c"] } });
    let est = await lerDasa();
    expect(est._ultimo_tier).toBe("FULL");
    expect(est._ultima_origem).toBe("matinal");
    expect(typeof est._ultima_analise_at).toBe("string");
    // FULL com 3 fontes continua INCONCLUSIVO pelo gate de 7, e mesmo assim credita
    // (tier anterior FULL), que e exatamente o caso dos 12 duplicados de 01/09.
    expect(est._status).toBe("INCONCLUSIVO");
    const carimbo = est._ultima_analise_at;

    let d = await planoDasa("noturno");
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_matinal");

    // Submissao SKIP (ledger de quem pulou) nao apaga nem renova o carimbo.
    await submeterDasa({ resultado: { _tier: "SKIP", sem_eventos: true, eventos: [] } });
    est = await lerDasa();
    expect(est._ultima_analise_at).toBe(carimbo);
    expect(est._ultimo_tier).toBe("FULL");

    // Submissao deferida (divida por teto) preserva o carimbo e liga a divida, que
    // vence o credito no plano seguinte.
    await submeterDasa({ _token_cap_deferred: true, resultado: { _tier: "LIGHT", sem_eventos: true, eventos: [], _token_cap_deferred: true } });
    est = await lerDasa();
    expect(est._ultima_analise_at).toBe(carimbo);
    expect(est._token_cap_deferred).toBe(true);
    d = await planoDasa("noturno");
    expect(d.tier).toBe("FULL");
    expect(d.motivos).toContain("deferred_prioritario");
  });

  it("mescla multi-semana: campos novos da semana corrente sobrevivem ao objeto da semana anterior com evento", async () => {
    await gravarEstado({
      [DASA]: {
        _last_scanned_at: horasAtrasIso(72),
        eventos: [{ titulo: "Evento antigo de teste", classificacao: "ECO", data_evento: diasAtras(3), fonte: "https://exemplo.test/x" }],
        sem_eventos: false
      }
    }, chaveEstadoSemanaAnterior());
    await gravarEstado({ [DASA]: dasaAnalisadaHaPouco() });
    const d = await planoDasa("noturno");
    expect(d.tier).toBe("SKIP");
    expect(d.motivos[0]).toBe("analisado_hoje_por_matinal");
  });
});

describe("TIERNULO1: _tier dentro de resultado chega ao gate de cobertura", () => {
  // Um it por caso: o estado da semana vive no Durable Object, e limpar so o KV no meio de
  // um it deixaria o registro anterior influenciando o ramo PRESERVADO da persistencia.
  it("LIGHT com 3 fontes deixa de ser INCONCLUSIVO (prova reversa: hoje grava INCONCLUSIVO)", async () => {
    await submeterDasa({ resultado: { _tier: "LIGHT", sem_eventos: true, eventos: [], fontes_consultadas: ["a", "b", "c"] } });
    const est = await lerDasa();
    expect(est._status).toBe("OK");
    const d = await planoDasa("noturno");
    expect(d.inconclusivo).toBe(false);
  });

  it("FULL com 3 fontes continua INCONCLUSIVO (o gate de 7 nao mudou)", async () => {
    await submeterDasa({ resultado: { _tier: "FULL", sem_eventos: true, eventos: [], fontes_consultadas: ["a", "b", "c"] } });
    const est = await lerDasa();
    expect(est._status).toBe("INCONCLUSIVO");
  });

  it("sem _tier nenhum continua INCONCLUSIVO (default conservador)", async () => {
    await submeterDasa({ resultado: { sem_eventos: true, eventos: [], fontes_consultadas: ["a", "b", "c"] } });
    const est = await lerDasa();
    expect(est._status).toBe("INCONCLUSIVO");
  });
});

describe("PONTUALFATO1: a varredura pontual so entra por documento novo", () => {
  it("deferido sem documento novo NAO entra no plano pontual; com documento novo entra", async () => {
    await gravarEstado({ [DASA]: { _last_scanned_at: horasAtrasIso(48), _token_cap_deferred: true, eventos: [], sem_eventos: true } });
    let p = await plano("pontual");
    expect(p.emissores.find((e) => e.empresa === DASA)).toBeUndefined();

    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9100002", hojeBRT())]));
    p = await plano("pontual");
    const d = p.emissores.find((e) => e.empresa === DASA);
    expect(d).toBeDefined();
    expect(d.cvm_novos).toBe(1);
  });
});

describe("excluir_top_n e top_n com extras por setor", () => {
  // O numero acompanha EMISSORES_LISTA em api/src/worker.js (104 desde a entrada da
  // Usina Pampa Sul, 04/09/2026). Quem adiciona emissor atualiza aqui, no gate do
  // motor (run_vixradar_varredura.ps1) e no Passo 3 da SKILL.md do noturno.
  it("excluir_top_n marca exatamente N do topo como SKIP coberto_matinal_top_N e mantem o total da carteira", async () => {
    const p = await plano("noturno", { excluir_top_n: 5 });
    expect(p.total).toBe(104);
    const cobertos = p.emissores.filter((e) => e.motivos[0] === "coberto_matinal_top_5");
    expect(cobertos.length).toBe(5);
    for (const c of cobertos) { expect(c.tier).toBe("SKIP"); expect(c.rodadas).toEqual([]); }
  });

  it("sem excluir_top_n ninguem recebe o motivo coberto_matinal (desligado por padrao)", async () => {
    const p = await plano("noturno");
    expect(p.emissores.some((e) => e.motivos.some((m) => m.startsWith("coberto_matinal")))).toBe(false);
  });

  it("top_n=15 devolve 15 mais um representante por setor descoberto, declarados em extras_setor", async () => {
    const p = await plano("matinal", { top_n: 15 });
    expect(p.top_n_solicitado).toBe(15);
    expect(p.top_n_efetivo).toBe(p.total);
    expect(p.total).toBeGreaterThanOrEqual(15);
    expect(Array.isArray(p.extras_setor)).toBe(true);
    expect(p.extras_setor.length).toBe(p.total - 15);
    const setoresTop = new Set(p.emissores.slice(0, 15).map((e) => e.setor));
    for (const x of p.extras_setor) {
      expect(setoresTop.has(x.setor)).toBe(false);
    }
  });

  it("top_n_estrito devolve exatamente top_n e ainda cobre todo setor presente no top", async () => {
    const p = await plano("matinal", { top_n: 15, top_n_estrito: true });
    expect(p.total).toBe(15);
    expect(p.top_n_efetivo).toBe(15);
  });
});

// MEDIDO CONTRA v4.9.233 (02/09/2026 02:16 BRT, antes da correcao), saida crua do vitest:
//   Tests  11 failed | 4 passed (15)   (o TIERNULO1 era um it so; virou tres depois)
//   FAIL PONTA BOA (prova reversa): expected 'LIGHT' to be 'SKIP'
//   FAIL LIGHT INCONCLUSIVO 8h/4h: expected 'LIGHT' to be 'SKIP'
//   FAIL estado legado: expected undefined to be null (ultimo_tier nao existia no payload)
//   FAIL credito no plano matinal: expected 'LIGHT' to be 'SKIP'
//   FAIL ponta a ponta: expected undefined to be 'FULL' (_ultimo_tier nao era gravado)
//   FAIL mescla multi-semana: expected 'LIGHT' to be 'SKIP'
//   FAIL TIERNULO1 LIGHT 3 fontes: expected 'INCONCLUSIVO' to be 'OK'
//   FAIL PONTUALFATO1: expected { empresa: 'Dasa', ... } to be undefined (deferido entrava na pontual)
//   FAIL excluir_top_n: expected +0 to be 5
//   FAIL top_n extras_setor: expected undefined to be 15
//   FAIL top_n_estrito: expected 19 to be 15
//   PASS fato novo vence, 16h nao credita, deferido vence, sem excluir_top_n (valem nas duas versoes)
