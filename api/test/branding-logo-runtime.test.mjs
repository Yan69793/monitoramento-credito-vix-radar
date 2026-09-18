import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// FE-10 (2026-09-18) — prova de runtime, pelo caminho real do Worker.
//
// O achado original dizia que o logo do white-label entrava sem escape no
// atributo src de <img> em dois pontos do frontend. Medindo o Worker, a mesma
// falha estava tambem do lado servidor: o relatorio compartilhado monta
// `<img src="${br.logo_data_url}">` no HTML servido a terceiros, e a validacao
// de gravacao (`/^data:image\/(png|svg\+xml|jpeg|jpg);base64,/`, sem ancora de
// fim) aceitava `data:image/png;base64,x" onerror="alert(1)`. O valor passava
// pela validacao, era gravado no KV e quebrava o atributo na renderizacao —
// XSS que dispara ao abrir o documento compartilhado, sem clique.
//
// Este teste mede o comportamento pelo endpoint real, e nao a forma do codigo:
//   - logo legitimo continua sendo gravado e devolvido inteiro;
//   - logo que tenta sair do atributo e descartado na gravacao, e nao chega ao KV.
//
// A ponta estrutural (regex extraida do fonte vivo, render com escape) esta em
// scripts/test-branding-logo-fe10.mjs.

const ADMIN_PASSWORD_TESTE = "test-admin-password-nao-usar-em-producao"; // wrangler.test.jsonc

const LOGO_LEGITIMO =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

const LOGOS_MALICIOSOS = [
  'data:image/png;base64,x" onerror="alert(1)',
  "data:image/png;base64,x' onerror='alert(1)",
  'data:image/svg+xml;base64,x"><script>alert(1)</script>',
  "javascript:alert(1)",
  "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
];

let contadorIp = 30;
function proximoIp() {
  contadorIp += 1;
  return `198.51.100.${contadorIp}`;
}

function post(action, corpo, token) {
  const headers = { "Content-Type": "application/json", "CF-Connecting-IP": proximoIp() };
  if (token) headers.Authorization = `Bearer ${token}`;
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers,
    body: JSON.stringify({ action, ...corpo }),
  });
}

// A conta admin nasce aprovada e com white_label true por este caminho, que e
// o mesmo usado pelo painel. Devolve o JWT de admin.
async function tokenDeAdmin() {
  const r = await post("admin_auto_login", { admin_senha: ADMIN_PASSWORD_TESTE });
  expect(r.status).toBe(200);
  const body = await r.json();
  expect(body.token, "admin_auto_login nao devolveu token").toBeTruthy();
  return body.token;
}

describe("FE-10: o logo do white-label nao pode sair do atributo src", () => {
  it("grava o logo legitimo e devolve o valor inteiro", async () => {
    const token = await tokenDeAdmin();
    const r = await post("salvar_branding", { branding: { logo_data_url: LOGO_LEGITIMO, gestora: "Gestora Teste" } }, token);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.ok).toBe(true);
    expect(body.branding.logo_data_url).toBe(LOGO_LEGITIMO);
  });

  for (const logo of LOGOS_MALICIOSOS) {
    it(`descarta na gravacao: ${JSON.stringify(logo.slice(0, 44))}`, async () => {
      const token = await tokenDeAdmin();
      const r = await post("salvar_branding", { branding: { logo_data_url: logo } }, token);
      expect(r.status).toBe(200);
      const body = await r.json();
      expect(body.ok).toBe(true);
      // A gravacao descarta o campo inteiro, em vez de guardar o valor sujo.
      expect(body.branding.logo_data_url).toBeUndefined();
    });
  }

  it("o valor descartado nao fica no KV e nao volta na leitura", async () => {
    const token = await tokenDeAdmin();
    const payload = 'data:image/png;base64,x" onerror="alert(1)';
    await post("salvar_branding", { branding: { logo_data_url: payload, gestora: "Gestora X" } }, token);
    const leitura = await post("ler_branding", {}, token);
    expect(leitura.status).toBe(200);
    const texto = JSON.stringify(await leitura.json());
    expect(texto).not.toContain("onerror");
    expect(texto).not.toContain(payload);
  });

  it("o caminho legitimo continua valendo depois de uma tentativa recusada", async () => {
    const token = await tokenDeAdmin();
    await post("salvar_branding", { branding: { logo_data_url: 'data:image/png;base64,x" onerror="alert(1)' } }, token);
    const r = await post("salvar_branding", { branding: { logo_data_url: LOGO_LEGITIMO } }, token);
    const body = await r.json();
    expect(body.branding.logo_data_url).toBe(LOGO_LEGITIMO);
  });

  it("a string vazia continua sendo o caminho de limpeza do logo", async () => {
    const token = await tokenDeAdmin();
    const r = await post("salvar_branding", { branding: { logo_data_url: "" } }, token);
    const body = await r.json();
    expect(body.branding.logo_data_url).toBe("");
  });
});
