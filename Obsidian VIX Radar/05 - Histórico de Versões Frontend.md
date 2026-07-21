---
data: 2026-07-07
tipo: referencia
tags: [vix-radar, frontend, versoes, historico]
status: ativo
---
# Histórico de Versões Frontend

**Notas:** Este arquivo centraliza o histórico detalhado de mudanças do frontend (index.html) versões v99–v112. O CLAUDE.md slim faz referência a este documento.

---

## v99 → v100 (09/04/2026)

**Dashboard de Mercado ("📊 Visão Geral"):** Nova seção na sidebar com visão executiva consolidada. Cards de resumo, mapa de calor por setor (13 setores), timeline de eventos recentes, quick stats.

- Refino visual: Tipografia Inter, glassmorphism nos cards, animações fade-in/scale, badges polidos, hover states, espaçamentos profissionais.
- ARQUIVO_PRE atualizado: Reduzido de 9 para 5 eventos. CSN promovido para CRÍTICO (downgrade Moody's). Removidos JBS, Petrobras, Embraer, Hapvida (expirados >7d). Mantidos Raízen e GPA (RE fundamentais para PDF/Arquivo).
- CACHE_VERSION: v99 → v100

**Correções herdadas (v97–v99):**
- Raízen data_evento corrigida para 2026-03-11
- Badge "fora da janela do painel" no PDF
- Nota de escopo no PDF
- MutationObserver fix para anomalias "relevante" (v94)
- Anomalias PRE com merge protegido (v93)
- Cache no-store headers (v90)

**Divergência documentada (by design):** O PDF (exportar()) inclui TODOS os eventos do ciclo sem filtro de janela. O dashboard aplica dentroJanela() com 30d para todos os eventos (janela única). Isso é intencional.

---

## v100 → v101 (09/04/2026)

1. Remoção admin_key auto-login: Eliminado fluxo de login automático via query parameter `?admin_key=`. Risco de segurança para ambiente de produção.
2. Remoção bloqueio devtools: Removido script que bloqueava Ctrl+U, Ctrl+Shift+I, F12 e menu de contexto. Teatro de segurança sem valor real.
3. CNPJ pendente removido: Rodapé LGPD agora exibe "VIX Radar · Lei 13.709/2018 (LGPD)" sem menção a CNPJ pendente.
4. CACHE_VERSION: v100 → v101

---

## v101 → v102 (09/04/2026)

CSS do Market Overview movido para stylesheet principal. Os estilos `.mo-*` estavam presos dentro da template literal do PDF export (`htmlContent`), não no DOM do app. Resultado: Visão Geral renderizava sem nenhum estilo visual (sem cards, grid, heatmap, timeline). Corrigido injetando o bloco CSS completo no `<style>` principal.

CACHE_VERSION: v101 → v102

### Subversões v102b e v102c
- **v102b:** Fix scroll da Visão Geral. `#main` tem `overflow: hidden`. Adicionado `overflow-y: auto`, `flex: 1`, `min-height: 0` ao `#mo-content`.
- **v102c:** Setores clicáveis no Market Overview. Cada setor no heatmap expande/colapsa lista de empresas. Clique na empresa abre painel (chama `selecionar(nome)`). Novos elementos: `.mo-heatmap-group`, `.mo-emp-list`, `.mo-emp-item`, chevron animado, dots de status por empresa.

---

## v102c → v103 (10/04/2026)

Fix contagem Market Overview. `analisarEventosGlobais()` lia apenas `ARQUIVO_PRE` (0 relevantes). Card "Relevantes Ativos" mostrava 0 enquanto dashboard principal mostrava 2. Corrigido para mergear `resultados` (live/KV) + `ARQUIVO_PRE`, com deduplicação por empresa+titulo. Agora ambas as views usam mesma base de dados.

CACHE_VERSION: v102c → v103

---

## v103 → v104 (10/04/2026)

Fix contagem arquivados no dashboard. `renderDashboard()` calculava `todosEventos` apenas de `resultados` (live). Eventos do `ARQUIVO_PRE` fora da janela (Raízen, GPA) não eram contados como arquivados. Corrigido com merge `resultados` + `ARQUIVO_PRE` com dedup. Agora o card "Arquivados por Empresa" reflete a realidade.

CACHE_VERSION: v103 → v104

---

## v104 → v105 (10/04/2026)

1. Botão "Configurações" no header desktop: Adicionado ao lado do botão "Sair". Abre painel de preferências do usuário.
2. Mobile bottom nav 3→4 abas: Dashboard, Mercado (Visão Geral), Análise, Config. Removida duplicação (2 botões iam para o mesmo lugar).
3. Botão "← Painel de Eventos" na Visão Geral: Permite voltar ao dashboard sem navegar pela sidebar.
4. Painel de Configurações do usuário: Perfil, preferências de notificação (email toggle, frequência), seção "sobre", opção de cancelar emails (unsubscribe). Prefs salvas em localStorage por email.
5. CACHE_VERSION: v104 → v105

---

## v105 → v106 (10/04/2026)

1. Disclaimer financeiro permanente: Barra no rodapé do app (visível quando logado) com texto informativo sobre natureza não-recomendatória do conteúdo. Links para Termos e Privacidade.
2. Cookie banner LGPD: Banner com aceite de cookies essenciais. Registra consentimento em localStorage. Exibido apenas na primeira visita (ou até aceitar).
3. CACHE_VERSION: v105 → v106

---

## v106 → v107 (10/04/2026)

Fix crítico Painel Admin — aba Engajamento (antes "Analytics de Uso"):
- O Worker retorna `consultas` (string) no ranking, `total` (string) no overview e `eventos` (string) no heatmap.
- Frontend lia `d.total` no ranking (campo inexistente → todas empresas "undefined"), somava strings concatenando no overview ("196"+"9"="1969"), e comparava lexicograficamente no heatmap ("2">"51" = false).
- Corrigidos os 4 renderizadores (`usoHtmlRanking`, `usoHtmlOverview`, `usoHtmlHeatmap`, `usoHtmlRetencao`) com coerção via `Number()` e mapeamento correto do campo `consultas`.
- Ranking enriquecido: Cabeçalho mostra total de consultas absoluto. Tooltip de cada linha mostra o share (%) do total geral.
- Rename da aba: "Analytics de Uso" → **"Engajamento"** no botão da navegação e no título da seção.
- CACHE_VERSION: v106 → v107

---

## v107 → v108 (10/04/2026)

**Sistema de auto-update do cliente:** Usuários não precisam mais apertar Ctrl+Shift+R ao publicar nova versão.
- Implementado detector (IIFE `autoUpdateDetector` no final do `index.html`) que faz polling de `/version.json` a cada 3 min.
- Reage a `visibilitychange` e `pageshow` (bfcache).
- Quando detecta versão nova, mostra banner dourado no topo da tela com countdown de 5 min.
- Botões "Atualizar agora" e "Depois" (adia 10 min).
- Após 5 min sem ação, reload automático com cache-buster `?_v=timestamp`.

**version.json:** Novo arquivo no deploy_zip, gerado automaticamente do `CACHE_VERSION` do `index.html`. Contém `{"version":"v108","deployed_at":"..."}`. Tamanho ~56 bytes. Configurado no `_headers` com `no-cache, no-store, must-revalidate` para nunca ser cacheado.

**Meta tags anti-cache no `<head>`:** Defesa em profundidade (`Cache-Control`, `Pragma`, `Expires` via `<meta http-equiv>`), complementando os headers HTTP que já estavam corretos.

CACHE_VERSION: v107 → v108, também exposto como `window.CACHE_VERSION` para o detector acessar.

---

## v108 → v109 (10/04/2026)

1. **Fix mobile header scroll horizontal:** O `#topbar` mobile (max-width 768px) virou `display: flex`. O `#top-right` recebeu `flex: 1 1 0`, `min-width: 0`, `overflow-x: auto`, `touch-action: pan-x`, `-webkit-overflow-scrolling: touch`, scrollbar escondida e `scroll-snap-type: x proximity`. Agora os botões Relatório PDF, Configurações e Sair deslizam lateralmente com o dedo quando não cabem todos na tela.

2. **Long-press no logo para acesso admin mobile:** Antes só havia `Ctrl+Shift+A` (teclado), inacessível no celular. Adicionado handler IIFE dentro do módulo admin que detecta touch/mouse press de 700ms no `#topbar .logo`. Tolerância de 10px de movimento (evita disparo em scrolls acidentais). Vibração tátil de 40ms se disponível. Reusa `abrirAdmin()`/`fecharAdmin()`. Título do logo: "Pressione e segure para abrir o painel admin".

3. CACHE_VERSION: v108 → v109

**Validação em produção v109:** HTTP 200, version.json `{"version":"v109","deployed_at":"2026-04-10T16:16:26Z"}`, Cache-Control `no-cache, no-store, must-revalidate`, 4 ocorrências de `longPressFired` no HTML, 1 ocorrência de `touch-action: pan-x`, teste end-to-end de cadastro + notificação WhatsApp + aprovação pelo celular validado com usuário real (+55 21 98108-8992).

---

## v109 → v110 (10/04/2026)

Primeiro passo da remoção do seletor de escopo. Comentário no código: *"v110: removido seletor de setor. O usuário só dispara varredura por emissor individual. Varredura completa de todas as empresas roda automaticamente 1x/dia às 18h30 BRT."*

1. Removida lógica multi-empresa do scopeMode "setores" em `renderEscopo`/`executarVarreduraSelecionada`. Setores deixaram de ser acionáveis manualmente.
2. Cron único noturno assumido como única fonte de varredura completa. UI ainda mostrava as três tabs (a remoção visual veio em v111).
3. CACHE_VERSION: v109 → v110

---

## v110 → v111 (10/04/2026)

Remoção definitiva do seletor de escopo da UI. **Decisão de produto:** o usuário só dispara análise por emissor individual; varredura completa de todas as empresas roda exclusivamente via cron noturno.

1. Removida UI de "scope tabs" ("Esta empresa | Por setor | Todas · auto ⏰") do modal Novo Pulso. O modal sempre opera no modo `empresa`.
2. Variável `setoresSelecionados` removida e função `toggleSetor()` deletada. Estado simplificado para sempre `scopeMode = 'empresa'`.
3. `renderEscopo()` simplificada: só dois ramos — "emissor selecionado" (card colorido) ou "nenhum emissor selecionado" (alerta vermelho pedindo seleção na sidebar).
4. `contarEmpresasSelecionadas()` reduzida para `return selecionada ? 1 : 0`.
5. `executarVarreduraSelecionada()` simplificada: `const empresas = selecionada ? [selecionada] : [];` (antes era branch por modo).
6. CACHE_VERSION: v110 → v111

---

## v111 → v112 (10/04/2026 19:25 UTC)

Renomeação semântica e refino visual do fluxo de monitoramento manual. **Sem mudança de comportamento ou endpoint** — só linguagem e CSS do botão principal.

1. **Renomeação "Varredura" → "Pulso" em toda a UI do emissor.**
   - Botão principal `⚙ Varredura…` → `⚙ Novo Pulso…` (linha ~2039)
   - Modal `⚡ Configurar Varredura` → `⚡ Novo Pulso` com subtítulo "Leitura instantânea do emissor selecionado" (linha ~6093)
   - Estados de loading/erro/empty: "Aguardando varredura" → "Aguardando pulso", "Sinais desta varredura" → "Sinais deste pulso", "Varredura privada" → "Pulso privado", etc.

2. **Mensagem de cron atualizada:** "varredura completa é automática (8h e 19h)" → "pulso completo é automático (18h30 BRT, pós-fechamento B3)". Reflete o cron real do Worker (`30 21 * * *` UTC = 18h30 BRT).

3. **Botão "Capturar Pulso" com estilo refinado:** padding 12px, font 13px peso 800, uppercase, box-shadow dourada, hover com elevação. Antes era `⚡ Iniciar Monitoramento`.

4. **Empty-state do emissor selecionado redesenhado:** card com border-left colorido pelo setor, badge `◆ {SETOR}` em uppercase, nome do emissor destacado. Antes era texto plano `Empresa selecionada: ...`.

5. **METRICAS_CURADAS notas:** "Varredura completa." → "Pulso completo." em duas entradas (Sabesp BB-BI, evento CVM RAD).

6. CACHE_VERSION: v111 → v112

---

## Estruturas críticas do index.html (v100+)

| Estrutura | Linha aprox. | Função |
|-----------|-------------|--------|
| EMISSORES | ~1794 | Objeto com 13 setores, 100 empresas |
| SETOR_DE | ~1850 | Mapa auto-gerado empresa→setor |
| METRICAS_CURADAS | ~2040 | KPIs estáticos por empresa (4 cards cada) |
| ARQUIVO_PRE | ~2179 | 5 eventos CRÍTICOS pré-carregados |
| ANALISE_V100 | ~2271 | Nota de análise da sessão 09/04/2026 |
| dentroJanela() | ~2975 | Filtra eventos por janela rolling |
| exportar() | ~3879 | Gera PDF (sem filtro de janela) |
| anomalias-pre | ~6133 | Script de anomalias de mercado pré-carregadas |
| Market Overview | ~7375 | Dashboard de Visão Geral de Mercado |

---

**Nota:** Este arquivo é canônico para histórico do frontend. O CLAUDE.md slim refere-se a este documento para detalhes de mudanças passadas. Manter atualizado conforme novos deploys ocorrem.
