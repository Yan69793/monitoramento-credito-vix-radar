#!/usr/bin/env node
// CURADORIA1 (2026-08-24) — guarda de cobertura e frescor dos cards de metrica.
//
// Por que existe: em 24/08/2026 a Braskem entrou na carteira pelo commit b13b605,
// que alterou api/src/worker.js, api/wrangler.toml e check-emissores-cadastro.mjs
// e NAO tocou app/index.html. A carteira mudou so no backend. O frontend ficou com
// AES Brasil no menu, sem Braskem em lugar nenhum, e sem metrica curada para ela.
// No mesmo dia a companhia protocolou recuperacao extrajudicial de US$ 10,9 bi e o
// painel exibia os quatro cards de risco vazios, com "Pendente".
//
// Ninguem viu porque nada no projeto comparava as tres tabelas que precisam
// concordar: EMISSORES_LISTA no Worker (a carteira), EMISSORES no frontend (o menu)
// e METRICAS_CURADAS no frontend (os cards). Mesma familia do NOMEMORTO1, onde eram
// tres tabelas de alias sem nada forcando a concordancia.
//
// LIMITE CONHECIDO, declarado de proposito. Esta guarda le dois arquivos estaticos e
// nao tem como saber de fato publicado depois deles. Entao ela NAO consegue reprovar
// "card desatualizado porque saiu acao de rating nova" nem "porque saiu evento
// critico novo". Isso e revisao manual. O unico candidato a oraculo no repo,
// data/labels/eventos_credito.jsonl, foi medido e nao serve: parou em 2026-07-31 e
// tem zero registros de Braskem, ou seja, aprovaria em silencio justamente o caso
// que originou esta guarda. Guarda que promete checagem que nao consegue fazer e
// pior que guarda ausente, entao aqui o frescor e por prazo fixo por tipo.
//
// Uso:
//   node scripts/check-metricas-curadas.mjs
//   node scripts/check-metricas-curadas.mjs --json
// Exit 0 se passa, 1 se reprova, 2 se nao conseguiu julgar.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
// Overrides existem para a prova de duas pontas: sem eles so da para demonstrar que
// a guarda aprova o caso bom, e prova de um lado so esconde guarda quebrada
// (regra 5 do CLAUDE.md).
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
const FRONTEND = process.env.METRICAS_FRONTEND_PATH || join(RAIZ, "app", "index.html");
// Relogio injetavel. Sem isto, o teste negativo de frescor caducaria sozinho: um
// as_of escolhido hoje para estar vencido pode estar valido daqui a um trimestre, e
// o teste passaria a falhar pelo motivo errado.
const HOJE = normalizarISO(process.env.METRICAS_HOJE || new Date().toISOString().slice(0, 10));
const JSON_OUT = process.argv.includes("--json");

// Emissor que esta na carteira e conscientemente nao tem card. Cada linha e decisao
// com data e motivo, e some quando resolvida. Sem este bloco a guarda vira ruido no
// primeiro emissor que entrar de madrugada, e ai a proxima lacuna real passa junto.
const EXCECOES_COBERTURA = {};

// O worker.js e um bundle com unicode escapado (\xE9). Ler literal deixaria
// "Ita\xFAsa" no lugar de "Itausa" e a guarda acusaria falso positivo.
function desescapar(s) {
  return String(s)
    .replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

// ---------------------------------------------------------------------------
// Extracao
// ---------------------------------------------------------------------------

function extrairEmissores(src) {
  const m = src.match(/var EMISSORES_LISTA\s*=\s*\[([\s\S]*?)\];/);
  if (!m) throw new Error("EMISSORES_LISTA nao encontrada em " + WORKER);
  return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
}

// O frontend e minificado numa linha unica de centenas de KB, entao regex de bloco
// nao serve. Balanceamento de chave respeitando string e escape e o unico jeito
// honesto de recortar o literal inteiro.
function recortarLiteral(txt, marcador, abre, fecha) {
  const p = txt.indexOf(marcador);
  if (p < 0) throw new Error(marcador + " nao encontrado em " + FRONTEND);
  let i = txt.indexOf(abre, p);
  let prof = 0, str = null, esc = false;
  for (let k = i; k < txt.length; k++) {
    const c = txt[k];
    if (esc) { esc = false; continue; }
    if (c === "\\") { esc = true; continue; }
    if (str) { if (c === str) str = null; continue; }
    if (c === '"' || c === "'" || c === "`") { str = c; continue; }
    if (c === abre) prof++;
    else if (c === fecha) { prof--; if (prof === 0) return txt.slice(i, k + 1); }
  }
  throw new Error(marcador + " com chave desbalanceada em " + FRONTEND);
}

function avaliarLiteral(lit, nome) {
  try {
    return new Function("return (" + lit + ")")();
  } catch (e) {
    throw new Error(nome + " nao e literal valido: " + (e && e.message ? e.message : String(e)));
  }
}

function extrairMetricas(html) {
  return avaliarLiteral(recortarLiteral(html, "METRICAS_CURADAS={", "{", "}"), "METRICAS_CURADAS");
}

// SETOR_DE deriva de EMISSORES em runtime, entao o menu real e EMISSORES.
function extrairMenu(html) {
  const obj = avaliarLiteral(recortarLiteral(html, "EMISSORES=", "{", "}"), "EMISSORES");
  const nomes = [];
  for (const [setor, arr] of Object.entries(obj)) {
    if (!Array.isArray(arr)) throw new Error("EMISSORES." + setor + " nao e array");
    for (const n of arr) nomes.push(n);
  }
  return nomes;
}

// ---------------------------------------------------------------------------
// Datas
// ---------------------------------------------------------------------------

function normalizarISO(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(s))) throw new Error("data fora do formato AAAA-MM-DD: " + s);
  return String(s);
}

const FIM_TRIMESTRE = { 1: "03-31", 2: "06-30", 3: "09-30", 4: "12-31" };

// Trimestre vira a ultima data do trimestre, para "2T26" e "2026-06-30" compararem
// iguais. Formato fora dos dois padroes reprova, nao passa em silencio.
function normalizarAsOf(v) {
  const s = String(v || "").trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const m = s.match(/^([1-4])T(\d{2}|\d{4})$/i);
  if (m) {
    const ano = m[2].length === 2 ? "20" + m[2] : m[2];
    return ano + "-" + FIM_TRIMESTRE[Number(m[1])];
  }
  return null;
}

function diasEntre(aISO, bISO) {
  return Math.round((Date.parse(bISO + "T00:00:00Z") - Date.parse(aISO + "T00:00:00Z")) / 86400000);
}

function somarDias(iso, n) {
  return new Date(Date.parse(iso + "T00:00:00Z") + n * 86400000).toISOString().slice(0, 10);
}

function diasUteisEntre(aISO, bISO) {
  let n = 0;
  for (let d = somarDias(aISO, 1); d <= bISO; d = somarDias(d, 1)) {
    const dow = new Date(Date.parse(d + "T00:00:00Z")).getUTCDay();
    if (dow !== 0 && dow !== 6) n++;
  }
  return n;
}

// Ultimo trimestre cuja janela de entrega (fim + 45d) ja venceu, com tolerancia de
// 15d. E o trimestre mais novo que um card honesto ja deveria estar refletindo.
function trimestreExigido(hoje) {
  const ano = Number(hoje.slice(0, 4));
  const candidatos = [];
  for (const a of [ano, ano - 1, ano - 2]) {
    for (const q of [1, 2, 3, 4]) candidatos.push(a + "-" + FIM_TRIMESTRE[q]);
  }
  const vencidos = candidatos.filter((f) => f < hoje && somarDias(f, 45 + 15) <= hoje).sort();
  return vencidos.length ? vencidos[vencidos.length - 1] : null;
}

// Idem para DFP: exercicio fechado + 90d de janela + 15d de tolerancia.
function exercicioExigido(hoje) {
  const ano = Number(hoje.slice(0, 4));
  const cands = [ano - 1 + "-12-31", ano - 2 + "-12-31", ano - 3 + "-12-31"];
  const vencidos = cands.filter((f) => f < hoje && somarDias(f, 90 + 15) <= hoje).sort();
  return vencidos.length ? vencidos[vencidos.length - 1] : null;
}

const TIPOS = ["itr", "dfp", "rating", "anbima", "evento_credito"];

// Devolve string com o motivo da reprovacao, ou null se o card esta no prazo.
function julgarFrescor(card, hoje) {
  const tipo = card.metric_type;
  if (!TIPOS.includes(tipo)) return "metric_type invalido: " + JSON.stringify(tipo) + " (validos: " + TIPOS.join(", ") + ")";
  const asOf = normalizarAsOf(card.as_of);
  if (!asOf) return "as_of fora dos formatos aceitos (AAAA-MM-DD ou NT AA): " + JSON.stringify(card.as_of);
  let src;
  try { src = normalizarISO(card.source_date); } catch (e) { return "source_date invalida: " + JSON.stringify(card.source_date); }
  if (src > hoje) return "source_date no futuro: " + src;
  if (asOf > hoje) return "as_of no futuro: " + asOf;

  if (tipo === "itr") {
    const exigido = trimestreExigido(hoje);
    if (exigido && asOf < exigido) return "ITR defasado: as_of " + asOf + ", mas o trimestre " + exigido + " ja venceu a janela de entrega (45d + 15d de tolerancia)";
    return null;
  }
  if (tipo === "dfp") {
    const exigido = exercicioExigido(hoje);
    if (exigido && asOf < exigido) return "DFP defasada: as_of " + asOf + ", mas o exercicio " + exigido + " ja venceu a janela de entrega (90d + 15d de tolerancia)";
    return null;
  }
  if (tipo === "rating") {
    const d = diasEntre(src, hoje);
    if (d > 365) return "rating sem reafirmacao ha " + d + " dias (limite 365), source_date " + src;
    return null;
  }
  if (tipo === "anbima") {
    const du = diasUteisEntre(src, hoje);
    if (du > 5) return "taxa ANBIMA com " + du + " dias uteis (limite 5), source_date " + src;
    return null;
  }
  // evento_credito
  const d = diasEntre(src, hoje);
  if (d > 30) return "evento de credito com " + d + " dias (limite 30), source_date " + src;
  return null;
}

// ---------------------------------------------------------------------------

function main() {
  const emissores = extrairEmissores(readFileSync(WORKER, "utf8"));
  const html = readFileSync(FRONTEND, "utf8");
  const metricas = extrairMetricas(html);
  const menu = extrairMenu(html);

  if (emissores.length < 50) { console.error("ERRO: so " + emissores.length + " emissores extraidos. Parser quebrou, e parser quebrado nao pode virar aprovacao."); process.exit(2); }
  if (Object.keys(metricas).length < 50) { console.error("ERRO: so " + Object.keys(metricas).length + " emissores em METRICAS_CURADAS. Parser quebrou."); process.exit(2); }

  const naCarteira = new Set(emissores);
  const comCard = new Set(Object.keys(metricas));
  const noMenu = new Set(menu);

  const falhas = [];
  const toleradas = [];
  const pendentes = [];
  const excecoesOciosas = [];

  // 1. Cobertura de metrica
  for (const emp of emissores) {
    if (comCard.has(emp)) { if (EXCECOES_COBERTURA[emp]) excecoesOciosas.push(emp); continue; }
    if (EXCECOES_COBERTURA[emp]) { toleradas.push({ emissor: emp, motivo: EXCECOES_COBERTURA[emp] }); continue; }
    falhas.push({ regra: "cobertura_metrica", emissor: emp, detalhe: "esta na carteira e nao tem card em METRICAS_CURADAS" });
  }
  for (const emp of comCard) {
    if (!naCarteira.has(emp)) falhas.push({ regra: "cobertura_metrica", emissor: emp, detalhe: "tem card curado mas saiu da carteira, orfa acumulando em silencio" });
  }

  // 2. Cobertura de menu
  for (const emp of emissores) {
    if (!noMenu.has(emp)) falhas.push({ regra: "cobertura_menu", emissor: emp, detalhe: "esta na carteira e nao aparece no menu EMISSORES do frontend" });
  }
  for (const emp of noMenu) {
    if (!naCarteira.has(emp)) falhas.push({ regra: "cobertura_menu", emissor: emp, detalhe: "esta no menu do frontend mas saiu da carteira" });
  }

  // 3, 4 e 5. Trio, fonte e frescor, card a card
  for (const [emp, cards] of Object.entries(metricas)) {
    if (!Array.isArray(cards) || !cards.length) { falhas.push({ regra: "cards", emissor: emp, detalhe: "entrada em METRICAS_CURADAS nao e lista de card" }); continue; }
    cards.forEach((card, i) => {
      const id = emp + " / card " + (i + 1) + " (" + (card && card.label ? card.label : "sem label") + ")";
      if (!card || typeof card !== "object") { falhas.push({ regra: "cards", emissor: emp, detalhe: id + ": card nao e objeto" }); return; }

      // 4. Fonte obrigatoria. Regra do projeto e nenhum numero sem fonte citada.
      if (!String(card.fonte || "").trim()) falhas.push({ regra: "fonte", emissor: emp, detalhe: id + ": sem campo fonte" });

      // 3. Integridade do trio. Meio preenchido e pior que vazio: da aparencia de
      // dado datado sem ser, e a checagem de frescor nao teria como rodar.
      const presentes = ["as_of", "source_date", "metric_type"].filter((c) => String(card[c] || "").trim());
      if (presentes.length === 0) { pendentes.push(id); return; }
      if (presentes.length < 3) {
        falhas.push({ regra: "trio", emissor: emp, detalhe: id + ": tem " + presentes.join(" e ") + " mas falta " + ["as_of", "source_date", "metric_type"].filter((c) => !presentes.includes(c)).join(" e ") });
        return;
      }

      // 5. Frescor por tipo
      const motivo = julgarFrescor(card, HOJE);
      if (motivo) falhas.push({ regra: "frescor", emissor: emp, detalhe: id + ": " + motivo });
    });
  }

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok: falhas.length === 0, hoje: HOJE, carteira: emissores.length, com_card: comCard.size, no_menu: noMenu.size, cards_sem_datacao: pendentes.length, falhas, toleradas, excecoes_ociosas: excecoesOciosas }, null, 2));
    process.exit(falhas.length === 0 ? 0 : 1);
  }

  console.log("Data de referencia: " + HOJE);
  console.log("Carteira (EMISSORES_LISTA): " + emissores.length + " | Com card (METRICAS_CURADAS): " + comCard.size + " | No menu (EMISSORES): " + noMenu.size);
  console.log("Trimestre exigido para metric_type=itr: " + trimestreExigido(HOJE) + " | Exercicio exigido para dfp: " + exercicioExigido(HOJE));

  if (toleradas.length) {
    console.log("\nSem card, mas com excecao declarada (" + toleradas.length + "):");
    for (const t of toleradas) console.log("  - " + t.emissor + ": " + t.motivo);
  }
  if (excecoesOciosas.length) {
    console.log("\nAVISO: excecao que ja nao e necessaria, remover de EXCECOES_COBERTURA: " + excecoesOciosas.join(", "));
  }
  if (pendentes.length) {
    console.log("\nPendencia declarada: " + pendentes.length + " card(s) sem as_of/source_date/metric_type.");
    console.log("Nao reprovam ainda. Sao os cards herdados que exibem idade nao declarada no painel,");
    console.log("e saem desta lista conforme o Marco 2 (recuracao) avanca.");
  }

  if (falhas.length === 0) {
    console.log("\nOK: toda a carteira tem card e aparece no menu, nenhum orfao, toda fonte citada,");
    console.log("e todo card datado esta dentro do prazo do seu metric_type.");
    process.exit(0);
  }

  console.error("\nREPROVADO: " + falhas.length + " problema(s).");
  for (const r of ["cobertura_metrica", "cobertura_menu", "cards", "fonte", "trio", "frescor"]) {
    const doTipo = falhas.filter((f) => f.regra === r);
    if (!doTipo.length) continue;
    console.error("\n  [" + r + "] " + doTipo.length);
    for (const f of doTipo) console.error("    - " + f.emissor + ": " + f.detalhe);
  }
  console.error("\nSe foi troca de carteira, o frontend tambem muda: METRICAS_CURADAS e EMISSORES em");
  console.error("app/index.html, nao so EMISSORES_LISTA em api/src/worker.js. Foi exatamente essa");
  console.error("metade esquecida que deixou a Braskem sem card no dia da recuperacao extrajudicial.");
  process.exit(1);
}

try {
  main();
} catch (e) {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
}
