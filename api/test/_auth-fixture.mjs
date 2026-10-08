// SESSION-ONE (2026-10-08): helper de autenticacao para a suite.
//
// Contexto: a partir da politica de sessao unica, `verificarJWT` so aceita
// token cujo payload carrega `sid` E cuja sessao continua ativa no UsuarioDO
// (op `checkSessaoAtiva`). Token montado a mao no teste, sem passar pelo
// login, perde a validade por construcao e vira 401. As fixtures antigas
// mintavam o JWT direto (HS256 + JWT_SECRET), o que nao cria sessao nenhuma.
//
// Estes helpers geram token pelo FLUXO REAL, o mesmo do cliente:
//   1. gravam o usuario no KV com `senha_hash` no formato de producao
//      (b64(salt 16B) + ":" + b64(derivado 32B), PBKDF2-SHA256 100k);
//   2. chamam `action=login`, que valida a senha, emite o `sid`, registra a
//      sessao ativa no UsuarioDO e devolve o token assinado.
//
// Nao ha bypass, atalho de teste, enfraquecimento de `verificarJWT` nem
// aceitacao de token antigo: e literalmente o caminho de producao.
//
// Cada login usa um `CF-Connecting-IP` TEST-NET-2 (RFC 5737, nao roteavel)
// proprio, porque o gate de rate limit anonimo e por identidade `ip:<ip>` e
// repetir o mesmo IP estouraria o burst (3/60s) dentro de um arquivo.
import { SELF, env } from "cloudflare:test";

export const SENHA_FIXTURE = "fixture-sessao-senha-0001";
export const EMAIL_FIXTURE = "fixture-sessao@example.com";

// Copia literal de hashSenha (api/src/worker.js, secao de auth):
// b64(salt 16B) + ":" + b64(derivado 32B), PBKDF2-SHA256 com 100k iteracoes.
// Escrito a mao de proposito, para o teste depender do FORMATO gravado no KV
// e nao de um export novo do worker.
export async function hashSenhaLocal(senha) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 1e5, hash: "SHA-256" }, key, 256);
  return `${btoa(String.fromCharCode(...salt))}:${btoa(String.fromCharCode(...new Uint8Array(bits)))}`;
}

export async function semearUsuario(email, { senha = SENHA_FIXTURE, status = "aprovado", extras = {} } = {}) {
  const registro = {
    email,
    nome: "Fixture Sessao",
    empresa: "Fixture SA",
    status,
    senha_hash: await hashSenhaLocal(senha),
    tenant: "default",
    ui_track: "current",
    white_label: false,
    created_at: "2026-01-01T00:00:00.000Z",
    ...extras,
  };
  await env.RADAR_KV.put("user:" + email.toLowerCase().trim(), JSON.stringify(registro));
  return registro;
}

let _ipSeq = 0;
export async function loginFixture(email, { senha = SENHA_FIXTURE, extra = {} } = {}) {
  _ipSeq += 1;
  const ip = "198.51.100." + (_ipSeq % 250);
  const res = await SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ action: "login", email, senha, ...extra }),
  });
  const body = await res.json().catch(() => null);
  if (res.status !== 200 || !body || typeof body.token !== "string" || !body.token) {
    throw new Error(`loginFixture falhou para ${email}: HTTP ${res.status}`);
  }
  return body;
}

// Semeia o usuario e devolve um token de sessao valido (fluxo real).
export async function tokenFixture(email = EMAIL_FIXTURE, opts = {}) {
  await semearUsuario(email, opts);
  const body = await loginFixture(email, opts);
  return body.token;
}

// Token com role admin: o login promove a `admin` quando o email bate com
// `ADMIN_EMAIL` do runtime (wrangler.test.jsonc: admin-test@example.com).
export async function tokenAdmin(opts = {}) {
  return await tokenFixture(env.ADMIN_EMAIL, opts);
}
