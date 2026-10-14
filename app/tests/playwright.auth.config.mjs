// Teste autenticado ponta a ponta, 100% local: frontend servido de .vx-stage e Worker REAL em workerd
// local (vx-auth-worker.mjs), ligados por roteamento do navegador. Nenhum byte sai para producao,
// preview ou terceiros (qualquer outro host e abortado pelo proprio spec).
import { defineConfig, devices } from '@playwright/test';

const ESTATICO = 4191;
const WORKER = 8788;
export default defineConfig({
  testDir: './tests',
  testMatch: /vx-auth-.*\.spec\.mjs$/,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  outputDir: './test-results-auth',
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: { trace: 'retain-on-failure', screenshot: 'only-on-failure', locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' },
  projects: [
    { name: 'desktop-1440', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'mobile-390', use: { ...devices['Desktop Chrome'], viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: false } },
  ],
  webServer: [
    { command: `node vx-stage.mjs && node vx-serve.mjs .vx-stage ${ESTATICO}`, url: `http://127.0.0.1:${ESTATICO}/`, reuseExistingServer: false, timeout: 30_000 },
    { command: `node vx-auth-worker.mjs ${WORKER}`, url: `http://127.0.0.1:${WORKER}/`, reuseExistingServer: false, timeout: 120_000 },
  ],
});
