---
data: 2026-08-29
tipo: auditoria
tags: [vix-radar, auditoria-geral, backend, frontend, rotinas]
status: fechada
---

# Auditoria Geral — VIX Radar (2026-08-29, noite)

Segunda auditoria geral do dia (a da tarde produziu SCANFALLBACK-MORTO1, WATCHDOG-NAOINICIOU1 e FRESCORNOTIFY1). Esta rodou readonly, com trabalho v4.9.222 de outra sessão em voo no working tree, revisado sem tocar.

## Veredito

Sistema saudável no núcleo e degradado na camada de agendamento local. Produção v4.9.221 com health integralmente verde (`ok`, `kv`, `telemetria`, `sentry_ok`, `verificador_ok`, `fonte_externa_ok` todos true, atribuição CVM por CNPJ reportando no health), suíte local 141/141 incluindo o código em voo, veracidade de UI sem achado bloqueante. Os problemas do dia estão nas rotinas: a Sentinela perdeu a sexta-feira inteira sem executar e sem sinal (P1), a AgendaSemanal está morta no lote 3 desde 26/08 com o monitor escalando sem dono (P2), e o cache de último recurso expira em 24h e foi de fato apagado pelo gap de 28/08 (P2). Cobertura desta auditoria: método por comando com saída citada em todas as camadas abaixo; não prova ausência de bug, prova o que foi coberto.

## Top riscos

| Sev | Área | Achado | Evidência | Correção | Causa raiz | Guarda sistêmica |
|---|---|---|---|---|---|---|
| P1 | Rotinas | SENTINELA-DIAPERDIDO1: nenhuma execução na sexta 29/08, task toda verde | 0 eventos no Operational (controle: 108 em 28/08, 1845 de outras tasks hoje), sem log do dia, `LastRun 28/08 17:55`, `NextRun 31/08`, `NumberOfMissedRuns 0` | Vigia de entrega no monitor-tasks + segunda âncora de meio-dia | Âncora 09h25/09h55 perdida no sono mata a cadeia de repetição do dia; StartWhenAvailable não ressuscita; única rotina sem vigia | Item na PENDENCIAS + item permanente na matriz da skill (entrega da Sentinela + controle positivo de detector) |
| P2 | Rotinas | AGENDASEM-TRAVA1: morta no lote 3 desde 26/08, escalada 3 dias sem dono | `monitor_20260829.log` (`exit=1073807364 idade=3d ESCALADO`), log da rotina morre em `Lote agendasem-3` 22:14:44, stderr 0 bytes, 8/20 atualizados | Observar dom 30/08 22h; se repetir, instrumentar o lote | Morte no `claude -p` sem stderr (padrão 27-30/07); alerta repetido sem entrada na fila vira ruído | Entrada na PENDENCIAS fecha o elo monitor → fila |
| P2 | Backend/KV | FALLBACKTTL1: `fallback:{empresa}` com TTL 86400, apagado pelo gap de 28/08 | `worker.js:15845` (put), `:15862` (leitura), regra VOLTTL1 de 20/08, gap de 28/08 documentado | `expirationTtl: 86400*3`, 1 linha, candidato ao v4.9.222 | VOLTTL1 corrigiu só a chave do incidente, sem varrer os demais puts diários | Varredura de `expirationTtl` 86400 virou item permanente da matriz (feita hoje: os demais são dedups de 24h intencionais) |
| P2 | Verificador | VERIFCACHE-ROUNDTRIP1 (já aberto 27/08): APROVADO_CORRIGIDO em cache volta como rejeição e retrata evento | PENDENCIAS 27/08, worker.js:12141-12142, 18714 | Aceitar `APROVADO_CORRIGIDO` na comparação + guard por `veredicto_original` | Campo de decisão sobrescrito pelo desfecho | Teste de round-trip proposto na entrada; empacotar no v4.9.222 |
| P3 | Watchdog | Alerta do WATCHDOG-NAOINICIOU1 falhou na única tentativa real | `retry-vixradar-noturno_20260829.log` 15:19:06 `Impossível conectar-se`; GET 200 sob PS 5.1 medido nesta sessão | Retentativa (2x) no bloco de alerta | Tentativa única em try/catch, janela pós-boot | Adendo na entrada do WATCHDOG; fechar só com entrega real provada |
| P3 | Docs | ESTADO/PENDENCIAS diziam "aguarda merge" com o merge já em origin/main | `git branch -r --contains ab2622f` e `a1c5283` → `origin/main` | Corrigido nesta sessão nos dois arquivos | Docs escritos na branch antes do merge, ninguém remediu depois | Regra já existente (medir antes de afirmar estado) aplicada no fechamento |
| P3 | Em voo | `score_calculado` (EWSFLOOR1) não inclui o +5 de "Padrão de deterioração" | worker.js:14614 (captura) vs :14673 (+5 pós-piso) | Nota de revisão para a sessão do v4.9.222 (capturar após o bloco de +5 ou documentar) | Contrafactual capturado antes de bônus condicional | Testes ews-piso cobrem o resto; item é semântico, não de soma |

## Backend

Worker v4.9.221 em produção = `wrangler.toml main` = repo (sem drift de versão). Diff não commitado é trabalho em voo do plano v4.9.222 (EWSFLOOR1, MATERIALSAT1, BRIEFDEDUP1 + 7 exports para teste), casado 1:1 com os testes untracked. Suíte local `npx vitest run`: **17 arquivos, 141 testes, 141 passando, exit 0**. Cascade Anthropic-only confirmado (`chamarClaudeAnalise` em 9637/9640/9833/9836/10481/10484 + verificador ~18964). Multi-semana: 23 call sites, N=2 (3), N=3 (5), N=5 (15), coerente com a doc. CORS por allowlist (`ALLOWED_ORIGINS`, worker.js:3634/17502), JWT sem fallback inseguro (uso direto de `env.JWT_SECRET`, presença checada no health :17416). Varredura de `expirationTtl: 86400`: 9 sites, 8 são dedup/token de 24h intencionais, 1 achado real (FALLBACKTTL1). Estado global de request e floating promises: sem achado no delta (única adição module-level do diff em voo é constante derivada imutável `_TAGS_MAT_POR_PESO`).

## Frontend

Bump v202.34 em voo: `CACHE_VERSION` e `?v=` alinhados em `app/` (index + admin-bootstrap + 7 exports + 5 imports), `deploy_zip/index.html` idêntico por hash ao `app/index.html`. Os 4 módulos de `app/js` alterados ainda divergem do `deploy_zip` (esperado: o `deploy-pages.ps1` sincroniza no deploy; gate 3.4 confere). Render novo do piso usa só campos internos do Worker (`piso_valor`, `score_calculado`, `piso_causa` de tabela fixa), sem sink de XSS novo. `app/admin/vr-admin-*.js` é legado sem nenhuma referência no `index.html` vivo (grep: nenhum hit fora dos próprios arquivos e comentários de migração em `app/js`).

## Veracidade da UI

`audit-ui-metrics.mjs`: exit 0, 0 bloqueantes, 9 informativos, 3 rótulos reservados conferidos manualmente contra o glossário: `totalEmissores = Object.values(EMISSORES).reduce(soma)` (universo), `criticosAtivos = c.size` com `c = new Set(criticos.map(empresa))` (emissores distintos), `relevantesAtivos = d.size` com `d = new Set(relevantes.filter(e => !c.has(e.empresa)))` (distintos, excluindo críticos), faixas do card 90/70 iguais às do glossário, janela de 30 dias declarada. Pendência de manutenção: quando o v202.34 subir, "piso" e "score calculado" precisam de entrada no glossário e na constante `TERMOS_RESERVADOS`.

## Segurança, perf e a11y

Sem achado novo. Método: delta do código desde a última auditoria (26/08) + greps dirigidos (JWT, CORS, sinks do render novo). Perf e a11y sem medição de navegador nesta sessão (lacuna declarada); último Lighthouse mobile 21/08 com A11y/BP/SEO 100 e nenhum delta de UI relevante desde então além da nota de piso (estilos inline mínimos).

## IA generativa / cascade LLM

Verificador adversarial segue no caminho crítico; a degradação conhecida é o VERIFCACHE-ROUNDTRIP1 (LLM05/output handling: o próprio sistema destrói a idempotência do veredicto), aberto e com correção proposta. Fila de verificação drenada hoje (`FIM: ... pendentes=0` às 14:55). Disjuntores de custo presentes (`cb:aberto:{provider}`). Sem mudança de provedores.

## Preditivo

`check-drivers-preditivos.ps1` (export 28/08): evento 23/103, momentum 3/103, recorrencia 12/103, desagio 11/103, mercado 0 e merton 0 (ambos MORTO_CONHECIDO, DRIVERMORTO1), `CHECK_DRIVERS_OK`. Sem regressão; merton segue aguardando pipeline de market_cap.

## Confiabilidade

Rotinas de 29/08: noturna 103/103 (`FIM: Total do dia 103/103`, com 60 deferidos por orçamento conforme ESTADO), matinal 20/20, verificação 14:55 com fila zero, coleta OK 17:02. O gap de 28/08 foi detectado pelo monitor das 07:00 (2 rotinas sem entrega, email enviado) e pelo frescor-check, confirmando as guardas da tarde. Achados novos: Sentinela (P1) e AgendaSemanal (P2) acima.

## Cobertura desta auditoria

| Camada | Coberta | Método | Lacuna |
|---|---|---|---|
| Repo/governança | sim | git status/branch/log com saída citada | — |
| Backend Worker | sim | suíte 141/141, greps dirigidos, leitura dos trechos em voo | leitura integral do worker não refeita (delta-based sobre a auditoria de 26/08) |
| Frontend | sim | diff -U0, hashes app vs deploy_zip, extração das linhas 3835/4187/4638 | sem execução em navegador |
| Veracidade UI | sim | audit-ui-metrics + conferência manual dos 3 termos | glossário ainda sem "piso" (entra com o v202.34) |
| Segurança | parcial | delta + greps JWT/CORS/sinks | sem varredura ASVS completa nesta sessão |
| Perf/a11y | não | — | sem browser run; último Lighthouse 21/08 |
| Confiabilidade | sim | logs de rotina, Scheduler, event log com controle positivo, health | causa exata do não-catch-up do StartWhenAvailable não determinada (comportamento documentado) |
| LLM/cascade | sim | greps de call sites, fila, pendência aberta | 11 `enviarResend` diretos não reclassificados um a um (delta zero desde EMAILSILENT1) |
| Preditivo | sim | check-drivers com saída colada | — |
| Migração KV→DO | não | — | segue sem métrica de progresso (risco conhecido da matriz) |

## Próximos passos

1. P1: vigia de entrega da Sentinela no `monitor-tasks.ps1` (código puro, sem token) + avaliar âncora extra de meio-dia.
2. P2: empacotar no v4.9.222 o VERIFCACHE-ROUNDTRIP1 e o FALLBACKTTL1 (1 linha) junto com as Fases 1.1-1.3 já em voo.
3. P2: observar AgendaSemanal domingo 30/08 22h e fechar ou instrumentar.
4. P3: retentativa no bloco de alerta do retry; glossário ganha "piso"/"score calculado" no deploy do v202.34; nota de revisão do `score_calculado` (+5) para a sessão em voo.

## Manutenção da skill

`references/audit-matrix.md` ganhou nesta sessão: varredura permanente de `expirationTtl` de 1 dia contra a cadência do escritor, vigia de entrega para rotina com âncora+repetição, controle positivo obrigatório para detector de ausência, e correção do caminho vivo dos módulos admin (`app/js/admin`; `app/admin` é legado). `SKILL.md` teve o comando de drift ampliado para incluir `app/js`.
