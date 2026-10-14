/**
 * Camada de dados da v2. So le endpoints que ja existem (op=state, op=ews, op=serie,
 * op=anomalias, GET / de health, action favorito_*). Nada de score, percentil ou
 * metrica financeira calculada aqui: so filtro, contagem e ordenacao para exibir.
 * Autenticacao: os mesmos helpers da v1 (_authHeadersGet/_authHeaders/_tratarSessaoExpirada),
 * entao token, sessao e permissoes continuam sendo decididos pelo Worker.
 */
import { parseISO, hoje0, sevEvento } from './util.js';

const base = () => (typeof API_BASE !== 'undefined' ? API_BASE : 'https://api.vixradar.com'); // eslint-disable-line no-undef
const authGet = () => (typeof _authHeadersGet === 'function' ? _authHeadersGet() : {}); // eslint-disable-line no-undef
const authPost = () => (typeof _authHeaders === 'function' ? _authHeaders() : { 'Content-Type': 'application/json', ...authGet() }); // eslint-disable-line no-undef

export class ErroDados extends Error {
  constructor(msg, status) { super(msg); this.status = status; }
}

async function getJSON(qs, { auth = true } = {}) {
  const r = await fetch(base() + qs, { method: 'GET', cache: 'no-store', headers: auth ? authGet() : {} });
  if (r.status === 401) {
    if (typeof _tratarSessaoExpirada === 'function') _tratarSessaoExpirada(r); // eslint-disable-line no-undef
    throw new ErroDados('Sessão expirada. Entre de novo para ver os dados.', 401);
  }
  if (!r.ok) throw new ErroDados(`A API respondeu HTTP ${r.status}.`, r.status);
  return r.json();
}
async function postJSON(body) {
  const r = await fetch(base(), { method: 'POST', credentials: 'include', headers: authPost(), body: JSON.stringify(body) });
  if (r.status === 401) {
    if (typeof _tratarSessaoExpirada === 'function') _tratarSessaoExpirada(r); // eslint-disable-line no-undef
    throw new ErroDados('Sessão expirada.', 401);
  }
  return r.json();
}

/* ---------- normalizacao identica a v1 (normalizarResultadoPayload + _v201Coletar) ---------- */
const CLASSES = ['CRITICO', 'ALERTA', 'ATENCAO', 'RELEVANTE', 'ECO'];
const TEXTO = ['titulo', 'evento', 'descricao', 'contexto', 'impacto_credito', 'cadeia_causal', 'memo_acontecimento',
  'memo_importancia_credito', 'memo_monitorar', 'memo_acao_sugerida'];

function idEvento(ev) {
  if (ev.id) return String(ev.id);
  const s = `${ev._empresa}|${ev.data_evento}|${ev.titulo || ''}`;
  let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return 'e' + (h >>> 0).toString(36);
}

/** Origem: mesma regra de _v201Origem. */
export function origemEvento(ev) {
  const t = String(ev.fonte_tipo || '').toUpperCase();
  const url = String(ev.fonte_primaria || ev.url || '');
  if (t === 'RATING' || t === 'AGENCIA_RATING' || t === 'RATING_AGENCIA') return 'rating';
  if (t === 'CVM_FATO_RELEVANTE' || /fato.relev/i.test(ev.titulo || '')) return 'fato_relevante';
  if (t.indexOf('CVM') === 0 || /rad\.cvm\.gov\.br|cvm\.gov\.br/i.test(url) || t === 'B3' || t === 'ANBIMA') return 'comunicado';
  if (t === 'REGULADOR' || t === 'REGULATORIO' || t === 'REGULATORIO_OFICIAL' || /(?:ans|aneel|antt|anatel|anp|antaq|anac|bcb)\.gov\.br/i.test(url)) return 'regulador';
  if (t === 'IMPRENSA') return 'imprensa';
  return 'comunicado';
}
export const ORIGENS = { rating: 'Rating', fato_relevante: 'Fato relevante', comunicado: 'CVM/B3', imprensa: 'Imprensa', regulador: 'Regulador' };
export function escopoEvento(ev) { return ev.escopo === 'setorial' ? 'setorial' : 'idiossincratico'; }

export function normalizarEstado(json, agora = new Date()) {
  const results = json && json.results;
  if (!results || typeof results !== 'object') throw new ErroDados('Resposta de estado sem resultados.', 0);
  const corte = new Date(agora); corte.setDate(corte.getDate() - 90); corte.setHours(0, 0, 0, 0);
  const scrub = typeof window._vixScrubMoney === 'function' ? window._vixScrubMoney : (x) => x;
  const normData = typeof normalizarDataEvento === 'function' ? normalizarDataEvento : (x) => x; // eslint-disable-line no-undef
  const emissores = {};
  const todos = [];
  for (const [empresa, r0] of Object.entries(results)) {
    const r = r0 || {};
    const eventos = (Array.isArray(r.eventos) ? r.eventos : []).map((e) => {
      const o = { ...e, data_evento: normData(e && e.data_evento) };
      TEXTO.forEach((k) => { if (o[k] != null) o[k] = scrub(o[k]); });
      return o;
    }).filter((e) => {
      if (!e.classificacao || e.classificacao === 'RUIDO') return false;
      const d = parseISO(e.data_evento);
      return !!d && !(d > agora) && CLASSES.includes(e.classificacao) && d >= corte;
    });
    emissores[empresa] = { empresa, timestamp: r.timestamp || r._salvo_em || null, n_eventos: eventos.length, bruto: r };
    eventos.forEach((e) => todos.push({ ...e, _empresa: r.empresa || e.empresa || empresa }));
  }
  // DEDUP1: mais recente primeiro, depois a mesma deduplicacao semantica da v1.
  todos.sort((a, b) => String(b.data_evento || '').localeCompare(String(a.data_evento || '')));
  const dedup = [];
  const dup = typeof _isDupSemantico === 'function' ? _isDupSemantico : null; // eslint-disable-line no-undef
  todos.forEach((ev) => { if (!dup || !dup(ev, dedup)) dedup.push(ev); });
  dedup.forEach((ev) => { ev._id = idEvento(ev); ev._sev = sevEvento(ev); ev._origem = origemEvento(ev); ev._escopo = escopoEvento(ev); });
  return { eventos: dedup, emissores, semana: json.week || null, atualizado_em: json.updated_at || null };
}

/* ---------- universo, setores, livro, favoritos ---------- */
export function universo() {
  const lista = []; const setorDe = {};
  if (typeof EMISSORES === 'object' && EMISSORES) { // eslint-disable-line no-undef
    Object.entries(EMISSORES).forEach(([setor, nomes]) => nomes.forEach((n) => { lista.push(n); setorDe[n] = setor; })); // eslint-disable-line no-undef
  }
  return { lista, setorDe, total: typeof TOTAL_EMISSORES === 'number' ? TOTAL_EMISSORES : lista.length }; // eslint-disable-line no-undef
}
export function livro() {
  try {
    const j = JSON.parse(localStorage.getItem('radar_carteira_v1') || '[]');
    return new Set((Array.isArray(j) ? j : []).map((x) => (x && (x.matched || x.nome)) || '').filter(Boolean));
  } catch (_) { return new Set(); }
}
export function favoritosHabilitados() { return Array.isArray(window.TENANT_FEATURES) && window.TENANT_FEATURES.indexOf('favoritos') >= 0; }
export function favoritos() {
  const f = Array.isArray(window.__radarFavoritos) ? window.__radarFavoritos : [];
  return new Set(f.map((e) => (e && e.empresa ? e.empresa : e)).filter(Boolean));
}
export async function alternarFavorito(empresa) {
  const o = await postJSON({ action: 'favorito_toggle', empresa });
  if (o && o.ok && Array.isArray(o.favoritos)) window.__radarFavoritos = o.favoritos; // mesma variavel da v1: as duas telas ficam em sincronia
  return favoritos();
}

/* ---------- carregamentos ---------- */
export async function carregarEstado() { return normalizarEstado(await getJSON('?op=state')); }
export async function carregarEWS() {
  const j = await getJSON('?op=ews');
  if (!j || j.ok !== true || !Array.isArray(j.ranking)) throw new ErroDados((j && j.erro) || 'Ranking EWS indisponível.', 0);
  const por = {}; j.ranking.forEach((r, i) => { por[r.empresa] = { ...r, posicao: i + 1 }; });
  return { ranking: j.ranking, porEmpresa: por, total: j.total, calculado_em: j.calculado_em || null };
}
export async function carregarEWSEmissor(empresa) {
  const j = await getJSON('?op=ews&empresa=' + encodeURIComponent(empresa));
  if (!j || j.ok !== true || !j.ews) throw new ErroDados((j && j.erro) || 'EWS indisponível.', 0);
  return j.ews;
}
export async function carregarAnomalias() {
  const j = await getJSON('?op=anomalias');
  const por = {}; ((j && j.resumo) || []).forEach((r) => { por[r.empresa] = r; });
  return { porEmpresa: por, detalhe: (j && j.detalhe) || {}, atualizado_em: (j && j.updated_at) || null };
}
export async function carregarSerie(empresa, horizonte = 90) {
  return getJSON(`?op=serie&empresa=${encodeURIComponent(empresa)}&horizonte=${horizonte}`);
}
export async function carregarHealth() { return getJSON('', { auth: false }); }

/** Janela, severidade, tipo, origem, setor, livro, favoritos, texto e dia: todos combinaveis. */
export function filtrarEventos(eventos, f, ctx) {
  const h = hoje0();
  const min = f.jan === 'tudo' ? null : (() => { const m = new Date(h); m.setDate(m.getDate() - parseInt(f.jan, 10)); return m; })();
  const q = (f.q || '').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  return eventos.filter((ev) => {
    if (!f.sev.has(ev._sev)) return false;
    if (!f.tipo.has(ev._escopo)) return false;
    if (!f.orig.has(ev._origem)) return false;
    const d = parseISO(ev.data_evento); if (!d) return false;
    if (min && d < min) return false;
    if (f.dia && ev.data_evento.slice(0, 10) !== f.dia) return false;
    if (f.setor && ctx.setorDe[ev._empresa] !== f.setor) return false;
    if (f.livro && !ctx.livro.has(ev._empresa)) return false;
    if (f.fav && !ctx.favs.has(ev._empresa)) return false;
    if (q) {
      const alvo = `${ev._empresa} ${ev.titulo || ''} ${ev.evento || ''}`.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      if (!alvo.includes(q)) return false;
    }
    return true;
  });
}
