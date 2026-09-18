import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// FE-08 — as duas funcoes de localStorage do frontend faziam JSON.parse e
// JSON.stringify sem validar forma. Valor corrompido ou escrito por outra
// versao da pagina caia em fallback silencioso, e o sintoma aparecia longe da
// causa. A gravacao ainda tinha catch vazio: falha ao gravar era invisivel.
//
// Prova de duas pontas, estrutural, sobre o arquivo REAL:
//   node scripts/test-ls-forma-fe08.mjs
// Contra o blob pre-correcao, deve FALHAR:
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-ls-forma-fe08.mjs $TEMP/index.pre.html
//
// O que este teste mede: leitura e gravacao rejeitam o que nao casa com a forma
// esperada e deixam registro, em vez de seguir com valor invalido em silencio.

const raizRepo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raizRepo, "app", "index.html");

const html = readFileSync(alvo, "utf8");
console.log(`[fe08] arquivo auditado: ${alvo} (${html.length} bytes)`);

// As tres funcoes sao de uma linha so, dentro de uma linha enorme do arquivo.
// A janela vai do inicio da funcao ate o inicio da proxima, para nao capturar
// o catch de uma funcao vizinha.
function corpo(funcao) {
  const i = html.indexOf(`function ${funcao}(`);
  assert.ok(i > 0, `${funcao} nao encontrada no arquivo`);
  const prox = html.indexOf("function ", i + 10);
  const fim = prox > i ? Math.min(prox, i + 700) : i + 700;
  return html.slice(i, fim);
}

test("existe uma checagem de forma para o que vem do localStorage", () => {
  assert.match(html, /function\s+_lsTipoOk\s*\(/, "_lsTipoOk nao existe");
  const f = corpo("_lsTipoOk");
  for (const tipo of ["array", "objeto", "string", "numero", "booleano"]) {
    assert.ok(f.includes(`"${tipo}"`), `_lsTipoOk nao trata a forma ${tipo}`);
  }
});

test("a leitura valida a forma antes de devolver o valor", () => {
  const f = corpo("_lsGet");
  assert.match(f, /_lsTipoOk\(/, "a leitura nao valida a forma");
  assert.match(f, /_vwarn\(/, "a leitura invalida nao deixa registro");
});

test("a gravacao nao tem catch vazio", () => {
  const f = corpo("_lsSet");
  assert.equal(/catch\([a-z0-9_]*\)\s*\{\s*\}/.test(f), false, "a gravacao ainda tem catch vazio");
  assert.match(f, /_vwarn\(/, "a falha de gravacao nao deixa registro");
});

test("a gravacao recusa valor que nao pode ser serializado", () => {
  const f = corpo("_lsSet");
  assert.match(f, /typeof\s+v\s*===\s*"function"/, "a gravacao nao recusa funcao");
  assert.match(f, /typeof\s+v\s*===\s*"symbol"/, "a gravacao nao recusa symbol");
  assert.match(f, /v\s*===\s*undefined/, "a gravacao nao recusa undefined");
});
