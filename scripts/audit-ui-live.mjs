// audit-ui-live.mjs
// Inventario de veracidade da UI contra o DOM AO VIVO, via CDP.
//
// Motivo (FERRAMENTACEGA1, auditoria 2026-08-20). O audit-ui-metrics.mjs e regex
// sobre o HTML de 700 KB minificado. Ele inventaria 5 metricas. O DOM real tem
// dezenas, e a maioria so existe atras de login, entao a ferramenta nunca viu o
// produto. Foi por isso que o SPREADUNIDADE1 sobreviveu meses: o card dizia
// "Spread ANBIMA ... bps" sobre taxa indicativa em percentual, e nenhuma camada
// automatizada olhava para o card renderizado.
//
// Esta versao conecta num browser que o operador ja autenticou, percorre o DOM,
// e inventaria TODA superficie que exibe numero. O resultado vira baseline
// versionado. Superficie nova sem entrada no baseline reprova, o que transforma
// a varredura de hoje em contrato permanente em vez de evento unico.
//
// Uso:
//   node scripts/audit-ui-live.mjs --cdp http://127.0.0.1:9333 --baseline ui-baseline.json
//   node scripts/audit-ui-live.mjs --cdp http://127.0.0.1:9333 --gravar-baseline
//
// O operador sobe o browser assim, com a sessao ja logada:
//   brave.exe --remote-debugging-port=9333 --remote-allow-origins=* --profile-directory="Default"

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { pathToFileURL } from "node:url";

// O projeto nao tem package.json na raiz e o playwright esta instalado global.
// ESM ignora NODE_PATH, entao resolve o caminho global na mao. Assim o script
// roda sem obrigar a criar dependencia nova no repo so para auditar.
async function carregarPlaywright() {
  try { return (await import("playwright")).chromium; } catch (_) { /* segue */ }
  let raiz = "";
  try { raiz = execSync("npm root -g", { encoding: "utf8" }).trim(); } catch (e) {
    console.error("FALHA: playwright nao encontrado e 'npm root -g' nao respondeu.");
    process.exit(2);
  }
  const alvo = path.join(raiz, "playwright", "index.mjs");
  const alvoCjs = path.join(raiz, "playwright", "index.js");
  const escolhido = fs.existsSync(alvo) ? alvo : alvoCjs;
  if (!fs.existsSync(escolhido)) {
    console.error(`FALHA: playwright ausente em ${raiz}. Instale com 'npm i -g playwright'.`);
    process.exit(2);
  }
  const mod = await import(pathToFileURL(escolhido).href);
  return mod.chromium || (mod.default && mod.default.chromium);
}
const chromium = await carregarPlaywright();

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : d; };
const flag = (n) => args.includes(n);

const CDP = opt("--cdp", "http://127.0.0.1:9333");
const ALVO = opt("--url", "vixradar.com");
// decodeURIComponent porque o pathname da import.meta.url vem percent-encoded e
// o projeto mora em "Monitoramento de Credito", com espacos.
const AQUI = path.dirname(decodeURIComponent(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")));
const BASELINE = path.resolve(opt("--baseline", path.join(AQUI, "..", "status", "ui-baseline.json")));
const GRAVAR = flag("--gravar-baseline");

// Termos com significado contratado no glossario de dominio. Se aparecerem como
// rotulo, a expressao ao lado tem obrigacao de medir o que o termo promete.
const RESERVADOS = ["emissores", "criticos", "críticos", "relevantes", "cobertura", "spread", "taxa indicativa", "ews", "score", "materialidade", "alertas", "sem alertas"];
// Unidades que, se aparecerem no valor, precisam bater com a grandeza da fonte.
const UNIDADES = ["%", "bps", "p.p.", "pts", "a.a.", "R$", "d", "dias", "x"];

const COLETOR = `(() => {
  const vis = e => { const s = getComputedStyle(e); return s.display !== 'none' && s.visibility !== 'hidden' && e.offsetHeight > 0; };
  const temNumero = t => /\\d/.test(t);
  const out = [];
  const seen = new Set();
  document.querySelectorAll('*').forEach(e => {
    if (e.children.length !== 0) return;
    if (!vis(e)) return;
    const txt = (e.textContent || '').trim();
    if (!txt || txt.length > 80 || !temNumero(txt)) return;
    // rotulo: irmao anterior sem digito, senao primeiro filho-irmao sem digito,
    // senao o cabecalho do bloco pai.
    // O rotulo tem que ser TEXTO SEM NUMERO. A versao anterior aceitava o irmao
    // anterior mesmo quando ele era outro VALOR, e o inventario saia deslocado em
    // um: "6 criticos (7d)" virava rotulo de "42". Rotulo com digito nao e
    // rotulo, e o proximo valor da fila.
    const semNumero = t => t && !/\\d/.test(t);
    let rot = '';
    // 1) atributos que declaram o rotulo de forma explicita vencem heuristica
    const attr = e.getAttribute('aria-label') || e.getAttribute('title') || (e.parentElement && (e.parentElement.getAttribute('aria-label') || e.parentElement.getAttribute('title'))) || '';
    if (semNumero(attr)) rot = attr.trim();
    // 2) irmao anterior, so se nao tiver digito
    if (!rot) { const s = e.previousElementSibling; const st = s && s.children.length === 0 ? (s.textContent||'').trim() : ''; if (semNumero(st)) rot = st; }
    // 3) irmao posterior sem digito (padrao valor-em-cima, rotulo-embaixo)
    if (!rot) { const s2 = e.nextElementSibling; const st2 = s2 && s2.children.length === 0 ? (s2.textContent||'').trim() : ''; if (semNumero(st2)) rot = st2; }
    // 4) qualquer folha irma sem digito
    if (!rot && e.parentElement) {
      const c = [...e.parentElement.children].filter(x => x !== e && x.children.length === 0 && semNumero((x.textContent||'').trim()));
      if (c.length) rot = (c[0].textContent || '').trim();
    }
    // 5) cabecalho do bloco pai, ainda exigindo ausencia de digito
    if (!rot && e.parentElement && e.parentElement.previousElementSibling) {
      const pt = (e.parentElement.previousElementSibling.textContent || '').trim();
      if (semNumero(pt)) rot = pt;
    }
    // 6) padrao "<strong>6</strong> criticos (7d)": o rotulo e o texto do PAI
    // menos o proprio valor. Sem isto, os tres contadores do cabecalho ficavam
    // "(sem rotulo)" e dois deles sumiam na deduplicacao.
    if (rot === '' && e.parentElement) {
      const pai = (e.parentElement.textContent || '').trim();
      const semValor = pai.replace(txt, '').replace(/\\s+/g, ' ').trim();
      if (semValor && semValor.length < 60) rot = semValor;
    }
    if (!rot) rot = '(sem rotulo)';
    // Indice entre irmaos entra na chave: tres <strong> irmaos com a mesma classe
    // e o mesmo rotulo derivado sao TRES superficies distintas, nao uma.
    const idxIrmao = e.parentElement ? [...e.parentElement.children].indexOf(e) : 0;
    const chave = (e.id || '') + '|' + (e.className || '').toString() + '|' + rot + '|' + idxIrmao;
    if (seen.has(chave)) return;
    seen.add(chave);
    // caminho estavel para reconhecer a superficie entre rodadas
    let caminho = [], n = e, guarda = 0;
    while (n && n !== document.body && guarda++ < 6) {
      caminho.unshift(n.id ? '#' + n.id : (n.className ? '.' + String(n.className).trim().split(/\\s+/)[0] : n.tagName.toLowerCase()));
      n = n.parentElement;
    }
    out.push({
      id: e.id || '',
      classe: (e.className || '').toString().slice(0, 60),
      caminho: caminho.join('>').slice(0, 160),
      rotulo: rot.replace(/\\s+/g, ' ').slice(0, 60),
      valor: txt.replace(/\\s+/g, ' ')
    });
  });
  return out;
})()`;

function unidadeDe(valor) {
  for (const u of UNIDADES) if (valor.includes(u)) return u;
  return "(sem unidade)";
}
function reservadoEm(rotulo) {
  const r = rotulo.toLowerCase();
  return RESERVADOS.filter((t) => r.includes(t));
}
function chaveDe(s) {
  return (s.id || s.caminho) + "::" + s.rotulo;
}

const nav = await chromium.connectOverCDP(CDP);
const ctxs = nav.contexts();
let page = null;
for (const c of ctxs) for (const p of c.pages()) if (p.url().includes(ALVO)) { page = p; break; }
if (!page) { console.error(`FALHA: nenhuma aba aberta em ${ALVO}. Abra a pagina no browser com CDP em ${CDP}.`); process.exit(2); }

console.log(`URL: ${page.url()}`);
const superficies = await page.evaluate(COLETOR);
console.log(`SUPERFICIES COM NUMERO: ${superficies.length}`);
console.log("");

const enriquecidas = superficies.map((s) => ({
  ...s,
  unidade: unidadeDe(s.valor),
  reservado: reservadoEm(s.rotulo)
}));

for (const s of enriquecidas) {
  const marca = s.reservado.length ? "  <<< TERMO RESERVADO: " + s.reservado.join(",") : "";
  console.log(`  [${s.unidade.padEnd(12)}] "${s.rotulo}" = "${s.valor}"${marca}`);
  console.log(`      ${s.caminho}`);
}
console.log("");

if (GRAVAR) {
  const payload = {
    gerado_em_url: page.url(),
    total: enriquecidas.length,
    nota: "Baseline de superficies com numero. Superficie nova sem entrada aqui reprova o audit-ui-live. Ver FERRAMENTACEGA1.",
    superficies: enriquecidas.map((s) => ({ chave: chaveDe(s), rotulo: s.rotulo, unidade: s.unidade, caminho: s.caminho, reservado: s.reservado }))
  };
  fs.mkdirSync(path.dirname(BASELINE), { recursive: true });
  fs.writeFileSync(BASELINE, JSON.stringify(payload, null, 2), "utf8");
  console.log(`BASELINE GRAVADO: ${BASELINE} (${payload.total} superficies)`);
  await nav.close();
  process.exit(0);
}

if (!fs.existsSync(BASELINE)) {
  console.log(`AVISO: baseline ausente em ${BASELINE}. Rode com --gravar-baseline para criar.`);
  await nav.close();
  process.exit(0);
}

const base = JSON.parse(fs.readFileSync(BASELINE, "utf8"));
const conhecidas = new Set((base.superficies || []).map((s) => s.chave));
const novas = enriquecidas.filter((s) => !conhecidas.has(chaveDe(s)));
const sumiram = (base.superficies || []).filter((b) => !enriquecidas.some((s) => chaveDe(s) === b.chave));

console.log(`BASELINE: ${base.total} superficies | AGORA: ${enriquecidas.length}`);
if (sumiram.length) {
  console.log(`INFO: ${sumiram.length} superficie(s) do baseline nao apareceram nesta rodada (aba fechada, estado diferente ou removida).`);
  sumiram.slice(0, 10).forEach((s) => console.log(`   - "${s.rotulo}" ${s.caminho}`));
}
if (novas.length) {
  console.log("");
  console.log(`FALHA: ${novas.length} superficie(s) NOVA(S) sem entrada no baseline.`);
  console.log("Toda superficie que exibe numero precisa da tripla rotulo, formula e unidade conferida.");
  novas.forEach((s) => console.log(`   + "${s.rotulo}" = "${s.valor}" [${s.unidade}] ${s.caminho}`));
  await nav.close();
  process.exit(1);
}

console.log("AUDIT_UI_LIVE_OK nenhuma superficie nova fora do baseline.");
await nav.close();
process.exit(0);
