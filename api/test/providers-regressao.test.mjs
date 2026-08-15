import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// Regressão dos achados da auditoria de 15/08/2026:
//  OPENROUTER-ORFAO1: o call site orfao de chamarOpenRouter (funcao removida no
//    v4.9.180, OPENROUTER-DEAD) fazia o probe do Perplexity falhar com
//    ReferenceError engolido por verificarHealthProvider, status sempre
//    "erro_desconhecido", e classificarNivelAlerta voltava nivel >= "amarelo"
//    com email de alerta falso de providers. Probe desligado por design:
//    perplexity agora e constante { status: "removido" }.
//  NOTIFYRL1: notificar_rotina exige routine_key e falha fechado (403) sem ela,
//    antes de qualquer rate limit ou efeito.

describe("admin_verificar_providers (OPENROUTER-ORFAO1)", () => {
  it("marca o probe do Perplexity como removido, nunca erro_desconhecido", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "admin_verificar_providers",
        admin_senha: "test-admin-password-nao-usar-em-producao",
      }),
    });
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.status).toBeTruthy();
    expect(body.status.perplexity.status).toBe("removido");
    expect(body.status.perplexity.codigo_ultimo_erro).toBeNull();
  });
});

describe("notificar_rotina (NOTIFYRL1)", () => {
  it("retorna 403 sem routine_key (fail-closed, sem efeito)", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "notificar_rotina",
        rotina: "teste",
        motivo: "sem chave",
      }),
    });
    expect(res.status).toBe(403);
  });
});
