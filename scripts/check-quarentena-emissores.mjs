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
import { avaliarQuarentena } from "./lib/quarentena-guarda.mjs";

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

async function fetchDescartados() {
  // Fluxo do ultimo sync, exposto no health com nome proprio (CFG-02 P2).
  const res = await fetch("https://api.vixradar.com", { headers: { "Cache-Control": "no-cache" } });
  if (!res.ok) throw new Error("health HTTP " + res.status);
  const h = await res.json();
  return h.cvm_ingestao_descartados_sem_dono != null ? h.cvm_ingestao_descartados_sem_dono : null;
}

async function main() {
  const data = await fetchQuarentena();
  const descartados = await fetchDescartados();
  const fila = data.fila || [];
  console.log(`acervo=${data.acervo} cobertura=${JSON.stringify(data.cobertura)} pct=${data.cobertura_pct} entidades_em_quarentena=${data.entidades_em_quarentena} retornadas=${fila.length} descartados_ingestao=${descartados}`);
  const r = avaliarQuarentena({ fila, entidades: data.entidades_em_quarentena, descartados, donoPorCnpj: donoPorCnpj(), soDigito: _soDigito });
  if (r.codigo === 0) {
    console.log(`OK: nenhuma das ${fila.length} entidades (maior volume da quarentena) pertence a um dos 103 por CNPJ.`);
  } else if (r.codigo === 1) {
    console.log("FALHA DE ATRIBUICAO: entidade(s) de emissor dos 103 na quarentena:");
    for (const f of r.falhas) console.log(`  cnpj=${f.cnpj} nome="${f.nome}" -> ${f.emissor} docs=${f.documentos}`);
  } else if (r.codigo === 3) {
    console.log(`FALHA DE VACUIDADE: fila de quarentena vazia mas a ingestao descartou ${descartados} documento(s) sem dono no ultimo sync. A guarda nao tem o que avaliar, e o descarte prova que a fila nao mostra o que foi recusado.`);
  } else {
    console.log("FALHA: fila vazia e o health nao expoe cvm_ingestao_descartados_sem_dono, nao ha como distinguir quarentena vazia de fila zerada por descarte.");
  }
  process.exit(r.codigo);
}

main().catch((e) => {
  console.error("ERRO: " + e.message);
  process.exit(2);
});
