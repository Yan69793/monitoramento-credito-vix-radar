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

// SUBSTRINGDONO1 (2026-08-25): terceira tabela que a guarda precisa enxergar. O
// mapa de aliases do leitor era privado dentro de buscarDocumentosCVM e virou
// ALIASES_LEITOR_CVM justamente para poder ser auditado daqui.
function extrairAliasesLeitor(src) {
  const m = src.match(/var ALIASES_LEITOR_CVM\s*=\s*\{([\s\S]*?)\n\};/);
  if (!m) throw new Error("ALIASES_LEITOR_CVM nao encontrada em api/src/worker.js");
  const porEmpresa = {};
  for (const par of m[1].matchAll(/"([^"]+)"\s*:\s*\[([^\]]*)\]/g)) {
    const empresa = desescapar(par[1]);
    porEmpresa[empresa] = [...par[2].matchAll(/"([^"]+)"/g)].map((x) => desescapar(x[1]));
  }
  return porEmpresa;
}

// ── SUBSTRINGDONO1: espelho do _donoDocumentoCVM do Worker ──────────────────
// Precisa ser o MESMO criterio, pelo mesmo motivo que semAcentoUp precisa ser o
// mesmo: guarda que julga por regra diferente da que roda em producao aprova o
// que o Worker reprova, e vice-versa. Se o Worker mudar de criterio, o teste
// api/test/cvm-atribuicao.test.mjs quebra primeiro.
function montarIndiceDono(emissores, aliasPorEmpresa, leitorPorEmpresa) {
  const out = [];
  const vistos = new Set();
  const add = (termo, dono) => {
    const t = semAcentoUp(termo);
    if (t.length < 2) return;
    const chave = t + "\0" + dono;
    if (vistos.has(chave)) return;
    vistos.add(chave);
    out.push({ termo: t, dono });
  };
  for (const e of emissores) add(e, e);
  for (const emp in aliasPorEmpresa) for (const a of aliasPorEmpresa[emp]) add(a, emp);
  for (const emp in leitorPorEmpresa) for (const a of leitorPorEmpresa[emp]) add(a, emp);
  return out.sort((x, y) => y.termo.length - x.termo.length);
}

function casaInicioDePalavra(nomeSA, termo) {
  let i = nomeSA.indexOf(termo);
  while (i >= 0) {
    if (i === 0 || !/[A-Z0-9]/.test(nomeSA.charAt(i - 1))) return true;
    i = nomeSA.indexOf(termo, i + 1);
  }
  return false;
}

function donoDe(indice, razaoSocial) {
  const n = semAcentoUp(razaoSocial);
  if (!n) return null;
  for (const c of indice) if (casaInicioDePalavra(n, c.termo)) return c.dono;
  return null;
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

  // ── SUBSTRINGDONO1 (2026-08-25) ──────────────────────────────────────────
  // A checagem acima pergunta "existe alguma companhia ativa que casa com este
  // emissor?". A CSN passava nela e mesmo assim ficou nove meses sem documento
  // proprio, porque a companhia que casava era a CSN MINERACAO, que pertence a
  // OUTRO emissor da carteira. Casar com a empresa do vizinho nao e casar.
  //
  // Esta segunda checagem pergunta o contrario, e e a pergunta que faltava:
  // "existe alguma companhia ativa da qual este emissor seja o dono?". Dono no
  // sentido do arbitro que roda em producao, ou seja, o termo mais longo que casa
  // no inicio de uma palavra da razao social. Emissor que nao e dono de nada
  // nunca vai receber documento da CVM, por mais verde que o painel esteja.
  //
  // SO DENOM_SOCIAL, deliberadamente, e este detalhe e a diferenca entre a guarda
  // funcionar e nao funcionar. O ipe_cia_aberta publica Nome_Companhia com a razao
  // social, nunca com o nome fantasia, e e esse valor que vai parar no campo `e` de
  // cvm:documentos e chega ao _donoDocumentoCVM. A CSN tem DENOM_COMERC "CSN" no
  // cadastro, entao aceitar o nome fantasia aqui faria a guarda aprovar a CSN por
  // um nome que o pipeline nunca ve. Medido: com os dois campos a guarda passava
  // mesmo sem o alias, que e exatamente o defeito que ela existe para pegar.
  // A checagem `casa()` la em cima continua olhando os dois de proposito, porque a
  // pergunta dela e outra, "esta companhia existe na CVM", e para isso nome
  // fantasia e prova legitima.
  const indice = montarIndiceDono(emissores, aliases, extrairAliasesLeitor(src));
  const possui = {};
  for (const a of ativos) {
    if (!a.social) continue;
    const d = donoDe(indice, a.social);
    if (d) (possui[d] = possui[d] || []).push(a.social);
  }
  const semRazaoPropria = [];
  for (const emp of emissores) {
    if (possui[emp]) continue;
    // Emissor ja reprovado como nome morto nao entra duas vezes no relatorio, e
    // excecao declarada continua tolerada: quem nao tem registro ativo nenhum
    // tambem nao tem como ser dono de razao social ativa.
    if (EXCECOES[emp]) continue;
    if (mortos.some((m) => m.emissor === emp)) continue;
    semRazaoPropria.push({ emissor: emp, aliases: aliases[emp] || [] });
  }

  const reprovado = mortos.length > 0 || semRazaoPropria.length > 0;

  if (JSON_OUT) {
    console.log(JSON.stringify({ ok: !reprovado, total: emissores.length, ativos_cvm: ativos.length, mortos, sem_razao_propria: semRazaoPropria, tolerados, excecoes_ociosas: excecoesOciosas }, null, 2));
  } else {
    console.log(`Emissores: ${emissores.length} | Companhias ATIVAS no cadastro CVM: ${ativos.length}`);
    if (tolerados.length) {
      console.log(`\nSem registro ativo, mas com excecao declarada (${tolerados.length}). Nao geram documento IPE, evento so por imprensa:`);
      for (const t of tolerados) console.log(`  - ${t.emissor}: ${t.motivo}`);
    }
    if (excecoesOciosas.length) {
      console.log(`\nAVISO: excecao que ja nao e necessaria, remover de EXCECOES: ${excecoesOciosas.join(", ")}`);
    }
    if (!reprovado) {
      console.log("\nOK: todo emissor casa com companhia ativa, por nome, por alias declarado, ou tem excecao registrada.");
      console.log("OK: todo emissor e dono de pelo menos uma razao social ativa, nenhum depende da companhia de outro.");
    }
    if (mortos.length) {
      console.error(`\nREPROVADO: ${mortos.length} emissor(es) sem registro ativo na CVM.`);
      for (const m of mortos) {
        console.error(`  - ${m.emissor}${m.aliases.length ? `  (aliases: ${m.aliases.join(", ")})` : "  (sem alias declarado)"}`);
      }
      console.error("\nProvavel renomeacao ou incorporacao. Confira a sucessora em");
      console.error("https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv e declare o alias");
      console.error("em SYNC_ALIAS_TO_EMPRESA. Desde SUBSTRINGDONO1 essa tabela e a unica: a ingestao e o");
      console.error("leitor consultam o mesmo arbitro, entao declarar uma vez vale nas duas pontas.");
    }
    if (semRazaoPropria.length) {
      console.error(`\nREPROVADO: ${semRazaoPropria.length} emissor(es) sem razao social propria no cadastro ativo.`);
      for (const s of semRazaoPropria) {
        console.error(`  - ${s.emissor}${s.aliases.length ? `  (aliases: ${s.aliases.join(", ")})` : "  (sem alias declarado)"}`);
      }
      console.error("\nO emissor existe na carteira mas nenhuma companhia ATIVA da CVM pertence a ele. Ou o nome");
      console.error("dele so aparece dentro do nome de outra companhia (foi o caso da CSN, cujo unico casamento");
      console.error("era CSN MINERACAO, que e outro emissor), ou a razao social real nunca foi declarada. Enquanto");
      console.error("ficar assim, este emissor nao recebe documento nenhum da CVM e so gera evento por imprensa.");
      console.error("Declare a razao social em SYNC_ALIAS_TO_EMPRESA, que desde SUBSTRINGDONO1 e a unica tabela.");
    }
  }
  process.exit(reprovado ? 1 : 0);
}

main().catch((e) => {
  console.error("ERRO:", e && e.message ? e.message : String(e));
  process.exit(2);
});
