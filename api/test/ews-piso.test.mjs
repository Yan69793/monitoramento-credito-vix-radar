import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { fixarRelogioDoFixture, soltarRelogio } from "./_relogio-fixo.mjs";
import estadoW31 from "./fixtures/estado-2026-W31.json" with { type: "json" };
import estadoW32 from "./fixtures/estado-2026-W32.json" with { type: "json" };
import estadoW33 from "./fixtures/estado-2026-W33.json" with { type: "json" };
import estadoW34 from "./fixtures/estado-2026-W34.json" with { type: "json" };
import estadoW35 from "./fixtures/estado-2026-W35.json" with { type: "json" };
import anomalias from "./fixtures/anomalias.json" with { type: "json" };

// EWSFLOOR1 (auditoria 2026-08-29, plano aprovado Fase 1.1).
//
// O plano mandou medir antes de mexer: o 66 (Raízen, Oncoclínicas, Oi) e o 53,2 da
// Light não aparecem em nenhuma das duas tabelas de piso (_RJ_FLOOR, piso por
// evento crítico), então a causa raiz só podia ser declarada depois de reproduzir
// o cálculo com o estado real dos emissores.
//
// Medição com fixture de produção (KV `radar:estado:2026-W3x` + anomalias, baixado
// 29/08/2026): o 66 é o piso crítico 61 (tag `default` em evento CRITICO) + "Padrão
// de deterioração" +5 (nSinaisRisco >= 3). O "53,2" da Light era estimativa de mão
// da sessão de auditoria, não valor medido: com o estado real a Light pontua 50,
// piso estrutural 50 aplicado (delta 36, sinais somam 14), soma da decomposição
// fecha em 50. A hipótese de defeito de soma (decomposição não fechando com o
// score) caiu.
//
// O que restou de real é semântico: o componente de piso carrega `peso_max: piso`
// ao lado de `pontos: delta`, o que lê como se o piso fosse um ponto somado. A
// correção (EWSFLOOR1) faz a resposta carregar o piso como metadado explícito —
// `piso_aplicado`, `piso_valor`, `piso_causa`, `score_calculado` — e o frontend
// renderiza o piso como mínimo aplicado, não como contribuição de ponto. Estes
// testes travam essa semântica.

const WEEKS = ["2026-W31", "2026-W32", "2026-W33", "2026-W34", "2026-W35"];
const ALVOS = ["Raízen", "Oncoclínicas", "Oi", "Light"];

const ESTADOS = [estadoW31, estadoW32, estadoW33, estadoW34, estadoW35];

async function mintJWT(secret) {
  const b64url = (buf) => Buffer.from(buf).toString("base64url");
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const agora = Math.floor(Date.now() / 1000);
  const body = b64url(JSON.stringify({ sub: "test", email: "test@example.com", iat: agora, exp: agora + 3600 }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(sig)}`;
}

async function ewsDe(empresa, token) {
  const r = await SELF.fetch(`https://exemplo.invalid/?op=ews&empresa=${encodeURIComponent(empresa)}`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  expect(r.status).toBe(200);
  const j = await r.json();
  expect(j.ok).toBe(true);
  return j.ews;
}

function somaPontos(decomp) {
  return Math.round((decomp || []).reduce((s, c) => s + (c.pontos || 0), 0) * 100) / 100;
}

describe("PISO EWS — semântica corrigida (EWSFLOOR1)", () => {
  let token;

  beforeEach(async () => {
    // RELOGIOTESTE1: os valores abaixo saem do decaimento de recencia do EWS
    // (exp(-0.046*dias)), que derrete cerca de 4,5% por dia de calendario. Sem
    // congelar, a suite so passa nas horas seguintes a medicao.
    fixarRelogioDoFixture();
    for (let i = 0; i < ESTADOS.length; i++) {
      await env.RADAR_KV.put(`radar:estado:${WEEKS[i]}`, JSON.stringify(ESTADOS[i]));
    }
    await env.RADAR_KV.put("mercado:anomalias:ativas", JSON.stringify(anomalias));
    token = await mintJWT(env.JWT_SECRET);
  });

  afterEach(() => {
    soltarRelogio();
  });

  it("reproduz o 66 (piso crítico 61 + padrão +5) e expõe o piso como metadado", async () => {
    for (const emp of ["Raízen", "Oncoclínicas", "Oi"]) {
      const ews = await ewsDe(emp, token);
      const soma = somaPontos(ews.decomposicao);

      // O 66 = piso crítico 61 (evento CRITICO com tag `default`) + "Padrão de
      // deterioração" +5. Medido no repro com estado real.
      expect(ews.score, `${emp}: score deve ser 66`).toBe(66);
      expect(ews.piso_aplicado, `${emp}: piso deve estar aplicado`).toBe(true);
      expect(ews.piso_valor, `${emp}: piso_valor deve ser 61`).toBe(61);
      expect(ews.piso_causa, `${emp}: causa do piso`).toMatch(/rj_ou_default_ativo/);

      // O componente de piso existe na decomposição e carrega peso_max 61.
      const floor61 = (ews.decomposicao || []).find((c) => c.tipo === "floor" && c.peso_max === 61);
      expect(floor61, `${emp}: deve haver componente de piso com peso_max 61`).toBeTruthy();

      // score_calculado = sinais + bônus de deterioração, sem piso. A soma da
      // decomposição = sinais + delta do piso + 5 do padrão, então score_calculado
      // fecha com `soma - floor.pontos`. Nada de pino fixo: deriva do próprio estado.
      expect(ews.score_calculado, `${emp}: score_calculado deve ser soma - delta do piso`).toBeCloseTo(soma - floor61.pontos, 1);
      // Piso agiu (sinais < 61 antes do +5), logo o sem-piso fica abaixo do final.
      expect(ews.score_calculado, `${emp}: score_calculado deve ser menor que o score final`).toBeLessThan(ews.score);

      // O padrão +5 é componente próprio.
      const padrao = (ews.decomposicao || []).find((c) => c.tipo_sinal === "multiplos_sinais");
      expect(padrao, `${emp}: deve haver componente Padrão de deterioração +5`).toBeTruthy();
      expect(padrao.pontos).toBe(5);

      // Invariante de soma: decomposição fecha com o score final. A tolerância
      // medida é 0,5: classificarEWS arredonda o score final para inteiro, então a
      // diferença máxima entre o score exibido e a soma dos `pontos` (cada um já a
      // 0,1) é 0,5 + ruído de float. Muito abaixo disso não há soma quebrada.
      expect(Math.abs(ews.score - soma), `${emp}: soma da decomposicao deve fechar`).toBeLessThan(0.6);
    }
  });

  it("Light: piso estrutural 50 aplicado, score calculado 14 e soma fecha", async () => {
    const ews = await ewsDe("Light", token);
    const soma = somaPontos(ews.decomposicao);

    // Medido no fixture (probe 30/08): sinais somam 14,0, piso estrutural 50 sobe
    // para 50 (delta 36). O "14,5" desta assertiva veio de antes do MATERIALSAT1,
    // que dampiou o boost de tag CRITICO na enriquecimento e derrubou o score
    // pre-piso em 0,5; os numeros aqui sao os do estado real do fixture.
    expect(ews.score).toBe(50);
    expect(ews.piso_aplicado).toBe(true);
    expect(ews.piso_valor).toBe(50);
    expect(ews.piso_causa).toBe("rj_estrutural");
    const floor = (ews.decomposicao || []).find((c) => c.tipo === "floor" && c.tipo_sinal === "rj_estrutural");
    expect(floor).toBeTruthy();
    expect(floor.pontos).toBeCloseTo(36, 1);
    // Light não ativa o +5 (nSinaisRisco < 3): score_calculado = sinais = soma - delta.
    expect(ews.score_calculado).toBeCloseTo(soma - floor.pontos, 1);
    expect(ews.score_calculado).toBeCloseTo(14, 1);

    expect(Math.abs(ews.score - soma)).toBeLessThan(0.6);
  });

  it("emissor sem piso: piso_aplicado false e piso_valor null", async () => {
    // Injeta emissor adicional na semana corrente: um único evento de tag fraca,
    // sem CRITICO, sem nSinaisRisco>=3, sem piso estrutural.
    const extra = {
      ...estadoW35,
      results: {
        ...estadoW35.results,
        "Emissor Sem Piso": {
          empresa: "Emissor Sem Piso",
          eventos: [
            {
              data_evento: "2026-08-28",
              titulo: "Evento isolado sem gravidade",
              classificacao: "RELEVANTE",
              tags: ["conversao_debentures"],
              fonte_tipo: "IMPRENSA"
            }
          ]
        }
      }
    };
    await env.RADAR_KV.put("radar:estado:2026-W35", JSON.stringify(extra));

    const ews = await ewsDe("Emissor Sem Piso", token);
    expect(ews.piso_aplicado).toBe(false);
    expect(ews.piso_valor).toBeNull();
    expect(ews.piso_causa).toBeNull();
    // score_calculado ainda é o valor honesto dos sinais, sem piso.
    expect(ews.score_calculado).toBeGreaterThan(0);
    expect(ews.score).toBeGreaterThan(0);
    expect(Math.abs(ews.score - somaPontos(ews.decomposicao))).toBeLessThan(0.6);
  });

  it("ranking: desempate por score_calculado desc entre scores iguais (PISODIFF1)", async () => {
    // O ranking (op=ews sem empresa) ordena por score desc e, dentro de scores
    // iguais, por score_calculado desc. Os três pisados do fixture empatam em 66
    // e devem vir ordenados por gravidade dos sinais, não pela ordem de EMISSORES_LISTA.
    const r = await SELF.fetch("https://exemplo.invalid/?op=ews", {
      headers: { Authorization: `Bearer ${token}` }
    });
    expect(r.status).toBe(200);
    const j = await r.json();
    expect(j.ok).toBe(true);
    const ranking = j.ranking || [];
    expect(ranking.length).toBeGreaterThan(0);

    const pisados = ranking.filter((x) => ["Raízen", "Oncoclínicas", "Oi"].indexOf(x.empresa) >= 0);
    expect(pisados.length).toBe(3);
    for (const p of pisados) {
      expect(p.score).toBe(66);
      expect(p.piso_aplicado).toBe(true);
      expect(typeof p.score_calculado).toBe("number");
    }
    // Dentro do grupo empatado em 66, ordenação por score_calculado desc.
    for (let i = 0; i < pisados.length - 1; i++) {
      expect(pisados[i].score_calculado).toBeGreaterThanOrEqual(pisados[i + 1].score_calculado);
    }
  });
});
