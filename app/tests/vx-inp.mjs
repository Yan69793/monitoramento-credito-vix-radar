// INP de LABORATORIO (nao e dado de campo): interacoes reais roteirizadas, CPU 4x mais lenta,
// fixtures deterministicas (nenhuma chamada sai), INP = pior interacao medida pelo Event Timing
// (com <50 interacoes o INP e a maior duracao). Serve para comparar versoes e achar gargalo; o
// numero de campo (CrUX/RUM) so existe com trafego real e nao e inferido daqui.
// Uso: node vx-inp.mjs [saida.json]   (exige .vx-stage: node vx-stage.mjs)
import { chromium } from '@playwright/test';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mockApi, sessaoTeste, diaUtil } from './tests/vx-fixtures.mjs';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const PORTA = 4198;
const saida = process.argv[2];
const srv = spawn(process.execPath, ['vx-serve.mjs', '.vx-stage', String(PORTA)], { cwd: aqui, stdio: 'ignore' });
const matar = () => { try { if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(srv.pid), '/T', '/F'], { stdio: 'ignore' }); else srv.kill(); } catch (_) { /* ok */ } };
process.on('exit', matar);
await new Promise((r) => setTimeout(r, 1500));

const MEDIDOR = () => {
  window.__inp = new Map();
  try {
    new PerformanceObserver((lista) => {
      for (const e of lista.getEntries()) {
        if (!e.interactionId) continue;
        const atual = window.__inp.get(e.interactionId);
        if (!atual || e.duration > atual.dur) window.__inp.set(e.interactionId, { dur: e.duration, tipo: e.name, alvo: e.target ? (e.target.id || e.target.className || e.target.tagName) : '' });
      }
    }).observe({ type: 'event', durationThreshold: 16, buffered: true });
  } catch (_) { /* navegador sem Event Timing */ }
};
const colher = (page) => page.evaluate(() => {
  const v = [...window.__inp.values()].sort((a, b) => b.dur - a.dur);
  return { interacoes: v.length, inp_ms: v.length ? Math.round(v[0].dur) : 0, pior: v[0] || null, top3: v.slice(0, 3).map((x) => `${x.tipo}:${Math.round(x.dur)}ms ${String(x.alvo).slice(0, 40)}`) };
});

async function cenario(browser, nome, viewport, roteiro) {
  const context = await browser.newContext({ viewport, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo', hasTouch: viewport.width < 800 });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.addInitScript(MEDIDOR);
  await roteiro(page, context);
  const r = await colher(page);
  await context.close();
  return { cenario: nome, viewport: `${viewport.width}x${viewport.height}`, ...r };
}
const esperar = (page, ms = 250) => page.waitForTimeout(ms);

const browser = await chromium.launch();
const resultados = [];
const URL0 = `http://127.0.0.1:${PORTA}`;
for (const vp of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
  resultados.push(await cenario(browser, 'landing anonima: Acessar, foco e digitacao no login', vp, async (page) => {
    await mockApi(page);
    await page.goto(URL0 + '/');
    await page.waitForTimeout(1200);
    await page.locator('.ph-nav__cta').click(); await esperar(page);
    await page.locator('#agEmail').click(); await page.keyboard.type('pessoa@empresa.com.br', { delay: 15 }); await esperar(page);
    await page.locator('#agPass').click(); await page.keyboard.type('senha-qualquer', { delay: 15 }); await esperar(page);
  }));
  resultados.push(await cenario(browser, 'v2 Eventos: chips, setor, detalhe, densidade', vp, async (page) => {
    await mockApi(page); await sessaoTeste(page, { flag: 'v2' });
    await page.goto(URL0 + '/#/eventos');
    await page.locator('.vx-ev').first().waitFor();
    await esperar(page, 500);
    if (vp.width >= 800) {
      await page.locator('.vx-chip[data-f="sev"][data-k="ECO"]').click(); await esperar(page);
      await page.locator('.vx-chip[data-f="sev"][data-k="RELEVANTE"]').click(); await esperar(page);
      await page.locator('#vx-setor').selectOption('Mineração e Siderurgia'); await esperar(page);
      await page.locator('#vx-setor').selectOption(''); await esperar(page);
      await page.locator(`.vx-dens-col[data-dia="${diaUtil(1)}"]`).click(); await esperar(page);
      await page.locator('body').click({ position: { x: 5, y: 300 } });
      for (const k of ['j', 'j', 'k', 'Escape']) { await page.keyboard.press(k); await esperar(page, 200); }
    }
    await page.locator('.vx-ev').first().click(); await esperar(page);
  }));
  resultados.push(await cenario(browser, 'v2 Empresas: mesa, abrir emissor, abas', vp, async (page) => {
    await mockApi(page); await sessaoTeste(page, { flag: 'v2' });
    await page.goto(URL0 + '/#/empresas');
    await page.locator('.vx-chip[data-tg="sinal"]').waitFor({ timeout: 8000 });
    await esperar(page, 500);
    await page.locator('.vx-chip[data-tg="sinal"]').click(); await esperar(page);
    await page.locator('.vx-chip[data-tg="sinal"]').click(); await esperar(page);
    await page.locator('#vx-e-ord').selectOption({ index: 1 }); await esperar(page);
    await page.locator('[data-dir]').click(); await esperar(page);
    await page.goto(URL0 + '/#/empresa/Braskem/visao');
    await page.locator('#vx-aba-papeis').waitFor({ timeout: 8000 }); await esperar(page, 500);
    await page.locator('#vx-aba-papeis').click(); await esperar(page, 400);
    await page.locator('#vx-aba-eventos').click(); await esperar(page, 400);
  }));
  resultados.push(await cenario(browser, 'v1 logada: Painel de Eventos e card', vp, async (page) => {
    await mockApi(page); await sessaoTeste(page, { flag: null });
    await page.goto(URL0 + '/');
    await page.waitForFunction(() => typeof mostrarDashboard === 'function' && document.querySelectorAll('#dash-eventos .v201-card').length > 0, null, { timeout: 15000 });
    await page.evaluate(() => mostrarDashboard());
    await esperar(page, 500);
    await page.locator('#dash-eventos .v201-card').first().click(); await esperar(page);
  }));
}
await browser.close();
matar();
console.table(resultados.map(({ cenario: c, viewport: v, interacoes, inp_ms }) => ({ cenario: c, viewport: v, interacoes, inp_ms })));
for (const r of resultados) console.log(`${r.viewport} | ${r.cenario} | INP ${r.inp_ms} ms | ${r.top3.join(' ; ')}`);
if (saida) fs.writeFileSync(saida, JSON.stringify(resultados, null, 2));
