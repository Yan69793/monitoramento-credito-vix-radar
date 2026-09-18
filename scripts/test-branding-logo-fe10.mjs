import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// FE-10 — logo_data_url entrava sem escape no atributo src da imagem, em dois
// pontos do frontend e num ponto do Worker (render do relatorio compartilhado).
//
// Prova de duas pontas, estrutural, sobre os arquivos REAIS:
//   node scripts/test-branding-logo-fe10.mjs
// Contra o blob pre-correcao, deve FALHAR:
//   git show HEAD:api/src/worker.js > $TEMP/worker.pre.js
//   git show HEAD:app/index.html   > $TEMP/index.pre.html
//   node scripts/test-branding-logo-fe10.mjs $TEMP/worker.pre.js $TEMP/index.pre.html
//
// O que este teste mede, por comportamento e nao por forma:
//   1. a validacao de gravacao do Worker recusa valor que carrega aspas, e
//      aceita os valores legitimamente gerados pelo frontend (FileReader);
//   2. o render do Worker passa o valor pela funcao de escape;
//   3. os pontos do frontend que montam <img src> com o logo escapam o valor.

const raizRepo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argWorker = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raizRepo, "api", "src", "worker.js");
const argApp = process.argv[3] ? path.resolve(process.argv[3]) : path.join(raizRepo, "app", "index.html");

const worker = readFileSync(argWorker, "utf8");
const html = readFileSync(argApp, "utf8");
console.log(`[fe10] worker auditado: ${argWorker} (${worker.length} bytes)`);
console.log(`[fe10] frontend auditado: ${argApp} (${html.length} bytes)`);

// casos legitimamente gerados por FileReader.readAsDataURL no frontend
const legitimos = [
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U",
  "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjwvc3ZnPg==",
  "",
];

// valores que tentam sair do atributo src
const maliciosos = [
  'data:image/png;base64,x" onerror="alert(1)',
  "data:image/png;base64,x' onerror='alert(1)",
  'data:image/svg+xml;base64,x"><script>alert(1)</script>',
  "javascript:alert(1)",
  "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
];

function extrairRegexGravacao(src) {
  // o literal tem "/" dentro da propria classe de caracteres
  // ([A-Za-z0-9+/=]), entao a varredura e pelo fim: ".test(s)" e o fechamento.
  const m = src.match(/\/\^data:image[\s\S]{0,160}?\/\.test\(s\)/);
  if (!m) return null;
  // remove apenas ".test(s)" (8 caracteres), preservando as duas barras do literal
  const literal = m[0].slice(0, -".test(s)".length);
  return new RegExp(literal.slice(1, -1));
}

test("a validacao de gravacao recusa valor com aspas", () => {
  const re = extrairRegexGravacao(worker);
  assert.ok(re, "regex de gravacao do logo nao encontrada no Worker");
  const aceitos = maliciosos.filter((v) => re.test(v));
  assert.deepEqual(aceitos, [], `validacao de gravacao aceitou valor perigoso: ${aceitos.join(" | ")}`);
});

test("a validacao de gravacao aceita os valores legitimamente gerados", () => {
  const re = extrairRegexGravacao(worker);
  assert.ok(re, "regex de gravacao do logo nao encontrada no Worker");
  for (const v of legitimos) {
    // a string vazia e o caminho de limpeza, tratado antes desta regex
    if (v === "") continue;
    assert.equal(re.test(v), true, `valor legitimo recusado: ${v.slice(0, 40)}...`);
  }
});

test("o render do Worker passa o logo pela funcao de escape", () => {
  const m = worker.match(/const logoImg = [^\n]{0,400}/);
  assert.ok(m, "atribuicao de logoImg nao encontrada no Worker");
  assert.match(m[0], /escapeHtml\(br\.logo_data_url\)/, "logo_data_url entra cru no atributo src do relatorio");
});

test("nenhum ponto do frontend monta <img src> com o logo sem escape", () => {
  const semEscape = [];
  const re = /<img src="'\s*\+\s*([A-Za-z_$][\w$.]*)/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const expr = m[1];
    if (!/logo/i.test(expr)) continue;
    // aceita apenas quando a expressao vem embrulhada em funcao de escape
    const antes = html.slice(Math.max(0, m.index - 40), m.index);
    const embrulhado = /[A-Za-z_$][\w$]*\(\s*$/.test(antes);
    if (!embrulhado) semEscape.push(`${expr} @ linha ${html.slice(0, m.index).split("\n").length}`);
  }
  assert.deepEqual(semEscape, [], `logo sem escape em <img src>: ${semEscape.join(" | ")}`);
});

test("o atributo nao quebra quando o valor carrega aspas", () => {
  const re = extrairRegexGravacao(worker);
  const escapeHtml = (s) =>
    String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

  for (const v of maliciosos) {
    assert.equal(re.test(v), false, `gravacao aceitou: ${v}`);
    // mesmo que um valor perigoso chegasse ao render (dado antigo em KV),
    // o escape tem que conter o dano dentro do atributo: nenhuma aspa crua
    // pode sobrar entre src=" e o fim do valor, e nenhum "<" pode sobrar solto.
    const tag = `<img src="${escapeHtml(v)}" alt="logo">`;
    assert.match(
      tag,
      /^<img src="[^"]*" alt="logo">$/,
      `escape nao conteve o payload dentro do atributo: ${tag}`,
    );
    assert.equal(/[<]/.test(escapeHtml(v)), false, `escape deixou "<" cru no valor: ${escapeHtml(v)}`);
  }
});
