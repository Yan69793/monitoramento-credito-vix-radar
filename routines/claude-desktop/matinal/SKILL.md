# ROTINA MATINAL DO VIX RADAR — SESSÃO SUPERSEDIDA. NÃO EXECUTAR.

**Status:** aposentada em 2026-09-12. Esta sessão agendada do Claude Desktop **não é mais o motor** da rotina matinal. Se você foi acionado por esta skill, **pare aqui e não execute nada**.

## Duas proibições, sem exceção

1. **NÃO desligue nenhuma task do Task Scheduler.** O Passo 0 que existia aqui rodava `Disable-ScheduledTask` em `VIXRadar-Matinal` e é exatamente o incidente que o monitor chama de guard quebrado. Aquela task é o motor agora. Desligar ela mata a rotina do dia.
2. **NÃO rode varredura nenhuma a partir desta sessão.** Nem `curl` no Worker para montar plano, nem análise com WebSearch, nem `receber_analise`. A análise e o submit são do motor.

## Quem é o motor hoje

O motor é o **Task Scheduler nativo**, com o estado em `logs\monitor-tasks\motor.json` (`motor: task-scheduler`):

| Rotina | Task | Wrapper |
|---|---|---|
| Matinal | `VIXRadar-Matinal` (diária 10:06) | `scripts\run_vixradar_matinal_claude.ps1` |
| Noturna | `VIXRadar-Noturno` (seg-sex 18:05) | `scripts\run_vixradar_noturno_claude.ps1` |

Os dois wrappers chamam o motor único, `scripts\run_vixradar_varredura.ps1`, que cobre 104 emissores, monta os lotes, faz o submit e escreve o ledger `logs\routines\vixradar-matinal_<data>.log`.

O provider de LLM é a assinatura Claude Code Pro (`VIXRADAR_LLM_PROVIDER=claude-subscription`). A afirmação antiga desta skill, de que o `claude` CLI standalone estava quebrado e por isso o wrapper não podia ser chamado, **deixou de ser verdade** em 12/09/2026: o que estava quebrado era a escalada paga, já corrigida.

## Limite de cota, que é o que importa na matinal

A matinal roda na assinatura, e a assinatura tem limite de sessão que a noturna e o seu uso manual também consomem. Quando o limite estoura, o motor aborta com o motivo nomeado no log (`LIMITE DE SESSAO da assinatura`), sem cair para chave paga. Regenerar token **não** resolve limite de cota, só o reset resolve.

A `Szuchmacher-RetryVixMatinal` continua **desligada** por decisão do operador: não há relançamento automático para a matinal. Se ela morrer por cota, o dia fica sem painel novo até a próxima execução.

## Por que esta skill foi aposentada

A implementação paralela que vivia aqui (orquestrador + análise com WebSearch) é uma segunda versão da rotina, sem idempotência por janela, sem lock do motor e sem cobertura por contrato. O motor tem as três.

O conteúdo original desta skill (18998 bytes, sha256 `2a9d3752ddbd25242ab7de8d1aac7c89d9e9b0ff136b976c36ea21860c984e92`) está preservado em:

`C:\Users\User\.claude\scheduled-tasks\backups\20260912-2032\vixradar-matinal-SKILL.md`

Se algum dia a decisão for voltar a rodar a rotina dentro do Claude Desktop, isso é decisão explícita do operador e exige desenhar a guarda anti-duplicata contra o motor primeiro.
