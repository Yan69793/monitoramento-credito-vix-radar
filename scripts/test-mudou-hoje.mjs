import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// MUDOUHOJE1 (14/10/2026): o quadro "O que mudou hoje" da Visao Geral filtrava por
// data_evento === hoje. Para edital de assembleia da CVM, data_evento herda a
// Data_Referencia (14/10), enquanto o documento foi entregue em 23/09
// (data_publicacao_fonte). Caso real: Algar Telecom, substituicao de agente fiduciario.
//
// MUDOUHOJE2 (16/10/2026, decisao do operador): "o que mudou hoje" e o que CHEGOU hoje.
// Quando a data de entrega/publicacao e conhecida, ela decide sozinha: entregue hoje entra,
// mesmo com data_evento de outro dia (ex.: edital entregue hoje para assembleia futura, ou
// fato com referencia de ontem); entregue antes de hoje nunca entra, mesmo com data_evento
// de hoje (ex.: CEMIG e Taesa de 16/10, boletim e edital de assembleia entregues antes).
// Sem data de entrega, vale data_evento === hoje (rotina). data_evento nunca e alterado.
//
// Roda sobre o arquivo REAL. Pre-correcao deve falhar nos casos "MUDOUHOJE2":
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-mudou-hoje.mjs $TEMP/index.pre.html

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raiz, "app", "index.html");
const html = readFileSync(alvo, "utf8");

const m = html.match(/function mudouHoje\(e,hoje\)\{.*?\}(?=function ews\(\))/s);
const mudouHoje = m ? new Function(`${m[0]}; return mudouHoje;`)() : null;
const HOJE = "2026-10-16";
const ONTEM = "2026-10-15";

test("a funcao mudouHoje existe e e usada no quadro", () => {
  assert.ok(mudouHoje, "mudouHoje ausente em " + alvo);
  assert.match(html, /changes=\(a\.todosEventos\|\|\[\]\)\.filter\(function\(e\)\{return mudouHoje\(e,today\)/);
});

test("Algar: edital entregue em 23/09 com data_evento de hoje NAO e 'mudou hoje'", () => {
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: "2026-09-23", _origem: "cvm_stitch" }, HOJE), false);
});

test("CEMIG/Taesa: documento de assembleia de hoje entregue antes NAO entra", () => {
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: ONTEM }, HOJE), false);
});

test("evento publicado hoje com data_evento de hoje entra", () => {
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: HOJE }, HOJE), true);
});

test("MUDOUHOJE2: entregue hoje entra mesmo com data_evento de outro dia", () => {
  assert.equal(mudouHoje({ data_evento: ONTEM, data_publicacao_fonte: HOJE }, HOJE), true); // referencia de ontem
  assert.equal(mudouHoje({ data_evento: "2026-10-30", data_publicacao_fonte: HOJE }, HOJE), true); // assembleia futura
  assert.equal(mudouHoje({ data_evento: "2025-12-31", data_publicacao_fonte: HOJE + "T09:30:00Z" }, HOJE), true);
});

test("MUDOUHOJE2: entregue antes de hoje nunca entra, qualquer que seja data_evento", () => {
  assert.equal(mudouHoje({ data_evento: ONTEM, data_publicacao_fonte: ONTEM }, HOJE), false);
  assert.equal(mudouHoje({ data_evento: "2026-10-30", data_publicacao_fonte: ONTEM }, HOJE), false);
});

test("evento de hoje sem data de publicacao (rotina) entra", () => {
  assert.equal(mudouHoje({ data_evento: HOJE }, HOJE), true);
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: "" }, HOJE), true);
  assert.equal(mudouHoje({ data_evento: HOJE + "T10:00:00Z" }, HOJE), true);
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: "nao_identificada" }, HOJE), true);
});

test("sem data de publicacao, evento de outro dia nunca entra", () => {
  assert.equal(mudouHoje({ data_evento: ONTEM }, HOJE), false);
  assert.equal(mudouHoje({}, HOJE), false);
  assert.equal(mudouHoje(null, HOJE), false);
});
