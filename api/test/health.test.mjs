import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// Automatiza o portao de verificacao que o CLAUDE.md do projeto pede para
// colar na mao apos deploy: GET / com ok:true, kv:true, telemetria:true.
describe("GET / (health check)", () => {
  // CVMFRESCOR1 (2026-08-19): cvm_fonte_ok entrou no _okHealth e e fail-closed,
  // entao sem meta de fonte o ok agregado e false por definicao. Este teste
  // cobre o caminho feliz, logo precisa semear uma fonte fresca. O
  // comportamento com fonte parada, meta ausente e sync falho fica em
  // cvm-frescor.test.mjs, que e quem guarda o contrato novo.
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
    // CVMFRESCOR1: ingestao cega derruba o health como secret ausente derruba.
    expect(body.cvm_fonte_ok).toBe(true);
  });
});
