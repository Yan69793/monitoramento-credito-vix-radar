// Monta em .vx-stage/ o MESMO layout que scripts/deploy-pages.ps1 publica:
// index.html e arquivos de raiz na raiz, app/js -> app/js, app/admin -> admin.
// Assim o teste local resolve "app/js/..." como em producao, sem tocar no deploy_zip.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(aqui, '..');
const dst = path.join(aqui, '.vx-stage');
fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(path.join(dst, 'app'), { recursive: true });
for (const f of ['index.html', '_headers', 'landing-demo.json', 'robots.txt', 'favicon.ico', 'favicon.svg', 'version.json', 'og-vix-radar-20261003.jpg']) {
  const s = path.join(app, f);
  if (fs.existsSync(s)) fs.copyFileSync(s, path.join(dst, f));
}
fs.cpSync(path.join(app, 'js'), path.join(dst, 'app', 'js'), { recursive: true });
if (fs.existsSync(path.join(app, 'admin'))) fs.cpSync(path.join(app, 'admin'), path.join(dst, 'admin'), { recursive: true });
console.log('[vx-stage] pronto em', dst);
