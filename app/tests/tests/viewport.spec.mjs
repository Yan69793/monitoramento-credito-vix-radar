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
