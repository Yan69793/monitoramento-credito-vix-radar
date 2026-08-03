/**
 * VIX Radar — Admin Fase 3 Polish (overlay + motion)
 * v202.1 — ES module refactor (was vr-admin-fase3.js IIFE)
 *
 * Linear/Vercel-inspired admin shell styling layer.
 */

/* ── Inject overlay polish CSS ────────────────────────────── */
function injectOverlayPolish() {
  if (document.getElementById('vr-admin-fase3-css')) return;
  const s = document.createElement('style');
  s.id = 'vr-admin-fase3-css';
  s.textContent =
    '#admin-overlay.vis{background:rgba(0,8,18,.72);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px)}' +
    '#admin-painel{border:1px solid #1e293b;box-shadow:0 25px 50px -12px rgba(0,0,0,.55);border-radius:10px}' +
    '.admin-tabs{border-bottom:1px solid #0D2438;padding-bottom:0;gap:2px;display:flex;flex-wrap:wrap}' +
    '.admin-tab-btn{font-size:10px;font-weight:600;letter-spacing:.05em;padding:8px 12px;border:none;border-bottom:2px solid transparent;background:transparent;color:#64748B;cursor:pointer;transition:color .15s,border-color .15s}' +
    '.admin-tab-btn:hover{color:#94A3B8}' +
    '.admin-tab-btn.active{color:#EDE8D8;border-bottom-color:#64748B}' +
    '.admin-section-title{font-size:11px;font-weight:700;letter-spacing:.06em;color:#94A3B8}' +
    '.admin-btn{font-size:10px;font-weight:600;letter-spacing:.04em;padding:6px 12px;border-radius:5px;border:1px solid #334155;background:#0D2438;color:#C8D5DF;cursor:pointer;transition:background .15s,border-color .15s,color .15s}' +
    '.admin-btn:hover{background:#1e293b;color:#EDE8D8;border-color:#475569}' +
    '.admin-tab-pane{animation:vr-admin-fade .2s ease}' +
    '@keyframes vr-admin-fade{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}' +
    '@media(prefers-reduced-motion:reduce){.admin-tab-pane{animation:none}#admin-overlay.vis{backdrop-filter:none}}';
  document.head.appendChild(s);
}

/* ── Init ─────────────────────────────────────────────────── */
export function initFase3Polish() {
  injectOverlayPolish();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initFase3Polish);
} else {
  initFase3Polish();
}
