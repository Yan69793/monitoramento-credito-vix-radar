/**
 * VIX Radar — Admin Bootstrap (ES Module Entry)
 * v202.1
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
// Basta buscar/substituir "?v=202.3" nos .js e mudar CACHE_VERSION no index.html.
import './admin/shared.js?v=202.3';
import './admin/modules.js?v=202.3';
import './admin/engajamento.js?v=202.3';
import './admin/metricas.js?v=202.3';
import './admin/fase3.js?v=202.3';

// Also expose the API client and router for direct use
export { api, createApiClient, fetchWithRetry, Skeleton } from './api.js?v=202.3';
export { initRouter, navigate, onRoute, registerRoutes, getCurrentRoute } from './admin-router.js?v=202.3';

// Export admin module APIs for programmatic use
export {
  loadHoje, calcHeart, sendReengage, getHeartHistory,
  renderHeartKpis, renderUserHealth, renderHeartbeats, injectHojeTab,
} from './admin/modules.js?v=202.3';

export {
  API_BASE, esc, getSenha, setSenha, authHeaders,
  postAdmin, skeletonBlock, injectBaseStyles, wrapWhenReady,
} from './admin/shared.js?v=202.3';

export { initEngajamento } from './admin/engajamento.js?v=202.3';
export { initMetricas } from './admin/metricas.js?v=202.3';
export { initFase3Polish } from './admin/fase3.js?v=202.3';

console.log('[VRAdmin] Bootstrap loaded — ES modules ready');
