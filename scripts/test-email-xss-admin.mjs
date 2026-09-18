import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// FE-09 — XSS armazenado no painel admin por e-mail do usuario em handler inline.
//
// Prova de duas pontas, estrutural, sobre o arquivo REAL:
//   node scripts/test-email-xss-admin.mjs [caminho/para/index.html]
// Sem argumento, audita app/index.html. Com argumento, audita o arquivo indicado,
// que e como a ponta ruim e medida contra o blob pre-correcao:
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-email-xss-admin.mjs $TEMP/index.pre.html   # DEVE FALHAR
//
// O que este teste mede: nenhum atributo de evento inline do painel de usuarios
// pode carregar o e-mail (nem qualquer interpolacao de dado). O e-mail passa a
// viajar em data-*, que e dado inerte, e o clique e resolvido por listener
// delegado no container.

const raizRepo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(raizRepo, "app", "index.html");

const html = readFileSync(alvo, "utf8");
console.log(`[fe09] arquivo auditado: ${alvo} (${html.length} bytes)`);

const handlersComEmail = [
  "adminAprovar('${e.email}')",
  "adminRejeitar('${e.email}')",
  "adminToggleWhiteLabel('${e.email}'",
];

test("nenhum handler inline carrega o e-mail do usuario", () => {
  for (const frag of handlersComEmail) {
    const n = html.split(frag).length - 1;
    assert.equal(n, 0, `residual de handler inline com e-mail: ${frag} (${n} ocorrencia(s))`);
  }
});

test("nenhum atributo de evento inline no arquivo interpola valor dinamico", () => {
  // on*= seguido de interpolacao de template ou de concatenacao de variavel.
  const padrao = /\bon[a-z]+\s*=\s*["'][^"']{0,200}?(\$\{|\+\s*[A-Za-z_$])/g;
  const achados = [...html.matchAll(padrao)].map((m) => m[0].slice(0, 90));
  assert.deepEqual(achados, [], `handler inline com dado dinamico: ${achados.join(" | ")}`);
});

test("o e-mail viaja em data-admin-email, escapado, ao lado da acao", () => {
  // O nome da funcao de escape mudou em FE-05 (`h` virou `escaparHtml`), entao a
  // asserção mede a forma: o valor do atributo tem que ser uma chamada de escape
  // sobre e.email, qualquer que seja o nome dela agora.
  const attrs = [...html.matchAll(/data-admin-email="([^"]*)"/g)].map((m) => m[1]);
  assert.equal(attrs.length, 5, `esperava 5 botoes com data-admin-email, achei ${attrs.length}`);
  for (const a of attrs) {
    assert.match(a, /^\$\{[A-Za-z_$][\w$]*\(e\.email\)\}$/, `data-admin-email sem escape: ${a}`);
  }
  for (const acao of ["aprovar", "rejeitar", "wl"]) {
    assert.equal(
      html.includes(`data-admin-action="${acao}"`),
      true,
      `acao ${acao} sem atributo de dados`,
    );
  }
});

test("a lista de usuarios tem listener delegado idempotente", () => {
  assert.equal(html.includes("__vixAdminDelegate"), true, "guarda de listener unico ausente");
  const m = html.match(/const e=document\.getElementById\("admin-users-list"\);([\s\S]{0,600})/);
  assert.ok(m, "ancora do container da lista nao encontrada");
  const trecho = m[1];
  assert.match(trecho, /addEventListener\("click"/, "listener delegado ausente");
  assert.match(trecho, /data-admin-action/, "listener nao resolve a acao por data-*");
  assert.match(trecho, /data-admin-email/, "listener nao resolve o e-mail por data-*");
});

test("os tres fluxos continuam ligados as mesmas funcoes", () => {
  const m = html.match(/const e=document\.getElementById\("admin-users-list"\);([\s\S]{0,600})/);
  const trecho = m[1];
  for (const fn of ["adminAprovar(em)", "adminRejeitar(em)", "adminToggleWhiteLabel(em,"]) {
    assert.equal(trecho.includes(fn), true, `fluxo nao preservado: ${fn}`);
  }
});
