// VIX-MOBILE-20261018: responsividade do painel autenticado, v1 e v2, 320 a 1440 px.
// API 100% interceptada (vx-fixtures.mjs), sessao de TESTE, nada sai para a rede.
// Cada tela mede: overflow horizontal, sobreposicao no cabecalho, alvo de toque,
// conteudo escondido sob a barra inferior, texto minusculo e colunas espremidas.
// Capturas em .mobile-shots/<rotulo>/ (ou VX_SHOTS_DIR), rotulo via VX_SHOTS, padrao "depois".
import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import { mockApi, sessaoTeste, estadoCincoSeveridades, diaUtil, API } from './vx-fixtures.mjs';

const ROTULO = process.env.VX_SHOTS || 'depois';
const movel = (info) => info.project.use.viewport.width <= 768;
const larg = (info) => info.project.use.viewport.width;

function diagnostico(page) {
  const erros = [];
  page.on('pageerror', (e) => erros.push('pageerror: ' + e.message));
  return erros;
}

function estadoComBrk() {
  const e = estadoCincoSeveridades();
  e.results['BRK Ambiental'] = {
    empresa: 'BRK Ambiental', timestamp: '2026-10-17T07:07:00Z',
    eventos: [{ id: 't-brk', classificacao: 'ATENCAO', data_evento: diaUtil(1), titulo: 'Falha de abastecimento de água e litigância em Paraíso do Tocantins',
      evento: 'Descrição de teste.', fonte_tipo: 'IMPRENSA', fonte_primaria: 'https://valor.globo.com/teste/brk', impacto_credito: 'Inferência de teste com texto longo o bastante para quebrar em várias linhas no celular.', escopo: 'idiossincratico' }],
  };
  return e;
}

function agenda() {
  const ev = (d, emissor, tipo, titulo) => ({ data: d, emissor, tipo, titulo, setor: 'Saneamento', fonte: 'CVM', fonte_url: 'https://www.rad.cvm.gov.br/teste' });
  const hoje = new Date(); const dia = (n) => { const d = new Date(hoje); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  return {
    ok: true, horizonte_dias: 30, gerado_em: new Date().toISOString(),
    cobertura: { total_emissores_universo: 104, com_vencimento: 10, com_assembleia: 40 },
    eventos: [
      ev(dia(1), 'Grupo Mateus', 'assembleia', 'AGE de teste 1'), ev(dia(1), 'Grupo Mateus', 'assembleia', 'AGE de teste 2'),
      ev(dia(1), 'Grupo Mateus', 'assembleia', 'AGE de teste 3'), ev(dia(1), 'Grupo Mateus', 'assembleia', 'AGE de teste 4'),
      ev(dia(8), 'Algar Telecom', 'assembleia', 'AGE de teste'), ev(dia(8), 'Algar Telecom', 'vencimento', 'Vencimento de debênture de teste'),
      ev(dia(10), 'Companhia de Saneamento Básico do Estado de São Paulo', 'resultado', 'ITR 3T26 de teste com título longo para medir quebra'),
    ],
  };
}

async function abrir(page, flag = null, hash = '/') {
  const erros = diagnostico(page);
  await mockApi(page, { estado: estadoComBrk() });
  await page.route(`${API}/**`, (route) => {
    const u = new URL(route.request().url());
    if (u.searchParams.get('op') === 'calendario') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(agenda()) });
    // medidor de varreduras do cabecalho com o texto mais longo que ele produz ("12 min atras")
    if (u.searchParams.get('action') === 'rl_inspect') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, limites: { session: [25] }, do_state: { timestamps_ultimos_30min: 3, ultimo_timestamp_ms: Date.now() - 12 * 60000 } }) });
    return route.fallback();
  });
  await sessaoTeste(page, { flag });
  await page.addInitScript(() => { try { localStorage.setItem('radar_cookies_aceitos', 'true'); } catch (_) { /* storage */ } });
  await page.goto(hash);
  return erros;
}

async function abrirV1(page) {
  const erros = await abrir(page);
  await page.waitForFunction(() => typeof mostrarDashboard === 'function' && document.querySelectorAll('#dash-eventos .v201-card').length > 0);
  return erros;
}

/** Mede a tela inteira no navegador. `escopo` = seletor do conteudo da tela. */
async function medir(page, escopo) {
  return page.evaluate((escopo) => {
    const vw = document.documentElement.clientWidth; const vh = window.innerHeight;
    const vis = (el) => { if (!el) return false; const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && +s.opacity !== 0; };
    const nome = (el) => el.id ? '#' + el.id : (el.className && typeof el.className === 'string' ? el.tagName.toLowerCase() + '.' + el.className.trim().split(/\s+/)[0] : el.tagName.toLowerCase());
    const out = { vw, docOverflow: document.documentElement.scrollWidth - vw, overflowEls: [], headerOverlap: [], pequenos: [], textoMin: [], coberto: null, navDesigual: null };
    const raiz = document.querySelector(escopo);
    // 1. elementos que saem da tela pela direita (exclui scrollers horizontais intencionais)
    if (raiz) {
      const dentroDeScroller = (el) => { for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) { const s = getComputedStyle(p); if ((s.overflowX === 'auto' || s.overflowX === 'scroll' || s.overflowX === 'hidden') && p.clientWidth < p.scrollWidth + 1) return true; } return false; };
      for (const el of raiz.querySelectorAll('*')) {
        if (!vis(el)) continue; const r = el.getBoundingClientRect();
        if (r.right > vw + 1 && !dentroDeScroller(el)) out.overflowEls.push(nome(el) + ' right=' + Math.round(r.right));
        if (out.overflowEls.length > 8) break;
      }
      // 2. texto visivel abaixo de 11px
      const w = document.createTreeWalker(raiz, NodeFilter.SHOW_TEXT);
      for (let n = w.nextNode(); n; n = w.nextNode()) {
        if (!n.textContent.trim()) continue; const el = n.parentElement; if (!vis(el)) continue;
        const fs = parseFloat(getComputedStyle(el).fontSize); if (fs < 11) out.textoMin.push(nome(el) + ' ' + fs + 'px "' + n.textContent.trim().slice(0, 20) + '"');
        if (out.textoMin.length > 8) break;
      }
      // 3. alvos de toque (so botoes reais, visiveis, no viewport)
      for (const el of raiz.querySelectorAll('button, [role="button"], select, a.btn, input[type="checkbox"]')) {
        if (!vis(el)) continue; const r = el.getBoundingClientRect(); if (r.bottom < 0 || r.top > vh * 3) continue;
        if (el.getAttribute('role') === 'switch') { if (r.height < 28) out.pequenos.push(nome(el) + ' switch ' + Math.round(r.height)); continue; }
        if (el.classList.contains('vx-dens-col')) continue; // barra do grafico de densidade: alvo e a coluna inteira, largura limitada pelo grafico (pendencia declarada)
        if (r.height < 40 || r.width < 40) out.pequenos.push(nome(el) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height) + ' "' + (el.textContent || '').trim().slice(0, 16) + '"');
      }
    }
    // 4. cabecalho: filhos visiveis nao podem se cruzar
    const tb = document.querySelector('#topbar');
    if (vis(tb)) {
      const itens = ['#topbar .logo', '#status-pill', '#btn-carteira', '#btn-mais', '#btn-cmdk', '#rl-meter'].map((s) => document.querySelector(s)).filter(vis);
      for (let i = 0; i < itens.length; i++) for (let j = i + 1; j < itens.length; j++) {
        const a = itens[i].getBoundingClientRect(), b = itens[j].getBoundingClientRect();
        const ix = Math.min(a.right, b.right) - Math.max(a.left, b.left), iy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (ix > 1 && iy > 1) out.headerOverlap.push(nome(itens[i]) + ' x ' + nome(itens[j]) + ' ' + Math.round(ix) + 'px');
      }
      const tr = tb.getBoundingClientRect(); for (const el of itens) { const r = el.getBoundingClientRect(); if (r.right > tr.right + 1 || r.left < tr.left - 1) out.headerOverlap.push(nome(el) + ' fora do topbar'); }
    }
    // 5. barra inferior: 5 botoes de largura igual e o fim do conteudo acima dela
    const nav = document.querySelector('#mobile-bottom-nav');
    if (vis(nav)) {
      const ws = [...nav.querySelectorAll('.mob-nav-btn')].filter(vis).map((b) => Math.round(b.getBoundingClientRect().width));
      out.navDesigual = Math.max(...ws) - Math.min(...ws);
      out.navBtns = ws.length;
    }
    return out;
  }, escopo);
}

/** Rola o contêiner da tela ate o fim e confere que o ultimo filho visivel fica acima da barra. */
async function fimVisivel(page, rolador, ultimo) {
  return page.evaluate(([rolador, ultimo]) => {
    const sc = rolador === 'window' ? null : document.querySelector(rolador);
    if (sc) sc.scrollTop = sc.scrollHeight; else window.scrollTo(0, document.documentElement.scrollHeight);
    const nav = document.querySelector('#mobile-bottom-nav');
    const r = nav && nav.getBoundingClientRect().height > 0 ? nav.getBoundingClientRect() : null;
    const els = [...document.querySelectorAll(ultimo)].filter((e) => e.getBoundingClientRect().height > 0);
    const u = els[els.length - 1]; if (!u || !r) return null;
    return Math.round(u.getBoundingClientRect().bottom - r.top); // > 0 = escondido sob a barra
  }, [rolador, ultimo]);
}

async function foto(page, info, nome) {
  const dir = `${process.env.VX_SHOTS_DIR || '.mobile-shots'}/${ROTULO}`; // fora do outputDir, que o Playwright limpa a cada rodada
  fs.mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: `${dir}/${info.project.name}-${nome}.png`, fullPage: false });
}

function checar(m, info, extra = {}) {
  const falhas = [];
  if (m.docOverflow > 1) falhas.push('documento rola na horizontal: +' + m.docOverflow + 'px');
  if (m.overflowEls.length) falhas.push('saem da tela: ' + m.overflowEls.join(', '));
  if (m.headerOverlap.length) falhas.push('cabecalho sobreposto: ' + m.headerOverlap.join(', '));
  if (movel(info)) {
    if (m.pequenos.length && !extra.ignorarToque) falhas.push('alvo < 40px: ' + m.pequenos.slice(0, 8).join(', '));
    if (m.textoMin.length) falhas.push('texto < 11px: ' + m.textoMin.join(', '));
    if (m.navDesigual != null && (m.navDesigual > 2 || m.navBtns !== 5)) falhas.push('barra inferior desigual: ' + m.navDesigual + 'px, ' + m.navBtns + ' botoes');
  }
  return falhas;
}

const NAV = { eventos: '#mob-btn-dashboard', visao: '#mob-btn-visaogeral', emissor: '#mob-btn-analise', agenda: '#mob-btn-agenda', config: '#mob-btn-config' };
const FN = {
  eventos: () => mostrarDashboard(), // eslint-disable-line no-undef
  visao: () => (window.mobNavVisaoGeral ? mobNavVisaoGeral() : window._marketOverviewClick()), // eslint-disable-line no-undef
  emissor: () => mobNavAnalise(), // eslint-disable-line no-undef
  agenda: () => agendaAbrir(), // eslint-disable-line no-undef
  config: () => mostrarConfig(), // eslint-disable-line no-undef
};
/** No celular navega tocando a barra inferior de verdade (como o usuario); no desktop chama a funcao. */
async function irV1(page, info, tela) {
  if (tela === 'emissor') await page.evaluate(() => selecionar('BRK Ambiental')); // eslint-disable-line no-undef
  if (larg(info) <= 768) await page.locator(NAV[tela]).click();
  else await page.evaluate(FN[tela]);
  await page.waitForTimeout(450); // fadeIn das telas e do overlay
}
/** Exatamente um item ativo na barra, e e o da tela aberta. */
async function navAtivo(page, info, tela) {
  if (larg(info) > 768) return [];
  const ativos = await page.evaluate(() => [...document.querySelectorAll('#mobile-bottom-nav .mob-nav-btn.active')].map((b) => '#' + b.id));
  return ativos.length === 1 && ativos[0] === NAV[tela] ? [] : ['barra inferior marca ' + JSON.stringify(ativos) + ' em vez de ' + NAV[tela]];
}

test.describe('v1', () => {
  test('Eventos', async ({ page }, info) => {
    const erros = await abrirV1(page);
    await irV1(page, info, 'eventos');
    await expect(page.locator('#dash-eventos .v201-card').first()).toBeVisible();
    await foto(page, info, 'v1-eventos');
    const m = await medir(page, '#dashboard');
    const f = checar(m, info).concat(await navAtivo(page, info, 'eventos'));
    // filtros: em celular, mesma largura em cada linha (grade, nao quebra torta)
    if (movel(info) && larg(info) < 768) {
      const fl = await page.evaluate(() => [...document.querySelectorAll('#v201-filter-bar .vf-cat')].filter((e) => e.getBoundingClientRect().height > 0).map((e) => Math.round(e.getBoundingClientRect().width)));
      if (fl.length >= 2 && Math.max(...fl) - Math.min(...fl) > 4) f.push('filtros com larguras diferentes: ' + fl.join('/'));
      const cob = await fimVisivel(page, '#dashboard', '#dash-eventos .v201-card');
      if (cob != null && cob > 0) f.push('ultimo cartao escondido sob a barra: ' + cob + 'px');
    }
    expect(erros).toEqual([]);
    expect(f, f.join('\n')).toEqual([]);
  });

  test('Visão', async ({ page }, info) => {
    const erros = await abrirV1(page);
    await irV1(page, info, 'visao');
    await foto(page, info, 'v1-visao');
    const m = await medir(page, '#mo-content');
    expect(erros).toEqual([]);
    const f = checar(m, info).concat(await navAtivo(page, info, 'visao'));
    expect(f, f.join('\n')).toEqual([]);
  });

  test('Emissor', async ({ page }, info) => {
    const erros = await abrirV1(page);
    await irV1(page, info, 'emissor');
    await expect(page.locator('#emp-panel')).toBeVisible();
    await foto(page, info, 'v1-emissor');
    const m = await medir(page, '#emp-head');
    const f = checar(m, info).concat(await navAtivo(page, info, 'emissor'));
    // nome do emissor ocupa a largura e nao vira coluna de uma palavra por linha
    const g = await page.evaluate(() => {
      const n = document.querySelector('#emp-nome') || document.querySelector('#emp-head h1, #emp-head h2, #emp-head .emp-nome');
      const r = n && n.getBoundingClientRect(); const lh = n ? parseFloat(getComputedStyle(n).lineHeight) || parseFloat(getComputedStyle(n).fontSize) * 1.2 : 0;
      const metaEls = [...document.querySelectorAll('#emp-head *')].filter((e) => /Última análise/.test(e.textContent) && e.children.length === 0);
      const meta = metaEls[0] && metaEls[0].getBoundingClientRect();
      return { nomeW: r ? Math.round(r.width) : 0, linhas: r ? Math.round(r.height / lh) : 0, metaW: meta ? Math.round(meta.width) : null, vw: document.documentElement.clientWidth };
    });
    if (movel(info) && g.nomeW && g.linhas > 2) f.push('nome do emissor em ' + g.linhas + ' linhas (' + g.nomeW + 'px)');
    if (movel(info) && g.metaW != null && g.metaW < g.vw * 0.5) f.push('metadado da analise espremido em ' + g.metaW + 'px');
    expect(erros).toEqual([]);
    expect(f, f.join('\n')).toEqual([]);
  });

  test('Agenda', async ({ page }, info) => {
    const erros = await abrirV1(page);
    await irV1(page, info, 'agenda');
    await expect(page.locator('#agenda-overlay .ag-evento').first()).toBeVisible();
    await page.waitForTimeout(300);
    await foto(page, info, 'v1-agenda');
    const m = await medir(page, '#agenda-overlay');
    const f = checar(m, info).concat(await navAtivo(page, info, 'agenda'));
    // tocar outro item da barra fecha a agenda e abre a tela pedida
    if (larg(info) < 768) {
      await page.locator(NAV.eventos).click();
      await page.waitForTimeout(300);
      if (await page.locator('#agenda-overlay').isVisible()) f.push('agenda continua aberta depois de tocar Eventos');
      f.push(...await navAtivo(page, info, 'eventos'));
    }
    const g = await page.evaluate(() => {
      const cols = [...document.querySelectorAll('#agenda-overlay .ag-evento')].filter((e) => e.getBoundingClientRect().height > 0).flatMap((row) => [...row.children].filter((c) => c.getBoundingClientRect().height > 0).map((c) => Math.round(c.getBoundingClientRect().width)));
      const nav = document.querySelector('#mobile-bottom-nav'); const ov = document.querySelector('#agenda-overlay');
      const navVis = nav && nav.getBoundingClientRect().height > 0;
      let navCoberto = false;
      if (navVis) { const r = nav.getBoundingClientRect(); const el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); navCoberto = !nav.contains(el); }
      return { minCol: cols.length ? Math.min(...cols) : null, navVis, navCoberto, ovBottom: ov ? Math.round(ov.getBoundingClientRect().bottom) : null };
    });
    if (movel(info) && g.minCol != null && g.minCol < 120) f.push('coluna da agenda com ' + g.minCol + 'px');
    if (movel(info) && larg(info) < 768 && g.navCoberto) f.push('agenda cobre a barra inferior');
    expect(erros).toEqual([]);
    expect(f, f.join('\n')).toEqual([]);
  });

  test('Configurações e menu', async ({ page }, info) => {
    const erros = await abrirV1(page);
    await irV1(page, info, 'config');
    await expect(page.locator('#config-panel')).toBeVisible();
    await foto(page, info, 'v1-config');
    const m = await medir(page, '#config-panel');
    const f = checar(m, info).concat(await navAtivo(page, info, 'config'));
    await page.locator('#btn-mais').click();
    await expect(page.locator('#menu-mais')).toBeVisible();
    await page.waitForTimeout(250);
    await foto(page, info, 'v1-menu');
    const g = await page.evaluate(() => {
      const mm = document.querySelector('#menu-mais'); const r = mm.getBoundingClientRect(); const vw = document.documentElement.clientWidth;
      const itens = [...mm.querySelectorAll('button, a')].filter((e) => e.getBoundingClientRect().height > 0).map((e) => Math.round(e.getBoundingClientRect().height));
      const emoji = [...mm.querySelectorAll('button, a')].some((e) => /\p{Extended_Pictographic}/u.test(e.textContent));
      return { left: Math.round(r.left), right: Math.round(r.right), vw, minItem: Math.min(...itens), emoji };
    });
    if (g.left < 0 || g.right > g.vw) f.push('menu fora da tela: ' + g.left + '..' + g.right);
    if (movel(info) && g.minItem < 44) f.push('item de menu com ' + g.minItem + 'px');
    if (g.emoji) f.push('menu usa emoji como icone');
    // fecha com Escape ou clique fora
    await page.mouse.click(5, page.viewportSize().height / 2);
    await expect(page.locator('#menu-mais')).toBeHidden();
    expect(erros).toEqual([]);
    expect(f, f.join('\n')).toEqual([]);
  });
});

test.describe('v2', () => {
  for (const [nome, hash, escopo] of [['eventos', '/#/eventos', '#vx2-root'], ['emissor', '/#/empresa/Braskem/visao', '#vx2-root'], ['empresas', '/#/empresas', '#vx2-root']]) {
    test('v2 ' + nome, async ({ page }, info) => {
      const erros = await abrir(page, 'v2', hash);
      await expect(page.locator('#vx2-root.vx-on')).toBeVisible();
      await page.waitForTimeout(500);
      await foto(page, info, 'v2-' + nome);
      const m = await medir(page, escopo);
      const f = checar(m, info);
      if (movel(info) && larg(info) < 768) {
        const g = await page.evaluate(() => {
          const nav = document.querySelector('.vx-bottom'); const bs = [...nav.querySelectorAll('button')].map((b) => Math.round(b.getBoundingClientRect().width));
          const glifo = [...nav.querySelectorAll('.ic')].some((s) => s.textContent.trim().length > 0 && !s.querySelector('svg'));
          const main = document.querySelector('#vx-main'); main.scrollTop = main.scrollHeight;
          const ult = [...document.querySelectorAll('#vx-tela > *')].filter((e) => e.getBoundingClientRect().height > 0).pop();
          const r = nav.getBoundingClientRect(); const topo = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
          return { desigual: Math.max(...bs) - Math.min(...bs), glifo, coberto: ult ? Math.round(ult.getBoundingClientRect().bottom - nav.getBoundingClientRect().top) : null, tapada: !nav.contains(topo) ? (topo && (topo.id || topo.className)) : null };
        });
        if (g.desigual > 2) f.push('barra v2 desigual: ' + g.desigual + 'px');
        if (g.glifo) f.push('barra v2 usa caractere unicode como icone');
        if (g.coberto != null && g.coberto > 0) f.push('fim da tela v2 sob a barra: ' + g.coberto + 'px');
        if (g.tapada) f.push('barra v2 tapada por ' + g.tapada);
      }
      expect(erros).toEqual([]);
      expect(f, f.join('\n')).toEqual([]);
    });
  }
});
