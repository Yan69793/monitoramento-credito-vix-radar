/**
 * VIX Radar — Admin Hash Router
 * v202.1 — hash-based router for admin tabs
 *
 * Routes:
 *   #/admin/hoje      → HEART dashboard
 *   #/admin/uso       → Engajamento / usage
 *   #/admin/metricas  → Métricas
 *
 * Usage:
 *   import { initRouter, navigate, onRoute } from './admin-router.js';
 *   initRouter({ defaultRoute: 'hoje' });
 */

/* ── Route store ──────────────────────────────────────────── */
const routes = new Map();
let currentRoute = null;
let defaultRoute = 'hoje';
let initialized = false;
let routePrefix = '/admin/';

/* ── Route matching ───────────────────────────────────────── */
function parseHash() {
  const hash = window.location.hash || '';
  // Support both #/admin/hoje and #hoje (legacy)
  if (hash.startsWith('#/' + routePrefix.replace(/^\/+/, ''))) {
    return hash.slice(('#' + routePrefix).length) || defaultRoute;
  }
  if (hash.startsWith('#/admin/')) {
    return hash.slice('#/admin/'.length).split('/')[0] || defaultRoute;
  }
  // Legacy single-word hash
  const word = hash.replace(/^#\/?/, '');
  if (word && routes.has(word)) return word;
  return defaultRoute;
}

function updateHash(route) {
  const newHash = '#' + routePrefix + route;
  if (window.location.hash !== newHash) {
    history.pushState(null, '', newHash);
  }
}

/* ── Handler execution ────────────────────────────────────── */
async function executeRoute(route) {
  if (currentRoute === route) return;

  const prev = currentRoute;
  currentRoute = route;

  // Call leave handler for previous route
  if (prev && routes.has(prev)) {
    const leaving = routes.get(prev);
    if (leaving.onLeave) {
      try { await leaving.onLeave(); } catch (e) { console.error('[router] onLeave error:', e); }
    }
  }

  // Call enter handler
  const entry = routes.get(route);
  if (entry && entry.onEnter) {
    try { await entry.onEnter(route); } catch (e) { console.error('[router] onEnter error:', e); }
  }

  // Dispatch event
  window.dispatchEvent(new CustomEvent('vr-admin-route-change', {
    detail: { route, previous: prev },
  }));
}

/* ── Public API ───────────────────────────────────────────── */

/**
 * Register a route handler.
 * @param {string}   route     Route name (e.g. 'hoje', 'uso', 'metricas')
 * @param {Function} onEnter   Called when entering the route
 * @param {Function} [onLeave] Called when leaving the route
 */
export function onRoute(route, onEnter, onLeave) {
  routes.set(route, { onEnter, onLeave });
}

/**
 * Navigate to a route programmatically.
 * @param {string} route  Route name
 * @param {boolean} [silent=false]  Don't update URL hash
 */
export function navigate(route, silent) {
  if (!silent) updateHash(route);
  executeRoute(route);
}

/**
 * Initialize the router.
 * @param {object} [opts]
 * @param {string} [opts.defaultRoute='hoje']
 * @param {string} [opts.prefix='/admin/']     Hash prefix
 * @param {boolean} [opts.syncTabs=true]        Auto-sync with .admin-tab-btn clicks
 */
export function initRouter(opts = {}) {
  if (initialized) return;
  initialized = true;

  defaultRoute = opts.defaultRoute || 'hoje';
  routePrefix = opts.prefix || '/admin/';
  if (!routePrefix.startsWith('/')) routePrefix = '/' + routePrefix;
  if (!routePrefix.endsWith('/')) routePrefix += '/';

  // Listen to hash changes
  window.addEventListener('hashchange', () => {
    const route = parseHash();
    executeRoute(route);
  });

  // Initial route
  const initial = parseHash();
  if (initial !== defaultRoute || window.location.hash) {
    executeRoute(initial);
  } else {
    // Set initial hash silently
    updateHash(defaultRoute);
    executeRoute(defaultRoute);
  }

  // Auto-sync with tab buttons if present
  if (opts.syncTabs !== false) {
    syncTabButtons();
  }
}

/* ── Tab button integration ───────────────────────────────── */
function syncTabButtons() {
  // Listen to clicks on tab buttons in the admin panel
  const delegate = (e) => {
    const btn = e.target.closest('.admin-tab-btn');
    if (!btn) return;

    const tabId = btn.getAttribute('data-tab') ||
      (btn.textContent || '').toLowerCase().replace(/[^a-z0-9]/g, '');

    // Map tab button IDs to route names
    const tabMap = {
      'hoje': 'hoje',
      'uso': 'uso',
      'engajamento': 'uso',
      'metricas': 'metricas',
      'métricas': 'metricas',
    };

    const route = tabMap[tabId] || tabId;
    if (routes.has(route) || route === currentRoute) {
      e.preventDefault();
      navigate(route);
    }
  };

  document.addEventListener('click', delegate, true);

  // Also listen for route changes to update tab button active states
  window.addEventListener('vr-admin-route-change', (e) => {
    const { route } = e.detail;
    const tabMap = { 'hoje': 'hoje', 'uso': 'uso', 'metricas': 'metricas' };
    const tabId = tabMap[route] || route;

    document.querySelectorAll('.admin-tab-btn').forEach((btn) => {
      const btnTab = btn.getAttribute('data-tab') ||
        (btn.textContent || '').toLowerCase().replace(/[^a-z0-9]/g, '');
      const btnRoute = tabMap[btnTab] || btnTab;
      btn.classList.toggle('active', btnRoute === tabId);
    });

    // Show/hide tab panes
    document.querySelectorAll('.admin-tab-pane[id]').forEach((pane) => {
      const paneId = pane.id.replace('admin-tab-', '');
      const paneRoute = tabMap[paneId] || paneId;
      pane.classList.toggle('active', paneRoute === tabId);
    });
  });
}

/**
 * Get the current active route.
 */
export function getCurrentRoute() {
  return currentRoute || defaultRoute;
}

/**
 * Register routes from a map object.
 * @param {object} routeMap  { routeName: { onEnter, onLeave } }
 */
export function registerRoutes(routeMap) {
  Object.entries(routeMap).forEach(([name, handlers]) => {
    routes.set(name, {
      onEnter: handlers.onEnter || handlers.enter || handlers,
      onLeave: handlers.onLeave || handlers.leave,
    });
  });
}
