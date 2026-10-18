import { SELF, env } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
const url = "https://example.com/?op=predictive_v1";
const base = () => ({ modelo: "lab", emissores: [{ name: "Alfa", cnpj: "00.000.000/0001-00", predictive_v1: { score: 42 } }] });
// data_observacao de hoje: desde EWS2IDADE1 pacote sem data ou com mais de 14 dias nao e exibido.
const ews = () => ({ schema: "ews2/1", sha256_rotulos: "a".repeat(64), homologacao: { g1a: true, g1b: true, g1c: true, g2: true, g3: false }, sinais_aprovados: ["H1"], exibir_probabilidade: false, data_observacao: new Date().toISOString().slice(0, 10), emissores: [{ cnpj: "00.000.000/0001-00", nome: "Alfa", sinais: { H1: 1 }, prob_180d: 0.8 }] });
const seed = async (key, val) => env.RADAR_KV.put(key, JSON.stringify(val));
const query = async () => SELF.fetch(url, { headers: { "x-admin-password": env.ADMIN_PASSWORD } });
afterEach(async () => { for (const k of ["predictive_v1:latest", "ews2:latest", "ews2:flag"]) await env.RADAR_KV.delete(k); });
describe("EWS2SHADOW1 fail closed e somente admin", () => {
  it("sem login nao acessa o lab", async () => {
    await seed("predictive_v1:latest", base());
    expect((await SELF.fetch(url)).status).toBe(401);
  });
  it("flag ausente conserva a resposta legada e bloqueia EWS2", async () => {
    const x = base(); await seed("predictive_v1:latest", x);
    const response = await query(); expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.user_facing).toBe(false);
    expect(body.ews2.ativo).toBe(false);
    expect(body.emissores).toEqual(x.emissores);
  });
  it("flag desligada mesmo com dados nunca expoe o novo modelo", async () => {
    await seed("predictive_v1:latest", base());
    await seed("ews2:latest", ews()); await seed("ews2:flag", { ativo: false });
    const got = await (await query()).json();
    expect(got.ews2.ativo).toBe(false);
    expect(got.emissores[0].ews2).toBeUndefined();
  });
  it("flag ligada mas sem homologacao permanece bloqueada", async () => {
    const x = base(); await seed("predictive_v1:latest", x);
    await seed("ews2:latest", { ...ews(), homologacao: { g1a: false } });
    await seed("ews2:flag", { ativo: true });
    const got = await (await query()).json();
    expect(got.ews2.ativo).toBe(false);
    expect(got.emissores).toEqual(x.emissores);
  });
  it("homologacao artificial no teste somente: merge sem probabilidade G3", async () => {
    await seed("predictive_v1:latest", base());
    await seed("ews2:latest", ews()); await seed("ews2:flag", { ativo: true });
    const got = await (await query()).json();
    expect(got.ews2.ativo).toBe(true);
    expect(got.emissores[0].predictive_v1.score).toBe(42);
    expect(got.emissores[0].ews2.prob_180d).toBeNull();
  });
});
