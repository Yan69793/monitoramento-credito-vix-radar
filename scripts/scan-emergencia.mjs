// scan-emergencia.mjs — Varredura de EMERGÊNCIA VIX Radar (Opção B / Híbrido)
// ---------------------------------------------------------------------------
// O QUE FAZ
//   Fallback da ingestão de notícias quando a varredura PRINCIPAL (Scheduled
//   Tasks do Claude Code no PC do operador — `routines/`) não roda. Cobre
//   SOMENTE os top-15 emissores prioritários, via API da Anthropic com a
//   ferramenta server-side de web search, e SOMENTE quando o feed está
//   desatualizado (staleness já validada pelo workflow antes de chamar este
//   script). O PC continua sendo a varredura principal (grátis via assinatura);
//   isto é o paraquedas para os nomes críticos.
//
// SECRETS (lidos do ambiente; nunca hardcode)
//   ANTHROPIC_API_KEY  — chave da API Anthropic (Messages + web search)
//   ROUTINE_API_KEY    — auth das rotinas no Worker (campo `routine_key`)
//   (ADMIN_PASSWORD é usado só no workflow, para o gate de staleness)
//
// CONTRATO
//   Espelha `routines/vixradar-noturno/SKILL.md`: 9 rodadas de busca, Lei Zero
//   (inventar dado é pior que não ter dado), janela de datas do
//   `dados_para_analise`, e o schema JSON canônico do campo `resultado`.
//   Provedor resultante no Worker: claude-sonnet-routine (sem `_matinal`).
//
// FALHA VISIVEL
//   Sem ANTHROPIC_API_KEY ou ROUTINE_API_KEY -> erro + exit 1; o fallback ausente
//   precisa ficar visivel no workflow.
//
// Node 20+ (fetch nativo). Sem dependências npm externas.
// ---------------------------------------------------------------------------

const API_BASE = "https://api.vixradar.com";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Mesmo tier do noturno (Sonnet). ID confirmado via skill claude-api.
const MODEL = "claude-sonnet-4-6";
const TOP_N = 15;
const ANTHROPIC_VERSION = "2023-06-01";
// Variante com dynamic filtering (suportada em Sonnet 4.6).
const WEB_SEARCH_TOOL = { type: "web_search_20260209", name: "web_search", max_uses: 12 };

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const ROUTINE_API_KEY = process.env.ROUTINE_API_KEY;

function failMissingSecret(msg) {
  console.log(`::error::${msg}`);
  console.log("Fallback obrigatorio nao executado.");
  process.exit(1);
}

if (!ANTHROPIC_API_KEY) failMissingSecret("ANTHROPIC_API_KEY ausente nos secrets do repo.");
if (!ROUTINE_API_KEY) failMissingSecret("ROUTINE_API_KEY ausente nos secrets do repo.");

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
async function analisarEmissor(empresa, setor, janelaInicio, janelaFim) {
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

// ── Fluxo principal ──────────────────────────────────────────────────────────
async function main() {
  console.log(`=== Varredura de emergência (Opção B) — top ${TOP_N} emissores ===`);

  const lista = await worker("listar_emissores_prioritarios", { top_n: TOP_N });
  const emissores = Array.isArray(lista.emissores) ? lista.emissores : [];
  if (emissores.length === 0) {
    console.log("::warning::Nenhum emissor prioritário retornado. Nada a fazer.");
    process.exit(0);
  }
  console.log(`Emissores prioritários: ${emissores.length} (de ${lista.total ?? "?"})`);

  let processados = 0;
  let eventosTotais = 0;
  let falhas = 0;

  for (const emissor of emissores) {
    const empresa = emissor.nome;
    const setor = emissor.setor || "";
    try {
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
  console.log(`Processados: ${processados}/${emissores.length} | eventos somados: ${eventosTotais} | falhas: ${falhas}`);
  if (falhas > 0) {
    console.log(`::error::Fallback incompleto: ${falhas} emissor(es) falharam.`);
    process.exit(1);
  }
  process.exit(0);
}

main().catch((e) => {
  console.log(`::error::Erro fatal no scan de emergência: ${e.message}`);
  // Falha real (ex.: Worker fora do ar) — sinaliza para o operador.
  process.exit(1);
});
