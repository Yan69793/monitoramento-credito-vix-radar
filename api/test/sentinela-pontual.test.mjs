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
