import { describe, expect, it } from "vitest";
import { _cvmChaveDoc, _enetExtrairLinhas, _enetInterpretarResposta, _enetLinhaNormalizada } from "../src/worker.js";

function linha(linkArgs = "'1','2','123','IPE'") {
  return [
    "00417-0",
    "Vale S.A.",
    "Fato Relevante",
    "tipo",
    "Assunto de fixture",
    "10/09/2026",
    "11/09/2026",
    "Ativo",
    "1",
    "VALE",
    `<a onclick="OpenDownloadDocumentos(${linkArgs})">$#</a>`,
    "FR",
    ""
  ].join("$&");
}

describe("CVM ENETWeb", () => {
  it("preserva delimitadores HTML e normaliza a linha de 13 campos", () => {
    const linhas = _enetExtrairLinhas(linha());
    expect(linhas).toHaveLength(1);
    expect(linhas[0]).toHaveLength(13);
    const doc = _enetLinhaNormalizada(linhas[0], { "4170": { e: "Vale S.A.", j: "00.000.000/0001-00" } });
    expect(doc).toMatchObject({ e: "Vale S.A.", d: "2026-09-10", de: "2026-09-11", c: "Fato Relevante" });
    expect(doc.l).toContain("numProtocolo=123");
  });

  it("lê temErro e dados dentro do envelope d", () => {
    const ok = _enetInterpretarResposta({ d: { temErro: false, expirouSessao: false, msgErro: "", dados: "05010-5$&CITIGROUP INC." } }, true);
    expect(ok.dados).toContain("05010-5");
    expect(ok.vazio).toBe(false);
    expect(_enetInterpretarResposta({ d: { temErro: false, expirouSessao: false, msgErro: "", dados: "" } }, true).vazio).toBe(true);
    expect(() => _enetInterpretarResposta({ d: { temErro: true, msgErro: "indisponivel", dados: "" } }, true)).toThrow("enet_indisponivel");
    expect(() => _enetInterpretarResposta({ d: { temErro: false, SolicitarCaptcha: "S", dados: "x" } }, true)).toThrow("enet_payload_invalido");
  });

  it("usa l como identidade e mantém colisão de protocolo com links distintos", () => {
    const a = _enetLinhaNormalizada(_enetExtrairLinhas(linha())[0], {});
    const b = _enetLinhaNormalizada(_enetExtrairLinhas(linha("'9','2','123','IPE'") )[0], {});
    expect(_cvmChaveDoc({ link: a.l, categoria: a.c, data: a.d, assunto: a.a })).not.toBe(_cvmChaveDoc({ link: b.l, categoria: b.c, data: b.d, assunto: b.a }));
    expect(a.l).not.toBe(b.l);
    expect(a._protocolo).toBe(b._protocolo);
  });
});
