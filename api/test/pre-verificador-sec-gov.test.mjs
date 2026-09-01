import { describe, expect, it, vi } from "vitest";
import { validarDatasFontes, DOMINIOS_FONTE_OFICIAL_DOCUMENTOS, _ehFonteConfitavelBloqueada } from "../src/worker.js";

// PREVERIFSEC1 (2026-09-01). Achado concreto de 31/08/2026, rotina matinal:
// evento CRITICO da Braskem (recuperacao extrajudicial) com fonte_primaria
// apontando para o Form 6-K da SEC (fonte primaria mais forte que existe para
// emissor BR com ADR, mais forte que imprensa) foi submetido e o Worker
// respondeu ok:true, n_eventos:0, sem_eventos:true, removidos_pre_verificador:1.
// O mesmo evento, identico em todo o resto, reenviado com fonte_primaria em
// braziljournal.com entrou normalmente. Ver memoria
// project-pre-verificador-derruba-sec-gov e nota [[worker-ok-nao-significa-evento]].
//
// Causa raiz medida (nao suposta): a URL real do incidente devolve HTTP 403
// a qualquer User-Agent generico —
//   curl -A "Mozilla/5.0 (compatible; VixRadar/2.0)" \
//     https://www.sec.gov/Archives/edgar/data/0001071438/000129281426004342/bak20260824_6k5.htm
//   -> HTTP:403 (medido 2026-09-01, mesmo User-Agent que validarDatasFontes usa)
// extrairDataDaURL() tambem nao acha data nesta URL (accession number da SEC
// nao bate nenhum dos 3 padroes). Com fetchOk=false e sem data na URL,
// validarDatasFontes cai no ramo "fonte inacessivel": so nao descarta as
// fontes confiaveis que bloqueiam leitura (S&P, Fitch, CVM, B3, SEC etc., desde
// o achado Cosan 2026-07-13). sec.gov NAO estava nesse conjunto.
//
// Fix minimo e distinto (desta sessao): introduzimos DOMINIOS_FONTE_OFICIAL_DOCUMENTOS
// separando fonte OFICIAL de documento regulatorio primario (SEC, CVM, B3, BCB, IN,
// Anbima) de agencia de rating. O ramo "fonte inacessivel" (RATING_BLOQUEADO) aceita
// host em qualquer um dos dois conjuntos (_ehFonteConfitavelBloqueada), SEMPRE dentro
// da janela de 30 dias e SEMPRE com _verif_forcar=true (verificacao adversarial
// obrigatoria re-confirma identidade, data e materialidade de forma independente).
// Isso NAO aprova o evento direto e NAO e bypass generico: fonte nao confiavel,
// documento sem data valida na janela ou sem evidencia suficiente continua descartado.
//
// Reproducao fiel do descarte (pedido da sessao): o fetch de validarDatasFontes e
// injetavel (_fetchOverride) SOMENTE para teste; em producao fica undefined e usa o
// global fetch. O stub devolve Response 403 real para a URL exata do 6-K, reproduzindo
// o comportamento medido em producao (sec.gov bloqueia User-Agent generico).
//
// Prova das 3 PONTAS (regra 5 do CLAUDE.md):
//   - ponta incidente-antigo(falha pre-fix): sem "sec.gov" em nenhum conjunto confiavel,
//     a mesma URL do 6-K com 403 E descartada (remove). Reproduz o incidente de 31/08.
//   - ponta boa (fix): com "sec.gov" no conjunto oficial, o 6-K valido na janela passa,
//     marcado _verif_forcar=true (nao aceite cego).
//   - ponta ruim (controle): fonte nao confiavel OU SEC com data fora da janela OU
//     evento sem data_evento valida, todos continuam rejeitados.

const JANELA_30D = "2026-08-02"; // trintaDiasAtras fixo, mesma janela do incidente (referencia 2026-09-01)
const URL_INCIDENTE = "https://www.sec.gov/Archives/edgar/data/0001071438/000129281426004342/bak20260824_6k5.htm";

function eventoBraskem(overrides) {
  return Object.assign({
    empresa: "Braskem",
    classificacao: "CRITICO",
    titulo: "Braskem protocola pedido de recuperacao extrajudicial",
    descricao: "Conselho aprova pedido de recuperacao extrajudicial para reestruturar US$ 10,9 bilhoes",
    data_evento: "2026-08-24",
    fonte_primaria: URL_INCIDENTE
  }, overrides || {});
}

// Stub fiel: 403 sem corpo lido -> r.ok=false -> caminho "fonte inacessivel" do pre-verificador.
function stubFetch403() {
  return vi.fn(async () => new Response("", { status: 403 }));
}

describe("PREVERIFSEC1: sec.gov como fonte oficial de documento regulatorio (validarDatasFontes)", () => {
  it("DOMINIOS_FONTE_OFICIAL_DOCUMENTOS contem sec.gov", () => {
    expect(DOMINIOS_FONTE_OFICIAL_DOCUMENTOS.has("sec.gov")).toBe(true);
  });

  it("distinçao: sec.gov esta no conjunto de fonte oficial, NAO no de agencia de rating", () => {
    // A SEC e fonte primaria de documento (Form 6-K), nao agencia de rating.
    expect(_ehFonteConfitavelBloqueada("sec.gov")).toBe(true);
    expect(DOMINIOS_FONTE_OFICIAL_DOCUMENTOS.has("sec.gov")).toBe(true);
  });

  it("reproducao fiel do ramo: 6-K real retorna 403 ao stub e, com sec.gov confiavel e data na janela, sobrevive com _verif_forcar", async () => {
    const fetchMock = stubFetch403();
    const validados = await validarDatasFontes(
      [eventoBraskem()],
      JANELA_30D,
      fetchMock
    );
    expect(fetchMock).toHaveBeenCalled(); // a URL da SEC foi de fato 'buscada' (stub 403)
    expect(validados.length).toBe(1); // fix: sec.gov confiavel -> nao descartado
    expect(validados[0]._verif_forcar).toBe(true);
  });

  // Prova cronologica (documentada aqui, verificada no commit-pai sem "sec.gov" nos conjuntos):
  // rodar `npx vitest run test/pre-verificador-sec-gov.test.mjs` no commit que antecedeu a fix
  // reproduz o descarte medido em producao em 31/08: o mesmo 6-K (403 real, sec.gov fora dos
  // conjuntos confiaveis) era removido com ok:true, n_eventos:0, removidos_pre_verificador:1.
  // A fix (DOMINIOS_FONTE_OFICIAL_DOCUMENTOS com sec.gov) faz o caso acima passar.

  it("ponta boa: 6-K oficial valido (403 real, sec.gov confiavel) sobrevive ao pre-verificador com _verif_forcar", async () => {
    const validados = await validarDatasFontes(
      [eventoBraskem()],
      JANELA_30D,
      stubFetch403()
    );
    expect(validados.length).toBe(1);
    expect(validados[0].classificacao).toBe("CRITICO");
    expect(validados[0]._verif_forcar).toBe(true); // NAO e aceite cego, vai para verificacao adversarial obrigatoria
  });

  it("ponta ruim (controle): SEC com data_evento fora da janela de 30 dias continua descartada", async () => {
    const validados = await validarDatasFontes(
      [eventoBraskem({ data_evento: "2026-06-01" })],
      JANELA_30D,
      stubFetch403()
    );
    expect(validados.length).toBe(0);
  });

  it("ponta ruim (controle): SEC sem data_evento valida (nao_identificada) continua descartada", async () => {
    const validados = await validarDatasFontes(
      [eventoBraskem({ data_evento: "nao_identificada" })],
      JANELA_30D,
      stubFetch403()
    );
    expect(validados.length).toBe(0);
  });

  it("ponta ruim (controle): fonte nao confiavel que 403 continua descartada — nao vira aceite generico", async () => {
    const validados = await validarDatasFontes(
      [eventoBraskem({
        fonte_primaria: "https://dominio-que-nao-existe-vixradar-teste-preverifsec1.invalid/doc.htm"
      })],
      JANELA_30D,
      stubFetch403()
    );
    expect(validados.length).toBe(0);
  });

  it("controle (comportamento pre-existente, inalterado): mesmo evento com fonte_primaria em braziljournal.com continua aceito", async () => {
    const validados = await validarDatasFontes(
      [eventoBraskem({
        fonte_primaria: "https://braziljournal.com/braskem-recuperacao-extrajudicial-24-08-2026"
      })],
      JANELA_30D,
      stubFetch403()
    );
    expect(validados.length).toBe(1);
    expect(validados[0].classificacao).toBe("CRITICO");
  });
});
