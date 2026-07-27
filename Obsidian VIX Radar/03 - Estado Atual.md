---
data: 2026-07-27
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 27/07 01h20 — **Diagnostico de rotinas: Noturno operacional, Matinal parada desde 23/07, 5 rotinas perifericas sem task no Scheduler.** Worker saudavel (HTTP 200, ok:true, v4.9.181, 0.763s). Detalhe completo em [[03 - Estado Atual#Diagnostico 27-07|Diagnostico 27/07]]. Acoes pendentes em [[PENDENCIAS.md]].
> [!success] 26/07 18h53 — **Noturno 26/07: submit_ok=90, skip_ok=13, submit_fail=0, 396.230 tokens, 3 criticos.** Criticos: Arteris, Oi, Oncoclinicas. Dreno verificacao async exit 0: fila 9, aprovados 6, rejeitados 3, 505.919 tokens. Shadow Fable 5: 1 comparacao (Arteris), ambos APROVADO, teto 300k atingido no lote 2 (319.582 acumulado).
> [!success] 25/07 18h56 — **Noturno 25/07: submit_ok=91, skip_ok=12, submit_fail=0, 377.238 tokens, 5 criticos.** Criticos: Aegea Saneamento, Kora Saude, Oi, Oncoclinicas, Raizen. Dreno verificacao async exit 0: fila 13, aprovados 8, rejeitados 5, 505.935 tokens.
> [!success] 26/07 — **Shadow mode Fable 5 ativado (piloto).** `Invoke-FableShadow` em `scripts/run_vixradar_verificacao_async.ps1`: chamada Fable 5 em paralelo ao Sonnet para eventos CRITICO, sem alterar veredicto real. Teto 300k tokens/execucao. Zero mudancas no Worker. Dados em `logs/routines/verificacao_fable_shadow_*.json`. Criterio DOCBILL1: revisao manual apos 2-4 semanas. Ver [[PENDENCIAS.md]] (SHADOW1, DOCBILL1).
> [!success] 25/07 16h00 — **Worker v4.9.181 + Frontend v201.88. Fila PENDENCIAS zerada.** v4.9.181: email_enviar (apresentacao Igor/Bradesco BBI), VERSAO3X fix (WORKER_VERSAO agora bate com nome do arquivo), guard no deploy-worker.ps1 (rejeita deploy se WORKER_VERSAO divergir do filename). Health: `ok:true`, `versao:v4.9.181`, 802ms. Cron 7132d3dd (27/07 09:57 BRT) agora coberto. Auditoria geral: [[67 - Auditoria Geral 2026-07-25]]. Detalhe: [[03a - Changelog]], [[PENDENCIAS.md]].
> [!success] 24/07 18h14 — **Noturno 24/07: submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens, 6 criticos.** Criticos: CSN, Kora Saude, Oi, Oncoclinicas, Pao de Acucar (GPA), Raizen. Dreno verificacao async exit 0: fila 14, aprovados 13, rejeitados 1, erros_parse 0, ~636k tokens.
> [!warning] 24/07 — **Matinal 24/07 nao disparou.** Task VIXRadar-Matinal foi recriada em 24/07 as 10:00 (StartBoundary do trigger). 24/07 era sexta-feira, dia util. O vault anterior registrava “fim de semana” incorretamente. Primeiro disparo da task recriada previsto para 27/07 as 10:00.
> [!success] 24/07 — **LOGLOCK1-REC resolvido.** Causa raiz: `FILE_ATTRIBUTE_PINNED` em 6177 itens (OneDrive). Flag removido + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID no `Write-Log` das 4 rotinas.
> [!success] 23/07 — Frontend v201.84: preview de link com `og:image` (1200x630). Worker v4.9.171–172 e FE v201.85 (FOCUSTRAP1) na cadeia do dia 23; superados pelo deploy 24/07.
> [!success] 23/07 10h15 — **Boletim diario reativado** (`RELATORIO_DIARIO_ENABLED` + `EMAIL_ALERTAS_ENABLED` no `[vars]`).
> [!info] 23/07 08h30 — Dashboard com eventos ate 21/07 naquele momento era ausencia de noticias novas, nao falha de ingestao (revalidar se o painel parecer “parado”).

## Versoes

| Componente | Versao | Health |
|---|---|---|
| Worker | **v4.9.181** | `ok:true`, kv/rate_limiter/telemetria true, `verificador_ok:true`, providers 2/2 |
| Frontend | **v201.88** | `CACHE_VERSION=v201.88`, `version.json` deployed_at 2026-07-24T22:01:35Z |
| Git | v4.9.181 | main, 4 arquivos modificados (shadow mode Fable 5, sem commit), working tree dirty |

## Cobertura

| Metrica | Valor |
|---|---|
| Emissores | 103 (universo) |
| Noturno 26/07 | submit_ok=90, skip_ok=13, submit_fail=0, 396.230 tokens (meta 500k, hard 700k sem hit), 3 criticos, ~41 min, dreno verif ok |
| Verificacao async 26/07 (pos-noturno) | fila 9, aprovados 6, rejeitados 3, erros_parse 0, refusals 0, 505.919 tokens, exit 0. Shadow Fable 5: 1 comparacao, concordou, teto 300k atingido |
| Noturno 25/07 | submit_ok=91, skip_ok=12, submit_fail=0, 377.238 tokens, 5 criticos, ~46 min, dreno verif ok |
| Verificacao async 25/07 (pos-noturno) | fila 13, aprovados 8, rejeitados 5, erros_parse 0, refusals 0, 505.935 tokens, exit 0 |
| Noturno 24/07 | submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens (meta 500k, hard 700k sem hit), 6 criticos, ~51 min, dreno verif ok |
| Matinal 23/07 | submit_ok=15 (top 15 por EWS), 5 criticos, 150.912 tokens, dreno verif ok |
| Criticos noturno 26/07 | Arteris, Oi, Oncoclinicas |
| Criticos noturno 25/07 | Aegea Saneamento, Kora Saude, Oi, Oncoclinicas, Raizen |
| Criticos noturno 24/07 | CSN, Kora Saude, Oi, Oncoclinicas, Pao de Acucar (GPA), Raizen |

## Tasks Scheduler (estado real em 27/07 01:20 BRT)

| Task | Estado | Ultima execucao | Resultado | Situacao |
|---|---|---|---|---|
| VIXRadar-Noturno | Ready | 26/07 18:00 | 0x0 (ok) | Rodando diariamente |
| VIXRadar-Matinal | Ready | 30.nov.1999 (nunca) | 0x41303 | Recriada em 24/07. Primeiro disparo novo previsto 27/07 10:00 |
| VIXRadar-AgendaSemanal | Ready | 30.nov.1999 (nunca) | 0x41303 | Nunca executou |
| VIXRadar-Verificacao-Async | N/A (inline) | 26/07 18:53 | exit 0 | Executa inline pos-noturno e pos-matinal. Nao e mais task separada |
| VIXRadar-Coleta-Volatilidade | REMOVIDA | 23/07 17:02 | ultimo log ok | Task nao existe mais no Scheduler. Parada ha 4 dias |
| VIXRadar-Export-Historico | REMOVIDA | 22/07 20:47 | ultimo log ok | Task nao existe mais no Scheduler. Parada ha 5 dias |
| VIXRadar-Reconciliacao-CVM | REMOVIDA | 21/07 12:31 | ultimo exit 1 | Task nao existe mais no Scheduler. Parada ha 6 dias |
| VIXRadar-Ranking-Mensal | REMOVIDA | Nunca | N/A | Task nao existe mais no Scheduler |
| Monitor-Tasks | REMOVIDA | 23/07 07:00 | 8 erros, 9 OK | Task nao existe mais no Scheduler. Vigia de falha silenciosa desativada |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok (health 27/07: kv:true) |
| RATE_LIMITER_DO | ok (health 27/07: rate_limiter:true) |
| RADAR_USAGE_EVENTS | ok (health 27/07: telemetria:true) |
| ESTADO_SEMANA_DO | declarado no `wrangler.toml` + usado no bundle (nao exposto no health publico) |
| Providers | 2/2 (Resend + Anthropic); probes OpenRouter removidos do health (OPENROUTERVIVO) |

## Pendencias ativas (topo)

Ver [[PENDENCIAS.md]]. **Fila aberta: 10 itens acionaveis** (3 P1, 5 P2, 2 P3), mais 1 P4 ja executado. Atualizado 27/07 01h35, apos revisao do diagnostico de rotinas (entraram: registrador da Monitor-Tasks, guard no `register-all-routines-scheduler.ps1`, consolidacao dos dois `PENDENCIAS.md`).

## Checklist pos-rotina

Apos cada noturna (ou evento de producao significativo), verificar:

- [x] `03 - Estado Atual.md` — atualizado 27/07 (diagnostico de rotinas)
- [ ] `03a - Changelog.md` — atualizar com noturnos 25 e 26/07
- [ ] `03b - Infraestrutura.md` — so se mudou binding/cron (sem mudanca de binding)
- [x] `00 - Indice (MOC).md` — pendente atualizar com dados deste diagnostico
- [x] `CLAUDE.md` — tabela Producao em v4.9.181 / v201.88 (sem alteracao)
- [x] `PENDENCIAS.md` — recriado 27/07 e revisado no mesmo dia: 10 itens acionaveis abertos

Script de drift: `pwsh ./scripts/check-vault-drift.ps1` compara vault contra health ao vivo e reporta divergencias. Execute apos cada deploy ou se suspeitar de desalinhamento.

---

## Diagnostico 27/07 (01:20 BRT)

Executado em modo somente leitura conforme procedimento de auditoria. Health check ao vivo colado abaixo.

### Metodo

- `Get-ScheduledTask` + `Get-ScheduledTaskInfo` para todas as tasks com prefixo VIXRadar- e Monitor-
- Leitura de todos os logs em `logs\routines\` e `logs\monitor-tasks\` dos ultimos 4 dias
- Health check do Worker com `curl.exe`
- Comparacao com o estado declarado neste vault

### Evidencias

**Tasks existentes (3):**
```
VIXRadar-AgendaSemanal  Ready  LastRun 30.nov.1999  NextRun 27.jul.2026 03:00  0x41303
VIXRadar-Matinal        Ready  LastRun 30.nov.1999  NextRun 27.jul.2026 10:00  0x41303
VIXRadar-Noturno        Ready  LastRun 26.jul 18:00  NextRun 27.jul.2026 18:00  0x0
```

**Tasks removidas (0 tasks encontradas no Scheduler):** Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM, Ranking-Mensal, Monitor-Tasks.

**Health Worker (27/07 01:20 BRT):**
```
{"ok":true,"versao":"v4.9.181","ts":"2026-07-27T04:20:02.165Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
HTTP:200 TEMPO:0.763480s
```

**Logs ausentes:** matinal 24/07 e 25/07 (25/07 sabado, ok; 24/07 sexta-feira, era para ter rodado). Monitor-tasks parado desde 23/07.

---

*Snapshot gerado em 2026-07-27 ~01h20 BRT (diagnostico de rotinas + health ao vivo 0.763s). Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
