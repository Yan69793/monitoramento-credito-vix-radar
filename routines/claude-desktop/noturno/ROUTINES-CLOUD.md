# VIX Radar — noturno cloud (Remote Routine)

> **ORFAO/ESPECULATIVO (2026-08-18, FASE 2 de governanca das rotinas).** Este documento
> descreve uma Claude Code Routine remota que **nunca foi criada**. `RemoteTrigger list`
> confirmado em 18/08 mostra so 2 Remote Routines VIX reais em producao: a de verificacao
> assincrona (`trig_01QeqBF3sSjuqUYE51a58RtA`) e a de frescor diario
> (`trig_01B4dbLeSg8NpnMLjkBUXs1N`, ver `routines/README.md`). Nenhuma remote de noturno
> existe. O texto abaixo tambem instrui usar `ROUTINE_API_KEY` (a chave de privilegio total)
> num ambiente remoto hipotetico — se esta rotina virar real algum dia, ela precisa de
> credencial dedicada e escopo minimo, mesmo padrao que `REMOTE_VERIFICACAO_KEY` ja estabeleceu
> para a verificacao (CHAVEESCOPO1, 18/08/2026), nao reusar a chave de privilegio total.
> Mecanismo real desde 02/09/2026 (MOTOR1): o motor e o Task Scheduler nativo,
> `VIXRadar-Noturno` -> `scripts\run_vixradar_noturno_claude.ps1` -> `run_vixradar_varredura.ps1`,
> na assinatura Claude Code Pro. A sessao agendada do Claude Desktop (`vixradar-noturno`,
> cron `0 18 * * *`) foi aposentada em 12/09/2026 e as 4 sessoes VIX do CCD estao
> `enabled: false`; os SKILL.md delas agora recusam execucao.
> Mantido sem apagar, pode virar plano real no futuro.

Execução autônoma em nuvem. **PROIBIDO Task/subagentes paralelos. PROIBIDO 1 agente por emissor.**

## Config

```
WORKER_URL = https://api.vixradar.com
ROUTINE_KEY = (definir via $env:ROUTINE_API_KEY — chave removida do disco 2026-07-24)
```

Core tiers: `scheduled-tasks/_shared/rotina-v2-core.md` (se no repo) ou `scripts/noturno-batch-sonnet.md` / `noturno-batch-haiku.md`.

## Passo 1 — Plano (1 call)

```bash
curl -s -X POST https://api.vixradar.com \
  -H "Content-Type: application/json" \
  -d '{"action":"listar_plano_rotina","routine_key":"<definido via $env:ROUTINE_API_KEY>","modo":"noturno"}'
```

Confirme `total=103`. Anote tiers e `buscas_estimadas`.

## Passo 2 — SKIP via curl (0 buscas LLM)

Todos `tier=SKIP`: payload mínimo + `receber_analise` `_matinal:false`, `provedor:"claude-sonnet-routine"`. Pausa 2s.

## Passo 3 — Análise sequencial (tier ≠ SKIP)

**Uma sessão, emissores em série.** Nunca spawn Task/subagent.

Ordem de prioridade:
1. FULL com EWS≥38 ou `cvm_novos>0` (mais buscas: até 5)
2. Demais LIGHT/AUDIT/FULL (LIGHT max 3 buscas)

Por emissor:
1. CVM do plano — não R1 web, não `dados_para_analise`.
2. Buscas só em `rodadas[]`.
3. Submit `receber_analise` `_matinal:false`, `provedor:"claude-sonnet-routine"`.
4. Linha: `OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok`

**Orçamento tokens ~500k** (hard mental 700k): após ~35 emissores analisados ou sinais de limite, restante → ledger deferred (`sem_eventos:true`, `_token_cap_deferred:true`).

PROIBIDO: gravar `testing/`, `.noturno_*`, JSON local. Submit só curl Worker.

## Passo 4 — Sumário

```
NOTURNO_RESUMO|processados|ok|fail|skip|deferred|buscas|criticos|economia_pct
```