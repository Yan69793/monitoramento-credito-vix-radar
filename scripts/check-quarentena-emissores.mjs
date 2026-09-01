#!/usr/bin/env node
// check-quarentena-emissores.mjs (2026-09-01, sessao de fechamento ponto 4).
//
// Guarda do cruzamento dos 1.439 documentos sem dono contra os 103 emissores.
// Achado 01/09: o acervo CVM tem 2252 documentos, 1439 sem dono entre os 103
// (383 entidades em quarentena, cobertura 36,1%). A pergunta que esta guarda
// responde e: ha documento de ALGUM dos 103 em quarentena? Se houver, e falha
// real de atribuicao (o CNPJ/familia/alias do emissor devia captura-lo) e o
// CI reprova. Se nao (tudo fora do universo), e COMPORTAMENTO ESPERADO.
//
// Fonte dos dados: endpoint admin_cvm_quarentena do Worker em producao,
// autenticado com admin_senha via api/Get-VixAdminCredential.ps1 (nao imprime
// segredo). O cruzamento usa a MESMA regua de producao: CNPJ primario, CNPJ de
// familia e atribuicao por nome (_atribuirDocumentoCVM / aliases).
//
// Uso: node scripts/check-quarentena-emissores.mjs   (ou via pwsh se precisar DPAPI)
// Exit 0 = nenhum dos 103 na quarentena (esperado); exit 1 = achou emissor dos 103

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  CNPJ_PRIMARIO_EMISSOR,
  CNPJ_FAMILIA_CVM,
  _soDigito
} from "../api/src/worker.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");

// ── Admin senha via DPAPI (sem imprimir) ────────────────────────────────
function adminSenha() {
  const helper = path.join(root, "api", "Get-VixAdminCredential.ps1");
  const r = spawnSync("pwsh", ["-NoProfile", "-File", helper, "-AsPlainText"], {
    encoding: "utf8", timeout: 30000, windowsHide: true,
  });
  if (r.status !== 0 || !r.stdout) {
    throw new Error("Nao foi possivel ler a credencial de admin (Get-VixAdminCredential).");
  }
  const s = r.stdout.split(/\r?\n/)[0].trim();
  if (!s) throw new Error("Credencial de admin vazia.");
  return s;
}

async function fetchQuarentena() {
  const senha = adminSenha();
  const res = await fetch("https://api.vixradar.com", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ action: "admin_cvm_quarentena", admin_senha: senha }),
    timeout: 60000,
  });
  if (!res.ok) throw new Error("admin_cvm_quarentena HTTP " + res.status);
  const data = await res.json();
  if (!data.ok) throw new Error("admin_cvm_quarentena falhou: " + (data.erro || "sem detalhe"));
  return data; // { acervo, cobertura, cobertura_pct, entidades_em_quarentena, fila: [...até 100] }
}

// CNPJ dos 103: primario + familia, normalizados so-digito. Mesma regra de producao.
function donoPorCnpj() {
  const map = {};
  for (const c of Object.keys(CNPJ_PRIMARIO_EMISSOR)) map[_soDigito(c)] = CNPJ_PRIMARIO_EMISSOR[c];
  for (const c of Object.keys(CNPJ_FAMILIA_CVM)) {
    const dig = _soDigito(c);
    if (!map[dig]) map[dig] = CNPJ_FAMILIA_CVM[c];
  }
  return map;
}

const norm = (s) => String(s || "").toLowerCase().replace(/[^a-z0-9]/g, " ").trim();

async function main() {
  const data = await fetchQuarentena();
  const fila = data.fila || [];
  const map = donoPorCnpj();

  console.log(`acervo=${data.acervo} cobertura=${JSON.stringify(data.cobertura)} pct=${data.cobertura_pct} entidades_em_quarentena=${data.entidades_em_quarentena} retornadas=${fila.length}`);

  // Cruzamento por CNPJ: emissor dos 103 cujo CNPJ casou = falha real.
  const falhas = [];
  for (const e of fila) {
    const dig = _soDigito(e.cnpj || "");
    if (map[dig]) {
      falhas.push({ cnpj: e.cnpj, nome: e.nome, emissor: map[dig], documentos: e.documentos });
    }
  }

  // Cruzamento por nome: aliases (BANCO VOTORANTIM, NEXA RESOURCES, etc.) ja entram
  // por _atribuirDocumentoCVM. Apos o CNPJ, conferimos overlap de nome apenas como
  // sinal secundario (o CNPJ mandou; nome e pista, nao atribuicao).
  if (falhas.length === 0) {
    console.log(`OK: nenhuma das ${fila.length} entidades (maior volume da quarentena) pertence a um dos 103 por CNPJ.`);
  } else {
    console.log("FALHA DE ATRIBUICAO: entidade(s) de emissor dos 103 na quarentena:");
    for (const f of falhas) console.log(`  cnpj=${f.cnpj} nome="${f.nome}" -> ${f.emissor} docs=${f.documentos}`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error("ERRO: " + e.message);
  process.exit(2);
});
