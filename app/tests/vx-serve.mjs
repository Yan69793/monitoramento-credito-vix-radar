// Servidor estatico de laboratorio com compressao brotli/gzip, para medir LCP de forma
// comparavel a producao (o Cloudflare serve o HTML em br: 741 KB -> 178 KB). O
// http-server nao comprime on-the-fly, entao medir nele superestima a transferencia.
// Uso: node vx-serve.mjs <diretorio> <porta>
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const raiz = path.resolve(process.argv[2] || '.vx-stage');
const porta = Number(process.argv[3] || 4191);
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.jpg': 'image/jpeg', '.png': 'image/png', '.txt': 'text/plain; charset=utf-8' };
const COMPRIMIVEL = new Set(['.html', '.js', '.mjs', '.css', '.json', '.svg', '.ico', '.txt']);
const cache = new Map();

http.createServer((req, res) => {
  let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (rel.endsWith('/')) rel += 'index.html';
  const arq = path.join(raiz, rel);
  if (!arq.startsWith(raiz) || !fs.existsSync(arq) || fs.statSync(arq).isDirectory()) { res.writeHead(404); return res.end('nao encontrado'); }
  const ext = path.extname(arq).toLowerCase();
  const cab = { 'Content-Type': TIPOS[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache', Vary: 'Accept-Encoding' };
  let corpo = fs.readFileSync(arq);
  const aceita = String(req.headers['accept-encoding'] || '');
  if (COMPRIMIVEL.has(ext) && corpo.length > 1024) {
    const enc = /\bbr\b/.test(aceita) ? 'br' : /\bgzip\b/.test(aceita) ? 'gzip' : '';
    if (enc) {
      const chave = enc + ':' + arq + ':' + corpo.length;
      if (!cache.has(chave)) cache.set(chave, enc === 'br'
        ? zlib.brotliCompressSync(corpo, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 5 } })
        : zlib.gzipSync(corpo, { level: 6 }));
      corpo = cache.get(chave); cab['Content-Encoding'] = enc;
    }
  }
  cab['Content-Length'] = corpo.length;
  res.writeHead(200, cab); res.end(corpo);
}).listen(porta, '127.0.0.1', () => console.log('[vx-serve]', raiz, 'porta', porta));
