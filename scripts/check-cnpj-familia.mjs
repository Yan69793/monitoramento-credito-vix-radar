#!/usr/bin/env node
// SUBSTRINGDONO1, fase CNPJ (2026-08-25) — guarda de quarentena nao declarada.
//
// scripts/gerar-familia-cnpj.mjs PROPOE candidato a familia e imprime para revisao a
// mao. Esta guarda faz a pergunta oposta e automatica: existe candidato plausivel
// que ficou de fora, sem CNPJ_FAMILIA_CVM declarado no worker.js e sem estar na
// lista de recusas? Se existir, e o mesmo estado que deixou a CSN sem fonte
// primaria por meses, so que agora detectavel antes do deploy em vez de descoberto
// numa auditoria.
//
// "Plausivel" aqui quer dizer: o CNPJ protocolou no ipe_cia_aberta do ano E o nome
// dele casa com algum emissor da carteira pelo mesmo criterio que roda em producao
// (_donoDocumentoCVM). Nao e todo CNPJ desconhecido do universo, e o subconjunto
// que um humano olhando o nome reconheceria na hora. E exatamente essa lacuna que
// this script fecha: entre "existe e ninguem viu" e "existe e alguem decidiu".
//
// Fonte de dado: data/cvm-referencia/ipe_entidades_*.json.gz, o indice do ANO
// gerado por scripts/gerar-familia-cnpj.mjs --snapshot. Fixo e versionado de
// proposito, para a guarda nao depender do que a CVM estiver servindo no dia
// (mesma razao do CURADORIA2 usar SNAPSHOT_CVM em vez de bater na rede toda hora).
// Rodar `node scripts/gerar-familia-cnpj.mjs --snapshot <csv>` para atualizar antes
// de auditar um periodo novo.
//
// Uso:
//   node scripts/check-cnpj-familia.mjs
//   node scripts/check-cnpj-familia.mjs --json

import { readFileSync } from "node:fs";
import { WORKER, RECUSADOS, soDigito, formatarCnpj, montarArbitroPorNome, lerEntidades } from "./gerar-familia-cnpj.mjs";

const JSON_OUT = process.argv.includes("--json");
const desescapar = (s) => String(s)
  .replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
  .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));

// Mesma leitura de scripts/check-emissores-cnpj.mjs: CNPJ_FAMILIA_CVM e uma IIFE no
// worker.js, o bloco curado a mao esta dentro de `_subs`, chave CNPJ e valor emissor.
function extrairFamiliaDeclarada(src) {
  const m = src.match(/var _subs\s*=\s*\{([\s\S]*?)\n {2}\};/);
  if (!m) throw new Error("_subs (bloco interno de CNPJ_FAMILIA_CVM) nao encontrado em " + WORKER);
  const out = new Set();
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) out.add(soDigito(desescapar(p[1])));
  return out;
}
function extrairPrimarioDeclarado(src) {
  const m = src.match(/var CNPJ_PRIMARIO_EMISSOR\s*=\s*\{([\s\S]*?)\n\};/);
  if (!m) throw new Error("CNPJ_PRIMARIO_EMISSOR nao encontrado em " + WORKER);
  const out = new Set();
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) out.add(soDigito(p[1]));
  return out;
}

function main() {
  const src = readFileSync(WORKER, "utf8");
  const arb = montarArbitroPorNome(src);
  const declarados = new Set([...extrairPrimarioDeclarado(src), ...extrairFamiliaDeclarada(src)]);
  const recusados = new Set(Object.keys(RECUSADOS).map(soDigito));

  const ent = lerEntidades();
  if (!ent) {
    console.error("ERRO: nenhum snapshot em data/cvm-referencia/. Rode node scripts/gerar-familia-cnpj.mjs --snapshot <ipe_cia_aberta.csv> primeiro.");
    process.exit(2);
  }

  const naoDeclarados = [];
  for (const cn in ent.payload.entidades) {
    if (declarados.has(cn)) continue;
    if (recusados.has(cn)) continue;
    const o = ent.payload.entidades[cn];
    const emp = arb.dono(o.nome);
    if (!emp) continue; // nome nao sugere nenhum emissor da carteira, nao e candidato
    naoDeclarados.push({ cnpj: formatarCnpj(cn), sugestao: emp, nome: o.nome, docs: o.docs, ultimo: o.ultimo });
  }
  naoDeclarados.sort((a, b) => b.docs - a.docs);

  const resumo = {
    ok: naoDeclarados.length === 0,
    fonte: ent.caminho,
    ano: ent.payload.ano,
    cnpjs_no_indice: Object.keys(ent.payload.entidades).length,
    declarados: declarados.size,
    recusados: recusados.size,
    nao_declarados: naoDeclarados
  };

  if (JSON_OUT) { console.log(JSON.stringify(resumo, null, 2)); process.exit(resumo.ok ? 0 : 1); }

  console.log("Indice: " + ent.caminho + " (ano " + ent.payload.ano + ")");
  console.log("  CNPJs no indice: " + resumo.cnpjs_no_indice);
  console.log("  ja declarados (primario + familia): " + resumo.declarados);
  console.log("  recusados com motivo: " + resumo.recusados);

  if (resumo.ok) {
    console.log("\nOK: nenhum CNPJ plausivel ficou fora da familia sem decisao.");
    process.exit(0);
  }

  console.error("\nREPROVADO: " + naoDeclarados.length + " CNPJ(s) com nome sugestivo e sem decisao.");
  for (const c of naoDeclarados) {
    console.error("  - " + c.cnpj + "  sugestao: " + c.sugestao + "  (" + c.nome + ", " + c.docs + " docs, ultimo " + c.ultimo + ")");
  }
  console.error("\nPara cada um: declare em CNPJ_FAMILIA_CVM (worker.js) se pertence ao emissor sugerido,");
  console.error("ou declare em RECUSADOS (scripts/gerar-familia-cnpj.mjs) com o motivo se nao pertence.");
  process.exit(1);
}

try { main(); } catch (e) {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
}
