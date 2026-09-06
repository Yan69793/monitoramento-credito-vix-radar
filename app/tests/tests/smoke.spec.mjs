// Smoke: a superficie publica (landing) carrega sem erro critico.
// Falha dura apenas em pageerror nao atribuivel a rede externa (ex.: CORS do
// ambiente localhost->api.vixradar.com). console/HTTP externos sao registrados
// (diagnostico de baseline), nao viram gate.
import { test, expect } from '@playwright/test';
import { openLanding, waitDemoCard, isExternalNetError } from './helpers.mjs';

test('landing carrega, CACHE_VERSION presente, card demo renderiza (sem fallback)', async ({ page }, testInfo) => {
  const diag = await openLanding(page, { extended: true });
  await waitDemoCard(page);

  const version = await page.evaluate(() => window.CACHE_VERSION || '');
  expect(version).toMatch(/^v\d/);

  const critical = diag.pageErrors.filter((e) => !isExternalNetError(e));
  expect(critical, `pageerrors criticos: ${diag.pageErrors.join(' | ')}`).toEqual([]);

  const httpAll = diag.httpErrors;
  // Ruido de ambiente local (verificado contra prod em 2026-09-06: ambos 200 em vixradar.com):
  // - /cdn-cgi/*  -> injetado pela Cloudflare na borda (email-decode, rum)
  // - /app/js/*   -> admin fora do escopo publico; prod serve 200 (root Pages tem a pasta app)
  const infraLocal = httpAll.filter((h) => /\/cdn-cgi\/|\/app\/js\//.test(h));
  const real = httpAll.filter((h) => !/\/cdn-cgi\/|\/app\/js\//.test(h));
  expect(real, `http >=400 same-origin (fora do ruido local): ${real.join(' | ')}`).toEqual([]);

  test.info().annotations.push({
    type: 'diagnostico',
    description: `console.error (${diag.consoleErrors.length}): ${diag.consoleErrors.slice(0, 5).join(' | ')} | infra-local (404/405 de /cdn-cgi e /app/js, 200 em prod): ${infraLocal.length}`,
  });
  console.log(`[diag] project=${testInfo.project.name} pageerrors=${diag.pageErrors.length} consoleError=${diag.consoleErrors.length} httpReal=${real.length} infraLocal=${infraLocal.length} consoleSample=${diag.consoleErrors.slice(0, 3).join(' || ')}`);
});
