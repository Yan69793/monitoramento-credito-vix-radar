// Monta .vx-mobile-stage/ com o mesmo layout do vx-stage.mjs (layout de deploy).
// VX_BASE_DIR (opcional) aponta para uma copia anterior de index.html e js/vx/css/vx.css,
// usada para rodar a mesma suite contra a versao antiga (prova de duas pontas).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(aqui, '..');
const dst = path.join(aqui, '.vx-mobile-stage');
fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(path.join(dst, 'app'), { recursive: true });
for (const f of ['index.html', '_headers', 'landing-demo.json', 'robots.txt', 'favicon.ico', 'favicon.svg', 'version.json', 'og-vix-radar-20261003.jpg']) {
  const s = path.join(app, f);
  if (fs.existsSync(s)) fs.copyFileSync(s, path.join(dst, f));
}
fs.cpSync(path.join(app, 'js'), path.join(dst, 'app', 'js'), { recursive: true });
if (fs.existsSync(path.join(app, 'admin'))) fs.cpSync(path.join(app, 'admin'), path.join(dst, 'admin'), { recursive: true });
const base = process.env.VX_BASE_DIR;
if (base) {
  const pares = [['index.html', 'index.html'], ['js/vx/css/vx.css', 'app/js/vx/css/vx.css'], ['js/vx/app.js', 'app/js/vx/app.js']];
  for (const [de, para] of pares) {
    const s = path.join(base, de);
    if (fs.existsSync(s)) fs.copyFileSync(s, path.join(dst, para));
  }
  console.log('[vx-mobile-stage] base sobrescrita por', base);
}
console.log('[vx-mobile-stage] pronto em', dst);
