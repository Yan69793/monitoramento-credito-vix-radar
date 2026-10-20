// EVOLUCAO1 (2026-10-19): Livro de Propostas de Evolucao do VIX Intelligence Evolution, marco 1.
// Memoria persistente, versionada e idempotente das propostas de melhoria (descoberta de emissor/fonte/
// indicador, ajuste de EWS, UX, seguranca, custo, codigo). O livro NUNCA executa nada: toda proposta nasce
// `proposta` e so muda de estado por decisao humana. Proposta automatica pode ser criada, aprovada nao.
// Modulo puro: recebe o KV e o relogio por parametro, sem import do Worker, para teste direto.

export const TIPOS = ["descoberta_emissor", "descoberta_fonte", "descoberta_setor", "indicador", "ews", "funcionalidade", "ux_ui", "seguranca", "desempenho", "custo", "codigo"];
// Tipos que alteram comportamento ou superficie de risco: aprovar autoriza so o PLANEJAMENTO, a execucao continua exigindo deploy autorizado.
export const TIPOS_CRITICOS = ["ews", "seguranca", "codigo"];
export const ORIGENS = ["rotina", "ia", "admin"];
export const LIMITES = { titulo: 140, descricao: 2000, fontes: 5, url: 500, pendentes_por_tenant: 200, propostas_ia_por_dia: 50, historico: 50 };

const PADRAO_INJECAO = /(ignore|ignorar|desconsidere|esque[cç]a)[^.]{0,40}(instru|regras|prompt|anterior)|system\s*prompt|you are now|voc[eê] agora [eé]|<\/?(system|assistant|tool)|\bjailbreak\b|revele?\s+(a\s+)?(chave|senha|secret)/i;

export function sanitizarTexto(valor, max) {
  const s = String(valor == null ? "" : valor).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁦-⁩]/g, " ").replace(/\s+/g, " ").trim();
  return s.length > max ? s.slice(0, max) : s;
}

function normalizarFonte(u) {
  try {
    const x = new URL(String(u).trim());
    if (x.protocol !== "https:" || x.username || x.password) return null;
    x.hash = "";
    const s = x.toString();
    return s.length <= LIMITES.url ? s : null;
  } catch (_e) { return null; }
}

async function sha256Hex(texto) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function tenantValido(t) { return typeof t === "string" && /^[a-z0-9_]{1,40}$/.test(t); }
const chaveProposta = (tenant, id) => `evolucao:${tenant}:p:${id}`;
const prefixoTenant = (tenant) => `evolucao:${tenant}:p:`;
const chaveOrcamentoIA = (tenant, dia) => `evolucao:${tenant}:ia:${dia}`;

// Validacao e normalizacao de uma proposta. Devolve { ok, proposta } ou { ok:false, codigo }.
export async function normalizarProposta(entrada) {
  const e = entrada && typeof entrada === "object" ? entrada : {};
  if (!TIPOS.includes(e.tipo)) return { ok: false, codigo: "EVOLUCAO_TIPO_INVALIDO" };
  const titulo = sanitizarTexto(e.titulo, LIMITES.titulo);
  const descricao = sanitizarTexto(e.descricao, LIMITES.descricao);
  if (titulo.length < 8 || descricao.length < 20) return { ok: false, codigo: "EVOLUCAO_TEXTO_INSUFICIENTE" };
  const brutas = Array.isArray(e.fontes) ? e.fontes.slice(0, LIMITES.fontes) : [];
  const fontes = Array.from(new Set(brutas.map(normalizarFonte).filter(Boolean))).sort();
  if (fontes.length < 1) return { ok: false, codigo: "EVOLUCAO_FONTE_AUSENTE" };
  const alvo = sanitizarTexto(e.alvo, 120).toLowerCase();
  const suspeita_injecao = PADRAO_INJECAO.test(`${titulo} ${descricao} ${alvo}`);
  // Identidade = tipo + alvo + titulo normalizado: reenvio da mesma ideia com outra redacao de descricao ou outra fonte nao duplica.
  const chaveNatural = [e.tipo, alvo, titulo.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")].join("|");
  const id = (await sha256Hex(chaveNatural)).slice(0, 32);
  return { ok: true, proposta: { id, tipo: e.tipo, alvo, titulo, descricao, fontes, suspeita_injecao, critico: TIPOS_CRITICOS.includes(e.tipo) } };
}

async function lerJson(kv, chave) { return kv.get(chave, "json").catch(() => null); }

async function pendentesDoTenant(kv, tenant) {
  let n = 0, cursor;
  do {
    const r = await kv.list({ prefix: prefixoTenant(tenant), cursor, limit: 1000 });
    for (const k of r.keys) { const p = await lerJson(kv, k.name); if (p && p.estado === "proposta") n++; }
    cursor = r.list_complete ? undefined : r.cursor;
  } while (cursor);
  return n;
}

// Cria a proposta de forma idempotente. Reenvio devolve a existente (criada:false) e nao reabre decisao ja tomada.
export async function proporEvolucao(kv, tenant, entrada, { origem, agora }) {
  if (!tenantValido(tenant)) return { ok: false, codigo: "EVOLUCAO_TENANT_INVALIDO" };
  if (!ORIGENS.includes(origem)) return { ok: false, codigo: "EVOLUCAO_ORIGEM_INVALIDA" };
  const n = await normalizarProposta(entrada);
  if (!n.ok) return n;
  const p = n.proposta;
  const existente = await lerJson(kv, chaveProposta(tenant, p.id));
  if (existente) return { ok: true, criada: false, id: p.id, estado: existente.estado, versao: existente.versao };
  if (await pendentesDoTenant(kv, tenant) >= LIMITES.pendentes_por_tenant) return { ok: false, codigo: "EVOLUCAO_FILA_CHEIA" };
  if (origem === "ia") {
    const chave = chaveOrcamentoIA(tenant, agora.slice(0, 10));
    const usados = Number(await kv.get(chave)) || 0;
    if (usados >= LIMITES.propostas_ia_por_dia) return { ok: false, codigo: "EVOLUCAO_ORCAMENTO_IA_ESGOTADO" };
    await kv.put(chave, String(usados + 1), { expirationTtl: 172800 });
  }
  const registro = { ...p, tenant, origem, estado: "proposta", versao: 1, criada_em: agora, historico: [{ v: 1, em: agora, evento: "criada", por: origem, estado: "proposta" }] };
  await kv.put(chaveProposta(tenant, p.id), JSON.stringify(registro));
  return { ok: true, criada: true, id: p.id, estado: "proposta", versao: 1 };
}

export async function listarEvolucao(kv, tenant, { estado, limite = 100 } = {}) {
  if (!tenantValido(tenant)) return { ok: false, codigo: "EVOLUCAO_TENANT_INVALIDO" };
  const itens = [];
  let cursor;
  do {
    const r = await kv.list({ prefix: prefixoTenant(tenant), cursor, limit: 1000 });
    for (const k of r.keys) { const p = await lerJson(kv, k.name); if (p && (!estado || p.estado === estado)) itens.push(p); }
    cursor = r.list_complete ? undefined : r.cursor;
  } while (cursor && itens.length < limite);
  itens.sort((a, b) => (a.criada_em < b.criada_em ? 1 : -1));
  return { ok: true, itens: itens.slice(0, limite) };
}

// Decisao humana. aprovar/rejeitar saem de `proposta`; reverter volta a decisao mais recente para `proposta` (rollback do livro).
// Nada aqui executa a mudanca: aprovada = autorizada para planejar/implementar por fluxo proprio.
export async function decidirEvolucao(kv, tenant, id, { decisao, motivo, ciente_suspeita }, { por, agora }) {
  if (!tenantValido(tenant)) return { ok: false, codigo: "EVOLUCAO_TENANT_INVALIDO" };
  if (!["aprovar", "rejeitar", "reverter"].includes(decisao)) return { ok: false, codigo: "EVOLUCAO_DECISAO_INVALIDA" };
  const m = sanitizarTexto(motivo, 500);
  if (m.length < 10) return { ok: false, codigo: "EVOLUCAO_MOTIVO_INSUFICIENTE" };
  if (typeof id !== "string" || !/^[0-9a-f]{32}$/.test(id)) return { ok: false, codigo: "EVOLUCAO_ID_INVALIDO" };
  const p = await lerJson(kv, chaveProposta(tenant, id));
  if (!p) return { ok: false, codigo: "EVOLUCAO_AUSENTE" };
  let novo;
  if (decisao === "reverter") {
    if (p.estado === "proposta") return { ok: false, codigo: "EVOLUCAO_ESTADO_CONFLITANTE" };
    novo = "proposta";
  } else {
    if (p.estado !== "proposta") return { ok: false, codigo: "EVOLUCAO_ESTADO_CONFLITANTE" };
    if (decisao === "aprovar" && p.suspeita_injecao && ciente_suspeita !== true) return { ok: false, codigo: "EVOLUCAO_SUSPEITA_NAO_RECONHECIDA" };
    novo = decisao === "aprovar" ? "aprovada" : "rejeitada";
  }
  const versao = p.versao + 1;
  const historico = p.historico.concat([{ v: versao, em: agora, evento: decisao, por, motivo: m, estado: novo }]).slice(-LIMITES.historico);
  const atualizado = { ...p, estado: novo, versao, historico };
  await kv.put(chaveProposta(tenant, id), JSON.stringify(atualizado));
  return { ok: true, id, estado: novo, versao, critico: p.critico };
}
