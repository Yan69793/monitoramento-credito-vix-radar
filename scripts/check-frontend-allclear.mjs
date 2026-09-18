// check-frontend-allclear.mjs
// Guarda geral contra afirmacao de ausencia sem leitura provada.
//
// Motivo (ZEROINDISPONIVEL1 / ALERTAMERCADOFALSO1 / ANBIMAVERDEFALSO1, auditoria
// 2026-08-20). Em um dia apareceram quatro superficies afirmando ausencia de
// risco a partir de dado que nunca foi lido:
//   - painel EWS na home publica: "Todos os emissores monitorados estao dentro
//     dos parametros normais", com ewsRankingCache === null;
//   - pulso do monitor operacional: verde com "Mercado em estabilidade", com
//     `resultados` vazio;
//   - briefing: "Nenhum alerta de mercado ativo (spread/volume) na janela",
//     alimentado por um detector que nao dispara por construcao;
//   - painel ANBIMA: check verde afirmando "Nenhuma anomalia detectada", com
//     zero debentures analisadas na amostra.
//
// A versao anterior desta guarda cobria 3 frases fixas. Isso resolve o caso de
// ontem e nao o de amanha. Esta versao varre TODA frase de ausencia do arquivo e
// exige que cada uma esteja classificada num manifesto versionado. Frase nova sem
// classificacao reprova, o que forca a decisao a ser tomada em vez de esquecida.
//
// Classificacoes aceitas no manifesto:
//   guardada     - afirma ausencia, mas so depois de provar que a leitura ocorreu
//   rotulo       - rotulo de campo, nao afirma nada sobre a carteira
//   demo         - texto do dataset de demonstracao, nunca sai de modo demo
//   comentario   - a frase so existe dentro de comentario de codigo
//   nao_revisada - encontrada e ainda nao julgada. NAO passa, aparece como pendencia
//
// Uso:
//   node scripts/check-frontend-allclear.mjs
//   node scripts/check-frontend-allclear.mjs --gravar-manifesto   (semeia nao_revisada)

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : d; };
const AQUI = path.dirname(decodeURIComponent(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")));
const ARQ = path.resolve(opt("--arquivo", path.join(AQUI, "..", "app", "index.html")));
const MANIFESTO = path.resolve(opt("--manifesto", path.join(AQUI, "..", "status", "allclear-manifesto.json")));
const GRAVAR = args.includes("--gravar-manifesto");

const src = fs.readFileSync(ARQ, "utf8");

// Extrai literais de string e verifica se afirmam ausencia.
const RE_LITERAL = /(['"`])((?:(?!\1)[^\\]|\\.){8,200}?)\1/g;
const GATILHO = /(nenhum|nenhuma|sem\s+\w|todos os|dentro dos par|estabilidade|nada\s+\w|n[aã]o h[aá])/i;
const LIXO = /(function|=>|querySelector|getElementById|className=|style="[^"]*$)/;

// MANIFESTOFRAGIL1 (PENDENCIAS, achado 20/08): a chave era tirada do literal
// bruto inteiro, tag e estilo inline inclusos. Trocar so a cor de um texto (ex:
// #6b7280 -> #94A3B8, A11YCONTRASTE1) mudava a chave e a frase reaparecia como
// "NOVA" apesar do texto visivel ser identico. Chave agora vem so do texto
// visivel: tag HTML removida antes de normalizar.
function textoVisivel(s) {
  return s.replace(/<[^>]*>/g, " ");
}

function normaliza(s) {
  return textoVisivel(s).replace(/\s+/g, " ").trim()
    .normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]/g, "").slice(0, 90);
}

// Marcadores LOCAIS: precisam existir dentro da JANELA de caracteres ao redor
// da frase. Cada um foi conferido manualmente uma vez: e um ramo de erro que
// roda ANTES da funcao que contem a frase, ou checagem inline no mesmo bloco.
const GUARDAS_LOCAIS = [
  "_ewsCarregou", "_semLeitura", "_detOk", "_nBase", "detector_operacional", "_detectorOperacional",
  "STATE.payload.ok === false"       // agenda: _render() aborta antes de chegar nos ag-empty
];
const JANELA = 3000;

// Marcadores GLOBAIS: o guard mora numa funcao CHAMADORA que pode estar em
// qualquer lugar do arquivo em relacao a frase, entao proximidade textual nao
// serve. AMARRADO POR CHAVE: cada entrada so vale para as frases cujo trecho da
// chave normalizada bate no `quando`, nunca um OR cego pra todo mundo, senao
// remover UM guard esconde a falta atras de outro guard que ainda existe no
// arquivo. Cada marcador foi conferido manualmente lendo o call site uma vez.
const GUARDAS_GLOBAIS = [
  { marcador: "res.ok !== true", quando: /(sem eventos materiais na janela|nenhum dado para os emissores selecionados|nenhum evento nos filt)/,
    onde: "briefing/comparar: o loader so chama o render apos checar res.ok !== true" },
  { marcador: "if (!eventos.length)", quando: /(nenhum destaque narrativo no periodo|periodo sem alertas materiais identificados|sem eventos no periodo|nenhum evento critico ou relevante no periodo selecionado)/,
    onde: "exportar PDF: window.exportar aborta antes de chamar buildHtml" }
];

const encontradas = new Map();
let m;
while ((m = RE_LITERAL.exec(src)) !== null) {
  const bruto = m[2].trim();
  if (!GATILHO.test(bruto)) continue;
  if (LIXO.test(bruto)) continue;
  const chave = normaliza(bruto);
  if (chave.length < 8) continue;
  if (encontradas.has(chave)) continue;
  const ini = Math.max(0, m.index - JANELA);
  const ctx = src.slice(ini, Math.min(src.length, m.index + JANELA));
  const globalAplicavel = GUARDAS_GLOBAIS.find((g) => g.quando.test(chave));
  const temGuarda = GUARDAS_LOCAIS.some((g) => ctx.includes(g)) || (globalAplicavel ? src.includes(globalAplicavel.marcador) : false);
  encontradas.set(chave, {
    chave,
    texto: bruto.replace(/\s+/g, " ").slice(0, 110),
    linha: src.slice(0, m.index).split("\n").length,
    guarda_por_perto: temGuarda
  });
}
const lista = [...encontradas.values()].sort((a, b) => a.linha - b.linha);

if (GRAVAR) {
  const anterior = fs.existsSync(MANIFESTO) ? JSON.parse(fs.readFileSync(MANIFESTO, "utf8")) : { frases: [] };
  const jaClassificada = new Map((anterior.frases || []).map((f) => [f.chave, f]));
  const frases = lista.map((f) => {
    const ant = jaClassificada.get(f.chave);
    return {
      chave: f.chave,
      texto: f.texto,
      classificacao: ant ? ant.classificacao : (f.guarda_por_perto ? "guardada" : "nao_revisada"),
      nota: ant ? ant.nota : ""
    };
  });
  fs.mkdirSync(path.dirname(MANIFESTO), { recursive: true });
  fs.writeFileSync(MANIFESTO, JSON.stringify({
    nota: "Toda frase que afirma ausencia precisa de classificacao. nao_revisada reprova de proposito. Ver ZEROINDISPONIVEL1.",
    total: frases.length, frases
  }, null, 2), "utf8");
  console.log(`MANIFESTO GRAVADO: ${MANIFESTO} (${frases.length} frases)`);
  process.exit(0);
}

if (!fs.existsSync(MANIFESTO)) {
  console.log(`FALHA: manifesto ausente em ${MANIFESTO}. Rode com --gravar-manifesto.`);
  process.exit(1);
}
const manifesto = JSON.parse(fs.readFileSync(MANIFESTO, "utf8"));
const mapa = new Map((manifesto.frases || []).map((f) => [f.chave, f]));

const novas = lista.filter((f) => !mapa.has(f.chave));
const naoRevisadas = lista.filter((f) => mapa.get(f.chave) && mapa.get(f.chave).classificacao === "nao_revisada");
const guardadasSemGuarda = lista.filter((f) => {
  const c = mapa.get(f.chave);
  return c && c.classificacao === "guardada" && !f.guarda_por_perto;
});

console.log(`ARQUIVO: ${path.basename(ARQ)}`);
console.log(`FRASES DE AUSENCIA: ${lista.length} | MANIFESTO: ${manifesto.total}`);
const porClasse = {};
for (const f of lista) { const c = mapa.get(f.chave); const k = c ? c.classificacao : "NOVA"; porClasse[k] = (porClasse[k] || 0) + 1; }
console.log("Por classificacao: " + Object.entries(porClasse).map(([k, v]) => `${k}=${v}`).join("  "));
console.log("");

let falhou = false;
if (novas.length) {
  falhou = true;
  console.log(`FALHA: ${novas.length} frase(s) de ausencia NOVA(S) sem classificacao no manifesto.`);
  novas.forEach((f) => console.log(`   + linha ~${f.linha}: "${f.texto}"`));
}
if (guardadasSemGuarda.length) {
  falhou = true;
  console.log(`FALHA: ${guardadasSemGuarda.length} frase(s) classificada(s) como 'guardada' perderam a guarda no codigo.`);
  guardadasSemGuarda.forEach((f) => console.log(`   ! linha ~${f.linha}: "${f.texto}"`));
}
if (naoRevisadas.length) {
  falhou = true;
  console.log(`FALHA: ${naoRevisadas.length} frase(s) ainda em 'nao_revisada'. Cada uma precisa de veredito.`);
  naoRevisadas.forEach((f) => console.log(`   ? linha ~${f.linha}: "${f.texto}"`));
}
if (falhou) {
  console.log("");
  console.log("Ausencia de dado nao e evidencia de saude. Classifique no manifesto ou pareie com guarda de leitura.");
  process.exit(1);
}
console.log("CHECK_ALLCLEAR_OK todas as frases de ausencia estao classificadas e guardadas.");
process.exit(0);
