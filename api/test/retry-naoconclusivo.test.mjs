import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena, resetIndiceQuarentena } from "./_quarentena-idx.mjs";
import { beforeEach, describe, expect, it } from "vitest";

// REPROVADO-FAILCLOSED1 (2026-09-06): gates sao fail-closed; indice ausente = erro.
// O KV e compartilhado entre test() do mesmo arquivo e o ConfigDO guarda copia
// propria: limpa os dois antes de semear o indice vazio.
beforeEach(async () => {
  await resetIndiceQuarentena(env);
  await bootstrapIndiceQuarentena(env);
});

// REPROVADO-FAILCLOSED1, retry bounded (auditoria 2026-09-05, decisao do operador, N=3).
//
// O verificador adversarial devolve REPROVADO tanto ao provar falsidade quanto ao NAO
// conseguir confirmar (fonte inacessivel, reCAPTCHA, fonte ausente). O evento real que so
// nao foi re-confirmavel permanece pendente no estado (ver test/retratar-reprovado.test.mjs)
// e a varredura seguinte re-emite o mesmo id para a fila de verificacao. Sem controle esse
// ciclo re-queimava verificacao adversaria paga no mesmo evento, indefinidamente.
//
// Contrato canonico escolhido pelo operador em 2026-09-05 (N=3):
//   - maximo 3 verificacoes NAO-CONCLUSIVAS por id;
//   - backoff persistente: apos n=1 proxima elegivel >= 24h; apos n=2 >= 48h;
//   - a 3a nao-conclusiva retira o id do ciclo automatico e marca revisao manual
//     (esgotado/aguarda_manual) no registro radar:verif:attempt:{id};
//   - NUNCA apaga evento com fonte citavel; nunca certifica (segue _pendente_verificacao);
//   - alucinacao sem fonte nenhuma segue terminal e retratavel (apagada, cache terminal);
//   - cache terminal so no desfecho realmente terminal (alucinacao apagada), nunca num
//     REPROVADO nao-conclusivo (nem esgotado: esgotado aguarda decisao, nao e desfecho);
//   - contador/backoff persistentes e idempotentes por id.
//
// Prova de DUAS PONTAS (regra 5 do CLAUDE.md) para cada portao:
//   - portao C (confirmar): tentativas 1 e 2 incrementam e seguem reprocessaveis; a 3a
//     esgota; uma 4a confirmacao e recusada (resultado.esgotados, contador nao anda).
//   - portao B (listar_fila_verificacao, a leitura que o motor atravessa): id esgotado
//     semeado na fila NAO e devolvido, enquanto um id livre ao lado e devolvido. E o que
//     torna a "quarta tentativa automatica" impossivel sem depender do motor se comportar.
//   - portao A (enfileirarVerificacaoAssincronaInterno, unico ponto de reentrada) usa o
//     mesmo helper _verifEstadoAuto provado acima pelos portoes B e C.
//
// Cada teste usa id/data proprios: o storage do arquivo e compartilhado entre os it(),
// entao reusar o mesmo id entre testes contaminaria o contador de tentativas.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const ADMIN_PASSWORD = "test-admin-password-nao-usar-em-producao";
const EMPRESA = "Acme Energia";
const SETOR = "Energia Eletrica";

const FONTE_CVM = "https://rad.cvm.gov.br/fato-160616";
const HOST_CVM = "rad.cvm.gov.br/fato-160616";

// _chaveDedupEvento(ev) = data|empresa_lowercase|host+path (cai para titulo quando sem fonte).
const ID_DATA_1 = "2026-08-13"; // reprocessaveis (teste 1)
const ID_DATA_2 = "2026-08-14"; // esgota na 3a (teste 2)
const ID_DATA_3 = "2026-08-15"; // quarta impossivel (teste 3)
const ID_DATA_FRESCO = "2026-08-12"; // controle livre no listar (teste 3)
const ID_DATA_4 = "2026-08-16"; // alucinacao terminal (teste 4)
const ID_DATA_5 = "2026-08-17"; // admin (teste 5)

function fazerId(data) {
  return `${data}|acme energia|${HOST_CVM}`;
}

const ID_1 = fazerId(ID_DATA_1);
const ID_2 = fazerId(ID_DATA_2);
const ID_3 = fazerId(ID_DATA_3);
const ID_FRESCO = fazerId(ID_DATA_FRESCO);
const ID_ALUCINACAO = `2026-08-16|acme energia|pedido tarifario na aneel`;
const ID_5 = fazerId(ID_DATA_5);

const TITULO_SEM_FONTE = "Pedido tarifario na ANEEL";

const VEREDITO_REPROVADO = {
  veredicto: "REPROVADO",
  confianca: 0.2,
  motivo: "evidencia nao encontrada",
  fontes_validas: [],
};

const TTL_REGISTRO = 60 * 60 * 24 * 90;

function eventoComFonte(dataEvento) {
  return {
    empresa: EMPRESA,
    classificacao: "CRITICO",
    titulo: "Distribuicao de resultados",
    evento: "Acme Energia divulgou resultado trimestral.",
    impacto_credito: "Sem impacto material imediato.",
    fonte_primaria: FONTE_CVM,
    fonte_tipo: "CVM",
    data_evento: dataEvento,
    tags: ["resultados"],
    _pendente_verificacao: true,
  };
}

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

async function lerRegistro(id) {
  return env.RADAR_KV.get(`radar:verif:attempt:${id}`, "json");
}

async function lerCache(id) {
  return env.RADAR_KV.get(`radar:verif:${id}`, "json");
}

// Simula o relogio andando: o backoff do registro existente vence. O contador n preservado,
// so a janela (proxima_em) e reescrita para o passado, como aconteceria com o passar de 24h.
async function vencerJanela(id) {
  const chave = `radar:verif:attempt:${id}`;
  const reg = await env.RADAR_KV.get(chave, "json");
  if (!reg) throw new Error("registro de tentativa ausente para vencer a janela");
  reg.proxima_em = "2020-01-01T00:00:00.000Z";
  await env.RADAR_KV.put(chave, JSON.stringify(reg), { expirationTtl: TTL_REGISTRO });
}

async function esgotar(id, dataEvento, semana) {
  const evento = eventoComFonte(dataEvento);
  for (let t = 1; t <= 3; t++) {
    if (t > 1) await vencerJanela(id);
    const r = await confirmar([item(semana, id, evento, VEREDITO_REPROVADO)]);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, rejeitados: 1, retratados: 0, esgotados: 0 });
  }
}

function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body)),
  });
}

function confirmar(itens) {
  return post({ action: "confirmar_verificacao", itens });
}

function listarFila() {
  return post({ action: "listar_fila_verificacao", dias: 3 });
}

function item(semana, id, evento, veredicto) {
  return { id, empresa: EMPRESA, semana, data_fila: "2026-09-05", setor: SETOR, evento, veredicto };
}

function diffHoras(isoFuturo, isoBase) {
  return (new Date(isoFuturo).getTime() - new Date(isoBase).getTime()) / 36e5;
}

describe("REPROVADO-FAILCLOSED1 retry bounded: maximo 3 nao-conclusivas por id, backoff, quarentena, nunca apaga evento real", () => {
  it("tentativas 1 e 2 permanecem reprocessaveis e nao-conclusivas nao envenenam cache", async () => {
    const SEMANA = "2026-W60";
    const evento = eventoComFonte(ID_DATA_1);
    await semear(SEMANA, [evento]);

    // Tentativa 1: contador n=1, esgotado ausente (reprocessavel), backoff ~24h.
    const r1 = await confirmar([item(SEMANA, ID_1, evento, VEREDITO_REPROVADO)]);
    const b1 = await r1.json();
    expect(b1.resultado).toMatchObject({ processados: 1, aprovados: 0, rejeitados: 1, retratados: 0, esgotados: 0 });
    let rec = await lerRegistro(ID_1);
    expect(rec.n).toBe(1);
    expect(rec.esgotado).toBeUndefined();
    expect(rec.aguarda_manual).toBeUndefined();
    expect(diffHoras(rec.proxima_em, rec.ultima_em)).toBeGreaterThan(23);
    expect(diffHoras(rec.proxima_em, rec.ultima_em)).toBeLessThan(25);
    // Evento real preservado, pendente, sem flag terminal, sem cache envenenado.
    let evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_rejeitado).toBeUndefined();
    expect(await lerCache(ID_1)).toBeNull();

    // Janela de 24h vence. Tentativa 2: n=2, esgotado ausente (ainda reprocessavel), ~48h.
    await vencerJanela(ID_1);
    const r2 = await confirmar([item(SEMANA, ID_1, evento, VEREDITO_REPROVADO)]);
    const b2 = await r2.json();
    expect(b2.resultado).toMatchObject({ processados: 1, rejeitados: 1, retratados: 0, esgotados: 0 });
    rec = await lerRegistro(ID_1);
    expect(rec.n).toBe(2);
    expect(rec.esgotado).toBeUndefined();
    expect(diffHoras(rec.proxima_em, rec.ultima_em)).toBeGreaterThan(47);
    expect(diffHoras(rec.proxima_em, rec.ultima_em)).toBeLessThan(49);

    evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_CVM);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(await lerCache(ID_1)).toBeNull();
  });

  it("tentativa 3 encerra a automacao: esgotado/aguarda_manual, evento com fonte segue vivo e pendente", async () => {
    const SEMANA = "2026-W61";
    const evento = eventoComFonte(ID_DATA_2);
    await semear(SEMANA, [evento]);

    for (let tentativa = 1; tentativa <= 3; tentativa++) {
      if (tentativa > 1) await vencerJanela(ID_2);
      const r = await confirmar([item(SEMANA, ID_2, evento, VEREDITO_REPROVADO)]);
      const b = await r.json();
      expect(b.resultado).toMatchObject({ processados: 1, rejeitados: 1, retratados: 0, esgotados: 0 });
    }

    const rec = await lerRegistro(ID_2);
    expect(rec.n).toBe(3);
    expect(rec.esgotado).toBe(true);
    expect(rec.aguarda_manual).toBe(true);
    expect(rec.proxima_em).toBeNull();
    // Nao apagou, nao certificou: evento preservado com a fonte citavel, ainda pendente.
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_CVM);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_rejeitado).toBeUndefined();
    // Esgotado aguarda decisao manual, nao e desfecho terminal: nada no cache de 30d.
    expect(await lerCache(ID_2)).toBeNull();
  });

  it("quarta tentativa automatica impossivel: confirmar recusa (esgotados) e listar nao entrega ao motor", async () => {
    const SEMANA = "2026-W62";
    const evento = eventoComFonte(ID_DATA_3);
    await semear(SEMANA, [evento]);
    await esgotar(ID_3, ID_DATA_3, SEMANA);

    // Portao C: uma 4a confirmacao que chegasse (motor orfao que listou antes do esgotamento)
    // e recusada sem recontar, sem rejeitar, sem mexer no evento.
    const r4 = await confirmar([item(SEMANA, ID_3, evento, VEREDITO_REPROVADO)]);
    const b4 = await r4.json();
    expect(b4.resultado).toMatchObject({ processados: 1, rejeitados: 0, esgotados: 1 });
    const rec = await lerRegistro(ID_3);
    expect(rec.n).toBe(3);
    expect(rec.esgotado).toBe(true);
    let evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(await lerCache(ID_3)).toBeNull();

    // Portao B: mesmo que o id esgotado esteja fisicamente na fila do dia (varredura antiga),
    // listar_fila_verificacao nao o devolve ao motor. Um id livre ao lado continua visivel:
    // prova de duas pontas.
    const hoje = new Date().toISOString().slice(0, 10);
    const filaBloqueada = {
      id: ID_3, empresa: EMPRESA, semana: SEMANA, setor: SETOR,
      evento: eventoComFonte(ID_DATA_3), criado_em: "2026-09-05T00:00:00.000Z",
    };
    const filaLivre = {
      id: ID_FRESCO, empresa: EMPRESA, semana: SEMANA, setor: SETOR,
      evento: eventoComFonte(ID_DATA_FRESCO), criado_em: "2026-09-05T00:00:00.000Z",
    };
    await env.RADAR_KV.put(`radar:verif_fila:${hoje}`, JSON.stringify([filaBloqueada, filaLivre]), { expirationTtl: 60 * 60 * 24 * 7 });

    const rl = await listarFila();
    expect(rl.status).toBe(200);
    const bl = await rl.json();
    expect(bl.total).toBe(1);
    expect(bl.itens.map((i) => i.id)).toEqual([ID_FRESCO]);
    expect(bl.cache_hits).not.toHaveProperty(ID_3);
  });

  it("alucinacao sem fonte nenhuma segue terminal: apagada, cache REPROVADO, sem registro de tentativa", async () => {
    const SEMANA = "2026-W63";
    const evento = {
      empresa: EMPRESA,
      classificacao: "CRITICO",
      titulo: TITULO_SEM_FONTE,
      evento: "Acme Energia entrou em recuperacao judicial.",
      impacto_credito: "Risco elevado.",
      fonte_primaria: null,
      fonte_secundaria: null,
      fonte_tipo: "IMPRENSA",
      data_evento: ID_DATA_4,
      tags: ["recuperacao-judicial"],
      _pendente_verificacao: true,
    };
    await semear(SEMANA, [evento]);

    const r = await confirmar([item(SEMANA, ID_ALUCINACAO, evento, VEREDITO_REPROVADO)]);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, rejeitados: 1, retratados: 1, esgotados: 0 });

    expect(await lerEventos(SEMANA)).toHaveLength(0);
    // Desfecho realmente terminal: cache preservado, e o contador de retry nao cria saga
    // para quem ja morreu (nao e nao-conclusivo, e falsidade provada por ausencia total).
    expect(await lerCache(ID_ALUCINACAO)).toMatchObject({ veredicto: "REPROVADO" });
    expect(await lerRegistro(ID_ALUCINACAO)).toBeNull();
  });

  it("exposicao admin: quarentena listada e limpavel pelo operador (reabre o id)", async () => {
    const SEMANA = "2026-W64";
    const evento = eventoComFonte(ID_DATA_5);
    await semear(SEMANA, [evento]);
    await esgotar(ID_5, ID_DATA_5, SEMANA);

    // Lista so a quarentena: o id esgotado aparece com n=3 e a empresa canonica do payload.
    const rl = await post({ action: "admin_verif_tentativas", admin_senha: ADMIN_PASSWORD, quarentena: true });
    const bl = await rl.json();
    expect(bl.ok).toBe(true);
    const achado = bl.registros.find((x) => x.id === ID_5);
    expect(achado).toBeTruthy();
    expect(achado.n).toBe(3);
    expect(achado.esgotado).toBe(true);
    expect(achado.aguarda_manual).toBe(true);
    expect(achado.empresa).toBe(EMPRESA);
    // REPROVADO-FAILCLOSED1 (2026-09-06): a listagem expoe o estado de quarentena do indice.
    expect(achado.quarentenado).toBe(true);

    // Sem senha admin, acesso negado.
    const rneg = await post({ action: "admin_verif_tentativas", quarentena: true });
    expect(rneg.status).toBe(403);

    // Decisao do operador: id QUARENTENADO => reabertura completa (reenfileira, limpa
    // attempt, reabre o evento no estado e so por ultimo remove o id do indice).
    const rlim = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_5 });
    const blim = await rlim.json();
    expect(blim.ok).toBe(true);
    expect(blim.quarentena).toBe(true);
    expect(blim.reaberto).toBe(true);
    expect(await lerRegistro(ID_5)).toBeNull();
    const idx5 = await env.RADAR_KV.get("radar:verif:quarentena_idx", "json");
    expect(idx5.ids[ID_5]).toBeUndefined();

    const rl2 = await post({ action: "admin_verif_tentativas", admin_senha: ADMIN_PASSWORD, quarentena: true });
    const bl2 = await rl2.json();
    expect(bl2.registros.find((x) => x.id === ID_5)).toBeUndefined();
  });
});
