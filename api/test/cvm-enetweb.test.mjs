import { describe, expect, it } from "vitest";
import { _cvmChaveDoc, _cvmPisoMetodologia, _enetExtrairLinhas, _enetInterpretarResposta, _enetLinhaNormalizada } from "../src/worker.js";

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

  it("calcula bootstrap próprio e reativa relativo só após metodologia igual", () => {
    expect(_cvmPisoMetodologia({ metodologia_id: "antiga" }, 4000, 1374)).toMatchObject({ piso: 961, bootstrap: 961, dinamico: 0, rebase: true });
    expect(_cvmPisoMetodologia({ metodologia_id: "enetweb_allowlist_v2" }, 1374, 1374)).toMatchObject({ piso: 961, dinamico: 961, rebase: false });
  });
  // PISOORFAO1 (2026-09-18). Com base anterior na mesma metodologia, o piso e o
  // dinamico. Antes, uma base de 441 recebia piso 961 (bootstrap de 0.7 x 1374) e o
  // sync ficava bloqueado por construcao, porque o universo real da carteira estava
  // bem abaixo da constante. Medido em producao: 441 candidatos contra piso 961,
  // bloqueio de 14/09 a 18/09, feed sem evento novo. A prova reversa e o primeiro
  // caso: antes da correcao ele dava piso 961 e bloqueava, agora da 308 e passa.
  it("PISOORFAO1: base menor que o bootstrap nao cria piso inalcancavel", () => {
    expect(_cvmPisoMetodologia({ metodologia_id: "enetweb_allowlist_v2" }, 441, 1374)).toMatchObject({ piso: 308, dinamico: 308, bootstrap: 961, modo: "dinamico" });
    // A protecao contra encolhimento continua: 0.7 x base anterior ainda e o chao.
    expect(_cvmPisoMetodologia({ metodologia_id: "enetweb_allowlist_v2" }, 1000, 1374)).toMatchObject({ piso: 700, modo: "dinamico" });
    // Sem base comparavel (primeira execucao ou troca de metodologia), segue o bootstrap.
    expect(_cvmPisoMetodologia(null, 0, 1374)).toMatchObject({ piso: 961, modo: "bootstrap" });
  });
  it("nunca usa o código 05010 como cadastro e preserva CITIGROUP por nome", () => {
    const cols = linha().split("$&");
    cols[0] = "05010-5";
    cols[1] = "CITIGROUP INC.";
    const doc = _enetLinhaNormalizada(cols, { "5010": { e: "CURTUMES" , j: "00.000.000/0001-00" } });
    expect(doc.e).toBe("CITIGROUP INC.");
    expect(doc.j).toBe("");
    expect(doc.e).not.toBe("CURTUMES");
  });
  it("usa l como identidade e mantém colisão de protocolo com links distintos", () => {
    const a = _enetLinhaNormalizada(_enetExtrairLinhas(linha())[0], {});
    const b = _enetLinhaNormalizada(_enetExtrairLinhas(linha("'9','2','123','IPE'") )[0], {});
    expect(_cvmChaveDoc({ link: a.l, categoria: a.c, data: a.d, assunto: a.a })).not.toBe(_cvmChaveDoc({ link: b.l, categoria: b.c, data: b.d, assunto: b.a }));
    expect(a.l).not.toBe(b.l);
    expect(a._protocolo).toBe(b._protocolo);
  });
});
