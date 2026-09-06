import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  _validarIndiceQuarentena,
  _eventoQuarentenado,
  obterQuarantineIdEvento,
  filtrarQuarentenaDoEstado,
  _verifCalcularProximaTentativa,
  registrarTentativaNaoConclusiva,
  _rotearParaConfigDO,
  _definirFalhaInjetadaTeste,
  _limparFalhasInjetadasTeste,
} from "../src/worker.js";
import { bootstrapIndiceQuarentena, resetIndiceQuarentena, adicionarAoIndice, lerIndice } from "./_quarentena-idx.mjs";

// =============================================================================
// REPROVADO-FAILCLOSED1 (2026-09-06): indice unico de quarentena de verificacao.
//
// T1 entrada n=3 (quarentena + ocultacao em todos os consumidores publicos)
// T2 reabertura administrativa (publication gate, remocao do indice por ultimo)
// T3 resolucao manual confirmar|descartar (auth/allowlist estritas)
// T4 MERGEDUP1 x quarentena (Q != D != K, 1 evento, sem orfao)
// T5 falha parcial de A (indice falha => n=2 +48h, nada de n=3, evento intacto)
// T6 indice (discriminacao fail-closed, ops do ConfigDO, concorrencia, bootstrap)
// T7 frescor (quarentenado nao certifica; so quarentenado => null/false)
// T8 shares retroativos + no-store + 503
// T10 caminho feliz com indice vazio valido
//
// Garantia: ordered fail-closed local/best-effort. Sem consistencia cross-PoP.
// =============================================================================

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao"; // vars do wrangler.test.jsonc
const ADMIN_PASSWORD = "test-admin-password-nao-usar-em-producao";
const EMPRESA = "Petrobras";
const SETOR = "Energia Eletrica";

const FONTE_A = "https://rad.cvm.gov.br/fato-160616";
const FONTE_B = "https://rad.cvm.gov.br/fato-160617";
const HOST_A = "rad.cvm.gov.br/fato-160616";
const HOST_B = "rad.cvm.gov.br/fato-160617";

const DATA_1 = "2026-09-03";
const DATA_2 = "2026-09-04";
const DATA_3 = "2026-09-05";

function fazerId(data, host) {
  return `${data}|${EMPRESA.toLowerCase()}|${host}`;
}
const ID_A = fazerId(DATA_1, HOST_A);
const ID_B = fazerId(DATA_2, HOST_B);

function eventoBase(extra) {
  return Object.assign(
    {
      empresa: EMPRESA,
      classificacao: "CRITICO",
      titulo: "Fato de credito relevante",
      evento: "Petrobras divulgou fato de credito.",
      impacto_credito: "Relevante para credito.",
      fonte_primaria: FONTE_A,
      fonte_tipo: "CVM",
      data_evento: DATA_1,
      tags: ["resultados"],
    },
    extra || {}
  );
}

const VEREDITO_REPROVADO = {
  veredicto: "REPROVADO",
  confianca: 0.2,
  motivo: "evidencia nao encontrada",
  fontes_validas: [],
};

function semanaISOAtual() {
  // Mesmo algoritmo do worker (semanaISO, quinta-feira = troca de semana ISO).
  const d = new Date();
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}
const SEMANA_ATUAL = semanaISOAtual();

async function mintJWT(secret, email) {
  const b64url = (buf) => Buffer.from(buf).toString("base64url");
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const agora = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ sub: "test", email: email || "test@example.com", iat: agora, exp: agora + 3600 }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(sig)}`;
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

function item(semana, id, evento, veredicto) {
  return { id, empresa: EMPRESA, semana, data_fila: "2026-09-05", setor: SETOR, evento, veredicto };
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

async function vencerJanela(id) {
  const chave = `radar:verif:attempt:${id}`;
  const reg = await env.RADAR_KV.get(chave, "json");
  if (!reg) throw new Error("registro de tentativa ausente");
  reg.proxima_em = "2020-01-01T00:00:00.000Z";
  await env.RADAR_KV.put(chave, JSON.stringify(reg), { expirationTtl: 60 * 60 * 24 * 90 });
}

async function quarentenarViaHTTP(id, dataEvento, semana) {
  const evento = eventoBase({ data_evento: dataEvento });
  for (let t = 1; t <= 3; t++) {
    if (t > 1) await vencerJanela(id);
    const r = await confirmar([item(semana, id, evento, VEREDITO_REPROVADO)]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, rejeitados: 1, retratados: 0 });
  }
}

async function estadoPublico(token) {
  const r = await SELF.fetch("https://example.com/?op=state", { headers: { Authorization: `Bearer ${token}` } });
  expect(r.status).toBe(200);
  return r.json();
}

beforeEach(async () => {
  // O KV e compartilhado entre test() do mesmo arquivo (probe 2026-09-06): limpa
  // tudo que este arquivo cria, mais a copia autoritativa do ConfigDO singleton.
  const _limpar = async (prefixo) => {
    const l = await env.RADAR_KV.list({ prefix: prefixo });
    for (const k of l.keys) { try { await env.RADAR_KV.delete(k.name); } catch (_) { } }
  };
  await _limpar("radar:verif:attempt:");
  await _limpar("radar:verif_fila:");
  await _limpar("radar:verif:");
  await _limpar("share:");
  await _limpar("share_user:");
  for (const w of ["2026-W60", "2026-W61", "2026-W61B", "2026-W62", "2026-W63", "2026-W64", "2026-W65", SEMANA_ATUAL]) {
    try { await env.RADAR_KV.delete(`radar:estado:${w}`); } catch (_) { }
  }
  await resetIndiceQuarentena(env);
  await bootstrapIndiceQuarentena(env);
  _limparFalhasInjetadasTeste(); // mapa de fault injection (T5/T9) e por arquivo
});

describe("T6 — indice: discriminacao fail-closed e ops do ConfigDO", () => {
  it("validacao: ausente/null/json/schema/ids-array/entrada-invalida reprovam; vazio valido so {schema:1,ids:{}}", () => {
    expect(_validarIndiceQuarentena(null).ok).toBe(false);
    expect(_validarIndiceQuarentena(undefined).ok).toBe(false);
    expect(_validarIndiceQuarentena("x").ok).toBe(false);
    expect(_validarIndiceQuarentena([]).ok).toBe(false);
    expect(_validarIndiceQuarentena({ schema: 2, ids: {} }).ok).toBe(false);
    expect(_validarIndiceQuarentena({ schema: 1 }).ok).toBe(false);
    expect(_validarIndiceQuarentena({ schema: 1, ids: null }).ok).toBe(false);
    expect(_validarIndiceQuarentena({ schema: 1, ids: [] }).ok).toBe(false);
    expect(_validarIndiceQuarentena({ schema: 1, ids: { q: [] } }).ok).toBe(false);
    const vazio = _validarIndiceQuarentena({ schema: 1, ids: {} });
    expect(vazio.ok).toBe(true);
    expect(Object.keys(vazio.indice.ids)).toHaveLength(0);
  });

  it("adicionar antes do bootstrap falha (ausencia = erro, nunca indice vazio)", async () => {
    await env.RADAR_KV.delete("radar:verif:quarentena_idx");
    await expect(_rotearParaConfigDO(env, "quarentenaAdicionar", [[{ id: "Q9" }]])).rejects.toThrow();
  });

  it("bootstrap cria vazio valido; duas adicoes concorrentes terminam com ambos; remover 1 preserva o resto", async () => {
    await resetIndiceQuarentena(env); // KV ausente: bootstrap tem que criar
    const boot = await _rotearParaConfigDO(env, "bootstrapQuarentena", []);
    expect(boot.criado).toBe(true);
    const idx1 = await lerIndice(env);
    expect(idx1.schema).toBe(1);
    expect(Object.keys(idx1.ids)).toHaveLength(0);

    await Promise.all([
      _rotearParaConfigDO(env, "quarentenaAdicionar", [[{ id: "QA", empresa: EMPRESA }]]),
      _rotearParaConfigDO(env, "quarentenaAdicionar", [[{ id: "QB", empresa: EMPRESA }]]),
    ]);
    const idx2 = await lerIndice(env);
    expect(Object.keys(idx2.ids).sort()).toEqual(["QA", "QB"]);

    const rem = await _rotearParaConfigDO(env, "quarentenaRemover", ["QA"]);
    expect(rem.removido).toBe(true);
    const idx3 = await lerIndice(env);
    expect(Object.keys(idx3.ids)).toEqual(["QB"]);

    // idempotencia: adicionar existente = no-op; remover ausente = no-op
    const addDeNovo = await _rotearParaConfigDO(env, "quarentenaAdicionar", [[{ id: "QB" }]]);
    expect(addDeNovo.adicionados).toBe(0);
    const remDeNovo = await _rotearParaConfigDO(env, "quarentenaRemover", ["QB"]);
    expect(remDeNovo.removido).toBe(true);
    const idx4 = await lerIndice(env);
    expect(Object.keys(idx4.ids)).toHaveLength(0);
  });
});

describe("T1/T5 — predicado, identidade e entrada n=3", () => {
  it("predicado: uniao flag OU indice; fallback legado usa empresa do contexto", () => {
    const ids = new Set(["Q1"]);
    expect(() => _eventoQuarentenado({}, null)).toThrow();
    expect(_eventoQuarentenado({}, ids)).toBe(false);
    expect(_eventoQuarentenado({ _verif_aguarda_manual: true }, ids)).toBe(true);
    expect(_eventoQuarentenado({ _verif_quarentena_id: "Q1" }, ids)).toBe(true);
    expect(_eventoQuarentenado({ _verif_quarentena_id: "Q2" }, ids)).toBe(false);
    // Fallback legado: sem ancora, id computado com a empresa do CONTEXTO (share antigo
    // sem empresa no evento casaria errado se usasse o evento cru).
    const evLegado = { data_evento: DATA_1, fonte_primaria: FONTE_A };
    expect(obterQuarantineIdEvento(evLegado, EMPRESA)).toBe(ID_A);
    expect(_eventoQuarentenado(evLegado, new Set([ID_A]), EMPRESA)).toBe(true);
    // Ancora vence a chave dedup: identidade canonica e a armazenada.
    const evAncora = Object.assign({}, evLegado, { _verif_quarentena_id: "QZ" });
    expect(obterQuarantineIdEvento(evAncora, EMPRESA)).toBe("QZ");
    expect(_eventoQuarentenado(evAncora, new Set(["QZ"]), EMPRESA)).toBe(true);
    // filtro muta localmente e reconta sem_eventos
    const estado = { results: { [EMPRESA]: { eventos: [evLegado, { data_evento: DATA_2, fonte_primaria: FONTE_A }] } } };
    const ocultos = filtrarQuarentenaDoEstado(estado, new Set([ID_A]));
    expect(ocultos).toBe(1);
    expect(estado.results[EMPRESA].eventos).toHaveLength(1);
  });

  it("calculo puro da proxima tentativa: n=1/24h, n=2/48h, n=3 esgotado; nunca n=4", () => {
    const agora = Date.now();
    const r1 = _verifCalcularProximaTentativa({}, agora, EMPRESA, ID_A, "2026-W36");
    expect(r1.n).toBe(1);
    expect(new Date(r1.proxima_em).getTime() - agora).toBeGreaterThan(23 * 36e5);
    const r2 = _verifCalcularProximaTentativa({ n: 1 }, agora, EMPRESA, ID_A, "2026-W36");
    expect(r2.n).toBe(2);
    expect(new Date(r2.proxima_em).getTime() - agora).toBeGreaterThan(47 * 36e5);
    const r3 = _verifCalcularProximaTentativa({ n: 2 }, agora, EMPRESA, ID_A, "2026-W36");
    expect(r3.n).toBe(3);
    expect(r3.esgotado).toBe(true);
    expect(r3.aguarda_manual).toBe(true);
    expect(r3.proxima_em).toBeNull();
    expect(r3.semana).toBe("2026-W36");
    const r4 = _verifCalcularProximaTentativa({ n: 3 }, agora, EMPRESA, ID_A, "2026-W36");
    expect(r4.n).toBe(4); // calculo puro; quem decide nao persistir n=4 e o fluxo n>=3
  });

  it("T1: 3a nao-conclusiva quarentena, grava ancora, esgota, e SOME de todos os consumidores publicos", async () => {
    const SEMANA = "2026-W60";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);

    // attempt terminal + flags + ancora no evento + id no indice
    const rec = await lerRegistro(ID_A);
    expect(rec.n).toBe(3);
    expect(rec.esgotado).toBe(true);
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);
    const idx = await lerIndice(env);
    expect(idx.ids[ID_A]).toBeTruthy();
    expect(idx.ids[ID_A].empresa).toBe(EMPRESA);

    // 4a confirmacao: recusada sem recontar nem mexer no evento (attempt primeiro)
    const r4 = await confirmar([item(SEMANA, ID_A, evento, VEREDITO_REPROVADO)]);
    const b4 = await r4.json();
    expect(b4.resultado).toMatchObject({ processados: 1, esgotados: 1, rejeitados: 0 });

    // Portao B: id quarentenado nao e entregue ao motor mesmo fisicamente na fila
    const hoje = new Date().toISOString().slice(0, 10);
    await env.RADAR_KV.put(
      `radar:verif_fila:${hoje}`,
      JSON.stringify([
        { id: ID_A, empresa: EMPRESA, semana: SEMANA, setor: SETOR, evento, criado_em: "2026-09-05T00:00:00.000Z" },
        { id: ID_B, empresa: EMPRESA, semana: SEMANA, setor: SETOR, evento: eventoBase({ data_evento: DATA_2, fonte_primaria: FONTE_B }), criado_em: "2026-09-05T00:00:00.000Z" },
      ]),
      { expirationTtl: 60 * 60 * 24 * 7 }
    );
    const rl = await post({ action: "listar_fila_verificacao", dias: 3 });
    const bl = await rl.json();
    expect(bl.total).toBe(1);
    expect(bl.itens.map((i) => i.id)).toEqual([ID_B]);

    // Consumidores publicos: o evento some do estado corrente (flag + indice).
    await semear(SEMANA_ATUAL, [eventoBase({ _pendente_verificacao: true, _verif_aguarda_manual: true, _verif_quarentena_id: ID_A })]);
    const token = await mintJWT(env.JWT_SECRET);
    const st = await estadoPublico(token);
    expect(st.ok).toBe(true);
    expect(st.results[EMPRESA].eventos).toHaveLength(0);
  });

  it("T5-A: indice falhou na entrada (A) => n=2 renovado +48h, sem esgotado, evento intacto, sem id no indice", async () => {
    const SEMANA = "2026-W61";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    // n=2 persistido, janela vencida
    await env.RADAR_KV.put(
      `radar:verif:attempt:${ID_A}`,
      JSON.stringify({ id: ID_A, n: 2, ultima_em: "2026-09-05T00:00:00.000Z", proxima_em: "2020-01-01T00:00:00.000Z" }),
      { expirationTtl: 60 * 60 * 24 * 90 }
    );

    // Fault injection em A (mapa SOMENTE ativo com ENVIRONMENT=test + var de teste):
    // o indice falha na entrada => NUNCA tocar no evento, nao persistir esgotado,
    // manter n=2 +48h.
    _definirFalhaInjetadaTeste("n3_indice");
    const res = await registrarTentativaNaoConclusiva(env, ID_A, EMPRESA, SEMANA);
    expect(res.quarentena).toBe(false);
    expect(res.indice_erro).toBeTruthy();
    expect(res.reg.n).toBe(2);
    expect(res.reg.esgotado).toBeUndefined();
    expect(new Date(res.reg.proxima_em).getTime() - Date.now()).toBeGreaterThan(47 * 36e5);

    const rec = await lerRegistro(ID_A);
    expect(rec.n).toBe(2);
    expect(rec.esgotado).toBeUndefined();
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._verif_quarentena_id).toBeUndefined();
    expect(evs[0]._verif_aguarda_manual).toBeUndefined();
    // A nao passou: indice nunca recebeu o id (ausente do KV, nunca vazio implicito)
    const idxRaw = await env.RADAR_KV.get("radar:verif:quarentena_idx", "json");
    expect(idxRaw.ids[ID_A]).toBeUndefined();
  });

  it("T5-B: persistencia do EVENTO falhou => indice segura a ocultacao sozinho (sem flag), attempt n=3 gravado", async () => {
    const SEMANA = "2026-W61C";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await env.RADAR_KV.put(
      `radar:verif:attempt:${ID_A}`,
      JSON.stringify({ id: ID_A, n: 2, ultima_em: "2026-09-05T00:00:00.000Z", proxima_em: "2020-01-01T00:00:00.000Z" }),
      { expirationTtl: 60 * 60 * 24 * 90 }
    );
    _definirFalhaInjetadaTeste("n3_evento");
    const res = await registrarTentativaNaoConclusiva(env, ID_A, EMPRESA, SEMANA);
    expect(res.quarentena).toBe(true);
    expect(res.erro).toBe("quarentena_parcial");
    expect(res.evento_erro).toBe("falha_injetada_evento");
    // B falhou: evento SEM flag, mas o indice contem o id (autoridade unica).
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._verif_quarentena_id).toBeUndefined();
    expect(evs[0]._verif_aguarda_manual).toBeUndefined();
    const idx = await lerIndice(env);
    expect(idx.ids[ID_A]).toBeTruthy();
    // C seguiu: attempt terminal n=3.
    const rec = await lerRegistro(ID_A);
    expect(rec.n).toBe(3);
    expect(rec.esgotado).toBe(true);
    // O predicado por uniao esconde pelo INDICE mesmo sem a flag (a correcao de
    // visibilidade/frescor nao pode depender da flag ter sido gravada).
    expect(_eventoQuarentenado(evs[0], new Set([ID_A]), EMPRESA)).toBe(true);
  });

  it("T5-C: persistencia do ATTEMPT falhou => attempt fica n=2, evento marcado, indice segura; retry recalcula n=3 e nunca n=4", async () => {
    const SEMANA = "2026-W61D";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await env.RADAR_KV.put(
      `radar:verif:attempt:${ID_A}`,
      JSON.stringify({ id: ID_A, n: 2, ultima_em: "2026-09-05T00:00:00.000Z", proxima_em: "2020-01-01T00:00:00.000Z" }),
      { expirationTtl: 60 * 60 * 24 * 90 }
    );
    _definirFalhaInjetadaTeste("n3_attempt");
    const res = await registrarTentativaNaoConclusiva(env, ID_A, EMPRESA, SEMANA);
    expect(res.quarentena).toBe(true);
    expect(res.erro).toBe("quarentena_parcial");
    expect(res.tentativa_erro).toBe("falha_injetada_attempt");
    // C falhou: attempt NAO gravado (n=2 preservado); A e B ok (indice + flag).
    const rec = await lerRegistro(ID_A);
    expect(rec.n).toBe(2);
    expect(rec.esgotado).toBeUndefined();
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);
    const idx = await lerIndice(env);
    expect(idx.ids[ID_A]).toBeTruthy();

    // Retry (sem injecao): parte do n persistido=2, recalcula n=3, A idempotente,
    // B ja_estava, C grava n=3. NUNCA n=4.
    _limparFalhasInjetadasTeste();
    const res2 = await registrarTentativaNaoConclusiva(env, ID_A, EMPRESA, SEMANA);
    expect(res2.quarentena).toBe(true);
    expect(res2.ja_estava).toBeUndefined();
    const rec2 = await lerRegistro(ID_A);
    expect(rec2.n).toBe(3);
    expect(rec2.esgotado).toBe(true);
    const idx2 = await lerIndice(env);
    expect(Object.keys(idx2.ids)).toEqual([ID_A]);
  });

  it("T5-C: indice ilegivel no portao C => 503, nenhum veredicto aplicado, estado e tentativa intactos", async () => {
    const SEMANA = "2026-W61B";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await env.RADAR_KV.put(
      `radar:verif:attempt:${ID_A}`,
      JSON.stringify({ id: ID_A, n: 2, ultima_em: "2026-09-05T00:00:00.000Z", proxima_em: "2020-01-01T00:00:00.000Z" }),
      { expirationTtl: 60 * 60 * 24 * 90 }
    );
    await env.RADAR_KV.delete("radar:verif:quarentena_idx");

    const r = await confirmar([item(SEMANA, ID_A, evento, VEREDITO_REPROVADO)]);
    expect(r.status).toBe(503);
    const b = await r.json();
    expect(b.ok).toBe(false);
    expect(b.quarentena_indice_indisponivel).toBe(true);
    expect(b.codigo).toBe("QUARENTENA_INDICE_ERRO");
    const rec = await lerRegistro(ID_A);
    expect(rec.n).toBe(2);
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._verif_quarentena_id).toBeUndefined();
    expect(await env.RADAR_KV.get("radar:verif:quarentena_idx", "json")).toBeNull();
  });
});

describe("T2 — reabertura administrativa com publication gate", () => {
  it("reabre: reenfileira, limpa attempt, evento pendente sem marca de espera, indice removido POR ULTIMO; duplo clique idempotente", async () => {
    const SEMANA = "2026-W62";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);

    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.ok).toBe(true);
    expect(b.quarentena).toBe(true);
    expect(b.reaberto).toBe(true);

    // attempt limpo; evento reaberto (aguarda_manual false, pendente true, ancora historica);
    const rec = await lerRegistro(ID_A);
    expect(rec).toBeNull();
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A); // ancora permanece como historico
    // indice sem o id; fila contem o item reenfileirado
    const idx = await lerIndice(env);
    expect(idx.ids[ID_A]).toBeUndefined();
    const hoje = new Date().toISOString().slice(0, 10);
    const fila = await env.RADAR_KV.get(`radar:verif_fila:${hoje}`, "json");
    expect(fila.some((it) => it.id === ID_A)).toBe(true);

    // Duplo clique: id ja nao esta em quarentena => semantica (A), ok idempotente
    const r2 = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    const b2 = await r2.json();
    expect(b2.ok).toBe(true);
    expect(b2.quarentena).toBe(false);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
  });

  it("auth invalida nao mexe em nada", async () => {
    const SEMANA = "2026-W63";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);
    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: "senha-errada", id: ID_A });
    expect(r.status).toBe(403);
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect((await lerRegistro(ID_A)).n).toBe(3);
  });
});

describe("T3 — resolucao manual confirmar|descartar", () => {
  async function prepararQuarentena() {
    const SEMANA = "2026-W64";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);
    return SEMANA;
  }

  it("decisao invalida => 400, nada muda; auth invalida => 403", async () => {
    await prepararQuarentena();
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "sei-la" });
    expect(r.status).toBe(400);
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    const r2 = await post({ action: "admin_verif_resolver", admin_senha: "senha-errada", id: ID_A, decisao: "confirmar" });
    expect(r2.status).toBe(403);
  });

  it("confirmar: attempt limpo, estado certificado, SOMENTE depois indice removido", async () => {
    const SEMANA = await prepararQuarentena();
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "confirmar", motivo: "fonte revalidada" });
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.ok).toBe(true);
    expect(b.resolvido).toBe(true);
    expect(b.indice_removido).toBe(true);
    expect(await lerRegistro(ID_A)).toBeNull();
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._pendente_verificacao).toBe(false);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._verif_manual.decisao).toBe("confirmar");
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
  });

  it("descartar: remove o evento do estado e depois o indice", async () => {
    const SEMANA = await prepararQuarentena();
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "descartar" });
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.ok).toBe(true);
    expect(await lerRegistro(ID_A)).toBeNull();
    expect(await lerEventos(SEMANA)).toHaveLength(0);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
  });
});

describe("T4 — MERGEDUP1 x quarentena: saida usa Q, nunca chaveOriginal assumido", () => {
  it("D != Q: veredicto com chaveOriginal nova tira a quarentena preservando 1 evento, sem orfao", async () => {
    const SEMANA = "2026-W65";
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA); // Q = ID_A (fonte A)

    // Simula correcao externa de fonte (SOURCEFIX-PAMPASUL1 style): o evento no estado
    // passa a ter fonte B (chave dedup K = ID_B), mantendo a ancora Q.
    const rawEstado = await env.RADAR_KV.get(`radar:estado:${SEMANA}`, "json");
    rawEstado.results[EMPRESA].eventos[0].fonte_primaria = FONTE_B;
    await env.RADAR_KV.put(`radar:estado:${SEMANA}`, JSON.stringify(rawEstado), { expirationTtl: 60 * 60 * 24 * 35 });

    // O motor confirma um item cujo id (chaveOriginal D) e K != Q, com veredicto APROVADO.
    const eventoK = eventoBase({ data_evento: DATA_1, fonte_primaria: FONTE_B });
    const r = await confirmar([item(SEMANA, ID_B, eventoK, { veredicto: "APROVADO", confianca: 0.9, motivo: "fonte confirmada", fontes_validas: [FONTE_B] })]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado).toMatchObject({ processados: 1, aprovados: 1, esgotados: 0, bloqueados_quarentena: 0 });

    // 1 evento apenas, publico, aprovado, sem marca de espera, ancora preservada como historico.
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0].fonte_primaria).toBe(FONTE_B);
    expect(evs[0]._pendente_verificacao).toBe(false);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);
    // Q ausente do indice (publication gate); sem entrada orfa.
    const idx = await lerIndice(env);
    expect(idx.ids[ID_A]).toBeUndefined();
    expect(idx.ids[ID_B]).toBeUndefined();
    expect(await lerRegistro(ID_A)).toBeNull();
  });
});

describe("T7 — frescor: quarentenado nao certifica", () => {
  it("mais novo quarentenado => feed usa o anterior; so quarentenado => null + feed_fresco false", async () => {
    const evAntigo = eventoBase({ data_evento: DATA_1, _pendente_verificacao: true });
    const evNovo = eventoBase({ data_evento: DATA_2, fonte_primaria: FONTE_B, _pendente_verificacao: true });
    await semear(SEMANA_ATUAL, [evAntigo, evNovo]);

    const health = () => SELF.fetch("https://example.com/").then((r) => r.json());

    let h = await health();
    expect(h.feed_evento_mais_novo).toBe(DATA_2);

    // quarentena so o mais novo
    await adicionarAoIndice(env, ID_B, { empresa: EMPRESA, semana: SEMANA_ATUAL });
    h = await health();
    expect(h.feed_evento_mais_novo).toBe(DATA_1);

    // quarentena o resto: feed sem nada certificavel
    await adicionarAoIndice(env, ID_A, { empresa: EMPRESA, semana: SEMANA_ATUAL });
    h = await health();
    expect(h.feed_evento_mais_novo).toBeNull();
    expect(h.feed_fresco).toBe(false);

    // indice ilegivel => nunca feed_fresco true
    await env.RADAR_KV.delete("radar:verif:quarentena_idx");
    h = await health();
    expect(h.feed_fresco).toBe(false);
  });
});

describe("T8 — shares retroativos + no-store", () => {
  it("share criado publico esconde o fato depois da quarentena; erro de indice = 503; criacao em erro = 503", async () => {
    await semear(SEMANA_ATUAL, [eventoBase({ _pendente_verificacao: true })]);
    const token = await mintJWT(env.JWT_SECRET);

    const rc = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ action: "share_criar", empresa: EMPRESA, ttl: "24h" }),
    });
    expect(rc.status).toBe(200);
    const bc = await rc.json();
    expect(bc.ok).toBe(true);
    const slug = bc.slug;

    // abre ANTES da quarentena: fato aparece, header no-store
    let rl = await SELF.fetch(`https://example.com/s/${slug}`);
    expect(rl.status).toBe(200);
    expect(rl.headers.get("Cache-Control")).toBe("no-store");
    let html = await rl.text();
    expect(html).toContain("Fato de credito relevante");

    // quarentena o evento DEPOIS do share criado
    await adicionarAoIndice(env, ID_A, { empresa: EMPRESA, semana: SEMANA_ATUAL });

    // MESMO slug: fato NAO aparece (filtro em toda abertura, registro nao alterado)
    rl = await SELF.fetch(`https://example.com/s/${slug}`);
    expect(rl.status).toBe(200);
    expect(rl.headers.get("Cache-Control")).toBe("no-store");
    html = await rl.text();
    expect(html).not.toContain("Fato de credito relevante");

    // indice ilegivel: 503, nunca renderizar cru
    await env.RADAR_KV.delete("radar:verif:quarentena_idx");
    rl = await SELF.fetch(`https://example.com/s/${slug}`);
    expect(rl.status).toBe(503);
    expect(rl.headers.get("Cache-Control")).toBe("no-store");

    // criacao de share em erro de indice: nao cria
    const rc2 = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ action: "share_criar", empresa: EMPRESA, ttl: "24h" }),
    });
    expect(rc2.status).toBe(503);
    const bc2 = await rc2.json();
    expect(bc2.ok).toBe(false);
    expect(bc2.quarentena_indice_indisponivel).toBe(true);
  });
});

describe("T9 — fault injection das SAIDAS: indice permanece ate a publicacao estar pronta", () => {
  async function prepararQuarentenaT9(semana) {
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(semana, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, semana);
  }

  it("reabertura: falha ENQUEUE => 500, indice/attempt/evento intactos", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("reabrir_enqueue");
    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_REENFILEIRA_FALHOU");
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect((await lerRegistro(ID_A)).n).toBe(3);
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
  });

  it("reabertura: falha DELETE ATTEMPT => 500, indice permanece (publicacao fechada)", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("attempt_delete");
    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_ATTEMPT_FALHOU");
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect((await lerRegistro(ID_A)).n).toBe(3);
    // Evento segue oculto: flag + indice intactos.
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
  });

  it("reabertura: falha PERSIST ESTADO => 500, indice permanece, evento segue marcado", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("reabrir_persist");
    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_REABERTURA_FALHOU");
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
  });

  it("reabertura: falha REMOVER INDICE (gate) => 500 APOS tudo pronto; evento reaberto continua oculto pelo indice (fail-closed)", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("gate_remover");
    const r = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_GATE_FALHOU");
    // Passos 1-5 ja rodaram: fila tem o item, attempt limpo, evento reaberto...
    expect(await lerRegistro(ID_A)).toBeNull();
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);
    // ...mas o indice PERMANECE: o evento continua oculto (publicacao nao pronta).
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect(_eventoQuarentenado(evs[0], new Set([ID_A]), EMPRESA)).toBe(true);
    // Retry converge sem duplicar: limpa injecao e reabre de novo (idempotente).
    _limparFalhasInjetadasTeste();
    const r2 = await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    expect(r2.status).toBe(200);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
  });

  it("resolver CONFIRMAR: falha PERSIST DECISAO => 500, indice permanece, evento segue em espera", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("resolver_persist");
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "confirmar" });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_RESOLUCAO_FALHOU");
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(true);
    expect(evs[0]._verif_manual).toBeUndefined();
  });

  it("resolver CONFIRMAR: falha REMOVER INDICE (gate) => 500 APOS estado certificado; evento continua oculto pelo indice", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("gate_remover");
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "confirmar" });
    expect(r.status).toBe(500);
    const b = await r.json();
    expect(b.codigo).toBe("QUARENTENA_GATE_FALHOU");
    // Estado certificado + attempt limpo, MAS indice segura a publicacao.
    expect(await lerRegistro(ID_A)).toBeNull();
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._pendente_verificacao).toBe(false);
    expect(evs[0]._verif_manual.decisao).toBe("confirmar");
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect(_eventoQuarentenado(evs[0], new Set([ID_A]), EMPRESA)).toBe(true);
  });

  it("resolver DESCARTAR: falha PERSIST => 500, evento continua no estado e indice permanece", async () => {
    const SEMANA = SEMANA_ATUAL;
    await prepararQuarentenaT9(SEMANA);
    _definirFalhaInjetadaTeste("resolver_persist");
    const r = await post({ action: "admin_verif_resolver", admin_senha: ADMIN_PASSWORD, id: ID_A, decisao: "descartar" });
    expect(r.status).toBe(500);
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect(await lerEventos(SEMANA)).toHaveLength(1);
  });

  it("MERGEDUP1: falha ANTES de remover indice (persist) => merge nao aplicado, evento e indice intactos", async () => {
    const SEMANA = SEMANA_ATUAL;
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);
    // Reabre para liberar o veredicto (attempt esgotado bloqueia o portao C).
    await post({ action: "admin_verif_tentativa_limpar", admin_senha: ADMIN_PASSWORD, id: ID_A });
    _definirFalhaInjetadaTeste("mesclar_persist");
    const r = await confirmar([item(SEMANA, ID_A, eventoBase({}), { veredicto: "APROVADO", confianca: 0.9, motivo: "ok", fontes_validas: [FONTE_A] })]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado.erros).toBe(1);
    expect(b.resultado.aprovados).toBe(0);
    // Nada aplicado: evento ainda marcado, indice intacto.
    const evs = await lerEventos(SEMANA);
    expect(evs[0]._verif_aguarda_manual).toBe(false); // reaberto antes da injecao
    expect(evs[0]._pendente_verificacao).toBe(true);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined(); // removido na reabertura
  });

  it("MERGEDUP1: falha AO remover indice (gate) => merge aplicado com sinalizacao de falha; indice real permanece; retry converge", async () => {
    const SEMANA = SEMANA_ATUAL;
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);
    // NAO usa admin_verif_tentativa_limpar aqui: reabertura administrativa REMOVE
    // o id do indice real como seu passo final, o que apagaria exatamente o
    // cenario que este teste precisa (Q ainda genuinamente no indice quando o
    // merge tenta sair da quarentena). Em vez disso apaga so o registro de
    // attempt (bypassa o portao A/attempt-esgotado, que e ortogonal a este
    // teste) e deixa o indice real (copia do ConfigDO + KV) intocado.
    await env.RADAR_KV.delete(`radar:verif:attempt:${ID_A}`);

    // Falha AO REMOVER: em producao este cenario existe quando a remocao no
    // ConfigDO falha de forma transitoria (KV put, timeout, etc.) — o merge ja
    // aplicou o conteudo (evento correto no estado) mas o id nao saiu do indice
    // real. O chamador recebe quarentena_erro e o evento continua oculto.
    _definirFalhaInjetadaTeste("gate_remover");
    const r = await confirmar([item(SEMANA, ID_A, eventoBase({}), { veredicto: "APROVADO", confianca: 0.9, motivo: "ok", fontes_validas: [FONTE_A] })]);
    expect(r.status).toBe(200);
    const b = await r.json();
    expect(b.resultado.aprovados).toBe(1);
    expect(b.resultado.mesclas_quarentena_erro).toBe(1);
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._pendente_verificacao).toBe(false);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);

    // Indice REAL (nao simulado) ainda contem Q: a remocao falhou de verdade,
    // entao o evento segue oculto pelo predicado em qualquer consumidor.
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    expect(_eventoQuarentenado(evs[0], new Set([ID_A]), EMPRESA)).toBe(true);

    // Retry converge sem duplicar evento: limpa injecao e reenvia (roundtrip
    // idempotente do MERGEDUP1) => remocao do indice completa, 1 evento so.
    // A quarta-tentativa/bloqueio por indice (portao C) nao intercepta este
    // reenvio porque o veredicto e APROVADO: e o unico caminho que sabe liberar
    // a propria ancora, com gate idempotente proprio (ver worker.js, comentario
    // "APROVADO e excecao deliberada" no handler de confirmar_verificacao).
    _limparFalhasInjetadasTeste();
    const r2 = await confirmar([item(SEMANA, ID_A, eventoBase({}), { veredicto: "APROVADO", confianca: 0.9, motivo: "ok", fontes_validas: [FONTE_A] })]);
    expect(r2.status).toBe(200);
    const b2 = await r2.json();
    expect(b2.resultado.aprovados).toBe(1);
    expect(b2.resultado.mesclas_quarentena_erro).toBe(0);
    expect(await lerEventos(SEMANA)).toHaveLength(1);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
  });

  it("MERGEDUP1: falha ao apagar attempt DENTRO do merge => propaga erro, indice NAO removido (nunca chega a tentar), evento segue oculto; retry com delete ok converge sem duplicar nem orfao", async () => {
    const SEMANA = SEMANA_ATUAL;
    const evento = eventoBase({ _pendente_verificacao: true });
    await semear(SEMANA, [evento]);
    await quarentenarViaHTTP(ID_A, DATA_1, SEMANA);
    // Mesmo desenho do teste anterior: bypassa so o portao A/attempt-esgotado
    // (apaga o registro ANTES, ortogonal a este teste) e deixa o indice real
    // (ConfigDO + KV) intocado, com ID_A genuinamente quarentenado.
    await env.RADAR_KV.delete(`radar:verif:attempt:${ID_A}`);

    // Falha especificamente no delete do attempt DENTRO do merge (nao no gate de
    // remocao do indice, que e o teste acima): o conteudo do evento ja foi
    // persistido (marca de espera limpa) mas o delete do attempt nao foi
    // confirmado, entao a funcao tem que propagar erro e NUNCA chegar a tentar
    // remover o indice — publicacao continua fechada pelo mesmo motivo que a
    // exigiria mesmo se a remocao do indice fosse tentada e desse certo.
    _definirFalhaInjetadaTeste("mesclar_attempt_delete");
    const r = await confirmar([item(SEMANA, ID_A, eventoBase({}), { veredicto: "APROVADO", confianca: 0.9, motivo: "ok", fontes_validas: [FONTE_A] })]);
    expect(r.status).toBe(200);
    const b = await r.json();
    // a) retorna erro: conta aprovado (conteudo aplicado) mas sinaliza quarentena_erro,
    // nunca um sucesso limpo — o mesmo contrato observavel do teste de gate acima.
    expect(b.resultado.aprovados).toBe(1);
    expect(b.resultado.mesclas_quarentena_erro).toBe(1);
    const evs = await lerEventos(SEMANA);
    expect(evs).toHaveLength(1);
    expect(evs[0]._verif_aguarda_manual).toBe(false);
    expect(evs[0]._pendente_verificacao).toBe(false);
    expect(evs[0]._verif_quarentena_id).toBe(ID_A);

    // b) quarantineId permanece no indice real: o delete falhou ANTES de a funcao
    // sequer tentar _mutarIndiceQuarentena("quarentenaRemover", ...).
    expect((await lerIndice(env)).ids[ID_A]).toBeTruthy();
    // c) evento continua oculto pelo indice em qualquer consumidor (predicado).
    expect(_eventoQuarentenado(evs[0], new Set([ID_A]), EMPRESA)).toBe(true);

    // d) retry com o delete funcionando converge e publica; e) sem duplicar
    // evento nem deixar orfao (attempt e indice ambos limpos ao final).
    _limparFalhasInjetadasTeste();
    const r2 = await confirmar([item(SEMANA, ID_A, eventoBase({}), { veredicto: "APROVADO", confianca: 0.9, motivo: "ok", fontes_validas: [FONTE_A] })]);
    expect(r2.status).toBe(200);
    const b2 = await r2.json();
    expect(b2.resultado.aprovados).toBe(1);
    expect(b2.resultado.mesclas_quarentena_erro).toBe(0);
    expect(await lerEventos(SEMANA)).toHaveLength(1);
    expect((await lerIndice(env)).ids[ID_A]).toBeUndefined();
    expect(await lerRegistro(ID_A)).toBeNull();
  });
});

describe("T10 — caminho feliz com indice vazio valido", () => {
  it("state/ews/briefing/share/gates funcionam normalmente com {schema:1,ids:{}}", async () => {
    await semear(SEMANA_ATUAL, [eventoBase({ _pendente_verificacao: false })]);
    const token = await mintJWT(env.JWT_SECRET);

    const st = await estadoPublico(token);
    expect(st.ok).toBe(true);
    expect(st.results[EMPRESA].eventos).toHaveLength(1);

    const rEws = await SELF.fetch(`https://example.com/?op=ews&empresa=${encodeURIComponent(EMPRESA)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(rEws.status).toBe(200);
    expect((await rEws.json()).ok).toBe(true);

    const rB = await SELF.fetch("https://example.com/?op=briefing_executivo&escopo=historico", {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(rB.status).toBe(200);
    const b = await rB.json();
    expect(b.ok).toBe(true);
    expect(b.briefing.resumo.eventos_total).toBeGreaterThanOrEqual(1);

    const rc = await SELF.fetch("https://example.com/", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ action: "share_criar", empresa: EMPRESA, ttl: "24h" }),
    });
    expect(rc.status).toBe(200);
    const bc = await rc.json();
    expect(bc.ok).toBe(true);

    const rl = await post({ action: "listar_fila_verificacao", dias: 3 });
    expect(rl.status).toBe(200);
    const bl = await rl.json();
    expect(bl.ok).toBe(true);
    expect(bl.total).toBe(0);
  });
});
