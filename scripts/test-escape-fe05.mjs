import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// FE-05 — dois defeitos no mesmo lugar, no card de evento de app/index.html:
//   a) o campo "Impacto para crédito" era o unico dos 17 do card a sair sem
//      escape, com o texto do evento vindo da API entrando cru no innerHTML;
//   b) a funcao de escape se chamava `h`, nome de uma letra que o mesmo arquivo
//      usa 8 vezes como variavel comum (headers de fetch, JSON do health,
//      elemento de DOM, horizonte do P14). Qualquer sombreamento futuro
//      transformaria o card inteiro em sink sem escape, e nenhum teste reprovava.
//
// Prova de duas pontas, estrutural, sobre o arquivo REAL:
//   node scripts/test-escape-fe05.mjs
// Contra o blob pre-correcao, deve FALHAR:
//   git show HEAD:app/index.html > $TEMP/index.pre.html
//   node scripts/test-escape-fe05.mjs $TEMP/index.pre.html
//
// O que este teste mede: nenhuma funcao de escape pode se chamar `h`, e o campo
// impacto_credito do card tem que passar pela funcao de escape do proprio bloco.

const raizRepo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const alvo = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raizRepo, "app", "index.html");

const html = readFileSync(alvo, "utf8");
console.log(`[fe05] arquivo auditado: ${alvo} (${html.length} bytes)`);

const RE_ESCAPE_BODY = /replace\(\s*\/\[\s*&<>"'\]\/g/g;

// Resolve o nome que recebe uma funcao de escape, a partir do offset do corpo dela.
function nomeDaEscapada(src, offsetCorpo) {
  const janela = src.slice(Math.max(0, offsetCorpo - 90), offsetCorpo);
  const m = janela.match(
    /(?:function\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{|([A-Za-z_$][\w$]*)\s*=\s*(?:function\s*\([^)]*\)\s*=>|\(?[^)=]{0,20}\)?\s*=>))/,
  );
  return m ? m[1] || m[2] : null;
}

function definicoesDeEscape(src) {
  const achados = [];
  RE_ESCAPE_BODY.lastIndex = 0;
  let m;
  while ((m = RE_ESCAPE_BODY.exec(src)) !== null) {
    achados.push({ nome: nomeDaEscapada(src, m.index), offset: m.index });
  }
  return achados;
}

test("nenhuma funcao de escape se chama h", () => {
  const defs = definicoesDeEscape(html);
  assert.ok(defs.length > 0, "nenhuma funcao de escape encontrada no arquivo");
  const ruins = defs.filter((d) => d.nome === "h");
  const detalhe = ruins
    .map((d) => `linha ${html.slice(0, d.offset).split("\n").length}`)
    .join(", ");
  assert.deepEqual(ruins, [], `funcao de escape ainda chamada h: ${detalhe}`);
});

test("o campo impacto_credito do card passa pelo escape", () => {
  assert.equal(
    html.includes('${escaparHtml(e.impacto_credito||"")}'),
    true,
    "impacto_credito nao esta embrulhado no escape do bloco",
  );
  assert.equal(
    html.includes('${e.impacto_credito||""}'),
    false,
    "impacto_credito ainda entra cru no card",
  );
});

test("a funcao de escape do card esta declarada no mesmo bloco de script", () => {
  const iCard = html.indexOf('${escaparHtml(e.impacto_credito||"")}');
  assert.ok(iCard > 0, "card de evento nao encontrado");
  const iniBloco = html.lastIndexOf("<script", iCard);
  const fimBloco = html.indexOf("</script>", iCard);
  assert.ok(iniBloco > 0 && fimBloco > iCard, "bloco de script do card nao delimitado");
  const bloco = html.slice(iniBloco, fimBloco);
  assert.match(
    bloco,
    /function\s+escaparHtml\s*\(/,
    "a funcao escaparHtml nao esta declarada no bloco que renderiza o card",
  );
});
