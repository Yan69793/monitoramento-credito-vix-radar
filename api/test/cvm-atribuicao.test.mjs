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

// ─────────────────────────────────────────────────────────────────────────────
// SUBSTRINGDONO1, fase CNPJ (2026-08-25).
//
// A fase anterior consertou o casamento por nome. Estes testes travam a mudanca
// seguinte, que e o nome parar de decidir. O motivo de nao bastar consertar o nome
// esta medido no proprio arquivo: mesmo com ancora de inicio de palavra, "AGRO
// INDUSTRIAS DO VALE SAO FRANCISCO" e "VALE BONITO AGROPECUARIA" continuam casando
// com o emissor Vale, porque VALE comeca palavra nas duas. Ancora nao salva quando
// o nome do emissor e palavra comum do portugues. CNPJ salva.
// ─────────────────────────────────────────────────────────────────────────────

const CNPJ_CSN = "33.042.730/0001-04";           // CIA SIDERURGICA NACIONAL
const CNPJ_CSN_MINERACAO = "08.902.291/0001-15"; // CSN MINERACAO S.A.
const CNPJ_CEMIG = "17.155.730/0001-64";         // primario, CIA ENERG MINAS GERAIS
const CNPJ_CEMIG_DIST = "06.981.180/0001-16";    // subsidiaria que protocola
const CNPJ_VALE = "33.592.510/0001-54";          // VALE S.A.
const CNPJ_AGRO_VALE = "13.642.699/0001-35";     // AGRO INDUSTRIAS DO VALE SAO FRANCISCO
const CNPJ_ZERADO = "00.000.000/0000-00";        // entidade estrangeira

function docCnpj(cnpj, razaoSocial, categoria = "Fato Relevante") {
  const d = hojeBRT();
  return { e: razaoSocial, j: cnpj, d, de: d, c: categoria, a: "assunto de teste", l: "https://exemplo.invalid/doc" };
}

async function quarentena() {
  const r = await SELF.fetch("https://exemplo.invalid/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "admin_cvm_quarentena", admin_senha: env.ADMIN_PASSWORD })
  });
  expect(r.status).toBe(200);
  const j = await r.json();
  expect(j.ok).toBe(true);
  return j;
}

describe("SUBSTRINGDONO1 fase CNPJ - o nome deixa de decidir", () => {
  describe("caso ruim: o que o nome errava, o CNPJ acerta", () => {
    it("nome que casa com Vale nao vira documento da Vale quando o CNPJ e de outra empresa", async () => {
      // O caso que a ancora de inicio de palavra NAO pega. Sem CNPJ este documento
      // seria da Vale, com CNPJ ele nao e de ninguem.
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        docCnpj(CNPJ_VALE, "VALE S.A."),
        docCnpj(CNPJ_AGRO_VALE, "AGRO INDÚSTRIAS DO VALE SÃO FRANCISCO S/A")
      ]));
      expect(await documentosDe("Vale")).toEqual(["VALE S.A."]);
    });

    it("CNPJ desconhecido nao e atribuido a ninguem, mesmo com nome sugestivo", async () => {
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([docCnpj(CNPJ_AGRO_VALE, "AGRO INDÚSTRIAS DO VALE SÃO FRANCISCO S/A")]));
      for (const emissor of ["Vale", "CSN", "CEMIG", "Oi"]) {
        expect(await documentosDe(emissor)).toEqual([]);
      }
    });

    it("o CNPJ manda mesmo quando o nome aponta para outro emissor", async () => {
      // Razao social propositalmente enganosa. Se o nome ainda decidisse, este
      // documento iria para a CSN Mineracao. O CNPJ e da CSN.
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([docCnpj(CNPJ_CSN, "CSN MINERAÇÃO S.A.")]));
      expect(await documentosDe("CSN")).toEqual(["CSN MINERAÇÃO S.A."]);
      expect(await documentosDe("CSN Mineração")).toEqual([]);
    });
  });

  describe("caso bom: quem tem CNPJ declarado recebe", () => {
    it("CSN e CSN Mineracao recebem cada uma o seu, pelo CNPJ", async () => {
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        docCnpj(CNPJ_CSN, "CIA SIDERURGICA NACIONAL"),
        docCnpj(CNPJ_CSN_MINERACAO, "CSN MINERAÇÃO S.A.")
      ]));
      expect(await documentosDe("CSN")).toEqual(["CIA SIDERURGICA NACIONAL"]);
      expect(await documentosDe("CSN Mineração")).toEqual(["CSN MINERAÇÃO S.A."]);
    });

    it("subsidiaria da familia conta para a holding", async () => {
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        docCnpj(CNPJ_CEMIG, "CIA ENERG MINAS GERAIS - CEMIG"),
        docCnpj(CNPJ_CEMIG_DIST, "CEMIG DISTRIBUIÇÃO S/A")
      ]));
      const docs = await documentosDe("CEMIG");
      expect(docs).toContain("CIA ENERG MINAS GERAIS - CEMIG");
      expect(docs).toContain("CEMIG DISTRIBUIÇÃO S/A");
    });

    it("a atribuicao declara por onde chegou", async () => {
      // Sem este campo nao da para medir cobertura, e sem medir cobertura a
      // renomeacao volta a ser invisivel ate alguem notar card errado.
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([docCnpj(CNPJ_CSN, "CIA SIDERURGICA NACIONAL")]));
      const r = await SELF.fetch("https://exemplo.invalid/", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "admin_documentos_cvm", admin_senha: env.ADMIN_PASSWORD, empresa: "CSN" })
      });
      const j = await r.json();
      expect(j.documentos[0].atribuicao).toBe("cnpj");
      expect(j.documentos[0].cnpj_cvm).toBe(CNPJ_CSN);
    });
  });

  describe("compatibilidade: o painel nao pode esvaziar no deploy", () => {
    it("registro antigo sem CNPJ continua atribuido pelo nome", async () => {
      // Os registros ja gravados em cvm:documentos nao tem o campo `j`. Entre o
      // deploy e o primeiro sync novo, eles precisam continuar valendo.
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        { e: "CIA SIDERURGICA NACIONAL", d: hojeBRT(), de: hojeBRT(), c: "Fato Relevante", a: "sem campo j", l: "https://exemplo.invalid/doc" }
      ]));
      expect(await documentosDe("CSN")).toEqual(["CIA SIDERURGICA NACIONAL"]);
    });

    it("CNPJ zerado da CVM tambem cai no arbitro por nome", async () => {
      // A CVM publica entidade estrangeira com 00.000.000/0000-00. Tratar isso como
      // CNPJ valido mandaria o documento para quarentena para sempre.
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([docCnpj(CNPJ_ZERADO, "JBS N.V.")]));
      expect(await documentosDe("JBS")).toEqual(["JBS N.V."]);
    });
  });

  describe("fila de revisao: o descarte deixa de ser silencioso", () => {
    it("CNPJ desconhecido aparece na fila, com contagem e sugestao", async () => {
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        docCnpj(CNPJ_CSN, "CIA SIDERURGICA NACIONAL"),
        docCnpj(CNPJ_AGRO_VALE, "AGRO INDÚSTRIAS DO VALE SÃO FRANCISCO S/A"),
        docCnpj(CNPJ_AGRO_VALE, "AGRO INDÚSTRIAS DO VALE SÃO FRANCISCO S/A", "Comunicado ao Mercado")
      ]));
      const q = await quarentena();
      expect(q.entidades_em_quarentena).toBe(1);
      expect(q.fila[0].cnpj).toBe(CNPJ_AGRO_VALE);
      expect(q.fila[0].documentos).toBe(2);
      // A sugestao por nome e pista para quem decide, e nao atribuicao.
      expect(q.fila[0].sugestao_por_nome).toBe("Vale");
      expect(await documentosDe("Vale")).toEqual([]);
    });

    it("acervo todo declarado devolve fila vazia e cobertura cheia", async () => {
      await env.RADAR_KV.put(KEY_DOCS, JSON.stringify([
        docCnpj(CNPJ_CSN, "CIA SIDERURGICA NACIONAL"),
        docCnpj(CNPJ_CEMIG_DIST, "CEMIG DISTRIBUIÇÃO S/A")
      ]));
      const q = await quarentena();
      expect(q.entidades_em_quarentena).toBe(0);
      expect(q.fila).toEqual([]);
      expect(q.cobertura.cnpj).toBe(2);
      expect(q.cobertura.quarentena).toBe(0);
      expect(q.cobertura_pct).toBe(100);
    });

    it("a fila exige senha de admin", async () => {
      const r = await SELF.fetch("https://exemplo.invalid/", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "admin_cvm_quarentena" })
      });
      expect(r.status).toBe(403);
    });
  });
});
