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
import { EMISSOR_CNPJ, SEM_ITR_CVM, EXERCICIO_DESLOCADO, A_DECIDIR, SNAPSHOT_CVM, SNAPSHOT_CVM_EM } from "./emissores-cnpj.mjs";

// SUBSTRINGDONO1, fase CNPJ (2026-08-25). Existem agora QUATRO copias de dado
// relacionado: este arquivo (canonico, ITR/Altman), scripts/predictive/
// cnpj_emissores.json (o mesmo uso, gerado por atualizar_altman_cvm.ps1),
// CNPJ_PRIMARIO_EMISSOR no worker.js (espelho deste arquivo, porque o Worker roda
// no Cloudflare e nao importa codigo local) e CNPJ_FAMILIA_CVM no worker.js (holding
// mais subsidiarias, usado na atribuicao de IPE).
//
// O projeto ja foi mordido exatamente por isto, tres tabelas de alias que
// precisavam concordar e nao concordavam (NOMEMORTO1, 2026-08-24). Sem uma guarda
// comparando as quatro, a camada CNPJ recria o mesmo problema que veio resolver, so
// que em dado mais dificil de conferir a olho: divergencia de nome se ve lendo o
// card, divergencia de CNPJ so aparece quando alguem confere numero contra numero.

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
const PREDICTIVE = process.env.CNPJ_PREDICTIVE_PATH || join(RAIZ, "scripts", "predictive", "cnpj_emissores.json");
const ITR_DIR = process.env.ITR_DIR || "";
const JSON_OUT = process.argv.includes("--json");

function soDigito(s) {
  return String(s || "").replace(/\D/g, "");
}

// CNPJ_PRIMARIO_EMISSOR no worker.js e declarado invertido em relacao a
// EMISSOR_CNPJ, chave e o CNPJ e valor e o nome do emissor, porque e assim que
// _atribuirDocumentoCVM consulta (recebe CNPJ, quer o emissor). A guarda devolve
// no formato emissor -> CNPJ, espelhando EMISSOR_CNPJ, para a comparacao ficar
// simetrica.
function extrairMapaWorker(src, nome) {
  const m = src.match(new RegExp("var " + nome + "\\s*=\\s*\\{([\\s\\S]*?)\\n\\};"));
  if (!m) throw new Error(nome + " nao encontrada em " + WORKER);
  const out = {};
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) out[desescapar(p[2])] = desescapar(p[1]);
  return out;
}
// CNPJ_FAMILIA_CVM e uma IIFE, nao um literal. O que a guarda precisa e o bloco
// `_subs` interno, que e a parte curada a mao (o resto vem de CNPJ_PRIMARIO_EMISSOR).
function extrairFamiliaWorker(src) {
  const m = src.match(/var _subs\s*=\s*\{([\s\S]*?)\n {2}\};/);
  if (!m) throw new Error("_subs (bloco interno de CNPJ_FAMILIA_CVM) nao encontrado em " + WORKER);
  const out = {};
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) out[desescapar(p[1])] = desescapar(p[2]);
  return out;
}

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

  // 5. Snapshot, offline. Antes desta checagem, um CNPJ bem formado mas digitado
  // errado so era pego pela rodada agendada, que baixa o indice, e podia ficar ate
  // uma semana no repo. Agora cai no push. O snapshot tambem e o que torna a
  // declaracao revisavel a olho, porque poe a razao social ao lado do emissor.
  for (const [emp, cnpj] of Object.entries(EMISSOR_CNPJ)) {
    if (!Object.prototype.hasOwnProperty.call(SNAPSHOT_CVM, cnpj)) {
      falhas.push({ regra: "fora_do_snapshot", emissor: emp, detalhe: cnpj + " nao esta no SNAPSHOT_CVM. Se e CNPJ novo, rode a rodada agendada para regravar o snapshot; se e digitacao errada, corrija o CNPJ" });
    } else if (!SNAPSHOT_CVM[cnpj]) {
      falhas.push({ regra: "snapshot_vazio", emissor: emp, detalhe: cnpj + " esta no snapshot sem razao social. Snapshot foi gravado de um indice incompleto" });
    }
  }
  for (const cnpj of Object.keys(SNAPSHOT_CVM)) {
    if (!porCnpj.has(cnpj)) falhas.push({ regra: "snapshot_orfao", emissor: SNAPSHOT_CVM[cnpj] || cnpj, detalhe: cnpj + " esta no SNAPSHOT_CVM e nenhum emissor aponta para ele" });
  }

  // 6. Opcional, so com o ITR baixado: o CNPJ existe mesmo no indice da CVM?
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
      if (!noIndice.has(cnpj)) { falhas.push({ regra: "cnpj_ausente_cvm", emissor: emp, detalhe: cnpj + " nao aparece no itr_cia_aberta_2026. CNPJ errado, ou a companhia deixou de protocolar e o emissor pertence a SEM_ITR_CVM" }); continue; }
      conferidosNaCvm++;
      // Snapshot contra o indice vivo. E aqui que renomeacao societaria aparece,
      // e ela nao e teorica neste projeto: a Eletrobras virou AXIA em 2025 e ficou
      // nove meses invisivel, a CCR virou Motiva e a Omega virou Serena (NOMEMORTO1).
      const vivo = noIndice.get(cnpj);
      const congelado = SNAPSHOT_CVM[cnpj];
      if (congelado && vivo !== congelado) {
        falhas.push({ regra: "snapshot_desatualizado", emissor: emp, detalhe: cnpj + " mudou de razao social na CVM. Snapshot de " + SNAPSHOT_CVM_EM + " diz " + JSON.stringify(congelado) + ", o indice vivo diz " + JSON.stringify(vivo) + ". Confirme que ainda e a companhia certa e regrave o snapshot" });
      }
    }
  }

  // 7. Reconciliacao das quatro fontes. Requisito, nao item de lista: sem isto a
  // camada CNPJ recria o NOMEMORTO1 em dado que ninguem confere a olho.
  let primarioWorker = {}, familiaWorker = {}, predictiva = {};
  const workerSrc = readFileSync(WORKER, "utf8");
  try { primarioWorker = extrairMapaWorker(workerSrc, "CNPJ_PRIMARIO_EMISSOR"); }
  catch (e) { falhas.push({ regra: "worker_sem_primario", emissor: "(estrutural)", detalhe: e.message }); }
  try { familiaWorker = extrairFamiliaWorker(workerSrc); }
  catch (e) { falhas.push({ regra: "worker_sem_familia", emissor: "(estrutural)", detalhe: e.message }); }
  try { predictiva = JSON.parse(readFileSync(PREDICTIVE, "utf8")); }
  catch (e) { falhas.push({ regra: "predictiva_ilegivel", emissor: "(estrutural)", detalhe: PREDICTIVE + ": " + e.message }); }

  // 7a. CNPJ_PRIMARIO_EMISSOR no worker.js tem que ser espelho fiel de EMISSOR_CNPJ.
  // Se divergirem, a guarda daqui aprova e o Worker em producao reprova, ou vice-versa.
  if (Object.keys(primarioWorker).length) {
    for (const emp of new Set([...Object.keys(EMISSOR_CNPJ), ...Object.keys(primarioWorker)])) {
      const a = soDigito(EMISSOR_CNPJ[emp]), b = soDigito(primarioWorker[emp]);
      if (a === b) continue;
      falhas.push({ regra: "primario_worker_diverge", emissor: emp, detalhe: "canonico=" + (EMISSOR_CNPJ[emp] || "ausente") + " worker.js=" + (primarioWorker[emp] || "ausente") + ". CNPJ_PRIMARIO_EMISSOR precisa ser copia fiel de EMISSOR_CNPJ" });
    }
  }

  // 7b. Familia nao pode conter um CNPJ que ja e primario de OUTRO emissor. Se
  // vazasse, o card de balanco de um emissor passaria a ler o ITR do outro.
  const primariosDig = new Map();
  for (const [emp, cnpj] of Object.entries(EMISSOR_CNPJ)) primariosDig.set(soDigito(cnpj), emp);
  for (const [cnpj, emp] of Object.entries(familiaWorker)) {
    const donoPrimario = primariosDig.get(soDigito(cnpj));
    if (donoPrimario && donoPrimario !== emp) {
      falhas.push({ regra: "familia_vaza_primario", emissor: emp, detalhe: cnpj + " esta em CNPJ_FAMILIA_CVM apontando para " + emp + ", mas e o CNPJ PRIMARIO de " + donoPrimario + ". Um emissor nao pode aparecer na familia de outro" });
    }
  }

  // 7c. Predictiva contra canonico. SEM_ITR_CVM e excecao tolerada de proposito: o
  // canonico nao declara primario para quem nao protocola ITR, mas a predictiva
  // (uso de Altman/reconciliador) pode ter CNPJ de IPE mesmo assim.
  if (Object.keys(predictiva).length) {
    for (const emp of emissores) {
      const a = EMISSOR_CNPJ[emp] ? soDigito(EMISSOR_CNPJ[emp]) : null;
      const b = predictiva[emp] ? soDigito(predictiva[emp].cnpj) : null;
      if (a === b) continue;
      if (a === null && SEM_ITR_CVM[emp]) continue; // tolerado, ver 7c acima
      falhas.push({ regra: "predictiva_diverge", emissor: emp, detalhe: "canonico=" + (EMISSOR_CNPJ[emp] || "ausente, SEM_ITR_CVM") + " predictiva=" + (predictiva[emp] ? predictiva[emp].cnpj + " (" + predictiva[emp].denom + ")" : "ausente") + ". Resolver em scripts/predictive/cnpj_emissores.overrides.json e regenerar" });
    }
    for (const emp of Object.keys(predictiva)) {
      if (!emissores.includes(emp)) falhas.push({ regra: "predictiva_orfa", emissor: emp, detalhe: "declarado na predictiva mas nao esta mais na carteira" });
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
    reconciliacao: {
      primario_worker: Object.keys(primarioWorker).length,
      familia_worker: Object.keys(familiaWorker).length,
      predictiva: Object.keys(predictiva).length
    },
    falhas
  };

  if (JSON_OUT) { console.log(JSON.stringify(resumo, null, 2)); process.exit(falhas.length === 0 ? 0 : 1); }

  console.log("Carteira: " + emissores.length);
  console.log("  com CNPJ declarado:      " + resumo.com_cnpj);
  console.log("  sem ITR na CVM:          " + resumo.sem_itr + "  (" + Object.keys(SEM_ITR_CVM).join(", ") + ")");
  console.log("  a decidir:               " + resumo.a_decidir + (resumo.a_decidir ? "  (" + Object.keys(A_DECIDIR).join(", ") + ")" : ""));
  console.log("  exercicio deslocado:     " + resumo.exercicio_deslocado + (resumo.exercicio_deslocado ? "  (" + Object.keys(EXERCICIO_DESLOCADO).join(", ") + ")" : ""));
  console.log("  snapshot da CVM:         " + Object.keys(SNAPSHOT_CVM).length + " razoes sociais congeladas em " + SNAPSHOT_CVM_EM);
  console.log("  conferidos no indice CVM: " + (semItrDir ? "nao conferido offline. O snapshot ja pega digitacao errada; rode com ITR_DIR para pegar renomeacao societaria" : conferidosNaCvm + "/" + resumo.com_cnpj + ", razao social conferida contra o indice vivo"));
  console.log("  reconciliacao (SUBSTRINGDONO1): worker.js primario=" + resumo.reconciliacao.primario_worker + " familia=" + resumo.reconciliacao.familia_worker + " | predictiva=" + resumo.reconciliacao.predictiva + " entradas");

  if (resumo.a_decidir) {
    console.log("\nFora da recuracao ate alguem decidir:");
    for (const [emp, motivo] of Object.entries(A_DECIDIR)) console.log("  - " + emp + ": " + motivo);
  }

  if (!falhas.length) { console.log("\nOK: toda a carteira esta declarada, sem orfa, sem CNPJ repetido."); process.exit(0); }

  console.error("\nREPROVADO: " + falhas.length + " problema(s).");
  for (const r of ["nao_declarado", "duplo_bloco", "orfa", "deslocado_sem_cnpj", "cnpj_formato", "cnpj_duplicado", "cnpj_ausente_cvm",
                   "worker_sem_primario", "worker_sem_familia", "predictiva_ilegivel",
                   "primario_worker_diverge", "familia_vaza_primario", "predictiva_diverge", "predictiva_orfa"]) {
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
