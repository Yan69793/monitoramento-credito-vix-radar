/**
 * VIX Radar — entrada leve carregada por todo visitante (substitui o admin-bootstrap
 * eager, VXADMINLAZY1). Tres responsabilidades, nenhuma com timer de rede:
 *   1. skip link acessivel (foca o conteudo visivel: painel ou landing);
 *   2. admin sob demanda: importa ../admin-bootstrap.js so com sessao, no atalho
 *      ou quando o painel abre. O atalho e o botao continuam no index.html (gate 3.4);
 *   3. feature flag por tela: a v2 so e importada se alguma tela estiver em v2.
 */
import { telasEmV2, aplicarFlagsDaUrl } from './core/flags.js';

window.__vxMainOk = true; // modulo liberado ~0,4 s apos o primeiro paint (VXLCP2)
/* ---------- 1. skip link ---------- */
document.addEventListener('click', (e) => {
  const a = e.target.closest && e.target.closest('[data-vx-skip]');
  if (!a) return;
  e.preventDefault();
  const ph = document.getElementById('publicHome');
  const landing = ph && getComputedStyle(ph).display !== 'none';
  const alvos = landing ? ['#publicHome h1:not([hidden])', '#publicHome main', '#publicHome'] : ['#vx2-root.vx-on .vx-main', '#main'];
  for (const sel of alvos) {
    const el = [...document.querySelectorAll(sel)].find((x) => x.offsetParent !== null);
    if (el) {
      if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '-1');
      el.focus();
      return;
    }
  }
});

/* ---------- 2. admin sob demanda ---------- */
let adminPromise = null;
export function carregarAdmin() {
  if (!adminPromise) {
    adminPromise = import('../admin-bootstrap.js?v=202.77').catch((err) => {
      adminPromise = null;
      console.error('[vx] falha ao carregar modulos admin', err);
    });
  }
  return adminPromise;
}
window.__vxCarregarAdmin = carregarAdmin;
function temSessao() {
  try { return !!localStorage.getItem('radar_user'); } catch (_) { return false; }
}
// Atalho admin: mesma familia de chord do index.html (Ctrl/Cmd + Shift|Alt + A).
document.addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && (e.shiftKey || e.altKey) && (e.key === 'A' || e.key === 'a')) carregarAdmin();
}, true);
// Botao em Configuracoes e qualquer clique que abra o overlay admin.
document.addEventListener('click', (e) => {
  if (e.target.closest && e.target.closest('#config-admin-entry, [onclick*="abrirAdmin"]')) carregarAdmin();
}, true);
// Usuario logado mantem o comportamento anterior (modulos carregados), sem pesar na landing.
if (temSessao()) {
  const cedo = () => carregarAdmin();
  if ('requestIdleCallback' in window) requestIdleCallback(cedo, { timeout: 4000 }); else window.addEventListener('load', cedo, { once: true });
}

/* ---------- 3. v2 atras de flag ---------- */
aplicarFlagsDaUrl();
if (telasEmV2().length) {
  import('./app.js').then((m) => m.iniciar()).catch((err) => console.error('[vx] v2 falhou ao iniciar, v1 segue ativa', err));
}
