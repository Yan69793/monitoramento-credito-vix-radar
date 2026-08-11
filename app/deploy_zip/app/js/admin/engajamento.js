/**
 * VIX Radar — Admin Engajamento (Fase 2)
 * v202.1 — ES module refactor (was vr-admin-engajamento.js IIFE)
 *
 * Imports from shared.js; wraps core usoCarregar/usoMudarVisao with skeleton + error handling.
 */

import { esc, skeletonBlock, wrapWhenReady } from './shared.js?v=202.6';

/* ── Styles ───────────────────────────────────────────────── */
function injectEngStyles() {
  if (document.getElementById('vr-admin-eng-css')) return;
  const s = document.createElement('style');
  s.id = 'vr-admin-eng-css';
  s.textContent =
    '#admin-tab-uso .uso-visao-row{display:flex;gap:4px;flex-wrap:wrap;margin:10px 0 12px}' +
    '#admin-tab-uso .uso-vis-btn{font-size:10px;font-weight:600;letter-spacing:.04em;padding:5px 10px;border-radius:5px;border:1px solid #0D2438;background:#001528;color:#64748B;cursor:pointer;transition:color .15s,border-color .15s,background .15s}' +
    '#admin-tab-uso .uso-vis-btn:hover{color:#94A3B8;border-color:#1e3a5f}' +
    '#admin-tab-uso .uso-vis-btn.active{background:#0D2438;color:#EDE8D8;border-color:#334155}' +
    '#admin-tab-uso .uso-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:8px;margin-bottom:12px}' +
    '#admin-tab-uso .uso-kpi{padding:10px;border:1px solid #0D2438;border-radius:6px;background:#000D1A}' +
    '#admin-tab-uso .uso-kpi-label{font-size:9px;color:#64748B;text-transform:uppercase;letter-spacing:.06em}' +
    '#admin-tab-uso .uso-kpi-value{font-size:22px;font-weight:700;color:#EDE8D8;line-height:1.2}' +
    '#admin-tab-uso .uso-erro{padding:10px;border-radius:5px;background:#451a1a;border:1px solid #7f1d1d;color:#fecaca;font-size:11px}';
  document.head.appendChild(s);
}

/* ── Skeleton helper ──────────────────────────────────────── */
function showSkeleton() {
  const el = document.getElementById('uso-conteudo');
  if (el) el.innerHTML = skeletonBlock(5);
}

/* ── Patching core functions ──────────────────────────────── */
function patchUsoCarregar() {
  wrapWhenReady('usoCarregar', (orig) => {
    return async function () {
      showSkeleton();
      try {
        await orig.apply(this, arguments);
      } catch (e) {
        const el = document.getElementById('uso-conteudo');
        if (el) {
          el.innerHTML = '<div class="uso-erro">Erro ao carregar engajamento: ' +
            esc(e.message || e) + '</div>';
        }
      }
    };
  });
}

function patchUsoMudarVisao() {
  wrapWhenReady('usoMudarVisao', (orig) => {
    return function (visao, btn) {
      const el = document.getElementById('uso-conteudo');
      if (el && el.querySelector('.vr-skeleton')) return orig.apply(this, arguments);
      orig.apply(this, arguments);
    };
  });
}

function patchAbaAtiva() {
  let tries = 0;
  function attempt() {
    const orig = window.adminAbaAtiva;
    if (typeof orig === 'function' && !orig._vrEngPatched) {
      window.adminAbaAtiva = function (id, el) {
        orig(id, el);
        // core already calls usoCarregar; wrapper adds skeleton
      };
      window.adminAbaAtiva._vrEngPatched = true;
      return;
    }
    if (++tries < 80) setTimeout(attempt, 150);
  }
  attempt();
}

/* ── Auto-refresh ─────────────────────────────────────────── */
let refreshTimer = null;

function startAutoRefresh() {
  if (refreshTimer) return;
  refreshTimer = setInterval(() => {
    const pane = document.getElementById('admin-tab-uso');
    if (pane && pane.classList.contains('active') && typeof window.usoCarregar === 'function') {
      window.usoCarregar();
    }
  }, 300000);
}

/* ── Init ─────────────────────────────────────────────────── */
export function initEngajamento() {
  injectEngStyles();
  patchUsoCarregar();
  patchUsoMudarVisao();
  patchAbaAtiva();
  startAutoRefresh();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEngajamento);
} else {
  initEngajamento();
}
