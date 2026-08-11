# Rotinas Operacionais — VIX Radar (fonte canônica versionada)

> **Atualizado 2026-08-07. Leia o aviso abaixo antes de mexer em qualquer task.**
>
> O agendamento está **dividido entre dois mecanismos**, e confundi-los causa
> execução dupla.
>
> **Matinal, Noturno e Verificacao-Async rodam por sessão agendada do Claude
> Desktop.** As tasks nativas homônimas do Windows Task Scheduler estão
> `Disabled` **de propósito**, como guarda anti-duplicata. Os scripts checam esse
> estado antes de rodar e registram `GUARD_OK` no log. **Nunca reabilitar essas
> três.** Reabilitar dispara os dois caminhos no mesmo horário, que é exatamente
> o incidente de duplicata citado no histórico desta página.
>
> **As demais rotinas seguem no Windows Task Scheduler** via scripts PowerShell
> (`scripts/run_vixradar_*.ps1`).
>
> Consequência prática para monitoramento: para as três migradas, o
> `LastTaskResult` do Task Scheduler está **congelado desde 06/08/2026 e não
> significa nada**. A saúde delas se lê pela linha `FIM:` no log em
> `logs/routines/vixradar-*_<data>.log`, que é o que o bloco `ROTINACEGA1` do
> `scripts/monitor-tasks.ps1` faz.
>
> Os arquivos `SKILL.md` nesta pasta são **referência documental e templates de prompt**
> usados pelos scripts. Para agendamento, a fonte de verdade é esta tabela mais o
> estado real da máquina; os SKILL.md são a fonte de verdade para o contrato analítico.

## Rotinas em sessão agendada do Claude Desktop (task nativa Disabled de propósito)

Estado da task nativa verificado na máquina em 2026-08-07, as três `Disabled`.

| Rotina | Gatilho | Script | Função |
|------|---------|--------|--------|
| `VIXRadar-Matinal` | Seg-Sex 10h00 BRT | `run_vixradar_matinal_claude.ps1` | Top 15 por EWS, Haiku (lotes 6) + Sonnet (EWS>=38, lotes 4) |
| `VIXRadar-Noturno` | Diário 18h00 BRT | `run_vixradar_noturno_claude.ps1` | 103/103 emissores, Haiku primeiro (lotes 15) + Sonnet depois (lotes 11) |
| `VIXRadar-Verificacao-Async` | Diário 10:20 BRT | `run_vixradar_verificacao_async.ps1` | Dreno da fila `radar:verif_fila:{data}` (também acionado inline pós-matinal e pós-noturno) |

## Tasks ativas no Windows Task Scheduler

| Task | Gatilho | Script | Função |
|------|---------|--------|--------|
| `VIXRadar-Export-Historico` | Diário 20:45 BRT | `run_vixradar_export_historico.ps1` | Exporta estado preditivo do KV para `data/historico/` |
| `VIXRadar-Reconciliacao-CVM` | Seg 08:00 BRT | `scripts/predictive/reconciliar_ipe_cvm.ps1` | Reconcilia IPE CVM (RJ/RE/default) vs estado semanal do Radar; publica KV `radar:reconciliacao_cvm:latest` + nota Obsidian |
| `VIXRadar-Ranking-Mensal` | Dia 1, 11:30 BRT | `run_vixradar_ranking_mensal.ps1` | Monitor mensal de ranking SEO |
| `VIXRadar-AgendaSemanal` | Dom 03:00 | `run_claude_routine.ps1 -RoutineId vixradar-agenda-semanal` | Calendário de divulgação trimestral, top 20 stale por execução. **Deve ficar Enabled**, é o gatilho oficial da skill. Ver nota abaixo |
| `Szuchmacher-AgendaMacro-Claude` | Sex 07:07 BRT | `run_claude_routine.ps1 -RoutineId atualizar-agenda-macro-szuchmacher` | Calendário macro semanal de szuchmacher.com.br. Religada 02/08/2026 — motivo original do desligamento (14/07, disparo fantasma via cron interno do skill) deixou de existir em 08/07 quando o sistema de cron interno inteiro foi aposentado (ver histórico abaixo); ficou desligada por omissão até esta investigação, sem decisão registrada. Deploy exige aprovação humana explícita (SKILL.md Passo 6) — o pior caso de falha é a rotina parar pedindo aprovação, nunca publicar sozinha. |

### Nota sobre `VIXRadar-AgendaSemanal` (corrigido 2026-08-07)

As duas afirmações que este README fazia sobre ela eram falsas, e as duas
apontavam para a ação errada.

Dizia que a task foi **desabilitada em 16/07**. Nunca foi. Em 07/08 está `Ready`
com `Enabled=True`, e está certo assim, porque é o gatilho oficial da skill.

Dizia que a **skill foi neutralizada em 14/07**. O que foi neutralizado é o cron
interno da skill, forçado para 31 de fevereiro, exatamente para não duplicar esta
task. A `SKILL.md` sempre existiu em
`C:\Users\User\.claude\scheduled-tasks\vixradar-agenda-semanal\`. O rótulo
`NEUTRALIZADA` na frontmatter dela é que gerou a confusão, e foi reescrito em 07/08.
Mesma armadilha que travou a `Szuchmacher-AgendaMacro-Claude` por 19 dias, ver
histórico de 02/08 abaixo.

A causa real do exit 6 de 03/08 está no log
`logs/routines/vixradar-agenda-semanal_20260803.log`, duas linhas apenas, o
pré-voo abortou porque o ambiente tinha `ANTHROPIC_MODEL=deepseek-v4-pro[1m]`.
Comportamento correto do guard, rodar rotina de análise contra agregador
não-Claude queima token sem entregar análise. A variável não está mais setada em
nenhum escopo e `Test-VixClaudeAmbienteLimpo` passa desde 07/08, então o próximo
disparo de domingo deve rodar. **Não validado ao vivo ainda**, conferir o log de
domingo.

## Contrato dos endpoints

Base URL: `https://api.vixradar.com` · método `POST` · `Content-Type: application/json`.
Todos exigem `"routine_key": "<ROUTINE_API_KEY>"` no corpo (403 sem ela).

Worker versão de referência: ver `CLAUDE.md` (tabela "Produção atual").

- `listar_todos_emissores` → `{ ok, total, emissores:[{nome,setor}] }`
- `listar_emissores_prioritarios` `{ top_n }` → `{ ok, total, emissores:[...] }`
- `dados_para_analise` `{ empresa, setor }` → `{ ok, janela_inicio, janela_fim, cvm_documentos, eventos_historicos, contexto_historico, instrumentos_ativos }`
- `receber_analise` `{ empresa, setor, resultado, _matinal? }` → `{ ok, empresa, semana, n_eventos, sem_eventos }`

`resultado` segue o schema JSON da seção "FORMATO JSON" de cada SKILL.md.

> **Segredo:** `ROUTINE_API_KEY` não é versionado. Vive como Wrangler secret
> no Worker e em `memory/credenciais.md` (gitignored). Os scripts leem a
> chave do ambiente/credenciais. Nunca cole em texto claro neste repo.

## Como recriar tasks (em caso de perda do Task Scheduler)

> **Antes de recriar qualquer coisa, leia isto.** Recriar `VIXRadar-Matinal`,
> `VIXRadar-Noturno` ou `VIXRadar-Verificacao-Async` como task **habilitada**
> produz execução dupla, porque elas já rodam pelo Claude Desktop. Se precisar
> recriá-las por qualquer motivo, criar e em seguida `Disable-ScheduledTask`,
> mantendo o guard. Só as tasks da segunda tabela devem nascer habilitadas.

As tasks do Windows são registradas via `Register-ScheduledTask` ou `schtasks /create`.
Consulte os scripts em `scripts/` para os comandos exatos de cada task.
Após recriar, validar com `Get-ScheduledTask -TaskName "VIXRadar-*"` conferindo
que as três migradas aparecem `Disabled`, rodar `pwsh scripts/monitor-tasks.ps1`
para confirmar que elas saem como `GUARD_OK` e não como erro, e registrar no
Obsidian (`03 - Estado de Produção.md`).

Se o agendamento do Claude Desktop se perder, o sintoma **não** aparece no
`LastTaskResult` das tasks, que está congelado. Aparece como `ROTINA SEM ENTREGA`
no `monitor-tasks.ps1`, que lê a linha `FIM:` do log da rotina. Esse é o único
vigia real das três hoje.

## Histórico de mudanças

- **2026-08-07:** Registrada a reversão de mecanismo que ninguém tinha documentado.
  Matinal, Noturno e Verificacao-Async voltaram do Windows Task Scheduler para
  sessão agendada do Claude Desktop, com as tasks nativas mantidas `Disabled`
  como guarda anti-duplicata. **A data exata da reversão não foi determinada.**
  O que se sabe por evidência: as três rodaram pelo Task Scheduler em 06/08
  (`LastRunTime` 11:31, 18:00 e 18:20), logo o desligamento veio depois disso, e
  em 07/08 as três já logavam `sessao agendada Claude Desktop` na linha de
  INICIO. Entre 16/07 e 06/08 este README afirmou o oposto do que a máquina
  fazia, incluindo a instrução de recriar as três como task habilitada, que hoje
  causaria execução dupla. Achado ao investigar por que o alerta diário do
  `monitor-tasks.ps1` trazia 8 erros e nenhum entrava no backlog, três dos oito
  eram essas tasks reportadas por `LastTaskResult` congelado. Correções do mesmo
  dia: `monitor-tasks.ps1` passou a tratá-las como `GUARD_OK` em vez de erro,
  alarma se alguma aparecer habilitada, e parou de escanear a si mesmo (o próprio
  `exit` dele é a contagem de achados, então virava um erro extra por dia).
- **2026-08-02:** `Szuchmacher-AgendaMacro-Claude` religada (`Enable-ScheduledTask`). Investigação disparada por `monitor-tasks.ps1` acusando `LastTaskResult=267011` (nunca rodou) com `LastRunTime` no sentinela 1999. Causa raiz: task ficou `Enabled:False` desde a janela de endurecimento de 14–16/07 (mesmo padrão aplicado à `VIXRadar-AgendaSemanal`, ver linha acima), motivo documentado na frontmatter do próprio `SKILL.md` (disparo fantasma via cron interno). Esse cron interno foi aposentado por completo em 08/07 (ver nota abaixo) — o risco que motivou o desligamento não existe mais desde então, mas ninguém religou a task nos 19 dias seguintes, e ela nunca entrou nesta tabela. Nota: a instrução de reativação escrita no próprio SKILL.md ("restaurar cron 7 7 \* \* 5") está obsoleta — refere-se ao mecanismo de cron interno já morto; hoje `Enable-ScheduledTask` no Windows Task Scheduler é suficiente e é o único gatilho real.
- **2026-07-16:** README reescrito — migração Claude Code Desktop → Windows Task Scheduler documentada. Horários e modelos corrigidos. `VIXRadar-AgendaSemanal` desabilitada.
- **2026-06-15:** Criação original — incidente de perda de registro do agendador Claude Desktop.
