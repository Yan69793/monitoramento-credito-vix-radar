// FILTROEVENTOS1 — regressao do filtro de severidade do feed (somente frontend).
//
// Causa reproduzida em producao: um estado legado em localStorage com as
// severidades do resumo em false zerava o feed e o cabecalho exibia "Nenhuma",
// sem caminho de volta pela UI (a lista canonica estava divergente entre
// FILTROS_DEFAULT, pills, resumo e a validacao de "ultima ativa").
//
// Contrato coberto (A..E):
//   A) legado todas=false => normaliza para todas=true;
//   B) somente ATENCAO=true => resumo "Atencao", nunca "Nenhuma";
//   C) desligar a ultima severidade ativa => recusada;
//   D) defaults permitem CRITICO, ALERTA, ATENCAO, RELEVANTE e ECO;
//   E) estado parcial valido continua preservado apos reload.
//
// Nao depende de backend/Worker: o bootstrap do patch v201 roda no parse do
// documento e o contrato e observavel via localStorage + #v201-filter-bar.
import { test, expect } from '@playwright/test';

const LS_KEY = 'radar_v201_filtros';
const SEED_FLAG = '__filtroeventos1_seed';
const CANON = ['CRITICO', 'ALERTA', 'ATENCAO', 'RELEVANTE', 'ECO'];
const ORIGEM_DEFAULT = {
  rating: true, fato_relevante: true, comunicado: true, imprensa: true, regulador: true,
};
const ESCOPO_DEFAULT = { idiossincratico: true, setorial: true };

// Objeto de severidade com as 5 chaves canonicas na ordem canonica.
function sev(ativas) {
  const o = {};
  for (const k of CANON) o[k] = ativas.includes(k);
  return o;
}

// Semeia o localStorage antes do primeiro parse do documento. O flag em
// sessionStorage garante que o seed valha uma vez so: num reload o valor lido
// e o que o proprio app persistiu, e nao o seed (senao o teste E se auto-enganaria).
async function seedOnce(page, payload) {
  await page.addInitScript(([key, raw, flag]) => {
    try {
      if (window.sessionStorage.getItem(flag)) return;
      window.localStorage.setItem(key, raw);
      window.sessionStorage.setItem(flag, '1');
    } catch (e) { /* storage bloqueado: o teste falha na assercao, nao aqui */ }
  }, [LS_KEY, JSON.stringify(payload), SEED_FLAG]);
}

async function lerFiltros(page) {
  const raw = await page.evaluate((k) => window.localStorage.getItem(k), LS_KEY);
  return raw ? JSON.parse(raw) : null;
}

// _v201Refresh() encadeia render do dashboard, que depende de dados que nao
// existem fora da sessao autenticada. O bar injeta antes disso, entao a falha
// e de ambiente; devolvemos a mensagem para virar anotacao, nao gate.
async function abrirPainelSeveridade(page) {
  const erro = await page.evaluate(() => {
    try { window._v201ToggleCat('severidade'); return null; } catch (e) { return String(e && e.message || e); }
  });
  return erro;
}

async function chamarToggleSev(page, s) {
  return page.evaluate((sevKey) => {
    try { window._v201ToggleSev(sevKey); return null; } catch (e) { return String(e && e.message || e); }
  }, s);
}

function textoDoResumo(page) {
  // Os 4 botoes de categoria carregam aria-expanded; o de severidade e o 2o.
  return page.locator('#v201-filter-bar button[aria-expanded]').nth(1).textContent();
}

test.describe('FILTROEVENTOS1 · severidade canonica', () => {
  test('A) legado com todas=false normaliza para todas=true', async ({ page }) => {
    await seedOnce(page, {
      janela: '30d',
      severidade: sev([]), // legado: nenhuma ativa
      escopo: ESCOPO_DEFAULT,
      origem: ORIGEM_DEFAULT,
    });
    await page.goto('/');

    const f = await lerFiltros(page);
    expect(f, 'normalizacao deveria ter persistido na carga').not.toBeNull();
    expect(f.severidade).toEqual(sev(CANON));

    // Segunda carga: nada muda (normalizacao e idempotente e nao reescreve).
    await page.reload();
    expect((await lerFiltros(page)).severidade).toEqual(sev(CANON));
  });

  test('B) somente ATENCAO ativa => resumo "Atencao", nunca "Nenhuma"', async ({ page }) => {
    await seedOnce(page, {
      janela: '30d',
      severidade: sev(['ATENCAO']),
      escopo: ESCOPO_DEFAULT,
      origem: ORIGEM_DEFAULT,
    });
    await page.goto('/');

    // Estado parcial valido nao e sobrescrito pela carga.
    expect((await lerFiltros(page)).severidade).toEqual(sev(['ATENCAO']));

    const erro = await abrirPainelSeveridade(page);
    if (erro) test.info().annotations.push({ type: 'nota', description: `refresh pos-carga: ${erro}` });

    const resumo = await textoDoResumo(page);
    expect(resumo).toContain('Atencao');
    expect(resumo).not.toContain('Nenhuma');
  });

  test('C) desligar a ultima severidade ativa e recusada', async ({ page }) => {
    page.on('dialog', (d) => d.accept());

    // C.1 — o caso que expoe a divergencia: a lista canonica tem ATENCAO como
    // unica ativa, mas o objeto persistido carrega uma chave fora da canonica
    // (ESTAVEL). Validar por Object.values() contava ESTAVEL e deixava desligar
    // a ultima canonica, zerando o feed de forma permanente.
    await seedOnce(page, {
      janela: '30d',
      severidade: Object.assign(sev(['ATENCAO']), { ESTAVEL: true }),
      escopo: ESCOPO_DEFAULT,
      origem: ORIGEM_DEFAULT,
    });
    await page.goto('/');

    // Na carga a chave fora da canonica ja sai do estado.
    let f = await lerFiltros(page);
    expect(Object.keys(f.severidade).sort(), 'ESTAVEL vazando nao pode ser chave de filtro').toEqual([...CANON].sort());

    const erro = await chamarToggleSev(page, 'ATENCAO');
    if (erro) test.info().annotations.push({ type: 'nota', description: `toggle recusado: ${erro}` });

    f = await lerFiltros(page);
    expect(CANON.filter((k) => f.severidade[k]), 'ATENCAO era a unica ativa').toEqual(['ATENCAO']);

    // C.2 — com duas ativas a recusa nao se aplica: o desligamento passa.
    await chamarToggleSev(page, 'CRITICO');
    await chamarToggleSev(page, 'ATENCAO');

    f = await lerFiltros(page);
    expect(CANON.filter((k) => f.severidade[k])).toEqual(['CRITICO']);
    expect(f.severidade.ATENCAO).toBe(false);
  });

  test('D) defaults permitem CRITICO, ALERTA, ATENCAO, RELEVANTE e ECO', async ({ page }) => {
    // Payload sem "severidade": o filtro precisa nascer completo pelo default.
    await seedOnce(page, { janela: '30d' });
    await page.goto('/');

    const f = await lerFiltros(page);
    expect(Object.keys(f.severidade).sort()).toEqual([...CANON].sort());
    for (const k of CANON) expect(f.severidade[k], `${k} deveria vir ativa por default`).toBe(true);

    const erro = await abrirPainelSeveridade(page);
    if (erro) test.info().annotations.push({ type: 'nota', description: `refresh pos-carga: ${erro}` });

    // Toda severidade canonica precisa de pill clicavel — era aqui que ATENCAO sumia.
    const pills = page.locator('#v201-filter-bar button[aria-pressed]');
    await expect(pills).toHaveCount(CANON.length);
    const rotulos = (await pills.allTextContents()).map((t) => t.trim()).sort();
    expect(rotulos).toEqual([...CANON].sort());
    for (const el of await pills.all()) {
      await expect(el).toHaveAttribute('aria-pressed', 'true');
    }

    // Com as 5 ativas o resumo e "Todas".
    expect(await textoDoResumo(page)).toContain('Todas');
  });

  test('E) estado parcial valido continua preservado apos reload', async ({ page }) => {
    const parcial = sev(['CRITICO', 'RELEVANTE']);
    await seedOnce(page, {
      janela: '30d',
      severidade: parcial,
      escopo: ESCOPO_DEFAULT,
      origem: ORIGEM_DEFAULT,
    });
    await page.goto('/');
    expect((await lerFiltros(page)).severidade).toEqual(parcial);

    await page.reload();
    expect((await lerFiltros(page)).severidade, 'reload nao pode achatar o estado parcial').toEqual(parcial);

    // Uma gravacao posterior (outro filtro qualquer) tambem nao pode "consertar"
    // o parcial para todas-true: a normalizacao so age em estado invalido.
    await page.evaluate(() => { try { window._v201SetJanela('Tudo'); } catch (e) {} });
    await page.reload();
    const depo = await lerFiltros(page);
    expect(depo.janela).toBe('Tudo');
    expect(depo.severidade, 'save de outro filtro nao pode mexer na severidade').toEqual(parcial);

    const erro = await abrirPainelSeveridade(page);
    if (erro) test.info().annotations.push({ type: 'nota', description: `refresh pos-reload: ${erro}` });

    // O resumo lista exatamente as ativas, na ordem canonica.
    const resumo = await textoDoResumo(page);
    expect(resumo).toContain('Critico+Relevante');
    expect(resumo).not.toContain('Nenhuma');
  });
});

// ---------------------------------------------------------------------------
// Ranking EWS — prova comportamental de que a severidade da linha obedece a
// sua propria pill, e nao a regra paralela ALERTA/ATENCAO => RELEVANTE||CRITICO.
//
// O caminho exercitado e o de producao: mutacao em #ews-ranking-panel ->
// MutationObserver -> _v201ApplyEwsV3 -> window._v201RenderEWSv3. O spy em
// _v201RenderEWSv3 e o que expoe o resultado do filtro; a alternativa (chamar
// _v201ApplyEwsV3 direto) nao existe, a funcao vive na closure do patch.
// ---------------------------------------------------------------------------

const RANKING = [
  { id: 'r-critico', severidade: 'CRITICO', score: 90 },
  { id: 'r-alerta', severidade: 'ALERTA', score: 80 },
  { id: 'r-atencao', severidade: 'ATENCAO', score: 70 },
  { id: 'r-relevante', severidade: 'RELEVANTE', score: 60 },
  { id: 'r-eco', severidade: 'ECO', score: 50 },
  { id: 'r-estavel', severidade: 'ESTAVEL', score: 40 },
  { id: 'r-desconhecida', severidade: 'NAO_MAPEADA', score: 30 },
  { id: 'r-por-label', label: 'ECO', score: 20 }, // severidade vem do label
  { id: 'r-score-zero', severidade: 'CRITICO', score: 0 }, // cai no pre-filtro score>0
];

// Semeia o estado ANTES do parse: a 1a carga so estabelece a origem, o reload e
// que roda o patch v201 lendo o localStorage. Diferente do seedOnce dos testes
// A..E, aqui varios estados no MESMO teste precisam valer a cada carga.
async function carregarComSeveridade(page, severidade) {
  await page.goto('/');
  await page.evaluate(([k, v]) => {
    window.localStorage.setItem(k, v);
  }, [LS_KEY, JSON.stringify({
    janela: '30d', severidade, escopo: ESCOPO_DEFAULT, origem: ORIGEM_DEFAULT,
  })]);
  await page.reload();
}

// Devolve os ids que sobreviveram ao filtro do ranking, na ordem do ranking.
async function sobreviventesEws(page, severidade) {
  await carregarComSeveridade(page, severidade);
  await page.evaluate((ranking) => {
    const panel = document.getElementById('ews-ranking-panel');
    window.__ewsCapturado = null;
    window._v201EwsData = { ranking };
    window._v201RenderEWSv3 = function (rows) {
      window.__ewsCapturado = rows.map((r) => `${r.id}:${r.severidade || r.label}`);
    };
    panel.dataset.v201Rendered = '0';
    panel.appendChild(document.createElement('span')); // gatilho do observer
  }, RANKING);

  // Se o filtro derrubar todas as linhas, _v201ApplyEwsV3 retorna antes de
  // renderizar e nao ha efeito observavel para esperar. O timeout curto existe
  // para virar uma falha legivel em vez de travar.
  await page.waitForFunction(() => window.__ewsCapturado !== null, null, { timeout: 5000 })
    .catch(() => {});
  const capturado = await page.evaluate(() => window.__ewsCapturado);
  expect(capturado, 'o ranking EWS nao renderizou: nenhuma linha sobreviveu ao filtro').not.toBeNull();
  return capturado.map((c) => c.split(':')[0]);
}

test.describe('FILTROEVENTOS1 · ranking EWS obedece a severidade canonica', () => {
  test('F) so ALERTA ativa => so a linha ALERTA permanece', async ({ page }) => {
    const ids = await sobreviventesEws(page, sev(['ALERTA']));

    expect(ids).toContain('r-alerta');
    for (const outro of ['r-critico', 'r-atencao', 'r-relevante', 'r-eco']) {
      expect(ids, `${outro} nao podia sobreviver a pill desligada`).not.toContain(outro);
    }
    expect(ids).toEqual(['r-alerta']);
  });

  test('G) so ATENCAO ativa => so a linha ATENCAO permanece', async ({ page }) => {
    const ids = await sobreviventesEws(page, sev(['ATENCAO']));

    expect(ids).toContain('r-atencao');
    for (const outro of ['r-critico', 'r-alerta', 'r-relevante', 'r-eco']) {
      expect(ids, `${outro} nao podia sobreviver a pill desligada`).not.toContain(outro);
    }
    expect(ids).toEqual(['r-atencao']);
  });

  test('H) ALERTA desligada => linha ALERTA sai, demais canonicas intactas', async ({ page }) => {
    const ids = await sobreviventesEws(page, sev(['CRITICO', 'ATENCAO', 'RELEVANTE', 'ECO']));

    expect(ids, 'ALERTA estava desligada').not.toContain('r-alerta');
    expect(ids).toEqual([
      'r-critico', 'r-atencao', 'r-relevante', 'r-eco',
      'r-estavel', 'r-desconhecida', 'r-por-label',
    ]);
  });

  test('I) ESTAVEL segue o estado de ECO', async ({ page }) => {
    const comEco = await sobreviventesEws(page, sev(['ECO']));
    expect(comEco).toContain('r-estavel');
    expect(comEco).toContain('r-eco');

    const semEco = await sobreviventesEws(page, sev(['CRITICO', 'ALERTA', 'ATENCAO', 'RELEVANTE']));
    expect(semEco, 'ESTAVEL nao pode sobreviver com ECO desligada').not.toContain('r-estavel');
    expect(semEco).not.toContain('r-eco');
    expect(semEco).toEqual(['r-critico', 'r-alerta', 'r-atencao', 'r-relevante']);
  });

  test('J) classificacao desconhecida segue ECO', async ({ page }) => {
    const comEco = await sobreviventesEws(page, sev(['ECO']));
    expect(comEco).toContain('r-desconhecida');

    const semEco = await sobreviventesEws(page, sev(['CRITICO', 'ALERTA', 'ATENCAO', 'RELEVANTE']));
    expect(semEco, 'classificacao desconhecida nao pode sobreviver com ECO desligada').not.toContain('r-desconhecida');
  });

  test('K) com as 5 ativas nada e descartado (fast-path so como otimizacao)', async ({ page }) => {
    const ids = await sobreviventesEws(page, sev(CANON));

    expect(ids).toEqual([
      'r-critico', 'r-alerta', 'r-atencao', 'r-relevante', 'r-eco',
      'r-estavel', 'r-desconhecida', 'r-por-label',
    ]);
    expect(ids, 'score>0 e um pre-filtro anterior, nao a severidade').not.toContain('r-score-zero');
  });
});
