// SAUDEFILA1 (20/10/2026): fila de verificacao atrasada nao pode pintar "servico indisponivel".
// Rodar: node --test app/tests/saude-sistema.test.mjs
// Prova de duas pontas: o caso de falha real continua vermelho e o caso so-fila vira aviso ambar.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = fs.readFileSync(path.join(APP, 'index.html'), 'utf8');

const m = html.match(/function vxClassificarSaude\(d\)\{[^\n]*\}\n/);
assert.ok(m, 'vxClassificarSaude nao encontrada em app/index.html');
const classificar = new Function(`${m[0]}; return vxClassificarSaude;`)();

// Payload real medido em 20/10/2026 12:59Z (recorte dos campos usados).
const real20out = {
  ok: false, bindings: { kv: true, rate_limiter: true, telemetria: true },
  admin_email_ok: true, sentry_ok: true, verificador_ok: false,
  verif_fila_atrasada: true, cvm_fonte_degrada_servico: false
};

test('caso real de 20/10: so a fila reprova, vira fila_atrasada (sem banner vermelho)', () => {
  assert.equal(classificar(real20out), 'fila_atrasada');
});

test('saudavel: ok true', () => {
  assert.equal(classificar({ ...real20out, ok: true, verificador_ok: true, verif_fila_atrasada: false }), 'ok');
});

test('kv fora continua sendo fora, mesmo com fila atrasada', () => {
  assert.equal(classificar({ ...real20out, bindings: { kv: false, telemetria: true } }), 'fora');
});

test('telemetria fora continua sendo fora', () => {
  assert.equal(classificar({ ...real20out, bindings: { kv: true, telemetria: false } }), 'fora');
});

test('sem resposta (null) e fora', () => {
  assert.equal(classificar(null), 'fora');
});

test('fila atrasada MAIS sentry fora nao e mascarada: degradado', () => {
  assert.equal(classificar({ ...real20out, sentry_ok: false }), 'degradado');
});

test('verificador falho sem fila atrasada (ex: chave invalida) e degradado', () => {
  assert.equal(classificar({ ...real20out, verif_fila_atrasada: false }), 'degradado');
});

test('fonte CVM degradando o servico e degradado', () => {
  assert.equal(classificar({ ...real20out, cvm_fonte_degrada_servico: true }), 'degradado');
});

test('banner e rodape usam a classificacao', () => {
  assert.match(html, /"fila_atrasada"!==vxClassificarSaude\(h\)&&"ok"!==vxClassificarSaude\(h\)&&mostrarBannerConfig\("erro_worker"\)/);
  assert.match(html, /_cls === "fila_atrasada"/);
});
