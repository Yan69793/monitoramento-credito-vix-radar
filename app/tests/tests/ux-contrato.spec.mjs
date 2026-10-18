// Contrato de indicador da interface (auditoria UX/UI de 18/10/2026).
// Cada teste guarda uma correcao e prova as duas pontas: reprova o caso ruim
// e aceita o bom. So exibicao: faixa, metodologia e dado continuam no Worker.
import { test, expect } from '@playwright/test';
import { openLanding } from './helpers.mjs';

async function semLanding(page) {
  await openLanding(page, { extended: true });
  await page.evaluate(() => {
    const ph = document.getElementById('publicHome');
    if (ph) ph.style.display = 'none';
  });
}

// EWSFAIXA1 (A05): mesmo score, mesma faixa e mesma cor em qualquer tela,
// com o clamp e o Math.round de classificarEWS do Worker.
test('faixa do score usa o clamp e o arredondamento do Worker', async ({ page }) => {
  await semLanding(page);
  const regua = await page.evaluate(() => {
    const k = (s) => window.vxSevKey(ewsFaixa(s).label);
    return { s55: k(55), s35_4: k(35.4), s35_5: k(35.5), s15_5: k(15.5), s60_6: k(60.6), s120: k(120), sNeg: k(-3) };
  });
  expect(regua).toEqual({ s55: 'ALERTA', s35_4: 'ATENCAO', s35_5: 'ALERTA', s15_5: 'ATENCAO', s60_6: 'CRITICO', s120: 'CRITICO', sNeg: 'ESTAVEL' });
});

test('Visao Geral pinta o score pela faixa, nao de vermelho fixo', async ({ page }) => {
  await semLanding(page);
  const m = await page.evaluate(() => {
    try { resultados = { Raizen: { empresa: 'Raizen', eventos: [] } }; } catch (_) {}
    try { resultados = { Raizen: { empresa: 'Raizen', eventos: [] } }; } catch (_) {}
    try {
      ewsRankingCache = { ranking: [
        { empresa: 'Critica', score: 61, decomposicao: [] },
        { empresa: 'Raizen', score: 55, decomposicao: [] },
        { empresa: 'Atencao', score: 20, decomposicao: [] },
      ] };
    } catch (_) {}
    window._vixDesign2026Render();
    const rows = [...document.querySelectorAll('#mo-content .vx2-rank .vx2-row')].map((r) => ({
      nome: r.querySelector('.vx2-name').textContent.trim(),
      cor: getComputedStyle(r.querySelector('.vx2-score')).color,
      fill: getComputedStyle(r.querySelector('.vx2-fill')).backgroundColor,
      tag: r.querySelector('.vx2-tag').textContent.trim(),
    }));
    const hexRgb = (h) => 'rgb(' + [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)).join(', ') + ')';
    return { rows, alerta: hexRgb(window.VX_SEV.ALERTA.cor), critico: hexRgb(window.VX_SEV.CRITICO.cor) };
  });
  const raizen = m.rows.find((r) => r.nome === 'Raizen');
  const critica = m.rows.find((r) => r.nome === 'Critica');
  expect(raizen.cor).toBe(m.alerta);
  expect(raizen.fill).toBe(m.alerta);
  expect(raizen.tag).toBe('ALERTA');
  expect(critica.cor).toBe(m.critico);
  expect(critica.tag).toBe('CRÍTICO');
  expect(raizen.cor).not.toBe(critica.cor);
});

// VXTERMOS1 (A41, A12): stub de emissor adiado nao mostra termo interno nem a rodada falsa.
const PROIBIDOS = /token_cap|deferred|ledger|Cap efetivo|Tier [A-Z]|EWS=/i;

function renderEmissor(page, analise, aba) {
  return page.evaluate(async ({ analise, aba }) => {
    resultados = { CPFL: Object.assign({ empresa: 'CPFL', eventos: [], alertas_mercado: [], timestamp: '2026-10-17T21:10:04.000Z' }, analise) };
    window.ARQUIVO_PRE = { CPFL: [] };
    window.__histEmissorCache = {};
    window.__histEmissorLoading = null;
    selecionada = 'CPFL'; modo = 'live'; abaAtual = aba; loading = false;
    window.renderEmpBody();
    await new Promise((r) => setTimeout(r, 0));
    const body = document.getElementById('emp-body');
    return { texto: body.innerText, rodadas: [...body.querySelectorAll('.rodada-row')].map((r) => r.innerText.replace(/\s+/g, ' ').trim()) };
  }, { analise, aba });
}

const STUB_ADIADO = {
  sem_eventos: true,
  cobertura_nota: 'Tier FULL. Cap efetivo 0 tokens - ledger minimo. EWS=0. Priorizar amanha.',
  fontes_consultadas: [{ rodada: '0', query: 'token_cap', resultado: 'deferred' }],
  _token_cap_deferred: true,
};

test('emissor adiado nao expoe token_cap, deferred nem ledger e esconde a rodada falsa', async ({ page }) => {
  await semLanding(page);
  const buscas = await renderEmissor(page, STUB_ADIADO, 'buscas');
  expect(buscas.texto).not.toMatch(PROIBIDOS);
  expect(buscas.rodadas).toEqual([]);
  expect(buscas.texto).toContain('Análise adiada por limite de processamento');
  const eventos = await renderEmissor(page, STUB_ADIADO, 'eventos');
  expect(eventos.texto).not.toMatch(PROIBIDOS);
  expect(eventos.texto).toContain('Análise adiada por limite de processamento');
});

test('rodada real continua visivel e nota comum so perde o jargao', async ({ page }) => {
  await semLanding(page);
  const r = await renderEmissor(page, {
    sem_eventos: true,
    cobertura_nota: 'Tier SKIP. CVM: 2 docs na janela. 0 novos. Motivos: sem_delta_24h.',
    fontes_consultadas: [
      { rodada: '0', query: 'token_cap', resultado: 'deferred' },
      { rodada: '2', query: '"CPFL" rating Fitch', resultado: 'sem novidade' },
    ],
  }, 'buscas');
  expect(r.texto).not.toMatch(PROIBIDOS);
  expect(r.rodadas).toHaveLength(1);
  expect(r.rodadas[0]).toContain('"CPFL" rating Fitch');
  expect(r.texto).toContain('CVM: 2 docs na janela');
  expect(r.texto).toContain('sem delta 24h');
});

// AGENDAKPI1 (A06): KPIs da Agenda seguem o horizonte, contando os eventos da lista.
test('KPIs da Agenda mudam com o horizonte e batem com a lista', async ({ page }) => {
  await semLanding(page);
  await page.evaluate(() => {
    const ev = (data, tipo, emissor) => ({ data, tipo, emissor, titulo: tipo + ' ' + emissor, fonte: 'CVM' });
    // Build de 90 dias: 18 emissores com assembleia, 1 com vencimento, nenhum resultado.
    const cobertura = { total_emissores_universo: 104, com_resultado: 0, com_vencimento: 1, com_assembleia: 18 };
    const lista = {
      7: [ev('2026-10-20', 'assembleia', 'Grupo Mateus')],
      30: [ev('2026-10-20', 'assembleia', 'Grupo Mateus'), ev('2026-10-30', 'assembleia', 'Grupo Mateus'),
        ev('2026-10-30', 'assembleia', 'Sabesp'), ev('2026-11-05', 'vencimento', 'CSN')],
    };
    const orig = window.fetch.bind(window);
    window.fetch = (url, opts) => {
      const u = String(url);
      if (u.includes('op=calendario')) {
        const h = Number((u.match(/horizonte=(\d+)/) || [])[1] || 30);
        const body = { ok: true, horizonte_dias: h, cobertura, eventos: lista[h] || [], gerado_em: '2026-10-18T04:01:00.000Z' };
        return Promise.resolve(new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } }));
      }
      return orig(url, opts);
    };
    try { localStorage.removeItem('vix:agenda:filtros:v1'); } catch (_) {}
  });
  const kpis = () => page.evaluate(() => {
    const o = {};
    document.querySelectorAll('#agenda-overlay .ag-stat').forEach((s) => {
      o[s.querySelector('.ag-stat-lbl').textContent.trim()] = s.querySelector('.ag-stat-val').textContent.trim();
    });
    return o;
  });
  await page.evaluate(() => { agendaAbrir(); agendaSetHorizonte(30); });
  await expect(page.locator('#agenda-overlay .ag-stat')).toHaveCount(5);
  await expect.poll(async () => (await kpis()).Horizonte).toBe('30d');
  const k30 = await kpis();
  await page.evaluate(() => agendaSetHorizonte(7));
  await expect.poll(async () => (await kpis()).Horizonte).toBe('7d');
  const k7 = await kpis();
  expect([k30.Assembleias, k30.Vencimentos, k30.Resultados]).toEqual(['3', '1', '0']);
  expect([k7.Assembleias, k7.Vencimentos, k7.Resultados]).toEqual(['1', '0', '0']);
  expect(k7.Universo).toBe('104');
});
