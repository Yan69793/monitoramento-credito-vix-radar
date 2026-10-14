// Validacao do redesign Institutional Intelligence 2030 (Fase 0.5 na v1 + v2 atras de flag).
// Tudo roda contra fixtures (vx-fixtures.mjs): a API e interceptada, nenhuma chamada sai.
// Sessao e de TESTE; isto NAO substitui o teste autenticado real em producao/preview.
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import fs from 'node:fs';
import { mockApi, sessaoTeste, IDS_CINCO, estadoCincoSeveridades, ews as ewsFix, serie as serieFix, diaUtil } from './vx-fixtures.mjs';

const CORES = { CRITICO: 'rgb(239, 68, 68)', ALERTA: 'rgb(249, 115, 22)', ATENCAO: 'rgb(234, 179, 8)', RELEVANTE: 'rgb(96, 165, 250)', ECO: 'rgb(148, 163, 184)' };
const ROTULOS = { CRITICO: 'CRÍTICO', ALERTA: 'ALERTA', ATENCAO: 'ATENÇÃO', RELEVANTE: 'RELEVANTE', ECO: 'ECO' };
const ehDesktop = (info) => info.project.name === 'desktop-1440';

function diagnostico(page) {
  const d = { erros: [], http: [] };
  page.on('pageerror', (e) => d.erros.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') d.erros.push('console: ' + m.text()); });
  page.on('response', (r) => { if (r.status() >= 400) d.http.push(`${r.status()} ${r.request().method()} ${r.url()}`); });
  return d;
}
async function abrirV2(page, hash = '#/eventos', opts = {}) {
  const d = diagnostico(page);
  const chamadas = await mockApi(page, opts);
  await sessaoTeste(page, { flag: 'v2' });
  await page.goto('/' + hash);
  await expect(page.locator('#vx2-root.vx-on')).toBeVisible();
  return { d, chamadas };
}
async function abrirV1(page, opts = {}) {
  const d = diagnostico(page);
  await mockApi(page, opts);
  await sessaoTeste(page, { flag: null });
  await page.goto('/');
  // a v1 logada abre na Visao Geral; o feed fica no Painel de Eventos
  await page.waitForFunction(() => typeof mostrarDashboard === 'function' && document.querySelectorAll('#dash-eventos .v201-card').length > 0);
  await page.evaluate(() => mostrarDashboard()); // eslint-disable-line no-undef
  await expect(page.locator('#dash-eventos .v201-card').first()).toBeVisible();
  return { d };
}
async function salvar(page, info, nome) {
  fs.mkdirSync('test-results-vx/shots', { recursive: true });
  await page.screenshot({ path: `test-results-vx/shots/${info.project.name}-${nome}.png`, fullPage: false });
}

/* ================= FASE 0.5: severidade canonica na v1 ================= */
test.describe('v1 corrigida (Fase 0.5)', () => {
  test('cinco severidades: rotulo, cor e ordem no feed; ALERTA nunca vira ECO', async ({ page }, info) => {
    const { d } = await abrirV1(page);
    const cards = page.locator('#dash-eventos .v201-card .vx-sev-badge');
    const sevs = await cards.evaluateAll((els) => els.map((e) => e.dataset.sev));
    // 5 do mesmo dia na ordem canonica (agrupados por emissor, um evento cada)
    const dia = sevs.slice(0, 5);
    expect(dia).toEqual(['CRITICO', 'ALERTA', 'ATENCAO', 'RELEVANTE', 'ECO']);
    for (const s of Object.keys(ROTULOS)) {
      const b = page.locator(`#dash-eventos .vx-sev-badge[data-sev="${s}"]`).first();
      await expect(b).toContainText(ROTULOS[s]);
      await expect(b).toHaveCSS('color', CORES[s]);
    }
    const alerta = page.locator('#dash-eventos .v201-card', { hasText: 'Evento ALERTA de teste' });
    await expect(alerta.locator('.vx-sev-badge')).toHaveAttribute('data-sev', 'ALERTA');
    await expect(alerta.locator('.vx-sev-badge')).not.toContainText('ECO');
    // KPIs da janela: cada severidade contada uma vez (antes ALERTA/ATENCAO sumiam)
    // fixture: 1 de cada no mesmo dia + 1 RELEVANTE da Sabesp a 3 dias uteis (dentro dos 7)
    const esperado = { CRITICO: '1', ALERTA: '1', ATENCAO: '1', RELEVANTE: '2' };
    for (const s of Object.keys(esperado)) {
      await expect(page.locator(`#v201-header-stats .vx-kpi[data-sev="${s}"] strong`)).toHaveText(esperado[s]);
    }
    if (ehDesktop(info)) await salvar(page, info, 'v1-feed');
    expect(d.erros.filter((e) => !/Failed to load resource/.test(e))).toEqual([]);
  });

  test('ranking EWS usa a cor canonica, nao a do Worker', async ({ page }) => {
    await abrirV1(page);
    const cor = await page.evaluate(() => [window.vxSevCfg('ALERTA').cor, window.vxSevCfg('RELEVANTE').cor, window.vxSevCfg('ESTAVEL').label, window.vxSevKey('Atenção')]);
    expect(cor).toEqual(['#F97316', '#60A5FA', 'ESTÁVEL', 'ATENCAO']);
  });
});

// VXLCP2: o que nao desenha a landing sai do caminho critico. Medido no mesmo relogio do navegador
// (performance.now), sem comparar com horario do Node. Duas pontas: o que DEVE esperar (3 fontes e 2 GETs
// de boot, so para anonimo) e o que NAO PODE esperar (Cormorant 500 do h1; qualquer chamada de quem tem sessao,
// coberta pelos testes da v2, que leem a saude da API na raiz como dado da tela).
test.describe('caminho critico da landing (VXLCP2)', () => {
  test('anonimo: so a fonte do h1 antes do primeiro paint; fontes restantes e GETs de boot depois dele, e tudo chega', async ({ page }) => {
    await mockApi(page);
    await page.goto('/');
    await expect(page.locator('#publicHome')).toBeVisible();
    await page.waitForFunction(() => document.fonts.size >= 4 && [...document.fonts].every((f) => f.status === 'loaded'), null, { timeout: 8000 });
    const m = await page.evaluate(() => {
      const fcp = performance.getEntriesByName('first-contentful-paint')[0].startTime;
      const r = performance.getEntriesByType('resource').map((e) => ({ n: e.name, t: e.startTime }));
      return { fcp, r };
    });
    const t = (re) => m.r.filter((e) => re.test(e.n)).map((e) => e.t);
    expect(t(/cormorant-garamond-latin-500/).length).toBeGreaterThan(0);
    for (const x of t(/cormorant-garamond-latin-500/)) expect(x).toBeLessThan(m.fcp + 50); // do h1, no caminho critico
    for (const re of [/inter-latin-wght/, /jetbrains-mono-latin/, /cormorant-garamond-latin-400/]) {
      const ts = t(re);
      expect(ts.length, String(re)).toBeGreaterThan(0);
      for (const x of ts) expect(x, String(re)).toBeGreaterThanOrEqual(m.fcp + 380);
    }
    const boot = m.r.filter((e) => /^https:\/\/api\.vixradar\.com\/?(\?op=calendario)?$/.test(e.n));
    expect(boot.length).toBeGreaterThan(0);
    for (const e of boot) expect(e.t, e.n).toBeGreaterThanOrEqual(m.fcp + 380);
    // nada ficou pendurado: favicon real e beacon liberados, nenhuma tag adiada sobrando
    await expect(page.locator('link[rel="icon"]')).toHaveAttribute('href', '/favicon.svg');
    expect(await page.locator('script[type="script-adiado"]').count()).toBe(0);
    expect(await page.locator('script[src*="cloudflareinsights"]').count()).toBe(1);
  });

  test('landing nao some sem JS adiado: h1 estendido visivel e sem a landing classica', async ({ page }) => {
    await mockApi(page);
    await page.goto('/');
    await expect(page.locator('h1.ph-h1')).toBeVisible();
    await expect(page.locator('#phClassic')).toBeHidden();
    const modo = await page.evaluate(() => window.VIX_LANDING_MODE);
    expect(modo).toBe('extended');
    await page.goto('/?landing=classic');
    await expect(page.locator('#phClassic')).toBeVisible();
    await expect(page.locator('h1.ph-h1')).toBeHidden();
  });
});

test.describe('pagina publica (anonimo)', () => {
  test('sem 401 para anonimo, admin nao carrega, favicon e 3 familias', async ({ page }) => {
    const pedidos = [];
    page.on('request', (r) => pedidos.push(`${r.method()} ${r.url()}`));
    const d = diagnostico(page);
    await mockApi(page);
    await page.goto('/');
    await expect(page.locator('#publicHome')).toBeVisible();
    await page.waitForTimeout(3500); // cobre o setTimeout de 3s do provider-monitor
    expect(pedidos.filter((p) => p.startsWith('POST https://api.vixradar.com'))).toEqual([]);
    expect(pedidos.filter((p) => /admin-bootstrap|\/admin\//.test(p))).toEqual([]);
    expect(pedidos.filter((p) => /fonts\.googleapis|fonts\.gstatic/.test(p))).toEqual([]);
    await expect(page.locator('link[rel="icon"]')).toHaveAttribute('href', '/favicon.svg');
    const fav = await page.request.get('/favicon.ico');
    expect(fav.headers()['content-type']).toMatch(/image/);
    const familias = await page.evaluate(() => [...document.fonts].map((f) => f.family.replace(/"/g, '')));
    expect([...new Set(familias)].sort()).toEqual(['Cormorant Garamond', 'Inter', 'JetBrains Mono']);
    const menores = await page.evaluate(() => [...document.querySelectorAll('#publicHome *')].filter((e) => e.offsetParent && e.childNodes.length && [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())).map((e) => parseFloat(getComputedStyle(e).fontSize)).filter((s) => s < 11));
    expect(menores).toEqual([]);
    await expect(page.locator('body')).not.toContainText('antes do mercado');
    await expect(page.locator('body')).not.toContainText('antes da manchete');
    expect(d.erros.filter((e) => !/Failed to load resource/.test(e))).toEqual([]);
  });

  test('skip link leva o foco ao conteudo', async ({ page }) => {
    await mockApi(page);
    await page.goto('/');
    // VXLCP2: main.js e liberado ~0,4 s depois do primeiro paint; antes disso o skip link e so a ancora nativa.
    await page.waitForFunction(() => window.__vxMainOk === true);
    await page.keyboard.press('Tab');
    await expect(page.locator('.vx-skip')).toBeFocused();
    await page.keyboard.press('Enter');
    const foco = await page.evaluate(() => document.activeElement && (document.activeElement.tagName + (document.activeElement.className || '')));
    expect(foco).toMatch(/^H1/);
  });

  test('axe na landing: 0 violacoes serias/criticas', async ({ page }) => {
    await mockApi(page);
    await page.goto('/');
    await expect(page.locator('#publicHome')).toBeVisible();
    const r = await new AxeBuilder({ page }).include('#publicHome').withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    const graves = r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    expect(graves.map((v) => `${v.id} (${v.nodes.length}): ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
  });
});

/* ================= v2: Painel de Eventos ================= */
test.describe('v2 Painel de Eventos', () => {
  test('ordem, rotulos e KPI que soma o feed', async ({ page }, info) => {
    const { d } = await abrirV2(page);
    const ids = await page.locator('.vx-ev').evaluateAll((els) => els.map((e) => e.dataset.ev));
    expect(ids.slice(0, 5)).toEqual(IDS_CINCO);
    for (const s of Object.keys(ROTULOS)) {
      const b = page.locator(`.vx-ev[data-sev="${s}"] .vx-badge`).first();
      await expect(b).toContainText(ROTULOS[s]);
      await expect(b).toHaveCSS('color', CORES[s]);
    }
    const total = Number(await page.locator('[data-total-filtro]').innerText());
    const soma = await page.locator('[data-sev-count] .vx-num').evaluateAll((els) => els.reduce((a, e) => a + Number(e.textContent), 0));
    expect(total).toBe(await page.locator('.vx-ev').count());
    expect(soma).toBe(total);
    await salvar(page, info, 'v2-eventos');
    expect(d.erros).toEqual([]);
  });

  test('paridade v1 x v2 no mesmo dado (janela 30d): ids, total e contagem por severidade', async ({ page, context }) => {
    await abrirV1(page);
    const v1 = await page.evaluate(() => {
      const cards = [...document.querySelectorAll('#dash-eventos .v201-card')];
      return cards.map((c) => `${c.dataset.empresa}|${c.querySelector('.vx-sev-badge').dataset.sev}|${c.querySelector('div:nth-child(2)').firstChild.textContent.trim()}`).sort();
    });
    const p2 = await context.newPage();
    await abrirV2(p2);
    const v2 = await p2.locator('.vx-ev').evaluateAll((els) => els.map((e) => `${e.dataset.empresa}|${e.dataset.sev}|${e.querySelector('.vx-ev-tit').textContent.trim()}`).sort());
    expect(v2).toEqual(v1);
    expect(v2.length).toBe(7);
  });

  test('filtros na URL, reabertura e CSV identico ao filtro', async ({ page }, info) => {
    test.skip(!ehDesktop(info), 'filtros desktop; mobile coberto no bottom sheet');
    await abrirV2(page);
    await page.locator('.vx-chip[data-f="sev"][data-k="ECO"]').click();
    await page.locator('.vx-chip[data-f="sev"][data-k="RELEVANTE"]').click();
    await expect(page).toHaveURL(/sev=CRITICO%2CALERTA%2CATENCAO|sev=CRITICO,ALERTA,ATENCAO/);
    await page.locator('#vx-setor').selectOption('Mineração e Siderurgia');
    await expect(page.locator('.vx-ev')).toHaveCount(1);
    const url = page.url();
    await page.reload();
    await expect(page).toHaveURL(url);
    await expect(page.locator('.vx-ev')).toHaveCount(1);
    await expect(page.locator('.vx-ev')).toHaveAttribute('data-ev', 't-atencao');
    // limpa setor e confere CSV = feed filtrado
    await page.locator('#vx-setor').selectOption('');
    const visiveis = await page.locator('.vx-ev').evaluateAll((els) => els.map((e) => e.dataset.ev));
    const [dl] = await Promise.all([page.waitForEvent('download'), page.locator('[data-csv]').click()]);
    const txt = fs.readFileSync(await dl.path(), 'utf8').replace(/^﻿/, '');
    const linhas = txt.trim().split(/\r\n/);
    const idx = linhas[0].split(';').indexOf('id');
    expect(linhas.slice(1).map((l) => l.split(';')[idx])).toEqual(visiveis);
    expect(visiveis).toEqual(['t-critico', 't-alerta', 't-atencao', 't-s2']);
  });

  test('detalhe: evidencia, inferencia, recomendacao; teclado J/K/Esc', async ({ page }, info) => {
    test.skip(!ehDesktop(info));
    await abrirV2(page);
    await page.locator('body').click({ position: { x: 5, y: 300 } });
    await page.keyboard.press('j');
    await expect(page).toHaveURL(/ev=t-critico/);
    const det = page.locator('#vx-det');
    await expect(det).toContainText('Evidência');
    await expect(det).toContainText('Inferência de teste para t-critico.');
    await expect(det).toContainText('Recomendação de teste para t-critico.');
    await expect(det).toContainText('piso aplicado');
    await expect(det.locator('a[href="https://www.rad.cvm.gov.br/teste/t-critico"]')).toBeVisible();
    await page.keyboard.press('j');
    await expect(page).toHaveURL(/ev=t-alerta/);
    await page.keyboard.press('Escape');
    await expect(page).not.toHaveURL(/ev=/);
    await page.keyboard.press('g'); await page.keyboard.press('c');
    await expect(page).toHaveURL(/#\/empresas/);
  });

  test('densidade: clique no dia filtra o feed', async ({ page }, info) => {
    test.skip(!ehDesktop(info));
    await abrirV2(page);
    await page.locator(`.vx-dens-col[data-dia="${diaUtil(1)}"]`).click();
    await expect(page).toHaveURL(new RegExp(`dia=${diaUtil(1)}`));
    await expect(page.locator('.vx-ev')).toHaveCount(5);
  });

  test('estados: carregando, erro e sem leitura', async ({ page, context }) => {
    // carregando
    await abrirV2(page, '#/eventos', { atraso: 2500 });
    await expect(page.locator('[aria-label="Carregando eventos"]')).toBeVisible();
    // erro
    const p2 = await context.newPage();
    await abrirV2(p2, '#/eventos', { falhar: new Set(['state']) });
    await expect(p2.locator('.vx-estado.erro')).toContainText('Isto não é ausência de alerta');
    // vazio: estado sem nenhum evento
    const p3 = await context.newPage();
    await abrirV2(p3, '#/eventos', { estado: { ok: true, results: { Vale: { empresa: 'Vale', eventos: [] } } } });
    await expect(p3.locator('.vx-estado')).toContainText('Sem leitura de eventos nesta sessão. Isto não é ausência de alerta.');
  });

  test('sem timers de rede: nenhuma chamada nova em 6s parado', async ({ page }) => {
    const { chamadas } = await abrirV2(page);
    await expect(page.locator('.vx-ev').first()).toBeVisible();
    await page.waitForTimeout(4000);
    const antes = chamadas.length;
    await page.waitForTimeout(6000);
    expect(chamadas.length).toBe(antes);
  });

  test('axe no Painel v2: 0 violacoes serias/criticas', async ({ page }) => {
    await abrirV2(page);
    await expect(page.locator('.vx-ev').first()).toBeVisible();
    const r = await new AxeBuilder({ page }).include('#vx2-root').withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    const graves = r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
    expect(graves.map((v) => `${v.id} (${v.nodes.length}): ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(' | ')}`)).toEqual([]);
  });
});

/* ================= v2: Empresas e emissor ================= */
test.describe('v2 Empresas', () => {
  test('mesa com o universo inteiro, ordem EWS = op=ews, CSV = filtro, indisponivel nao vira zero', async ({ page }, info) => {
    const { d } = await abrirV2(page, '#/empresas');
    const total = await page.evaluate(() => Object.values(EMISSORES).flat().length); // eslint-disable-line no-undef
    expect(total).toBeGreaterThanOrEqual(104);
    if (ehDesktop(info)) {
      await expect(page.locator('.vx-table tbody tr')).toHaveCount(total);
      const ordem = await page.locator('.vx-table tbody tr').evaluateAll((trs) => trs.slice(0, 4).map((t) => t.dataset.empresa));
      expect(ordem).toEqual(ewsFix().ranking.map((r) => r.empresa));
      const linhaSemEws = page.locator('.vx-table tbody tr[data-empresa="Azul"] td').nth(3);
      await expect(linhaSemEws).toHaveText('—');
      await page.locator('.vx-chip[data-tg="sinal"]').click();
      await expect(page.locator('.vx-table tbody tr')).toHaveCount(4);
      const [dl] = await Promise.all([page.waitForEvent('download'), page.locator('[data-csv]').click()]);
      const linhas = fs.readFileSync(await dl.path(), 'utf8').replace(/^﻿/, '').trim().split(/\r\n/);
      expect(linhas.length - 1).toBe(4);
      expect(linhas[1].split(';')[0]).toBe('Braskem');
      await page.reload();
      await expect(page.locator('.vx-table tbody tr')).toHaveCount(4);
    } else {
      await expect(page.locator('.vx-cards > li')).toHaveCount(total);
    }
    await salvar(page, info, 'v2-empresas');
    expect(d.erros).toEqual([]);
  });

  test('emissor: EWS, piso, drivers e serie identica ao endpoint; abas na URL', async ({ page }, info) => {
    const { d } = await abrirV2(page, '#/empresa/Braskem/visao');
    await expect(page.locator('.vx-emp-h h1')).toHaveText('Braskem');
    await expect(page.locator('.vx-card').first()).toContainText('score_calculado');
    await expect(page.locator('.vx-card').first()).toContainText('58,5');
    await expect(page.locator('.vx-card').first().locator('.vx-drivers li')).toHaveCount(2);
    const pts = await page.locator('.vx-card').nth(1).locator('circle title').allTextContents();
    expect(pts).toEqual(serieFix('Braskem').ews_serie.map((p) => `${p.data}: ${p.score}`));
    await page.locator('#vx-aba-papeis').click();
    await expect(page).toHaveURL(/#\/empresa\/Braskem\/papeis/);
    await page.locator('[data-papel="BRKMA1"]').press('Enter');
    await expect(page.locator('[data-papel="BRKMA1"]')).toHaveAttribute('aria-expanded', 'true');
    await page.locator('#vx-aba-eventos').click();
    await expect(page.locator('.vx-timeline')).toContainText('Evento CRITICO de teste');
    await salvar(page, info, 'v2-emissor');
    const r = await new AxeBuilder({ page }).include('#vx2-root').withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    expect(r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => v.id)).toEqual([]);
    expect(d.erros).toEqual([]);
  });

  test('delegacao para a v1 preserva PDF/comentarios e volta', async ({ page }, info) => {
    test.skip(!ehDesktop(info));
    await abrirV2(page, '#/empresa/Braskem/comentarios');
    await page.locator('[data-v1="nenhuma"]').click();
    await expect(page.locator('#vx2-root')).not.toHaveClass(/vx-on/);
    await expect(page.locator('#vx2-voltar')).toBeVisible();
    await page.locator('#vx2-voltar').click();
    await expect(page.locator('#vx2-root.vx-on')).toBeVisible();
  });
});

/* ================= mobile ================= */
test.describe('mobile', () => {
  for (const tela of ['#/eventos', '#/empresas', '#/empresa/Braskem/visao']) {
    test(`sem rolagem horizontal e alvos >=44px: ${tela}`, async ({ page }, info) => {
      test.skip(ehDesktop(info));
      await abrirV2(page, tela);
      await page.waitForTimeout(500);
      const m = await page.evaluate(() => {
        const r = document.querySelector('#vx2-root .vx-main');
        return { scroll: r.scrollWidth, client: r.clientWidth, doc: document.documentElement.scrollWidth, vw: window.innerWidth };
      });
      expect(m.scroll).toBeLessThanOrEqual(m.client);
      expect(m.doc).toBeLessThanOrEqual(m.vw);
      const pequenos = await page.evaluate(() => [...document.querySelectorAll('#vx2-root .vx-bottom button, #vx2-root .vx-ev, #vx2-root .vx-cards button, #vx2-root .vx-aba, #vx2-root .vx-btn')]
        .filter((b) => b.offsetParent).map((b) => ({ t: b.textContent.trim().slice(0, 20), h: b.getBoundingClientRect().height })).filter((x) => x.h < 44));
      expect(pequenos).toEqual([]);
      await expect(page.locator('.vx-bottom')).toBeVisible();
      await salvar(page, info, 'v2' + tela.replace(/[#/]/g, '-'));
    });
  }
  test('filtros em bottom sheet no mobile', async ({ page }, info) => {
    test.skip(ehDesktop(info));
    await abrirV2(page);
    await expect(page.locator('#vx-filtros')).toBeHidden();
    await page.locator('[data-abrir-filtros]').click();
    await expect(page.locator('#vx-filtros')).toBeVisible();
    await page.locator('.vx-chip[data-f="sev"][data-k="ECO"]').click();
    await expect(page).toHaveURL(/sev=/);
  });
});

/* ================= flag / rollback ================= */
test.describe('flag e rollback', () => {
  test('padrao e v1: sem flag a v2 nao aparece e a v1 renderiza', async ({ page }) => {
    await abrirV1(page);
    await expect(page.locator('#vx2-root.vx-on')).toHaveCount(0);
  });
  test('?ui=v1 desliga e ?ui=v2 liga', async ({ page }) => {
    await mockApi(page);
    await sessaoTeste(page, { flag: null });
    await page.goto('/?ui=v2#/eventos');
    await expect(page.locator('#vx2-root.vx-on')).toBeVisible();
    await page.goto('/?ui=v1');
    await page.waitForFunction(() => document.querySelectorAll('#dash-eventos .v201-card').length > 0);
    await expect(page.locator('#vx2-root.vx-on')).toHaveCount(0);
  });
});
