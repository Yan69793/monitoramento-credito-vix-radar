import { describe, expect, it } from "vitest";
import {
  avaliarAvancoFeed,
  _tetosFonteCVM,
  AVANCO_FEED_ESTADOS,
} from "../src/worker.js";

// AVANCOFEED1 (2026-09-01). Guarda de avanco do feed.
//
// Episodio que originou: entre 28/08 e 01/09/2026 o painel ficou parado em
// 28/08. As tres rotinas rodaram, a noturna fechou com submit_ok=103 e todo
// semaforo estava verde. Medido em producao em 01/09: o teto do acervo da CVM
// era exatamente 2026-08-28, igual ao evento mais novo do feed. O lote semanal
// publicado no domingo 30/08 so carrega documento ate a sexta 28/08, e o
// proximo lote e 06/09. Ou seja, nao havia fato para persistir.
//
// O unico gate que media isso, `checks.evento_mais_novo`, dispara por
// "N dias uteis sem evento" (limite 2). Em 02/09 ele reprovaria esse mesmo
// estado saudavel. Alarme que toca sozinho e como alarme que nao toca: foi
// assim que o CVMURL404 passou quatro dias invisivel.
//
// PROVA DE DUAS PONTAS, que e o que este arquivo trava:
//   - a regra ACEITA feed no teto da fonte com a fonte dentro da cadencia,
//     inclusive no caso real de 01/09 e no de 02/09 que a regua antiga reprova;
//   - a regra REPROVA fonte a frente do feed quando o pipeline ja escreveu
//     depois de o lote ter chegado, que e "rodou, gravou e nao persistiu fato".

// Regua ANTIGA, reproduzida aqui so para provar que ela reprova o caso bom.
// Contagem de dias uteis apos a data, igual a `_cvmDiasUteisApos` do Worker.
const EVENTO_MAX_DU_ANTIGO = 2;
function diasUteisApos(dataISO, hojeISO) {
  const ini = new Date(dataISO + "T00:00:00Z");
  const fim = new Date(hojeISO + "T00:00:00Z");
  if (fim <= ini) return 0;
  let n = 0;
  const cur = new Date(ini.getTime());
  while (cur < fim) {
    cur.setUTCDate(cur.getUTCDate() + 1);
    const dow = cur.getUTCDay();
    if (dow !== 0 && dow !== 6) n++;
  }
  return n;
}
function reguaAntigaReprova(feedMax, hojeISO) {
  return diasUteisApos(feedMax, hojeISO) > EVENTO_MAX_DU_ANTIGO;
}

// Medida real de producao em 2026-09-01, das duas pontas:
//   MAX data_evento no estado (amostra 15 emissores) = 2026-08-28
//   MAX Data_Entrega no acervo cvm:documentos        = 2026-08-28
//   cvm_fonte_last_modified                          = 2026-08-30 (data pura,
//                                                       o health nao devolve hora)
//   cvm_fonte_proxima_prevista                       = 2026-09-06
//   cvm_fonte_ciclos_perdidos                        = 0
const CASO_REAL_0109 = {
  feed_max: "2026-08-28",
  fonte_max_referencia: "2026-08-28",
  fonte_max_entrega: "2026-08-28",
  fonte_dentro_cadencia: true,
  fonte_cadencia: "semanal",
  fonte_proxima_prevista: "2026-09-06",
  fonte_last_modified: "2026-08-30",
  estado_updated_at: "2026-08-31T13:31:00.000Z",
};

describe("_tetosFonteCVM", () => {
  it("le a forma compacta gravada em cvm:documentos ({d, de})", () => {
    const t = _tetosFonteCVM([
      { e: "BRASKEM S.A.", d: "2026-08-20", de: "2026-08-24" },
      { e: "VALE S.A.", d: "2026-08-27", de: "2026-08-28" },
      { e: "PETROBRAS", d: "2026-08-11", de: "2026-08-12" },
    ]);
    expect(t.max_data_referencia).toBe("2026-08-27");
    expect(t.max_data_entrega).toBe("2026-08-28");
    expect(t.total).toBe(3);
  });

  it("le a forma expandida do leitor ({data, data_entrega})", () => {
    const t = _tetosFonteCVM([
      { empresa_cvm: "OI S.A.", data: "2026-08-19", data_entrega: "2026-08-21" },
      { empresa_cvm: "CSN", data: "2026-08-26", data_entrega: "2026-08-28" },
    ]);
    expect(t.max_data_referencia).toBe("2026-08-26");
    expect(t.max_data_entrega).toBe("2026-08-28");
  });

  it("ignora lixo sem quebrar e devolve nulos para acervo vazio ou invalido", () => {
    expect(_tetosFonteCVM(null)).toEqual({ max_data_entrega: null, max_data_referencia: null, total: 0 });
    expect(_tetosFonteCVM([])).toEqual({ max_data_entrega: null, max_data_referencia: null, total: 0 });
    const t = _tetosFonteCVM([null, { d: "" }, { d: "28/08/2026" }, { de: "nao_identificada" }, { d: "2026-08-25" }]);
    expect(t.max_data_referencia).toBe("2026-08-25");
    expect(t.max_data_entrega).toBe(null);
    expect(t.total).toBe(5);
  });
});

describe("avaliarAvancoFeed - ACEITA (nao alerta) quando nao ha fato para persistir", () => {
  it("caso real de 01/09/2026: feed no teto da fonte, fonte dentro da cadencia", () => {
    const r = avaliarAvancoFeed(CASO_REAL_0109);
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SAUDAVEL);
    expect(r.alerta).toBe(false);
    expect(r.teto_comparavel).toBe("2026-08-28");
    expect(r.teto_origem).toBe("data_referencia");
    expect(r.atraso_dias).toBe(0);
    expect(r.fonte_proxima_prevista).toBe("2026-09-06");
    expect(r.diagnostico).toContain("2026-09-06");
  });

  it("02/09/2026: a regua antiga reprova o mesmo estado e a nova aceita", () => {
    // Este e o ponto do fix. Em 02/09 o feed continua em 28/08 e continua
    // saudavel, porque o proximo lote da CVM so sai em 06/09.
    expect(reguaAntigaReprova("2026-08-28", "2026-09-02")).toBe(true);
    const r = avaliarAvancoFeed(CASO_REAL_0109);
    expect(r.alerta).toBe(false);
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SAUDAVEL);
  });

  it("feed A FRENTE da fonte tambem e saude: imprensa e rating publicam todo dia util", () => {
    const r = avaliarAvancoFeed({ ...CASO_REAL_0109, feed_max: "2026-09-01" });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SAUDAVEL);
    expect(r.alerta).toBe(false);
    expect(r.atraso_dias).toBe(0);
  });

  it("teto comparavel e Data_Referencia, nao Data_Entrega: protocolo atrasado nao vira alerta", () => {
    // Documento entregue em 28/08 sobre fato de 20/08. O evento herda a data de
    // REFERENCIA (_resolverDataDocCvm prefere doc.data), entao o feed em 20/08
    // esta correto. Comparar contra Data_Entrega acusaria o pipeline a toa.
    const r = avaliarAvancoFeed({
      feed_max: "2026-08-20",
      fonte_max_referencia: "2026-08-20",
      fonte_max_entrega: "2026-08-28",
      fonte_dentro_cadencia: true,
      fonte_last_modified: "2026-08-30T06:12:00.000Z",
      estado_updated_at: "2026-08-31T13:31:00.000Z",
    });
    expect(r.teto_origem).toBe("data_referencia");
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SAUDAVEL);
    expect(r.alerta).toBe(false);
  });

  it("fonte parada e reportada como fonte parada, sem alarme duplo do pipeline", () => {
    const r = avaliarAvancoFeed({ ...CASO_REAL_0109, fonte_dentro_cadencia: false });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.FONTE_PARADA);
    expect(r.alerta).toBe(false);
    expect(r.diagnostico).toContain("cvm_fonte_motivo");
  });

  it("fonte a frente mas sem varredura depois do lote: janela normal, nao alerta", () => {
    const r = avaliarAvancoFeed({
      ...CASO_REAL_0109,
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_last_modified: "2026-08-30T06:12:00.000Z",
      estado_updated_at: "2026-08-29T13:31:00.000Z",
    });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.AGUARDANDO);
    expect(r.alerta).toBe(false);
    expect(r.pipeline_escreveu_apos_lote).toBe(false);
  });

  it("sem teto de fonte legivel nao inventa veredicto sobre o pipeline", () => {
    const r = avaliarAvancoFeed({ feed_max: "2026-08-28", fonte_max_referencia: null, fonte_max_entrega: null });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.FONTE_INDETERMINADA);
    expect(r.alerta).toBe(false);
  });
});

describe("avaliarAvancoFeed - REPROVA (alerta) quando a fonte andou e o feed nao", () => {
  it("pipeline_nao_persistiu: fonte em 30/08, feed em 28/08, estado escrito em 31/08", () => {
    const r = avaliarAvancoFeed({
      feed_max: "2026-08-28",
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_dentro_cadencia: true,
      fonte_last_modified: "2026-08-30T06:12:00.000Z",
      estado_updated_at: "2026-08-31T13:31:00.000Z",
    });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.NAO_PERSISTIU);
    expect(r.alerta).toBe(true);
    expect(r.pipeline_escreveu_apos_lote).toBe(true);
    expect(r.atraso_dias).toBe(2);
    expect(r.diagnostico).toContain("removidos_pre_verificador");
  });

  it("Last-Modified sem hora vale o FIM do dia, nao a meia-noite", () => {
    // Medido em producao em 01/09/2026: o health devolve
    // cvm_fonte_last_modified:"2026-08-30", data pura. Tomar isso como 00:00Z
    // faria a varredura de domingo 13:05Z contar como "rodou depois do lote"
    // mesmo com a CVM publicando a noite, e o gate acusaria o pipeline por uma
    // janela que ele ainda nao teve.
    const domingoAntesDoLote = avaliarAvancoFeed({
      feed_max: "2026-08-28",
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_dentro_cadencia: true,
      fonte_last_modified: "2026-08-30",
      estado_updated_at: "2026-08-30T13:05:00.000Z",
    });
    expect(domingoAntesDoLote.referencia_lote).toBe("2026-08-30T23:59:59.000Z");
    expect(domingoAntesDoLote.pipeline_escreveu_apos_lote).toBe(false);
    expect(domingoAntesDoLote.estado).toBe(AVANCO_FEED_ESTADOS.AGUARDANDO);
    expect(domingoAntesDoLote.alerta).toBe(false);

    // Mesma data pura, mas a varredura da segunda ja rodou: agora alerta.
    const segundaDepoisDoLote = avaliarAvancoFeed({
      feed_max: "2026-08-28",
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_dentro_cadencia: true,
      fonte_last_modified: "2026-08-30",
      estado_updated_at: "2026-08-31T13:05:00.000Z",
    });
    expect(segundaDepoisDoLote.pipeline_escreveu_apos_lote).toBe(true);
    expect(segundaDepoisDoLote.estado).toBe(AVANCO_FEED_ESTADOS.NAO_PERSISTIU);
    expect(segundaDepoisDoLote.alerta).toBe(true);
  });

  it("Last-Modified com hora e usado como veio, sem arredondar para o fim do dia", () => {
    const r = avaliarAvancoFeed({
      feed_max: "2026-08-28",
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_dentro_cadencia: true,
      fonte_last_modified: "2026-08-30T06:12:00.000Z",
      estado_updated_at: "2026-08-30T13:05:00.000Z",
    });
    expect(r.referencia_lote).toBe("2026-08-30T06:12:00.000Z");
    expect(r.pipeline_escreveu_apos_lote).toBe(true);
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.NAO_PERSISTIU);
  });

  it("sem Last-Modified, a chegada do lote cai para o fim do dia da maior Data_Entrega", () => {
    const r = avaliarAvancoFeed({
      feed_max: "2026-08-28",
      fonte_max_referencia: "2026-08-30",
      fonte_max_entrega: "2026-08-30",
      fonte_dentro_cadencia: true,
      fonte_last_modified: null,
      estado_updated_at: "2026-08-31T13:31:00.000Z",
    });
    expect(r.referencia_lote).toBe("2026-08-30T23:59:59.000Z");
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.NAO_PERSISTIU);
    expect(r.alerta).toBe(true);
  });

  it("sem UM evento datado no estado inteiro e ausencia de dado, nao ausencia de fato", () => {
    const r = avaliarAvancoFeed({ ...CASO_REAL_0109, feed_max: null });
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SEM_EVENTO);
    expect(r.alerta).toBe(true);
  });

  it("entrada vazia nao passa em silencio", () => {
    const r = avaliarAvancoFeed(undefined);
    expect(r.estado).toBe(AVANCO_FEED_ESTADOS.SEM_EVENTO);
    expect(r.alerta).toBe(true);
  });
});

describe("avaliarAvancoFeed - contrato dos campos que o frescor-check consome", () => {
  it("expoe as duas medidas e a referencia de lote em todo veredicto comparavel", () => {
    for (const entrada of [
      CASO_REAL_0109,
      { ...CASO_REAL_0109, fonte_dentro_cadencia: false },
      { ...CASO_REAL_0109, fonte_max_referencia: "2026-08-30", fonte_max_entrega: "2026-08-30" },
    ]) {
      const r = avaliarAvancoFeed(entrada);
      expect(r.feed_max_data_evento).toBe("2026-08-28");
      expect(r.fonte_max_data_entrega).not.toBe(null);
      expect(r.teto_comparavel).not.toBe(null);
      expect(r.referencia_lote).not.toBe(null);
      expect(typeof r.diagnostico).toBe("string");
      expect(r.diagnostico.length).toBeGreaterThan(40);
      expect(typeof r.alerta).toBe("boolean");
    }
  });

  it("os seis estados sao distintos e nenhum veredicto sai sem estado", () => {
    const vistos = new Set();
    const entradas = [
      CASO_REAL_0109,
      { ...CASO_REAL_0109, fonte_dentro_cadencia: false },
      { ...CASO_REAL_0109, feed_max: null },
      { feed_max: "2026-08-28" },
      { ...CASO_REAL_0109, fonte_max_referencia: "2026-08-30", fonte_max_entrega: "2026-08-30" },
      { ...CASO_REAL_0109, fonte_max_referencia: "2026-08-30", fonte_max_entrega: "2026-08-30", estado_updated_at: "2026-08-29T13:31:00.000Z" },
    ];
    for (const e of entradas) {
      const r = avaliarAvancoFeed(e);
      expect(r.estado).toBeTruthy();
      vistos.add(r.estado);
    }
    expect(vistos.size).toBe(6);
    expect(new Set(Object.values(AVANCO_FEED_ESTADOS))).toEqual(vistos);
  });
});
