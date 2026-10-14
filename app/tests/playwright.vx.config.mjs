// Config da validacao do redesign (Fase 0.5 + v2). Porta propria e sem reuso de
// servidor: nunca testa por engano o app/ de outra worktree ou sessao.
import { defineConfig, devices } from '@playwright/test';

const PORT = 4190;
export default defineConfig({
  testDir: './tests',
  testMatch: /vx-.*\.spec\.mjs$/,
  testIgnore: /vx-auth-.*\.spec\.mjs$/, // roda em playwright.auth.config.mjs (Worker real em workerd local)
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  outputDir: './test-results-vx',
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: { baseURL: `http://127.0.0.1:${PORT}`, trace: 'retain-on-failure', screenshot: 'only-on-failure', locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' },
  projects: [
    { name: 'desktop-1440', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'mobile-390', use: { ...devices['Desktop Chrome'], viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: false } },
    { name: 'mobile-360', use: { ...devices['Desktop Chrome'], viewport: { width: 360, height: 780 }, hasTouch: true, isMobile: false } },
  ],
  webServer: {
    command: `node vx-stage.mjs && npx http-server .vx-stage -a 127.0.0.1 -p ${PORT} -c-1 -s`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
