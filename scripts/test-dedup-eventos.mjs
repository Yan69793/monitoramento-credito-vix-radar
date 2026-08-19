#!/usr/bin/env node
// DEDUP1 (2026-08-19): regressao para _normTituloDedup/_isDupSemantico e para a
// ordenacao de _v201Coletar em app/index.html. Nao ha suite de teste para app/
// (HTML/JS servido direto, sem package.json - ver CLAUDE.md secao Testes), entao
// isto roda como script standalone: `node scripts/test-dedup-eventos.mjs`.
//
// Extrai as funcoes DIRETO do arquivo real (nunca reescreve/cola copia), entao
// nao ha como este teste ficar verde com codigo diferente do que esta em producao.
//
// Bug original: normalizacao removia "novo/nova/novos/novas" (palavras com
// significado temporal), truncava o titulo em 70 caracteres, e considerava
// duplicata qualquer titulo igual dentro de uma janela de 45 dias - suficiente
// para colapsar atualizacao real de uma mesma saga (RJ/RE em capitulos, rating
// revisado, comunicado complementar) contra o evento original.

import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const INDEX_HTML = path.join(ROOT, "app", "index.html");

function extrairFuncoesDedup(html) {
  const i = html.indexOf("function _normTituloDedup");
  const j = html.indexOf("</script></head>", i);
  if (i < 0 || j < 0) throw new Error("_normTituloDedup nao encontrado em app/index.html - arquivo mudou de forma?");
  return html.slice(i, j);
}

function extrairColetar(html) {
  const i = html.indexOf("function _v201Coletar");
  const j = html.indexOf("function _v201RenderBanner", i);
  if (i < 0 || j < 0) throw new Error("_v201Coletar nao encontrado em app/index.html - arquivo mudou de forma?");
  return html.slice(i, j);
}

const html = readFileSync(INDEX_HTML, "utf-8");
const src = extrairFuncoesDedup(html) + ";globalThis._isDupSemantico=_isDupSemantico;globalThis._normTituloDedup=_normTituloDedup;";
eval(src);

let falhas = 0;
function casoCru(nome, existentes, evNovo, esperado) {
  const dup = globalThis._isDupSemantico(evNovo, existentes);
  const ok = dup === esperado;
  if (!ok) falhas++;
  console.log((ok ? "PASS" : "FAIL") + " - " + nome + " | esperado=" + esperado + " obtido=" + dup);
}
function caso(nome, empresa, antigo, novo, esperado) {
  casoCru(nome, [{ ...antigo, empresa }], { ...novo, empresa }, esperado);
}

caso(
  "republicacao real da mesma nota (fio), mesma URL base -> deduplica",
  "Raízen",
  { titulo: "Justica homologa plano de recuperacao extrajudicial da Raizen", data_evento: "2026-07-28", fonte_primaria: "https://braziljournal.com/x?utm_source=twitter" },
  { titulo: "Justica homologa plano de recuperacao extrajudicial da Raizen", data_evento: "2026-07-30", fonte_primaria: "https://braziljournal.com/x" },
  true
);

caso(
  "mesma URL fonte, titulo reescrito por agregador -> deduplica (fonte manda mais que texto)",
  "Eneva",
  { titulo: "Eneva capta R$ 900 milhoes em nova debenture", data_evento: "2026-08-10", fonte_primaria: "https://valor.globo.com/x?src=share" },
  { titulo: "Eneva: emissao de debenture de R$ 900 mi e concluida", data_evento: "2026-08-11", fonte_primaria: "https://valor.globo.com/x" },
  true
);

caso(
  "matinal + noturno mesma nota, mesmo dia, mesma empresa -> deduplica (intradia legitimo)",
  "Oi",
  { titulo: "Oi segue em recuperacao judicial, sem fato relevante novo hoje", data_evento: "2026-08-18", fonte_primaria: "" },
  { titulo: "Oi segue em recuperacao judicial, sem fato relevante novo hoje", data_evento: "2026-08-18", fonte_primaria: "" },
  true
);

caso(
  "capitulo novo de RJ/RE dias depois, titulo bem diferente -> MANTEM",
  "Oncoclínicas",
  { titulo: "Justica defere o processamento da recuperacao extrajudicial de R$ 5,1 bilhoes", data_evento: "2026-08-04", fonte_primaria: "https://mercadoeconsumo.com.br/a" },
  { titulo: "Oncoclinicas: acionistas ratificam pedido de recuperacao extrajudicial apos aval da Justica", data_evento: "2026-08-13", fonte_primaria: "https://fincred.com.br/b" },
  false
);

caso(
  "comunicado complementar, so a palavra 'nova' diferencia -> MANTEM (novo/nova nao e mais removido)",
  "CSN",
  { titulo: "CSN comunica ao mercado sobre revisao do covenant de divida", data_evento: "2026-08-05", fonte_primaria: "https://cvm.gov.br/a" },
  { titulo: "CSN comunica ao mercado sobre nova revisao do covenant de divida", data_evento: "2026-08-18", fonte_primaria: "https://cvm.gov.br/b" },
  false
);

caso(
  "atualizacao de rating dias depois de evento anterior -> MANTEM",
  "Light",
  { titulo: "Light informa sobre andamento do processo de recuperacao judicial", data_evento: "2026-07-20", fonte_primaria: "https://a.com/1" },
  { titulo: "Fitch rebaixa rating da Light para CCC apos revisao trimestral", data_evento: "2026-08-15", fonte_primaria: "https://b.com/2" },
  false
);

caso(
  "nota de analista repetida em dias DIFERENTES sem fato novo -> MANTEM (dia diferente descaracteriza dup)",
  "Kora Saúde",
  { titulo: "Kora Saude segue em processo de recuperacao extrajudicial, sem fato novo na janela", data_evento: "2026-08-14", fonte_primaria: "https://cvm.gov.br/x" },
  { titulo: "Kora Saude segue em processo de recuperacao extrajudicial, sem fato novo na janela", data_evento: "2026-08-18", fonte_primaria: "https://cvm.gov.br/y" },
  false
);

casoCru(
  "titulo identico, MESMO dia, empresas DIFERENTES -> MANTEM (dedup nao cruza empresa)",
  [{ titulo: "Emissao de debentures aprovada pelo conselho", data_evento: "2026-08-10", empresa: "CEMIG", fonte_primaria: "https://a.com/1" }],
  { titulo: "Emissao de debentures aprovada pelo conselho", data_evento: "2026-08-10", empresa: "Equatorial Energia", fonte_primaria: "https://b.com/2" },
  false
);

console.log("---");
console.log(falhas === 0 ? "TODOS OS CASOS PASSARAM" : falhas + " CASO(S) FALHARAM");

// Ordenacao: numa colisao real, sobrevive o evento mais NOVO, nao o primeiro que chegou.
const coletarSrc = extrairColetar(html);
eval(coletarSrc.replace(/^function _v201Coletar/, "globalThis._v201Coletar = function"));
globalThis._v201PassaFiltro = () => true; // fora de escopo deste teste

const resultadosSim = {
  raizen: {
    empresa: "Raízen",
    eventos: [
      { titulo: "Justica homologa plano de recuperacao extrajudicial da Raizen", data_evento: "2026-07-28", fonte_primaria: "https://braziljournal.com/x?utm_source=twitter" },
      { titulo: "Justica homologa plano de recuperacao extrajudicial da Raizen", data_evento: "2026-07-30", fonte_primaria: "https://braziljournal.com/x" },
    ],
  },
};
globalThis.resultados = resultadosSim;
globalThis.ARQUIVO_PRE = {};
const sobreviventes = globalThis._v201Coletar();
const ordemOk = sobreviventes.length === 1 && sobreviventes[0].data_evento === "2026-07-30";
console.log((ordemOk ? "PASS" : "FAIL") + " - dup real sobrevive com a data MAIS RECENTE (2026-07-30): " + JSON.stringify(sobreviventes.map((e) => e.data_evento)));
if (!ordemOk) falhas++;

if (falhas > 0) {
  console.error(falhas + " falha(s) no total.");
  process.exit(1);
}
console.log("OK: dedup de eventos passou em todos os casos.");
