---
name: vixradar-varredura
description: >
  Executa e valida varreduras matinais/noturnas do VIX Radar com seguranca (motor
  run_vixradar_varredura.ps1): pre-flight de tasks/locks/mutex/heartbeats/logs,
  proibicao de concorrencia, lock valido x orfao, provider automatico
  OpenRouter/DeepSeek, plano (dedup, deferred_prioritario, backlog), cobertura
  temporal (Total do dia N/M), validacao da linha FIM (analisados, submit_fail,
  lotes_falha_provider) e health final (painel_fresco/feed_fresco). Use ao rodar ou
  auditar a varredura do dia ou investigar FIM suspeito. Nao usar para repor dias
  perdidos (/repor-varredura) nem auditoria completa (/vix-radar-audit).
date: 2026-09-08
disable-model-invocation: true
---

# Varredura matinal/noturno — executar e validar com segurança

## Regras de contenção (valem sempre)

1. **Nunca deployar, commitar ou alterar código durante uma varredura.** A varredura grava
   produção (receber_analise → estado); mudar código no meio invalida a leitura do log.
2. **Ler somente o necessário:** log do dia em `logs/routines/`, metrics JSON do dia, estado
   das tasks + provider, GET / de health. Não varrer o vault Obsidian nem o repo.
3. **Parar assim que houver evidência suficiente.** `FIM:` + `ROTINA_RESUMO` + health
   respondem "rodou? entregou? fresco?" — não cavar mais.

## O que é

- `vixradar-matinal`: diária ~10h06 BRT, topo (`top_n=20`, FULL) · `vixradar-noturno`: seg-sex
  ~18h05 BRT, cauda (`noturno`, LIGHT). Logs: `logs/routines/vixradar-{matinal,
  noturno}_{YYYYMMDD}.log`.
- Motor único `scripts/run_vixradar_varredura.ps1 -Rotina matinal|noturno` (wrappers
  `run_vixradar_matinal_claude.ps1`/`run_vixradar_noturno_claude.ps1` no Task Scheduler).
  Declarativo: `scripts/cutover-motor.ps1` + `logs/monitor-tasks/motor.json`; divergência viva
  = registrar, não corrigir durante varredura.

## Pre-flight (antes de rodar ou julgar um log)

- **Provider** (`scripts/lib/vixradar-llm-provider.ps1`, env User `VIXRADAR_LLM_PROVIDER`):
  ausente/`none` → `BLOQUEADO_SEM_PROVIDER` + **exit 86** antes de mutex/lock/sonda — não
  rodou, não gastou; esperado quando bloqueado. `openrouter` = **automático e ativo**
  (`AUTH_MODO: openrouter` no log; modelo efetivo DeepSeek — fix 08/09:
  `deepseek/deepseek-v4-flash-0731`). `claude-manual` = só com `-ForceClaude`; `deepseek` =
  reservado. Sem `AUTH_MODO: openrouter` em varredura agendada, suspeitar regressão.
- **Tasks:** `Get-ScheduledTask`/`Get-ScheduledTaskInfo` em `VIXRadar-Matinal`,
  `VIXRadar-Noturno` (Enabled, LastRunTime, LastTaskResult). `monitor-tasks.ps1` vigia:
  exit 86 é esperado; ≠ 86 em rotina bloqueada gera 9006. Heartbeats são vigiados pelo
  watchdog do Worker (staleness ~26h) — sinal local mais direto é o FIM.
- **Feriado B3:** `SKIP: feriado B3. FIM: ... Total 0/0.` = **sucesso legítimo**.

## Concorrência — nunca duas varreduras iguais ao mesmo tempo

- **Mutex global por rotina:** `Global\vixradar-matinal-v2` / `Global\vixradar-noturno-v2`.
  Segunda instância loga `ABORT: outra instancia ... (mutex ocupado)` e sai limpo em 0 tokens
  (exit 0) — a trava funcionando, não falha.
- Matinal e noturno têm mutex separados (coexistem); a sentinela tem o próprio
  (`Global\vixradar-sentinela-v1`) — a varredura espera até 25 min por ela antes do plano.

## Lock de arquivo — válido x órfão

`logs/routines/vixradar-{rotina}_{YYYYMMDD}.lock`: escrito **antes** da 1ª chamada ao Worker,
**tocado a cada lote**, removido no fim. Régua de 30 min (`$LockAbandonoMin`):

- **Válido/vivo:** `LastWriteTime` < 30 min → outra execução rodando; quem chega loga
  `ABORT: lock ... (outra execucao viva)`.
- **Órfão:** ≥ 30 min sem toque → execução anterior morreu (crash); o motor loga
  `LOCK_ABANDONADO: ... assumindo` e assume (04/09: 78,2 min → 104/104).
- Nunca apagar lock à mão sem conferir mutex/processo (lock vivo + remoção = duas varreduras).

## Ler o log — o que é o que

Linhas-chave: `LOCK_OK`/`INICIO`, `AUTH_MODO`/`MODELO_EFETIVO`, `CAP_EFETIVO`/`CUSTO_DIA`,
`Plano {SKIP,LIGHT,FULL,AUDIT} total=N`, `ALVO <empresa> ... motivo=<ews_alto|
prioritario_padrao|deferred_prioritario>`, ledger `OK|empresa|tier|classif|n_ev|submit_ok|
status|avanco_data` (`DRYRUN|` prefix), `LOTE_FECHADO`, `DEFERIDOS ... motivo=`, `FIM:`,
`ROTINA_RESUMO|`, `POS-...: drenando fila...`, `Cleanup`.

Ledger (regra FEEDRETRO1): `ANALISADO` = entregou; `SKIP`/`DEFERIDO` mandam 0 (não analisam).
`submit_ok` conta **evento persistido** (`n_eventos>=1`), não POST aceito — o Worker devolve
`ok:true` mesmo descartando a fonte (`DESCARTADO` sem somar).

## Dedup, deferred_prioritario e backlog

- **dedup:** re-submissão do mesmo fato não duplica. FIM expõe `chaves_novas` (fato novo),
  `descartados` (fonte rejeitada por validarDatasFontes), `eventos_avanco_data`.
  `eventos_avanco_data=0` em dia quieto é **legítimo** (FEEDRETRO1 FASE2): mede avanço
  temporal, nunca prova ausência.
- **`deferred_prioritario`:** emissor que ficou `DEFERIDO` (cap/excedente) volta no plano
  seguinte com esse motivo — retomada planejada, não erro.
- **DEFERIDO ≠ entrega e ≠ falha:** não conta para idempotência nem dispara retry; `SKIP`
  conta como processado. Retry é só para falha real de execução/entrega, nunca cap planejado.
- **backlog:** varredura que não dá conta do plano (cap dinâmico) deixa excedente no Worker
  (`excedente_worker`); o plano seguinte preserva (`backlog=True`).

## Cobertura temporal — `Total do dia N/M`

`N` = emissores com linha no ledger, `M` = total do plano. Medidos: matinal 23/23, noturno
104/104. Dia útil **sem** FIM = gap → `/repor-varredura`, nunca re-executar às cegas.
`N<M` com resto não-DEFERIDO = investigar (lote falhou? ABORT?).

## Validar a linha FIM

`FIM:` traz `Total do dia N/M` + contadores do ledger/metrics (`analisados`, `skip`,
`deferidos`, `submits_aceitos`, `submit_ok`, `submit_fail`, `lotes`, `buscas`,
`silent_fail`, `criticos`, `auth_escalou`, `eventos_avanco_data`, `chaves_novas`,
`descartados`, `duracao_sec`).
- **Esperado:** `submit_fail=0`, `silent_fail=0`, `auth_escalou=nenhum`,
  `ROTINA_RESUMO|...|OK|` (vira `PARCIAL` se silent_fail+skip_fail+batch_fail+submit_fail+
  deferred_fail > 0).
- `criticos>0` é normal (CRITICO entra na fila de verificação; o POS- da rotina drena).
  `deferidos>0` com `motivo=cap_efetivo` é planejado.
- **`lotes_falha_provider`:** rotina que expõe o campo (sentinela FIM: `lotes_ok=..,
  lotes_falha_provider=0`); 0 = esperado. No motor, lote falho **por provider** (429/upstream)
  é falha real — com o fix de 08/09, 0 lotes por falha de provider sai com **exit 9** (antes,
  exit 0 falso mascarava o 429). ≠ DEFERIDO por cap (falha = retry; cap = planejado).
- Dry-run: `FIM_DRYRUN:` + `DRYRUN|` no ledger — nunca conta como entrega do dia.

## Health final — painel_fresco / feed_fresco

Portão: `curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code}"`
→ HTTP 200, `ok:true`, `telemetria:true`, `kv:true` (ver `checks.estado_semanal`,
`checks.painel_fresco`, `checks.evento_mais_novo`/`feed_fresco`). Cole a saída real.

- **`painel_fresco`** = SLA de **escrita** da rotina (`estado_semanal.updated_at` vs agenda
  real: matinal diária, noturno seg-sex). Fora do `ok` agregado (HEALTHSPLIT1/PAINELFRESCOR1):
  pontualidade, não o serviço. Exibe `idade_min`, `fresco`, `regra`.
- **`feed_fresco`** = idade do **evento** mais novo em dias úteis (EVENTOFRESCOR1/FEEDRETRO1);
  só anda com persistência de evento novo, nunca por re-narrar fato antigo.
- Juntos: `painel_fresco:true` + `feed_fresco:true` = estado novo **e** fato novo; painel
  fresco + feed preso em data antiga = re-ancoragem (FEEDRETRO1) → `/repor-varredura`.

## Saídas e encerramento

Varredura real (não dry-run) com `submit_ok>0` drena a fila de verificação
(`POS-...: dreno concluido`) e roda `Cleanup`. Exit codes: 0 = concluído (inclui ABORT por
mutex/lock e SKIP de feriado), 86 = bloqueado sem provider, 1 = erro fatal de setup,
9 = 0 lotes por falha de provider (fix 08/09). Estado mudado → atualizar `status/ESTADO.md`.
