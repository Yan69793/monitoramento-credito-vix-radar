import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { derivarPropostasDeErros, proporEvolucao, listarEvolucao } from "../src/evolucao.mjs";

// EVOLUCAO2: coletor de erros. Duas pontas: erro isolado nao vira proposta, erro recorrente vira; simulacao nao grava, aplicar grava.
const ADMIN = "test-admin-password-nao-usar-em-producao";
const ROTINA = "test-routine-key-nao-usar-em-producao";
const reg = (i, empresa, host, extra = {}) => ({ id: `2026-10-1${i % 9}|${empresa}|${host}/noticia-${i}`, empresa, n: 3, esgotado: true, aguarda_manual: true, ...extra });
const lote = (n, empresa, host) => Array.from({ length: n }, (_, i) => reg(i, empresa, host));
let ip = 0;
const chamar = (corpo) => SELF.fetch("https://example.com/", { method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": `10.8.0.${++ip % 250}` }, body: JSON.stringify(corpo) });

beforeEach(async () => {
  for (const p of ["evolucao:", "radar:verif:attempt:"]) { const r = await env.RADAR_KV.list({ prefix: p }); for (const k of r.keys) await env.RADAR_KV.delete(k.name); }
});

describe("EVOLUCAO2: derivacao pura", () => {
  it("abaixo do limiar nao propoe; no limiar propoe fonte e emissor", () => {
    expect(derivarPropostasDeErros(lote(2, "Raízen", "sec.gov"))).toEqual([]);
    const p = derivarPropostasDeErros(lote(3, "Raízen", "www.sec.gov"));
    expect(p.map((x) => x.tipo)).toEqual(["descoberta_fonte", "descoberta_emissor"]);
    expect(p[0]).toMatchObject({ alvo: "sec.gov", fontes: ["https://sec.gov/"] });
    expect(p[0].descricao).toContain("3 itens");
  });
  it("so conta itens esgotados e ids distintos; tentativa em andamento e duplicata ficam de fora", () => {
    const regs = [...lote(2, "Oi", "x.com.br"), { ...reg(5, "Oi", "x.com.br"), esgotado: false, aguarda_manual: false, n: 2 }, reg(0, "Oi", "x.com.br")];
    expect(derivarPropostasDeErros(regs)).toEqual([]);
  });
  it("id malformado ou host invalido nao quebra nem gera proposta", () => {
    const ruins = [{ id: "sem-pipes", esgotado: true }, { id: "a|b|<script>", esgotado: true }, null, { esgotado: true }, ...Array.from({ length: 3 }, (_, i) => ({ id: `d|Emp|localhost/${i}`, esgotado: true }))];
    expect(derivarPropostasDeErros(ruins).filter((x) => x.tipo === "descoberta_fonte")).toEqual([]);
  });
  it("proposta derivada passa pelo livro e e idempotente mesmo com contagem maior", async () => {
    const a = derivarPropostasDeErros(lote(3, "Oi", "br.advfn.com"))[0];
    const b = derivarPropostasDeErros(lote(5, "Oi", "br.advfn.com"))[0];
    const r1 = await proporEvolucao(env.RADAR_KV, "vix_core", a, { origem: "rotina", agora: "2026-10-20T10:00:00.000Z" });
    const r2 = await proporEvolucao(env.RADAR_KV, "vix_core", b, { origem: "rotina", agora: "2026-10-20T11:00:00.000Z" });
    expect(r1.criada).toBe(true);
    expect(r2).toMatchObject({ criada: false, id: r1.id });
  });
});

describe("EVOLUCAO2: endpoint evolucao_coletar", () => {
  const semear = async () => { for (const r of lote(3, "Raízen", "sec.gov")) await env.RADAR_KV.put("radar:verif:attempt:" + r.id, JSON.stringify(r)); };
  it("sem credencial: 403", async () => {
    expect((await chamar({ action: "evolucao_coletar" })).status).toBe(403);
    expect((await chamar({ action: "evolucao_coletar", routine_key: "errada" })).status).toBe(403);
  });
  it("padrao e simulacao: devolve derivadas e NAO grava nada", async () => {
    await semear();
    const j = await (await chamar({ action: "evolucao_coletar", admin_senha: ADMIN })).json();
    expect(j).toMatchObject({ ok: true, simulacao: true, lidos: 3 });
    expect(j.propostas).toHaveLength(2);
    expect((await env.RADAR_KV.list({ prefix: "evolucao:" })).keys).toHaveLength(0);
  });
  it("aplicar grava so no livro, uma vez; segunda coleta nao duplica; tentativas intactas", async () => {
    await semear();
    const a = await (await chamar({ action: "evolucao_coletar", routine_key: ROTINA, aplicar: true })).json();
    expect(a).toMatchObject({ ok: true, simulacao: false, derivadas: 2, criadas: 2, ja_existiam: 0 });
    const b = await (await chamar({ action: "evolucao_coletar", admin_senha: ADMIN, aplicar: true })).json();
    expect(b).toMatchObject({ criadas: 0, ja_existiam: 2 });
    const itens = (await listarEvolucao(env.RADAR_KV, "vix_core")).itens;
    expect(itens.map((i) => [i.estado, i.origem])).toEqual([["proposta", "rotina"], ["proposta", "rotina"]]);
    expect((await env.RADAR_KV.list({ prefix: "radar:verif:attempt:" })).keys).toHaveLength(3);
  });
  it("tenant desconhecido: 400", async () => {
    expect((await chamar({ action: "evolucao_coletar", admin_senha: ADMIN, tenant: "x" })).status).toBe(400);
  });
});
