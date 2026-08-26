import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

// SENTINELA1 (2026-08-25).
//
// Tres mudancas provadas aqui, cada uma nas duas pontas (regra 5 do CLAUDE.md):
//
// 1. Identidade de documento. _cvmNovosDesde comparava YYYY-MM-DD, entao documento
//    entregue no MESMO dia civil de uma varredura nunca contava como novo. Isso ja
//    mordia o top 15, analisado duas vezes por dia. Prova reversa: o teste
//    "mesmo dia civil" falha contra o codigo anterior, onde dt > since dava false
//    para dt === since, o tier saia SKIP e motivos traziam sem_delta_30h.
//
// 2. Marcacao so depois da entrega. cvm_vistos e escrito no receber_analise
//    bem-sucedido, nunca na leitura do plano. Analise que falha nao pode consumir
//    o gatilho, senao o evento some calado (familia EMAILSILENT1 / CVMURL404).
//
// 3. modo pontual. Recorte do plano noturno por gatilho duro, com teto e excedente
//    declarado. Sem gatilho a resposta e vazia, que e o que permite a rotina
//    Sentinela sair em 0 token na maioria das execucoes.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const KEY_DOCS = "cvm:documentos";

// Par razao social -> emissor ja exercitado em cvm-atribuicao.test.mjs, entao a
// atribuicao nao e a variavel sob teste aqui.
const DASA_RAZAO = "DIAGNOSTICOS DA AMERICA SA";
const DASA = "Dasa";
const OI_RAZAO = "OI S.A. - EM RECUPERAÇÃO JUDICIAL";
const CSN_RAZAO = "CIA SIDERURGICA NACIONAL";
const COPASA_RAZAO = "COMPANHIA DE SANEAMENTO DE MINAS GERAIS";
const MOVIDA_RAZAO = "MOVIDA PARTICIPACOES S.A.";
const SENDAS_RAZAO = "SENDAS DISTRIBUIDORA S.A.";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}

function agoraBRT() {
  return new Date(Date.now() - 3 * 60 * 60 * 1e3);
}

function chaveEstadoSemanaCorrente() {
  return `radar:estado:${semanaISO(agoraBRT())}`;
}

function hojeBRT() {
  return agoraBRT().toISOString().slice(0, 10);
}

function diasAtras(n) {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

// numProtocolo e o identificador estavel que _cvmIdDoc extrai do link.
function doc(razaoSocial, protocolo, dataEntrega, categoria = "Fato Relevante") {
  return {
    e: razaoSocial,
    d: dataEntrega,
    de: dataEntrega,
    c: categoria,
    a: "assunto de teste",
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

// Estado com a ultima varredura de Dasa carimbada HOJE. E este carimbo que fazia o
// documento do proprio dia desaparecer do gatilho na regra antiga.
async function estadoDasaVarridaHoje() {
  const semana = chaveEstadoSemanaCorrente();
  await env.RADAR_KV.put(semana, JSON.stringify({
    week: semana,
    updated_at: new Date().toISOString(),
    results: {
      [DASA]: {
        _last_scanned_at: new Date().toISOString(),
        eventos: [],
        sem_eventos: true
      }
    }
  }));
}

async function limpar() {
  const chaves = [chaveEstadoSemanaCorrente(), KEY_DOCS, "radar:cvm_vistos:dasa"];
  for (const k of chaves) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

beforeEach(limpar);
afterEach(limpar);

describe("SENTINELA1 parte 1: documento novo por identidade, nao por data", () => {
  it("PONTA BOA: documento entregue no mesmo dia civil da ultima varredura CONTA como novo", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000001", hojeBRT())]));

    const p = await plano("noturno");
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    // Contra o codigo anterior isto era 0, o tier saia SKIP e o motivo era
    // sem_delta_30h. E a prova reversa desta correcao.
    expect(dasa.cvm_novos).toBe(1);
    expect(dasa.tier).toBe("FULL");
    expect(dasa.motivos).toContain("cvm_delta_1");
    expect(dasa.cvm_novos_ids).toEqual(["p:9000001"]);
  });

  it("PONTA RUIM: documento anterior a ultima varredura NAO conta, nao ha enxurrada", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000002", diasAtras(5))]));

    const p = await plano("noturno");
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    expect(dasa.cvm_novos).toBe(0);
    expect(dasa.motivos).not.toContain("cvm_delta_1");
  });

  it("PONTA RUIM: protocolo ja registrado em cvm_vistos NAO conta", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000003", hojeBRT())]));
    await env.RADAR_KV.put("radar:cvm_vistos:dasa", JSON.stringify({ ids: ["p:9000003"], ts: new Date().toISOString() }));

    const p = await plano("noturno");
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    expect(dasa.cvm_novos).toBe(0);
  });
});

describe("SENTINELA1 parte 2: cvm_vistos so e escrito apos entrega bem-sucedida", () => {
  it("ler o plano NAO marca nada", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000010", hojeBRT())]));

    await plano("pontual");
    const gravado = await env.RADAR_KV.get("radar:cvm_vistos:dasa");
    expect(gravado).toBeNull();

    // Gatilho intacto: uma segunda leitura devolve o mesmo emissor.
    const p2 = await plano("pontual");
    expect(p2.emissores.map((e) => e.empresa)).toContain(DASA);
  });

  it("receber_analise bem-sucedido marca, e o gatilho para de disparar", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000011", hojeBRT())]));

    const antes = await plano("pontual");
    expect(antes.emissores.map((e) => e.empresa)).toContain(DASA);

    const res = await post({
      action: "receber_analise",
      empresa: DASA,
      setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true },
      cvm_ids_analisados: ["p:9000011"]
    });
    expect(res.status).toBe(200);
    const corpo = await res.json();
    expect(corpo.ok).toBe(true);
    expect(corpo.cvm_marcados).toBe(1);

    const depois = await plano("pontual");
    expect(depois.emissores.map((e) => e.empresa)).not.toContain(DASA);
  });

  it("entrega que FALHA nao marca nada e o gatilho sobrevive", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000012", hojeBRT())]));

    // Empresa fora de EMISSORES_LISTA: a acao rejeita antes de persistir.
    const res = await post({
      action: "receber_analise",
      empresa: "Empresa Que Nao Existe Ltda",
      setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true },
      cvm_ids_analisados: ["p:9000012"]
    });
    expect(res.status).toBe(400);

    const gravado = await env.RADAR_KV.get("radar:cvm_vistos:dasa");
    expect(gravado).toBeNull();
    const depois = await plano("pontual");
    expect(depois.emissores.map((e) => e.empresa)).toContain(DASA);
  });

  it("marcar duas vezes o mesmo protocolo e idempotente", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000013", hojeBRT())]));

    const um = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true }, cvm_ids_analisados: ["p:9000013"]
    });
    expect((await um.json()).cvm_marcados).toBe(1);

    const dois = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true }, cvm_ids_analisados: ["p:9000013"]
    });
    expect((await dois.json()).cvm_marcados).toBe(0);

    const guardado = JSON.parse(await env.RADAR_KV.get("radar:cvm_vistos:dasa"));
    expect(guardado.ids).toEqual(["p:9000013"]);
  });
});

describe("SENTINELA1 parte 3: modo pontual", () => {
  it("PONTA BOA: sem gatilho nenhum, o plano volta vazio", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));

    const p = await plano("pontual");
    expect(p.ok).toBe(true);
    expect(p.modo).toBe("pontual");
    expect(p.total).toBe(0);
    expect(p.emissores).toEqual([]);
    expect(p.pontual_candidatos).toBe(0);
  });

  it("PONTA BOA: com gatilho, volta SOMENTE o emissor gatilhado", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000020", hojeBRT())]));

    const p = await plano("pontual");
    expect(p.total).toBe(1);
    expect(p.emissores[0].empresa).toBe(DASA);
    expect(p.emissores[0].tier).not.toBe("SKIP");
    // O noturno do mesmo estado devolve os 103. O recorte e o que a pontual faz.
    const n = await plano("noturno");
    expect(n.total).toBe(103);
  });

  it("teto corta e o excedente e declarado, nao sumido", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
      doc(DASA_RAZAO, "9000030", hojeBRT()),
      doc(OI_RAZAO, "9000031", hojeBRT()),
      doc(CSN_RAZAO, "9000032", hojeBRT()),
      doc(COPASA_RAZAO, "9000033", hojeBRT()),
      doc(MOVIDA_RAZAO, "9000034", hojeBRT()),
      doc(SENDAS_RAZAO, "9000035", hojeBRT())
    ]));

    const p = await plano("pontual", { teto: 2 });
    expect(p.pontual_teto).toBe(2);
    expect(p.total).toBe(2);
    expect(p.pontual_candidatos).toBeGreaterThanOrEqual(3);
    expect(p.pontual_excedente).toBe(p.pontual_candidatos - 2);
  });

  it("modo noturno e matinal nao ganham os campos da pontual", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    const n = await plano("noturno");
    expect(n.pontual_candidatos).toBeNull();
    expect(n.pontual_excedente).toBeNull();
  });
});

describe("SENTINELA1 parte 4: gatilho da matinal nao depende mais do horario", () => {
  it("PONTA BOA: documento novo promove a FULL na matinal com motivo cvm_overnight", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000040", hojeBRT())]));
    const semana = chaveEstadoSemanaCorrente();
    // EWS baixo e varredura recente: sem o gatilho de documento, cairia em SKIP.
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana,
      updated_at: new Date().toISOString(),
      results: { [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true } }
    }));

    const p = await plano("matinal", { top_n: 103 });
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    expect(dasa.tier).toBe("FULL");
    expect(dasa.motivos.some((m) => m.startsWith("cvm_overnight_"))).toBe(true);
  });

  it("PONTA RUIM: sem documento novo, o motivo cvm_overnight nao aparece", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    const semana = chaveEstadoSemanaCorrente();
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana,
      updated_at: new Date().toISOString(),
      results: { [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true } }
    }));

    const p = await plano("matinal", { top_n: 103 });
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    if (dasa) {
      expect(dasa.motivos.some((m) => m.startsWith("cvm_overnight_"))).toBe(false);
    }
  });
});

// DEFERGRUDA1 (2026-08-25, achado ao rodar a Sentinela em producao).
//
// `_token_cap_deferred` ligava e nunca desligava. Os cinco ramos de
// persistirResultadoCompartilhadoInterno faziam `if (payload... === true) X = true`
// sem else, e os ramos de sem_eventos reaproveitam o objeto anterior, entao a
// bandeira sobrevivia a qualquer analise real.
//
// Consequencia medida em producao antes da correcao: o modo pontual devolveu os
// MESMOS 8 emissores em duas execucoes seguidas (VLI, Embraer, Nexa Resources,
// Even Construtora entre eles), sendo que os 4 primeiros ja tinham sido analisados
// e submetidos com ok:true na primeira. A varredura pontual entraria em laco,
// reanalisando os mesmos emissores duas vezes por hora o dia inteiro. E explica o
// backlog de 34: emissor deferido uma vez virava FULL permanente na noturna,
// gastando token todo dia e realimentando o proprio deferimento.
//
// Prova reversa: contra o codigo anterior o primeiro teste falha, porque
// deferido continua true depois da analise real.
describe("DEFERGRUDA1: analise real limpa o flag de deferido", () => {
  it("PONTA BOA: emissor deferido que recebe analise real deixa de sair como deferido", async () => {
    const semana = chaveEstadoSemanaCorrente();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana,
      updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: new Date().toISOString(),
          eventos: [], sem_eventos: true, _token_cap_deferred: true
        }
      }
    }));

    const antes = await plano("pontual");
    expect(antes.emissores.map((e) => e.empresa)).toContain(DASA);
    expect(antes.emissores.find((e) => e.empresa === DASA).deferido).toBe(true);

    const res = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true }
    });
    expect(res.status).toBe(200);

    const depois = await plano("pontual");
    expect(depois.emissores.map((e) => e.empresa)).not.toContain(DASA);
  });

  it("PONTA RUIM: submit de cap-deferred CONTINUA marcando o emissor", async () => {
    const semana = chaveEstadoSemanaCorrente();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana, updated_at: new Date().toISOString(),
      results: { [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true } }
    }));

    const res = await post({
      action: "receber_analise", empresa: DASA, setor: "Saúde",
      resultado: { eventos: [], sem_eventos: true, _token_cap_deferred: true }
    });
    expect(res.status).toBe(200);

    const depois = await plano("pontual");
    const dasa = depois.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    expect(dasa.deferido).toBe(true);
    expect(dasa.motivos).toContain("deferred_prioritario");
  });
});

// DEFERGRUDA2 (2026-08-25). A correcao do DEFERGRUDA1 estava certa e nao bastava.
//
// montarPlanoRotina le com carregarEstadoMultiSemana(env, 3) e a escrita de
// receber_analise vai so para a semana corrente. A mescla percorre da semana mais
// VELHA para a mais NOVA, e tem um ramo que devolve o objeto da semana velha quando
// a nova nao tem evento e a velha tem, corrigindo apenas _last_scanned_at. Toda
// bandeira de controle gravada na semana nova sumia ali.
//
// Prova crua colhida do KV de producao antes da correcao:
//   W35 (corrente) VLI: eventos=0 sem_eventos=true _token_cap_deferred=undefined
//   W34            VLI: eventos=1 sem_eventos=false _token_cap_deferred=true
//   W35 (corrente) Copel: eventos=1 sem_eventos=false _token_cap_deferred=undefined
// VLI saia deferido com horas_stale=0,1. Copel limpava, porque a semana corrente dela
// tem evento e cai no ramo de dedup, que espalha o registro novo.
//
// Prova reversa: contra o codigo anterior o primeiro teste falha, porque o plano
// reapresenta o emissor mesmo com a semana corrente limpa.
function semanaAnterior() {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() - 7);
  return `radar:estado:${semanaISO(d)}`;
}

describe("DEFERGRUDA2: bandeira de semana anterior nao ressuscita o deferido", () => {
  afterEach(async () => {
    try { await env.RADAR_KV.delete(semanaAnterior()); } catch (_) { }
  });

  it("PONTA BOA: semana corrente sem evento e sem flag vence a semana anterior com evento e flag", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    // Semana anterior: TEM evento e TEM a bandeira. E o registro que a mescla preserva.
    await env.RADAR_KV.put(semanaAnterior(), JSON.stringify({
      week: "anterior", updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: diasAtras(7) + "T12:00:00.000Z",
          eventos: [{ classificacao: "ECO", titulo: "evento antigo", data_evento: diasAtras(7) }],
          sem_eventos: false,
          _token_cap_deferred: true
        }
      }
    }));
    // Semana corrente: analise real, sem evento e SEM a bandeira.
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true }
      }
    }));

    const p = await plano("pontual");
    // Contra o codigo anterior, DASA voltava aqui com deferido=true e horas_stale fresco.
    expect(p.emissores.map((e) => e.empresa)).not.toContain(DASA);
  });

  it("PONTA RUIM: se a semana CORRENTE tem a bandeira, ela continua valendo", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(semanaAnterior(), JSON.stringify({
      week: "anterior", updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: diasAtras(7) + "T12:00:00.000Z",
          eventos: [{ classificacao: "ECO", titulo: "evento antigo", data_evento: diasAtras(7) }],
          sem_eventos: false
        }
      }
    }));
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true, _token_cap_deferred: true }
      }
    }));

    const p = await plano("pontual");
    const dasa = p.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    expect(dasa.deferido).toBe(true);
  });

  it("evento da semana velha NAO e perdido pela correcao", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(semanaAnterior(), JSON.stringify({
      week: "anterior", updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: diasAtras(7) + "T12:00:00.000Z",
          eventos: [{ classificacao: "RELEVANTE", titulo: "evento que nao pode sumir", data_evento: diasAtras(3) }],
          sem_eventos: false,
          _token_cap_deferred: true
        }
      }
    }));
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true }
      }
    }));

    // O plano noturno traz os 103; DASA tem que continuar sendo promovido pelo evento
    // material recente da semana anterior, prova de que a correcao mexeu so na bandeira.
    const n = await plano("noturno");
    const dasa = n.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    expect(dasa.tier).toBe("FULL");
    expect(dasa.motivos).toContain("imprensa_recente_7d");
  });
});

// DEFERGRUDA3 (2026-08-25). Segundo laco, achado ao provar a convergencia do primeiro.
//
// A pontual analisa em lote Haiku com ~2 buscas. O tier FULL exige _coberturaMin=7 em
// persistirResultadoCompartilhadoInterno, entao TODA analise dela grava
// _status:"INCONCLUSIVO". Com inconclusivo no gatilho, a rotina reapresentava o proprio
// trabalho. Medido em producao: 13 dos 20 emissores ja analisados com submit_ok
// voltaram a fila pontual, todos por esse gatilho.
//
// Gatilho da pontual e FATO NOVO ou DIVIDA. "Rodou e nao concluiu" e qualidade de
// cobertura e ja tem dono, o ramo inconclusivo_stale_breakout do plano noturno.
//
// Prova reversa: contra o codigo anterior o primeiro teste falha, porque o emissor
// inconclusivo entra na pontual.
describe("DEFERGRUDA3: inconclusivo nao e gatilho da pontual", () => {
  it("PONTA BOA: emissor INCONCLUSIVO sem documento novo e sem deferido NAO entra na pontual", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: new Date().toISOString(),
          eventos: [], sem_eventos: true, _status: "INCONCLUSIVO"
        }
      }
    }));

    const p = await plano("pontual");
    expect(p.emissores.map((e) => e.empresa)).not.toContain(DASA);
  });

  it("PONTA BOA: o noturno CONTINUA cuidando do inconclusivo, nada ficou orfao", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    // Stale > 48h aciona o inconclusivo_stale_breakout do plano noturno.
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: {
          _last_scanned_at: diasAtras(3) + "T12:00:00.000Z",
          eventos: [], sem_eventos: true, _status: "INCONCLUSIVO"
        }
      }
    }));

    const n = await plano("noturno");
    const dasa = n.emissores.find((e) => e.empresa === DASA);
    expect(dasa).toBeDefined();
    expect(dasa.tier).toBe("FULL");
    expect(dasa.motivos).toContain("inconclusivo_stale_breakout");
  });

  it("PONTA RUIM: documento novo ou deferido continuam entrando", async () => {
    await estadoDasaVarridaHoje();
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "9000050", hojeBRT())]));
    const p1 = await plano("pontual");
    expect(p1.emissores.map((e) => e.empresa)).toContain(DASA);

    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([]));
    await env.RADAR_KV.put(chaveEstadoSemanaCorrente(), JSON.stringify({
      week: "corrente", updated_at: new Date().toISOString(),
      results: {
        [DASA]: { _last_scanned_at: new Date().toISOString(), eventos: [], sem_eventos: true, _token_cap_deferred: true }
      }
    }));
    const p2 = await plano("pontual");
    expect(p2.emissores.map((e) => e.empresa)).toContain(DASA);
  });
});
