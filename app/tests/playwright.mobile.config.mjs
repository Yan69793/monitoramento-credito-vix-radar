// Responsividade do painel autenticado (VIX-MOBILE-20261018), v1 e v2, 320 a 1440 px.
// Porta propria e sem reuso de servidor. VX_BASE_DIR roda a mesma suite contra a versao antiga.
import { defineConfig, devices } from '@playwright/test';

const PORT = 4192;
const vp = (name, width, height, touch) => ({
  name, use: { ...devices['Desktop Chrome'], viewport: { width, height }, hasTouch: touch, isMobile: false },
});
export default defineConfig({
  testDir: './tests',
  testMatch: /vx-mobile\.spec\.mjs$/,
  fullyParallel: false,
  workers: 2,
  retries: 0,
  timeout: 90_000,
  outputDir: './test-results-mobile',
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: { baseURL: `http://127.0.0.1:${PORT}`, trace: 'off', screenshot: 'off', locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' },
  projects: [
    vp('w320', 320, 640, true),
    vp('w375', 375, 812, true),
    vp('w390', 390, 844, true),
    vp('w430', 430, 932, true),
    vp('w768', 768, 1024, true),
    vp('w1024', 1024, 768, false),
    vp('w1440', 1440, 900, false),
  ],
  webServer: {
    command: `node vx-mobile-stage.mjs && npx http-server .vx-mobile-stage -a 127.0.0.1 -p ${PORT} -c-1 -s`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: false,
    timeout: 30_000,
  },
});
