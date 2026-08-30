// check-cache-version.mjs — guarda do CACHEBUMP1 no pre-commit.
//
// CACHEBUMP1 (20/08, terceira ocorrencia): alinhar o cache version do frontend a
// mao quebrou o painel tres vezes. A lição de 30/08 (recaida ao editar CACHE_VERSION
// manualmente sem alcancar os ?v=) mostrou que aviso nao basta: precisa reprovar no
// commit. Este script valida que CACHE_VERSION bate com todos os ?v= de um index.html
// (blob em staging, materializado pelo hook) e dos modulos app/js staged.
//
// Uso (chamado pelo hook, nao pelo operador):
//   node scripts/check-cache-version.mjs <index.html> [mod1.js mod2.js ...]
//
// Exit 0 = alinhado. Exit 1 = divergencia, com a lista na stdout. Onde o index nao
// existir, nao valida nada (gate silencioso so quando ha index).
import { readFileSync, existsSync } from "node:fs";

const [indexPath, ...modulos] = process.argv.slice(2);
if (!indexPath || !existsSync(indexPath)) {
  process.exit(0);
}

const html = readFileSync(indexPath, "utf8");

const mVer = html.match(/CACHE_VERSION\s*=\s*"v([0-9]+\.[0-9]+)"/);
if (!mVer) {
  console.error(`check-cache-version: CACHE_VERSION nao encontrado em ${indexPath}`);
  process.exit(1);
}
const ver = mVer[1];

const divergencias = [];
const reV = /[?&]v=([0-9][0-9.]*)/g;

function checar(arquivo, texto) {
  for (const match of texto.matchAll(reV)) {
    const v = match[1].replace(/^v/, "");
    if (v !== ver) {
      divergencias.push(`${arquivo}: ?v=${v} mas CACHE_VERSION e v${ver}`);
    }
  }
}

checar(indexPath, html);
for (const mod of modulos) {
  if (existsSync(mod)) checar(mod, readFileSync(mod, "utf8"));
}

if (divergencias.length > 0) {
  console.error(divergencias.join("\n"));
  process.exit(1);
}
