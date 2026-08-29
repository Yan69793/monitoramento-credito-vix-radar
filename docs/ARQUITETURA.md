# Arquitetura — Radar de Crédito Privado

> **DESATUALIZADO desde 2026-06-14.** Conteúdo histórico preservado abaixo para registro.
> Cita `radar-standalone-worker.js` (v3.6) e `index.html` v19 — a arquitetura atual usa `api/v4.9.187.js` e `radar-standalone-worker.js` não existe mais.
> **Fonte atual:** [ARQUITETURA-TECNICA.md](ARQUITETURA-TECNICA.md) (retrato medido em 2026-08-26, v4.9.221),
> [README.md](../README.md) e [`Obsidian VIX Radar/03 - Estado Atual.md`](../Obsidian%20VIX%20Radar/03%20-%20Estado%20Atual.md).

---

> Documento derivado da análise de `index.html` (v19 · live) e `radar-standalone-worker.js` (v3.6).
> **NÃO edite este documento manualmente** — atualize-o via `/spec` quando a arquitetura mudar.

---

## 1. Princípio Central: Thin Client / Fat Server

| Camada | Arquivo | Responsabilidade |
|--------|---------|-----------------|
| **Frontend (Thin Client)** | `index.html` | Captura intenções do usuário, renderiza HTML/CSS, exibe JSON retornado pelo Worker |
| **Backend (Fat Server)** | `radar-standalone-worker.js` | Toda lógica de crédito, classificação CRÍTICO/RELEVANTE, chamadas às APIs de IA, persistência no KV |

**Regra inviolável:** Nenhuma lógica de classificação de crédito pode existir no `index.html`. O frontend apenas recebe o campo `classificacao` no JSON e aplica classes CSS correspondentes.

---

## 2. Comportamentos (Behavior-Based Layout)

O sistema é organizado em torno de **comportamentos de interface**, não de rotas:

### `#dashboard` — Painel da Semana
- Exibido na carga inicial e ao clicar em "← Painel"
- Consome `GET ?action=dashboard` do Worker (dados do KV semanal)
- Mostra `stat-grid` (4 cards: Total, Críticos, Relevantes, Pendentes)
- Elementos ocultos para compatibilidade: `#s-total`, `#s-crit`, `#s-rel`, `#s-pend`

### `#emp-panel` — Painel de Empresa
- Oculto inicialmente (`display:none`), ativado ao clicar em emissor no sidebar
- Estrutura interna fixa: `#emp-head` → `#fontes-bar` → `#abas-bar` → `#emp-body`
- Abas disponíveis: **Eventos** | **Rodadas de busca** | **Alertas de mercado** | **📦 Arquivo**

### `#sidebar` — Lista de Emissores
- Desktop: largura fixa `220px`, sempre visível
- Mobile: drawer bottom-sheet `height: 75vh`, `transform: translateY(100%)` fechado, `translateY(0)` aberto
- Contém `#busca` (filtro em tempo real) e `#sidebar-list` (renderizado via JS)

### `#topbar` — Barra Superior
- Grid 3 colunas: logo | centro (hora/data) | direita (botões)
- Contém: botão **ℹ Documentação**, botão **📄 Relatório PDF**, seletor de modo Live
- Mobile: `mode-wrap` e `#btn-guia` são ocultados

### `#mobile-bottom-nav` — Navegação Mobile
- `display: none !important` em desktop
- `display: flex !important` em mobile (≤ 768px)
- Posição: `fixed; bottom: 0`, altura `calc(60px + env(safe-area-inset-bottom))`

### `#status-bar` — Barra de Status
- Fixa no rodapé, exibe status das fontes: CVM RAD, ANBIMA Data, B3 UP2DATA, Moody's Local, Austin Rating
- Elementos: `.status-item.ok` (verde), `.status-item.warn` (amarelo)

---

## 3. Dados de Emissores — Estrutura `EMISSORES`

O objeto `EMISSORES` no `index.html` define os 13 setores cobertos e seus emissores:

| Setor | Qtd Emissores | Regulador (frontend) |
|-------|--------------|---------------------|
| Energia Elétrica | 14 | ANEEL |
| Transportes e Logística | 11 | ANTT / ANTAQ / ANAC |
| Saneamento | 6 | ANA / ARSESP / ARSAE |
| Petróleo, Gás e Combustíveis | 5 | ANP |
| Mineração e Siderurgia | 5 | DNPM / IBAMA / ANM |
| Financeiro | 5 | BACEN / CVM |
| Locação de Veículos e Mobilidade | 2 | DENATRAN e CVM |
| Papel, Celulose e Embalagens | 3 | IBAMA / MAPA |
| Agronegócio | 9 | MAPA / CADE |
| Saúde | 4 | ANS / ANVISA |
| Telecom e Tecnologia | 3 | ANATEL / CADE |
| Real Estate e Construção | 6 | CVM / Banco Central |
| Varejo e Consumo | 3 | CADE / Procon |

**Total atual: ~76 emissores** (variável conforme `TOTAL_EMISSORES` no JS).

---

## 4. Regras Absolutas da Arquitetura

### 4.1 Classificação de Crédito — apenas no Worker
- As strings `"CRITICO"` e `"RELEVANTE"` devem ser determinadas **exclusivamente** pelo `radar-standalone-worker.js`
- O `index.html` usa estas strings apenas para aplicar classes CSS (`.crit`, `.rel`)
- Nunca criar lógica `if (event.keywords.includes("default"))` no frontend

### 4.2 Isolamento por Setor
- `FILTROS_SETORIAIS` no Worker: cada setor tem `critico[]`, `relevante[]`, `ruido[]`, `tags_prioritarias[]`, `reguladores_focus`, `lente_modelo`
- Setores mapeados no Worker (v3.6): Energia Elétrica, Transportes e Logística, Financeiro, Real Estate e Construção
- Setores não mapeados usam lógica genérica (fallback silencioso)

### 4.3 Janelas Temporais Fixas
- **Janela ativa:** últimos 7 dias corridos (hoje − 7 dias, fuso UTC-3)
- **DESCARTE IMEDIATO:** qualquer evento anterior ao início da janela
- Sem eventos na janela → `sem_eventos: true`, JSON válido retornado

### 4.4 Cascata de IA (ordem de fallback)
```
Gemini 2.0 Flash (padrão)
    ↓ RATE_LIMIT (429) ou 5xx
OpenRouter → perplexity/sonar-pro
    ↓ RATE_LIMIT ou 5xx
Perplexity Sonar Pro (direto)
    ↓ todos falharam
Erro 502 com mensagem amigável
```
- Se o frontend pedir `provedor: "perplexity"` explicitamente, a ordem é invertida
- Erros `CHAVE_NAO_CONFIGURADA` e `CHAVE_INVALIDA` pulam silenciosamente para o próximo

### 4.5 Persistência KV
- Chave: `dashboard:semana:{YYYY-WNN}` (semana ISO)
- TTL: 10 dias
- Regra de sobrescrita: novo resultado só substitui o existente se tiver **mais eventos**
- `sem_eventos: true` nunca apaga resultado com eventos

### 4.6 Bloqueios de Segurança no Frontend
- Ctrl+U (view-source), Ctrl+S, Ctrl+Shift+I/J/C (DevTools), F12 bloqueados
- Menu de contexto (botão direito) bloqueado
- **NÃO remover estes bloqueios** — são parte do produto

---

## 5. Estrutura JSON Retornado pelo Worker

```json
{
  "empresa": "string",
  "data_analise": "YYYY-MM-DD",
  "sem_eventos": false,
  "cobertura_nota": "string",
  "_provedor_usado": "gemini|openrouter|perplexity",
  "timestamp": "ISO-8601",
  "fontes_consultadas": [
    { "rodada": 1, "query": "string", "resultado": "string" }
  ],
  "eventos": [{
    "classificacao": "CRITICO|RELEVANTE",
    "titulo": "string",
    "evento": "string",
    "impacto_credito": "string",
    "contexto": "string",
    "monitorar": "string",
    "lente_setorial": "string",
    "regulador_focus": "string",
    "fonte_primaria": "https://url-real.com",
    "fonte_tipo": "CVM|AGENCIA_RATING|ANBIMA|B3|IMPRENSA",
    "data_evento": "YYYY-MM-DD|nao_identificada",
    "tags": ["string"]
  }]
}
```

---

## 6. Pontos de Extensão Seguros

### 6.1 Novos Filtros Setoriais (Worker)
- Adicionar entrada em `FILTROS_SETORIAIS` no `radar-standalone-worker.js`
- Estrutura obrigatória: `{ tese_credito, critico[], relevante[], ruido[], tags_prioritarias[], reguladores_focus, lente_modelo }`
- Adicionar chave correspondente em `REGULADORES` (Worker) e `REGULADOR` (index.html)
- Adicionar lista de emissores em `EMISSORES` (index.html)

### 6.2 Novas Abas no Painel de Empresa
- Adicionar `<button class="aba-btn">` em `#abas-bar`
- Adicionar case correspondente na função `setAba()`
- NÃO remover abas existentes: `aba-eventos`, `aba-buscas`, `aba-alertas`, `aba-arquivo`

### 6.3 Novos Endpoints no Worker
- Adicionar rota em `if (request.method === "GET")` ou POST handler
- Manter padrão CORS via objeto `CORS` e função `resp()`
- Nunca expor chaves de API diretamente no response

### 6.4 Novos Emissores
- Adicionar ao array do setor correspondente em `EMISSORES`
- O mapa `SETOR_DE` é gerado automaticamente via `Object.entries`

---

## 7. Endpoints da API

| Método | Parâmetros | Descrição |
|--------|-----------|-----------|
| `GET /` | — | Health check: retorna status das chaves e KV |
| `GET /?action=dashboard` | — | Retorna todos os resultados do KV da semana atual |
| `POST /` | `{ empresa, setor, provedor?, contexto_historico? }` | Dispara análise via cascata de IA |
| `OPTIONS /` | — | CORS preflight |

---

## 8. IDs Críticos — Nunca Renomear

```
#topbar          #body            #sidebar         #sidebar-list
#busca           #main            #dashboard       #emp-panel
#emp-head        #emp-body        #fontes-bar      #abas-bar
#status-bar      #mobile-bottom-nav  #mobile-drawer-overlay
#btn-run         #btn-varredura   #emp-badge       #emp-setor-label
#emp-nome-label  #dash-eventos    #dash-data       #versao
```
