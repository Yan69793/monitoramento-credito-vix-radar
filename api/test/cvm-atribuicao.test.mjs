import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

// SUBSTRINGDONO1 (auditoria 2026-08-25).
//
// A rotina matinal de 25/08 entregou, no campo cvm_documentos do plano:
//   - para o emissor "Oi", 28 documentos, dos quais 4 eram da Oi. O resto era
//     SEQUOIA LOGISTICA, TRES TENTOS AGROINDUSTRIAL, SANEAMENTO DE GOIAS,
//     EQUATORIAL GOIAS e CONCESSIONARIA PONTE RIO-NITEROI. Nenhuma dessas razoes
//     sociais tem "Oi" como palavra: o que casava era a substring "OI" dentro de
//     SEQU(OI)A, AGR(OI)NDUSTRIAL, G(OI)AS e NITER(OI).
//   - para o emissor "CSN", 5 documentos, todos da CSN MINERACAO, que e outro
//     emissor da carteira, com outro CNPJ. Exatamente os mesmos 5 que o plano
//     entregava para "CSN Mineracao".
//
// O dano nao foi cosmetico. Em 31/07/2026 a Fitch rebaixou a CSN de B para CCC+,
// o relatorio foi protocolado na CVM em 05/08 sob "CIA SIDERURGICA NACIONAL", e a
// rotina caiu para imprensa por nao ter fonte primaria. Nao tinha mesmo: a CSN
// nao tinha alias declarado, "CIA SIDERURGICA NACIONAL" nao contem "CSN", e o
// documento nunca chegava a entrar em cvm:documentos. A aparencia de saude vinha
// do defeito vizinho, que enchia o campo com documento da mineradora.
//
// Este arquivo trava as duas pontas de cada guarda (regra 5 do CLAUDE.md):
// reprova o caso ruim E aceita o caso bom. Uma ponta so esconderia a regressao
// obvia, que e uma atribuicao que rejeita tudo e passa no teste de contaminacao.

const KEY_DOCS = "cvm:documentos";

// Razoes sociais reais, copiadas do ipe_cia_aberta_2026.csv e do cad_cia_aberta.csv
// da CVM em 25/08/2026. Acento incluido de proposito: o casamento e sem acento dos
// dois lados (ACENTOMATCH1) e o teste tem que exercitar isso.
const OI_REAL = "OI S.A. - EM RECUPERAÇÃO JUDICIAL";
const SEQUOIA = "SEQUOIA LOGÍSTICA E TRANSPORTES S.A.";
const TRES_TENTOS = "TRÊS TENTOS AGROINDUSTRIAL S.A.";
const SANEAGO = "SANEAMENTO DE GOIAS SA";
const EQUATORIAL_GO = "EQUATORIAL GOIAS DISTRIBUIDORA DE ENERGIA S.A.";
const ECOPONTE = "CONCESSIONARIA PONTE RIO-NITERÓI S.A. - ECOPONTE";
const CSN_MINERACAO = "CSN MINERAÇÃO S.A.";
const CSN_PROPRIA = "CIA SIDERURGICA NACIONAL";
// Aliases deliberadamente prefixo, que a ancora de inicio de palavra NAO pode
// quebrar: o termo declarado e "SENDAS DISTRIB" e "MOVIDA PART", mais curtos que a
// razao social publicada. Se a ancora fosse exigida nas duas pontas, estes dois
// parariam de casar e a correcao trocaria um bug por outro.
const SENDAS = "SENDAS DISTRIBUIDORA S.A.";
const MOVIDA = "MOVIDA PARTICIPACOES S.A.";
// NOMEMORTO1 nao pode regredir: emissor renomeado continua achando documento.
const AXIA = "AXIA ENERGIA S.A.";
// Os cinco que a tabela de ingestao aposentada descartava na porta. Cada um tinha
// alias em SYNC_ALIAS_TO_EMPRESA e nao tinha em SYNC_ALIAS_NOMES_CVM, entao a
// atribuicao sabia de quem era e o documento nunca chegava a ser gravado. Razoes
// sociais conferidas no ipe_cia_aberta_2026.csv de 25/08/2026.
const CINCO_CEGOS = [
  ["DIAGNOSTICOS DA AMERICA SA", "Dasa"],
  ["NATURA COSMETICOS SA", "Natura &Co"],
  ["TELEFÔNICA BRASIL S.A.", "Vivo (Telefônica Brasil)"],
  ["TIM S.A.", "TIM Brasil"],
  ["TRANSMISSORA ALIANÇA DE ENERGIA ELÉTRICA S.A.", "Taesa"]
];
// Copasa: mesmo buraco da CSN, achado pela guarda nova. A razao social e
// "COMPANHIA DE SANEAMENTO DE MINAS GERAIS" e o nome COPASA so existe no
// DENOM_COMERC do cadastro, campo que o ipe_cia_aberta nao publica.
const COPASA = "COMPANHIA DE SANEAMENTO DE MINAS GERAIS";

function hojeBRT() {
  // Mesmo relogio do Worker (obterAgoraBRT subtrai 3h fixas). Usar UTC aqui faria
  // o teste passar de dia e quebrar depois das 21h BRT, quando a data UTC ja virou.
  return new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString().split("T")[0];
}

function doc(razaoSocial, categoria = "Fato Relevante", assunto = "assunto de teste") {
  const d = hojeBRT();
  return { e: razaoSocial, d, de: d, c: categoria, a: assunto, l: "https://exemplo.invalid/doc" };
}

// Cada razao social entra com UM documento, para que a contagem devolvida seja
// legivel diretamente como "quais razoes sociais este emissor reivindicou".
const ACERVO = [
  doc(OI_REAL),
  doc(SEQUOIA),
  doc(TRES_TENTOS),
  doc(SANEAGO),
  doc(EQUATORIAL_GO),
  doc(ECOPONTE),
  doc(CSN_MINERACAO),
  doc(CSN_PROPRIA, "Dados Econômico-Financeiros", "Relatório de Agência de Rating - Fitch"),
  doc(SENDAS),
  doc(MOVIDA),
  doc(AXIA),
  doc(COPASA),
  ...CINCO_CEGOS.map(([razao]) => doc(razao))
];

async function documentosDe(empresa) {
  const r = await SELF.fetch("https://exemplo.invalid/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      action: "admin_documentos_cvm",
      admin_senha: env.ADMIN_PASSWORD,
      empresa
    })
  });
  expect(r.status).toBe(200);
  const j = await r.json();
  expect(j.ok).toBe(true);
  return j.documentos.map((d) => d.empresa_cvm);
}

describe("SUBSTRINGDONO1 - atribuicao de documento CVM por emissor", () => {
  beforeEach(async () => {
    await env.RADAR_KV.put(KEY_DOCS, JSON.stringify(ACERVO));
  });

  describe("caso ruim: o documento de um emissor nao pode aparecer em outro", () => {
    it("CSN nao recebe documento da CSN Mineracao", async () => {
      const docs = await documentosDe("CSN");
      expect(docs).not.toContain(CSN_MINERACAO);
    });

    it("Oi nao recebe documento de razao social que apenas contem a substring OI", async () => {
      const docs = await documentosDe("Oi");
      for (const intruso of [SEQUOIA, TRES_TENTOS, SANEAGO, EQUATORIAL_GO, ECOPONTE]) {
        expect(docs).not.toContain(intruso);
      }
    });

    it("Oi recebe apenas o que e dela", async () => {
      // A asercao forte. `not.toContain` item a item passaria se a lista viesse
      // com um intruso novo que ninguem lembrou de listar acima.
      expect(await documentosDe("Oi")).toEqual([OI_REAL]);
    });

    it("documento de companhia fora da carteira nao e atribuido a ninguem", async () => {
      // Sequoia, Tres Tentos, Saneago e Ecoponte nao sao emissores. Nenhum dos 103
      // pode reivindica-los.
      const orfaos = [SEQUOIA, TRES_TENTOS, SANEAGO, ECOPONTE];
      for (const emissor of ["Oi", "CSN", "CSN Mineração", "Equatorial Energia", "Vale", "Rumo"]) {
        const docs = await documentosDe(emissor);
        for (const orfao of orfaos) expect(docs).not.toContain(orfao);
      }
    });
  });

  describe("caso bom: quem tem documento continua recebendo", () => {
    it("CSN Mineracao recebe o documento da CSN Mineracao", async () => {
      expect(await documentosDe("CSN Mineração")).toEqual([CSN_MINERACAO]);
    });

    it("CSN recebe o documento da propria Cia Siderurgica Nacional", async () => {
      // A outra metade do incidente. Sem o alias novo, este emissor devolve lista
      // vazia mesmo com o relatorio da Fitch gravado no acervo.
      expect(await documentosDe("CSN")).toEqual([CSN_PROPRIA]);
    });

    it("Oi recebe o documento da Oi", async () => {
      expect(await documentosDe("Oi")).toContain(OI_REAL);
    });

    it("Equatorial Energia recebe o documento da subsidiaria Equatorial Goias", async () => {
      // Casamento legitimo por prefixo de palavra, que a correcao nao pode matar.
      expect(await documentosDe("Equatorial Energia")).toContain(EQUATORIAL_GO);
    });

    it("alias declarado como prefixo continua casando razao social mais longa", async () => {
      // "SENDAS DISTRIB" -> "SENDAS DISTRIBUIDORA S.A." e "MOVIDA PART" ->
      // "MOVIDA PARTICIPACOES S.A.". A ancora vale so no inicio do termo.
      expect(await documentosDe("Assaí Atacadista")).toContain(SENDAS);
      expect(await documentosDe("Movida")).toContain(MOVIDA);
    });

    it("NOMEMORTO1 nao regride: emissor renomeado continua achando documento", async () => {
      expect(await documentosDe("Eletrobras")).toContain(AXIA);
    });

    it("Copasa recebe documento da Companhia de Saneamento de Minas Gerais", async () => {
      expect(await documentosDe("Copasa")).toEqual([COPASA]);
    });

    it.each(CINCO_CEGOS)("%s pertence a %s", async (razao, emissor) => {
      // Estes cinco tinham alias na tabela de atribuicao e nao tinham na tabela de
      // ingestao, que era o unico jeito de o documento entrar em cvm:documentos.
      // Sabia-se de quem era e jogava-se fora na porta. Com um arbitro unico para
      // as duas pontas esse estado deixou de existir.
      expect(await documentosDe(emissor)).toContain(razao);
    });
  });

  describe("invariante: um documento tem no maximo um dono", () => {
    it("nenhuma razao social do acervo e reivindicada por dois emissores", async () => {
      // Varre a carteira inteira e monta o mapa inverso. E a asercao que teria
      // pegado o defeito sozinha: CSN e CSN Mineracao apareciam as duas como donas
      // do mesmo documento, e a Oi aparecia como dona de quatro documentos alheios.
      const r = await SELF.fetch("https://exemplo.invalid/", { method: "GET" });
      expect(r.status).toBe(200);

      const donos = new Map();
      const emissores = ACERVO.map((d) => d.e);
      const carteira = [
        "Oi", "CSN", "CSN Mineração", "Equatorial Energia", "Assaí Atacadista",
        "Movida", "Eletrobras", "Vale", "Gerdau", "Usiminas", "Rumo", "Sabesp",
        "Pão de Açúcar (GPA)", "Raízen", "Simpar", "Vamos", "JSL", "Copasa",
        ...CINCO_CEGOS.map(([, emissor]) => emissor)
      ];
      for (const emissor of carteira) {
        for (const razao of await documentosDe(emissor)) {
          if (!donos.has(razao)) donos.set(razao, []);
          donos.get(razao).push(emissor);
        }
      }
      const disputados = [...donos.entries()].filter(([, lista]) => lista.length > 1);
      expect(disputados, `razoes sociais com mais de um dono: ${JSON.stringify(disputados)}`).toEqual([]);
      expect(emissores.length).toBeGreaterThan(0);
    });
  });
});
