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

### P1 — Recriar task Monitor-Tasks no Scheduler

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** A task Monitor-Tasks foi removida do Task Scheduler (ultimo log 23/07). Sem ela, nao ha vigia de falha silenciosa: se a Noturno falhar, ninguem detecta. O script `scripts\monitor-tasks.ps1` continua existindo e funcional.
**Acao:** Recriar task diaria as 07:00 executando `scripts\monitor-tasks.ps1`. Bloqueado pelo item seguinte, nao existe registrador pronto para essa task.
**Validacao:** Log `logs\monitor-tasks\monitor_YYYYMMDD.log` gerado no dia seguinte ao recrear.

### P1 - Criar script de registro da task Monitor-Tasks

**Origem:** Revisao do diagnostico 27/07.
**Descricao:** Bloqueia o item acima. Nao existe `scripts\register-monitor-tasks.ps1`. As outras quatro tasks removidas tem registrador proprio (`register-reconciliacao-cvm-task.ps1`, `register-export-historico-task.ps1`, `register-ranking-mensal-task.ps1`, `fix_task_coleta_volatilidade.ps1`); a Monitor-Tasks nao tem. Recriar exige escrever o registrador antes, nao e um comando unico.
**Acao:** Escrever `scripts\register-monitor-tasks.ps1` no mesmo padrao dos demais: trigger diario 07:00, acao `-NoProfile -ExecutionPolicy Bypass -File`, comentario de reversao no cabecalho. Executar e conferir.
**Validacao:** `Get-ScheduledTask -TaskName 'Monitor-Tasks'` retorna Ready e o log do dia seguinte aparece em `logs\monitor-tasks\`.

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

### P2 - Verificar primeiro disparo da Matinal (27/07 10:00) e da AgendaSemanal (27/07 03:00)

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task VIXRadar-Matinal foi recriada em 24/07 as 10:00 (StartBoundary do trigger). Nunca disparou desde a recriacao (LastRunTime 30.nov.1999). Primeiro disparo previsto para hoje 27/07 as 10:00. Se nao disparar, a cobertura matinal (top 15 por EWS) permanece parada desde 23/07.
A VIXRadar-AgendaSemanal esta no mesmo estado (LastRunTime 30.nov.1999, 0x41303) e dispara hoje as 03:00, tambem primeiro disparo desde a recriacao. Nao e defeito: o trigger e segunda-feira 03:00 e a task nasceu na sexta 24/07, entao hoje e a primeira segunda depois disso.
**Acao:** Apos as 03:00, conferir o log da rotina `vixradar-agenda-semanal` em `logs\routines\`. Apos as 10:00, conferir se `logs\routines\vixradar-matinal_20260727.log` foi gerado.
**Validacao:** Ambos os logs presentes, matinal com submit_ok e metrics correspondentes, e `Get-ScheduledTaskInfo` com LastTaskResult 0 nas duas.

### P2 - Guard em register-all-routines-scheduler.ps1, o nome engana e o script derruba o disparo do dia

**Origem:** Revisao do diagnostico 27/07.
**Descricao:** Apesar do nome "all routines", o script declara apenas 6 tasks: VIXRadar-AgendaSemanal, VIXRadar-Matinal, VIXRadar-Noturno e as 3 Szuchmacher. Nao cobre Monitor-Tasks, Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM nem Ranking-Mensal, que sao justamente as 5 removidas. Quem rodar o script achando que restaura tudo nao restaura nada disso.
Agravante: a linha 83 executa `Unregister-ScheduledTask` antes de registrar cada task. Isso zera o LastRunTime e faz a task perder o disparo do dia se o horario do trigger ja passou.
[Hipotese] E a causa provavel da matinal perdida em 24/07, sexta-feira: o script foi rodado depois das 10h e a task nasceu de novo sem executar. Com a Monitor-Tasks fora do ar, uma repeticao passa despercebida.
Nao propor troca de script: REGDRIFT1 (resolvido 23/07) declarou este o registrador canonico justamente por ter config mais resiliente, e marcou `register-vixradar-tasks.ps1` como DEPRECATED. O problema aqui e escopo e efeito colateral, nao escolha de script.
[Aberto] O que removeu as 5 tasks entre 23 e 24/07 continua sem explicacao. Este script nao remove nenhuma delas, nem com `-Remove`, que so alcanca as 6 declaradas. Enquanto a causa for desconhecida, pode repetir.
**Acao:** Deixar o escopo explicito no cabecalho, listando as 5 tasks nao cobertas e o registrador de cada uma. Emitir aviso na saida quando o re-registro acontecer depois do horario do trigger do dia. Investigar o que removeu as 5 tasks: checar `Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational` por eventos 141 (task deletada) entre 23 e 24/07, se a retencao do log ainda cobrir a janela.
**Validacao:** Cabecalho e saida do script declaram o escopo e o efeito de perder o disparo. Rodar com `-Status` nao altera nada. Causa da remocao identificada ou registrada como nao apurada por falta de log.

### P2 - Consolidar os dois PENDENCIAS.md

**Origem:** Revisao do diagnostico 27/07.
**Descricao:** Existem dois arquivos com esse nome. `PENDENCIAS.md` na raiz do projeto, 31 KB, rastreado no git, ultima alteracao 26/07 17h47, com o historico longo. `Obsidian VIX Radar\PENDENCIAS.md`, este arquivo, 5 KB, untracked, criado em 27/07. O MOC passou a apontar para este, entao o da raiz vira backlog orfao que ninguem le. O wikilink `[[PENDENCIAS.md]]` so resolve para o do vault: o da raiz esta fora do vault e nunca foi alcancavel por link do Obsidian.
Verificado em 27/07: a fila aberta do arquivo da raiz e zero. A tabela "Pendencias abertas" dele contem apenas itens ja resolvidos, mais DOCBILL1 e SHADOW1, que ja constam aqui. Ou seja, nao ha trabalho aberto exclusivo la, o conteudo restante e historico. Isso torna a consolidacao de baixo risco.
**Acao:** Escolher uma das opcoes.
Opcao A (recomendada), vault como canonico: mover o conteudo ainda vivo do arquivo da raiz para ca, mandar o restante para `Obsidian VIX Radar\_Arquivo\PENDENCIAS (historico ate 2026-07-26).md`, apagar o da raiz no git com commit explicando a mudanca de local, e commitar este arquivo (hoje untracked). Coerente com a regra do CLAUDE.md local de que o Obsidian prevalece.
Opcao B, raiz como canonico: descartar este arquivo e reverter o ponteiro do MOC para a raiz. Mantem o historico intacto e o rastreamento no git, mas deixa o wikilink quebrado de novo.
**Validacao:** Um unico PENDENCIAS.md ativo, o outro arquivado ou removido, MOC apontando para o vivo, e o arquivo canonico rastreado no git.

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

*Atualizado em 2026-07-27 ~01h35 BRT (revisao do diagnostico: registrador da Monitor-Tasks, guard no register-all-routines-scheduler, consolidacao dos dois PENDENCIAS.md).*
