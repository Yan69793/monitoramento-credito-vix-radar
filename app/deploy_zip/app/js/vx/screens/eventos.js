/**
 * Painel de Eventos v2 (dossie §7.0.1): home unica, KPIs com unidade e periodo,
 * densidade por dia util (5 semanas), filtros combinaveis na URL, feed priorizado
 * por severidade > EWS do emissor > nome dentro de cada dia, painel de detalhe com
 * Evidencia -> Inferencia -> Recomendacao, CSV do filtro e estados honestos.
 */
import { esc, badge, sevCfg, sevOrd, parseISO, fmtLongo, fmtCurto, diasUteis, isoLocal, num, csv, baixar, montarRota } from '../core/util.js';
import { filtrarEventos, ORIGENS } from '../core/data.js';

const JANELAS = { '7d': '7 dias', '30d': '30 dias', '90d': '90 dias' };
const TIPOS = { idiossincratico: 'Idiossincrático', setorial: 'Setorial' };

export function lerFiltros(q) {
  const lista = (k, todos) => { const v = q.get(k); if (!v) return new Set(todos); const s = new Set(v.split(',').filter((x) => todos.includes(x))); return s.size ? s : new Set(todos); };
  const jan = JANELAS[q.get('jan')] ? q.get('jan') : '30d';
  return {
    jan,
    sev: lista('sev', window.VX_SEV_ORDEM.slice()),
    tipo: lista('tipo', Object.keys(TIPOS)),
    orig: lista('orig', Object.keys(ORIGENS)),
    setor: q.get('setor') || '',
    fav: q.get('fav') === '1', livro: q.get('livro') === '1',
    q: q.get('q') || '', dia: /^\d{4}-\d{2}-\d{2}$/.test(q.get('dia') || '') ? q.get('dia') : '',
    ev: q.get('ev') || '',
  };
}
function paraQuery(f) {
  const q = new URLSearchParams();
  if (f.jan !== '30d') q.set('jan', f.jan);
  const todos = (s, t) => s.size === t.length;
  if (!todos(f.sev, window.VX_SEV_ORDEM)) q.set('sev', window.VX_SEV_ORDEM.filter((k) => f.sev.has(k)).join(','));
  if (!todos(f.tipo, Object.keys(TIPOS))) q.set('tipo', [...f.tipo].join(','));
  if (!todos(f.orig, Object.keys(ORIGENS))) q.set('orig', [...f.orig].join(','));
  if (f.setor) q.set('setor', f.setor);
  if (f.fav) q.set('fav', '1');
  if (f.livro) q.set('livro', '1');
  if (f.q) q.set('q', f.q);
  if (f.dia) q.set('dia', f.dia);
  if (f.ev) q.set('ev', f.ev);
  return q;
}

/** Ordem do feed: dia desc; dentro do dia severidade (VX_SEV), EWS do emissor desc, nome. */
export function ordenarFeed(eventos, ewsPor) {
  const score = (e) => { const r = ewsPor && ewsPor[e._empresa]; return r && typeof r.score === 'number' ? r.score : -1; };
  return eventos.slice().sort((a, b) => String(b.data_evento).slice(0, 10).localeCompare(String(a.data_evento).slice(0, 10))
    || sevOrd(a._sev) - sevOrd(b._sev) || score(b) - score(a) || String(a._empresa).localeCompare(String(b._empresa), 'pt-BR'));
}

function kpis(c, base, filtrados, f) {
  const S = c.S;
  const ult7 = diasUteis(7); const ini7 = ult7[0]; const fim7 = ult7[ult7.length - 1];
  const em7 = base.filter((e) => { const d = parseISO(e.data_evento); return d && d >= ini7 && d <= new Date(fim7.getTime() + 864e5); });
  const alertaMais = em7.filter((e) => e._sev === 'CRITICO' || e._sev === 'ALERTA').length;
  const comSinal = new Set(em7.map((e) => e._empresa)).size;
  const ewsCrit = S.ews ? S.ews.ranking.filter((r) => String(r.label || '').toUpperCase() === 'CRITICO').length : null;
  const porSev = {}; window.VX_SEV_ORDEM.forEach((k) => { porSev[k] = 0; }); filtrados.forEach((e) => { porSev[e._sev]++; });
  const quebra = window.VX_SEV_ORDEM.map((k) => `<span data-sev-count="${k}">${sevCfg(k).label} <span class="vx-num">${porSev[k]}</span></span>`).join(' · ');
  const per7 = `${fmtCurto(ini7)} a ${fmtCurto(fim7)}`;
  return `<section class="vx-kpis" aria-label="Indicadores">
    <div class="vx-kpi" data-kpi="ews-critico"><div class="vx-kpi-v">${ewsCrit == null ? '—' : num(ewsCrit)}</div><div class="vx-kpi-l">emissores com EWS em CRÍTICO</div><div class="vx-kpi-p">${S.ews ? 'cálculo EWS de ' + esc(S.ews.calculado_em || 'data não informada') : 'ranking indisponível'}</div></div>
    <div class="vx-kpi" data-kpi="alerta-mais"><div class="vx-kpi-v">${num(alertaMais)}</div><div class="vx-kpi-l">eventos ALERTA ou acima</div><div class="vx-kpi-p">últimos 7 dias úteis · ${per7}</div></div>
    <div class="vx-kpi" data-kpi="com-sinal"><div class="vx-kpi-v">${num(comSinal)}<span class="vx-muted" style="font-size:var(--vx-fs-14)"> de ${num(c.uni.total)}</span></div><div class="vx-kpi-l">emissores com evento</div><div class="vx-kpi-p">últimos 7 dias úteis · ${per7}</div></div>
    <div class="vx-kpi" data-kpi="no-filtro"><div class="vx-kpi-v" data-total-filtro>${num(filtrados.length)}</div><div class="vx-kpi-l">eventos no filtro atual</div><div class="vx-kpi-p">janela ${JANELAS[f.jan]}${f.dia ? ' · dia ' + esc(f.dia) : ''} · ${quebra}</div></div>
  </section>`;
}

function densidade(eventos, f) {
  const dias = diasUteis(25);
  const por = {}; eventos.forEach((e) => { const k = String(e.data_evento).slice(0, 10); (por[k] = por[k] || []).push(e); });
  const max = Math.max(1, ...dias.map((d) => (por[isoLocal(d)] || []).length));
  const cols = dias.map((d) => {
    const k = isoLocal(d); const evs = por[k] || [];
    const cont = {}; evs.forEach((e) => { cont[e._sev] = (cont[e._sev] || 0) + 1; });
    const desc = window.VX_SEV_ORDEM.filter((s) => cont[s]).map((s) => `${cont[s]} ${sevCfg(s).label}`).join(', ') || 'nenhum evento';
    const barras = window.VX_SEV_ORDEM.slice().reverse().filter((s) => cont[s]).map((s) => `<span class="vx-sevbar" data-sev="${s}" style="height:${(cont[s] / max) * 100}%"></span>`).join('');
    return `<button type="button" class="vx-dens-col${evs.length ? '' : ' vazio'}" data-dia="${k}" aria-pressed="${f.dia === k}" aria-label="${fmtLongo(d)}: ${evs.length} eventos (${desc})" title="${fmtCurto(d)}: ${desc}">${barras}</button>`;
  }).join('');
  return `<section class="vx-dens" aria-label="Eventos por dia útil nas últimas 5 semanas">
    <div class="vx-dens-h"><span>Eventos por dia útil · últimas 5 semanas (${fmtCurto(dias[0])} a ${fmtCurto(dias[dias.length - 1])}), empilhados por severidade, com os filtros exceto janela</span>${f.dia ? '<button type="button" class="vx-chip" data-limpar-dia>Limpar dia ' + esc(f.dia) + '</button>' : ''}</div>
    <div class="vx-dens-row">${cols}</div>
    <div class="vx-dens-x"><span>${fmtCurto(dias[0])}</span><span>${fmtCurto(dias[dias.length - 1])}</span></div>
  </section>`;
}

function filtrosUI(c, f) {
  const chip = (grupo, k, label, on) => `<button type="button" class="vx-chip" data-f="${grupo}" data-k="${k}" aria-pressed="${on}">${label}</button>`;
  const setores = Object.keys(typeof EMISSORES === 'object' ? EMISSORES : {}); // eslint-disable-line no-undef
  return `<div class="vx-filtros" id="vx-filtros" role="region" aria-label="Filtros do feed">
    <fieldset class="vx-fgroup"><legend>Janela</legend>${Object.entries(JANELAS).map(([k, l]) => chip('jan', k, l, f.jan === k)).join('')}</fieldset>
    <fieldset class="vx-fgroup"><legend>Severidade</legend>${window.VX_SEV_ORDEM.map((k) => chip('sev', k, `<span aria-hidden="true" style="color:${sevCfg(k).cor}">${sevCfg(k).icone}</span> ${sevCfg(k).label}`, f.sev.has(k))).join('')}</fieldset>
    <fieldset class="vx-fgroup"><legend>Tipo</legend>${Object.entries(TIPOS).map(([k, l]) => chip('tipo', k, l, f.tipo.has(k))).join('')}</fieldset>
    <fieldset class="vx-fgroup"><legend>Origem</legend>${Object.entries(ORIGENS).map(([k, l]) => chip('orig', k, l, f.orig.has(k))).join('')}</fieldset>
    <div class="vx-fgroup"><label for="vx-setor">Setor</label><select id="vx-setor" class="vx-select" data-f="setor"><option value="">Todos</option>${setores.map((s) => `<option${s === f.setor ? ' selected' : ''}>${esc(s)}</option>`).join('')}</select></div>
    <div class="vx-fgroup">${chip('livro', '1', 'Só meu livro', f.livro)}${c.favOn ? chip('fav', '1', 'Só favoritos', f.fav) : ''}</div>
    <button type="button" class="vx-btn" data-limpar>Limpar filtros</button>
    <button type="button" class="vx-btn vx-filtros-m" data-fechar-filtros>Aplicar</button>
  </div>`;
}

function cartao(e, sel, livro) {
  const d = parseISO(e.data_evento);
  const host = (e.fonte_primaria || e.url || '').split('/')[2] || '';
  return `<li><button type="button" class="vx-ev" data-ev="${esc(e._id)}" data-sev="${e._sev}" data-empresa="${esc(e._empresa)}"${sel ? ' aria-current="true"' : ''}>
    ${badge(e._sev)}<span class="vx-ev-emp">${esc(e._empresa)}${livro ? ' <span class="vx-ev-livro">· do seu livro</span>' : ''}</span>
    <span class="vx-ev-meta">${esc(ORIGENS[e._origem] || e._origem)}${e._escopo === 'setorial' ? ' · setorial' : ''} · ${fmtCurto(d)}${host ? ' · ' + esc(host.replace(/^www\./, '')) : ''}</span>
    <span class="vx-ev-tit">${esc(e.titulo || e.evento || 'Evento sem título')}</span>
  </button></li>`;
}

function bloco(titulo, texto, cls = '') {
  return `<div class="vx-cadeia ${cls}"><p>${texto ? esc(texto) : '<span class="vx-muted">Não informado pela análise.</span>'}</p></div>`;
}
export function detalhe(c, e) {
  if (!e) return `<aside class="vx-det" id="vx-det" aria-label="Detalhe do evento"><p class="vx-muted">Selecione um evento para ver evidência, inferência e recomendação. Teclas J e K percorrem o feed.</p></aside>`;
  const r = c.S.ews && c.S.ews.porEmpresa[e._empresa];
  const url = e.fonte_primaria || e.url || '';
  const urlOk = /^https?:\/\//i.test(url);
  const ewsTxt = r ? `<b class="vx-num">${num(r.score)}</b> ${badge(r.label)} · #${r.posicao} no ranking EWS${r.piso_aplicado ? ` · piso aplicado (sem piso: <span class="vx-num">${num(r.score_calculado, 1)}</span>)` : ''}` :
    (c.S.ews ? 'fora do ranking EWS (o Worker só ranqueia emissor com score acima de zero ou com anomalia)' : 'ranking EWS indisponível');
  return `<aside class="vx-det vx-aberto" id="vx-det" aria-label="Detalhe do evento" tabindex="-1">
    <button type="button" class="vx-btn vx-det-close" data-fechar-det>Fechar</button>
    <div>${badge(e._sev)} <span class="vx-muted">${esc(fmtLongo(parseISO(e.data_evento)))}</span></div>
    <h2>${esc(e._empresa)}: ${esc(e.titulo || e.evento || '')}</h2>
    <h3>Evidência</h3>
    <div class="vx-cadeia">
      <p>${esc(e.evento || e.descricao || e.memo_acontecimento || e.titulo || '')}</p>
      <p class="vx-muted">Fonte: ${urlOk ? `<a href="${esc(url)}" target="_blank" rel="noopener">${esc(url.split('/')[2] || url)}</a>` : 'sem link registrado'} · origem ${esc(ORIGENS[e._origem] || e._origem)} · data do evento ${esc(e.data_evento)}${e.data_publicacao_fonte ? ' · publicado na fonte em ' + esc(e.data_publicacao_fonte) : ' · data de publicação na fonte não informada'}</p>
    </div>
    <h3>Inferência <span class="vx-tag-inferido">modelo</span></h3>
    ${bloco('Inferência', e.impacto_credito || e.memo_importancia_credito || e.cadeia_causal, 'inf')}
    <h3>Recomendação</h3>
    ${bloco('Recomendação', e.memo_acao_sugerida || e.memo_monitorar, 'rec')}
    <h3>EWS do emissor</h3>
    <p>${ewsTxt}</p>
    <div class="vx-acts">
      <button type="button" class="vx-btn vx-btn-primary" data-ir="${esc(montarRota('empresa', [e._empresa, 'visao']))}">Abrir empresa</button>
      <button type="button" class="vx-btn" data-v1="comparar" data-empresa="${esc(e._empresa)}">Comparar</button>
    </div>
  </aside>`;
}

export function renderEventos(alvo, c, rota) {
  const S = c.S;
  const f = lerFiltros(rota.q);
  const atualizar = (mut) => { mut(f); c.ir(montarRota('eventos', [], paraQuery(f)), { substituir: true }); };
  // estados: carregando, erro, sem leitura, vazio
  if (!S.estado) {
    alvo.innerHTML = S.erros.estado
      ? `<div class="vx-estado erro" role="alert"><b>Não foi possível ler os eventos.</b> ${esc(S.erros.estado)} Isto não é ausência de alerta. ${S.carregadoEm ? 'Última tentativa: ' + esc(S.carregadoEm.toLocaleTimeString('pt-BR')) + '.' : ''} <button type="button" class="vx-btn" data-acao="atualizar">Tentar de novo</button></div>`
      : `<div aria-busy="true" aria-label="Carregando eventos">${'<div class="vx-skel"></div>'.repeat(8)}</div>`;
    return;
  }
  const ctxF = { setorDe: c.setorDe, livro: c.livro, favs: c.favs };
  const base = S.estado.eventos;
  const filtrados = ordenarFeed(filtrarEventos(base, f, ctxF), S.ews && S.ews.porEmpresa);
  const paraDens = filtrarEventos(base, { ...f, jan: 'tudo', dia: '' }, ctxF);
  const sel = filtrados.find((e) => e._id === f.ev) || null;
  let feed;
  if (!base.length) feed = '<div class="vx-estado">Sem leitura de eventos nesta sessão. Isto não é ausência de alerta.</div>';
  else if (!filtrados.length) feed = '<div class="vx-estado">Nenhum evento nos filtros atuais. Ajuste janela, severidade ou os demais filtros. Isto não significa ausência de risco fora do filtro.</div>';
  else {
    const porDia = {}; filtrados.forEach((e) => { const k = String(e.data_evento).slice(0, 10); (porDia[k] = porDia[k] || []).push(e); });
    feed = Object.keys(porDia).map((k) => `<h2 class="vx-dia">${esc(fmtLongo(parseISO(k)))} · ${porDia[k].length} ${porDia[k].length === 1 ? 'evento' : 'eventos'}</h2><ol>${porDia[k].map((e) => cartao(e, sel && sel._id === e._id, c.livro.has(e._empresa))).join('')}</ol>`).join('');
  }
  alvo.innerHTML = `
    <h1 class="vx-sr">Painel de Eventos</h1>
    ${kpis(c, base, filtrados, f)}
    ${densidade(paraDens, f)}
    <div class="vx-acts" style="margin:0 0 var(--vx-space-2)">
      <button type="button" class="vx-btn vx-filtros-m" data-abrir-filtros aria-controls="vx-filtros">Filtros (F)</button>
      <button type="button" class="vx-btn" data-csv>Exportar CSV do filtro (${filtrados.length})</button>
    </div>
    ${filtrosUI(c, f)}
    <div class="vx-sheet-bg" data-fechar-filtros></div>
    <p class="vx-resumo" aria-live="polite">${filtrados.length} ${filtrados.length === 1 ? 'evento' : 'eventos'} · ${new Set(filtrados.map((e) => e._empresa)).size} emissores · ordem: dia, severidade, EWS do emissor</p>
    <div class="vx-split">
      <section class="vx-feed" aria-label="Feed de eventos">${feed}</section>
      ${detalhe(c, sel)}
    </div>`;

  alvo.onclick = (e) => {
    const t = e.target.closest('button,select'); if (!t) return;
    if (t.dataset.f && t.tagName === 'BUTTON') {
      const g = t.dataset.f; const k = t.dataset.k;
      atualizar((x) => {
        if (g === 'jan') { x.jan = k; x.dia = ''; }
        else if (g === 'livro') x.livro = !x.livro;
        else if (g === 'fav') x.fav = !x.fav;
        else { const s = x[g]; if (s.has(k)) { if (s.size > 1) s.delete(k); } else s.add(k); }
      });
    } else if (t.dataset.dia) atualizar((x) => { x.dia = x.dia === t.dataset.dia ? '' : t.dataset.dia; x.jan = '90d'; });
    else if ('limparDia' in t.dataset) atualizar((x) => { x.dia = ''; });
    else if ('limpar' in t.dataset) c.ir('#/eventos', { substituir: true });
    else if (t.dataset.ev) { atualizar((x) => { x.ev = t.dataset.ev; }); const d = document.getElementById('vx-det'); if (d) d.focus({ preventScroll: true }); }
    else if ('fecharDet' in t.dataset) atualizar((x) => { x.ev = ''; });
    else if ('abrirFiltros' in t.dataset) { alvo.querySelector('#vx-filtros').classList.add('vx-aberto'); alvo.querySelector('.vx-sheet-bg').classList.add('vx-aberto'); const p = alvo.querySelector('#vx-filtros .vx-chip'); if (p) p.focus(); }
    else if ('fecharFiltros' in t.dataset) { alvo.querySelector('#vx-filtros').classList.remove('vx-aberto'); alvo.querySelector('.vx-sheet-bg').classList.remove('vx-aberto'); }
    else if ('csv' in t.dataset) {
      const cols = [
        { titulo: 'data_evento', valor: (x) => x.data_evento }, { titulo: 'severidade', valor: (x) => x._sev },
        { titulo: 'emissor', valor: (x) => x._empresa }, { titulo: 'setor', valor: (x) => c.setorDe[x._empresa] || '' },
        { titulo: 'tipo', valor: (x) => x._escopo }, { titulo: 'origem', valor: (x) => x._origem },
        { titulo: 'titulo', valor: (x) => x.titulo || '' }, { titulo: 'fonte', valor: (x) => x.fonte_primaria || x.url || '' },
        { titulo: 'ews_score', valor: (x) => { const r = S.ews && S.ews.porEmpresa[x._empresa]; return r ? r.score : ''; } },
        { titulo: 'id', valor: (x) => x._id },
      ];
      baixar(`vixradar-eventos-${isoLocal(new Date())}.csv`, csv(filtrados, cols));
    }
  };
  alvo.onchange = (e) => { if (e.target.dataset.f === 'setor') atualizar((x) => { x.setor = e.target.value; }); };
  // atalhos J/K/Enter/Esc/F (vindos do shell)
  const raiz = document.getElementById('vx2-root');
  if (raiz._vxTeclaEv) raiz.removeEventListener('vx:tecla', raiz._vxTeclaEv);
  raiz._vxTeclaEv = (ev) => {
    const k = ev.detail.key;
    const ids = filtrados.map((x) => x._id);
    const i = ids.indexOf(f.ev);
    if (k === 'j' || k === 'J' || k === 'k' || k === 'K') {
      if (!ids.length) return;
      const n = (k === 'j' || k === 'J') ? Math.min(ids.length - 1, i + 1) : Math.max(0, i < 0 ? 0 : i - 1);
      atualizar((x) => { x.ev = ids[n]; });
      const b = document.querySelector(`.vx-ev[data-ev="${CSS.escape(ids[n])}"]`); if (b) { b.focus(); b.scrollIntoView({ block: 'nearest' }); }
    } else if (k === 'Enter' && sel && !(ev.detail.target && ev.detail.target.closest && ev.detail.target.closest('button'))) {
      c.ir(montarRota('empresa', [sel._empresa, 'visao']));
    } else if (k === 'Escape') { if (f.ev) atualizar((x) => { x.ev = ''; }); }
    else if (k === 'f' || k === 'F') { const b = alvo.querySelector('[data-abrir-filtros]'); if (b && b.offsetParent) b.click(); else { const p = alvo.querySelector('#vx-filtros .vx-chip'); if (p) p.focus(); } }
  };
  raiz.addEventListener('vx:tecla', raiz._vxTeclaEv);
}
