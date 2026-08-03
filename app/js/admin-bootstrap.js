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
import './admin/shared.js';
import './admin/modules.js';
import './admin/engajamento.js';
import './admin/metricas.js';
import './admin/fase3.js';

// Also expose the API client and router for direct use
export { api, createApiClient, fetchWithRetry, Skeleton } from './api.js';
export { initRouter, navigate, onRoute, registerRoutes, getCurrentRoute } from './admin-router.js';

// Export admin module APIs for programmatic use
export {
  loadHoje, calcHeart, sendReengage, getHeartHistory,
  renderHeartKpis, renderUserHealth, renderHeartbeats, injectHojeTab,
} from './admin/modules.js';

export {
  API_BASE, esc, getSenha, setSenha, authHeaders,
  postAdmin, skeletonBlock, injectBaseStyles, wrapWhenReady,
} from './admin/shared.js';

export { initEngajamento } from './admin/engajamento.js';
export { initMetricas } from './admin/metricas.js';
export { initFase3Polish } from './admin/fase3.js';

console.log('[VRAdmin] Bootstrap loaded — ES modules ready');
