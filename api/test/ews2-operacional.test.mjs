import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";
import { EMAIL_FIXTURE, tokenFixture } from "./_auth-fixture.mjs";
import estadoW35 from "./fixtures/estado-2026-W35.json" with { type: "json" };
import anomalias from "./fixtures/anomalias.json" with { type: "json" };

// EWS2OPER1 (2026-10-18, nota 126): sinais estruturais do EWS 2.0 no EWS do cliente, atras de flag. Duas pontas:
// sem flag, flag desligada ou payload com hash de nota errado, a resposta e a de antes; com tudo valido, acrescenta ews2.
const NOTA = "950c7b0404ff900877f161840ea0a601711860ba67baa4ae09f6e554900138c5";
const payload = (sha = NOTA, data = "2026-08-28") => ({
  schema: "ews2/1", sha256_rotulos: "c".repeat(64), homologacao: { g1a: false, g1b: false, g1c: true, g2: false, g3: false },
  liberacao: { modo: "operacional_por_decisao_do_operador", nota_sha256: sha }, sinais_aprovados: ["H1", "H6"], exibir_probabilidade: false,
  data_observacao: data, emissores: [{ cnpj: "x", nome: "Raízen", sinais: { H1: 1, H6: 1 }, prob_180d: null, severidade: "alta" }],
});

let token;
beforeEach(async () => {
  await bootstrapIndiceQuarentena(env);
  fixarRelogioDoFixture();
  await env.RADAR_KV.put("radar:estado:2026-W35", JSON.stringify(estadoW35));
  await env.RADAR_KV.put("mercado:anomalias:ativas", JSON.stringify(anomalias));
  token = await tokenFixture(EMAIL_FIXTURE);
});
afterEach(async () => {
  soltarRelogio();
  for (const k of ["ews2:latest", "ews2:flag"]) await env.RADAR_KV.delete(k);
});

async function ews(empresa) {
  const q = empresa ? `&empresa=${encodeURIComponent(empresa)}` : "";
  const r = await SELF.fetch(`https://exemplo.invalid/?op=ews${q}`, { headers: { Authorization: `Bearer ${token}` } });
  expect(r.status).toBe(200);
  return r.json();
}

describe("EWS2OPER1: EWS 2.0 no EWS do cliente, fail-closed", () => {
  it("sem flag a resposta nao ganha ews2", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload()));
    const j = await ews("Raízen");
    expect(j.ews.ews2).toBeUndefined();
  });
  it("flag desligada nao expoe", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload()));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: false }));
    expect((await ews("Raízen")).ews.ews2).toBeUndefined();
  });
  it("hash de nota errado nao expoe mesmo com flag ligada", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload("0".repeat(64))));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    expect((await ews("Raízen")).ews.ews2).toBeUndefined();
  });
  it("flag ligada e payload valido anexam ews2 sem mexer no score", async () => {
    const antes = (await ews("Raízen")).ews;
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload()));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    const depois = (await ews("Raízen")).ews;
    expect(depois.ews2).toEqual({ severidade: "alta", sinais: { H1: 1, H6: 1 }, data_observacao: "2026-08-28" });
    const { ews2: _x, ...resto } = depois;
    expect(resto).toEqual(antes);
  });
  it("pacote com mais de 14 dias some sozinho (EWS2IDADE1), mesmo com flag ligada", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload(NOTA, "2026-08-15")));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    expect((await ews("Raízen")).ews.ews2).toBeUndefined();
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload(NOTA, "2026-08-16")));
    expect((await ews("Raízen")).ews.ews2.severidade).toBe("alta");
  });
  it("ranking ganha ews2 so no emissor do payload", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(payload()));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    const j = await ews();
    const rai = j.ranking.find((x) => x.empresa === "Raízen");
    expect(rai && rai.ews2 && rai.ews2.severidade).toBe("alta");
    expect(j.ranking.filter((x) => x.ews2).length).toBe(1);
  });
});
