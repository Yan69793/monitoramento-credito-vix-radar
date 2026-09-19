// CVMFRESCOR1 (2026-08-19) - harness local do calculo de frescor da fonte CVM.
//
// Existe para cobrir a parte puramente algoritmica (contagem de dias uteis e de
// dias corridos + decisao de frescor) em Node cru, sem subir Worker nenhum. A
// premissa original, de que o vitest nao rodava local porque o Smart App Control
// bloqueava workerd.exe por assinatura (CodeIntegrity 3077/3033), foi refutada
// por medicao em 20/08/2026 (VerifiedAndReputablePolicyState=0, nenhum evento
// CodeIntegrity cita workerd). A causa real de o vitest nao rodar local apos o
// deploy e `npm ci --omit=dev` apagando as devDeps. O script foi mantido mesmo
// assim porque garante o calculo em qualquer node: a premissa nasceu errada,
// o arquivo nao.
//
// Regra de ouro herdada do test-dedup-eventos.mjs: extrair as funcoes DIRETO do
// worker.js real, nunca reescrever uma copia. Copia solta passa verde enquanto o
// codigo de producao regride. Desde o HARNESSMORTO1 isso vale tambem para as
// constantes de decisao: o unico stub e o relogio, porque fixar o dia e
// requisito do teste, nao copia de logica.
//
// HARNESSMORTO1 (2026-09-19). De 20/08 a 19/09 este script saiu com exit 1 em
// TODA execucao e ninguem viu. O CVMCADENCIA1 (73c3a5d, 20/08) trocou a regua de
// 2 dias uteis por 2 ciclos semanais: avaliarFrescorCVM passou a depender de
// _cvmDiasCorridosApos, _cvmProximaPublicacaoPrevista e de constantes novas, e a
// lista de extracao daqui nao acompanhou. Medido por execucao commit a commit: o
// pai a4a0b47 passa 31/31 e o proprio 73c3a5d ja morre no ReferenceError. Nada
// acusou porque gate nenhum roda .mjs, o run-all-tests.ps1 so enumera
// scripts/test-*.ps1. Duas guardas nasceram dai:
//   1. antes de rodar caso nenhum, toda referencia do codigo extraido a uma
//      declaracao de topo do worker.js tem que estar extraida ou no preludio.
//      Faltando uma, o script sai dizendo quem usa, o que falta e em que linha
//      do worker.js aquilo mora;
//   2. scripts/test-frescor-cvm.ps1 poe este arquivo no gate scripts-tests.yml.
//
// Uso: node scripts/test-frescor-cvm.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const src = fs.readFileSync(path.join(raiz, "api", "src", "worker.js"), "utf8");
const linhasWorker = src.split(/\r?\n/);

// Indice das declaracoes de TOPO do worker.js (coluna zero), nome -> linhas onde
// aparecem. E a regua da guarda de dependencia: nome que o codigo extraido usa e
// que mora aqui e dependencia de verdade; o resto e global do JS ou variavel
// local, e nao precisa de extracao.
const RE_DECL_TOPO = /^(?:export\s+(?:default\s+)?)?(?:async\s+)?(?:function(?:\s*\*\s*|\s+)|class\s+|(?:var|let|const)\s+)([A-Za-z_$][\w$]*)/;
const declaracoesTopo = new Map();
for (let i = 0; i < linhasWorker.length; i++) {
  const m = RE_DECL_TOPO.exec(linhasWorker[i]);
  if (!m) continue;
  if (!declaracoesTopo.has(m[1])) declaracoesTopo.set(m[1], []);
  declaracoesTopo.get(m[1]).push(i + 1);
}

function extrair(nome, tipo) {
  const marca = (tipo === "async" ? "async function " : "function ") + nome + "(";
  const ini = src.indexOf(marca);
  if (ini < 0) throw new Error("nao achei a funcao " + nome + " em api/src/worker.js");
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

// Constante de decisao sai do worker.js igual funcao. Antes CVM_FONTE_META_KEY e
// CVM_FONTE_MAX_DU eram copiadas no preludio a mao, e a segunda sobreviveu aqui
// um mes depois de o Worker ter deixado de te-la (CVMCADENCIA1 aposentou a regua
// de dias uteis). Constante copiada e copia de logica pela porta dos fundos:
// muda o limite em producao e o teste segue verde com o numero velho.
function extrairVar(nome) {
  const achadas = [];
  const re = new RegExp("^(?:var|let|const)\\s+" + nome + "\\s*=");
  for (let i = 0; i < linhasWorker.length; i++) {
    if (re.test(linhasWorker[i])) achadas.push(i);
  }
  if (achadas.length === 0) throw new Error("nao achei a constante " + nome + " em api/src/worker.js");
  if (achadas.length > 1) {
    throw new Error("constante " + nome + " declarada " + achadas.length + "x no topo (linhas " + achadas.map((n) => n + 1).join(", ") + "), extracao ambigua");
  }
  const texto = linhasWorker[achadas[0]];
  try {
    new Function(texto);
  } catch (e) {
    throw new Error("a declaracao de " + nome + " (api/src/worker.js:" + (achadas[0] + 1) + ") nao fecha em uma linha so, estender o extrator: " + e.message);
  }
  return texto;
}

// --- guarda de dependencia (HARNESSMORTO1) ---------------------------------
// Varre o codigo extraido atras de identificador livre. Tira comentario, string,
// template e regex literal antes de olhar, senao palavra dentro de comentario ou
// de mensagem de erro viraria dependencia inventada. O miolo de ${...} num
// template volta a ser codigo, porque la dentro pode haver chamada de verdade.
const PALAVRAS_ANTES_DE_REGEX = new Set([
  "return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await"
]);

function regexPodeComecar(feito) {
  const m = /(\S)\s*$/.exec(feito);
  if (!m) return true;
  const c = m[1];
  if (c === ")" || c === "]") return false;
  if (/[\w$]/.test(c)) {
    const p = /([\w$]+)\s*$/.exec(feito);
    return !!p && PALAVRAS_ANTES_DE_REGEX.has(p[1]);
  }
  return true;
}

function soCodigo(s) {
  let out = "";
  let i = 0;
  const n = s.length;
  while (i < n) {
    const c = s[i];
    const d = s[i + 1];
    if (c === "/" && d === "/") {
      while (i < n && s[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && d === "*") {
      const f = s.indexOf("*/", i + 2);
      i = f < 0 ? n : f + 2;
      out += " ";
      continue;
    }
    if (c === '"' || c === "'") {
      i++;
      while (i < n && s[i] !== c) {
        if (s[i] === "\\") i++;
        i++;
      }
      i++;
      out += "0";
      continue;
    }
    if (c === "`") {
      i++;
      while (i < n && s[i] !== "`") {
        if (s[i] === "\\") {
          i += 2;
          continue;
        }
        if (s[i] === "$" && s[i + 1] === "{") {
          let prof = 1;
          let j = i + 2;
          while (j < n && prof > 0) {
            if (s[j] === "{") prof++;
            else if (s[j] === "}") prof--;
            j++;
          }
          out += " " + soCodigo(s.slice(i + 2, j - 1)) + " ";
          i = j;
          continue;
        }
        i++;
      }
      i++;
      out += "0";
      continue;
    }
    if (c === "/" && regexPodeComecar(out)) {
      i++;
      let classe = false;
      while (i < n) {
        const r = s[i];
        if (r === "\\") {
          i += 2;
          continue;
        }
        if (r === "\n") break;
        if (classe) {
          if (r === "]") classe = false;
        } else if (r === "[") {
          classe = true;
        } else if (r === "/") {
          break;
        }
        i++;
      }
      i++;
      while (i < n && /[a-z]/i.test(s[i])) i++;
      out += "0";
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function referenciasEm(codigo) {
  const c = soCodigo(codigo);
  const ids = new Set();
  const re = /[A-Za-z_$][\w$]*/g;
  let m;
  while ((m = re.exec(c)) !== null) {
    // Miolo de numero (864e5 -> "e5") e continuacao de palavra nunca sao nome.
    if (m.index > 0 && /[\w$]/.test(c[m.index - 1])) continue;
    let k = m.index - 1;
    while (k >= 0 && /\s/.test(c[k])) k--;
    // Acesso a propriedade (obj.nome) nao e referencia livre; spread (...nome) e.
    if (k >= 0 && c[k] === "." && !(k >= 2 && c[k - 1] === "." && c[k - 2] === ".")) continue;
    ids.add(m[0]);
  }
  return ids;
}

function declaradosEm(codigo) {
  const c = soCodigo(codigo);
  const nomes = new Set();
  let m;
  const reVar = /\b(?:var|let|const)\s+([A-Za-z_$][\w$]*)/g;
  while ((m = reVar.exec(c)) !== null) nomes.add(m[1]);
  const reFn = /\bfunction\b\s*\*?\s*([A-Za-z_$][\w$]*)?\s*\(([^)]*)\)/g;
  while ((m = reFn.exec(c)) !== null) {
    if (m[1]) nomes.add(m[1]);
    for (const p of m[2].split(",")) {
      const id = /([A-Za-z_$][\w$]*)/.exec(p.replace(/\.\.\./g, "").split("=")[0] || "");
      if (id) nomes.add(id[1]);
    }
  }
  const reCatch = /\bcatch\s*\(\s*([A-Za-z_$][\w$]*)/g;
  while ((m = reCatch.exec(c)) !== null) nomes.add(m[1]);
  const reSeta = /\(([^()]*)\)\s*=>|\b([A-Za-z_$][\w$]*)\s*=>/g;
  while ((m = reSeta.exec(c)) !== null) {
    if (m[2]) nomes.add(m[2]);
    if (m[1]) {
      for (const p of m[1].split(",")) {
        const id = /([A-Za-z_$][\w$]*)/.exec(p.replace(/\.\.\./g, "").split("=")[0] || "");
        if (id) nomes.add(id[1]);
      }
    }
  }
  return nomes;
}

// --- o que sai do worker.js -------------------------------------------------
const FUNCOES = [
  ["_cvmDiasUteisApos", "sync"],
  ["_cvmDiasCorridosApos", "sync"],
  ["_cvmProximaPublicacaoPrevista", "sync"],
  ["_cvmMaxDataEntrega", "sync"],
  ["gravarFonteCVMMeta", "async"],
  ["avaliarFrescorCVM", "async"]
];
const CONSTANTES = [
  "CVM_FONTE_META_KEY",
  "CVM_FONTE_CICLO_DIAS",
  "CVM_FONTE_MAX_CICLOS",
  "CVM_FONTE_MAX_FALHAS",
  "CVM_FONTE_MOTIVOS_DUROS",
  "CVM_FONTE_DOW_PUBLICACAO"
];

// Unico stub deliberado: o relogio, que o teste precisa fixar.
const preludio = `
var __HOJE_FAKE = null;
function obterAgoraBRT() { return new Date(__HOJE_FAKE); }
`;

const unidades = [];
try {
  for (const [nome, tipo] of FUNCOES) unidades.push({ nome: nome, codigo: extrair(nome, tipo) });
  for (const nome of CONSTANTES) unidades.push({ nome: nome, codigo: extrairVar(nome) });
} catch (e) {
  console.log("FALHA extracao: " + e.message);
  console.log("\nEXTRACAO INCOMPLETA: nenhum caso rodou.\n");
  process.exit(1);
}

const fornecidos = new Set(unidades.map((u) => u.nome));
for (const n of declaradosEm(preludio)) fornecidos.add(n);
const faltando = [];
for (const u of unidades) {
  const locais = declaradosEm(u.codigo);
  for (const id of referenciasEm(u.codigo)) {
    if (fornecidos.has(id) || locais.has(id) || !declaracoesTopo.has(id)) continue;
    faltando.push({ quem: u.nome, dep: id, linha: declaracoesTopo.get(id)[0] });
  }
}
if (faltando.length > 0) {
  for (const f of faltando) {
    console.log("FALHA extracao: " + f.quem + " usa " + f.dep + " (api/src/worker.js:" + f.linha + "), que nao esta na lista de extracao nem no preludio");
  }
  console.log("\nEXTRACAO INCOMPLETA: " + faltando.length + " dependencia(s) fora da lista, nenhum caso rodou.");
  console.log("Acrescente cada uma em FUNCOES ou CONSTANTES no topo deste arquivo, nunca uma copia da funcao.\n");
  process.exit(1);
}

const mod = new Function(
  preludio +
    unidades.map((u) => u.codigo).join("\n\n") +
    "\nreturn { " + FUNCOES.map((f) => f[0]).join(", ") + ", setHoje: function(d){ __HOJE_FAKE = d; } };"
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

console.log("\n=== contagem de dias corridos (unidade do ciclo semanal, CVMCADENCIA1) ===");
// Dia corrido nao pula fim de semana de proposito: o lote CIA_ABERTA/DOC roda
// justamente aos domingos, entao contar dia util subestimaria a idade da fonte.
checa("domingo 16 -> quarta 19 = 3 dias", mod._cvmDiasCorridosApos("2026-08-16", "2026-08-19"), 3);
checa("quarta 05 -> quarta 19 = 14 dias", mod._cvmDiasCorridosApos("2026-08-05", "2026-08-19"), 14);
checa("mesmo dia = 0 dia", mod._cvmDiasCorridosApos("2026-08-19", "2026-08-19"), 0);
checa("data futura nao vira negativo", mod._cvmDiasCorridosApos("2026-08-25", "2026-08-19"), 0);
checa("data invalida devolve null", mod._cvmDiasCorridosApos("lixo", "2026-08-19"), null);

console.log("\n=== proxima publicacao prevista (o lote da CVM roda domingo) ===");
checa("de domingo 16 projeta o domingo seguinte", mod._cvmProximaPublicacaoPrevista("2026-08-16"), "2026-08-23");
checa("de quarta 19 projeta domingo 23", mod._cvmProximaPublicacaoPrevista("2026-08-19"), "2026-08-23");
checa("data invalida devolve null", mod._cvmProximaPublicacaoPrevista("lixo"), null);

console.log("\n=== max data de entrega ===");
checa("pega o maior de", mod._cvmMaxDataEntrega([{ de: "2026-08-11" }, { de: "2026-08-16" }, { de: "2026-08-13" }]), "2026-08-16");
checa("cai para d quando nao ha de", mod._cvmMaxDataEntrega([{ d: "2026-08-12" }]), "2026-08-12");
checa("array vazio devolve null", mod._cvmMaxDataEntrega([]), null);
checa("nao-array devolve null", mod._cvmMaxDataEntrega(null), null);

console.log("\n=== decisao de frescor (hoje fixado em 2026-08-19, quarta) ===");
// DECISAO A (2c8acc6 + d392335, 13/09/2026): `ok` passou a seguir a ULTIMA
// ESCRITA, nao a idade. Sync que gravou direito mantem ok:true mesmo com a fonte
// vencida, e a idade vive em motivo, idade_dias e ciclos_perdidos. Os casos
// abaixo cobram o contrato como ele esta em producao e como a suite vitest
// (api/test/cvm-frescor.test.mjs) cobra. Ficam pinados de proposito: virar essa
// semantica de novo tem que quebrar teste, nao passar despercebido.
// Divergencia conhecida, registrada e NAO resolvida aqui: o CLAUDE.md do projeto
// ainda descreve a regra anterior ("fonte_externa_ok so vai a false depois de
// dois ciclos semanais perdidos") e o comentario da propria avaliarFrescorCVM
// ainda se anuncia fail-closed. Quem decide qual das duas vale e o operador.
mod.setHoje("2026-08-19T12:00:00Z");
const casos = [
  ["meta ausente e fail-closed", undefined, { ok: false, motivo: "sem_meta" }],
  ["fonte de ontem passa", { ok: true, last_modified_iso: "2026-08-18" }, { ok: true, motivo: "ok" }],
  ["fonte de segunda passa", { ok: true, last_modified_iso: "2026-08-17" }, { ok: true, motivo: "ok" }],
  // 16/08 e o caso do incidente que criou o CVMFRESCOR1 e reprovava pela regua de
  // 2 dias uteis. Com cadencia semanal ele passa: domingo e o dia de publicacao,
  // e a regua velha acendia o painel toda quarta sem nada ter acontecido.
  ["domingo 16 passa, publicacao semanal normal (CVMCADENCIA1)", { ok: true, last_modified_iso: "2026-08-16" }, { ok: true, motivo: "ok" }],
  // Fronteira da regra: 13 dias ainda e um ciclo perdido (feriado, remanejo,
  // atraso de lote), 14 sao dois ciclos e a fonte parou de verdade.
  ["06/08, 13 dias, 1 ciclo perdido, motivo segue ok", { ok: true, last_modified_iso: "2026-08-06" }, { ok: true, motivo: "ok" }],
  ["05/08, 14 dias, 2 ciclos perdidos, motivo acusa a parada", { ok: true, last_modified_iso: "2026-08-05" }, { ok: true, motivo: "fonte_sem_publicar_ha_2_ciclos_semanais_14_dias" }],
  ["ultimo sync falhou reprova mesmo com data de hoje", { ok: false, motivo: "nao_e_deflate", last_modified_iso: "2026-08-19" }, { ok: false, motivo: "ultimo_sync_falhou:nao_e_deflate" }],
  ["sem data nenhuma acusa no motivo", { ok: true }, { ok: true, motivo: "sem_data_de_referencia" }],
  ["fallback para max_data_entrega quando falta o header", { ok: true, max_data_entrega: "2026-08-18" }, { ok: true, motivo: "ok" }],
];
for (const [titulo, meta, esperado] of casos) {
  const r = await mod.avaliarFrescorCVM(envFake(meta));
  checa(titulo, { ok: r.ok, motivo: r.motivo }, esperado);
}

console.log("\n=== idade e ciclo no payload (o sinal acionavel depois da DECISAO A) ===");
const rCiclo2 = await mod.avaliarFrescorCVM(envFake({ ok: true, last_modified_iso: "2026-08-05" }));
checa("14 dias contam 2 ciclos perdidos, cadencia semanal", { dias: rCiclo2.idade_dias, ciclos: rCiclo2.ciclos_perdidos, cadencia: rCiclo2.cadencia }, { dias: 14, ciclos: 2, cadencia: "semanal" });
checa("e projeta a publicacao seguinte a partir da ultima", rCiclo2.proxima_prevista, "2026-08-09");
const rCiclo1 = await mod.avaliarFrescorCVM(envFake({ ok: true, last_modified_iso: "2026-08-06" }));
checa("13 dias contam 1 ciclo perdido", { dias: rCiclo1.idade_dias, ciclos: rCiclo1.ciclos_perdidos }, { dias: 13, ciclos: 1 });
// idade_du fica no payload por compatibilidade: watch-vixradar-health.ps1,
// deploy-worker.ps1 e o log das rotinas imprimem esse campo.
checa("idade_du continua no payload para quem ja imprime o campo", rCiclo1.idade_du, 9);

console.log("\n=== falha dura da fonte, separada de cadencia (CVMDURA1) ===");
const rDura3 = await mod.avaliarFrescorCVM(envFake({ ok: false, motivo: "http_404", falhas_consecutivas: 3, last_modified_iso: "2026-08-16" }));
checa("404 com 3 falhas marca falha dura sem degradar o servico", { ok: rDura3.ok, dura: rDura3.falha_dura, degrada: rDura3.degrada_servico, dias: rDura3.idade_dias }, { ok: false, dura: true, degrada: false, dias: 3 });
const rDura4 = await mod.avaliarFrescorCVM(envFake({ ok: false, motivo: "http_404", falhas_consecutivas: 4, last_modified_iso: "2026-08-16" }));
checa("na 4a falha seguida escala para degradacao de servico", { dura: rDura4.falha_dura, degrada: rDura4.degrada_servico }, { dura: true, degrada: true });
const rMole = await mod.avaliarFrescorCVM(envFake({ ok: false, motivo: "sem_data_de_referencia", falhas_consecutivas: 9, last_modified_iso: "2026-08-16" }));
checa("motivo que nao e duro nunca escala, por mais que repita", { dura: rMole.falha_dura, degrada: rMole.degrada_servico }, { dura: false, degrada: false });

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

const envBackfillVelho = envFake(undefined, [{ de: "2026-08-05" }]);
const rBackfillVelho = await mod.avaliarFrescorCVM(envBackfillVelho);
checa("backfill de documento com 14 dias acusa a parada, nao mascara", { ok: rBackfillVelho.ok, motivo: rBackfillVelho.motivo }, { ok: true, motivo: "fonte_sem_publicar_ha_2_ciclos_semanais_14_dias" });

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
