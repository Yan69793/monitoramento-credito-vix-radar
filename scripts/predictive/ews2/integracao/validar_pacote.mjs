// Portao de publicacao do pacote `ews2:latest`. Usa o PROPRIO adaptador do Worker (validarPayload, liberacaoValida,
// LIBERACAO_NOTA_SHA256): o que este script aceita e exatamente o que o Worker aceita, sem segunda regua.
// Checagens extras de rotina, que o adaptador nao faz: 104 emissores, cnpj unico, data_observacao esperada.
//
// Uso: node validar_pacote.mjs <pacote.json> [--n 104] [--T AAAA-MM-DD]
// Saida: uma linha JSON {ok, erros, ...}. Exit 0 so com ok=true.
import { readFileSync } from "node:fs";
import { SCHEMA, LIBERACAO_NOTA_SHA256, validarPayload, liberacaoValida } from "./ews2_adapter.mjs";

const args = process.argv.slice(2);
const caminho = args[0];
const opt = (nome, padrao) => { const i = args.indexOf(nome); return i >= 0 && args[i + 1] ? args[i + 1] : padrao; };
const nEsperado = Number(opt("--n", "104"));
const tEsperado = opt("--T", null);

const erros = [];
let p = null;
try {
  p = JSON.parse(readFileSync(caminho, "utf8").replace(/^﻿/, ""));
} catch (e) {
  erros.push("json ilegivel: " + e.message);
}
if (p) {
  if (p.schema !== SCHEMA) erros.push("schema diferente de " + SCHEMA);
  if (!liberacaoValida(p)) erros.push("liberacao.nota_sha256 diferente do fixado no adaptador (" + LIBERACAO_NOTA_SHA256 + ")");
  for (const e of validarPayload(p).erros) erros.push("adaptador: " + e);
  const lista = Array.isArray(p.emissores) ? p.emissores : [];
  if (lista.length !== nEsperado) erros.push("emissores: " + lista.length + " (esperado " + nEsperado + ")");
  const cnpjs = new Set(lista.map((e) => e && e.cnpj));
  if (cnpjs.size !== lista.length) erros.push("cnpj duplicado no pacote");
  if (p.exibir_probabilidade !== false) erros.push("exibir_probabilidade tem que ser false (G3 nao calculado)");
  if (tEsperado && p.data_observacao !== tEsperado) erros.push("data_observacao " + p.data_observacao + " (esperado " + tEsperado + ")");
}
const out = {
  ok: erros.length === 0, erros,
  schema: p && p.schema, data_observacao: p && p.data_observacao, n: p && Array.isArray(p.emissores) ? p.emissores.length : null,
  sinais_aprovados: p && p.sinais_aprovados, resumo: p && p.resumo, nota_sha256: p && p.liberacao && p.liberacao.nota_sha256,
};
console.log(JSON.stringify(out));
process.exit(out.ok ? 0 : 1);
