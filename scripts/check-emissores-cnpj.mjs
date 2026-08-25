#!/usr/bin/env node
// CURADORIA2 (2026-08-24) — guarda da tabela emissor -> companhia da CVM.
//
// Por que existe: o Marco 2 vai puxar alavancagem, EBITDA e divida liquida do
// itr_cia_aberta da CVM. Casar emissor com companhia por nome erra e erra feio,
// porque holding e subsidiaria compartilham o nome. Medido: Sabesp casava com a
// COPASA, Taesa com a Copel GT, CBA com a CEB, CSN com a CSN Mineracao. Numero de
// outra empresa exibido com "CVM" na fonte e pior que o dado velho de hoje.
//
// Por isso a atribuicao vive declarada em scripts/emissores-cnpj.mjs e esta guarda
// existe para garantir que ninguem da a volta nela. O que ela cobra:
//
//   1. Todo emissor da carteira esta declarado em exatamente um dos quatro blocos.
//      Emissor novo entrando na carteira reprova ate alguem decidir de quem sai o
//      numero dele. Foi a ausencia desse tipo de cobranca que deixou a Braskem sem
//      card no dia da recuperacao extrajudicial (CURADORIA1).
//   2. Nenhum emissor em dois blocos ao mesmo tempo.
//   3. Nenhuma linha orfa, apontando para emissor que ja saiu da carteira.
//   4. CNPJ com formato valido e sem duplicata, porque dois emissores apontando
//      para a mesma companhia significa que um dos dois esta errado.
//
// Offline por padrao. Com ITR_DIR apontando para o itr_cia_aberta descompactado,
// confere tambem se cada CNPJ declarado existe mesmo no indice da CVM, o que e a
// unica checagem que pega CNPJ digitado errado.
//
// Uso:
//   node scripts/check-emissores-cnpj.mjs
//   ITR_DIR=/caminho/itr node scripts/check-emissores-cnpj.mjs
//   node scripts/check-emissores-cnpj.mjs --json

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { EMISSOR_CNPJ, SEM_ITR_CVM, EXERCICIO_DESLOCADO, A_DECIDIR } from "./emissores-cnpj.mjs";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
const ITR_DIR = process.env.ITR_DIR || "";
const JSON_OUT = process.argv.includes("--json");

const desescapar = (s) => String(s)
  .replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
  .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));

function extrairEmissores(src) {
  const m = src.match(/var EMISSORES_LISTA\s*=\s*\[([\s\S]*?)\];/);
  if (!m) throw new Error("EMISSORES_LISTA nao encontrada em " + WORKER);
  return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
}

// EXERCICIO_DESLOCADO nao e um destino, e uma anotacao sobre um emissor que ja tem
// CNPJ. Por isso fica fora da conta de "exatamente um bloco".
const BLOCOS = { EMISSOR_CNPJ, SEM_ITR_CVM, A_DECIDIR };

function main() {
  const emissores = extrairEmissores(readFileSync(WORKER, "utf8"));
  if (emissores.length < 50) { console.error("ERRO: so " + emissores.length + " emissores extraidos, parser quebrou."); process.exit(2); }

  const falhas = [];

  // 1 e 2. Cobertura e exclusividade.
  for (const emp of emissores) {
    const onde = Object.entries(BLOCOS).filter(([, b]) => Object.prototype.hasOwnProperty.call(b, emp)).map(([n]) => n);
    if (onde.length === 0) falhas.push({ regra: "nao_declarado", emissor: emp, detalhe: "entrou na carteira e ninguem declarou de qual companhia da CVM sai o numero dele. Decida em scripts/emissores-cnpj.mjs: EMISSOR_CNPJ se tem ITR, SEM_ITR_CVM se nao protocola, A_DECIDIR se ainda nao da para dizer" });
    else if (onde.length > 1) falhas.push({ regra: "duplo_bloco", emissor: emp, detalhe: "declarado em " + onde.join(" e ") + " ao mesmo tempo" });
  }

  // 3. Orfas.
  const naCarteira = new Set(emissores);
  for (const [nome, bloco] of Object.entries(BLOCOS)) {
    for (const emp of Object.keys(bloco)) {
      if (!naCarteira.has(emp)) falhas.push({ regra: "orfa", emissor: emp, detalhe: "declarado em " + nome + " mas nao esta mais na carteira" });
    }
  }
  for (const emp of Object.keys(EXERCICIO_DESLOCADO)) {
    if (!naCarteira.has(emp)) falhas.push({ regra: "orfa", emissor: emp, detalhe: "declarado em EXERCICIO_DESLOCADO mas nao esta mais na carteira" });
    else if (!EMISSOR_CNPJ[emp]) falhas.push({ regra: "deslocado_sem_cnpj", emissor: emp, detalhe: "esta em EXERCICIO_DESLOCADO mas nao tem CNPJ declarado, a anotacao nao se aplica a nada" });
  }

  // 4. Formato e duplicata de CNPJ.
  const porCnpj = new Map();
  for (const [emp, cnpj] of Object.entries(EMISSOR_CNPJ)) {
    if (!/^\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}$/.test(cnpj)) {
      falhas.push({ regra: "cnpj_formato", emissor: emp, detalhe: "CNPJ fora do formato NN.NNN.NNN/NNNN-NN: " + JSON.stringify(cnpj) });
      continue;
    }
    if (porCnpj.has(cnpj)) falhas.push({ regra: "cnpj_duplicado", emissor: emp, detalhe: "aponta para o mesmo CNPJ de " + porCnpj.get(cnpj) + " (" + cnpj + "), um dos dois esta errado" });
    else porCnpj.set(cnpj, emp);
  }

  // 5. Opcional, so com o ITR baixado: o CNPJ existe mesmo no indice da CVM?
  let conferidosNaCvm = 0, semItrDir = true;
  if (ITR_DIR) {
    const idxPath = join(ITR_DIR, "itr_cia_aberta_2026.csv");
    if (!existsSync(idxPath)) {
      console.error("ERRO: ITR_DIR definido mas " + idxPath + " nao existe. Ausencia de dado nao pode virar aprovacao silenciosa.");
      process.exit(2);
    }
    semItrDir = false;
    const idx = new TextDecoder("latin1").decode(readFileSync(idxPath));
    const noIndice = new Map();
    for (const l of idx.split("\n").slice(1)) {
      const c = l.split(";");
      if (c.length < 4) continue;
      if (!noIndice.has(c[0])) noIndice.set(c[0], c[3].trim());
    }
    if (noIndice.size < 200) { console.error("ERRO: so " + noIndice.size + " companhias no indice do ITR, download truncado."); process.exit(2); }
    for (const [emp, cnpj] of Object.entries(EMISSOR_CNPJ)) {
      if (!noIndice.has(cnpj)) falhas.push({ regra: "cnpj_ausente_cvm", emissor: emp, detalhe: cnpj + " nao aparece no itr_cia_aberta_2026. CNPJ errado, ou a companhia deixou de protocolar e o emissor pertence a SEM_ITR_CVM" });
      else conferidosNaCvm++;
    }
  }

  const resumo = {
    ok: falhas.length === 0,
    carteira: emissores.length,
    com_cnpj: Object.keys(EMISSOR_CNPJ).length,
    sem_itr: Object.keys(SEM_ITR_CVM).length,
    a_decidir: Object.keys(A_DECIDIR).length,
    exercicio_deslocado: Object.keys(EXERCICIO_DESLOCADO).length,
    conferidos_no_indice_cvm: semItrDir ? null : conferidosNaCvm,
    falhas
  };

  if (JSON_OUT) { console.log(JSON.stringify(resumo, null, 2)); process.exit(falhas.length === 0 ? 0 : 1); }

  console.log("Carteira: " + emissores.length);
  console.log("  com CNPJ declarado:      " + resumo.com_cnpj);
  console.log("  sem ITR na CVM:          " + resumo.sem_itr + "  (" + Object.keys(SEM_ITR_CVM).join(", ") + ")");
  console.log("  a decidir:               " + resumo.a_decidir + (resumo.a_decidir ? "  (" + Object.keys(A_DECIDIR).join(", ") + ")" : ""));
  console.log("  exercicio deslocado:     " + resumo.exercicio_deslocado + (resumo.exercicio_deslocado ? "  (" + Object.keys(EXERCICIO_DESLOCADO).join(", ") + ")" : ""));
  console.log("  conferidos no indice CVM: " + (semItrDir ? "nao conferido, rode com ITR_DIR para checar CNPJ digitado errado" : conferidosNaCvm + "/" + resumo.com_cnpj));

  if (resumo.a_decidir) {
    console.log("\nFora da recuracao ate alguem decidir:");
    for (const [emp, motivo] of Object.entries(A_DECIDIR)) console.log("  - " + emp + ": " + motivo);
  }

  if (!falhas.length) { console.log("\nOK: toda a carteira esta declarada, sem orfa, sem CNPJ repetido."); process.exit(0); }

  console.error("\nREPROVADO: " + falhas.length + " problema(s).");
  for (const r of ["nao_declarado", "duplo_bloco", "orfa", "deslocado_sem_cnpj", "cnpj_formato", "cnpj_duplicado", "cnpj_ausente_cvm"]) {
    const doTipo = falhas.filter((f) => f.regra === r);
    if (!doTipo.length) continue;
    console.error("\n  [" + r + "] " + doTipo.length);
    for (const f of doTipo) console.error("    - " + f.emissor + ": " + f.detalhe);
  }
  process.exit(1);
}

try { main(); } catch (e) {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
}
