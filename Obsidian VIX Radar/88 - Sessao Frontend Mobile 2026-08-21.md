---
data: 2026-08-21
tipo: frontend
tags: [vix-radar, frontend, mobile, lighthouse, deploy, acessibilidade]
status: concluido
---

# 88 — Sessão Frontend Mobile 2026-08-21

Sequência da nota [[87 - Fechamento Rotinas 2026-08-21]]. Depois das rotinas, o painel foi aberto e o operador perguntou por que as notícias do dia não apareciam. Diagnóstico e correção nesta nota.

## Por que as notícias do dia não apareciam

- Os dados estavam gravados: KV `radar:estado:2026-W34` com os eventos das rotinas (Oi arresto TJRJ 19/08, Hapvida ANS 20/08, Light Fitch 19/08 etc., `updated_at` 22:21Z, 103 emissores).
- A aba aberta desde a manhã nunca puxava dados novos. `carregarResultadosCompartilhados()` (fetch de `?op=state`) só rodava na carga da página. O AUTONOMIAOFF1 removeu o refresh periódico, e os gatilhos de visibilitychange/pageshow só checavam versão nova de deploy (banner), não dados.
- Eventos com data de HOJE (21/08) não existem no sistema: as rotinas não acharam nenhum fato datado de 21/08, os fatos mais recentes são de 20/08. Zero eventos submetidos com `data_evento` 21/08 (conferido nos lotes do %TEMP% e no KV).

## Correção: refresh ao voltar para a aba

`app/index.html`: os handlers de visibilitychange e pageshow agora também chamam `_rdrDataRefresh()`, que roda `carregarResultadosCompartilhados()` com throttle de 60s, salva no localStorage e re-renderiza (sidebar, painel do emissor ou dashboard). Respeita o AUTONOMIAOFF1: é gatilho do usuário, não timer.

## Incidente v202.24 → v202.25

O primeiro deploy do fix (v202.24) subiu com `SyntaxError: Unexpected token 'var'`: o bloco foi inserido com `var` no meio de uma expressão com vírgulas e sem ponto-e-vírgula antes do `try` seguinte. Todos os gates do deploy passaram verdes porque o gate 3.3 só parseia os arquivos `.js` externos, não os 27 blocos `<script>` inline do index.html. Só o Lighthouse (errors-in-console) expôs. Corrigido em v202.25 com o bloco numa IIFE própria terminada em `;`, e com `node --check` por bloco inline antes do commit. Observação registrada: Observation 36 do task-observer (atualizada).

## Melhorias mobile (v202.26 a v202.28)

Auditoria com Lighthouse mobile (390x844) mais medições em runtime. Estado inicial: A11y 92, Best Practices 96, SEO 92.

- v202.26: contraste `#71717A` → `#A1A1AA` nos spans do ranking EWS (3.66/3.96 → acima de 4.5:1). Filtros do feed com aria-label contendo o texto visível. Botão Mercado da nav inferior com label alinhado. Drawer-fechar 44→48px. Pills do filtro maiores. Links LGPD ganham href com preventDefault. Ranking EWS empilha em coluna única abaixo de 520px (o grid de 130px + overflow hidden cortava conteúdo).
- v202.27: filtros sem aria-label (texto visível vira o nome acessível). Bottom nav esconde quando o drawer de emissores abre (alvos sobrepostos no rodapé).
- v202.28: drawer fechado fica invisível por completo (visibility/opacity/pointer-events com delay de transição). Antes, uma faixa de 60px ficava visível sobre a nav inferior, com o botão de fechar sobreposto ao botão Config.

## Resultado final

Lighthouse mobile: **A11y 100, Best Practices 100, SEO 100**. Console sem erros. Portão: health `ok:true`, HTTP 200, v4.9.208.

Resta:

- CLS ~0.16 a 0.43, varia entre rodadas, sem atribuição de elemento no relatório. Provável: fontes e painéis injetados após o paint.
- Categoria agentic browsing: llms.txt e agent-accessibility-tree (fora do escopo mobile clássico).

## Deploys e commits

| Versão | Commit | O quê |
|---|---|---|
| v202.24 | 87192b3 / 44fc97b | refresh na aba (com SyntaxError) |
| v202.25 | 2774b14 / ba07f6e | correção do SyntaxError |
| v202.26 | 74b9250 / 3159ffc | contraste, labels, toques, EWS empilhado |
| v202.27 | a1c2637 / 0d6eadf | aria-labels, nav escondida com drawer |
| v202.28 | 6968825 / 895ef8e | drawer fechado invisível |

Deploys via `deploy-pages.ps1` com todos os gates verdes, validação em produção e push no GitHub (branch main).

Ver [[00 - Índice (MOC)]] e [[03 - Estado Atual]].
