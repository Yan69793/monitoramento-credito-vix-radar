---
data: 2026-07-20
tipo: recovery
tags: [vix-radar, recovery, deploy, ingest-gap1, incidente]
status: resolvido
---
# Recovery e Deploy — VIX Radar (2026-07-20)

Sessão de recovery após INGEST-GAP1 detectado na [[62 - Auditoria Completa e Correcoes 2026-07-20]]. Operador presente e aprovando ações em tempo real.

## Linha do tempo do incidente

```
00:25  Máquina desligada (shutdown, não suspensa)
10:00  Trigger Matinal — PERDIDO (máquina off)
12:24  Cold boot (BootType=0x0, normal boot)
12:32  Task Scheduler dispara tarefas perdidas em lote
       VIXRadar-AgendaSemanal → OK (LastResult=0)
       VIXRadar-Verificacao-Async → OK (LastResult=0)
       VIXRadar-Matinal → FALHOU (0x800710E0, sessão interativa não pronta)
14:28  Recovery manual inicia: Start-ScheduledTask VIXRadar-Noturno
15:33  Noturno concluído: 103/103 ok, 9 críticos, 535k tokens
15:34  Matinal disparada (1a tentativa)
15:39  Matinal interrompida pelo register (Unregister-ScheduledTask matou o processo)
15:34  Matinal re-disparada (2a tentativa)
15:46  Matinal concluída: 13/13 ok, 7 críticos, 132k tokens
15:46  Sistema 100% recuperado
```

## Causa raiz

Máquina foi **desligada** (não suspensa) às 00:25. Cold boot às 12:24. Task Scheduler detectou triggers perdidos e disparou em lote às 12:32.

**VIXRadar-Matinal** falhou com `0x800710E0` ("O operador ou administrador recusou o pedido") porque:
- `StartWhenAvailable=false` → Scheduler fez tentativa única, sem retry
- `LogonType=InteractiveToken` → sessão interativa não estava 100% estabelecida 8 min após cold boot

Tasks irmãs que **funcionaram** no mesmo segundo (AgendaSemanal, Verificacao-Async) tinham `StartWhenAvailable=true`.

## Recovery executado

### Noturno (catch-up completo)
- **Plano:** 80 LIGHT + 23 FULL, 0 SKIP
- **Filas:** 94 haiku + 9 sonnet
- **Resultado:** 103/103 submit_ok, 0 fail, 535k tokens
- **Duração:** ~65 min (14:28 a 15:33)
- **Críticos (9):** Taesa, Oncoclínicas, Oi, Kora Saúde, Raízen, Cosan, mais 4

### Matinal (re-scan focado)
- **Plano:** 5 SKIP + 5 LIGHT + 8 FULL
- **Filas:** 6 haiku + 7 sonnet
- **Resultado:** 13/13 submit_ok, 0 fail, 132k tokens
- **Duração:** ~12 min (15:34 a 15:46)
- **Críticos (7):** Oncoclínicas (REX R$ 5,1 bi), Oi (RJ, venda UPI R$ 60 mi, inadimplência CVM), Kora Saúde (RE, AGD 21/07), Raízen (reestruturação R$ 65 bi, penny stock), Cosan (2 eventos)

### Interrupção da 1a Matinal
O `register-vixradar-tasks.ps1` executado pelo operador às ~15:40 removeu a task (`Unregister-ScheduledTask`) enquanto a Matinal rodava, matando o processo no meio do batch sonnet-2. A 2a execução completou normalmente.

## Deploy v4.9.167

| Fix | Descrição |
|---|---|
| F002 | 7 `catch{}` vazios → `console.error`. 2 no health check (`_verificadorRealOk`, `_filaVerifAtrasada`) — os mais críticos |
| F014 | `handleResendWebhook`: cap 1MB (Content-Length + pós-leitura), 413 se exceder |

**Versão no bundle corrigida** (estava `"v4.9.166"` hardcoded, deploy inicial reportava versão errada mesmo com código novo). Redeploy com `WORKER_VERSAO = "v4.9.167"` confirmado em produção. Commit `1842499` pushado.

## Fix estrutural — register-vixradar-tasks.ps1

Script já estava corrigido no repo (commit `c39e894`), faltava reexecutar como Admin. Operador executou manualmente:

```
VIXRadar-Matinal: StartWhenAvailable=true, DisallowBatteries=false, StopBatteries=false, RunLevel=HighestAvailable
VIXRadar-Noturno: StartWhenAvailable=true, DisallowBatteries=false, StopBatteries=false, RunLevel=HighestAvailable
```

**Efeito:** se a máquina estiver desligada no horário do trigger, o Scheduler executa a task assim que possível após o boot. A sessão interativa ainda é requisito (Claude Code), mas o retry automático elimina gaps multi-dia.

**Risco residual:** cold boot + início de sessão interativa pode levar >8 min. Se o Scheduler tentar antes da sessão estar pronta, volta a falhar com `0x800710E0`. Mitigação futura: adicionar trigger `AtStartup` com delay de 10 min.

## Estado final

| Componente | Estado |
|---|---|
| Worker | v4.9.167 (F002 + F014) |
| Frontend | v201.80 |
| Emissores | 103/103 atualizados, 0 stale |
| Tasks | StartWhenAvailable=true, sem bloqueio bateria |
| Health | ok:true, kv/telemetria/verificador ok |
| Git | Sincronizado, sem drift |

## Críticos ativos para acompanhar

| Emissor | Evento | Data-chave |
|---|---|---|
| Oncoclínicas | REX R$ 5,1 bi, 37% adesão, meta 50%+1 em 90 dias | AGD pendente |
| Kora Saúde | RE R$ 1,3 bi, vencimento antecipado suspenso | AGD 21/07/2026 |
| Raízen | Reestruturação R$ 65 bi, penny stock, B3 prazo mar/2027 | Negociações em curso |
| Oi | RJ, venda UPI R$ 60 mi, inadimplência CVM | Aprovação CADE/Anatel |
| Cosan | 2 eventos críticos | — |
