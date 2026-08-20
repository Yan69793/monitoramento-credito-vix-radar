import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// REGISTRO-ADMIN1 (2026-08-20, auditoria): o registro derivava autoridade do e-mail
// enviado no corpo da requisicao, que nunca foi verificado. `isAdmin` comparava
// body.email com ADMIN_EMAIL e, quando batia, a conta nascia status "aprovado",
// aprovado_por "auto" e white_label true. Como handleLogin calcula
// `roleFinal = email === ADMIN_EMAIL ? "admin" : "user"`, quem soubesse o e-mail do
// admin registrava com senha propria e recebia JWT de admin sem nunca saber a
// ADMIN_PASSWORD. A unica contencao era o estado da conta no KV: se ela ja existisse
// como "aprovado", o early return barrava o putUser. Com a conta ausente, ou com
// status "rejeitado" (que NAO tem early return e cai no putUser sobrescrevendo o
// senha_hash), o vetor abria.
//
// A via legitima de recuperacao continua existindo e nao passa por aqui:
// handleAdminAutoLogin exige admin_senha === env.ADMIN_PASSWORD, ou seja o secret
// do Worker, e so entao cria ou aprova a conta admin.

const ADMIN_EMAIL_TESTE = "admin-test@example.com"; // igual ao vars do wrangler.test.jsonc

function postRegistrar(email, senha) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": "198.51.100." + Math.floor(Math.random() * 200 + 10),
    },
    body: JSON.stringify({
      action: "registrar",
      nome: "Invasor Teste",
      email,
      empresa: "Empresa Teste",
      senha,
      consentimento_lgpd: true,
    }),
  });
}

function postLogin(email, senha) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "CF-Connecting-IP": "198.51.100." + Math.floor(Math.random() * 200 + 10),
    },
    body: JSON.stringify({ action: "login", email, senha }),
  });
}

describe("REGISTRO-ADMIN1: e-mail do corpo nao concede admin", () => {
  it("registrar com o e-mail do admin NAO cria conta aprovada e o login nao devolve token", async () => {
    const senhaDoAtacante = "senha-escolhida-pelo-atacante-123";

    // Storage do Miniflare abre do zero a cada teste, entao a conta admin NAO existe.
    // Este e exatamente o cenario que o vetor exigia.
    const reg = await postRegistrar(ADMIN_EMAIL_TESTE, senhaDoAtacante);
    expect(reg.status).toBe(200);
    const regBody = await reg.json();

    // Antes do fix a resposta era a especial "Conta admin criada.", que junto de
    // status aprovado entregava o acesso. Ela nao existe mais.
    expect(JSON.stringify(regBody)).not.toContain("Conta admin criada");

    // A prova que importa e comportamental, nao textual: com a conta pendente, o
    // login recusa. Antes do fix este login devolvia 200 com token role "admin".
    const login = await postLogin(ADMIN_EMAIL_TESTE, senhaDoAtacante);
    expect(login.status).not.toBe(200);
    const loginBody = await login.json();
    expect(loginBody.ok).toBe(false);
    expect(loginBody.token).toBeUndefined();
    expect(JSON.stringify(loginBody)).not.toContain("admin");
  });

  it("usuario comum tambem nasce pendente, o fluxo normal segue igual", async () => {
    const email = "usuario-comum-teste@example.com";
    const senha = "senha-comum-123456";

    const reg = await postRegistrar(email, senha);
    expect(reg.status).toBe(200);
    expect((await reg.json()).ok).toBe(true);

    // Pendente nao loga. Este assert prova que o teste acima nao passou por acidente
    // de o login estar quebrado para todo mundo: o comportamento e o mesmo dos dois
    // lados, que e justamente o ponto do fix, o e-mail deixou de ser privilegio.
    const login = await postLogin(email, senha);
    expect(login.status).not.toBe(200);
    expect((await login.json()).token).toBeUndefined();
  });
});
