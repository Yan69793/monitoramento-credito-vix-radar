#!/usr/bin/env node
// SENDASGPA1 (auditoria 2026-08-24) - guarda contra alias contraditorio.
//
// Por que existe: SYNC_ALIAS_TO_EMPRESA tinha "SENDAS DISTRIB" apontando para o Assai e
// "SENDAS DISTRIBUIDORA" apontando para o GPA, dois emissores diferentes da carteira. O
// documento da CVM chega com "SENDAS DISTRIBUIDORA S.A.", que contem as DUAS chaves, e
// todo consumidor casa por substring. Quem varre com for..in e para no primeiro match
// acertava por ordem de insercao. Quem inverte a tabela e coleta todos os aliases de cada
// emissor (SYNC_EMPRESA_TO_ALIASES, introduzido no NOMEMORTO1 no mesmo dia) errava, e
// passou a entregar documento do Assai para o GPA.
//
// A licao e mais geral que o caso: numa tabela consultada por substring, duas chaves onde
// uma esta contida na outra so podem apontar para o mesmo emissor. Se apontam para
// emissores diferentes, o resultado depende da ordem de iteracao de quem consulta, e cada
// consumidor novo e um sorteio. Nenhum teste pegava isso porque cada consumidor, isolado,
// devolvia um resultado plausivel.
//
// O que faz:
//   1. reprova alias contido em outro alias apontando para emissor diferente
//   2. reprova alias apontando para emissor que nao esta em EMISSORES_LISTA
//   3. reprova chave da tabela privada do leitor que nao e nome de emissor
//
// Uso:
//   node scripts/check-alias-coerencia.mjs
//   node scripts/check-alias-coerencia.mjs --json
// Saida: exit 0 se coerente, 1 se ha contradicao ou ponteiro morto, 2 se nao deu para ler.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
// Mesmo override do check-emissores-cadastro.mjs, pela mesma razao: sem ele so da para
// provar que a guarda aprova o caso bom, e prova de um lado so esconde guarda quebrada
// (regra 5 do CLAUDE.md).
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
const JSON_OUT = process.argv.includes("--json");

// O worker.js e um bundle com unicode escapado (\xE9). Sem desescapar, "Assa\xED
// Atacadista" nunca casaria com o emissor "Assai Atacadista" da lista.
function desescapar(s) {
  return s.replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
          .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

function extrairEmissores(src) {
  const m = src.match(/var EMISSORES_LISTA\s*=\s*\[([\s\S]*?)\];/);
  if (!m) throw new Error("EMISSORES_LISTA nao encontrada em api/src/worker.js");
  return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
}

function extrairAliasToEmpresa(src) {
  const m = src.match(/var SYNC_ALIAS_TO_EMPRESA\s*=\s*\{([\s\S]*?)\n\};/);
  if (!m) throw new Error("SYNC_ALIAS_TO_EMPRESA nao encontrada em api/src/worker.js");
  const pares = [];
  // Linha de comentario nunca vira par: o regex exige aspas no inicio do campo, e
  // comentario aqui comeca com //. Confirmado pelo teste de sanidade abaixo.
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) {
    pares.push({ alias: desescapar(p[1]), empresa: desescapar(p[2]) });
  }
  return pares;
}

// Tabela privada dentro de buscarDocumentosCVM. Ela sobrevive ao NOMEMORTO1 de proposito
// (tem aliases que nao servem para atribuir, so para buscar), mas as chaves dela tem que
// ser nome de emissor, senao sao entradas que nunca sao consultadas.
function extrairAliasesDoLeitor(src) {
  const m = src.match(/async function buscarDocumentosCVM[\s\S]*?const aliases = \{([\s\S]*?)\n    \};/);
  if (!m) throw new Error("tabela 'aliases' de buscarDocumentosCVM nao encontrada");
  return [...m[1].matchAll(/^\s*"([^"]+)"\s*:\s*\[/gm)].map((x) => desescapar(x[1]));
}

function main() {
  const src = readFileSync(WORKER, "utf8");
  const emissores = extrairEmissores(src);
  const pares = extrairAliasToEmpresa(src);
  const chavesLeitor = extrairAliasesDoLeitor(src);

  // Sanidade: se o parse degradar (bundle minificado de outro jeito, refatoracao), a
  // guarda passaria verde por nao achar nada. Ausencia de dado nao pode virar aprovacao.
  if (emissores.length < 50 || pares.length < 20 || chavesLeitor.length < 10) {
    console.error(`ERRO: parse raso (emissores=${emissores.length} aliases=${pares.length} leitor=${chavesLeitor.length}). Estrutura do worker.js mudou, ajustar os regex antes de confiar nesta guarda.`);
    process.exit(2);
  }

  const emissorSet = new Set(emissores);
  const contradicoes = [];
  const orfaos = [];
  const leitorOrfao = [];

  // 1. alias contido em outro alias, apontando para emissor diferente.
  for (let i = 0; i < pares.length; i++) {
    for (let j = i + 1; j < pares.length; j++) {
      const a = pares[i], b = pares[j];
      if (a.empresa === b.empresa) continue;
      const contido = a.alias.includes(b.alias) || b.alias.includes(a.alias);
      if (contido) contradicoes.push({ a: a.alias, empresa_a: a.empresa, b: b.alias, empresa_b: b.empresa });
    }
  }

  // 2. alias apontando para emissor que saiu da carteira.
  for (const p of pares) {
    if (!emissorSet.has(p.empresa)) orfaos.push(p);
  }

  // 3. chave do leitor que nao e emissor: entrada que nunca sera consultada.
  for (const k of chavesLeitor) {
    if (!emissorSet.has(k)) leitorOrfao.push(k);
  }

  const ok = contradicoes.length === 0 && orfaos.length === 0 && leitorOrfao.length === 0;

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok, emissores: emissores.length, aliases: pares.length, chaves_leitor: chavesLeitor.length, contradicoes, orfaos, leitor_orfao: leitorOrfao }, null, 2));
  } else {
    console.log(`Emissores: ${emissores.length} | Aliases de atribuicao: ${pares.length} | Chaves da tabela do leitor: ${chavesLeitor.length}`);
    if (contradicoes.length) {
      console.error(`\nREPROVADO: ${contradicoes.length} par(es) de alias em contradicao. Um alias esta contido no outro e eles apontam para emissores diferentes, entao o resultado depende de quem consulta primeiro:`);
      for (const c of contradicoes) console.error(`  - "${c.a}" -> ${c.empresa_a}   CONTRA   "${c.b}" -> ${c.empresa_b}`);
      console.error("\nDecida de qual emissor e a razao social e deixe UMA chave. O casamento e por substring, a mais curta ja cobre a mais longa.");
    }
    if (orfaos.length) {
      console.error(`\nREPROVADO: ${orfaos.length} alias apontando para emissor fora de EMISSORES_LISTA:`);
      for (const o of orfaos) console.error(`  - "${o.alias}" -> "${o.empresa}" (nao existe na carteira)`);
    }
    if (leitorOrfao.length) {
      console.error(`\nREPROVADO: ${leitorOrfao.length} chave da tabela de buscarDocumentosCVM que nao e nome de emissor, logo nunca e consultada:`);
      for (const k of leitorOrfao) console.error(`  - "${k}"`);
    }
    if (ok) console.log("\nOK: nenhum alias contraditorio, nenhum ponteiro para emissor inexistente.");
  }
  process.exit(ok ? 0 : 1);
}

try {
  main();
} catch (e) {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
}
