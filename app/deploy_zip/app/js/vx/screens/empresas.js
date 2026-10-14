/**
 * Empresas v2: Mesa de Investigacao dos emissores do universo em <table> nativa
 * (sem AG Grid). Ordenacao, filtros, busca, favoritos, livro, CSV e estado na URL.
 * Coluna sem dado na API fica "—" e nunca entra como zero na ordenacao.
 */
import { esc, badge, sevOrd, parseISO, fmtCurto, num, csv, baixar, montarRota, isoLocal, hoje0, fmtDataHora } from '../core/util.js';

const COLS = [
  { k: 'fav', t: '★', ord: false },
  { k: 'empresa', t: 'Emissor' },
  { k: 'setor', t: 'Setor' },
  { k: 'ews', t: 'EWS', n: true },
  { k: 'faixa', t: 'Faixa EWS' },
  { k: 'sev', t: 'Severidade máx. 30d' },
  { k: 'ultimo', t: 'Último evento' },
  { k: 'n30', t: 'Eventos 30d', n: true },
  { k: 'anom', t: 'Anomalias ativas', n: true },
  { k: 'delta', t: 'Δ EWS 90d', n: true },
  { k: 'taxa', t: 'Taxa ANBIMA (papel destaque)', n: true },
  { k: 'analise', t: 'Último registro de análise' },
];

/** Papel destaque da serie ANBIMA (op=serie): objeto do Worker ou codigo dentro de papeis. */
export function destaqueDe(serie) {
  if (!serie || !serie.destaque) return null;
  const d = typeof serie.destaque === 'object' ? serie.destaque : (serie.papeis || []).find((p) => p.codigo_ativo === serie.destaque);
  return d && typeof d.taxa_indicativa === 'number' ? d : null;
}

export function linhas(c) {
  const S = c.S; const h = hoje0(); const corte = new Date(h); corte.setDate(corte.getDate() - 30);
  const porEmp = {};
  (S.estado ? S.estado.eventos : []).forEach((e) => { (porEmp[e._empresa] = porEmp[e._empresa] || []).push(e); });
  return c.uni.lista.map((nome) => {
    const evs = (porEmp[nome] || []).slice().sort((a, b) => String(b.data_evento).localeCompare(String(a.data_evento)));
    const e30 = evs.filter((e) => { const d = parseISO(e.data_evento); return d && d >= corte; });
    const sevMax = e30.length ? e30.slice().sort((a, b) => sevOrd(a._sev) - sevOrd(b._sev))[0]._sev : null;
    const r = S.ews && S.ews.porEmpresa[nome];
    const an = S.anom && S.anom.porEmpresa[nome];
    const serie = S.cacheSerie[nome];
    const est = S.estado && S.estado.emissores[nome];
    return {
      empresa: nome, setor: c.setorDe[nome] || '',
      ews: r ? r.score : null, faixa: r ? r.label : null, posicao: r ? r.posicao : null,
      sev: sevMax, ultimo: evs[0] || null, n30: S.estado ? e30.length : null,
      anom: S.anom ? (an ? an.total : 0) : null, anomCritica: !!(an && an.tem_critica),
      delta: serie && typeof serie.ews_delta === 'number' ? serie.ews_delta : null,
      taxa: destaqueDe(serie) ? destaqueDe(serie).taxa_indicativa : null,
      taxaTxt: destaqueDe(serie) ? (destaqueDe(serie).taxa_display || null) : null,
      analise: est && est.timestamp ? est.timestamp : null,
      fav: c.favs.has(nome), livro: c.livro.has(nome),
    };
  });
}

function valorOrd(l, k) {
  if (k === 'sev') return l.sev ? sevOrd(l.sev) : null;
  if (k === 'ultimo') return l.ultimo ? String(l.ultimo.data_evento) : null;
  if (k === 'faixa') return l.faixa ? sevOrd(l.faixa) : null;
  return l[k];
}
export function ordenar(ls, k, dir) {
  const m = dir === 'asc' ? 1 : -1;
  return ls.slice().sort((a, b) => {
    const va = valorOrd(a, k); const vb = valorOrd(b, k);
    if (va == null && vb == null) return a.empresa.localeCompare(b.empresa, 'pt-BR');
    if (va == null) return 1; if (vb == null) return -1; // indisponivel vai sempre para o fim
    const r = typeof va === 'number' ? va - vb : String(va).localeCompare(String(vb), 'pt-BR');
    return r * m || a.empresa.localeCompare(b.empresa, 'pt-BR');
  });
}
export function filtrar(ls, q) {
  const t = (q.get('q') || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
  const setor = q.get('setor') || ''; const sev = q.get('sev') || '';
  return ls.filter((l) => (!setor || l.setor === setor)
    && (!sev || l.sev === sev)
    && (q.get('fav') !== '1' || l.fav) && (q.get('livro') !== '1' || l.livro)
    && (q.get('sinal') !== '1' || l.ews != null)
    && (!t || `${l.empresa} ${l.setor}`.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').includes(t)));
}

function celula(l, k, c) {
  switch (k) {
    case 'fav': return c.favOn ? `<button type="button" class="vx-star" data-fav="${esc(l.empresa)}" aria-pressed="${l.fav}" aria-label="${l.fav ? 'Remover' : 'Adicionar'} ${esc(l.empresa)} dos favoritos">${l.fav ? '★' : '☆'}</button>` : '';
    case 'empresa': return `<button type="button" class="vx-link" data-ir="${esc(montarRota('empresa', [l.empresa, 'visao']))}">${esc(l.empresa)}</button>${l.livro ? ' <span class="vx-ev-livro">livro</span>' : ''}`;
    case 'setor': return esc(l.setor);
    case 'ews': return l.ews == null ? '<span class="vx-muted" title="Fora do ranking: o Worker só ranqueia score acima de zero ou com anomalia">—</span>' : `${num(l.ews)} <span class="vx-muted">#${l.posicao}</span>`;
    case 'faixa': return l.faixa ? badge(l.faixa) : '<span class="vx-muted">—</span>';
    case 'sev': return l.sev ? badge(l.sev) : '<span class="vx-muted">sem evento</span>';
    case 'ultimo': return l.ultimo ? `<span class="vx-num">${fmtCurto(parseISO(l.ultimo.data_evento))}</span> ${esc((l.ultimo.titulo || '').slice(0, 70))}` : '<span class="vx-muted">sem evento em 90d</span>';
    case 'n30': return l.n30 == null ? '—' : num(l.n30);
    case 'anom': return l.anom == null ? '—' : `${num(l.anom)}${l.anomCritica ? ' <span style="color:var(--vx-sev-critico)">crítica</span>' : ''}`;
    case 'delta': return l.delta == null ? '<span class="vx-muted" title="Série por emissor: abra a empresa para carregar">—</span>' : (l.delta > 0 ? '+' : '') + num(l.delta, 1);
    case 'taxa': return l.taxa == null ? '<span class="vx-muted" title="Série ANBIMA por emissor: abra a empresa para carregar">—</span>' : esc(l.taxaTxt || num(l.taxa, 2));
    case 'analise': return l.analise ? esc(fmtDataHora(l.analise)) : '<span class="vx-muted">não registrado</span>';
    default: return '';
  }
}

export function renderEmpresas(alvo, c, rota) {
  const S = c.S; const q = new URLSearchParams(rota.q);
  if (!S.estado && !S.ews) {
    alvo.innerHTML = (S.erros.estado && S.erros.ews)
      ? `<div class="vx-estado erro" role="alert"><b>Não foi possível ler os emissores.</b> ${esc(S.erros.estado)} Isto não é ausência de risco. <button type="button" class="vx-btn" data-acao="atualizar">Tentar de novo</button></div>`
      : `<div aria-busy="true" aria-label="Carregando emissores">${'<div class="vx-skel"></div>'.repeat(10)}</div>`;
    return;
  }
  const ord = COLS.some((x) => x.k === q.get('ord') && x.ord !== false) ? q.get('ord') : 'ews';
  const dir = q.get('dir') === 'asc' ? 'asc' : 'desc';
  const todas = linhas(c);
  const vis = ordenar(filtrar(todas, q), ord, dir);
  const setores = [...new Set(todas.map((l) => l.setor))].filter(Boolean).sort((a, b) => a.localeCompare(b, 'pt-BR'));
  const aviso = [S.erros.estado && `eventos indisponíveis (${esc(S.erros.estado)})`, S.erros.ews && `EWS indisponível (${esc(S.erros.ews)})`, S.erros.anom && `anomalias indisponíveis (${esc(S.erros.anom)})`].filter(Boolean);
  const chip = (k, l) => `<button type="button" class="vx-chip" data-tg="${k}" aria-pressed="${q.get(k) === '1'}">${l}</button>`;
  alvo.innerHTML = `
    <h1 class="vx-sr">Empresas: mesa de investigação</h1>
    ${aviso.length ? `<div class="vx-estado erro" role="alert">Dados parciais: ${aviso.join(' · ')}. Colunas afetadas aparecem com —.</div>` : ''}
    <div class="vx-filtros" style="display:flex" role="region" aria-label="Filtros da mesa">
      <div class="vx-fgroup"><label for="vx-e-setor">Setor</label><select id="vx-e-setor" class="vx-select" data-q="setor"><option value="">Todos</option>${setores.map((s) => `<option${s === q.get('setor') ? ' selected' : ''}>${esc(s)}</option>`).join('')}</select></div>
      <div class="vx-fgroup"><label for="vx-e-sev">Severidade 30d</label><select id="vx-e-sev" class="vx-select" data-q="sev"><option value="">Todas</option>${window.VX_SEV_ORDEM.map((k) => `<option value="${k}"${k === q.get('sev') ? ' selected' : ''}>${window.VX_SEV[k].label}</option>`).join('')}</select></div>
      <div class="vx-fgroup"><label for="vx-e-ord">Ordenar</label><select id="vx-e-ord" class="vx-select" data-q="ord">${COLS.filter((x) => x.ord !== false).map((x) => `<option value="${x.k}"${x.k === ord ? ' selected' : ''}>${esc(x.t)}</option>`).join('')}</select>
        <button type="button" class="vx-chip" data-dir aria-label="Inverter ordem">${dir === 'desc' ? '↓ desc' : '↑ asc'}</button></div>
      <div class="vx-fgroup">${chip('sinal', 'Só com EWS')}${chip('livro', 'Só meu livro')}${c.favOn ? chip('fav', 'Só favoritos') : ''}</div>
      <button type="button" class="vx-btn" data-csv>Exportar CSV (${vis.length})</button>
      <button type="button" class="vx-btn" data-v1="comparar">Comparar até 5</button>
    </div>
    <p class="vx-resumo" aria-live="polite">${vis.length} de ${todas.length} emissores · EWS ${S.ews ? 'calculado em ' + esc(S.ews.calculado_em || 'data não informada') : 'indisponível'} · Δ EWS e taxa ANBIMA vêm da série de cada emissor e só aparecem depois de abrir a empresa</p>
    <div class="vx-table-wrap" tabindex="0" role="region" aria-label="Tabela de emissores, role para ver todas as colunas">
      <table class="vx-table">
        <caption class="vx-sr">Emissores monitorados, ordenados por ${esc(COLS.find((x) => x.k === ord).t)} ${dir === 'desc' ? 'decrescente' : 'crescente'}</caption>
        <thead><tr>${COLS.map((x) => `<th scope="col"${x.k === ord ? ` aria-sort="${dir === 'desc' ? 'descending' : 'ascending'}"` : ''}>${x.ord === false ? `<span class="vx-sr">Favorito</span><span aria-hidden="true" style="padding:8px 10px;display:block">${x.t}</span>` : `<button type="button" data-ord="${x.k}">${esc(x.t)}</button>`}</th>`).join('')}</tr></thead>
        <tbody>${vis.map((l) => `<tr data-empresa="${esc(l.empresa)}">${COLS.map((x) => `<td${x.n ? ' class="n"' : ''}>${celula(l, x.k, c)}</td>`).join('')}</tr>`).join('')}</tbody>
      </table>
    </div>
    <ul class="vx-cards" aria-label="Emissores">${vis.map((l) => `<li data-empresa="${esc(l.empresa)}">
      <div class="l1"><button type="button" class="vx-link" data-ir="${esc(montarRota('empresa', [l.empresa, 'visao']))}">${esc(l.empresa)}</button>${celula(l, 'fav', c)}</div>
      <div class="l2"><span class="vx-muted">${esc(l.setor)}</span><span>EWS ${celula(l, 'ews', c)} ${l.faixa ? badge(l.faixa) : ''}</span></div>
      <div class="l3"><span>${celula(l, 'ultimo', c)}</span>${l.sev ? badge(l.sev) : ''}</div>
    </li>`).join('')}</ul>`;

  const ir = (mut) => { mut(q); c.ir(montarRota('empresas', [], q), { substituir: true }); };
  alvo.onclick = async (e) => {
    const t = e.target.closest('button'); if (!t) return;
    if (t.dataset.ord) ir((x) => { if (x.get('ord') === t.dataset.ord || (!x.get('ord') && t.dataset.ord === 'ews')) x.set('dir', dir === 'desc' ? 'asc' : 'desc'); else { x.set('ord', t.dataset.ord); x.set('dir', 'desc'); } });
    else if ('dir' in t.dataset) ir((x) => { x.set('ord', ord); x.set('dir', dir === 'desc' ? 'asc' : 'desc'); });
    else if (t.dataset.tg) ir((x) => { if (x.get(t.dataset.tg) === '1') x.delete(t.dataset.tg); else x.set(t.dataset.tg, '1'); });
    else if (t.dataset.fav) { t.disabled = true; await c.alternarFav(t.dataset.fav); }
    else if ('csv' in t.dataset) {
      const cols = [
        { titulo: 'emissor', valor: (l) => l.empresa }, { titulo: 'setor', valor: (l) => l.setor },
        { titulo: 'ews_score', valor: (l) => (l.ews == null ? '' : l.ews) }, { titulo: 'ews_posicao', valor: (l) => l.posicao || '' },
        { titulo: 'ews_faixa', valor: (l) => l.faixa || '' }, { titulo: 'severidade_max_30d', valor: (l) => l.sev || '' },
        { titulo: 'ultimo_evento_data', valor: (l) => (l.ultimo ? l.ultimo.data_evento : '') }, { titulo: 'ultimo_evento_titulo', valor: (l) => (l.ultimo ? l.ultimo.titulo || '' : '') },
        { titulo: 'eventos_30d', valor: (l) => (l.n30 == null ? '' : l.n30) }, { titulo: 'anomalias_ativas', valor: (l) => (l.anom == null ? '' : l.anom) },
        { titulo: 'ews_delta_90d', valor: (l) => (l.delta == null ? '' : l.delta) }, { titulo: 'taxa_anbima_destaque', valor: (l) => (l.taxa == null ? '' : (l.taxaTxt || l.taxa)) },
        { titulo: 'ultimo_registro_analise', valor: (l) => l.analise || '' }, { titulo: 'favorito', valor: (l) => (l.fav ? 'sim' : '') }, { titulo: 'livro', valor: (l) => (l.livro ? 'sim' : '') },
      ];
      baixar(`vixradar-empresas-${isoLocal(new Date())}.csv`, csv(vis, cols));
    }
  };
  alvo.onchange = (e) => { const k = e.target.dataset.q; if (k) ir((x) => { if (e.target.value) x.set(k, e.target.value); else x.delete(k); if (k === 'ord') x.set('dir', 'desc'); }); };
}
