import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath, pathToFileURL } from "node:url";

// Prova direta no handler real do Worker, em processo Node. Isto existe porque o
// runner Vitest deste ambiente nao consegue criar processos filhos (esbuild/workerd
// falham com spawn EPERM). O caminho testado e o mesmo `worker_default.fetch` que a
// suite Vitest exercise via `cloudflare:test`; aqui trocamos apenas os bindings por
// stubs em memoria e a Resend por um fetch deterministico.
const CAMINHO_WORKER = fileURLToPath(new URL("../api/src/worker.js", import.meta.url));
const worker = await import(pathToFileURL(CAMINHO_WORKER).href);

function criarAmbiente() {
  const store = new Map();
  const kv = {
    get: async (k, tipo) => {
      const v = store.get(k);
      if (v === undefined || v === null) return null;
      if (tipo === "json") return JSON.parse(v);
      return v;
    },
    put: async (k, v) => { store.set(k, typeof v === "string" ? v : JSON.stringify(v)); },
    delete: async (k) => { store.delete(k); },
    list: async (opts = {}) => {
      const prefix = opts.prefix || "";
      return { keys: [...store.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true, cursor: undefined };
    }
  };
  const rateLimiter = {
    idFromName: (n) => n,
    get: () => ({ fetch: async () => new Response(JSON.stringify({ allowed: true }), { status: 200, headers: { "Content-Type": "application/json" } }) })
  };
  const env = {
    RADAR_KV: kv,
    RADAR_USAGE_EVENTS: { writeDataPoint() {} },
    RATE_LIMITER_DO: rateLimiter,
    ADMIN_EMAIL: "admin-test@example.com",
    ADMIN_PASSWORD: "senha-admin-teste",
    ROUTINE_API_KEY: "chave-rotina-teste",
    RESEND_API_KEY: "chave-resend-teste",
    JWT_SECRET: "segredo-jwt-teste",
    MAIL_FROM_OVERRIDE: "VIX Radar <teste@example.com>"
  };
  const ctx = { waitUntil() {}, passThroughOnException() {} };
  return { env, ctx, store };
}

async function chamar(env, ctx, body, ip = "203.0.113.91") {
  const req = new Request("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify(body)
  });
  return worker.default.fetch(req, env, ctx);
}

function instalarResendMock() {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const payload = JSON.parse(init && init.body || "{}");
    const to = String(payload && payload.to && payload.to[0] || "");
    if (to.includes("@falha-envio.example")) {
      return new Response(
        JSON.stringify({ statusCode: 422, name: "validation_error", message: "Recipient domain rejected the message (mock)" }),
        { status: 422, headers: { "Content-Type": "application/json" } }
      );
    }
    return new Response(JSON.stringify({ id: "mock-resend-id-0001" }), { status: 200, headers: { "Content-Type": "application/json" } });
  };
  return () => { globalThis.fetch = originalFetch; };
}

test("SCANFALLBACK-MORTO1: reproduz o 400 e prova o payload valido no handler real", async () => {
  const { env, ctx } = criarAmbiente();
  const rLista = await chamar(env, ctx, { action: "listar_emissores_prioritarios", routine_key: "chave-rotina-teste", top_n: 15 });
  assert.equal(rLista.status, 200);
  const lista = await rLista.json();
  assert.equal(lista.ok, true);
  assert.ok(Array.isArray(lista.emissores) && lista.emissores.length > 0);
  assert.ok(Array.isArray(lista.sem_setor));

  const emissor = lista.emissores[0];
  assert.equal(typeof emissor.empresa, "string");
  assert.ok(emissor.empresa.length > 0);
  assert.equal(typeof emissor.setor, "string");
  assert.ok(emissor.setor.length > 0);

  // Metade 1 do defeito antigo: o contrato usa `empresa`, nao `nome`.
  const rNome = await chamar(env, ctx, { action: "dados_para_analise", routine_key: "chave-rotina-teste", empresa: emissor.nome, setor: emissor.setor });
  assert.equal(rNome.status, 400);
  assert.equal((await rNome.json()).erro, "empresa e setor obrigatorios.");

  // Metade 2 do defeito antigo: o setor era ausente/vaazio na chamada.
  const rSemSetor = await chamar(env, ctx, { action: "dados_para_analise", routine_key: "chave-rotina-teste", empresa: emissor.empresa, setor: "" });
  assert.equal(rSemSetor.status, 400);
  assert.equal((await rSemSetor.json()).erro, "empresa e setor obrigatorios.");

  // Payload valido, derivado do contrato real do endpoint.
  const rOk = await chamar(env, ctx, { action: "dados_para_analise", routine_key: "chave-rotina-teste", empresa: emissor.empresa, setor: emissor.setor });
  assert.equal(rOk.status, 200);
  const body = await rOk.json();
  assert.equal(body.ok, true);
  assert.equal(body.empresa, emissor.empresa);
  assert.equal(body.setor, emissor.setor);
  assert.match(body.janela_inicio, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(body.janela_fim, /^\d{4}-\d{2}-\d{2}$/);
});


test("SCANFALLBACK-MORTO1: item sem setor canonico e rejeitado", async () => {
  const { env, ctx } = criarAmbiente();
  const rLista = await chamar(env, ctx, { action: "listar_emissores_prioritarios", routine_key: "chave-rotina-teste", top_n: 15 });
  const lista = await rLista.json();
  assert.equal(rLista.status, 200);
  const emissor = lista.emissores[0];
  const contrato = worker._listarPrioritariosComSetor([
    { empresa: emissor.empresa, ews_score: 1 },
    { empresa: "Emissor Sem Setor Canonico Teste" }
  ]);
  assert.equal(contrato.emissores.length, 1);
  assert.equal(contrato.emissores[0].setor, emissor.setor);
  assert.deepEqual(contrato.sem_setor, ["Emissor Sem Setor Canonico Teste"]);
});

test("EMAILSILENT1 residual: sucesso de lote inteiro", async () => {
  const { env, ctx } = criarAmbiente();
  const restaurar = instalarResendMock();
  try {
    const r = await chamar(env, ctx, { action: "email_enviar", admin_senha: "senha-admin-teste", assunto: "teste", html: "<p>ok</p>", destinatarios: ["lote-ok-1@example.com", "lote-ok-2@example.com"] }, "203.0.113.92");
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.ok, true);
    assert.equal(body.enviado, true);
    assert.equal(body.enviados, 2);
    assert.equal(body.falhas, 0);
    assert.equal(body.ids.length, 2);
    assert.deepEqual(body.erros, []);
  } finally { restaurar(); }
});

test("EMAILSILENT1 residual: falha de destinatario unico continua 500", async () => {
  const { env, ctx } = criarAmbiente();
  const restaurar = instalarResendMock();
  try {
    const r = await chamar(env, ctx, { action: "email_enviar", admin_senha: "senha-admin-teste", assunto: "teste", html: "<p>falha</p>", destinatarios: ["lote-ruim@falha-envio.example"] }, "203.0.113.93");
    assert.equal(r.status, 500);
    const body = await r.json();
    assert.equal(body.ok, false);
    assert.match(String(body.detalhe), /422/);
  } finally { restaurar(); }
});

test("EMAILSILENT1 residual: lote sem nenhum sucesso nao e 207 parcial", async () => {
  const { env, ctx } = criarAmbiente();
  const restaurar = instalarResendMock();
  try {
    const r = await chamar(env, ctx, { action: "email_enviar", admin_senha: "senha-admin-teste", assunto: "teste", html: "<p>falha total</p>", destinatarios: ["ruim-1@falha-envio.example", "ruim-2@falha-envio.example"] }, "203.0.113.95");
    assert.equal(r.status, 500);
    const body = await r.json();
    assert.equal(body.ok, false);
    assert.equal(body.enviado, false);
    assert.equal(body.enviados, 0);
    assert.equal(body.falhas, 2);
    assert.equal(body.total, 2);
    assert.deepEqual(body.ids, []);
    assert.equal(body.erros.length, 2);
    assert.notEqual(r.status, 207);
  } finally { restaurar(); }
});

test("EMAILSILENT1 residual: lote misto conta sucesso e nomeia falha", async () => {
  const { env, ctx } = criarAmbiente();
  const restaurar = instalarResendMock();
  try {
    const r = await chamar(env, ctx, { action: "email_enviar", admin_senha: "senha-admin-teste", assunto: "teste", html: "<p>misto</p>", destinatarios: ["lote-misto-ok@example.com", "lote-misto-ruim@falha-envio.example"] }, "203.0.113.94");
    assert.equal(r.status, 207);
    const body = await r.json();
    assert.equal(body.ok, false);
    assert.equal(body.enviado, false);
    assert.equal(body.enviados, 1);
    assert.equal(body.falhas, 1);
    assert.equal(body.total, 2);
    assert.deepEqual(body.ids, ["mock-resend-id-0001"]);
    assert.equal(body.erros.length, 1);
    assert.equal(body.erros[0].destinatario, "lote-misto-ruim@falha-envio.example");
    assert.match(String(body.erros[0].erro), /422/);
  } finally { restaurar(); }
});