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
    const body = await medirComRelogioEEstado("2026-09-07T13:50:00Z", "2026-09-06T13:20:00.000Z");
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
