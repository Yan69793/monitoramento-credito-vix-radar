// node --test scripts/predictive/ews2/integracao/
import { test } from "node:test";
import assert from "node:assert/strict";
import { validarPayload, fundir, remover, flagAtiva } from "./ews2_adapter.mjs";

const AGORA = Date.UTC(2026, 9, 18, 12); // relogio dos testes: pacotes de 16/10 tem 2 dias

const bom = () => ({
  schema: "ews2/1", protocolo: "G0-v3", versao_pipeline: "ews2-backtest-v0.1", gerado_em: "2026-10-16T00:00:00Z",
  sha256_rotulos: "a".repeat(64), homologacao: { g1a: true, g1b: true, g1c: true, g2: true, g3: false },
  sinais_aprovados: ["H1"], exibir_probabilidade: false, data_observacao: "2026-10-16",
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
  const r = fundir(base, bom(), { ativo: true }, AGORA);
  assert.equal(r.ews2.ativo, true);
  assert.equal(r.ews2.cobertos, 1);
  assert.deepEqual(r.emissores[0].predictive_v1, base.emissores[0].predictive_v1);
  assert.deepEqual(r.emissores[0].ews2.sinais, { H1: 1 });
  assert.equal(r.emissores[0].ews2.prob_180d, null);
  assert.equal(r.emissores[1].ews2, null);
  const comG3 = { ...bom(), homologacao: { g1a: true, g1b: true, g1c: true, g2: true, g3: true }, exibir_probabilidade: true };
  assert.equal(fundir(base, comG3, { ativo: true }, AGORA).emissores[0].ews2.prob_180d, 0.2);
});

test("flag ligada com payload invalido: nada muda e o motivo e dito", () => {
  const base = pv1();
  const r = fundir(base, { ...bom(), sinais_aprovados: ["H9"] }, { ativo: true }, AGORA);
  assert.equal(r.ews2.ativo, false);
  assert.match(r.ews2.motivo, /desconhecido/);
  assert.deepEqual(r.emissores, base.emissores);
});

test("rollback puro devolve o payload sem EWS 2.0", () => {
  const base = pv1();
  const r = remover(fundir(base, bom(), { ativo: true }, AGORA));
  assert.deepEqual(r, base);
});

// Liberacao operacional (nota 126): duas pontas.
import { anexarEws, liberacaoValida, LIBERACAO_NOTA_SHA256, LIBERACAO_MODO } from "./ews2_adapter.mjs";
const liberado = () => ({ schema: "ews2/1", sha256_rotulos: "b".repeat(64), homologacao: { g1a: false, g1b: false, g1c: true, g2: false, g3: false },
  liberacao: { modo: LIBERACAO_MODO, nota_sha256: LIBERACAO_NOTA_SHA256 }, sinais_aprovados: ["H1", "H6"], exibir_probabilidade: false,
  data_observacao: "2026-10-16", emissores: [{ cnpj: "1", nome: "Raízen", sinais: { H1: 1, H6: 1 }, prob_180d: null, severidade: "alta" }] });
test("liberacao com hash exato aceita homologacao reprovada", () => {
  assert.equal(liberacaoValida(liberado()), true);
  assert.equal(validarPayload(liberado()).ok, true);
});
test("liberacao com hash errado, modo errado ou ausente continua bloqueando", () => {
  assert.equal(validarPayload({ ...liberado(), liberacao: { modo: LIBERACAO_MODO, nota_sha256: "0".repeat(64) } }).ok, false);
  assert.equal(validarPayload({ ...liberado(), liberacao: { modo: "outro", nota_sha256: LIBERACAO_NOTA_SHA256 } }).ok, false);
  const { liberacao: _l, ...sem } = liberado();
  assert.equal(validarPayload(sem).ok, false);
});
test("liberacao nao libera probabilidade sem G3", () => {
  assert.equal(validarPayload({ ...liberado(), exibir_probabilidade: true }).ok, false);
});
test("anexarEws acrescenta ews2 sem tocar campos e respeita a flag", () => {
  const ews = [{ empresa: "Raízen", score: 40 }, { empresa: "Outra", score: 10 }];
  const r = anexarEws(ews, liberado(), { ativo: true }, AGORA);
  assert.deepEqual(r[0], { empresa: "Raízen", score: 40, ews2: { severidade: "alta", sinais: { H1: 1, H6: 1 }, data_observacao: "2026-10-16" } });
  assert.deepEqual(r[1], { empresa: "Outra", score: 10 });
  assert.deepEqual(anexarEws(ews, liberado(), { ativo: false }), ews);
  assert.deepEqual(anexarEws(ews, liberado(), null), ews);
  assert.deepEqual(anexarEws(ews, { ...liberado(), liberacao: null }, { ativo: true }, AGORA), ews);
});

// EWS2IDADE1: pacote velho some sozinho. Duas pontas: 14 dias aparece, 15 nao; sem data nao aparece.
import { pacoteFresco, idadeDias, IDADE_MAX_DIAS } from "./ews2_adapter.mjs";
test("pacote ate IDADE_MAX_DIAS aparece, acima some, sem data some", () => {
  const ews = [{ empresa: "Raízen", score: 40 }];
  const em = (dia) => Date.UTC(2026, 9, 16 + dia, 12);
  assert.equal(IDADE_MAX_DIAS, 14);
  assert.equal(idadeDias(liberado(), em(14)), 14);
  assert.ok(anexarEws(ews, liberado(), { ativo: true }, em(14))[0].ews2);
  assert.deepEqual(anexarEws(ews, liberado(), { ativo: true }, em(15)), ews);
  assert.deepEqual(anexarEws(ews, { ...liberado(), data_observacao: null }, { ativo: true }, em(0)), ews);
  assert.deepEqual(anexarEws(ews, { ...liberado(), data_observacao: "16/10/2026" }, { ativo: true }, em(0)), ews);
  assert.equal(pacoteFresco(liberado(), Date.UTC(2026, 9, 1)), false); // data no futuro distante tambem nao vale
  const f = fundir({ emissores: [{ name: "Alfa" }] }, bom(), { ativo: true }, em(30));
  assert.equal(f.ews2.ativo, false);
  assert.match(f.ews2.motivo, /pacote velho/);
});
