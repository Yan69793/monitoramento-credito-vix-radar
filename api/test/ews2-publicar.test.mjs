import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";

// EWS2PUB1 (2026-10-18): publicacao do pacote EWS 2.0 pela rotina semanal no GitHub Actions, com a ROUTINE_API_KEY, sem
// token Cloudflare no CI. Duas pontas: o pacote bom grava e deixa o anterior de lado; chave errada, pacote ruim e qualquer
// tentativa de LIGAR a flag nao encostam em nada. Relogio congelado em 30/08/2026 (RELOGIOTESTE1).
const KEY = "test-routine-key-nao-usar-em-producao";
const NOTA = "950c7b0404ff900877f161840ea0a601711860ba67baa4ae09f6e554900138c5";

const emissores = (n = 104) => Array.from({ length: n }, (_, i) => ({
  cnpj: "00.000.000/%s-00".replace("%s", String(i).padStart(4, "0")), nome: "E" + i,
  sinais: { H1: i % 2, H5: null, H6: 0 }, prob_180d: null, severidade: ["alta", "media", "baixa"][i % 3],
}));
const pacote = (extra = {}) => ({
  schema: "ews2/1", protocolo: "G0-v4", gerado_em: "2026-08-29T10:00:00+00:00", data_observacao: "2026-08-28",
  sha256_rotulos: "c".repeat(64), homologacao: { g1a: false, g1b: false, g1c: true, g2: true, g3: false },
  liberacao: { modo: "operacional_por_decisao_do_operador", nota_sha256: NOTA },
  sinais_aprovados: ["H1", "H5", "H6"], exibir_probabilidade: false, emissores: emissores(), ...extra,
});

async function post(body, key = KEY) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.88" },
    body: JSON.stringify(Object.assign(key === null ? {} : { routine_key: key }, body)),
  });
}
const kv = async (k) => env.RADAR_KV.get(k, "json");

beforeEach(async () => { await bootstrapIndiceQuarentena(env); fixarRelogioDoFixture(); });
afterEach(async () => {
  soltarRelogio();
  for (const k of ["ews2:latest", "ews2:latest:anterior", "ews2:flag", "ews2:flag:anterior"]) await env.RADAR_KV.delete(k);
});

describe("EWS2PUB1 ews2_publicar", () => {
  it("sem chave ou com chave errada: 403 e KV intocado", async () => {
    for (const k of [null, "errada"]) {
      const r = await post({ action: "ews2_publicar", pacote: pacote() }, k);
      expect(r.status).toBe(403);
    }
    expect(await kv("ews2:latest")).toBeNull();
  });

  it("pacote valido grava, confere a releitura e guarda o anterior", async () => {
    const velho = pacote({ gerado_em: "2026-08-22T10:00:00+00:00", data_observacao: "2026-08-21" });
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(velho));
    const r = await post({ action: "ews2_publicar", pacote: pacote() });
    expect(r.status).toBe(200);
    const j = await r.json();
    expect(j).toMatchObject({ ok: true, gravado: true, releitura_confere: true, emissores: 104, data_observacao: "2026-08-28" });
    expect(j.anterior.data_observacao).toBe("2026-08-21");
    expect((await kv("ews2:latest")).gerado_em).toBe("2026-08-29T10:00:00+00:00");
    expect((await kv("ews2:latest:anterior")).data_observacao).toBe("2026-08-21");
    expect(await kv("ews2:flag")).toBeNull();            // publicar nunca encosta na flag
  });

  const ruins = {
    "nota com hash errado": () => pacote({ liberacao: { modo: "operacional_por_decisao_do_operador", nota_sha256: "0".repeat(64) } }),
    "sem liberacao": () => pacote({ liberacao: null }),
    "schema errado": () => pacote({ schema: "ews2/0" }),
    "probabilidade exibivel": () => pacote({ exibir_probabilidade: true }),
    "pacote velho (20 dias)": () => pacote({ data_observacao: "2026-08-10" }),
    "sem data": () => pacote({ data_observacao: null }),
    "data no futuro": () => pacote({ data_observacao: "2026-09-20" }),
    "103 emissores truncados para 50": () => pacote({ emissores: emissores(50) }),
    "cnpj duplicado": () => pacote({ emissores: [...emissores(103), emissores(1)[0]] }),
    "severidade invalida": () => pacote({ emissores: emissores().map((e, i) => (i === 0 ? { ...e, severidade: "critica" } : e)) }),
    "sinal fora de 0/1/null": () => pacote({ emissores: emissores().map((e, i) => (i === 0 ? { ...e, sinais: { H1: 2, H5: null, H6: 0 } } : e)) }),
  };
  for (const [nome, fazer] of Object.entries(ruins)) {
    it("reprova " + nome + " sem gravar", async () => {
      await env.RADAR_KV.put("ews2:latest", JSON.stringify(pacote({ gerado_em: "2026-08-22T10:00:00+00:00", data_observacao: "2026-08-21" })));
      const r = await post({ action: "ews2_publicar", pacote: fazer() });
      expect(r.status).toBe(400);
      expect((await r.json()).ok).toBe(false);
      expect((await kv("ews2:latest")).data_observacao).toBe("2026-08-21");     // o que estava continua
      expect(await kv("ews2:latest:anterior")).toBeNull();
    });
  }
});

describe("EWS2PUB1 ews2_flag_desligar e ews2_estado", () => {
  it("desliga, guarda a flag anterior e nao tem caminho para ligar", async () => {
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    const r = await post({ action: "ews2_flag_desligar", motivo: "teste: EWS atual melhor", relatorio: "logs/x.json", ativo: true });
    expect(r.status).toBe(200);
    const f = await kv("ews2:flag");
    expect(f.ativo).toBe(false);
    expect(f.origem).toBe("conferencia_automatica");
    expect(f.motivo).toBe("teste: EWS atual melhor");
    expect((await kv("ews2:flag:anterior")).ativo).toBe(true);
  });

  it("sem motivo ou sem chave: recusa e a flag fica como estava", async () => {
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    expect((await post({ action: "ews2_flag_desligar" })).status).toBe(400);
    expect((await post({ action: "ews2_flag_desligar", motivo: "x" }, "errada")).status).toBe(403);
    expect((await kv("ews2:flag")).ativo).toBe(true);
  });

  it("estado mostra o pacote e a flag sem expor os emissores", async () => {
    await env.RADAR_KV.put("ews2:latest", JSON.stringify(pacote()));
    await env.RADAR_KV.put("ews2:flag", JSON.stringify({ ativo: true }));
    const j = await (await post({ action: "ews2_estado" })).json();
    expect(j.latest).toEqual({ gerado_em: "2026-08-29T10:00:00+00:00", data_observacao: "2026-08-28", sinais_aprovados: ["H1", "H5", "H6"], emissores: 104 });
    expect(j.flag.ativo).toBe(true);
    expect((await post({ action: "ews2_estado" }, "errada")).status).toBe(403);
  });
});
