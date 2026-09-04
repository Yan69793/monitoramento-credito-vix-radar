import { SELF, env } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";

// FONTELATENCIA1 (2026-08-21, decisao do operador): evento CRITICO/RELEVANTE
// recente promove o emissor para a fila aprofundada da noturna na mesma semana,
// sem depender de cvm_novos. Antes, a promocao dependia do ZIP semanal da CVM e
// um emissor que aparecia na imprensa esperava ate domingo para subir de fila.
//
// Prova reversa embutida: contra o codigo antigo este teste falha porque o
// branch `_temEventoMaterialRecente(eventos, 7)` nao existia antes da regra, o
// tier sairia LIGHT ou SKIP e `motivos` nao conteria `imprensa_recente_7d`.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";

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

function isoDiasAtras(n) {
  const d = agoraBRT();
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

async function postPlano() {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.91" },
    body: JSON.stringify({ action: "listar_plano_rotina", routine_key: ROUTINE_KEY, modo: "noturno" })
  });
}

afterEach(async () => {
  try { await env.RADAR_KV.delete(chaveEstadoSemanaCorrente()); } catch (_) { }
});

describe("FONTELATENCIA1: imprensa recente promove para fila aprofundada", () => {
  it("emissor com evento RELEVANTE nos ultimos 7 dias sai FULL com motivo imprensa_recente_7d", async () => {
    const semana = chaveEstadoSemanaCorrente();
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana,
      updated_at: new Date().toISOString(),
      results: {
        "Vibra Energia": {
          _last_scanned_at: isoDiasAtras(3) + "T12:00:00.000Z",
          eventos: [
            {
              classificacao: "RELEVANTE",
              titulo: "Fato relevante de teste",
              data_evento: isoDiasAtras(2)
            }
          ],
          sem_eventos: false
        }
      }
    }));

    const res = await postPlano();
    expect(res.status).toBe(200);
    const plano = await res.json();
    expect(plano.ok).toBe(true);
    // Acompanha EMISSORES_LISTA em api/src/worker.js (104 desde a Usina Pampa Sul, 04/09/2026).
    expect(plano.total).toBe(104);

    const vibra = plano.emissores.find((e) => e.empresa === "Vibra Energia");
    expect(vibra).toBeDefined();
    expect(vibra.tier).toBe("FULL");
    expect(vibra.motivos).toContain("imprensa_recente_7d");
  });

  it("emissor sem evento recente nao ganha o motivo", async () => {
    const semana = chaveEstadoSemanaCorrente();
    await env.RADAR_KV.put(semana, JSON.stringify({
      week: semana,
      updated_at: new Date().toISOString(),
      results: {
        "Vibra Energia": {
          _last_scanned_at: isoDiasAtras(1) + "T12:00:00.000Z",
          eventos: [],
          sem_eventos: true
        }
      }
    }));

    const res = await postPlano();
    expect(res.status).toBe(200);
    const plano = await res.json();
    const vibra = plano.emissores.find((e) => e.empresa === "Vibra Energia");
    expect(vibra).toBeDefined();
    expect(vibra.motivos).not.toContain("imprensa_recente_7d");
  });
});
