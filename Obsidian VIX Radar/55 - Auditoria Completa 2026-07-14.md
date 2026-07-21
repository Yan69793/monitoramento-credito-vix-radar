---
data: 2026-07-14
tipo: auditoria
tags: [vix-radar, auditoria, operacional]
status: ativo
---
# Auditoria Completa — VIX Radar (2026-07-14)

## Sintese executiva

Sistema funcional, health `ok:true` (v4.9.155), 103/103 emissores cobertos no KV, verificador ativo. Porem: matinal de hoje estourou hard cap com 966k tokens para apenas 4/15 emissores (Sonnet ~241k/emissor real vs 40k/emissor estimado). Noturna de 13/07 rodou sem logs sobreviventes (cleanup agressivo da matinal destruiu evidencias). Causa primaria dos 3 dias sem atualizacao (10-12/07): saldo Anthropic pre-pago esgotado (-US$1,21), 3o episodio em 10 dias. Migracao para assinatura Claude Code aplicada mas token budgeting permanece descalibrado.

## Versoes e drift

| Camada | Repo | Producao | Drift? |
|---|---|---|---|
| Worker | v4.9.155 (`api/v4.9.155.js`) | v4.9.155 | Nao |
| Frontend | v201.75 (`deploy_zip/version.json`) | v201.75 | Nao |
| Bindings | kv/rate_limiter/telemetria | Todos true | Nao |
| Providers | 2/2 configurados | 2/2 | Nao |
| Verificador | ativo | `verificador_ok:true` | Nao |
| Emissores | 103 (`EMISSORES_LISTA`) | 103 (`listar_todos_emissores`) | Nao |

## Incidentes abertos

| ID | Severidade | Descricao | Estado |
|---|---|---|---|
| MAT1/CRED1 | CRITICO | Saldo Anthropic esgotado 10-12/07, 3o episodio em 10 dias | Corrigido (assinatura), risco residual: limite semanal |
| CHUNK1 | ALTO | `Split-IntoChunks` colapsava lotes em 1 emissor | Corrigido e commitado (`return ,$chunks`) |
| STATELEAK1 | ALTO | KV com 125 chaves vs 103 canonicas (22 residuos mojibake) | Corrigido (v4.9.153) |
| CLEANAGG1 | ALTO | Cleanup agressivo da matinal destruia logs da noturna do dia anterior | **Corrigido nesta auditoria** — `Remove-IfStale` agora respeita `$KeepDays` mesmo em modo agressivo |
| TOKENEST1 | ALTO | Estimativa de tokens 6x abaixo do real (40k/emissor vs 240k/emissor) | **Aberto** — causa o hard cap ser ultrapassado em 5x |
| RACEKV1 | MEDIO | `persistirResultadoCompartilhado` sem lock KV (read-modify-write race) | Aberto, design pronto (nota 54), deploy pendente |
| HARDCAP_BYPASS | ALTO | Hard cap so verificado entre lotes, lote unico de 966k passou batido | **Aberto** — sem solucao sem throttling mid-batch |
| AGENDA_CREDIT | ALTO | `VIXRadar-AgendaSemanal` falhando por "Credit balance too low" | Aberto |

## Achados

### CRITICO
- **Cleanup agressivo destruia evidencias da noturna** — `cleanup-rotina-artifacts.ps1:22` usava `$Aggressive -or` para bypassar `$KeepDays`, removendo logs do dia anterior independente da idade. Matinal chamava `Invoke-Cleanup -Aggressive` ao final, apagando logs da noturna da noite anterior. Evidencia: nenhum log de noturna sobreviveu apos 02/07. Corrigido: remocao do `$Aggressive -or` na condicao, mantendo extended targets (metrics JSON) mas respeitando `$KeepDays`.

### ALTO
- **Token budgeting descalibrado (TOKENEST1)** — Matinal 14/07: 1 lote Sonnet de 4 emissores consumiu 966k tokens (~241k/emissor). Estimativa usada: 40k/emissor (6x abaixo). Script so verifica tokens apos conclusao do lote, sem throttling mid-batch. Hard cap de 180k foi ultrapassado em 5.3x. Evidencia: `matinal_metrics_20260714.json` — `tokens_total_est: 966367, token_hard_cap: 180000, deferred: 11`.

- **Sem evidencias da noturna 13/07** — Task Scheduler confirma execucao as 18:00 com exit 0, mas zero logs sobreviventes. Cleanup da matinal de 14/07 10:00 removeu todos os artefatos. Impossivel confirmar cobertura real dos 103 emissores na noturna de 13/07. Evidencia: `logs/routines/` sem arquivos `*noturno*20260713*`.

- **AgendaSemanal quebrada** — `VIXRadar-AgendaSemanal` falhou 13/07 03:00 com exit 1. Motivo: "Credit balance too low (assinatura Claude Code)". Calendario de divulgacao pode estar desatualizado no KV.

### MEDIO
- **Repo sujo com 27 arquivos modificados** — Multiplos fixes de 13/07 nao commitados: CHUNK1 (2 scripts), migracao auth (3 scripts), monitor-tasks.ps1, deploy-pages.ps1, + marketing. Risco de perda em caso de checkout ou conflito.

- **`--add-dir` carrega ~1MB de contexto por lote** — Scripts dir (505K) + scheduled-tasks dir (487K) enviados a cada `claude -p`. Parte significativa do consumo de tokens sem beneficio proporcional.

- **7+ catch blocks vazios em writes KV** — `v4.9.155.js`: cursor persistence, rate limit recording, circuit breaker recording. Falhas transientes de KV sao silenciosamente ignoradas.

- **`admin_health_check` requer `admin_senha` (ADMIN_PASSWORD)**, nao `routine_key` — documentado na skill de auditoria como `action=admin_health_check + senha`, mas o campo esperado e `admin_senha`, nao `routine_key`.

## Validacao em producao

| Teste | Resultado | Evidencia |
|---|---|---|
| `GET /` health publico | `ok:true, v4.9.155, verificador_ok:true, providers 2/2` | curl 17:19 BRT |
| `listar_todos_emissores` | 103 emissores | curl com `routine_key` |
| `version.json` frontend | `v201.75` deploy 13/07 00:22Z | curl |
| `admin_health_check` com `routine_key` | `Acesso negado` (esperado — requer `admin_senha`) | curl |
| `data/historico/2026-07-13/` | 4 arquivos (manifest, predictive, series_delta, zscores) | dir |
| Matinal 14/07 | 4/15 processados, 966k tokens, 11 deferred | `matinal_metrics_20260714.json` |
| Verificacao async 14/07 | Fila vazia, 0 eventos pendentes | `verificacao_async_metrics_20260714.json` |
| Noturna 13/07 | Task Scheduler exit 0, sem logs sobreviventes | `Get-ScheduledTask` |

## Lacunas

- `admin_health_check` nao testado (requer `ADMIN_PASSWORD`, indisponivel no escopo readonly)
- `dados_para_analise` com emissor canonico nao testado (requer validate full pipeline)
- `receber_analise` smoke test nao executado (requer payload JSON completo + escrita KV)
- Testes autenticados com JWT nao executados (escopo readonly)
- Bloco E (frontend/CORS) verificado apenas `version.json`; regra CSS `<strong>` nao conferida no bundle atual
- RACEKV1 design pronto mas deploy pendente (nota 54)

## Próximos passos

### P0 — Antes da noturna 18:00 hoje
1. **Recalibrar estimativa de tokens** nos scripts matinal e noturno — subir de 40k/emissor para 80k/emissor (Sonnet) e 25k/emissor (Haiku) como estimativa inicial conservadora, com ajuste baseado em medias moveis das ultimas 3 execucoes.
2. **Commitar fixes pendentes** — CHUNK1, migracao auth, CLEANAGG1, com mensagens atomicas.

### P1 — Esta semana
3. **Resolver TOKENEST1** — implementar media movel de tokens/emissor por modelo, ajustar `$TokenPerEmitterSonnet` e `$TokenPerEmitterHaiku` dinamicamente.
4. **Migrar para Claude Code Routines (Remote)** — seguir `REGISTRAR-CLOUD.md`, eliminar dependencia do PC local.
5. **Aplicar RACEKV1** — DO-based lock para `persistirResultadoCompartilhado` (design na nota 54).

### P2 — Backlog
6. Auditar `--add-dir` — remover arquivos desnecessarios do contexto, manter so o essencial (batch prompt templates).
7. Preencher catch blocks vazios em writes KV com `telemetria.error()`.
8. Adicionar alerta de "Credit balance too low" no `monitor-tasks.ps1`.
