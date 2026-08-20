/**
 * VIX Radar — Admin Métricas (Fase 2)
 * v202.1 — ES module refactor (was vr-admin-metricas.js IIFE)
 *
 * Enhancement layer over core adminCarregarMetricas with skeleton + error.
 */

import { esc, skeletonBlock, wrapWhenReady } from './shared.js?v=202.18';

/* ── Styles ───────────────────────────────────────────────── */
function injectMetStyles() {
  if (document.getElementById('vr-admin-met-css')) return;
  const s = document.createElement('style');
  s.id = 'vr-admin-met-css';
  s.textContent =
    '#admin-tab-metricas .met-block{border:1px solid #0D2438;border-radius:6px;padding:12px;margin-bottom:10px;background:#000D1A}' +
    '#admin-tab-metricas .met-snap{font-variant-numeric:tabular-nums;font-size:18px;font-weight:700;color:#EDE8D8}' +
    '#admin-tab-metricas .met-intro{font-size:11px;color:#94A3B8;line-height:1.6;margin-bottom:12px;padding:10px;border:1px solid #0D2438;border-radius:6px;background:#001528}' +
    '#admin-tab-metricas .met-formula{font-family:\'IBM Plex Mono\',ui-monospace,monospace;font-size:9px;color:#64748B;white-space:pre-line;margin:8px 0;padding:8px;background:#001020;border-radius:4px}';
  document.head.appendChild(s);
}

/* ── Patch core adminCarregarMetricas ─────────────────────── */
function patchMetricas() {
  wrapWhenReady('adminCarregarMetricas', (orig) => {
    return function () {
      const el = document.getElementById('met-conteudo');
      if (el) el.innerHTML = skeletonBlock(6);
      try {
        orig.apply(this, arguments);
      } catch (e) {
        if (el) {
          el.innerHTML = '<div class="uso-erro">Erro ao calcular métricas: ' +
            esc(e.message || e) + '</div>';
        }
      }
    };
  });
}

/* ── Init ─────────────────────────────────────────────────── */
export function initMetricas() {
  injectMetStyles();
  patchMetricas();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initMetricas);
} else {
  initMetricas();
}
