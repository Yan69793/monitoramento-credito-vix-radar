# PROMPT DE HANDOFF COMPLETO — RADAR DE CRÉDITO PRIVADO v4

> **DESATUALIZADO desde 2026-06-14.** Conteúdo histórico preservado abaixo para registro.
> Cita "50 empresas emissoras" — hoje são 103.
> **Fonte atual:** [README.md](../README.md) e [`Obsidian VIX Radar/03 - Estado Atual.md`](../Obsidian%20VIX%20Radar/03%20-%20Estado%20Atual.md).

---

## Para: Claude Code / Nova sessão de Claude
## Objetivo: Entender tudo que foi construído, testar exaustivamente e deixar perfeito

---

## PARTE 1 — O QUE FOI FEITO

### Visão geral do produto
Foi construído do zero um **Radar de Inteligência de Crédito Privado com IA**, um sistema web completo que monitora 50 empresas emissoras de renda fixa no Brasil — debêntures, letras financeiras, CRI, CRA e cotas de fundos fechados. O sistema usa a API da Anthropic com busca nativa na internet para varrer fontes oficiais diariamente e classificar eventos por criticidade, eliminando a necessidade de a equipe de gestão de fundos caçar informação manualmente.

### Problema que resolve
Gestores de fundos de renda fixa precisam monitorar diariamente dezenas de emissores para identificar eventos que possam afetar o spread ou a capacidade de pagamento de papéis na carteira. Antes deste sistema, essa varredura era feita manualmente, consumindo horas por dia e dependendo de atenção humana constante. O Radar automatiza isso: varre 6 fontes por empresa, classifica eventos em 3 níveis (🔴🟡⚪) e entrega um resumo executivo por emissor.

### Resultado entregue
- Sistema web completo deployado em produção no Cloudflare Pages
- URL: `https://radar-credito.pages.dev`
- Custo operacional: ~R$ 25/mês (apenas API da Anthropic)
- Sem servidor próprio, sem banco de dados, sem manutenção de infraestrutura
- Funciona em qualquer navegador, sem instalação

### O que o sistema faz especificamente
1. **Varredura por empresa:** para cada emissor selecionado, executa 6 rodadas de busca na internet cobrindo fatos relevantes da CVM, ações de rating, resultados trimestrais, emissões de dívida, eventos judiciais e regulatórios
2. **Classificação inteligente:** cada evento encontrado é classificado como 🔴 CRÍTICO (requer atenção imediata), 🟡 RELEVANTE (consta na newsletter do dia) ou ⚪ RUÍDO (descartado)
3. **Output estruturado:** para cada evento entrega título, descrição objetiva com números, impacto para crédito, contexto histórico, próximo gatilho a monitorar, tags e link para a fonte original
4. **Newsletter:** exporta todos os eventos do dia em texto formatado pronto para colar no e-mail da equipe
5. **Modo demo:** para apresentações e treinamento, carrega eventos ilustrativos sem precisar da API

---

## PARTE 2 — COMO FOI FEITO

### Decisões técnicas e por quê cada uma foi tomada

**Cloudflare Pages em vez de servidor próprio**
Escolhido porque elimina toda a complexidade de infraestrutura. Não há servidor para manter, atualizar ou monitorar. O deploy é um ZIP de 16KB. A função serverless tem latência baixa por estar na edge da Cloudflare. Custo zero no plano gratuito para o volume de uma equipe interna.

**HTML/CSS/JS puro em vez de React/Next.js**
Escolhido deliberadamente para eliminar dependências de build. O arquivo `index.html` abre em qualquer navegador sem precisar de `npm install`, webpack, babel ou qualquer outra ferramenta. Isso é crítico para um sistema interno que precisa ser mantido por pessoas que não são necessariamente desenvolvedores. O trade-off é que o código é mais verboso, mas a simplicidade operacional compensa.

**API da Anthropic com web_search tool nativa**
Em vez de construir scrapers frágeis que quebram quando os sites mudam de layout, o sistema usa a capacidade de busca nativa do Claude. Isso significa que o motor analítico já sabe o que buscar, como interpretar o que encontrou e como classificar — tudo em uma única chamada de API. A ferramenta `web_search_20250305` permite ao modelo fazer múltiplas buscas sequenciais dentro de uma única resposta.

**Cloudflare Pages Function como proxy**
A chave da Anthropic nunca é exposta no frontend. Toda chamada passa por `functions/api/radar.js`, que roda no servidor da Cloudflare, injeta a chave e repassa para a API. O browser só vê `POST /api/radar` com `{empresa, setor}` — sem nunca ver a chave.

**Sistema de prompts em duas camadas**
O system prompt define o papel (analista de crédito sênior), as regras de classificação, o protocolo de 6 rodadas de busca e o schema JSON de saída. O user prompt injeta o contexto específico: nome da empresa, setor e regulador setorial. Isso garante que o modelo sempre consulte o regulador correto — ANEEL para energia elétrica, ANP para petróleo, BACEN para financeiro, etc.

### Iterações e bugs corrigidos durante o desenvolvimento

**Iteração 1 — ZIP com estrutura errada (bug 404)**
O primeiro deploy enviou o ZIP com estrutura `radar-credito/public/index.html`. O Cloudflare Pages exige `index.html` na raiz do ZIP. Corrigido na v2.

**Iteração 2 — Function não respondia a POST (bug 405)**
A função usava `export async function onRequestPost()`. O Cloudflare retornava 405 para requisições POST porque a rota não estava sendo mapeada corretamente. Corrigido na v3 trocando para `export async function onRequest()` com verificação de método manual + adicionando `_routes.json` para forçar o roteamento de `/api/*` para as functions.

**Iteração 3 — Fundo escuro sem identidade visual (v4)**
O fundo original era preto puro `#080A0E`. Ajustado para azul-marinho escuro `#0A0F1E` com todos os painéis derivados em tons de azul escuro, dando identidade visual ao sistema sem perder a legibilidade.

### Arquitetura de arquivos
```
radar-credito/              ← raiz do deploy Cloudflare Pages
├── index.html              ← frontend completo (~900 linhas, HTML/CSS/JS inline)
│                              contém: UI, estado, dados demo, lógica de render
├── _routes.json            ← instrui Cloudflare a rotear /api/* para as functions
└── functions/
    └── api/
        └── radar.js        ← Pages Function serverless
                               contém: CORS, validação, system prompt, chamada Anthropic
```

### Fluxo de dados completo
```
1. Usuário abre radar-credito.pages.dev
   → Cloudflare serve index.html (edge, ~10ms)

2. Página carrega em modo Demo
   → Dados pré-carregados em memória, sem chamada de rede

3. Usuário clica Live ⚡ → seleciona empresa → ⚡ Executar Radar
   → JS faz: POST /api/radar { empresa: "Petrobras", setor: "Petróleo e Gás" }

4. Cloudflare roteia /api/radar para functions/api/radar.js
   → Function valida campos
   → Busca ANTHROPIC_API_KEY do environment
   → Monta system prompt + user prompt com regulador injetado
   → POST https://api.anthropic.com/v1/messages (com a chave, server-side)

5. Claude executa 6 rodadas de busca na internet
   → R1: fatos relevantes CVM
   → R2: ações de rating
   → R3: resultado trimestral
   → R4: emissões de dívida
   → R5: eventos de stress financeiro
   → R6: eventos regulatórios do setor

6. Claude retorna JSON estruturado com eventos classificados

7. Function extrai blocos type:"text", faz parse do JSON
   → Retorna JSON limpo para o frontend (sem a chave API)

8. Frontend renderiza cards de evento com classificação, impacto, fonte
   → Atualiza contadores, badge da empresa, indicadores na sidebar
```

---

## PARTE 3 — COMO USAR O SISTEMA

### Acesso
URL de produção: `https://radar-credito.pages.dev`

Não requer login, não requer instalação. Abre em qualquer navegador moderno.

### Interface — visão geral

**Topbar (barra superior)**
- `[RADAR ● CRÉDITO PRIVADO]` — logo do sistema
- `🔴 N críticos | 🟡 N relevantes | ⚙ N/50` — contadores do dia
- `↗ Newsletter` — exporta eventos para e-mail (aparece quando há eventos)
- `Demo | Live ⚡` — toggle de modo

**Sidebar (coluna esquerda)**
- Campo de busca para filtrar emissores
- 10 setores com cores distintas
- 50 emissores, cada um com indicador: 🔴 crítico, 🟡 relevante, ✓ sem eventos, · não analisado

**Painel principal (área central)**
- Dashboard inicial com contadores e resumo dos eventos do dia
- Painel de empresa ao selecionar um emissor

**Status bar (rodapé)**
- Indicadores de status de cada fonte de dados
- Hora da última atualização

### Modo Demo — para apresentações e treinamento

1. O sistema abre neste modo automaticamente
2. Banner amarelo avisa que os dados são ilustrativos
3. Clique nas empresas com dados de demonstração:
   - **Oi** → evento 🔴 CRÍTICO (recuperação judicial)
   - **Rumo** → evento 🟡 RELEVANTE (nova emissão de debêntures)
   - **Sabesp** → evento 🟡 RELEVANTE (resultado 4T25)
   - **CCR** → evento 🟡 RELEVANTE (revisão tarifária ANTT)
   - **Equatorial Energia** → ✓ sem eventos
4. Explore as abas: Eventos, Rodadas de busca, Alertas de mercado
5. Clique em ↗ Newsletter para ver o formato de exportação

**Quando usar o modo Demo:**
- Apresentações para a equipe ou gestores
- Treinamento de novos membros
- Demonstração do sistema sem consumir créditos da API
- Testes de interface

### Modo Live ⚡ — para uso operacional real

1. Clique em **Live ⚡** no canto superior direito
2. O banner desaparece e os contadores zeram
3. Selecione qualquer empresa na sidebar
4. Clique em **⚡ Executar Radar**
5. Aguarde 15-35 segundos (o modelo executa 6 buscas na internet)
6. O resultado aparece com:
   - Badge de classificação (🔴 CRÍTICO / 🟡 RELEVANTE / ✓ SEM EVENTOS)
   - Cards de evento com descrição, impacto, contexto e fonte
   - Aba "Rodadas de busca" mostrando exatamente o que foi pesquisado
   - Aba "Alertas de mercado" para alertas quantitativos

**Melhores empresas para testar:**
- **Sabesp, Rumo, Eneva** — alta cobertura de imprensa, resultados recentes
- **Oi** — em processo de RJ, quase sempre retorna evento crítico
- **Petrobras** — alta cobertura, eventos regulatórios frequentes
- **Klabin, Suzano** — geralmente estáveis, bom para testar "sem eventos"

### Como interpretar um evento

Cada card de evento contém:

| Campo | O que significa |
|---|---|
| 🔴 CRÍTICO / 🟡 RELEVANTE | Nível de urgência para a gestão |
| Título | Resumo em até 10 palavras |
| Evento | O que aconteceu, quando, quem confirmou, qual o número |
| Impacto para crédito | Como isso afeta spread ou capacidade de pagamento |
| Contexto | Comparação com histórico ou peers |
| 📌 Monitorar | Próximo gatilho ou data a acompanhar |
| Tags | Categorias: rating, liquidez, resultado, governance, M&A, legal... |
| Fonte | Link direto para o documento ou notícia original |

### Como exportar a newsletter

1. Após analisar as empresas do dia, clique em **↗ Newsletter**
2. O texto formatado é copiado para o clipboard
3. Cole direto no e-mail, WhatsApp ou Slack da equipe
4. O formato inclui: classificação, empresa, título, evento, impacto, fonte

### Frequência de uso recomendada

| Horário | Ação |
|---|---|
| 7h30 | Rodar radar nas empresas de maior risco da carteira |
| 12h | Verificar se houve fatos relevantes na CVM no período da manhã |
| 17h | Rodar varredura completa antes do fechamento e enviar newsletter |

---

## PARTE 4 — COMO OTIMIZAR O SISTEMA

### Otimizações de prompt (maior impacto)

**O1 — Adicionar lista real da carteira no system prompt**
Atualmente o sistema monitora 50 empresas genéricas. Quando João fornecer a lista real dos emissores da carteira, substituir o array `EMISSORES` no `index.html` e os setores correspondentes. Isso reduz ruído — o modelo não busca informações irrelevantes.

**O2 — Injetar contexto histórico por empresa**
Para empresas em watchlist interno (com situação de atenção), adicionar ao user prompt uma linha como: `CONTEXTO INTERNO: empresa em monitoramento desde jan/2026 por deterioração de covenants`. Isso direciona o modelo para buscar eventos mais específicos.

**O3 — Ajustar o threshold de classificação por setor**
Energia elétrica tem eventos regulatórios frequentes que são ruído para outros setores. Adicionar no system prompt: `Para o setor de Energia Elétrica, eventos de constrained-off abaixo de 15% da capacidade são ⚪ RUÍDO`. Calibrar por setor com a equipe de gestão.

**O4 — Melhorar o campo "monitorar"**
Instruir o modelo a sempre incluir uma data específica no campo `monitorar`: `"Próximo resultado (4T25): fevereiro/2026"` em vez de `"Acompanhar próximo resultado"`. Adicionar ao system prompt: `O campo monitorar DEVE conter uma data ou prazo específico quando disponível.`

### Otimizações de UX (médio impacto)

**O5 — Timeout explícito com retry**
Se a chamada à API demorar mais de 35 segundos, mostrar: "A análise está demorando. Tentando novamente..." e reiniciar automaticamente. Implementar com `AbortController`:
```javascript
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 35000);
const res = await fetch('/api/radar', { signal: controller.signal, ... });
clearTimeout(timeout);
```

**O6 — Persistir resultados no sessionStorage**
Os resultados somem ao recarregar a página. Salvar após cada análise:
```javascript
// Após receber resultado:
sessionStorage.setItem('radar_resultados', JSON.stringify(resultados));

// Ao carregar a página:
const salvo = sessionStorage.getItem('radar_resultados');
if (salvo && modo === 'live') resultados = JSON.parse(salvo);
```

**O7 — Botão "Analisar todos" com fila**
Processar as 50 empresas sequencialmente com delay de 3 segundos entre cada uma para evitar rate limit. Progress bar: "12/50". Código base:
```javascript
async function analisarTodos() {
  const empresas = Object.values(EMISSORES).flat();
  for (let i = 0; i < empresas.length; i++) {
    await analisar(empresas[i]);
    atualizarProgress(i+1, empresas.length);
    if (i < empresas.length - 1) await sleep(3000);
  }
}
```

**O8 — Filtro por setor e por classificação**
Adicionar dois dropdowns acima da sidebar:
- Setor: "Todos | Energia Elétrica | Transportes..."
- Status: "Todos | 🔴 Crítico | 🟡 Relevante | ⏳ Não analisadas"

**O9 — Newsletter em HTML formatado para email**
O export atual gera texto puro. Para Gmail/Outlook com formatação visual:
```javascript
const html = `<table style="font-family:monospace;max-width:680px">
  ${eventos.map(e => `<tr style="background:${e.classificacao==='CRITICO'?'#150808':'#0F1320'};
    border-left:3px solid ${e.classificacao==='CRITICO'?'#EF4444':'#D97806'}">
    <td style="padding:12px">${e.titulo}<br><small>${e.evento}</small></td>
  </tr>`).join('')}
</table>`;
```

### Otimizações de infraestrutura (baixo custo)

**O10 — Restringir CORS para produção**
Atualmente `Access-Control-Allow-Origin: *`. Para maior segurança, trocar em `radar.js` para:
```javascript
"Access-Control-Allow-Origin": "https://radar-credito.pages.dev",
```

**O11 — Domínio próprio**
Configurar `radar.suagestora.com.br` em: Cloudflare Dashboard → radar-credito → Custom domains. Requer que o domínio esteja no Cloudflare (se não estiver, adicionar via Domains → Add domain). Sem custo adicional.

**O12 — Upgrade para Opus em eventos críticos**
Para eventos com score muito alto (termos como "recuperação judicial", "default"), escalar para `claude-opus-4-6` automaticamente. Adicionar na function:
```javascript
const modeloEscolhido = termosCriticos.some(t => userPrompt.toLowerCase().includes(t))
  ? "claude-opus-4-20250514"
  : "claude-sonnet-4-20250514";
```
Custo adicional apenas quando necessário.

**O13 — Cache de resultados por 4 horas**
Usar Cloudflare KV para cachear resultados. Evita rechamadas desnecessárias para a mesma empresa no mesmo dia:
```javascript
const cacheKey = `${empresa}-${hoje}`;
const cached = await env.RADAR_KV.get(cacheKey);
if (cached) return new Response(cached, { headers });
// ... chamada à API ...
await env.RADAR_KV.put(cacheKey, JSON.stringify(resultado), { expirationTtl: 14400 });
```
Requer criar um KV namespace no Cloudflare e fazer binding em Settings → KV namespace bindings.

### Otimizações de custo

| Cenário | Custo estimado/mês |
|---|---|
| 5 empresas/dia × 22 dias úteis | ~R$ 3/mês |
| 20 empresas/dia × 22 dias úteis | ~R$ 11/mês |
| 50 empresas/dia × 22 dias úteis | ~R$ 25/mês |
| Com cache KV (O13) — redução de 60-70% | ~R$ 7-10/mês para 50 empresas |

O cache é a otimização de custo de maior impacto. Uma empresa analisada às 7h30 não precisa ser re-analisada às 12h se não houve novo fato relevante.

---

## PARTE 5 — TESTES EXAUSTIVOS

### FASE 1 — Infraestrutura (executar no terminal)

**T1.1 — Function responde?**
```bash
curl -X POST https://radar-credito.pages.dev/api/radar \
  -H "Content-Type: application/json" \
  -d '{"empresa":"Klabin","setor":"Papel e Celulose"}'
```
Esperado: JSON (não HTML)

**T1.2 — CORS correto?**
```bash
curl -X OPTIONS https://radar-credito.pages.dev/api/radar \
  -H "Origin: https://radar-credito.pages.dev" \
  -H "Access-Control-Request-Method: POST" -v 2>&1 | grep -E "< HTTP|Allow|Origin"
```
Esperado: `204` com `Access-Control-Allow-Origin: *`

**T1.3 — Validação de campos?**
```bash
curl -X POST https://radar-credito.pages.dev/api/radar \
  -H "Content-Type: application/json" \
  -d '{"empresa":"Petrobras"}'
```
Esperado: `{"error":"Campos empresa e setor são obrigatórios."}`

**T1.4 — GET bloqueado?**
```bash
curl -X GET https://radar-credito.pages.dev/api/radar
```
Esperado: `{"error":"Method not allowed"}`

**T1.5 — Chave configurada?**
Se T1.1 retornar `{"error":"ANTHROPIC_API_KEY não configurada..."}` → ir em Cloudflare → radar-credito → Settings → Environment variables → verificar se `ANTHROPIC_API_KEY` está presente.

### FASE 2 — Frontend modo Demo

**T2.1** Abrir URL → banner amarelo aparece? Contadores mostram 🔴 1, 🟡 3, ⚙ 5/50?
**T2.2** Clicar em Oi → badge 🔴 CRÍTICO aparece? Card com título, descrição, impacto, monitorar?
**T2.3** Clicar em Rumo → badge 🟡 RELEVANTE? Campos completos?
**T2.4** Clicar em Sabesp → resultado 4T25 com números (EBITDA R$ 3,1 bi)?
**T2.5** Clicar em CCR → revisão tarifária ANTT 6,8%?
**T2.6** Clicar em Equatorial → badge ✓ SEM EVENTOS?
**T2.7** Clicar em Aegea → mensagem "sem dados de demonstração"?
**T2.8** Aba "Rodadas de busca" → lista de rodadas com queries e resultados?
**T2.9** Aba "Alertas de mercado" na Oi → alerta de LIQUIDEZ?
**T2.10** Buscar "Kla" → apenas Klabin aparece?
**T2.11** Clicar em ↗ Newsletter → botão muda para "✓ Copiado"? Colar em editor e verificar texto?
**T2.12** Clicar nos chips de fonte (T1 · CVM RAD) → abre URL no navegador?

### FASE 3 — Frontend modo Live

**T3.1** Clicar Live ⚡ → banner some, contadores zeram?
**T3.2** Selecionar Sabesp → botão ⚡ Executar Radar aparece?
**T3.3** Executar Sabesp → loading com 3 dots animados? Texto "6 rodadas de busca"?
**T3.4** Aguardar resultado → sem erro? JSON renderizado corretamente?
**T3.5** Aba "Rodadas de busca" → 4-6 rodadas executadas? Queries reais?
**T3.6** Executar Oi → evento 🔴 sobre recuperação judicial?
**T3.7** Executar Klabin → retorna sem_eventos=true?
**T3.8** Executar Petrobras → evento relacionado a ANP ou preço do petróleo?
**T3.9** Executar TIM Brasil → regulador ANATEL mencionado nas buscas?
**T3.10** Exportar newsletter com 2+ eventos Live → texto inclui todos?

### FASE 4 — Edge cases

**T4.1** Clicar em empresa enquanto outra está carregando → não trava?
**T4.2** Recarregar a página em modo Live → resultados somem (esperado — sem persistência ainda)?
**T4.3** Digitar "D'Or" na busca → Rede D'Or aparece?
**T4.4** Digitar "Â" → Âmbar Energia aparece?
**T4.5** Janela estreita (800px) → sidebar e painel não se sobrepõem?
**T4.6** Navegar Petrobras → Sabesp → Petrobras → resultado anterior ainda está?
**T4.7** No DevTools → Network → inspecionar request a /api/radar → body só tem empresa e setor (sem API key)?
**T4.8** Inspecionar response de /api/radar → não contém string "sk-ant-"?

---

## INFORMAÇÕES TÉCNICAS DO DEPLOY

**Plataforma:** Cloudflare Pages (plano Free)
**Variável de ambiente:** `ANTHROPIC_API_KEY` = `sk-ant-...` (configurada em Settings → Environment variables)
**Modelo:** `claude-sonnet-4-20250514`
**Beta header:** `anthropic-beta: web-search-2025-03-05`
**Ferramenta:** `web_search_20250305`
**Max tokens:** 4000

**Para novo deploy:**
1. Fazer alterações nos arquivos
2. Gerar ZIP com: `index.html` + `_routes.json` + `functions/api/radar.js` na raiz
3. Cloudflare → radar-credito → Create deployment → arrastar ZIP
4. Aguardar 30-60 segundos
5. Testar `radar-credito.pages.dev`

---

## REGRA ABSOLUTA — NUNCA VIOLAR

Este sistema é usado para decisões reais de investimento em crédito privado.

**INVENTAR DADOS É PIOR DO QUE NÃO TER DADOS.**

Toda melhoria de prompt, toda mudança na lógica de classificação, todo ajuste de UX deve preservar esta regra: o sistema só reporta o que encontrou nas buscas, com fonte rastreável e data real. Se não encontrou nada, diz que não encontrou.

Nunca sacrifique fidelidade por velocidade, completude ou aparência de profundidade.

O campo `fonte_primaria` deve sempre ser uma URL real. O campo `data_evento` deve ser uma data real ou `"não_identificada"` — nunca uma data estimada ou fabricada.
