// Helpers compartilhados dos specs de baseline do frontend.
// Escopo: superficie publica anonima (landing #publicHome + card demo local).
// Dashboard autenticado fica fora (senha de admin nunca em teste).
import { expect } from '@playwright/test';

export const isLinux = process.platform === 'linux';
export const BASE = 'http://127.0.0.1:4173';

export function isExternalNetError(msg = '') {
  const m = String(msg);
  return /failed to fetch|networkerror|load failed|net::err_|cors/i.test(m);
}

export async function collectDiagnostics(page) {
  const diag = { pageErrors: [], consoleErrors: [], httpErrors: [], overflows: [] };
  page.on('pageerror', (err) => diag.pageErrors.push(String(err && err.message || err)));
  page.on('console', (msg) => {
    if (msg.type() === 'error') diag.consoleErrors.push(msg.text());
  });
  page.on('response', (res) => {
    if (res.status() >= 400 && new URL(res.url()).hostname === '127.0.0.1') {
      diag.httpErrors.push(`${res.status()} ${res.url()}`);
    }
  });
  return diag;
}

export async function ensureExtended(page) {
  const card = page.locator('#phDemoCard');
  const hidden = await card.isHidden().catch(() => true);
  if (hidden) {
    const saiba = page.locator('#phBtnSaiba');
    if (await saiba.isVisible().catch(() => false)) await saiba.click();
    await expect(page.locator('#publicHome')).toHaveClass(/vix-landing-extended/, { timeout: 15_000 });
  }
}

export async function openLanding(page, { extended = false } = {}) {
  const diag = await collectDiagnostics(page);
  await page.goto(BASE + '/', { waitUntil: 'domcontentloaded' });
  await expect(page.locator('#publicHome')).toBeVisible({ timeout: 15_000 });
  if (extended) await ensureExtended(page);
  return diag;
}

// Espera o card demo da landing estendida terminar de renderizar (local /landing-demo.json).
export async function waitDemoCard(page) {
  await ensureExtended(page);
  const card = page.locator('#phDemoCard');
  await expect(card).toBeVisible({ timeout: 15_000 });
  await expect(card).not.toHaveAttribute('data-demo-fallback', '1', { timeout: 15_000 });
}

export function measureOverflow(page) {
  return page.evaluate(() => ({
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: document.documentElement.clientWidth,
    overflowX: document.documentElement.scrollWidth > document.documentElement.clientWidth,
  }));
}

export function isVisibleInViewport(page, handle) {
  return handle.evaluate((el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 &&
      r.top < window.innerHeight && r.left < window.innerWidth;
  });
}

export async function tabFocusOrder(page, steps = 8) {
  const order = [];
  for (let i = 0; i < steps; i += 1) {
    await page.keyboard.press('Tab');
    const info = await page.evaluate(() => {
      const el = document.activeElement;
      if (!el || el === document.body) return { tag: 'BODY', text: '' };
      const r = el.getBoundingClientRect();
      return {
        tag: el.tagName,
        id: el.id || '',
        cls: typeof el.className === 'string' ? el.className.slice(0, 40) : '',
        text: (el.textContent || '').trim().slice(0, 40),
        visible: r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0,
      };
    });
    order.push(info);
    if (info.tag === 'BODY') break;
  }
  return order;
}
