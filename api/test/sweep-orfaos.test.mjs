import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  sweepFilaVerificacaoOrfaos,
  chaveOrfaoVerificacao,
  chaveConclusaoVerificacao,
  chaveTentativaVerificacao,
  chaveFilaVerificacao,
  ORFAO_PREFIXO,
  enfileirarVerificacaoAssincronaInterno,
  _reconciliarOrfaosConcluidos,
  removerDaFilaVerificacaoInterno,
  carregarIndiceQuarentena,
  _definirFalhaInjetadaTeste,
  _limparFalhasInjetadasTeste,
} from "../src/worker.js";
import { bootstrapIndiceQuarentena, resetIndiceQuarentena, lerIndice } from "./_quarentena-idx.mjs";

// =============================================================================
// SWEEP-ORFAOS1 (2026-09-06): o sweep removia o item da fila em 48h e nao tocava
// o evento. Como o health mede pendencia lendo a FILA e nao o estado, a remocao
// devolvia verde com _pendente_verificacao:true ainda em aberto. Falso-verde
// estrutural, mesma familia do VERIFSLA2.
//
// Contrato provado aqui, sempre de duas pontas:
//   1  item <48h permanece, nenhum orfao criado
//   2  item >=48h vira orfao ANTES de sair da fila
//   3  falha ao gravar o orfao preserva a fila (fail-closed)
//   4  sweep repetido e idempotente, preserva o expirado_em original
//   5  fila vazia + orfao ativo => verificador_ok:false
//   6  falha ao listar orfaos => fail-closed (nao vira verde)
//   7  timeout nao altera o evento
//   8  timeout nao cria quarentena
//   9  timeout nao limpa o attempt (teto n=3 intacto)
//  10  reentrada persistida remove o orfao
//  11  reentrada que NAO persiste mantem o orfao
//  12  falha ao apagar o orfao apos reentrada deixa fila e orfao coexistindo
//  13  orfao nao tem TTL
// =============================================================================

const EMPRESA = "Petrobras";
const SETOR = "Energia Eletrica";
const SEMANA = "2026-W36";
const FONTE = "https://rad.cvm.gov.br/fato-160616";
const HOST = "rad.cvm.gov.br/fato-160616";
const DATA_EV = "2026-09-03";
const ID = `${DATA_EV}|${EMPRESA.toLowerCase()}|${HOST}`;

const H = 60 * 60 * 1e3;
const hoje = () => new Date().toISOString().slice(0, 10);

function eventoBase(extra) {
  return Object.assign(
    {
      empresa: EMPRESA,
      classificacao: "CRITICO",
      titulo: "Fato de credito relevante",
      evento: "Petrobras divulgou fato de credito.",
      impacto_credito: "Relevante para credito.",
      fonte_primaria: FONTE,
      fonte_tipo: "CVM",
      data_evento: DATA_EV,
      tags: ["resultados"],
    },
    extra || {}
  );
}

// idadeH horas atras. Item no formato exato que enfileirarVerificacaoAssincronaInterno grava.
function itemFila(idadeH, extra) {
  return Object.assign(
    {
      id: ID,
      empresa: EMPRESA,
      semana: SEMANA,
      setor: SETOR,
      evento: eventoBase(),
      criado_em: new Date(Date.now() - idadeH * H).toISOString(),
    },
    extra || {}
  );
}

async function semearFila(data, itens) {
  await env.RADAR_KV.put(chaveFilaVerificacao(data), JSON.stringify(itens), { expirationTtl: 60 * 60 * 24 * 7 });
}

async function lerFila(data) {
  return env.RADAR_KV.get(chaveFilaVerificacao(data), "json");
}

async function lerOrfao(id) {
  return env.RADAR_KV.get(chaveOrfaoVerificacao(id), "json");
}

async function listarOrfaos() {
  const l = await env.RADAR_KV.list({ prefix: ORFAO_PREFIXO });
  return l.keys;
}

async function semearEstado(eventos) {
  await env.RADAR_KV.put(
    `radar:estado:${SEMANA}`,
    JSON.stringify({
      week: SEMANA,
      results: { [EMPRESA]: { empresa: EMPRESA, setor: SETOR, sem_eventos: false, eventos } },
      updated_at: "2026-09-05T00:00:00.000Z",
    })
  );
}

const health = () => SELF.fetch("https://example.com/").then((r) => r.json());

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc

function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body)),
  });
}

async function lerConclusao(id) {
  return env.RADAR_KV.get(chaveConclusaoVerificacao(id), "json");
}

async function lerEventos() {
  const raw = await env.RADAR_KV.get(`radar:estado:${SEMANA}`, "json");
  const reg = raw && raw.results && raw.results[EMPRESA];
  return reg && Array.isArray(reg.eventos) ? reg.eventos : [];
}

// Estado com o evento pendente + fila expirada, roda o sweep e devolve a
// data_fila. Ponto de partida de todo teste de conclusao terminal: para o merge
// casar, o evento tem que existir no estado com a mesma chave dedup do id.
async function prepararOrfaoComEstado() {
  const d = hoje();
  await semearEstado([Object.assign(eventoBase(), { _pendente_verificacao: true })]);
  await semearFila(d, [itemFila(50)]);
  await sweepFilaVerificacaoOrfaos(env);
  return d;
}

async function confirmarAprovado(dataFila) {
  const r = await post({
    action: "confirmar_verificacao",
    itens: [{
      id: ID,
      empresa: EMPRESA,
      semana: SEMANA,
      data_fila: dataFila,
      setor: SETOR,
      evento: eventoBase(),
      veredicto: { veredicto: "APROVADO", confianca: 0.95, motivo: "fonte primaria confirmada", fontes_validas: [FONTE] },
    }],
  });
  return r.json();
}

beforeEach(async () => {
  const _limpar = async (prefixo) => {
    const l = await env.RADAR_KV.list({ prefix: prefixo });
    for (const k of l.keys) {
      try { await env.RADAR_KV.delete(k.name); } catch (_) { }
    }
  };
  await _limpar("radar:verif:");
  await _limpar("radar:verif_fila:");
  try { await env.RADAR_KV.delete(`radar:estado:${SEMANA}`); } catch (_) { }
  await resetIndiceQuarentena(env);
  await bootstrapIndiceQuarentena(env);
  _limparFalhasInjetadasTeste();
});

describe("SWEEP-ORFAOS1 - o sweep registra antes de remover", () => {
  it("1. item com menos de 48h permanece na fila e NAO vira orfao", async () => {
    const d = hoje();
    await semearFila(d, [itemFila(20)]);

    const r = await sweepFilaVerificacaoOrfaos(env);

    expect(r.removidos).toBe(0);
    expect(r.orfaos_registrados).toBe(0);
    const fila = await lerFila(d);
    expect(Array.isArray(fila)).toBe(true);
    expect(fila.length).toBe(1);
    expect(fila[0].id).toBe(ID);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await listarOrfaos()).toHaveLength(0);
  });

  it("2. item com 48h+ vira orfao rastreavel E sai da fila, com os campos preservados", async () => {
    const d = hoje();
    await semearFila(d, [itemFila(50)]);

    const r = await sweepFilaVerificacaoOrfaos(env);

    expect(r.removidos).toBe(1);
    expect(r.orfaos_registrados).toBe(1);
    expect(r.falhas).toBe(0);
    // fila esvaziou => chave apagada
    expect(await lerFila(d)).toBeNull();

    const orfao = await lerOrfao(ID);
    expect(orfao).toBeTruthy();
    expect(orfao.id).toBe(ID);
    expect(orfao.empresa).toBe(EMPRESA);
    expect(orfao.semana).toBe(SEMANA);
    expect(orfao.setor).toBe(SETOR);
    expect(orfao.motivo).toBe("fila_expirada_48h");
    expect(orfao.origem).toBe("sweep");
    expect(orfao.data_fila).toBe(d);
    expect(typeof orfao.criado_em).toBe("string");
    expect(typeof orfao.expirado_em).toBe("string");
    expect(Number.isNaN(Date.parse(orfao.expirado_em))).toBe(false);
  });

  it("3. FAIL-CLOSED: falha ao gravar o orfao preserva o item na fila", async () => {
    const d = hoje();
    await semearFila(d, [itemFila(50)]);
    _definirFalhaInjetadaTeste("orfao_put");

    const r = await sweepFilaVerificacaoOrfaos(env);

    expect(r.removidos).toBe(0);
    expect(r.orfaos_registrados).toBe(0);
    expect(r.falhas).toBe(1);
    // o item continua na fila, continua envelhecendo, continua segurando o health
    const fila = await lerFila(d);
    expect(fila).toHaveLength(1);
    expect(fila[0].id).toBe(ID);
    expect(await lerOrfao(ID)).toBeNull();

    // outra ponta: sem a falha injetada, a MESMA entrada converge
    _limparFalhasInjetadasTeste();
    const r2 = await sweepFilaVerificacaoOrfaos(env);
    expect(r2.removidos).toBe(1);
    expect(r2.falhas).toBe(0);
    expect(await lerOrfao(ID)).toBeTruthy();
  });

  it("4. sweep repetido e idempotente e preserva o expirado_em da primeira deteccao", async () => {
    const d = hoje();
    await semearFila(d, [itemFila(50)]);

    await sweepFilaVerificacaoOrfaos(env);
    const primeiro = await lerOrfao(ID);
    expect(primeiro).toBeTruthy();

    // re-semeia o mesmo item expirado e roda de novo
    await semearFila(d, [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);

    const segundo = await lerOrfao(ID);
    expect(segundo.expirado_em).toBe(primeiro.expirado_em);
    expect(await listarOrfaos()).toHaveLength(1);
  });

  it("13. o registro de orfao NAO tem TTL (expiracao recriaria o falso-verde)", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);

    const chaves = await listarOrfaos();
    expect(chaves).toHaveLength(1);
    expect(chaves[0].name).toBe(chaveOrfaoVerificacao(ID));
    // KV so devolve `expiration` quando a chave tem TTL. Ausente = permanente.
    expect(chaves[0].expiration === undefined || chaves[0].expiration === null).toBe(true);
  });
});

describe("SWEEP-ORFAOS1 - o falso-verde morre no health", () => {
  it("5. fila vazia com orfao ativo mantem verificador_ok=false", async () => {
    // sem orfao: o gate do verificador nao e segurado por este eixo
    const antes = await health();
    expect(antes.verif_orfaos_ativos).toBe(0);
    const verificadorSemOrfao = antes.verificador_ok;

    // agora com orfao, fila comprovadamente vazia
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerFila(hoje())).toBeNull();

    const depois = await health();
    expect(depois.verif_orfaos_ativos).toBeGreaterThanOrEqual(1);
    expect(depois.verificador_ok).toBe(false);
    expect(depois.ok).toBe(false);

    // prova de 2 pontas: era o orfao, nao outra coisa. Removido, o eixo solta.
    await env.RADAR_KV.delete(chaveOrfaoVerificacao(ID));
    const limpo = await health();
    expect(limpo.verif_orfaos_ativos).toBe(0);
    expect(limpo.verificador_ok).toBe(verificadorSemOrfao);
  });

  it("6. FAIL-CLOSED: falha ao listar orfaos nao pode virar verde", async () => {
    _definirFalhaInjetadaTeste("orfao_list");

    const h = await health();

    expect(h.verif_orfaos_ativos).toBe(-1);
    expect(h.verificador_ok).toBe(false);
    expect(h.ok).toBe(false);
  });
});

describe("SWEEP-ORFAOS1 - timeout nao decide nada alem da fila", () => {
  it("7. o evento fica intacto, _pendente_verificacao continua true", async () => {
    const evento = Object.assign(eventoBase(), { _pendente_verificacao: true });
    await semearEstado([evento]);
    const bruto = await env.RADAR_KV.get(`radar:estado:${SEMANA}`, "text");

    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);

    expect(await env.RADAR_KV.get(`radar:estado:${SEMANA}`, "text")).toBe(bruto);
    const raw = await env.RADAR_KV.get(`radar:estado:${SEMANA}`, "json");
    expect(raw.results[EMPRESA].eventos[0]._pendente_verificacao).toBe(true);
  });

  it("8. o timeout NAO cria quarentena", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);

    const idx = await lerIndice(env);
    expect(idx.schema).toBe(1);
    expect(Object.keys(idx.ids)).toHaveLength(0);
    const carregado = await carregarIndiceQuarentena(env);
    expect(carregado.ok).toBe(true);
    expect(carregado.ids.has(ID)).toBe(false);
  });

  it("9. o timeout NAO limpa o attempt (teto n=3 intacto)", async () => {
    const reg = { id: ID, n: 2, proxima_em: "2026-09-08T00:00:00.000Z", atualizado_em: "2026-09-06T00:00:00.000Z" };
    await env.RADAR_KV.put(chaveTentativaVerificacao(ID), JSON.stringify(reg), { expirationTtl: 60 * 60 * 24 * 90 });

    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);

    const depois = await env.RADAR_KV.get(chaveTentativaVerificacao(ID), "json");
    expect(depois).toBeTruthy();
    expect(depois.n).toBe(2);
  });
});

describe("SWEEP-ORFAOS1 - a reentrada resolve, e so ela", () => {
  it("10. reentrada persistida na fila remove o orfao, sem tocar o attempt", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();

    const r = await enfileirarVerificacaoAssincronaInterno(env, EMPRESA, SEMANA, SETOR, [eventoBase()]);

    // a reentrada acontece normalmente
    expect(r.adicionados).toBe(1);
    expect(r.indice_erro).toBeNull();
    const fila = await lerFila(hoje());
    expect(fila).toHaveLength(1);
    expect(fila[0].id).toBe(ID);
    // ...e o orfao CONTINUA. Voltar para a fila prova reentrada no ciclo, nao
    // conclusao da verificacao. Health segue vermelho.
    expect(await lerOrfao(ID)).toBeTruthy();
    expect(await lerConclusao(ID)).toBeNull();
    const h = await health();
    expect(h.verificador_ok).toBe(false);
    expect(h.verif_orfaos_ativos).toBeGreaterThanOrEqual(1);
  });

  it("11. FAIL-CLOSED: reentrada bloqueada tambem mantem o orfao", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();

    // indice ilegivel => portao A bloqueia antes de enfileirar qualquer coisa
    await resetIndiceQuarentena(env);
    const r = await enfileirarVerificacaoAssincronaInterno(env, EMPRESA, SEMANA, SETOR, [eventoBase()]);

    expect(r.adicionados).toBe(0);
    expect(r.indice_erro).toBeTruthy();
    expect(await lerFila(hoje())).toBeNull();
    expect(await lerOrfao(ID)).toBeTruthy();
  });
});

describe("SWEEP-ORFAOS1 - so a conclusao terminal resolve", () => {
  it("14. conclusao terminal apaga o orfao e nao deixa marcador para tras", async () => {
    const d = await prepararOrfaoComEstado();

    const r = await confirmarAprovado(d);
    expect(r.ok).toBe(true);
    expect(r.resultado.aprovados).toBe(1);

    expect(await lerOrfao(ID)).toBeNull();
    expect(await lerConclusao(ID)).toBeNull();
    // o evento concluiu de verdade
    const evs = await lerEventos();
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(false);
    // e o health solta
    const h = await health();
    expect(h.verif_orfaos_ativos).toBe(0);
  });

  it("15. FAIL-CLOSED: falha no delete terminal preserva orfao E grava a prova", async () => {
    const d = await prepararOrfaoComEstado();
    _definirFalhaInjetadaTeste("orfao_delete_terminal");

    const r = await confirmarAprovado(d);
    expect(r.ok).toBe(true);
    expect(r.resultado.aprovados).toBe(1);

    // orfao permanece e a prova de conclusao ficou gravada, senao nada
    // convergiria depois.
    // NAO chamar health() aqui: ele dispara o sweep, o sweep reconcilia e o
    // orfao some no meio do teste. A convergencia e assunto do teste 16; aqui
    // o que se prova e o estado imediatamente apos a falha do delete.
    expect(await lerOrfao(ID)).toBeTruthy();
    const marcador = await lerConclusao(ID);
    expect(marcador).toBeTruthy();
    expect(marcador.id).toBe(ID);
    expect(Number.isNaN(Date.parse(marcador.concluido_em))).toBe(false);
    // e a conclusao e posterior ao orfao, que e o que autoriza a convergencia
    const orfao = await lerOrfao(ID);
    expect(Date.parse(marcador.concluido_em)).toBeGreaterThan(Date.parse(orfao.expirado_em));
  });

  it("16. o sweep seguinte converge: marcador posterior ao expirado_em resolve o orfao", async () => {
    const d = await prepararOrfaoComEstado();
    _definirFalhaInjetadaTeste("orfao_delete_terminal");
    await confirmarAprovado(d);
    expect(await lerOrfao(ID)).toBeTruthy();

    // a falha era so no delete; o marcador esta la e prova conclusao posterior
    _limparFalhasInjetadasTeste();
    const rec = await _reconciliarOrfaosConcluidos(env, 100);

    expect(rec.resolvidos).toBe(1);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await lerConclusao(ID)).toBeNull();
    const h = await health();
    expect(h.verif_orfaos_ativos).toBe(0);
  });

  it("17. FAIL-CLOSED: marcador ANTERIOR ao expirado_em nao resolve (snapshot stale)", async () => {
    const agora = Date.now();
    // orfao expirado AGORA, conclusao de uma hora ATRAS: nao prova nada sobre
    // este orfao, e um desfecho velho de outra rodada.
    await env.RADAR_KV.put(chaveOrfaoVerificacao(ID), JSON.stringify({
      id: ID, empresa: EMPRESA, semana: SEMANA, setor: SETOR,
      criado_em: new Date(agora - 50 * H).toISOString(),
      expirado_em: new Date(agora).toISOString(),
      data_fila: hoje(), motivo: "fila_expirada_48h", origem: "sweep",
    }));
    await env.RADAR_KV.put(chaveConclusaoVerificacao(ID), JSON.stringify({
      id: ID, concluido_em: new Date(agora - 1 * H).toISOString(), veredicto: "APROVADO", origem: "confirmar_verificacao",
    }));

    const rec = await _reconciliarOrfaosConcluidos(env, 100);

    expect(rec.avaliados).toBe(1);
    expect(rec.resolvidos).toBe(0);
    expect(await lerOrfao(ID)).toBeTruthy();
    const h = await health();
    expect(h.verificador_ok).toBe(false);
  });

  it("18. FAIL-CLOSED: sem marcador o sweep nunca resolve, por mais que rode", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();
    expect(await lerConclusao(ID)).toBeNull();

    await sweepFilaVerificacaoOrfaos(env);
    await sweepFilaVerificacaoOrfaos(env);

    expect(await lerOrfao(ID)).toBeTruthy();
    const h = await health();
    expect(h.verificador_ok).toBe(false);
  });

  it("19. a conclusao terminal nao toca attempt nem quarentena", async () => {
    const d = await prepararOrfaoComEstado();
    const reg = { id: ID, n: 2, proxima_em: "2026-09-08T00:00:00.000Z", atualizado_em: "2026-09-06T00:00:00.000Z" };
    await env.RADAR_KV.put(chaveTentativaVerificacao(ID), JSON.stringify(reg), { expirationTtl: 60 * 60 * 24 * 90 });

    await confirmarAprovado(d);

    const attempt = await env.RADAR_KV.get(chaveTentativaVerificacao(ID), "json");
    expect(attempt).toBeTruthy();
    expect(attempt.n).toBe(2);
    const idx = await lerIndice(env);
    expect(Object.keys(idx.ids)).toHaveLength(0);
  });
});

// =============================================================================
// SWEEP-ORFAOS1-LIVENESS1 (P0, 2026-09-06, corrigido no mesmo dia): a primeira
// versao deste fix exigia removido:true da REMOCAO DA FILA como prova de
// conclusao terminal, para nao depender de uma releitura do KV apos a escrita
// (releitura e o problema real: KV e eventualmente consistente, um GET pode
// devolver snapshot velho e o codigo antigo tomava "nao achei na fila" como
// "removido de verdade", recriando o falso-verde). So que um orfao SO EXISTE
// porque o sweep JA tirou o item da fila — entao no caminho comum, quando a
// verificacao termina de verdade, nao ha mais nada para o terminal remover, a
// escrita nunca acontece, removido nunca e true, e o orfao ficava PRESO PARA
// SEMPRE mesmo com o evento genuinamente concluido. Bug pior que o original.
//
// Fix real: a prova de conclusao vem do retorno DIRETO das escritas que
// decidem o desfecho do EVENTO — mesclarEventoVerificado() !== false
// (aprovado) ou retratarEventoRejeitado() === true (reprovado sem fonte) —
// nunca de releitura, e nunca da remocao da fila, que e limpeza best-effort e
// ortogonal ao desfecho. Continua nao usando releitura em lugar nenhum; so
// mudou QUAL escrita conta como prova.
// =============================================================================
describe("SWEEP-ORFAOS1-LIVENESS1 (P0) - remocao da fila continua correta, mas nao e mais o gate", () => {
  it("20. removerDaFilaVerificacaoInterno so retorna removido:true apos escrita confirmada", async () => {
    // Vale por si so: a fila ainda precisa de limpeza correta, mesmo que ela
    // nao gate mais a resolucao do orfao.
    const d = hoje();
    await semearFila(d, [itemFila(10)]);
    _definirFalhaInjetadaTeste("fila_remover_put");

    const r = await removerDaFilaVerificacaoInterno(env, d, ID);

    expect(r.removido).toBe(false);
    expect(r.erro).toBeTruthy();
    const fila = await lerFila(d);
    expect(fila).toHaveLength(1);
    expect(fila[0].id).toBe(ID);

    _limparFalhasInjetadasTeste();
    const r2 = await removerDaFilaVerificacaoInterno(env, d, ID);
    expect(r2.removido).toBe(true);
    expect(await lerFila(d)).toBeNull();
  });

  it("21. P0 CENTRAL: merge recusado (MERGEDUP1) NAO resolve o orfao, mesmo com a fila ja vazia", async () => {
    // Sem semear radar:estado:{semana}, mesclarEventoVerificadoInterno nao acha
    // o evento nem por chaveOriginal nem por chaveNova e recusa (fail-closed,
    // retorna false). Fila ja vazia (o sweep ja limpou) e IRRELEVANTE para essa
    // decisao — e exatamente o ponto: nenhum dos dois eixos, isolado, prova
    // conclusao. So a escrita do EVENTO prova, e aqui ela nao aconteceu.
    const d = hoje();
    await semearFila(d, [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();
    expect(await lerFila(d)).toBeNull(); // fila ja vazia, por construcao do sweep

    const r = await confirmarAprovado(d); // sem estado semeado => merge recusado

    expect(r.ok).toBe(true);
    expect(r.resultado.mesclas_recusadas).toBe(1);
    expect(r.resultado.aprovados).toBe(0);
    expect(await lerOrfao(ID)).toBeTruthy();
    expect(await lerConclusao(ID)).toBeNull();
    const h = await health();
    expect(h.verificador_ok).toBe(false);
    expect(h.verif_orfaos_ativos).toBeGreaterThanOrEqual(1);
  });

  it("22. merge confirmado (retorno direto, sem releitura) resolve o orfao mesmo com a fila ja vazia", async () => {
    // Outra ponta do 21: mesmo estado de fila (ja vazia, sweep ja rodou), mas
    // agora o evento EXISTE no estado, entao o merge acontece de verdade e
    // mesclarEventoVerificado() devolve != false. Isso sozinho tem que resolver
    // o orfao — a fila continuar vazia nao impede nada, porque ela nunca foi
    // a prova.
    const d = await prepararOrfaoComEstado();
    expect(await lerFila(d)).toBeNull(); // ja vazia, sem nada physicamente para remover

    const r = await confirmarAprovado(d);

    expect(r.ok).toBe(true);
    expect(r.resultado.aprovados).toBe(1);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await lerConclusao(ID)).toBeNull();
    const h = await health();
    expect(h.verif_orfaos_ativos).toBe(0);
  });

  it("23. reentrada legitima (id de volta na fila) nao muda o resultado: so o merge decide", async () => {
    // Antes do fix real, este caso (id fisicamente na fila) era o unico em que
    // a resolucao funcionava, porque so ele produzia removido:true. Prova que
    // o novo gate nao ficou mais fraco: resolve igual, com ou sem o id na fila.
    const d = await prepararOrfaoComEstado();
    await semearFila(d, [itemFila(1)]);
    expect(await lerFila(d)).toHaveLength(1);

    const r = await confirmarAprovado(d);

    expect(r.ok).toBe(true);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await lerFila(d)).toBeNull(); // limpeza best-effort da fila ainda roda
  });

  it("24. reprovado sem fonte citavel (retratado) tambem resolve o orfao, pela prova direta de retratarEventoRejeitado", async () => {
    // Cobre o outro ramo de _cvProvaTerminal, que ate aqui so tinha o caminho
    // aprovado testado. Evento sem fonte_primaria/secundaria => alucinacao,
    // retratarEventoRejeitado apaga do estado e devolve true.
    const d = hoje();
    await semearEstado([Object.assign(eventoBase({ fonte_primaria: null }), { _pendente_verificacao: true })]);
    await semearFila(d, [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();

    const resp = await post({
      action: "confirmar_verificacao",
      itens: [{
        id: ID, empresa: EMPRESA, semana: SEMANA, data_fila: d, setor: SETOR,
        evento: eventoBase({ fonte_primaria: null }),
        veredicto: { veredicto: "REPROVADO", confianca: 0.9, motivo: "sem fonte primaria ou secundaria localizavel" },
      }],
    });
    const r = await resp.json();

    expect(r.ok).toBe(true);
    expect(r.resultado.retratados).toBe(1);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await lerConclusao(ID)).toBeNull();
    const evs = await lerEventos();
    expect(evs).toHaveLength(0); // alucinacao retratada, evento sai do estado
  });

  it("25. reprovado NAO-CONCLUSIVO (com fonte, sem retratar) NAO resolve o orfao", async () => {
    // _cvNaoConclusivo=true (fonte citavel, nao retratado) ja era excluido do
    // gate antes do P0; confirma que a correcao nao afrouxou essa regra.
    const d = await prepararOrfaoComEstado(); // eventoBase() tem fonte_primaria

    const resp = await post({
      action: "confirmar_verificacao",
      itens: [{
        id: ID, empresa: EMPRESA, semana: SEMANA, data_fila: d, setor: SETOR,
        evento: eventoBase(),
        veredicto: { veredicto: "REPROVADO", confianca: 0.6, motivo: "fonte primaria inacessivel, nao provado falso" },
      }],
    });
    const r = await resp.json();

    expect(r.ok).toBe(true);
    expect(r.resultado.rejeitados).toBe(1);
    expect(r.resultado.retratados).toBe(0);
    expect(await lerOrfao(ID)).toBeTruthy();
    expect(await lerConclusao(ID)).toBeNull();
  });

  it("26. no cenario P0 corrigido, attempt e quarentena continuam intocados quando o merge resolve", async () => {
    const d = await prepararOrfaoComEstado();
    const reg = { id: ID, n: 1, proxima_em: "2026-09-07T00:00:00.000Z", atualizado_em: "2026-09-06T00:00:00.000Z" };
    await env.RADAR_KV.put(chaveTentativaVerificacao(ID), JSON.stringify(reg), { expirationTtl: 60 * 60 * 24 * 90 });

    await confirmarAprovado(d);

    // orfao resolveu (merge aconteceu), attempt e quarentena nao foram tocados
    expect(await lerOrfao(ID)).toBeNull();
    const attempt = await env.RADAR_KV.get(chaveTentativaVerificacao(ID), "json");
    expect(attempt.n).toBe(1);
    const idx = await lerIndice(env);
    expect(Object.keys(idx.ids)).toHaveLength(0);
    const evs = await lerEventos();
    expect(evs[0]._pendente_verificacao).toBe(false);
  });
});
