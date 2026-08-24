import { SELF, env } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";

// RELOGIO3H1 (auditoria 2026-08-24). `_last_scanned_at` e INSTANTE de varredura e e
// comparado contra Date.now() cru em _parseHorasStale. O caminho de receber_analise
// gravava esse campo com obterAgoraBRT(), que devolve `new Date(Date.now() - 3h)`. Isso
// esta certo para derivar o DIA CIVIL brasileiro, e errado para carimbar um instante:
// todo emissor nascia com 3h de atraso e o gate de frescor acusava stale antes da hora.
//
// So atingia emissor COM evento. Quem vem com sem_eventos:true entra em outro ramo de
// persistirResultadoCompartilhado, que sobrescreve o campo com UTC real. Por isso o
// defeito sobreviveu: metade da carteira sempre reportou certo.
//
// Medido em producao antes da correcao, 24/08 17:17 BRT, emissores da MESMA rodada
// noturna com 3 minutos entre os submits:
//   Light, Aegea, CSN, Hapvida (com evento)  -> horas_stale = 3,40
//   Rumo, Simpar               (sem evento)  -> horas_stale = 0,40
//
// Prova reversa: contra o codigo antigo o primeiro teste falha com horas_stale ~3, e o
// segundo (emissor sem evento) passa nos dois, que e exatamente o que escondia o bug.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const EMISSOR_COM_EVENTO = "Vibra Energia";
const EMISSOR_SEM_EVENTO = "Rumo";

function semanaISO(d) {
  const data = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dia = data.getUTCDay() || 7;
  data.setUTCDate(data.getUTCDate() + 4 - dia);
  const pj = new Date(Date.UTC(data.getUTCFullYear(), 0, 1));
  return `${data.getUTCFullYear()}-W${String(Math.ceil(((data - pj) / 864e5 + 1) / 7)).padStart(2, "0")}`;
}

function agoraBRT() {
  return new Date(Date.now() - 3 * 60 * 60 * 1e3);
}

function chaveEstadoSemanaCorrente() {
  return `radar:estado:${semanaISO(agoraBRT())}`;
}

function hojeBRT() {
  return agoraBRT().toISOString().slice(0, 10);
}

// Cobertura alta de proposito: com poucas fontes o payload sem_eventos cai no ramo
// INCONCLUSIVO e o teste mediria outro caminho que nao o do bug.
function fontes(n) {
  return Array.from({ length: n }, (_, i) => ({ rodada: `R${i + 1}`, query: `consulta ${i + 1}`, resultado: "sem achado" }));
}

async function submeter(empresa, resultado) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.92" },
    body: JSON.stringify({ action: "receber_analise", routine_key: ROUTINE_KEY, empresa, setor: "Teste", _matinal: false, provedor: "teste-relogio", resultado })
  });
}

async function horasStale(empresa) {
  const res = await SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.92" },
    body: JSON.stringify({ action: "listar_plano_rotina", routine_key: ROUTINE_KEY, modo: "noturno" })
  });
  expect(res.status).toBe(200);
  const b = await res.json();
  const alvo = (b.emissores || []).find((e) => e.empresa === empresa);
  expect(alvo, `emissor ${empresa} ausente do plano`).toBeTruthy();
  return alvo.horas_stale;
}

afterEach(async () => {
  try { await env.RADAR_KV.delete(chaveEstadoSemanaCorrente()); } catch (_) { }
});

describe("RELOGIO3H1 - varredura recem-gravada nao pode nascer com horas de atraso", () => {
  it("emissor COM evento reporta frescor proximo de zero", async () => {
    const r = await submeter(EMISSOR_COM_EVENTO, {
      empresa: EMISSOR_COM_EVENTO,
      setor: "Teste",
      sem_eventos: false,
      classificacao_geral: "RELEVANTE",
      cobertura_nota: "",
      fontes_consultadas: fontes(8),
      eventos: [{
        classificacao: "RELEVANTE",
        titulo: "Evento de teste do relogio",
        evento: "Texto de teste.",
        impacto_credito: "Texto de teste.",
        fonte_primaria: "https://www.fitchratings.com/entity/teste-relogio",
        fonte_tipo: "IMPRENSA",
        data_evento: hojeBRT(),
        data_aproximada: false
      }],
      _tier: "FULL",
      _rotina_v2: true
    });
    expect(r.status).toBe(200);

    const h = await horasStale(EMISSOR_COM_EVENTO);
    // 0,5h de folga cobre a latencia do teste. O bug produzia 3,0.
    expect(h).toBeLessThan(0.5);
  });

  it("emissor SEM evento continua reportando frescor proximo de zero", async () => {
    const r = await submeter(EMISSOR_SEM_EVENTO, {
      empresa: EMISSOR_SEM_EVENTO,
      setor: "Teste",
      sem_eventos: true,
      classificacao_geral: "ECO",
      cobertura_nota: "Nada material na janela.",
      fontes_consultadas: fontes(8),
      eventos: [],
      _tier: "FULL",
      _rotina_v2: true
    });
    expect(r.status).toBe(200);

    const h = await horasStale(EMISSOR_SEM_EVENTO);
    expect(h).toBeLessThan(0.5);
  });

  it("os dois caminhos concordam entre si", async () => {
    // A assimetria entre os dois ramos foi o que manteve o defeito invisivel por meses.
    // Este teste prende a simetria, nao so os valores.
    await submeter(EMISSOR_COM_EVENTO, {
      empresa: EMISSOR_COM_EVENTO, setor: "Teste", sem_eventos: false, classificacao_geral: "RELEVANTE",
      cobertura_nota: "", fontes_consultadas: fontes(8),
      eventos: [{ classificacao: "RELEVANTE", titulo: "Evento de teste do relogio", evento: "Texto.", impacto_credito: "Texto.", fonte_primaria: "https://www.fitchratings.com/entity/teste-relogio", fonte_tipo: "IMPRENSA", data_evento: hojeBRT(), data_aproximada: false }],
      _tier: "FULL", _rotina_v2: true
    });
    await submeter(EMISSOR_SEM_EVENTO, {
      empresa: EMISSOR_SEM_EVENTO, setor: "Teste", sem_eventos: true, classificacao_geral: "ECO",
      cobertura_nota: "Nada material na janela.", fontes_consultadas: fontes(8), eventos: [],
      _tier: "FULL", _rotina_v2: true
    });

    const comEvento = await horasStale(EMISSOR_COM_EVENTO);
    const semEvento = await horasStale(EMISSOR_SEM_EVENTO);
    expect(Math.abs(comEvento - semEvento)).toBeLessThan(0.5);
  });
});
