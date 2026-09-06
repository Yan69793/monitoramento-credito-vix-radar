// QA do frontend VIX Radar — baseline ANTES do redesign.
// - Roda contra o proprio app/ servido localmente (http-server), sem deploy.
// - Screenshots de baseline so rodam em Linux (CI): nunca gerar canonico em Windows.
//   O canonico nasce na 1a rodada Linux (workflow_dispatch) e so entra no repo
//   por commit controlado apos aprovacao humana.
// - workers: 1 (screenshots/ordem estaveis) e retries: 0 (baseline deterministica).
import { defineConfig, devices } from '@playwright/test';

const PORT = 4173;
const isLinux = process.platform === 'linux';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  // Template fixo (sem platform): os PNGs de baseline nascem no Linux do CI e
  // sao validados no mesmo ambiente. O nome passado ja inclui a extensao.
  snapshotPathTemplate: '{testDir}/__screenshots__/{arg}',
  expect: {
    timeout: 10_000,
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.02,
      threshold: 0.2,
      animations: 'disabled',
    },
  },
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } },
    },
    {
      name: 'mobile',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 375, height: 812 },
        deviceScaleFactor: 1,
        hasTouch: true,
      },
    },
  ],
  webServer: {
    command: `npx http-server .. -a 127.0.0.1 -p ${PORT} -c-1 -s`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
});

// Convencao usada pelos specs: screenshots visuais so em Linux (CI).
export { isLinux };
