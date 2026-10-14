import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// MUDOUHOJE1 (14/10/2026): o quadro "O que mudou hoje" da Visao Geral filtrava por
// data_evento === hoje. Para edital de assembleia da CVM, data_evento herda a
// Data_Referencia (14/10), enquanto o documento foi entregue em 23/09
// (data_publicacao_fonte). Caso real: Algar Telecom, substituicao de agente fiduciario.
// O filtro agora tambem exige que a publicacao da fonte, quando conhecida, seja de hoje.
// data_evento nunca e alterado.
//
// Roda sobre o arquivo REAL. Pre-correcao deve falhar:
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-mudou-hoje.mjs $TEMP/index.pre.html

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raiz, "app", "index.html");
const html = readFileSync(alvo, "utf8");

const m = html.match(/function mudouHoje\(e,hoje\)\{.*?\}(?=function ews\(\))/s);
const mudouHoje = m ? new Function(`${m[0]}; return mudouHoje;`)() : null;
const HOJE = "2026-10-14";

test("a funcao mudouHoje existe e e usada no quadro", () => {
  assert.ok(mudouHoje, "mudouHoje ausente em " + alvo);
  assert.match(html, /changes=\(a\.todosEventos\|\|\[\]\)\.filter\(function\(e\)\{return mudouHoje\(e,today\)/);
});

test("Algar: edital entregue em 23/09 com data_evento de hoje NAO e 'mudou hoje'", () => {
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: "2026-09-23", _origem: "cvm_stitch" }, HOJE), false);
});

test("evento publicado hoje entra", () => {
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: HOJE }, HOJE), true);
});

test("evento de hoje sem data de publicacao (rotina) entra", () => {
  assert.equal(mudouHoje({ data_evento: HOJE }, HOJE), true);
  assert.equal(mudouHoje({ data_evento: HOJE, data_publicacao_fonte: "" }, HOJE), true);
  assert.equal(mudouHoje({ data_evento: HOJE + "T10:00:00Z" }, HOJE), true);
});

test("evento de outro dia nunca entra", () => {
  assert.equal(mudouHoje({ data_evento: "2026-10-13", data_publicacao_fonte: HOJE }, HOJE), false);
  assert.equal(mudouHoje({ data_evento: "2026-10-13" }, HOJE), false);
  assert.equal(mudouHoje(null, HOJE), false);
});
