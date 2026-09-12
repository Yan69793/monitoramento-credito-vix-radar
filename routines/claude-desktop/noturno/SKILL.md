# ROTINA NOTURNA DO VIX RADAR — SESSÃO SUPERSEDIDA. NÃO EXECUTAR.

**Status:** aposentada em 2026-09-12. Esta sessão agendada do Claude Desktop **não é mais o motor** da rotina noturna. Se você foi acionado por esta skill, **pare aqui e não execute nada**.

## Duas proibições, sem exceção

1. **NÃO desligue nenhuma task do Task Scheduler.** O Passo 0 que existia aqui rodava `Disable-ScheduledTask` em `VIXRadar-Noturno` e é exatamente o incidente que o monitor chama de guard quebrado. Aquela task é o motor agora. Desligar ela mata a rotina do dia.
2. **NÃO rode varredura nenhuma a partir desta sessão.** Nem `curl` no Worker para montar plano, nem subagente de análise, nem `receber_analise`. A análise e o submit são do motor.

## Quem é o motor hoje

O motor é o **Task Scheduler nativo**, com o estado em `logs\monitor-tasks\motor.json` (`motor: task-scheduler`):

| Rotina | Task | Wrapper |
|---|---|---|
| Noturna | `VIXRadar-Noturno` (seg-sex 18:05) | `scripts\run_vixradar_noturno_claude.ps1` |
| Matinal | `VIXRadar-Matinal` (diária 10:06) | `scripts\run_vixradar_matinal_claude.ps1` |

Os dois wrappers chamam o motor único, `scripts\run_vixradar_varredura.ps1`, que cobre 104 emissores, monta os lotes, faz o submit e escreve o ledger `logs\routines\vixradar-noturno_<data>.log`.

O provider de LLM é a assinatura Claude Code Pro (`VIXRADAR_LLM_PROVIDER=claude-subscription`). A afirmação antiga desta skill, de que o `claude` CLI standalone estava quebrado e por isso o wrapper não podia ser chamado, **deixou de ser verdade** em 12/09/2026: o que estava quebrado era a escalada paga, já corrigida.

## Se o que você quer é recuperar uma noite perdida

Não é por aqui. O caminho é a task `Szuchmacher-RetryVixNoturno` (gatilhos 21:30 e 23:20), que relança o motor e julga a entrega pelo ledger. Ela sai no-op quando o ledger já confirma entrega.

## Por que esta skill foi aposentada

A implementação paralela que vivia aqui (orquestrador + subagentes com WebSearch) já corrompeu o feed: em 08/08/2026 uma segunda execução leu fonte mais velha e sobrescreveu 3 emissores (Rumo, Bradesco, Tupy). O motor tem idempotência por janela, lock, mutex e cobertura por contrato, que esta skill não tinha.

O conteúdo original desta skill (39140 bytes, sha256 `6a5b56edad7847c8ffaba8064e52e5c0c0ec500a2061743b14fec1511ed6ef6b`) está preservado em:

`C:\Users\User\.claude\scheduled-tasks\backups\20260912-2032\vixradar-noturno-SKILL.md`

Se algum dia a decisão for voltar a rodar a rotina dentro do Claude Desktop, isso é decisão explícita do operador e exige desenhar a guarda anti-duplicata contra o motor primeiro.
