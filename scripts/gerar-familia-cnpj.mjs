#!/usr/bin/env node
// SUBSTRINGDONO1 / fase CNPJ (2026-08-25) — propoe o mapa CNPJ -> emissor.
//
// Por que existe. A atribuicao de documento da CVM vai deixar de casar por nome e
// passar a casar por CNPJ, que e o identificador que sobrevive a renomeacao. O
// arquivo ipe_cia_aberta ja traz CNPJ_Companhia na coluna 0 e o Worker nunca leu
// essa coluna. Mas so o CNPJ da holding nao basta: a subsidiaria protocola no CNPJ
// dela, e o documento dela e noticia de credito da holding. A CEMIG Distribuicao
// protocolou 36 documentos em 2026 e o mercado le isso como CEMIG.
//
// Entao existem duas tabelas com papeis diferentes, e confundi-las quebra os dois
// lados:
//   PRIMARIO  um CNPJ por emissor, a entidade consolidada que carrega a divida.
//             Alimenta ITR e balanco. Vive em scripts/emissores-cnpj.mjs
//             (EMISSOR_CNPJ, CURADORIA2). Tem que continuar unico: se a familia
//             vazar para ca, o card de alavancagem passa a ler o ITR da
//             distribuidora.
//   FAMILIA   muitos CNPJs por emissor, holding mais as subsidiarias que
//             protocolam. Alimenta a atribuicao de IPE. E o que este script propoe.
//
// Este script NAO decide nada. Ele le o acervo e propoe candidatos, cada um com o
// nome e a contagem de documentos, para revisao a mao. A saida revisada e que vai
// para o worker.js. Mesma disciplina do CURADORIA2: cada linha e uma decisao, e
// nada e inferido em runtime.
//
// Por que a proposta ainda usa o nome. E o unico sinal disponivel para adivinhar de
// quem e um CNPJ que ninguem declarou. A diferenca em relacao ao que havia antes e
// que aqui o nome so sugere, um humano confirma, e o resultado vira dado fixo. Em
// producao o nome deixa de decidir.
//
// Uso:
//   node scripts/gerar-familia-cnpj.mjs --snapshot caminho/ipe_cia_aberta_2026.csv
//       le o CSV da CVM, recorta a janela que o Worker usa e grava o snapshot
//       versionado em data/cvm/, para a guarda poder remedir sempre contra a mesma
//       base em vez do que a CVM estiver servindo no dia.
//
//   node scripts/gerar-familia-cnpj.mjs
//       le o snapshot mais recente de data/cvm/ e imprime os candidatos.
//
//   node scripts/gerar-familia-cnpj.mjs --json

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, statSync } from "node:fs";
import { gzipSync, gunzipSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
// NAO em data/cvm/, que esta no .gitignore de proposito para cache de CSV grande e
// regeneravel da CVM. Estes dois artefatos sao o oposto: pequenos, curados, e existem
// exatamente para NAO mudar com o que a CVM estiver servindo no dia. Base ignorada
// nao serve de referencia para guarda remedir.
const DIR_SNAP = join(RAIZ, "data", "cvm-referencia");
const JSON_OUT = process.argv.includes("--json");
const iSnap = process.argv.indexOf("--snapshot");
const CSV_ENTRADA = iSnap >= 0 ? process.argv[iSnap + 1] : null;

// A janela do syncCVMAutomatico: 35 dias para tras em Data_Entrega, e
// Data_Referencia dentro do mesmo intervalo, contada no relogio de Brasilia.
const DIAS_JANELA = 35;

function semAcentoUp(s) {
  return String(s || "").toUpperCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}
function soDigito(s) {
  return String(s || "").replace(/\D/g, "");
}
function formatarCnpj(d) {
  const x = soDigito(d).padStart(14, "0");
  return x.slice(0, 2) + "." + x.slice(2, 5) + "." + x.slice(5, 8) + "/" + x.slice(8, 12) + "-" + x.slice(12);
}
// O worker.js e um bundle com unicode escapado (\xE9).
function desescapar(s) {
  return s.replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
          .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

// ── Espelho do _donoDocumentoCVM do Worker ─────────────────────────────────
// Precisa ser o MESMO criterio. Guarda que julga por regra diferente da que roda
// em producao propoe candidato que o Worker nunca veria, e vice-versa.
function lerLista(src, nome) {
  const m = src.match(new RegExp("var " + nome + "\\s*=\\s*\\[([\\s\\S]*?)\\n\\];"));
  if (!m) throw new Error(nome + " nao encontrada em " + WORKER);
  const semComentario = m[1].split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  return [...semComentario.matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
}
function lerMapa(src, nome) {
  const m = src.match(new RegExp("var " + nome + "\\s*=\\s*\\{([\\s\\S]*?)\\n\\};"));
  if (!m) throw new Error(nome + " nao encontrada em " + WORKER);
  const out = {};
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) out[desescapar(p[1])] = desescapar(p[2]);
  return out;
}
function lerMapaLista(src, nome) {
  const m = src.match(new RegExp("var " + nome + "\\s*=\\s*\\{([\\s\\S]*?)\\n\\};"));
  if (!m) throw new Error(nome + " nao encontrada em " + WORKER);
  const out = {};
  for (const p of m[1].matchAll(/"([^"]+)"\s*:\s*\[([^\]]*)\]/g)) {
    out[desescapar(p[1])] = [...p[2].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
  }
  return out;
}
function montarArbitroPorNome(src) {
  const emissores = lerLista(src, "EMISSORES_LISTA");
  const aliasToEmp = lerMapa(src, "SYNC_ALIAS_TO_EMPRESA");
  const leitor = lerMapaLista(src, "ALIASES_LEITOR_CVM");
  const idx = [];
  const vistos = new Set();
  const add = (termo, dono) => {
    const t = semAcentoUp(termo);
    if (t.length < 2) return;
    const k = t + "\0" + dono;
    if (vistos.has(k)) return;
    vistos.add(k);
    idx.push({ termo: t, dono });
  };
  for (const e of emissores) add(e, e);
  for (const a in aliasToEmp) add(a, aliasToEmp[a]);
  for (const e in leitor) for (const a of leitor[e]) add(a, e);
  idx.sort((x, y) => y.termo.length - x.termo.length);
  const casa = (nomeSA, termo) => {
    let i = nomeSA.indexOf(termo);
    while (i >= 0) {
      if (i === 0 || !/[A-Z0-9]/.test(nomeSA.charAt(i - 1))) return true;
      i = nomeSA.indexOf(termo, i + 1);
    }
    return false;
  };
  return {
    emissores,
    dono(razaoSocial) {
      const n = semAcentoUp(razaoSocial);
      if (!n) return null;
      for (const c of idx) if (casa(n, c.termo)) return c.dono;
      return null;
    }
  };
}

// ── Recusas declaradas ─────────────────────────────────────────────────────
// CNPJ cujo nome casa com emissor da carteira e que NAO e do grupo. Cada linha
// existe para o proximo que rodar este script nao "descobrir" de novo e declarar
// por engano. Medido em 25/08 no ipe_cia_aberta_2026.
export const RECUSADOS = {
  "13.642.699/0001-35": "AGRO INDUSTRIAS DO VALE SAO FRANCISCO S/A. Casa com o emissor Vale porque 'VALE' comeca palavra em 'DO VALE SAO FRANCISCO'. Nenhuma relacao com a Vale S.A. (33.592.510/0001-54).",
  "01.794.428/0001-16": "VALE BONITO AGROPECUARIA S/A. Mesmo mecanismo, 'VALE' comeca a razao social. Nenhuma relacao com a Vale S.A."
};

function recortarJanela(csvTexto) {
  const linhas = csvTexto.split("\n");
  const cab = linhas[0].split(";").map((h) => h.trim().replace(/\r/g, ""));
  const iCnpj = cab.indexOf("CNPJ_Companhia");
  const iNome = cab.indexOf("Nome_Companhia");
  const iData = cab.indexOf("Data_Referencia");
  const iCat = cab.indexOf("Categoria");
  const iAssunto = cab.indexOf("Assunto");
  const iEntrega = cab.indexOf("Data_Entrega");
  const iLink = cab.indexOf("Link_Download");
  if (iCnpj < 0 || iNome < 0 || iCat < 0 || iEntrega < 0) {
    throw new Error("ipe_cia_aberta sem CNPJ_Companhia, Nome_Companhia, Categoria ou Data_Entrega. Schema da CVM mudou.");
  }
  const src = readFileSync(WORKER, "utf8");
  const categorias = lerLista(src, "CVM_CATEGORIAS");
  // Relogio de Brasilia, igual ao obterAgoraBRT do Worker. Usar UTC aqui geraria
  // janela de um dia a mais depois das 21h BRT.
  const agoraBRT = new Date(Date.now() - 3 * 60 * 60 * 1000);
  const hoje = agoraBRT.toISOString().split("T")[0];
  const desde = new Date(agoraBRT.getTime() - DIAS_JANELA * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
  const docs = [];
  for (let i = 1; i < linhas.length; i++) {
    const c = linhas[i].split(";");
    if (c.length < 7) continue;
    const cat = (c[iCat] || "").trim();
    if (!categorias.includes(cat)) continue;
    const entrega = (c[iEntrega] || "").trim();
    if (entrega < desde) continue;
    const dataRef = (c[iData] || "").trim();
    if (dataRef > hoje || dataRef < desde) continue;
    docs.push({
      // Mesma forma do registro em cvm:documentos, para o teto poder ser remedido
      // com fidelidade. `j` e o CNPJ, campo novo desta fase.
      e: (c[iNome] || "").trim(),
      j: (c[iCnpj] || "").trim(),
      d: dataRef,
      de: entrega,
      c: cat,
      a: (c[iAssunto] || "").trim().replace(/\r/g, ""),
      l: (c[iLink] || "").trim().replace(/\r/g, "")
    });
  }
  return { docs, janela: { desde, ate: hoje, dias: DIAS_JANELA } };
}

// O indice de entidades cobre o ANO INTEIRO, e nao a janela. Subsidiaria que
// protocola por trimestre nao aparece numa janela de 35 dias, e um mapa de familia
// construido so pela janela reapareceria incompleto a cada trimestre, com o CNPJ
// dela caindo em quarentena como se fosse novidade. Medido em 25/08: a janela ve
// 36 candidatos, o ano ve 46, e as 10 que faltam sao AXIA Sul, AXIA UHE Santo
// Antonio, Auren Participacoes, Bradesco Leasing, CPFL Renovaveis, Light Energia,
// Light Servicos, Suzano Holding, Banco Pan e Rodovias das Colinas.
// O indice e leve porque guarda uma linha por CNPJ, sem assunto e sem link.
function indexarEntidades(csvTexto) {
  const linhas = csvTexto.split("\n");
  const cab = linhas[0].split(";").map((h) => h.trim().replace(/\r/g, ""));
  const iCnpj = cab.indexOf("CNPJ_Companhia");
  const iNome = cab.indexOf("Nome_Companhia");
  const iCat = cab.indexOf("Categoria");
  const iEntrega = cab.indexOf("Data_Entrega");
  const categorias = lerLista(readFileSync(WORKER, "utf8"), "CVM_CATEGORIAS");
  const porCnpj = new Map();
  for (let i = 1; i < linhas.length; i++) {
    const c = linhas[i].split(";");
    if (c.length < 7) continue;
    if (!categorias.includes((c[iCat] || "").trim())) continue;
    const cn = soDigito(c[iCnpj]);
    if (!cn || cn === "0".repeat(14)) continue;
    const entrega = (c[iEntrega] || "").trim();
    if (!porCnpj.has(cn)) porCnpj.set(cn, { nome: (c[iNome] || "").trim(), docs: 0, ultimo: "" });
    const o = porCnpj.get(cn);
    o.docs++;
    if (entrega > o.ultimo) o.ultimo = entrega;
  }
  return Object.fromEntries([...porCnpj.entries()].sort((a, b) => b[1].docs - a[1].docs));
}

function gravarSnapshot(csvPath) {
  const texto = new TextDecoder("latin1").decode(readFileSync(csvPath));
  const { docs, janela } = recortarJanela(texto);
  if (!existsSync(DIR_SNAP)) mkdirSync(DIR_SNAP, { recursive: true });
  const payload = {
    gerado_em: janela.ate,
    origem: "ipe_cia_aberta (CVM), recortado pela mesma janela e categorias do syncCVMAutomatico",
    janela,
    documentos: docs.length,
    empresas: new Set(docs.map((d) => d.e)).size,
    cnpjs: new Set(docs.map((d) => soDigito(d.j)).filter((x) => x && x !== "0".repeat(14))).size,
    bytes_serializado: Buffer.byteLength(JSON.stringify(docs), "utf8"),
    docs
  };
  const destino = join(DIR_SNAP, "ipe_janela_" + janela.ate + ".json.gz");
  writeFileSync(destino, gzipSync(Buffer.from(JSON.stringify(payload), "utf8")));

  const entidades = indexarEntidades(texto);
  const ano = janela.ate.slice(0, 4);
  const destinoEnt = join(DIR_SNAP, "ipe_entidades_" + ano + ".json.gz");
  const payloadEnt = {
    gerado_em: janela.ate,
    origem: "ipe_cia_aberta (CVM), ano inteiro, so as categorias monitoradas, uma linha por CNPJ",
    ano,
    cnpjs: Object.keys(entidades).length,
    entidades
  };
  writeFileSync(destinoEnt, gzipSync(Buffer.from(JSON.stringify(payloadEnt), "utf8")));

  return { destino, payload, destinoEnt, payloadEnt };
}

function lerEntidades() {
  if (!existsSync(DIR_SNAP)) return null;
  const arquivos = readdirSync(DIR_SNAP).filter((f) => /^ipe_entidades_.*\.json\.gz$/.test(f)).sort();
  if (!arquivos.length) return null;
  const p = join(DIR_SNAP, arquivos[arquivos.length - 1]);
  return { caminho: p, payload: JSON.parse(gunzipSync(readFileSync(p)).toString("utf8")) };
}

function lerSnapshotMaisRecente() {
  if (!existsSync(DIR_SNAP)) throw new Error("data/cvm/ nao existe. Rode com --snapshot <ipe_cia_aberta.csv> primeiro.");
  const arquivos = readdirSync(DIR_SNAP).filter((f) => /^ipe_janela_.*\.json\.gz$/.test(f)).sort();
  if (!arquivos.length) throw new Error("nenhum snapshot em data/cvm/. Rode com --snapshot <ipe_cia_aberta.csv> primeiro.");
  const p = join(DIR_SNAP, arquivos[arquivos.length - 1]);
  return { caminho: p, payload: JSON.parse(gunzipSync(readFileSync(p)).toString("utf8")), bytes: statSync(p).size };
}

async function main() {
  if (CSV_ENTRADA) {
    const { destino, payload } = gravarSnapshot(CSV_ENTRADA);
    console.log("Snapshot gravado: " + destino);
    console.log("  janela        : " + payload.janela.desde + " a " + payload.janela.ate + " (" + payload.janela.dias + " dias)");
    console.log("  documentos    : " + payload.documentos);
    console.log("  empresas      : " + payload.empresas);
    console.log("  CNPJs         : " + payload.cnpjs);
    console.log("  serializado   : " + (payload.bytes_serializado / 1024 / 1024).toFixed(2) + " MB (limite de valor do KV: 25 MB)");
    return;
  }

  const { caminho, payload, bytes } = lerSnapshotMaisRecente();
  const src = readFileSync(WORKER, "utf8");
  const arb = montarArbitroPorNome(src);
  const { EMISSOR_CNPJ } = await import("file://" + join(RAIZ, "scripts", "emissores-cnpj.mjs").replace(/\\/g, "/"));

  const primarios = new Map();
  for (const e in EMISSOR_CNPJ) primarios.set(soDigito(EMISSOR_CNPJ[e]), e);
  const recusados = new Set(Object.keys(RECUSADOS).map(soDigito));

  // A proposta sai do indice do ANO, nao da janela, pelo motivo escrito no
  // comentario de indexarEntidades. A janela serve para medir o teto do KV.
  const ent = lerEntidades();
  if (!ent) throw new Error("indice de entidades ausente em data/cvm/. Rode com --snapshot <ipe_cia_aberta.csv>.");

  const candidatos = new Map();
  let semCnpj = payload.docs.filter((d) => { const c = soDigito(d.j); return !c || c === "0".repeat(14); }).length;
  for (const cn in ent.payload.entidades) {
    if (primarios.has(cn)) continue;
    if (recusados.has(cn)) continue;
    const o = ent.payload.entidades[cn];
    const emp = arb.dono(o.nome);
    if (!emp) continue;
    candidatos.set(cn, { emissor: emp, nome: o.nome, docs: o.docs, ultimo: o.ultimo });
  }

  const porEmissor = {};
  for (const [cn, o] of candidatos) (porEmissor[o.emissor] = porEmissor[o.emissor] || []).push({ cnpj: formatarCnpj(cn), ...o });

  if (JSON_OUT) {
    console.log(JSON.stringify({ snapshot: caminho, candidatos: porEmissor, recusados: RECUSADOS, sem_cnpj: semCnpj }, null, 2));
    return;
  }

  console.log("Entidades do ano: " + ent.caminho + "  (" + ent.payload.cnpjs + " CNPJs distintos)");
  console.log("Snapshot da janela: " + caminho + "  (" + (bytes / 1024).toFixed(0) + " KB comprimido)");
  console.log("  janela " + payload.janela.desde + " a " + payload.janela.ate + ", " + payload.documentos + " documentos, " + payload.empresas + " empresas");
  console.log("  primarios ja declarados: " + primarios.size + " | recusas declaradas: " + recusados.size);
  console.log("  documentos sem CNPJ utilizavel: " + semCnpj + "  (caem no arbitro por nome, e o caso das entidades estrangeiras)");
  console.log("");
  console.log("CANDIDATOS A FAMILIA: " + candidatos.size + " CNPJs em " + Object.keys(porEmissor).length + " emissores.");
  console.log("Revise um a um e cole no CNPJ_FAMILIA_CVM do worker.js. Nada aqui e automatico.");
  console.log("");
  for (const emp of Object.keys(porEmissor).sort()) {
    for (const x of porEmissor[emp].sort((a, b) => b.docs - a.docs)) {
      console.log('  "' + x.cnpj + '": ' + JSON.stringify(emp) + ", // " + x.nome + " (" + x.docs + " docs, ultimo " + x.ultimo + ")");
    }
  }
}

main().catch((e) => {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
});
