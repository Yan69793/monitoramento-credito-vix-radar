// Modulo comum do harness de materialidade (Fase 1.2, MATERIALSAT1).
// Usado pelo script de snapshot (scripts/_materialidade-snapshot.mjs) e pelo
// teste permanente (test/materialidade.test.mjs). O ranking completo nasce
// AQUI, uma implementacao so, para o snapshot e o teste nunca divergirem.
import {
  carregarEstadoMultiSemana,
  enriquecerEvento,
  normalizarMojibake,
  SETOR_DE_EMPRESA,
  _chaveDedupBriefing
} from "../src/worker.js";

// Mock minimo de KV: so carregarEstadoCompartilhado usa `get(key, "text")`.
export function fakeKVFromMap(map) {
  return {
    get: async (k) => (map[k] !== undefined ? map[k] : null)
  };
}

// Mesma sequencia do montarBriefingInterno: mescla 5 semanas via funcao real,
// enriquece cada evento com enriquecerEvento real, ordena por materialidade
// desc (estavel, como o Array.prototype.sort do worker).
export async function rankingCompleto(kvMap) {
  const estado = await carregarEstadoMultiSemana({ RADAR_KV: fakeKVFromMap(kvMap) }, 5);
  const todos = [];
  for (const emp of Object.keys(estado.results)) {
    const res = estado.results[emp];
    if (!res || !Array.isArray(res.eventos)) continue;
    const setorEmp = SETOR_DE_EMPRESA[emp] || res.setor || "Outros";
    const setorNorm = normalizarMojibake(String(setorEmp));
    for (const ev of res.eventos) {
      const copia = Object.assign({}, ev, { empresa: emp });
      enriquecerEvento(copia, setorNorm);
      todos.push(copia);
    }
  }
  todos.sort((a, b) => {
    const ma = a._enriquecimento ? a._enriquecimento.materialidade : 0;
    const mb = b._enriquecimento ? b._enriquecimento.materialidade : 0;
    return mb - ma;
  });
  return todos.map((ev) => ({
    empresa: ev.empresa,
    titulo: (ev.titulo || "").slice(0, 60),
    data_evento: ev.data_evento,
    classificacao: ev.classificacao,
    setor: normalizarMojibake(String(SETOR_DE_EMPRESA[ev.empresa] || "Outros")),
    tags: Array.isArray(ev.tags) ? ev.tags.slice(0, 4) : [],
    materialidade: ev._enriquecimento ? ev._enriquecimento.materialidade : 0
  }));
}

// Variante do ranking com o dedup do briefing (BRIEFDEDUP1, Fase 1.3):
// mescla real + enriquecimento real + chave real de dedup, retorna o top N no
// mesmo shape do top_eventos do endpoint. Usada pelo cross-check do teste de
// materialidade e pelo teste de briefing.
export async function rankingTopComDedup(kvMap, n = 10) {
  const estado = await carregarEstadoMultiSemana({ RADAR_KV: fakeKVFromMap(kvMap) }, 5);
  const todos = [];
  for (const emp of Object.keys(estado.results)) {
    const res = estado.results[emp];
    if (!res || !Array.isArray(res.eventos)) continue;
    const setorEmp = SETOR_DE_EMPRESA[emp] || res.setor || "Outros";
    const setorNorm = normalizarMojibake(String(setorEmp));
    for (const ev of res.eventos) {
      const copia = Object.assign({}, ev, { empresa: emp });
      enriquecerEvento(copia, setorNorm);
      todos.push(copia);
    }
  }
  todos.sort((a, b) => {
    const ma = a._enriquecimento ? a._enriquecimento.materialidade : 0;
    const mb = b._enriquecimento ? b._enriquecimento.materialidade : 0;
    return mb - ma;
  });
  const vistos = new Set();
  const dedup = [];
  for (const ev of todos) {
    const k = _chaveDedupBriefing(ev);
    if (vistos.has(k)) continue;
    vistos.add(k);
    dedup.push(ev);
  }
  return dedup.slice(0, n).map((ev) => ({
    empresa: ev.empresa,
    data: ev.data_evento,
    m: ev._enriquecimento ? ev._enriquecimento.materialidade : 0
  }));
}

// Todas as combinacoes de classificacao x tag x setor usadas pelo ranking real,
// para a invariante de saturacao rodar sobre o dominio inteiro.
export const CLASSIFICACOES = ["CRITICO", "RELEVANTE", "ECO"];
