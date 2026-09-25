#!/usr/bin/env node
// Guarda contra acento destruido no frontend (achado de 2026-09-25).
//
// Por que existe: o commit e2983c8 ("make redesigned overview the default landing") inseriu
// o bloco <script> marcado com VIX-DESIGN-2026 com TODO caractere nao-ASCII ja substituido
// por '?'. O texto visivel virou "Vis?o Geral", "O que merece aten??o agora", "Ranking de
// deteriora??o", "fal?ncia", "inadimpl?ncia". O defeito foi para producao e ficou no ar.
//
// Ninguem pegou porque '?' e um caractere ASCII legitimo: passa por qualquer verificacao de
// encoding, o arquivo continua UTF-8 valido, e nao existe erro de sintaxe. O unico sinal e
// semantico: a palavra portuguesa deixou de existir. Foi assim que o valor do KPI "Universo
// monitorado" saiu 0 no mesmo commit, por um caminho diferente (leitura de window.EMISSORES,
// que e undefined porque a declaracao e const e nao cria propriedade em window).
//
// A licao que este arquivo guarda: corrupcao de acento nao se detecta por encoding, se
// detecta por forma da palavra. E o discriminador que separa o falso positivo do defeito real
// e onde o '?' esta: ternario de JavaScript vive em CODIGO, corrupcao de acento vive DENTRO de
// literal de string. Por isso o scanner abaixo rastreia comentario, regex, string simples e
// interpolacao de template, em vez de aplicar regex sobre o arquivo cru. Regex sobre o texto
// cru acusa 8 ternarios legitimos deste frontend como se fossem defeito.
//
// O que faz:
//   1. extrai os literais de string de cada bloco <script> dos arquivos alvo
//   2. reprova '?' colado a letras dos dois lados, que e a assinatura de acento destruido
//   3. preserva ternario (codigo) e literal que e exatamente "?" (placeholder de dado ausente)
//   4. preserva query string do tipo '/version.json?t=', unico formato legitimo que casa
//
// Escopo declarado: SOMENTE literais de string dentro de <script>. Texto estatico solto no
// HTML nao e varrido. Foi onde o defeito real apareceu, e alargar o escopo sem necessidade
// so aumenta a chance de falso positivo.
//
// Uso:
//   node scripts/check-acentos-frontend.mjs
//   node scripts/check-acentos-frontend.mjs --json
//   node scripts/check-acentos-frontend.mjs caminho1.html caminho2.html
// Saida: exit 0 se limpo, 1 se ha acento destruido, 2 se nao deu para ler.

import { readFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

const ALVOS_PADRAO = ["app/index.html", "app/deploy_zip/index.html"];

// --- scanner: onde comeca e onde termina cada literal de string -------------------------

function pularRegex(src, i) {
  const n = src.length;
  let j = i + 1;
  let classe = false;
  while (j < n) {
    const d = src[j];
    if (d === "\\") { j += 2; continue; }
    if (d === "[") classe = true;
    else if (d === "]") classe = false;
    else if (d === "/" && !classe) return j + 1;
    else if (d === "\n") return j;
    j += 1;
  }
  return n;
}

function pularString(src, i) {
  // src[i] e a aspa de abertura. Devolve o indice depois do fechamento.
  const c = src[i];
  const n = src.length;
  let j = i + 1;
  while (j < n) {
    if (src[j] === "\\") { j += 2; continue; }
    if (c === "`" && src[j] === "$" && src[j + 1] === "{") { j = fimDaInterpolacao(src, j + 2); continue; }
    if (src[j] === c) return j + 1;
    j += 1;
  }
  return n;
}

function fimDaInterpolacao(src, i) {
  // src[i-2] e src[i-1] eram '$' e '{'. Devolve o indice depois do '}' par.
  const n = src.length;
  let j = i;
  let prof = 1;
  while (j < n && prof > 0) {
    const c = src[j];
    if (c === "\\") { j += 2; continue; }
    if (c === '"' || c === "'" || c === "`") { j = pularString(src, j); continue; }
    if (c === "/" && src[j + 1] === "/") { const f = src.indexOf("\n", j); j = f === -1 ? n : f + 1; continue; }
    if (c === "/" && src[j + 1] === "*") { const f = src.indexOf("*/", j + 2); j = f === -1 ? n : f + 2; continue; }
    if (c === "{") prof += 1;
    else if (c === "}") prof -= 1;
    j += 1;
  }
  return j;
}

export function literaisDeString(src) {
  const out = [];
  const n = src.length;
  let i = 0;
  let anterior = "";
  const abreRegex = () => anterior === "" || "([{,;=:!&|?+-*%~^<>".includes(anterior);

  while (i < n) {
    const c = src[i];

    if (c === "/" && src[i + 1] === "/") { const f = src.indexOf("\n", i); i = f === -1 ? n : f + 1; continue; }
    if (c === "/" && src[i + 1] === "*") { const f = src.indexOf("*/", i + 2); i = f === -1 ? n : f + 2; continue; }
    if (c === "/" && abreRegex()) { i = pularRegex(src, i); anterior = "/"; continue; }

    if (c === '"' || c === "'") {
      const fim = pularString(src, i);
      out.push(src.slice(i + 1, fim - 1));
      i = fim;
      anterior = c;
      continue;
    }

    if (c === "`") {
      let j = i + 1;
      let inicio = j;
      while (j < n) {
        if (src[j] === "\\") { j += 2; continue; }
        if (src[j] === "$" && src[j + 1] === "{") {
          out.push(src.slice(inicio, j));                        // trecho literal do template
          const fim = fimDaInterpolacao(src, j + 2);
          // A interpolacao e codigo, mas pode conter strings dentro dela:
          // `${c ? '<b>aten??o</b>' : ''}`. Descer e obrigatorio.
          for (const t of literaisDeString(src.slice(j + 2, Math.max(j + 2, fim - 1)))) out.push(t);
          j = fim;
          inicio = j;
          continue;
        }
        if (src[j] === "`") break;
        j += 1;
      }
      out.push(src.slice(inicio, j));
      i = j + 1;
      anterior = "`";
      continue;
    }

    if (!/\s/.test(c)) anterior = c;
    i += 1;
  }
  return out;
}

export function blocosScript(html) {
  const out = [];
  const re = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html)) !== null) out.push(m[1]);
  return out;
}

// --- regra ------------------------------------------------------------------------------

// '?' colado a letras dos dois lados: assinatura de acento destruido ('aten??o', 'n?o').
const SUSPEITO = /[A-Za-zÀ-ɏ]\?+[a-zÀ-ɏ]/g;

// Unico formato legitimo que casa com a regra: query string ('/version.json?t=').
// O '=' ou '&' logo depois da palavra denuncia a URL.
const FIM_DE_QUERY = /^[=&]/;

export function acentosDestruidos(src) {
  const achados = [];
  for (const texto of literaisDeString(src)) {
    if (texto.trim() === "?") continue; // placeholder de dado ausente, nao corrupcao
    SUSPEITO.lastIndex = 0;
    let m;
    while ((m = SUSPEITO.exec(texto)) !== null) {
      const depois = texto.slice(m.index + m[0].length);
      if (FIM_DE_QUERY.test(depois)) continue;
      achados.push(texto.slice(Math.max(0, m.index - 40), m.index + m[0].length + 40));
    }
  }
  return achados;
}

// --- CLI --------------------------------------------------------------------------------

function analisar(caminho) {
  const html = readFileSync(caminho, "utf8");
  const blocos = blocosScript(html);
  const achados = [];
  let literais = 0;
  for (const b of blocos) {
    literais += literaisDeString(b).length;
    for (const a of acentosDestruidos(b)) achados.push(a);
  }
  return { caminho, blocos: blocos.length, literais, achados };
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const alvos = args.filter((a) => !a.startsWith("--"));
  const lista = alvos.length ? alvos : ALVOS_PADRAO;

  const resultados = [];
  for (const caminho of lista) {
    try {
      resultados.push(analisar(caminho));
    } catch (e) {
      console.error(`nao deu para ler ${caminho}: ${e.message}`);
      process.exit(2);
    }
  }

  const total = resultados.reduce((n, r) => n + r.achados.length, 0);

  if (json) {
    console.log(JSON.stringify({ total, resultados }, null, 2));
  } else {
    for (const r of resultados) {
      console.log(`${r.caminho}: ${r.blocos} bloco(s) <script>, ${r.literais} literal(is) de string`);
      for (const a of r.achados) console.log(`  ACENTO DESTRUIDO  ...${a}...`);
    }
    if (total === 0) {
      console.log("OK: nenhum acento destruido em literal de string.");
    } else {
      console.log(`REPROVADO: ${total} ocorrencia(s). O texto perdeu acento na escrita e o`);
      console.log("usuario le '?' no lugar da letra. Corrija a string, nao o encoding do arquivo.");
    }
  }

  process.exit(total === 0 ? 0 : 1);
}

// So executa quando chamado direto, para o modulo poder ser importado por teste.
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
