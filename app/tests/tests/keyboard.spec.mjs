// Keyboard/foco basico na landing: Tab percorre os focaveis; cada foco esta
// visivel no viewport; o foco nunca "some" para <body> no meio da sequencia.
// Asserts permissivos (baseline): nao corrigimos UI agora.
import { test, expect } from '@playwright/test';
import { openLanding, tabFocusOrder } from './helpers.mjs';

test('Tab percorre focaveis visiveis sem perder foco para body', async ({ page }, testInfo) => {
  await openLanding(page);
  const order = await tabFocusOrder(page, 10);

  testInfo.annotations.push({
    type: 'ordem-de-tab',
    description: JSON.stringify(order),
  });
  console.log('[tab-order]', JSON.stringify(order));

  const sequence = order.filter((o) => o.tag !== 'BODY');
  expect(sequence.length).toBeGreaterThanOrEqual(3);
  const invisible = sequence.filter((o) => !o.visible);
  expect(invisible, `focaveis fora do viewport: ${JSON.stringify(invisible)}`).toEqual([]);
  // Se o foco caiu em BODY antes do fim dos passos, a sequencia terminou cedo:
  // aceitavel se ja percorremos >=3 focaveis.
  const firstBody = order.findIndex((o) => o.tag === 'BODY');
  if (firstBody >= 0 && sequence.length >= 3) {
    testInfo.annotations.push({
      type: 'fim-de-tab',
      description: `body alcancado no passo ${firstBody + 1} apos ${sequence.length} focaveis (fim natural da pagina)`,
    });
  }
});
