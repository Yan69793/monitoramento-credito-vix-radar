import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// RATE_LIMITS_ANONIMO.burst = [3, 60] (worker.js ~:3663): 3 requests em 60s por
// identidade. Sem JWT a identidade e "ip:<CF-Connecting-IP>" (resolverIdentidadeRL).
// O gate roda ANTES de handleLogin (worker.js ~:15796-15803), entao mesmo login
// com credencial invalida conta para o burst.
function postLogin(ip) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": ip,
    },
    body: JSON.stringify({
      action: "login",
      email: "nao-existe-teste@example.com",
      senha: "senha-errada-123",
    }),
  });
}

describe("rate limit de login (RLADMIN1, camada burst)", () => {
  it("libera as 3 primeiras tentativas e bloqueia a 4a com 429/burst", async () => {
    const ip = "203.0.113.55"; // TEST-NET-3 (RFC 5737), nao roteavel
    const respostas = [];
    for (let i = 0; i < 4; i++) {
      respostas.push(await postLogin(ip));
    }

    // 1a-3a: passam do rate limiter e caem em handleLogin, que rejeita
    // credencial inexistente com 401 (nunca 429 - o limite ainda nao estourou).
    for (let i = 0; i < 3; i++) {
      expect(respostas[i].status, `tentativa ${i + 1}`).toBe(401);
    }

    // 4a: bloqueada pelo RateLimiterDO antes de chegar em handleLogin.
    const bloqueada = respostas[3];
    expect(bloqueada.status).toBe(429);
    const body = await bloqueada.json();
    expect(body.ok).toBe(false);
    expect(body._rate_limit.camada).toBe("burst");
    expect(body._rate_limit.retry_after_sec).toBeGreaterThan(0);
  });

  it("identidade separada (IP diferente) nao herda o bloqueio da outra", async () => {
    const res = await postLogin("203.0.113.99");
    expect(res.status).toBe(401);
  });
});

// ADMINRL-FIX1 (v4.9.191): admin_senha CORRETA pula o checkRateLimitV2. O painel
// admin dispara 4+ POSTs em paralelo com a senha certa (loadHoje), o que estourava
// o burst anonimo de 3/60s. Brute force continua throttled: senha errada segue no check.
// Incidente 2026-08-12 15:13 BRT.
function postAdminSenha(ip, senha) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": ip,
    },
    body: JSON.stringify({
      action: "admin_listar",
      admin_senha: senha,
    }),
  });
}

describe("gate de rate limit com admin_senha (ADMINRL-FIX1)", () => {
  it("senha admin errada continua throttled: 4a tentativa responde 429/burst", async () => {
    const ip = "203.0.113.66";
    const respostas = [];
    for (let i = 0; i < 4; i++) {
      respostas.push(await postAdminSenha(ip, "senha-admin-errada"));
    }

    // 1a-3a: passam do rate limiter e caem no handler, que responde 403.
    for (let i = 0; i < 3; i++) {
      expect(respostas[i].status, `tentativa ${i + 1}`).toBe(403);
    }

    // 4a: bloqueada pelo RateLimiterDO antes do handler.
    const bloqueada = respostas[3];
    expect(bloqueada.status).toBe(429);
    const body = await bloqueada.json();
    expect(body._rate_limit.camada).toBe("burst");
  });

  it("senha admin correta nao estoura o burst: 6 requests em sequencia, nenhum 429", async () => {
    const ip = "203.0.113.77";
    const respostas = [];
    for (let i = 0; i < 6; i++) {
      respostas.push(await postAdminSenha(ip, "test-admin-password-nao-usar-em-producao"));
    }

    for (let i = 0; i < 6; i++) {
      expect(respostas[i].status, `request ${i + 1}`).not.toBe(429);
    }
    // admin_listar com senha correta responde ok (payload admin, nao importa o conteudo aqui).
    expect(respostas[0].status).toBe(200);
  });
});
