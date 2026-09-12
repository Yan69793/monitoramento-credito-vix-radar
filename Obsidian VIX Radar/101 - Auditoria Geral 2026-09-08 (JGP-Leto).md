---
data: 2026-09-08
tipo: auditoria
tags: [vix-radar, auditoria-geral, jgp-leto]
status: saudavel-com-achado
---

# Auditoria Geral 2026-09-08 (preparacao demonstracao JGP/Leto)

> [!info] 08/09 BRT — Auditoria geral read-only (`/vix-radar-general-audit`), parcial por limite de orcamento da sessao (backend profundo: greps de risco concluidos; perf/a11y em lab e suite vitest local NAO rodados). Nucleo saudavel.
> **Status:** vigente · **Data da Versao:** 2026-09-08 · **Origem do Registro:** pedido do operador (sistema sera apresentado a area de credito do JGP, atual Leto) · **Condicao de Obsolescencia:** cai quando as acoes abaixo forem executadas ou quando o Worker passar do v4.9.243 / frontend do v202.42.

**Produção medida ao vivo (08/09 11:28Z):** Worker v4.9.243, frontend v202.42, `HTTP:200 TEMPO:0.30s`, `ok:true`, kv/rate_limiter/telemetria/verificador_ok/sentry_ok/admin_email_ok/fonte_externa_ok true, `verif_orfaos_ativos:0`, `painel_fresco:true` (atualizado 04:37Z), `feed_fresco:true` (evento mais novo 04/09, idade_du 2). Repo == prod em versao; noturna de 07/09 = `SKIP: feriado B3` legitimo; sentinela controlada de 08/09 (01:22–01:36 BRT) = `FIM: resultado=OK analisados=8 submit_fail=0 lotes_ok=2 lotes_falha_provider=0`.

**Veracidade da UI:** `audit-ui-metrics.mjs` exit 0, 0 bloqueantes. Termos reservados conferidos no codigo (Market Overview, app/index.html ~L4150-4200): "Emissores" = totalEmissores (104); "Críticos" = emissores distintos com >=1 CRITICO em 30d; "Relevantes" = distintos RELEVANTE excluindo criticos; "Sem alertas" = (104-crit-relev)/104 com denominador e janela 30d explicitos e faixas >=90/>=70/<70 coerentes (valor e chip). Guardas ZEROINDISPONIVEL1/MOCARDFALSO1 presentes ("sem leitura" quando sem dados). CSS: nenhuma regra global `strong{color}` (0 hits `^strong {`); modulos `app/js` == `deploy_zip/app/js` por hash; auth Bearer no index via `_authHeaders()`.

**Achados:**

1. **P2 — Drift de conteudo sob o mesmo rotulo v202.42:** repo `app/index.html` (hash `9d9087e5…`) contem D2 (commits `f38e6f5`/`d44f37b`/`10e8e18`, 06/09) sem bump de CACHE_VERSION; producao == `app/deploy_zip/index.html` (hash `f3381aa2…`, servido ao vivo, SEM D2). Quem comparar so versao ve "sem drift". Correcao: bump para v202.43 no mesmo commit da aprovacao estetica D2 (ou revert); so depois, deploy Pages.
2. **P3 — Glossario/skill desatualizados:** `glossario-dominio.md` diz universo (103); producao/repo = 104 (Pampa Sul, `TOTAL_EMISSORES=104` no HTML servido). Atualizar termo "Emissores".
3. **P3 — Governanca da skill expirada:** SKILL.md/audit-matrix alinhadas a v4.9.236/v202.36 (03/09); producao v4.9.243/v202.42. Atualizar blocos de governanca (tags 237-243: FEEDRETRO1, FONTEDIVERG1, MERGEDUP1, REPROVADO-FAILCLOSED1, SWEEP-ORFAOS1/LIVENESS1 ja cobertas no ESTADO/PENDENCIAS, falta a matriz).
4. **P3 — Doc de watchdog defasada:** CLAUDE.md diz "7 heartbeats (sync_cvm, varredura_batch, varredura_matinal, newsletter, healthcheck_diario, cascade_analise, verificacao_async) com limites 16h/48h/26h". Codigo (v4.9.233, WATCHDOG-AGENTEMORTO1) monitora **5**: sync_cvm, newsletter, healthcheck_diario, varredura_local, verificacao_async; limite 16h so p/ verificacao_async, 26h demais. Atualizar CLAUDE.md (linha afirmava 7 desde 01/09 e nao acompanhou o v4.9.233 de 02/09).

**Conferencias backend ok:** bindings (KV, RATE_LIMITER_DO, ESTADO_SEMANA_DO, EMISSOR_DO, USUARIO_DO, CONFIG_DO, RADAR_USAGE_EVENTS) + migration v3 no toml; crons 30 15/30 21/0 1/0 4; `VARREDURA_CRON_AI_ENABLED=false`; bundle `v4.9.243.js` com `WORKER_VERSAO="v4.9.243"`; node --check OK (22.681 linhas); `carregarEstadoMultiSemana` presente com N=2/3/5 conforme endpoint (montarPlano/batch=3; leituras pesadas=5; feed/mercado=2) — coerente com "janela varia, nunca assumir N=5"; TTL 86400: 9 sites, todos dedup/token de 24h ou ja corrigidos (fallback 72h, FALLBACKTTL1) — nenhuma violacao VOLTTL1 nova; `CHAVEESCOPO1` respeitado (exatamente 3 aceites dual de REMOTE_VERIFICACAO_KEY); disjuntor so barra os 2 ramos LLM (`_RAMOS_CRON_COM_LLM`); Math.random so em jitter de login (LOGINTIMING1) e amostragem; sanitizador de payload 17 refs; `enviarEmailRastreado` 6 call sites.

**Lacunas declaradas (nao cobertas nesta sessao):** suite vitest local (exige `npm ci` com devDeps em `api/`); auditoria perf/a11y em lab (Lighthouse/axe — baseline Frontend-QA existe e esta verde no CI); XSS em `renderEventoCard` (lacuna ja declarada em 02/09, nao reaberta); heartbeats vivos (exige credencial, nao lido); aprovacao estetica D2 pendente do operador.

**Acoes recomendadas:** (1) decidir D2 (aprovar com bump v202.43 ou reverter) antes de qualquer deploy Pages; (2) atualizar CLAUDE.md (watchdog 5, nao 7); (3) atualizar skill/matriz/glossario (v4.9.243/v202.42; 104 emissores); (4) registrar este resumo como pendencia de fechamento.

Proximo passo sugerido: rodar a suite vitest (`cd api && npm ci && npm test`) e a checagem de modulos/rotinas agendadas numa sessao sem limite de orcamento, antes da demonstracao.
