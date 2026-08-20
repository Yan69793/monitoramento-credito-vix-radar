import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

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
  });
});
