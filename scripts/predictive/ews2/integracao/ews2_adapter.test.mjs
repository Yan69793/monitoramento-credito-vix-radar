// node --test scripts/predictive/ews2/integracao/
import { test } from "node:test";
import assert from "node:assert/strict";
import { validarPayload, fundir, remover, flagAtiva } from "./ews2_adapter.mjs";

const bom = () => ({
  schema: "ews2/1", protocolo: "G0-v3", versao_pipeline: "ews2-backtest-v0.1", gerado_em: "2026-10-16T00:00:00Z",
  sha256_rotulos: "a".repeat(64), homologacao: { g1a: true, g1b: true, g1c: true, g2: true, g3: false },
  sinais_aprovados: ["H1"], exibir_probabilidade: false,
  emissores: [{ cnpj: "00.000.000/0001-00", nome: "Alfa", sinais: { H1: 1 }, prob_180d: 0.2, severidade: "alta" }],
});
const pv1 = () => ({ schema_v: 2, modelo: "rule_v1+logistic_v2", emissores: [{ name: "Alfa", predictive_v1: { score: 10 } }, { name: "Beta", predictive_v1: { score: 5 } }] });

test("payload valido passa; defeitos sao nomeados", () => {
  assert.equal(validarPayload(bom()).ok, true);
  const r = validarPayload({ ...bom(), homologacao: { g1a: true, g1b: false, g1c: true } });
  assert.equal(r.ok, false);
  assert.ok(r.erros.some((e) => e.includes("g1b")));
  assert.equal(validarPayload({ ...bom(), homologacao: { ...bom().homologacao, g2: false } }).ok, false);
  assert.equal(validarPayload({ ...bom(), sinais_aprovados: [] }).ok, false);
  assert.equal(validarPayload({ ...bom(), exibir_probabilidade: true }).ok, false); // sem G3
  assert.equal(validarPayload({ ...bom(), sha256_rotulos: "x" }).ok, false);
  assert.equal(validarPayload(null).ok, false);
});

test("flag desligada: payload original intocado", () => {
  const base = pv1();
  const r = fundir(base, bom(), { ativo: false });
  assert.equal(r.ews2.ativo, false);
  assert.deepEqual(r.emissores, base.emissores);
  assert.deepEqual(fundir(base, bom(), null).emissores, base.emissores);
  assert.equal(flagAtiva({ ativo: "true" }), false);
});

test("flag ligada + homologado: acrescenta sem alterar campos existentes, sem probabilidade antes do G3", () => {
  const base = pv1();
  const r = fundir(base, bom(), { ativo: true });
  assert.equal(r.ews2.ativo, true);
  assert.equal(r.ews2.cobertos, 1);
  assert.deepEqual(r.emissores[0].predictive_v1, base.emissores[0].predictive_v1);
  assert.deepEqual(r.emissores[0].ews2.sinais, { H1: 1 });
  assert.equal(r.emissores[0].ews2.prob_180d, null);
  assert.equal(r.emissores[1].ews2, null);
  const comG3 = { ...bom(), homologacao: { g1a: true, g1b: true, g1c: true, g2: true, g3: true }, exibir_probabilidade: true };
  assert.equal(fundir(base, comG3, { ativo: true }).emissores[0].ews2.prob_180d, 0.2);
});

test("flag ligada com payload invalido: nada muda e o motivo e dito", () => {
  const base = pv1();
  const r = fundir(base, { ...bom(), sinais_aprovados: ["H9"] }, { ativo: true });
  assert.equal(r.ews2.ativo, false);
  assert.match(r.ews2.motivo, /desconhecido/);
  assert.deepEqual(r.emissores, base.emissores);
});

test("rollback puro devolve o payload sem EWS 2.0", () => {
  const base = pv1();
  const r = remover(fundir(base, bom(), { ativo: true }));
  assert.deepEqual(r, base);
});
