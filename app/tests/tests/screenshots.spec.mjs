// Baseline visual (toHaveScreenshot) da superficie publica.
// SO roda em Linux (CI): nunca gerar canonico em Windows — rendering difere e
// o baseline precisa nascer no mesmo ambiente em que sera validado.
//
// Politica de baseline (aprovada):
// - 1a rodada Linux (workflow_dispatch generate-baseline) roda com
//   `--update-snapshots` e PUBLIC A os PNGs como artefato (nunca commita).
// - Apos aprovacao humana, os PNGs entram no repo por commit controlado.
// - Rodadas seguintes comparam contra o PNG commitado e falham por regressao;
//   se o baseline nao estiver commitado, o teste falha com instrucao
//   (nada e criado silenciosamente em CI normal).
import { test, expect } from '@playwright/test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { openLanding, waitDemoCard, isLinux } from './helpers.mjs';

const SKIP_MSG = 'baseline visual gerado/validado somente no Linux do CI (Windows gera rendering divergente)';
const BASELINE_DIR = path.join(process.cwd(), 'tests', '__screenshots__');

test.describe('visual baseline', () => {
  test.skip(!isLinux, SKIP_MSG);

  test('landing por viewport', async ({ page }, testInfo) => {
    const name = `landing-${testInfo.project.name}.png`;
    const baselinePath = path.join(BASELINE_DIR, name);
    const generating = process.env.UPDATE_SNAPSHOTS === '1';

    if (!generating && !existsSync(baselinePath)) {
      // Politica: sem baseline commitado, CI normal FALHA com instrucao
      // (nada e criado silenciosamente). Geracao explicita roda com
      // UPDATE_SNAPSHOTS=1 + --update-snapshots (CI Linux) e publica artefatos.
      test.fail(
        true,
        `baseline ${name} ausente no repo. Gerar via CI Linux (workflow_dispatch generate-baseline), revisar os artefatos e commitar em etapa controlada.`,
      );
    }

    await openLanding(page, { extended: true });
    await waitDemoCard(page);
    await expect(page).toHaveScreenshot(name, {
      maxDiffPixelRatio: 0.02,
      animations: 'disabled',
    });
  });
});
