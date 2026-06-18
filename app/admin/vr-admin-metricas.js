/**
 * VIX Radar — Admin Métricas (Fase 2)
 * Enhancement layer sobre adminCarregarMetricas do core
 * v201.67
 */
(function () {
  "use strict";

  var S = window.VRAdminShared || {};
  var skeleton = S.skeletonBlock || function () {
    return '<div class="uso-loading">Carregando métricas…</div>';
  };
  var wrap = S.wrapWhenReady || function (n, w) {
    var o = window[n];
    if (typeof o === "function") window[n] = w(o);
  };

  function injectMetStyles() {
    if (document.getElementById("vr-admin-met-css")) return;
    var s = document.createElement("style");
    s.id = "vr-admin-met-css";
    s.textContent =
      "#admin-tab-metricas .met-block{border:1px solid #0D2438;border-radius:6px;padding:12px;margin-bottom:10px;background:#000D1A}" +
      "#admin-tab-metricas .met-snap{font-variant-numeric:tabular-nums;font-size:18px;font-weight:700;color:#EDE8D8}" +
      "#admin-tab-metricas .met-intro{font-size:11px;color:#94A3B8;line-height:1.6;margin-bottom:12px;padding:10px;border:1px solid #0D2438;border-radius:6px;background:#001528}" +
      "#admin-tab-metricas .met-formula{font-family:'IBM Plex Mono',ui-monospace,monospace;font-size:9px;color:#64748B;white-space:pre-line;margin:8px 0;padding:8px;background:#001020;border-radius:4px}";
    document.head.appendChild(s);
  }

  function patchMetricas() {
    wrap("adminCarregarMetricas", function (orig) {
      return function () {
        var el = document.getElementById("met-conteudo");
        if (el) el.innerHTML = skeleton(6);
        try {
          orig.apply(this, arguments);
        } catch (e) {
          if (el) {
            el.innerHTML =
              '<div class="uso-erro">Erro ao calcular métricas: ' +
              (S.esc ? S.esc(e.message || e) : String(e)) +
              "</div>";
          }
        }
      };
    });
  }

  function init() {
    injectMetStyles();
    patchMetricas();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();