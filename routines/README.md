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

Universo completo confirmado ao vivo em 18/08/2026 (`Get-ScheduledTask`, não suposição).
Só as ligadas ao VIX Radar entram aqui — `Szuchmacher-*` de outros sistemas (briefing,
fechamento diário, lead nurture) e `RadarQuant-ScanDiario` (projeto `radar-quant-brasil`,
raiz diferente) compartilham a mesma máquina e ficam fora de escopo deste documento.

| Task | Gatilho real | Script | Função |
|------|---------|--------|--------|
| `VIXRadar-AgendaSemanal` | Dom 22:00 BRT | `run_vixradar_agenda_semanal.ps1` | Calendário de divulgação trimestral, top 20 stale por execução. Ver nota abaixo |
| `VIXRadar-Coleta-Volatilidade` | Diário 17:00 BRT | `run_coleta_volatilidade.ps1` | Coleta cotações + volatilidade e publica no KV. Sem LLM |
| `VIXRadar-Export-Historico` | Diário 20:45 BRT | `run_vixradar_export_historico.ps1` | Exporta estado preditivo do KV para `data/historico/`. Sem LLM |
| `VIXRadar-Reconciliacao-CVM` | Seg 08:00 BRT | `scripts/predictive/reconciliar_ipe_cvm.ps1` | Reconcilia IPE CVM (RJ/RE/default) vs estado semanal do Radar; publica KV `radar:reconciliacao_cvm:latest` + nota Obsidian. Sem LLM |
| `VIXRadar-Health-Watch` | **DESATIVADO 21/08/2026** | `watch-vixradar-health.ps1` | Vigia de health a cada 15 min (criado 13/08, `HEALTHWATCH1`), desligado por decisão do operador. Alerta de queda continua via `canonical-test` (6h) e `frescor-check` (diário). Reativar: `Enable-ScheduledTask -TaskName "VIXRadar-Health-Watch"` |
| `Szuchmacher-RetryVixMatinal` | Seg-Sex 13:30 BRT | `retry-vixradar.ps1 -RoutineId vixradar-matinal` | Relança a matinal via `claude` CLI local se o log do dia não tiver `FIM:` válido até o horário. Watchdog da sessão Claude Desktop, não duplica se ela ainda estiver rodando (lock de 3h da skill) |
| `Szuchmacher-RetryVixNoturno` | Diário 21:30 BRT | `retry-vixradar.ps1 -RoutineId vixradar-noturno` | Mesmo watchdog, para a noturna |
| `VIXRadar-Ranking-Mensal` | — | `run_vixradar_ranking_mensal.ps1` | **OBSOLETO.** Task não existe no Scheduler (confirmado 18/08, 0 resultado). Script funcional, sem LLM quebrado (usa `claude -p` só para a medição, do jeito certo), simplesmente não está agendado desde antes de 11/07. Ver nota abaixo |
| `Szuchmacher-AgendaMacro-Claude` | Sex 07:07 BRT | `run_claude_routine.ps1 -RoutineId atualizar-agenda-macro-szuchmacher` | Calendário macro semanal de szuchmacher.com.br (projeto irmão, mesmo runner genérico). Deploy exige aprovação humana explícita (SKILL.md Passo 6) |

### Nota sobre `VIXRadar-AgendaSemanal` (corrigido 2026-08-18, FASE 2)

Estava morta em silêncio desde antes de 10/08. Causa raiz: o runner genérico
(`run_claude_routine.ps1`) subia o Claude com `--tools 'WebSearch,WebFetch'` — essa
flag **substitui** o conjunto de ferramentas, não soma, então o Bash desaparecia. A
`SKILL.md` antiga mandava o próprio modelo rodar `curl.exe` contra o Worker. Sem
shell, os logs de 10/08 e 16/08 mostram o modelo relatando "não tenho shell" e "não
consigo executar curl", mas o wrapper gravava `FIM: concluido` com exit 0 do mesmo
jeito. Confirmado ao vivo em produção: 20 emissores com `atualizado_em:null` e
trimestre vencido (Equatorial, CEMIG, Eletrobras, Engie e outros).

Corrigido com wrapper dedicado (`scripts/run_vixradar_agenda_semanal.ps1`, mesmo
desenho de `run_vixradar_verificacao_async.ps1`): o PowerShell faz toda a I/O com o
Worker, o `claude -p` só pesquisa e devolve JSON. A task foi repontada para esse
script; o `Trigger` (domingo e quarta, 22:00) foi preservado sem alteração.

**Correção da suposição inicial desta mesma sessão:** o `DaysOfWeek` do trigger
real inclui domingo **e** quarta-feira (2x/semana), o que a primeira leitura desta
auditoria classificou como drift sem decisão por trás. Falso — o vault Obsidian
(`03 - Estado Atual.md`, entrada de 14/08) e o próprio `api/src/worker.js`
(`listarEmissoresCalendarioStale`, comentário `CALVAL-V2 (regra 9)`) confirmam que
foi decisão deliberada de 14/08/2026: a regra 9 do CALVAL-V2 criou o motivo
`revalidar_proximo` (trimestre previsto em ≤7 dias sem confirmação ainda), que
precisa de cadência mais curta que semanal para pegar evento iminente a tempo. Com
2 execuções/semana e cap de 20 emissores/execução, a cobertura rotativa real dos
103 emissores é ~2,6 semanas, não as "5–7 semanas" que a `SKILL.md` calcula
assumindo 1x/semana — esse texto da skill está desatualizado e não foi corrigido
nesta sessão (é só a fórmula de cobertura no comentário, não afeta o
funcionamento). Horário mantido em 22:00 (nunca houve confirmação de que 03:00,
citado em versões antigas deste documento, foi real em produção).

**Gap conhecido, não corrigido nesta sessão:** `scripts/monitor-tasks.ps1` (~linha 374) tem um
bloco especial para `VIXRadar-AgendaSemanal` que só interpreta `exit code 1` (comportamento da
implementação antiga) para dar diagnóstico específico ("Credit balance too low", "API key
invalida", etc. lendo o log). O script novo nunca retorna 1 (usa 2 a 8, um código por causa).
Nada fica invisível — o catch-all genérico (`} elseif ($code -ne 0) { ... "exit code $code
nao-benigno" ...`) ainda classifica qualquer falha como erro — só perde o diagnóstico
específico. Consertar exige mapear os novos exit codes (2=claude ausente, 3=health, 4=chave
ausente, 5=sem credencial, 6=ambiente contaminado ou erros de posting, 7=probe WebSearch ou
falha de auth em lote, 8=Worker recusou `listar_calendario_stale`) no bloco de diagnóstico.
Fora do escopo desta sessão por ser mudança em arquivo de monitoramento crítico já hardened,
sem pressa (não é blind spot, só diagnóstico menos específico).

### Nota sobre `VIXRadar-Ranking-Mensal` (2026-08-18, FASE 2)

Decisão desta sessão: descontinuar em vez de recriar a task. Não há sinal de falta
sentida em 5+ semanas sem rodar. Script e `SKILL.md` seguem intactos no repo/`.claude`
com nota de quarentena, `scripts/register-ranking-mensal-task.ps1` existe se a
decisão for revertida no futuro (registrar de novo + validar com execução
controlada antes de reclassificar como ativa).

## Claude Code Routines remotas (nuvem, `claude.ai/code`)

Confirmado ao vivo via `RemoteTrigger list` em 18/08/2026. Só existem **2** rotinas VIX
remotas reais, apesar do que os `ROUTINES-CLOUD.md` de matinal/noturno sugerem (ver aviso de
topo desses dois arquivos, marcados órfão/especulativo na mesma sessão — nenhuma remote de
matinal/noturno existe hoje).

| Rotina | Trigger ID | Gatilho real | Função |
|--------|-----------|---------------|--------|
| VIX Radar — Verificação Async Remote | `trig_01QeqBF3sSjuqUYE51a58RtA` | 02:00 e 14:00 BRT (`0 5,17 * * *` UTC) | Drena a fila `radar:verif_fila` em paralelo com o mecanismo local, credencial dedicada `REMOTE_VERIFICACAO_KEY` (escopo restrito, CHAVEESCOPO1). Contrato completo em `routines/claude-desktop/verificacao-async/ROUTINES-CLOUD.md` |
| VIX Radar — frescor diário | `trig_01B4dbLeSg8NpnMLjkBUXs1N` | Diário 23:00 BRT (`0 2 * * *` UTC) | Dispara `frescor-check.yml` e `canonical-test.yml` via GitHub Actions, lê os logs dos runs (cobertura, staleness, versão/health), gera print HTML do estado e entrega via `SendUserFile`. Não documentada em lugar nenhum até esta sessão. Não faz POST direto ao Worker, só lê Actions |

### Correção de cron (2026-08-18, FASE 2)

O `ROUTINES-CLOUD.md` da verificação remota sempre prometeu `02:00 e 14:00 BRT`, desenhado
para cobrir a maior lacuna do mecanismo local (18:20→10:20, ~16h sem toque). O
`cron_expression` real configurado no trigger, porém, era `20 10,18 * * *` **em UTC** — a
mesma string do cron local (`10:20 e 18:20 BRT`) colada sem converter fuso, ou seja
`07:20 e 15:20 BRT` na prática: disparava ~3h antes de cada execução local e nunca cobria a
janela noturna, o oposto do objetivo declarado. Bug de criação do mesmo dia (18/08), não
decisão. Corrigido via `RemoteTrigger update` para `0 5,17 * * *` (05:00/17:00 UTC = 02:00/14:00
BRT), confirmado pelo `next_run_at` retornado.

## Contrato dos endpoints

Base URL: `https://api.vixradar.com` · método `POST` · `Content-Type: application/json`.
Todos exigem `"routine_key": "<ROUTINE_API_KEY>"` no corpo (403 sem ela).

Worker versão de referência: ver `CLAUDE.md` (tabela "Produção atual").

- `listar_todos_emissores` → `{ ok, total, emissores:[{nome,setor}] }`
- `listar_emissores_prioritarios` `{ top_n }` → `{ ok, total, emissores:[...] }`
- `dados_para_analise` `{ empresa, setor }` → `{ ok, janela_inicio, janela_fim, cvm_documentos, eventos_historicos, contexto_historico, instrumentos_ativos }`
- `receber_analise` `{ empresa, setor, resultado, _matinal? }` → `{ ok, empresa, semana, n_eventos, sem_eventos }`
- `listar_fila_verificacao` `{ origem, ids? }` → `{ ok, total, itens:[...], system_prompt, user_prompt, cache_hits:{id:veredicto} }` — `cache_hits` traz veredicto já pago de ciclo anterior (VERIFCACHE1), reenviar sem reverificar
- `reservar_itens_fila` `{ origem, itens:[{id,data_fila}] }` → `{ ok, reservados:[ids], ja_reservados:[{id,claimante,ha_ms}], protecao_ativa }` — reserva atômica antes de verificar (CONCORVERIF1), janela de 20 min, aceita `ROUTINE_API_KEY` ou `REMOTE_VERIFICACAO_KEY`
- `confirmar_verificacao` `{ origem, inicio, itens:[{id,empresa,semana,data_fila,setor,evento,veredicto}] }` → `{ ok, resultado:{processados,aprovados,rejeitados,retratados,erros} }` — atenção, contagens vêm aninhadas em `resultado`, não na raiz

`resultado` de `receber_analise` segue o schema JSON da seção "FORMATO JSON" de cada SKILL.md. Contrato completo dos três endpoints de verificação (payload exato, passo a passo, critério adversarial) está no `SKILL.md` da rotina `vixradar-verificacao-async`, não repetido aqui.

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

- **2026-08-18 (FASE 2 de governança das rotinas):** Auditoria completa do universo real de
  rotinas (Task Scheduler ao vivo, `RemoteTrigger list`, `git log`, código-fonte do Worker),
  aplicando à `AgendaSemanal` o mesmo padrão de robustez/auditabilidade já validado na
  verificação assíncrona (entrada abaixo). Achados corrigidos: (1) `VIXRadar-AgendaSemanal`
  morta em silêncio desde antes de 10/08 — `run_claude_routine.ps1` subia o Claude com
  `--tools 'WebSearch,WebFetch'` (substitui, não soma) contra uma `SKILL.md` que mandava rodar
  `curl.exe`, sem shell a rotina não fazia nada mas gravava `FIM: concluido` exit 0; corrigido
  com `scripts/run_vixradar_agenda_semanal.ps1` dedicado, testado ao vivo contra produção duas
  vezes (primeira interrompida por limite de conta do usuário, com falha corretamente
  reportada — exit 7 + alerta admin, não silenciosa; segunda limpa, exit 0, 8/20 emissores
  atualizados, `atualizado_em` confirmado em produção via nova consulta independente); task
  repontada, `Trigger` domingo+quarta 22:00 preservado sem alteração. (2) `VIXRadar-Ranking-
  Mensal` não existe no Task Scheduler (confirmado, zero resultado), descontinuada
  formalmente. (3) Segunda Remote Routine (`VIX Radar — frescor diário`, 23:00 BRT) documentada
  pela primeira vez. (4) Cron da verificação remota estava errado desde a criação no mesmo dia
  — prometia 02:00/14:00 BRT mas o `cron_expression` real era a string do cron local colada
  sem converter fuso (`07:20/15:20 BRT` de fato); corrigido via `RemoteTrigger update`. (5)
  `ROUTINES-CLOUD.md` de matinal/noturno descreviam Remote Routines que nunca existiram,
  instruindo `ROUTINE_API_KEY` de privilégio total; marcados órfão/especulativo. (6) Suposição
  própria corrigida antes de agir: o disparo 2x/semana da AgendaSemanal parecia drift, mas o
  vault e `CALVAL-V2 (regra 9)` no Worker confirmam que foi decisão deliberada de 14/08 (cadência
  mais curta para o motivo `revalidar_proximo`). Pendência registrada, não bloqueante:
  `monitor-tasks.ps1` tem diagnóstico específico para `VIXRadar-AgendaSemanal` amarrado ao exit
  code antigo (1), que o script novo não usa mais (usa 2-8); catch-all genérico ainda classifica
  qualquer falha como erro, só perde o diagnóstico fino — não é blind spot. Matriz completa e
  evidência em `Obsidian VIX Radar/10_Estado_Atual_Validado.md`. Achado extra na verificação de
  fechamento: `retry-vixradar.ps1` e `monitor-tasks.ps1` tinham o mesmo regex
  `(\d+)/\d+ processados` que não casava com "N/N **emissores** processados" (palavra extra no
  meio), causou retry falso real da matinal em 17/08 (rotina já tinha entregue 19/19 às 11:35,
  watchdog relançou às 13:30 achando que não). Sessão relançada se autodiagnosticou sem
  duplicar nada, mas queimou sessão à toa. Corrigido nos dois arquivos, commit `ad06ad4`.
- **2026-08-18:** Primeira prova ao vivo de dual-execução real na fila de verificação: a sessão local
  (Claude Desktop, `origem:"local"`) e a Claude Code Routine remote (`origem:"remote"`, roda 02:00 e
  14:00 BRT, ver `ROUTINES-CLOUD.md` na pasta da rotina) drenaram a mesma fila em paralelo. Fila com 26
  itens no início da checagem local; `reservar_itens_fila` devolveu `protecao_ativa:true` (reserva via
  Durable Object, CONCORVERIF1) e confirmou 20 itens já `ja_reservados` pela `remote` cerca de 11 minutos
  antes, sobrando 6 para a sessão local processar — 4 reaproveitados via `cache_hits` (VERIFCACHE1, sem
  busca nova) e 2 verificados do zero contra fonte primária CVM (Movida, Aegea Saneamento). Fila terminou
  em 0, com ~30s de lag de propagação do Durable Object antes do último item sumir de
  `listar_fila_verificacao`. Health final em produção: `{"ok":true,"versao":"v4.9.198",...,"kv":true,
  "telemetria":true,"sentry_ok":true,"verificador_ok":true}` — confirma que `verificador_ok` volta a
  `true` sozinho quando a fila é drenada, sem reinício nem intervenção manual. Corrigidos no mesmo dia,
  no `SKILL.md` da rotina e na seção "Contrato dos endpoints" acima: o formato real da resposta de
  `confirmar_verificacao` (contagens aninhadas em `resultado{}`, não na raiz — versão anterior do SKILL
  documentava a raiz e o log da execução registrou contadores vazios com `ok:true` até a releitura do
  JSON bruto) e a regra de reaproveitamento de `cache_hits` (ausente do SKILL até então).
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
