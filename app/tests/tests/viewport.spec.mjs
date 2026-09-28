// Viewport: mede overflow horizontal nas larguras desktop (1280) e mobile (375).
// Neste baseline o overflow e REGISTRADO (nao vira gate): o alvo do redesign e
// zero overflow; hoje qualquer ocorrencia pre-existente fica documentada.
import { test, expect } from '@playwright/test';
import { openLanding, measureOverflow } from './helpers.mjs';

test('landing sem overflow horizontal (medicao registrada)', async ({ page }, testInfo) => {
  await openLanding(page, { extended: true });
  const m = await measureOverflow(page);
  testInfo.annotations.push({
    type: 'medicao-overflow',
    description: `${testInfo.project.name}: scrollWidth=${m.scrollWidth} clientWidth=${m.clientWidth} overflowX=${m.overflowX}`,
  });
  console.log(`[overflow:${testInfo.project.name}]`, JSON.stringify(m));
  expect(m.scrollWidth).toBeGreaterThan(0);
});

test('visao geral respeita a altura real do main e alcanca o ultimo item', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const publicHome = document.getElementById('publicHome');
    if (publicHome) publicHome.style.display = 'none';
    if (typeof window._marketOverviewClick === 'function') window._marketOverviewClick();
    const host = document.getElementById('mo-content');
    const parent = document.getElementById('main');
    if (!host || !parent) throw new Error('mo-content/main ausente');
    host.innerHTML = Array.from({ length: 60 }, (_, i) =>
      '<div style="height:40px;border-bottom:1px solid #333">probe ' + i + '</div>'
    ).join('');
    host.scrollTop = host.scrollHeight;
    const hr = host.getBoundingClientRect();
    const pr = parent.getBoundingClientRect();
    const lr = host.lastElementChild.getBoundingClientRect();
    return {
      scrollable: host.scrollHeight > host.clientHeight,
      maxed: Math.abs(host.scrollTop - (host.scrollHeight - host.clientHeight)) <= 1,
      hostBottom: Math.round(hr.bottom),
      parentBottom: Math.round(pr.bottom),
      lastBottom: Math.round(lr.bottom),
    };
  });
  expect(m.scrollable).toBe(true);
  expect(m.maxed).toBe(true);
  expect(m.hostBottom).toBeLessThanOrEqual(m.parentBottom + 1);
  expect(m.lastBottom).toBeLessThanOrEqual(m.parentBottom + 1);
});


test('visao geral distingue falta de leitura de zero medido', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const publicHome = document.getElementById('publicHome');
    if (publicHome) publicHome.style.display = 'none';
    try { resultados = {}; } catch (_) {}
    try { ewsRankingCache = { ranking: [] }; } catch (_) {}
    window._vixDesign2026Render();
    const vals = [...document.querySelectorAll('#mo-content .vx2-kpi-v')].map((e) => e.textContent.trim());
    return { vals, text: document.getElementById('mo-content').textContent };
  });
  expect(m.vals[1]).toBe('—');
  expect(m.vals[2]).toBe('—');
  expect(m.text).toContain('Sem leitura');
});


test('navegacao principal alterna Visao Geral e Painel de Eventos sem duplicar a pagina atual', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome');
    if (ph) ph.style.display = 'none';
    if (typeof window._marketOverviewClick !== 'function') throw new Error('Visao Geral indisponivel');
    window._marketOverviewClick();
    const btn = document.getElementById('sidebar-visao-geral');
    const label = () => btn?.querySelector('.sidebar-view-label')?.textContent?.trim() || '';
    const first = { label: label(), oldButton: !!document.querySelector('#mo-content .vx2-old') };
    btn.click();
    const second = { label: label(), dashVisible: getComputedStyle(document.getElementById('dashboard')).display !== 'none' };
    btn.click();
    const third = { label: label(), overviewVisible: getComputedStyle(document.getElementById('mo-content')).display !== 'none' };
    return { first, second, third };
  });
  expect(m.first.label).toBe('Painel de Eventos');
  expect(m.first.oldButton).toBe(false);
  expect(m.second.label).toBe('Visão Geral');
  expect(m.second.dashVisible).toBe(true);
  expect(m.third.label).toBe('Painel de Eventos');
  expect(m.third.overviewVisible).toBe(true);
});


test('boot autenticado prioriza Visao Geral sem duplicar navegacao no mobile', async ({ page }) => {
  await openLanding(page, { extended: true });
  const bootContract = await page.evaluate(() => [...document.scripts].some((s) =>
    (s.textContent || '').includes('window._marketOverviewClick?window._marketOverviewClick():mostrarDashboard()')
  ));
  expect(bootContract).toBe(true);
  await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    window._marketOverviewClick();
  });
  const btn = page.locator('#sidebar-visao-geral');
  if ((await page.viewportSize()).width <= 768) {
    await expect(page.locator('#mob-btn-visaogeral')).toHaveClass(/active/);
    await expect(btn).toBeHidden();
    await page.evaluate(() => { if (typeof mobNavEmissores === 'function') mobNavEmissores(); });
    await expect(page.locator('#mobile-bottom-nav')).toBeVisible();
    await expect(page.locator('#mob-btn-analise')).toHaveClass(/active/);
  } else {
    await expect(btn.locator('.sidebar-view-label')).toHaveText('Painel de Eventos');
    await expect(btn).toHaveClass(/events-primary/);
    await expect(btn.locator('.sidebar-action-cue')).toBeVisible();
  }
});


test('cards compactos do Painel de Eventos mantem densidade controlada', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    if (typeof mostrarDashboard === 'function') mostrarDashboard();
    const host = document.getElementById('dash-eventos');
    host.innerHTML = renderEventoCard({ classificacao:'RELEVANTE', titulo:'Evento objetivo para teste de densidade', evento:'Descrição suficientemente longa para validar truncamento em uma única linha sem perder a estrutura do card.', data_evento:'2026-09-27', fonte_tipo:'CVM', _empresa:'Emissor Teste' }, true);
    const card = host.querySelector('.ev-card.compact');
    const body = card.querySelector('.ev-card-body');
    const txt = card.querySelector('.ev-texto');
    const meta = card.querySelector('.ev-meta-v63');
    return { height: Math.round(card.getBoundingClientRect().height), paddingTop: parseFloat(getComputedStyle(body).paddingTop), clamp: getComputedStyle(txt).webkitLineClamp, meta: getComputedStyle(meta).display };
  });
  expect(m.height).toBeLessThanOrEqual(115);
  expect(m.paddingTop).toBeLessThanOrEqual(8);
  expect(m.clamp).toBe('1');
  expect(m.meta).toBe('none');
});


test('visao geral nao corta texto informativo e oferece acesso ao emissor', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    try { resultados = { Sabesp: { empresa:'Sabesp', eventos:[{ classificacao:'RELEVANTE', titulo:'Evento de teste', data_evento:'2026-09-27' }] } }; } catch (_) {}
    try { ewsRankingCache = { ranking:[{ empresa:'Sabesp', score:72, faixa:'ATENCAO', decomposicao:[{ fator:'driver informativo completo sem corte visual', pontos:5 }] }] }; } catch (_) {}
    window._vixDesign2026Render();
    const driver = document.querySelector('#mo-content .vx2-driver');
    const open = document.querySelector('#mo-content .vx2-open');
    if (!driver || !open) throw new Error('driver/link da Visao Geral ausente');
    const cs = getComputedStyle(driver);
    window.__vxTesteSelecionado = null;
    const original = window.selecionar;
    window.selecionar = (name) => { window.__vxTesteSelecionado = name; };
    open.click();
    window.selecionar = original;
    return { overflow:cs.overflow, textOverflow:cs.textOverflow, whiteSpace:cs.whiteSpace, display:cs.display, text:driver.textContent.trim(), link:open.textContent.trim(), selected:window.__vxTesteSelecionado };
  });
  expect(m.textOverflow).not.toBe('ellipsis');
  expect(m.whiteSpace).toBe('normal');
  expect(m.display).not.toBe('none');
  expect(m.text).toContain('driver informativo completo');
  expect(m.link).toContain('Ver emissor');
  expect(m.selected).toBe('Sabesp');
});


test('Painel de Eventos consolida dois eventos da mesma empresa no mesmo dia', async ({ page }) => {
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    resultados = {
      'Empresa Teste': { empresa:'Empresa Teste', eventos:[
        { classificacao:'CRITICO', titulo:'Evento crítico', data_evento:'2026-09-27', fonte_tipo:'CVM' },
        { classificacao:'RELEVANTE', titulo:'Segundo evento', data_evento:'2026-09-27', fonte_tipo:'IMPRENSA' }
      ] }
    };
    if (typeof mostrarDashboard === 'function') mostrarDashboard();
    if (typeof _v201Refresh === 'function') _v201Refresh();
    const g = document.querySelector('.v201-emp-agrupado');
    if (!g) throw new Error('grupo consolidado ausente');
    const h = g.querySelector('header');
    const body = g.querySelector('[id^=emp-body-]');
    const before = { text:h.textContent, expanded:h.getAttribute('aria-expanded'), display:getComputedStyle(body).display, cards:body.querySelectorAll('.v201-card').length };
    h.click();
    const after = { expanded:h.getAttribute('aria-expanded'), display:getComputedStyle(body).display };
    return { before, after };
  });
  expect(m.before.text).toContain('2 atualizações no dia');
  expect(m.before.expanded).toBe('false');
  expect(m.before.display).toBe('none');
  expect(m.before.cards).toBe(2);
  expect(m.after.expanded).toBe('true');
  expect(m.after.display).not.toBe('none');
});


test('Agenda consolida varias divulgacoes da mesma empresa no mesmo dia', async ({ page }) => {
  await openLanding(page, { extended: true });
  await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    const orig = window.fetch.bind(window);
    window.fetch = (url, opts) => {
      if (String(url).includes('op=calendario')) {
        const body = {
          ok:true, horizonte_dias:30, cobertura:{total_emissores_universo:104,com_resultado:1,com_vencimento:1,com_assembleia:0},
          eventos:[
            {data:'2026-09-28',emissor:'Empresa Agenda',tipo:'resultado',titulo:'Resultado trimestral',fonte:'CVM'},
            {data:'2026-09-28',emissor:'Empresa Agenda',tipo:'vencimento',titulo:'Vencimento debênture',fonte:'ANBIMA'}
          ]
        };
        return Promise.resolve(new Response(JSON.stringify(body), {status:200, headers:{'Content-Type':'application/json'}}));
      }
      return orig(url, opts);
    };
    agendaAbrir();
  });
  await page.waitForSelector('#agenda-overlay .ag-evento-grupo', { timeout:5000 });
  const g = page.locator('#agenda-overlay .ag-evento-grupo').first();
  await expect(g).toContainText('Empresa Agenda');
  await expect(g).toContainText('2 atualizações');
  await expect(g).toHaveAttribute('aria-expanded','false');
  await g.click();
  await expect(g).toHaveAttribute('aria-expanded','true');
  await expect(g.locator('.ag-evento')).toHaveCount(2);
});


test('mobile primary views stay mutually exclusive', async ({ page }) => {
  test.skip((await page.viewportSize()).width > 768, 'mobile only');
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    const visible = (id) => getComputedStyle(document.getElementById(id)).display !== 'none';
    window._marketOverviewClick();
    const overview = { mo:visible('mo-content'), dash:visible('dashboard'), emp:visible('emp-panel'), cfg:visible('config-panel') };
    mobNavDashboard();
    const events = { mo:visible('mo-content'), dash:visible('dashboard'), emp:visible('emp-panel'), cfg:visible('config-panel') };
    selecionada = 'Sabesp'; window.selecionada = 'Sabesp'; mobNavAnalise();
    const issuer = { mo:visible('mo-content'), dash:visible('dashboard'), emp:visible('emp-panel'), cfg:visible('config-panel') };
    mobNavConfig();
    const config = { mo:visible('mo-content'), dash:visible('dashboard'), emp:visible('emp-panel'), cfg:visible('config-panel') };
    return { overview, events, issuer, config };
  });
  expect(m.overview).toEqual({ mo:true, dash:false, emp:false, cfg:false });
  expect(m.events).toEqual({ mo:false, dash:true, emp:false, cfg:false });
  expect(m.issuer).toEqual({ mo:false, dash:false, emp:true, cfg:false });
  expect(m.config).toEqual({ mo:false, dash:false, emp:false, cfg:true });
});

test('mobile bottom nav reflects overview and issuer drawer remains navigable', async ({ page }) => {
  test.skip((await page.viewportSize()).width > 768, 'mobile only');
  await openLanding(page, { extended: true });
  const m = await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    window._marketOverviewClick();
    const overviewActive = document.getElementById('mob-btn-visaogeral').classList.contains('active');
    const analysisInitiallyActive = document.getElementById('mob-btn-analise').classList.contains('active');
    selecionada = null; window.selecionada = null; mobNavAnalise();
    const nav = document.getElementById('mobile-bottom-nav');
    const sidebar = document.getElementById('sidebar');
    return {
      overviewActive,
      analysisInitiallyActive,
      analysisActive: document.getElementById('mob-btn-analise').classList.contains('active'),
      navDisplay: getComputedStyle(nav).display,
      drawerOpen: sidebar.classList.contains('drawer-open'),
      overviewShortcutInDrawer: getComputedStyle(document.getElementById('sidebar-visao-geral')).display
    };
  });
  expect(m.overviewActive).toBe(true);
  expect(m.analysisInitiallyActive).toBe(false);
  expect(m.analysisActive).toBe(true);
  expect(m.navDisplay).toBe('flex');
  expect(m.drawerOpen).toBe(true);
  expect(m.overviewShortcutInDrawer).toBe('none');
});

test('mobile bottom buttons respond to real taps', async ({ page }) => {
  test.skip((await page.viewportSize()).width > 768, 'mobile only');
  await openLanding(page, { extended: true });
  await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    window._marketOverviewClick();
  });

  await page.locator('#mob-btn-dashboard').click();
  await expect(page.locator('#dashboard')).toBeVisible();
  await expect(page.locator('#mo-content')).toBeHidden();

  await page.locator('#mob-btn-visaogeral').click();
  await expect(page.locator('#mo-content')).toBeVisible();
  await expect(page.locator('#dashboard')).toBeHidden();

  await page.evaluate(() => { selecionada = null; window.selecionada = null; });
  await page.locator('#mob-btn-analise').click();
  await expect(page.locator('#sidebar')).toHaveClass(/drawer-open/);
  await expect(page.locator('#mobile-bottom-nav')).toBeVisible();

  await page.locator('#mob-btn-dashboard').click();
  await expect(page.locator('#sidebar')).not.toHaveClass(/drawer-open/);
  await expect(page.locator('#dashboard')).toBeVisible();

  await page.locator('#mob-btn-config').click();
  await expect(page.locator('#config-panel')).toBeVisible();

  await page.evaluate(() => {
    window.agendaAbrir = () => document.getElementById('agenda-overlay').classList.add('show');
  });
  await page.locator('#mob-btn-agenda').click();
  await expect(page.locator('#agenda-overlay')).toHaveClass(/show/);
  await expect(page.locator('#mob-btn-config')).toHaveClass(/active/);
});

test('mobile topbar is compact and does not duplicate bottom navigation', async ({ page }) => {
  test.skip((await page.viewportSize()).width > 768, 'mobile only');
  await openLanding(page, { extended: true });
  await page.evaluate(() => {
    const ph = document.getElementById('publicHome'); if (ph) ph.style.display = 'none';
    window._marketOverviewClick();
  });
  await expect(page.locator('#top-center')).toBeHidden();
  await expect(page.locator('#btn-agenda')).toBeHidden();
  await expect(page.locator('#btn-carteira')).toBeVisible();
  await expect(page.locator('#btn-mais')).toBeVisible();
  const m = await page.locator('#top-right').evaluate((el) => ({
    scrollWidth: el.scrollWidth,
    clientWidth: el.clientWidth,
    overflowX: getComputedStyle(el).overflowX
  }));
  expect(m.scrollWidth).toBeLessThanOrEqual(m.clientWidth + 1);
  expect(m.overflowX).not.toBe('auto');
  await expect(page.locator('#mob-btn-visaogeral')).toContainText('Visão');
});
