import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// HISTFLAT1 (2026-08-19): executarPipelinePreditivo (worker.js ~13804) tinha a
// LEITURA do historico real (ews:hist:{empresa}) atras do mesmo gate que decide
// se um ponto NOVO e gravado (persistHist). O unico caller com opts (endpoint
// admin_executar_predictive, usado por scripts/smoke-preditivo-lab.ps1) passa
// skip_hist_persist:true, entao pulava a leitura inteira e calculava hist_len=1
// para os 103 emissores, mesmo com serie real acumulada no KV. Esse payload
// achatado era gravado em predictive_v1:latest, a MESMA chave que os crons
// matinal/noturno (worker.js scheduled(), ~17521/17567) escrevem 2x/dia com
// ponto real. Qualquer chamada admin depois do ultimo cron do dia sobrescrevia
// o snapshot correto. Fix: leitura sempre roda; so a escrita de ponto novo
// (persistirHistEwsBatch) continua condicionada a persistHist.
//
// HISTFLAT2 (2026-08-19, achado DEPOIS do fix acima em producao real - hist_len
// continuava 1 para os 103 pos-deploy): kvEwsHistKey (worker.js ~13539) grava com
// empresa.toLowerCase().trim() antes do encodeURIComponent. histMap era montado
// decodificando essa mesma chave (fica lowercase), mas lido com "histMap[empresa]"
// usando o case original de EMISSORES_LISTA (ex. "Oncoclínicas", com maiuscula).
// Miss de lookup silencioso: histRaw sempre [], mesmo nos crons que sempre leram
// (persistHist=true la, HISTFLAT1 nunca afetou esse caminho). Esse era o bug
// real por tras dos 8 dias de hist_len=1 na producao, nao so o HISTFLAT1.
// O teste abaixo seeda a chave EXATAMENTE como kvEwsHistKey grava (lowercase),
// para nao mascarar este bug de novo como a primeira versao deste teste fez.

function postAdmin(action, extra) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, admin_senha: env.ADMIN_PASSWORD, ...extra }),
  });
}

function kvEwsHistKey(empresa) {
  // Copia literal de worker.js:13539-13541 - o teste tem que gravar exatamente
  // como o codigo real grava, senao mascara bug de mismatch de chave de novo.
  return "ews:hist:" + encodeURIComponent(String(empresa || "").toLowerCase().trim());
}

const EMPRESA_TESTE = "Oncoclínicas";
const HIST_KEY = kvEwsHistKey(EMPRESA_TESTE);

describe("HISTFLAT1+2 - leitura de historico real (gate de escrita + case da chave)", () => {
  it("admin_executar_predictive (skip_hist_persist) LE serie real pre-existente em vez de tratar como vazia", async () => {
    // Seed com HIST_KEY = kvEwsHistKey(EMPRESA_TESTE), ou seja, minusculo - exatamente
    // como a escrita real grava. Empresa exibida/lida em EMISSORES_LISTA continua com
    // maiuscula ("Oncoclínicas"). Se o lookup nao normalizar (HISTFLAT2), isto falha com
    // hist_len=1 mesmo com a leitura ligada (HISTFLAT1 corrigido nao basta sozinho).
    const serieReal = [
      { data: "2026-08-16", score: 60 },
      { data: "2026-08-17", score: 63 },
    ];
    await env.RADAR_KV.put(HIST_KEY, JSON.stringify(serieReal));

    const res = await postAdmin("admin_executar_predictive");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.lab_interno).toBe(true);

    const emissor = body.emissores.find((e) => e.name === EMPRESA_TESTE);
    expect(emissor, "emissor de teste deveria estar no payload").toBeTruthy();
    // 2 pontos pre-existentes + o ponto de hoje computado em memoria = 3.
    // Antes do fix, histMap ficava {} e isso dava sempre 1.
    expect(emissor.features.hist_len).toBe(3);
  });

  it("chamada admin (lab) NAO grava ponto novo na serie real - isolamento preservado", async () => {
    const serieReal = [{ data: "2026-08-10", score: 40 }];
    await env.RADAR_KV.put(HIST_KEY, JSON.stringify(serieReal));

    await postAdmin("admin_executar_predictive");

    const posDepois = await env.RADAR_KV.get(HIST_KEY, "json");
    expect(posDepois).toEqual(serieReal); // inalterada: lab nao persiste
  });

  it("sem serie previa, hist_len e 1 (comportamento correto para emissor novo, nao regrediu)", async () => {
    await env.RADAR_KV.delete(HIST_KEY);
    const res = await postAdmin("admin_executar_predictive");
    const body = await res.json();
    const emissor = body.emissores.find((e) => e.name === EMPRESA_TESTE);
    expect(emissor.features.hist_len).toBe(1);
  });
});

// Formula pura de acumulacao (worker.js ~13853), a mesma usada pelos crons
// matinal/noturno com persistHist=true. Cobertura de idempotencia que a
// integracao acima nao exercita porque simular scheduled() foge do escopo
// minimo deste fix. Ja validada localmente fora do vitest (Node puro, sem
// Miniflare) contra os criterios do pedido: dia N->1, N+1->2, N+2->3,
// reprocessar N+2 continua 3 sem duplicar, valores antigos intactos,
// ordenacao cronologica, ausencia temporaria nao apaga serie anterior.
function proximoHist(histRaw, dataISO, score) {
  return [{ data: dataISO, score: Math.round(score * 10) / 10 }, ...histRaw.filter((h) => h && h.data !== dataISO)].slice(0, 90);
}

describe("formula de acumulacao de historico (pura, sem KV)", () => {
  it("cresce 1 ponto por dia novo", () => {
    let h = [];
    h = proximoHist(h, "2026-08-11", 50); expect(h.length).toBe(1);
    h = proximoHist(h, "2026-08-12", 52); expect(h.length).toBe(2);
    h = proximoHist(h, "2026-08-13", 55); expect(h.length).toBe(3);
  });

  it("reprocessar o mesmo dia nao duplica, so atualiza o score do dia", () => {
    let h = proximoHist(proximoHist([], "2026-08-11", 50), "2026-08-12", 52);
    h = proximoHist(h, "2026-08-12", 99); // reprocessa 12/08 com score diferente
    expect(h.length).toBe(2);
    expect(h.find((p) => p.data === "2026-08-12").score).toBe(99);
    expect(h.find((p) => p.data === "2026-08-11").score).toBe(50); // dia anterior intacto
  });

  it("mantem ordenacao cronologica decrescente (mais novo primeiro)", () => {
    let h = proximoHist(proximoHist(proximoHist([], "2026-08-11", 1), "2026-08-12", 2), "2026-08-13", 3);
    expect(h.map((p) => p.data)).toEqual(["2026-08-13", "2026-08-12", "2026-08-11"]);
  });

  it("ausencia temporaria (pulou um dia) nao apaga a serie anterior", () => {
    let h = proximoHist(proximoHist([], "2026-08-11", 1), "2026-08-12", 2);
    // 13/08 nao rodou (blackout). 14/08 roda normal.
    h = proximoHist(h, "2026-08-14", 4);
    expect(h.length).toBe(3);
    expect(h.map((p) => p.data)).toEqual(["2026-08-14", "2026-08-12", "2026-08-11"]);
  });
});
