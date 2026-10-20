/* Relatorio Executivo 2.0 (REL-EXEC2, 20/10/2026)
 *
 * Logica pura do PDF executivo do VIX Radar. Extraida do bloco inline "pdf-export-executivo"
 * do app/index.html para poder ser testada direto em Node (node --test) e em Chromium
 * (Playwright page.pdf). O index.html continua responsavel por coletar os dados do painel
 * (resultados, METRICAS_CURADAS, SETOR_DE, anomalias, ranking EWS, branding) e abrir a janela.
 *
 * Regras de conteudo (nascem de EBA/GL/2020/06 8.5, BCBS 239 principios 7 e 9, IOSCO CoC):
 *  - fato (evento datado e com fonte) fica separado de interpretacao (memo/impacto);
 *  - metrica financeira so aparece com valor e fonte ou referencia; senao a linha some e a
 *    lacuna e declarada no anexo;
 *  - direcao (deterioracao/melhora) so vem de campo declarado ou de comparacao de janelas;
 *    ausencia de evento nunca e apresentada como melhora;
 *  - texto generico e duplicata sao removidos, campo vazio nao e preenchido com texto padrao.
 */
(function (root, factory) {
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else if (root) root.VixRelatorioExecutivo = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this), function () {
  'use strict';

  var VERSAO = 'REL-EXEC2';
  var DIA = 864e5;

  var PRESETS = {
    sobrio_dark_navy: { bg: '#001830', text: '#EDE8D8', accent: '#B7985D', muted: '#8899AA', divider: '#0D2438' },
    classic_gold: { bg: '#1A1208', text: '#F5EBD4', accent: '#D4AF37', muted: '#6B5838', divider: '#2A1D0E' },
    minimal_slate: { bg: '#1E293B', text: '#E2E8F0', accent: '#94A3B8', muted: '#94A3B8', divider: '#334155' }
  };

  /* ---------- utilitarios ---------- */

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function trunc(s, n) {
    s = String(s || '').replace(/\s+/g, ' ').trim();
    return s.length > n ? s.slice(0, n - 1).replace(/[\s,;:.]+$/, '') + '…' : s;
  }

  function norm(s) {
    return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9% ]+/g, ' ').replace(/\s+/g, ' ').trim();
  }

  var STOP = {};
  ('de da do das dos a o as os e em no na nos nas por para com um uma que se ao aos sobre apos pela pelo ' +
   'sa s cia companhia ltda mais ou como foi sao ser tem ter seu sua')
    .split(' ').forEach(function (w) { STOP[w] = 1; });

  function tokens(s) {
    var set = {};
    norm(s).split(' ').forEach(function (w) { if (w.length > 2 && !STOP[w]) set[w] = 1; });
    return set;
  }

  function sizeOf(set) { return Object.keys(set).length; }

  function inter(a, b) {
    var n = 0;
    Object.keys(a).forEach(function (k) { if (b[k]) n++; });
    return n;
  }

  function jaccard(a, b) {
    var i = inter(a, b), u = sizeOf(a) + sizeOf(b) - i;
    return u ? i / u : 0;
  }

  function similares(a, b, limiar) {
    var j = jaccard(a, b);
    if (j >= (limiar || 0.6)) return true;
    var m = Math.min(sizeOf(a), sizeOf(b));
    return m >= 4 && inter(a, b) / m >= 0.8;
  }

  function parseISO(iso) {
    if (!iso || typeof iso !== 'string') return null;
    var m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return new Date(+m[1], +m[2] - 1, +m[3]);
    m = iso.match(/^(\d{2})\/(\d{2})\/(\d{4})/);
    return m ? new Date(+m[3], +m[2] - 1, +m[1]) : null;
  }

  function fmtData(iso) {
    var d = parseISO(iso);
    if (!d) return 'data n/d';
    return ('0' + d.getDate()).slice(-2) + '/' + ('0' + (d.getMonth() + 1)).slice(-2) + '/' + d.getFullYear();
  }

  function ponto(t) { return /[.!?]$/.test(t) ? t : t + '.'; }

  function seguro(url) { return typeof url === 'string' && /^https?:\/\/[^\s"'<>]+$/i.test(url.trim()); }

  function hostOf(url) {
    var m = String(url || '').match(/^https?:\/\/([^\/?#]+)/i);
    return m ? m[1].replace(/^www\./i, '') : '';
  }

  function urlKey(url) {
    if (!seguro(url)) return '';
    // a query entra na chave: na CVM/ENET o documento e identificado pelo protocolo na query
    var m = url.trim().match(/^https?:\/\/(?:www\.)?([^\/?#]+)([^?#]*)(\?[^#]*)?/i);
    if (!m) return '';
    var path = m[2].replace(/\/+$/, '').toLowerCase(), q = m[3] && m[3].length > 1 ? m[3] : '';
    return path.length > 1 || q ? m[1].toLowerCase() + path + q : '';
  }

  var RANK = { CRITICO: 0, RELEVANTE: 1 };
  function rank(c) { return RANK[c] != null ? RANK[c] : 9; }
  function tituloDe(ev) { return String(ev.titulo || ev.evento || ev.descricao || '').trim(); }

  /* ---------- 1. deduplicacao ---------- */

  function pesoConteudo(ev) {
    return ['memo_acontecimento', 'contexto', 'memo_importancia_credito', 'impacto_credito',
      'memo_monitorar', 'memo_acao_sugerida', 'cadeia_causal'].reduce(function (n, k) {
      return n + String(ev[k] || '').length;
    }, 0) + (seguro(ev.fonte_primaria) ? 50 : 0);
  }

  function deduplicarEventos(lista) {
    var porEmp = {}, out = [];
    (lista || []).forEach(function (ev) {
      if (!ev) return;
      var emp = ev._empresa || ev.empresa || '';
      (porEmp[emp] = porEmp[emp] || []).push(ev);
    });
    Object.keys(porEmp).forEach(function (emp) {
      var clusters = [];
      porEmp[emp].forEach(function (ev) {
        var tk = tokens(tituloDe(ev)), uk = urlKey(ev.fonte_primaria), dt = parseISO(ev.data_evento);
        var alvo = null;
        for (var i = 0; i < clusters.length && !alvo; i++) {
          var c = clusters[i];
          var dif = dt && c.dt ? Math.abs(dt - c.dt) : (!dt && !c.dt ? 0 : Infinity);
          var mesmaUrl = uk && c.urls[uk];
          if ((dif <= 3 * DIA && similares(tk, c.tk, 0.6)) || (mesmaUrl && dif <= 7 * DIA && jaccard(tk, c.tk) >= 0.3)) alvo = c;
        }
        if (!alvo) { alvo = { eventos: [], urls: {}, tk: tk, dt: dt }; clusters.push(alvo); }
        alvo.eventos.push(ev);
        if (uk) alvo.urls[uk] = 1;
      });
      clusters.forEach(function (c) {
        var rep = c.eventos.slice().sort(function (a, b) {
          return rank(a.classificacao) - rank(b.classificacao) || pesoConteudo(b) - pesoConteudo(a);
        })[0];
        var vistos = {}, fontes = [];
        c.eventos.forEach(function (e) {
          [e.fonte_primaria].concat(Array.isArray(e.fontes) ? e.fontes : []).forEach(function (u) {
            if (seguro(u) && !vistos[u.trim()]) { vistos[u.trim()] = 1; fontes.push(u.trim()); }
          });
        });
        out.push(Object.assign({}, rep, { _empresa: emp, fontes: fontes, n_reportes: c.eventos.length }));
      });
    });
    return out.sort(function (a, b) {
      return rank(a.classificacao) - rank(b.classificacao) || String(b.data_evento || '').localeCompare(String(a.data_evento || ''));
    });
  }

  /* ---------- 2. limpeza de texto generico ---------- */

  var GENERICAS = [
    /\b(acompanhar|monitorar|observar)\b[^.]{0,30}\b(de perto|atentamente|com atencao)\b/,
    /\b(acompanhar|monitorar|observar)\b[^.]{0,25}\b(desdobramentos|evolucao|situacao|cenario|proximos passos)\b/,
    /\bpode (vir a )?(impactar|afetar|pressionar)\b[^.]{0,40}\b(credito|empresa|emissor|companhia|geracao de caixa)\b/,
    /\b(sem|nenhum) (impacto|efeito) (relevante|material|significativo|imediato)\b/,
    /\b(sem|nao ha) (informacoes|dados) adicionais\b/,
    /\bem (linha|conformidade) com o (esperado|setor)\b/,
    /\b(tema|assunto) (segue|permanece|merece) (em )?(observacao|acompanhamento|atencao)\b/,
    /^(n\/?d|nd|n\/a|na|-|—|sem informacao)\.?$/
  ];

  function sentencas(txt) {
    // sem lookbehind de regex: Safari/iOS < 16.4 nao o parseia e o arquivo inteiro deixaria de carregar
    return String(txt || '').replace(/\s+/g, ' ').trim().replace(/([.!?;])\s+(?=[A-ZÀ-Ú0-9"“(])/g, '$1\u0001').split('\u0001').filter(Boolean);
  }

  function ehGenerica(frase) {
    if (/\d/.test(frase) || frase.length > 150) return false;
    var n = norm(frase);
    return GENERICAS.some(function (re) { return re.test(n); });
  }

  function limparGenerico(texto, titulo) {
    var tkTit = titulo ? tokens(titulo) : null, vistos = {};
    var ok = sentencas(texto).filter(function (s) {
      if (ehGenerica(s)) return false;
      var k = norm(s);
      if (!k || vistos[k]) return false;
      vistos[k] = 1;
      if (tkTit && sizeOf(tkTit) >= 3 && jaccard(tokens(s), tkTit) >= 0.8) return false;
      return true;
    });
    return ok.join(' ').trim();
  }

  /* ---------- 3. comparacao de janelas ---------- */

  function sevDe(crit, rel) { return crit > 0 ? 2 : (rel > 0 ? 1 : 0); }

  // op=state monta o painel com 5 semanas ISO (carregarEstadoMultiSemana(env, 5)). Garantido:
  // 4 semanas fechadas + a corrente. O shell passa a cobertura exata; 28 e o piso seguro.
  var COBERTURA_PADRAO = 28;

  function janelas(dias, agora) {
    var hoje = agora ? new Date(agora.getFullYear(), agora.getMonth(), agora.getDate()) : (function () { var d = new Date(); d.setHours(0, 0, 0, 0); return d; })();
    // janela atual = exatamente `dias` dias contando hoje; anterior = os `dias` dias imediatamente antes
    return { hoje: hoje, ini: new Date(hoje.getTime() - (dias - 1) * DIA), iniAnt: new Date(hoje.getTime() - (2 * dias - 1) * DIA) };
  }

  function compararJanelas(eventos, dias, agora, coberturaDias) {
    var J = janelas(dias, agora), hoje = J.hoje, ini = J.ini, iniAnt = J.iniAnt;
    var cobertura = typeof coberturaDias === 'number' && coberturaDias > 0 ? coberturaDias : COBERTURA_PADRAO;
    var completo = dias * 2 <= cobertura;
    var por = {};
    (eventos || []).forEach(function (ev) {
      var d = parseISO(ev.data_evento), emp = ev._empresa;
      if (!d || d > hoje || !emp || (ev.classificacao !== 'CRITICO' && ev.classificacao !== 'RELEVANTE')) return;
      var k = d >= ini ? 'at' : (d >= iniAnt ? 'an' : null);
      if (!k) return;
      var o = por[emp] = por[emp] || { empresa: emp, at: { c: 0, r: 0 }, an: { c: 0, r: 0 } };
      o[k][ev.classificacao === 'CRITICO' ? 'c' : 'r']++;
    });
    var r = {
      dias: dias, cobertura: cobertura,
      anterior_completo: completo,
      atual: { crit: 0, rel: 0, emissores: 0 }, anterior: { crit: 0, rel: 0, emissores: 0 },
      deterioracoes: [], melhorias: [], novos: [], estaveis: [], sairam: [], porEmpresa: {}
    };
    Object.keys(por).forEach(function (emp) {
      var o = por[emp], sa = sevDe(o.at.c, o.at.r), sn = sevDe(o.an.c, o.an.r), st, motivo = '';
      r.atual.crit += o.at.c; r.atual.rel += o.at.r; r.anterior.crit += o.an.c; r.anterior.rel += o.an.r;
      if (sa) r.atual.emissores++;
      if (sn) r.anterior.emissores++;
      if (!completo) {
        // base nao cobre o periodo anterior inteiro: nenhuma direcao e afirmada
        st = sa ? 'sem_base' : 'fora'; motivo = 'sem base comparável (o painel cobre ' + cobertura + ' dias)';
      } else if (!sa && sn) { st = 'saiu'; motivo = 'sem eventos críticos ou relevantes no período (ausência de notícia não é prova de melhora)'; }
      else if (sa === 2 && (sn < 2 || o.at.c > o.an.c)) {
        st = 'deterioracao';
        motivo = sn === 0 ? 'crítico novo, sem eventos no período anterior'
          : sn === 1 ? 'escalou de relevante para crítico' : 'mais eventos críticos que no período anterior (' + o.an.c + ' para ' + o.at.c + ')';
      } else if (sa && !sn) { st = 'novo'; motivo = 'entrou na lista, sem eventos no período anterior'; }
      else if (sa && sa < sn) { st = 'melhoria'; motivo = 'sem eventos críticos no período (antes: ' + o.an.c + ')'; }
      else if (sa === 2 && sn === 2 && o.at.c < o.an.c) { st = 'melhoria'; motivo = 'menos eventos críticos (' + o.an.c + ' para ' + o.at.c + ')'; }
      else { st = 'estavel'; motivo = 'sem mudança de severidade'; }
      r.porEmpresa[emp] = { status: st, motivo: motivo, atual: o.at, anterior: o.an };
      var item = { empresa: emp, motivo: motivo, atual: o.at, anterior: o.an };
      if (st === 'deterioracao') r.deterioracoes.push(item);
      else if (st === 'melhoria') r.melhorias.push(item);
      else if (st === 'novo') r.novos.push(item);
      else if (st === 'saiu') r.sairam.push(item);
      else if (sa && st === 'estavel') r.estaveis.push(item);
    });
    r.deterioracoes.sort(function (a, b) { return b.atual.c - a.atual.c; });
    return r;
  }

  /* ---------- 4. EWS explicavel ---------- */

  function confNum(c) {
    if (typeof c === 'number' && isFinite(c)) return c > 1 ? Math.min(c / 100, 1) : Math.max(c, 0);
    var s = norm(c);
    if (/^(alta|high)/.test(s)) return 0.85;
    if (/^(media|medium)/.test(s)) return 0.6;
    if (/^(baixa|low)/.test(s)) return 0.35;
    return null;
  }

  function explicarEws(item) {
    if (!item) return null;
    var fat = (item.decomposicao || item.drivers || []).filter(function (f) { return f && typeof f.pontos === 'number' && f.pontos > 0; })
      .sort(function (a, b) { return b.pontos - a.pontos; });
    var total = fat.reduce(function (s, f) { return s + f.pontos; }, 0);
    var top = fat.slice(0, 3).map(function (f) {
      var url = f.fonte && (f.fonte.url || f.fonte);
      return {
        fator: String(f.fator || f.tipo_sinal || 'fator'), tag: f.tipo_sinal || '', pontos: f.pontos,
        pesoMax: typeof f.peso_max === 'number' ? f.peso_max : null, pct: total ? f.pontos / total : 0,
        direcao: f.direcao || '', data: f.data_evento || (f.fonte && f.fonte.data_publicacao) || '',
        fonte: seguro(url) ? url : '', fato: f.fato || f.detalhe || '', conf: confNum(f.confianca)
      };
    });
    var pc = 0, pw = 0;
    fat.forEach(function (f) { var c = confNum(f.confianca); if (c != null) { pc += c * f.pontos; pw += f.pontos; } });
    var cm = pw ? pc / pw : null;
    // EWSVAR7D1: variacao so quando a API entrega o score de 7 dias atras; ausente fica null, nunca estimada.
    var temVar = typeof item.delta_7d === 'number' && isFinite(item.delta_7d) && typeof item.score_anterior_7d === 'number' && isFinite(item.score_anterior_7d);
    return {
      empresa: item.empresa, score: item.score, label: item.label || '', total_fatores: fat.length, fatores: fat, top: top,
      pctTop3: total ? top.reduce(function (s, f) { return s + f.pontos; }, 0) / total : 0,
      confianca: cm == null ? 'n/d' : (cm >= 0.75 ? 'alta' : cm >= 0.5 ? 'média' : 'baixa'),
      confiancaNum: cm,
      piso: item.piso_aplicado ? { valor: item.piso_valor, causa: item.piso_causa || '' } : null,
      ews2: item.ews2 && item.ews2.severidade ? String(item.ews2.severidade) : '',
      melhoras: fat.filter(function (f) { return f.direcao === 'melhora'; }),
      calculado_em: item.calculado_em || '',
      variacao7d: temVar ? { anterior: item.score_anterior_7d, delta: item.delta_7d, data: item.data_anterior_7d || '' } : null
    };
  }

  /* ---------- 5. metricas verificaveis ---------- */

  var CATS = [
    ['Rating', /rating/i], ['Alavancagem', /alavanc|d[ií]vida l[ií]quida\s*\/\s*ebitda|dl\s*\/\s*ebitda/i],
    ['Dívida líquida', /d[ií]vida l[ií]quida$|^dl$/i], ['EBITDA', /^ebitda/i], ['DL/PL', /dl\s*\/\s*pl/i],
    ['Basileia', /basileia/i], ['Liquidez', /liquidez/i], ['Covenants', /covenant/i]
  ];

  // scrub: mesmo filtro de valores monetarios que o painel aplica na nota (window._vixScrubMoney)
  function metricasVerificaveis(emp, curadas, anomalia, scrub) {
    var arr = (curadas && curadas[emp]) || [], linhas = [], achadas = {};
    arr.forEach(function (m) {
      if (!m || m.value == null || String(m.value).trim() === '' || String(m.value).trim() === '—') return;
      var lab = String(m.label || '');
      var cat = CATS.filter(function (c) { return c[1].test(lab); })[0];
      if (!cat) return;
      var temFonte = (m.fonte && String(m.fonte).trim()) || (m.ref && String(m.ref).trim());
      if (!temFonte) return;
      achadas[cat[0]] = 1;
      linhas.push({
        label: lab, value: String(m.value), data: m.as_of || m.source_date || '', ref: m.ref ? String(m.ref) : '',
        fonte: m.fonte ? String(m.fonte) : '', status: m.status || '', note: m.note ? String(scrub ? scrub(String(m.note)) || '' : m.note).trim() : ''
      });
    });
    // anomalias do painel: lista [{tipo, severidade, dados:{taxa_atual_pct, taxa_media_pct, delta_pp, data}}]
    var sp = (Array.isArray(anomalia) ? anomalia : []).filter(function (a) {
      return a && a.tipo === 'spread' && a.dados && typeof a.dados.taxa_atual_pct === 'number' && isFinite(a.dados.taxa_atual_pct);
    })[0];
    if (sp) {
      achadas['Spread'] = 1;
      var d = sp.dados, med = typeof d.taxa_media_pct === 'number' ? ' (média ' + d.taxa_media_pct.toFixed(2).replace('.', ',') + '%)' : '';
      linhas.push({ label: 'Taxa indicativa (mercado secundário)', value: d.taxa_atual_pct.toFixed(2).replace('.', ',') + '%' + med, data: d.data || '', ref: '', fonte: 'anomalia de spread detectada (' + (sp.severidade || 'n/d') + ')', status: '', note: '' });
    }
    var ausentes = ['Rating', 'Alavancagem', 'Liquidez', 'Covenants', 'Spread'].filter(function (c) { return !achadas[c]; });
    return { linhas: linhas, ausentes: ausentes };
  }

  function ratingTxt(emp, curadas) {
    var arr = (curadas && curadas[emp]) || [];
    var r = arr.filter(function (x) { return x && /rating/i.test(x.label || '') && String(x.value || '').trim() && (x.fonte || x.ref); })[0];
    return r ? String(r.value) + (r.ref ? ' (' + r.ref + ')' : '') : '';
  }

  /* ---------- 6. prioridade e gatilhos ---------- */

  function priorizar(emissores) {
    return emissores.map(function (e) {
      var base = e.crit > 0 ? 40 : (e.rel > 0 ? 15 : 0);
      var ews = typeof e.ewsScore === 'number' ? Math.min(e.ewsScore, 100) * 0.4 : 0;
      var p = base + ews + (e.deterioracao ? 10 : 0) + (e.novoCritico ? 10 : 0);
      return Object.assign({}, e, { prioridade: Math.round(p * 10) / 10 });
    }).sort(function (a, b) { return b.prioridade - a.prioridade || b.crit - a.crit || a.empresa.localeCompare(b.empresa); });
  }

  function gatilhos(eventosEmp, exp) {
    var out = [], vistos = {};
    function add(txt, origem) {
      var k = norm(txt);
      if (!k || vistos[k] || out.length >= 4) return;
      vistos[k] = 1;
      out.push({ texto: trunc(txt, 190), origem: origem });
    }
    eventosEmp.forEach(function (ev) {
      var t = limparGenerico(ev.memo_monitorar, tituloDe(ev));
      sentencas(t).slice(0, 2).forEach(function (s) { add(s, 'memo do evento'); });
    });
    if (exp) {
      exp.top.filter(function (f) { return f.direcao === 'deterioracao'; }).forEach(function (f) {
        add('Fator ativo no EWS: ' + f.fator + ' (' + f.pontos + ' pts' + (f.data ? ', ' + fmtData(f.data) : '') + ')', 'EWS');
      });
      if (exp.piso) add('Piso do EWS aplicado' + (exp.piso.causa ? ': ' + exp.piso.causa : '') + (exp.piso.valor != null ? ' (' + exp.piso.valor + ')' : ''), 'EWS');
    }
    return out;
  }

  /* ---------- 7. modelo de dados ---------- */

  function montarModelo(dias, eventos, ews, opts) {
    opts = opts || {};
    var agora = opts.agora || new Date();
    var hoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
    var corte = janelas(dias, agora).ini;
    var dedup = deduplicarEventos(eventos);
    var atuais = dedup.filter(function (e) { var d = parseISO(e.data_evento); return d && d >= corte; });
    var cmp = compararJanelas(dedup, dias, agora, opts.coberturaDias);
    var setorDe = opts.setorDe || {};
    var ewsMap = {}, ewsLista = (ews || []).map(explicarEws).filter(Boolean);
    ewsLista.forEach(function (e) { ewsMap[e.empresa] = e; });
    var porEmp = {};
    atuais.forEach(function (ev) { (porEmp[ev._empresa] = porEmp[ev._empresa] || []).push(ev); });
    var base = Object.keys(porEmp).map(function (emp) {
      var evs = porEmp[emp], c = cmp.porEmpresa[emp] || {};
      return {
        empresa: emp, setor: setorDe[emp] || '—', eventos: evs,
        crit: evs.filter(function (e) { return e.classificacao === 'CRITICO'; }).length,
        rel: evs.filter(function (e) { return e.classificacao === 'RELEVANTE'; }).length,
        ewsScore: ewsMap[emp] ? ewsMap[emp].score : null,
        deterioracao: c.status === 'deterioracao',
        novoCritico: c.status === 'deterioracao' && c.anterior && !c.anterior.c,
        tendencia: c.status || 'estavel'
      };
    });
    var prior = priorizar(base);
    var criticos = atuais.filter(function (e) { return e.classificacao === 'CRITICO'; });
    return {
      dias: dias, agora: agora, atuais: atuais, dedup: dedup, brutos: (eventos || []).length, cmp: cmp,
      emissores: prior, ews: ewsLista, ewsMap: ewsMap, criticos: criticos,
      relevantes: atuais.filter(function (e) { return e.classificacao === 'RELEVANTE'; }),
      setorDe: setorDe, curadas: opts.curadas || {}, anomalias: opts.anomalias || {},
      scrub: typeof opts.scrub === 'function' ? opts.scrub : null
    };
  }

  function resumoDecisorio(m) {
    var c = m.cmp, f = [];
    var nCrit = m.criticos.length, nRel = m.relevantes.length;
    var cmpTxt = c.anterior_completo
      ? ' No período anterior de ' + m.dias + ' dias: ' + c.anterior.crit + ' críticos e ' + c.anterior.rel + ' relevantes.'
      : '';
    f.push(m.dias + ' dias: ' + nCrit + ' evento' + (nCrit === 1 ? '' : 's') + ' crítico' + (nCrit === 1 ? '' : 's') + ' e ' + nRel + ' relevante' + (nRel === 1 ? '' : 's') +
      ' em ' + m.emissores.length + ' emissor' + (m.emissores.length === 1 ? '' : 'es') + '.' + cmpTxt);
    if (!c.anterior_completo) {
      f.push('Sem comparação com o período anterior: o painel guarda ' + c.cobertura + ' dias de eventos e a comparação exige ' + (m.dias * 2) + '. Nenhuma deterioração ou melhora é afirmada.');
    } else if (c.deterioracoes.length) {
      f.push('Deterioração em ' + c.deterioracoes.length + ' emissor' + (c.deterioracoes.length === 1 ? '' : 'es') + ': ' +
        ponto(c.deterioracoes.slice(0, 4).map(function (d) { return d.empresa; }).join(', ') + (c.deterioracoes.length > 4 ? ' e outros' : '')));
    } else f.push('Nenhum emissor com deterioração de severidade em relação ao período anterior.');
    if (c.anterior_completo) {
      if (c.melhorias.length) {
        f.push(ponto('Melhora de severidade em ' + c.melhorias.slice(0, 4).map(function (d) { return d.empresa; }).join(', ')));
      } else f.push('Nenhuma melhora de severidade identificada nos dados do período.');
    }
    if (c.sairam.length) f.push(c.sairam.length + ' emissor' + (c.sairam.length === 1 ? ' saiu' : 'es saíram') + ' da lista por falta de eventos, o que não indica melhora de crédito.');
    if (m.ews.length) {
      var top = m.ews[0];
      var alto = m.ews.filter(function (e) { return /ALERTA|CRITICO/i.test(e.label); }).length;
      f.push('EWS: maior score ' + top.score + ' (' + top.empresa + (top.label ? ', ' + top.label : '') + '); ' + alto + ' dos ' + m.ews.length + ' maiores scores em faixa ALERTA ou CRÍTICO.');
    }
    if (m.emissores.length) {
      f.push(ponto('Prioridade de revisão: ' + m.emissores.slice(0, 3).map(function (e) { return e.empresa; }).join(', ')));
    }
    return f.slice(0, 7);
  }

  /* ---------- 8. graficos SVG ---------- */

  var PAL = ['#001830', '#B7985D', '#5B6B7F', '#C9CED6'];

  function svgComparativo(c) {
    var v = [
      ['Críticos', c.anterior.crit, c.atual.crit, '#991B1B'],
      ['Relevantes', c.anterior.rel, c.atual.rel, '#B7985D']
    ];
    var mx = Math.max(1, c.anterior.crit, c.atual.crit, c.anterior.rel, c.atual.rel);
    var s = '<svg viewBox="0 0 340 112" width="100%" role="img" aria-label="Eventos por severidade, período anterior e atual" xmlns="http://www.w3.org/2000/svg" style="max-width:340px">';
    v.forEach(function (row, i) {
      var y = 8 + i * 52;
      s += '<text x="0" y="' + (y + 11) + '" font-size="9" fill="#475569" font-weight="700">' + esc(row[0]) + '</text>';
      [['Anterior', row[1], '#9CA3AF'], ['Atual', row[2], row[3]]].forEach(function (b, j) {
        var yy = y + 16 + j * 14, w = Math.round(b[1] / mx * 210);
        s += '<rect x="58" y="' + yy + '" width="' + Math.max(w, 1) + '" height="10" fill="' + b[2] + '"/>' +
          '<text x="' + (62 + w) + '" y="' + (yy + 9) + '" font-size="9" fill="#111827" font-weight="700">' + b[1] + '</text>' +
          '<text x="0" y="' + (yy + 9) + '" font-size="8" fill="#6B7280">' + b[0] + '</text>';
      });
    });
    return s + '</svg>';
  }

  function svgEws(lista) {
    var n = lista.length;
    if (!n) return '';
    var h = 18 + n * 16;
    var s = '<svg viewBox="0 0 420 ' + h + '" width="100%" role="img" aria-label="Composição do score EWS por fator" xmlns="http://www.w3.org/2000/svg" style="max-width:470px">';
    PAL.forEach(function (c, i) {
      s += '<rect x="' + (150 + i * 66) + '" y="2" width="8" height="8" fill="' + c + '"/><text x="' + (161 + i * 66) + '" y="9" font-size="8" fill="#475569">' + (i < 3 ? 'Fator ' + (i + 1) : 'Demais') + '</text>';
    });
    lista.forEach(function (e, i) {
      var y = 16 + i * 16, x = 150, scale = 230 / 100;
      var soma = 0;
      s += '<text x="0" y="' + (y + 9) + '" font-size="8.5" fill="#111827" font-weight="700">' + esc(trunc(e.empresa, 28)) + '</text>';
      e.top.forEach(function (f, k) {
        var w = Math.max(f.pontos * scale, 1);
        s += '<rect x="' + x.toFixed(1) + '" y="' + y + '" width="' + w.toFixed(1) + '" height="11" fill="' + PAL[k] + '"><title>' + esc(f.fator + ': ' + f.pontos + ' pts') + '</title></rect>';
        x += w; soma += f.pontos;
      });
      var resto = Math.max((e.score || 0) - soma, 0);
      if (resto > 0.5) {
        var w2 = resto * scale;
        s += '<rect x="' + x.toFixed(1) + '" y="' + y + '" width="' + w2.toFixed(1) + '" height="11" fill="' + PAL[3] + '"/>';
        x += w2;
      }
      s += '<text x="' + (x + 5).toFixed(1) + '" y="' + (y + 10) + '" font-size="9" fill="#111827" font-weight="700">' + esc(e.score) + '</text>';
    });
    return s + '</svg>';
  }

  function svgSetores(dist) {
    if (!dist.length) return '';
    var mx = Math.max.apply(null, dist.map(function (d) { return d.total; }).concat([1]));
    var s = '<svg viewBox="0 0 340 ' + (dist.length * 16 + 4) + '" width="100%" role="img" aria-label="Concentração setorial de eventos" xmlns="http://www.w3.org/2000/svg" style="max-width:340px">';
    dist.forEach(function (d, i) {
      var y = 2 + i * 16, wc = d.criticos / mx * 170, wr = d.relevantes / mx * 170;
      s += '<text x="0" y="' + (y + 9) + '" font-size="8.5" fill="#475569">' + esc(trunc(d.setor, 24)) + '</text>' +
        '<rect x="125" y="' + y + '" width="' + wc.toFixed(1) + '" height="10" fill="#991B1B"/>' +
        '<rect x="' + (125 + wc).toFixed(1) + '" y="' + y + '" width="' + wr.toFixed(1) + '" height="10" fill="#B7985D"/>' +
        '<text x="' + (130 + wc + wr).toFixed(1) + '" y="' + (y + 9) + '" font-size="9" fill="#111827" font-weight="700">' + d.total + '</text>';
    });
    return s + '</svg>';
  }

  function distSetores(m) {
    var map = {};
    m.atuais.forEach(function (ev) {
      var s = m.setorDe[ev._empresa] || 'Outros';
      var o = map[s] = map[s] || { setor: s, criticos: 0, relevantes: 0 };
      if (ev.classificacao === 'CRITICO') o.criticos++; else o.relevantes++;
    });
    return Object.keys(map).map(function (k) { var o = map[k]; o.total = o.criticos + o.relevantes; return o; })
      .sort(function (a, b) { return b.total - a.total; }).slice(0, 8);
  }

  /* ---------- 9. registro de fontes ---------- */

  function novoRegistro() {
    var lista = [], idx = {};
    return {
      lista: lista,
      add: function (url, data, emp) {
        if (!seguro(url)) return 0;
        var k = urlKey(url) || url.trim();
        if (!idx[k]) { lista.push({ n: lista.length + 1, url: url.trim(), data: data || '', emp: emp || '' }); idx[k] = lista.length; }
        return idx[k];
      }
    };
  }

  function refs(reg, ev) {
    var n = (ev.fontes && ev.fontes.length ? ev.fontes : [ev.fonte_primaria]).map(function (u) { return reg.add(u, ev.data_evento, ev._empresa); }).filter(Boolean);
    return n.length ? ' <sup class="ref">[' + n.join(',') + ']</sup>' : ' <sup class="ref semfonte">[sem fonte]</sup>';
  }

  /* ---------- 10. HTML ---------- */

  function css(t) {
    return '@page{size:A4 portrait;margin:12mm 11mm 15mm;@bottom-center{content:"Página " counter(page) " de " counter(pages);font-size:8pt;color:#6B7280}}' +
      '*{box-sizing:border-box;margin:0;padding:0}' +
      'body{font-family:"DM Sans",Inter,system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;font-size:11px;line-height:1.5;color:#111827;background:#fff;max-width:210mm;margin:0 auto}' +
      '.print-bar{position:fixed;top:0;left:0;right:0;background:#001830;padding:10px 18px;display:flex;gap:10px;align-items:center;z-index:99}' +
      '.print-bar span{color:#C9A96E;font-size:11px;font-weight:700;letter-spacing:.08em;margin-right:auto}' +
      '.btn-p{background:#B7985D;color:#001020;border:none;padding:8px 18px;border-radius:4px;font-size:12px;font-weight:800;cursor:pointer;font-family:inherit}.btn-s{background:transparent;color:#B7985D;border:1px solid #B7985D}' +
      '.cover-header{background:' + t.bg + ';color:' + t.text + ';padding:18px 24px 14px}' +
      '.cover-top{display:flex;justify-content:space-between;align-items:flex-start;gap:20px}' +
      '.cover-brand{display:flex;align-items:center;gap:12px}.cover-logo-img{max-height:40px;max-width:150px;object-fit:contain}' +
      '.cover-name{font-size:15px;font-weight:900;letter-spacing:.16em;color:' + t.accent + '}' +
      '.cover-sub{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:' + t.muted + ';margin-top:2px}' +
      '.cover-right{text-align:right;flex:1}.cover-type{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:' + t.muted + '}' +
      '.cover-date{font-size:13px;font-weight:700;margin-top:3px;color:' + t.text + '}.cover-period{font-size:10px;color:' + t.muted + ';margin-top:2px}' +
      '.conf{background:' + t.accent + ';color:#001020;text-align:center;font-size:10px;font-weight:800;letter-spacing:.12em;padding:4px;text-transform:uppercase}' +
      '.block{padding:12px 24px}.sec-h{font-size:10.5px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;margin-bottom:8px;padding-bottom:4px;border-bottom:2px solid #B7985D;color:#001830}' +
      '.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:10px}' +
      '.kpi{border:1px solid #E5E7EB;border-radius:4px;padding:7px 8px;text-align:center}.kpi .n{font-size:22px;font-weight:900;line-height:1.1;color:#001830}.kpi .l{font-size:9px;text-transform:uppercase;letter-spacing:.07em;color:#6B7280}.kpi .d{font-size:9.5px;color:#475569}' +
      '.resumo{list-style:none}.resumo li{padding:3px 0 3px 12px;position:relative;border-bottom:1px solid #F1F3F5}.resumo li:before{content:"";position:absolute;left:0;top:9px;width:5px;height:5px;background:#B7985D}' +
      '.cols{display:grid;grid-template-columns:1fr 1fr;gap:12px}.muted{color:#6B7280;font-style:italic}' +
      'table.data{width:100%;border-collapse:collapse;font-size:10px;table-layout:fixed}table.data th{background:#001830;color:#C9A96E;padding:5px 6px;text-align:left;font-size:9px;letter-spacing:.07em;text-transform:uppercase}' +
      'table.data td{padding:4px 6px;border-bottom:1px solid #ECEEF1;vertical-align:top;overflow-wrap:anywhere}table.data tr:nth-child(even) td{background:#FAFAFA}table.data .num{text-align:center;font-weight:700;font-variant-numeric:tabular-nums}' +
      '.tag{display:inline-block;font-size:8.5px;font-weight:800;letter-spacing:.05em;padding:1px 5px;border-radius:2px;text-transform:uppercase}.tag.crit{background:#FEE2E2;color:#991B1B}.tag.rel{background:#FEF3C7;color:#92400E}.tag.ok{background:#E5E7EB;color:#374151}' +
      '.ficha{border:1px solid #D1D5DB;border-radius:4px;margin-bottom:9px;overflow:hidden}.ficha-h{background:#F3F4F6;padding:6px 10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;border-bottom:2px solid #B7985D}' +
      '.ficha-h strong{font-size:12px;color:#001830}.ficha-h .m{font-size:9.5px;color:#475569;margin-left:auto}.ficha-b{padding:7px 10px;display:grid;grid-template-columns:1.25fr 1fr;gap:4px 14px}' +
      '.ficha-b h4{font-size:8.5px;letter-spacing:.09em;text-transform:uppercase;color:#7C6A3A;margin:5px 0 2px}.ficha-b ul{list-style:none}.ficha-b li{padding:1px 0;font-size:10px}.ficha-b p{font-size:10px}' +
      '.fato{color:#111827}.interp{color:#475569;font-style:italic}.ref{font-size:8px;color:#7C6A3A;font-weight:700}.ref.semfonte{color:#991B1B}' +
      '.ev-card{margin-bottom:8px;border:1px solid #E5E7EB;border-radius:4px;overflow:hidden}.ev-head{padding:5px 9px;display:flex;flex-wrap:wrap;align-items:center;gap:8px;border-bottom:1px solid #E5E7EB;background:#FAFAFA}.ev-meta{font-size:9.5px;color:#6B7280;margin-left:auto}' +
      '.ev-body{padding:6px 9px}.ev-body h3{font-size:11.5px;margin-bottom:3px;line-height:1.35}.ev-body p{font-size:10px;margin-bottom:3px}.ev-body .rot{font-size:8.5px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#7C6A3A}' +
      '.anexo-h{background:#001830;color:#C9A96E;padding:10px 24px;font-size:13px;font-weight:800;letter-spacing:.1em;text-transform:uppercase}' +
      '.fontes li{font-size:9.5px;margin-bottom:2px;word-break:break-all}.disclaimer{margin:8px 24px 10px;padding:9px 12px;background:#F9FAFB;border:1px solid #E5E7EB;border-radius:4px;font-size:9px;color:#6B7280;line-height:1.5}' +
      '.footer-bar{border-top:2px solid #E5E7EB;padding:8px 24px;display:flex;justify-content:space-between;gap:12px;font-size:9.5px;color:#6B7280;background:#F9FAFB}.footer-logo{font-weight:800;color:#001830;letter-spacing:.08em}' +
      '@media print{*{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important}html,body{width:auto!important;max-width:none!important;margin:0!important;background:#fff!important;font-size:9.5pt!important}' +
      '.no-print{display:none!important}.cover-header,.block,.disclaimer,.footer-bar,.anexo-h{padding-left:0!important;padding-right:0!important}.disclaimer{margin-left:0;margin-right:0}' +
      '.ficha,.ev-card,.kpi,tr,svg{break-inside:avoid!important;page-break-inside:avoid!important}.sec-h,.ficha-h,.anexo-h{break-after:avoid!important}' +
      '.page-break{break-before:page!important;page-break-before:always!important}thead{display:table-header-group!important}a[href]:after{content:none!important}p{orphans:3;widows:3}}';
  }

  function tendTag(st) {
    var map = { deterioracao: ['crit', 'Deterioração'], melhoria: ['ok', 'Melhora'], novo: ['rel', 'Novo'], estavel: ['ok', 'Estável'], saiu: ['ok', 'Sem eventos'], sem_base: ['ok', 'Sem base'] };
    var x = map[st] || map.estavel;
    return '<span class="tag ' + x[0] + '">' + x[1] + '</span>';
  }

  function tabelaMudancas(lista, vazio) {
    if (!lista.length) return '<p class="muted">' + esc(vazio) + '</p>';
    return '<table class="data"><thead><tr><th style="width:30%">Emissor</th><th style="width:22%">Críticos / relev.</th><th>Motivo</th></tr></thead><tbody>' +
      lista.slice(0, 6).map(function (d) {
        return '<tr><td><strong>' + esc(d.empresa) + '</strong></td><td class="num">' + d.anterior.c + '/' + d.anterior.r + ' → ' + d.atual.c + '/' + d.atual.r + '</td><td>' + esc(d.motivo) + '</td></tr>';
      }).join('') + '</tbody></table>' + (lista.length > 6 ? '<p class="muted">+' + (lista.length - 6) + ' no anexo.</p>' : '');
  }

  function fmtDelta7d(v) {
    if (!v) return '—';
    var d = Math.round(v.delta * 10) / 10;
    var txt = (d > 0 ? '+' : d < 0 ? '−' : '') + String(Math.abs(d)).replace('.', ',');
    return txt + '<br><span class="muted">era ' + esc(String(v.anterior).replace('.', ',')) + '</span>';
  }

  function secEws(m) {
    var top = m.ews.slice(0, 8);
    var comVar = top.some(function (e) { return e.variacao7d; });
    if (!top.length) {
      return '<section class="block"><h2 class="sec-h">Early Warning Score</h2><p class="muted">Ranking EWS indisponível. Recarregue o painel antes de exportar, nenhum score foi estimado.</p></section>';
    }
    var linhas = top.map(function (e, i) {
      var drv = e.top.length ? e.top.map(function (f) {
        return esc(trunc(f.fator, 34)) + ' <b>' + f.pontos + (f.pesoMax ? '/' + f.pesoMax : '') + '</b>' + (f.direcao === 'melhora' ? ' (melhora)' : '');
      }).join('<br>') : '<span class="muted">sem decomposição</span>';
      var extra = (e.piso ? 'Piso ' + esc(e.piso.valor != null ? e.piso.valor : '') + (e.piso.causa ? ': ' + esc(trunc(e.piso.causa, 40)) : '') : '') + (e.ews2 ? (e.piso ? '<br>' : '') + 'EWS 2.0: ' + esc(e.ews2) : '');
      return '<tr><td class="num">' + (i + 1) + '</td><td><strong>' + esc(e.empresa) + '</strong></td><td class="num">' + esc(e.score) + '</td>' + (comVar ? '<td class="num">' + fmtDelta7d(e.variacao7d) + '</td>' : '') + '<td>' + esc(e.label || '—') + '</td><td>' + drv + '</td><td class="num">' + esc(e.confianca) + '</td><td>' + (extra || '—') + '</td></tr>';
    }).join('');
    return '<section class="block"><h2 class="sec-h">Early Warning Score explicado</h2>' + svgEws(top) +
      '<table class="data" style="margin-top:8px"><thead><tr><th style="width:5%">#</th><th style="width:17%">Emissor</th><th style="width:8%">Score</th>' + (comVar ? '<th style="width:8%">Δ 7 dias</th>' : '') + '<th style="width:12%">Faixa</th><th>Fatores (pontos / máximo)</th><th style="width:9%">Confiança</th><th style="width:16%">Piso / EWS 2.0</th></tr></thead><tbody>' + linhas + '</tbody></table>' +
      '<p class="muted" style="margin-top:4px">' + (comVar
        ? 'Δ 7 dias compara o score atual com o registrado entre 7 e 10 dias atrás, — quando não há registro nessa janela. '
        : 'Variação de 7 dias indisponível nesta exportação, a API não entregou histórico do score para estes emissores. ') +
      'Confiança é a média dos fatores ponderada por pontos, n/d quando a base não informa.</p></section>';
  }

  function fichaEmissor(e, m, reg) {
    var exp = m.ewsMap[e.empresa], c = m.cmp.porEmpresa[e.empresa] || {};
    var evs = e.eventos.slice(0, 2);
    var fatos = evs.map(function (ev) {
      var det = limparGenerico(ev.memo_acontecimento || ev.contexto, tituloDe(ev));
      return '<li class="fato"><span class="tag ' + (ev.classificacao === 'CRITICO' ? 'crit' : 'rel') + '">' + (ev.classificacao === 'CRITICO' ? 'Crít.' : 'Relev.') + '</span> ' + fmtData(ev.data_evento) + ' — ' + esc(trunc(tituloDe(ev), 150)) +
        (ev.n_reportes > 1 ? ' <span class="muted">(' + ev.n_reportes + ' reportes)</span>' : '') + refs(reg, ev) + (det ? '<br><span style="color:#475569">' + esc(trunc(det, 170)) + '</span>' : '') + '</li>';
    }).join('');
    var vistos = {}, interp = [];
    e.eventos.forEach(function (ev) {
      var t = limparGenerico(ev.memo_importancia_credito || ev.impacto_credito || '', tituloDe(ev));
      var k = norm(t).slice(0, 80);
      if (t && !vistos[k] && interp.length < 1) { vistos[k] = 1; interp.push(trunc(t, 280)); }
    });
    var acao = '';
    for (var i = 0; i < e.eventos.length && !acao; i++) acao = limparGenerico(e.eventos[i].memo_acao_sugerida, tituloDe(e.eventos[i]));
    var met = metricasVerificaveis(e.empresa, m.curadas, m.anomalias[e.empresa], m.scrub);
    var metHtml = met.linhas.length
      ? '<table class="data"><tbody>' + met.linhas.slice(0, 4).map(function (l) {
          return '<tr><td style="width:38%">' + esc(l.label) + '</td><td><strong>' + esc(trunc(l.value, 40)) + '</strong><br><span style="color:#6B7280;font-size:8.5px">' + esc(l.data ? fmtData(l.data) : (l.ref ? l.ref : 'data n/d')) + (l.status === 'breach' ? ' · fora do limite de referência' : '') + '</span></td></tr>';
        }).join('') + '</tbody></table>'
      : '<p class="muted">Sem métrica financeira verificável na base para este emissor.</p>';
    var gat = gatilhos(e.eventos, exp).slice(0, 3);
    var gatHtml = gat.length ? '<ul>' + gat.map(function (g) { return '<li>' + esc(g.texto) + ' <span class="ref">[' + esc(g.origem) + ']</span></li>'; }).join('') + '</ul>' : '<p class="muted">Nenhum gatilho específico informado na base.</p>';
    var ewsLinha = exp ? 'EWS <strong>' + esc(exp.score) + '</strong> ' + esc(exp.label) + (exp.top[0] ? ' · maior fator: ' + esc(trunc(exp.top[0].fator, 30)) : '') : '<span class="muted">EWS fora do ranking carregado</span>';
    return '<article class="ficha"><header class="ficha-h"><strong>' + esc(e.empresa) + '</strong><span class="m">' + esc(e.setor) + ' · ' + ewsLinha + '</span>' + tendTag(c.status) + '</header><div class="ficha-b">' +
      '<div><h4>Fatos</h4><ul>' + fatos + '</ul>' + (e.eventos.length > 2 ? '<p class="muted">+' + (e.eventos.length - 2) + ' evento(s) no anexo.</p>' : '') +
      (interp.length ? '<h4>Leitura analítica (interpretação)</h4>' + interp.map(function (t) { return '<p class="interp">' + esc(t) + '</p>'; }).join('') : '') +
      (acao ? '<p class="interp"><b>Ação sugerida:</b> ' + esc(trunc(acao, 220)) + '</p>' : '') + '</div>' +
      '<div><h4>Impacto financeiro verificável</h4>' + metHtml + '<h4>Gatilhos de monitoramento</h4>' + gatHtml + '</div></div></article>';
  }

  function secWatch(m) {
    var lim = 14, lista = m.emissores.slice(0, lim);
    var linhas = lista.map(function (e) {
      var c = m.cmp.porEmpresa[e.empresa] || { anterior: { c: 0, r: 0 }, atual: { c: e.crit, r: e.rel } };
      var rt = ratingTxt(e.empresa, m.curadas);
      return '<tr><td><strong>' + esc(e.empresa) + '</strong></td><td>' + esc(e.setor) + '</td><td>' + (e.crit ? '<span class="tag crit">Crítico</span>' : '<span class="tag rel">Relevante</span>') + '</td><td class="num">' + (m.cmp.anterior_completo ? c.anterior.c + '/' + c.anterior.r + ' → ' : '') + e.crit + '/' + e.rel + '</td><td>' + tendTag(c.status) + '</td><td>' + (rt ? esc(trunc(rt, 26)) : '<span class="muted">n/d</span>') + '</td></tr>';
    }).join('');
    return '<section class="block"><h2 class="sec-h">Watchlist do período</h2><table class="data"><thead><tr><th style="width:22%">Emissor</th><th style="width:18%">Setor</th><th style="width:12%">Alerta</th><th style="width:17%">Crít./relev. (ant → atual)</th><th style="width:14%">Tendência</th><th>Rating (fonte)</th></tr></thead><tbody>' + linhas + '</tbody></table>' +
      (m.emissores.length > lim ? '<p class="muted">+' + (m.emissores.length - lim) + ' emissores no anexo técnico.</p>' : '') + '</section>';
  }

  function metodologiaCurta(brand, dataCurta, hora) {
    return '<div class="disclaimer"><strong>Metodologia e limitações.</strong> Eventos classificados por inteligência artificial com curadoria humana a partir de fontes públicas (CVM, RI, imprensa especializada, agências de rating). Fato (evento datado com fonte numerada) aparece separado de interpretação (em itálico). Métricas financeiras só aparecem com valor e fonte ou referência, e a data da fonte vem junto. Comparação com o período anterior usa a mesma janela de dias imediatamente anterior e só mede eventos classificados, ausência de evento não é melhora. Não constitui recomendação de investimento, oferta de valores mobiliários nem parecer de crédito vinculante. Distribuição restrita ao destinatário autorizado.' +
      (brand.cnpj ? ' ' + (brand.gestora ? esc(brand.gestora) + ' · ' : '') + 'CNPJ ' + esc(brand.cnpj) + '.' : '') + ' Gerado em ' + dataCurta + ' ' + hora + ' via VIX Radar (relatório ' + VERSAO + ').</div>';
  }

  function cardEvento(ev, reg) {
    var crit = ev.classificacao === 'CRITICO';
    var fato = limparGenerico(ev.memo_acontecimento || ev.contexto, tituloDe(ev));
    var imp = limparGenerico(ev.memo_importancia_credito || ev.impacto_credito, tituloDe(ev));
    var mon = limparGenerico(ev.memo_monitorar, tituloDe(ev));
    var ac = limparGenerico(ev.memo_acao_sugerida, tituloDe(ev));
    var cad = limparGenerico(ev.cadeia_causal, tituloDe(ev));
    return '<article class="ev-card"><header class="ev-head"><span class="tag ' + (crit ? 'crit' : 'rel') + '">' + (crit ? 'Crítico' : 'Relevante') + '</span><strong>' + esc(ev._empresa) + '</strong>' +
      '<span class="ev-meta">' + esc(fmtData(ev.data_evento)) + (ev.n_reportes > 1 ? ' · ' + ev.n_reportes + ' reportes' : '') + '</span></header><div class="ev-body">' +
      (tituloDe(ev) ? '<h3>' + esc(tituloDe(ev)) + '</h3>' : '') +
      '<p><span class="rot">Fato</span> ' + (fato ? esc(trunc(fato, 520)) : '<span class="muted">sem detalhe factual além do título</span>') + refs(reg, ev) + '</p>' +
      (imp ? '<p class="interp"><span class="rot">Interpretação</span> ' + esc(trunc(imp, 420)) + '</p>' : '') +
      (cad ? '<p class="interp"><span class="rot">Cadeia causal (interpretação)</span> ' + esc(trunc(cad, 320)) + '</p>' : '') +
      (mon ? '<p><span class="rot">Monitorar</span> ' + esc(trunc(mon, 300)) + '</p>' : '') +
      (ac ? '<p class="interp"><span class="rot">Ação sugerida</span> ' + esc(trunc(ac, 300)) + '</p>' : '') +
      '</div></article>';
  }

  function secAnexo(m, reg, brand) {
    var s = '<div class="anexo-h page-break">Anexo técnico</div>';
    // A. eventos
    var porEmp = {};
    m.atuais.forEach(function (ev) { (porEmp[ev._empresa] = porEmp[ev._empresa] || []).push(ev); });
    s += '<section class="block"><h2 class="sec-h">A. Eventos do período (deduplicados: ' + m.atuais.length + ' de ' + m.brutos + ' registros na janela de comparação)</h2>';
    m.emissores.forEach(function (e) { s += (porEmp[e.empresa] || []).map(function (ev) { return cardEvento(ev, reg); }).join(''); });
    s += '</section>';
    // B. decomposicao EWS
    s += '<section class="block"><h2 class="sec-h">B. Decomposição completa do EWS</h2>';
    if (!m.ews.length) s += '<p class="muted">Ranking EWS indisponível na geração deste relatório.</p>';
    m.ews.slice(0, 20).forEach(function (e) {
      s += '<table class="data" style="margin-bottom:8px"><thead><tr><th colspan="5">' + esc(e.empresa) + ' · score ' + esc(e.score) + ' ' + esc(e.label) + ' · ' + e.total_fatores + ' fator(es) · confiança ' + esc(e.confianca) + (e.piso ? ' · piso ' + esc(e.piso.valor) : '') + (e.calculado_em ? ' · calculado ' + esc(fmtData(e.calculado_em)) : '') + '</th></tr>' +
        '<tr><th style="width:34%">Fator</th><th style="width:10%">Pontos</th><th style="width:12%">Direção</th><th style="width:14%">Data</th><th>Fato / fonte</th></tr></thead><tbody>' +
        (e.fatores.length ? e.fatores.map(function (f) {
          var url = f.fonte && (f.fonte.url || ''), n = seguro(url) ? reg.add(url, f.data_evento, e.empresa) : 0;
          return '<tr><td>' + esc(trunc(f.fator || f.tipo_sinal, 60)) + '</td><td class="num">' + f.pontos + (typeof f.peso_max === 'number' ? '/' + f.peso_max : '') + '</td><td>' + esc(f.direcao || '—') + '</td><td>' + esc(f.data_evento ? fmtData(f.data_evento) : '—') + '</td><td>' + esc(trunc(f.fato || f.detalhe || f.justificativa_curta || '—', 160)) + (n ? ' <sup class="ref">[' + n + ']</sup>' : '') + '</td></tr>';
        }).join('') : '<tr><td colspan="5" class="muted">Sem decomposição retornada pela API.</td></tr>') + '</tbody></table>';
    });
    s += '</section>';
    // C. metricas
    var linhasM = [], lacunas = [];
    m.emissores.forEach(function (e) {
      var mv = metricasVerificaveis(e.empresa, m.curadas, m.anomalias[e.empresa], m.scrub);
      mv.linhas.forEach(function (l) {
        linhasM.push('<tr><td>' + esc(e.empresa) + '</td><td>' + esc(l.label) + '</td><td><strong>' + esc(trunc(l.value, 60)) + '</strong></td><td>' + esc(l.data ? fmtData(l.data) : 'n/d') + '</td><td>' + esc(trunc([l.ref, l.fonte].filter(Boolean).join(' · '), 90)) + '</td><td>' + esc(l.status === 'breach' ? 'fora do limite de referência' : '') + (l.note ? ' ' + esc(trunc(l.note, 80)) : '') + '</td></tr>');
      });
      lacunas.push(e.empresa + ': ' + (mv.ausentes.length ? mv.ausentes.join(', ') : 'completo'));
    });
    s += '<section class="block"><h2 class="sec-h">C. Métricas por emissor com proveniência</h2>' +
      (linhasM.length ? '<table class="data"><thead><tr><th style="width:17%">Emissor</th><th style="width:15%">Métrica</th><th style="width:16%">Valor</th><th style="width:11%">Data</th><th>Fonte / referência</th><th style="width:16%">Observação</th></tr></thead><tbody>' + linhasM.join('') + '</tbody></table>' : '<p class="muted">Nenhuma métrica com fonte ou referência para os emissores do período.</p>') +
      '<h2 class="sec-h" style="margin-top:10px">Lacunas de dado (não coberto pela base ou sem fonte)</h2><p style="font-size:9.5px">' + esc(lacunas.join(' | ')) + '</p>' +
      '<p class="muted">Liquidez e covenants não existem como campo na base atual, por isso nenhuma ficha os exibe. Spread aparece quando a série de mercado secundário está carregada.</p></section>';
    // D. regras
    s += '<section class="block"><h2 class="sec-h">D. Regras aplicadas</h2><ul style="font-size:9.5px;list-style:none"><li><b>Deduplicação:</b> mesmo emissor, datas a até 3 dias e títulos com similaridade (Jaccard ≥ 0,6 ou contenção ≥ 0,8), ou mesma URL de artigo com título parcialmente similar. Mantém o registro mais completo e soma as fontes.</li>' +
      '<li><b>Texto genérico:</b> frases curtas, sem número, do tipo "monitorar de perto" ou "pode impactar o crédito", e memo que repete o título, são removidos. Campo vazio fica vazio.</li>' +
      '<li><b>Tendência:</b> janela atual contra a janela imediatamente anterior de mesmo tamanho. Deterioração = crítico novo, escalada de relevante para crítico ou mais críticos. Melhora = menor severidade com eventos no período. Emissor sem eventos é "sem eventos", nunca melhora.</li>' +
      '<li><b>Prioridade:</b> 40 pontos se há crítico ou 15 se só relevante, mais 0,4 × score EWS, mais 10 se deterioração e 10 se crítico novo.</li>' +
      '<li><b>Janela:</b> período atual = os ' + m.dias + ' dias até hoje, inclusive. O painel guarda ' + m.cmp.cobertura + ' dias de eventos (5 semanas ISO). A comparação só é feita quando o dobro do período cabe nessa base' + (m.cmp.anterior_completo ? '.' : ', o que não ocorre neste relatório, então nenhuma tendência foi calculada.') + '</li></ul></section>';
    if (m.cmp.sairam.length || m.cmp.novos.length || m.cmp.estaveis.length) {
      s += '<section class="block"><h2 class="sec-h">E. Demais movimentos</h2>' +
        (m.cmp.novos.length ? '<p style="font-size:9.5px"><b>Entraram na lista (relevante):</b> ' + esc(m.cmp.novos.map(function (x) { return x.empresa; }).join(', ')) + '.</p>' : '') +
        (m.cmp.sairam.length ? '<p style="font-size:9.5px"><b>Sem eventos no período (tinham no anterior):</b> ' + esc(m.cmp.sairam.map(function (x) { return x.empresa; }).join(', ')) + '.</p>' : '') +
        (m.cmp.estaveis.length ? '<p style="font-size:9.5px"><b>Estáveis em alerta:</b> ' + esc(m.cmp.estaveis.map(function (x) { return x.empresa; }).join(', ')) + '.</p>' : '') + '</section>';
    }
    return s;
  }

  function secFontes(reg) {
    if (!reg.lista.length) return '<section class="block"><h2 class="sec-h">Índice de fontes</h2><p class="muted">Nenhuma fonte com URL válida nos eventos do período.</p></section>';
    return '<section class="block"><h2 class="sec-h">Índice de fontes</h2><ol class="fontes" style="padding-left:18px">' + reg.lista.map(function (f) {
      return '<li value="' + f.n + '"><a href="' + esc(f.url) + '">' + esc(hostOf(f.url)) + '</a> · ' + esc(f.emp) + ' · ' + esc(fmtData(f.data)) + ' · <span style="color:#6B7280">' + esc(trunc(f.url, 90)) + '</span></li>';
    }).join('') + '</ol></section>';
  }

  function buildHtml(dias, eventos, ews, brand, opts) {
    opts = opts || {};
    brand = brand || {};
    var t = brand.theme || PRESETS.sobrio_dark_navy;
    var tipo = opts.tipo === 'anexo' || opts.tipo === 'completo' ? opts.tipo : 'executivo';
    var m = montarModelo(dias, eventos, ews, opts);
    var agora = m.agora;
    var dataLong = agora.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
    var dataCurta = agora.toLocaleDateString('pt-BR');
    var hora = agora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    var nomeGestora = brand.gestora ? esc(String(brand.gestora).toUpperCase()) : 'RADAR';
    var subtitulo = brand.gestora ? 'Monitoramento de Crédito Privado' : 'Inteligência de Crédito Privado';
    var logo = brand.logo && /^(data:image\/|https?:\/\/)/i.test(brand.logo)
      ? '<img src="' + esc(brand.logo) + '" alt="logo" class="cover-logo-img">'
      : '<svg width="34" height="24" viewBox="0 0 40 28" fill="none"><path d="M40 8.47V14.98L30.45 6.51L20.30 14.98L10.15 6.51L0 14.98V8.47L10.15 0L20.30 8.47L30.45 0L40 8.47Z" fill="' + t.accent + '"/><path d="M40 21.49V28L30.45 19.54L20.30 28L10.15 19.54L0 28V21.49L10.15 13.03L20.30 21.49L30.45 13.03L40 21.49Z" fill="' + t.accent + '"/></svg>';
    var reg = novoRegistro();
    var c = m.cmp;
    var rotulo = tipo === 'anexo' ? 'Anexo técnico' : 'Relatório executivo';
    var corpo = '';

    if (tipo !== 'anexo') {
      var delta = function (a, b) { return c.anterior_completo ? (a >= b ? '+' : '') + (a - b) + ' vs anterior' : 'sem base comparável'; };
      var semBase = '<p class="muted">Comparação indisponível: o painel guarda ' + c.cobertura + ' dias de eventos e a comparação de ' + dias + ' dias exige ' + (dias * 2) + '. Use 7 dias para ver a tendência.</p>';
      corpo += '<section class="block"><h2 class="sec-h">Resumo decisório</h2><div class="kpis">' +
        '<div class="kpi"><div class="n" style="color:#991B1B">' + m.criticos.length + '</div><div class="l">Críticos</div><div class="d">' + delta(c.atual.crit, c.anterior.crit) + '</div></div>' +
        '<div class="kpi"><div class="n" style="color:#92400E">' + m.relevantes.length + '</div><div class="l">Relevantes</div><div class="d">' + delta(c.atual.rel, c.anterior.rel) + '</div></div>' +
        '<div class="kpi"><div class="n">' + m.emissores.length + '</div><div class="l">Emissores em alerta</div><div class="d">' + delta(c.atual.emissores, c.anterior.emissores) + '</div></div>' +
        '<div class="kpi"><div class="n" style="color:#B7985D">' + (c.anterior_completo ? c.deterioracoes.length : 'n/d') + '</div><div class="l">Deteriorações</div><div class="d">' + (c.anterior_completo ? c.melhorias.length + ' melhora(s)' : 'sem base comparável') + '</div></div></div>' +
        '<ul class="resumo">' + resumoDecisorio(m).map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul></section>' +
        '<section class="block">' + (c.anterior_completo
          ? '<div class="cols"><div><h2 class="sec-h">Deteriorações</h2>' + tabelaMudancas(c.deterioracoes, 'Nenhuma deterioração de severidade.') + '</div>' +
            '<div><h2 class="sec-h">Melhorias</h2>' + tabelaMudancas(c.melhorias, 'Nenhuma melhora de severidade nos dados.') + '</div></div>'
          : '<h2 class="sec-h">Deteriorações e melhorias</h2>' + semBase) +
        '<div class="cols" style="margin-top:10px"><div><h2 class="sec-h">Eventos: anterior x atual</h2>' + (c.anterior_completo ? svgComparativo(c) : '<p class="muted">Sem base comparável.</p>') + '</div><div><h2 class="sec-h">Concentração setorial</h2>' + (svgSetores(distSetores(m)) || '<p class="muted">Sem eventos no período.</p>') + '</div></div></section>' +
        secEws(m) +
        '<section class="block"><h2 class="sec-h">Fichas dos emissores prioritários</h2>' + m.emissores.slice(0, 5).map(function (e) { return fichaEmissor(e, m, reg); }).join('') +
        (m.emissores.length > 5 ? '<p class="muted">Demais ' + (m.emissores.length - 5) + ' emissor(es) na watchlist e no anexo técnico.</p>' : '') + '</section>' +
        secWatch(m);
    }
    if (tipo !== 'executivo') {
      corpo += (tipo === 'anexo' ? '' : '') + secAnexo(m, reg, brand);
    } else {
      corpo += '<section class="block"><p class="muted">Anexo técnico (todos os eventos, decomposição do EWS, métricas e fontes) disponível na opção "Completo" ou "Anexo técnico" do exportador.</p></section>';
    }
    corpo += secFontes(reg) + metodologiaCurta(brand, dataCurta, hora);

    return '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="UTF-8">' +
      '<title>' + nomeGestora + ' — ' + rotulo + ' ' + dataCurta + '</title><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>' + css(t) + '</style>' +
      '<script>function salvarPdf(){requestAnimationFrame(function(){requestAnimationFrame(function(){window.print()})})}</script>' +
      '</head><body>' +
      '<div class="print-bar no-print"><span>' + rotulo.toUpperCase() + ' — pré-visualização</span><button class="btn-p btn-s" onclick="window.close()">Fechar</button><button class="btn-p" onclick="salvarPdf()">Salvar PDF</button></div>' +
      '<div style="height:52px" class="no-print"></div><div class="doc">' +
      '<header class="cover-header"><div class="cover-top"><div class="cover-brand">' + logo + '<div><div class="cover-name">' + nomeGestora + '</div><div class="cover-sub">' + subtitulo + '</div></div></div>' +
      '<div class="cover-right"><div class="cover-type">' + rotulo + '</div><div class="cover-date">' + esc(dataLong) + '</div><div class="cover-period">Últimos ' + dias + ' dias · Semana ' + esc(opts.semana || '—') + ' · ' + hora + '</div>' +
      (brand.analista ? '<div class="cover-period">Analista: <strong>' + esc(brand.analista) + '</strong>' + (brand.credencial ? ' · ' + esc(brand.credencial) : '') + '</div>' : '') +
      '</div></div></header><div class="conf">Confidencial — uso restrito ao destinatário</div>' + corpo +
      '<footer class="footer-bar"><span><span class="footer-logo">' + nomeGestora + '</span> · ' + rotulo + '</span><span>CONFIDENCIAL</span><span>' + dataCurta + ' ' + hora + '</span></footer></div></body></html>';
  }

  return {
    VERSAO: VERSAO, PRESETS: PRESETS, esc: esc, trunc: trunc, buildHtml: buildHtml, montarModelo: montarModelo,
    deduplicarEventos: deduplicarEventos, limparGenerico: limparGenerico, compararJanelas: compararJanelas,
    explicarEws: explicarEws, metricasVerificaveis: metricasVerificaveis, priorizar: priorizar, gatilhos: gatilhos,
    resumoDecisorio: resumoDecisorio, ratingTxt: ratingTxt, secEws: secEws
  };
});
