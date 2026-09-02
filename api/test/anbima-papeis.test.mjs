import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  _grupoAnbima,
  _formatarTaxaDisplay,
  _selecionarDestaquePapeis,
  _probeJanelaAnbima,
  _agruparRegistrosAnbima,
  _mergePapeisSerie,
  _papeisNaDataReferencia,
  _familiasDosPapeis,
  parseANBIMATxt
} from "../src/worker.js";

// PAPEIS1 (2026-09-02): taxa indicativa ANBIMA por papel.
//
// O card "Taxa indicativa ANBIMA" exibia a media aritmetica diaria de
// `taxa_indicativa` de TODOS os papeis do emissor, rotulada "% a.a.". Na ENEVA
// dava ~5,91: media de 5 papeis DI+spread (~0,74) com 14 IPCA+ (~7,76), dois
// grupos que nao se somam. Estes testes travam a correcao: taxa persistida e
// servida por codigo_ativo, com natureza (grupo) derivada do indice_correcao,
// destaque por papel individual (pct_reune escalar, nunca soma), fail-closed
// para serie legada sem metadados, e o caminhante de fronteira do backfill
// que nao para em 404 isolado.

const JWT_SECRET = "test-jwt-secret-nao-usar-em-producao";
const EMPRESA = "Eneva";
const DATA_REF = "2026-08-28";

function kvSerieKey(empresa) {
  return `mercado:serie:${encodeURIComponent(empresa.toLowerCase().trim())}`;
}

// 19 linhas reais do arquivo publico ANBIMA db260828.txt (iso-8859-1), exatas
// no numero de `@` (as colunas pct_reune=13 e ref_ntnb=14 dependem disso).
const ENEVA_TXT = [
  "ENEV38@ENEVA S.A. (*)@15/07/2029@DI + 1,7%@1,1042@0,7405@0,9299@0,0432@0,8867@0,9732@1034,756887@101,5478@509,75@@",
  "ENEV48@ENEVA S.A. (*)@15/07/2032@DI + 2%@0,9638@0,641@0,8051@0,0378@0,7673@0,8431@1061,99556@104,182@880,37@@",
  "ENEVA3@ENEVA S.A. (*)@15/12/2029@DI + 0,9%@0,7656@0,5916@0,6846@0,0291@0,6555@0,7137@1036,452207@100,5653@665,03@@",
  "ENEVC0@ENEVA S.A. (*)@15/04/2029@DI + 1%@0,6731@0,5301@0,5815@0,0599@0,5216@0,6414@1064,27723@100,8937@540,32@5@",
  "ENEVD0@ENEVA S.A. (*)@15/04/2031@DI + 1,15%@0,8142@0,5628@0,6801@0,0557@0,6244@0,7359@1070,438486@101,4216@765,17@35@",
  "ENEV13@ENEVA S.A.@15/12/2027@IPCA + 4,2259%@6,6475@6,292@6,4277@0,0958@6,3319@6,5236@960,24281@98,4073@192,89@@15/05/2027",
  "ENEV15@ENEVA S.A.@15/06/2030@IPCA + 5,5%@7,8944@7,6105@7,7629@0,1003@7,6626@7,8634@1377,979142@94,7218@641,55@40@15/05/2029",
  "ENEV16@ENEVA S.A.@15/09/2030@IPCA + 4,127%@7,93@7,6754@7,7826@0,0559@7,7267@7,8386@1316,473854@90,8079@699,97@@15/05/2029",
  "ENEV18@ENEVA S.A. (*)@15/07/2032@IPCA + 6,5254%@8,1217@7,8731@7,9745@0,0831@7,8915@8,0577@1130,293634@94,524@1046,68@5@15/05/2031",
  "ENEV19@ENEVA S.A. (*)@15/09/2032@IPCA + 6,9%@8,1075@7,8727@7,9924@0,0785@7,9138@8,071@1184,190927@95,8494@1047,26@10@15/05/2031",
  "ENEV26@ENEVA S.A.@15/09/2035@IPCA + 4,5034%@8,0959@7,8671@8,0172@0,0774@7,9399@8,0947@1168,64024@80,478@1627,61@@15/05/2035",
  "ENEV28@ENEVA S.A. (*)@15/07/2037@IPCA + 6,5891%@7,9846@7,6614@7,8241@0,0844@7,7398@7,9086@1099,754689@91,9631@1816,6@@15/05/2037",
  "ENEV29@ENEVA S.A. (*)@15/09/2037@IPCA + 7%@8,0919@7,7655@7,9432@0,0978@7,8454@8,0411@1161,441768@93,9679@1772,42@@15/05/2035",
  "ENEV32@ENEVA S.A.@15/05/2029@IPCA + 5,05%@7,8497@7,5038@7,7551@0,0602@7,6949@7,8154@1430,015284@96,0254@399,83@35@15/08/2028",
  "ENEV39@ENEVA S.A. (*)@15/09/2042@IPCA + 7,15%@7,9715@7,5822@7,7834@0,059@7,7244@7,8425@1169,927169@94,594@2350,98@@15/08/2040",
  "ENEVA0@ENEVA S.A. (*)@15/04/2034@IPCA + 6,5643%@8,093@7,8782@7,983@0,0676@7,9155@8,0507@1059,722899@93,2344@1326,97@@15/05/2033",
  "ENEVA4@ENEVA S.A. (*)@15/01/2036@IPCA + 6,7078%@8,0173@7,8072@7,9024@0,0468@7,8556@7,9493@960,891444@92,5129@1748,08@10@15/05/2035",
  "ENEVB0@ENEVA S.A. (*)@15/04/2039@IPCA + 6,6737%@7,9423@7,6159@7,776@0,0629@7,7131@7,839@1047,527297@92,1262@1988,17@@15/05/2037",
  "ENEVB4@ENEVA S.A. (*)@15/01/2041@IPCA + 6,6709%@7,877@7,5912@7,7126@0,0714@7,6412@7,784@952,760362@91,7341@2209,91@10@15/08/2040"
].join("\n");

function parseTxt(txt) {
  return parseANBIMATxt(new TextEncoder().encode(txt));
}

function b64urlBytes(bytes) {
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function mintJwt(secret, payload) {
  const enc = new TextEncoder();
  const header = b64urlBytes(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64urlBytes(enc.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64urlBytes(new Uint8Array(sig))}`;
}

async function authHeaders() {
  const token = await mintJwt(JWT_SECRET, { email: "teste-papeis@example.com", exp: Math.floor(Date.now() / 1e3) + 3600 });
  return { Authorization: `Bearer ${token}` };
}

async function serieAuthed(empresa) {
  const res = await SELF.fetch(`https://example.com/?op=serie&empresa=${encodeURIComponent(empresa)}`, { method: "GET", headers: await authHeaders() });
  return { status: res.status, body: res.status === 200 ? await res.json() : null };
}

// Serie completa: registro legado (media diaria) + papeis montados a partir das
// 19 linhas reais, pelo mesmo caminho de producao (parse -> agrupar -> merge).
function serieEnevaCompleta() {
  const ag = _agruparRegistrosAnbima(parseTxt(ENEVA_TXT));
  const serie = {
    registros: [{ data: DATA_REF, taxa_indicativa_pct: 5.91, spread_bps: 5.91, unidade: "pct_ao_ano", n_papeis: 19, fonte: "anbima_publico" }],
    updated_at: "2026-08-28T00:00:00Z"
  };
  _mergePapeisSerie(serie, EMPRESA, ag.porEmpresa[EMPRESA].papeis, DATA_REF);
  return serie;
}

describe("PAPEIS1: unidade — grupo e formato", () => {
  it("_grupoAnbima classifica as 5 familias e OUTRO", () => {
    expect(_grupoAnbima("IPCA + 5,5%")).toBe("IPCA");
    expect(_grupoAnbima("IPCA + 4,2259%")).toBe("IPCA");
    expect(_grupoAnbima("DI + 1,7%")).toBe("DI_SPREAD");
    expect(_grupoAnbima("DI + 2%")).toBe("DI_SPREAD");
    expect(_grupoAnbima("114,65% do DI")).toBe("PCT_DI");
    expect(_grupoAnbima("100% do DI")).toBe("PCT_DI");
    expect(_grupoAnbima("PREFIXADO 16,762%")).toBe("PRE_FIXADO");
    expect(_grupoAnbima("IGP-M")).toBe("OUTRO");
    expect(_grupoAnbima("")).toBe("OUTRO");
  });

  it("_formatarTaxaDisplay formata pelo grupo e nunca inferiria natureza do numero", () => {
    expect(_formatarTaxaDisplay("DI_SPREAD", 1.7)).toBe("DI + 1,70%");
    expect(_formatarTaxaDisplay("PCT_DI", 102.8272)).toBe("102,83% do DI");
    expect(_formatarTaxaDisplay("IPCA", 7.7629)).toBe("IPCA + 7,76%");
    expect(_formatarTaxaDisplay("PRE_FIXADO", 17.2314)).toBe("17,23% a.a.");
    expect(_formatarTaxaDisplay("OUTRO", 5.0)).toBeNull();
    expect(_formatarTaxaDisplay("IPCA", null)).toBeNull();
    // o mesmo valor numerico nao pode ser formatado como se fosse outro grupo
    expect(_formatarTaxaDisplay("DI_SPREAD", 7.7629)).not.toBe(_formatarTaxaDisplay("IPCA", 7.7629));
  });
});

describe("PAPEIS1: ENEVA mista (5 DI + 14 IPCA), destaque por papel", () => {
  it("parse das 19 linhas reais gera 19 papeis (5 DI_SPREAD + 14 IPCA)", () => {
    const ag = _agruparRegistrosAnbima(parseTxt(ENEVA_TXT));
    expect(ag.porEmpresa[EMPRESA]).toBeTruthy();
    const papeis = ag.porEmpresa[EMPRESA].papeis;
    expect(papeis.length).toBe(19);
    expect(papeis.filter((p) => p.grupo === "DI_SPREAD").length).toBe(5);
    expect(papeis.filter((p) => p.grupo === "IPCA").length).toBe(14);
  });

  it("destaque por papel individual: ENEV15 (pct_reune 40), nunca soma nem media", () => {
    const serie = serieEnevaCompleta();
    const papeis = _papeisNaDataReferencia(serie, DATA_REF, "2026-06-01");
    expect(papeis.length).toBe(19);

    const sel = _selecionarDestaquePapeis(papeis);
    expect(sel.motivo).toBeNull();
    expect(sel.destaque.codigo_ativo).toBe("ENEV15");
    expect(sel.destaque.pct_reune).toBe(40);
    expect(sel.destaque.percentual_taxa).toBeCloseTo(7.7629, 4);
    expect(sel.destaque.taxa_display).toBe("IPCA + 7,76%");

    // guarda anti-agregacao (decisao do operador): somar pct_reune dos 19 papeis
    // daria 150, numero que nao pertence a ativo nenhum. O destaque e o escalar
    // maximo (40), nunca a soma.
    const soma = papeis.reduce((acc, p) => acc + (typeof p.pct_reune === "number" ? p.pct_reune : 0), 0);
    expect(soma).toBe(150);
    expect(sel.destaque.pct_reune).not.toBe(soma);

    // a taxa do destaque e a do papel, nao a media legada do emissor (~5,91)
    expect(sel.destaque.percentual_taxa).not.toBeCloseTo(5.91, 2);
  });

  it("familias agrupam sem campo de soma/liquidez (pct_reune e escalar por papel)", () => {
    const serie = serieEnevaCompleta();
    const papeis = _papeisNaDataReferencia(serie, DATA_REF, "2026-06-01");
    const fams = _familiasDosPapeis(papeis);
    expect(fams.map((f) => f.grupo)).toEqual(["IPCA", "DI_SPREAD"]);
    expect(fams[0].papeis.length).toBe(14);
    expect(fams[1].papeis.length).toBe(5);
    for (const f of fams) {
      expect(f.pct_reune).toBeUndefined();
      expect(f.liquidez).toBeUndefined();
      expect(f.soma).toBeUndefined();
      expect(f.total).toBeUndefined();
      // cada papel carrega o proprio escalar
      for (const p of f.papeis) {
        expect(p).toHaveProperty("codigo_ativo");
        expect(p).toHaveProperty("taxa_display");
      }
    }
  });

  it("sem nenhum pct_reune > 0, destaque null + motivo, papeis ainda listados", () => {
    const papeis = [
      { codigo_ativo: "X1", data_vencimento: "2030-01-01", percentual_taxa: 5.0, pct_reune: null, taxa_display: "IPCA + 5,00%" },
      { codigo_ativo: "X2", data_vencimento: "2031-01-01", percentual_taxa: 6.0, pct_reune: 0, taxa_display: "IPCA + 6,00%" }
    ];
    const sel = _selecionarDestaquePapeis(papeis);
    expect(sel.destaque).toBeNull();
    expect(sel.motivo).toBe("sem_liquidez_reune");
  });

  it("desempate determinístico: vencimento desc, depois codigo_ativo asc", () => {
    const base = (codigo, vencimento) => ({ codigo_ativo: codigo, data_vencimento: vencimento, percentual_taxa: 5.0, pct_reune: 10 });
    // mesmo pct_reune: vence o vencimento mais tardio
    const a = _selecionarDestaquePapeis([base("A", "2027-01-01"), base("B", "2028-01-01")]);
    expect(a.destaque.codigo_ativo).toBe("B");
    // mesmo pct_reune e mesmo vencimento: vence codigo asc
    const b = _selecionarDestaquePapeis([base("B", "2028-01-01"), base("A", "2028-01-01")]);
    expect(b.destaque.codigo_ativo).toBe("A");
  });
});

describe("PAPEIS1: persistencia por papel (merge idempotente)", () => {
  const papelA = { codigo_ativo: "ENEV15", data_vencimento: "2030-06-15", indice_original: "IPCA + 5,5%", grupo: "IPCA", percentual_taxa: 7.76, taxa_indicativa: 7.76, pct_reune: 40 };
  const papelB = { codigo_ativo: "ENEV32", data_vencimento: "2029-05-15", indice_original: "IPCA + 5,05%", grupo: "IPCA", percentual_taxa: 7.75, taxa_indicativa: 7.75, pct_reune: 35 };

  it("dois syncs em dias diferentes => 2 pontos por papel, sem contaminar outro papel", () => {
    const serie = { registros: [] };
    _mergePapeisSerie(serie, EMPRESA, [papelA, papelB], "2026-08-27");
    _mergePapeisSerie(serie, EMPRESA, [papelA, papelB], "2026-08-28");
    expect(serie.papeis["ENEV15"].historico.length).toBe(2);
    expect(serie.papeis["ENEV32"].historico.length).toBe(2);
    expect(serie.papeis["ENEV15"].historico.map((h) => h.data)).toEqual(["2026-08-27", "2026-08-28"]);
    // o historico de ENEV15 so tem pontos do proprio codigo
    for (const h of serie.papeis["ENEV15"].historico) expect(h.data).toBeTruthy();
  });

  it("mesmo dia reprocessado nao duplica ponto (idempotente)", () => {
    const serie = { registros: [] };
    _mergePapeisSerie(serie, EMPRESA, [papelA], "2026-08-28");
    _mergePapeisSerie(serie, EMPRESA, [papelA], "2026-08-28");
    expect(serie.papeis["ENEV15"].historico.length).toBe(1);
  });
});

describe("PAPEIS1: op=serie autenticado", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(kvSerieKey(EMPRESA));
  });

  it("entrega destaque/papeis/familias/data_referencia a partir do KV (caminho de producao)", async () => {
    await env.RADAR_KV.put(kvSerieKey(EMPRESA), JSON.stringify(serieEnevaCompleta()));
    const { status, body } = await serieAuthed(EMPRESA);
    expect(status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.data_referencia).toBe(DATA_REF);
    expect(body.papeis.length).toBe(19);
    expect(body.destaque.codigo_ativo).toBe("ENEV15");
    expect(body.destaque.taxa_display).toBe("IPCA + 7,76%");
    expect(body.destaque.pct_reune).toBe(40);
    expect(body.familias.map((f) => f.grupo)).toEqual(["IPCA", "DI_SPREAD"]);
    expect(body.destaque_motivo).toBeNull();
    // campos legados marcados como deprecados (nao expor no frontend)
    expect(body._legado_deprecado).toContain("spread_atual");
    expect(body._legado_deprecado).toContain("taxa_indicativa_atual_pct");
  });

  it("serie legada sem papeis falha fechado: papeis vazio, destaque null, nunca 5,91 (item 7)", async () => {
    await env.RADAR_KV.put(kvSerieKey(EMPRESA), JSON.stringify({
      registros: [{ data: DATA_REF, taxa_indicativa_pct: 5.91, spread_bps: 5.91, unidade: "pct_ao_ano", n_papeis: 19, fonte: "anbima_publico" }],
      updated_at: "2026-08-28T00:00:00Z"
      // sem campo `papeis`: e exatamente o estado gravado antes da PAPEIS1
    }));
    const { status, body } = await serieAuthed(EMPRESA);
    expect(status).toBe(200);
    expect(body.papeis).toEqual([]);
    expect(body.destaque).toBeNull();
    expect(body.destaque_motivo).toBe("sem_liquidez_reune");
    // o legado continua presente para consumidores internos, mas o card nao pode
    // usa-lo: nao ha papel nenhum com taxa_display populado.
    expect(body.spread_atual).toBe(5.91);
    expect(body.papeis.some((p) => p.taxa_display)).toBe(false);
  });

  it("op=serie sem token devolve 401 (porta fechada), nao vaza papeis", async () => {
    await env.RADAR_KV.put(kvSerieKey(EMPRESA), JSON.stringify(serieEnevaCompleta()));
    const anon = await SELF.fetch(`https://example.com/?op=serie&empresa=${encodeURIComponent(EMPRESA)}`, { method: "GET" });
    expect(anon.status).toBe(401);
  });
});

describe("PAPEIS1: backfill — caminhante de fronteira (mock probeFn, sem rede)", () => {
  const ehUtil = (d) => {
    const dow = new Date(d + "T00:00:00Z").getUTCDay();
    return dow !== 0 && dow !== 6;
  };

  it("nao para em 404 isolado: 200 -> sabado 404 -> domingo 404 -> 200 no dia util anterior", async () => {
    const FILES = new Set(["2026-09-02", "2026-08-28"]); // 200 so nestes
    const probeFn = async (d) => (FILES.has(d) ? 200 : 404);
    const r = await _probeJanelaAnbima({ probeFn, desde: "2026-09-02", minAusenciasUteis: 15, ehUtil });

    // continua apos os 404 isolados de 09-01 (util) e o fim de semana, achando 08-28
    expect(r.datasEncontradas).toContain("2026-08-28");
    expect(r.datasEncontradas).toContain("2026-09-02");
    expect(r.primeiro).toBe("2026-08-28");
    expect(r.ultimo).toBe("2026-09-02");
    // os 404 do fim de semana foram registrados (nao contados como dia util faltante)
    expect(r.paradas.some((p) => p.data === "2026-08-29" && p.status === 404)).toBe(true);
    expect(r.paradas.some((p) => p.data === "2026-08-30" && p.status === 404)).toBe(true);
    expect(r.terminou_por).toBe("ausencias_consecutivas");
  });

  it("encerra somente apos 15 dias uteis consecutivos sem 200, nao no primeiro 404", async () => {
    const FILES = new Set(["2026-09-02"]);
    const probeFn = async (d) => (FILES.has(d) ? 200 : 404);
    const r = await _probeJanelaAnbima({ probeFn, desde: "2026-09-02", minAusenciasUteis: 15, ehUtil });

    expect(r.terminou_por).toBe("ausencias_consecutivas");
    expect(r.datasEncontradas).toEqual(["2026-09-02"]);
    expect(r.primeiro).toBe("2026-09-02");
    expect(r.ultimo).toBe("2026-09-02");
    // andou para tras bem alem do primeiro 404 (15 dias uteis ~ 3 semanas)
    const datasParadas = r.paradas.map((p) => p.data);
    expect(datasParadas.some((d) => d < "2026-08-20")).toBe(true);
  });

  it("um unico 404 util nao encerra: com minAusenciasUteis alto, o 200 seguinte reseta o contador", async () => {
    const FILES = new Set(["2026-09-02", "2026-08-31"]);
    const probeFn = async (d) => (FILES.has(d) ? 200 : 404);
    const r = await _probeJanelaAnbima({ probeFn, desde: "2026-09-02", minAusenciasUteis: 15, ehUtil });
    expect(r.datasEncontradas).toContain("2026-08-31");
    expect(r.primeiro).toBe("2026-08-31");
  });
});
