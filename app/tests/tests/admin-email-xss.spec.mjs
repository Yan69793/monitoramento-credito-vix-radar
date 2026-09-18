// FE-09 — prova dinamica em navegador real do XSS armazenado no painel admin.
//
// Cenario: um cadastro com e-mail capaz de quebrar o contexto do atributo. No
// codigo pre-correcao esse e-mail entrava cru em cinco handlers inline
// (adminAprovar/adminRejeitar/adminToggleWhiteLabel) e o payload executava ao
// clicar no controle. Depois da correcao o e-mail viaja em data-admin-email,
// dado inerte, e o clique e resolvido por listener delegado.
//
// Nao usa senha de admin: a API e inteiramente stubada por page.route, e a sessao
// administrativa e apenas o estado local do cliente (localStorage), como o app ja
// monta depois do login.
//
// Duas pontas, o mesmo spec contra os dois arquivos:
//   npx playwright test tests/admin-email-xss.spec.mjs --project=desktop
//      -> passa no app corrigido
//   FE09_URL=/tests/.local/prefix/index.html npx playwright test ... (mesmo spec)
//      -> FALHA no blob pre-correcao, provando que o teste detecta o defeito
import { test, expect } from '@playwright/test';

const PAYLOAD_EMAIL = "x'),window.__fe09Pwned=1,('y@z.com";
const EMAIL_BOM = 'cliente@empresa.com.br';
const ALVO = process.env.FE09_URL || '/';

function usuarios() {
  return [
    {
      email: PAYLOAD_EMAIL,
      nome: 'Payload',
      empresa: 'ACME',
      status: 'pendente',
      created_at: '2026-09-18T00:00:00Z',
      white_label: false,
    },
    {
      email: EMAIL_BOM,
      nome: 'Cliente',
      empresa: 'ACME',
      status: 'aprovado',
      created_at: '2026-09-18T00:00:00Z',
      white_label: false,
    },
  ];
}

async function preparar(page, posts) {
  await page.route('https://api.vixradar.com/**', async (route) => {
    let body = {};
    try {
      body = JSON.parse(route.request().postData() || '{}');
    } catch (_) {
      body = {};
    }
    posts.push({
      action: body.action,
      email: body.email === undefined ? null : body.email,
      valor: body.valor === undefined ? null : body.valor,
    });
    if (body.action === 'admin_listar') {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ok: true, usuarios: usuarios() }),
      });
    }
    return route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ ok: true, mensagem: 'ok' }),
    });
  });

  await page.addInitScript(() => {
    localStorage.setItem(
      'radar_user',
      JSON.stringify({ email: 'szuchmacheryan@gmail.com', nome: 'Operador' }),
    );
    localStorage.setItem('radar_jwt', 'token-de-teste-nao-e-credencial-real');
    window.__fe09Pwned = undefined;
  });

  await page.goto(ALVO, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => typeof window.adminCarregarUsuarios === 'function', null, {
    timeout: 20_000,
  });
  await page.evaluate(() => {
    if (typeof window.abrirAdmin === 'function') window.abrirAdmin();
    const painel = document.getElementById('admin-painel');
    if (painel) painel.style.display = 'block';
    const gate = document.getElementById('admin-auth-gate');
    if (gate) gate.style.display = 'none';
  });
  await page.evaluate(() => window.adminCarregarUsuarios());
  await expect(page.locator('#admin-users-list .admin-user-card')).toHaveCount(2, {
    timeout: 15_000,
  });
}

test('FE-09: e-mail malicioso nao cria handler inline e nao executa', async ({ page }) => {
  const posts = [];
  const dialogos = [];
  page.on('dialog', async (d) => {
    dialogos.push(d.message());
    await d.dismiss();
  });
  await preparar(page, posts);

  // 1) nenhum atributo de evento inline sobrou na lista de usuarios
  const handlers = await page.evaluate(() =>
    [...document.querySelectorAll('#admin-users-list *')].flatMap((el) =>
      [...el.attributes].filter((a) => /^on/i.test(a.name)).map((a) => `${el.tagName}.${a.name}`),
    ),
  );
  expect(handlers, `handlers inline encontrados: ${handlers.join(', ')}`).toEqual([]);

  // 2) o payload sobreviveu intacto no atributo de dados, sem quebrar o contexto
  const noAtributo = await page
    .locator('#admin-users-list [data-admin-email]')
    .first()
    .getAttribute('data-admin-email');
  expect(noAtributo).toBe(PAYLOAD_EMAIL);

  // 3) o e-mail do cadastro aparece como texto, escapado
  await expect(page.locator('#admin-users-list .admin-user-email').first()).toContainText('@');

  // 4) clicar no controle aprova o e-mail exato, sem executar o payload
  await page.locator('#admin-users-list [data-admin-action="aprovar"]').first().click();
  await expect
    .poll(() => posts.some((p) => p.action === 'admin_aprovar'), { timeout: 10_000 })
    .toBe(true);
  const aprovacao = posts.find((p) => p.action === 'admin_aprovar');
  expect(aprovacao.email).toBe(PAYLOAD_EMAIL);

  const pwned = await page.evaluate(() => window.__fe09Pwned);
  expect(pwned, 'payload executou no clique').toBeUndefined();
  expect(dialogos, `dialogos disparados: ${dialogos.join(' | ')}`).toEqual([]);
});

test('FE-09 reverso: o clique nunca executa o payload do e-mail', async ({ page }) => {
  // Prova de execucao isolada, sem depender da checagem estrutural acima. Roda o
  // mesmo caminho nas duas pontas: no blob pre-correcao o clique executa o codigo
  // injetado e marca window.__fe09Pwned, aqui isso reprova o teste. No app
  // corrigido o clique apenas aprova o e-mail exato.
  const posts = [];
  const dialogos = [];
  page.on('dialog', async (d) => {
    dialogos.push(d.message());
    await d.dismiss();
  });
  await preparar(page, posts);

  // Clica pelo rotulo visivel, que existe nas duas versoes, para que a prova
  // funcione tanto no app corrigido quanto no blob pre-correcao (que nao tem
  // data-admin-action).
  await page.getByRole('button', { name: 'Aprovar', exact: true }).first().click();
  await page.waitForTimeout(800);

  const pwned = await page.evaluate(() => window.__fe09Pwned);
  expect(pwned, 'payload do e-mail executou no clique do controle').toBeUndefined();
  expect(dialogos, `dialogos disparados: ${dialogos.join(' | ')}`).toEqual([]);

  await expect
    .poll(() => posts.some((p) => p.action === 'admin_aprovar'), { timeout: 10_000 })
    .toBe(true);
  expect(posts.find((p) => p.action === 'admin_aprovar').email).toBe(PAYLOAD_EMAIL);
});

test('FE-09: fluxo legitimo continua aprovando, rejeitando e alternando white-label', async ({
  page,
}) => {

  const posts = [];
  const dialogos = [];
  page.on('dialog', async (d) => {
    dialogos.push(d.message());
    await d.dismiss();
  });
  await preparar(page, posts);

  const cardBom = page.locator('#admin-users-list .admin-user-card').nth(1);
  await expect(cardBom.locator('.admin-user-email')).toHaveText(EMAIL_BOM);

  // aprovado + white-label off -> o botao concede: data-admin-wl = "true"
  const btnWl = cardBom.locator('[data-admin-action="wl"]');
  const wlAntes = await btnWl.getAttribute('data-admin-wl');
  expect(wlAntes).toBe('true');
  await btnWl.click();
  await expect
    .poll(() => posts.some((p) => p.action === 'user_white_label_toggle'), { timeout: 10_000 })
    .toBe(true);
  const wl = posts.find((p) => p.action === 'user_white_label_toggle');
  expect(wl.email).toBe(EMAIL_BOM);
  expect(wl.valor).toBe(true);

  // aprovado -> o botao de status rejeita
  await cardBom.locator('[data-admin-action="rejeitar"]').click();
  await expect
    .poll(() => posts.some((p) => p.action === 'admin_rejeitar'), { timeout: 10_000 })
    .toBe(true);
  expect(posts.find((p) => p.action === 'admin_rejeitar').email).toBe(EMAIL_BOM);

  // nenhum dialogo e nenhum handler inline apos a re-renderizacao
  const handlers = await page.evaluate(() =>
    [...document.querySelectorAll('#admin-users-list *')].flatMap((el) =>
      [...el.attributes].filter((a) => /^on/i.test(a.name)).map((a) => `${el.tagName}.${a.name}`),
    ),
  );
  expect(handlers).toEqual([]);
  expect(dialogos).toEqual([]);
});
