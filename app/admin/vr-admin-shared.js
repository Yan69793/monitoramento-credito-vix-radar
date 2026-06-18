/**
 * VIX Radar — Admin shared utilities + design tokens
 * v201.69 — shortcut robusto + z-index admin
 */
(function () {
  "use strict";

  var API = typeof API_BASE !== "undefined" ? API_BASE : "https://api.vixradar.com";

  function isAdminShortcut(e) {
    if (!e || e.repeat) return false;
    if (!(e.ctrlKey || e.metaKey)) return false;
    var keyOk = e.code === "KeyA" || (e.key && String(e.key).toLowerCase() === "a");
    if (!keyOk) return false;
    return e.shiftKey || e.altKey;
  }

  function toggleAdminPanel() {
    var overlay = document.getElementById("admin-overlay");
    if (!overlay) return false;
    overlay.style.zIndex = "100002";
    if (overlay.classList.contains("vis")) {
      if (typeof window.fecharAdmin === "function") {
        window.fecharAdmin();
        document.body.classList.remove("vr-admin-open");
        return true;
      }
    } else if (typeof window.abrirAdmin === "function") {
      document.body.classList.add("vr-admin-open");
      window.abrirAdmin();
      return true;
    }
    return false;
  }

  function registerAdminShortcut() {
    if (window._vrAdminShortcutRegistered) return;
    window._vrAdminShortcutRegistered = true;
    document.addEventListener(
      "keydown",
      function (e) {
        if (!isAdminShortcut(e)) return;
        if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable)) {
          /* ainda permite — admin é global */
        }
        e.preventDefault();
        e.stopPropagation();
        if (!toggleAdminPanel()) {
          setTimeout(function () {
            toggleAdminPanel();
          }, 200);
        }
      },
      true
    );
  }

  function patchAdminToggle() {
    var wrap = function (name, after) {
      var tries = 0;
      function attempt() {
        var orig = window[name];
        if (typeof orig === "function" && !orig._vrShortcutPatched) {
          window[name] = function () {
            var r = orig.apply(this, arguments);
            after();
            return r;
          };
          window[name]._vrShortcutPatched = true;
          return;
        }
        if (++tries < 80) setTimeout(attempt, 150);
      }
      attempt();
    };
    wrap("abrirAdmin", function () {
      var o = document.getElementById("admin-overlay");
      if (o) o.style.zIndex = "100002";
      document.body.classList.add("vr-admin-open");
    });
    wrap("fecharAdmin", function () {
      document.body.classList.remove("vr-admin-open");
    });
  }

  function esc(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function getSenha() {
    try {
      return sessionStorage.getItem("radar_admin_senha") || "";
    } catch (_) {
      return "";
    }
  }

  function setSenha(v) {
    try {
      if (v) sessionStorage.setItem("radar_admin_senha", v);
      else sessionStorage.removeItem("radar_admin_senha");
    } catch (_) {}
  }

  function authHeaders() {
    var h = { "Content-Type": "application/json" };
    try {
      var t = localStorage.getItem("radar_jwt");
      if (t) h.Authorization = "Bearer " + t;
    } catch (_) {}
    return h;
  }

  async function postAdmin(action, extra) {
    var senha = getSenha();
    if (!senha) throw new Error("Senha admin ausente");
    var body = Object.assign({ action: action, admin_senha: senha }, extra || {});
    var r = await fetch(API, {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return r.json();
  }

  function skeletonBlock(rows) {
    var n = rows || 4;
    var bars = "";
    for (var i = 0; i < n; i++) {
      bars +=
        '<div class="vr-sk-row">' +
        '<span class="vr-sk-line" style="width:' +
        (40 + (i % 3) * 15) +
        '%"></span>' +
        '<span class="vr-sk-line vr-sk-short"></span>' +
        "</div>";
    }
    return '<div class="vr-skeleton">' + bars + "</div>";
  }

  function injectBaseStyles() {
    if (document.getElementById("vr-admin-shared-css")) return;
    var s = document.createElement("style");
    s.id = "vr-admin-shared-css";
    s.textContent =
      ".vr-skeleton{padding:8px 0}" +
      ".vr-sk-row{display:flex;gap:10px;align-items:center;padding:8px 0;border-bottom:1px solid #0D2438}" +
      ".vr-sk-line{display:block;height:10px;border-radius:3px;background:linear-gradient(90deg,#0D2438 25%,#1a3a52 50%,#0D2438 75%);background-size:200% 100%;animation:vr-sk-pulse 1.2s ease-in-out infinite}" +
      ".vr-sk-short{width:48px;flex-shrink:0;margin-left:auto}" +
      "@keyframes vr-sk-pulse{0%{background-position:100% 0}100%{background-position:-100% 0}}" +
      "@media(prefers-reduced-motion:reduce){.vr-sk-line{animation:none;background:#1a3a52}}" +
      ".uso-kpi-value,.uso-evento-count,.uso-rank-count,.uso-ret-val{font-variant-numeric:tabular-nums}" +
      ".uso-heatmap td{transition:background .15s ease}" +
      ".uso-vis-btn:focus-visible,.admin-tab-btn:focus-visible,.admin-btn:focus-visible{outline:2px solid #64748B;outline-offset:2px}" +
      "#admin-overlay{z-index:100002!important}" +
      "#admin-overlay.vis{display:flex!important}" +
      "body.vr-admin-open #publicHome{pointer-events:none}";
    document.head.appendChild(s);
  }

  function wrapWhenReady(name, wrapper) {
    var tries = 0;
    function attempt() {
      var orig = window[name];
      if (typeof orig === "function" && !orig._vrWrapped) {
        var wrapped = wrapper(orig);
        wrapped._vrWrapped = true;
        window[name] = wrapped;
        return true;
      }
      if (++tries < 80) setTimeout(attempt, 150);
      return false;
    }
    attempt();
  }

  window.VRAdminShared = {
    API: API,
    esc: esc,
    getSenha: getSenha,
    setSenha: setSenha,
    authHeaders: authHeaders,
    postAdmin: postAdmin,
    skeletonBlock: skeletonBlock,
    injectBaseStyles: injectBaseStyles,
    wrapWhenReady: wrapWhenReady,
  };

  injectBaseStyles();
  registerAdminShortcut();
  patchAdminToggle();
})();