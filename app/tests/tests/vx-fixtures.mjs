// Fixtures deterministicas da v2 (e da correcao de severidade da v1).
// Datas relativas ao dia do teste, em dia util, para os filtros de janela
// valerem sempre. Nenhum dado real de producao: nomes de emissor sao os do
// universo publico do index.html, titulos e numeros sao ficticios de teste.
// Sessao: radar_user/radar_jwt sao valores de teste deste harness local; a API
// e 100% interceptada por page.route, nada sai para a rede.

export const API = 'https://api.vixradar.com';

export function diaUtil(n) { // n-esimo dia util para tras (0 = hoje ou ultimo dia util)
  const d = new Date(); d.setHours(12, 0, 0, 0);
  let k = -1;
  for (;;) {
    const w = d.getDay();
    if (w !== 0 && w !== 6) { k += 1; if (k === n) break; }
    d.setDate(d.getDate() - 1);
  }
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const ev = (id, classificacao, data, titulo, extra = {}) => ({
  id, classificacao, data_evento: data, titulo,
  evento: `Descrição de teste do evento ${id}.`,
  fonte_tipo: 'CVM', fonte_primaria: `https://www.rad.cvm.gov.br/teste/${id}`,
  impacto_credito: `Inferência de teste para ${id}.`, memo_acao_sugerida: `Recomendação de teste para ${id}.`,
  escopo: 'idiossincratico', ...extra,
});

/** Cinco severidades no MESMO dia, uma por emissor: a ordem do feed e o teste. */
export function estadoCincoSeveridades() {
  const d0 = diaUtil(1);
  return {
    ok: true, week: '2026-W42', updated_at: new Date().toISOString(),
    results: {
      Azul: { empresa: 'Azul', timestamp: '2026-10-13T21:10:00Z', eventos: [ev('t-eco', 'ECO', d0, 'Evento ECO de teste')] },
      Light: { empresa: 'Light', timestamp: '2026-10-13T21:11:00Z', eventos: [ev('t-alerta', 'ALERTA', d0, 'Evento ALERTA de teste')] },
      Oi: { empresa: 'Oi', timestamp: '2026-10-13T21:12:00Z', eventos: [ev('t-relevante', 'RELEVANTE', d0, 'Evento RELEVANTE de teste')] },
      Braskem: { empresa: 'Braskem', timestamp: '2026-10-13T21:13:00Z', eventos: [ev('t-critico', 'CRITICO', d0, 'Evento CRITICO de teste')] },
      Vale: { empresa: 'Vale', timestamp: '2026-10-13T21:14:00Z', eventos: [ev('t-atencao', 'ATENCAO', d0, 'Evento ATENCAO de teste')] },
      Sabesp: {
        empresa: 'Sabesp', timestamp: '2026-10-13T21:15:00Z', eventos: [
          ev('t-s1', 'RELEVANTE', diaUtil(3), 'Sabesp evento relevante antigo', { fonte_tipo: 'IMPRENSA', fonte_primaria: 'https://valor.globo.com/teste/s1' }),
          ev('t-s2', 'CRITICO', diaUtil(12), 'Sabesp evento crítico de 12 dias úteis', { fonte_tipo: 'RATING' }),
          ev('t-s3', 'ECO', diaUtil(40), 'Sabesp evento fora da janela de 30d'),
        ],
      },
    },
  };
}
export const IDS_CINCO = ['t-critico', 't-alerta', 't-atencao', 't-relevante', 't-eco'];

export const ews = () => ({
  ok: true, total: 4, calculado_em: diaUtil(0),
  ranking: [
    { empresa: 'Braskem', score: 72, label: 'CRITICO', cor: '#DC2626', score_calculado: 58.5, piso_aplicado: true, piso_valor: 72, piso_causa: 'recuperacao_judicial', calculado_em: diaUtil(0),
      decomposicao: [{ tag: 'piso-rj', tipo: 'floor', pontos: 72, data_evento: diaUtil(1), justificativa_curta: 'Piso de teste', verificado: true }, { tag: 'downgrade', pontos: 30.5, justificativa_curta: 'Driver de teste', verificado: true }] },
    { empresa: 'Light', score: 45, label: 'ALERTA', cor: '#EA580C', score_calculado: 45, piso_aplicado: false, decomposicao: [{ tag: 'covenant', pontos: 45 }] },
    { empresa: 'Vale', score: 20, label: 'ATENCAO', cor: '#D97706', score_calculado: 20, piso_aplicado: false, decomposicao: [{ tag: 'liquidez', pontos: 20 }] },
    { empresa: 'Sabesp', score: 12, label: 'ESTAVEL', cor: '#2D6A4F', score_calculado: 12, piso_aplicado: false, decomposicao: [{ tag: 'imprensa', pontos: 12 }] },
  ],
});

export const serie = (empresa) => ({
  ok: true, empresa, horizonte: 90,
  ews_serie: [{ data: diaUtil(30), score: 40 }, { data: diaUtil(15), score: 55 }, { data: diaUtil(1), score: 72 }],
  ews_atual: 72, ews_delta: 32, data_referencia: diaUtil(1), updated_at: new Date().toISOString(),
  papeis: [{ codigo_ativo: 'BRKMA1', grupo: 'DI+', data_vencimento: '2029-05-15', taxa_indicativa: 2.15, taxa_display: 'DI + 2,15%', historico: [{ data: diaUtil(20), taxa_indicativa: 1.9 }, { data: diaUtil(1), taxa_indicativa: 2.15 }] }],
  destaque: { codigo_ativo: 'BRKMA1', grupo: 'DI+', taxa_indicativa: 2.15, taxa_display: 'DI + 2,15%', historico: [{ data: diaUtil(20), taxa_indicativa: 1.9 }, { data: diaUtil(1), taxa_indicativa: 2.15 }] },
  destaque_motivo: 'maior_liquidez',
});

export const health = () => ({
  ok: true, versao: 'v4.9.267-teste', ts: new Date().toISOString(),
  painel_atualizado_em: '2026-10-14T04:35:04.523Z', painel_fresco: true, painel_emissores_deferidos: 85, painel_emissores_total: 104,
  cvm_ingestao_recebidos: 9507, cvm_ingestao_atribuidos: 820, cvm_ingestao_quarentena: 8687,
  cvm_atribuicao_por_cnpj: 474, cvm_atribuicao_por_nome: 346, cvm_atribuicao_quarentena: 747, cvm_atribuicao_sem_dono: 7940, cvm_atribuicao_cobertura_pct: 52.3,
});

/**
 * Intercepta toda chamada a API. opts.estado substitui o estado; opts.falhar = Set de ops
 * que devolvem 500; opts.atraso (ms) segura op=state para o teste de carregamento.
 */
export async function mockApi(page, opts = {}) {
  const chamadas = [];
  // /cdn-cgi/* (email-decode e RUM) e injetado pela Cloudflare no HTML de producao que esta no repo;
  // localmente nao existe. Responder vazio evita 404/405 de ambiente, sem esconder erro do app.
  await page.route('**/cdn-cgi/**', (r) => r.fulfill({ status: 200, contentType: 'application/javascript', body: '' }));
  await page.route(`${API}/**`, async (route) => {
    const req = route.request(); const u = new URL(req.url());
    const op = u.searchParams.get('op') || '';
    let body = {}; try { body = req.postDataJSON() || {}; } catch (_) { /* GET */ }
    chamadas.push({ method: req.method(), op, action: body.action || '' });
    const json = (o, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(o) });
    if (opts.falhar && opts.falhar.has(op || body.action || 'health')) return json({ ok: false, erro: 'falha simulada' }, 500);
    if (op === 'state') { if (opts.atraso) await new Promise((r) => setTimeout(r, opts.atraso)); return json(opts.estado || estadoCincoSeveridades()); }
    if (op === 'ews') return u.searchParams.get('empresa') ? json({ ok: true, ews: { empresa: u.searchParams.get('empresa'), score: 0, label: 'ESTAVEL', score_calculado: 0, piso_aplicado: false, decomposicao: [], calculado_em: diaUtil(0) } }) : json(opts.ews || ews());
    if (op === 'serie') return json(serie(u.searchParams.get('empresa')));
    if (op === 'anomalias') return json({ ok: true, anomalias_ativas: 1, resumo: [{ empresa: 'Braskem', total: 2, tem_critica: true, tipos: ['taxa'], ultima_deteccao: diaUtil(1) }], detalhe: {} });
    if (req.method() === 'GET' && !op) return json(health());
    if (body.action === 'favorito_listar') return json({ ok: true, favoritos: ['Vale'] });
    if (body.action === 'favorito_toggle') return json({ ok: true, favoritos: ['Vale', body.empresa] });
    return json({ ok: true });
  });
  return chamadas;
}

/** Sessao de TESTE (valores ficticios, nunca credencial real). */
export async function sessaoTeste(page, { flag = null } = {}) {
  await page.addInitScript(([f]) => {
    try {
      localStorage.setItem('radar_user', JSON.stringify({ email: 'qa@vx.test', nome: 'QA Teste' }));
      localStorage.setItem('radar_jwt', 'jwt-de-teste-local');
      localStorage.setItem('radar_onboarding_visto', '1');
      if (f) localStorage.setItem('vx_ui_telas', JSON.stringify({ eventos: f, empresas: f }));
    } catch (_) { /* storage bloqueado */ }
  }, [flag]);
}
