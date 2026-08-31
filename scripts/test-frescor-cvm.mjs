// CVMFRESCOR1 (2026-08-19) - harness local do calculo de frescor da fonte CVM.
//
// Existe para cobrir a parte puramente algoritmica (contagem de dias uteis e
// corridos, decisao de frescor, falha dura x cadencia) em Node cru, sem subir
// Worker nenhum. A premissa original, de que a suite vitest nao rodava local
// porque o Smart App Control bloqueava workerd.exe por assinatura (CodeIntegrity
// 3077/3033), foi refutada por medicao em 20/08/2026
// (VerifiedAndReputablePolicyState=0, nenhum evento CodeIntegrity cita workerd).
// A causa real de o vitest nao rodar local apos o deploy e `npm ci --omit=dev`
// apagando as devDeps. O script foi mantido mesmo assim porque garante o
// calculo em qualquer node, mais rapido que Miniflare para iteracao local.
//
// Regra de ouro herdada do test-dedup-eventos.mjs: extrair as funcoes DIRETO do
// worker.js real, nunca reescrever uma copia. Copia solta passa verde enquanto o
// codigo de producao regride. Encontrado quebrado em 31/08 (segunda vez): o
// CVMDURA1 (24/08) acrescentou falha_dura/degrada_servico a avaliarFrescorCVM e
// o harness nao tinha acompanhado, ReferenceError em _cvmDiasCorridosApos por
// falta de extracao, sintoma identico ao drift do CVMCADENCIA1 em 20/08.
//
// Uso: node scripts/test-frescor-cvm.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const src = fs.readFileSync(path.join(raiz, "api", "src", "worker.js"), "utf8");

function extrair(nome, tipo) {
  const marca = (tipo === "async" ? "async function " : "function ") + nome + "(";
  const ini = src.indexOf(marca);
  if (ini < 0) throw new Error("nao achei " + nome + " em api/src/worker.js");
  let i = src.indexOf("{", ini);
  let prof = 0;
  for (let j = i; j < src.length; j++) {
    if (src[j] === "{") prof++;
    else if (src[j] === "}") {
      prof--;
      if (prof === 0) return src.slice(ini, j + 1);
    }
  }
  throw new Error("nao consegui fechar as chaves de " + nome);
}

const fonte = [
  extrair("_cvmDiasUteisApos", "sync"),
  extrair("_cvmDiasCorridosApos", "sync"),
  extrair("_cvmProximaPublicacaoPrevista", "sync"),
  extrair("_cvmMaxDataEntrega", "sync"),
  extrair("gravarFonteCVMMeta", "async"),
  extrair("avaliarFrescorCVM", "async"),
].join("\n\n");

// Constantes e dependencia que as funcoes esperam encontrar no escopo do Worker.
const preludio = `
var CVM_FONTE_META_KEY = "cvm:fonte_meta";
var CVM_FONTE_CICLO_DIAS = 7;
var CVM_FONTE_MAX_CICLOS = 2;
var CVM_FONTE_MAX_FALHAS = 4;
var CVM_FONTE_MOTIVOS_DUROS = /^(http_\\d{3}|excecao:|fonte_ausente_no_catalogo|nao_e_zip|nao_e_deflate)/;
var CVM_FONTE_DOW_PUBLICACAO = 0;
var __HOJE_FAKE = null;
function obterAgoraBRT() { return new Date(__HOJE_FAKE); }
`;

const mod = new Function(
  preludio + fonte + "\nreturn { _cvmDiasUteisApos, _cvmDiasCorridosApos, _cvmProximaPublicacaoPrevista, _cvmMaxDataEntrega, gravarFonteCVMMeta, avaliarFrescorCVM, setHoje: function(d){ __HOJE_FAKE = d; } };"
)();

function envFake(meta, docs) {
  const gravado = [];
  const e = {
    _gravado: gravado,
    RADAR_KV: {
      get: async (k) => {
        if (k === "cvm:fonte_meta") return meta === undefined ? null : meta;
        if (k === "cvm:documentos") return docs === undefined ? null : docs;
        return null;
      },
      put: async (k, v) => { gravado.push({ k, v: JSON.parse(v) }); },
    },
  };
  return e;
}

let falhas = 0;
let total = 0;
function checa(titulo, real, esperado) {
  total++;
  const a = JSON.stringify(real);
  const b = JSON.stringify(esperado);
  if (a === b) {
    console.log("  OK   " + titulo);
  } else {
    falhas++;
    console.log("  FALHA " + titulo + "\n         esperado: " + b + "\n         obtido:   " + a);
  }
}

console.log("\n=== contagem de dias uteis (fim de semana nao conta) ===");
// 2026-08-14 sexta, 15 sabado, 16 domingo, 17 segunda, 18 terca, 19 quarta.
checa("sexta 14 -> segunda 17 = 1 du", mod._cvmDiasUteisApos("2026-08-14", "2026-08-17"), 1);
checa("sexta 14 -> sexta 14 = 0 du", mod._cvmDiasUteisApos("2026-08-14", "2026-08-14"), 0);
checa("domingo 16 -> quarta 19 = 3 du", mod._cvmDiasUteisApos("2026-08-16", "2026-08-19"), 3);
checa("terca 18 -> quarta 19 = 1 du", mod._cvmDiasUteisApos("2026-08-18", "2026-08-19"), 1);
checa("segunda 17 -> quarta 19 = 2 du", mod._cvmDiasUteisApos("2026-08-17", "2026-08-19"), 2);
checa("sexta 14 -> sabado 15 = 0 du", mod._cvmDiasUteisApos("2026-08-14", "2026-08-15"), 0);
checa("data invalida devolve null", mod._cvmDiasUteisApos("lixo", "2026-08-19"), null);
checa("data futura nao vira negativo", mod._cvmDiasUteisApos("2026-08-25", "2026-08-19"), 0);

console.log("\n=== max data de entrega ===");
checa("pega o maior de", mod._cvmMaxDataEntrega([{ de: "2026-08-11" }, { de: "2026-08-16" }, { de: "2026-08-13" }]), "2026-08-16");
checa("cai para d quando nao ha de", mod._cvmMaxDataEntrega([{ d: "2026-08-12" }]), "2026-08-12");
checa("array vazio devolve null", mod._cvmMaxDataEntrega([]), null);
checa("nao-array devolve null", mod._cvmMaxDataEntrega(null), null);

console.log("\n=== dias corridos (fim de semana CONTA, ao contrario de dias uteis) ===");
checa("quarta 12 -> quarta 19 = 7 dias corridos (dias uteis seria 5)", mod._cvmDiasCorridosApos("2026-08-12", "2026-08-19"), 7);
checa("sexta 14 -> segunda 17 = 3 dias corridos (dias uteis seria 1)", mod._cvmDiasCorridosApos("2026-08-14", "2026-08-17"), 3);
checa("data invalida devolve null", mod._cvmDiasCorridosApos("lixo", "2026-08-19"), null);
checa("data futura nao vira negativo", mod._cvmDiasCorridosApos("2026-08-25", "2026-08-19"), 0);

console.log("\n=== proxima publicacao prevista (sempre o domingo seguinte) ===");
checa("de sexta 14 -> domingo 16", mod._cvmProximaPublicacaoPrevista("2026-08-14"), "2026-08-16");
checa("do proprio domingo 16 -> pula pro domingo seguinte 23", mod._cvmProximaPublicacaoPrevista("2026-08-16"), "2026-08-23");
checa("de quarta 19 -> domingo 23", mod._cvmProximaPublicacaoPrevista("2026-08-19"), "2026-08-23");
checa("sem ref devolve null", mod._cvmProximaPublicacaoPrevista(null), null);

console.log("\n=== decisao de frescor (hoje fixado em 2026-08-19, quarta) ===");
mod.setHoje("2026-08-19T12:00:00Z");

const envSemMeta = envFake(undefined, undefined);
const rSemMeta = await mod.avaliarFrescorCVM(envSemMeta);
checa("meta ausente e fail-closed", { ok: rSemMeta.ok, motivo: rSemMeta.motivo }, { ok: false, motivo: "sem_meta" });

const casos = [
  ["fonte de ontem passa", { ok: true, last_modified_iso: "2026-08-18" }, { ok: true, motivo: "ok" }],
  ["domingo 16 (ciclo normal de publicacao) passa, nao e mais falso-positivo", { ok: true, last_modified_iso: "2026-08-16" }, { ok: true, motivo: "ok" }],
  ["13 dias corridos (1 ciclo perdido) ainda passa, no limite", { ok: true, last_modified_iso: "2026-08-06" }, { ok: true, motivo: "ok" }],
  ["14 dias corridos (2 ciclos perdidos) reprova, no limite exato", { ok: true, last_modified_iso: "2026-08-05" }, { ok: false, motivo: "fonte_sem_publicar_ha_2_ciclos_semanais_14_dias" }],
  ["21 dias corridos (3 ciclos perdidos) reprova", { ok: true, last_modified_iso: "2026-07-29" }, { ok: false, motivo: "fonte_sem_publicar_ha_3_ciclos_semanais_21_dias" }],
  ["data de referencia invalida reprova com motivo proprio", { ok: true, last_modified_iso: "lixo" }, { ok: false, motivo: "data_invalida" }],
];
for (const [titulo, meta, esperado] of casos) {
  const env = envFake(meta, undefined);
  const r = await mod.avaliarFrescorCVM(env);
  checa(titulo, { ok: r.ok, motivo: r.motivo }, esperado);
}

const envSyncFalhou = envFake({ ok: false, motivo: "timeout", last_modified_iso: "2026-08-18" }, undefined);
const rSyncFalhou = await mod.avaliarFrescorCVM(envSyncFalhou);
checa("ultimo sync falhou reprova mesmo com data de hoje", { ok: rSyncFalhou.ok, motivo: rSyncFalhou.motivo }, { ok: false, motivo: "ultimo_sync_falhou:timeout" });

const envFalhaNula = envFake({ ok: false, motivo: "timeout" }, undefined);
const rFalhaNula = await mod.avaliarFrescorCVM(envFalhaNula);
checa("sem data nenhuma reprova", { ok: rFalhaNula.ok, motivo: rFalhaNula.motivo }, { ok: false, motivo: "ultimo_sync_falhou:timeout" });

console.log("\n=== KV indisponivel ===");
const rSemKV = await mod.avaliarFrescorCVM({});
checa("sem binding de KV reprova", { ok: rSemKV.ok, motivo: rSemKV.motivo }, { ok: false, motivo: "kv_indisponivel" });

console.log("\n=== CVMFRESCOR1b: backfill a partir de cvm:documentos ===");

const envBackfillOk = envFake(undefined, [{ de: "2026-08-18" }]);
const rBackfillOk = await mod.avaliarFrescorCVM(envBackfillOk);
checa("sem meta mas com documentos de ontem, passa", { ok: rBackfillOk.ok, motivo: rBackfillOk.motivo }, { ok: true, motivo: "ok" });
checa("backfill gravou a meta uma vez", envBackfillOk._gravado.length, 1);
checa("backfill marcou a origem", envBackfillOk._gravado[0].v.origem, "backfill_documentos");
checa("backfill escreveu na chave certa", envBackfillOk._gravado[0].k, "cvm:fonte_meta");

const envBackfillVelho = envFake(undefined, [{ de: "2026-08-01" }]);
const rBackfillVelho = await mod.avaliarFrescorCVM(envBackfillVelho);
checa("backfill com documento de 18 dias atras (2 ciclos) reprova", { ok: rBackfillVelho.ok, motivo: rBackfillVelho.motivo }, { ok: false, motivo: "fonte_sem_publicar_ha_2_ciclos_semanais_18_dias" });

const envSemNada = envFake(undefined, undefined);
const rSemNada = await mod.avaliarFrescorCVM(envSemNada);
checa("sem meta e sem documentos continua fail-closed", { ok: rSemNada.ok, motivo: rSemNada.motivo }, { ok: false, motivo: "sem_meta" });
checa("fail-closed nao grava nada", envSemNada._gravado.length, 0);

const envComMeta = envFake({ ok: true, last_modified_iso: "2026-08-18" }, [{ de: "2026-08-01" }]);
const rComMeta = await mod.avaliarFrescorCVM(envComMeta);
checa("meta existente tem precedencia sobre o backfill", { ok: rComMeta.ok, motivo: rComMeta.motivo }, { ok: true, motivo: "ok" });
checa("com meta presente nao regrava", envComMeta._gravado.length, 0);

console.log("\n=== CVMDURA1: falha dura x cadencia normal ===");

const env404 = envFake({ ok: false, motivo: "http_404", last_modified_iso: "2026-08-18", falhas_consecutivas: 0 }, undefined);
const r404 = await mod.avaliarFrescorCVM(env404);
checa("http_404 e falha dura", r404.falha_dura, true);
checa("http_404 com 1 falha consecutiva nao degrada servico ainda (teto 4)", r404.degrada_servico, false);

const env404x4 = envFake({ ok: false, motivo: "http_404", last_modified_iso: "2026-08-18", falhas_consecutivas: 4 }, undefined);
const r404x4 = await mod.avaliarFrescorCVM(env404x4);
checa("4a falha http_404 consecutiva degrada servico", { falha_dura: r404x4.falha_dura, degrada_servico: r404x4.degrada_servico }, { falha_dura: true, degrada_servico: true });

const envCadencia = envFake({ ok: false, motivo: "sem_publicacao_na_janela", last_modified_iso: "2026-08-18", falhas_consecutivas: 9 }, undefined);
const rCadencia = await mod.avaliarFrescorCVM(envCadencia);
checa("motivo de cadencia (nao dos duros) nunca degrada servico mesmo com muitas falhas", { falha_dura: rCadencia.falha_dura, degrada_servico: rCadencia.degrada_servico }, { falha_dura: false, degrada_servico: false });

console.log("\n" + (falhas === 0 ? "TUDO VERDE" : (falhas + " FALHA(S)")) + " em " + total + " casos.");
process.exit(falhas === 0 ? 0 : 1);
