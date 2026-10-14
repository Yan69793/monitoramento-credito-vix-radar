/** Utilitarios puros da v2: escape, severidade (le window.VX_SEV), datas, CSV, URL. */

export function esc(v) {
  return String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/* ---------- severidade: fonte unica e window.VX_SEV (index.html, VXSEV1) ---------- */
export const SEV_ORDEM = () => window.VX_SEV_ORDEM;
export const sevKey = (v) => window.vxSevKey(v);
export const sevCfg = (v) => window.vxSevCfg(v);
export const sevOrd = (v) => window.vxSevOrd(v);
/** Severidade de EVENTO: desconhecido vira ECO, igual a v1 (_v201Sev). */
export function sevEvento(ev) { const k = sevKey(ev && ev.classificacao); return k && k !== 'ESTAVEL' ? k : 'ECO'; }
export function badge(sev, extra = '') {
  const k = sevKey(sev) || '';
  const c = sevCfg(sev);
  const label = k ? c.label : esc(String(sev || '—'));
  return `<span class="vx-badge" data-sev="${k}"${extra}><span aria-hidden="true">${c.icone}</span> ${label}</span>`;
}

/* ---------- datas (sempre calendario local, como a v1) ---------- */
export function parseISO(d) {
  if (!d || typeof d !== 'string') return null;
  const m = d.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return m ? new Date(+m[1], +m[2] - 1, +m[3], 12, 0, 0) : null;
}
export function isoLocal(d) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
export function hoje0() { const h = new Date(); h.setHours(0, 0, 0, 0); return h; }
const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const MESES_L = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const DIAS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
export function fmtCurto(d) { return d ? `${String(d.getDate()).padStart(2, '0')}/${MESES[d.getMonth()]}` : ''; }
export function fmtLongo(d) { return d ? `${String(d.getDate()).padStart(2, '0')} de ${MESES_L[d.getMonth()]} de ${d.getFullYear()} · ${DIAS[d.getDay()]}` : ''; }
export function fmtMes(d) { return d ? `${MESES_L[d.getMonth()]} de ${d.getFullYear()}` : ''; }
export function fmtDataHora(iso) {
  if (!iso) return 'não informado';
  const d = new Date(iso);
  if (isNaN(d)) return 'não informado';
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' }) + ' BRT';
}
/** Ultimos n dias uteis (seg-sex), do mais antigo ao mais novo. Mesma regra da v1 (_v201JanUteis). */
export function diasUteis(n, ate = hoje0()) {
  const out = []; const d = new Date(ate); let guarda = 0;
  while (out.length < n && guarda++ < 400) { const w = d.getDay(); if (w !== 0 && w !== 6) out.push(new Date(d)); d.setDate(d.getDate() - 1); }
  return out.reverse();
}

/* ---------- numeros: indisponivel nunca vira zero ---------- */
export function num(v, casas = 0) {
  if (v === null || v === undefined || v === '' || !isFinite(Number(v))) return '—';
  return Number(v).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
}

/* ---------- CSV (separador ; e BOM, abre direto no Excel pt-BR) ---------- */
export function csv(linhas, colunas) {
  const q = (v) => { const s = String(v == null ? '' : v); return /[";\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const corpo = [colunas.map((c) => q(c.titulo)).join(';')].concat(linhas.map((l) => colunas.map((c) => q(c.valor(l))).join(';')));
  return '﻿' + corpo.join('\r\n');
}
export function baixar(nome, conteudo, tipo = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob([conteudo], { type: tipo }));
  const a = document.createElement('a'); a.href = url; a.download = nome; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

/* ---------- rota por hash: #/tela/arg1/arg2?chave=valor ---------- */
export function lerRota(hash = location.hash) {
  const h = String(hash || '').replace(/^#\/?/, '');
  const [caminho, qs] = h.split('?');
  const partes = caminho.split('/').filter(Boolean).map((p) => decodeURIComponent(p));
  return { tela: partes[0] || '', args: partes.slice(1), q: new URLSearchParams(qs || '') };
}
export function montarRota(tela, args = [], q = null) {
  const caminho = [tela].concat(args.map((a) => encodeURIComponent(a))).join('/');
  const s = q ? q.toString() : '';
  return '#/' + caminho + (s ? '?' + s : '');
}
