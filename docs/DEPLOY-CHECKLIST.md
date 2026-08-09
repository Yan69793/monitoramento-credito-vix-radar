# ✅ DEPLOY_CHECKLIST — Radar de Crédito Privado

> **DESATUALIZADO desde 2026-06-14.** Conteúdo histórico preservado abaixo para registro.
> Descreve checklist manual para `radar-standalone-worker.js`, que não existe mais — o deploy atual é `pwsh scripts/deploy-worker.ps1` / `pwsh scripts/deploy-pages.ps1`.
> **Fonte atual:** [README.md](../README.md) e [`Obsidian VIX Radar/03 - Estado Atual.md`](../Obsidian%20VIX%20Radar/03%20-%20Estado%20Atual.md).

---

Use este checklist **antes de cada deploy**. Não pule nenhum item.

---

## 🔍 FASE 1: Validação de Arquivos

- [ ] `index.html` presente no diretório
- [ ] `radar-standalone-worker.js` presente no diretório
- [ ] `_headers` presente no diretório
- [ ] `_routes.json` presente no diretório
- [ ] Nenhum arquivo faltando (nunca deploy com 3 arquivos)
- [ ] Nenhum arquivo extra desnecessário (só esses 4 + PDFs/XLSXs se for referência)

**Se falhar**: PARE. Não fazer deploy sem os 4 arquivos.

---

## 🔐 FASE 2: Segurança

### Frontend (`index.html`)

- [ ] Procurar por "GEMINI_API_KEY" → 0 resultados
- [ ] Procurar por "OPENROUTER_API_KEY" → 0 resultados
- [ ] Procurar por "PERPLEXITY_API_KEY" → 0 resultados
- [ ] Procurar por "JWT_SECRET" → 0 resultados
- [ ] Procurar por "RadarAdmin@2026" → 0 resultados (senhas só em env vars)
- [ ] Procurar por "Radar2026" → 0 resultados (senhas só em env vars)
- [ ] Confirmar que admin panel requer password via `prompt()` (nunca hardcoded)
- [ ] Confirmar que JWT é armazenado em `localStorage`, não em global JS

### Backend (`radar-standalone-worker.js`)

- [ ] Procurar por "GEMINI_API_KEY = " → 0 resultados (deve vir de `env.GEMINI_API_KEY`)
- [ ] Procurar por "OPENROUTER_API_KEY = " → 0 resultados
- [ ] Procurar por "PERPLEXITY_API_KEY = " → 0 resultados
- [ ] Procurar por "JWT_SECRET = " → 0 resultados
- [ ] Procurar por chaves hardcoded (ex: `sk-...`) → 0 resultados
- [ ] Confirmar que todas as rotas POST/admin requerem `validarJWT()` com nível admin
- [ ] Confirmar que cascadeAI só tenta próximo provider se `response.status === 429`
- [ ] Confirmar que nenhuma chave de API é logada em KV (nunca expor secretos em logs)

**Se falhar**: PARE. Remover todas as secrets antes de deploy.

---

## ✅ FASE 3: Funcionalidade Crítica

### Autenticação

- [ ] Login com email + "Radar2026" funciona e retorna JWT
- [ ] Tokens JWT expiram em 12h (ou conforme `exp` setado)
- [ ] Login com senha errada retorna erro "Email ou senha incorretos"
- [ ] Admin login com "RadarAdmin@2026" abre painel (se deslocar para frontend, revalidar)
- [ ] localStorage limpo, página refresh → volta ao login

### Dashboard

- [ ] Eventos com `classificacao === "critico"` aparecem se < 15 dias
- [ ] Eventos com `classificacao === "relevante"` aparecem se < 7 dias
- [ ] Eventos com data > 15/7 dias não aparecem no dashboard
- [ ] Eventos com `classificacao === "ruido"` nunca aparecem
- [ ] Se não há eventos, painel fica vazio (sem erro de "dados não encontrados")
- [ ] Card exibe: empresa, evento, relevância, tag, data, link

### Filtros

- [ ] Drawer de filtros abre/fecha
- [ ] Filtro por setor filtra corretamente
- [ ] Filtro por criticidade (crítico/relevante) filtra corretamente
- [ ] Limpar filtros volta ao estado original
- [ ] Filtros persistem em URL (se implementado) ou localStorage

### Análise / Watchdog

- [ ] Botão "Analisar" dispara `POST /analyze` com JWT
- [ ] Loading spinner aparece durante análise
- [ ] Análise completa em <30s (caso contrário, timeout)
- [ ] Se Gemini sucesso → resultado aparece imediatamente
- [ ] Se Gemini 429 → tenta OpenRouter (sem avisar ao user)
- [ ] Se OpenRouter 429 → tenta Perplexity
- [ ] Se todos falham → erro "Serviço temporariamente indisponível"
- [ ] Se chave inválida (401/403) → erro "Erro de autenticação interna" (sem cascade)
- [ ] Watchdog roda às 8h e 18h em dias úteis (verificar logs)

### Admin Panel

- [ ] Acessar com Ctrl+Shift+A abre prompt de senha
- [ ] Senha errada → "Acesso negado"
- [ ] Senha certa → painel aparece
- [ ] Botão "Test Providers" testa Gemini, OpenRouter, Perplexity (mostra status de cada um)
- [ ] Botão "Export Logs" baixa CSV com logs de acesso
- [ ] Logs mostram: timestamp, user, ação (login, analyze, export_log)

### Acesso aos Eventos

- [ ] GET `/eventos?dias=15&classif=critico` retorna JSON estruturado
- [ ] GET `/eventos?dias=7&classif=relevante` retorna JSON estruturado
- [ ] GET `/eventos?setor=Financeiro` (se implementado) filtra por setor
- [ ] Sem JWT → 403 (acesso negado)
- [ ] Com JWT expirado → 403 (acesso negado)
- [ ] Com JWT válido → 200 + eventos

**Se falhar em qualquer acima**: PARE. Debugar, testar em staging, depois retry.

---

## 🧪 FASE 4: Tratamento de Erros

### Conexão / Rede

- [ ] Desligar internet → erro "Verifique sua conexão"
- [ ] Ligar internet novamente → retoma
- [ ] Worker offline → erro "Serviço indisponível" (sem stack trace)

### API Externas

- [ ] Gemini key inválida → erro "Erro de autenticação interna"
- [ ] OpenRouter balance zerado → tenta Perplexity (esperado)
- [ ] Perplexity key expirada → erro final "Serviço temporariamente indisponível"
- [ ] Nenhum erro mostra status HTTP cru (sempre msg amigável pt-BR)

### Dados

- [ ] KV vazio → dashboard vazio (não erro)
- [ ] localStorage bloqueado (modo privado) → aviso "Use modo normal"
- [ ] Setor inexistente → filtra resultado vazio (não erro)

### Parsing

- [ ] Resposta Gemini malformada (não JSON) → error log + msg "Resultado inválido"
- [ ] Resposta ANBIMA faltando campos → graceful fallback (não crash)

**Se falhar em qualquer**: revisar try-catch, adicionar tratamento, retry deploy.

---

## 📊 FASE 5: Performance

- [ ] Carregamento da página em modo produção < 2s (sem cache)
- [ ] Com cache localStorage → < 500ms
- [ ] Análise completa (Gemini + resposta) < 30s
- [ ] Export logs < 5s
- [ ] Worker tempo resposta normal < 1s (exceto durante análise)
- [ ] Nenhum console.error ou console.warn visível ao user
- [ ] Nenhum memory leak detectável (DevTools → Memory)

---

## 🚀 FASE 6: Deploy Técnico

### Worker Deploy

- [ ] Acessar Cloudflare Dashboard → Workers
- [ ] Selecionar `radar-credito-api` (produção) ou `radar-credito-api-staging`
- [ ] Fazer upload do ZIP ou copiar conteúdo de `radar-standalone-worker.js`
- [ ] Clicar "Save and Deploy"
- [ ] Esperar "Deployment successful"
- [ ] Testar endpoint `?action=teste` → recebe resposta de cada provider
- [ ] **NUNCA fazer deploy do Pages antes do Worker estar 100% OK**

### Pages Deploy

- [ ] Acessar Cloudflare Dashboard → Pages
- [ ] Selecionar `radar-credito` (produção) ou `radar-credito-staging`
- [ ] Fazer upload do ZIP com `index.html` + `_headers` + `_routes.json`
- [ ] Clicar "Upload files" ou "Direct Upload"
- [ ] Esperar "Deployment successful"
- [ ] Clicar preview URL
- [ ] Testar login, dashboard, admin panel

### Pós-Deploy

- [ ] Abrir URL produção em browser novo (Incognito) → sem cache
- [ ] Fazer login
- [ ] Verificar dashboard carrega
- [ ] Abrir DevTools → Console → sem erro
- [ ] Testar análise completa
- [ ] Verificar localStorage tem `token` e `user_email`
- [ ] Logout e refresh → volta ao login

---

## 📝 FASE 7: Documentação & Rollback

- [ ] Anotar a data/hora do deploy
- [ ] Anotar o que foi mudado (ex: "Adicionado filtro por setor")
- [ ] Se possível, manter ZIP anterior (~7 dias) para rollback rápido
- [ ] Avisar equipe que deploy foi concluído (Slack, email, etc.)

### Se Problema Pós-Deploy (30min depois)

- [ ] Rollback: fazer upload do ZIP anterior
- [ ] Testar novamente (Fases 1-5)
- [ ] Documentar o problema (qual erro, quando começou)
- [ ] Debugar offline antes de novo deploy

---

## ⏱️ Tempo Esperado

- **Fases 1-2 (Validação)**: 5 minutos
- **Fases 3-5 (Testes)**: 15-20 minutos
- **Fase 6 (Deploy)**: 5 minutos
- **Fase 7 (Pós-Deploy)**: 5 minutos

**Total**: ~30-40 minutos por deploy

Se tá demorando mais, algo tá errado. Revisar.

---

## 🚨 BLOQUEADORES DE DEPLOY

**NÃO DEPLOY se:**

- [ ] Algum dos 4 arquivos está faltando
- [ ] Tem secret/chave no frontend ou worker (hardcoded)
- [ ] Admin panel acessível sem senha
- [ ] Erro não tratado aparece ao user (stack trace)
- [ ] Teste de login não funciona
- [ ] Console mostra erro que impede dashboard carregar
- [ ] Nenhum provider de IA respondendo (todos 401/403)
- [ ] Worker não fez deploy ou Deploy diz "failed"

**Se tá em qualquer desses**, voltar ao código, arrumar, testar em staging, depois retry.

---

## ✨ Pronto para Deploy?

Se chegou até aqui com TODAS as checkboxes marcadas ✅, seu deploy está seguro.

**Nunca** faça um deploy parcial ou "acho que tá ok". O Radar é usado por clientes reais. Credibilidade é tudo.

---

**Última atualização**: 2026-04-02  
**Versão**: 2.0  
**Responsável**: Yan Szuchmacher

