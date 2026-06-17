import { readFileSync, writeFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dir = dirname(fileURLToPath(import.meta.url));
const bundle = readFileSync(join(__dir, "..", "v4.9.136.js"), "utf8");

function extractFn(name) {
  const re = new RegExp(`function ${name}\\([^)]*\\)\\s*\\{`, "m");
  const m = bundle.match(re);
  if (!m) throw new Error(`function ${name} not found`);
  let i = bundle.indexOf(m[0]);
  let depth = 0;
  let started = false;
  for (; i < bundle.length; i++) {
    const c = bundle[i];
    if (c === "{") { depth++; started = true; }
    else if (c === "}") {
      depth--;
      if (started && depth === 0) return bundle.slice(bundle.indexOf(m[0]), i + 1);
    }
  }
  throw new Error(`unbalanced ${name}`);
}

const prelude = `
var FRONTEND_URL = "https://vixradar.com";
function escapeHtml(s) {
  if (s === null || s === void 0) return "";
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function formatarData(iso) {
  if (!iso) return "";
  const [ano, mes, dia] = iso.split("-");
  return parseInt(dia) + " " + ["jan","fev","mar","abr","mai","jun","jul","ago","set","out","nov","dez"][parseInt(mes)-1] + " " + ano;
}
function __name22222222(fn) { return fn; }
`;

const montar = extractFn("montarEmailHTML");
const fixtures = extractFn("eventosFixturesTeste");

const fn = new Function(prelude + fixtures + montar + `
  return { montarEmailHTML, eventosFixturesTeste };
`);
const { montarEmailHTML, eventosFixturesTeste } = fn();
const hoje = new Date().toISOString().split("T")[0];
const html = montarEmailHTML(hoje, eventosFixturesTeste(hoje), "https://api.vixradar.com/?action=email_unsubscribe&email=preview%40vixradar.com&ts=1&sig=preview");
const out = join(__dir, "..", "..", "app", "_preview", "boletim-diario.html");
writeFileSync(out, html, "utf8");
console.log("Preview:", out);