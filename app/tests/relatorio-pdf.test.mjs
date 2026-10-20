// REL-EXEC2 (20/10/2026): renderiza o Relatorio Executivo 2.0 em PDF real (Chromium headless,
// A4) e mede paginacao e overflow. Fixtures sinteticas, sem dado de cliente.
// Rodar: node --test app/tests/relatorio-pdf.test.mjs   (usa o Chromium do Playwright instalado)
// Saida dos PDFs: VIX_PDF_OUT ou E:\Diretorio\Claude\tmp\operacional\vix-radar\relatorio-exec2
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const R = require(path.join(HERE, '..', 'js', 'relatorio-executivo.js'));
const OUT = process.env.VIX_PDF_OUT || 'E:\\Diretorio\\Claude\\tmp\\operacional\\vix-radar\\relatorio-exec2';
mkdirSync(OUT, { recursive: true });

let browser = null, motivoSkip = '';
before(async () => {
  try {
    const { chromium } = require(path.join(HERE, 'node_modules', 'playwright-core'));
    browser = await chromium.launch();
  } catch (e) { motivoSkip = 'Chromium indisponivel: ' + String(e.message).split('\n')[0]; }
});
after(async () => { if (browser) await browser.close(); });

const AGORA = new Date(2026, 9, 20, 10, 0, 0);
const iso = (d) => { const x = new Date(AGORA.getFullYear(), AGORA.getMonth(), AGORA.getDate() - d); return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`; };
const SETORES = ['Energia', 'Saneamento', 'Varejo', 'Transporte', 'Óleo e Gás', 'Construção', 'Telecom', 'Proteínas'];
const TEMAS = [
  'rebaixamento de rating pela agência com perspectiva negativa', 'pedido de waiver para covenant de alavancagem',
  'atraso no pagamento de cupom de debêntures', 'renegociação de dívida bancária de curto prazo',
  'queda de 18% na geração operacional de caixa no trimestre', 'oferta de recompra de bonds com deságio',
  'aumento de capital com diluição relevante', 'venda de ativo estratégico para reforço de caixa'
];

function gerar(nEmissores, eventosPorEmissor) {
  const evs = [], ews = [], curadas = {}, setorDe = {}, anom = {};
  for (let i = 0; i < nEmissores; i++) {
    const emp = `Emissor Sintético ${String(i + 1).padStart(2, '0')} S.A.`;
    setorDe[emp] = SETORES[i % SETORES.length];
    for (let k = 0; k < eventosPorEmissor; k++) {
      const tema = TEMAS[(i + k) % TEMAS.length];
      evs.push({
        _empresa: emp, data_evento: iso((i * 5 + k * 6) % 28), classificacao: (i + k) % 3 === 0 ? 'CRITICO' : 'RELEVANTE',
        titulo: `${emp.split(' S.A.')[0]} comunica ${tema} (${k + 1})`,
        memo_acontecimento: `Comunicado ao mercado informa ${tema}, com efeito estimado de R$ ${(i + 1) * 40 + k} milhões no horizonte de 12 meses. Acompanhar de perto os desdobramentos.`,
        memo_importancia_credito: `Reduz a cobertura de juros em ${(k + 1) * 0.2 + 0.3} vez e antecipa vencimentos de R$ ${(i + 2) * 30} milhões.`,
        memo_monitorar: `Verificar a posição de caixa no próximo ITR e a janela de vencimentos de ${2027 + (k % 3)}.`,
        memo_acao_sugerida: 'Rever limite de exposição até a divulgação do próximo balanço.',
        fonte_primaria: `https://www.rad.cvm.gov.br/enet/doc-${i}-${k}`
      });
    }
    if (i < Math.min(nEmissores, 12)) {
      ews.push({
        empresa: emp, score: Math.max(20, 88 - i * 4), label: i < 3 ? 'CRITICO' : i < 7 ? 'ALERTA' : 'ATENCAO', calculado_em: iso(0),
        decomposicao: [
          { fator: 'Eventos críticos recentes', pontos: 24 - i, peso_max: 35, direcao: 'deterioracao', confianca: 0.8, data_evento: iso(2), tipo_sinal: 'evento', fonte: { url: `https://www.rad.cvm.gov.br/enet/doc-${i}-0` }, fato: 'Comunicado de fato relevante' },
          { fator: 'Spread em alta no secundário', pontos: 14, peso_max: 20, direcao: 'deterioracao', confianca: 0.6 },
          { fator: 'Rating sob revisão', pontos: 9, peso_max: 15, direcao: 'deterioracao', confianca: 0.9 },
          { fator: 'Liquidez de caixa', pontos: 3, peso_max: 10, direcao: 'melhora' }
        ]
      });
    }
    if (i % 2 === 0) curadas[emp] = [
      { label: 'Rating', value: 'A-', ref: 'S&P 09/2026' },
      { label: 'Alavancagem', value: `${(2 + i * 0.1).toFixed(1).replace('.', ',')}x`, fonte: 'ITR 2T26', as_of: '2026-06-30' }
    ];
    if (i % 3 === 0) anom[emp] = [{ tipo: 'spread', severidade: 'critica', dados: { taxa_atual_pct: 13.4 + i * 0.1, taxa_media_pct: 12.0, data: iso(1) } }];
  }
  return { evs, ews, curadas, setorDe, anom };
}

const TAMANHOS = { pequena: [2, 2], media: [12, 3], grande: [40, 4] };
const BRAND = { theme: R.PRESETS.sobrio_dark_navy, gestora: 'Gestora Exemplo', analista: 'Analista Teste', credencial: 'CNPI 0000', cnpj: '', logo: '' };

async function renderizar(nome, tipo, dias, f) {
  const html = R.buildHtml(dias, f.evs, f.ews, BRAND, { tipo, agora: AGORA, semana: '2026-W43', setorDe: f.setorDe, curadas: f.curadas, anomalias: f.anom });
  writeFileSync(path.join(OUT, `${nome}-${tipo}.html`), html);
  const page = await browser.newPage({ viewport: { width: 794, height: 1123 } });
  await page.setContent(html, { waitUntil: 'load' });
  await page.emulateMedia({ media: 'print' });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  const texto = await page.evaluate(() => document.body.innerText);
  const pdf = await page.pdf({ format: 'A4', preferCSSPageSize: true, printBackground: true });
  await page.close();
  writeFileSync(path.join(OUT, `${nome}-${tipo}.pdf`), pdf);
  const paginas = (pdf.toString('latin1').match(/\/Type\s*\/Page[^s]/g) || []).length;
  return { paginas, overflow, texto, bytes: pdf.length };
}

for (const [nome, [nE, nEv]] of Object.entries(TAMANHOS)) {
  test(`PDF ${nome}: executivo fica entre 3 e 5 paginas A4, sem overflow horizontal`, async (t) => {
    if (!browser) return t.skip(motivoSkip);
    const f = gerar(nE, nEv);
    const r = await renderizar(nome, 'executivo', 30, f);
    console.log(`  [${nome}] executivo: ${r.paginas} paginas, ${r.bytes} bytes, overflow ${r.overflow}px`);
    assert.ok(r.paginas >= 3 && r.paginas <= 5, `paginas=${r.paginas}`);
    assert.ok(r.overflow <= 1, `overflow horizontal ${r.overflow}px`);
    assert.doesNotMatch(r.texto, /desdobramentos/i, 'texto generico no PDF');
    assert.doesNotMatch(r.texto, /undefined|NaN|\[object/);
    assert.match(r.texto, /Gestora Exemplo/i);
    assert.match(r.texto, /resumo decisório/i);
    assert.match(r.texto, /leitura analítica/i);
  });
}

test('PDF: anexo cresce com o volume e o executivo nao', async (t) => {
  if (!browser) return t.skip(motivoSkip);
  const m = gerar(...TAMANHOS.media), g = gerar(...TAMANHOS.grande);
  const exeM = await renderizar('media', 'executivo', 30, m), exeG = await renderizar('grande', 'executivo', 30, g);
  const comM = await renderizar('media', 'completo', 30, m), comG = await renderizar('grande', 'completo', 30, g);
  console.log(`  completo: media=${comM.paginas}p grande=${comG.paginas}p | executivo: media=${exeM.paginas}p grande=${exeG.paginas}p`);
  assert.ok(comG.paginas > comM.paginas, 'anexo deve crescer com mais eventos');
  assert.ok(comM.paginas > exeM.paginas);
  assert.ok(exeG.paginas <= 5);
  assert.match(comG.texto, /anexo técnico/i);
  assert.match(comG.texto, /índice de fontes/i);
  assert.match(comG.texto, /decomposição completa do EWS/i);
});

test('PDF: anexo isolado nao traz as fichas do executivo', async (t) => {
  if (!browser) return t.skip(motivoSkip);
  const r = await renderizar('media', 'anexo', 30, gerar(...TAMANHOS.media));
  assert.doesNotMatch(r.texto, /fichas dos emissores prioritários/i);
  assert.match(r.texto, /lacunas de dado/i);
});
