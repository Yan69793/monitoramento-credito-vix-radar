// check-version-drift.mjs — guarda do CFG-04 (drift entre a versao canonica do
// repo e a versao que a documentacao declara).
//
// O achado, medido em 18/09/2026: `api/wrangler.toml` apontava main =
// "v4.9.257.js" e producao respondia versao v4.9.257, enquanto o README
// declarava v4.9.255 nas duas linhas de versao do Worker. O README parou de
// acompanhar no deploy do v4.9.255 (16/09); o wrangler.toml andou em 18/09 por
// um commit que nao passou pelo scripts/deploy-worker.ps1, unico lugar que roda
// o scripts/sync-version-docs.ps1. Ou seja: quem conserta a doc e o deploy;
// quando o caminho do deploy e contornado, nada percebe.
//
// Esta guarda fecha isso pelo lado da deteccao, sem depender do deploy: compara
// a versao canonica (a chave `main` do wrangler.toml, que e o bundle que sobe)
// com a versao declarada no README.
//
// Nao depende de numero de linha. As ancoras sao as mesmas que o
// scripts/sync-version-docs.ps1 usa para corrigir, entao o detector e o
// consertador concordam por construcao. Ancora que deixar de casar REPROVA: o
// pior resultado possivel aqui seria a linha sair do arquivo e a guarda passar
// em silencio dizendo que esta tudo certo.
//
// Uso:
//   node scripts/check-version-drift.mjs [wrangler.toml] [README.md]
// Sem argumento, audita o repo. Com argumento, audita os arquivos indicados, que
// e como a ponta ruim e medida contra uma bancada sem tocar no repo real:
//   node scripts/check-version-drift.mjs <tmp>/wrangler.toml <tmp>/README.md
// Exit 0 = sem drift. Exit 1 = drift ou ancora ausente.

import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const tomlPath = process.argv[2] ? path.resolve(process.argv[2]) : path.join(raiz, "api", "wrangler.toml");
const readmePath = process.argv[3] ? path.resolve(process.argv[3]) : path.join(raiz, "README.md");

const problemas = [];
const reprovar = (msg) => problemas.push(msg);

// --- 1. Versao canonica do repo -------------------------------------------
if (!existsSync(tomlPath)) {
  reprovar(`api/wrangler.toml nao existe em ${tomlPath}`);
}
let canonica = null;
if (existsSync(tomlPath)) {
  const toml = readFileSync(tomlPath, "utf8");
  const m = toml.match(/^\s*main\s*=\s*"([^"]+)"/m);
  if (!m) {
    reprovar("nao encontrei a chave `main` em api/wrangler.toml");
  } else {
    canonica = m[1].replace(/\.js$/, "");
    if (!/^v4\.9\.\d+$/.test(canonica)) {
      reprovar(`a chave main de api/wrangler.toml nao tem a forma v4.9.NNN: "${m[1]}"`);
      canonica = null;
    }
  }
}

// --- 2. Versao declarada no README ----------------------------------------
// ← e a seta da ancora, escrita como escape para o arquivo nao depender de
// encoding na comparacao.
const ANCORAS = [
  {
    nome: "README.md :: comentario do bundle vivo",
    re: /(v4\.9\.\d+)\.js\s*←\s*bundle Worker em produção/,
  },
  {
    nome: "README.md :: tabela Versoes em Producao, linha Worker",
    re: /\|\s*Worker `radar-credito-api`\s*\|\s*(v4\.9\.\d+)\s*\|/,
  },
];

const declaradas = [];
if (!existsSync(readmePath)) {
  reprovar(`README.md nao existe em ${readmePath}`);
} else {
  const readme = readFileSync(readmePath, "utf8");
  for (const a of ANCORAS) {
    const m = readme.match(a.re);
    if (!m) {
      reprovar(`ancora ausente: ${a.nome}. A linha saiu do arquivo ou mudou de forma; a guarda nao consegue afirmar nada sobre ela.`);
      continue;
    }
    declaradas.push({ nome: a.nome, versao: m[1] });
  }
}

// --- 3. Comparacao ---------------------------------------------------------
if (canonica) {
  for (const d of declaradas) {
    if (d.versao !== canonica) {
      reprovar(`DRIFT: ${d.nome} declara ${d.versao}, mas a versao canonica do repo e ${canonica} (api/wrangler.toml, chave main).`);
    }
  }
  const distintas = [...new Set(declaradas.map((d) => d.versao))];
  if (distintas.length > 1) {
    reprovar(`DRIFT interno no README: as linhas de versao do Worker divergem entre si (${distintas.join(", ")}).`);
  }
}

// --- Resultado -------------------------------------------------------------
if (problemas.length === 0) {
  console.log(`check-version-drift: sem drift. canonica=${canonica}, declarada em ${declaradas.length} ancora(s): ${declaradas.map((d) => d.versao).join(", ")}`);
  process.exit(0);
}

console.error("check-version-drift: DRIFT DE VERSAO");
for (const p of problemas) console.error(`  - ${p}`);
console.error(`  canonica (api/wrangler.toml main) = ${canonica}`);
console.error("  corrija com: pwsh ./scripts/sync-version-docs.ps1 -WorkerVersion " + (canonica || "v4.9.NNN"));
process.exit(1);
