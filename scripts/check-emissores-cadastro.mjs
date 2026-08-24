#!/usr/bin/env node
// NOMEMORTO1 (auditoria 2026-08-24) — guarda contra emissor com nome morto.
//
// Por que existe: a Eletrobras virou AXIA ENERGIA em 10/11/2025 e o VIX Radar
// passou nove meses procurando documento e noticia por um nome que a CVM nao
// registra mais. Nao foi negligencia de ninguem, foi ausencia de guarda: nada no
// projeto comparava a lista de emissores com o cadastro vivo da CVM, entao a
// renomeacao so aparecia quando alguem tropecava nela. Na mesma varredura vieram
// CCR -> Motiva Infraestrutura e Omega Energia -> Serena Energia, ambas tambem
// invisiveis, e AES Brasil, que nao tem mais registro ativo nenhum.
//
// O que faz: baixa cad_cia_aberta.csv (atualizado todo dia, e o unico ramo do
// portal que nunca parou) e confere se cada emissor de EMISSORES_LISTA casa com
// alguma companhia ATIVA, seja pelo proprio nome ou por um alias declarado em
// SYNC_ALIAS_TO_EMPRESA. Emissor sem nenhum casamento e reprovado.
//
// Deliberadamente roda em Node e nao em PowerShell: o canal de alerta desta
// familia de problema tem que viver na nuvem. O VIXRadar-Health-Watch era local,
// foi desligado em 21/08/2026 por decisao do operador, e a fonte da CVM ficou
// escura quatro dias sem ninguem ver. Guarda que depende de maquina ligada nao e
// guarda.
//
// Uso:
//   node scripts/check-emissores-cadastro.mjs
//   node scripts/check-emissores-cadastro.mjs --json
// Saida: exit 0 se todos casam, exit 1 se algum emissor esta sem registro ativo.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..");
// Override de caminho existe para a prova de duas pontas: sem ele so da para
// demonstrar que a guarda aprova o caso bom, e prova de um lado so esconde
// guarda quebrada (regra 5 do CLAUDE.md).
const WORKER = process.env.EMISSORES_WORKER_PATH || join(RAIZ, "api", "src", "worker.js");
const CAD_URL = "https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv";
const JSON_OUT = process.argv.includes("--json");

// Mesma normalizacao do _semAcentoUp do worker (ACENTOMATCH1). Precisa ser a
// mesma, senao a guarda aprova o que o Worker reprova e vice-versa.
function semAcentoUp(s) {
  return String(s || "").toUpperCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

// O worker.js e um bundle com unicode escapado (\xE9). Ler literal deixaria
// "Ita\xFAsa" no lugar de "Itaúsa" e a guarda acusaria falso positivo.
function desescapar(s) {
  return s.replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
          .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

// Excecoes declaradas. Nem todo emissor sem registro ativo e bug: alguns
// fecharam capital, um e estrangeiro e nunca protocolou IPE, outro foi
// incorporado. O que NAO pode acontecer e tolerar isso em silencio, senao a
// guarda vira ruido e a proxima renomeacao de verdade passa junto. Cada linha
// aqui e uma decisao consciente, com data e motivo, e some quando resolvida.
//
// Consequencia pratica em todos os casos abaixo: o emissor nao gera documento
// IPE novo, entao evento dele so pode vir de imprensa e rating. Isso e piso de
// cobertura conhecido, nao falha de ingestao.
const EXCECOES = {
  // AES Brasil saiu da carteira em 2026-08-24 (CARTEIRA-24AGO1). Foi incorporada
  // pela Auren Energia, que ja estava nos 103, entao manter as duas contava o
  // mesmo risco duas vezes. Nao precisa mais de excecao porque nao e mais emissor.
  "Banco Pan": "BANCO PAN SA consta CANCELADA no cadastro. Fechamento de capital. Segue como emissor de divida, sem protocolo IPE. Aberto em 2026-08-24.",
  "Banco Votorantim": "Sem registro ativo como companhia aberta. VOTORANTIM FINANCAS esta CANCELADA e Banco BV nao consta. Emissor de divida sem protocolo IPE. Aberto em 2026-08-24.",
  "Nexa Resources": "Companhia de Luxemburgo, listada via BDR. Nunca foi companhia aberta registrada na CVM, entao nao ha nome a casar. Excecao permanente."
};

function extrairEmissores(src) {
  const m = src.match(/var EMISSORES_LISTA\s*=\s*\[([\s\S]*?)\];/);
  if (!m) throw new Error("EMISSORES_LISTA nao encontrada em api/src/worker.js");
  return [...m[1].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
}

function extrairAliases(src) {
  const m = src.match(/var SYNC_ALIAS_TO_EMPRESA\s*=\s*\{([\s\S]*?)\n\};/);
  if (!m) throw new Error("SYNC_ALIAS_TO_EMPRESA nao encontrada em api/src/worker.js");
  const porEmpresa = {};
  for (const par of m[1].matchAll(/"([^"]+)"\s*:\s*"([^"]+)"/g)) {
    const alias = desescapar(par[1]);
    const empresa = desescapar(par[2]);
    if (!porEmpresa[empresa]) porEmpresa[empresa] = [];
    porEmpresa[empresa].push(alias);
  }
  return porEmpresa;
}

// Parser de CSV simples basta: o cad_cia_aberta usa ';' e nao tem campo com
// aspas nem ';' embutido. Se isso mudar, o teste de sanidade abaixo reprova.
function parseCad(texto) {
  const linhas = texto.split("\n");
  const cab = linhas[0].split(";").map((h) => h.trim().replace(/\r/g, ""));
  const iDenom = cab.indexOf("DENOM_SOCIAL");
  const iComerc = cab.indexOf("DENOM_COMERC");
  const iSit = cab.indexOf("SIT");
  if (iDenom < 0 || iSit < 0) throw new Error("cad_cia_aberta.csv sem DENOM_SOCIAL ou SIT. Schema da CVM mudou.");
  const ativos = [];
  for (let i = 1; i < linhas.length; i++) {
    const c = linhas[i].split(";");
    if (c.length <= iSit) continue;
    if ((c[iSit] || "").trim() !== "ATIVO") continue;
    ativos.push({ social: semAcentoUp(c[iDenom]), comerc: semAcentoUp(iComerc >= 0 ? c[iComerc] : "") });
  }
  return ativos;
}

function casa(nome, ativos) {
  const n = semAcentoUp(nome).replace(/\s*\(.*$/, "").trim();
  if (!n) return false;
  const chave = n.slice(0, Math.min(n.length, 8));
  // Prefixo de 8 e o mesmo tamanho que o matchPrincipal do syncCVMAutomatico usa,
  // mas aqui a ancora e mais apertada de proposito. Com `includes` solto a guarda
  // aprovava um emissor inventado chamado "Ferrovia Fantasma Renomeada", porque
  // existe "FERROVIA CENTRO-ATLANTICA" no cadastro e as 8 primeiras letras batem
  // no meio da string. Guarda que aceita nome inventado nao prova nada. Agora o
  // casamento exige inicio de razao social ou inicio de palavra.
  const bate = (campo) => !!campo && (campo.startsWith(chave) || campo.includes(" " + chave));
  return ativos.some((a) => bate(a.social) || bate(a.comerc));
}

async function main() {
  const src = readFileSync(WORKER, "utf8");
  const emissores = extrairEmissores(src);
  const aliases = extrairAliases(src);

  const res = await fetch(CAD_URL, { signal: AbortSignal.timeout(120000) });
  if (!res.ok) {
    console.error(`ERRO: cad_cia_aberta.csv respondeu HTTP ${res.status}. Sem cadastro nao da para julgar, e ausencia de dado nao pode virar aprovacao silenciosa.`);
    process.exit(2);
  }
  // O arquivo vem em latin-1, nao utf-8. Decodificar errado quebra todo nome acentuado.
  const texto = new TextDecoder("latin1").decode(await res.arrayBuffer());
  const ativos = parseCad(texto);
  if (ativos.length < 300) {
    console.error(`ERRO: so ${ativos.length} companhias ATIVAS no cadastro. Esperado algo acima de 700. Download truncado ou schema mudou.`);
    process.exit(2);
  }

  const mortos = [];
  const tolerados = [];
  const excecoesOciosas = [];
  for (const emp of emissores) {
    let ok = casa(emp, ativos);
    const alts = aliases[emp] || [];
    if (!ok) ok = alts.some((a) => casa(a, ativos));
    if (ok) {
      // Excecao que voltou a casar sozinha (emissor reabriu capital, ou alguem
      // declarou o alias certo). Avisar para a lista nao apodrecer.
      if (EXCECOES[emp]) excecoesOciosas.push(emp);
      continue;
    }
    if (EXCECOES[emp]) { tolerados.push({ emissor: emp, motivo: EXCECOES[emp] }); continue; }
    mortos.push({ emissor: emp, aliases: alts });
  }

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok: mortos.length === 0, total: emissores.length, ativos_cvm: ativos.length, mortos, tolerados, excecoes_ociosas: excecoesOciosas }, null, 2));
  } else {
    console.log(`Emissores: ${emissores.length} | Companhias ATIVAS no cadastro CVM: ${ativos.length}`);
    if (tolerados.length) {
      console.log(`\nSem registro ativo, mas com excecao declarada (${tolerados.length}). Nao geram documento IPE, evento so por imprensa:`);
      for (const t of tolerados) console.log(`  - ${t.emissor}: ${t.motivo}`);
    }
    if (excecoesOciosas.length) {
      console.log(`\nAVISO: excecao que ja nao e necessaria, remover de EXCECOES: ${excecoesOciosas.join(", ")}`);
    }
    if (mortos.length === 0) {
      console.log("\nOK: todo emissor casa com companhia ativa, por nome, por alias declarado, ou tem excecao registrada.");
    } else {
      console.error(`\nREPROVADO: ${mortos.length} emissor(es) sem registro ativo na CVM.`);
      for (const m of mortos) {
        console.error(`  - ${m.emissor}${m.aliases.length ? `  (aliases: ${m.aliases.join(", ")})` : "  (sem alias declarado)"}`);
      }
      console.error("\nProvavel renomeacao ou incorporacao. Confira a sucessora em");
      console.error("https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv e declare o alias");
      console.error("em SYNC_ALIAS_NOMES_CVM e SYNC_ALIAS_TO_EMPRESA, nesta ordem. O leitor deriva da segunda.");
    }
  }
  process.exit(mortos.length === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
});
