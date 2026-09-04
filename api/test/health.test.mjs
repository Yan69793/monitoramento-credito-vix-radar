import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}
function agoraBRT() { return new Date(Date.now() - 3 * 60 * 60 * 1e3); }
function chaveEstadoParaInstante(isoRealUtc) {
  const semanaAtual = semanaISO(new Date(new Date(isoRealUtc).getTime() - 3 * 60 * 60 * 1e3));
  return `radar:estado:${semanaAtual}`;
}

// Automatiza o portao de verificacao que o CLAUDE.md do projeto pede para
// colar na mao apos deploy: GET / com ok:true, kv:true, telemetria:true.
describe("GET / (health check)", () => {
  // HEALTHSPLIT1 (2026-08-20): cvm_fonte_ok SAIU do _okHealth e virou
  // fonte_externa_ok, campo proprio. A semeadura abaixo continua porque este
  // teste tambem afirma fonte_externa_ok:true no caminho feliz, mas o ok
  // agregado ja nao depende dela. Comportamento da fonte com meta ausente,
  // ciclo perdido e sync falho fica em cvm-frescor.test.mjs, que e quem guarda
  // o contrato de cadencia (CVMCADENCIA1, regra de 2 ciclos semanais).
  beforeEach(async () => {
    const hoje = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
    await env.RADAR_KV.put("cvm:fonte_meta", JSON.stringify({
      ok: true,
      sincronizado_em: (/* @__PURE__ */ new Date()).toISOString(),
      last_modified_iso: hoje,
      max_data_entrega: hoje,
      documentos: 120,
      origem: "teste_health"
    }));
  });

  it("responde ok:true com todos os bindings presentes", async () => {
    const res = await SELF.fetch("https://example.com/");
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.bindings.kv).toBe(true);
    expect(body.bindings.rate_limiter).toBe(true);
    expect(body.bindings.telemetria).toBe(true);
    // SENTRY1 (v4.9.184): sentry_ok entra no mesmo _okHealth que os demais
    // secrets obrigatorios (SECRETMISS1). Se regredir para false aqui, o
    // formato do SENTRY_DSN de teste em wrangler.test.jsonc quebrou.
    expect(body.admin_email_ok).toBe(true);
    expect(body.sentry_ok).toBe(true);
    expect(body.verificador_ok).toBe(true);
    // HEALTHSPLIT1: frescor de fonte externa tem campo proprio e NAO compoe o
    // `ok`. Se alguem religar cvm_fonte_ok no _okHealth, o teste de 4 dias em
    // cvm-frescor.test.mjs quebra junto e o CI reprova antes do deploy.
    expect(body.fonte_externa_ok).toBe(true);
    expect(body.cvm_fonte_ok).toBe(true);
    expect(body.cvm_fonte_cadencia).toBe("semanal");
    // PAINELFRESCOR1: sem nenhum radar:estado: semeado neste teste, os campos
    // ficam null (indeterminado), nunca false - false significa "conferido e
    // stale", null significa "sem dado para conferir". ok continua true: isto
    // e canal proprio, fora de _okHealth (HEALTHSPLIT1).
    expect(body.painel_atualizado_em).toBeNull();
    expect(body.painel_idade_min).toBeNull();
    expect(body.painel_fresco).toBeNull();
  });
});

// PAINELFRESCOR1 (INCIDENTE-FRESHNESS2, 03/09/2026): o painel travou em
// 11:09 BRT por 12h41 em 02/09 com ok:true o tempo todo, porque nenhum campo
// do health media a idade do ESTADO (o que a tela mostra). Estes testes
// travam o relogio (mesma tecnica de _relogio-fixo.mjs) e semeiam
// radar:estado:{semana} com um updated_at controlado, provando o SLA nas
// duas regras (matinal diaria, noturna seg-sex) com as duas pontas de cada.
describe("GET / painel_fresco (SLA de agenda real)", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  async function medirComRelogioEEstado(isoAgoraReal, isoUpdatedAt) {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(isoAgoraReal));
    // Isolamento explicito: o KV do pool de teste PERSISTE entre os it() do
    // mesmo arquivo, e varios instantes deste bloco caem na MESMA semana ISO
    // (03/09 quinta, 05/09 sabado e 06/09 domingo sao todos da semana de
    // 31/08 a 06/09). Sem apagar antes, o valor semeado por um teste vazava
    // para o seguinte - foi o que fez o caso "sem nenhum estado semeado" ler
    // 2026-09-05T13:20:00Z na primeira execucao desta suite. Apaga as DUAS
    // chaves que _lerUpdatedAtEstado consulta (semana corrente e anterior).
    const chaveAtual = chaveEstadoParaInstante(isoAgoraReal);
    const chaveAnterior = chaveEstadoParaInstante(new Date(new Date(isoAgoraReal).getTime() - 7 * 864e5).toISOString());
    await env.RADAR_KV.delete(chaveAtual);
    await env.RADAR_KV.delete(chaveAnterior);
    if (isoUpdatedAt) {
      await env.RADAR_KV.put(chaveAtual, JSON.stringify({ week: chaveAtual.replace("radar:estado:", ""), updated_at: isoUpdatedAt, results: {} }));
    }
    const res = await SELF.fetch("https://example.com/");
    return res.json();
  }

  // 2026-09-03 e quinta (dia util). 04/09 sexta, 05/09 sabado, 06/09 domingo, 07/09 segunda.
  it("dia util 01:40 BRT, updated_at de ontem 19:00 -> fresco true (regra noturna)", async () => {
    const body = await medirComRelogioEEstado("2026-09-03T04:40:00Z", "2026-09-02T22:00:00.000Z");
    expect(body.painel_regra).toMatch(/noturna/);
    expect(body.painel_exigido_desde).toBe("2026-09-02T21:00:00.000Z");
    expect(body.painel_fresco).toBe(true);
    expect(body.painel_idade_min).toBeGreaterThan(0);
    expect(body.ok).toBe(true);
  });

  it("mesmo instante, updated_at de ontem 11:09 -> fresco false (reproduz o incidente de 02/09)", async () => {
    const body = await medirComRelogioEEstado("2026-09-03T04:40:00Z", "2026-09-02T14:09:28.138Z");
    expect(body.painel_fresco).toBe(false);
    // ok segue true: painel_fresco e canal proprio (HEALTHSPLIT1), nao derruba o portao.
    expect(body.ok).toBe(true);
  });

  it("sabado 12:00 BRT, updated_at do mesmo sabado 10:20 -> fresco true (regra matinal)", async () => {
    const body = await medirComRelogioEEstado("2026-09-05T15:00:00Z", "2026-09-05T13:20:00.000Z");
    expect(body.painel_regra).toMatch(/matinal/);
    expect(body.painel_fresco).toBe(true);
  });

  it("domingo 09:00 BRT, updated_at de SABADO 10:20 -> fresco true (regra noturna nao vale fim de semana)", async () => {
    const body = await medirComRelogioEEstado("2026-09-06T12:00:00Z", "2026-09-05T13:20:00.000Z");
    expect(body.painel_fresco).toBe(true);
  });

  it("segunda 10:50 BRT, updated_at de DOMINGO 10:20 -> fresco false (matinal de hoje ja venceu)", async () => {
    // 2026-09-14 (nao 09-07): 07/09 e feriado B3 (Independencia), caso ja
    // coberto pelos dois testes FERIADOB3-PAINEL1 abaixo. Esta segunda-feira
    // precisa ser dia util comum para nao colidir com o cenario de feriado.
    const body = await medirComRelogioEEstado("2026-09-14T13:50:00Z", "2026-09-13T13:20:00.000Z");
    expect(body.painel_fresco).toBe(false);
  });

  // FERIADOB3-PAINEL1: a matinal pula feriado B3 por instrucao da skill, a
  // noturna nao pula. Sem esta distincao o gate do canonical-test reprovaria a
  // CI em 07/09/2026 (segunda, Independencia), com a matinal legitimamente sem
  // escrever. Duas pontas: no feriado o checkpoint da matinal nao vale; no dia
  // util seguinte ele volta a valer.
  it("feriado B3 (segunda 07/09) 15:00 BRT, updated_at de domingo 10:20 -> fresco true (matinal nao roda em feriado)", async () => {
    const body = await medirComRelogioEEstado("2026-09-07T18:00:00Z", "2026-09-06T13:20:00.000Z");
    expect(body.painel_fresco).toBe(true);
    // O checkpoint vencedor no feriado e a matinal de DOMINGO (piso 06/09
    // 10:00 BRT = 13:00Z), nunca a de segunda: cobrar 07/09 10:00 seria exigir
    // escrita de uma rotina que a propria skill manda pular no feriado.
    expect(body.painel_exigido_desde).toBe("2026-09-06T13:00:00.000Z");
  });

  it("dia util seguinte ao feriado (terca 08/09) 15:00 BRT, updated_at de domingo 10:20 -> fresco false", async () => {
    const body = await medirComRelogioEEstado("2026-09-08T18:00:00Z", "2026-09-06T13:20:00.000Z");
    expect(body.painel_fresco).toBe(false);
  });

  it("sem nenhum estado semeado -> campos null, nunca false", async () => {
    const body = await medirComRelogioEEstado("2026-09-03T04:40:00Z", null);
    expect(body.painel_atualizado_em).toBeNull();
    expect(body.painel_idade_min).toBeNull();
    expect(body.painel_fresco).toBeNull();
    expect(body.ok).toBe(true);
  });
});

// FEEDRETRO1 (2026-09-04): duas guardas novas, complementares a painel_fresco.
// feed_fresco mede o EVENTO (mesma formula de checks.evento_mais_novo do
// admin_health_check), nao a rotina. feed_ultimo_evento_novo_em e um carimbo
// que so avanca quando a data mais nova de fato do feed avanca de verdade,
// nunca por chave nova de um fato ja conhecido (dedup por data|empresa|
// host+path deixava duplicata antiga, com URL diferente, ser tratada como
// "evento novo"; medido em 03/09: os 17 itens da fila de verificacao daquela
// noite eram todos datados de agosto, e uma regra por chave-nova teria
// carimbado "fato novo" sem o feed sair do lugar).
describe("GET / feed_fresco (evento mais novo do feed, nao a rotina)", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  async function medirComEventos(isoAgoraReal, eventosDasa) {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(isoAgoraReal));
    const chaveAtual = chaveEstadoParaInstante(isoAgoraReal);
    const chaveAnterior = chaveEstadoParaInstante(new Date(new Date(isoAgoraReal).getTime() - 7 * 864e5).toISOString());
    await env.RADAR_KV.delete(chaveAtual);
    await env.RADAR_KV.delete(chaveAnterior);
    await env.RADAR_KV.put(chaveAtual, JSON.stringify({
      week: chaveAtual.replace("radar:estado:", ""),
      updated_at: isoAgoraReal,
      results: { Dasa: { sem_eventos: false, eventos: eventosDasa } }
    }));
    const res = await SELF.fetch("https://example.com/");
    return res.json();
  }

  it("evento de 10 dias atras -> feed_fresco false", async () => {
    const body = await medirComEventos("2026-09-03T04:40:00Z", [
      { classificacao: "RELEVANTE", titulo: "t", data_evento: "2026-08-24", fonte_primaria: "https://x.com/a", tags: [] }
    ]);
    expect(body.feed_evento_mais_novo).toBe("2026-08-24");
    expect(body.feed_idade_du).toBeGreaterThan(2);
    expect(body.feed_fresco).toBe(false);
  });

  it("evento de hoje -> feed_fresco true", async () => {
    const body = await medirComEventos("2026-09-03T04:40:00Z", [
      { classificacao: "RELEVANTE", titulo: "t", data_evento: "2026-09-03", fonte_primaria: "https://x.com/a", tags: [] }
    ]);
    expect(body.feed_evento_mais_novo).toBe("2026-09-03");
    expect(body.feed_idade_du).toBe(0);
    expect(body.feed_fresco).toBe(true);
  });
});

// Casos A/B/C do operador (04/09, correcao 2): a semantica e avanco da
// FRONTEIRA GLOBAL, nunca novidade de chave. Testa o caminho de escrita real
// (POST receber_analise), nao um mock - le o estado bruto do KV depois do
// submit, mesmo padrao de lerDasa() em plano-credito-dia.test.mjs. As URLs de
// evento usam data no path (/2026/08/10/.../) de proposito: extrairDataDaURL
// aceita sem precisar buscar a pagina (regra de ouro da skill repor-varredura,
// worker.js:12862-12869), entao o teste nao depende de rede.
describe("receber_analise: fronteira global do feed (carimbo so avanca por data)", () => {
  const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
  const EMPRESA = "Dasa";
  const FRONTEIRA_ATUAL = "2026-08-20";
  const CARIMBO_FIXO = "2026-08-20T09:00:00.000Z";
  const AGORA_FAKE = "2026-09-03T14:00:00Z";

  afterEach(() => {
    vi.useRealTimers();
  });

  function chaveAtual() { return chaveEstadoParaInstante(AGORA_FAKE); }

  async function seedComFronteira() {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(AGORA_FAKE));
    const chave = chaveAtual();
    await env.RADAR_KV.delete(chave);
    await env.RADAR_KV.put(chave, JSON.stringify({
      week: chave.replace("radar:estado:", ""),
      updated_at: CARIMBO_FIXO,
      results: {
        [EMPRESA]: {
          sem_eventos: false,
          eventos: [{
            classificacao: "RELEVANTE", titulo: "Fato anterior", data_evento: FRONTEIRA_ATUAL,
            fonte_primaria: "https://www.rad.cvm.gov.br/enet/frmDownloadDocumento.aspx?id=1",
            fonte_tipo: "CVM_FATO_RELEVANTE", tags: []
          }]
        }
      },
      feed_frontier_data: FRONTEIRA_ATUAL,
      feed_ultimo_evento_novo_em: CARIMBO_FIXO
    }));
  }

  async function submeter(dataEvento, url) {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.77" },
      body: JSON.stringify({
        action: "receber_analise",
        routine_key: ROUTINE_KEY,
        empresa: EMPRESA,
        setor: "Saúde",
        _tier: "FULL",
        provedor: "teste-feedretro1",
        resultado: {
          sem_eventos: false,
          eventos: [{
            classificacao: "RELEVANTE", titulo: "Evento de teste", data_evento: dataEvento,
            data_aproximada: false, fonte_primaria: url, fonte_tipo: "IMPRENSA", tags: []
          }],
          fontes_consultadas: [{ rodada: "R2", query: "teste feedretro1", resultado: "achou fonte" }],
          cobertura_nota: "teste FEEDRETRO1"
        }
      })
    });
    expect(res.status).toBe(200);
    return res.json();
  }

  async function lerEstadoBruto() {
    return env.RADAR_KV.get(chaveAtual(), "json");
  }

  it("caso A: evento velho com chave nova (URL diferente) nao avanca a fronteira nem o carimbo", async () => {
    await seedComFronteira();
    const j = await submeter("2026-08-10", "https://www.infomoney.com.br/mercados/2026/08/10/teste-a-chave-nova/");
    expect(j.ok).toBe(true);
    const est = await lerEstadoBruto();
    expect(est.feed_frontier_data).toBe(FRONTEIRA_ATUAL);
    expect(est.feed_ultimo_evento_novo_em).toBe(CARIMBO_FIXO);
  });

  it("caso B: evento com data maior que a fronteira avanca a fronteira e o carimbo", async () => {
    await seedComFronteira();
    const j = await submeter("2026-09-03", "https://www.infomoney.com.br/mercados/2026/09/03/teste-b-avanco/");
    expect(j.ok).toBe(true);
    const est = await lerEstadoBruto();
    expect(est.feed_frontier_data).toBe("2026-09-03");
    expect(est.feed_ultimo_evento_novo_em).not.toBe(CARIMBO_FIXO);
    expect(new Date(est.feed_ultimo_evento_novo_em).getTime()).toBeGreaterThan(new Date(CARIMBO_FIXO).getTime());
  });

  it("caso C: duplicata da MESMA data maxima, com URL alternativa, nao avanca o carimbo", async () => {
    await seedComFronteira();
    const j = await submeter(FRONTEIRA_ATUAL, "https://www.moneytimes.com.br/2026/08/20/teste-c-url-alternativa/");
    expect(j.ok).toBe(true);
    const est = await lerEstadoBruto();
    expect(est.feed_frontier_data).toBe(FRONTEIRA_ATUAL);
    expect(est.feed_ultimo_evento_novo_em).toBe(CARIMBO_FIXO);
  });
});

// Casos do operador (correcao final, 04/09): n_eventos_avanco_data mede avanco
// TEMPORAL (quantas DATAS DISTINTAS superam o maximo anterior), nunca quantidade
// de fatos novos - dois fatos legitimos e diferentes na MESMA data nova contam 1
// avanco, nao 2. n_chaves_novas mede outra coisa (chave de dedup ausente em
// anterior, com qualquer data) e nunca prova ausencia de outro evento legitimo
// na mesma data. Mesma tecnica de URL com data no path da suite de fronteira
// acima, para nao depender de rede.
describe("receber_analise: n_eventos_avanco_data mede avanco temporal, nao contagem de fatos", () => {
  const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
  const EMPRESA = "Dasa";
  const FRONTEIRA_ATUAL = "2026-08-20";
  const URL_CONHECIDA = "https://www.rad.cvm.gov.br/enet/frmDownloadDocumento.aspx?id=1";
  const AGORA_FAKE = "2026-09-03T15:00:00Z";

  afterEach(() => {
    vi.useRealTimers();
  });

  function chaveAtual() { return chaveEstadoParaInstante(AGORA_FAKE); }

  async function seed() {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(AGORA_FAKE));
    const chave = chaveAtual();
    await env.RADAR_KV.delete(chave);
    await env.RADAR_KV.put(chave, JSON.stringify({
      week: chave.replace("radar:estado:", ""),
      updated_at: "2026-08-20T09:00:00.000Z",
      results: {
        [EMPRESA]: {
          sem_eventos: false,
          eventos: [{
            // `empresa` DENTRO do evento e obrigatorio no fixture: _chaveDedupEvento usa
            // data|empresa|fonte_base, e o pipeline real sempre preenche esse campo antes
            // de persistir (receber_analise faz Object.assign({}, e, { empresa }) na cadeia
            // do validarDatasFontes). Seed sem ele gera chave diferente do evento reenviado
            // e faria o caso 1 e o 5 medirem chave nova onde nao ha.
            empresa: EMPRESA,
            classificacao: "RELEVANTE", titulo: "Fato anterior", data_evento: FRONTEIRA_ATUAL,
            fonte_primaria: URL_CONHECIDA, fonte_tipo: "CVM_FATO_RELEVANTE", tags: []
          }]
        }
      }
    }));
  }

  async function submeter(eventosSpec) {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.77" },
      body: JSON.stringify({
        action: "receber_analise",
        routine_key: ROUTINE_KEY,
        empresa: EMPRESA,
        setor: "Saúde",
        _tier: "FULL",
        provedor: "teste-avanco-data",
        resultado: {
          sem_eventos: false,
          eventos: eventosSpec.map((e, i) => ({
            classificacao: "RELEVANTE", titulo: "Evento de teste " + i, data_evento: e.data,
            data_aproximada: false, fonte_primaria: e.url, fonte_tipo: "IMPRENSA", tags: []
          })),
          fontes_consultadas: [{ rodada: "R2", query: "teste avanco data", resultado: "achou fonte" }],
          cobertura_nota: "teste avanco data"
        }
      })
    });
    expect(res.status).toBe(200);
    return res.json();
  }

  it("caso 1: evento repetido (mesma chave de dedup) -> n_eventos_avanco_data=0", async () => {
    await seed();
    const j = await submeter([{ data: FRONTEIRA_ATUAL, url: URL_CONHECIDA }]);
    expect(j.ok).toBe(true);
    expect(j.n_eventos_avanco_data).toBe(0);
  });

  it("caso 2: chave nova com data_evento <= max anterior -> n_eventos_avanco_data=0", async () => {
    await seed();
    const j = await submeter([{ data: "2026-08-10", url: "https://www.infomoney.com.br/mercados/2026/08/10/teste-caso2/" }]);
    expect(j.ok).toBe(true);
    expect(j.n_eventos_avanco_data).toBe(0);
    expect(j.n_chaves_novas).toBe(1);
  });

  it("caso 3: evento com data_evento > max anterior -> n_eventos_avanco_data=1", async () => {
    await seed();
    const j = await submeter([{ data: "2026-09-03", url: "https://www.infomoney.com.br/mercados/2026/09/03/teste-caso3/" }]);
    expect(j.ok).toBe(true);
    expect(j.n_eventos_avanco_data).toBe(1);
    expect(j.max_data_evento_antes).toBe(FRONTEIRA_ATUAL);
    expect(j.max_data_evento_depois).toBe("2026-09-03");
  });

  it("caso 4: segundo fato legitimo na MESMA data nova nao dobra n_eventos_avanco_data", async () => {
    await seed();
    const j = await submeter([
      { data: "2026-09-03", url: "https://www.infomoney.com.br/mercados/2026/09/03/teste-caso4-a/" },
      { data: "2026-09-03", url: "https://www.moneytimes.com.br/2026/09/03/teste-caso4-b/" }
    ]);
    expect(j.ok).toBe(true);
    expect(j.n_eventos_avanco_data).toBe(1);
    expect(j.n_chaves_novas).toBe(2);
  });

  it("caso 5: n_chaves_novas e medido separado, nao confundir com avanco de data", async () => {
    await seed();
    const j = await submeter([
      { data: FRONTEIRA_ATUAL, url: URL_CONHECIDA },
      { data: "2026-08-15", url: "https://www.infomoney.com.br/mercados/2026/08/15/teste-caso5/" }
    ]);
    expect(j.ok).toBe(true);
    expect(j.n_eventos_avanco_data).toBe(0);
    expect(j.n_chaves_novas).toBe(1);
    expect(j.n_eventos_conhecidos).toBe(1);
  });
});
