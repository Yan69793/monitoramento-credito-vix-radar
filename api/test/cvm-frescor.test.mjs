import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// CVMFRESCOR1 (auditoria 2026-08-19), contrato revisado por CVMCADENCIA1 e
// HEALTHSPLIT1 (auditoria 2026-08-20).
//
// De 14/08 a 19/08 o Painel de Eventos ficou congelado e TODO semaforo do
// sistema permaneceu verde. O motivo de ninguem ver era interno e continua
// valendo: nenhuma camada media frescor de DADO, todas mediam se o escritor
// rodou.
//   - heartbeat:sync_cvm ficava "ok" porque a funcao retornava sem lancar, e
//     baixar um arquivo que nao mudou e um sucesso perfeito;
//   - frescor-check.yml validava estado_semanal.updated_at, que fica verde com
//     conteudo reciclado, ja que a rotina escreve todo dia;
//   - a tira de fontes do rodape do frontend e HTML estatico com classe "ok".
//
// O que estava ERRADO na versao de 19/08, e que estes testes agora travam no
// sentido certo:
//   1. CVMCADENCIA1 - o diagnostico dizia "a CVM parou de publicar". Nao parou.
//      O ramo CIA_ABERTA/DOC tem cadencia SEMANAL declarada na propria pagina
//      do dataset e publica aos domingos. Medir isso com regua de 2 dias uteis
//      fazia o health ir a vermelho toda quarta ou quinta, previsivelmente. A
//      regra virou ciclo perdido: so alerta apos DOIS ciclos semanais sem
//      publicacao, ou seja passados 14 dias corridos.
//   2. HEALTHSPLIT1 - frescor de fonte de terceiro saiu do `ok` agregado. `ok`
//      significa "servico de pe e integro" para 13 consumidores, entre eles um
//      que ABORTA rotacao de chave e outro que dispara varredura de emergencia.
//      Nenhum deles tem acao util diante de "a CVM publica aos domingos". O
//      sinal agora vive em `fonte_externa_ok`, com canal de alerta proprio.
//
// O fail-closed nao afrouxou: meta ausente, ilegivel ou sem data continua
// contando como fonte NAO fresca. O que mudou e onde esse false aparece.

const META_KEY = "cvm:fonte_meta";

// FUSOTESTE1 (2026-08-21): o Worker conta o dia no relogio de Brasilia
// (obterAgoraBRT subtrai 3h fixas), mas este helper usava UTC puro. Entre 21h e
// meia-noite BRT a data do UTC ja virou, o helper gerava referencia de um dia a
// mais, e o teste de 14 dias via 13. A suite passava de dia e quebrava de noite
// sem ninguem nunca roda-la nesse horario. O helper agora usa o mesmo relogio
// BRT do Worker.
function diasAtrasISO(n) {
  const d = new Date(Date.now() - 3 * 60 * 60 * 1e3);
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

async function health() {
  const res = await SELF.fetch("https://example.com/");
  expect(res.status).toBe(200);
  return res.json();
}

async function seedMeta(meta) {
  await env.RADAR_KV.put(META_KEY, JSON.stringify(meta));
}

describe("CVMFRESCOR1 - idade da fonte CVM no health", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
    // CVMFRESCOR1b: avaliarFrescorCVM cai para cvm:documentos quando nao ha
    // meta. Sem limpar aqui, os testes de fail-closed passariam ou falhariam
    // conforme o lixo deixado por outro teste, que e o tipo de flakiness que
    // faz suite verde nao significar nada.
    await env.RADAR_KV.delete("cvm:documentos");
  });

  it("fail-closed: sem cvm:fonte_meta a fonte NAO conta como fresca", async () => {
    // Este e o caso que mais importa. A tentacao de fazer meta ausente valer
    // como "ok" para nao incomodar no primeiro deploy e exatamente como o
    // sistema ficou cego antes. Ausencia de sinal nao e sinal de saude.
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(b.cvm_fonte_motivo).toBe("sem_meta");
    // HEALTHSPLIT1: fonte externa nao derruba mais o agregado.
    expect(b.ok).toBe(true);
  });

  it("fonte publicada hoje conta como fresca", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified: "irrelevante para o calculo",
      last_modified_iso: diasAtrasISO(0),
      max_data_entrega: diasAtrasISO(0),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.fonte_externa_ok).toBe(true);
    expect(b.cvm_fonte_idade_du).toBe(0);
    expect(b.cvm_fonte_ciclos_perdidos).toBe(0);
    expect(b.cvm_fonte_cadencia).toBe("semanal");
    expect(b.ok).toBe(true);
  });

  // ── CVMCADENCIA1: a regra e ciclo perdido, nao dia util ────────────────────
  it("4 dias corridos (menos de 1 ciclo) NAO derruba a fonte", async () => {
    // Este e o caso real de 20/08/2026: publicacao no domingo 16/08, consulta na
    // quinta 20/08, 4 dias uteis de idade. A regra velha reprovava e o health
    // ficava vermelho toda semana no meio da semana, sem nada ter acontecido.
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(4),
      max_data_entrega: diasAtrasISO(4),
      documentos: 646,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.fonte_externa_ok).toBe(true);
    expect(b.cvm_fonte_ciclos_perdidos).toBe(0);
    expect(b.ok).toBe(true);
  });

  it("13 dias (1 ciclo perdido) ainda NAO derruba, pode ser feriado ou atraso de lote", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(13),
      max_data_entrega: diasAtrasISO(13),
      documentos: 646,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ciclos_perdidos).toBe(1);
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.fonte_externa_ok).toBe(true);
  });

  it("14 dias (2 ciclos perdidos) derruba fonte_externa_ok, e ai a fonte parou de verdade", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(14),
      max_data_entrega: diasAtrasISO(14),
      documentos: 646,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ciclos_perdidos).toBe(2);
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(String(b.cvm_fonte_motivo)).toMatch(/^fonte_sem_publicar_ha_\d+_ciclos_semanais_\d+_dias$/);
    // Servico continua de pe. Este e o coracao do HEALTHSPLIT1.
    expect(b.ok).toBe(true);
  });

  it("fonte parada ha 30 dias derruba fonte_externa_ok mas nao o servico", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(30),
      max_data_entrega: diasAtrasISO(30),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(b.cvm_fonte_ciclos_perdidos).toBeGreaterThanOrEqual(4);
    expect(String(b.cvm_fonte_motivo)).toMatch(/^fonte_sem_publicar_ha_\d+_ciclos_semanais_\d+_dias$/);
    expect(b.ok).toBe(true);
  });

  it("ultimo sync com falha derruba mesmo com data recente na meta", async () => {
    // O sync pode falhar DEPOIS de ler o Last-Modified (arquivo corrompido,
    // metodo de compressao trocado). Data recente nao pode salvar um sync que
    // nao chegou a gravar documento nenhum.
    await seedMeta({
      ok: false,
      motivo: "nao_e_deflate",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(0),
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(String(b.cvm_fonte_motivo)).toContain("ultimo_sync_falhou");
    expect(b.ok).toBe(true);
  });

  it("meta sem nenhuma data utilizavel nao passa por omissao", async () => {
    await seedMeta({ ok: true, sincronizado_em: new Date().toISOString(), documentos: 5, origem: "teste" });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(b.cvm_fonte_motivo).toBe("sem_data_de_referencia");
    expect(b.ok).toBe(true);
  });

  it("CVMFRESCOR1b: sem meta, deriva a idade de cvm:documentos e grava o backfill", async () => {
    // Sem isto, TODO deploy deixaria o health vermelho com motivo "sem_meta"
    // ate o proximo cron, ou seja ate 12h de alarme falso por subida. Alarme
    // que grita pelo motivo errado deixa de ser lido.
    const hoje = diasAtrasISO(0);
    await env.RADAR_KV.put("cvm:documentos", JSON.stringify([
      { e: "TESTE S.A.", d: hoje, de: hoje, c: "Fato Relevante", a: "x", l: "https://exemplo" }
    ]));
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.ok).toBe(true);
    const meta = await env.RADAR_KV.get(META_KEY, "json");
    expect(meta).toBeTruthy();
    expect(meta.origem).toBe("backfill_documentos");
    expect(meta.max_data_entrega).toBe(hoje);
  });

  it("CVMFRESCOR1b: backfill com documentos velhos reprova, nao mascara", async () => {
    await env.RADAR_KV.put("cvm:documentos", JSON.stringify([
      { e: "TESTE S.A.", d: diasAtrasISO(30), de: diasAtrasISO(30), c: "Fato Relevante", a: "x", l: "https://exemplo" }
    ]));
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(String(b.cvm_fonte_motivo)).toMatch(/^fonte_sem_publicar_ha_\d+_ciclos_semanais_\d+_dias$/);
    expect(b.ok).toBe(true);
  });

  it("CVMFRESCOR1b: meta existente tem precedencia sobre o backfill", async () => {
    // O backfill mede so os 103 emissores; o Last-Modified do servidor mede o
    // arquivo inteiro. O sinal fraco nunca pode sobrescrever o forte.
    await env.RADAR_KV.put("cvm:documentos", JSON.stringify([
      { e: "TESTE S.A.", d: diasAtrasISO(90), de: diasAtrasISO(90), c: "Fato Relevante", a: "x", l: "https://exemplo" }
    ]));
    await seedMeta({ ok: true, sincronizado_em: new Date().toISOString(), last_modified_iso: diasAtrasISO(0), origem: "sync_automatico" });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    const meta = await env.RADAR_KV.get(META_KEY, "json");
    expect(meta.origem).toBe("sync_automatico");
  });

  it("cai para max_data_entrega quando o servidor nao manda Last-Modified", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified: null,
      last_modified_iso: null,
      max_data_entrega: diasAtrasISO(0),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.ok).toBe(true);
  });
});

describe("CVMFRESCOR1 - endpoints admin de frescor", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
    // CVMFRESCOR1b: avaliarFrescorCVM cai para cvm:documentos quando nao ha
    // meta. Sem limpar aqui, os testes de fail-closed passariam ou falhariam
    // conforme o lixo deixado por outro teste, que e o tipo de flakiness que
    // faz suite verde nao significar nada.
    await env.RADAR_KV.delete("cvm:documentos");
  });

  function postAdmin(action, extra) {
    return SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, admin_senha: env.ADMIN_PASSWORD, ...extra }),
    });
  }

  it("admin_frescor_cvm exige senha", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "admin_frescor_cvm", admin_senha: "errada" }),
    });
    expect(res.status).toBe(403);
  });

  it("admin_frescor_cvm devolve o diagnostico sem mexer no dado", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(30),
      max_data_entrega: diasAtrasISO(30),
      origem: "teste"
    });
    const res = await postAdmin("admin_frescor_cvm", {});
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.ok).toBe(true);
    expect(b.frescor.ok).toBe(false);
    expect(b.frescor.idade_du).toBeGreaterThan(2);
    // CVMCADENCIA1: o endpoint admin passa a expor ciclo perdido, que e o campo
    // pelo qual a decisao e tomada. idade_du fica so como informacao.
    expect(b.frescor.ciclos_perdidos).toBeGreaterThanOrEqual(2);
    expect(b.frescor.cadencia).toBe("semanal");
  });

  it("admin_sync_cvm manual carimba a meta em vez de deixar invariante quebrada", async () => {
    // Antes deste fix, a carga manual sobrescrevia cvm:documentos e deixava a
    // meta apontando para o sync automatico anterior. Health passaria a medir
    // a idade de um dado que nao existe mais.
    const hoje = diasAtrasISO(0);
    const res = await postAdmin("admin_sync_cvm", {
      documentos: [{ e: "TESTE S.A.", d: hoje, de: hoje, c: "Fato Relevante", a: "assunto", l: "https://exemplo" }]
    });
    expect(res.status).toBe(200);
    const meta = await env.RADAR_KV.get(META_KEY, "json");
    expect(meta).toBeTruthy();
    expect(meta.origem).toBe("admin_manual");
    expect(meta.max_data_entrega).toBe(hoje);
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
  });
});

// ── CVMDURA1 + CVMMETAWIPE1 (auditoria 2026-08-24) ────────────────────────────
//
// Incidente: em 23/08/2026 a CVM removeu ipe_cia_aberta_2026.zip do servidor.
// O sync passou a responder 404, `cvm:documentos` congelou na carga de 15/08, e
// as rotinas perderam o gatilho primario de evento. O painel ficou 4 dias sem
// nenhum fato novo (evento mais recente 20/08 com 103 emissores varridos em
// 23/08) e NADA ficou vermelho:
//   - CVM_FONTE_MAX_CICLOS tolera 14 dias, regra desenhada para CADENCIA
//     semanal, e engolia um 404 duro com a mesma paciencia;
//   - o caminho de erro de gravarFonteCVMMeta sobrescrevia a meta inteira,
//     apagando max_data_entrega, entao o health devolvia idade_dias:null e nem
//     dava para saber ha quanto tempo a fonte estava escura;
//   - VIXRadar-Health-Watch, unico canal que alertava em fonte_externa_ok,
//     estava Disabled desde 21/08.
//
// Contrato travado aqui: fonte que NAO RESPONDE e incidente, nao cadencia. Cai
// na hora em fonte_externa_ok e, repetindo, escala para o `ok` agregado.
describe("CVMDURA1 - falha dura da fonte separada de cadencia", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
    await env.RADAR_KV.delete("cvm:documentos");
  });

  it("404 recente marca falha dura e derruba a fonte, sem derrubar o servico", async () => {
    await seedMeta({
      ok: false,
      motivo: "http_404",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(1),
      max_data_entrega: diasAtrasISO(1),
      ultimo_sync_ok_em: new Date().toISOString(),
      falhas_consecutivas: 1,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.fonte_externa_ok).toBe(false);
    expect(b.cvm_fonte_falha_dura).toBe(true);
    expect(b.cvm_fonte_falhas_consecutivas).toBe(1);
    expect(b.cvm_fonte_degrada_servico).toBe(false);
    // Uma falha pode ser blip de rede. Nao acorda ninguem pelo `ok`.
    expect(b.ok).toBe(true);
  });

  it("404 repetido acima do limite escala para o ok agregado", async () => {
    await seedMeta({
      ok: false,
      motivo: "http_404",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(9),
      max_data_entrega: diasAtrasISO(9),
      ultimo_sync_ok_em: null,
      falhas_consecutivas: 4,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_falha_dura).toBe(true);
    expect(b.cvm_fonte_degrada_servico).toBe(true);
    // Este e o ponto do fix: ingestao de fato relevante parada ha 2 dias de
    // crons deixa de ser "frescor de terceiro" e vira plataforma degradada.
    expect(b.ok).toBe(false);
  });

  it("CVMMETAWIPE1: falha preserva a idade da fonte em vez de devolver null", async () => {
    // O sintoma real em producao: cvm_fonte_idade_dias e ciclos_perdidos vinham
    // null porque o erro tinha apagado max_data_entrega. Alerta que diz "falhou"
    // sem dizer ha quanto tempo perde a metade acionavel da informacao.
    await seedMeta({
      ok: false,
      motivo: "http_404",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(9),
      max_data_entrega: diasAtrasISO(9),
      ultimo_sync_ok_em: "2026-08-17T08:01:16.000Z",
      falhas_consecutivas: 2,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_idade_dias).toBe(9);
    expect(b.cvm_fonte_ciclos_perdidos).toBe(1);
    expect(b.cvm_fonte_idade_du).toBeGreaterThan(0);
    expect(b.cvm_fonte_ultimo_sync_ok_em).toBe("2026-08-17T08:01:16.000Z");
  });

  it("fonte_ausente_no_catalogo tambem conta como falha dura", async () => {
    // Estado em que nem a URL canonica nem o catalogo CKAN conhecem o arquivo
    // do ano corrente. E o pior caso: nao ha para onde apontar.
    await seedMeta({
      ok: false,
      motivo: "fonte_ausente_no_catalogo",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(2),
      max_data_entrega: diasAtrasISO(2),
      falhas_consecutivas: 5,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_falha_dura).toBe(true);
    expect(b.cvm_fonte_degrada_servico).toBe(true);
    expect(b.ok).toBe(false);
  });

  it("caso bom: sync ok recente nao marca falha dura nem degrada nada", async () => {
    // Prova da outra ponta. Sem ela, um bug que marcasse falha_dura sempre
    // passaria despercebido e o `ok` ficaria preso em false.
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(0),
      max_data_entrega: diasAtrasISO(0),
      ultimo_sync_ok_em: new Date().toISOString(),
      falhas_consecutivas: 0,
      documentos: 646,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.fonte_externa_ok).toBe(true);
    expect(b.cvm_fonte_falha_dura).toBe(false);
    expect(b.cvm_fonte_degrada_servico).toBe(false);
    expect(b.ok).toBe(true);
  });

  it("motivo NAO duro nao escala, mesmo com muitas falhas", async () => {
    // CVM_FONTE_MAX_CICLOS continua sendo o dono do caso "arquivo presente e
    // velho". A escalada nova so vale para fonte que nao responde.
    await seedMeta({
      ok: false,
      motivo: "sem_data_de_referencia",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(1),
      max_data_entrega: diasAtrasISO(1),
      falhas_consecutivas: 9,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_falha_dura).toBe(false);
    expect(b.cvm_fonte_degrada_servico).toBe(false);
    expect(b.ok).toBe(true);
  });
  it("CVMMETAWIPE1: meta ja destruida por versao antiga deriva a idade de cvm:documentos", async () => {
    // Caso real de 24/08: o wipe aconteceu ANTES do fix subir, entao nao havia
    // max_data_entrega para o merge preservar e o health seguia devolvendo
    // idade null. O merge so protege daqui para frente; este fallback conserta
    // o retrovisor, derivando a idade dos documentos que ainda estao no KV.
    await env.RADAR_KV.put("cvm:documentos", JSON.stringify([
      { e: "TESTE S.A.", d: diasAtrasISO(9), de: diasAtrasISO(9), c: "Fato Relevante", a: "x", l: "https://exemplo" }
    ]));
    await seedMeta({
      ok: false,
      motivo: "http_404",
      sincronizado_em: new Date().toISOString(),
      origem: "sync_automatico"
    });
    const b = await health();
    expect(b.cvm_fonte_falha_dura).toBe(true);
    expect(b.cvm_fonte_idade_dias).toBe(9);
    expect(b.cvm_fonte_ciclos_perdidos).toBe(1);
    expect(b.fonte_externa_ok).toBe(false);
  });
});

// ── NOMEMORTO1 + ACENTOMATCH1 (auditoria 2026-08-24) ──────────────────────────
//
// Dois bugs da mesma familia, achados medindo o cvm:documentos de producao.
//
// NOMEMORTO1: existiam TRES tabelas de alias que precisavam concordar. O
// documento entrava por SYNC_ALIAS_NOMES_CVM, era atribuido por
// SYNC_ALIAS_TO_EMPRESA, e sumia no leitor, que tinha copia propria e
// incompleta. Medido em 24/08: "AXIA ENERGIA S.A." e "AXIA ENERGIA NORDESTE
// S.A." estavam gravados no KV e buscarDocumentosCVM("Eletrobras") devolvia 0.
// A Eletrobras virou AXIA em 10/11/2025, entao eram nove meses de emissor cego,
// exibido como sem_eventos, que o painel apresenta como ausencia de fato.
// Depois do fix, 28 documentos.
//
// ACENTOMATCH1: o alias da Sabesp e escrito sem acento e a CVM publica
// "CIA SANEAMENTO BÁSICO ESTADO SÃO PAULO". String.includes e literal, entao o
// documento ficava orfao. Depois do fix, 11 documentos.
//
// O contrato travado aqui NAO e uma contagem, que depende do que a CVM publicou.
// E a invariante: o leitor enxerga todo alias que a ingestao conhece.
describe("NOMEMORTO1 - leitor enxerga todo alias que a ingestao conhece", () => {
  const KEY = "cvm:documentos";
  const hoje = diasAtrasISO(0);

  function doc(nomeCvm) {
    return { e: nomeCvm, d: hoje, de: hoje, c: "Fato Relevante", a: "assunto de teste", l: "https://exemplo/" + encodeURIComponent(nomeCvm) };
  }

  async function consultar(empresa) {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "admin_documentos_cvm", admin_senha: env.ADMIN_PASSWORD, empresa }),
    });
    expect(res.status).toBe(200);
    return res.json();
  }

  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
    await env.RADAR_KV.put(KEY, JSON.stringify([
      doc("AXIA ENERGIA S.A."),
      doc("AXIA ENERGIA NORDESTE S.A."),
      doc("MOTIVA INFRAESTRUTURA DE MOBILIDADE S.A."),
      doc("SERENA ENERGIA S.A."),
      doc("CIA SANEAMENTO B\u00c1SICO ESTADO S\u00c3O PAULO"),
      doc("AUREN ENERGIA S.A"),
      doc("EMPRESA QUE NINGUEM MONITORA S.A.")
    ]));
  });

  it("exige senha de admin", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "admin_documentos_cvm", admin_senha: "errada", empresa: "Eletrobras" }),
    });
    expect(res.status).toBe(403);
  });

  it("emissor renomeado acha o documento da razao social nova", async () => {
    // Este e o caso Eletrobras/AXIA, que ficou nove meses invisivel.
    const b = await consultar("Eletrobras");
    expect(b.total).toBe(2);
    expect(b.aliases_derivados).toContain("AXIA ENERGIA");
    expect(b.documentos.map((d) => d.empresa_cvm)).toContain("AXIA ENERGIA S.A.");
  });

  it("CCR acha documento protocolado como Motiva", async () => {
    const b = await consultar("CCR");
    expect(b.total).toBe(1);
    expect(b.documentos[0].empresa_cvm).toBe("MOTIVA INFRAESTRUTURA DE MOBILIDADE S.A.");
  });

  it("Omega Energia acha documento protocolado como Serena", async () => {
    const b = await consultar("Omega Energia");
    expect(b.total).toBe(1);
    expect(b.documentos[0].empresa_cvm).toBe("SERENA ENERGIA S.A.");
  });

  it("ACENTOMATCH1: alias sem acento casa com razao social acentuada", async () => {
    const b = await consultar("Sabesp");
    expect(b.total).toBe(1);
    expect(b.documentos[0].empresa_cvm).toContain("SANEAMENTO");
  });

  it("caso bom: emissor sem renomeacao continua funcionando", async () => {
    // Prova da outra ponta. Sem ela, um fix que quebrasse o caminho normal
    // passaria despercebido enquanto os casos de renomeacao ficassem verdes.
    const b = await consultar("Auren Energia");
    expect(b.total).toBe(1);
    expect(b.documentos[0].empresa_cvm).toBe("AUREN ENERGIA S.A");
  });

  it("nao devolve documento de empresa que nao e do emissor consultado", async () => {
    // Guarda contra o erro oposto: alias frouxo demais que passa a puxar
    // documento alheio e contamina a analise de credito com fato de terceiro.
    const b = await consultar("Eletrobras");
    expect(b.documentos.map((d) => d.empresa_cvm)).not.toContain("EMPRESA QUE NINGUEM MONITORA S.A.");
    expect(b.documentos.map((d) => d.empresa_cvm)).not.toContain("AUREN ENERGIA S.A");
  });
});
