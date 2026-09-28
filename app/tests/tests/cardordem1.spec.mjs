// CARDORDEM1 — regressao do CARD DO EMISSOR x TIMELINE DO EMISSOR (somente frontend).
//
// Defeito medido em producao (24/09/2026):
//   * Cogna: evento ECO de 24/09 gerado as 18:09:58 e persistido as 18:10:04.
//   * Tupy: o Painel/Timeline exibia o evento CVM de 24/09.
//   * o card do emissor nao colocava o 24/09 no topo e a contagem do card
//     divergia da contagem da "Timeline · ultimos 90 dias" do mesmo emissor.
//
// A divergencia Timeline/Card tinha TRES causas, todas no frontend:
//
//   1. FONTES DIFERENTES — a Timeline do emissor (`p15-timeline-module`,
//      `#emp-hist-timeline`) somava `historico_emissor.eventos_semana_atual`
//      (estado semanal do KV, servido por `GET /?op=historico_emissor`) a
//      `resultados` + `ARQUIVO_PRE`; o card lia so os dois ultimos. Era por isso
//      que um evento novo (o CVM de 24/09) aparecia na Timeline e nao no card.
//
//   2. DEDUP DIFERENTE — o card deduplicava por titulo+data exatos, a Timeline
//      por `data|titulo[0:80]`. Duplicata semantica contava 2 num lado e 1 no
//      outro.
//
//   3. ORDEM — os DOIS ordenavam severidade (CRITICO > RELEVANTE > ECO) ANTES da
//      data, entao um ECO novo caia abaixo de um RELEVANTE/CRITICO antigo.
//
// Correcao sob teste: UM construtor unico (`eventosEmissor90`) usado pelo card e
// pela Timeline, com as tres fontes, uma dedup so (`_isDupSemantico`) e ordem
// data DESC com severidade apenas desempatando a MESMA data. O conserto da dedup
// exige `_fonteCanonica`: `_isDupSemantico` comparava a URL SEM a query
// (`split('?')[0]`) e, como todo documento CVM do RAD compartilha o caminho
// `.../frmDownloadDocumento.aspx`, colapsava documentos DISTINTOS.
//
// Contrato coberto:
//   A) ECO 24/09 aparece antes de RELEVANTE 07/08 (caso de producao);
//   B) evento novo nunca fica abaixo de evento antigo so por ser ECO;
//   C) ordem e data DESC, severidade so desempata a MESMA data;
//   D) card e Timeline do emissor: MESMO conjunto e MESMA contagem;
//   E) o mesmo vale no caminho de arquivo (`sem_eventos`);
//   F) evento que existe SO em historico_emissor aparece no card e na Timeline;
//   G) `_isDupSemantico`: documentos CVM distintos permanecem distintos, e a
//      mesma URL (mesmo com parametros de tracking) continua sendo duplicata;
//   H) nos 26 eventos reais do estado semanal (W35): nenhum evento distinto
//      perdido — 26 -> 25 (a unica queda e um par identico duplicado), contra
//      26 -> 18 da regra antiga (8 eventos distintos colapsados indevidamente).
//
// RELOGIOTESTE1: relogio da pagina congelado em 2026-09-24 18:10:04 BRT. As
// janelas (90 dias do card/Timeline, 30 dias do Painel) sao relativas a "agora";
// fixture datado sem relogio preso derrete sozinho com o calendario.
//
// Nao toca backend/Worker: o proprio app/index.html e servido localmente
// (playwright.config.mjs, webServer).
import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// 2026-09-24 18:10:04 BRT = 21:10:04Z — o instante em que o pulso persistiu o
// ECO da Cogna (evidencia de producao citada acima).
const INSTANTE_FIXTURE = '2026-09-24T21:10:04.000Z';

// Estado semanal real usado pelo Worker (mesma fixture das suites de backend).
const FIXTURE_W35 = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../api/test/fixtures/estado-2026-W35.json'
);

async function congelarRelogio(page) {
  await page.addInitScript((iso) => {
    const FIXO = new Date(iso).getTime();
    const Real = Date;
    class MockDate extends Real {
      constructor(...args) {
        if (args.length === 0) super(FIXO);
        else super(...args);
      }
      static now() { return FIXO; }
    }
    window.Date = MockDate;
  }, INSTANTE_FIXTURE);
}

// Um unico evaluate: monta o fixture, renderiza o card (e, via wrapper do modulo
// p15, a Timeline do emissor) e colhe os dois lados no MESMO estado. Em dois
// evaluates separados o bootstrap do app poderia repovoar `resultados` entre a
// montagem e a leitura, e o teste mediria outra coisa.
function renderFixture(page, payload) {
  return page.evaluate(async (p) => {
    const empresa = p.empresa;
    resultados = {};
    resultados[empresa] = {
      empresa,
      sem_eventos: !!p.sem_eventos,
      eventos: p.eventos || [],
      alertas_mercado: [],
      fontes_consultadas: [],
      timestamp: '2026-09-24T21:10:04.000Z',
    };
    window.ARQUIVO_PRE = { [empresa]: p.arquivo || [] };
    window.__histEmissorCache = p.historico
      ? { [empresa]: { ts: Date.now(), data: { ok: true, empresa, eventos_semana_atual: p.historico } } }
      : {};
    window.__histEmissorLoading = null;
    selecionada = empresa;
    modo = 'live';
    abaAtual = 'eventos';
    loading = false;

    // window.renderEmpBody esta envolto pelo modulo p15: ele renderiza o card e
    // agenda a injecao da Timeline. Esperar o tick deixa a Timeline no DOM.
    window.renderEmpBody();
    await new Promise((r) => setTimeout(r, 0));

    const cards = Array.from(document.querySelectorAll('#emp-body .ev-card')).map((el) => ({
      classe: el.className,
      data: (el.querySelector('.ev-date')?.textContent || '').trim() || null,
      titulo: (el.querySelector('.ev-titulo')?.textContent || '').trim() || null,
    }));
    const badge = document.querySelector('#emp-body .change-badge-v63');
    const header = document.querySelector('#emp-body .evts-header span');
    const tlCount = document.querySelector('#emp-hist-timeline .emp-hist-count');
    const tlItens = Array.from(document.querySelectorAll('#emp-hist-timeline .emp-hist-item')).map((el) => ({
      data: (el.querySelector('.emp-hist-date')?.textContent || '').trim() || null,
      titulo: (el.querySelector('.emp-hist-title')?.textContent || '').trim() || null,
    }));
    // A Timeline guarda a contagem em texto ("N evento(s) — expandir"); o numero
    // e o que o usuario compara com o cabecalho do card.
    const tlNumero = tlCount ? Number((/(\d+)/.exec(tlCount.textContent) || [])[1]) : null;

    return {
      cards,
      badge: badge ? badge.textContent.trim() : null,
      header: header ? header.textContent.trim() : null,
      timelinePresente: !!document.getElementById('emp-hist-timeline'),
      timelineNumero: tlNumero,
      timelineItens: tlItens,
    };
  }, payload);
}

// ── Fixtures ───────────────────────────────────────────────────────────────
// 24/09 e RELEVANTE 07/08 (07 de agosto) estao os dois dentro da janela de 90d.
const ECO_24_09 = {
  classificacao: 'ECO',
  titulo: 'Fato relevante — 9a emissao de debentures',
  evento: 'Comunicado ao mercado protocolado na CVM em 24/09.',
  data_evento: '2026-09-24',
  fonte_tipo: 'CVM',
  fonte_primaria: 'https://www.rad.cvm.gov.br/ENET/frmExibirArquivoIPEExterno.aspx?NumeroSequencialDocumento=123',
};
// NOTA de fixture: cada evento DISTINTO tem base de URL propria. A base sem
// query nao identifica documento CVM nenhum (todos os documentos RAD saem de
// `frmDownloadDocumento.aspx`); e justamente por isso a regra antiga colapsava
// documentos distintos — ver contrato G e H.
const RELEVANTE_07_08 = {
  classificacao: 'RELEVANTE',
  titulo: 'Resultado 2T26 — alavancagem sobe para 3,4x',
  evento: 'Divulgacao do resultado do 2T26 em 07/08.',
  data_evento: '2026-08-07',
  fonte_tipo: 'CVM',
  fonte_primaria: 'https://ri.cogna.com.br/resultado-2t26/',
};

test.describe('CARDORDEM1 · card do emissor x Timeline do emissor', () => {
  test('A) ECO de 24/09 aparece antes do RELEVANTE de 07/08', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    const r = await renderFixture(page, {
      empresa: 'Cogna',
      eventos: [RELEVANTE_07_08, ECO_24_09], // evento novo entra DEPOIS na ordem de origem
    });

    expect(r.cards, 'os dois eventos deveriam aparecer').toHaveLength(2);
    expect(r.cards.map((c) => c.data)).toEqual(['2026-09-24', '2026-08-07']);
    expect(r.cards[0].titulo).toContain('9a emissao');
    expect(r.cards[0].classe).toContain('eco');
  });

  test('B) evento novo nao fica abaixo de antigo so por ser ECO', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    const criticoAntigo = {
      ...RELEVANTE_07_08,
      classificacao: 'CRITICO',
      titulo: 'Recuperacao extrajudicial protocolada',
      data_evento: '2026-07-01',
      fonte_primaria: 'https://ri.tupy.com.br/fato-relevante-recuperacao-extrajudicial/',
    };
    const r = await renderFixture(page, {
      empresa: 'Tupy',
      eventos: [criticoAntigo, ECO_24_09],
    });

    expect(r.cards, 'os dois eventos deveriam aparecer').toHaveLength(2);
    expect(r.cards[0].data, 'o ECO de 24/09 nao pode ser enterrado por um CRITICO de 01/07').toBe('2026-09-24');
  });

  test('C) severidade desempata somente a MESMA data', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    const mesmoDia = '2026-09-19';
    const r = await renderFixture(page, {
      empresa: 'Rumo',
      eventos: [
        { ...ECO_24_09, data_evento: mesmoDia, titulo: 'ECO do dia', fonte_primaria: 'https://exemplo.test/a' },
        { ...RELEVANTE_07_08, data_evento: mesmoDia, titulo: 'RELEVANTE do dia', fonte_primaria: 'https://exemplo.test/b' },
        { ...ECO_24_09, classificacao: 'CRITICO', data_evento: mesmoDia, titulo: 'CRITICO do dia', fonte_primaria: 'https://exemplo.test/c' },
      ],
    });

    expect(r.cards.map((c) => c.titulo)).toEqual(['CRITICO do dia', 'RELEVANTE do dia', 'ECO do dia']);
  });

  test('D) card e Timeline do emissor tem o MESMO conjunto e a MESMA contagem', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    // Duplicata semantica real de producao: o mesmo evento re-detectado num pulso
    // seguinte (mesma data, mesmo titulo) + a terceira copia no ARQUIVO_PRE.
    const r = await renderFixture(page, {
      empresa: 'Cogna',
      eventos: [ECO_24_09, { ...ECO_24_09 }, RELEVANTE_07_08],
      arquivo: [{ ...ECO_24_09 }],
    });

    expect(r.cards, 'o card deduplica a tripla para 2').toHaveLength(2);
    expect(r.cards.map((c) => c.data)).toEqual(['2026-09-24', '2026-08-07']);
    // Contagem visivel do card tem que bater com o conjunto (1 eco + 1 relevante).
    expect(r.badge).toBe('0 crítico(s), 1 relevante(s), 1 eco(s) na janela ativa');
    expect(r.header).toContain('2 evento(s) identificado(s)');
    // Timeline do emissor: mesmo conjunto, mesma contagem, mesma ordem.
    expect(r.timelinePresente, 'Timeline do emissor deveria estar no DOM').toBe(true);
    expect(r.timelineNumero, 'contagem da Timeline tem que bater com a do card').toBe(r.cards.length);
    expect(r.timelineItens.slice(0, 2).map((i) => i.titulo)).toEqual(r.cards.map((c) => c.titulo));
  });

  test('E) caminho de arquivo (sem_eventos) mantem ordem e contagem', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    const r = await renderFixture(page, {
      empresa: 'Santos Brasil',
      sem_eventos: true,
      eventos: [],
      arquivo: [RELEVANTE_07_08, ECO_24_09],
    });

    expect(r.cards, 'os dois eventos arquivados deveriam aparecer').toHaveLength(2);
    expect(r.cards.map((c) => c.data)).toEqual(['2026-09-24', '2026-08-07']);
    expect(r.timelineNumero).toBe(r.cards.length);
  });

  test('F) evento que existe SO em historico_emissor aparece no card e na Timeline', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    // Caso Tupy: o evento novo chega pelo estado semanal do KV
    // (`eventos_semana_atual`), que o card nao lia antes da correcao.
    const cvm24 = {
      classificacao: 'RELEVANTE',
      titulo: 'CVM registra assembleia de debenturistas',
      evento: 'Documento protocolado e refletido no estado semanal.',
      data_evento: '2026-09-24',
      fonte_tipo: 'CVM',
      fonte_primaria: 'https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1559907&numSequencia=1081473',
    };
    const r = await renderFixture(page, {
      empresa: 'Tupy',
      eventos: [RELEVANTE_07_08],
      historico: [cvm24],
    });

    expect(r.cards, 'card deve trazer o evento de historico_emissor').toHaveLength(2);
    expect(r.cards.map((c) => c.data)).toEqual(['2026-09-24', '2026-08-07']);
    expect(r.cards[0].titulo).toContain('assembleia de debenturistas');
    expect(r.timelineNumero).toBe(r.cards.length);
    expect(r.timelineNumero).toBe(2);
  });

  test('F2) evento INFORMATIVO (ECO promovido por materialidade) aparece nos dois lados', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    // O backend PROMOVE a INFORMATIVO todo ECO/RUIDO que a materialidade
    // operacional considera material (`ev.classificacao = "INFORMATIVO"`, 3 sitios
    // em api/src/worker.js). O valor nao era tratado em lugar nenhum do app: a
    // Timeline (filtro "!= RUIDO") mostrava, o card (filtro CRITICO/RELEVANTE/ECO)
    // nao. E o candidato mais provavel para "a Timeline mostra o 24/09 e o card
    // nao". O conjunto canonico passa a contar INFORMATIVO como ECO.
    const promovido = {
      ...ECO_24_09,
      classificacao: 'INFORMATIVO',
      titulo: 'Fato relevante promovido por materialidade operacional',
    };
    const r = await renderFixture(page, {
      empresa: 'Cogna',
      eventos: [RELEVANTE_07_08, promovido],
    });

    expect(r.cards, 'o card tem que mostrar o ECO promovido a INFORMATIVO').toHaveLength(2);
    expect(r.cards.map((c) => c.data)).toEqual(['2026-09-24', '2026-08-07']);
    expect(r.cards[0].classe).toContain('eco');
    expect(r.timelineNumero, 'mesma contagem nos dois lados').toBe(r.cards.length);
    expect(r.badge).toBe('0 crítico(s), 1 relevante(s), 1 eco(s) na janela ativa');
  });
});

test.describe('DEDUPFONTE1 · _isDupSemantico nao colapsa documentos distintos', () => {
  test('G) documentos CVM distintos permanecem distintos; mesma URL segue duplicata', async ({ page }) => {
    await page.goto('/');

    const r = await page.evaluate(() => {
      const docA = 'https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1550853&numSequencia=1081473';
      const docB = 'https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1552285&numSequencia=1076991';
      const base = { empresa: 'Oncoclínicas', classificacao: 'RELEVANTE', data_evento: '2026-08-04' };
      const com = (titulo, fonte) => ({ ...base, titulo, fonte_primaria: fonte });
      const existe = (lista, ev) => _isDupSemantico({ ...ev, empresa: 'Oncoclínicas' }, lista);

      const lista = [com('Doc A', docA)];
      return {
        canonicaComUtm: _fonteCanonica(docA + '&utm_source=news'),
        canonicaSemUtm: _fonteCanonica(docA),
        docDistintoEhDup: existe(lista, com('Doc B', docB)),
        mesmaUrlEhDup: existe(lista, com('Doc A', docA)),
        mesmaUrlComUtmEhDup: existe(lista, com('Doc A', docA + '&utm_source=news')),
        mesmoTituloDataEhDup: existe(lista, com('Doc A', 'https://outro.test/x')),
        outroEmissorEhDup: _isDupSemantico({ ...com('Doc A', docA), empresa: 'Raízen' }, lista),
        tituloDataDiferenteEhDup: existe(lista, com('Doc C', 'https://terceiro.test/y')),
      };
    });

    // A query e o que IDENTIFICA o documento CVM: nao pode ser descartada...
    expect(r.canonicaComUtm).toBe(r.canonicaSemUtm);
    expect(r.docDistintoEhDup, 'documentos CVM distintos nao podem ser a mesma coisa').toBe(false);
    // ...mas a mesma URL continua duplicata, com ou sem tracking.
    expect(r.mesmaUrlEhDup).toBe(true);
    expect(r.mesmaUrlComUtmEhDup).toBe(true);
    // Mesmo titulo+data (outra fonte) e o caso classico de duplicata.
    expect(r.mesmoTituloDataEhDup).toBe(true);
    // Dedup e por emissor: outro emissor nunca colide.
    expect(r.outroEmissorEhDup).toBe(false);
    // Titulo e data diferentes: nao e duplicata.
    expect(r.tituloDataDiferenteEhDup).toBe(false);
  });
});

test.describe('DEDUPREAL1 · 26 eventos reais (estado W35): nenhum evento distinto perdido', () => {
  test('H) conjunto final preserva todo evento distinto (26 -> 25, nao 26 -> 18)', async ({ page }) => {
    await congelarRelogio(page);
    await page.goto('/');

    const estado = JSON.parse(fs.readFileSync(FIXTURE_W35, 'utf8'));
    const porEmissor = {};
    for (const [empresa, obj] of Object.entries(estado.results || estado)) {
      const eventos = (obj && obj.eventos) || [];
      if (eventos.length) porEmissor[empresa] = eventos;
    }

    const r = await page.evaluate((dados) => {
      const out = {};
      for (const [empresa, eventos] of Object.entries(dados)) {
        // Regra ANTIGA, reproduzida aqui apenas para comparar: fonte comparada
        // pela base SEM a query (o defeito) + titulo+data exatos.
        const legado = [];
        const legadoVisto = [];
        const eLegado = (ev) => {
          const emp = ev.empresa || empresa;
          const d = String(ev.data_evento || '');
          const f = (ev.fonte_primaria || '').split('?')[0].replace(/\/$/, '');
          for (const ex of legadoVisto) {
            if ((ex.empresa || empresa) !== emp) continue;
            if ((ev.titulo || '') === (ex.titulo || '') && d === (ex.data_evento || '')) return true;
            const g = (ex.fonte_primaria || '').split('?')[0].replace(/\/$/, '');
            if (f && g && f === g) return true;
            if (_normTituloDedup(ev.titulo) === _normTituloDedup(ex.titulo) && d === (ex.data_evento || '')) return true;
          }
          return false;
        };
        for (const ev of eventos) {
          const e = { ...ev, empresa: ev.empresa || empresa };
          if (eLegado(e)) continue;
          legadoVisto.push(e);
          legado.push(e);
        }

        // Regra em producao: o construtor unico usado pelo card e pela Timeline.
        resultados = { [empresa]: { empresa, sem_eventos: false, eventos, fontes_consultadas: [], timestamp: new Date().toISOString() } };
        window.ARQUIVO_PRE = {};
        window.__histEmissorCache = {};
        const atual = eventosEmissor90(empresa);

        // `url` e a fonte canonica: e ela que define "mesmo documento".
        const limpo = (e) => ({ data: e.data_evento, titulo: e.titulo, url: _fonteCanonica(e.fonte_primaria) });
        out[empresa] = {
          bruto: eventos.map(limpo),
          legado: legado.map((e) => `${e.data_evento}|${e.titulo}`),
          atual: atual.map(limpo),
        };
      }
      return out;
    }, porEmissor);

    const bruto = [], legado = [], atual = [];
    const chave = (e) => `${e.data}|${e.titulo}`;
    for (const v of Object.values(r)) {
      bruto.push(...v.bruto);
      legado.push(...v.legado);
      atual.push(...v.atual);
    }

    // Ponto de partida medido na fixture real: 26 eventos brutos.
    expect(bruto, 'estado W35 tem 26 eventos').toHaveLength(26);
    // A regra antiga entregava 18 (8 eventos DISTINTOS colapsados indevidamente).
    expect(legado, 'a regra antiga colapsava 8 eventos distintos (medido)').toHaveLength(18);
    // A regra corrigida entrega 25: a unica queda e o MESMO documento CVM
    // (numProtocolo=1552285) registrado duas vezes no estado semanal, com titulos
    // e datas diferentes (2026-08-04 e 2026-08-05).
    expect(atual, 'so pode cair duplicata do MESMO documento').toHaveLength(25);

    // Nada que o card ja mostrava pode desaparecer.
    const chavesAtual = atual.map(chave);
    for (const k of legado) expect(chavesAtual, `evento perdido na correcao: ${k}`).toContain(k);

    // Os 8 eventos DISTINTOS que a regra antiga colapsava: 7 voltam ao conjunto e
    // o 8o e a copia antiga de um documento que segue visivel pela data mais nova.
    const descartadosPelaRegraAntiga = bruto.filter((e) => !legado.includes(chave(e)));
    const recuperados = atual.filter((e) => !legado.includes(chave(e)));
    expect(descartadosPelaRegraAntiga, 'a regra antiga descartava 8 eventos distintos').toHaveLength(8);
    expect(recuperados, '7 dos 8 voltam; o 8o e copia do mesmo documento').toHaveLength(7);
    for (const d of descartadosPelaRegraAntiga) {
      const voltou = chavesAtual.includes(chave(d));
      const copiaDocumental = atual.some((a) => a.url && a.url === d.url);
      expect(voltou || copiaDocumental, `evento sumiu sem justificativa: ${chave(d)}`).toBe(true);
    }

    // O unico descarte do conjunto final e o registro ANTIGO (04/08) do documento
    // CVM que continua no conjunto pelo registro mais novo (05/08). E o que garante
    // que uma copia antiga nunca rebaixa a posicao de um documento novo.
    const faltando = bruto.filter((e) => !chavesAtual.includes(chave(e)));
    expect(faltando, 'o unico descarte e o registro antigo do mesmo documento').toHaveLength(1);
    expect(faltando[0].data, 'o descartado e o registro antigo').toBe('2026-08-04');
    expect(atual.filter((a) => a.url === faltando[0].url).map((a) => a.data))
      .toEqual(['2026-08-05']);

    // Contagem por emissor (medida na fixture) — prova que os eventos materiais
    // novos seguem visiveis: 2T26 de 14/08, venda da JV em 20/08, capital da
    // Light em 20/08, fato relevante da Oi em 11/08 e doc CVM da Raizen em 12/08.
    const recuperadosDe = (v) => v.atual.filter((e) => !v.legado.includes(chave(e)));
    const datasDe = (v, fecha) => recuperadosDe(v).map((e) => e.data).sort();
    expect(r['Oncoclínicas'].atual, 'Oncoclínicas: 8 de 9').toHaveLength(8);
    expect(r['Oncoclínicas'].legado, 'a regra antiga entregava 5 de 9').toHaveLength(5);
    expect(datasDe(r['Oncoclínicas'])).toEqual(['2026-08-03', '2026-08-14', '2026-08-20']);
    expect(r['Light'].atual).toHaveLength(4);
    expect(r['Light'].legado).toHaveLength(2);
    expect(datasDe(r['Light'])).toEqual(['2026-07-30', '2026-08-20']);
    expect(r['Raízen'].atual, 'Raízen: 6 de 6 (documentos CVM distintos preservados)').toHaveLength(6);
    expect(datasDe(r['Raízen'])).toEqual(['2026-08-12']);
    expect(r['Oi'].atual, 'Oi: 7 de 7').toHaveLength(7);
    expect(datasDe(r['Oi'])).toEqual(['2026-08-11']);
  });
});
