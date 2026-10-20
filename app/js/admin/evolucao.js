/**
 * VIX Radar — Admin: aba Evolucao (EVOLUCAO-UI1, VIX Intelligence Evolution)
 *
 * Lista o livro de propostas (action evolucao_listar) e decide cada uma
 * (evolucao_decidir: aprovar, rejeitar, reverter), sempre com motivo.
 * Aprovar NAO executa nada: so registra a autorizacao para planejar.
 * Carrega so no clique da aba (AUTONOMIAOFF1: nenhum timer de rede).
 * Todo texto da proposta vem de fonte nao confiavel: sempre via esc().
 */

import { esc, postAdmin } from './shared.js?v=202.83';

const ROTULO_ESTADO = { proposta: 'Aguardando decisao', aprovada: 'Aprovada', rejeitada: 'Rejeitada' };
const ROTULO_TIPO = {
  descoberta_emissor: 'Emissor', descoberta_fonte: 'Fonte', descoberta_setor: 'Setor', indicador: 'Indicador',
  ews: 'EWS', funcionalidade: 'Funcionalidade', ux_ui: 'UX/UI', seguranca: 'Seguranca', desempenho: 'Desempenho',
  custo: 'Custo', codigo: 'Codigo',
};
let filtroEstado = 'proposta';

function injectEvolucaoStyles() {
  if (document.getElementById('vr-evolucao-css')) return;
  const s = document.createElement('style');
  s.id = 'vr-evolucao-css';
  s.textContent =
    '.evo-filtros{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px}' +
    '.evo-card{border:1px solid #0D2438;border-radius:6px;padding:12px 14px;margin-bottom:10px}' +
    '.evo-topo{display:flex;gap:8px;align-items:center;flex-wrap:wrap;font-size:12px;opacity:.85;margin-bottom:6px}' +
    '.evo-selo{border:1px solid #B7985D;border-radius:10px;padding:1px 8px}' +
    '.evo-alerta{border-color:#c0504d;color:#e8a09e}' +
    '.evo-titulo{font-weight:600;margin-bottom:4px}' +
    '.evo-desc{font-size:13px;line-height:1.45;margin-bottom:6px;overflow-wrap:anywhere}' +
    '.evo-fontes a{font-size:12px;overflow-wrap:anywhere;display:block}' +
    '.evo-acoes{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}' +
    '.evo-hist{font-size:12px;opacity:.75;margin-top:6px}' +
    '.evo-msg{font-size:13px;margin:8px 0}';
  document.head.appendChild(s);
}

function fontesHtml(fontes) {
  return (fontes || []).filter((u) => /^https:\/\//.test(String(u))).map((u) =>
    '<a href="' + esc(u) + '" target="_blank" rel="noopener noreferrer">' + esc(u) + '</a>').join('');
}

function cardHtml(p) {
  const selos = ['<span class="evo-selo">' + esc(ROTULO_TIPO[p.tipo] || p.tipo) + '</span>',
    '<span class="evo-selo">' + esc(ROTULO_ESTADO[p.estado] || p.estado) + '</span>',
    '<span>origem: ' + esc(p.origem) + '</span>', '<span>v' + esc(p.versao) + '</span>',
    '<span>' + esc(String(p.criada_em || '').slice(0, 10)) + '</span>'];
  if (p.critico) selos.push('<span class="evo-selo evo-alerta">critico</span>');
  if (p.suspeita_injecao) selos.push('<span class="evo-selo evo-alerta">texto suspeito, revisar com cuidado</span>');
  const ultima = (p.historico || [])[(p.historico || []).length - 1];
  const hist = ultima && ultima.evento !== 'criada'
    ? '<div class="evo-hist">Ultima decisao: ' + esc(ultima.evento) + ' em ' + esc(String(ultima.em || '').slice(0, 16).replace('T', ' ')) + ' (' + esc(ultima.motivo || '') + ')</div>' : '';
  const acoes = p.estado === 'proposta'
    ? '<button class="admin-btn" data-evo="aprovar" data-id="' + esc(p.id) + '">Aprovar</button>' +
      '<button class="admin-btn" data-evo="rejeitar" data-id="' + esc(p.id) + '">Rejeitar</button>'
    : '<button class="admin-btn" data-evo="reverter" data-id="' + esc(p.id) + '">Desfazer decisao</button>';
  return '<div class="evo-card" data-card="' + esc(p.id) + '"><div class="evo-topo">' + selos.join('') + '</div>' +
    '<div class="evo-titulo">' + esc(p.titulo) + '</div><div class="evo-desc">' + esc(p.descricao) + '</div>' +
    '<div class="evo-fontes">' + fontesHtml(p.fontes) + '</div>' + hist + '<div class="evo-acoes">' + acoes + '</div></div>';
}

export async function loadEvolucao() {
  const alvo = document.getElementById('vr-admin-evolucao');
  if (!alvo) return;
  const filtros = '<div class="evo-filtros">' + [['proposta', 'Aguardando decisao'], ['aprovada', 'Aprovadas'], ['rejeitada', 'Rejeitadas'], ['', 'Todas']]
    .map(([v, r]) => '<button class="admin-btn' + (v === filtroEstado ? ' active' : '') + '" data-evo-filtro="' + v + '">' + r + '</button>').join('') + '</div>';
  alvo.innerHTML = '<div class="admin-section"><div class="admin-section-title">Propostas de evolucao</div>' + filtros +
    '<div class="evo-msg">Aprovar so autoriza planejar a mudanca. Nada e executado automaticamente.</div><div id="evo-lista" class="evo-msg">Carregando...</div></div>';
  let j;
  try { j = await postAdmin('evolucao_listar', filtroEstado ? { estado: filtroEstado } : {}); }
  catch (e) { j = { ok: false, erro: e && e.message }; }
  const lista = document.getElementById('evo-lista');
  if (!lista) return;
  if (!j || j.ok !== true) { lista.textContent = 'Nao foi possivel carregar: ' + ((j && (j.erro || j.codigo)) || 'erro desconhecido'); return; }
  const itens = Array.isArray(j.itens) ? j.itens : [];
  lista.innerHTML = itens.length ? itens.map(cardHtml).join('')
    : 'Nenhuma proposta ' + (filtroEstado ? 'neste filtro' : 'ainda') + '. Elas aparecem quando o sistema encontra erro repetido (verificacao esgotada ou evento real sem alerta do EWS 2.0).';
}

async function decidir(id, decisao, card) {
  const rot = { aprovar: 'aprovar', rejeitar: 'rejeitar', reverter: 'desfazer a decisao de' }[decisao];
  const motivo = window.prompt('Motivo para ' + rot + ' esta proposta (minimo 10 caracteres):', '');
  if (motivo === null) return;
  const extra = { id, decisao, motivo };
  if (decisao === 'aprovar' && card && card.querySelector('.evo-alerta')) {
    if (!window.confirm('Esta proposta tem texto marcado como suspeito ou e critica. Confirma que revisou e quer aprovar?')) return;
    extra.ciente_suspeita = true;
  }
  let j;
  try { j = await postAdmin('evolucao_decidir', extra); } catch (e) { j = { ok: false, erro: e && e.message }; }
  if (!j || j.ok !== true) { window.alert('Decisao recusada: ' + ((j && (j.codigo || j.erro)) || 'erro')); return; }
  loadEvolucao();
}

export function injectEvolucaoTab() {
  const painel = document.getElementById('admin-painel');
  const tabs = painel && painel.querySelector('.admin-tabs');
  if (!tabs || document.getElementById('admin-tab-evolucao')) return;
  const btn = document.createElement('button');
  btn.className = 'admin-tab-btn';
  btn.setAttribute('data-tab', 'evolucao');
  btn.textContent = 'Evolucao';
  btn.addEventListener('click', () => {
    if (typeof window.adminAbaAtiva === 'function') window.adminAbaAtiva('evolucao', btn);
    loadEvolucao();
  });
  tabs.appendChild(btn);
  const pane = document.createElement('div');
  pane.id = 'admin-tab-evolucao';
  pane.className = 'admin-tab-pane vr-admin-tab-pane';
  pane.innerHTML = '<div id="vr-admin-evolucao"></div>';
  pane.addEventListener('click', (e) => {
    const f = e.target.closest('[data-evo-filtro]');
    if (f) { filtroEstado = f.getAttribute('data-evo-filtro'); loadEvolucao(); return; }
    const b = e.target.closest('[data-evo]');
    if (b) decidir(b.getAttribute('data-id'), b.getAttribute('data-evo'), b.closest('.evo-card'));
  });
  const panes = painel.querySelectorAll('.admin-tab-pane');
  const ultimo = panes[panes.length - 1];
  if (ultimo && ultimo.parentNode) ultimo.parentNode.insertBefore(pane, ultimo.nextSibling);
  else painel.appendChild(pane);
}

export function initEvolucao() {
  injectEvolucaoStyles();
  if (document.getElementById('admin-painel')) injectEvolucaoTab();
  const orig = window.abrirAdmin;
  if (typeof orig === 'function' && !window._vrEvolucaoOpenPatched) {
    window._vrEvolucaoOpenPatched = true;
    window.abrirAdmin = function () { const r = orig.apply(this, arguments); setTimeout(injectEvolucaoTab, 250); return r; };
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initEvolucao);
else initEvolucao();
