/**
 * VIX Radar — Admin Modules (HEART + endpoints)
 * v202.1 — ES module refactor (was vr-admin-modules.js IIFE)
 *
 * Imports from shared.js, exports: loadHoje, calcHeart, sendReengage,
 *   getHeartHistory, renderHeartKpis, renderUserHealth, renderHeartbeats,
 *   initTabHoje, injectHojeTab
 */

import { API_BASE, esc, getSenha, authHeaders, postAdmin } from './shared.js';

/* ── Helpers ──────────────────────────────────────────────── */
async function fetchHealth() {
  const r = await fetch(API_BASE, { cache: 'no-store' });
  return r.json();
}

async function fetchHeartbeats() {
  const r = await fetch(API_BASE + '?action=heartbeats', {
    headers: authHeaders(),
    cache: 'no-store',
  });
  if (r.status === 401 && typeof _tratarSessaoExpirada === 'function') {
    _tratarSessaoExpirada(r);
    return null;
  }
  return r.json();
}

function daysSince(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  return Math.floor((Date.now() - d.getTime()) / 86400000);
}

/* ── HEART metrics ────────────────────────────────────────── */
export function calcHeart(users, retencao, overview) {
  const aprovados = users.filter((u) => u.status === 'aprovado');
  const retMap = {};
  (retencao || []).forEach((r) => { retMap[r.email] = r; });

  let active7 = 0, active30 = 0;
  aprovados.forEach((u) => {
    const r = retMap[u.email];
    if (!r) return;
    if ((r.eventos_7d || 0) > 0) active7++;
    if ((r.eventos_30d || 0) > 0) active30++;
  });

  const ev = {};
  (overview || []).forEach((o) => { ev[o.evento] = o.total || 0; });
  const logins = ev.login || 0;
  const consultas = ev.consulta_empresa || 0;
  const aberturas = ev.abertura_analise || 0;

  const adoption = aprovados.length
    ? Math.round((aprovados.length / Math.max(users.length, 1)) * 100) : 0;
  const retention = aprovados.length
    ? Math.round((active30 / aprovados.length) * 100) : 0;
  const engagement = Math.min(100, Math.round((logins + consultas) / 2));
  const taskSuccess = aberturas > 0
    ? Math.min(100, Math.round((consultas / aberturas) * 100))
    : consultas > 0 ? 75 : 0;
  const happiness = aprovados.length
    ? Math.min(100, Math.round((active7 / aprovados.length) * 100) + (retention > 50 ? 10 : 0))
    : 0;

  return {
    happiness, engagement, adoption, retention, taskSuccess,
    meta: {
      aprovados: aprovados.length, active7, active30,
      logins, consultas,
    },
  };
}

/* ── HEART history ────────────────────────────────────────── */
const HEART_HIST_KEY = 'vr_heart_history_v1';

export function saveHeartHistory(heart) {
  try {
    let hist = JSON.parse(localStorage.getItem(HEART_HIST_KEY) || '[]');
    hist.push({
      ts: Date.now(),
      h: heart.happiness, e: heart.engagement,
      a: heart.adoption, r: heart.retention, t: heart.taskSuccess,
    });
    if (hist.length > 14) hist = hist.slice(-14);
    localStorage.setItem(HEART_HIST_KEY, JSON.stringify(hist));
    return hist;
  } catch (_) { return []; }
}

export function getHeartHistory() {
  try { return JSON.parse(localStorage.getItem(HEART_HIST_KEY) || '[]'); }
  catch (_) { return []; }
}

/* ── Sparkline SVG ────────────────────────────────────────── */
function renderSparkline(values, w, h) {
  if (!values || values.length < 2) return '';
  const min = Math.min.apply(null, values);
  const max = Math.max.apply(null, values);
  const range = max - min || 1;
  const pts = values
    .map((v, i) => {
      const x = (i / (values.length - 1)) * w;
      const y = h - ((v - min) / range) * (h - 4) - 2;
      return x.toFixed(1) + ',' + y.toFixed(1);
    })
    .join(' ');
  return (
    '<svg class="vr-spark" width="' + w + '" height="' + h +
    '" viewBox="0 0 ' + w + ' ' + h +
    '" aria-hidden="true"><polyline fill="none" stroke="currentColor" ' +
    'stroke-width="1.5" points="' + pts + '"/></svg>'
  );
}

/* ── Render HEART KPIs ────────────────────────────────────── */
export function renderHeartKpis(heart, hist) {
  const items = [
    { key: 'H', label: 'Happiness', val: heart.happiness, hint: 'Ativos 7d / aprovados', field: 'h' },
    { key: 'E', label: 'Engagement', val: heart.engagement, hint: 'Logins + consultas (30d)', field: 'e' },
    { key: 'A', label: 'Adoption', val: heart.adoption, hint: 'Aprovados / total cadastros', field: 'a' },
    { key: 'R', label: 'Retention', val: heart.retention, hint: 'Com eventos 30d', field: 'r' },
    { key: 'T', label: 'Task success', val: heart.taskSuccess, hint: 'Consultas / aberturas', field: 't' },
  ];
  const history = hist || getHeartHistory();
  return (
    '<div class="vr-heart-row">' +
    items.map((it) => {
      const col = it.val >= 70 ? 'ok' : it.val >= 40 ? 'mid' : 'low';
      const series = history.map((row) => row[it.field]);
      return (
        '<div class="vr-heart-kpi ' + col + '" title="' + esc(it.hint) + '">' +
        '<span class="vr-heart-letter">' + it.key + '</span>' +
        '<span class="vr-heart-val">' + it.val + '%</span>' +
        renderSparkline(series, 56, 18) +
        '<span class="vr-heart-lbl">' + esc(it.label) + '</span></div>'
      );
    }).join('') +
    '</div>'
  );
}

/* ── Render user health table ─────────────────────────────── */
export function renderUserHealth(users, retencao) {
  const retMap = {};
  (retencao || []).forEach((r) => { retMap[r.email] = r; });
  const rows = users
    .slice()
    .sort((a, b) => (a.status || '').localeCompare(b.status || '') || (a.email || '').localeCompare(b.email || ''))
    .map((u) => {
      const r = retMap[u.email] || {};
      const ult = r.ultimo_acesso || '';
      const dias = daysSince(ult);
      const stale = u.status === 'aprovado' && (dias === null || dias > 30);
      const pill = u.status === 'aprovado' ? (stale ? 'warn' : 'ok')
        : u.status === 'pendente' ? 'pend' : 'no';
      return (
        '<tr' + (stale ? ' class="vr-stale"' : '') + '>' +
        '<td><span class="vr-pill ' + pill + '">' + esc(u.status) + '</span></td>' +
        '<td class="vr-mono">' + esc(u.email) + '</td>' +
        '<td>' + esc(u.nome || '\u2014') + '</td>' +
        '<td class="vr-num">' + (r.eventos_30d != null ? r.eventos_30d : '\u2014') + '</td>' +
        '<td class="vr-mono vr-muted">' +
        (ult ? esc(String(ult).slice(0, 16)) : 'sem telemetria') +
        (dias != null ? ' <span class="vr-muted">(' + dias + 'd)</span>' : '') +
        '</td>' +
        '<td>' + (stale
          ? '<button type="button" class="vr-btn-mini vr-btn-reengage-one" data-email="' + esc(u.email) + '">Boletim</button>'
          : '<span class="vr-muted">\u2014</span>') +
        '</td></tr>'
      );
    }).join('');
  return (
    '<div class="vr-table-wrap"><table class="vr-admin-table">' +
    '<thead><tr><th>Status</th><th>E-mail</th><th>Nome</th><th>30d</th><th>Último acesso</th><th>Ação</th></tr></thead>' +
    '<tbody>' + rows + '</tbody></table></div>'
  );
}

/* ── Render heartbeats ────────────────────────────────────── */
export function renderHeartbeats(hb) {
  if (!hb || !hb.heartbeats) return '<p class="vr-muted">Sem heartbeats.</p>';
  const entries = Object.keys(hb.heartbeats)
    .map((k) => ({
      k, v: hb.heartbeats[k],
      ts: hb.heartbeats[k] && hb.heartbeats[k].ts ? new Date(hb.heartbeats[k].ts).getTime() : 0,
    }))
    .sort((a, b) => b.ts - a.ts).slice(0, 12);
  return (
    '<ul class="vr-hb-list">' +
    entries.map((e) => {
      const st = (e.v && e.v.status) || '?';
      const cls = st === 'ok' ? 'ok' : st === 'alerta' || st === 'erro' ? 'err' : 'mid';
      return '<li class="vr-hb-item ' + cls + '">' +
        '<span class="vr-hb-agent">' + esc(e.k) + '</span>' +
        '<span class="vr-hb-st">' + esc(st) + '</span>' +
        '<span class="vr-hb-ts">' + esc(e.v && e.v.ts ? String(e.v.ts).slice(0, 19) : '') + '</span></li>';
    }).join('') + '</ul>'
  );
}

/* ── Send reengagement ────────────────────────────────────── */
export async function sendReengage(emails, btn) {
  if (!emails || !emails.length) return;
  const label = btn && btn.textContent;
  if (!window.confirm('Enviar boletim para ' + emails.length + ' usuário(s)?\n\n' + emails.join('\n'))) return;
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando…'; }
  try {
    const r = await postAdmin('newsletter_envio_direcionado', { destinatarios: emails });
    const out = document.getElementById('vr-dry-out');
    if (out) { out.hidden = false; out.textContent = JSON.stringify(r, null, 2); }
    alert(r.ok ? 'Boletim enviado para ' + emails.length + ' destinatário(s).' : 'Falha: ' + (r.erro || 'erro'));
  } catch (e) {
    alert('Erro: ' + (e.message || e));
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = label || 'Enviar'; }
  }
}

/* ── Tab: Hoje (HEART dashboard) ──────────────────────────── */
export async function loadHoje() {
  const el = document.getElementById('vr-admin-hoje');
  if (!el) return;
  el.innerHTML = '<div class="vr-loading">Carregando painel HEART…</div>';
  try {
    const [usersRes, usoOv, usoRet, health, hb, dry] = await Promise.all([
      postAdmin('admin_listar', {}),
      postAdmin('uso', { visao: 'overview' }),
      postAdmin('uso', { visao: 'retencao' }),
      fetchHealth(),
      fetchHeartbeats(),
      postAdmin('relatorio_dry_run', {}),
    ]);

    if (!usersRes.ok) throw new Error(usersRes.erro || 'admin_listar falhou');
    const users = usersRes.usuarios || [];
    const overview = (usoOv.data || []).slice();
    const retencao = usoRet.data || [];
    const heart = calcHeart(users, retencao, overview);
    const hist = saveHeartHistory(heart);

    const stale = users.filter((u) => {
      if (u.status !== 'aprovado') return false;
      const r = retencao.find((x) => x.email === u.email);
      if (!r || !r.ultimo_acesso) return true;
      const d = daysSince(r.ultimo_acesso);
      return d === null || d > 30;
    });

    el.innerHTML =
      '<div class="vr-admin-section">' +
      '<div class="vr-section-head"><h3>Hoje</h3><span class="vr-muted">Framework HEART · dados ao vivo</span></div>' +
      renderHeartKpis(heart, hist) +
      '<div class="vr-stat-grid">' +
      '<div class="vr-stat"><span class="vr-stat-val">' + (health.versao || '\u2014') + '</span><span class="vr-stat-lbl">Worker</span></div>' +
      '<div class="vr-stat"><span class="vr-stat-val ' + (health.ok ? 'ok' : 'err') + '">' + (health.ok ? 'OK' : 'DEG') + '</span><span class="vr-stat-lbl">Health</span></div>' +
      '<div class="vr-stat"><span class="vr-stat-val">' + heart.meta.aprovados + '</span><span class="vr-stat-lbl">Aprovados</span></div>' +
      '<div class="vr-stat"><span class="vr-stat-val ' + (stale.length ? 'warn' : 'ok') + '">' + stale.length + '</span><span class="vr-stat-lbl">Inativos &gt;30d</span></div>' +
      '<div class="vr-stat"><span class="vr-stat-val">' + (dry.total_destinatarios != null ? dry.total_destinatarios : '\u2014') + '</span><span class="vr-stat-lbl">E-mail semanal</span></div>' +
      '</div>' +
      (stale.length
        ? '<div class="vr-alert vr-alert-action"><span>\u26a0 ' + stale.length + ' aprovado(s) sem login há 30+ dias.</span>' +
          '<button type="button" class="admin-btn vr-btn-reengage-all" id="vr-btn-reengage-all">Enviar boletim (' + stale.length + ')</button></div>'
        : '') +
      '<h4 class="vr-subhead">Saúde por usuário</h4>' +
      renderUserHealth(users, retencao) +
      '<h4 class="vr-subhead">Operações (heartbeats)</h4>' +
      renderHeartbeats(hb) +
      '<div class="vr-actions">' +
      '<button type="button" class="admin-btn" id="vr-btn-dry-run">Dry-run relatório</button>' +
      '<button type="button" class="admin-btn" id="vr-btn-refresh-hoje">Atualizar</button>' +
      '</div>' +
      '<pre id="vr-dry-out" class="vr-pre" hidden></pre></div>';

    // Bind buttons
    const btnRef = document.getElementById('vr-btn-refresh-hoje');
    if (btnRef) btnRef.onclick = loadHoje;

    document.getElementById('vr-btn-dry-run')?.addEventListener('click', async () => {
      const out = document.getElementById('vr-dry-out');
      try {
        const d = await postAdmin('relatorio_dry_run', {});
        if (out) { out.hidden = false; out.textContent = JSON.stringify(d, null, 2); }
      } catch (e) {
        if (out) { out.hidden = false; out.textContent = String(e.message || e); }
      }
    });

    const staleEmails = stale.map((u) => u.email);
    document.getElementById('vr-btn-reengage-all')?.addEventListener('click', function () {
      sendReengage(staleEmails.slice(0, 25), this);
    });

    document.querySelectorAll('.vr-btn-reengage-one').forEach((b) => {
      b.addEventListener('click', function () {
        const em = this.getAttribute('data-email');
        if (em) sendReengage([em], this);
      });
    });
  } catch (e) {
    el.innerHTML = '<div class="admin-msg err">Erro: ' + esc(e.message || e) + '</div>';
  }
}

/* ── Inject styles ────────────────────────────────────────── */
function injectStyles() {
  if (document.getElementById('vr-admin-modules-css')) return;
  const s = document.createElement('style');
  s.id = 'vr-admin-modules-css';
  s.textContent =
    '#admin-tab-hoje.vr-admin-tab-pane{display:none}' +
    '#admin-tab-hoje.vr-admin-tab-pane.active{display:block}' +
    '.vr-heart-row{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px;margin:12px 0 16px}' +
    '.vr-heart-kpi{padding:10px 8px;border:1px solid #0D2438;border-radius:6px;background:#000D1A;text-align:center}' +
    '.vr-heart-kpi.ok{border-color:#1e3a5f}' +
    '.vr-heart-kpi.mid{border-color:#5a4a1a}' +
    '.vr-heart-kpi.low{border-color:#5a1a1a}' +
    '.vr-heart-letter{font-size:10px;font-weight:700;color:#64748B;letter-spacing:.06em}' +
    '.vr-heart-val{display:block;font-size:24px;font-weight:700;color:#EDE8D8;margin:2px 0;font-variant-numeric:tabular-nums}' +
    '.vr-heart-lbl{display:block;font-size:8px;color:#64748B;text-transform:uppercase;letter-spacing:.06em;margin-top:2px}' +
    '.vr-spark{color:#64748B;margin-top:4px}' +
    '.vr-stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px;margin:12px 0}' +
    '.vr-stat{padding:10px;border:1px solid #0D2438;border-radius:6px;background:#000D1A}' +
    '.vr-stat-val{font-size:20px;font-weight:700;color:#EDE8D8;display:block}' +
    '.vr-stat-val.ok{color:#34D399}.vr-stat-val.err{color:#EF4444}.vr-stat-val.warn{color:#F59E0B}' +
    '.vr-stat-lbl{font-size:9px;color:#64748B;text-transform:uppercase;letter-spacing:.06em}' +
    '.vr-subhead{font-size:11px;font-weight:600;color:#94A3B8;margin:16px 0 8px}' +
    '.vr-section-head{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:8px}' +
    '.vr-table-wrap{overflow-x:auto}' +
    '.vr-admin-table{width:100%;border-collapse:collapse;font-size:11px}' +
    '.vr-admin-table th{text-align:left;padding:6px 8px;border-bottom:2px solid #0D2438;color:#64748B;font-weight:600;text-transform:uppercase;font-size:9px;letter-spacing:.05em}' +
    '.vr-admin-table td{padding:6px 8px;border-bottom:1px solid #0D2438;color:#C8D5DF;vertical-align:middle}' +
    '.vr-mono{font-family:\'JetBrains Mono\',ui-monospace,monospace;font-size:11px}' +
    '.vr-muted{color:#64748B;font-size:10px}' +
    '.vr-num{text-align:right;font-variant-numeric:tabular-nums}' +
    '.vr-pill{display:inline-block;padding:1px 6px;border-radius:4px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:.04em}' +
    '.vr-pill.ok{background:#064E3B;color:#34D399}' +
    '.vr-pill.warn{background:#78350F;color:#F59E0B}' +
    '.vr-pill.pend{background:#1E3A5F;color:#60A5FA}' +
    '.vr-pill.no{background:#1F2937;color:#6B7280}' +
    '.vr-stale{background:rgba(239,68,68,.06)}' +
    '.vr-btn-mini{font-size:9px;padding:2px 8px;border-radius:3px;border:1px solid #334155;background:#0D2438;color:#94A3B8;cursor:pointer}' +
    '.vr-btn-mini:hover{background:#1e293b;color:#EDE8D8;border-color:#475569}' +
    '.vr-alert{padding:8px 10px;border-radius:5px;background:#451a1a;border:1px solid #7f1d1d;color:#fecaca;font-size:11px;margin:8px 0}' +
    '.vr-alert-action{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}' +
    '.vr-hb-list{list-style:none;margin:0;padding:0;font-size:11px}' +
    '.vr-hb-item{display:flex;gap:8px;padding:5px 0;border-bottom:1px solid #0D2438}' +
    '.vr-hb-agent{flex:1;color:#C8D5DF}' +
    '.vr-hb-st{font-weight:700;text-transform:uppercase;font-size:9px}' +
    '.vr-hb-item.ok .vr-hb-st{color:#34D399}' +
    '.vr-hb-item.err .vr-hb-st{color:#EF4444}' +
    '.vr-hb-item.mid .vr-hb-st{color:#94A3B8}' +
    '.vr-hb-ts{color:#64748B;font-family:monospace;font-size:9px}' +
    '.vr-actions{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}' +
    '.vr-pre{font-size:10px;background:#000D1A;border:1px solid #0D2438;padding:8px;border-radius:5px;overflow:auto;max-height:160px;color:#94A3B8}' +
    '.vr-loading{color:#64748B;font-size:12px;padding:16px}' +
    '@media(max-width:720px){.vr-heart-row{grid-template-columns:repeat(2,1fr)}}' +
    '@media(prefers-reduced-motion:reduce){.vr-heart-kpi{transition:none}}';
  document.head.appendChild(s);
}

/* ── Inject the "Hoje" tab into admin panel ───────────────── */
export function injectHojeTab() {
  const painel = document.getElementById('admin-painel');
  const tabs = painel && painel.querySelector('.admin-tabs');
  if (!tabs || document.getElementById('admin-tab-hoje')) return;

  const btn = document.createElement('button');
  btn.className = 'admin-tab-btn';
  btn.setAttribute('data-tab', 'hoje');
  btn.textContent = 'Hoje';
  btn.addEventListener('click', () => {
    if (typeof adminAbaAtiva === 'function') adminAbaAtiva('hoje', btn);
    loadHoje();
  });
  tabs.insertBefore(btn, tabs.firstChild);

  const pane = document.createElement('div');
  pane.id = 'admin-tab-hoje';
  pane.className = 'admin-tab-pane vr-admin-tab-pane';
  pane.innerHTML = '<div id="vr-admin-hoje"></div>';
  const firstPane = painel.querySelector('.admin-tab-pane');
  painel.insertBefore(pane, firstPane);

  // Patch adminAbaAtiva to trigger loadHoje on tab switch
  const origAba = window.adminAbaAtiva;
  if (origAba && !window._vrAdminAbaPatched) {
    window._vrAdminAbaPatched = true;
    window.adminAbaAtiva = function (id, el) {
      origAba(id, el);
      if (id === 'hoje') loadHoje();
    };
  }
}

function patchAuth() {
  const orig = window.adminAutenticar;
  if (!orig || window._vrAdminAuthPatched) return;
  window._vrAdminAuthPatched = true;
  window.adminAutenticar = async function () {
    const inp = document.getElementById('admin-senha-input');
    if (inp && inp.value.trim()) {
      try { sessionStorage.setItem('radar_admin_senha', inp.value.trim()); } catch (_) {}
    }
    await orig.apply(this, arguments);
    injectHojeTab();
    loadHoje();
  };
}

function patchOpen() {
  const orig = window.abrirAdmin;
  if (!orig || window._vrAdminOpenPatched) return;
  window._vrAdminOpenPatched = true;
  window.abrirAdmin = function () {
    orig.apply(this, arguments);
    setTimeout(() => {
      injectHojeTab();
      const painel = document.getElementById('admin-painel');
      if (painel && painel.style.display !== 'none') loadHoje();
    }, 200);
  };
}

/* ── Backward-compatible global ───────────────────────────── */
window.VRAdmin = {
  ...window.VRAdmin || {},
  loadHoje, calcHeart, postAdmin, sendReengage, getHeartHistory,
};

/* ── Init ─────────────────────────────────────────────────── */
export function initTabHoje() {
  injectStyles();
  patchAuth();
  patchOpen();
  if (document.getElementById('admin-painel')) injectHojeTab();
}

// Auto-init when module loads
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initTabHoje);
} else {
  initTabHoje();
}

