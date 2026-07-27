---
data: 2026-07-27
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## Abertas (27/07)

### P2 - Verificar se AgendaSemanal e Matinal se repetem sem erro apos falha da AgendaSemanal 27/07 03:00

**Origem:** Validacao pos-registro da Monitor-Tasks, 27/07 07:04.
**Descricao:** Primeiro disparo real da AgendaSemanal desde a recriacao (27/07 03:00) terminou com exit=1. Log `logs\routines\vixradar-agenda-semanal_20260727.log` so tem a linha INICIO, sem detalhe do erro, o processo morreu sem escrever mais nada. `monitor-tasks.ps1` classifica esse par exit=1 mais nome VIXRadar-AgendaSemanal como "Credit balance too low" por um padrao ja codificado no script de incidente anterior, isso e inferencia por historico, nao confirmacao do log de hoje. Probe `claude -p "pong" --model claude-haiku-4-5-20251001` as 07:04 respondeu normal, entao nao ha bloqueio de credito acontecendo agora. Fica em aberto se foi um blip transitorio ou se o mesmo vai acontecer na Matinal (10:00) ou na Noturno (18:00), que tambem dependem de `claude -p`.
**Acao:** Apos 10:00, conferir `logs\routines\vixradar-matinal_20260727.log` e o exit code da task Matinal. Se falhar com o mesmo padrao, investigar saldo/quota da assinatura Claude Code usada nas rotinas antes da Noturno das 18:00.
**Validacao:** Matinal com exit 0 e submit_ok correspondente, ou causa raiz do exit=1 identificada e diferente de quota.

### P1 — Recriar task VIXRadar-Reconciliacao-CVM no Scheduler

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** A task foi removida. Ultimo log 21/07 com exit code 1 (falha). Sem reconciliacao, dados do sistema podem divergir dos protocolos CVM oficiais sem deteccao.
**Acao:** Recriar task + investigar e corrigir o exit code 1 que ja existia antes da remocao.
**Validacao:** Log `logs\routines\vixradar-reconciliacao-cvm_*.log` com exit 0.

### P2 — Recriar task VIXRadar-Coleta-Volatilidade no Scheduler

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task removida. Ultimo log 23/07 com 281 bytes (provavelmente ok). Scores de volatilidade no dashboard podem estar desatualizados apos 4 dias sem coleta.
**Acao:** Recriar task diaria ~17:00.
**Validacao:** Log `logs\routines\coleta_volatilidade_*.log` gerado no dia seguinte.

### P2 — Recriar task VIXRadar-Export-Historico no Scheduler

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task removida. Ultimo log 22/07 (ok). Backups diarios de dados parados ha 5 dias.
**Acao:** Recriar task diaria 20:45.
**Validacao:** Log `logs\routines\vixradar-export_*.log` gerado no dia seguinte.

### P2 - Verificar primeiro disparo da Matinal (27/07 10:00)

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task VIXRadar-Matinal foi recriada em 24/07 as 10:00 (StartBoundary do trigger). Nunca disparou desde a recriacao (confirmado ainda em 1999.11.30/0x41303 no log da Monitor-Tasks das 07:00 de hoje). Primeiro disparo previsto para hoje 27/07 as 10:00. Se nao disparar, a cobertura matinal (top 15 por EWS) permanece parada desde 23/07.
**Acao:** Apos as 10:00, conferir se `logs\routines\vixradar-matinal_20260727.log` foi gerado.
**Validacao:** Log presente, com submit_ok e metrics correspondentes, e `Get-ScheduledTaskInfo` com LastTaskResult 0.

### P2 - Guard em register-all-routines-scheduler.ps1, o nome engana e o script derruba o disparo do dia

**Origem:** Revisao do diagnostico 27/07.
**Descricao:** Apesar do nome "all routines", o script declara apenas 6 tasks: VIXRadar-AgendaSemanal, VIXRadar-Matinal, VIXRadar-Noturno e as 3 Szuchmacher. Nao cobre Monitor-Tasks, Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM nem Ranking-Mensal, que sao justamente as 5 removidas. Quem rodar o script achando que restaura tudo nao restaura nada disso.
Agravante: a linha 83 executa `Unregister-ScheduledTask` antes de registrar cada task. Isso zera o LastRunTime e faz a task perder o disparo do dia se o horario do trigger ja passou.
[Hipotese] E a causa provavel da matinal perdida em 24/07, sexta-feira: o script foi rodado depois das 10h e a task nasceu de novo sem executar. Com a Monitor-Tasks fora do ar, uma repeticao passa despercebida.
Nao propor troca de script: REGDRIFT1 (resolvido 23/07) declarou este o registrador canonico justamente por ter config mais resiliente, e marcou `register-vixradar-tasks.ps1` como DEPRECATED. O problema aqui e escopo e efeito colateral, nao escolha de script.
[Aberto] O que removeu as 5 tasks entre 23 e 24/07 continua sem explicacao. Este script nao remove nenhuma delas, nem com `-Remove`, que so alcanca as 6 declaradas. Enquanto a causa for desconhecida, pode repetir.
**Acao:** Deixar o escopo explicito no cabecalho, listando as 5 tasks nao cobertas e o registrador de cada uma. Emitir aviso na saida quando o re-registro acontecer depois do horario do trigger do dia. Investigar o que removeu as 5 tasks: checar `Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational` por eventos 141 (task deletada) entre 23 e 24/07, se a retencao do log ainda cobrir a janela.
**Validacao:** Cabecalho e saida do script declaram o escopo e o efeito de perder o disparo. Rodar com `-Status` nao altera nada. Causa da remocao identificada ou registrada como nao apurada por falta de log.

### P3 — SHADOW1: Revisao manual do shadow Fable 5 apos 2-4 semanas

**Origem:** Sessao 26/07 pt6 (implementacao do piloto shadow mode).
**Descricao:** `Invoke-FableShadow` compara veredictos Sonnet vs Fable 5 para CRITICOs. Apos 2-4 semanas de operacao, revisar `logs/routines/verificacao_fable_shadow_*.json` e adjudicar manualmente casos `pendente_adjudicacao: true`. Se houver ao menos 1 caso confirmado de falso-negativo do Sonnet capturado pelo Fable 5, criterio DOCBILL1 atingido.
**Prazo:** ~10-24/08/2026.
**Acao:** Revisar arquivos shadow acumulados, adjudicar divergencias, decidir se troca modelo primario.
**Validacao:** DOCBILL1 atingido ou decisao documentada de manter Sonnet.

### P3 — VIXRadar-Ranking-Mensal: decidir se implementa ou remove de vez

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task nunca executou (LastRunTime 1999 na epoca em que existia). Agora a task foi removida. Script `scripts\run_vixradar_ranking_mensal.ps1` existe. Funcionalidade nunca foi entregue.
**Acao:** Decidir se implementa ou remove scripts e documentacao relacionados.
**Validacao:** Decisao documentada.

### P4 — Corrigir documentacao do vault sobre o dia 24/07

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** O vault registrava "24/07 sem log matinal no diretorio (fim de semana ou sem disparo no path de logs)". 24/07 foi sexta-feira, dia util. A task foi recriada nesse dia, o que explica a ausencia do log.
**Acao:** Ja corrigido no `03 - Estado Atual.md` em 27/07.
**Validacao:** Corrigido.

---

## Fechadas (historico recente)

### Consolidar os dois PENDENCIAS.md

**Fechado em:** 27/07 (commit `76720a7`).
**Descricao:** Opcao A executada. `PENDENCIAS.md` da raiz (31 KB, fila aberta zero, conferido antes de mover) movido via `git mv` para `Obsidian VIX Radar\_Arquivo\PENDENCIAS (historico ate 2026-07-26).md`, com aviso de congelamento no topo. `Obsidian VIX Radar\PENDENCIAS.md` (este arquivo) passou a ser o canonico rastreado no git. `README.md` e `PROMPTS-RADAR.md` corrigidos, a linha 5 deste ultimo dizia que o arquivo da raiz vencia o Obsidian em conflito, isso teria virado instrucao falsa se nao corrigido.

### Monitor-Tasks — Registrador criado, task recriada e primeiro disparo validado

**Fechado em:** 27/07 07:04.
**Descricao:** `scripts\register-monitor-tasks.ps1` criado e executado. Task Ready no Scheduler, trigger diario 07:00. Primeiro disparo real confirmado: rodou 27/07 07:00:00, exit=7, `logs\monitor-tasks\monitor_20260727.log` (1863 bytes) e `erros_20260727.json` (4344 bytes) gerados. Exit 7 nao e falha do vigia, e a contagem de 7 tasks de terceiros (Szuchmacher-*, nao VIX Radar) com LastTaskResult nao-benigno que ele escaneou e reportou corretamente, exatamente a funcao para a qual foi recriado. Escaneou 12 tasks no total, 3 OK, 7 erros, 2 warnings (incluindo o achado novo da AgendaSemanal, ver P2 acima). `Get-ScheduledTaskInfo` confirma proxima execucao 28/07 07:00:00.

### SHADOW1 — Implementacao do piloto shadow mode Fable 5

**Fechado em:** 26/07.
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Aguardando periodo de avaliacao (ver SHADOW1 em abertas, P3).

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Aguardando periodo de shadow (ver P3 SHADOW1).
**Descricao:** 1 caso confirmado de falso-negativo do Sonnet capturado pelo Fable 5 = criterio atingido = decidir troca do modelo primario.

---

*Atualizado em 2026-07-27 07h04 BRT (validacao pos-registro: Monitor-Tasks e consolidacao dos PENDENCIAS.md movidas para Fechadas, achado novo da AgendaSemanal com exit=1 as 03:00). Fila aberta: 8 itens acionaveis (1 P1, 5 P2, 2 P3).*
