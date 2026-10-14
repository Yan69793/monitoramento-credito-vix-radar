/**
 * Pagina do emissor v2 (dossie §7.0.2). Abas na URL (#/empresa/<nome>/<aba>).
 * EWS, piso e drivers exatamente como o Worker devolve (op=ews), serie real de ate
 * 90 dias (op=serie) desenhada em SVG com eixo e tabela alternativa, evidencias
 * CVM/ANBIMA e timeline em <ol>. Comentarios, rodadas, alertas de mercado, arquivo,
 * PDF, Novo Pulso, compartilhar e comparador continuam na v1 e abrem por delegacao.
 */
import { esc, badge, sevOrd, parseISO, fmtCurto, fmtLongo, fmtMes, num, montarRota, fmtDataHora } from '../core/util.js';
import * as D from '../core/data.js';
import { destaqueDe } from './empresas.js';

const ABAS = [
  ['visao', 'Visão geral'], ['eventos', 'Eventos'], ['papeis', 'Papéis ANBIMA'],
  ['rodadas', 'Rodadas de busca', 'v1'], ['alertas', 'Alertas de mercado', 'v1'], ['comentarios', 'Comentários', 'v1'], ['arquivo', 'Arquivo', 'v1'],
];

function grafico(pontos, { titulo, unidade, casas = 0 }) {
  const ok = pontos.filter((p) => p && p.data && typeof p.v === 'number');
  if (ok.length < 2) return `<p class="vx-muted">${ok.length === 1 ? `Um único ponto na janela: ${esc(ok[0].data)} = ${num(ok[0].v, casas)}${unidade}.` : 'Sem série registrada na janela.'}</p>`;
  const W = 640, H = 200, L = 44, R = 12, T = 12, B = 28;
  const vs = ok.map((p) => p.v); let min = Math.min(...vs), max = Math.max(...vs);
  if (min === max) { min -= 1; max += 1; }
  const t0 = parseISO(ok[0].data).getTime(), t1 = parseISO(ok[ok.length - 1].data).getTime() || t0 + 1;
  const x = (d) => L + ((parseISO(d).getTime() - t0) / Math.max(1, t1 - t0)) * (W - L - R);
  const y = (v) => T + (1 - (v - min) / (max - min)) * (H - T - B);
  const path = ok.map((p, i) => `${i ? 'L' : 'M'}${x(p.data).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ');
  const ticks = [min, (min + max) / 2, max];
  return `<figure class="vx-chart" style="margin:0">
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(titulo)}: ${ok.length} pontos de ${esc(ok[0].data)} a ${esc(ok[ok.length - 1].data)}, de ${num(ok[0].v, casas)} a ${num(ok[ok.length - 1].v, casas)}${unidade}">
      <line class="ax" x1="${L}" y1="${H - B}" x2="${W - R}" y2="${H - B}"/><line class="ax" x1="${L}" y1="${T}" x2="${L}" y2="${H - B}"/>
      ${ticks.map((v) => `<text x="${L - 6}" y="${y(v) + 4}" text-anchor="end">${num(v, casas)}</text>`).join('')}
      <text x="${L}" y="${H - 8}">${esc(fmtCurto(parseISO(ok[0].data)))}</text><text x="${W - R}" y="${H - 8}" text-anchor="end">${esc(fmtCurto(parseISO(ok[ok.length - 1].data)))}</text>
      <path class="ln" d="${path}"/>
      ${ok.map((p) => `<circle class="pt" cx="${x(p.data).toFixed(1)}" cy="${y(p.v).toFixed(1)}" r="3"><title>${esc(p.data)}: ${num(p.v, casas)}${unidade}</title></circle>`).join('')}
    </svg>
    <details><summary class="vx-muted">Ver dados em tabela (${ok.length} pontos)</summary>
      <table class="vx-table"><thead><tr><th scope="col" style="padding:6px 10px">Data</th><th scope="col" style="padding:6px 10px">${esc(titulo)}</th></tr></thead>
      <tbody>${ok.map((p) => `<tr><td>${esc(p.data)}</td><td class="n">${num(p.v, casas)}${unidade}</td></tr>`).join('')}</tbody></table>
    </details>
  </figure>`;
}

function blocoEws(c, nome, ews, serie) {
  if (!ews) return `<div class="vx-card"><h2>Score EWS</h2><p class="vx-muted">${c.S.erros.ews ? 'EWS indisponível: ' + esc(c.S.erros.ews) : 'Carregando EWS do emissor…'}</p></div>`;
  const rk = c.S.ews && c.S.ews.porEmpresa[nome];
  const drivers = (ews.decomposicao || ews.drivers || []);
  const delta = serie && typeof serie.ews_delta === 'number' ? serie.ews_delta : null;
  return `<div class="vx-card">
    <h2>Score EWS</h2>
    <div style="display:flex;gap:16px;align-items:baseline;flex-wrap:wrap">
      <span class="vx-ews-big">${num(ews.score)}</span>${badge(ews.label)}
      <span class="vx-muted">${rk ? '#' + rk.posicao + ' no ranking de ' + num(c.S.ews.total) : 'fora do ranking (score zero e sem anomalia)'}</span>
      <span class="vx-muted">Δ 90d: ${delta == null ? 'sem série suficiente' : `<b class="vx-num">${delta > 0 ? '+' : ''}${num(delta, 1)}</b>`}</span>
    </div>
    <h3 style="font-size:var(--vx-fs-12);color:var(--vx-text-2);margin:12px 0 4px">Por que este score</h3>
    <p style="margin:0">Score exibido <b class="vx-num">${num(ews.score)}</b> · score dos sinais sem piso (<code>score_calculado</code>) <b class="vx-num">${num(ews.score_calculado, 1)}</b> · piso aplicado (<code>piso_aplicado</code>): <b>${ews.piso_aplicado ? 'sim' : 'não'}</b>${ews.piso_aplicado ? ` · piso <b class="vx-num">${num(ews.piso_valor)}</b>${ews.piso_causa ? ' por ' + esc(ews.piso_causa) : ''}` : ''}. Cálculo do Worker em ${esc(ews.calculado_em || 'data não informada')}; nada aqui é recalculado no navegador.</p>
    <ul class="vx-drivers" aria-label="Drivers do score">${drivers.length ? drivers.map((d) => `<li>
      <span><b>${esc(d.tag || d.fator || d.tipo_sinal || 'sinal')}</b>${d.tipo === 'floor' ? ' <span class="vx-muted">(piso)</span>' : ''}<br><span class="vx-muted">${esc(d.justificativa_curta || d.materialidade_credito || '')}${d.data_evento ? ' · ' + esc(d.data_evento) : ''}${d.verificado === false ? ' · <span class="vx-tag-inferido">não verificado</span>' : ''}</span></span>
      <span class="vx-num">${d.pontos != null ? (d.pontos > 0 ? '+' : '') + num(d.pontos, 1) : (d.peso != null ? num(d.peso, 1) : '—')}</span>
    </li>`).join('') : '<li class="vx-muted">Sem drivers no cálculo atual.</li>'}</ul>
  </div>`;
}

function timeline(evs) {
  if (!evs.length) return '<p class="vx-muted">Nenhum evento nos últimos 90 dias. Isto não é ausência de risco: a cobertura depende das fontes lidas.</p>';
  const porMes = {}; evs.forEach((e) => { const k = String(e.data_evento).slice(0, 7); (porMes[k] = porMes[k] || []).push(e); });
  return `<ol class="vx-timeline">${Object.keys(porMes).sort().reverse().map((k) => `<li><h3>${esc(fmtMes(parseISO(k + '-01')))}</h3><ol>${porMes[k].map((e) => {
    const url = e.fonte_primaria || e.url || '';
    return `<li>${badge(e._sev)} <span class="vx-num vx-muted">${esc(fmtCurto(parseISO(e.data_evento)))}</span> ${esc(e.titulo || e.evento || '')}
      <div class="vx-muted" style="font-size:var(--vx-fs-12)">${esc(D.ORIGENS[e._origem] || e._origem)}${/^https?:\/\//i.test(url) ? ` · <a href="${esc(url)}" target="_blank" rel="noopener">${esc(url.split('/')[2])}</a>` : ''}</div></li>`;
  }).join('')}</ol></li>`).join('')}</ol>`;
}

function papeis(serie) {
  if (!serie) return '<p class="vx-muted">Carregando papéis…</p>';
  const ps = Array.isArray(serie.papeis) ? serie.papeis : [];
  if (!ps.length) return `<p class="vx-muted">Sem papéis ANBIMA na janela${serie.data_referencia ? ' de referência ' + esc(serie.data_referencia) : ''}.</p>`;
  const dest = destaqueDe(serie);
  return `<p class="vx-muted">Fonte: ANBIMA via Worker (op=serie) · data de referência ${esc(serie.data_referencia || 'não informada')}${dest ? ' · destaque ' + esc(dest.codigo_ativo) + (serie.destaque_motivo ? ' (' + esc(serie.destaque_motivo) + ')' : '') : ''}</p>
  <ul class="vx-papeis">${ps.map((p) => `<li><button type="button" data-papel="${esc(p.codigo_ativo)}" aria-expanded="false">
    <span><b>${esc(p.codigo_ativo)}</b> <span class="vx-muted">${esc(p.grupo || '')} · venc. ${esc(p.data_vencimento || 'n/d')}</span></span>
    <span class="vx-num">${esc(p.taxa_display || (p.taxa_indicativa != null ? num(p.taxa_indicativa, 2) + '%' : '—'))}</span></button>
    <div hidden data-papel-hist="${esc(p.codigo_ativo)}">${grafico((p.historico || []).map((h) => ({ data: h.data, v: h.taxa_indicativa != null ? h.taxa_indicativa : h.percentual_taxa })), { titulo: 'Taxa indicativa ' + p.codigo_ativo, unidade: '%', casas: 2 })}</div></li>`).join('')}</ul>`;
}

export function renderEmissor(alvo, c, rota) {
  const S = c.S; const nome = rota.args[0]; const aba = ABAS.some((a) => a[0] === rota.args[1]) ? rota.args[1] : 'visao';
  if (!c.uni.lista.includes(nome)) { alvo.innerHTML = `<div class="vx-estado erro" role="alert">Emissor "${esc(nome)}" não está no universo monitorado. <button type="button" class="vx-btn" data-ir="#/empresas">Voltar a Empresas</button></div>`; return; }
  const setor = c.setorDe[nome] || '';
  // carregamento sob demanda: EWS do emissor (do ranking quando houver) e serie 90d
  let ews = S.ews && S.ews.porEmpresa[nome] ? S.ews.porEmpresa[nome] : S.cacheEwsEmp[nome];
  if (!ews && S.ews && !S.cacheEwsEmp[nome] && !S.erros['ews:' + nome]) {
    S.cacheEwsEmp[nome] = null;
    D.carregarEWSEmissor(nome).then((v) => { S.cacheEwsEmp[nome] = v; }).catch((e) => { S.erros['ews:' + nome] = e.message; }).finally(() => { if (location.hash.includes(encodeURIComponent(nome))) c.ir(location.hash, { substituir: true }); });
  }
  const serie = S.cacheSerie[nome];
  if (serie === undefined && !S.erros['serie:' + nome]) {
    S.cacheSerie[nome] = null;
    D.carregarSerie(nome, 90).then((v) => { S.cacheSerie[nome] = v; }).catch((e) => { S.erros['serie:' + nome] = e.message; delete S.cacheSerie[nome]; }).finally(() => { if (location.hash.includes(encodeURIComponent(nome))) c.ir(location.hash, { substituir: true }); });
  }
  const evs = (S.estado ? S.estado.eventos : []).filter((e) => e._empresa === nome).sort((a, b) => String(b.data_evento).localeCompare(String(a.data_evento)) || sevOrd(a._sev) - sevOrd(b._sev));
  const est = S.estado && S.estado.emissores[nome];
  const fav = c.favs.has(nome);
  const cvm = evs.filter((e) => e._origem === 'comunicado' || e._origem === 'fato_relevante');
  const erroSerie = S.erros['serie:' + nome];
  let corpo = '';
  if (aba === 'visao') {
    const ewsSerie = serie && Array.isArray(serie.ews_serie) ? serie.ews_serie.map((h) => ({ data: h.data, v: h.score })) : [];
    const dest = destaqueDe(serie);
    corpo = `<div class="vx-grid2">
      ${blocoEws(c, nome, ews, serie)}
      <div class="vx-card"><h2>Série EWS · até 90 dias</h2>${erroSerie ? `<p class="vx-muted">Série indisponível: ${esc(erroSerie)}</p>` : (serie ? grafico(ewsSerie, { titulo: 'Score EWS', unidade: '' }) : '<div class="vx-skel"></div>')}
        <p class="vx-muted" style="font-size:var(--vx-fs-11)">Fonte: histórico EWS do Worker (op=serie, horizonte 90)${serie && serie.updated_at ? ' · série ANBIMA atualizada em ' + esc(fmtDataHora(serie.updated_at)) : ''}</p></div>
      <div class="vx-card"><h2>Taxa ANBIMA do papel destaque</h2>${!serie ? (erroSerie ? '<p class="vx-muted">Indisponível.</p>' : '<div class="vx-skel"></div>') : (dest ? `<p class="vx-muted">${esc(dest.codigo_ativo)} · ${esc(dest.grupo || '')} · último ${esc(dest.taxa_display || '')}</p>` + grafico((dest.historico || []).map((h) => ({ data: h.data, v: h.taxa_indicativa != null ? h.taxa_indicativa : h.percentual_taxa })), { titulo: 'Taxa indicativa', unidade: '%', casas: 2 }) : '<p class="vx-muted">Sem papel destaque na janela.</p>')}</div>
      <div class="vx-card"><h2>Evidências CVM recentes</h2>${cvm.length ? `<ul class="vx-drivers">${cvm.slice(0, 8).map((e) => `<li><span>${badge(e._sev)} ${esc(e.titulo || '')}<br><span class="vx-muted">${esc(e.data_evento)}${/^https?:\/\//i.test(e.fonte_primaria || '') ? ` · <a href="${esc(e.fonte_primaria)}" target="_blank" rel="noopener">documento</a>` : ''}</span></span></li>`).join('')}</ul>` : '<p class="vx-muted">Nenhum comunicado CVM atribuído a este emissor nos últimos 90 dias.</p>'}
        <p class="vx-muted" style="font-size:var(--vx-fs-11)">Último registro de análise: ${est && est.timestamp ? esc(fmtDataHora(est.timestamp)) : 'não registrado'}</p></div>
    </div>`;
  } else if (aba === 'eventos') corpo = timeline(evs);
  else if (aba === 'papeis') corpo = erroSerie ? `<p class="vx-muted">Papéis indisponíveis: ${esc(erroSerie)}</p>` : papeis(serie);
  else corpo = `<div class="vx-estado">Esta aba segue na versão clássica nesta fase, sem perda de função. <button type="button" class="vx-btn vx-btn-primary" data-v1="nenhuma" data-empresa="${esc(nome)}">Abrir ${esc(ABAS.find((a) => a[0] === aba)[1])} na versão clássica</button></div>`;

  alvo.innerHTML = `
    <nav class="vx-crumb" aria-label="Trilha"><button type="button" data-ir="#/empresas">Empresas</button> / <button type="button" data-ir="${esc(montarRota('empresas', [], new URLSearchParams({ setor })))}">${esc(setor)}</button> / <span aria-current="page">${esc(nome)}</span></nav>
    <header class="vx-emp-h">
      <h1>${esc(nome)}</h1>
      ${ews ? `<span class="vx-num" style="font-size:var(--vx-fs-20)">${num(ews.score)}</span>${badge(ews.label)}` : ''}
      ${c.favOn ? `<button type="button" class="vx-star" data-fav="${esc(nome)}" aria-pressed="${fav}" aria-label="${fav ? 'Remover dos' : 'Adicionar aos'} favoritos">${fav ? '★' : '☆'}</button>` : ''}
      <div class="vx-acts" style="margin:0">
        <button type="button" class="vx-btn" data-v1="comparar" data-empresa="${esc(nome)}">Comparar</button>
        <button type="button" class="vx-btn" data-v1="pulso" data-empresa="${esc(nome)}">Novo Pulso</button>
        <button type="button" class="vx-btn" data-v1="share" data-empresa="${esc(nome)}">Compartilhar</button>
        <button type="button" class="vx-btn" data-v1="pdf" data-empresa="${esc(nome)}">PDF</button>
      </div>
    </header>
    <div class="vx-abas" role="tablist" aria-label="Seções do emissor">${ABAS.map(([k, l, v1]) => `<button type="button" role="tab" class="vx-aba" id="vx-aba-${k}" aria-selected="${k === aba}" aria-controls="vx-painel" tabindex="${k === aba ? 0 : -1}" data-aba="${k}">${esc(l)}${v1 ? ' <span class="vx-muted">↗</span>' : ''}</button>`).join('')}</div>
    <section id="vx-painel" role="tabpanel" aria-labelledby="vx-aba-${aba}" tabindex="0">${corpo}</section>`;

  alvo.onclick = async (e) => {
    const t = e.target.closest('button'); if (!t) return;
    if (t.dataset.aba) c.ir(montarRota('empresa', [nome, t.dataset.aba]), { substituir: true });
    else if (t.dataset.fav) { t.disabled = true; await c.alternarFav(nome); }
    else if (t.dataset.papel) {
      const box = alvo.querySelector(`[data-papel-hist="${CSS.escape(t.dataset.papel)}"]`);
      const ab = t.getAttribute('aria-expanded') !== 'true'; t.setAttribute('aria-expanded', String(ab)); if (box) box.hidden = !ab;
    }
  };
  alvo.onkeydown = (e) => {
    const t = e.target; if (!t.dataset || !t.dataset.aba) return;
    const i = ABAS.findIndex((a) => a[0] === t.dataset.aba);
    let n = null; if (e.key === 'ArrowRight') n = (i + 1) % ABAS.length; else if (e.key === 'ArrowLeft') n = (i - 1 + ABAS.length) % ABAS.length; else if (e.key === 'Home') n = 0; else if (e.key === 'End') n = ABAS.length - 1;
    if (n != null) { e.preventDefault(); const b = alvo.querySelector(`#vx-aba-${ABAS[n][0]}`); if (b) b.focus(); }
  };
}
export { fmtLongo };
