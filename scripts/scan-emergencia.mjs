// scan-emergencia.mjs — Varredura de EMERGÊNCIA VIX Radar (Opção B / Híbrido)
// ---------------------------------------------------------------------------
// O QUE FAZ
//   Fallback da ingestão de notícias quando a varredura PRINCIPAL (Scheduled
//   Tasks do Claude Code no PC do operador — `routines/`) não roda. Cobre
//   SOMENTE os top-15 emissores prioritários, via provider de LLM com busca
//   web server-side (Anthropic ou OpenRouter, ver PROVIDER abaixo), e SOMENTE quando o feed está
//   desatualizado (staleness já validada pelo workflow antes de chamar este
//   script). O PC continua sendo a varredura principal (grátis via assinatura);
//   isto é o paraquedas para os nomes críticos.
//
// PROVIDER (CLAUDE-FREE-MIGRATION; ANTHROPIC_API_PAYG = NÃO AUTORIZADO)
//   VIXRADAR_FALLBACK_PROVIDER = anthropic (padrão, compatibilidade) | openrouter
//   anthropic  -> ANTHROPIC_API_KEY           (Messages API + web search server-side)
//   openrouter -> VIXRADAR_OPENROUTER_API_KEY (ou OPENROUTER_API_KEY): POST em
//                 openrouter.ai com o server tool openrouter:web_search, mesmo
//                 adapter de scripts/lib/vixradar-openrouter.ps1. Sem claude e sem
//                 chave Anthropic paga.
//   Provider desconhecido NÃO cai para anthropic: cair gastaria a chave paga por
//   engano, que é justamente o que a migração proíbe.
//
// SECRETS (lidos do ambiente; nunca hardcode)
//   ROUTINE_API_KEY    — auth das rotinas no Worker (campo `routine_key`), sempre exigida
//   (ADMIN_PASSWORD é usado só no workflow, para o gate de staleness)
//
// CONTRATO
//   Espelha `routines/vixradar-noturno/SKILL.md`: 9 rodadas de busca, Lei Zero
//   (inventar dado é pior que não ter dado), janela de datas do
//   `dados_para_analise`, e o schema JSON canônico do campo `resultado`.
//   Provedor resultante no Worker: claude-sonnet-routine (sem `_matinal`).
//
// FALHA VISIVEL
//   Sem a chave do provider ativo, ou provider desconhecido, ou sem
//   ROUTINE_API_KEY -> erro + exit 1; o fallback ausente precisa ficar visivel no
//   workflow. Chave do provider INATIVO nao bloqueia: e o que permite rodar sem
//   chave Anthropic paga quando o caminho ativo nao depende dela.
//
// Node 20+ (fetch nativo). Sem dependências npm externas.
// ---------------------------------------------------------------------------

const API_BASE = process.env.VIXRADAR_API_BASE || "https://api.vixradar.com";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Mesmo tier do noturno (Sonnet). ID confirmado via skill claude-api.
const MODEL = "claude-sonnet-4-6";
const TOP_N = 15;
const ANTHROPIC_VERSION = "2023-06-01";
// Variante com dynamic filtering (suportada em Sonnet 4.6).
const WEB_SEARCH_TOOL = { type: "web_search_20260209", name: "web_search", max_uses: 12 };

// ── Provider do fallback: unica decisao de qual credencial e exigida ────────
const PROVIDERS = {
  anthropic: { chaves: ["ANTHROPIC_API_KEY"] },
  openrouter: { chaves: ["VIXRADAR_OPENROUTER_API_KEY", "OPENROUTER_API_KEY"] },
};
const PROVIDER = (process.env.VIXRADAR_FALLBACK_PROVIDER || "anthropic").trim().toLowerCase();

const OPENROUTER_URL = process.env.VIXRADAR_OPENROUTER_URL || "https://openrouter.ai/api/v1/chat/completions";
// Mesmo default do adapter das rotinas. ID VERSIONADO de proposito: o slug sem
// versao e ponteiro movel de upstream (mesma familia do 429 de 07/09/2026).
const OPENROUTER_MODEL_DEFAULT = "deepseek/deepseek-v4-flash-0731";
// Server tools: o OpenRouter roda o loop de busca server-side, o que dispensa o
// tratamento de `pause_turn` que a branch Anthropic precisa.
const OPENROUTER_TOOLS = [{ type: "openrouter:web_search" }];

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const ROUTINE_API_KEY = process.env.ROUTINE_API_KEY;

function failMissingSecret(msg) {
  console.log(`::error::${msg}`);
  console.log("Fallback obrigatorio nao executado.");
  process.exit(1);
}

function chaveDoProvider(nome) {
  const def = PROVIDERS[nome];
  if (!def) return null;
  for (const envName of def.chaves) {
    const valor = process.env[envName];
    if (valor) return { env: envName, valor };
  }
  return null;
}

if (!ROUTINE_API_KEY) failMissingSecret("ROUTINE_API_KEY ausente nos secrets do repo.");
if (!PROVIDERS[PROVIDER]) {
  failMissingSecret(`VIXRADAR_FALLBACK_PROVIDER desconhecido: "${PROVIDER}". Valores aceitos: ${Object.keys(PROVIDERS).join(", ")}.`);
}
const API_KEY_ATIVA = chaveDoProvider(PROVIDER);
if (!API_KEY_ATIVA) {
  failMissingSecret(`provider "${PROVIDER}" ativo e nenhuma chave dele esta presente (${PROVIDERS[PROVIDER].chaves.join(" ou ")}).`);
}
console.log(`provider de analise: ${PROVIDER} (chave ${API_KEY_ATIVA.env})`);

// ── Chamada ao Worker (endpoints das rotinas, auth via routine_key) ──────────
async function worker(action, extra = {}) {
  const resp = await fetch(`${API_BASE}/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, routine_key: ROUTINE_API_KEY, ...extra }),
  });
  const text = await resp.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`Worker ${action}: resposta não-JSON (HTTP ${resp.status}): ${text.slice(0, 200)}`);
  }
  if (!resp.ok) throw new Error(`Worker ${action}: HTTP ${resp.status}: ${text.slice(0, 200)}`);
  return json;
}

// ── System prompt: CONTRATO ANALÍTICO (espelha o SKILL.md do noturno) ────────
function buildSystemPrompt(janelaInicio, janelaFim) {
  return `Você é o analista sênior de crédito privado do VIX Radar executando uma varredura de EMERGÊNCIA (fallback) para UM emissor. Cubra a janela ${janelaInicio}..${janelaFim}.

REGRA ABSOLUTA — LEI ZERO
INVENTAR DADOS É PIOR DO QUE NÃO TER DADOS. Só reporte o que encontrou concretamente via web search, com fonte rastreável (URL real) e data real. Se nada relevante após as 9 rodadas, retorne "sem_eventos": true com "cobertura_nota" provando as buscas. NUNCA invente uma URL.

REGRA DE DATA DO EVENTO
1. "data_evento" é extraída do texto do artigo/documento (o CONTEÚDO), não do path da URL.
2. Se "data_evento" for anterior a ${janelaInicio} E o emissor não estiver em reestruturação contínua → FORA DA JANELA → descarte.
3. Sem data verificável → NÃO crie o evento. Nunca atribua a data de hoje a um artigo antigo.
Crie eventos somente na janela ${janelaInicio}..${janelaFim}.

PROTOCOLO DE BUSCA — 9 RODADAS (use a ferramenta web_search; conte R4 e R4b separadamente)
- R1: {empresa} site:rad.cvm.gov.br OR site:dados.cvm.gov.br fato relevante
- R2: {empresa} rating rebaixamento downgrade Moody's Fitch S&P Austin
- R3: {empresa} resultado trimestral EBITDA alavancagem
- R4: {empresa} emissão debênture CRI CRA FIDC captação mercado de capitais
- R4b: {empresa} letra financeira LF emissão banco captação (site:bcb.gov.br OR site:anbima.com.br OR site:b3.com.br)
- R5: {empresa} recuperação judicial default covenant waiver
- R6: {empresa} regulatório tarifa regulador
- R7: {empresa} RI comunicado dividendos JCP assembleia conselho guidance M&A aquisição
- R8: {empresa} análise sell-side research relatório analista (infomoney/valor/btgpactual/xpi/suno/moneytimes/seudinheiro)
R4 e R4b são INDEPENDENTES — nunca pule R4b.

PROTOCOLO DE COBERTURA
- "fontes_consultadas" obrigatório: uma entrada por rodada ({rodada, query, resultado}), contando R4 e R4b separadamente. "resultado" ∈ {"X artigos, Y na janela", "nenhum resultado relevante na janela", "resultados fora da janela ou RUIDO", "fonte inacessível nesta execução"}.
- "sem_eventos": true exige "cobertura_nota" explícita provando as 9 rodadas. Nunca retorne "fontes_consultadas": [].

CLASSIFICAÇÃO — 4 TIERS
- CRITICO: downgrade por agência reconhecida; RJ/RExtrajudicial; default/vencimento antecipado; breach de covenant/waiver; cross-default; intervenção regulatória >10% EBITDA/receita; assembleia de debenturistas por inadimplência/waiver/reestruturação; fraude/investigação por regulador; FR CVM tratando de qualquer item acima.
- RELEVANTE: resultado fora de tendência; emissão >R$500mi; emissão em condições mais onerosas; M&A de grande porte que altera perfil de dívida/garantias; venda relevante de ativo; reestruturação societária com reflexo em garantias; guidance revisado p/ baixo; outlook alterado p/ negativo; ação regulatória 3–10% EBITDA.
- ECO: emissão em condições de mercado; bônus/stock options; dividendos/JCP; AGO/conselho sem implicação de crédito; M&A pequeno/médio; guidance reafirmado/para cima; comunicados rotineiros; rating reafirmado.
- RUIDO (descartar): publicidade; menção tangencial; repetição; especulação sem fonte primária; evento de terceiros; rumor.

MEMO DO ANALISTA (linguagem de crédito privado BR — DL/EBITDA, ICSD, PU, spread, duration, call, put, subordinação, cross-default; PROIBIDO jargão de equity/macro genérico)
CRITICO/RELEVANTE: memo completo (máx 2–3 frases por bloco, ≥1 fonte primária) — memo_acontecimento, memo_importancia_credito, memo_monitorar, memo_acao_sugerida.
ECO: enxuto — memo_importancia_credito "Sem impacto direto no crédito — fato informacional do RI."; memo_monitorar "Manter em dossiê para contexto do emissor."; memo_acao_sugerida "Nenhuma ação requerida."
RESEARCH_HOUSE é opinião — NUNCA CRITICO (máx RELEVANTE).

SAÍDA
Responda com UM ÚNICO objeto JSON (sem markdown, sem texto fora do JSON) no formato:
{"empresa":"","data_analise":"YYYY-MM-DD","sem_eventos":false,"cobertura_nota":"","instrumentos_ativos":[],"fontes_consultadas":[{"rodada":"1","query":"","resultado":""}],"eventos":[{"classificacao":"CRITICO|RELEVANTE|ECO","titulo":"","evento":"","impacto_credito":"","memo_acontecimento":"","memo_importancia_credito":"","memo_monitorar":"","memo_acao_sugerida":"","nivel_conviccao":"alta","fonte_primaria":"https://","fonte_tipo":"CVM_RAD|B3|ANBIMA|RATING_AGENCY|IMPRENSA_OFICIAL|RESEARCH_HOUSE|IMPRENSA","data_evento":"YYYY-MM-DD","data_publicacao_fonte":"","data_aproximada":false,"tags":[]}]}
"instrumentos_ativos": subconjunto de ["debenture","cri","cra","lf","fidc"] com evidência concreta; sem evidência → [].`;
}

// ── Extrai o objeto JSON da resposta (concatena blocos de texto) ─────────────
function extrairResultado(message) {
  const texto = (message.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("");
  // Isola do primeiro "{" ao último "}" — robusto a preâmbulo/sufixo.
  const inicio = texto.indexOf("{");
  const fim = texto.lastIndexOf("}");
  if (inicio === -1 || fim === -1 || fim <= inicio) {
    throw new Error(`Sem JSON parseável na resposta: ${texto.slice(0, 200)}`);
  }
  return JSON.parse(texto.slice(inicio, fim + 1));
}

// ── Chamada à API Anthropic com web search (adaptive thinking, sem stream) ───
async function analisarEmissorAnthropic(empresa, setor, janelaInicio, janelaFim) {
  const system = buildSystemPrompt(janelaInicio, janelaFim);
  const userMsg = `Emissor: ${empresa} (setor: ${setor}). Execute as 9 rodadas de web search para a janela ${janelaInicio}..${janelaFim} e devolva o objeto JSON canônico do campo "resultado". Preencha "empresa" com "${empresa}".`;

  const resp = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      thinking: { type: "adaptive" },
      system,
      tools: [WEB_SEARCH_TOOL],
      messages: [{ role: "user", content: userMsg }],
    }),
  });

  const text = await resp.text();
  if (!resp.ok) throw new Error(`Anthropic HTTP ${resp.status}: ${text.slice(0, 300)}`);
  const message = JSON.parse(text);

  // pause_turn: loop server-side de web search atingiu o limite — reenvia p/ continuar.
  let msg = message;
  let guard = 0;
  const historico = [{ role: "user", content: userMsg }];
  while (msg.stop_reason === "pause_turn" && guard < 4) {
    historico.push({ role: "assistant", content: msg.content });
    const r2 = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 8000,
        thinking: { type: "adaptive" },
        system,
        tools: [WEB_SEARCH_TOOL],
        messages: historico,
      }),
    });
    const t2 = await r2.text();
    if (!r2.ok) throw new Error(`Anthropic (pause_turn) HTTP ${r2.status}: ${t2.slice(0, 300)}`);
    msg = JSON.parse(t2);
    guard++;
  }

  if (msg.stop_reason === "refusal") {
    throw new Error("Anthropic recusou a requisição (stop_reason: refusal).");
  }
  return extrairResultado(msg);
}

// ── Chamada ao OpenRouter (server tool openrouter:web_search) ────────────────
// Mesmo contrato de saida da branch Anthropic: o objeto sai por `extrairResultado`,
// entao o parser de JSON e o schema do campo `resultado` continuam sendo um so. O
// loop de busca roda server-side, o que dispensa o tratamento de `pause_turn`.
// A chave vem de API_KEY_ATIVA e nunca entra em log, URL ou mensagem de erro.
async function analisarEmissorOpenRouter(empresa, setor, janelaInicio, janelaFim) {
  const system = buildSystemPrompt(janelaInicio, janelaFim);
  const userMsg = `Emissor: ${empresa} (setor: ${setor}). Execute as 9 rodadas de web search para a janela ${janelaInicio}..${janelaFim} e devolva o objeto JSON canônico do campo "resultado". Preencha "empresa" com "${empresa}".`;

  const resp = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${API_KEY_ATIVA.valor}`,
    },
    body: JSON.stringify({
      model: process.env.VIXRADAR_OPENROUTER_MODEL || OPENROUTER_MODEL_DEFAULT,
      max_tokens: 8000,
      messages: [
        { role: "system", content: system },
        { role: "user", content: userMsg },
      ],
      tools: OPENROUTER_TOOLS,
      // OR429-FIX: reativa o failover nativo entre providers do mesmo modelo.
      allow_fallbacks: true,
    }),
  });

  const text = await resp.text();
  if (!resp.ok) throw new Error(`OpenRouter HTTP ${resp.status}: ${text.slice(0, 300)}`);
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`OpenRouter: resposta não-JSON: ${text.slice(0, 200)}`);
  }

  const escolha = (json.choices && json.choices[0]) || {};
  if (escolha.finish_reason === "content_filter") {
    throw new Error("OpenRouter recusou a requisição (finish_reason: content_filter).");
  }
  const conteudo = escolha.message && escolha.message.content;
  // Normaliza para o formato de blocos que `extrairResultado` ja consome.
  const texto = typeof conteudo === "string" ? conteudo : JSON.stringify(conteudo || "");
  return extrairResultado({ content: [{ type: "text", text: texto }] });
}

// ── Despacho por provider (nome mantido: o call site nao muda) ───────────────
async function analisarEmissor(empresa, setor, janelaInicio, janelaFim) {
  if (PROVIDER === "openrouter") {
    return analisarEmissorOpenRouter(empresa, setor, janelaInicio, janelaFim);
  }
  return analisarEmissorAnthropic(empresa, setor, janelaInicio, janelaFim);
}

// ── Fluxo principal ──────────────────────────────────────────────────────────
async function main() {
  console.log(`=== Varredura de emergência (Opção B) — top ${TOP_N} emissores ===`);

  const lista = await worker("listar_emissores_prioritarios", { top_n: TOP_N });
  const emissores = Array.isArray(lista.emissores) ? lista.emissores : [];
  const semSetor = Array.isArray(lista.sem_setor) ? lista.sem_setor : [];
  if (semSetor.length > 0) {
    console.log(`::warning::${semSetor.length} emissor(es) prioritario(s) sem setor canonico em SETOR_DE_EMPRESA e nao enviados: ${semSetor.join(", ")}`);
  }
  if (emissores.length === 0) {
    if (semSetor.length > 0) {
      console.log("::error::Fallback sem emissores com setor canonico em SETOR_DE_EMPRESA; nada executado.");
      process.exitCode = 1;
      return;
    }
    console.log("::warning::Nenhum emissor prioritário retornado. Nada a fazer.");
    process.exitCode = 0;
    return;
  }
  console.log(`Emissores prioritários: ${emissores.length} (de ${lista.total ?? "?"})`);

  let processados = 0;
  let eventosTotais = 0;
  let falhas = semSetor.length;

  for (const emissor of emissores) {
    const empresa = emissor.empresa;
    const setor = emissor.setor;
    try {
      // SCANFALLBACK-MORTO1: contrato real de `listar_emissores_prioritarios` usa
      // `empresa`, nao `nome`; `setor` vem do mapa SETOR_DE_EMPRESA do Worker. Se
      // qualquer um faltar, falha visivel em vez de repetir o HTTP 400 de 08/09.
      if (!empresa || !setor) {
        throw new Error("listar_emissores_prioritarios devolveu emissor sem empresa/setor");
      }
      const dados = await worker("dados_para_analise", { empresa, setor });
      const janelaInicio = dados.janela_inicio;
      const janelaFim = dados.janela_fim;
      if (!janelaInicio || !janelaFim) {
        throw new Error("dados_para_analise sem janela_inicio/janela_fim");
      }

      const resultado = await analisarEmissor(empresa, setor, janelaInicio, janelaFim);
      // Garante o nome canônico no payload.
      resultado.empresa = empresa;

      const rec = await worker("receber_analise", { empresa, setor, resultado });
      const n = Number(rec.n_eventos || 0);
      eventosTotais += n;
      processados++;
      console.log(`  [ok] ${empresa}: n_eventos=${n}${rec.sem_eventos ? " (sem_eventos)" : ""}`);
    } catch (e) {
      falhas++;
      console.log(`::warning::  [falha] ${empresa}: ${e.message}`);
    }
  }

  console.log("=== Resumo ===");
  console.log(`Processados: ${processados}/${emissores.length + semSetor.length} | eventos somados: ${eventosTotais} | falhas: ${falhas}`);
  if (falhas > 0) {
    console.log(`::error::Fallback incompleto: ${falhas} emissor(es) falharam.`);
    process.exitCode = 1;
    return;
  }
  process.exitCode = 0;
}

main().catch((e) => {
  console.log(`::error::Erro fatal no scan de emergência: ${e.message}`);
  // Falha real (ex.: Worker fora do ar) — sinaliza para o operador.
  process.exitCode = 1;
});
