// PDFINJECT1 (18/10/2026): regressao do relatorio PDF (exportar).
// Um snippet de terceiro foi colado em todo "</head>" do index.html, inclusive nos
// dois que vivem dentro de string JS do exportador. O "</script>" literal do snippet
// fecha o <script> do app no parser HTML, o resto do template vira texto da pagina
// (\n, ${...} e HTML cru) e o override do PDF Executivo nem chega a ser definido.
//
// Rodar: node --test app/tests/exportar-pdf.test.mjs
// Alvo alternativo (prova de duas pontas): VIX_INDEX_HTML=<arquivo> node --test ...
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ALVOS = process.env.VIX_INDEX_HTML
  ? [process.env.VIX_INDEX_HTML]
  : [path.join(APP, 'index.html'), path.join(APP, 'deploy_zip', 'index.html')];

// Extrai <script> clássicos como o tokenizer HTML faz: o conteúdo termina no
// primeiro "</script" literal, esteja ele dentro de string JS ou nao.
function scriptsInline(html) {
  const out = [];
  const abre = /<script\b([^>]*)>/gi;
  let m;
  while ((m = abre.exec(html))) {
    const ini = abre.lastIndex;
    const fim = html.toLowerCase().indexOf('</script', ini);
    if (fim < 0) break;
    const attrs = m[1];
    const tipo = (attrs.match(/\btype\s*=\s*["']?([^"'\s>]+)/i) || [])[1] || '';
    const linha = html.slice(0, m.index).split('\n').length;
    if (!/\bsrc\s*=/i.test(attrs) && (tipo === '' || /^(text|application)\/javascript$/i.test(tipo))) {
      out.push({ linha, src: html.slice(ini, fim) });
    }
    abre.lastIndex = fim + 8;
  }
  return out;
}

function stubs(html) {
  const escritos = [];
  const janela = { document: { write: (s) => escritos.push(s), close() {}, title: '' } };
  const ctx = {
    console, Set, Map, Date, JSON, Math, Object, Array, String, Promise, parseInt,
    setTimeout: () => 0,
    alert: (msg) => { throw new Error('alert: ' + msg); },
    localStorage: { getItem: () => null },
    fetch: async () => ({ ok: false }),
    registrarAcesso() {},
    semanaISO: () => '2026-W42',
    SETOR_DE: { 'Emissor <X>': 'Energia' },
    resultados: {
      'Emissor <X>': {
        eventos: [{
          classificacao: 'CRITICO',
          data_evento: new Date().toISOString().slice(0, 10),
          titulo: 'Titulo <b>cru</b>',
          memo_acontecimento: 'linha 1\nlinha 2',
          fonte_primaria: 'https://www.rad.cvm.gov.br/x?a=1&b=2'
        }]
      }
    },
    document: { getElementById: () => null, createElement: () => ({}) }
  };
  ctx.window = ctx;
  ctx.open = () => janela;
  vm.createContext(ctx);
  // REL-EXEC2: a logica do relatorio vive em app/js/relatorio-executivo.js; o bloco inline
  // do index.html e so a casca que coleta dados e abre a janela.
  vm.runInContext(readFileSync(path.join(APP, 'js', 'relatorio-executivo.js'), 'utf8'), ctx, { filename: 'relatorio-executivo.js' });
  return { ctx, escritos, html };
}

for (const alvo of ALVOS) {
  const html = readFileSync(alvo, 'utf8');
  const nome = path.relative(path.resolve(APP, '..'), alvo);
  const scripts = scriptsInline(html);

  test(`${nome}: todo <script> inline parseia (nenhum foi cortado por </script> literal)`, () => {
    const erros = [];
    for (const s of scripts) {
      try { new vm.Script(s.src, { filename: `${nome}:${s.linha}` }); }
      catch (e) { erros.push(`linha ${s.linha}: ${e.message}`); }
    }
    assert.deepEqual(erros, []);
  });

  test(`${nome}: exportador legado chega inteiro ao fim do template`, () => {
    const s = scripts.find((x) => x.src.includes('function exportar('));
    assert.ok(s, 'script com function exportar( nao encontrado');
    const corpo = s.src.slice(s.src.indexOf('function exportar('));
    assert.match(corpo, /<\/body>\\n<\/html>`/, 'template do exportar foi truncado');
    assert.doesNotMatch(corpo.slice(0, corpo.indexOf('</html>`')), /linkedin|<\/script/i);
  });

  test(`${nome}: PDF Executivo gera documento valido`, async () => {
    const s = scripts.find((x) => x.src.includes('PDF Executivo v201'));
    assert.ok(s, 'bloco do PDF Executivo nao encontrado como <script> proprio');
    const { ctx, escritos } = stubs(html);
    vm.runInContext(s.src, ctx);
    assert.equal(typeof ctx.exportar, 'function');
    assert.equal(typeof ctx.abrirSeletorPDF, 'function');
    await ctx.exportar(7);
    assert.equal(escritos.length, 1, 'window.open nao recebeu o documento');
    const doc = escritos[0];

    assert.equal(doc.split('</head><body>').length, 2, 'precisa de exatamente um </head><body>');
    assert.ok(doc.startsWith('<!DOCTYPE html>') && doc.endsWith('</body></html>'));
    assert.doesNotMatch(doc, /\$\{/, 'interpolacao nao resolvida no documento');
    assert.doesNotMatch(doc, /\\n/, 'escape \\n literal no documento');
    assert.doesNotMatch(doc, /linkedin|licdn/i, 'script de terceiro dentro do relatorio');
    assert.match(doc, /<style>@page\{size:A4 portrait/);
    assert.match(doc, /@media print\{/);
    assert.match(doc, /function salvarPdf\(\)\{[^<]*window\.print\(\)/);
    assert.match(doc, /onclick="salvarPdf\(\)"/);

    const internos = scriptsInline(doc);
    assert.equal(internos.length, 1, 'relatorio deve ter so o script salvarPdf');
    new vm.Script(internos[0].src);

    // escape de dado do usuario: HTML do titulo nao vira tag
    assert.match(doc, /Titulo &lt;b&gt;cru&lt;\/b&gt;/);
    assert.doesNotMatch(doc, /Titulo <b>/);
    assert.match(doc, /<strong>Emissor &lt;X&gt;<\/strong>/);
    // deploy_zip/index.html e copia gerada no deploy: ate o proximo deploy ainda carrega o
    // gerador antigo, que nao usa o modulo. Cada alvo e validado pelo gerador que contem.
    if (html.includes('js/relatorio-executivo.js')) {
      assert.match(doc, /Resumo decisório/);
      assert.match(doc, /Fichas dos emissores prioritários/);
    } else {
      assert.match(doc, /<h3>Titulo &lt;b&gt;cru&lt;\/b&gt;<\/h3>/);
    }
    assert.match(doc, /href="https:\/\/www\.rad\.cvm\.gov\.br\/x\?a=1&amp;b=2"/);

    // CSS equilibrado
    const css = doc.slice(doc.indexOf('<style>') + 7, doc.indexOf('</style>'));
    assert.equal((css.match(/\{/g) || []).length, (css.match(/\}/g) || []).length, 'chaves do CSS desbalanceadas');
  });
}
