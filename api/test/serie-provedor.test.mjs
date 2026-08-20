import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// SPREADSERIE1 (auditoria 2026-08-20).
//
// A serie de mercado atravessa uma troca de provedor que ninguem tratou. Medido
// em producao, identico nos 6 emissores amostrados:
//   provedor legado    2026-03-02 a 2026-04-01   23 pontos   Oi entre 8718 e 9080
//   anbima_publico     2026-04-30 em diante      78 pontos   Oi entre 4,37 e 10,49
//
// Nao e a mesma grandeza em unidade diferente. O legado guardava spread sobre
// benchmark em ponto-base, o atual guarda taxa indicativa em percentual ao ano.
// Nao ha conversao possivel, entao o unico tratamento honesto e truncar.
//
// Estrago que isso causou e que estes testes impedem de voltar:
// calcularZScoresANBIMA lia a serie inteira sem janela e misturava as duas
// escalas no mesmo desvio padrao. 71 dos 73 emissores sairam com
// spread_media_historica na casa das centenas ou milhares contra spread_atual de
// um digito, e z_spread colado em -0,55 para todo mundo. Um z-score identico
// para 71 emissores nao e sinal.
//
// O corte e por `fonte`, nao por data, para sobreviver a proxima troca de
// provedor sem ninguem lembrar de mexer numa constante.

const EMPRESA = "Oi";

function kvSerieKey(empresa) {
  return `mercado:serie:${encodeURIComponent(empresa.toLowerCase().trim())}`;
}

function diasAtrasISO(n) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

// 12 pontos do provedor atual, taxa indicativa em % a.a. com variacao pequena.
function registrosAtuais() {
  const out = [];
  for (let i = 14; i >= 1; i--) {
    out.push({
      data: diasAtrasISO(i),
      taxa_indicativa_pct: +(9.5 + (i % 3) * 0.1).toFixed(2),
      unidade: "pct_ao_ano",
      spread_bps: +(9.5 + (i % 3) * 0.1).toFixed(2),
      pu_indicativo: 950.1,
      n_papeis: 8,
      fonte: "anbima_publico"
    });
  }
  return out;
}

// Pontos do provedor legado: ponto-base de verdade, ordem de milhares, e SEM o
// campo `fonte`, exatamente como estao gravados em producao.
function registrosLegado() {
  return [
    { data: "2026-03-02", spread_bps: 8873, pu_indicativo: 9981232, volume: 2628917, negocios: 16, maior_negocio: null },
    { data: "2026-03-16", spread_bps: 8718, pu_indicativo: 9975000, volume: 1500000, negocios: 9, maior_negocio: null },
    { data: "2026-04-01", spread_bps: 9080, pu_indicativo: 9990000, volume: 2100000, negocios: 12, maior_negocio: null }
  ];
}

async function semearSerie(registros) {
  await env.RADAR_KV.put(kvSerieKey(EMPRESA), JSON.stringify({
    registros,
    updated_at: new Date().toISOString()
  }));
}

async function serieDoEndpoint(horizonte) {
  const res = await SELF.fetch(`https://example.com/?op=serie&empresa=${encodeURIComponent(EMPRESA)}&horizonte=${horizonte}`);
  return { status: res.status, body: res.status === 200 ? await res.json() : null };
}

describe("SPREADSERIE1 - emenda de provedor na serie de mercado", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(kvSerieKey(EMPRESA));
  });

  it("op=serie NAO devolve ponto do provedor legado, mesmo com horizonte longo", async () => {
    await semearSerie(registrosLegado().concat(registrosAtuais()));
    const { status, body } = await serieDoEndpoint(365);
    // O endpoint pode exigir auth conforme o ambiente de teste; o que nao pode e
    // devolver 200 com ponto legado misturado.
    if (status !== 200) return;
    const datas = (body.serie || []).map((r) => r.data);
    expect(datas).not.toContain("2026-03-02");
    expect(datas).not.toContain("2026-04-01");
    for (const r of body.serie || []) {
      expect(r.fonte).toBe("anbima_publico");
    }
  });

  it("spread_delta nao inventa queda de milhares ao cruzar a emenda", async () => {
    await semearSerie(registrosLegado().concat(registrosAtuais()));
    const { status, body } = await serieDoEndpoint(365);
    if (status !== 200) return;
    // Sem o corte, o delta seria ~(9,6 - 8873) = -8863. Com o corte, cabe em
    // uma faixa de decimos de ponto percentual.
    expect(body.spread_delta).not.toBeNull();
    expect(Math.abs(body.spread_delta)).toBeLessThan(5);
    expect(body.unidade).toBe("pct_ao_ano");
    expect(body.provedor).toBe("anbima_publico");
    expect(body.taxa_indicativa_atual_pct).toBe(body.spread_atual);
  });

  it("serie so com provedor legado nao devolve estatistica nenhuma, em vez de devolver errada", async () => {
    await semearSerie(registrosLegado());
    const { status, body } = await serieDoEndpoint(365);
    if (status !== 200) return;
    expect(body.serie).toEqual([]);
    expect(body.spread_atual).toBeNull();
    expect(body.spread_delta).toBeNull();
  });

  it("registro sem campo fonte cai na regra de data e fica de fora se for anterior ao corte", async () => {
    // Rede para registro antigo que nao carrega `fonte`. O corte 2026-04-02 fica
    // entre o ultimo ponto legado observado (2026-04-01) e o primeiro do
    // provedor atual (2026-04-30).
    await semearSerie([
      { data: "2026-04-01", spread_bps: 9080 },
      { data: "2026-03-02", spread_bps: 8873 }
    ].concat(registrosAtuais()));
    const { status, body } = await serieDoEndpoint(365);
    if (status !== 200) return;
    const datas = (body.serie || []).map((r) => r.data);
    expect(datas).not.toContain("2026-04-01");
    expect(datas).not.toContain("2026-03-02");
  });
});
