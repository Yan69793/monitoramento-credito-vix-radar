// Autenticacao, sessao, expiracao, isolamento e acesso nao autorizado, PONTA A PONTA e 100% local.
//
// O que roda de verdade: o frontend publicado (.vx-stage, mesmo layout do deploy) e o Worker REAL
// (api/src/worker.js em workerd local, via vx-auth-worker.mjs) com a config de teste do repo. O
// navegador acredita estar em https://vixradar.com falando com https://api.vixradar.com: as duas
// origens sao roteadas para localhost, entao o CORS do Worker (ALLOWED_ORIGINS) e exercido como em
// producao e nenhum byte sai da maquina. Qualquer outro host e abortado.
//
// Contas: geradas pelo vx-auth-worker.mjs a cada execucao (e-mail @example.com, senha aleatoria),
// gravadas so no KV local e em um arquivo temporario. Este spec nunca imprime credencial.
//
// O que isto NAO e: nao prova nada contra producao nem contra o preview. O preview (origem
// *.pages.dev) nao esta em ALLOWED_ORIGINS do Worker de producao, entao ele nem consegue autenticar
// la; e login em producao exige conta real, que esta fora do alcance deste teste por desenho.
import { test, expect } from '@playwright/test';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ESTATICO = 'http://127.0.0.1:4191';
const WORKER = 'http://127.0.0.1:8788';
const ORIGEM = 'https://vixradar.com';
// O webServer (vx-auth-worker.mjs) so sobe DEPOIS de os arquivos de teste serem carregados: ler as contas aqui, nao no import.
let contas;
test.beforeAll(() => { contas = JSON.parse(fs.readFileSync(path.join(os.tmpdir(), 'vx-auth-seed.json'), 'utf8')); });
const cfgTeste = fs.readFileSync(path.resolve(import.meta.dirname, '..', '..', '..', 'api', 'wrangler.test.jsonc'), 'utf8');
const JWT_SECRET = /"JWT_SECRET":\s*"([^"]+)"/.exec(cfgTeste)[1];

let seqIp = 20;
const proximoIp = () => '198.51.100.' + (seqIp++ % 250); // TEST-NET-2: o rate limit anonimo e por IP

async function instalarRotas(context, hospedeiros) {
  await context.route('**/*', (r) => { hospedeiros.add(new URL(r.request().url()).host); return r.abort(); }); // tudo que nao e nosso
  await context.route(/^https:\/\/vixradar\.com\//, async (route) => {
    const u = new URL(route.request().url());
    const r = await fetch(ESTATICO + u.pathname + u.search);
    const h = { 'content-type': r.headers.get('content-type') || 'text/html', 'cache-control': 'no-cache' };
    await route.fulfill({ status: r.status, headers: h, body: Buffer.from(await r.arrayBuffer()) });
  });
  await context.route(/^https:\/\/api\.vixradar\.com\//, async (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const headers = { ...req.headers(), origin: ORIGEM, 'cf-connecting-ip': proximoIp(), 'accept-encoding': 'identity' };
    for (const k of ['host', 'connection', 'content-length']) delete headers[k];
    const r = await fetch(WORKER + u.pathname + u.search, { method: req.method(), headers, body: ['GET', 'HEAD'].includes(req.method()) ? undefined : req.postDataBuffer() });
    const h = {};
    r.headers.forEach((v, k) => { if (!['content-encoding', 'content-length', 'transfer-encoding', 'connection'].includes(k)) h[k] = v; });
    await route.fulfill({ status: r.status, headers: h, body: Buffer.from(await r.arrayBuffer()) });
  });
}

async function novoContexto(browser, info) {
  const context = await browser.newContext({ viewport: info.project.use.viewport, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  const hospedeiros = new Set();
  await instalarRotas(context, hospedeiros);
  const page = await context.newPage();
  const dialogos = [];
  page.on('dialog', (d) => { dialogos.push(d.message()); d.accept(); });
  return { context, page, hospedeiros, dialogos };
}

async function loginPelaTela(page, conta, { senha = conta.senha } = {}) {
  await page.goto(ORIGEM + '/');
  await expect(page.locator('#publicHome')).toBeVisible();
  await page.locator('.ph-nav__cta').click(); // "Acessar": mesmo caminho do usuario
  await page.locator('#agEmail').fill(conta.email);
  await page.locator('#agPass').fill(senha);
  await page.locator('#agBtnLogin').click();
}
const armazenado = (page) => page.evaluate(() => ({ jwt: localStorage.getItem('radar_jwt'), user: localStorage.getItem('radar_user') }));

async function chamar(body, token) {
  const r = await fetch(WORKER + '/', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: ORIGEM, 'CF-Connecting-IP': proximoIp(), ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify(body) });
  let j = null; try { j = await r.json(); } catch (_) { /* corpo vazio */ }
  return { status: r.status, j };
}
async function ler(qs, token) {
  const r = await fetch(WORKER + '/' + qs, { headers: { Origin: ORIGEM, 'CF-Connecting-IP': proximoIp(), ...(token ? { Authorization: 'Bearer ' + token } : {}) } });
  return r.status;
}
async function tokenDe(conta) {
  const r = await chamar({ action: 'login', email: conta.email, senha: conta.senha });
  expect(r.status).toBe(200);
  return r.j.token;
}
function b64u(buf) { return Buffer.from(buf).toString('base64url'); }
function reassinar(token, patch) { // mesma tecnica de api/test/sessao-unica.test.mjs: HS256 com o JWT_SECRET de TESTE
  const [h, p] = token.split('.');
  const payload = { ...JSON.parse(Buffer.from(p, 'base64url').toString('utf8')), ...patch };
  const corpo = b64u(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', JWT_SECRET).update(`${h}.${corpo}`).digest('base64url');
  return `${h}.${corpo}.${sig}`;
}

test.describe('API sem credencial ou com credencial errada', () => {
  test('anonimo e recusado em leitura e em escrita; acao admin e de rotina negadas', async () => {
    expect(await ler('?op=state')).toBe(401);
    expect(await ler('?op=ews')).toBe(401);
    expect((await chamar({ action: 'favorito_listar' })).status).toBe(401);
    expect((await chamar({ action: 'favorito_toggle', empresa: 'Braskem' })).status).toBe(401);
    expect((await chamar({ action: 'minha_analise_salvar', empresa: 'Braskem' })).status).toBe(401);
    expect((await chamar({ action: 'admin_listar' })).status).toBe(403);
    expect((await chamar({ action: 'admin_aprovar', email: contas.pendente.email })).status).toBe(403);
    expect((await chamar({ action: 'receber_analise', empresa: 'X' })).status).toBe(403);
    // e a conta pendente continua pendente: nenhuma das chamadas acima a aprovou
    expect((await chamar({ action: 'login', email: contas.pendente.email, senha: contas.pendente.senha })).status).toBe(401);
  });

  test('token comum nao vira admin; token adulterado e token sem assinatura valida sao recusados', async () => {
    const t = await tokenDe(contas.a);
    expect((await chamar({ action: 'admin_listar' }, t)).status).toBe(403);
    expect((await chamar({ action: 'admin_listar', admin_senha: 'senha-errada' }, t)).status).toBe(403);
    expect((await chamar({ action: 'refresh_cookie' }, t)).status).toBe(200); // o token em si e bom
    const adulterado = t.slice(0, -3) + (t.endsWith('AAA') ? 'BBB' : 'AAA');
    expect((await chamar({ action: 'refresh_cookie' }, adulterado)).status).toBe(401);
    const promovido = reassinar(t, { role: 'admin' }).split('.').slice(0, 2).join('.') + '.' + 'x'.repeat(43); // payload de admin, assinatura falsa
    expect((await chamar({ action: 'admin_listar' }, promovido)).status).toBeGreaterThanOrEqual(401);
    expect((await chamar({ action: 'refresh_cookie' }, promovido)).status).toBe(401);
  });
});

test.describe('login, persistencia e expiracao pela tela', () => {
  test('senha errada e conta pendente: mesma mensagem generica, nada gravado no navegador', async ({ browser }, info) => {
    const { context, page } = await novoContexto(browser, info);
    await loginPelaTela(page, contas.a, { senha: 'errada-' + contas.a.senha });
    await expect(page.locator('#agLoginErr')).toContainText('Credenciais inválidas');
    expect(await armazenado(page)).toEqual({ jwt: null, user: null });
    await page.reload();
    await loginPelaTela(page, contas.pendente);
    await expect(page.locator('#agLoginErr')).toContainText('Credenciais inválidas'); // anti-enumeracao: pendente nao se distingue de errada
    expect(await armazenado(page)).toEqual({ jwt: null, user: null });
    await context.close();
  });

  test('login correto: sessao gravada, sobrevive a recarga, e toda chamada de dados leva o token', async ({ browser }, info) => {
    const { context, page, hospedeiros } = await novoContexto(browser, info);
    const ops = [];
    page.on('request', (r) => { const m = /^https:\/\/api\.vixradar\.com\/\?op=([a-z_]+)/.exec(r.url()); if (m) ops.push({ op: m[1], auth: !!r.headers()['authorization'] }); });
    await loginPelaTela(page, contas.a);
    await page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await page.waitForLoadState('load');
    await expect(page.locator('#main')).toBeVisible();
    const s1 = await armazenado(page);
    expect(JSON.parse(s1.user).email).toBe(contas.a.email);
    expect(s1.jwt.split('.')).toHaveLength(3);
    expect(await page.locator('body').innerText()).not.toContain(s1.jwt); // token nunca aparece na tela
    await page.reload();
    await expect(page.locator('#main')).toBeVisible();
    expect(JSON.parse((await armazenado(page)).user).email).toBe(contas.a.email);
    // leituras que exigem sessao (op=state, op=ews) sempre saem com o token; op=calendario e publica por desenho
    const exigem = ops.filter((o) => ['state', 'ews'].includes(o.op));
    expect(exigem.length, JSON.stringify(ops)).toBeGreaterThan(0);
    expect(exigem.filter((o) => !o.auth), JSON.stringify(ops)).toEqual([]);
    // contencao: so os dois hospedeiros virtuais foram usados com sucesso; o resto foi abortado (beacon de terceiros)
    expect([...hospedeiros].every((h) => !/vixradar\.com$/.test(h))).toBe(true);
    await context.close();
  });

  test('expiracao: token vencido (assinatura valida, exp no passado) derruba a sessao com aviso e limpa o navegador', async ({ browser }, info) => {
    const { context, page } = await novoContexto(browser, info);
    await loginPelaTela(page, contas.a);
    await page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await page.waitForLoadState('load');
    const { jwt } = await armazenado(page);
    const vencido = reassinar(jwt, { exp: Math.floor(Date.now() / 1000) - 3600 });
    expect((await chamar({ action: 'refresh_cookie' }, vencido)).status).toBe(401); // servidor recusa
    await page.evaluate((v) => localStorage.setItem('radar_jwt', v), vencido);
    await page.reload();
    await expect(page.locator('#agLoginErr')).toContainText('Sua sessão expirou');
    await expect(page.locator('#publicHome')).toBeVisible();
    expect(await armazenado(page)).toEqual({ jwt: null, user: null });
    await context.close();
  });
});

test.describe('sessao unica e isolamento entre usuarios', () => {
  test('segundo login da mesma conta encerra a primeira sessao; a outra conta nao e afetada', async ({ browser }, info) => {
    const c1 = await novoContexto(browser, info);
    await loginPelaTela(c1.page, contas.a);
    await c1.page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await c1.page.waitForLoadState('load');
    const t1 = (await armazenado(c1.page)).jwt;

    const cb = await novoContexto(browser, info);
    await loginPelaTela(cb.page, contas.b);
    await cb.page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    const tb = (await armazenado(cb.page)).jwt;

    const c2 = await novoContexto(browser, info);
    await loginPelaTela(c2.page, contas.a); // mesma conta, outro navegador
    await c2.page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await expect.poll(() => c2.dialogos.join('|')).toContain('sessão anterior desta conta foi encerrada');
    const t2 = (await armazenado(c2.page)).jwt;
    expect(t2).not.toBe(t1);

    expect((await chamar({ action: 'refresh_cookie' }, t1)).status).toBe(401);
    expect((await chamar({ action: 'refresh_cookie' }, t2)).status).toBe(200);
    expect((await chamar({ action: 'refresh_cookie' }, tb)).status).toBe(200); // B intacta

    // a primeira aba descobre na proxima chamada autenticada (o produto trata o 401 em _fetchAut) e cai para o login com o aviso
    await c1.page.evaluate(() => _fetchAut('https://api.vixradar.com/?op=state', { headers: _authHeadersGet() })); // eslint-disable-line no-undef
    await expect(c1.page.locator('#agLoginErr')).toContainText('Sua sessão expirou');
    await expect(c1.page.locator('#publicHome')).toBeVisible();
    expect(await armazenado(c1.page)).toEqual({ jwt: null, user: null });
    for (const c of [c1, cb, c2]) await c.context.close();
  });

  test('dados privados nao cruzam entre contas, nem por parametro forjado', async ({ browser }, info) => {
    const ta = await tokenDe(contas.a);
    const tb = await tokenDe(contas.b);
    const marca = 'Empresa-' + crypto.randomBytes(3).toString('hex');
    const t = await chamar({ action: 'favorito_toggle', empresa: marca }, ta);
    expect(t.status).toBe(200);
    expect(t.j.marcado).toBe(true);
    const deA = await chamar({ action: 'favorito_listar' }, ta);
    expect(deA.j.favoritos.map((f) => f.empresa)).toContain(marca);
    const deB = await chamar({ action: 'favorito_listar' }, tb);
    expect(deB.j.favoritos.map((f) => f.empresa)).not.toContain(marca);
    // B tenta ler A por e-mail forjado no corpo e por cabecalho: o servidor usa a identidade do token
    const forjado = await chamar({ action: 'favorito_listar', email: contas.a.email, usuario: contas.a.email }, tb);
    expect(forjado.j.favoritos.map((f) => f.empresa)).not.toContain(marca);
    // B remove "a mesma empresa" na propria lista: a marca de A continua la
    await chamar({ action: 'favorito_toggle', empresa: marca }, tb);
    const depois = await chamar({ action: 'favorito_listar' }, ta);
    expect(depois.j.favoritos.map((f) => f.empresa)).toContain(marca);
    // limpeza no KV local (o Worker e descartavel, mas o teste fica idempotente)
    await chamar({ action: 'favorito_toggle', empresa: marca }, ta);
    const info2 = await novoContexto(browser, info);
    await loginPelaTela(info2.page, contas.b);
    await info2.page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    expect(JSON.parse((await armazenado(info2.page)).user).email).toBe(contas.b.email); // a tela de B mostra B
    await info2.context.close();
  });
});

test.describe('v2 atras de flag com sessao real', () => {
  test('?ui=v2 logado monta a v2; sessao invalidada em outro navegador vira aviso, nao tela quebrada', async ({ browser }, info) => {
    const c1 = await novoContexto(browser, info);
    const erros = [];
    c1.page.on('pageerror', (e) => erros.push(e.message));
    await loginPelaTela(c1.page, contas.a);
    await c1.page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await c1.page.waitForLoadState('load');
    await c1.page.goto(ORIGEM + '/?ui=v2#/eventos');
    await expect(c1.page.locator('#vx2-root.vx-on')).toBeVisible();
    // outra pessoa entra com a mesma conta: a sessao desta aba morre no servidor
    await tokenDe(contas.a);
    await c1.page.reload();
    await expect(c1.page.locator('#agLoginErr')).toContainText('Sua sessão expirou');
    expect(erros).toEqual([]);
    expect(await armazenado(c1.page)).toEqual({ jwt: null, user: null });
    await c1.context.close();
  });
});

test.describe('logout (menu Mais > Sair)', () => {
  test('Sair limpa o navegador e volta a landing; o token antigo SEGUE valido no servidor (pendencia de seguranca, comportamento atual)', async ({ browser }, info) => {
    const { context, page } = await novoContexto(browser, info);
    await loginPelaTela(page, contas.a);
    await page.waitForFunction(() => !!localStorage.getItem('radar_jwt'));
    await page.waitForLoadState('load');
    const antigo = (await armazenado(page)).jwt;
    await page.locator('#btn-mais').click();
    await page.locator('#btn-sair').click();
    await expect(page.locator('#publicHome')).toBeVisible();
    expect(await armazenado(page)).toEqual({ jwt: null, user: null });
    // PENDENCIA, nao regressao desta entrega: o Sair e so do cliente (onclick inline no index.html, sem chamada ao Worker).
    // Quem tiver copiado o token antes continua autenticado ate expirar ou ate um novo login da conta (sessao unica).
    // Quando o Worker ganhar um logout que invalide o sid, trocar 200 por 401 aqui.
    expect((await chamar({ action: 'refresh_cookie' }, antigo)).status).toBe(200);
    await context.close();
  });
});
