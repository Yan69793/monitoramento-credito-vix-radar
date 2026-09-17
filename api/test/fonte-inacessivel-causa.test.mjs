import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { validarDatasFontes, _ehFonteConfitavelBloqueada } from "../src/worker.js";

// FONTEINACESSIVEL-SILENCIOSO1 (2026-09-16). Relato do operador: o Worker aceita o POST de
// `receber_analise` com HTTP 200 e ok:true, descarta evento e a rotina fecha como sucesso.
//
// MEDIDO em 16/09/2026, sem supor:
//   - Lote 1 do harness M3 (5 emissores, logs/routines/teste-miniatur.../lote1_submissao.json):
//     a Braskem devolveu HTTP 200, ok:true, n_eventos=8 de 10 e `descartes.fonte_inacessivel: 2`.
//     As duas URLs submetidas estavam corrompidas no rascunho do M3 (`...braskem.ghtm`,
//     `...acao-cai-13`), devolvem HTTP 404 ao UA do Worker, e as corretas (`.ghtml`, como o
//     proprio smoke do harness ja tinha) devolvem HTTP 200. Medicao da rede, colada em
//     logs/routines/teste-miniaturaminimaxm3/diagnostico_braskem.txt.
//   - Noturna de producao do mesmo dia (logs/routines/vixradar-noturno_20260916.log:186):
//     `DESCARTADO|BRF|enviados=1|persistidos=0|fonte_inacessivel=1`, rotina fechando PARCIAL
//     sem alerta. A fonte (agfeed.com.br) responde HTTP 200 ao UA do Worker com
//     `article:published_time` de 2026-04-13, fora da janela de 30 dias.
//
// CAUSA RAIZ ESTRUTURAL (o que este arquivo trava): `descartes.fonte_inacessivel` era o
// AGREGADO dos QUATRO `continue` de `validarDatasFontes` (data antiga na URL, data antiga no
// HTML, divergencia >60d, fetch falhou) e apenas o quarto imprimia log. Os outros tres saiam
// mudos, entao nem o console do Worker nem a resposta do POST diziam qual ramo disparou:
// "2 descartes" era indistinguivel de "fonte bloqueada por bot" quando na verdade era URL 404
// e "fonte antiga". O contador por causa e a linha com `motivo=` fecham esse buraco SEM mudar
// um unico aceite.
//
// Prova das pontas (regra 5): o caso BOM (cada ramo agora nomeado, com o valor que decidiu) e o
// caso RUIM (o aceite nao mudou: host confiavel com data de fonte antiga continua entrando com
// _verif_forcar, evento com data na URL dentro da janela continua aceito sem fetch, e descarte
// real continua descartando). Contra o codigo anterior, os asserts de causa falham (o contador
// nao existia) e os asserts de aceite passam identicos — o defeito era de visibilidade, nao de
// criterio.

// Mesmo relogio do Worker (obterAgoraBRT subtrai 3h fixas). Fixture em data RELATIVA de
// proposito: a suite roda tambem com o relogio adiantado (196 dias, worker-tests.yml) e valor
// datado fixo comparado contra Date.now() real quebraria a rodada deslocada.
function agoraBRT() {
  return new Date(Date.now() - 3 * 60 * 60 * 1e3);
}
function dataRel(dias) {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

const TRINTA = dataRel(-30);
const HOJE = dataRel(0);

// HTML minimo com a mesma marca que o extrator real procura (extrairDataDoHTML, worker.js:13714).
function htmlComData(iso) {
  return `<html><head><meta property="article:published_time" content="${iso}T08:00:00-03:00"></head><body>${"x".repeat(200)}</body></html>`;
}
const stubStatus = (status) => vi.fn(async () => new Response("", { status }));
const stubHtml = (html) => vi.fn(async () => new Response(html, { status: 200 }));

function evento(over) {
  return Object.assign({
    empresa: "Teste",
    classificacao: "ECO",
    titulo: "evento de teste",
    data_evento: dataRel(-1),
    fonte_primaria: "https://portal-exemplo.com.br/nota-sem-data-na-url"
  }, over || {});
}

describe("FONTEINACESSIVEL-SILENCIOSO1: os QUATRO ramos de descarte de validarDatasFontes passam a ter causa nomeada", () => {
  it("ramo (1/4) data antiga na propria URL: conta data_url_antiga e nem chega a buscar a fonte", async () => {
    const semFetch = stubStatus(404);
    const contador = {};
    const antiga = dataRel(-400).replace(/-/g, "/");
    const validados = await validarDatasFontes(
      [evento({ fonte_primaria: `https://portal-exemplo.com.br/${antiga}/nota-antiga` })],
      TRINTA,
      semFetch,
      contador
    );
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ data_url_antiga: 1 });
    expect(semFetch).not.toHaveBeenCalled(); // o ramo decide antes do fetch
  });

  it("ramo (2/4) data antiga no HTML da fonte, host nao confiavel: conta data_fonte_antiga (antes, silencio total)", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({ data_evento: dataRel(-1) })],
      TRINTA,
      stubHtml(htmlComData(dataRel(-200))),
      contador
    );
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ data_fonte_antiga: 1 });
  });

  it("ramo (3/4) data do HTML dentro da janela mas divergindo >60d do data_evento: conta data_fonte_divergente", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({ data_evento: dataRel(-100) })],
      TRINTA,
      stubHtml(htmlComData(dataRel(-1))),
      contador
    );
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ data_fonte_divergente: 1 });
  });

  it("ramo (4/4) fetch falhou em host nao confiavel: conta fonte_inacessivel_fetch", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({ fonte_primaria: "https://dominio-inexistente-fonteinacessivel.invalid/doc.htm" })],
      TRINTA,
      stubStatus(404),
      contador
    );
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ fonte_inacessivel_fetch: 1 });
  });

  it("cada ramo imprime a propria linha com motivo= (o agregado deixa de ser a unica leitura)", async () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => { });
    try {
      await validarDatasFontes([evento({ fonte_primaria: "https://dominio-inexistente-fonteinacessivel.invalid/doc.htm" })], TRINTA, stubStatus(404), {});
      await validarDatasFontes([evento()], TRINTA, stubHtml(htmlComData(dataRel(-200))), {});
      const linhas = spy.mock.calls.map((c) => String(c[0])).join("\n");
      expect(linhas).toContain("[validarDatas][DESCARTADO_FONTE_INACESSIVEL] motivo=fonte_inacessivel_fetch");
      expect(linhas).toContain("[validarDatas][DESCARTADO_DATA_FONTE_ANTIGA] motivo=data_fonte_antiga");
    } finally {
      spy.mockRestore();
    }
  });

  it("invariante: soma das causas por ramo == enviados - aceitos, e nenhuma causa inventada", async () => {
    const contador = {};
    const eventos = [
      // (1) data antiga na URL
      evento({ fonte_primaria: `https://portal-exemplo.com.br/${dataRel(-400).replace(/-/g, "/")}/a` }),
      // (2) data antiga no HTML
      evento({ fonte_primaria: "https://portal-exemplo.com.br/a", data_evento: dataRel(-1) }),
      // (3) divergencia >60d
      evento({ data_evento: dataRel(-100) }),
      // (4) fetch falhou
      evento({ fonte_primaria: "https://dominio-inexistente-fonteinacessivel.invalid/doc.htm" })
    ];
    // o stub decide pelo URL: ".invalid" devolve 404 (ramo 4), a URL "/a" devolve HTML com data
    // antiga (ramo 2), e o restante devolve HTML com data na janela (ramo 3, por divergencia)
    const fetch4 = vi.fn(async (url) => {
      const u = String(url);
      if (u.includes(".invalid")) return new Response("", { status: 404 });
      if (u.endsWith("/a")) return new Response(htmlComData(dataRel(-200)), { status: 200 });
      return new Response(htmlComData(dataRel(-1)), { status: 200 });
    });
    const validados = await validarDatasFontes(eventos, TRINTA, fetch4, contador);
    const soma = Object.values(contador).reduce((a, b) => a + b, 0);
    expect(validados.length + soma).toBe(eventos.length);
    expect(contador).toEqual({
      data_url_antiga: 1,
      data_fonte_antiga: 1,
      data_fonte_divergente: 1,
      fonte_inacessivel_fetch: 1
    });
  });

  it("sem contador (chamadores antigos): continua funcionando e descartando igual", async () => {
    const validados = await validarDatasFontes([evento()], TRINTA, stubHtml(htmlComData(dataRel(-200))));
    expect(validados.length).toBe(0);
  });

  it("PONTA RUIM: aceite nao mudou — data do HTML na janela e sem divergencia entra, sem causa contada", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({ data_evento: dataRel(-1) })],
      TRINTA,
      stubHtml(htmlComData(dataRel(-2))),
      contador
    );
    expect(validados.length).toBe(1);
    expect(contador).toEqual({});
  });

  it("PONTA RUIM: host confiavel com data de fonte antiga continua aceito com _verif_forcar (regressao do ramo 14320)", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({ fonte_primaria: "https://valor.globo.com/financas/nota-sentinel1.ghtml", data_evento: dataRel(-1) })],
      TRINTA,
      stubHtml(htmlComData(dataRel(-400))),
      contador
    );
    expect(validados.length).toBe(1);
    expect(validados[0]._verif_forcar).toBe(true);
    expect(contador).toEqual({});
  });

  it("PONTA RUIM: data na URL dentro da janela continua aceita sem fetch", async () => {
    const semFetch = stubStatus(500);
    const contador = {};
    const naJanela = dataRel(-5);
    const validados = await validarDatasFontes(
      [evento({ fonte_primaria: `https://portal-exemplo.com.br/${naJanela.replace(/-/g, "/")}/nota` })],
      TRINTA,
      semFetch,
      contador
    );
    expect(validados.length).toBe(1);
    expect(contador).toEqual({});
    expect(semFetch).not.toHaveBeenCalled();
  });
});

describe("FONTEINACESSIVEL-SILENCIOSO1: reproducao dos dois incidentes medidos em 16/09/2026", () => {
  it("Braskem: URL .ghtm corrompida no rascunho do M3 (HTTP 404 medido) -> causa fonte_inacessivel_fetch", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({
        empresa: "Braskem",
        classificacao: "CRITICO",
        data_evento: dataRel(-1),
        fonte_primaria: "https://pipelinevalor.globo.com/negocios/noticia/aporte-da-petrobras-e-entrave-na-tratativa-com-credores-da-braskem.ghtm"
      })],
      TRINTA,
      stubStatus(404),
      contador
    );
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ fonte_inacessivel_fetch: 1 });
  });

  it("Braskem: com a URL correta (.ghtml, HTTP 200 medido) o mesmo evento e aceito - o defeito era de payload, nao do Worker", async () => {
    const contador = {};
    const validados = await validarDatasFontes(
      [evento({
        empresa: "Braskem",
        classificacao: "CRITICO",
        data_evento: dataRel(-1),
        fonte_primaria: "https://pipelinevalor.globo.com/negocios/noticia/aporte-da-petrobras-e-entrave-na-tratativa-com-credores-da-braskem.ghtml"
      })],
      TRINTA,
      stubHtml(htmlComData(dataRel(-1))),
      contador
    );
    expect(validados.length).toBe(1);
    expect(contador).toEqual({});
  });

  it("BRF na noturna de producao: agfeed.com.br acessivel (HTTP 200) com data de 2026-04-13 -> causa data_fonte_antiga, que antes nao gerava log nenhum", async () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => { });
    const contador = {};
    let validados;
    try {
      validados = await validarDatasFontes(
        [evento({
          empresa: "BRF",
          data_evento: dataRel(-21), // 2026-08-26 no dia do incidente
          fonte_primaria: "https://agfeed.com.br/negocios/depois-de-levantar-mais-de-r-5-bi-em-2025-brf-busca-ate-r-15-bilhao-em-novos-cras/"
        })],
        TRINTA,
        stubHtml(htmlComData("2026-04-13")), // valor medido na fonte real em 16/09/2026
        contador
      );
      const linhas = spy.mock.calls.map((c) => String(c[0])).join("\n");
      expect(linhas).toContain("motivo=data_fonte_antiga");
      expect(linhas).toContain("dataFonte=2026-04-13");
    } finally {
      spy.mockRestore();
    }
    expect(validados.length).toBe(0);
    expect(contador).toEqual({ data_fonte_antiga: 1 });
  });
});

describe("FONTEINACESSIVEL-SILENCIOSO1: dominio confiavel e subdominio (avaliacao pedida no item 5)", () => {
  // `_matchDominio` casa por ROTULO (host igual ou qualquer sufixo de rotulos), nao por
  // substring: e isso que faz "sub.valor.globo.com" ser confiavel sem abrir "globo.com"
  // inteiro, e e tambem o motivo de "pipelinevalor.globo.com" NAO ser confiavel (sibling, nao
  // subdominio do que esta na lista). Medido na fonte real em 16/09: a pagina do pipelinevalor
  // responde HTTP 200 ao UA do Worker, ou seja, nao ha bloqueio de bot a cobrir ali.
  it("cobre subdominio real e nao abre o dominio pai", () => {
    expect(_ehFonteConfitavelBloqueada("valor.globo.com")).toBe(true);
    expect(_ehFonteConfitavelBloqueada("www.valor.globo.com")).toBe(true);
    expect(_ehFonteConfitavelBloqueada("sub.data.cvm.gov.br")).toBe(true);
    expect(_ehFonteConfitavelBloqueada("pipelinevalor.globo.com")).toBe(false);
    expect(_ehFonteConfitavelBloqueada("globo.com")).toBe(false);
    expect(_ehFonteConfitavelBloqueada("")).toBe(false);
  });
});

// --- Ponta HTTP: a resposta do POST passa a carregar a decomposicao -------------------
// O aceite nao muda; o que muda e a rotina conseguir separar "fonte bloqueada" de "URL 404 /
// data antiga" sem depender do console do Worker (que ela nao le).
const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const EMPRESA = "Dasa";

function resultadoCom(eventos) {
  return {
    empresa: EMPRESA,
    setor: "Teste",
    sem_eventos: false,
    classificacao_geral: "ECO",
    cobertura_nota: "teste de descarte por causa",
    eventos,
    fontes_consultadas: [
      { rodada: "R1", familia: "emissor", query: "consulta 1", resultado: "teste", classificacao: "ok" },
      { rodada: "R2", familia: "divida", query: "consulta 2", resultado: "teste", classificacao: "ok" },
      { rodada: "R3", familia: "fato", query: "consulta 3", resultado: "teste", classificacao: "ok" }
    ],
    _tier: "FULL",
    _rotina_v2: true
  };
}

function eventoRotina(over) {
  return Object.assign({
    classificacao: "ECO",
    titulo: "evento de teste de causa",
    evento: "descricao do evento de teste",
    impacto_credito: "impacto",
    fonte_primaria: "https://dominio-inexistente-fonteinacessivel.invalid/doc.htm",
    fonte_tipo: "IMPRENSA",
    data_evento: dataRel(-1),
    data_aproximada: false,
    tags: ["teste"]
  }, over || {});
}

async function submeter(resultado) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.77" },
    body: JSON.stringify({
      action: "receber_analise",
      routine_key: ROUTINE_KEY,
      empresa: EMPRESA,
      setor: "Teste",
      _matinal: false,
      provedor: "teste-fonteinacessivel",
      resultado
    })
  });
}

async function limpar() {
  for (const k of ["radar:estado:" + semanaISOBRT(), `radar:cvm_vistos:${EMPRESA.toLowerCase()}`]) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

// semana ISO do relogio BRT, mesma conta do Worker (evita depender de outra lib no isolate)
function semanaISOBRT() {
  const d = agoraBRT();
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil(((t - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}

beforeEach(async () => {
  await bootstrapIndiceQuarentena(env);
  await limpar();
});
afterEach(limpar);

describe("FONTEINACESSIVEL-SILENCIOSO1: resposta de receber_analise separa o agregado por causa", () => {
  it("PONTA BOA: dois eventos descartados por causas diferentes aparecem separados, e a chave antiga segue preenchida", async () => {
    const res = await submeter(resultadoCom([
      // fetch falha de verdade (host .invalid nao resolve): ramo 4
      eventoRotina({ titulo: "fetch falha" }),
      // data antiga na propria URL: ramo 1, sem fetch
      eventoRotina({ titulo: "data antiga na url", fonte_primaria: "https://portal-exemplo.com.br/2020/01/15/nota-antiga" })
    ]));
    expect(res.status).toBe(200);
    const body = await res.json();

    expect(body.ok).toBe(true);
    expect(body.n_eventos).toBe(0);
    // compatibilidade com scripts/run_vixradar_varredura.ps1:1574 (a chave agregada continua)
    expect(body.descartes.fonte_inacessivel).toBe(2);
    expect(body.descartes.fonte_inacessivel_por_causa).toEqual({
      data_url_antiga: 1,
      fonte_inacessivel_fetch: 1
    });
  });

  it("PONTA RUIM/controle: entrega sem descarte material responde com a decomposicao zerada e nao conta causa inexistente", async () => {
    const res = await submeter(resultadoCom([
      // data na URL dentro da janela: aceito sem fetch
      eventoRotina({ fonte_primaria: `https://portal-exemplo.com.br/${dataRel(-5).replace(/-/g, "/")}/nota` })
    ]));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.descartes.fonte_inacessivel).toBe(0);
    expect(body.descartes.fonte_inacessivel_por_causa).toEqual({});
  });
});
