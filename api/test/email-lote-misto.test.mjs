import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// EMAILSILENT1 residual (2026-09-11): `enviarResend` engolia falha por
// destinatario quando `destArray.length > 1` e retornava so
// `{ batch: true, enviados: N, ids: [...] }`. Lote de 2 com 1 falha saia
// indistinguivel de lote 2/2 no sucesso. A correcao preserva os sucessos e
// acrescenta `falhas`, `total` e `erros` com o destinatario perdido.
//
// O endpoint admin `email_enviar` e a ponta observavel deste contrato. O mock de
// api.resend.com em vitest.config.mts reprova deterministicamente qualquer
// destinatario em @falha-envio.example (422, como a recusa real de dominio) e
// aprova os demais com id "mock-resend-id-0001".

const ADMIN_SENHA = "test-admin-password-nao-usar-em-producao";
let seqIp = 0;
function ipUnico() { seqIp++; return `203.0.113.${90 + seqIp}`; }

function enviar(destinatarios) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ipUnico() },
    body: JSON.stringify({
      action: "email_enviar",
      admin_senha: ADMIN_SENHA,
      assunto: "Teste determinístico de lote",
      html: "<p>corpo de teste</p>",
      destinatarios,
    }),
  });
}

describe("EMAILSILENT1 residual: enviarResend preserva sucessos e reporta falhas", () => {
  it("SUCESSO: lote inteiro bom informa enviados=2 e falhas=0", async () => {
    const r = await enviar(["lote-bom-1@example.com", "lote-bom-2@example.com"]);
    expect(r.status).toBe(200);
    const body = await r.json();
    expect(body.ok).toBe(true);
    expect(body.enviado).toBe(true);
    expect(body.enviados).toBe(2);
    expect(body.falhas).toBe(0);
    expect(body.ids.length).toBe(2);
    expect(body.erros).toEqual([]);
  });

  it("FALHA: um unico destinatario recusado ainda falha fechado no endpoint", async () => {
    const r = await enviar(["lote-ruim@falha-envio.example"]);
    expect(r.status).toBe(500);
    const body = await r.json();
    expect(body.ok).toBe(false);
    expect(body.erro).toBe("Falha ao enviar email.");
    expect(String(body.detalhe)).toContain("422");
  });

  it("FALHA TOTAL: lote sem nenhum sucesso nao vira 207 parcial", async () => {
    const r = await enviar(["lote-total-ruim-1@falha-envio.example", "lote-total-ruim-2@falha-envio.example"]);
    expect(r.status).toBe(500);
    const body = await r.json();
    expect(body.ok).toBe(false);
    expect(body.enviado).toBe(false);
    expect(body.enviados).toBe(0);
    expect(body.falhas).toBe(2);
    expect(body.total).toBe(2);
    expect(body.ids).toEqual([]);
    expect(body.erros).toHaveLength(2);
    expect(r.status).not.toBe(207);
  });

  it("LOTE MISTO: o sucesso continua contabilizado e a falha nomeia o destinatario perdido", async () => {
    const r = await enviar(["lote-misto-ok@example.com", "lote-misto-ruim@falha-envio.example"]);
    expect(r.status).toBe(207);
    const body = await r.json();

    expect(body.ok).toBe(false);
    expect(body.enviado).toBe(false);
    expect(body.enviados).toBe(1);
    expect(body.falhas).toBe(1);
    expect(body.total).toBe(2);
    expect(body.ids).toEqual(["mock-resend-id-0001"]);
    expect(body.erros).toHaveLength(1);
    expect(body.erros[0].destinatario).toBe("lote-misto-ruim@falha-envio.example");
    expect(String(body.erros[0].erro)).toContain("422");
  });
});