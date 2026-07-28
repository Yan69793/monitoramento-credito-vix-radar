import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.join(here, "../api/src/worker.js"), "utf8");

function functionSource(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notEqual(start, -1, `funcao ausente: ${name}`);
  const next = source.indexOf("\nfunction ", start + 1);
  assert.notEqual(next, -1, `limite ausente: ${name}`);
  const block = source.slice(start, next);
  const metadata = block.indexOf("\n__name(");
  return metadata >= 0 ? block.slice(0, metadata) : block;
}

const context = {
  CALENDARIO_RESULTADOS_V1: {
    emissores: {
      Bradesco: { trimestres: [
        { periodo: "2T26", data_prevista: "2026-05-07", status: "estimado", fonte: "estimado_historico" }
      ] }
    }
  },
  obterAgoraBRT: () => new Date("2026-07-28T12:00:00Z"),
  __name: () => {}
};
vm.createContext(context);
for (const name of ["mergeTrimestresCalendario", "obterTrimestresEmpresaSync", "obterTrimestresEmpresaMergedSync", "obterCalendarioEmpresa"]) {
  vm.runInContext(functionSource(name), context);
}
const overrides = { emissores: { Bradesco: { trimestres: [
  { periodo: "2T26", data_prevista: "2026-08-05", status: "agendado", fonte: "https://ri.bradesco/" }
] } } };
const calendar = context.obterCalendarioEmpresa("Bradesco", overrides);
assert.equal(calendar.proxima_divulgacao.data_prevista, "2026-08-05");
assert.equal(calendar.proxima_divulgacao.status, "agendado");
assert.equal(calendar.proxima_divulgacao.fonte, "https://ri.bradesco/");

assert.match(source, /volatilidadeKV\.selic_fonte === "BCB_SGS_1178"/);
assert.match(source, /selicAgeDays >= -1 && selicAgeDays <= 10/);
assert.match(source, /const selicAnual = selicFresh/);
assert.doesNotMatch(source, /0\.1375|SELIC a 15%/);
assert.doesNotMatch(source, /market_cap\s*>\s*100/);
assert.doesNotMatch(source, /patrimonio_liquido[^\n]{0,200}mktCap|mktCap[^\n]{0,200}patrimonio_liquido/);
assert.match(source, /obterCalendarioEmpresa\(emp, _calOverridesState\)/);
assert.match(source, /obterCalendarioEmpresa\(_calEmp, _calOverridesOp\)/);
assert.equal((source.match(/__WORKER_VERSION__/g) || []).length, 1);
assert.doesNotMatch(source, /sourceMappingURL=/);
console.log("REGRESSION_OK calendario_overrides merton_inputs selic_source build_contract");