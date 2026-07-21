---
data: 2026-07-21
tipo: auditoria
tags: [vix-radar, auditoria-geral, backend, frontend, llm, preditivo]
status: ativo
---

# Auditoria Geral, VIX Radar, 2026-07-21 (tarde)

Rodada `/vix-radar-general-audit` em modo readonly, pos deploy v4.9.168 / v201.81 e pos atualizacao da propria skill (Estado Atual, OPENROUTERVIVO, Merton).

Nao reabre ADMINXSS1, PDFXSS1, VOLTASK1, VERSAO3X (resolvidos). Cruzou `PENDENCIAS.md`.

## Veredito

Nucleo de producao saudavel: Worker v4.9.168, frontend v201.81, health ~170 ms, bindings ok, POST anonimo 401, `app/` = `deploy_zip/` 8/8 por hash, matinal de hoje com submit_ok=18 e dreno de verificacao ok. O risco residual de produto e o Merton ainda mover score com driver quase invisivel, alimentado por coleta que roda com sucesso operacional mas `sucesso=0` cotacoes novas. Documentacao de estado (vault + header do PENDENCIAS) ainda descreve 167/80.

## Top riscos (novos ou reconfirmados com evidencia fresca)

| Sev | ID | Achado | Evidencia | Acao |
|-----|-----|--------|-----------|------|
| P1 | MERTONLIVE1 | Score Merton soma sempre; driver so com `dd < 1.5` | `v4.9.168.js:12989-12990` | Push driver quando `score +=` mudar; documentar modelo |
| P2 | VOLFEED1 | Coleta LastResult 0 mas `sucesso=0`, falha=21, cache_skip=73 | `coleta_volatilidade_20260721.log`, `meta_volatilidade.json` | Diagnosticar collect_cotacoes; nao confiar em exit 0 da task |
| P2 | METRICSZERO1 | Skip idempotente zera metrics do dia | log 20/07 15:33 submit_ok=103 vs metrics JSON 0; script grava metrics sempre `:682` | Nao regravar no skip |
| P2 | VERIFQ-ORFAO1 / VERIFINJ1 / DEDUPFILA1 / ROUTINEKEY-PLAIN1 | Reconfirmados no bundle 168 e SKILL noturno L38 | linhas 7797+, 10135, key plain | Deploy Worker + secret |
| P3 | DOCSTALE1 | Estado Atual e header PENDENCIAS em 167/80 | vault `03`, PENDENCIAS L1-8 | Atualizar snapshot pos esta auditoria |
| P3 | INDEXNOSTORE / admin `?v=201.69` | index no-store; scripts admin cache bust antigo | `_headers`, `index.html:3989-3993` | Deploy Pages |

## Versoes e drift

| Camada | Repo | Producao | Drift? |
|---|---|---|---|
| Worker | `main=v4.9.168.js`, `WORKER_VERSAO=v4.9.168` | health `versao:v4.9.168` | Nao |
| Frontend | `version.json` + `CACHE_VERSION=v201.81` | `vixradar.com/version.json` v201.81 | Nao |
| deploy_zip | hash = app (index, version, headers, 5 admin js) | deployado | Nao |
| Vault Estado Atual | snapshot 20/07 167/80 | prod 168/81 | Sim (doc) |
| Git | dirty: CLAUDE.md, PENDENCIAS.md, meta_volatilidade.json; untracked graphify | HEAD `4af3142` | Working tree sujo (docs/dados) |

Health bruto: `ok:true`, bindings kv/rate_limiter/telemetria true, providers 2/2, verificador_ok true. `ESTADO_SEMANA_DO` esta no wrangler e no codigo; health publico nao expoe o binding.

## Backend

- Bindings: RADAR_KV, RATE_LIMITER_DO, ESTADO_SEMANA_DO, RADAR_USAGE_EVENTS, route, crons presentes.
- `handleRegistrar` rejeita `<>` em nome/empresa/email (`:5594`).
- Merton: `calcMertonDD` / `scoreMertonToRisk` vivos; `drivers.push("merton")` so se `f.merton_dd < 1.5` enquanto `score += scoreMertonToRisk(...)` sempre.
- OpenRouter: `probeOpenRouterSonarPro` em cron `:14690`, health diario `:15235`, metricas `:15539` (OPENROUTERVIVO).
- Verificador: interpolacao crua `Titulo: ${ev.titulo}` em `:10135` (VERIFINJ1); fila KV sem DO lock (VERIFQ-ORFAO1).
- `carregarEstadoMultiSemana(env, 5)` em paths criticos; alguns usam 3 (aceitavel por contexto).
- POST `{}` anonimo: HTTP 401.

## Frontend

- `strong` global so `font-weight:600`, sem `color` (`:2809-2811`).
- XSS admin/PDF: `h(e.nome||"-")`, `h(e.email)`, `h(e.empresa||"-")` e campos de evento com `h()`.
- Scripts admin ainda `?v=201.69` com app em v201.81.
- index.html ~700 KB, Cache-Control no-store (INDEXNOSTORE).

## Rotinas

| Task | LastRun | Result | Nota |
|---|---|---|---|
| Matinal | 21/07 10:00 | 0 | submit_ok=18, dreno ok |
| Noturno | 20/07 18:00 | 0 | run real 14:28 submit_ok=103; 18h skip; metrics zeradas |
| Verif async | 21/07 10:20 | 0 | 12 aprov / 3 rej |
| Coleta vol | 21/07 13:29 | 0 | sucesso cotacao=0 (VOLFEED1) |
| Recon CVM | 20/07 12:32 | 1 | dry-run manual 21/07: 0 divergencias, exit ok no log |

## IA / LLM (OWASP 2025)

- LLM01: VERIFINJ1 aberto.
- LLM05: PDF/admin XSS fechados no 168/81.
- LLM09: verificador adversarial no path; fila orfao/pendente sem UI (VERIFQ-ORFAO1).
- LLM10: DEDUPFILA1, VERIFMODEL1 (Sonnet 100%), OPENROUTERVIVO, SKIP24H.

## Skill general-audit

Atualizada nesta sessao (manha): Estado Atual, OPENROUTERVIVO, Merton, ESTADO_SEMANA_DO, METRICSZERO1. Sem lacuna nova de escopo nesta rodada alem de VOLFEED1 (promover a matriz se repetir).

## Proximos passos

1. MERTONLIVE1: driver sempre que pontuar + documentar.
2. VOLFEED1: por que `collect_cotacoes` devolve sucesso=0 com task Result 0.
3. METRICSZERO1: script local, nao regravar metrics no skip.
4. ROUTINEKEY-PLAIN1: tirar chave do SKILL.md.
5. Lote Worker: VERIFQ-ORFAO1, VERIFINJ1, DEDUPFILA1.
6. DOCSTALE1: atualizar `03 - Estado Atual.md` e header do PENDENCIAS.

## Lacunas desta rodada

- Sem browser Playwright (a11y/FOCUSTRAP1 nao re-medidos).
- Sem JWT/admin_senha: nao reteste `receber_analise` end-to-end nem staleness 103 via API autenticada.
- Sem confirmar se `OPENROUTER_API_KEY` existe no Worker (so caminho de codigo).
- Conteudo exato da ROUTINE_KEY nao foi impresso (so existencia L38).
