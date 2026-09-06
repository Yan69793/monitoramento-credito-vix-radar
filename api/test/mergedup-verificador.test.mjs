import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// MERGEDUP1 (auditoria 2026-09-05, fix 2026-09-05).
//
// `mesclarEventoVerificadoInterno` casava o evento verificado com o que ja estava
// no estado por chave dedup RECALCULADA:
//
//   const chaveNovo = _chaveDedupEvento(evEnriquecido);
//   const idx = existentes.findIndex(ev => _chaveDedupEvento(ev) === chaveNovo);
//   if (idx >= 0) { merge no lugar } else { existentes.push(evEnriquecido); }
//
// So que `_chaveDedupEvento` inclui host+path de `fonte_primaria`, e
// `aplicarCorrecaoVerificador` REESCREVE `fonte_primaria` quando o veredicto e
// CORRIGIR com `correcoes.fonte_primaria` presente em `fontes_validas`. Reescrita a
// fonte, a chave muda, o findIndex nao acha nada e o codigo empurra DUPLICATA em vez
// de atualizar o evento existente. O call site (`confirmar_verificacao`) sempre teve
// `it.id`, que e exatamente a chave dedup de quando o item entrou na fila, e nao a
// passava adiante.
//
// Fix: `it.id` viaja como `chaveOriginal` ate o interno. Com ela presente o
// comportamento e fail-closed — casou exatamente 1, atualiza no lugar; casou 0 ou
// mais de 1, aborta sem gravar e sem push, contabilizando `mesclas_recusadas`. O
// caminho legado (chamador que nao informa chave) segue casando por `chaveNovo`.
//
// Prova de DUAS PONTAS (regra 5 do CLAUDE.md):
//   - ponta ruim: CORRIGIR que troca `fonte_primaria` (inclusive null -> URL, o caso
//     exato da Usina Pampa Sul em SOURCEFIX-PAMPASUL1) tem que terminar com 1 evento.
//     Contra o codigo pre-fix esses casos terminavam com 2.
//   - ponta boa: APROVADO sem mexer na fonte continua atualizando no lugar, e
//     REPROVADO continua retratando. O fix nao pode ter fechado o caminho feliz.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const EMPRESA = "Acme Energia";
const SETOR = "Energia Eletrica";

const FONTE_A = "https://example.com/fato-a";
const FONTE_B = "https://example.com/fato-b";

// _chaveDedupEvento(ev) = data|empresa_lowercase|host+path, e cai para
// data|empresa|titulo_normalizado quando fonte_primaria e vazia.
const ID_A = `2026-08-13|acme energia|example.com/fato-a`;
// Titulo escolhido sem acento, sem termo fraco e sem a preposicao "de", para que
// normalizarTituloParaDedup seja identidade a menos de lowercase.
const TITULO_SEM_FONTE = "Pedido tarifario na ANEEL";
const ID_SEM_FONTE = `2026-08-14|acme energia|pedido tarifario na aneel`;

function eventoBase(over) {
  return Object.assign({
    empresa: EMPRESA,
    classificacao: "RELEVANTE",
    titulo: "Evento original antes da verificacao",
    evento: "Acme Energia divulgou fato ao mercado.",
    impacto_credito: "Sem impacto material imediato.",
    fonte_primaria: FONTE_A,
    fonte_tipo: "IMPRENSA",
    data_evento: "2026-08-13",
    tags: ["resultados"],
  }, over || {});
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

describe("MERGEDUP1: verificador que altera fonte_primaria nao pode duplicar nem perder evento", () => {
  it("ponta boa: APROVADO sem mudanca de fonte mantem 1 evento, atualizado no lugar", async () => {
    const SEMANA = "2026-W40";
    await semear(SEMANA, [eventoBase({ _pendente_verificacao: true })]);

    const r = await confirmar([
      item(SEMANA, ID_A, eventoBase({ titulo: "Titulo confirmado pelo verificador" }), {
        veredicto: "APROVADO",
        confianca: 0.95,
        motivo: "fontes consistentes",
        fontes_validas: [FONTE_A],
      }),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 1, erros: 0, mesclas_recusadas: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].titulo).toBe("Titulo confirmado pelo verificador");
    expect(evs[0].fonte_primaria).toBe(FONTE_A);
    expect(evs[0]._pendente_verificacao).toBe(false);
  });

  it("ponta ruim: CORRIGIR que troca fonte_primaria continua com 1 evento (pre-fix davam 2)", async () => {
    const SEMANA = "2026-W41";
    await semear(SEMANA, [eventoBase({ _pendente_verificacao: true })]);

    const r = await confirmar([
      item(SEMANA, ID_A, eventoBase({}), {
        veredicto: "CORRIGIR",
        confianca: 0.9,
        motivo: "fonte apontava para documento errado",
        correcoes: { fonte_primaria: FONTE_B },
        fontes_validas: [FONTE_B],
      }),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 1, erros: 0, mesclas_recusadas: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_B);
    expect(evs[0]._pendente_verificacao).toBe(false);
  });

  it("ponta ruim: CORRIGIR de fonte ausente para URL continua com 1 evento (caso Pampa Sul)", async () => {
    const SEMANA = "2026-W42";
    await semear(SEMANA, [
      eventoBase({
        data_evento: "2026-08-14",
        titulo: TITULO_SEM_FONTE,
        fonte_primaria: null,
        fonte_secundaria: "https://imprensa.example.com/materia",
        _fonte_oficial_confirmada: false,
        _pendente_verificacao: true,
      }),
    ]);

    const r = await confirmar([
      item(
        SEMANA,
        ID_SEM_FONTE,
        eventoBase({ data_evento: "2026-08-14", titulo: TITULO_SEM_FONTE, fonte_primaria: null }),
        {
          veredicto: "CORRIGIR",
          confianca: 0.9,
          motivo: "fonte oficial localizada",
          correcoes: { fonte_primaria: FONTE_B },
          fontes_validas: [FONTE_B],
        }
      ),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 1, erros: 0, mesclas_recusadas: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_B);
  });

  it("ponta boa: REPROVADO segue retratando o evento pendente (comportamento atual, explicitado)", async () => {
    const SEMANA = "2026-W43";
    await semear(SEMANA, [eventoBase({ _pendente_verificacao: true })]);

    const r = await confirmar([
      item(SEMANA, ID_A, eventoBase({}), {
        veredicto: "REPROVADO",
        confianca: 0.2,
        motivo: "evidencia nao encontrada",
        fontes_validas: [],
      }),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, rejeitados: 1, retratados: 1, erros: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(0);
  });

  it("fail-closed: chaveOriginal que nao casa com nada recusa o merge e nao empurra", async () => {
    const SEMANA = "2026-W44";
    await semear(SEMANA, [eventoBase({ _pendente_verificacao: true })]);

    // Nem a chave original (id da fila) nem a chave nova (derivada da fonte do evento
    // que chega) correspondem a qualquer evento do estado. E o caso em que o codigo
    // antigo empurraria um evento novo, ressuscitando algo que ninguem rastreia.
    const r = await confirmar([
      item(
        SEMANA,
        `2026-08-13|acme energia|example.com/fonte-que-nao-existe`,
        eventoBase({ fonte_primaria: "https://example.com/fonte-orfa" }),
        {
          veredicto: "APROVADO",
          confianca: 0.95,
          motivo: "aprovado, mas id nao corresponde a nenhum evento do estado",
          fontes_validas: [FONTE_A],
        }
      ),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, mesclas_recusadas: 1, erros: 0 });

    // Nada foi empurrado: o estado continua com o unico evento original, intacto.
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].titulo).toBe("Evento original antes da verificacao");
    expect(evs[0]._pendente_verificacao).toBe(true);
  });

  it("idempotencia: reenvio do mesmo item apos o merge ja aplicado nao duplica", async () => {
    const SEMANA = "2026-W46";
    await semear(SEMANA, [eventoBase({ _pendente_verificacao: true })]);

    const veredicto = {
      veredicto: "CORRIGIR",
      confianca: 0.9,
      motivo: "fonte corrigida",
      correcoes: { fonte_primaria: FONTE_B },
      fontes_validas: [FONTE_B],
    };

    // 1a passada: casa por chaveOriginal e troca a fonte, entao o evento no estado
    // passa a carregar a chave NOVA.
    const r1 = await confirmar([item(SEMANA, ID_A, eventoBase({}), veredicto)]);
    expect((await r1.json()).resultado).toMatchObject({ aprovados: 1, mesclas_recusadas: 0 });

    // 2a passada (replay do cache, VERIFCACHE-ROUNDTRIP1): o mesmo id da fila ja nao
    // corresponde a evento nenhum, mas a chave nova sim. Tem que ser no-op, nunca push.
    const r2 = await confirmar([item(SEMANA, ID_A, eventoBase({}), veredicto)]);
    expect((await r2.json()).resultado).toMatchObject({ aprovados: 1, mesclas_recusadas: 0 });

    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_B);
  });

  it("fail-closed: chaveOriginal ambigua (2 eventos com a mesma chave) recusa o merge", async () => {
    const SEMANA = "2026-W45";
    // Estado ja duplicado (exatamente o estrago que o MERGEDUP1 produzia): dois
    // eventos com a mesma data, empresa e fonte, portanto a mesma chave dedup.
    await semear(SEMANA, [
      eventoBase({ titulo: "Copia um", _pendente_verificacao: true }),
      eventoBase({ titulo: "Copia dois", _pendente_verificacao: true }),
    ]);

    const r = await confirmar([
      item(SEMANA, ID_A, eventoBase({}), {
        veredicto: "APROVADO",
        confianca: 0.95,
        motivo: "aprovado, mas o estado esta ambiguo",
        fontes_validas: [FONTE_A],
      }),
    ]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 0, mesclas_recusadas: 1, erros: 0 });

    // Recusa nao "resolve" a ambiguidade escolhendo um: deixa os 2 como estavam.
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(2);
    expect(evs.map((e) => e.titulo).sort()).toEqual(["Copia dois", "Copia um"]);
  });
});
