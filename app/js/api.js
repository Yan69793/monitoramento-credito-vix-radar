/**
 * VIX Radar — API Fetch Wrapper
 * v202.1 — reactive {loading, data, error} with retry, timeout, skeleton states
 *
 * Usage:
 *   import { createApiClient, fetchWithRetry, api } from './api.js';
 *   const { state, abort } = api.get('/path');
 *   state.loading  // true while fetching
 *   state.data     // null → populated on success
 *   state.error    // null → populated on failure
 */

/* ── State factory ────────────────────────────────────────── */
function createReactiveState() {
  const listeners = new Set();
  const _state = { loading: false, data: null, error: null };
  const handler = {
    set(target, prop, value) {
      target[prop] = value;
      listeners.forEach((fn) => { try { fn({ ...target }); } catch (_) {} });
      return true;
    },
  };
  const state = new Proxy(_state, handler);
  return {
    state,
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    reset() { state.loading = false; state.data = null; state.error = null; },
  };
}

/* ── Helpers ──────────────────────────────────────────────── */
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function withTimeout(promise, ms, controller) {
  if (!ms || ms <= 0) return promise;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      controller && controller.abort();
      reject(new Error(`Timeout após ${ms}ms`));
    }, ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

/* ── Core fetch with retry ────────────────────────────────── */
export async function fetchWithRetry(url, opts = {}) {
  const {
    retries = 3,
    retryDelay = 800,
    timeout = 12000,
    retryOn5xx = true,
    retryOnNetwork = true,
    fetchOptions = {},
    signal,
  } = opts;

  let lastError = null;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const controller = new AbortController();
    if (signal) {
      if (signal.aborted) throw new DOMException('Aborted', 'AbortError');
      signal.addEventListener('abort', () => controller.abort(), { once: true });
    }

    try {
      const resp = await withTimeout(
        fetch(url, { ...fetchOptions, signal: controller.signal }),
        timeout, controller,
      );

      if (!resp.ok) {
        if (resp.status === 401 || resp.status === 403) {
          const body = await resp.json().catch(() => null);
          const err = new Error(body?.erro || `HTTP ${resp.status}`);
          err.status = resp.status; err.response = resp; err.data = body;
          throw err;
        }
        if (retryOn5xx && resp.status >= 500 && attempt < retries) {
          lastError = new Error(`HTTP ${resp.status}`);
          lastError.status = resp.status;
          console.warn(`[api] Retry ${attempt + 1}/${retries + 1} status=${resp.status}`);
          await sleep(retryDelay * Math.pow(2, attempt));
          continue;
        }
        const body = await resp.json().catch(() => null);
        const err = new Error(body?.erro || `HTTP ${resp.status}`);
        err.status = resp.status; err.response = resp; err.data = body;
        throw err;
      }

      const contentType = resp.headers.get('content-type') || '';
      return contentType.includes('application/json') ? await resp.json() : resp;
    } catch (err) {

/* ── API Client factory ───────────────────────────────────── */
export function createApiClient(baseUrl, options = {}) {
  const {
    timeout = 12000,
    retries = 3,
    defaultHeaders = {},
  } = options;

  const buildUrl = (path) => {
    if (path.startsWith('http')) return path;
    return baseUrl.replace(/\/+$/, '') + '/' + path.replace(/^\/+/, '');
  };

  const mergeHeaders = (extra) => {
    const h = { ...defaultHeaders, 'Content-Type': 'application/json' };
    if (extra) Object.assign(h, extra);
    return h;
  };

  function request(path, reqOpts = {}) {
    const {
      method = 'GET',
      body,
      headers: extraHeaders,
      timeout: reqTimeout = timeout,
      retries: reqRetries = retries,
      state: externalState,
    } = reqOpts;

    const { state, reset } = externalState
      ? { state: externalState, reset() {} }
      : createReactiveState();

    const controller = new AbortController();
    reset();
    state.loading = true;

    const fetchOptions = {
      method,
      headers: mergeHeaders(extraHeaders),
      signal: controller.signal,
    };
    if (body) fetchOptions.body = typeof body === 'string' ? body : JSON.stringify(body);

    const promise = fetchWithRetry(buildUrl(path), {
      timeout: reqTimeout,
      retries: reqRetries,
      retryOn5xx: method === 'GET',
      fetchOptions,
      signal: controller.signal,
    })
      .then((data) => { state.data = data; state.error = null; state.loading = false; return data; })
      .catch((err) => {
        if (err.name !== 'AbortError') { state.error = err; state.data = null; }
        state.loading = false;
        throw err;
      });

    return { state, abort: () => controller.abort(), promise };
  }

  return {
    get(path, opts) { return request(path, { ...opts, method: 'GET' }); },
    post(path, body, opts) { return request(path, { ...opts, method: 'POST', body }); },
    put(path, body, opts) { return request(path, { ...opts, method: 'PUT', body }); },
    delete(path, opts) { return request(path, { ...opts, method: 'DELETE' }); },
    request,
    createState: createReactiveState,
  };
}

/* ── Skeleton helpers ─────────────────────────────────────── */
export const Skeleton = {
  block(rows = 4) {
    let bars = '';
    for (let i = 0; i < rows; i++) {
      bars +=
        '<div class="vr-sk-row">' +
        '<span class="vr-sk-line" style="width:' + (40 + (i % 3) * 15) + '%"></span>' +
        '<span class="vr-sk-line vr-sk-short"></span></div>';
    }
    return '<div class="vr-skeleton">' + bars + '</div>';
  },

  table(rows = 5, cols = 4) {
    let html = '<div class="vr-skeleton vr-skeleton-table">';
    for (let i = 0; i < rows; i++) {
      html += '<div class="vr-sk-row">';
      for (let j = 0; j < cols; j++) {
        html += '<span class="vr-sk-line" style="width:' + (40 + ((i + j) % 3) * 20) + 'px;flex-shrink:0"></span>';
      }
      html += '</div>';
    }
    return html + '</div>';
  },

  card() {
    return (
      '<div class="vr-skeleton vr-skeleton-card">' +
      '<span class="vr-sk-line" style="width:60%;height:14px;margin-bottom:8px"></span>' +
      '<span class="vr-sk-line" style="width:90%;height:10px;margin-bottom:6px"></span>' +
      '<span class="vr-sk-line" style="width:75%;height:10px"></span></div>'
    );
  },

  kpi(count = 4) {
    let html = '<div style="display:grid;grid-template-columns:repeat(' + count + ',1fr);gap:8px">';
    for (let i = 0; i < count; i++) {
      html +=
        '<div class="vr-skeleton">' +
        '<span class="vr-sk-line" style="width:32px;height:22px;margin-bottom:6px"></span>' +
        '<span class="vr-sk-line" style="width:80%"></span></div>';
    }
    return html + '</div>';
  },

  injectStyles() {
    if (document.getElementById('vr-api-skeleton-css')) return;
    const s = document.createElement('style');
    s.id = 'vr-api-skeleton-css';
    s.textContent =
      '.vr-skeleton{padding:8px 0}' +
      '.vr-sk-row{display:flex;gap:10px;align-items:center;padding:8px 0;border-bottom:1px solid #0D2438}' +
      '.vr-sk-line{display:block;height:10px;border-radius:3px;background:linear-gradient(90deg,#0D2438 25%,#1a3a52 50%,#0D2438 75%);background-size:200% 100%;animation:vr-sk-pulse 1.2s ease-in-out infinite}' +
      '.vr-sk-short{width:48px;flex-shrink:0;margin-left:auto}' +
      '@keyframes vr-sk-pulse{0%{background-position:100% 0}100%{background-position:-100% 0}}' +
      '@media(prefers-reduced-motion:reduce){.vr-sk-line{animation:none;background:#1a3a52}}';
    document.head.appendChild(s);
  },
};

/* ── Default pre-configured instance ──────────────────────── */
const API_BASE =
  (typeof window !== 'undefined' && window.API_BASE) ||
  'https://api.vixradar.com';

export const api = createApiClient(API_BASE, {
  timeout: 12000,
  retries: 3,
  defaultHeaders: { 'Content-Type': 'application/json' },
});

export default api;
