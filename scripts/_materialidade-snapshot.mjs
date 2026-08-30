// Harness de snapshot do ranking de materialidade (Fase 1.2, MATERIALSAT1).
//
// Uso: SNAP_OUT=<out-ranking.json> node scripts/_materialidade-snapshot.mjs
//
// 1) Strip dos estados crus (test/_rawstate/*.json, baixados do KV de producao
//    29/08/2026) para test/fixtures/materialidade-estado-2026-W3x.json. O
//    estado de entrada fica fixo e versionado.
// 2) Ranking completo via modulo comum (test/_materialidade-common.mjs), com a
//    mescla e o enriquecerEvento reais do worker, gravado em SNAP_OUT.
//
// O snapshot "before" roda com o codigo pre-recalibracao; o "after" depois. O
// diff entre eles e o aceite da Fase 1.2. O teste permanente compara o ranking
// do harness com o after gravado, travando a recalibracao.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { rankingCompleto } from "../api/test/_materialidade-common.mjs";

// ATENCAO: importar o worker limpa `process.argv` (efeito colateral do modulo,
// medido 29/08). O target do ranking vem de SNAP_OUT, nunca de argv.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const RAW = path.join(ROOT, "api", "test", "_rawstate");
const FIX = path.join(ROOT, "api", "test", "fixtures");
const WEEKS = ["2026-W31", "2026-W32", "2026-W33", "2026-W34", "2026-W35"];

// Campos que a cadeia materialidade consome. Qualquer coisa fora disto e
// ignorada no ranking; manter so isto mantem o fixture enxuto (3,5MB -> ~0,8MB)
// e trava o que o harness precisa.
const EV_KEEP = [
  "titulo", "data_evento", "fonte_primaria", "classificacao",
  "tags", "impacto_credito", "_confianca", "empresa"
];
const RES_KEEP = [
  "setor", "eventos", "_last_scanned_at", "timestamp",
  "_status", "_motivo", "_token_cap_deferred", "sem_eventos",
  "cobertura_nota", "memo_conviccao", "memo_acontecimento",
  "memo_relevancia", "memo_acao"
];

function stripEstado(raw) {
  const out = { week: raw.week, updated_at: raw.updated_at, results: {} };
  for (const [emp, res] of Object.entries(raw.results || {})) {
    const r2 = {};
    for (const k of RES_KEEP) if (res[k] !== undefined) r2[k] = res[k];
    if (Array.isArray(res.eventos)) {
      r2.eventos = res.eventos.map((ev) => {
        const e2 = {};
        for (const k of EV_KEEP) if (ev[k] !== undefined) e2[k] = ev[k];
        return e2;
      });
    }
    out.results[emp] = r2;
  }
  return out;
}

// strip dos estados (idempotente). So roda quando o estado cru ainda esta em
// _rawstate. Com _rawstate removido (estados de entrada ja versionados em
// fixtures), o strip pula e o ranking regenera direto dos fixtures.
if (fs.existsSync(RAW)) {
  for (const w of WEEKS) {
    const raw = JSON.parse(fs.readFileSync(path.join(RAW, `${w}.json`), "utf8"));
    const stripped = stripEstado(raw);
    const out = path.join(FIX, `materialidade-estado-${w}.json`);
    fs.writeFileSync(out, JSON.stringify(stripped), "utf8");
    const nEv = Object.values(stripped.results).reduce((s, r) => s + (r.eventos ? r.eventos.length : 0), 0);
    console.log(`strip ${w}: ${Object.keys(stripped.results).length} emissores, ${nEv} eventos, ${out} (${fs.statSync(out).size} bytes)`);
  }
} else {
  console.log(`pula strip: ${RAW} ausente, fixtures de estado ja versionadas.`);
}

const target = process.env.SNAP_OUT;
if (!target) {
  console.log("uso: SNAP_OUT=<out-ranking.json> node scripts/_materialidade-snapshot.mjs");
  process.exit(1);
}

const kvMap = {};
for (const w of WEEKS) {
  kvMap[`radar:estado:${w}`] = fs.readFileSync(path.join(FIX, `materialidade-estado-${w}.json`), "utf8");
}
const ranking = await rankingCompleto(kvMap);
const saturados = ranking.filter((e) => e.materialidade >= 100);
fs.writeFileSync(target, JSON.stringify(ranking, null, 1), "utf8");
console.log(`ranking completo: ${ranking.length} eventos, ${saturados.length} saturados em 100.`);
console.log(`gravado em ${target}`);
