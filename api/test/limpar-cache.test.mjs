import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// LIMPARCACHE2 (v4.9.274): admin_limpar_cache so apaga o estado da semana com
// confirmacao explicita "LIMPAR <semana>". Incidente 2026-10-18: um clique sem
// aviso apagou radar:estado:2026-W42 e o painel voltou a mostrar a data de 11/10.
const SENHA = "test-admin-password-nao-usar-em-producao";

function limpar(extra = {}, ip = "203.0.113.120") {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ action: "admin_limpar_cache", admin_senha: SENHA, ...extra }),
  });
}

async function semanaAtual() {
  const r = await limpar();
  const b = await r.json();
  return b.semana;
}

async function semear(semana) {
  await env.RADAR_KV.put(
    `radar:estado:${semana}`,
    JSON.stringify({ week: semana, results: { "Empresa A": { eventos: [] }, "Empresa B": { eventos: [] } }, updated_at: "2026-10-17T14:10:58.000Z" })
  );
}

describe("admin_limpar_cache com confirmacao (LIMPARCACHE2)", () => {
  it("sem confirmar: responde 409 e NAO apaga o estado", async () => {
    const semana = await semanaAtual();
    await semear(semana);
    const r = await limpar();
    expect(r.status).toBe(409);
    const b = await r.json();
    expect(b.ok).toBe(false);
    expect(b.codigo).toBe("CONFIRMACAO_OBRIGATORIA");
    expect(b.n_empresas).toBe(2);
    expect(b.confirmar_com).toBe(`LIMPAR ${semana}`);
    expect(await env.RADAR_KV.get(`radar:estado:${semana}`)).not.toBeNull();
  });

  it("confirmacao errada: 409 e estado intacto", async () => {
    const semana = await semanaAtual();
    await semear(semana);
    const r = await limpar({ confirmar: "LIMPAR 1999-W01" }, "203.0.113.121");
    expect(r.status).toBe(409);
    expect(await env.RADAR_KV.get(`radar:estado:${semana}`)).not.toBeNull();
  });

  it("senha errada: 403 mesmo com confirmacao correta", async () => {
    const semana = await semanaAtual();
    await semear(semana);
    const r = await limpar({ admin_senha: "errada", confirmar: `LIMPAR ${semana}` }, "203.0.113.122");
    expect(r.status).toBe(403);
    expect(await env.RADAR_KV.get(`radar:estado:${semana}`)).not.toBeNull();
  });

  it("confirmacao correta: arquiva antes, grava auditoria com a chave do arquivo e so entao apaga", async () => {
    const semana = await semanaAtual();
    await semear(semana);
    const r = await limpar({ confirmar: `LIMPAR ${semana}` }, "203.0.113.123");
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.ok).toBe(true);
    expect(b.n_empresas).toBe(2);
    expect(b.arquivo).toMatch(new RegExp(`^radar:arquivo:${semana}:\\d+$`));

    expect(await env.RADAR_KV.get(`radar:estado:${semana}`)).toBeNull();
    const arq = JSON.parse(await env.RADAR_KV.get(b.arquivo));
    expect(Object.keys(arq.results)).toEqual(["Empresa A", "Empresa B"]);
    expect(arq.updated_at).toBe("2026-10-17T14:10:58.000Z");

    const audits = await env.RADAR_KV.list({ prefix: "audit:limpar_cache:" });
    const ultimo = JSON.parse(await env.RADAR_KV.get(audits.keys.at(-1).name));
    expect(ultimo.arquivo).toBe(b.arquivo);
    expect(ultimo.n_empresas).toBe(2);
  });
});
