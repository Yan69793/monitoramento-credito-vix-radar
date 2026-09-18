import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// FE-09 (2026-09-18): XSS armazenado no painel admin por e-mail do usuario em
// handler inline. O frontend foi corrigido (o e-mail passou a viajar em
// data-admin-email com listener delegado), e esta e a defesa adicional do lado
// do servidor: o cadastro deixa de aceitar caracteres que nao existem em
// endereco de e-mail e que serviam para quebrar o contexto do atributo.
//
// Antes: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ aceitava apostrofo, parenteses, aspas,
// barra e virgula no local-part, e o guarda extra barrava somente < e >.
// Agora: local-part em [A-Za-z0-9._%+-], dominio em [A-Za-z0-9-] com rotulos
// separados por ponto e TLD de 2+ letras, teto de 254 caracteres.
//
// Este teste e a ponta de entrada. A ponta de saida (o frontend nao montar
// handler executavel) esta em scripts/test-email-xss-admin.mjs e em
// app/tests/tests/admin-email-xss.spec.mjs, que roda em navegador real.

const LANCADOS_MALICIOSOS = [
  "x'),window.__fe09Pwned=1,('y@z.com",
  "a'b@c.com",
  'a"b@c.com',
  "a(b)@c.com",
  "a,b@c.com",
  "a;b@c.com",
  "a\\b@c.com",
  "a/b@c.com",
  "a b@c.com",
  "a`b@c.com",
  "a>b@c.com",
  "a@b.c",
  "sem-arroba.example.com",
  "a@b",
  "a@@b.com",
  "usuario@dominio",
  "a@" + "x".repeat(260) + ".com",
];

const VALIDOS = [
  "cliente@empresa.com.br",
  "joao.silva+tag@empresa.com.br",
  "user_name%x@sub.dominio.com",
  "a-b.c@d-e.com.br",
  "primeiro.ultimo@empresa.io",
];

let contadorIp = 10;
function proximoIp() {
  contadorIp += 1;
  return `198.51.100.${contadorIp}`;
}

function postRegistrar(email) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": proximoIp(),
    },
    body: JSON.stringify({
      action: "registrar",
      nome: "Teste FE-09",
      email,
      empresa: "Empresa Teste",
      senha: "senha-de-teste-123456",
      consentimento_lgpd: true,
    }),
  });
}

describe("FE-09: cadastro recusa e-mail que serviria de vetor de injection", () => {
  for (const email of LANCADOS_MALICIOSOS) {
    it(`recusa ${JSON.stringify(email.slice(0, 40))}`, async () => {
      const r = await postRegistrar(email);
      expect(r.status).toBe(400);
      const body = await r.json();
      expect(body.ok).toBe(false);
      expect(body.erro).toBe("E-mail inválido.");
      // O e-mail recusado nao pode virar conta: nenhum token, nenhum id de usuario.
      expect(body.token).toBeUndefined();
    });
  }

  it("o payload do FE-09 nao passa pelo guarda de < e >, e pela regra de formato", async () => {
    const payload = "x'),window.__fe09Pwned=1,('y@z.com";
    const r = await postRegistrar(payload);
    expect(r.status).toBe(400);
    // Prova de que a recusa vem da regra de formato, e nao do guarda de < >:
    // a mensagem so e "E-mail inválido." quando a primeira checagem dispara.
    expect((await r.json()).erro).toBe("E-mail inválido.");
  });
});

describe("FE-09: e-mail legitimo continua aceito", () => {
  for (const email of VALIDOS) {
    it(`aceita ${email}`, async () => {
      const r = await postRegistrar(email);
      expect(r.status).toBe(200);
      const body = await r.json();
      expect(body.ok).toBe(true);
    });
  }
});
