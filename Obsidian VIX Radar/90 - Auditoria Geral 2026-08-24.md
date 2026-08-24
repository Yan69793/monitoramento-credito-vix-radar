---
data: 2026-08-24
tipo: auditoria
tags: [vix-radar, auditoria-geral, veracidade-ui]
status: saudavel
---

# Auditoria Geral 2026-08-24 — VIX Radar

Readonly, skill `vix-radar-general-audit`. Sem deploy, sem mudança em produção.

## Veredito

Saudável. Portão de produção 200 com `ok:true` (kv/rate_limiter/telemetria/sentry_ok/verificador_ok/admin_email_ok tudo true, providers 2/2). Sem achado bloqueante. Veracidade da UI batendo com o glossário nos 3 termos reservados. Auth fail-closed nos 3 probes. Código em HEAD idêntico a prod (v4.9.208 / v202.30); os 317 arquivos "modificados" são exclusivamente ruído CRLF (zero diff real, `git diff -w` = 0), com o `main` local à frente só dos 2 commits de histórico de dados.

## Top riscos

Nenhum P0/P1 confirmado. Dois itens de observação, nenhum reprova:

| Sev | Area | Achado | Evidencia | Correcao | Causa raiz | Guarda |
|---|---|---|---|---|---|---|
| Observação | Fonte | `fonte_externa_ok:false` (`cvm_fonte_motivo:ultimo_sync_falhou:http_404`), `cvm_fonte_ciclos_perdidos:null`, domínio CVMCADENCIA1 | health público 24/08 | Fonte `CIA_ABERTA/DOC` é SEMANAL, pública aos domingos; 24/08 (segunda) após domingo 23/08 sem lote pode ser cadência, não incidente. Acompanhar, não abrir incidente | Diagnóstico apressado já foi refutado 2x (19 e 20/08) | Sinal próprio em `fonte_externa_ok`, fora do `ok` agregado (HEALTHSPLIT1). Confirmar contra ramos `INF_DIARIO`/`CAD` antes de qualquer conclusão |
| Observação | Repo | `main` local ahead 2 de `origin/main` (só `chore(data): historico 2026-08-22/23`) | `git log origin/main..HEAD` | Push dos 2 commits de dados | Commits de rotina de export não empurrados | Fluxo de deploy exige push pós-validação; incluir em próxima sessão |

## Backend (confirmado OK)

- **Bindings** todos presentes e intactos no `api/wrangler.toml`: `RADAR_KV` (`c6805b8d...`), `RATE_LIMITER_DO`, `ESTADO_SEMANA_DO`, `EMISSOR_DO`, `USUARIO_DO`, `CONFIG_DO`; migrations v1/v2/v3 com `new_sqlite_classes` para os 3 DOs de domínio; `RADAR_USAGE_EVENTS` AE; route `api.vixradar.com` custom_domain; 4 crons (`30 15`, `30 21`, `0 1`, `0 4`); observability head 1.
- **main = `v4.9.208.js`**, changelog completo v4.9.196-208 reescrito (`WRCGL1`), gate de changelog presente no `deploy-worker.ps1`.
- **Auth fail-closed provado ao vivo:** `op=state` sem JWT → 401; `receber_analise` anônimo → 403; login inexistente → 401 genérico (anti-enumeração).
- **CORS:** allowlist `ALLOWED_ORIGINS` = `vixradar.com`/`www.vixradar.com`, refletida apenas para origem permitida. OPTIONS pré-vôo responde 204.
- **`sem_eventos` com prova:** `receber_analise` exige `_coberturaMin` (7, ou 3 LIGHT) — cobertura rasa vira INCONCLUSIVO, nunca ausência falsa.
- **Multi-semana:** `carregarEstadoMultiSemana(env, 5)` presente; endpoints críticos coerentes.
- **OpenRouter:** `verificarSaldoOpenRouter` vivo 1 call site (monitora saldo conta Perplexity), não contamina o health; Perplexity segue `{status:"removido"}`.
- **`waitUntil` 5 usos; `sanitizarPayloadRadar` no write-path (17 ocorrências).**

## Frontend (confirmado OK)

- **`app/index.html` e `app/deploy_zip/index.html`** SHA-256 idênticos (`e7297231...`); `version.json` v202.30 consistente.
- **CSS `strong`:** todas as ocorrências de seletor `strong` são escopadas (`.ph-metric strong`, `.ph-card strong`, `.ews-disclaimer strong`, `.com-author-label strong`, PDF `.cover-meta strong`/`.disclaimer strong`). Não existe regra global `strong { color }`. Conforme a matriz.
- **XSS:** `esc()`/`x()`/`h()` de escape usados em `titulo`/`empresa`/descricao (feed admin, anomalias, timelline, PDF). `document.write` só no fluxo de PDF gerado em popup próprio (intencional).
- **A11y:** teclado nos clicáveis do Market Overview/heatmap, `aria-label`, `aria-live` role status no toast, `tabindex`/`onkeydown` Enter+Espaço — herdados de v202.26/28.

## Veracidade da UI

`audit-ui-metrics.mjs` → exit 0, **0 bloqueantes**, 9 informativos, 3 termos reservados a conferir. Conferência manual, todos OK contra o glossário:

| Termo | Código | Mede | Conforme |
|---|---|---|---|
| Emissores | `+e.totalEmissores+` = `sum(EMISSORES[setor].length)` | universo 103 | ✓ |
| Críticos | `c = new Set(t.map(e=>e.empresa))` (eventos CRITICO na janela 30d) | emissores distintos com CRITICO | ✓ |
| Relevantes | `d = new Set(a.filter(e=>!c.has(e.empresa)).map(e=>e.empresa))` | emissores RELEVANTE excluindo críticos | ✓ |
| Sem alertas | `(totalEmissores-criticosAtivos-relevantesAtivos)/total` | denominador explícito, janela fixa "· 30 dias" declarada | ✓ |

Faixas: `>=90` mo-healthy `#16a34a`, `>=70` mo-relevant `#d97706`, `<70` mo-critical `#dc2626` — cor derivada do mesmo valor do selo.

## Segurança, perf e a11y

- `ANTHROPIC_API_KEY`/`ROUTINE_API_KEY`/`ADMIN_EMAIL`/`SENTRY_DSN` como secrets, sem fallback inseguro (gate do `deploy-worker.ps1`).
- Guarda `_semLeitura` cobre os 5 cards (ZEROINDISPONIVEL1/MOCARDFALSO1 no código).
- Core Web Vitals não re-medidos nesta auditoria readonly (rodada Lighthouse 100/100/100 foi 21/08, nota [[88 - Sessao Frontend Mobile 2026-08-21]]).

## IA generativa / cascade LLM

- Cascade Claude Haiku/Sonnet + Gemini fallback; OpenRouter fora do cascade de análise (desde v4.9.108).
- Caminho crítico do verificador adversarial `deveVerificar` + fila `radar:verif_fila:{data}` mantido (CONCORVERIF1 reserva atômica, CHAVEESCOPO1 credencial escopada).

## Cobertura desta auditoria

| Camada | Coberta | Metodo | Lacuna |
|---|---|---|---|
| Repo/governanca | Sim | git status/diff/log | Ruído CRLF 317 arquivos: descartado por `diff -w`=0, não inspecionado arquivo a arquivo |
| Backend | Sim | wrangler.toml + bundle v4.9.208 + probes live | `wrangler secret list` não executado (health cobre os 3 secrets que derrubam ok) |
| Frontend | Sim | index.html/deploy_zip SHA-256 + CSS/XSS | Sem Lighthouse nesta sessão |
| Veracidade UI | Sim | audit-ui-metrics.mjs + conferência manual | Só a Visão Geral de Mercado; demais telas por amostragem |
| Segurança | Sim | 3 probes auth + revisão CORS/secrets | Não varreu payloads injetados em cada tela |
| Perf | Parcial | estático (tamanho/greps) | Core Web Vitals não re-medido |
| A11y | Parcial | teclado/aria-live por heredagem | Leitor de tela não testado |
| Confiabilidade | Sim | health completo + export diário 23/08 (103/103, 0 erros) | DOs não auditados por saúde interna (sem campo público) |
| Cascade/IA | Parcial | caminho crítico + secrets | OWASP LLM Top 10 não re-analisado item a item |

## Próximos passos

1. Push dos 2 commits de histórico (`chore(data)` 22 e 23/08) para `origin/main`.
2. Confirmar status do `fonte_externa_ok:false` contra ramo `INF_DIARIO`/`CAD` da CVM na próxima janela — se domingo 23/08 realmente não publicou lote, é cadência; se 2 ciclos perdidos, abre alerta próprio.
3. Sem janela nova recomendada para esta sessão; pendências canônicas (MANIFESTOFRAGIL1, DEDUPON2, FEEDRERENDER1, ORF3D593D6, DRIVERMORTO1, WORKTREE12) seguem como registrado.
