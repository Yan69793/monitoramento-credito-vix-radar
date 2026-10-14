import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { tokenAdmin, tokenFixture } from "./_auth-fixture.mjs";

// ADDPREVIEWCORS1 (2026-10-14, v4.9.268): a origem do preview de homologacao do
// frontend v2 entra na ALLOWED_ORIGINS do Worker.
//
// Defeito medido em producao antes da correcao: o preflight OPTIONS vindo de
// https://ui-v2-preview.radar-credito.pages.dev respondia 204 com `Vary: Origin`
// e NENHUM Access-Control-Allow-Origin, entao o navegador bloqueava toda leitura
// e o preview nao autenticava com credencial nenhuma, em nenhuma conta.
//
// Prova de DUAS PONTAS, como manda a regra 5 das regras de auditoria:
//   - a origem nova PASSA a receber o cabecalho;
//   - origem fora da lista CONTINUA sem o cabecalho, inclusive a impostora que
//     apenas CONTEM a origem permitida como prefixo. `corsHeaders` usa
//     ALLOWED_ORIGINS.includes(origin), ou seja igualdade exata: nao ha wildcard
//     e nao ha match por substring. Se alguem trocar por startsWith/endsWith/
//     indexOf, o caso do sufixo impostor reprova aqui;
//   - as quatro origens que ja existiam seguem aceitas (o commit nao pode ter
//     trocado a lista, so acrescentado a ela);
//   - e o cabecalho NAO concede privilégio: autenticacao e autorizacao
//     continuam identicas para a origem nova.
const PREVIEW = "https://ui-v2-preview.radar-credito.pages.dev";
const ORIGENS_EXISTENTES = [
  "https://vixradar.com",
  "https://www.vixradar.com",
  "https://radar-credito.pages.dev",
  "https://radar-credito-staging.pages.dev"
];

// Um IP por requisicao: o gate de rate limit anonimo e por identidade `ip:<ip>`
// e repetir o mesmo IP estouraria o burst dentro do arquivo (ver rate-limit.test.mjs).
let ipSeq = 0;
function proxIp() {
  ipSeq += 1;
  return "192.0.2." + (ipSeq % 250);
}

async function preflight(origin) {
  const headers = {
    "CF-Connecting-IP": proxIp(),
    "Access-Control-Request-Method": "GET",
    "Access-Control-Request-Headers": "authorization"
  };
  if (origin) headers.Origin = origin;
  return SELF.fetch("https://example.com/?op=calendario", { method: "OPTIONS", headers });
}

describe("ALLOWED_ORIGINS: origem do preview (ADDPREVIEWCORS1)", () => {
  it("ponta boa: a origem do preview recebe Access-Control-Allow-Origin", async () => {
    const res = await preflight(PREVIEW);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(PREVIEW);
    expect(res.headers.get("Vary")).toContain("Origin");
    expect(res.headers.get("Access-Control-Allow-Credentials")).toBe("true");
  });

  it("sem regressao: as quatro origens que ja existiam continuam aceitas", async () => {
    for (const o of ORIGENS_EXISTENTES) {
      const res = await preflight(o);
      expect(res.headers.get("Access-Control-Allow-Origin"), o).toBe(o);
    }
  });

  it("ponta ruim: origem desconhecida nao recebe o cabecalho", async () => {
    const res = await preflight("https://atacante.example");
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("ponta ruim: origem permitida usada como PREFIXO, com sufixo impostor, e recusada", async () => {
    const res = await preflight(PREVIEW + ".atacante.example");
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("ponta ruim: sem cabecalho Origin nao ha Access-Control-Allow-Origin", async () => {
    const res = await preflight(null);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });
});

describe("ADDPREVIEWCORS1: a origem nova nao ganha privilegio nenhum", () => {
  it("anonimo do preview continua 401 na leitura autenticada", async () => {
    const res = await SELF.fetch("https://example.com/?op=dados_privados", {
      headers: { Origin: PREVIEW, "CF-Connecting-IP": proxIp() }
    });
    expect(res.status).toBe(401);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(PREVIEW);
  });

  it("token real obtido do preview entra normalmente (controle positivo)", async () => {
    const token = await tokenFixture("cors-preview@example.com");
    const res = await SELF.fetch("https://example.com/?op=dados_privados", {
      headers: { Origin: PREVIEW, Authorization: "Bearer " + token, "CF-Connecting-IP": proxIp() }
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(PREVIEW);
  });

  it("token comum nao vira admin so por vir da origem do preview", async () => {
    const token = await tokenFixture("cors-preview-comum@example.com");
    const res = await SELF.fetch("https://example.com/?op=admin_assets", {
      headers: { Origin: PREVIEW, Authorization: "Bearer " + token, "CF-Connecting-IP": proxIp() }
    });
    expect(res.status).toBe(403);
  });

  it("token admin continua atravessando o portao admin pela origem do preview", async () => {
    const token = await tokenAdmin();
    const res = await SELF.fetch("https://example.com/?op=admin_assets", {
      headers: { Origin: PREVIEW, Authorization: "Bearer " + token, "CF-Connecting-IP": proxIp() }
    });
    // 200 com assets configurados, 404 sem: os dois significam que passou do
    // portao de autorizacao, que e o que este caso mede.
    expect([200, 404]).toContain(res.status);
  });

  it("escrita anonima a partir do preview continua negada", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: PREVIEW, "CF-Connecting-IP": proxIp() },
      body: JSON.stringify({ action: "receber_analise", empresa: "Dasa" })
    });
    expect([401, 403]).toContain(res.status);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(PREVIEW);
  });
});
