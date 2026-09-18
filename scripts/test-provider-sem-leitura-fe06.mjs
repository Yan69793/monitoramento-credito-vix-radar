import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// FE-06 — o monitor de provedores tinha `.catch(function(){})` vazio: falha de
// rede virava silencio e o painel ficava sem indicacao de que nao leu.
//
// Prova de duas pontas, estrutural, sobre o arquivo REAL:
//   node scripts/test-provider-sem-leitura-fe06.mjs
// Contra o blob pre-correcao, deve FALHAR:
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-provider-sem-leitura-fe06.mjs $TEMP/index.pre.html
//
// O que este teste mede, e por que os tres pontos juntos:
//   1. a falha deixa registro (nao ha mais catch vazio);
//   2. o painel passa a exibir "SEM LEITURA" em vez de simplesmente sumir;
//   3. esse estado tem regra de estilo propria com display:block. Sem a regra,
//      a classe nova herda o display:none da regra base #provider-banner e a
//      mensagem nunca aparece na tela — registrada, mas invisivel, que e a
//      mesma falha de origem um nivel abaixo;
//   4. o elemento e criado quando ainda nao existe, para o erro de primeira
//      carga nao cair no vazio.

const raizRepo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raizRepo, "app", "index.html");

const html = readFileSync(alvo, "utf8");
console.log(`[fe06] arquivo auditado: ${alvo} (${html.length} bytes)`);

// o trecho do monitor de provedores, do fetch de status ate o fim da cadeia
function trechoMonitor(src) {
  const i = src.indexOf('action:"status_providers"');
  assert.ok(i > 0, "monitor de provedores nao encontrado no arquivo");
  return src.slice(i, i + 3200);
}

test("a falha do monitor de provedores nao e mais silenciosa", () => {
  const trecho = trechoMonitor(html);
  assert.equal(
    /\.catch\(function\(\)\{\}\)/.test(trecho),
    false,
    "o catch do monitor de provedores continua vazio",
  );
  assert.match(trecho, /_vwarn\("\[providers\]/, "a falha nao deixa registro");
});

test("o painel passa a exibir o estado sem leitura", () => {
  const trecho = trechoMonitor(html);
  assert.match(trecho, /SEM LEITURA/, "o estado sem leitura nao e exibido");
  assert.match(
    trecho,
    /nivel-desconhecido/,
    "a classe do estado sem leitura nao e aplicada",
  );
});

test("o estado sem leitura tem estilo proprio que o torna visivel", () => {
  const regra = html.match(/#provider-banner\.nivel-desconhecido\{[^}]*\}/);
  assert.ok(regra, "nao existe regra CSS para #provider-banner.nivel-desconhecido");
  assert.match(regra[0], /display:block/, "a regra existe mas nao torna o painel visivel");
});

test("o painel e criado quando a primeira carga ja falha", () => {
  const trecho = trechoMonitor(html);
  assert.match(
    trecho,
    /createElement\("div"\)/,
    "sem o elemento criado na falha de primeira carga, a mensagem nao tem onde aparecer",
  );
});
