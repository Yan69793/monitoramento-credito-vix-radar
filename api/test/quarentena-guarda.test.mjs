import { describe, expect, it } from "vitest";
import { avaliarQuarentena } from "../../scripts/lib/quarentena-guarda.mjs";

// CFG-02 P3 (2026-09-21). check-quarentena-emissores.mjs saia 0 com
// "nenhuma das 0 entidades", aprovando conjunto vazio enquanto o health
// declarava 9426 documentos descartados. T4 trava as duas pontas da decisao.
const soDigito = (s) => String(s || "").replace(/\D/g, "");
const donoPorCnpj = { "11222333000181": "EMISSOR_A" };
const base = { donoPorCnpj, soDigito };

describe("CFG-02 P3 - T4 guarda de quarentena nao aprova vacuo", () => {
  it("ruim: fila vazia com descarte positivo reprova (codigo 3)", () => {
    const r = avaliarQuarentena({ ...base, fila: [], entidades: 0, descartados: 9426 });
    expect(r.codigo).toBe(3);
    expect(r.motivo).toBe("fila_vazia_com_descarte_positivo");
  });

  it("ruim: fila vazia e descarte nao medivel reprova (codigo 4)", () => {
    expect(avaliarQuarentena({ ...base, fila: [], entidades: 0, descartados: null }).codigo).toBe(4);
    expect(avaliarQuarentena({ ...base, fila: [], entidades: 0, descartados: undefined }).codigo).toBe(4);
  });

  it("ruim: emissor dos 103 na fila continua reprovando (codigo 1)", () => {
    const r = avaliarQuarentena({ ...base, fila: [{ cnpj: "11.222.333/0001-81", nome: "A", documentos: 3 }], entidades: 1, descartados: 3 });
    expect(r.codigo).toBe(1);
    expect(r.falhas[0].emissor).toBe("EMISSOR_A");
  });

  it("bom: fila vazia com descarte zero medido aprova", () => {
    expect(avaliarQuarentena({ ...base, fila: [], entidades: 0, descartados: 0 }).codigo).toBe(0);
  });

  it("bom: fila com entidade fora dos 103 aprova", () => {
    const r = avaliarQuarentena({ ...base, fila: [{ cnpj: "99.999.999/0001-99", nome: "FORA", documentos: 5 }], entidades: 1, descartados: 5 });
    expect(r.codigo).toBe(0);
  });

  it("bom: fila nao vazia aprova mesmo sem medir descarte", () => {
    const r = avaliarQuarentena({ ...base, fila: [{ cnpj: "99.999.999/0001-99", nome: "FORA", documentos: 5 }], entidades: 1, descartados: null });
    expect(r.codigo).toBe(0);
  });
});
