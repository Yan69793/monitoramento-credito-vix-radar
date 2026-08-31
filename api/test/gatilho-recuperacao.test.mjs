import { describe, expect, it } from "vitest";
import { aplicarRegrasNegocio, PALAVRAS_CRITICAS } from "../src/worker.js";

// BRASKEMDETECT1 (2026-08-24). A Braskem protocolou recuperacao extrajudicial
// (US$ 10,9 bi) e a noturna das 16h nao trouxe. Duas causas somadas: o ZIP
// ipe_cia_aberta_2026.zip estava em 404 (CVMURL404, gatilho primario morto) e a
// busca de imprensa nao alcancou o protocolo. Alem da query de busca (R5), a
// camada deterministica de promocao (aplicarRegrasNegocio -> PALAVRAS_CRITICAS)
// so reconhecia "recuperacao judicial", nunca "extrajudicial". Como a substring
// "recuperacao judicial" nao existe dentro de "recuperacao extrajudicial", um
// evento classificado RELEVANTE com essa descricao passava intacto.
//
// Prova reversa embutida: contra o codigo antigo (PALAVRAS_CRITICAS sem o termo
// extrajudicial), o teste 1 e o 2 falham porque o evento continua RELEVANTE e a
// flag _promovido_automaticamente nao existe. O contraexemplo e fixo: protocolo
// da Braskem de 24/08, nao dado inventado.

describe("BRASKEMDETECT1: gatilho de recuperacao extrajudicial", () => {
  it("descricao com 'recuperacao extrajudicial' promove RELEVANTE -> CRITICO", () => {
    const res = aplicarRegrasNegocio({
      empresa: "Braskem",
      classificacao: "RELEVANTE",
      descricao: "Conselho aprova pedido de recuperacao extrajudicial para reestruturar US$ 10,9 bilhoes",
      data_evento: "2026-08-24",
      tags: ["reestruturacao"]
    }, "2026-08-31");
    expect(res).not.toBeNull();
    expect(res.classificacao).toBe("CRITICO");
    expect(res._promovido_automaticamente).toBe(true);
  });

  it("variante acentuada 'recuperação extrajudicial' tambem promove", () => {
    const res = aplicarRegrasNegocio({
      empresa: "Braskem",
      classificacao: "RELEVANTE",
      descricao: "Pedido de recuperação extrajudicial protocolado na CVM",
      data_evento: "2026-08-24",
      tags: ["reestruturacao"]
    }, "2026-08-31");
    expect(res).not.toBeNull();
    expect(res.classificacao).toBe("CRITICO");
  });

  it("PALAVRAS_CRITICAS contem o termo extrajudicial nas duas formas", () => {
    expect(PALAVRAS_CRITICAS).toContain("recuperacao extrajudicial");
    expect(PALAVRAS_CRITICAS).toContain("recuperação extrajudicial");
  });

  it("evento ja CRITICO nao muda e nao ganha flag de promocao", () => {
    const res = aplicarRegrasNegocio({
      empresa: "Braskem",
      classificacao: "CRITICO",
      descricao: "Conselho aprova pedido de recuperacao extrajudicial",
      data_evento: "2026-08-24",
      tags: ["recuperacao-judicial"]
    }, "2026-08-31");
    expect(res.classificacao).toBe("CRITICO");
    expect(res._promovido_automaticamente).toBeUndefined();
  });

  it("evento fora da janela de 30 dias e descartado (null)", () => {
    const res = aplicarRegrasNegocio({
      empresa: "Braskem",
      classificacao: "RELEVANTE",
      descricao: "Conselho aprova pedido de recuperacao extrajudicial",
      data_evento: "2026-01-01",
      tags: ["reestruturacao"]
    }, "2026-08-31");
    expect(res).toBeNull();
  });
});
