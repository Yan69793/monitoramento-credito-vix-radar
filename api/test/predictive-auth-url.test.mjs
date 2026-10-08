import { SELF, env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { EMAIL_FIXTURE, tokenAdmin, tokenFixture } from "./_auth-fixture.mjs";

const fixturePassword = "test-admin-password-nao-usar-em-producao";

// SESSION-ONE: o token passa a vir do fluxo real de login (sessao unica). O
// helper antigo montava um JWT HS256 a mao, sem sessao ativa no UsuarioDO, e
// por isso o verificarJWT o recusa agora — corretamente. Usa apenas os
// bindings sinteticos de wrangler.test.jsonc, nunca senha real na URL.
async function jwt(role) {
  return role === "admin" ? await tokenAdmin() : await tokenFixture(EMAIL_FIXTURE);
}

describe("laboratorio preditivo sem senha na URL", () => {
  beforeAll(() => {
    // Wrangler pode carregar .env. Nunca colocar uma credencial local real na URL,
    // nem inclui-la em mensagem de falha de assercao.
    if (env.ADMIN_PASSWORD !== fixturePassword || env.JWT_SECRET !== "test-jwt-secret-nao-usar-em-producao") {
      throw new Error("Bindings de autenticacao nao sinteticos. Corrija o isolamento do runner antes de testar.");
    }
  });
  it.each(["admin_senha", "senha"])("senha correta em %s nao autentica", async (parameter) => {
    const url = new URL("https://example.com/?op=predictive_v1");
    url.searchParams.set(parameter, fixturePassword);
    const response = await SELF.fetch(url.toString());
    expect(response.status).toBe(401);
    expect((await response.json()).ok).toBe(false);
  });

  it("JWT admin continua lendo o laboratorio", async () => {
    await env.RADAR_KV.put("predictive_v1:latest", JSON.stringify({ fixture: true }));
    const response = await SELF.fetch("https://example.com/?op=predictive_v1", {
      headers: { Authorization: `Bearer ${await jwt("admin")}` }
    });
    expect(response.status).toBe(200);
    const payload = await response.json();
    expect(payload.ok).toBe(true);
    expect(payload.auth_via).toBe("jwt_admin");
    expect(payload.fixture).toBe(true);
  });

  it("JWT comum e senha correta em query nao concedem acesso admin", async () => {
    const url = new URL("https://example.com/?op=predictive_v1");
    url.searchParams.set("admin_senha", fixturePassword);
    const response = await SELF.fetch(url.toString(), { headers: { Authorization: `Bearer ${await jwt("user")}` } });
    expect(response.status).toBe(403);
  });

  it.each(["x-admin-password", "X-Admin-Auth"])("cliente existente com header %s continua autenticando", async (header) => {
    const response = await SELF.fetch("https://example.com/?op=predictive_v1", { headers: { [header]: env.ADMIN_PASSWORD } });
    expect(response.status).toBe(200);
    expect((await response.json()).auth_via).toBe("admin_password");
  });
});
