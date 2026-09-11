import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// SCANFALLBACK-MORTO1 (2026-09-11). Prova deterministica do contrato real entre o
// endpoint que lista os prioritarios e o endpoint que recebe o payload de analise.
//
// O defeito de 08/09: `scripts/scan-emergencia.mjs` montava `{empresa: emissor.nome,
// setor: emissor.setor || ""}`. `listar_emissores_prioritarios` devolve `empresa`
// (nao `nome`) e nao devolvia `setor`; `dados_para_analise` exige os dois. O
// resultado era HTTP 400 "empresa e setor obrigatorios." nos 19 emissores.
//
// A correcao deriva `setor` do mapa canonico SETOR_DE_EMPRESA no proprio Worker,
// o mesmo mapa ja usado por `listar_todos_emissores` e pelo fallback de
// `receber_analise`. Aqui NAO ha `|| "Outros"`: item cujo `empresa` nao esta em
// SETOR_DE_EMPRESA sai em `sem_setor` e nao e enviado, em vez de receber setor
// inventado que `dados_para_analise` aceitaria como se fosse canonico.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
let seqIp = 0;
function ipUnico() { seqIp++; return `203.0.113.${110 + seqIp}`; }

function postar(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ipUnico() },
    body: JSON.stringify(Object.assign({ routine_key: ROUTINE_KEY }, body)),
  });
}

async function prioritarios() {
  const r = await postar({ action: "listar_emissores_prioritarios", top_n: 15 });
  expect(r.status).toBe(200);
  return r.json();
}

async function dados(payload) {
  return postar(Object.assign({ action: "dados_para_analise" }, payload));
}

describe("SCANFALLBACK-MORTO1: contrato listar_emissores_prioritarios -> dados_para_analise", () => {
  it("reproduz o HTTP 400 anterior e prova o payload valido derivado do contrato real", async () => {
    const lista = await prioritarios();
    expect(lista.ok).toBe(true);
    expect(Array.isArray(lista.emissores)).toBe(true);
    expect(Array.isArray(lista.sem_setor)).toBe(true);
    expect(lista.emissores.length).toBeGreaterThan(0);

    const emissor = lista.emissores[0];
    expect(typeof emissor.empresa).toBe("string");
    expect(emissor.empresa.length).toBeGreaterThan(0);
    // O setor precisa vir do endpoint; sem regra local inventada no script.
    expect(typeof emissor.setor).toBe("string");
    expect(emissor.setor.length).toBeGreaterThan(0);

    // Contrato anterior: `nome` nao existe e o setor nao era devolvido. As duas
    // chamadas abaixo sao as metades do 400 de 08/09; cada uma sozinha ja reprova.
    const rNome = await dados({ empresa: emissor.nome, setor: emissor.setor });
    expect(rNome.status).toBe(400);
    expect((await rNome.json()).erro).toBe("empresa e setor obrigatorios.");

    const rSemSetor = await dados({ empresa: emissor.empresa, setor: "" });
    expect(rSemSetor.status).toBe(400);
    expect((await rSemSetor.json()).erro).toBe("empresa e setor obrigatorios.");

    // Contrato corrigido: `empresa` do endpoint + `setor` canonico do Worker.
    const rOk = await dados({ empresa: emissor.empresa, setor: emissor.setor });
    expect(rOk.status).toBe(200);
    const body = await rOk.json();
    expect(body.ok).toBe(true);
    expect(body.empresa).toBe(emissor.empresa);
    expect(body.setor).toBe(emissor.setor);
    expect(body.janela_inicio).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(body.janela_fim).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});