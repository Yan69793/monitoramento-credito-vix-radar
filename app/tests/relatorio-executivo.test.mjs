// REL-EXEC2 (20/10/2026): testes da logica do Relatorio Executivo 2.0 (app/js/relatorio-executivo.js).
// Rodar: node --test app/tests/relatorio-executivo.test.mjs
// Cada regra tem prova de duas pontas: o caso ruim e reprovado e o caso bom e aceito.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const R = require(path.join(APP, 'js', 'relatorio-executivo.js'));

const AGORA = new Date(2026, 9, 20, 10, 0, 0); // 20/10/2026
const iso = (diasAtras) => {
  const d = new Date(AGORA.getFullYear(), AGORA.getMonth(), AGORA.getDate() - diasAtras);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const ev = (emp, diasAtras, cls, titulo, extra = {}) =>
  ({ _empresa: emp, data_evento: iso(diasAtras), classificacao: cls, titulo, ...extra });

/* ---------- deduplicacao ---------- */

test('dedup: funde o mesmo fato reportado por duas fontes e soma as fontes', () => {
  const lista = [
    ev('Americanas', 3, 'CRITICO', 'Americanas protocola pedido de recuperação extrajudicial', { fonte_primaria: 'https://www.valor.com.br/empresas/2026/10/17/americanas-pede-rj' }),
    ev('Americanas', 3, 'CRITICO', 'Americanas protocola pedido de recuperação extrajudicial na Justiça', { fonte_primaria: 'https://www.infomoney.com.br/mercados/americanas-re', memo_importancia_credito: 'Eleva risco de default dos bonds, com dívida de R$ 12 bilhões.' })
  ];
  const out = R.deduplicarEventos(lista);
  assert.equal(out.length, 1);
  assert.equal(out[0].n_reportes, 2);
  assert.equal(out[0].fontes.length, 2);
  assert.match(out[0].memo_importancia_credito, /R\$ 12 bilhões/, 'mantem o registro mais completo');
});

test('dedup: NAO funde eventos distintos do mesmo emissor no mesmo dia', () => {
  const lista = [
    ev('Gol', 2, 'CRITICO', 'Gol suspende pagamento de cupom de debêntures'),
    ev('Gol', 2, 'RELEVANTE', 'Gol anuncia nova rota para Miami com frota própria')
  ];
  assert.equal(R.deduplicarEventos(lista).length, 2);
});

test('dedup: NAO funde mesmo titulo de emissores diferentes nem datas distantes', () => {
  const t = 'Fitch rebaixa rating corporativo para BB';
  assert.equal(R.deduplicarEventos([ev('CSN', 2, 'CRITICO', t), ev('Usiminas', 2, 'CRITICO', t)]).length, 2);
  assert.equal(R.deduplicarEventos([ev('CSN', 2, 'CRITICO', t), ev('CSN', 20, 'CRITICO', t)]).length, 2);
});

test('dedup: URL de homepage compartilhada nao funde eventos diferentes', () => {
  const home = 'https://ri.empresa.com.br/';
  const out = R.deduplicarEventos([
    ev('Marfrig', 1, 'RELEVANTE', 'Marfrig divulga resultado do terceiro trimestre', { fonte_primaria: home }),
    ev('Marfrig', 1, 'RELEVANTE', 'Marfrig contrata linha de crédito sindicalizada', { fonte_primaria: home })
  ]);
  assert.equal(out.length, 2);
});

/* ---------- texto generico ---------- */

test('limparGenerico: remove frase vazia e mantem frase com numero', () => {
  const t = 'Acompanhar de perto os desdobramentos. A dívida líquida subiu para 4,2x o EBITDA. Pode impactar o crédito da empresa.';
  const out = R.limparGenerico(t, 'Outro titulo qualquer');
  assert.match(out, /4,2x o EBITDA/);
  assert.doesNotMatch(out, /desdobramentos/i);
  assert.doesNotMatch(out, /Pode impactar o crédito/i);
});

test('limparGenerico: memo igual ao titulo some e campo vazio fica vazio', () => {
  const titulo = 'Moody’s rebaixa rating da Light para Caa1 com perspectiva negativa';
  assert.equal(R.limparGenerico(titulo, titulo), '');
  assert.equal(R.limparGenerico('Sem impacto relevante.', 'x'), '');
  assert.equal(R.limparGenerico('', 'x'), '');
});

test('limparGenerico: frase generica com numero NAO e removida', () => {
  assert.match(R.limparGenerico('Pode impactar o crédito em R$ 300 milhões ao ano.', 't'), /300 milhões/);
});

/* ---------- comparacao de janelas ---------- */

test('compararJanelas: classifica deterioracao, melhoria, novo e saiu', () => {
  const E = [
    // A: sem eventos antes, critico agora -> deterioracao
    ev('A', 2, 'CRITICO', 'a1'),
    // B: 2 criticos antes, 1 agora -> melhoria
    ev('B', 20, 'CRITICO', 'b1'), ev('B', 22, 'CRITICO', 'b2'), ev('B', 3, 'CRITICO', 'b3'),
    // C: relevante novo sem historico -> novo
    ev('C', 4, 'RELEVANTE', 'c1'),
    // D: tinha critico antes, nada agora -> saiu (NAO e melhoria)
    ev('D', 21, 'CRITICO', 'd1'),
    // E: relevante antes e agora -> estavel
    ev('E', 21, 'RELEVANTE', 'e1'), ev('E', 3, 'RELEVANTE', 'e2')
  ];
  const c = R.compararJanelas(E, 14, AGORA);
  const st = (e) => c.porEmpresa[e].status;
  assert.equal(st('A'), 'deterioracao');
  assert.equal(st('B'), 'melhoria');
  assert.equal(st('C'), 'novo');
  assert.equal(st('D'), 'saiu');
  assert.equal(st('E'), 'estavel');
  assert.deepEqual(c.melhorias.map((x) => x.empresa), ['B']);
  assert.ok(!c.melhorias.some((x) => x.empresa === 'D'), 'ausencia de evento nao e melhora');
  assert.equal(c.atual.crit, 2);
  assert.equal(c.anterior.crit, 3);
  assert.equal(c.anterior_completo, true);
  assert.equal(R.compararJanelas([], 60, AGORA).anterior_completo, false, 'janela dupla > 90 dias vem truncada');
});

test('compararJanelas: escalada de relevante para critico e deterioracao', () => {
  const c = R.compararJanelas([ev('F', 20, 'RELEVANTE', 'f1'), ev('F', 2, 'CRITICO', 'f2')], 14, AGORA);
  assert.equal(c.porEmpresa.F.status, 'deterioracao');
  assert.match(c.porEmpresa.F.motivo, /escalou/);
});

/* ---------- EWS ---------- */

test('explicarEws: top 3 por pontos, percentual, confianca e piso', () => {
  const item = {
    empresa: 'Gol', score: 72, label: 'ALERTA', piso_aplicado: true, piso_valor: 60, piso_causa: 'recuperação judicial',
    decomposicao: [
      { fator: 'Rating', pontos: 10, peso_max: 15, direcao: 'deterioracao', confianca: 0.9, fonte: { url: 'https://agencia.com/r1' } },
      { fator: 'Eventos críticos', pontos: 30, peso_max: 40, direcao: 'deterioracao', confianca: 0.6, data_evento: iso(2) },
      { fator: 'Spread', pontos: 20, direcao: 'deterioracao' },
      { fator: 'Liquidez', pontos: 5, direcao: 'melhora' },
      { fator: 'Zerado', pontos: 0 }
    ]
  };
  const e = R.explicarEws(item);
  assert.deepEqual(e.top.map((f) => f.fator), ['Eventos críticos', 'Spread', 'Rating']);
  assert.equal(e.total_fatores, 4);
  assert.ok(Math.abs(e.pctTop3 - 60 / 65) < 1e-9);
  assert.equal(e.confianca, 'média');
  assert.equal(e.piso.causa, 'recuperação judicial');
  assert.equal(e.melhoras.length, 1);
  assert.equal(e.top[2].fonte, 'https://agencia.com/r1');
});

test('explicarEws: sem confianca informada devolve n/d, nunca inventa', () => {
  const e = R.explicarEws({ empresa: 'X', score: 10, label: 'ESTAVEL', decomposicao: [{ fator: 'a', pontos: 4 }] });
  assert.equal(e.confianca, 'n/d');
  assert.equal(e.piso, null);
  assert.equal(R.explicarEws(null), null);
});

test('EWSVAR7D1: com score de 7 dias a variacao aparece no item e na tabela', () => {
  const e = R.explicarEws({ empresa: 'Gol', score: 72, label: 'ALERTA', score_anterior_7d: 64.5, delta_7d: 7.5, data_anterior_7d: '2026-10-13', decomposicao: [{ fator: 'a', pontos: 4 }] });
  assert.deepEqual(e.variacao7d, { anterior: 64.5, delta: 7.5, data: '2026-10-13' });
  const html = R.secEws({ ews: [e] });
  assert.match(html, /Δ 7 dias/);
  assert.match(html, /\+7,5/);
  assert.match(html, /era 64,5/);
  assert.doesNotMatch(html, /a API pública do EWS não entrega o score anterior/);
});

test('EWSVAR7D1: sem score anterior (null ou ausente) nao inventa variacao', () => {
  const semCampo = R.explicarEws({ empresa: 'X', score: 10, decomposicao: [] });
  const nulo = R.explicarEws({ empresa: 'Y', score: 10, score_anterior_7d: null, delta_7d: null, decomposicao: [] });
  assert.equal(semCampo.variacao7d, null);
  assert.equal(nulo.variacao7d, null);
  const html = R.secEws({ ews: [semCampo, nulo] });
  assert.doesNotMatch(html, /Δ 7 dias/);
  assert.match(html, /Variação de 7 dias indisponível/);
});

test('EWSVAR7D1: queda de score sai com sinal de menos e emissor sem historico mostra traco', () => {
  const caiu = R.explicarEws({ empresa: 'A', score: 30, score_anterior_7d: 40, delta_7d: -10, decomposicao: [] });
  const sem = R.explicarEws({ empresa: 'B', score: 20, decomposicao: [] });
  const html = R.secEws({ ews: [caiu, sem] });
  assert.match(html, /−10/);
  assert.match(html, /<td class="num">—<\/td>/);
});

/* ---------- metricas ---------- */

test('metricasVerificaveis: exige valor e fonte ou referencia', () => {
  const curadas = {
    Emp: [
      { label: 'Rating', value: 'AA-', ref: 'S&P 08/2026' },
      { label: 'Alavancagem', value: '3,1x', fonte: 'ITR 2T26', as_of: '2026-06-30', status: 'breach' },
      { label: 'EBITDA', value: '1,2 bi' },                       // sem fonte: fora
      { label: 'Dívida Líquida', value: '', fonte: 'ITR 2T26' },   // sem valor: fora
      { label: 'Receita', value: '9 bi', fonte: 'ITR' }            // categoria nao reportada
    ]
  };
  const m = R.metricasVerificaveis('Emp', curadas, null);
  assert.deepEqual(m.linhas.map((l) => l.label), ['Rating', 'Alavancagem']);
  assert.ok(m.ausentes.includes('Liquidez') && m.ausentes.includes('Covenants'));
  assert.ok(!m.ausentes.includes('Rating'));
  assert.equal(R.ratingTxt('Emp', curadas), 'AA- (S&P 08/2026)');
  assert.equal(R.ratingTxt('Outra', curadas), '');
});

test('metricasVerificaveis: taxa indicativa so entra da anomalia de spread', () => {
  const an = [{ tipo: 'volume', severidade: 'relevante', dados: { fator: 3 } },
    { tipo: 'spread', severidade: 'critica', dados: { taxa_atual_pct: 14.35, taxa_media_pct: 12.1, data: iso(1) } }];
  const m = R.metricasVerificaveis('Emp', {}, an);
  assert.equal(m.linhas.length, 1);
  assert.match(m.linhas[0].value, /14,35%/);
  assert.ok(!m.ausentes.includes('Spread'));
  assert.equal(R.metricasVerificaveis('Emp', {}, []).linhas.length, 0);
});

/* ---------- documento ---------- */

function fixture(n) {
  const evs = [];
  for (let i = 0; i < n; i++) {
    const emp = `Emissor ${String.fromCharCode(65 + (i % 12))}${Math.floor(i / 12)}`;
    evs.push(ev(emp, (i * 3) % 26, i % 3 === 0 ? 'CRITICO' : 'RELEVANTE', `Fato número ${i} sobre covenant e refinanciamento do emissor ${emp}`, {
      memo_acontecimento: `Em ${iso(1)} o emissor divulgou fato ${i} com impacto de R$ ${i + 10} milhões. Acompanhar de perto os desdobramentos.`,
      memo_importancia_credito: `Pressiona a cobertura de juros em ${i + 1} décimos.`,
      memo_monitorar: `Verificar vencimento de R$ ${i + 50} milhões no próximo trimestre.`,
      fonte_primaria: `https://www.cvm.gov.br/docs/fato-${i}`
    }));
  }
  return evs;
}

const BRAND = { theme: R.PRESETS.sobrio_dark_navy, gestora: 'Gestora <Teste>', analista: 'Ana', credencial: 'CNPI 123', cnpj: '00.000.000/0001-00', logo: '' };
const OPTS = (extra = {}) => ({ agora: AGORA, semana: '2026-W43', setorDe: { 'Emissor A0': 'Energia' }, curadas: {}, anomalias: {}, ...extra });

test('buildHtml: executivo nao traz anexo, completo traz, e ambos sao HTML valido', () => {
  const evs = fixture(30);
  const exe = R.buildHtml(14, evs, [], BRAND, OPTS({ tipo: 'executivo' }));
  const comp = R.buildHtml(14, evs, [], BRAND, OPTS({ tipo: 'completo' }));
  const anx = R.buildHtml(14, evs, [], BRAND, OPTS({ tipo: 'anexo' }));
  assert.doesNotMatch(exe, /class="anexo-h/);
  assert.match(comp, /class="anexo-h/);
  assert.match(anx, /class="anexo-h/);
  assert.doesNotMatch(anx, /Fichas dos emissores prioritários/);
  for (const d of [exe, comp, anx]) {
    assert.ok(d.startsWith('<!DOCTYPE html>') && d.endsWith('</body></html>'));
    assert.doesNotMatch(d, /\$\{|undefined|NaN|\[object/);
    assert.equal((d.match(/<script/g) || []).length, 1, 'so o script salvarPdf');
    assert.equal(d.split('</head><body>').length, 2);
  }
  assert.ok(comp.length > exe.length);
});

test('buildHtml: no maximo 5 fichas no executivo, todas as demais no anexo', () => {
  const evs = fixture(30);
  const exe = R.buildHtml(14, evs, [], BRAND, OPTS());
  assert.ok((exe.match(/<article class="ficha"/g) || []).length <= 5);
  const comp = R.buildHtml(30, evs, [], BRAND, OPTS({ tipo: 'completo' }));
  assert.equal((comp.match(/<article class="ev-card"/g) || []).length, 30);
});

test('buildHtml: escapa HTML do usuario, bloqueia URL perigosa e respeita white-label', () => {
  const evs = [
    ev('Emp <b>X</b>', 1, 'CRITICO', 'Titulo <img src=x onerror=alert(1)>', { fonte_primaria: 'javascript:alert(1)', memo_acontecimento: '<script>alert(1)</script> ocorreu em 10 de outubro com R$ 5 mi' }),
    ev('Emp <b>X</b>', 1, 'CRITICO', 'Outro fato', { fonte_primaria: 'https://ok.com.br/a?x=1&y=2' })
  ];
  const d = R.buildHtml(7, evs, [], BRAND, OPTS({ tipo: 'completo' }));
  assert.doesNotMatch(d, /<img src=x/);
  assert.doesNotMatch(d, /<script>alert/);
  assert.doesNotMatch(d, /href="javascript/i);
  assert.match(d, /Emp &lt;b&gt;X&lt;\/b&gt;/);
  assert.match(d, /href="https:\/\/ok\.com\.br\/a\?x=1&amp;y=2"/);
  assert.match(d, /GESTORA &lt;TESTE&gt;/);
  assert.match(d, /Analista: <strong>Ana<\/strong> · CNPI 123/);
  assert.match(d, /CNPJ 00\.000\.000\/0001-00/);
});

test('buildHtml: separa fato de interpretacao e nao imprime texto generico', () => {
  const d = R.buildHtml(14, fixture(6), [], BRAND, OPTS({ tipo: 'completo' }));
  assert.match(d, /class="rot">Fato</);
  assert.match(d, /class="rot">Interpretação</);
  assert.doesNotMatch(d, /desdobramentos/i);
  assert.match(d, /Leitura analítica \(interpretação\)/);
});

test('buildHtml: ficha sem metrica verificavel declara a lacuna e nao inventa rating', () => {
  const d = R.buildHtml(14, fixture(3), [], BRAND, OPTS({ tipo: 'completo' }));
  assert.match(d, /Sem métrica financeira verificável na base/);
  assert.doesNotMatch(d, /Rating \(fonte\)<\/th>[\s\S]*?AA/);
  assert.match(d, /Liquidez, Covenants/);
});

test('buildHtml: EWS indisponivel avisa e nao estima score', () => {
  const d = R.buildHtml(14, fixture(4), [], BRAND, OPTS());
  assert.match(d, /Ranking EWS indisponível/);
});

test('buildHtml: EWS com decomposicao aparece com fatores, grafico e confianca', () => {
  const ews = [{ empresa: 'Emissor A0', score: 64, label: 'ALERTA', decomposicao: [{ fator: 'Eventos críticos', pontos: 30, peso_max: 40, direcao: 'deterioracao', confianca: 0.8 }] }];
  const d = R.buildHtml(14, fixture(12), ews, BRAND, OPTS());
  assert.match(d, /<svg[^>]+aria-label="Composição do score EWS por fator"/);
  assert.match(d, /Eventos críticos <b>30\/40<\/b>/);
  assert.match(d, /alta/);
});

test('resumoDecisorio: so afirma o que os numeros sustentam', () => {
  const m = R.montarModelo(14, [ev('A', 2, 'CRITICO', 'a1'), ev('B', 2, 'RELEVANTE', 'b1'), ev('B', 21, 'CRITICO', 'b0')], [], OPTS());
  const r = R.resumoDecisorio(m).join(' | ');
  assert.match(r, /1 evento crítico e 1 relevante em 2 emissores/);
  assert.match(r, /Deterioração em 1 emissor: A/);
  assert.match(r, /Melhora de severidade em B/);
  const vazio = R.resumoDecisorio(R.montarModelo(14, [ev('Z', 2, 'RELEVANTE', 'z')], [], OPTS())).join(' | ');
  assert.match(vazio, /Nenhuma melhora de severidade/);
  assert.match(vazio, /Nenhum emissor com deterioração/);
});

test('priorizar: critico com EWS alto vence relevante isolado', () => {
  const p = R.priorizar([
    { empresa: 'Rel', crit: 0, rel: 3, ewsScore: 20 },
    { empresa: 'Crit', crit: 1, rel: 0, ewsScore: 60, deterioracao: true, novoCritico: true }
  ]);
  assert.equal(p[0].empresa, 'Crit');
  assert.equal(p[0].prioridade, 84);
});

/* ---------- achados da revisao independente (20/10) ---------- */

test('dedup: protocolos CVM diferentes na mesma pagina NAO sao a mesma fonte nem o mesmo evento', () => {
  const u = (n) => `https://www.rad.cvm.gov.br/ENET/frmExibirArquivoIPEExterno.aspx?NumeroProtocoloEntrega=${n}`;
  const out = R.deduplicarEventos([
    ev('Emp', 2, 'RELEVANTE', 'Fato Relevante emissao de debentures', { fonte_primaria: u(111) }),
    ev('Emp', 25, 'CRITICO', 'Fato Relevante rebaixamento de rating', { fonte_primaria: u(222) })
  ]);
  assert.equal(out.length, 2);
  // mesma URL exata e mesmo fato continua fundindo
  const dup = R.deduplicarEventos([
    ev('Emp', 2, 'CRITICO', 'Fato Relevante rebaixamento de rating pela Fitch', { fonte_primaria: u(333) }),
    ev('Emp', 3, 'CRITICO', 'Rebaixamento de rating da companhia', { fonte_primaria: u(333) })
  ]);
  assert.equal(dup.length, 1);
  // mesma URL com fatos a mais de 7 dias nao funde
  assert.equal(R.deduplicarEventos([
    ev('Emp', 2, 'CRITICO', 'Fato Relevante rebaixamento de rating', { fonte_primaria: u(444) }),
    ev('Emp', 20, 'CRITICO', 'Fato Relevante rebaixamento de rating', { fonte_primaria: u(444) })
  ]).length, 2);
});

test('fontes: emissores diferentes com protocolos diferentes recebem numeros diferentes', () => {
  const u = (n) => `https://www.rad.cvm.gov.br/ENET/frmExibirArquivoIPEExterno.aspx?NumeroProtocoloEntrega=${n}`;
  const d = R.buildHtml(7, [ev('X', 1, 'CRITICO', 'Fato da X', { fonte_primaria: u(1) }), ev('Z', 1, 'CRITICO', 'Fato da Z', { fonte_primaria: u(2) })], [], BRAND, OPTS());
  assert.match(d, /<sup class="ref">\[1\]<\/sup>/);
  assert.match(d, /<sup class="ref">\[2\]<\/sup>/);
  assert.match(d, /NumeroProtocoloEntrega=2/);
});

test('janela: atual tem exatamente N dias contando hoje, e data futura fica fora', () => {
  const c = R.compararJanelas([ev('A', 7, 'CRITICO', 'a'), ev('B', 6, 'CRITICO', 'b'), ev('C', -2, 'CRITICO', 'futuro')], 7, AGORA);
  assert.equal(c.porEmpresa.A.atual.c, 0, 'evento de 7 dias atras e do periodo anterior');
  assert.equal(c.porEmpresa.A.anterior.c, 1);
  assert.equal(c.porEmpresa.B.atual.c, 1);
  assert.ok(!c.porEmpresa.C, 'evento futuro ignorado');
});

test('cobertura: sem base comparavel, nenhuma deterioracao ou melhora e afirmada', () => {
  const E = [ev('A', 3, 'CRITICO', 'a'), ev('B', 40, 'CRITICO', 'b-antigo'), ev('B', 2, 'RELEVANTE', 'b')];
  const c = R.compararJanelas(E, 30, AGORA, 31);
  assert.equal(c.anterior_completo, false);
  assert.equal(c.deterioracoes.length + c.melhorias.length + c.novos.length + c.sairam.length, 0);
  assert.equal(c.porEmpresa.A.status, 'sem_base');
  const d = R.buildHtml(30, E, [], BRAND, OPTS({ coberturaDias: 31 }));
  assert.match(d, /Sem comparação com o período anterior: o painel guarda 31 dias/);
  assert.doesNotMatch(d, /crítico novo, sem eventos no período anterior/);
  assert.doesNotMatch(d, /vs anterior/);
  // com base suficiente a comparacao volta (prova da outra ponta)
  const ok = R.compararJanelas(E, 7, AGORA, 31);
  assert.equal(ok.anterior_completo, true);
  assert.equal(ok.porEmpresa.A.status, 'deterioracao');
});

test('compatibilidade: modulo nao usa lookbehind de regex (Safari < 16.4)', async () => {
  const { readFileSync } = await import('node:fs');
  assert.doesNotMatch(readFileSync(path.join(APP, 'js', 'relatorio-executivo.js'), 'utf8'), /\(\?<[=!]/);
  assert.deepEqual(R.limparGenerico('Primeira frase. Segunda frase com 2 itens.', 'x').length > 0, true);
});

test('nota da metrica passa pelo mesmo filtro de valores do painel', () => {
  const curadas = { E: [{ label: 'Alavancagem', value: '3x', fonte: 'ITR', note: 'Covenant de 3,5x; dívida de R$ 2 bilhões' }] };
  const scrub = (t) => t.replace(/R\$\s*[\d.,]+\s*bilh(ões|ão)/g, '');
  assert.match(R.metricasVerificaveis('E', curadas, null).linhas[0].note, /R\$ 2 bilhões/);
  assert.doesNotMatch(R.metricasVerificaveis('E', curadas, null, scrub).linhas[0].note, /R\$/);
});

test('white-label: CNPJ sem gestora nao deixa separador solto', () => {
  const d = R.buildHtml(7, [ev('A', 1, 'CRITICO', 'a')], [], { ...BRAND, gestora: '', cnpj: '11.111.111/0001-11' }, OPTS());
  assert.match(d, /autorizado\. CNPJ 11\.111\.111\/0001-11\./);
  assert.match(d, /class="cover-name">RADAR</);
});
