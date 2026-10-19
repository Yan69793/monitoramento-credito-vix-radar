import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { avaliarFrescorCVM, gravarFonteCVMMeta } from "../src/worker.js";

// CVMLASTMOD1 (2026-10-19). Medido em producao: GET / devolvia
// cvm_fonte_last_modified:null com cvm_fonte_ultimo_sync_ok_em recente. A ingestao
// ENET (syncCVMAutomatico) grava o meta da fonte com ok:true e SEM os campos do ZIP,
// e o ramo ok:true de gravarFonteCVMMeta fazia spread do meta novo, apagando o
// Last-Modified do ultimo ZIP. Na Sentinela isso deixava `precisaSync` sempre
// verdadeiro (data do zip contra string vazia).
//
// Duas pontas: o meta da ENET (sem a chave) herda o anterior; o do ZIP (com a
// chave, inclusive null) continua decidindo. E o health expoe o marcador do acervo.

const META_KEY = "cvm:fonte_meta";
const ZIP_LM = "Sun, 18 Oct 2026 10:00:21 GMT";

async function lerMeta() {
  return env.RADAR_KV.get(META_KEY, "json");
}

async function seedZip() {
  await gravarFonteCVMMeta(env, {
    ok: true,
    sincronizado_em: "2026-10-18T13:00:00.000Z",
    last_modified: ZIP_LM,
    last_modified_iso: "2026-10-18",
    max_data_entrega: "2026-10-17",
    documentos: 1000,
    origem: "sync_automatico"
  });
}

const META_ENET = {
  ok: true,
  origem: "enetweb",
  base_presente: true,
  sincronizado_em: "2026-10-18T21:30:35.359Z",
  max_data_entrega: "2026-10-18",
  conteudo_sha256: "a".repeat(64),
  documentos: 10186
};

describe("CVMLASTMOD1 - Last-Modified do ZIP sobrevive a escrita da ENET", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
  });

  it("escrita ENET sem a chave herda last_modified e last_modified_iso do anterior", async () => {
    await seedZip();
    await gravarFonteCVMMeta(env, { ...META_ENET });
    const m = await lerMeta();
    expect(m.origem).toBe("enetweb");
    expect(m.last_modified).toBe(ZIP_LM);
    expect(m.last_modified_iso).toBe("2026-10-18");
    expect(m.conteudo_sha256).toBe("a".repeat(64));
    expect(m.ultimo_sync_ok_em).toBe("2026-10-18T21:30:35.359Z");
    const f = await avaliarFrescorCVM(env);
    expect(f.last_modified).toBe("2026-10-18");
  });

  it("escrita do ZIP com a chave decide, inclusive para null", async () => {
    await seedZip();
    await gravarFonteCVMMeta(env, { ok: true, sincronizado_em: "2026-10-19T13:00:00.000Z", last_modified: null, last_modified_iso: null, origem: "sync_automatico" });
    const m = await lerMeta();
    expect(m.last_modified).toBeNull();
    expect(m.last_modified_iso).toBeNull();
  });

  it("escrita do ZIP com valor novo substitui o anterior", async () => {
    await seedZip();
    await gravarFonteCVMMeta(env, { ok: true, sincronizado_em: "2026-10-25T13:00:00.000Z", last_modified: "Sun, 25 Oct 2026 10:00:00 GMT", last_modified_iso: "2026-10-25", origem: "sync_automatico" });
    const m = await lerMeta();
    expect(m.last_modified_iso).toBe("2026-10-25");
  });

  it("ENET sem anterior nao inventa data", async () => {
    await gravarFonteCVMMeta(env, { ...META_ENET });
    const m = await lerMeta();
    expect(m.last_modified ?? null).toBeNull();
    expect(m.last_modified_iso ?? null).toBeNull();
  });

  it("health expoe cvm_fonte_last_modified preservado e cvm_acervo_sha256 da ENET", async () => {
    await seedZip();
    await gravarFonteCVMMeta(env, { ...META_ENET });
    const res = await SELF.fetch("https://example.com/");
    expect(res.status).toBe(200);
    const h = await res.json();
    expect(h.cvm_fonte_last_modified).toBe("2026-10-18");
    expect(h.cvm_acervo_sha256).toBe("a".repeat(64));
  });
});
