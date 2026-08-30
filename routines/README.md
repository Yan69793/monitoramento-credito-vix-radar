# Rotinas Operacionais — VIX Radar (fonte canônica versionada)

**Status:** vigente
**Data da Versão:** 2026-08-25
**Origem do Registro:** `Get-ScheduledTask` ao vivo em 25/08/2026, logs em
`logs/routines/`, e decisão do operador sobre a inversão de horários.
**Condição de Obsolescência:** perde validade quando o mecanismo de agendamento
do Claude Desktop mudar, quando qualquer linha das duas tabelas divergir do que
`Get-ScheduledTask` responde, ou quando a rotina Sentinela for aposentada.

> **INVERSÃO DE HORÁRIOS (2026-08-25). Os nomes das rotinas estão invertidos em
> relação aos horários, e isso é deliberado.**
>
> A rotina chamada `vixradar-noturno` roda **de manhã, às 10h**, e é ela que varre
> os 103 emissores. A chamada `vixradar-matinal` roda **à noite, às 18h**, e é a
> passada curta no top 15. Os identificadores não foram renomeados de propósito:
> eles aparecem em nome de arquivo de log, no argumento `-RoutineId` dos dois
> vigias de retry, na leitura do `scripts/monitor-tasks.ps1`, nos nomes de
> heartbeat dentro do Worker (`varredura_matinal`, `varredura_batch`) e na lista
> `expectedAgents` do watchdog. Renomear tocaria tudo isso para ganho de função
> zero. **Ao ler um log, vá pelo horário, não pelo nome.**
>
> Motivo da inversão: quem abre o painel ao meio-dia via 88 dos 103 emissores com
> dado da noite anterior, e fato relevante no Brasil sai principalmente depois do
> fechamento. Com a varredura completa às 10h, o lote da noite anterior entra 15h
> depois em vez de 23h, e ao meio-dia as 103 foram olhadas há uma hora e meia.
> Custo aceito: notícia intradiária em emissor fora do top 15 espera a manhã
> seguinte, em vez de ser pega às 18h do mesmo dia.

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
| `VIXRadar-Noturno` | **Diário 10h00 BRT** | `run_vixradar_noturno_claude.ps1` | 103/103 emissores, fila rápida em Haiku primeiro (lotes de até 15) + fila aprofundada em Sonnet depois (lotes de até 16). **É a varredura completa, e roda de manhã** |
| `VIXRadar-Matinal` | **Seg-Sex 18h00 BRT** | `run_vixradar_matinal_claude.ps1` | Top 15 por EWS, Haiku (lotes 6) + Sonnet (EWS>=38, lotes 4). **É a passada curta, e roda à noite** |
| `VIXRadar-Verificacao-Async` | **Diário 11h00 e 18h45 BRT** | `run_vixradar_verificacao_async.ps1` | Dreno da fila `radar:verif_fila:{data}` (também acionado inline pós-varredura) |

A verificação passou a ter **duas sessões, e a das 18h45 não é opcional**. Sem
ela, tudo que a passada das 18h enfileira fica preso até o dia seguinte. A task
desabilitada guarda dois triggers (10h20 e 18h20), o que indica que a cobertura
dupla já foi o desenho original e se perdeu em algum momento. Critério de aceite,
fila em zero antes da virada do dia, conferido por `listar_fila_verificacao`.

A das 11h existe porque a varredura completa fecha por volta de 10h35 (medido:
18:06→18:33 em 18/08, 18:05→18:40 em 20/08, no horário antigo). Drenar às 10h20
seria esvaziar fila que ainda está enchendo.

## Tasks ativas no Windows Task Scheduler

Universo completo confirmado ao vivo em 18/08/2026 (`Get-ScheduledTask`, não suposição).
Só as ligadas ao VIX Radar entram aqui — `Szuchmacher-*` de outros sistemas (briefing,
fechamento diário, lead nurture) e `RadarQuant-ScanDiario` (projeto `radar-quant-brasil`,
raiz diferente) compartilham a mesma máquina e ficam fora de escopo deste documento.

| Task | Gatilho real | Script | Função |
|------|---------|--------|--------|
| `VIXRadar-AgendaSemanal` | **Dom e Qua** 22:00 BRT | `run_vixradar_agenda_semanal.ps1` | Calendário de divulgação trimestral, top 20 stale por execução. Ver nota abaixo |
| `VIXRadar-Coleta-Volatilidade` | Diário 17:00 BRT | `run_coleta_volatilidade.ps1` | Coleta cotações + volatilidade e publica no KV. Sem LLM |
| `VIXRadar-Export-Historico` | Diário 20:45 BRT | `run_vixradar_export_historico.ps1` | Exporta estado preditivo do KV para `data/historico/`. Sem LLM |
| `VIXRadar-Reconciliacao-CVM` | Seg 08:00 BRT | `scripts/predictive/reconciliar_ipe_cvm.ps1` | Reconcilia IPE CVM (RJ/RE/default) vs estado semanal do Radar; publica KV `radar:reconciliacao_cvm:latest` + nota Obsidian. Sem LLM |
| `VIXRadar-Health-Watch` | **DESATIVADO 21/08/2026** | `watch-vixradar-health.ps1` | Vigia de health a cada 15 min (criado 13/08, `HEALTHWATCH1`), desligado por decisão do operador. Alerta de queda continua via `canonical-test` (6h) e `frescor-check` (diário). Reativar: `Enable-ScheduledTask -TaskName "VIXRadar-Health-Watch"` |
| `VIXRadar-Sentinela` | **Seg-Sex, 09h25 e 09h55 até 17h25 e 17h55 BRT** | `run_vixradar_sentinela.ps1` | Varredura pontual por gatilho. Consulta `listar_plano_rotina modo=pontual` e analisa só quem tem documento da CVM ainda não entregue à análise, deferido por teto ou inconclusivo. Teto de 8 emissores e 120k tokens por execução. Na maioria das execuções sai em 0 token. Ver seção própria abaixo |
| `Szuchmacher-RetryVixMatinal` | **Seg-Sex 21:30 BRT** | `retry-vixradar.ps1 -RoutineId vixradar-matinal` | Relança a matinal (top 15, que agora roda às 18h) via `claude` CLI local se o log do dia não tiver `FIM:` válido até o horário. Watchdog da sessão Claude Desktop, não duplica se ela ainda estiver rodando (lock de 3h da skill) |
| `Szuchmacher-RetryVixNoturno` | **Diário 13:30 BRT** | `retry-vixradar.ps1 -RoutineId vixradar-noturno` | Mesmo watchdog, para a varredura completa, que agora roda às 10h |
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

### Nota sobre `VIXRadar-Sentinela` (SENTINELA1, criada 2026-08-25)

**Gatilhos da pontual, e o que ficou de fora de propósito.** Entra quem tem
documento da CVM ainda não entregue à análise (**fato novo**) ou quem ficou deferido
pelo teto de tokens (**dívida**). Não entram EWS, staleness nem `inconclusivo`. Os
dois primeiros já são cobertos pelas passadas diárias. O terceiro saiu no
DEFERGRUDA3, porque a pontual analisa em lote Haiku com ~2 buscas contra um
`_coberturaMin` de 7 no tier FULL, então toda análise dela grava `INCONCLUSIVO` e a
rotina reapresentava o próprio trabalho. Quem cuida do inconclusivo é o ramo
`inconclusivo_stale_breakout` do plano noturno, que promove a FULL depois de 48h.

**Status:** vigente · **Data da Versão:** 2026-08-25 · **Origem do Registro:**
implementada e medida contra produção v4.9.216 nesta sessão ·
**Condição de Obsolescência:** perde validade se o modo `pontual` mudar de
contrato no Worker, se o protocolo `RESULTADO|` do lote mudar, ou quando existir
uma ação de sincronização da CVM autenticada por `ROUTINE_API_KEY` (ver o limite
de SLA abaixo, que só então deixa de valer).

Detector barato na frente, análise cara atrás. Roda duas vezes por hora, aos :25 e
aos :55, das 09h25 às 17h55 em dias úteis.

**Por que dois disparos.** Com um por hora, colisão vira buraco. Documento
ingerido às 10h05, tentativa das 10h25 encontra a varredura completa rodando e
aborta, próxima só às 11h25, quase duas horas. Com o segundo disparo o mesmo caso
é pego às 10h55. Escolheu-se gatilho fixo em vez de bandeira de colisão porque
bandeira é estado que pode ficar preso, máquina reinicia com ela ligada e ninguém
vê.

**Regra de entrada.** Age quando o acervo da CVM que o Worker enxerga
(`cvm_fonte_last_modified` do health, público, sem credencial) mudou desde a
última vez que a rotina agiu, **ou** quando sobrou backlog da execução anterior.
A segunda metade não é detalhe: sem ela, emissor deferido por teto de tokens só
voltaria a ser olhado se a CVM publicasse de novo, o que pode nunca acontecer.
Estado em `logs/routines/sentinela_state.json`.

**Marcação de documento.** O plano devolve `cvm_novos_ids` por emissor, e esses ids
só entram em `radar:cvm_vistos:{empresa}` no `receber_analise` bem-sucedido.
Execução que morre no meio, estoura teto ou toma submit recusado deixa o gatilho
intacto e o emissor volta na execução seguinte.

**Limite de SLA, e este é o ponto honesto da rotina.** A latência de até uma hora
vale entre o **Worker ingerir** o documento e a análise sair, dentro da janela
operacional. **Não** vale entre a CVM **publicar** e a análise sair: a ingestão
continua presa aos crons do Worker das 12h30 e 18h30 BRT. Fechar essa ponta
exigiria uma ação de sincronização autenticada por `ROUTINE_API_KEY`, que hoje não
existe — `admin_sync_cvm_auto` e `sync_cvm` pedem `admin_senha`, e dar a senha de
admin a uma rotina contraria o CHAVEESCOPO1. A rotina faz um `HEAD` no zip da CVM
a cada execução e registra no log quando o arquivo está à frente do que o Worker
ingeriu, justamente para essa decisão nascer de dado medido.

**Sincronização sob demanda (SENTINELA-SYNC1).** Quando o `HEAD` acusa
`Last-Modified` novo, a rotina manda o Worker reingerir na hora via
`admin_sync_cvm_auto`, em vez de esperar os crons das 12h30 e 18h30. **O SLA conta da
publicação na CVM até a análise sair.** A credencial sai do cofre DPAPI `CurrentUser`
que `upload_volatilidade_kv.ps1`, `monitor-tasks.ps1` e `watch-vixradar-health.ps1` já
usam, lido por `api/Get-VixAdminCredential.ps1`. Nenhum segredo novo. Sem cofre a
rotina **não aborta**: registra o atraso medido e segue com o acervo atual.
`zip_last_modified` só avança no estado quando o sync volta `ok`, então falha de sync
não consome o gatilho.

**Tetos.** Oito emissores, 120k tokens e **22 minutos de relógio** por execução. O
teto de tempo é conferido antes de cada lote, então um lote lento não empurra os
seguintes. O que passar de qualquer um dos três fica deferido e volta pelo mesmo
gatilho, porque nada é marcado em `cvm_vistos`.

**Timeout por lote (SENTINELA-HANG1).** O `claude -p` roda por `Start-Process` com os
três fluxos redirecionados para arquivo, o que dá `WaitForExit(ms)` e de quebra elimina
o deadlock clássico de pipe, onde o buffer de `stderr` enche, o filho bloqueia
escrevendo e o pai bloqueia lendo `stdout`. O teto por lote é o que sobra do teto da
execução, com piso de 4 min. No estouro, `taskkill /T /F` mata a **árvore**, porque
`claude.exe` é lançador e o trabalho real está no `node` filho. Não há re-disparo
imediato de propósito: lote que estourou o relógio estoura de novo e gastaria o teto
duas vezes. Quem reexecuta é o backlog, com os emissores intactos.

Medição que motivou a rotina: em 25/08 a CVM republicou o arquivo às 07h58 BRT e o
Worker só ingeriu às 12h30. E o `modo=pontual` em produção acusou **34 emissores
parados na fila de deferidos** por teto de tokens. A causa apareceu ao **rodar a
rotina duas vezes e comparar as listas de alvo**: eram os mesmos 8 emissores, quatro
deles já analisados com `ok:true` na primeira execução. A bandeira
`_token_cap_deferred` ligava e nunca desligava (DEFERGRUDA1, corrigido no Worker
v4.9.217). Emissor deferido uma vez virava FULL permanente no tiering da noturna,
gastando 9 rodadas de busca todo dia e realimentando o próprio deferimento. Nenhuma
leitura de código tinha achado isso; rodar duas vezes e comparar a saída achou.

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
