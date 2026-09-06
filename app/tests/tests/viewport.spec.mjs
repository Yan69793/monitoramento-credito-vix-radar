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
