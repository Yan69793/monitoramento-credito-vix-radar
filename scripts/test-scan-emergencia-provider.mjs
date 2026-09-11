import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";

// Pre-check provider-aware do fallback de emergencia (CLAUDE-FREE-MIGRATION).
//
// O defeito corrigido: `scripts/scan-emergencia.mjs` exigia ANTHROPIC_API_KEY como gate
// duro, e o Pre-check do workflow idem, mesmo com ANTHROPIC_API_PAYG = NAO AUTORIZADO. O
// provider ativo e quem decide qual chave e exigida; a chave de um provider INATIVO nao
// bloqueia. Provider desconhecido nao cai para anthropic (cair gastaria a chave paga).
//
// Prova offline de duas pontas: o caso ruim (chave do provider ativo ausente) reprova, e o
// caso bom (chave presente) passa o gate E executa de ponta a ponta. Nenhuma chamada de
// rede real: os casos de reprovacao usam porta morta local (127.0.0.1:9) e o caminho feliz
// usa um servidor HTTP local efemero que faz de Worker e de endpoint do provider. Nada
// toca producao e nada gasta token.
//
// Nota de execucao: o caminho feliz PRECISA de spawn assincrono. Com spawnSync o processo
// pai bloqueia o event loop e o servidor falso (que roda nesse mesmo processo) nunca
// responde, o que trava o filho ate o timeout. Nao volte a usar spawnSync ali.
const SCRIPT = fileURLToPath(new URL("./scan-emergencia.mjs", import.meta.url));
const PORTA_MORTA = "http://127.0.0.1:9";
const CHAVES = ["ANTHROPIC_API_KEY", "VIXRADAR_OPENROUTER_API_KEY", "OPENROUTER_API_KEY", "ROUTINE_API_KEY", "VIXRADAR_FALLBACK_PROVIDER", "VIXRADAR_API_BASE", "VIXRADAR_OPENROUTER_URL"];

function ambienteLimpo(overrides) {
  const env = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!CHAVES.includes(k)) env[k] = v;
  }
  env.VIXRADAR_API_BASE = PORTA_MORTA;
  Object.assign(env, overrides);
  return env;
}

// Para os casos que NAO precisam responder nada em casa: o filho morre no gate ou
// falha rapido na porta morta, sem depender do event loop do pai.
function rodar(overrides = {}) {
  const r = spawnSync(process.execPath, [SCRIPT], { env: ambienteLimpo(overrides), encoding: "utf8", timeout: 20000 });
  return { status: r.status, stdout: r.stdout || "", stderr: r.stderr || "" };
}

// Para os casos em que o servidor falso precisa responder durante a execucao do filho.
function rodarAsync(overrides = {}) {
  return new Promise((resolve) => {
    const filho = spawn(process.execPath, [SCRIPT], { env: ambienteLimpo(overrides) });
    let stdout = "";
    let stderr = "";
    filho.stdout.on("data", (c) => { stdout += c; });
    filho.stderr.on("data", (c) => { stderr += c; });
    const limite = setTimeout(() => filho.kill("SIGKILL"), 20000);
    filho.on("close", (status) => {
      clearTimeout(limite);
      resolve({ status, stdout, stderr });
    });
  });
}

const GATE_OK = "provider de analise:";

// ── Servidor local que faz de Worker (rotina) E de endpoint do provider ──────
function servidorFalso() {
  const chamadas = { worker: [], provider: [] };
  const server = createServer((req, res) => {
    let corpo = "";
    req.on("data", (c) => { corpo += c; });
    req.on("end", () => {
      const body = JSON.parse(corpo || "{}");
      const responder = (obj, status = 200) => {
        res.writeHead(status, { "content-type": "application/json" });
        res.end(JSON.stringify(obj));
      };
      if (req.url.includes("/chat/completions")) {
        chamadas.provider.push({ authorization: req.headers.authorization, body });
        return responder({
          id: "orc-1",
          choices: [{
            finish_reason: "stop",
            message: {
              role: "assistant",
              content: '{"empresa":"Petrobras","data_analise":"2026-09-11","sem_eventos":false,"cobertura_nota":"9 rodadas","instrumentos_ativos":["debenture"],"fontes_consultadas":[{"rodada":"1","query":"q","resultado":"X artigos, Y na janela"}],"eventos":[]}',
            },
          }],
          usage: { total_tokens: 21 },
        });
      }
      chamadas.worker.push(body.action);
      if (body.action === "listar_emissores_prioritarios") {
        return responder({ ok: true, total: 1, emissores: [{ empresa: "Petrobras", setor: "Petróleo, Gás e Combustíveis", ews_score: 9 }], sem_setor: [] });
      }
      if (body.action === "dados_para_analise") {
        return responder({ ok: true, empresa: body.empresa, setor: body.setor, janela_inicio: "2026-08-12", janela_fim: "2026-09-11" });
      }
      if (body.action === "receber_analise") {
        return responder({ ok: true, n_eventos: 1 });
      }
      return responder({ ok: false, erro: "action nao esperada: " + body.action }, 400);
    });
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, chamadas, porta: server.address().port }));
  });
}

test("provider default (anthropic) sem ANTHROPIC_API_KEY reprova nomeando a chave do provider ativo", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste" });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /::error::/);
  assert.match(r.stdout, /ANTHROPIC_API_KEY/);
  assert.ok(!r.stdout.includes(GATE_OK), "nao podia passar o gate sem chave do provider ativo");
});

test("provider anthropic com chave passa o gate (compatibilidade preservada)", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste", ANTHROPIC_API_KEY: "chave-anthropic-de-teste" });
  assert.ok(r.stdout.includes(`${GATE_OK} anthropic`), "gate devia passar com a chave do provider ativo");
});

test("provider openrouter sem nenhuma chave OpenRouter reprova e NAO menciona Anthropic", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste", VIXRADAR_FALLBACK_PROVIDER: "openrouter" });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /openrouter/);
  assert.match(r.stdout, /VIXRADAR_OPENROUTER_API_KEY/);
  assert.ok(
    !r.stdout.includes("ANTHROPIC_API_KEY"),
    "com provider openrouter ativo o gate nao pode exigir nem citar a chave Anthropic"
  );
});

test("provider openrouter com chave passa o gate sem chave Anthropic paga", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste", VIXRADAR_FALLBACK_PROVIDER: "openrouter", OPENROUTER_API_KEY: "chave-openrouter-de-teste" });
  assert.ok(r.stdout.includes(`${GATE_OK} openrouter`), "gate devia passar so com a chave OpenRouter");
  assert.ok(!r.stdout.includes("ANTHROPIC_API_KEY"), "gate nao podia citar a chave Anthropic");
});

test("chave dedicada VIXRADAR_OPENROUTER_API_KEY tambem passa o gate (precedencia declarada)", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste", VIXRADAR_FALLBACK_PROVIDER: "openrouter", VIXRADAR_OPENROUTER_API_KEY: "chave-dedicada-de-teste" });
  assert.ok(r.stdout.includes(`${GATE_OK} openrouter`));
  assert.ok(r.stdout.includes("VIXRADAR_OPENROUTER_API_KEY"), "o log deve nomear qual chave foi aceita");
});

test("provider desconhecido nao cai para anthropic", () => {
  const r = rodar({ ROUTINE_API_KEY: "rotina-de-teste", VIXRADAR_FALLBACK_PROVIDER: "opernrouter", ANTHROPIC_API_KEY: "chave-anthropic-de-teste" });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /desconhecido/);
  assert.match(r.stdout, /opernrouter/);
  assert.ok(!r.stdout.includes(`${GATE_OK} anthropic`), "typo de provider nao pode virar anthropic silenciosamente");
});

test("sem ROUTINE_API_KEY reprova antes da decisao de provider", () => {
  const r = rodar({ ANTHROPIC_API_KEY: "chave-anthropic-de-teste" });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /ROUTINE_API_KEY/);
  assert.ok(!r.stdout.includes(GATE_OK));
});

test("ponta boa: provider openrouter executa 1/1 ponta a ponta e chama o endpoint com server tool", async () => {
  const { server, chamadas, porta } = await servidorFalso();
  try {
    const base = `http://127.0.0.1:${porta}`;
    const r = await rodarAsync({
      ROUTINE_API_KEY: "rotina-de-teste",
      VIXRADAR_FALLBACK_PROVIDER: "openrouter",
      OPENROUTER_API_KEY: "chave-openrouter-de-teste",
      VIXRADAR_API_BASE: base,
      VIXRADAR_OPENROUTER_URL: `${base}/api/v1/chat/completions`,
    });

    // Nao existe chave Anthropic em lugar nenhum e mesmo assim roda ponta a ponta.
    assert.equal(r.status, 0, `stdout: ${r.stdout}`);
    assert.ok(r.stdout.includes(`${GATE_OK} openrouter`));
    assert.match(r.stdout, /Processados: 1\/1/);
    assert.ok(!r.stdout.includes("Fallback incompleto"));
    assert.ok(!r.stdout.includes("ANTHROPIC_API_KEY"));

    assert.deepEqual(chamadas.worker, ["listar_emissores_prioritarios", "dados_para_analise", "receber_analise"]);
    assert.equal(chamadas.provider.length, 1, "devia chamar o provider uma vez por emissor");
    const req = chamadas.provider[0];
    assert.equal(req.authorization, "Bearer chave-openrouter-de-teste");
    assert.equal(req.body.model, "deepseek/deepseek-v4-flash-0731");
    assert.deepEqual(req.body.tools, [{ type: "openrouter:web_search" }]);
    assert.equal(req.body.allow_fallbacks, true);
    assert.equal(req.body.messages.length, 2);
    assert.equal(req.body.messages[0].role, "system");
    assert.match(req.body.messages[1].content, /Petrobras/);
  } finally {
    server.close();
  }
});

test("ponta negativa do despacho: com provider anthropic o endpoint OpenRouter nao e chamado", async () => {
  const { server, chamadas, porta } = await servidorFalso();
  try {
    const base = `http://127.0.0.1:${porta}`;
    const r = await rodarAsync({
      ROUTINE_API_KEY: "rotina-de-teste",
      ANTHROPIC_API_KEY: "chave-anthropic-de-teste",
      VIXRADAR_API_BASE: PORTA_MORTA,
      VIXRADAR_OPENROUTER_URL: `${base}/api/v1/chat/completions`,
    });
    assert.ok(r.stdout.includes(`${GATE_OK} anthropic`));
    assert.equal(chamadas.provider.length, 0, "provider anthropic nao pode acionar o endpoint OpenRouter");
  } finally {
    server.close();
  }
});
