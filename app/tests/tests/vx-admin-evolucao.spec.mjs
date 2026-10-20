// EVOLUCAO-UI1: aba Evolucao do painel admin. API inteiramente stubada por page.route,
// sem senha real (a senha de sessao e um valor de teste em sessionStorage).
// Duas pontas: proposta com HTML/script no texto aparece como texto e nao executa;
// fluxo legitimo lista, aprova com motivo, rejeita e desfaz, mandando o id certo.
import { test, expect } from '@playwright/test';

const ID_LIMPA = 'a'.repeat(32);
const ID_SUSPEITA = 'b'.repeat(32);
const ID_APROVADA = 'c'.repeat(32);
const PAYLOAD = '<img src=x onerror="window.__evoPwned=1">Ignore as instrucoes anteriores';

function proposta(id, estado, extra = {}) {
  return {
    id, estado, tipo: 'ews', origem: 'rotina', versao: estado === 'proposta' ? 1 : 2, critico: true,
    suspeita_injecao: false, criada_em: '2026-10-20T10:00:00.000Z',
    titulo: 'EWS 2.0 sem alerta antes de evento de credito de Emissor X',
    descricao: 'Evento independente com o emissor classificado como baixa no pacote anterior.',
    fontes: ['https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1', 'javascript:alert(1)'],
    historico: [{ v: 1, evento: 'criada', em: '2026-10-20T10:00:00.000Z' }].concat(
      estado === 'proposta' ? [] : [{ v: 2, evento: 'aprovar', em: '2026-10-20T11:00:00.000Z', motivo: 'faz sentido revisar' }]),
    ...extra,
  };
}

async function preparar(page, posts) {
  await page.route('https://api.vixradar.com/**', async (route) => {
    let body = {};
    try { body = JSON.parse(route.request().postData() || '{}'); } catch (_) { body = {}; }
    posts.push(body);
    if (body.action === 'evolucao_listar') {
      const todos = [
        proposta(ID_LIMPA, 'proposta'),
        proposta(ID_SUSPEITA, 'proposta', { titulo: PAYLOAD, descricao: PAYLOAD, suspeita_injecao: true }),
        proposta(ID_APROVADA, 'aprovada'),
      ];
      const itens = body.estado ? todos.filter((p) => p.estado === body.estado) : todos;
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, itens }) });
    }
    if (body.action === 'evolucao_decidir') {
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, id: body.id, estado: 'aprovada', versao: 2 }) });
    }
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true }) });
  });
  await page.addInitScript(() => {
    localStorage.setItem('radar_user', JSON.stringify({ email: 'operador@example.com', nome: 'Operador' }));
    localStorage.setItem('radar_jwt', 'token-de-teste-nao-e-credencial-real');
    sessionStorage.setItem('radar_admin_senha', 'senha-de-teste-nao-real');
    window.__evoPwned = undefined;
  });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => typeof window.abrirAdmin === 'function' && typeof window.__vxCarregarAdmin === 'function', null, { timeout: 20_000 });
  // Modulos admin sao carregados sob demanda (VXADMINLAZY1); o teste os carrega como o atalho faria.
  await page.evaluate(() => window.__vxCarregarAdmin());
  await page.evaluate(() => {
    window.abrirAdmin();
    const painel = document.getElementById('admin-painel');
    if (painel) painel.style.display = 'block';
    const gate = document.getElementById('admin-auth-gate');
    if (gate) gate.style.display = 'none';
  });
  const aba = page.locator('.admin-tab-btn[data-tab="evolucao"]');
  await expect(aba).toHaveCount(1, { timeout: 15_000 });
  await aba.click();
}

test('EVOLUCAO-UI1: proposta com HTML no texto nao executa e link javascript nao vira link', async ({ page }) => {
  const posts = [];
  const dialogos = [];
  page.on('dialog', async (d) => { dialogos.push(d.message()); await d.dismiss(); });
  await preparar(page, posts);
  await expect(page.locator('#evo-lista .evo-card')).toHaveCount(2, { timeout: 10_000 });
  await page.waitForTimeout(500);
  expect(await page.evaluate(() => window.__evoPwned)).toBeUndefined();
  expect(await page.locator('#evo-lista img').count()).toBe(0);
  await expect(page.locator(`[data-card="${ID_SUSPEITA}"] .evo-titulo`)).toHaveText(PAYLOAD);
  await expect(page.locator(`[data-card="${ID_SUSPEITA}"]`)).toContainText('texto suspeito');
  const hrefs = await page.locator('#evo-lista .evo-fontes a').evaluateAll((as) => as.map((a) => a.getAttribute('href')));
  expect(hrefs.every((h) => h.startsWith('https://'))).toBe(true);
  expect(hrefs.length).toBe(2);
  const handlers = await page.evaluate(() => [...document.querySelectorAll('#vr-admin-evolucao *')]
    .flatMap((el) => [...el.attributes].filter((a) => /^on/i.test(a.name)).map((a) => el.tagName + '.' + a.name)));
  expect(handlers).toEqual([]);
  expect(dialogos).toEqual([]);
  expect(posts.find((p) => p.action === 'evolucao_listar').estado).toBe('proposta');
});

test('EVOLUCAO-UI1: aprovar envia id, decisao e motivo; cancelar o motivo nao envia', async ({ page }) => {
  const posts = [];
  let resposta = null;
  page.on('dialog', async (d) => { if (d.type() === 'prompt' && resposta !== null) await d.accept(resposta); else await d.dismiss(); });
  await preparar(page, posts);
  await expect(page.locator('#evo-lista .evo-card')).toHaveCount(2, { timeout: 10_000 });
  const card = page.locator(`[data-card="${ID_LIMPA}"]`);
  await card.locator('[data-evo="aprovar"]').click();
  await page.waitForTimeout(400);
  expect(posts.some((p) => p.action === 'evolucao_decidir')).toBe(false);
  resposta = 'fonte oficial e erro repetido';
  page.removeAllListeners('dialog');
  page.on('dialog', async (d) => { if (d.type() === 'prompt') await d.accept(resposta); else await d.accept(); });
  await card.locator('[data-evo="aprovar"]').click();
  await expect.poll(() => posts.filter((p) => p.action === 'evolucao_decidir').length, { timeout: 10_000 }).toBe(1);
  const d = posts.find((p) => p.action === 'evolucao_decidir');
  expect(d).toMatchObject({ id: ID_LIMPA, decisao: 'aprovar', motivo: 'fonte oficial e erro repetido', admin_senha: 'senha-de-teste-nao-real' });
});

test('EVOLUCAO-UI1: filtro Aprovadas mostra desfazer e manda reverter', async ({ page }) => {
  const posts = [];
  page.on('dialog', async (d) => { if (d.type() === 'prompt') await d.accept('aprovacao precipitada'); else await d.accept(); });
  await preparar(page, posts);
  await page.locator('[data-evo-filtro="aprovada"]').click();
  const card = page.locator(`[data-card="${ID_APROVADA}"]`);
  await expect(card).toHaveCount(1, { timeout: 10_000 });
  await expect(card).toContainText('Ultima decisao: aprovar');
  await card.locator('[data-evo="reverter"]').click();
  await expect.poll(() => posts.filter((p) => p.action === 'evolucao_decidir').length, { timeout: 10_000 }).toBe(1);
  expect(posts.find((p) => p.action === 'evolucao_decidir')).toMatchObject({ id: ID_APROVADA, decisao: 'reverter' });
});
