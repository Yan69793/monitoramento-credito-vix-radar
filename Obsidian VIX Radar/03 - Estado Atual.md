---
data: 2026-07-24
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 24/07 18h30 — **Worker v4.9.178 + Frontend v201.87 em produção, sem drift repo/prod.** Sprint de segurança e custo (Etapas 1–3 + CSRF-COOKIE1 + CATCH60 + F013 + PRED2) e a11y/cache no Pages (FOCUSTRAP1, INDEXNOSTORE, TOGGLEA11Y1, CONTRASTMUTED1). Health ao vivo: `ok:true`, `versao:v4.9.178`, kv/rate_limiter/telemetria true, `verificador_ok:true`, providers 2/2. Frontend `version.json` e `CACHE_VERSION=v201.87`. Git `99d0bed`. Detalhe: [[03a - Changelog]], [[PENDENCIAS.md]].
> [!success] 24/07 18h14 — **Noturno 24/07: submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens, 6 críticos.** Críticos: CSN, Kora Saúde, Oi, Oncoclínicas, Pão de Açúcar (GPA), Raízen. Dreno verificação async exit 0: fila 14, aprovados 13, rejeitados 1, erros_parse 0, ~636k tokens.
> [!success] 24/07 — **LOGLOCK1-REC resolvido.** Causa raiz: `FILE_ATTRIBUTE_PINNED` em 6177 itens (OneDrive). Flag removido + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID no `Write-Log` das 4 rotinas.
> [!success] 23/07 — Frontend v201.84: preview de link com `og:image` (1200x630). Worker v4.9.171–172 e FE v201.85 (FOCUSTRAP1) na cadeia do dia 23; superados pelo deploy 24/07.
> [!success] 23/07 10h15 — **Boletim diário reativado** (`RELATORIO_DIARIO_ENABLED` + `EMAIL_ALERTAS_ENABLED` no `[vars]`).
> [!info] 23/07 08h30 — Dashboard com eventos até 21/07 naquele momento era ausência de notícias novas, não falha de ingestão (revalidar se o painel parecer “parado”).

## Versões

| Componente | Versão | Health |
|---|---|---|
| Worker | **v4.9.178** | `ok:true`, kv/rate_limiter/telemetria true, `verificador_ok:true`, providers 2/2 |
| Frontend | **v201.87** | `CACHE_VERSION=v201.87`, `version.json` deployed_at 2026-07-24T21:04:21Z |
| Git | `99d0bed` (PRED2 / v4.9.178) | `main` limpa, alinhada a `origin/main` |

## Cobertura

| Métrica | Valor |
|---|---|
| Emissores | 103 (universo) |
| Noturno 24/07 | submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens (meta 500k, hard 700k sem hit), 6 críticos, ~51 min, dreno verif ok |
| Verificação async 24/07 (pós-noturno) | fila 14, aprovados 13, rejeitados 1, erros_parse 0, refusals 0, ~636k tokens, exit 0 |
| Matinal 23/07 | submit_ok=15 (top 15 por EWS), 5 críticos, 150.912 tokens, dreno verif ok |
| Noturno 22/07 | submit_ok=92 + 11 SKIP = 103/103, 5 críticos, 468.045 tokens |
| Críticos noturno 24/07 | CSN, Kora Saúde, Oi, Oncoclínicas, Pão de Açúcar (GPA), Raízen |

## Tasks Scheduler

| Task | Trigger | Status recente |
|---|---|---|
| VIXRadar-Matinal | 10h seg-sex | 23/07 Result 0 (submit_ok=15); 24/07 sem log matinal no diretório (fim de semana ou sem disparo no path de logs) |
| VIXRadar-Noturno | 18h diario | **24/07 18:04–18:14 Result 0** (submit_ok=103, dreno exit 0) |
| VIXRadar-Coleta-Volatilidade | ~17h | VOLCOLETA1/MONITORCEGO1 resolvidos 23/07; validar LastTaskResult em sessão Admin se necessário |
| VIXRadar-Verificacao-Async | 10:20 + dreno inline | 24/07 18:14 dreno pós-noturno exit 0 |
| VIXRadar-Export-Historico | 20:45 diario | 22/07 20:47 Result 0 |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok (health) |
| RATE_LIMITER_DO | ok (health) |
| RADAR_USAGE_EVENTS | ok (telemetria:true) |
| ESTADO_SEMANA_DO | declarado no `wrangler.toml` + usado no bundle (não exposto no health público) |
| Providers | 2/2 (Resend + Anthropic); probes OpenRouter removidos do health (OPENROUTERVIVO) |

## Pendências ativas (topo)

Ver [[PENDENCIAS.md]]. Após sprint 24/07 a maior parte dos P1/P2 de segurança e custo está **RESOLVIDO**. Residuais úteis:

| P | Item |
|---|---|
| P3 | HDASH1-RES — código morto `handleUso` / senha em query (não é bypass) |
| P3 | ALRT1-RES — alerta crítico vs `prefs.newsletter` (decisão de produto) |
| P3 | P-CVM — `admin_corrigir_datas_cvm_kv` em lote (requer admin) |
| P3 higiene | `Set-Cookie radar_token` ainda emitido no login embora `extractToken` ignore cookie (CSRF-COOKIE1) |
| P3 higiene | Remover funções mortas `probeOpenRouter*` do bundle |

## Checklist pós-rotina

Após cada noturna (ou evento de produção significativo), verificar:

- [x] `03 - Estado Atual.md` — atualizado 24/07 (esta nota)
- [x] `03a - Changelog.md` — entrada sprint 24/07
- [ ] `03b - Infraestrutura.md` — só se mudou binding/cron (sem mudança de binding nesta sprint)
- [x] `00 - Índice (MOC).md` — versões Worker/Frontend
- [x] `CLAUDE.md` — tabela Produção já em v4.9.178 / v201.87

Script de drift: `pwsh ./scripts/check-vault-drift.ps1` compara vault contra health ao vivo e reporta divergências. Execute após cada deploy ou se suspeitar de desalinhamento.

---

*Snapshot gerado em 2026-07-24 ~18h45 BRT (health ao vivo + metrics noturno/verif 24/07 + git 99d0bed). Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
