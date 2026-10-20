import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// SENHAMIN8 (2026-10-19): senha minima subiu de 6 para 8 caracteres, decisao do
// operador. A regra vivia copiada em tres handlers (registrar, resetar_senha,
// admin_reset_senha) e agora le uma constante unica. Este teste cobre os tres
// pelas duas pontas: 7 caracteres e recusado, 8 e aceito. Tambem recusa senha
// que nao e string, que antes passava porque (123456789).length e undefined.

let contadorIp = 40;
function proximoIp() {
  contadorIp += 1;
  return `198.51.100.${contadorIp}`;
}

function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": proximoIp() },
    body: JSON.stringify(body),
  });
}

let seq = 0;
function emailNovo() {
  seq += 1;
  return `senhamin8.${seq}.${Date.now()}@empresa.com.br`;
}

function registrar(email, senha) {
  return post({ action: "registrar", nome: "Teste SENHAMIN8", email, empresa: "Empresa Teste", senha, consentimento_lgpd: true });
}

async function criarUsuario() {
  const email = emailNovo();
  const r = await registrar(email, "senha-inicial-123");
  expect(r.status).toBe(200);
  return email;
}

async function tokenReset(email) {
  const token = `tok-senhamin8-${seq}-${Date.now()}`;
  await env.RADAR_KV.put(`reset:${token}`, JSON.stringify({ email, created_at: Date.now() }));
  return token;
}

describe("SENHAMIN8: registrar", () => {
  it("recusa 7 caracteres", async () => {
    const r = await registrar(emailNovo(), "1234567");
    expect(r.status).toBe(400);
    expect((await r.json()).erro).toBe("Senha mínima: 8 caracteres.");
  });
  it("recusa senha que nao e string", async () => {
    const r = await registrar(emailNovo(), 123456789);
    expect(r.status).toBe(400);
    expect((await r.json()).erro).toBe("Senha mínima: 8 caracteres.");
  });
  it("aceita 8 caracteres", async () => {
    const r = await registrar(emailNovo(), "12345678");
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
  });
});

describe("SENHAMIN8: resetar_senha", () => {
  it("recusa 7 caracteres e nao consome o token", async () => {
    const email = await criarUsuario();
    const token = await tokenReset(email);
    const r = await post({ action: "resetar_senha", token, nova_senha: "1234567" });
    expect(r.status).toBe(400);
    expect((await r.json()).erro).toBe("Senha mínima: 8 caracteres.");
    expect(await env.RADAR_KV.get(`reset:${token}`)).not.toBeNull();
  });
  it("aceita 8 caracteres", async () => {
    const email = await criarUsuario();
    const token = await tokenReset(email);
    const r = await post({ action: "resetar_senha", token, nova_senha: "12345678" });
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
  });
});

describe("SENHAMIN8: admin_reset_senha", () => {
  it("recusa 7 caracteres", async () => {
    const email = await criarUsuario();
    const r = await post({ action: "admin_reset_senha", admin_senha: env.ADMIN_PASSWORD, email, nova_senha: "1234567" });
    expect(r.status).toBe(400);
    expect((await r.json()).erro).toBe("Senha mínima: 8 caracteres.");
  });
  it("aceita 8 caracteres", async () => {
    const email = await criarUsuario();
    const r = await post({ action: "admin_reset_senha", admin_senha: env.ADMIN_PASSWORD, email, nova_senha: "12345678" });
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
  });
  it("sem a senha de admin continua 403, antes de olhar a nova senha", async () => {
    const email = await criarUsuario();
    const r = await post({ action: "admin_reset_senha", admin_senha: "errada", email, nova_senha: "12345678" });
    expect(r.status).toBe(403);
  });
});
