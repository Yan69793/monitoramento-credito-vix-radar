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
// RELOGIO-GUARDA1 (2026-08-24): era `new Date().toISOString()`, que e dia civil
// UTC. Entre 21h e 24h BRT a guarda ja imprimia o dia seguinte, e foi assim que a
// rodada das 23h17 do dia 24 declarou "Data de referencia: 2026-08-25".
//
// E a licao do RELOGIO3H1 ao contrario, e por isso vale escrever qual e qual. La o
// defeito foi usar BRT para INSTANTE (`_last_scanned_at` nascia 3h no passado e
// inflava horas_stale). Aqui o defeito era usar UTC para DIA CIVIL. As duas regras
// convivem: instante e UTC cru, dia civil e BRT. Trimestre, exercicio e janela de
// dias sao dia civil, entao BRT.
//
// Sem horario de verao no Brasil desde 2019, o -3h fixo e o mesmo que o Worker usa
// em obterAgoraBRT (api/src/worker.js).
const HOJE = normalizarISO(process.env.METRICAS_HOJE || new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10));
const JSON_OUT = process.argv.includes("--json");

// Emissor que esta na carteira e conscientemente nao tem card. Cada linha e decisao
// com data e motivo, e some quando resolvida. Sem este bloco a guarda vira ruido no
// primeiro emissor que entrar de madrugada, e ai a proxima lacuna real passa junto.
const EXCECOES_COBERTURA = {};

// EXCECAO-FRESCOR1 (2026-08-24). Card RECURADO cuja datacao e real e verificavel,
// mas cai fora da janela do proprio metric_type.
//
// Por que precisa existir. Ate aqui havia so dois estados, card sem o trio (cai no
// balde de pendencia, nao reprova) e card com o trio (julgado pela regua). Faltava o
// terceiro, que e "eu curei, a data e esta, e ela nao passa". Sem ele, quem cura um
// emissor e esbarra num card vencido tem duas saidas e as duas sao ruins: deixar o
// card mudo, e ai ele some dentro do balde dos herdados fingindo que ninguem mexeu,
// ou inventar data mais nova. O primeiro foi o que eu fiz na Unidas e o que a
// auditoria pegou como P2: permite curar o que passa e silenciar o que nao passa,
// mantendo o agregado verde.
//
// A diferenca que faz isto NAO ser um segundo silencio: a excecao exige o trio
// completo no card. A data continua declarada e legivel por maquina, o que fica
// suspenso e so o VEREDICTO. E ela e impressa por nome em toda rodada, junto do
// motivo que a regua deu. Excecao tem que ser mais barulhenta que pendencia, nao
// menos, senao ela vira o buraco de volta com outro nome.
//
// Chave "Emissor / label", nunca so o emissor, para nao dar para cobrir uma
// companhia inteira de uma vez.
const EXCECOES_FRESCOR = {
  "Unidas / Rating": {
    desde: "2026-08-24",
    motivo: "Moody's Local AA.br, ultima acao em jul/2025, sem acao dentro da janela de 365d. Dia exato nao fixado, o card usa 2025-07-01, o COMECO do mes: em regua de frescor o arredondamento nunca pode ser na direcao que lisonjeia, e o fim do mes faria o card parecer mais fresco do que talvez seja. Sai daqui quando houver acao de rating nova."
  }
};

// Acima de quantas excecoes o problema deixa de ser o card e passa a ser a regua.
// Nasce de uma medicao: a carteira tem 103 cards de Rating e so 2 datados dentro da
// janela hoje. Os outros 100 estao SEM DATA, que nao e o mesmo que vencidos, entao
// nao da para condenar a regua ainda (medido de fato: 1 vencido, a Unidas com ~419
// dias, contra 2 aprovados). Mas se a recuracao avancar e o bloco encher, a resposta
// certa e revisar o limite de 365d para rating, nao empilhar linha. Este estopim
// existe para a gente nao sonambular ate 101 excecoes achando que cada uma foi uma
// decisao consciente.
const EXCECOES_FRESCOR_ALERTA = 15;

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
  const frescorTolerado = [];
  const excecoesFrescorOciosas = [];
  const chavesFrescorUsadas = new Set();

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

  // Excecao de frescor apontando para card que nao existe mais. Sem isto, renomear um
  // label deixa a excecao viva cobrindo nada, e ninguem percebe.
  const conferirOrfasFrescor = () => {
    for (const chave of Object.keys(EXCECOES_FRESCOR)) {
      if (!chavesFrescorUsadas.has(chave)) {
        falhas.push({ regra: "excecao_orfa", emissor: chave, detalhe: "excecao de frescor declarada e nao existe card com essa chave. Label renomeado, emissor fora da carteira, ou a chave esta errada" });
      }
    }
  };

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
      const chaveExc = emp + " / " + (card && card.label ? card.label : "sem label");
      const exc = EXCECOES_FRESCOR[chaveExc];
      const presentes = ["as_of", "source_date", "metric_type"].filter((c) => String(card[c] || "").trim());
      if (presentes.length === 0) {
        // EXCECAO-FRESCOR1: excecao sobre card sem datacao e o proprio buraco que
        // este bloco fecha, entao reprova em vez de tolerar. Excecao suspende
        // VEREDICTO, nunca datacao.
        if (exc) {
          chavesFrescorUsadas.add(chaveExc);
          falhas.push({ regra: "excecao_sem_trio", emissor: emp, detalhe: id + ": tem excecao de frescor declarada mas o card nao tem as_of/source_date/metric_type. Excecao so vale para card datado, senao ela vira um segundo silencio" });
          return;
        }
        pendentes.push(id);
        return;
      }
      if (presentes.length < 3) {
        falhas.push({ regra: "trio", emissor: emp, detalhe: id + ": tem " + presentes.join(" e ") + " mas falta " + ["as_of", "source_date", "metric_type"].filter((c) => !presentes.includes(c)).join(" e ") });
        return;
      }

      // 5. Frescor por tipo
      const motivo = julgarFrescor(card, HOJE);
      if (motivo && exc) {
        chavesFrescorUsadas.add(chaveExc);
        frescorTolerado.push({ chave: chaveExc, veredicto: motivo, desde: exc.desde || "sem data", motivo: exc.motivo || "sem motivo" });
        return;
      }
      if (!motivo && exc) {
        // Voltou para dentro da janela. Mesmo tratamento que EXCECOES_COBERTURA da a
        // excecao que ja nao e necessaria: avisa para remover, senao apodrece.
        chavesFrescorUsadas.add(chaveExc);
        excecoesFrescorOciosas.push(chaveExc);
        return;
      }
      if (motivo) falhas.push({ regra: "frescor", emissor: emp, detalhe: id + ": " + motivo });
    });
  }

  conferirOrfasFrescor();

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok: falhas.length === 0, hoje: HOJE, carteira: emissores.length, com_card: comCard.size, no_menu: noMenu.size, cards_sem_datacao: pendentes.length, frescor_tolerado: frescorTolerado, excecoes_frescor_ociosas: excecoesFrescorOciosas, falhas, toleradas, excecoes_ociosas: excecoesOciosas }, null, 2));
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
  if (frescorTolerado.length) {
    console.log("\nExcecao de frescor declarada (" + frescorTolerado.length + "): card RECURADO, datacao real, fora da janela.");
    console.log("Nao reprovam, mas nao sao pendencia: alguem curou, declarou a data e suspendeu o veredicto.");
    for (const t of frescorTolerado) {
      console.log("  - " + t.chave + " | desde " + t.desde);
      console.log("      regua diz: " + t.veredicto);
      console.log("      motivo:    " + t.motivo);
    }
    if (frescorTolerado.length > EXCECOES_FRESCOR_ALERTA) {
      console.log("\n  AVISO: " + frescorTolerado.length + " excecoes, acima do limite de " + EXCECOES_FRESCOR_ALERTA + ".");
      console.log("  Excecao em massa nao e excecao. A partir daqui o suspeito passa a ser a REGUA,");
      console.log("  nao o card. Revisar o limite do metric_type em vez de empilhar mais uma linha.");
    }
  }
  if (excecoesFrescorOciosas.length) {
    console.log("\nAVISO: excecao de frescor que ja nao e necessaria, o card voltou para dentro da janela.");
    console.log("Remover de EXCECOES_FRESCOR: " + excecoesFrescorOciosas.join(", "));
  }
  if (pendentes.length) {
    console.log("\nPendencia declarada: " + pendentes.length + " card(s) sem as_of/source_date/metric_type.");
    console.log("Sao os cards NUNCA RECURADOS, que exibem idade nao declarada no painel, e saem");
    console.log("desta lista conforme o Marco 2 avanca. Card curado que nao passa a regua NAO cai");
    console.log("aqui, vai para a excecao declarada acima, senao os dois estados se confundem.");
  }

  if (falhas.length === 0) {
    console.log("\nOK: toda a carteira tem card e aparece no menu, nenhum orfao, toda fonte citada,");
    if (frescorTolerado.length) {
      // A frase antiga afirmava que TODO card datado esta no prazo. Com excecao viva
      // isso vira mentira, e linha de resumo que mente e pior que resumo nenhum.
      console.log("e todo card datado esta dentro do prazo do seu metric_type, salvo " + frescorTolerado.length + " com");
      console.log("excecao declarada e nomeada acima.");
    } else {
      console.log("e todo card datado esta dentro do prazo do seu metric_type.");
    }
    process.exit(0);
  }

  console.error("\nREPROVADO: " + falhas.length + " problema(s).");
  for (const r of ["cobertura_metrica", "cobertura_menu", "cards", "fonte", "trio", "frescor", "excecao_sem_trio", "excecao_orfa"]) {
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
