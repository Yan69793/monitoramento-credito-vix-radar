import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { tokenFixture, tokenAdmin } from "./_auth-fixture.mjs";

// ADMINISO1 (2026-10-19): prova de que o servidor, e nao a interface, decide quem
// executa operacao administrativa. Usuario comum com sessao VALIDA, mesmo mandando
// no corpo campos que um cliente adulterado mandaria (role, is_admin, admin_email),
// nunca pode receber 2xx de uma action admin_*. Lista de actions extraida do
// proprio worker.js, para action nova nao ficar de fora sem ninguem perceber.

const ACTIONS_ADMIN = [
  "admin_aprovar", "admin_auto_login", "admin_corrigir_datas_cvm_kv", "admin_custo",
  "admin_cvm_quarentena", "admin_deduplicar_eventos_kv", "admin_documentos_cvm",
  "admin_email_envios", "admin_enviar_whatsapp", "admin_executar_batch",
  "admin_executar_batch_legado", "admin_executar_matinal", "admin_executar_predictive",
  "admin_frescor_cvm", "admin_health_check", "admin_kv_put", "admin_limpar_cache",
  "admin_listar", "admin_mercado", "admin_recalcular_anomalias", "admin_rejeitar",
  "admin_remover_data", "admin_resend_domain_add", "admin_resend_domain_list",
  "admin_resend_domain_verify", "admin_resend_webhook_create", "admin_reset_senha",
  "admin_sanear_calendario", "admin_sweep_revalidacao", "admin_sync_cvm",
  "admin_sync_cvm_auto", "admin_sync_mercado", "admin_ui_track_listar", "admin_ui_track_set",
  "admin_upload_dados_privados", "admin_upsert_analise", "admin_verif_orfao_resolver",
  "admin_verif_resolver", "admin_verif_tentativa_limpar", "admin_verif_tentativas",
  "admin_verificar_evento", "admin_verificar_providers",
];

let seqIp = 0;
function post(body, token) {
  seqIp += 1;
  const headers = { "Content-Type": "application/json", "CF-Connecting-IP": `203.0.113.${(seqIp % 250) + 1}` };
  if (token) headers.Authorization = "Bearer " + token;
  return SELF.fetch("https://example.com/", { method: "POST", headers, body: JSON.stringify(body) });
}

const FORJADO = { role: "admin", is_admin: true, admin: true, usuario: { role: "admin" } };

describe("ADMINISO1: usuario comum nao executa operacao administrativa", () => {
  it("a lista do teste cobre todas as actions admin_* do worker", async () => {
    const fonte = (await import("../src/worker.js?raw")).default;
    const achadas = new Set([...fonte.matchAll(/action === "(admin_[a-z_0-9]+)"/g)].map((m) => m[1]));
    const faltando = [...achadas].filter((a) => !ACTIONS_ADMIN.includes(a));
    expect(faltando).toEqual([]);
  });

  for (const action of ACTIONS_ADMIN) {
    it(`${action}: sessao de usuario comum com papel forjado nao passa`, async () => {
      const token = await tokenFixture(`comum.${action}@example.com`);
      const r = await post({ action, ...FORJADO, email: "alvo@example.com", nova_senha: "12345678" }, token);
      expect(r.status, `${action} devolveu ${r.status}`).toBeGreaterThanOrEqual(400);
      expect(r.status).toBeLessThan(500);
    });
  }

  it("sem sessao nenhuma, admin_listar recusa", async () => {
    const r = await post({ action: "admin_listar", ...FORJADO });
    expect([401, 403]).toContain(r.status);
  });

  it("senha de admin errada continua recusada com sessao de usuario comum", async () => {
    const token = await tokenFixture("comum.senha-errada@example.com");
    const r = await post({ action: "admin_listar", admin_senha: "errada" }, token);
    expect(r.status).toBe(403);
  });

  it("ponta boa: a senha de admin correta ainda abre admin_listar", async () => {
    const r = await post({ action: "admin_listar", admin_senha: env.ADMIN_PASSWORD });
    expect(r.status).toBe(200);
    expect((await r.json()).ok).toBe(true);
  });

  it("ponta boa: sessao do admin real nao e barrada pelo mesmo teste", async () => {
    const token = await tokenAdmin();
    const r = await post({ action: "admin_listar", admin_senha: env.ADMIN_PASSWORD }, token);
    expect(r.status).toBe(200);
  });
});
