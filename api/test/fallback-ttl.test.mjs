import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { beforeEach, describe, expect, it } from "vitest";

// REPROVADO-FAILCLOSED1 (2026-09-06): gates sao fail-closed; indice ausente = erro.
beforeEach(async () => { await bootstrapIndiceQuarentena(env); });

// FALLBACKTTL1 (auditoria 29/08/2026, fix 30/08, deploy v4.9.225) — a LACUNA que
// PENDENCIAS.md:439 registra como nao fechada: nenhum teste automatizado cobria o par
// `salvarCacheUltimoResorte` / `buscarCacheUltimoResorte`. Este arquivo fecha a lacuna.
//
// O defeito original: `salvarCacheUltimoResorte` gravava `fallback:{empresa}` em
// `RADAR_KV` com `expirationTtl: 86400` e `buscarCacheUltimoResorte` tinha corte de
// idade proprio em 24h — o MESMO numero do intervalo da varredura diaria, o que viola
// VOLTTL1 (TTL >= 2x o intervalo de escrita). Em 28/08/2026 nao houve varredura e o
// cache de ultimo recurso dos 103 emissores foi apagado; o painel passou a devolver
// 503 em vez da analise de ontem. Fix no ar: `expirationTtl: 86400 * 3` na escrita
// (worker.js:17838) e `idadeHoras > 48` na leitura (worker.js:17864), com margem de
// 24h entre o corte de servico e o vencimento de armazenamento.
//
// Prova de DUAS PONTAS (regra 5 do CLAUDE.md), pelo caminho real do Worker:
//   - ponta boa (o que o fix comprou): cachê de 36h ainda e SERVIVEL. Com o corte
//     antigo de 24h esta chamada devolvia 503 — e e exatamente o cenario de 28/08
//     (uma varredura perdida) que o fix existe para cobrir.
//   - ponta negativa (o gate nao foi removido): cachê de 60h NAO e servido, mesmo
//     com a chave presente no KV. Sem esta ponta, "passar a servir tudo" tambem
//     passaria no teste.
//
// O caminho exercitado e a rota paga `consulta_empresa`: o cascade do Worker so tem
// `claude-haiku-analise` (worker.js:21524-21526) e neste ambiente a chave e dummy, o
// que deixa `_baseResA` nulo e cai em `buscarCacheUltimoResorte` (worker.js:21613).
// `_teste: true` num ambiente nao-production pula o JWT (worker.js:21466); o KV e
// lido direto por `env.RADAR_KV`, a mesma chave que a varredura grava.

const IP_TESTE = "203.0.113.90";
const EMPRESA = "Simpar";
const SETOR = "Energia";
const HORA_MS = 36e5;

// Mesmo formato de `_fallback_ts` que salvarCacheUltimoResorte escreve
// (worker.js:17829): hora local de Sao Paulo com offset -03:00.
function tsSaoPaulo(data) {
  return data.toLocaleString("sv-SE", { timeZone: "America/Sao_Paulo" }).replace(" ", "T") + "-03:00";
}

async function semearFallback(idadeHoras) {
  const ts = tsSaoPaulo(new Date(Date.now() - idadeHoras * HORA_MS));
  await env.RADAR_KV.put(
    `fallback:${EMPRESA}`,
    JSON.stringify({ empresa: EMPRESA, setor: SETOR, eventos: [], sem_eventos: true, _fallback_ts: ts })
  );
  return ts;
}

async function pedirAnalise() {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": IP_TESTE },
    body: JSON.stringify({ _teste: true, empresa: EMPRESA, setor: SETOR })
  });
}

describe("FALLBACKTTL1: cache de ultimo recurso sobrevive a 1 dia sem varredura", () => {
  it("ponta boa: cache de 36h e servido com _de_cache e idade reportada", async () => {
    const ts = await semearFallback(36);
    // Pre-condicao medida: a chave existe de fato antes da chamada (senao o 503 da
    // ponta negativa seria indistinguivel de "chave ausente").
    const bruto = await env.RADAR_KV.get(`fallback:${EMPRESA}`, "text");
    expect(bruto).toBeTruthy();
    expect(JSON.parse(bruto)._fallback_ts).toBe(ts);

    const r = await pedirAnalise();
    expect(r.status).toBe(200);
    const corpo = await r.json();
    expect(corpo._de_cache).toBe(true);
    expect(corpo._cache_idade_horas).toBeGreaterThan(35);
    expect(corpo._cache_idade_horas).toBeLessThan(37);
    expect(corpo._score_confianca).toBeGreaterThanOrEqual(0.3);
    expect(String(corpo._aviso || "")).toContain("h atras");
    // O corte de 48h deixou passar 36h: com o gate antigo de 24h este 200 era 503.
    expect(r.status).not.toBe(503);
  });

  it("ponta negativa: cache de 60h esta no KV e MESMO ASSIM nao e servido", async () => {
    await semearFallback(60);
    const bruto = await env.RADAR_KV.get(`fallback:${EMPRESA}`, "text");
    expect(bruto).toBeTruthy(); // existe

    const r = await pedirAnalise();
    expect(r.status).toBe(503);
    const corpo = await r.json();
    expect(corpo.ok).toBe(false);
    expect(corpo._de_cache).toBeUndefined();
    expect(String(corpo.erro || "")).toContain("temporariamente indisponivel");
  });
});
