import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// CVMFRESCOR1 (auditoria 2026-08-19).
//
// De 14/08 a 19/08 o Painel de Eventos ficou congelado em 14/08 e TODO semaforo
// do sistema permaneceu verde. A causa primaria foi externa, a CVM parou de
// publicar (ipe/fre/itr_cia_aberta_2026 com Last-Modified de 2026-08-16 no
// servidor da propria CVM), mas o motivo de ninguem ver foi interno: nenhuma
// camada media frescor de DADO, todas mediam se o escritor rodou.
//   - heartbeat:sync_cvm ficava "ok" porque a funcao retornava sem lancar, e
//     baixar um arquivo que nao mudou e um sucesso perfeito;
//   - frescor-check.yml validava estado_semanal.updated_at, que fica verde com
//     conteudo reciclado, ja que a rotina escreve todo dia;
//   - a tira de fontes do rodape do frontend e HTML estatico com classe "ok".
//
// Estes testes travam o contrato novo: a idade da fonte CVM entra no _okHealth
// e e fail-closed. Se alguem afrouxar isso, o CI reprova antes do deploy.

const META_KEY = "cvm:fonte_meta";

function diasAtrasISO(n) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

async function health() {
  const res = await SELF.fetch("https://example.com/");
  expect(res.status).toBe(200);
  return res.json();
}

async function seedMeta(meta) {
  await env.RADAR_KV.put(META_KEY, JSON.stringify(meta));
}

describe("CVMFRESCOR1 - idade da fonte CVM no health", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
  });

  it("fail-closed: sem cvm:fonte_meta a fonte NAO conta como fresca", async () => {
    // Este e o caso que mais importa. A tentacao de fazer meta ausente valer
    // como "ok" para nao incomodar no primeiro deploy e exatamente como o
    // sistema ficou cego antes. Ausencia de sinal nao e sinal de saude.
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.cvm_fonte_motivo).toBe("sem_meta");
    expect(b.ok).toBe(false);
  });

  it("fonte publicada hoje conta como fresca e o health volta a ok:true", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified: "irrelevante para o calculo",
      last_modified_iso: diasAtrasISO(0),
      max_data_entrega: diasAtrasISO(0),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.cvm_fonte_idade_du).toBe(0);
    expect(b.ok).toBe(true);
  });

  it("fonte parada ha 30 dias derruba cvm_fonte_ok e o ok agregado", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(30),
      max_data_entrega: diasAtrasISO(30),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.cvm_fonte_idade_du).toBeGreaterThan(2);
    expect(String(b.cvm_fonte_motivo)).toMatch(/^fonte_parada_ha_\d+_dias_uteis$/);
    expect(b.ok).toBe(false);
  });

  it("ultimo sync com falha derruba mesmo com data recente na meta", async () => {
    // O sync pode falhar DEPOIS de ler o Last-Modified (arquivo corrompido,
    // metodo de compressao trocado). Data recente nao pode salvar um sync que
    // nao chegou a gravar documento nenhum.
    await seedMeta({
      ok: false,
      motivo: "nao_e_deflate",
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(0),
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(String(b.cvm_fonte_motivo)).toContain("ultimo_sync_falhou");
    expect(b.ok).toBe(false);
  });

  it("meta sem nenhuma data utilizavel nao passa por omissao", async () => {
    await seedMeta({ ok: true, sincronizado_em: new Date().toISOString(), documentos: 5, origem: "teste" });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(false);
    expect(b.cvm_fonte_motivo).toBe("sem_data_de_referencia");
    expect(b.ok).toBe(false);
  });

  it("cai para max_data_entrega quando o servidor nao manda Last-Modified", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified: null,
      last_modified_iso: null,
      max_data_entrega: diasAtrasISO(0),
      documentos: 120,
      origem: "teste"
    });
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
    expect(b.ok).toBe(true);
  });
});

describe("CVMFRESCOR1 - endpoints admin de frescor", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
  });

  function postAdmin(action, extra) {
    return SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, admin_senha: env.ADMIN_PASSWORD, ...extra }),
    });
  }

  it("admin_frescor_cvm exige senha", async () => {
    const res = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "admin_frescor_cvm", admin_senha: "errada" }),
    });
    expect(res.status).toBe(403);
  });

  it("admin_frescor_cvm devolve o diagnostico sem mexer no dado", async () => {
    await seedMeta({
      ok: true,
      sincronizado_em: new Date().toISOString(),
      last_modified_iso: diasAtrasISO(30),
      max_data_entrega: diasAtrasISO(30),
      origem: "teste"
    });
    const res = await postAdmin("admin_frescor_cvm", {});
    expect(res.status).toBe(200);
    const b = await res.json();
    expect(b.ok).toBe(true);
    expect(b.frescor.ok).toBe(false);
    expect(b.frescor.idade_du).toBeGreaterThan(2);
  });

  it("admin_sync_cvm manual carimba a meta em vez de deixar invariante quebrada", async () => {
    // Antes deste fix, a carga manual sobrescrevia cvm:documentos e deixava a
    // meta apontando para o sync automatico anterior. Health passaria a medir
    // a idade de um dado que nao existe mais.
    const hoje = diasAtrasISO(0);
    const res = await postAdmin("admin_sync_cvm", {
      documentos: [{ e: "TESTE S.A.", d: hoje, de: hoje, c: "Fato Relevante", a: "assunto", l: "https://exemplo" }]
    });
    expect(res.status).toBe(200);
    const meta = await env.RADAR_KV.get(META_KEY, "json");
    expect(meta).toBeTruthy();
    expect(meta.origem).toBe("admin_manual");
    expect(meta.max_data_entrega).toBe(hoje);
    const b = await health();
    expect(b.cvm_fonte_ok).toBe(true);
  });
});
