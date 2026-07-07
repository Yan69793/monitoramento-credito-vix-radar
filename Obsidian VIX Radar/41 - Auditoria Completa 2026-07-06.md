# Auditoria Completa — VIX Radar (2026-07-06)

Skill: `/vix-radar-audit`. Contexto: pós-rotina noturna 18h, disparada por incidente de execução concorrente detectado nesta sessão.

## Síntese executiva

Sistema **saudável**. Worker v4.9.146 e Frontend v201.69 sem drift repo/produção. Cobertura dos 103 emissores validada (`stale_24h:0`, `max_stale:1.5h`, conteúdo real). Incidente do dia — noturno rodou **duplicado** e a 2ª instância submeteu cobertura mínima — **corrigido nesta sessão** (mutex + stderr por-PID + deduplicação de agendador). O run canônico (18:00) entregou análise real dos 103.

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker | `wrangler.toml main="v4.9.146.js"` | `GET /` `versao:"v4.9.146"` | Não |
| Frontend | `version.json v201.69` | `vixradar.com/version.json v201.69` | Não |

## Incidente do dia — execução concorrente da noturna (RESOLVIDO)

**[Fato]** A rotina noturna disparou **duas vezes** em 2026-07-06:
- Task Scheduler nativo `VIXRadar-Noturno` (cron diário 18:00), PID 20620 às 18:00:01 — instância **canônica**, análise real.
- Scheduled-task Claude Code `vixradar-noturno` (cron `0 18 * * *` + jitter 324s), ~18:06 — **duplicata**.

**[Causa raiz]** `run_vixradar_noturno_claude.ps1:189` redirecionava stderr do `claude -p` para arquivo **date-tagged compartilhado** (`noturno_stderr_<data>.txt`). Duas instâncias no mesmo dia → mesma path. A canônica (18:00) reteve o handle; a duplicata (18:06) tomou *sharing violation* (`The process cannot access the file ... being used by another process`) em **todo** lote → exceção terminante → 37 submits de cobertura mínima (`NENHUM`, 0 buscas, 0 tokens).

**[Evidência]** `logs/routines/noturno_metrics_20260706.json`: `tokens_total_est:0`, `buscas_total:0`, `submit_ok:37` (stubs), `duracao_sec:196`. Log da duplicata: 37× `WARN: <empresa>|sem RESULTADO apos retry - submit minimo de cobertura pendente`.

**[Correção aplicada]** em `scripts/run_vixradar_noturno_claude.ps1`:
1. **stderr por-PID** — `noturno_stderr_<data>_<PID>.txt` (isola handle por processo).
2. **Mutex global** `Global\vixradar-noturno-v2` via `WaitOne(0)` não-bloqueante — 2ª instância sai limpa (`return`) em 0 tokens. Validado cross-process (Start-Job: A adquire=True, B=False).
3. **Deduplicação** — scheduled-task Claude Code `vixradar-noturno` **desabilitada** (`update_scheduled_task enabled=false`); gatilho oficial passa a ser exclusivamente a Task nativa 18:00 (decisão do operador).
4. Sintaxe validada via `ParseFile` (parse OK, chaves balanceadas).

**[Validação de cobertura]** `audit-routine-staleness.ps1`: `total:103`, `stale_24h:0`, `presos_data:0`, `max_stale:1.5h`, última análise `2026-07-06T21:10-21:11Z` (18:10-18:11 BRT, posterior ao fim da duplicata às 18:09) com conteúdo real (ex.: PRIO com detalhamento S&P/Moody's/produção). Os 37 stubs foram sobrescritos pela análise real da instância canônica (last-write-wins na semana corrente).

## Achados

### BAIXO
- **Encoding no script de auditoria** — `audit-routine-staleness.ps1` não força `[Console]::OutputEncoding=UTF8` (ao contrário dos 3 scripts de rotina, corrigidos em 05/07); nomes acentuados vêm com `�` no output (`produ��o`, `est�vel`). Artefato de display do próprio auditor, **não** corrupção em produção. Recomendação: aplicar o mesmo cabeçalho UTF-8 do script de rotina.
- **Doc drift** — `03 - Estado de Produção.md` tabela de versões (linha 47) ainda registrava Worker v4.9.145; produção = v4.9.146. Corrigido nesta sessão.

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` | HTTP 200, 1.07s | `ok:true, versao:v4.9.146, kv:true, rate_limiter:true, telemetria:true, verificador_ok:true, providers 2/2` |
| POST anônimo | HTTP 401 | fail-closed OK |
| Staleness 103 | saudável | `total:103, stale_24h:0, presos_data:0, max_stale:1.5h` |
| Bindings wrangler | OK | `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS` + `[observability]` presentes |
| Verif. assíncrona | disparou 18:27 BRT | `list_scheduled_tasks` `lastRunAt 2026-07-06T21:27` (confirma 2º horário 18:20) |

## Lacunas

- Não testei `receber_analise` smoke nem `admin_health_check` autenticado (readonly; sem necessidade — cobertura já provada pelo gate dos 103).
- Não inspecionei o bundle `v4.9.146.js` linha a linha (fica para a auditoria geral — nota 42).

## Próximos passos

- P2: aplicar cabeçalho UTF-8 em `audit-routine-staleness.ps1`.
- P3: monitorar próxima noturna (07/07 18:00) para confirmar que só a Task nativa dispara e o mutex nunca é acionado por duplicata.
