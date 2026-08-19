// CVMFRESCOR1 (2026-08-19) - harness local do calculo de frescor da fonte CVM.
//
// Existe porque a suite vitest NAO roda nesta maquina: o Smart App Control
// bloqueia workerd.exe por assinatura (CodeIntegrity 3077/3033), entao
// api/test/cvm-frescor.test.mjs so e confiavel no CI. Este script cobre a parte
// puramente algoritmica (contagem de dias uteis + decisao de frescor) sem
// precisar subir Worker nenhum, e roda em qualquer node.
//
// Regra de ouro herdada do test-dedup-eventos.mjs: extrair as funcoes DIRETO do
// worker.js real, nunca reescrever uma copia. Copia solta passa verde enquanto o
// codigo de producao regride.
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
  extrair("_cvmMaxDataEntrega", "sync"),
  extrair("gravarFonteCVMMeta", "async"),
  extrair("avaliarFrescorCVM", "async"),
].join("\n\n");

// Constantes e dependencia que as funcoes esperam encontrar no escopo do Worker.
const preludio = `
var CVM_FONTE_META_KEY = "cvm:fonte_meta";
var CVM_FONTE_MAX_DU = 2;
var __HOJE_FAKE = null;
function obterAgoraBRT() { return new Date(__HOJE_FAKE); }
`;

const mod = new Function(
  preludio + fonte + "\nreturn { _cvmDiasUteisApos, _cvmMaxDataEntrega, gravarFonteCVMMeta, avaliarFrescorCVM, setHoje: function(d){ __HOJE_FAKE = d; } };"
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

console.log("\n=== decisao de frescor (hoje fixado em 2026-08-19, quarta) ===");
mod.setHoje("2026-08-19T12:00:00Z");
const casos = [
  ["meta ausente e fail-closed", undefined, { ok: false, motivo: "sem_meta" }],
  ["fonte de ontem passa", { ok: true, last_modified_iso: "2026-08-18" }, { ok: true, motivo: "ok" }],
  ["fonte de segunda passa no limite (2 du)", { ok: true, last_modified_iso: "2026-08-17" }, { ok: true, motivo: "ok" }],
  ["o caso real do incidente, domingo 16, reprova", { ok: true, last_modified_iso: "2026-08-16" }, { ok: false, motivo: "fonte_parada_ha_3_dias_uteis" }],
  // sexta 14 tambem da 3 du, nao 4: 15 e 16 sao fim de semana e nao contam.
  ["sexta 14 reprova (3 du, sabado e domingo nao contam)", { ok: true, last_modified_iso: "2026-08-14" }, { ok: false, motivo: "fonte_parada_ha_3_dias_uteis" }],
  ["quinta 13 reprova (4 du)", { ok: true, last_modified_iso: "2026-08-13" }, { ok: false, motivo: "fonte_parada_ha_4_dias_uteis" }],
  ["ultimo sync falhou reprova mesmo com data de hoje", { ok: false, motivo: "nao_e_deflate", last_modified_iso: "2026-08-19" }, { ok: false, motivo: "ultimo_sync_falhou:nao_e_deflate" }],
  ["sem data nenhuma reprova", { ok: true }, { ok: false, motivo: "sem_data_de_referencia" }],
  ["fallback para max_data_entrega quando falta o header", { ok: true, max_data_entrega: "2026-08-18" }, { ok: true, motivo: "ok" }],
];
for (const [titulo, meta, esperado] of casos) {
  const r = await mod.avaliarFrescorCVM(envFake(meta));
  checa(titulo, { ok: r.ok, motivo: r.motivo }, esperado);
}

console.log("\n=== KV indisponivel ===");
const rSemKv = await mod.avaliarFrescorCVM({});
checa("sem binding de KV reprova", { ok: rSemKv.ok, motivo: rSemKv.motivo }, { ok: false, motivo: "kv_indisponivel" });

console.log("\n=== CVMFRESCOR1b: backfill a partir de cvm:documentos ===");
// Sem meta mas COM documentos, deriva a idade em vez de acusar sem_meta. Isto
// existe para que deploy novo nao produza 12h de alarme falso ate o cron rodar.
const envBackfillFresco = envFake(undefined, [{ de: "2026-08-18" }, { de: "2026-08-11" }]);
const rBackfillFresco = await mod.avaliarFrescorCVM(envBackfillFresco);
checa("sem meta mas com documentos de ontem, passa", { ok: rBackfillFresco.ok, motivo: rBackfillFresco.motivo }, { ok: true, motivo: "ok" });
checa("backfill gravou a meta uma vez", envBackfillFresco._gravado.length, 1);
checa("backfill marcou a origem", envBackfillFresco._gravado[0] && envBackfillFresco._gravado[0].v.origem, "backfill_documentos");
checa("backfill escreveu na chave certa", envBackfillFresco._gravado[0] && envBackfillFresco._gravado[0].k, "cvm:fonte_meta");

const envBackfillVelho = envFake(undefined, [{ de: "2026-08-15" }]);
const rBackfillVelho = await mod.avaliarFrescorCVM(envBackfillVelho);
checa("o caso real de hoje via backfill, sabado 15, reprova", { ok: rBackfillVelho.ok, motivo: rBackfillVelho.motivo }, { ok: false, motivo: "fonte_parada_ha_3_dias_uteis" });

const envSemNada = envFake(undefined, []);
const rSemNada = await mod.avaliarFrescorCVM(envSemNada);
checa("sem meta e sem documentos continua fail-closed", { ok: rSemNada.ok, motivo: rSemNada.motivo }, { ok: false, motivo: "sem_meta" });
checa("fail-closed nao grava nada", envSemNada._gravado.length, 0);

// Meta existente tem que ganhar do backfill, senao o sinal fraco sobrescreveria
// o Last-Modified autoritativo do servidor da CVM a cada leitura de health.
const envMetaVence = envFake({ ok: true, last_modified_iso: "2026-08-18" }, [{ de: "2026-01-01" }]);
const rMetaVence = await mod.avaliarFrescorCVM(envMetaVence);
checa("meta existente tem precedencia sobre o backfill", { ok: rMetaVence.ok, motivo: rMetaVence.motivo }, { ok: true, motivo: "ok" });
checa("com meta presente nao regrava", envMetaVence._gravado.length, 0);

console.log("\n" + (falhas === 0 ? "TUDO VERDE" : falhas + " FALHA(S)") + " em " + total + " casos.\n");
process.exit(falhas === 0 ? 0 : 1);
