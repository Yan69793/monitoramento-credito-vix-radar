// Adaptador de integracao reversivel do EWS 2.0 ao VIX Radar. Funcoes puras, sem IO, sem binding.
// NAO esta ligado ao Worker (api/src/worker.js intocado, G0-v1 item 11). Quando a homologacao e a autorizacao
// existirem, a ligacao e UMA chamada em op=predictive_v1 (ver CONTRATO.md), atras de flag desligada por padrao.
//
// Contrato de entrada (chave KV proposta `ews2:latest`, escrita so pelo pipeline local homologado):
//   { schema: "ews2/1", protocolo: "G0-v3", versao_pipeline, gerado_em, sha256_rotulos, homologacao: {g1a,g1b,g1c,g2,g3},
//     sinais_aprovados: ["H1", ...], exibir_probabilidade: bool, emissores: [{ cnpj, nome, sinais: {H1:0|1,...}, prob_180d|null, severidade }] }
// Flag: `ews2:flag` = {"ativo": false} por padrao. Sem flag, sem payload valido ou sem homologacao completa, o
// adaptador devolve o payload original SEM mudanca, e diz por que (campo ews2.motivo). Rollback = apagar a flag.

export const SCHEMA = "ews2/1";
export const SINAIS = ["H1", "H2a", "H2b", "H2c", "H3", "H4", "H5", "H6", "H8"];
// Liberacao operacional por decisao do operador (nota 126, 18/10/2026): aceita payload com homologacao reprovada SO se o
// bloco `liberacao` citar esta nota com este sha256 exato. Editar a nota muda o hash e volta a bloquear (fail-closed).
export const LIBERACAO_MODO = "operacional_por_decisao_do_operador";
export const LIBERACAO_NOTA_SHA256 = "950c7b0404ff900877f161840ea0a601711860ba67baa4ae09f6e554900138c5";

export function liberacaoValida(p) {
  const l = p && p.liberacao;
  return !!(l && l.modo === LIBERACAO_MODO && l.nota_sha256 === LIBERACAO_NOTA_SHA256);
}

export function validarPayload(p) {
  const erros = [];
  if (!p || typeof p !== "object") return { ok: false, erros: ["payload ausente"] };
  if (p.schema !== SCHEMA) erros.push("schema diferente de " + SCHEMA);
  if (!/^[0-9a-f]{64}$/.test(String(p.sha256_rotulos || ""))) erros.push("sha256_rotulos invalido");
  const h = p.homologacao || {};
  if (!liberacaoValida(p)) for (const g of ["g1a", "g1b", "g1c", "g2"]) if (h[g] !== true) erros.push("homologacao." + g + " nao aprovada");
  if (!Array.isArray(p.sinais_aprovados) || p.sinais_aprovados.length === 0) erros.push("sem sinal aprovado em G2");
  else for (const s of p.sinais_aprovados) if (!SINAIS.includes(s)) erros.push("sinal desconhecido: " + s);
  if (p.exibir_probabilidade === true && h.g3 !== true) erros.push("probabilidade exibivel exige G3 aprovado");
  if (!Array.isArray(p.emissores)) erros.push("emissores ausente");
  else for (const e of p.emissores) {
    if (!e || typeof e.cnpj !== "string") { erros.push("emissor sem cnpj"); break; }
    if (!e.sinais || typeof e.sinais !== "object") { erros.push("emissor " + e.cnpj + " sem sinais"); break; }
    for (const s of p.sinais_aprovados) if (![0, 1, null].includes(e.sinais[s])) { erros.push("emissor " + e.cnpj + " sinal " + s + " fora de {0,1,null}"); break; }
    if (e.prob_180d != null && !(e.prob_180d >= 0 && e.prob_180d <= 1)) { erros.push("emissor " + e.cnpj + " prob_180d fora de [0,1]"); break; }
  }
  return { ok: erros.length === 0, erros };
}

// Pacote velho nao aparece (EWS2IDADE1, 18/10/2026). A rotina semanal publica toda segunda com T = dia util anterior,
// entao o pacote normal tem ate ~10 dias. Acima de IDADE_MAX_DIAS corridos (uma execucao perdida), ou sem data valida,
// o sinal some sozinho em vez de ser exibido como se fosse atual. `agora` so e passado pelos testes.
export const IDADE_MAX_DIAS = 14;

export function idadeDias(p, agora = Date.now()) {
  const d = /^\d{4}-\d{2}-\d{2}$/.test(String((p && p.data_observacao) || "")) ? Date.parse(p.data_observacao + "T00:00:00Z") : NaN;
  return Number.isFinite(d) ? Math.floor((agora - d) / 86400000) : null;
}

export function pacoteFresco(p, agora = Date.now()) {
  const i = idadeDias(p, agora);
  return i !== null && i >= -1 && i <= IDADE_MAX_DIAS;
}

export function flagAtiva(flag) {
  return !!(flag && typeof flag === "object" && flag.ativo === true);
}

// Funde o EWS 2.0 no payload de predictive_v1 SEM alterar nenhum campo existente: so acrescenta `ews2` por emissor
// (chave `name` do predictive_v1 casa com `nome` do ews2) e um bloco `ews2` no topo. Probabilidade so se G3 aprovou.
export function fundir(predictiveV1, ews2, flag, agora = Date.now()) {
  const base = predictiveV1 && typeof predictiveV1 === "object" ? predictiveV1 : { emissores: [] };
  if (!flagAtiva(flag)) return { ...base, ews2: { ativo: false, motivo: "flag desligada" } };
  const v = validarPayload(ews2);
  if (!v.ok) return { ...base, ews2: { ativo: false, motivo: "payload invalido: " + v.erros.join("; ") } };
  if (!pacoteFresco(ews2, agora)) return { ...base, ews2: { ativo: false, motivo: "pacote velho: data_observacao " + ews2.data_observacao + ", limite " + IDADE_MAX_DIAS + " dias" } };
  const porNome = new Map((ews2.emissores || []).map((e) => [String(e.nome || "").toLowerCase().trim(), e]));
  const porCnpj = new Map((ews2.emissores || []).map((e) => [e.cnpj, e]));
  const emissores = (base.emissores || []).map((em) => {
    const e = porCnpj.get(em.cnpj) || porNome.get(String(em.name || "").toLowerCase().trim());
    if (!e) return { ...em, ews2: null };
    const sinais = {};
    for (const s of ews2.sinais_aprovados) sinais[s] = e.sinais[s];
    return { ...em, ews2: { sinais, severidade: e.severidade ?? null, prob_180d: ews2.exibir_probabilidade === true ? e.prob_180d ?? null : null } };
  });
  return {
    ...base, emissores,
    ews2: { ativo: true, schema: ews2.schema, protocolo: ews2.protocolo, versao_pipeline: ews2.versao_pipeline, gerado_em: ews2.gerado_em,
      sinais_aprovados: ews2.sinais_aprovados, exibir_probabilidade: ews2.exibir_probabilidade === true, cobertos: emissores.filter((x) => x.ews2).length },
  };
}

// EWS do cliente (op=ews): anexa `ews2` {severidade, sinais} a cada objeto do EWS atual, casando por nome do emissor
// (`empresa`). NUNCA altera campo existente. Flag desligada, payload invalido ou pacote velho: devolve sem mudanca.
export function anexarEws(objetos, ews2, flag, agora = Date.now()) {
  const lista = Array.isArray(objetos) ? objetos : [];
  if (!flagAtiva(flag) || !validarPayload(ews2).ok || !pacoteFresco(ews2, agora)) return lista;
  const porNome = new Map((ews2.emissores || []).map((e) => [String(e.nome || "").toLowerCase().trim(), e]));
  return lista.map((o) => {
    const e = o && porNome.get(String(o.empresa || "").toLowerCase().trim());
    if (!e) return o;
    const sinais = {};
    for (const s of ews2.sinais_aprovados) sinais[s] = e.sinais[s];
    return { ...o, ews2: { severidade: e.severidade ?? null, sinais, data_observacao: ews2.data_observacao || null } };
  });
}

// Rollback puro: devolve o payload sem nada do EWS 2.0 (o que a flag desligada tambem produz).
export function remover(predictiveComEws2) {
  if (!predictiveComEws2 || typeof predictiveComEws2 !== "object") return predictiveComEws2;
  const { ews2: _e, ...resto } = predictiveComEws2;
  return { ...resto, emissores: (resto.emissores || []).map(({ ews2: _x, ...em }) => em) };
}
