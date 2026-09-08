import { describe, expect, it } from "vitest";
import { montarEmailAlertaCritico } from "../src/worker.js";

// Achado confirmado em admin_upsert_analise (auditoria 2026-09-07): o payload
// (body.payload.eventos) chega a dispararAlertaCritico -> montarEmailAlertaCritico
// sem a sanitizacao usada nos demais e-mails do sistema (compartilhamento,
// briefing), permitindo HTML/JS arbitrario no e-mail de alerta enviado via Resend.
// titulo, evento e impacto_credito eram interpolados crus no HTML.

const EVENTO_MALICIOSO = {
  classificacao: "CRITICO",
  titulo: '<img src=x onerror=alert(1)>Rebaixamento',
  evento: '<script>alert(document.cookie)</script>Fato relevante',
  impacto_credito: '"><svg onload=alert(2)>Piora no rating'
};

describe("XSS em montarEmailAlertaCritico (admin_upsert_analise)", () => {
  it("escapa titulo, evento e impacto_credito no HTML do alerta", () => {
    const html = montarEmailAlertaCritico("Empresa Teste", [EVENTO_MALICIOSO], "2026-09-07");
    expect(html).not.toContain("<script>");
    expect(html).not.toContain("<img src=x onerror=alert(1)>");
    expect(html).not.toContain("<svg onload=alert(2)>");
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(html).toContain("&lt;svg onload=alert(2)&gt;");
  });

  it("caminho feliz continua legivel, sem escapar texto normal", () => {
    const html = montarEmailAlertaCritico("Empresa Teste", [{
      classificacao: "CRITICO",
      titulo: "Rebaixamento de rating",
      evento: "Agencia rebaixou a nota de credito da empresa",
      impacto_credito: "Piora no custo de capital"
    }], "2026-09-07");
    expect(html).toContain("Rebaixamento de rating");
    expect(html).toContain("Agencia rebaixou a nota de credito da empresa");
    expect(html).toContain("Piora no custo de capital");
  });
});
