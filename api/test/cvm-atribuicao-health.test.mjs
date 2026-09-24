import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CNPJ_FAMILIA_CVM, _coberturaAtribuicaoAcervo } from "../src/worker.js";

// CFG-02 P2 (2026-09-21). O health separa a origem da atribuicao do fluxo de
// ingestao. A conta do sync precisa fechar, recebidos = atribuidos + quarentena
// + descartados, para que cobertura de 100% do acervo nunca esconda perda antes
// da gravacao.
const META_KEY = "cvm:fonte_meta";

function hojeISO() { return new Date(Date.now() - 3 * 60 * 60 * 1e3).toISOString().slice(0, 10); }
async function health() {
  const res = await SELF.fetch("https://example.com/");
  expect(res.status).toBe(200);
  return res.json();
}
async function seedMeta(extra) {
  await env.RADAR_KV.put(META_KEY, JSON.stringify(Object.assign({
    ok: true,
    sincronizado_em: new Date().toISOString(),
    last_modified_iso: hojeISO(),
    max_data_entrega: hojeISO(),
    falhas_consecutivas: 0,
    origem: "teste_cfg02"
  }, extra)));
}

describe("CFG-02 P2 - health separa origem de atribuicao do descarte de ingestao", () => {
  beforeEach(async () => {
    await env.RADAR_KV.delete(META_KEY);
    await env.RADAR_KV.delete("cvm:documentos");
  });

  it("T2 legado: descarte historico entra na conta de recebidos, sem fingir cobertura total", async () => {
    await seedMeta({
      documentos: 796,
      descartados_allowlist: 9426,
      cobertura_atribuicao: { cnpj: 441, nome: 355, quarentena: 0, sem_dono: 0 },
      cobertura: { portal: { total: 10222, resolvidos: 796, pct: 7.79 }, zip: { total: 800, resolvidos: 796 } }
    });
    const b = await health();
    expect(b.cvm_atribuicao_quarentena).toBe(0);
    expect(b.cvm_atribuicao_por_cnpj).toBe(441);
    expect(b.cvm_atribuicao_por_nome).toBe(355);
    expect(b.cvm_atribuicao_sem_dono).toBe(0);
    expect(b.cvm_atribuicao_cobertura_pct).toBe(100);
    expect(b.cvm_ingestao_descartados_sem_dono).toBe(9426);
    expect(b.cvm_ingestao_recebidos).toBe(10222);
    expect(b.cvm_ingestao_atribuidos).toBe(796);
    expect(b.cvm_ingestao_quarentena).toBe(0);
    expect(b.cvm_ingestao_descartados).toBe(9426);
  });

  it("T2 novo: documento sem dono permanece em quarentena e nada e descartado", async () => {
    await seedMeta({
      documentos: 800,
      descartados_allowlist: 0,
      descartados_teto: 0,
      cobertura_atribuicao: { cnpj: 441, nome: 355, quarentena: 2, sem_dono: 2 }
    });
    const b = await health();
    expect(b.cvm_ingestao_recebidos).toBe(800);
    expect(b.cvm_ingestao_atribuidos).toBe(796);
    expect(b.cvm_ingestao_quarentena).toBe(4);
    expect(b.cvm_ingestao_descartados).toBe(0);
    expect(b.cvm_ingestao_recebidos).toBe(b.cvm_ingestao_atribuidos + b.cvm_ingestao_quarentena + b.cvm_ingestao_descartados);
  });

  // T2, ponta ruim: meta legado {portal,zip}. Antes, quarentena = total - resolvidos
  // = 9426 e cnpj/nome recebiam zip/portal. Agora nao ha origem medida, entao
  // null, nunca um numero derivado do descarte.
  it("T2 ruim: meta legado portal/zip nao vira quarentena nem cnpj/nome", async () => {
    await seedMeta({
      documentos: 796,
      descartados_allowlist: 9426,
      cobertura: { portal: { total: 10222, resolvidos: 796, pct: 7.79 }, zip: { total: 800, resolvidos: 796 } }
    });
    const b = await health();
    expect(b.cvm_atribuicao_quarentena).toBeNull();
    expect(b.cvm_atribuicao_por_cnpj).toBeNull();
    expect(b.cvm_atribuicao_por_nome).toBeNull();
    expect(b.cvm_atribuicao_cobertura_pct).toBeNull();
    expect(b.cvm_atribuicao_quarentena).not.toBe(9426);
    expect(b.cvm_ingestao_descartados_sem_dono).toBe(9426);
    expect(b.cvm_ingestao_recebidos).toBeNull();
    expect(b.cvm_ingestao_atribuidos).toBeNull();
    expect(b.cvm_ingestao_quarentena).toBeNull();
    expect(b.cvm_ingestao_descartados).toBeNull();
  });

  it("T2: sem descarte gravado, o campo de descarte e null e nao zero", async () => {
    await seedMeta({ documentos: 10, cobertura: { cnpj: 10, nome: 0, quarentena: 0, sem_dono: 0 } });
    const b = await health();
    expect(b.cvm_ingestao_descartados_sem_dono).toBeNull();
    expect(b.cvm_atribuicao_por_cnpj).toBe(10);
    expect(b.cvm_ingestao_recebidos).toBe(10);
    expect(b.cvm_ingestao_atribuidos).toBe(10);
    expect(b.cvm_ingestao_quarentena).toBe(0);
    expect(b.cvm_ingestao_descartados).toBe(0);
  });
});

describe("CFG-02 P2 - T3 invariante de soma da cobertura de atribuicao", () => {
  const cnpjDeclarado = Object.keys(CNPJ_FAMILIA_CVM)[0];
  const docs = [
    { j: cnpjDeclarado, e: "QUALQUER NOME" },          // cnpj declarado -> cnpj
    { j: "12.345.678/0001-95", e: "ENTIDADE X" },      // cnpj presente e nao declarado -> quarentena
    { j: "12.345.678/0001-95", e: "ENTIDADE X" },
    { j: "00.000.000/0000-00", e: "ZZZ SEM DONO SA" }, // cnpj zerado, nome sem alias -> sem_dono
    { j: "", e: "ZZZ SEM DONO SA" }                    // sem cnpj -> sem_dono
  ];

  it("T3 bom: cnpj+nome+quarentena+sem_dono = total do acervo", () => {
    const c = _coberturaAtribuicaoAcervo(docs);
    expect(c.cnpj + c.nome + c.quarentena + c.sem_dono).toBe(docs.length);
    expect(c.cnpj).toBe(1);
    expect(c.quarentena).toBe(2);
    expect(c.sem_dono).toBe(2);
  });

  // Ponta ruim: a derivacao de 20773 pre-correcao (quarentena = portal.total -
  // portal.resolvidos) nao respeita a invariante contra o acervo real. 10222
  // recebidos no portal, 796 no acervo: 796 + 654 + 9426 = 10876 != 796.
  it("T3 ruim: a formula antiga viola a invariante e a nova nao", () => {
    const portal = { total: 10222, resolvidos: 796 };
    const zip = { resolvidos: 796 };
    const antiga = { cnpj: zip.resolvidos, nome: 654, quarentena: portal.total - portal.resolvidos };
    expect(antiga.cnpj + antiga.nome + antiga.quarentena).not.toBe(796);
    const acervo = Array.from({ length: 796 }, () => ({ j: cnpjDeclarado, e: "X" }));
    const c = _coberturaAtribuicaoAcervo(acervo);
    expect(c.cnpj + c.nome + c.quarentena + c.sem_dono).toBe(796);
  });

  it("T3: entrada vazia ou invalida nao lanca e soma zero", () => {
    expect(_coberturaAtribuicaoAcervo([])).toEqual({ cnpj: 0, nome: 0, quarentena: 0, sem_dono: 0 });
    expect(_coberturaAtribuicaoAcervo(null)).toEqual({ cnpj: 0, nome: 0, quarentena: 0, sem_dono: 0 });
  });
});
