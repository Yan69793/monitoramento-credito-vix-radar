import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// Automatiza o portao de verificacao que o CLAUDE.md do projeto pede para
// colar na mao apos deploy: GET / com ok:true, kv:true, telemetria:true.
describe("GET / (health check)", () => {
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
  });
});
