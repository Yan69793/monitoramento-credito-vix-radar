---
data: 2026-08-14
tipo: auditoria
tags: [vix-radar, auditoria, engenharia]
status: ativo
---

# Auditoria Geral 2026-08-14 (vix-radar-general-audit)

## Veredito

Saudavel. Nucleo solido em auth, CORS, rate limit, telemetria, sanitizacao de ingestao, veracidade da UI e versionamento repo/producao. Health ao vivo: Worker v4.9.193, `ok:true`, todos os bindings e sub-checks true, HTTP 200 em 0,25s. Frontend v202.8 em producao, `app/index.html` e `app/deploy_zip` identicos (MD5), admin sincronizado, CACHE_VERSION coerente. Zero bloqueante no script de veracidade da UI; 3 termos reservados conferidos manualmente contra o glossario e corretos.

## Achados novos (todos P3)

1. **Skill com referencia morta (OPENROUTERVIVO).** SKILL.md citava `probeOpenRouterSonarPro`, removido no v4.9.180 (OPENROUTER-DEAD, `api/src/worker.js:7486`). Caminho vivo: `verificarSaldoOpenRouter` (~13886) + probe `chamarOpenRouter` no health (~14015). Corrigido na skill nesta auditoria.
2. **Matriz nao cobria CALVAL-V2 nem XSS write-path.** Subsistemas novos de 12-13/08 (tier de fonte da agenda, strip de HTML em `sanitizarPayloadRadar`). Checklist adicionado a `references/audit-matrix.md`.
3. **"Cobertura ANBIMA" e terceiro sentido do termo reservado** (`app/index.html:5486-5491`). Rotulo qualificado e com texto explicativo, nao engana, mas o glossario manda: um termo, um significado. Adicionar "Cobertura ANBIMA" (disponibilidade de preco ANBIMA por emissor) ao glossario ou renomear o rotulo.
4. **Disjuntor de custo fail-open e silencioso em erro de KV** (`api/src/worker.js:17911-17923`). `verificarDisjuntorDiario` engole excecao e retorna false. Mitigado pelo gate de health das rotinas (KV fora derruba ok e as rotinas param), mas o catch mudo esconde o evento. Correcao barata: `console.error` no catch.
5. **"Sem alertas" sem denominador explicito.** Formula correta (verificada), mas o contrato de indicador exige numerador/denominador declarados; o card mostra so o percentual e o selo.
6. **Git: 2 diretorios untracked** na raiz do repo: `Operacoes-Recorrentes/` (vazio) e `docs/entrevista-ff/` (material de preparacao Financial Finesse, nao relacionado ao VIX Radar). Commit, mover ou ignorar.

## Cobertura verificada sem achado

- Secrets hardcoded no src: nenhum (grep por padroes sk-/AKIA/eyJ).
- `Math.random`: 2 usos benignos (jitter de retry, taxa de amostragem).
- Estado global entre requests: `ADMIN_EMAIL`/`NEWSLETTER_DESTINATARIOS` so atribuidos em `aplicarConfigRuntime(env)`, idempotente.
- Multi-semana: `op=state` e endpoints criticos usam `carregarEstadoMultiSemana(env, 5)`; 2-3 semanas so em newsletter/health/auxiliares.
- `receber_analise`: routine_key 403 fail-closed, empresa validada contra EMISSORES_LISTA, sanitizador no write path, fila de verificacao com sampling, `sem_eventos` so com eventos vazios pos-sanitizacao, guarda INCONCLUSIVO contra cobertura <9 rodadas.
- XSS: `renderEventoCard` escapa tudo com `h()`; comentarios com `_escapeHtmlComentario`; admin com `esc()` (email, nome, status, heartbeats); briefing usa `_mkEl` (textContent); Market Overview v100 com `x()` + strip no Worker. Modulos admin interpolam so numeros/constantes.
- Merton: `calcMertonDD`/`scoreMertonToRisk` documentados (Bharath & Shumway 2008), driver `merton` visivel, exposto so via `op=predictive_v1` (admin).
- CSS: `strong` com color so em seletores escopados (`.cover-meta strong`, `.disclaimer strong`).
- Health nao mascara: `verificador_ok` no agregado e ja capturou os incidentes de 05/08 e 12/08.

## Lacunas declaradas

- Perf e a11y em navegador nao medidos nesta sessao (sem browser tooling). HTML ~700KB, CSP deliberadamente ausente (documentado no CLAUDE.md).
- `wrangler secret list` nao executado (sem token de API nesta sessao; o deploy-worker.ps1 tem gate de secret proprio).
- Logs de rotina em `logs/routines/` nao varridos a fundo (escopo de engenharia).
- Suites de teste nao rodam local (Smart App Control bloqueia workerd), CI verde documentado.

## Pendencias cruzadas

- P0 AUTHWEEK1: segue parcial, reset da assinatura em 15/08 08h. Guarda proposta (notificar 429 de limite semanal) aberta.
- P2 "fila de verificacao >20h validar": RESOLVIDO por evidencia, health ao vivo `verificador_ok:true` (dreno de 13/08 15h16-15h27 registrado em [[81 - Auditoria Geral e incidentes 2026-08-13]]).
- P2 canonical-test.yml: segue aberto.
- P3 Pages:Edit no token, P3 agenda 2x/semana, P3 postAdmin sem Bearer (confirmado vivo em `app/admin/vr-admin-shared.js:118-129`): seguem abertos.
