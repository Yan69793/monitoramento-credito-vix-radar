/**
 * VIX Radar — Admin modular (HEART + endpoints)
 * v201.68 — HEART + reengajamento + sparklines
 * Depende: abrirAdmin, adminAbaAtiva, adminAutenticar (core index.html)
 */
(function () {
  "use strict";

  var API = typeof API_BASE !== "undefined" ? API_BASE : "https://api.vixradar.com";

  function esc(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function getSenha() {
    try {
      return localStorage.getItem("radar_admin_senha") || "";
    } catch (_) {
      return "";
    }
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

  async function fetchHealth() {
    var r = await fetch(API, { cache: "no-store" });
    return r.json();
  }

  async function fetchHeartbeats() {
    var r = await fetch(API + "?action=heartbeats", {
      headers: authHeaders(),
      cache: "no-store",
    });
    if (r.status === 401 && typeof _tratarSessaoExpirada === "function") {
      _tratarSessaoExpirada(r);
      return null;
    }
    return r.json();
  }

  /* ── HEART metrics ───────────────────────────────────── */
  function calcHeart(users, retencao, overview) {
    var aprovados = users.filter(function (u) {
      return u.status === "aprovado";
    });
    var retMap = {};
    (retencao || []).forEach(function (r) {
      retMap[r.email] = r;
    });
    var active7 = 0;
    var active30 = 0;
    aprovados.forEach(function (u) {
      var r = retMap[u.email];
      if (!r) return;
      if ((r.eventos_7d || 0) > 0) active7++;
      if ((r.eventos_30d || 0) > 0) active30++;
    });
    var ev = {};
    (overview || []).forEach(function (o) {
      ev[o.evento] = o.total || 0;
    });
    var logins = ev.login || 0;
    var consultas = ev.consulta_empresa || 0;
    var aberturas = ev.abertura_analise || 0;
    var adoption = aprovados.length
      ? Math.round((aprovados.length / Math.max(users.length, 1)) * 100)
      : 0;
    var retention = aprovados.length
      ? Math.round((active30 / aprovados.length) * 100)
      : 0;
    var engagement = Math.min(100, Math.round((logins + consultas) / 2));
    var taskSuccess =
      aberturas > 0 ? Math.min(100, Math.round((consultas / aberturas) * 100)) : consultas > 0 ? 75 : 0;
    var happiness = aprovados.length
      ? Math.min(100, Math.round((active7 / aprovados.length) * 100) + (retention > 50 ? 10 : 0))
      : 0;

    return {
      happiness: happiness,
      engagement: engagement,
      adoption: adoption,
      retention: retention,
      taskSuccess: taskSuccess,
      meta: {
        aprovados: aprovados.length,
        active7: active7,
        active30: active30,
        logins: logins,
        consultas: consultas,
      },
    };
  }

  var HEART_HIST_KEY = "vr_heart_history_v1";

  function saveHeartHistory(heart) {
    try {
      var hist = JSON.parse(localStorage.getItem(HEART_HIST_KEY) || "[]");
      hist.push({
        ts: Date.now(),
        h: heart.happiness,
        e: heart.engagement,
        a: heart.adoption,
        r: heart.retention,
        t: heart.taskSuccess,
      });
      if (hist.length > 14) hist = hist.slice(-14);
      localStorage.setItem(HEART_HIST_KEY, JSON.stringify(hist));
      return hist;
    } catch (_) {
      return [];
    }
  }

  function getHeartHistory() {
    try {
      return JSON.parse(localStorage.getItem(HEART_HIST_KEY) || "[]");
    } catch (_) {
      return [];
    }
  }

  function renderSparkline(values, w, h) {
    if (!values || values.length < 2) return "";
    var min = Math.min.apply(null, values);
    var max = Math.max.apply(null, values);
    var range = max - min || 1;
    var pts = values
      .map(function (v, i) {
        var x = (i / (values.length - 1)) * w;
        var y = h - ((v - min) / range) * (h - 4) - 2;
        return x.toFixed(1) + "," + y.toFixed(1);
      })
      .join(" ");
    return (
      '<svg class="vr-spark" width="' +
      w +
      '" height="' +
      h +
      '" viewBox="0 0 ' +
      w +
      " " +
      h +
      '" aria-hidden="true"><polyline fill="none" stroke="currentColor" stroke-width="1.5" points="' +
      pts +
      '"/></svg>'
    );
  }

  function renderHeartKpis(heart, hist) {
    var items = [
      { key: "H", label: "Happiness", val: heart.happiness, hint: "Ativos 7d / aprovados", field: "h" },
      { key: "E", label: "Engagement", val: heart.engagement, hint: "Logins + consultas (30d)", field: "e" },
      { key: "A", label: "Adoption", val: heart.adoption, hint: "Aprovados / total cadastros", field: "a" },
      { key: "R", label: "Retention", val: heart.retention, hint: "Com eventos 30d", field: "r" },
      { key: "T", label: "Task success", val: heart.taskSuccess, hint: "Consultas / aberturas", field: "t" },
    ];
    var history = hist || getHeartHistory();
    return (
      '<div class="vr-heart-row">' +
      items
        .map(function (it) {
          var col = it.val >= 70 ? "ok" : it.val >= 40 ? "mid" : "low";
          var series = history.map(function (row) {
            return row[it.field];
          });
          return (
            '<div class="vr-heart-kpi ' +
            col +
            '" title="' +
            esc(it.hint) +
            '">' +
            '<span class="vr-heart-letter">' +
            it.key +
            "</span>" +
            '<span class="vr-heart-val">' +
            it.val +
            "%</span>" +
            renderSparkline(series, 56, 18) +
            '<span class="vr-heart-lbl">' +
            esc(it.label) +
            "</span></div>"
          );
        })
        .join("") +
      "</div>"
    );
  }

  async function sendReengage(emails, btn) {
    if (!emails || !emails.length) return;
    var label = btn && btn.textContent;
    if (
      !window.confirm(
        "Enviar boletim de reengajamento para " + emails.length + " usuário(s)?\n\n" + emails.join("\n")
      )
    ) {
      return;
    }
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Enviando…";
    }
    try {
      var r = await postAdmin("newsletter_envio_direcionado", { destinatarios: emails });
      var out = document.getElementById("vr-dry-out");
      if (out) {
        out.hidden = false;
        out.textContent = JSON.stringify(r, null, 2);
      }
      if (r.ok) {
        alert("Boletim enviado para " + emails.length + " destinatário(s).");
      } else {
        alert("Falha: " + (r.erro || "erro desconhecido"));
      }
    } catch (e) {
      alert("Erro: " + (e.message || e));
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = label || "Enviar";
      }
    }
  }

  function daysSince(iso) {
    if (!iso) return null;
    var d = new Date(iso);
    if (isNaN(d.getTime())) return null;
    return Math.floor((Date.now() - d.getTime()) / 86400000);
  }

  function renderUserHealth(users, retencao) {
    var retMap = {};
    (retencao || []).forEach(function (r) {
      retMap[r.email] = r;
    });
    var rows = users
      .slice()
      .sort(function (a, b) {
        return (a.status || "").localeCompare(b.status || "") || (a.email || "").localeCompare(b.email || "");
      })
      .map(function (u) {
        var r = retMap[u.email] || {};
        var ult = r.ultimo_acesso || "";
        var dias = daysSince(ult);
        var stale = u.status === "aprovado" && (dias === null || dias > 30);
        var pill =
          u.status === "aprovado"
            ? stale
              ? "warn"
              : "ok"
            : u.status === "pendente"
              ? "pend"
              : "no";
        return (
          "<tr" +
          (stale ? ' class="vr-stale"' : "") +
          ">" +
          "<td><span class=\"vr-pill " +
          pill +
          '">' +
          esc(u.status) +
          "</span></td>" +
          "<td class=\"vr-mono\">" +
          esc(u.email) +
          "</td>" +
          "<td>" +
          esc(u.nome || "—") +
          "</td>" +
          '<td class="vr-num">' +
          (r.eventos_30d != null ? r.eventos_30d : "—") +
          "</td>" +
          '<td class="vr-mono vr-muted">' +
          (ult ? esc(String(ult).slice(0, 16)) : "sem telemetria") +
          (dias != null ? ' <span class="vr-muted">(' + dias + "d)</span>" : "") +
          "</td>" +
          "<td>" +
          (stale
            ? '<button type="button" class="vr-btn-mini vr-btn-reengage-one" data-email="' +
              esc(u.email) +
              '">Boletim</button>'
            : '<span class="vr-muted">—</span>') +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
    return (
      '<div class="vr-table-wrap"><table class="vr-admin-table">' +
      "<thead><tr><th>Status</th><th>E-mail</th><th>Nome</th><th>30d</th><th>Último acesso</th><th>Ação</th></tr></thead>" +
      "<tbody>" +
      rows +
      "</tbody></table></div>"
    );
  }

  function renderHeartbeats(hb) {
    if (!hb || !hb.heartbeats) return '<p class="vr-muted">Sem heartbeats.</p>';
    var entries = Object.keys(hb.heartbeats)
      .map(function (k) {
        var v = hb.heartbeats[k];
        return { k: k, v: v, ts: v && v.ts ? new Date(v.ts).getTime() : 0 };
      })
      .sort(function (a, b) {
        return b.ts - a.ts;
      })
      .slice(0, 12);
    return (
      '<ul class="vr-hb-list">' +
      entries
        .map(function (e) {
          var st = (e.v && e.v.status) || "?";
          var cls = st === "ok" ? "ok" : st === "alerta" || st === "erro" ? "err" : "mid";
          return (
            '<li class="vr-hb-item ' +
            cls +
            '"><span class="vr-hb-agent">' +
            esc(e.k) +
            '</span><span class="vr-hb-st">' +
            esc(st) +
            '</span><span class="vr-hb-ts">' +
            esc(e.v && e.v.ts ? String(e.v.ts).slice(0, 19) : "") +
            "</span></li>"
          );
        })
        .join("") +
      "</ul>"
    );
  }

  /* ── Tab: Hoje (HEART dashboard) ─────────────────────── */
  async function loadHoje() {
    var el = document.getElementById("vr-admin-hoje");
    if (!el) return;
    el.innerHTML = '<div class="vr-loading">Carregando painel HEART…</div>';
    try {
      var usersRes = await postAdmin("admin_listar", {});
      var usoOv = await postAdmin("uso", { visao: "overview" });
      var usoRet = await postAdmin("uso", { visao: "retencao" });
      var health = await fetchHealth();
      var hb = await fetchHeartbeats();
      var dry = await postAdmin("relatorio_dry_run", {});

      if (!usersRes.ok) throw new Error(usersRes.erro || "admin_listar falhou");
      var users = usersRes.usuarios || [];
      var overview = (usoOv.data || []).slice();
      var retencao = usoRet.data || [];
      var heart = calcHeart(users, retencao, overview);
      var hist = saveHeartHistory(heart);

      var stale = users.filter(function (u) {
        if (u.status !== "aprovado") return false;
        var r = retencao.find(function (x) {
          return x.email === u.email;
        });
        if (!r || !r.ultimo_acesso) return true;
        var d = daysSince(r.ultimo_acesso);
        return d === null || d > 30;
      });

      el.innerHTML =
        '<div class="vr-admin-section">' +
        '<div class="vr-section-head"><h3>Hoje</h3><span class="vr-muted">Framework HEART · dados ao vivo</span></div>' +
        renderHeartKpis(heart, hist) +
        '<div class="vr-stat-grid">' +
        '<div class="vr-stat"><span class="vr-stat-val">' +
        (health.versao || "—") +
        '</span><span class="vr-stat-lbl">Worker</span></div>' +
        '<div class="vr-stat"><span class="vr-stat-val ' +
        (health.ok ? "ok" : "err") +
        '">' +
        (health.ok ? "OK" : "DEG") +
        '</span><span class="vr-stat-lbl">Health</span></div>' +
        '<div class="vr-stat"><span class="vr-stat-val">' +
        heart.meta.aprovados +
        '</span><span class="vr-stat-lbl">Aprovados</span></div>' +
        '<div class="vr-stat"><span class="vr-stat-val ' +
        (stale.length ? "warn" : "ok") +
        '">' +
        stale.length +
        '</span><span class="vr-stat-lbl">Inativos &gt;30d</span></div>' +
        '<div class="vr-stat"><span class="vr-stat-val">' +
        (dry.total_destinatarios != null ? dry.total_destinatarios : "—") +
        '</span><span class="vr-stat-lbl">E-mail semanal</span></div>' +
        "</div>" +
        (stale.length
          ? '<div class="vr-alert vr-alert-action">' +
            "<span>⚠ " +
            stale.length +
            " aprovado(s) sem login há 30+ dias.</span>" +
            '<button type="button" class="admin-btn vr-btn-reengage-all" id="vr-btn-reengage-all">Enviar boletim para inativos (' +
            stale.length +
            ")</button></div>"
          : "") +
        "<h4 class=\"vr-subhead\">Saúde por usuário</h4>" +
        renderUserHealth(users, retencao) +
        '<h4 class="vr-subhead">Operações (heartbeats)</h4>' +
        renderHeartbeats(hb) +
        '<div class="vr-actions">' +
        '<button type="button" class="admin-btn" id="vr-btn-dry-run">Dry-run relatório</button>' +
        '<button type="button" class="admin-btn" id="vr-btn-refresh-hoje">Atualizar</button>' +
        "</div>" +
        '<pre id="vr-dry-out" class="vr-pre" hidden></pre>' +
        "</div>";

      var btnDry = document.getElementById("vr-btn-dry-run");
      var btnRef = document.getElementById("vr-btn-refresh-hoje");
      if (btnRef) btnRef.onclick = loadHoje;
      if (btnDry)
        btnDry.onclick = async function () {
          var out = document.getElementById("vr-dry-out");
          try {
            var d = await postAdmin("relatorio_dry_run", {});
            if (out) {
              out.hidden = false;
              out.textContent = JSON.stringify(d, null, 2);
            }
          } catch (e) {
            if (out) {
              out.hidden = false;
              out.textContent = String(e.message || e);
            }
          }
        };

      var staleEmails = stale.map(function (u) {
        return u.email;
      });
      var btnAll = document.getElementById("vr-btn-reengage-all");
      if (btnAll)
        btnAll.onclick = function () {
          sendReengage(staleEmails.slice(0, 25), btnAll);
        };
      document.querySelectorAll(".vr-btn-reengage-one").forEach(function (b) {
        b.onclick = function () {
          var em = b.getAttribute("data-email");
          if (em) sendReengage([em], b);
        };
      });
    } catch (e) {
      el.innerHTML =
        '<div class="admin-msg err">Erro: ' + esc(e.message || e) + "</div>";
    }
  }

  /* ── Inject UI ───────────────────────────────────────── */
  function injectStyles() {
    if (document.getElementById("vr-admin-modules-css")) return;
    var s = document.createElement("style");
    s.id = "vr-admin-modules-css";
    s.textContent =
      "#admin-tab-hoje.vr-admin-tab-pane{display:none}" +
      "#admin-tab-hoje.vr-admin-tab-pane.active{display:block}" +
      ".vr-heart-row{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px;margin:12px 0 16px}" +
      ".vr-heart-kpi{padding:10px 8px;border:1px solid #0D2438;border-radius:6px;background:#000D1A;text-align:center}" +
      ".vr-heart-kpi.ok{border-color:#166534}.vr-heart-kpi.mid{border-color:#854D0E}.vr-heart-kpi.low{border-color:#7F1D1D}" +
      ".vr-heart-letter{font-size:10px;font-weight:700;color:#64748B;letter-spacing:.08em;display:block}" +
      ".vr-heart-val{font-size:20px;font-weight:700;font-variant-numeric:tabular-nums;color:#EDE8D8;display:block;line-height:1.2}" +
      ".vr-heart-lbl{font-size:9px;color:#64748B;display:block;margin-top:2px}" +
      ".vr-spark{display:block;margin:4px auto 2px;color:#475569;opacity:.85}" +
      ".vr-heart-kpi.ok .vr-spark{color:#34D399}.vr-heart-kpi.mid .vr-spark{color:#FBBF24}.vr-heart-kpi.low .vr-spark{color:#F87171}" +
      ".vr-btn-mini{font-size:9px;font-weight:600;padding:3px 7px;border-radius:4px;border:1px solid #334155;background:#0D2438;color:#94A3B8;cursor:pointer}" +
      ".vr-btn-mini:hover{color:#EDE8D8;border-color:#475569}" +
      ".vr-btn-mini:disabled{opacity:.5;cursor:not-allowed}" +
      ".vr-alert-action{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}" +
      ".vr-stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:8px;margin:12px 0}" +
      ".vr-stat{padding:8px;border:1px solid #0D2438;border-radius:5px;background:#001528}" +
      ".vr-stat-val{font-size:14px;font-weight:700;font-variant-numeric:tabular-nums;display:block;color:#C8D5DF}" +
      ".vr-stat-val.ok{color:#34D399}.vr-stat-val.warn{color:#FBBF24}.vr-stat-val.err{color:#EF4444}" +
      ".vr-stat-lbl{font-size:9px;color:#64748B;text-transform:uppercase;letter-spacing:.06em}" +
      ".vr-table-wrap{overflow:auto;max-height:280px;border:1px solid #0D2438;border-radius:6px}" +
      ".vr-admin-table{width:100%;border-collapse:collapse;font-size:11px}" +
      ".vr-admin-table th{position:sticky;top:0;background:#001528;color:#64748B;text-align:left;padding:6px 8px;font-weight:600}" +
      ".vr-admin-table td{padding:6px 8px;border-top:1px solid #0D2438;color:#C8D5DF}" +
      ".vr-admin-table tr.vr-stale td{background:rgba(127,29,29,.12)}" +
      ".vr-pill{font-size:9px;font-weight:700;padding:2px 6px;border-radius:3px;text-transform:uppercase}" +
      ".vr-pill.ok{background:#14532d;color:#86efac}.vr-pill.warn{background:#713f12;color:#fde68a}" +
      ".vr-pill.pend{background:#1e3a5f;color:#93c5fd}.vr-pill.no{background:#3f1212;color:#fca5a5}" +
      ".vr-mono{font-family:'IBM Plex Mono',ui-monospace,monospace;font-size:10px}" +
      ".vr-num{font-variant-numeric:tabular-nums;text-align:right}" +
      ".vr-muted{color:#64748B!important;font-size:10px}" +
      ".vr-subhead{font-size:11px;font-weight:700;color:#94A3B8;margin:16px 0 8px;letter-spacing:.04em}" +
      ".vr-section-head{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:4px}" +
      ".vr-section-head h3{margin:0;font-size:13px;color:#EDE8D8}" +
      ".vr-alert{padding:8px 10px;border-radius:5px;background:#451a1a;border:1px solid #7f1d1d;color:#fecaca;font-size:11px;margin:8px 0}" +
      ".vr-hb-list{list-style:none;margin:0;padding:0;font-size:11px}" +
      ".vr-hb-item{display:flex;gap:8px;padding:5px 0;border-bottom:1px solid #0D2438}" +
      ".vr-hb-agent{flex:1;color:#C8D5DF}.vr-hb-st{font-weight:700;text-transform:uppercase;font-size:9px}" +
      ".vr-hb-item.ok .vr-hb-st{color:#34D399}.vr-hb-item.err .vr-hb-st{color:#EF4444}.vr-hb-item.mid .vr-hb-st{color:#94A3B8}" +
      ".vr-hb-ts{color:#64748B;font-family:monospace;font-size:9px}" +
      ".vr-actions{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}" +
      ".vr-pre{font-size:10px;background:#000D1A;border:1px solid #0D2438;padding:8px;border-radius:5px;overflow:auto;max-height:160px;color:#94A3B8}" +
      ".vr-loading{color:#64748B;font-size:12px;padding:16px}" +
      "@media(max-width:720px){.vr-heart-row{grid-template-columns:repeat(2,1fr)}}" +
      "@media(prefers-reduced-motion:reduce){.vr-heart-kpi{transition:none}}";
    document.head.appendChild(s);
  }

  function injectHojeTab() {
    var painel = document.getElementById("admin-painel");
    var tabs = painel && painel.querySelector(".admin-tabs");
    if (!tabs || document.getElementById("admin-tab-hoje")) return;

    var btn = document.createElement("button");
    btn.className = "admin-tab-btn";
    btn.textContent = "Hoje";
    btn.onclick = function () {
      if (typeof adminAbaAtiva === "function") adminAbaAtiva("hoje", btn);
      loadHoje();
    };
    tabs.insertBefore(btn, tabs.firstChild);

    var pane = document.createElement("div");
    pane.id = "admin-tab-hoje";
    pane.className = "admin-tab-pane vr-admin-tab-pane";
    pane.innerHTML = '<div id="vr-admin-hoje"></div>';
    painel.insertBefore(pane, painel.querySelector(".admin-tab-pane"));

    var origAba = window.adminAbaAtiva;
    if (origAba && !window._vrAdminAbaPatched) {
      window._vrAdminAbaPatched = true;
      window.adminAbaAtiva = function (id, el) {
        origAba(id, el);
        if (id === "hoje") loadHoje();
      };
    }
  }

  function patchAuth() {
    var orig = window.adminAutenticar;
    if (!orig || window._vrAdminAuthPatched) return;
    window._vrAdminAuthPatched = true;
    window.adminAutenticar = async function () {
      var inp = document.getElementById("admin-senha-input");
      if (inp && inp.value.trim()) {
        try {
          localStorage.setItem("radar_admin_senha", inp.value.trim());
        } catch (_) {}
      }
      await orig.apply(this, arguments);
      injectHojeTab();
      loadHoje();
    };
  }

  function patchOpen() {
    var orig = window.abrirAdmin;
    if (!orig || window._vrAdminOpenPatched) return;
    window._vrAdminOpenPatched = true;
    window.abrirAdmin = function () {
      orig.apply(this, arguments);
      setTimeout(function () {
        injectHojeTab();
        var painel = document.getElementById("admin-painel");
        if (painel && painel.style.display !== "none") loadHoje();
      }, 200);
    };
  }

  function init() {
    injectStyles();
    patchAuth();
    patchOpen();
    if (document.getElementById("admin-painel")) injectHojeTab();
  }

  window.VRAdmin = {
    loadHoje: loadHoje,
    calcHeart: calcHeart,
    postAdmin: postAdmin,
    sendReengage: sendReengage,
    getHeartHistory: getHeartHistory,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();