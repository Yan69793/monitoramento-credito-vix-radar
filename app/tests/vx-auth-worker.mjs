// Sobe o Worker REAL (api/src/worker.js, o mesmo codigo de producao) em workerd local, com a
// config de teste do repo (api/wrangler.test.jsonc: KV, Durable Objects e segredos de TESTE,
// sem conta, sem rota, sem nada de producao). Serve ao teste autenticado ponta a ponta
// (vx-auth-e2e.spec.mjs), que NAO toca producao nem preview.
//
// Por que um arquivo de entrada proprio: worker.js tem exports nomeados de funcao/constante
// para a suite vitest (CONCLUSAO_PREFIXO etc.). O workerd recusa isso no `wrangler dev`
// ("provided value is not of type 'function or ExportedHandler'"). A entrada abaixo reexporta
// so o handler e os Durable Objects. worker.js nao e alterado.
//
// Uso: node vx-auth-worker.mjs [porta]   (a porta padrao e 8788)
import { spawn, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const api = process.env.VX_API_DIR ? path.resolve(process.env.VX_API_DIR) : path.resolve(aqui, '..', '..', 'api');
const porta = String(process.argv[2] || process.env.VX_AUTH_WORKER_PORT || 8788);
const wrangler = path.join(api, 'node_modules', 'wrangler', 'bin', 'wrangler.js');
const cfgOrigem = path.join(api, 'wrangler.test.jsonc');
if (!fs.existsSync(wrangler)) {
  console.error(`[vx-auth-worker] wrangler ausente em ${wrangler}. Rode "npm ci" em api/ (ou aponte VX_API_DIR).`);
  process.exit(2);
}
try { fs.unlinkSync(path.join(os.tmpdir(), 'vx-auth-seed.json')); } catch (_) { /* nao existia */ }
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vx-auth-'));
const worker = path.join(api, 'src', 'worker.js').replace(/\\/g, '/');
fs.writeFileSync(path.join(tmp, 'entry.mjs'), `export { default, EmissorDO, UsuarioDO, ConfigDO, EstadoSemanaDO, RateLimiterDO } from ${JSON.stringify(worker)};\n`);
const cfg = fs.readFileSync(cfgOrigem, 'utf8');
if (!cfg.includes('"main": "src/worker.js"')) { console.error('[vx-auth-worker] wrangler.test.jsonc mudou de forma: "main" nao encontrado.'); process.exit(2); }
fs.writeFileSync(path.join(tmp, 'wrangler.auth.jsonc'), cfg.replace('"main": "src/worker.js"', '"main": "entry.mjs"'));

// Contas de TESTE, geradas a cada execucao (senha aleatoria, e-mail @example.com) e gravadas so no KV
// local deste Worker e num arquivo temporario lido pelo spec. Nada disto existe em producao.
function hashSenha(s) {
  const salt = crypto.randomBytes(16); // mesmo formato do Worker: b64(salt):b64(PBKDF2-SHA256 100k, 32 B)
  return salt.toString('base64') + ':' + crypto.pbkdf2Sync(s, salt, 100000, 32, 'sha256').toString('base64');
}
const sufixo = crypto.randomBytes(3).toString('hex');
const contas = {};
const kv = [];
for (const [rotulo, status] of [['a', 'aprovado'], ['b', 'aprovado'], ['pendente', 'pendente']]) {
  const email = 'vxauth-' + rotulo + '-' + sufixo + '@example.com';
  const senha = crypto.randomBytes(15).toString('base64url');
  contas[rotulo] = { email, senha, status };
  kv.push({ key: 'user:' + email, value: JSON.stringify({ email, nome: 'Teste ' + rotulo.toUpperCase(), empresa: 'Teste SA', status, senha_hash: hashSenha(senha), tenant: 'default', ui_track: 'current', white_label: false, created_at: new Date().toISOString() }) });
}
const jsonKv = path.join(tmp, 'seed-kv.json');
fs.writeFileSync(jsonKv, JSON.stringify(kv));
const persist = path.join(tmp, 'persist');
const sem = spawnSync(process.execPath, [wrangler, 'kv', 'bulk', 'put', jsonKv, '--binding', 'RADAR_KV', '--local', '--persist-to', persist, '-c', path.join(tmp, 'wrangler.auth.jsonc')], { cwd: api, encoding: 'utf8' });
if (sem.status !== 0) { console.error('[vx-auth-worker] falha ao semear o KV local:', (sem.stderr || sem.stdout || '').slice(0, 600)); process.exit(3); }
fs.writeFileSync(path.join(os.tmpdir(), 'vx-auth-seed.json'), JSON.stringify(contas));
console.log('[vx-auth-worker] contas de teste semeadas no KV local (' + Object.keys(contas).join(', ') + ')');

const filho = spawn(process.execPath, [wrangler, 'dev', '-c', path.join(tmp, 'wrangler.auth.jsonc'), '--local', '--port', porta, '--ip', '127.0.0.1', '--persist-to', persist], { cwd: api, stdio: 'inherit' });
function matar() {
  try {
    if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(filho.pid), '/T', '/F'], { stdio: 'ignore' });
    else filho.kill('SIGKILL');
  } catch (_) { /* ja encerrou */ }
}
for (const s of ['SIGINT', 'SIGTERM', 'exit']) process.on(s, matar);
filho.on('exit', (c) => process.exit(c ?? 0));
