# DEVELOPMENT — Radar de Crédito Privado

Versão 2.0 | Atualizado 2026-04-02

---

## 🎯 Visão Geral

O Radar é um sistema de monitoramento de crédito privado em tempo real. Estrutura:
- **Frontend**: `index.html` — Single Page App rodando em Cloudflare Pages
- **Backend**: `radar-standalone-worker.js` — Worker autônomo em Cloudflare Workers
- **Storage**: `RADAR_KV` — Cache KV para eventos e logs de acesso
- **Autenticação**: JWT HS256 (Web Crypto API) + localStorage (12h de sessão)

**URL Produção**: https://radar-credito.pages.dev  
**Worker Produção**: https://radar-credito-api.prospects-intel.workers.dev  
**Worker Staging**: https://radar-credito-api-staging... (URL será confirmada)

---

## 🔒 Segurança — Regras Imutáveis

### Nunca no Frontend
- ❌ Chaves de API (Gemini, OpenRouter, Perplexity)
- ❌ JWT_SECRET
- ❌ Senhas de admin/user
- ❌ Lógica de controle de acesso (regras de "quem pode ver o quê")

Tudo que tá no frontend é visível com 2 cliques no DevTools.

### Sempre no Backend (Worker)
- ✅ Validação de JWT
- ✅ Verificação de permissões (admin vs user)
- ✅ Chamadas a APIs externas (Gemini, OpenRouter, Perplexity)
- ✅ Leitura/escrita em KV
- ✅ Logging de acessos

### Environment Variables — Worker Settings
- `GEMINI_API_KEY` — Google AI Studio (free, 1.500 req/dia)
- `OPENROUTER_API_KEY` — OpenRouter (pago, verificar saldo em openrouter.ai/credits)
- `PERPLEXITY_API_KEY` — Perplexity (pago, renew em perplexity.ai/settings/api)
- `JWT_SECRET` — Gerado uma vez, mantido fixo
- `ADMIN_PASSWORD` — RadarAdmin@2026 (copiar do seu gestor de senha)
- `USER_PASSWORD` — Radar2026

**Nunca** escrever essas variáveis em arquivo `.js` ou `.html`. Sempre via Cloudflare Dashboard → Worker Settings → Environment Variables.

---

## 📂 Estrutura do Código

### Frontend (`index.html`)

```
index.html
├── <head>
│   ├── Fontes (Inter)
│   ├── Estilos globais (CSS variables para navy/gold)
│   └── Data attributes para i18n (pt-BR)
├── <body>
│   ├── #app (raiz Vue.js)
│   ├── Admin panel (escondido, Ctrl+Shift+A ou 5 clicks)
│   ├── Login modal
│   ├── Dashboard (cards de críticos/relevantes)
│   ├── Drawers para filtros
│   └── <script> (todo JS inline)
```

**Padrão de acesso:**
- Sem login: painel vazio ("Faça login para ver eventos")
- User logado: vê eventos dos últimos 15 dias (críticos) e 7 dias (relevantes)
- Admin logado: acesso a access logs, export CSV, teste de providers

**Padrão de erro (sempre pt-BR):**
```javascript
showError("Erro ao buscar eventos", "Verifique sua conexão com a internet")
// nunca: console.error(err.message) ou "API returned 502"
```

### Backend (`radar-standalone-worker.js`)

```
worker.js
├── export default { async fetch(request, env) {} }
├── Funções auxiliares
│   ├── dataHoje() — retorna data em UTC-3 (Brasília)
│   ├── kvGet() / kvPut() — abstrações para KV
│   ├── gerarJWT() / validarJWT() — autenticação
│   └── cascadeAI() — orquestra Gemini → OpenRouter → Perplexity
├── Rotas
│   ├── POST /login — retorna JWT
│   ├── GET /eventos?dias=15&classif=critico — filtra eventos do KV
│   ├── POST /admin/log_acesso — registra ação
│   ├── GET /admin/get_log — retorna logs (requer JWT admin)
│   ├── GET /admin/export_log — CSV (requer JWT admin)
│   ├── GET /?action=teste — testa cada provider
│   └── POST /analyze — dispara análise (requer JWT user)
└── Tratamento de erros
    ├── 400 — request malformado
    ├── 401 — sem JWT
    ├── 403 — JWT inválido/expirado
    ├── 429 — rate limit (ao 1º Gemini, tenta OpenRouter; ao 2º, tenta Perplexity)
    └── 500 — erro interno (nunca expor stack trace)
```

---

## 🚀 Fluxo de Implementação — 3 Passos

### Passo 1: Planejar em 3 Linhas
Antes de abrir o editor, escrever:

```
O quê: Adicionar filtro de setor no frontend
Onde: index.html, linha ~1200 (drawer de filtros) + worker GET /eventos?setor=
Teste: Abrir staging, selecionar "Elétrico", verificar se carrega só eventos desse setor
```

### Passo 2: Implementar
Editar os arquivos conforme planejado. Padrão de commit (se usar Git):

```
[FEATURE] Filtro por setor no dashboard
- Frontend: adicionar checkbox para cada setor no drawer
- Worker: parsing de ?setor= e filtro no KV query
- Test: OK em staging, 3 setores testados
```

### Passo 3: Testar Tudo

Usar o **DEPLOY_CHECKLIST.md** (arquivo próximo a este).

---

## 🔄 Cascade AI — Como Funciona

Quando uma análise é disparada (`POST /analyze`):

1. **Gemini 2.0 Flash** (timeout 25s)
   - Free, 1.500 req/dia
   - Se sucesso → retorna resultado
   - Se 429 (rate limit) → vai ao passo 2
   - Se erro de chave/auth → NÃO tenta próximo (erro de config, não de capacity)

2. **OpenRouter sonar-pro** (timeout 20s)
   - Pago (~R$0.01 por análise)
   - Se sucesso → retorna resultado
   - Se 429 → vai ao passo 3
   - Se erro de chave/auth → NÃO tenta próximo

3. **Perplexity sonar-pro** (timeout 25s)
   - Pago (~R$0.01 por análise)
   - Se sucesso → retorna resultado
   - Se falha → erro final (sem próximo fallback)

**Regra crítica**: só dispara próximo provider se rate limit (429). Não dispara se chave inválida (401/403).

---

## 📊 Classificação de Eventos

### 🔴 Crítico
- Rebaixamento de rating ou perspectiva negativa
- Default, atraso, recuperação judicial
- Covenant breach ou waiver
- Fraude, investigação regulatória
- Spread >1pp vs média 20 dias
- Volume >1,5× média histórica
- **Janela**: últimos 15 dias

### 🟡 Relevante
- Resultado trimestral (ITR, DFP)
- Emissão, recompra, amortização de dívida
- M&A, desinvestimento, mudança de controle
- Revisão de perspectiva de rating
- Mudança de auditoria ou conselho
- Notícia com impacto financeiro/operacional
- **Janela**: últimos 7 dias

### ⚪ Ruído
- Marketing, produto, operação sem impacto financeiro
- Repetição de notícia
- Sem relação com crédito
- **Tratamento**: descartar, nunca aparecer no frontend

---

## 🐛 Cenários de Erro — Como Tratar

| Erro | Causa | Ação | Mensagem ao User |
|------|-------|------|------------------|
| **API key missing** | `GEMINI_API_KEY` não setada em Worker | Checklist: variáveis de env no Dashboard Cloudflare | "Serviço indisponível. Contate o admin" |
| **API key invalid** | Chave expirada ou revogada | Renovar em Google AI Studio / OpenRouter / Perplexity | "Erro de autenticação interna. Contate o admin" |
| **Worker timeout** | Análise > 25s | Reduzir escopo de análise ou aumentar timeout | "Análise demorou. Tente novamente" |
| **Sem eventos** | KV vazio ou fora da janela | Esperado. Não é erro | (sem mensagem, dashboard vazio) |
| **JWT expirado** | localStorage > 12h | User refaz login | "Sessão expirada. Faça login novamente" |
| **localStorage bloqueado** | Browser em modo privado / cookie policy | Informar user | "Não conseguimos salvar sua sessão. Use modo normal" |
| **Cold start Worker** | Primeiro request do dia (Cloudflare hibernation) | Normal. Aceitar latência 2-3s | (sem mensagem, user vê loading) |
| **KV quota exceeded** | Muitos logs acumulados | Arquivo de logs antigos (> 30 dias) | "Admin: limpar logs em KV" |

---

## 🧪 Teste Manual — Checklist Por Cenário

### Cenário 1: Login
- [ ] Email inválido → erro "Email ou senha incorretos"
- [ ] Senha errada → erro "Email ou senha incorretos"
- [ ] Email correto + senha correta → localStorage setado, dashboard carrega
- [ ] Abrir DevTools → localStorage tem `token` e `user_email`

### Cenário 2: Dashboard Vazio
- [ ] Novo user (KV sem eventos) → painel vazio, sem erro
- [ ] Filtro "últimos 15 dias" mas só tem eventos de 20 dias atrás → painel vazio
- [ ] Setor sem eventos → painel vazio

### Cenário 3: Admin Panel
- [ ] 5 clicks no logo ou Ctrl+Shift+A → prompt de senha
- [ ] Senha errada → "Acesso negado"
- [ ] Senha certa → painel abre, vê logs e botão de test
- [ ] Clica "Test Providers" → testa Gemini, OpenRouter, Perplexity individualmente
- [ ] Clica "Export Logs" → download CSV

### Cenário 4: Análise
- [ ] Clica "Analisar" → loading spinner
- [ ] Gemini responde em <5s → sucesso, evento aparece no dashboard
- [ ] Gemini rate limit (429) → tenta OpenRouter, continua
- [ ] Todos 429 → erro "Serviço temporariamente indisponível"
- [ ] Chave inválida → erro "Erro de autenticação interna" (sem cascade)

### Cenário 5: Filtros
- [ ] Abre drawer de filtros
- [ ] Seleciona setor → dashboard filtra
- [ ] Seleciona criticidade (crítico/relevante) → filtra
- [ ] Limpa filtro → volta a mostrar tudo

### Cenário 6: Logout
- [ ] Clica logout → localStorage limpo
- [ ] Refresh página → volta ao login
- [ ] Tenta acessar admin sem token → painel vazio

---

## 🔧 Como Modificar — Exemplos Reais

### Exemplo 1: Aumentar Janela de Críticos para 20 dias

**Plano:**
```
O quê: Críticos aparecem há 20 dias, não 15
Onde: worker GET /eventos, linha ~250 (filtro 15 dias) + frontend, linha ~800 (label "últimos 15")
Teste: Staging, inserir evento de 18 dias atrás, verificar se aparece
```

**Implementação:**
1. Worker: mudar `15` para `20` na query de KV
2. Frontend: atualizar label e tooltip
3. Testar com evento fictício de 18 dias

### Exemplo 2: Adicionar Campo "Ação Recomendada" em Cada Evento

**Plano:**
```
O quê: Card de evento mostra "Ação: Revisar exposição" ou "Ação: Contato com emissor"
Onde: worker GET /eventos (retorna novo campo) + frontend card component (renderiza)
Teste: Staging, criar evento crítico, verificar se action_recommended aparece
```

**Implementação:**
1. Worker: adicionar lógica que seta `action_recommended` baseado em `classificacao`
2. Frontend: renderizar novo campo em cada card
3. Testar crítico e relevante

### Exemplo 3: Integrar ANBIMA Data Real

**Plano:**
```
O quê: Buscar spreads de um papel direto da ANBIMA Data
Onde: worker POST /analyze (add HTTP fetch para ANBIMA antes de Gemini)
Teste: Staging, analisar uma debênture, verificar se spread aparece no resultado
```

**Implementação:**
1. Worker: HTTP fetch(`https://data.anbima.com.br/...`)
2. Parse resposta JSON
3. Passar dados para Gemini como contexto
4. Testar com papel real (ex: VALE15)

---

## 📋 Deploy — Passo a Passo

**SEMPRE usar o `DEPLOY_CHECKLIST.md`**

Resumo rápido:
1. Editar código
2. Rodar checklist (4 arquivos presentes? JWT funciona? Erros tratados?)
3. ZIP com `index.html` + `radar-standalone-worker.js` + `_headers` + `_routes.json`
4. Deploy Worker primeiro (Cloudflare Workers → Upload ZIP)
5. Deploy Pages depois (Cloudflare Pages → Upload ZIP)
6. Testar em staging
7. Testar em produção

---

## 🚨 Red Flags — Quando Pedir Ajuda

Se você tá vendo isso e não tem certeza, **pare e pergunte**:

- Mexer em JWT ou autenticação
- Adicionar nova rota POST/GET sem saber o retorno esperado
- Mudar estrutura de dados no KV (pode quebrar logs antigos)
- Adicionar nova variável de environment (precisa setar no Dashboard também)
- Modificar cascade AI sem testar cada provider
- Remover ou renomear arquivo (_headers, _routes.json, etc.)

---

## 📞 Contato

- **Dono**: Yan Szuchmacher (yan.szuchmacher@...)
- **Slack**: #radar-dev (se tiver)
- **Issues críticas**: mensagem direto no Slack

---

**Última atualização**: 2026-04-02  
**Status**: Em produção com usuários reais  
**Backup**: Sempre manter ZIP de cada deploy
