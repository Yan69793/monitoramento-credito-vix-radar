/**
 * VIX Radar — Admin Bootstrap (ES Module Entry)
 * v202.8
 *
 * Replaces the old <script src="admin/vr-admin-*.js"> loading sequence.
 * Add ONE script tag to index.html:
 *   <script type="module" src="app/js/admin-bootstrap.js"></script>
 *
 * Imports all admin modules; each auto-inits on load.
 * Backward-compatible: exposes window.VRAdminShared and window.VRAdmin.
 */

// Order matters: shared → modules → engajamento → metricas → fase3
// CACHEJS1 (v202.3): query param em static import previne cache de modulo truncado.
// Ao subir de versao: trocar TODO "?v=<antiga>" por "?v=<nova>" em app/js/**/*.js e no
// <script src> do index.html, e mudar CACHE_VERSION. Se um ficar para tras, o browser baixa
// shared.js duas vezes como dois modulos distintos. O gate 3.2 do deploy so olha o
// index.html, o resto e conferido pelo 3.4a.
import './admin/shared.js?v=202.37';
import './admin/modules.js?v=202.37';
import './admin/engajamento.js?v=202.37';
import './admin/metricas.js?v=202.37';
import './admin/fase3.js?v=202.37';

// Also expose the API client and router for direct use
export { api, createApiClient, fetchWithRetry, Skeleton } from './api.js?v=202.37';
export { initRouter, navigate, onRoute, registerRoutes, getCurrentRoute } from './admin-router.js?v=202.37';

// Export admin module APIs for programmatic use
export {
  loadHoje, calcHeart, sendReengage, getHeartHistory,
  renderHeartKpis, renderUserHealth, renderHeartbeats, injectHojeTab,
} from './admin/modules.js?v=202.37';

export {
  API_BASE, esc, getSenha, setSenha, authHeaders,
  postAdmin, skeletonBlock, injectBaseStyles, wrapWhenReady,
} from './admin/shared.js?v=202.37';

export { initEngajamento } from './admin/engajamento.js?v=202.37';
export { initMetricas } from './admin/metricas.js?v=202.37';
export { initFase3Polish } from './admin/fase3.js?v=202.37';

console.log('[VRAdmin] Bootstrap loaded — ES modules ready');
