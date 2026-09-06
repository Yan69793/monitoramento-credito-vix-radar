import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  sweepFilaVerificacaoOrfaos,
  chaveOrfaoVerificacao,
  chaveTentativaVerificacao,
  chaveFilaVerificacao,
  ORFAO_PREFIXO,
  enfileirarVerificacaoAssincronaInterno,
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

function eventoBase() {
  return {
    empresa: EMPRESA,
    classificacao: "CRITICO",
    titulo: "Fato de credito relevante",
    evento: "Petrobras divulgou fato de credito.",
    impacto_credito: "Relevante para credito.",
    fonte_primaria: FONTE,
    fonte_tipo: "CVM",
    data_evento: DATA_EV,
    tags: ["resultados"],
  };
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

    expect(r.adicionados).toBe(1);
    expect(r.indice_erro).toBeNull();
    const fila = await lerFila(hoje());
    expect(fila).toHaveLength(1);
    expect(fila[0].id).toBe(ID);
    expect(await lerOrfao(ID)).toBeNull();
    expect(await listarOrfaos()).toHaveLength(0);
  });

  it("11. FAIL-CLOSED: reentrada que NAO persiste mantem o orfao", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();

    // indice ilegivel => portao A bloqueia antes de enfileirar qualquer coisa
    await resetIndiceQuarentena(env);
    const r = await enfileirarVerificacaoAssincronaInterno(env, EMPRESA, SEMANA, SETOR, [eventoBase()]);

    expect(r.adicionados).toBe(0);
    expect(r.indice_erro).toBeTruthy();
    expect(await lerFila(hoje())).toBeNull();
    // o rastro nao pode ter sumido
    expect(await lerOrfao(ID)).toBeTruthy();
  });

  it("12. falha ao apagar o orfao apos reentrada deixa fila E orfao (vermelho a mais)", async () => {
    await semearFila(hoje(), [itemFila(50)]);
    await sweepFilaVerificacaoOrfaos(env);
    expect(await lerOrfao(ID)).toBeTruthy();

    _definirFalhaInjetadaTeste("orfao_delete_reentrada");
    const r = await enfileirarVerificacaoAssincronaInterno(env, EMPRESA, SEMANA, SETOR, [eventoBase()]);

    // a reentrada valeu: o item esta na fila
    expect(r.adicionados).toBe(1);
    const fila = await lerFila(hoje());
    expect(fila).toHaveLength(1);
    expect(fila[0].id).toBe(ID);
    // e o orfao coexiste, segurando o health em vermelho
    expect(await lerOrfao(ID)).toBeTruthy();
    const h = await health();
    expect(h.verificador_ok).toBe(false);

    // outra ponta: sem a falha, a mesma reentrada limpa
    _limparFalhasInjetadasTeste();
    await env.RADAR_KV.delete(chaveFilaVerificacao(hoje()));
    const r2 = await enfileirarVerificacaoAssincronaInterno(env, EMPRESA, SEMANA, SETOR, [eventoBase()]);
    expect(r2.adicionados).toBe(1);
    expect(await lerOrfao(ID)).toBeNull();
  });
});
