import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { beforeEach, describe, expect, it } from "vitest";

// REPROVADO-FAILCLOSED1 (2026-09-06): gates sao fail-closed; indice ausente = erro.
beforeEach(async () => { await bootstrapIndiceQuarentena(env); });

// REPROVADO-FAILCLOSED1 (auditoria 2026-09-05).
//
// O verificador adversarial parte do MANDATO "assuma falso ate provar verdadeiro" e
// devolve REPROVADO tanto quando prova que o evento e falso quanto quando simplesmente
// NAO consegue provar que e verdadeiro (fonte inacessivel, reCAPTCHA no rad.cvm.gov.br,
// fonte_primaria ausente). A regra do prompt e explicita:
//
//   "Se uma evidencia nao for encontrada por busca, veredicto deve ser REPROVADO
//    com motivo explicitando a falha."
//   "abaixo de 0.4: evidencia ausente ou insuficiente — REPROVADO obrigatorio"
//
// Ou seja, REPROVADO e a saida de FALTA de confirmacao, nao de prova de falsidade, e
// ter `fonte_primaria`/`fonte_secundaria` preenchido NAO vale como evidencia: o contrato
// exige fonte DISTINTA da citada pelo gerador, achada por busca ativa. Sobre essa saida,
// `retratarEventoRejeitadoInterno` apagava do estado QUALQUER evento com
// `_pendente_verificacao === true` que casasse por chave dedup, sem perguntar se a
// rejeicao foi "e falso" ou "nao consegui conferir". Um evento REAL cuja fonte ficou
// temporariamente inacessivel para o verificador era apagado de vez.
//
// Foi o risco concreto da Usina Pampa Sul (SOURCEFIX-PAMPASUL1, 05/09): o ITR tem
// fonte_primaria no RAD CVM (bloqueado por reCAPTCHA para o verificador) e o evento da
// ANEEL tem fonte_primaria null com secundaria na imprensa. Os dois sao reais e teriam
// sido apagados pelo REPROVADO.
//
// Fail-closed real (auditoria determinou que marcar e limpar certificava um evento que o
// contrato diz nao confirmado): so apagar evento SEM nenhuma fonte citavel (primaria nem
// secundaria), que e alucinacao sem proveniencia. Evento COM fonte e NAO-CONCLUSIVO: nao
// apaga, nao certifica, permanece intocado com `_pendente_verificacao` ainda true, sem
// `_verif_rejeitado`, elegivel para reprocessamento quando o emissor for varrido de novo.
// E o REPROVADO nao-conclusivo NAO vai ao cache `radar:verif:{id}` (TTL 30d): o motor de
// verificacao usa cache_hits para pular o LLM e auto-confirmar, entao cachear travaria a
// reavaliacao quando a fonte voltasse a ser acessivel. Alucinacao sem fonte, que retratou
// de verdade, segue cacheada como terminal.
//
// Prova de DUAS PONTAS (regra 5 do CLAUDE.md):
//   - ponta ruim: evento real COM fonte (primaria ou secundaria) tem que sobreviver ao
//     REPROVADO, ainda pendente e sem cache envenenado. Contra o codigo pre-fix esses
//     casos terminavam com 0 eventos.
//   - ponta boa: evento SEM fonte nenhuma continua sendo apagado e o veredicto vai ao
//     cache. O fix nao pode ter desligado a limpeza de alucinacao nem o cache terminal.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const EMPRESA = "Acme Energia";
const SETOR = "Energia Eletrica";

const FONTE_CVM = "https://rad.cvm.gov.br/fato-160616";
const FONTE_IMPRENSA = "https://www.megawhat.com.br/noticia";

// _chaveDedupEvento(ev) = data|empresa_lowercase|host+path, caindo para
// data|empresa|titulo_normalizado quando fonte_primaria e vazia.
const ID_CVM = `2026-08-13|acme energia|rad.cvm.gov.br/fato-160616`;
const TITULO_SEM_FONTE = "Pedido tarifario na ANEEL";
const ID_SEM_FONTE = `2026-08-14|acme energia|pedido tarifario na aneel`;
const ID_ALUCINACAO = `2026-08-15|acme energia|pedido tarifario na aneel`;

const VEREDITO_REPROVADO = {
  veredicto: "REPROVADO",
  confianca: 0.2,
  motivo: "evidencia nao encontrada",
  fontes_validas: [],
};

async function semear(semana, eventos) {
  await env.RADAR_KV.put(
    `radar:estado:${semana}`,
    JSON.stringify({
      week: semana,
      results: { [EMPRESA]: { empresa: EMPRESA, setor: SETOR, sem_eventos: false, eventos } },
      updated_at: "2026-09-05T00:00:00.000Z",
    })
  );
}

async function lerEventos(semana) {
  const raw = await env.RADAR_KV.get(`radar:estado:${semana}`, "json");
  const reg = raw && raw.results && raw.results[EMPRESA];
  return reg && Array.isArray(reg.eventos) ? reg.eventos : [];
}

async function lerCache(id) {
  return env.RADAR_KV.get(`radar:verif:${id}`, "json");
}

function confirmar(itens) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "confirmar_verificacao", routine_key: ROUTINE_KEY, itens }),
  });
}

function item(semana, id, evento, veredicto) {
  return { id, empresa: EMPRESA, semana, data_fila: "2026-09-05", setor: SETOR, evento, veredicto };
}

describe("REPROVADO-FAILCLOSED1: REPROVADO nao apaga nem certifica evento real que so nao foi re-verificavel", () => {
  it("ponta ruim: evento real com fonte primaria (RAD CVM) sobrevive ao REPROVADO, ainda pendente", async () => {
    const SEMANA = "2026-W50";
    const evento = {
      empresa: EMPRESA,
      classificacao: "RELEVANTE",
      titulo: "Distribuicao de resultados",
      evento: "Acme Energia divulgou resultado trimestral.",
      impacto_credito: "Sem impacto material imediato.",
      fonte_primaria: FONTE_CVM,
      fonte_tipo: "CVM",
      data_evento: "2026-08-13",
      tags: ["resultados"],
      _pendente_verificacao: true,
    };
    await semear(SEMANA, [evento]);

    const r = await confirmar([item(SEMANA, ID_CVM, evento, VEREDITO_REPROVADO)]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, rejeitados: 1, retratados: 0, erros: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_CVM);
    // Nao certifica: continua pendente, sem flag terminal. Nenhum consumidor (feed, cards,
    // EWS, briefing, historico, op=state) filtra _verif_rejeitado e a sanitizacao remove
    // todo _* antes do frontend, entao limpar o pendente pintaria o evento como confirmado.
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_rejeitado).toBeUndefined();
    // Nao envenena o cache de 30d que o motor usa pra pular re-verificacao via cache_hits.
    expect(await lerCache(ID_CVM)).toBeNull();
  });

  it("ponta ruim: evento real com fonte primaria nula mas secundaria presente sobrevive ao REPROVADO", async () => {
    const SEMANA = "2026-W51";
    const evento = {
      empresa: EMPRESA,
      classificacao: "RELEVANTE",
      titulo: TITULO_SEM_FONTE,
      evento: "Acme Energia protocolou pedido tarifario.",
      impacto_credito: "Sem impacto material imediato.",
      fonte_primaria: null,
      fonte_secundaria: FONTE_IMPRENSA,
      fonte_tipo: "IMPRENSA",
      data_evento: "2026-08-14",
      tags: ["regulatorio"],
      _pendente_verificacao: true,
    };
    await semear(SEMANA, [evento]);

    const r = await confirmar([item(SEMANA, ID_SEM_FONTE, evento, VEREDITO_REPROVADO)]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, rejeitados: 1, retratados: 0, erros: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_secundaria).toBe(FONTE_IMPRENSA);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_rejeitado).toBeUndefined();
    expect(await lerCache(ID_SEM_FONTE)).toBeNull();
  });

  it("ponta boa: evento sem nenhuma fonte (alucinacao) segue apagado e REPROVADO vai ao cache", async () => {
    const SEMANA = "2026-W52";
    const evento = {
      empresa: EMPRESA,
      classificacao: "CRITICO",
      titulo: TITULO_SEM_FONTE,
      evento: "Acme Energia entrou em recuperacao judicial.",
      impacto_credito: "Risco elevado.",
      fonte_primaria: null,
      fonte_secundaria: null,
      fonte_tipo: "IMPRENSA",
      data_evento: "2026-08-15",
      tags: ["recuperacao-judicial"],
      _pendente_verificacao: true,
    };
    await semear(SEMANA, [evento]);

    const r = await confirmar([item(SEMANA, ID_ALUCINACAO, evento, VEREDITO_REPROVADO)]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, rejeitados: 1, retratados: 1, erros: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(0);
    // Alucinacao retratada e terminal: cache preservado evita re-verificacao paga do mesmo
    // fantasma em execucoes futuras.
    expect(await lerCache(ID_ALUCINACAO)).toMatchObject({ veredicto: "REPROVADO" });
  });
});
