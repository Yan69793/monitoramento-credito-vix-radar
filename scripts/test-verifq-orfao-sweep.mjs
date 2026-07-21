/**
 * Teste unitario da logica de deteccao de pendentes orfaos (VERIFQ-ORFAO1).
 * Replica a decisao pura de detectarPendentesOrfaos sem carregar o monolito
 * nem depender de KV/DO reais.
 * Run: node scripts/test-verifq-orfao-sweep.mjs
 */
import assert from "node:assert/strict";

const HORA_MS = 60 * 60 * 1e3;

function classificarPendente(ev, agoraMs, idsNaFila, limiteMs) {
  if (ev._pendente_verificacao !== true) return null;
  if (!ev._pendente_desde) {
    return { motivo: "sem_timestamp_pendente_desde", idade_h: null };
  }
  const idadeMs = agoraMs - Date.parse(ev._pendente_desde);
  if (!(idadeMs >= limiteMs)) return null;
  if (idsNaFila.has(ev._id)) return null;
  return { motivo: "pendente_sem_fila_alem_do_limite", idade_h: Math.round(idadeMs / 36e5) };
}

let passed = 0;
function check(name, fn) {
  try {
    fn();
    console.log("OK ", name);
    passed++;
  } catch (e) {
    console.error("FAIL", name, e.message);
    process.exitCode = 1;
  }
}

const AGORA = Date.parse("2026-07-21T18:00:00.000Z");

check("evento nao pendente e ignorado", () => {
  const r = classificarPendente({ _pendente_verificacao: false }, AGORA, new Set(), 48 * HORA_MS);
  assert.equal(r, null);
});

check("pendente recente (< limite) e ignorado, dreno ainda pode processar", () => {
  const ev = { _pendente_verificacao: true, _pendente_desde: new Date(AGORA - 2 * HORA_MS).toISOString(), _id: "x1" };
  const r = classificarPendente(ev, AGORA, new Set(), 48 * HORA_MS);
  assert.equal(r, null);
});

check("pendente antigo mas ainda na fila e ignorado (dreno pode chegar)", () => {
  const ev = { _pendente_verificacao: true, _pendente_desde: new Date(AGORA - 72 * HORA_MS).toISOString(), _id: "x2" };
  const r = classificarPendente(ev, AGORA, new Set(["x2"]), 48 * HORA_MS);
  assert.equal(r, null);
});

check("pendente antigo E fora da fila e marcado orfao", () => {
  const ev = { _pendente_verificacao: true, _pendente_desde: new Date(AGORA - 72 * HORA_MS).toISOString(), _id: "x3" };
  const r = classificarPendente(ev, AGORA, new Set(["outro-id"]), 48 * HORA_MS);
  assert.ok(r);
  assert.equal(r.motivo, "pendente_sem_fila_alem_do_limite");
  assert.equal(r.idade_h, 72);
});

check("pendente sem _pendente_desde (legado pre-v4.9.171) nunca e retratado automaticamente", () => {
  const ev = { _pendente_verificacao: true, _id: "x4" };
  const r = classificarPendente(ev, AGORA, new Set(), 48 * HORA_MS);
  assert.ok(r);
  assert.equal(r.motivo, "sem_timestamp_pendente_desde");
  assert.equal(r.idade_h, null);
});

check("limite exatamente no limiar conta como orfao (>=, nao >)", () => {
  const ev = { _pendente_verificacao: true, _pendente_desde: new Date(AGORA - 48 * HORA_MS).toISOString(), _id: "x5" };
  const r = classificarPendente(ev, AGORA, new Set(), 48 * HORA_MS);
  assert.ok(r);
  assert.equal(r.idade_h, 48);
});

console.log(`\n${passed} testes passaram.`);
if (process.exitCode) {
  console.error("Alguns testes falharam.");
} else {
  console.log("Todos os testes passaram.");
}
