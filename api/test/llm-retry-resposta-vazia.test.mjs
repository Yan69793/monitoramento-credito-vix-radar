import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import {
  LLM_RETRY_CONFIG,
  _llmEsperaMs,
  _llmFetchComRetry,
  _llmTextoDe,
  _llmErroRespostaVazia,
  _llmJsonDaResposta,
  chamarClaudeAnalise,
  chamarClaudeVerificador,
  dataCustoBRT,
} from "../src/worker.js";

// LLM-01, LLM-02 e LLM-03 (2026-09-18) — prova de runtime pelo caminho real.
//
// Dois defeitos medidos no mesmo endpoint do provedor:
//
// LLM-01: chamarClaudeAnalise e chamarClaudeVerificador devolviam
//   `(data.content || []).filter(c => c.type === "text").map(c => c.text).join("\n")`
//   direto. Resposta HTTP 200 sem bloco de texto — recusa, resposta so com
//   chamada de ferramenta, corpo truncado — virava string vazia e seguia pelo
//   cascade como analise concluida. Nao havia contador.
//
// LLM-02/03: duas politicas de resiliencia para o mesmo provedor. A analise
//   tentava 2 vezes com espera fixa de 2s, so para 5xx e timeout — o 429 saia
//   direto como RATE_LIMIT, sem nova tentativa. O verificador tentava uma vez
//   so e nao tratava 429 nem 5xx.
//
// Este teste chama as FUNCOES REAIS do worker (import de ../src/worker.js), com
// duas injecoes que existem so para teste e em producao ficam undefined:
//   _fetch  — a funcao de rede, para devolver a resposta que cada cenario pede;
//   _dormir — o relogio, para a suite nao gastar segundos reais de backoff.
// Nada mais e simulado: o parse da resposta, a contagem de tentativas, a
// classificacao de retentavel e a telemetria sao o codigo que roda em producao.

const MODELO_ANALISE = "claude-haiku-4-5-20251001";

// Configuracao rapida: mesma forma da de producao, com tempos que nao pesam na
// suite. jitter 0 torna as esperas deterministicas para poder comparar.
const CFG_RAPIDO = { max_tentativas: 3, base_ms: 10, teto_ms: 100, jitter: 0, timeout_ms: 1e3 };

function http(status, corpo) {
  return new Response(typeof corpo === "string" ? corpo : JSON.stringify(corpo), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function ok(texto, stop_reason = "end_turn") {
  return http(200, {
    content: texto === null ? [] : texto === undefined ? [{ type: "tool_use", id: "t1", name: "web_search" }] : [{ type: "text", text: texto }],
    stop_reason,
    usage: { input_tokens: 10, output_tokens: 5 },
  });
}

// Desliga com AbortError, que e como o timeout do AbortController chega ao catch.
function estouroDeTempo() {
  const e = new Error("The operation was aborted");
  e.name = "AbortError";
  return Promise.reject(e);
}

// Fila de respostas. Cada chamada consome a proxima; a ultima se repete, para o
// cenario de esgotamento nao precisar listar todas as tentativas.
function fila(respostas) {
  const chamadas = [];
  const fn = async (url, init) => {
    chamadas.push({ url, init });
    const r = respostas[Math.min(chamadas.length - 1, respostas.length - 1)];
    return typeof r === "function" ? r(url, init) : r;
  };
  fn.chamadas = chamadas;
  return fn;
}

// Relogio injetado: registra as esperas em vez de dormi-las.
function relogio() {
  const esperas = [];
  return { esperas, dormir: async (ms) => { esperas.push(ms); } };
}

// Fetch que nunca responde: so termina quando o sinal de abort dispara. E o
// provedor travado, o unico cenario em que o orcamento de tempo importa. Honra
// init.signal de proposito - sem isso o teste mediria a si mesmo, nao o codigo.
function provedorTravado() {
  const chamadas = [];
  const fn = (url, init) =>
    new Promise((_, rej) => {
      chamadas.push(init);
      init.signal.addEventListener("abort", () => {
        const e = new Error("The operation was aborted");
        e.name = "AbortError";
        rej(e);
      });
    });
  fn.chamadas = chamadas;
  return fn;
}

async function analisar(fetchFn, dormir, extra) {
  return chamarClaudeAnalise("chave-de-teste", "system", "user", {
    _fetch: fetchFn,
    _dormir: dormir,
    _retry: CFG_RAPIDO,
    ...(extra || {}),
  });
}

function eventosDeTeste() {
  return [{ empresa: "Emissor Teste", titulo: "Fato relevante", fonte_primaria: "https://exemplo.test/x", data_evento: "2026-09-01" }];
}

describe("LLM-01: resposta sem bloco de texto deixa de ser sucesso", () => {
  it("caso bom: resposta com texto volta inteira e sem erro", async () => {
    const f = fila([ok("Analise concluida com fundamento.")]);
    const texto = await analisar(f, relogio().dormir);
    expect(texto).toBe("Analise concluida com fundamento.");
    expect(f.chamadas.length).toBe(1);
  });

  it("caso ruim: HTTP 200 sem nenhum bloco de texto falha explicitamente", async () => {
    const f = fila([ok(null)]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/PROVEDOR_RESPOSTA_VAZIA/);
    // Nao retenta: e resposta definitiva do provedor, nao falha de transporte.
    expect(f.chamadas.length).toBe(1);
  });

  it("caso ruim: bloco de texto so com espaco em branco tambem falha", async () => {
    const f = fila([ok("   \n\t  ")]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/PROVEDOR_RESPOSTA_VAZIA/);
  });

  it("caso ruim: resposta so com chamada de ferramenta, sem texto, falha", async () => {
    const f = fila([ok(undefined)]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/PROVEDOR_RESPOSTA_VAZIA/);
  });

  it("o motivo final preserva o stop_reason, que separa recusa de truncamento", async () => {
    const f = fila([ok(null, "refusal")]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/stop_reason=refusal/);
  });

  it("a telemetria conta a resposta vazia em canal proprio", async () => {
    const chave = `radar:llm:resposta_vazia:${dataCustoBRT()}`;
    const antes = Number(await env.RADAR_KV.get(chave)) || 0;
    const f = fila([ok(null)]);
    await expect(analisar(f, relogio().dormir, { env })).rejects.toThrow(/PROVEDOR_RESPOSTA_VAZIA/);
    const depois = Number(await env.RADAR_KV.get(chave)) || 0;
    expect(depois).toBe(antes + 1);
  });

  it("o verificador tambem trata resposta vazia como erro de provedor", async () => {
    const f = fila([ok(null)]);
    await expect(
      chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f, _dormir: relogio().dormir, _retry: CFG_RAPIDO })
    ).rejects.toThrow(/PROVEDOR_RESPOSTA_VAZIA/);
  });

  it("o verificador distingue resposta vazia de resposta com texto sem JSON", async () => {
    const f = fila([ok("nao tenho JSON nenhum aqui")]);
    await expect(
      chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f, _dormir: relogio().dormir, _retry: CFG_RAPIDO })
    ).rejects.toThrow(/sem JSON na resposta/);
  });

  it("o verificador segue devolvendo o array quando a resposta tem JSON", async () => {
    const f = fila([ok('[{"veredicto":"APROVADO","confianca":0.9}]')]);
    const r = await chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f, _dormir: relogio().dormir, _retry: CFG_RAPIDO });
    expect(Array.isArray(r)).toBe(true);
    expect(r[0].veredicto).toBe("APROVADO");
  });

  it("o erro de resposta vazia carrega a marca que o separa de indisponibilidade", () => {
    // O catch do cascade da consulta_empresa le esta marca para NAO alimentar o
    // disjuntor de provedor. Sem ela, tres respostas vazias em 5 minutos abrem o
    // circuito por 600s e a varredura inteira passa a pular o provedor - o
    // oposto do que o LLM-01 veio consertar. A prova ponta a ponta de que o
    // disjuntor nao abre esta em _tmp_cb/ (bancada), porque exige controlar a
    // resposta do provedor; aqui se garante a marca que a torna possivel.
    const e = _llmErroRespostaVazia("claude-haiku-4-5-20251001", { stop_reason: "refusal" });
    expect(e.__respostaVazia).toBe(true);
    expect(e.message).toMatch(/PROVEDOR_RESPOSTA_VAZIA/);
    // E um erro de indisponibilidade NAO pode carregar a marca, senao o
    // disjuntor nunca abriria.
    const indisponivel = new Error("PROVEDOR_INDISPONIVEL: 5xx (503)");
    expect(indisponivel.__respostaVazia).toBeUndefined();
  });

  it("corpo malformado vira erro normalizado, nunca SyntaxError cru", async () => {
    // Antes da politica unica a leitura do corpo ficava dentro do try que
    // normalizava tudo. Se ela saisse de la sem tratamento, um corpo truncado
    // chegaria a quem classifica por mensagem como SyntaxError, e o
    // classificador cairia em "erro_desconhecido".
    const truncado = new Response('{"content":[{"type":"text","text":"corta no mei', {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
    const f = fila([truncado]);
    let erro = null;
    try {
      await analisar(f, relogio().dormir);
    } catch (e) {
      erro = e;
    }
    expect(erro).not.toBeNull();
    expect(erro.name).not.toBe("SyntaxError");
    expect(String(erro.message)).toMatch(/PROVEDOR_RESPOSTA_INVALIDA/);
    expect(String(erro.message)).toContain("nao e JSON valido");
  });

  it("o verificador tambem normaliza corpo malformado", async () => {
    const f = fila([new Response("nao sou json nenhum", { status: 200, headers: { "Content-Type": "application/json" } })]);
    await expect(
      chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f, _dormir: relogio().dormir, _retry: CFG_RAPIDO })
    ).rejects.toThrow(/PROVEDOR_RESPOSTA_INVALIDA/);
  });

  it("_llmJsonDaResposta devolve o objeto e normaliza a falha", async () => {
    await expect(_llmJsonDaResposta(new Response('{"a":1}', { status: 200 }))).resolves.toEqual({ a: 1 });
    await expect(_llmJsonDaResposta(new Response("{quebrado", { status: 200 }))).rejects.toThrow(/PROVEDOR_RESPOSTA_INVALIDA/);
  });

  it("_llmTextoDe junta varios blocos de texto e ignora os que nao sao texto", () => {
    expect(_llmTextoDe({ content: [{ type: "text", text: "a" }, { type: "tool_use" }, { type: "text", text: "b" }] })).toBe("a\nb");
    expect(_llmTextoDe({})).toBe("");
    expect(_llmTextoDe(null)).toBe("");
  });
});

describe("LLM-02/03: politica unica de retry nos dois caminhos", () => {
  it("sucesso na primeira tentativa nao espera nem repete", async () => {
    const f = fila([ok("ok")]);
    const rel = relogio();
    expect(await analisar(f, rel.dormir)).toBe("ok");
    expect(f.chamadas.length).toBe(1);
    expect(rel.esperas).toEqual([]);
  });

  it("429 seguido de sucesso: retenta e conclui", async () => {
    const f = fila([http(429, { error: "rate limited" }), ok("depois do 429")]);
    const rel = relogio();
    expect(await analisar(f, rel.dormir)).toBe("depois do 429");
    expect(f.chamadas.length).toBe(2);
    expect(rel.esperas.length).toBe(1);
  });

  it("5xx seguido de sucesso: retenta e conclui", async () => {
    const f = fila([http(503, "indisponivel"), ok("depois do 503")]);
    expect(await analisar(f, relogio().dormir)).toBe("depois do 503");
    expect(f.chamadas.length).toBe(2);
  });

  it("timeout seguido de sucesso: retenta e conclui", async () => {
    const f = fila([estouroDeTempo, ok("depois do timeout")]);
    expect(await analisar(f, relogio().dormir)).toBe("depois do timeout");
    expect(f.chamadas.length).toBe(2);
  });

  it("401 nao retenta: chave invalida nao melhora repetindo", async () => {
    const f = fila([http(401, "unauthorized")]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/CHAVE_INVALIDA/);
    expect(f.chamadas.length).toBe(1);
  });

  it("400 nao retenta: pedido malformado nao melhora repetindo", async () => {
    const f = fila([http(400, "bad request")]);
    await expect(analisar(f, relogio().dormir)).rejects.toThrow(/PROVEDOR_INDISPONIVEL: 400/);
    expect(f.chamadas.length).toBe(1);
  });

  it("esgotamento: para no maximo configurado e preserva o motivo da ultima falha", async () => {
    const f = fila([http(503, "indisponivel")]);
    const rel = relogio();
    let erro = null;
    try {
      await analisar(f, rel.dormir);
    } catch (e) {
      erro = e;
    }
    expect(erro).not.toBeNull();
    expect(f.chamadas.length).toBe(CFG_RAPIDO.max_tentativas);
    expect(erro.tentativas).toBe(CFG_RAPIDO.max_tentativas);
    // A mensagem carrega as duas formas: "5xx" (o que o classificador de health
    // casa por regex) e o numero (o que diz qual erro foi).
    expect(String(erro.message)).toContain("5xx");
    expect(String(erro.message)).toContain("503");
  });

  it("o verificador usa a mesma politica: 429 seguido de sucesso tambem retenta la", async () => {
    const f = fila([http(429, "rate limited"), ok('[{"veredicto":"APROVADO","confianca":0.9}]')]);
    const rel = relogio();
    const r = await chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f, _dormir: rel.dormir, _retry: CFG_RAPIDO });
    expect(f.chamadas.length).toBe(2);
    expect(rel.esperas.length).toBe(1);
    expect(r[0].veredicto).toBe("APROVADO");
  });

  it("o verificador tambem esgota no maximo e nao retenta 401", async () => {
    const f5 = fila([http(500, "erro")]);
    await expect(
      chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f5, _dormir: relogio().dormir, _retry: CFG_RAPIDO })
    ).rejects.toThrow(/PROVEDOR_INDISPONIVEL/);
    expect(f5.chamadas.length).toBe(CFG_RAPIDO.max_tentativas);

    const f401 = fila([http(401, "unauthorized")]);
    await expect(
      chamarClaudeVerificador(MODELO_ANALISE, eventosDeTeste(), env, { _fetch: f401, _dormir: relogio().dormir, _retry: CFG_RAPIDO })
    ).rejects.toThrow(/CHAVE_INVALIDA/);
    expect(f401.chamadas.length).toBe(1);
  });

  it("o backoff cresce entre as tentativas e respeita o teto", async () => {
    const f = fila([http(503, "erro")]);
    const rel = relogio();
    await expect(analisar(f, rel.dormir)).rejects.toThrow();
    // base 10, teto 100, jitter 0: 2a tentativa espera 20, 3a espera 40.
    expect(rel.esperas).toEqual([20, 40]);

    const cfgTeto = { max_tentativas: 6, base_ms: 10, teto_ms: 40, jitter: 0, timeout_ms: 1e3 };
    const f2 = fila([http(503, "erro")]);
    const rel2 = relogio();
    await expect(_llmFetchComRetry("https://exemplo.test", {}, cfgTeto, rel2.dormir, f2)).rejects.toThrow();
    expect(rel2.esperas.every((ms) => ms <= 40)).toBe(true);
    expect(rel2.esperas).toEqual([20, 40, 40, 40, 40]);
  });

  it("o jitter espalha a espera dentro da faixa, sem cair abaixo da base", () => {
    const cfg = { base_ms: 1e3, teto_ms: 1e4, jitter: 0.5 };
    const valores = [];
    for (let i = 0; i < 200; i++) valores.push(_llmEsperaMs(2, cfg));
    // tentativa 2 => base 2000; com jitter 0.5 a espera fica em [2000, 3000].
    expect(Math.min(...valores)).toBeGreaterThanOrEqual(2e3);
    expect(Math.max(...valores)).toBeLessThanOrEqual(3e3);
    // e de fato varia, ou nao seria jitter
    expect(new Set(valores).size).toBeGreaterThan(50);
  });

  it("a configuracao de producao e explicita e finita", () => {
    expect(LLM_RETRY_CONFIG.max_tentativas).toBeGreaterThan(1);
    expect(Number.isFinite(LLM_RETRY_CONFIG.max_tentativas)).toBe(true);
    expect(LLM_RETRY_CONFIG.base_ms).toBeGreaterThan(0);
    expect(LLM_RETRY_CONFIG.teto_ms).toBeGreaterThanOrEqual(LLM_RETRY_CONFIG.base_ms);
    expect(LLM_RETRY_CONFIG.jitter).toBeGreaterThan(0);
    expect(LLM_RETRY_CONFIG.timeout_ms).toBeGreaterThan(0);
    // Orcamento tem que existir e nao pode ser menor que um timeout so, senao
    // nem a primeira tentativa caberia.
    expect(Number.isFinite(LLM_RETRY_CONFIG.orcamento_ms)).toBe(true);
    expect(LLM_RETRY_CONFIG.orcamento_ms).toBeGreaterThanOrEqual(LLM_RETRY_CONFIG.timeout_ms);
  });

  it("caso bom: com orcamento folgado, falha rapida continua usando todas as tentativas", async () => {
    // O orcamento existe para cortar a tentativa LENTA, nao a repeticao barata.
    // Um 503 que responde na hora nao pode perder tentativa por causa dele.
    const cfg = { ...CFG_RAPIDO, orcamento_ms: 6e4 };
    const f = fila([http(503, "indisponivel")]);
    await expect(_llmFetchComRetry("https://exemplo.test", {}, cfg, relogio().dormir, f)).rejects.toThrow();
    expect(f.chamadas.length).toBe(cfg.max_tentativas);
  });

  it("caso limite: provedor travado para no orcamento, nao em tentativas x timeout", async () => {
    // O unico caso em que o orcamento importa. Sem ele, este cenario gastaria
    // 5 x 60s; com ele, tem que terminar perto do teto.
    const cfg = { max_tentativas: 5, base_ms: 10, teto_ms: 10, jitter: 0, timeout_ms: 6e4, orcamento_ms: 120 };
    const f = provedorTravado();
    const t0 = Date.now();
    let erro = null;
    try {
      await _llmFetchComRetry("https://exemplo.test", {}, cfg, null, f);
    } catch (e) {
      erro = e;
    }
    const gasto = Date.now() - t0;
    expect(erro).not.toBeNull();
    // 3s de margem sobre um teto de 120ms: folga suficiente para nao depender de
    // precisao de relogio em maquina carregada.
    expect(gasto).toBeLessThan(3000);
    expect(f.chamadas.length).toBeLessThan(cfg.max_tentativas);
    expect(erro.orcamento_estourado).toBe(true);
    // E o motivo final continua sendo o da ultima falha real, nao um texto novo.
    expect(String(erro.message)).toMatch(/Timeout/);
  }, 30000);

  it("falha de transporte tambem retenta, que era o buraco da politica antiga", async () => {
    const erroDeRede = () => { throw Object.assign(new Error("fetch failed"), { name: "TypeError" }); };
    const f = fila([erroDeRede, ok("depois da falha de rede")]);
    expect(await analisar(f, relogio().dormir)).toBe("depois da falha de rede");
    expect(f.chamadas.length).toBe(2);
  });
});
