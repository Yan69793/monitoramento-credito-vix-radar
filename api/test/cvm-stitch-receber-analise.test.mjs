import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

// CVMSTITCH1 (2026-09-15). Feed de eventos congelado desde 2026-09-11 com a fonte
// CVM avancando ate 2026-09-14, e o gate `Frescor da Ingestao` reprovando com
// "FONTE ANDOU E O FEED NAO (pipeline_nao_persistiu): feed_max=2026-09-11
// teto_elegivel=2026-09-14".
//
// CAUSA RAIZ: `receber_analise` era o UNICO dos 5 caminhos que persistem payload no
// estado que nao chamava `costurarCvmEmEventos` (os outros 4: executarVarreduraBatch,
// executarVarreduraBatchComFila, executarVarreduraMatinal e consulta_empresa). Desde
// VARREDURA_CRON_AI_ENABLED=false (v4.9.143) a varredura de IA saiu do cron do Worker
// para as rotinas locais, que entregam por `receber_analise` — entao este virou o
// unico caminho de producao, e nele o documento oficial da CVM entrava em
// `cvm_documentos`, era gravado, e nunca virava evento. Documento com dono na
// carteira, dentro da janela e material e exatamente a regua que o gate de avanco usa
// como teto ELEGIVEL: o gate cobrava do pipeline um teto que o pipeline nunca tinha
// como atingir por esse caminho.
//
// MEDIDO nos estados de producao (KV radar:estado:*): `_cobertura_cvm` e `_sintetico`
// com ZERO ocorrencias em W28..W38, contra 58 e 118 em W19/W18, quando a varredura
// ainda rodava dentro do Worker. Caso concreto de 14/09: ISA Energia entrou no lote
// noturno por `cvm_delta_1` (o Aviso aos Debenturistas de 14/09), foi analisada, e o
// estado dela ficou com um unico evento datado de 2026-09-08 vindo de imprensa.
//
// Este arquivo trava as duas pontas (regra 5 do CLAUDE.md): o caso BOM (documento
// material com dono vira evento datado, na mesma janela e materialidade de sempre) e
// o caso RUIM (documento nao material, documento sem dono e documento fora da janela
// NAO viram evento, e a ausencia certificada do emissor segue intacta). Prova reversa:
// contra o codigo anterior o caso bom falha (n_eventos=0, nenhum evento do documento)
// e os casos ruins passam nos dois — que e exatamente o desenho que manteve o defeito
// invisivel por semanas.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const KEY_DOCS = "cvm:documentos";

// Razao social -> emissor, par ja exercitado em cvm-atribuicao.test.mjs (CINCO_CEGOS):
// a atribuicao nao e a variavel sob teste aqui.
const DASA_RAZAO = "DIAGNOSTICOS DA AMERICA SA";
const DASA = "Dasa";
// Razao social de fora da carteira: serve para o documento sem dono.
const TERCEIRO_RAZAO = "ISHARES US OIL & GAS EXPLORATION & PRODUCTION ETF";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}

// Mesmo relogio do Worker (obterAgoraBRT subtrai 3h fixas): usar UTC faria o teste
// passar de dia e quebrar depois das 21h BRT.
function agoraBRT() {
  return new Date(Date.now() - 3 * 60 * 60 * 1e3);
}

function chaveEstadoSemanaCorrente() {
  return `radar:estado:${semanaISO(agoraBRT())}`;
}

function hojeBRT() {
  return agoraBRT().toISOString().slice(0, 10);
}

function diasAtras(n) {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

function doc(razaoSocial, protocolo, categoria = "Fato Relevante", assunto = "assunto de teste", data = hojeBRT()) {
  return {
    e: razaoSocial,
    d: data,
    de: data,
    c: categoria,
    a: assunto,
    l: `https://www.rad.cvm.gov.br/ENET/frmExibirArquivoIPEExterno.aspx?NumeroProtocoloEntrega=${protocolo}&numProtocolo=${protocolo}`
  };
}

// Payload de rotina com ausencia certificada: cobertura LIGHT completa (3 buscas) e
// zero evento. E o mesmo formato que a noturna manda para emissor sem fato novo.
function resultadoSemEvento() {
  return {
    empresa: DASA,
    setor: "Teste",
    sem_eventos: true,
    classificacao_geral: "ECO",
    cobertura_nota: "Nenhum fato material na janela.",
    eventos: [],
    fontes_consultadas: [
      { rodada: "R1", familia: "emissor", query: "consulta 1", resultado: "sem achado", classificacao: "ok" },
      { rodada: "R2", familia: "divida", query: "consulta 2", resultado: "sem achado", classificacao: "ok" },
      { rodada: "R3", familia: "fato", query: "consulta 3", resultado: "sem achado", classificacao: "ok" }
    ],
    _tier: "LIGHT",
    _rotina_v2: true
  };
}

async function submeter(resultado) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.61" },
    body: JSON.stringify({
      action: "receber_analise",
      routine_key: ROUTINE_KEY,
      empresa: DASA,
      setor: "Teste",
      _matinal: false,
      provedor: "teste-cvm-stitch",
      resultado
    })
  });
}

async function registroDe(empresa) {
  const raw = await env.RADAR_KV.get(chaveEstadoSemanaCorrente(), "json");
  return raw ? (raw.results || {})[empresa] : null;
}

async function semanaGravada() {
  return env.RADAR_KV.get(chaveEstadoSemanaCorrente(), "json");
}

async function limpar() {
  for (const k of [chaveEstadoSemanaCorrente(), KEY_DOCS, `radar:cvm_vistos:${DASA.toLowerCase()}`]) {
    try { await env.RADAR_KV.delete(k); } catch (_) { }
  }
}

beforeEach(async () => {
  await bootstrapIndiceQuarentena(env);
  await limpar();
});
afterEach(limpar);

describe("CVMSTITCH1: documento da CVM entregue a rotina vira evento no feed", () => {
  it("PONTA BOA: Fato Relevante com dono, dentro da janela e material vira evento datado", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(DASA_RAZAO, "7000001")]));

    const res = await submeter(resultadoSemEvento());
    expect(res.status).toBe(200);
    const body = await res.json();

    // A rotina mede evento persistido, nao ACK: `n_eventos` e o que o
    // Submit-Analise conta como submit_ok (SUBMITOK-ENGANOSO1).
    expect(body.n_eventos).toBe(1);
    expect(body.sem_eventos).toBe(false);
    expect(body.max_data_evento_depois).toBe(hojeBRT());

    const reg = await registroDe(DASA);
    expect(reg).toBeTruthy();
    const eventos = reg.eventos || [];
    expect(eventos.length).toBe(1);
    expect(eventos[0].data_evento).toBe(hojeBRT());
    expect(eventos[0].fonte).toBe("CVM");
    expect(eventos[0]._sintetico).toBe(true);
    // O teste de ausencia NAO pode sobreviver a um evento real no mesmo payload.
    expect(reg.sem_eventos).toBe(false);
    // A costura tem que aparecer auditavel no registro, com a janela medida.
    expect(reg._cobertura_cvm).toBeTruthy();
    expect(reg._cobertura_cvm.docs_sintetizados).toBe(1);
    expect(reg._cobertura_cvm.total_docs_janela).toBe(1);

    // E a fronteira global do feed tem que andar de verdade: e este campo que o
    // health serve como feed_ultimo_evento_novo_em.
    const semana = await semanaGravada();
    expect(semana.feed_frontier_data).toBe(hojeBRT());
    expect(semana.feed_ultimo_evento_novo_em).toBeTruthy();
  });

  it("PONTA RUIM: documento NAO material do mesmo emissor nao vira evento", async () => {
    // Mesmo emissor, mesma data, mesmo dono. Muda so a categoria: "Calendario de
    // Eventos Corporativos" nao e categoria material e o emissor nao esta em
    // ANCORAS_SINTETICAS, entao nao ha gatilho nenhum que autorize sintetizar.
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
      doc(DASA_RAZAO, "7000002", "Calendário de Eventos Corporativos", "-")
    ]));

    const res = await submeter(resultadoSemEvento());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.n_eventos).toBe(0);
    expect(body.sem_eventos).toBe(true);

    const reg = await registroDe(DASA);
    expect(reg).toBeTruthy();
    expect(reg.eventos || []).toHaveLength(0);
    expect(reg.sem_eventos).toBe(true);
  });

  it("PONTA RUIM: Fato Relevante sem dono na carteira nao vira evento de ninguem", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([doc(TERCEIRO_RAZAO, "7000003")]));

    const res = await submeter(resultadoSemEvento());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.n_eventos).toBe(0);

    const reg = await registroDe(DASA);
    expect(reg.eventos || []).toHaveLength(0);
    // Nenhum documento chega ao emissor (sem dono na carteira), entao nao ha nem
    // evento nem cobertura auditada a registrar: a resposta diz 0 e o estado fica
    // como ausencia comprovada do emissor.
    expect(reg.sem_eventos).toBe(true);
  });

  it("PONTA RUIM: documento material do emissor mas fora da janela de 30 dias nao vira evento", async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
      doc(DASA_RAZAO, "7000004", "Fato Relevante", "assunto de teste", diasAtras(45))
    ]));

    const res = await submeter(resultadoSemEvento());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.n_eventos).toBe(0);

    const reg = await registroDe(DASA);
    expect(reg.eventos || []).toHaveLength(0);
    expect(reg.sem_eventos).toBe(true);
  });

  it("o teto ELEGIVEL do gate de frescor e a mesma regua da costura", async () => {
    // Dois documentos do mesmo emissor: um material dentro da janela e um nao
    // material. O registro tem que mostrar a janela inteira sendo AUDITADA
    // (cobertura_total = 1) e sintetizar exatamente o material. Se a costura
    // usasse outra janela ou outro criterio, o teto que o frescor-check compara
    // com o feed deixaria de descrever o que o pipeline consegue publicar.
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
      doc(DASA_RAZAO, "7000005"),
      doc(DASA_RAZAO, "7000006", "Calendário de Eventos Corporativos", "-")
    ]));

    const res = await submeter(resultadoSemEvento());
    const body = await res.json();
    expect(body.n_eventos).toBe(1);

    const reg = await registroDe(DASA);
    expect(reg._cobertura_cvm.total_docs_janela).toBe(2);
    expect(reg._cobertura_cvm.docs_sintetizados).toBe(1);
    expect(reg._cobertura_cvm.exclusoes_auditadas_count).toBe(1);
    expect(reg._cobertura_cvm.cobertura_total).toBe(1);
  });
});
