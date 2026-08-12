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
  AGENDA_ALIASES: { "AXIA Energia": "Eletrobras" },
  EMISSORES_LISTA: ["Eletrobras", "Bradesco", "Petrobras"],
  CALVAL_FONTES_SECUNDARIAS: [
    "infomoney.com.br", "moneytimes.com.br", "advfn.com", "xpi.com.br",
    "conteudos.xpi.com.br", "btgpactual.com", "bb.com.br", "investidor10.com.br",
    "statusinvest.com.br", "fundamentus.com.br", "suno.com.br", "einvestidor.estadao.com.br"
  ],
  obterAgoraBRT: () => new Date("2026-07-28T12:00:00Z"),
  console,
  URL,
  Date,
  __name: () => {}
};
vm.createContext(context);
for (const name of [
  "mergeTrimestresCalendario",
  "_agendaSlug",
  "_agendaExtrairDominio",
  "classificarTierFonte",
  "_calvalTemFonteOficial",
  "_calvalContarFontesSecundarias",
  "calcularStatusValidacaoTrimestre",
  "migrarTrimestreParaV2",
  "registrarAuditoriaMudancaData",
  "_calvalAppendAuditoria",
  "aplicarRegraNaoSobrescrever",
  "mergeTrimestresCalendarioValidado",
  "resolverAliasAgenda",
  "_agendaMatchEmissorPorRazao",
  "_agendaParseVencimentoDate",
  "cvmDocConfirmaDivulgacao",
  "obterTrimestresEmpresaSync",
  "obterTrimestresEmpresaMergedSync",
  "obterCalendarioEmpresa"
]) {
  vm.runInContext(functionSource(name), context);
}

// ── Asserts pre-existentes (contrato do calendario) ─────────────────────────
const overrides = { emissores: { Bradesco: { trimestres: [
  { periodo: "2T26", data_prevista: "2026-08-05", status: "agendado", fonte: "https://ri.bradesco/" }
] } } };
const calendar = context.obterCalendarioEmpresa("Bradesco", overrides);
assert.equal(calendar.proxima_divulgacao.data_prevista, "2026-08-05");
assert.equal(calendar.proxima_divulgacao.status, "agendado");
assert.equal(calendar.proxima_divulgacao.fonte, "https://ri.bradesco/");
// override oficial segue confirmado na leitura (CALVAL-V2)
assert.equal(calendar.proxima_divulgacao.status_validacao, "CONFIRMADO_OFICIAL");

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

// ── CALVAL-V2: classificacao de tier de fonte ───────────────────────────────
assert.equal(context.classificarTierFonte("https://ri.petrobras.com.br/x", "Petrobras"), "ri");
assert.equal(context.classificarTierFonte("https://www.rad.cvm.gov.br/x", "Petrobras"), "cvm");
assert.equal(context.classificarTierFonte("https://www.b3.com.br/pt_br/x", "Petrobras"), "b3");
assert.equal(context.classificarTierFonte("https://www2.gerdau.com.br/ri/x", "Gerdau"), "corporativo");
assert.equal(context.classificarTierFonte("https://www.infomoney.com.br/x", "Petrobras"), "secundario");
assert.equal(context.classificarTierFonte("estimado_historico", "Petrobras"), "nenhum");
assert.equal(context.classificarTierFonte("", "Petrobras"), "nenhum");
assert.equal(context.classificarTierFonte("https://site-desconhecido.com/x", "Petrobras"), "secundario");

// ── CALVAL-V2: migracao de trimestre legado ─────────────────────────────────
const migr = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-07-28", status: "estimado", fonte: "estimado_historico" },
  "2026-08-12", "Bradesco"
);
assert.equal(migr.status_validacao, "PENDENTE");
assert.equal(migr.nivel_confianca, "baixa");
assert.equal(migr.fonte_primaria, null);
assert.equal(migr.url_fonte_primaria, null);
assert.equal(migr.data_ultima_verificacao, "2026-08-12");

// ── CALVAL-V2: oficial nunca e sobrescrita por secundaria divergente ────────
const atualOficial = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-05", status: "agendado", fonte: "https://ri.bradesco/", url_fonte_primaria: "https://ri.bradesco/" },
  null, "Bradesco"
);
assert.equal(atualOficial.status_validacao, "CONFIRMADO_OFICIAL");
const novoSec = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-07", status: "agendado", fonte: "https://www.infomoney.com.br/x" },
  "2026-08-12", "Bradesco"
);
const protegido = context.aplicarRegraNaoSobrescrever(atualOficial, novoSec);
assert.equal(protegido.data_prevista, "2026-08-05");
assert.equal(protegido.status_validacao, "DIVERGENTE");
assert.ok(protegido.observacao_divergencia);
assert.equal(protegido.divergencias[0].data_alternativa, "2026-08-07");
assert.equal(protegido.auditoria[0].motivo, "divergencia_ignorada");

// ── CALVAL-V2: alteracao posterior pelo RI vence e gera auditoria ───────────
const novoRi = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-10", status: "agendado", fonte: "https://ri.bradesco/", url_fonte_primaria: "https://ri.bradesco/" },
  "2026-08-12", "Bradesco"
);
const mudado = context.aplicarRegraNaoSobrescrever(atualOficial, novoRi);
assert.equal(mudado.data_prevista, "2026-08-10");
assert.equal(mudado.status_validacao, "CONFIRMADO_OFICIAL");
assert.equal(mudado.auditoria[0].motivo, "correcao_ri");
assert.equal(mudado.auditoria[0].data_anterior, "2026-08-05");
assert.equal(mudado.auditoria[0].data_nova, "2026-08-10");
assert.ok(mudado.auditoria[0].timestamp);

// ── CALVAL-V2: NAO_INFORMADO nunca apaga data ja conhecida ──────────────────
const semData = context.migrarTrimestreParaV2({ periodo: "2T26" }, "2026-08-12", "Bradesco");
assert.equal(semData.status_validacao, "NAO_INFORMADO");
assert.equal(context.aplicarRegraNaoSobrescrever(atualOficial, semData).data_prevista, "2026-08-05");

// ── CALVAL-V2: trimestre fiscal verbatim, sem conversao ─────────────────────
const fiscal = context.migrarTrimestreParaV2(
  { periodo: "3T25F", data_prevista: "2026-09-15", status: "agendado", fonte: "https://ri.bradesco/", trimestre_fiscal: true },
  "2026-08-12", "Bradesco"
);
assert.equal(fiscal.periodo, "3T25F");
assert.equal(fiscal.trimestre_fiscal, true);
assert.equal(fiscal.status_validacao, "CONFIRMADO_OFICIAL");

// ── CALVAL-V2: fonte secundaria unica nao vira cross-check (regressao CI 2) ─
const single = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-12", status: "agendado", fonte: "https://www.infomoney.com.br/x" },
  null, "Bradesco"
);
assert.equal(single.status_validacao, "PENDENTE");

// ── CALVAL-V2: cross-check (2 secundarias concordantes) ─────────────────────
const cross = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-12", status: "agendado",
    fonte: "https://www.infomoney.com.br/x",
    fontes_secundarias: [
      { fonte: "infomoney.com.br", url: "https://www.infomoney.com.br/x" },
      { fonte: "moneytimes.com.br", url: "https://www.moneytimes.com.br/y" }
    ] },
  null, "Bradesco"
);
assert.equal(cross.status_validacao, "CONFIRMADO_CROSSCHECK");

// ── CALVAL-V2: divergencia so entre secundarias -> PENDENTE ─────────────────
const divSec = context.migrarTrimestreParaV2(
  { periodo: "2T26", data_prevista: "2026-08-12", status: "agendado",
    fonte: "https://www.infomoney.com.br/x",
    divergencias: [{ fonte: "moneytimes.com.br", url: "u", data_alternativa: "2026-08-14" }] },
  null, "Bradesco"
);
assert.equal(divSec.status_validacao, "PENDENTE");

// ── CALVAL-V2: auditoria de mudanca de data ─────────────────────────────────
const reg = context.registrarAuditoriaMudancaData(
  { data_prevista: "2026-08-05" }, { data_prevista: "2026-08-10" }, "https://ri.bradesco/", "atualizacao_rotina"
);
assert.equal(reg.data_anterior, "2026-08-05");
assert.equal(reg.data_nova, "2026-08-10");
assert.equal(reg.fonte, "https://ri.bradesco/");
assert.equal(reg.motivo, "atualizacao_rotina");
assert.ok(reg.timestamp);
assert.equal(context.registrarAuditoriaMudancaData({ data_prevista: "x" }, { data_prevista: "x" }, "u", "atualizacao_rotina"), null);
assert.equal(context.registrarAuditoriaMudancaData({ data_prevista: "x" }, { data_prevista: "x" }, "u", "confirmacao_cvm").motivo, "confirmacao_cvm");

// ── CALVAL-V2: aliases de empresa renomeada ─────────────────────────────────
assert.equal(context.resolverAliasAgenda("AXIA Energia"), "Eletrobras");
assert.equal(context.resolverAliasAgenda("Eletrobras"), "Eletrobras");
assert.equal(context.resolverAliasAgenda(""), "");

// ── CALVAL-V2: confronto com publicacao efetiva no CVM ──────────────────────
const docItr = { c: "ITR", e: "Eletrobras", a: "ITR 2T26", d: "2026-08-12", l: "https://www.rad.cvm.gov.br/x" };
assert.equal(context.cvmDocConfirmaDivulgacao(docItr, "Eletrobras", "2026-08-08"), true);
assert.equal(context.cvmDocConfirmaDivulgacao(docItr, "Eletrobras", "2026-07-20"), false);
assert.equal(context.cvmDocConfirmaDivulgacao(docItr, "Bradesco", "2026-08-08"), false);
assert.equal(context.cvmDocConfirmaDivulgacao({ c: "ATA", e: "Eletrobras", d: "2026-08-12" }, "Eletrobras", "2026-08-08"), false);

console.log("REGRESSION_OK calendario_overrides calval_v2 merton_inputs selic_source build_contract");
