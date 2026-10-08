import { SELF, env } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { emitirSessaoUnica, verificarJWT } from "../src/worker.js";

// SESSION-ONE (politica de sessao unica). O gate vive no Worker: `emitirSessaoUnica`
// grava o `sid` da sessao ativa no UsuarioDO do usuario e o assina no JWT;
// `verificarJWT` so aceita token cujo `sid` ainda e o ativo. Estes testes cobrem
// invalidez do token antigo, login administrativo, isolamento entre contas,
// concorrencia, expiracao, token sem sid/sid estranho e falha de storage
// (fail-closed). Nada aqui enfraquece o gate: todo token nasce do login real.

const SENHA = "senha-unica-teste-001";
const ADMIN_PASSWORD = "test-admin-password-nao-usar-em-producao";

async function hashSenha(senha) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 1e5, hash: "SHA-256" }, key, 256);
  return btoa(String.fromCharCode(...salt)) + ":" + btoa(String.fromCharCode(...new Uint8Array(bits)));
}

async function semear(email) {
  await env.RADAR_KV.put(
    "user:" + email.toLowerCase().trim(),
    JSON.stringify({
      email,
      nome: "Auditoria Sessao",
      empresa: "Testes",
      status: "aprovado",
      senha_hash: await hashSenha(SENHA),
      tenant: "default",
      ui_track: "current",
      white_label: false,
      created_at: new Date().toISOString(),
    })
  );
}

// IP TEST-NET-3 (RFC 5737, nao roteavel) proprio por requisicao: o gate de rate
// limit anonimo e por identidade `ip:<ip>`.
let ipSeq = 0;
function proximoIp() {
  ipSeq += 1;
  return "203.0.113." + (ipSeq % 250);
}

async function post(action, extra = {}, token = "", ip = proximoIp()) {
  const r = await SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": ip,
      ...(token ? { Authorization: "Bearer " + token } : {}),
    },
    body: JSON.stringify({ action, ...extra }),
  });
  return { status: r.status, body: await r.json() };
}

async function loginOk(email, senha = SENHA) {
  const r = await post("login", { email, senha });
  expect(r.status).toBe(200);
  expect(typeof r.body.token).toBe("string");
  return r.body;
}

async function tokenValido(token) {
  return (await post("refresh_cookie", {}, token)).status === 200;
}

// Re-assina um token REAL (mantendo o sid da sessao ativa) com um patch no
// payload, usando o mesmo HS256/JWT_SECRET do Worker. Serve para exercitar
// expiracao e ausencia de sid sem inventar sessao paralela.
function b64urlEncodeStr(str) {
  return btoa(unescape(encodeURIComponent(str))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlDecodeStr(s) {
  return decodeURIComponent(escape(atob(s.replace(/-/g, "+").replace(/_/g, "/"))));
}
async function reassinar(token, patch) {
  const [header, body] = token.split(".");
  const payload = JSON.parse(b64urlDecodeStr(body));
  Object.assign(payload, patch);
  const novoBody = b64urlEncodeStr(JSON.stringify(payload));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.JWT_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${novoBody}`));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${header}.${novoBody}.${sigB64}`;
}

// UsuarioDO que falha nas ops de sessao: simula storage indisponivel sem tocar
// no codigo de producao. Usado so nos testes unitarios de fail-closed.
function envComDOQuebrado() {
  return {
    JWT_SECRET: env.JWT_SECRET,
    USUARIO_DO: {
      idFromName: (n) => n,
      get: () => ({ fetch: async () => { throw new Error("storage indisponivel"); } }),
    },
  };
}

describe("SESSION-ONE: somente o ultimo login permanece ativo", () => {
  it("novo login invalida imediatamente o token anterior; credenciais e usuario preservados", async () => {
    const email = "sessao-unica-audit@example.com";
    await semear(email);
    const a = await loginOk(email);
    expect(await tokenValido(a.token)).toBe(true);
    const primeira = await post("refresh_cookie", {}, a.token);
    expect(primeira.status).toBe(200);

    const b = await loginOk(email);
    expect(b.token).not.toBe(a.token);
    expect(b.sessao_anterior_encerrada).toBe(true);

    expect(await tokenValido(a.token)).toBe(false);
    expect(await tokenValido(b.token)).toBe(true);
    // as credenciais seguem valendo (o bloqueio e de sessao, nao de conta)
    const c = await loginOk(email);
    expect(await tokenValido(c.token)).toBe(true);
  });

  it("mensagem_sessao acompanha a flag sessao_anterior_encerrada", async () => {
    const email = "sessao-unica-msg@example.com";
    await semear(email);
    const a = await loginOk(email);
    expect(a.mensagem_sessao).toBeNull();
    const b = await loginOk(email);
    expect(b.sessao_anterior_encerrada).toBe(true);
    expect(typeof b.mensagem_sessao).toBe("string");
    expect(b.mensagem_sessao.length).toBeGreaterThan(0);
  });

  it("isolamento entre usuarios: a segunda sessao de A nunca derruba a de B", async () => {
    const a = "sessao-unica-iso-a@example.com";
    const b = "sessao-unica-iso-b@example.com";
    await semear(a);
    await semear(b);
    const ta1 = (await loginOk(a)).token;
    const tb1 = (await loginOk(b)).token;
    const ta2 = (await loginOk(a)).token;
    expect(await tokenValido(ta2)).toBe(true);
    expect(await tokenValido(ta1)).toBe(false); // A teve a sessao anterior encerrada
    expect(await tokenValido(tb1)).toBe(true); // B intacto
  });

  it("concorrencia: N logins simultaneos da mesma conta deixam exatamente 1 token valido", async () => {
    const email = "sessao-unica-conc@example.com";
    await semear(email);
    const respostas = await Promise.all(Array.from({ length: 5 }, () => post("login", { email, senha: SENHA })));
    for (const r of respostas) expect(r.status).toBe(200);
    const tokens = respostas.map((r) => r.body.token);
    expect(new Set(tokens).size).toBe(tokens.length); // sids distintos
    let validos = 0;
    for (const t of tokens) if (await tokenValido(t)) validos += 1;
    expect(validos).toBe(1);
  });

  it("expiracao: token com exp no passado e recusado mesmo com a sessao ativa", async () => {
    const email = "sessao-unica-exp@example.com";
    await semear(email);
    const { token } = await loginOk(email);
    expect(await tokenValido(token)).toBe(true);
    const expirado = await reassinar(token, { exp: Math.floor(Date.now() / 1000) - 10 });
    expect(await tokenValido(expirado)).toBe(false);
    expect(await tokenValido(token)).toBe(true); // o token vigente segue valendo
  });

  it("token sem sid (fixture antiga) e recusado", async () => {
    const email = "sessao-unica-nosid@example.com";
    await semear(email);
    const { token } = await loginOk(email);
    const semSid = await reassinar(token, { sid: undefined });
    expect(JSON.parse(b64urlDecodeStr(semSid.split(".")[1])).sid).toBeUndefined();
    expect(await tokenValido(semSid)).toBe(false);
  });

  it("sid estranho (assinatura valida, sessao inexistente) e recusado", async () => {
    const email = "sessao-unica-siderrado@example.com";
    await semear(email);
    const { token } = await loginOk(email);
    const estranho = await reassinar(token, { sid: "00000000-0000-4000-8000-000000000000" });
    expect(await tokenValido(estranho)).toBe(false);
    expect(await tokenValido(token)).toBe(true);
  });

  it("o login administrativo tambem aplica sessao unica", async () => {
    const r1 = await post("admin_auto_login", { admin_senha: ADMIN_PASSWORD });
    expect(r1.status).toBe(200);
    expect(JSON.parse(b64urlDecodeStr(r1.body.token.split(".")[1])).role).toBe("admin");
    expect(await tokenValido(r1.body.token)).toBe(true);

    const r2 = await post("admin_auto_login", { admin_senha: ADMIN_PASSWORD });
    expect(r2.status).toBe(200);
    expect(r2.body.sessao_anterior_encerrada).toBe(true);
    expect(r2.body.token).not.toBe(r1.body.token);
    expect(await tokenValido(r1.body.token)).toBe(false);
    expect(await tokenValido(r2.body.token)).toBe(true);
  });

  it("falha de storage do UsuarioDO e fail-closed: nao emite token e nao autentica", async () => {
    await expect(emitirSessaoUnica(envComDOQuebrado(), { email: "x@example.com" })).rejects.toBeTruthy();

    const email = "sessao-unica-storage@example.com";
    await semear(email);
    const { token } = await loginOk(email);
    expect(await tokenValido(token)).toBe(true);
    // Com o DO indisponivel, o mesmo token real deixa de autenticar.
    expect(await verificarJWT(envComDOQuebrado(), token)).toBeNull();
  });
});
