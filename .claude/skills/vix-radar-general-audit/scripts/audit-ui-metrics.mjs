#!/usr/bin/env node
/**
 * audit-ui-metrics.mjs — detector da classe de defeito "a UI mente".
 *
 * Motivacao (achado 2026-07-27): o card "Cobertura 62%" da Visao Geral nao media
 * cobertura de varredura, media percentual de emissores SEM alerta, e pintava o
 * numero de verde fixo enquanto o selo ao lado dizia "critico". Backend correto,
 * deploy correto, health verde, e mesmo assim a tela comunicava o oposto do fato.
 * Nenhum check da auditoria geral olhava para isso.
 *
 * O script nao julga semantica sozinho. Ele produz as evidencias que tornam o
 * julgamento barato e obrigatorio:
 *
 *   BLOQUEANTE  Encoding de severidade incoerente — dentro do mesmo bloco visual,
 *               um elemento escolhe a cor por condicao e o vizinho usa cor fixa
 *               da MESMA familia. Prova que o codigo sabe calcular a severidade
 *               e um dos elementos ignora. Foi exatamente o bug do card.
 *
 *   INFO        Cor de familia semantica fixa sobre valor interpolado. Muitas
 *               vezes e intencional (o card "Criticos" e vermelho porque a
 *               categoria e critica). Nao reprova, so lista para leitura.
 *
 *   INVENTARIO  Tabela rotulo -> expressao que alimenta o numero, marcando termos
 *               reservados do glossario de dominio. Revisao humana obrigatoria:
 *               e aqui que "Cobertura" medindo "sem alertas" fica visivel.
 *
 * Uso:
 *   node audit-ui-metrics.mjs "<caminho>/app/index.html"
 *   node audit-ui-metrics.mjs "<caminho>/app/index.html" --verbose
 *
 * Exit: 0 sem bloqueante, 1 com bloqueante, 2 erro de execucao.
 */

import fs from "node:fs";

const args = process.argv.slice(2);
const verbose = args.includes("--verbose");
const alvo = args.find((a) => !a.startsWith("--"));

if (!alvo) {
  console.error("uso: node audit-ui-metrics.mjs <caminho/index.html> [--verbose]");
  process.exit(2);
}
if (!fs.existsSync(alvo)) {
  console.error(`arquivo nao encontrado: ${alvo}`);
  process.exit(2);
}
const html = fs.readFileSync(alvo, "utf8");
const linhaDe = (i) => html.slice(0, i).split("\n").length;

/* ================================================================== *
 * Glossario de termos reservados do dominio VIX Radar.
 * Rotulo de UI que usa um destes precisa medir exatamente isto.
 * Fonte canonica: references/glossario-dominio.md
 * ================================================================== */
const TERMOS_RESERVADOS = {
  cobertura:
    "fracao do universo efetivamente VARRIDA/ANALISADA, ou rodadas de busca concluidas. NUNCA 'emissores sem alerta'.",
  criticos: "contagem de emissores com evento classificado CRITICO pelo pipeline.",
  critico: "evento classificado CRITICO pelo pipeline.",
  relevantes: "contagem de emissores com evento RELEVANTE (excluindo os ja criticos).",
  relevante: "evento classificado RELEVANTE pelo pipeline.",
  emissores: "contagem do universo monitorado (103).",
  ews: "Early Warning Score do emissor.",
  score: "score preditivo de credito.",
  staleness: "idade do dado desde a ultima atualizacao real.",
  varredura: "execucao de analise sobre o universo, nao contagem de alertas.",
};

/* ================================================================== *
 * 1. Familias de cor semantica, inferidas do proprio CSS.
 *    Uma familia = conjunto de classes com o mesmo radical e sufixos
 *    semanticos distintos (ok/warn/crit...). Exigir >=2 membros elimina
 *    o ruido de classes de cor decorativa.
 * ================================================================== */
const SUFIXOS = {
  ok: "verde", success: "verde", healthy: "verde", verde: "verde", estavel: "verde",
  warn: "ambar", alerta: "ambar", atencao: "ambar", relevant: "ambar", ambar: "ambar", attn: "ambar",
  crit: "vermelho", critico: "vermelho", critical: "vermelho", danger: "vermelho",
  erro: "vermelho", neg: "vermelho", vermelho: "vermelho",
};

const declaradas = new Set();
for (const m of html.matchAll(/\.([a-zA-Z][\w-]*)\s*[,{]/g)) declaradas.add(m[1]);

const familias = new Map(); // radical -> Map(classe -> balde)
for (const cls of declaradas) {
  const partes = cls.split("-");
  const sufixo = partes[partes.length - 1].toLowerCase();
  const balde = SUFIXOS[sufixo];
  if (!balde) continue;
  const radical = partes.slice(0, -1).join("-") || "«sem-radical»";
  if (!familias.has(radical)) familias.set(radical, new Map());
  familias.get(radical).set(cls, balde);
}
// familia real precisa de >=2 membros com baldes diferentes
for (const [radical, membros] of familias) {
  if (membros.size < 2 || new Set(membros.values()).size < 2) familias.delete(radical);
}
const classeParaFamilia = new Map();
for (const [radical, membros] of familias) {
  for (const c of membros.keys()) classeParaFamilia.set(c, radical);
}

/* ================================================================== *
 * 2. Slots de severidade: cada atributo class="..." que carrega cor
 *    de familia, marcado como LITERAL ou DINAMICO.
 * ================================================================== */
const slots = [];
for (const m of html.matchAll(/class="([^"]{0,400}?)"/g)) {
  const attr = m[1];
  const dinamico = /'\s*\+|\$\{|"\s*\+|\?/.test(attr);
  const membros = [...classeParaFamilia.keys()].filter((c) => new RegExp(`(^|[\\s"'+])${c}([\\s"'+]|$)`).test(attr));
  let fams = [...new Set(membros.map((c) => classeParaFamilia.get(c)))];
  // Classe montada por variavel: `class="mo-card-chip '+s+'"`. O nome final nunca
  // aparece literal, mas o RADICAL da familia sim. Sem isto o slot dinamico fica
  // invisivel e o par incoerente nao e detectado (era o caso do card "Cobertura").
  if (dinamico) {
    for (const radical of familias.keys()) {
      if (radical === "«sem-radical»") continue;
      if (!fams.includes(radical) && new RegExp(`(^|[\\s"'+])${radical}([\\s"'+-]|$)`).test(attr)) fams.push(radical);
    }
  }
  if (fams.length === 0) continue;
  slots.push({
    idx: m.index,
    attr,
    dinamico,
    familias: fams,
    conteudoInterpolado: /^[^<]{0,12}(?:'\s*\+|\$\{|"\s*\+)/.test(html.slice(m.index + m[0].length + 1, m.index + m[0].length + 40)),
  });
}

/* ================================================================== *
 * BLOQUEANTE — mesma familia, slots vizinhos, um dinamico e outro fixo.
 * ================================================================== */
// LIMITE CONHECIDO (medido em 2026-07-27, nao especulacao): 260 e uma janela de
// PROXIMIDADE, nao de container real. Ela nao alcanca o painel "anomalia-dado" do
// VIX Radar, onde o slot dinamico ("Spread atual") e o literal ("Variacao") ficam
// a 570 caracteres um do outro — esse caso so foi achado por leitura manual.
// Testado subir para 700: nao capturou o caso (o pareamento morre antes por outro
// slot intermediario) e AINDA introduziu um falso positivo, pareando o chip do card
// "Criticos" com o "mo-pulse" do cabecalho, que sao componentes diferentes.
// Trocar a janela por caracteres pela fronteira real do elemento (parse de DOM em
// vez de regex sobre string) e a correcao de verdade. Ate la: a auditoria NAO pode
// tratar exit 0 como "UI toda coerente", so como "nenhum par proximo incoerente".
const JANELA = 260;
// Raiz de container: `class="mo-card"`, `class="kpi-tile"` — a palavra fecha a aspa
// sem modificador. Cruzar uma dessas significa que os dois slots estao em cards
// diferentes e nao se contradizem.
const RE_FRONTEIRA = /class="[^"]*\b(?:card|tile|kpi|metric|panel|stat)"/;
const bloqueantes = [];
for (let i = 0; i < slots.length - 1; i++) {
  for (let j = i + 1; j < slots.length && slots[j].idx - slots[i].idx <= JANELA; j++) {
    const a = slots[i];
    const b = slots[j];
    if (a.dinamico === b.dinamico) continue;
    if (RE_FRONTEIRA.test(html.slice(a.idx, b.idx))) break;
    // Familia CSS diferente NAO descarta: o bug real do card "Cobertura" tinha o
    // valor em mo-healthy (familia "mo-") e o selo em mo-card-chip-* (familia
    // "mo-card-chip-"). Radicais distintos, mesma decisao de severidade.
    const fixo = a.dinamico ? b : a;
    if (!fixo.conteudoInterpolado) continue; // cor fixa sobre texto fixo nao mente
    bloqueantes.push({
      familia: `${fixo.familias.join("/")} vs ${(a.dinamico ? a : b).familias.join("/")}`,
      linha: linhaDe(fixo.idx),
      classeFixa: fixo.attr,
      classeDinamica: (a.dinamico ? a : b).attr.slice(0, 90),
      trecho: html.slice(fixo.idx, fixo.idx + 130).replace(/\s+/g, " "),
    });
    break;
  }
}

/* ================================================================== *
 * INFO — cor de familia fixa sobre valor interpolado (pode ser proposital).
 * ================================================================== */
const informativos = slots.filter((s) => !s.dinamico && s.conteudoInterpolado && !bloqueantes.some((b) => linhaDe(s.idx) === b.linha && b.classeFixa === s.attr));

/* ================================================================== *
 * INVENTARIO — rotulo -> expressao.
 * ================================================================== */
const metricas = [];
const reRotulo = /class="[^"]*(?:card-label|stat-lbl|kpi-label|metric-label|rs-label)[^"]*"[^>]*>([^<'"$]{2,40})<\/(?:div|span)>\s*<(?:div|span) class="([^"]{0,200})"[^>]*>(.{0,110}?)<\/(?:div|span)>/gs;
for (const m of html.matchAll(reRotulo)) {
  const rotulo = m[1].trim();
  if (!rotulo) continue;
  const chave = rotulo.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const reservado = Object.keys(TERMOS_RESERVADOS).find((t) => chave === t || chave.startsWith(t + " "));
  metricas.push({
    rotulo,
    classeValor: m[2].replace(/\s+/g, " ").trim(),
    expressao: m[3].replace(/\s+/g, " ").trim(),
    reservado: reservado || null,
    linha: linhaDe(m.index),
  });
}

/* ================================================================== *
 * Relatorio
 * ================================================================== */
const L = [];
L.push("AUDITORIA DE VERACIDADE DA UI");
L.push(`alvo: ${alvo}`);
L.push(`familias de cor semantica: ${familias.size ? [...familias.keys()].map((r) => `${r}{${[...familias.get(r).keys()].map((c) => (r === "«sem-radical»" ? c : c.slice(r.length + 1))).join("|")}}`).join(", ") : "nenhuma"}`);
L.push("");

if (bloqueantes.length === 0) {
  L.push("[BLOQUEANTE] Nenhum encoding de severidade incoerente.");
} else {
  L.push(`[BLOQUEANTE] ${bloqueantes.length} encoding(s) de severidade incoerente(s):`);
  L.push("");
  bloqueantes.forEach((b, i) => {
    L.push(`  ${i + 1}. linha ${b.linha} — familia "${b.familia}"`);
    L.push(`     cor FIXA:     class="${b.classeFixa}"  (sobre valor interpolado)`);
    L.push(`     cor DINAMICA: class="${b.classeDinamica}"  (vizinho, mesma familia)`);
    L.push(`     O vizinho calcula a severidade; este elemento nao. Um dos dois mente.`);
    L.push(`     ${b.trecho.slice(0, 120)}`);
    L.push("");
  });
}

L.push("");
L.push(`[INFO] ${informativos.length} cor(es) de familia fixa(s) sobre valor interpolado (frequentemente proposital).`);
if (verbose) {
  for (const s of informativos) L.push(`  linha ${linhaDe(s.idx)}: class="${s.attr.slice(0, 70)}"`);
} else if (informativos.length) {
  L.push("  use --verbose para listar.");
}

L.push("");
L.push(`[INVENTARIO] ${metricas.length} metrica(s) rotulo -> expressao.`);
L.push("  Todo TERMO RESERVADO exige conferencia contra references/glossario-dominio.md.");
L.push("");
for (const m of metricas) {
  L.push(`  "${m.rotulo}" (linha ${m.linha})${m.reservado ? "   <<< TERMO RESERVADO" : ""}`);
  L.push(`      expr: ${m.expressao.slice(0, 100)}`);
  if (m.reservado) L.push(`      deve medir: ${TERMOS_RESERVADOS[m.reservado]}`);
}

const reservados = metricas.filter((m) => m.reservado).length;
L.push("");
L.push(`RESUMO: ${bloqueantes.length} bloqueante(s), ${informativos.length} informativo(s), ${reservados} rotulo(s) reservado(s) a conferir.`);

console.log(L.join("\n"));
process.exit(bloqueantes.length > 0 ? 1 : 0);
