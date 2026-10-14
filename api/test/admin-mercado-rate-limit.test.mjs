import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// RLADMIN4 (2026-10-09): o formulario admin_mercado (content-type
// application/x-www-form-urlencoded, campo `senha`) retornava ANTES do gate
// RLADMIN2/RLADMIN3, que so olha corpos JSON com `admin_senha`. Vetor: brute force do
// ADMIN_PASSWORD sem throttle, e a senha certa devolvia a pagina admin autenticada.
// Estes testes travam as duas pontas: senha ERRADA entra no rate limit (burst anonimo,
// 3/60s por IP - mesmo RATE_LIMITS_ANONIMO do login) e senha CORRETA nao e throttled
// (paridade com ADMINRL-FIX1, que evita self-DoS do painel).

function formMercado(campos) {
  const f = new URLSearchParams();
  f.set("action", "admin_mercado");
  for (const [k, v] of Object.entries(campos)) f.set(k, v);
  return f;
}

function postMercado(ip, campos) {
  return SELF.fetch("https://example.com/?action=admin_mercado", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "CF-Connecting-IP": ip
    },
    body: formMercado(campos).toString()
  });
}

describe("RLADMIN4 - rate limit no formulario admin_mercado (form-urlencoded)", () => {
  it("senha errada e bloqueada com 429 na 4a tentativa (burst 3/60s por IP)", async () => {
    const ip = "198.51.100.41"; // TEST-NET-2 (RFC 5737), nao roteavel
    const respostas = [];
    for (let i = 0; i < 4; i++) {
      respostas.push(await postMercado(ip, { senha: "senha-errada-" + i }));
    }
    // 1a-3a: passam do limiter e caem no login form (200 com HTML de senha, sem autenticar).
    for (let i = 0; i < 3; i++) {
      expect(respostas[i].status, `tentativa ${i + 1}`).toBe(200);
      const html = await respostas[i].text();
      expect(html).toContain('name="senha"'); // pagina de senha, NAO o painel
      expect(html).not.toContain("ADMIN DE MERCADO");
    }
    // 4a: bloqueada ANTES de chegar em handleAdminMercado.
    const bloqueada = respostas[3];
    expect(bloqueada.status).toBe(429);
    const body = await bloqueada.json();
    expect(body._rate_limit?.camada).toBe("burst");
  });

  it("senha correta nao e throttled (o painel dispara multiplos POSTs)", async () => {
    const ip = "198.51.100.42";
    for (let i = 0; i < 4; i++) {
      const r = await postMercado(ip, { senha: env.ADMIN_PASSWORD });
      expect(r.status, `chamada correta ${i + 1}`).toBe(200);
      const html = await r.text();
      expect(html).toContain("ADMIN DE MERCADO"); // painel autenticado
    }
  });

  it("o vetor do JSON com admin_senha continua throttled (sem regressao do RLADMIN2)", async () => {
    const ip = "198.51.100.43";
    const respostas = [];
    for (let i = 0; i < 4; i++) {
      respostas.push(
        await SELF.fetch("https://example.com/?action=admin_mercado", {
          method: "POST",
          headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
          body: JSON.stringify({ action: "admin_listar", admin_senha: "senha-errada-" + i })
        })
      );
    }
    expect(respostas[3].status).toBe(429);
  });
});
