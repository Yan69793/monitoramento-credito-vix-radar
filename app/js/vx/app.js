/**
 * Shell da v2: raiz isolada (#vx2-root) por cima da v1, roteador por hash, barra
 * inferior no mobile, atalhos e recarga SO por gatilho do usuario (AUTONOMIAOFF1:
 * carga inicial, botao Atualizar, visibilitychange e pageshow; nenhum timer).
 * A v1 continua carregada por baixo: login, sessao, admin, PDF, Novo Pulso,
 * comentarios e comparador seguem nela e sao abertos por delegacao.
 */
import { versaoDaTela } from './core/flags.js';
import { esc, lerRota, montarRota, fmtDataHora, num } from './core/util.js';
import * as D from './core/data.js';
import { renderEventos } from './screens/eventos.js';
import { renderEmpresas } from './screens/empresas.js';
import { renderEmissor } from './screens/emissor.js';

const S = {
  carregando: false, carregadoEm: null,
  estado: null, ews: null, anom: null, health: null,
  erros: {}, uni: D.universo(),
  cacheSerie: {}, cacheEwsEmp: {},
};
let root, main, ultimoFoco = null;

function sessaoAtiva() { try { return !!localStorage.getItem('radar_user'); } catch (_) { return false; } }
function landingVisivel() { const p = document.getElementById('publicHome'); return !!(p && p.offsetParent !== null && getComputedStyle(p).display !== 'none'); }

function telaDaRota(r) { return r.tela === 'empresa' || r.tela === 'empresas' ? 'empresas' : (r.tela === 'eventos' || r.tela === '' ? 'eventos' : r.tela); }

export function ctx() {
  return {
    S, uni: S.uni, setorDe: S.uni.setorDe, livro: D.livro(), favs: D.favoritos(), favOn: D.favoritosHabilitados(),
    ir, recarregar, abrirV1, alternarFav,
  };
}

export function ir(hash, { substituir = false } = {}) {
  if (substituir) history.replaceState(null, '', hash); else if (location.hash !== hash) history.pushState(null, '', hash);
  render();
}

async function alternarFav(empresa) {
  try { await D.alternarFavorito(empresa); } catch (e) { console.warn('[vx] favorito', e); }
  render();
}

/** Delega uma acao que so existe na v1 (comentarios, PDF, Novo Pulso, comparador, agenda...). */
export function abrirV1(acao, empresa) {
  esconder();
  history.pushState(null, '', '#/classico');
  try {
    if (empresa && typeof window.selecionar === 'function') window.selecionar(empresa);
    const f = {
      pdf: window.abrirSeletorPDF, pulso: window.abrirModalVarredura, share: window.abrirModalShare,
      comparar: window.compararAbrir, agenda: window.agendaAbrir, config: window.mostrarConfig, carteira: window.carteiraAbrir,
    }[acao];
    if (typeof f === 'function') f();
  } catch (e) { console.warn('[vx] acao v1', acao, e); }
  mostrarBotaoVoltar();
}

function mostrarBotaoVoltar() {
  let b = document.getElementById('vx2-voltar');
  if (!b) {
    b = document.createElement('button');
    b.id = 'vx2-voltar'; b.type = 'button';
    b.textContent = 'Voltar à nova interface';
    b.style.cssText = 'position:fixed;right:16px;bottom:calc(76px + env(safe-area-inset-bottom,0px));z-index:899;background:#B7985D;color:#001020;border:0;border-radius:6px;padding:12px 16px;font:600 13px Inter,system-ui,sans-serif;min-height:44px;cursor:pointer';
    b.addEventListener('click', () => { b.remove(); ir('#/eventos'); });
    document.body.appendChild(b);
  }
}

function esconder() { if (root) { root.classList.remove('vx-on'); root.setAttribute('aria-hidden', 'true'); } document.documentElement.style.overflow = ''; }

/* ---------- dados ---------- */
export async function recarregar() {
  if (S.carregando || !sessaoAtiva()) return;
  S.carregando = true; render();
  const tarefas = {
    estado: D.carregarEstado(), ews: D.carregarEWS(), anom: D.carregarAnomalias(), health: D.carregarHealth(),
  };
  const nomes = Object.keys(tarefas);
  const res = await Promise.allSettled(Object.values(tarefas));
  res.forEach((r, i) => {
    const k = nomes[i];
    if (r.status === 'fulfilled') { S[k] = r.value; delete S.erros[k]; } else { S.erros[k] = (r.reason && r.reason.message) || 'falha'; }
  });
  S.cacheSerie = {}; S.cacheEwsEmp = {};
  S.carregando = false; S.carregadoEm = new Date();
  render();
}

/* ---------- selo de frescor e cobertura (9.13) ---------- */
function selo() {
  const h = S.health;
  if (!h) return `<div class="vx-selo" role="status"><span><span class="vx-dot nd"></span>${S.erros.health ? 'Saúde da base indisponível: ' + esc(S.erros.health) : 'Lendo a saúde da base…'}</span></div>`;
  const fresco = h.painel_fresco === true; const sabe = typeof h.painel_fresco === 'boolean';
  const def = h.painel_emissores_deferidos; const tot = h.painel_emissores_total;
  const analise = (typeof def === 'number' && typeof tot === 'number')
    ? `Última rodada de análise: <b class="vx-num">${num(tot - def)}</b> de <b class="vx-num">${num(tot)}</b> analisados, <b class="vx-num">${num(def)}</b> deferidos. Conclusão integral não verificada.`
    : 'Conclusão da análise: não verificada (o health não informa deferidos).';
  const rec = h.cvm_ingestao_recebidos, atr = h.cvm_ingestao_atribuidos;
  const cnpj = h.cvm_atribuicao_por_cnpj, nome = h.cvm_atribuicao_por_nome, qa = h.cvm_atribuicao_quarentena;
  const atribuivel = [cnpj, nome, qa].every((x) => typeof x === 'number') ? cnpj + nome + qa : null;
  const pctRec = (typeof rec === 'number' && rec > 0 && typeof atr === 'number') ? (atr / rec * 100) : null;
  return `<div class="vx-selo" role="status" aria-label="Frescor e cobertura da base">
    <span><span class="vx-dot ${sabe ? (fresco ? 'ok' : 'atrasado') : 'nd'}"></span>Estado do painel atualizado em <b>${esc(fmtDataHora(h.painel_atualizado_em))}</b> · ${sabe ? (fresco ? 'dentro do prazo' : 'atrasado') : 'frescor não informado'}</span>
    <span>${analise}</span>
    <span title="Fonte: health do Worker (${esc(h.versao || '')}), lido em ${esc(fmtDataHora(h.ts))}">Documentos CVM: <b class="vx-num">${num(rec)}</b> recebidos · <b class="vx-num">${num(atr)}</b> atribuídos (${pctRec == null ? '—' : num(pctRec, 1) + '%'} dos recebidos) · <b class="vx-num">${num(h.cvm_ingestao_quarentena)}</b> em quarentena · <b class="vx-num">${num(h.cvm_atribuicao_sem_dono)}</b> sem identificação · cobertura do universo atribuível <b class="vx-num">${num(h.cvm_atribuicao_cobertura_pct, 1)}%</b> = ${num((cnpj || 0) + (nome || 0))}/${num(atribuivel)} (CNPJ + nome sobre CNPJ + nome + quarentena) · fonte: health ${esc(fmtDataHora(h.ts))}</span>
  </div>`;
}

/* ---------- render ---------- */
/* VIX-MOBILE-20261018: icones desenhados no mesmo traco da barra da v1 (24px, stroke 1.5),
   no lugar dos caracteres unicode, que cada sistema desenha de um jeito. */
const svgIc = (d) => `<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const ICONE = {
  eventos: svgIc('<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>'),
  empresas: svgIc('<path d="M4 21V5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16"/><path d="M15 9h4a1 1 0 0 1 1 1v11"/><path d="M3 21h18"/><path d="M8 8h3M8 12h3M8 16h3"/>'),
  busca: svgIc('<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>'),
  livro: svgIc('<path d="M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1z"/>'),
  mais: svgIc('<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>'),
};
function shell(rota, tela) {
  const atual = (t) => (tela === t ? ' aria-current="page"' : '');
  return `
  <header class="vx-top">
    <span class="vx-brand">VIX Radar</span>
    <nav class="vx-tabs-top" aria-label="Telas">
      <button type="button" class="vx-tab-top" data-ir="#/eventos"${atual('eventos')}>Painel de Eventos</button>
      <button type="button" class="vx-tab-top" data-ir="#/empresas"${atual('empresas')}>Empresas</button>
    </nav>
    <form class="vx-search" role="search" data-busca>
      <label class="vx-sr" for="vx-busca">Buscar emissor ou evento</label>
      <input id="vx-busca" type="search" autocomplete="off" placeholder="Buscar emissor ou evento  ( / )" value="${esc(rota.q.get('q') || '')}">
    </form>
    <div class="vx-top-actions">
      <button type="button" class="vx-btn" data-acao="atualizar" ${S.carregando ? 'disabled aria-busy="true"' : ''}>${S.carregando ? 'Atualizando…' : 'Atualizar'}</button>
      <button type="button" class="vx-btn vx-hide-m" data-v1="agenda">Agenda</button>
      <button type="button" class="vx-btn vx-hide-m" data-acao="classico">Versão clássica</button>
    </div>
  </header>
  ${selo()}
  <main class="vx-main" id="vx-main" tabindex="-1"><div class="vx-wrap" id="vx-tela"></div></main>
  <nav class="vx-bottom" aria-label="Navegação principal">
    <button type="button" data-ir="#/eventos"${tela === 'eventos' && !rota.q.get('livro') ? ' aria-current="page"' : ''}><span class="ic" aria-hidden="true">${ICONE.eventos}</span>Eventos</button>
    <button type="button" data-ir="#/empresas"${atual('empresas')}><span class="ic" aria-hidden="true">${ICONE.empresas}</span>Empresas</button>
    <button type="button" data-acao="busca"><span class="ic" aria-hidden="true">${ICONE.busca}</span>Busca</button>
    <button type="button" data-ir="#/eventos?livro=1"${tela === 'eventos' && rota.q.get('livro') ? ' aria-current="page"' : ''}><span class="ic" aria-hidden="true">${ICONE.livro}</span>Livro</button>
    <button type="button" data-acao="mais" aria-expanded="false" aria-controls="vx-mais"><span class="ic" aria-hidden="true">${ICONE.mais}</span>Mais</button>
  </nav>
  <div class="vx-mais" id="vx-mais">
    <button type="button" class="vx-btn" data-v1="agenda">Agenda</button>
    <button type="button" class="vx-btn" data-v1="config">Ajustes</button>
    <button type="button" class="vx-btn" data-v1="carteira">Editar meu livro</button>
    <button type="button" class="vx-btn" data-v1="pdf">PDF executivo</button>
    <button type="button" class="vx-btn" data-acao="classico">Versão clássica</button>
  </div>`;
}

export function render() {
  if (!root) return;
  const rota = lerRota();
  if (rota.tela === 'classico') { esconder(); return; }
  const tela = telaDaRota(rota);
  if (!sessaoAtiva() || landingVisivel() || versaoDaTela(tela) !== 'v2') { esconder(); return; }
  root.classList.add('vx-on'); root.removeAttribute('aria-hidden');
  document.documentElement.style.overflow = 'hidden';
  const rolagem = main ? main.scrollTop : 0;
  const foco = document.activeElement && document.activeElement.id;
  root.innerHTML = shell(rota, tela);
  main = root.querySelector('#vx-main');
  const alvo = root.querySelector('#vx-tela');
  const c = ctx();
  if (rota.tela === 'empresa' && rota.args[0]) renderEmissor(alvo, c, rota);
  else if (tela === 'empresas') renderEmpresas(alvo, c, rota);
  else renderEventos(alvo, c, rota);
  if (S.carregadoEm && !S.carregando) main.scrollTop = rolagem;
  if (foco) { const el = document.getElementById(foco); if (el) { el.focus(); if (el.setSelectionRange && el.value) el.setSelectionRange(el.value.length, el.value.length); } }
}

/* ---------- eventos globais da raiz ---------- */
function ligar() {
  root.addEventListener('click', (e) => {
    const b = e.target.closest('[data-ir],[data-acao],[data-v1]');
    if (!b || !root.contains(b)) return;
    if (b.dataset.ir) { e.preventDefault(); ir(b.dataset.ir); return; }
    if (b.dataset.v1) { abrirV1(b.dataset.v1, b.dataset.empresa || null); return; }
    const a = b.dataset.acao;
    if (a === 'atualizar') recarregar();
    else if (a === 'classico') abrirV1('nenhuma');
    else if (a === 'busca') { const i = root.querySelector('#vx-busca'); if (i) i.focus(); }
    else if (a === 'mais') { const m = root.querySelector('#vx-mais'); const ab = m.classList.toggle('vx-aberto'); b.setAttribute('aria-expanded', String(ab)); }
  });
  root.addEventListener('submit', (e) => {
    if (!e.target.matches('[data-busca]')) return;
    e.preventDefault();
    const v = root.querySelector('#vx-busca').value.trim();
    const r = lerRota(); const tela = r.tela === 'empresas' ? 'empresas' : 'eventos';
    const q = new URLSearchParams(r.tela === tela ? r.q : '');
    if (v) q.set('q', v); else q.delete('q');
    // Nome exato de emissor vai direto para a pagina dele.
    const exato = S.uni.lista.find((n) => n.toLowerCase() === v.toLowerCase());
    ir(exato ? montarRota('empresa', [exato, 'visao']) : montarRota(tela, [], q));
  });
  // Teclado: / busca, G E / G C navegam. J/K/Enter/Esc/F ficam na tela de eventos.
  let g = false;
  document.addEventListener('keydown', (e) => {
    if (!root.classList.contains('vx-on')) return;
    const t = e.target; const digitando = t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);
    if (digitando) { if (e.key === 'Escape') t.blur(); return; }
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === '/') { e.preventDefault(); const i = root.querySelector('#vx-busca'); if (i) i.focus(); return; }
    if (g) { g = false; if (e.key === 'e' || e.key === 'E') { ir('#/eventos'); return; } if (e.key === 'c' || e.key === 'C') { ir('#/empresas'); return; } }
    if (e.key === 'g' || e.key === 'G') { g = true; return; }
    root.dispatchEvent(new CustomEvent('vx:tecla', { detail: e }));
  });
  window.addEventListener('hashchange', render);
  window.addEventListener('popstate', render);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && root.classList.contains('vx-on')) recarregar(); });
  window.addEventListener('pageshow', (e) => { if (e.persisted) recarregar(); });
  // Login/logout da v1 mostram/escondem a landing: observa o atributo, sem timer.
  const ph = document.getElementById('publicHome');
  if (ph) new MutationObserver(() => { if (!landingVisivel() && sessaoAtiva() && !S.carregadoEm) recarregar(); render(); }).observe(ph, { attributes: true, attributeFilter: ['style', 'class', 'hidden'] });
}

export function iniciar() {
  if (root) return;
  const css = document.createElement('link');
  css.rel = 'stylesheet'; css.href = new URL('./css/vx.css', import.meta.url).href;
  document.head.appendChild(css);
  root = document.createElement('div');
  root.id = 'vx2-root'; root.setAttribute('aria-hidden', 'true');
  document.body.appendChild(root);
  ligar();
  if (sessaoAtiva() && (!location.hash || location.hash === '#' || location.hash === '#/')) history.replaceState(null, '', location.pathname + location.search + '#/eventos');
  render();
  if (sessaoAtiva()) recarregar();
}

export { S as estadoV2, ultimoFoco };
