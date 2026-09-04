---
Status: Vigente
Data da Versão: 2026-08-18 (alinhada à produção, Worker v4.9.198)
Origem do Registro: Claude
Condição de Obsolescência: próxima auditoria completa de rotinas, ou quando qualquer linha desta matriz divergir do estado real confirmado em produção/Task Scheduler/Remote Routines
tags: [vix-radar, rotinas, governanca, fase-2, auditoria]
---

# Estado Atual Validado — Governança de Rotinas (FASE 2)

> [!info] Atualização de versão, 2026-09-04 (não reabre a auditoria de rotinas abaixo, datada de 18/08 e ainda válida na sua própria matéria)
> Produção do Worker em **v4.9.240**, frontend em **v202.39**. O plano FEEDRETRO1 foi fechado por inteiro nesta data (Fases 0 a 3), e a Fase 3 tocou a governança desta matriz num ponto que não estava escrito em lugar nenhum: **o que conta como entrega de uma rotina**. A regra ficou registrada na seção `## Semântica de entrega e de retry`, abaixo. Nenhuma rotina mudou de classificação. Mudaram os gatilhos de `Szuchmacher-RetryVixNoturno`, que passou a ter dois (21:30 e 23:20, Seg-Sex), e a matinal foi confirmada como diária depois de o script de registro ser achado divergente do Scheduler vivo (DRIFTRETRY1).

> [!info] Atualização de versão, 2026-09-03 (não reabre a auditoria de rotinas abaixo, datada de 18/08 e ainda válida na sua própria matéria)
> Produção do Worker avançou de v4.9.198 (data desta auditoria) para **v4.9.236**, via INCIDENTE-FRESHNESS2 (detalhe em `PENDENCIAS.md` e `status/ESTADO.md`). Repositório local e `origin/main` sincronizados, ambos no commit `b5460c1745b117d1534d4ad5ea8d729fc9355824`, confirmado por comparação direta de SHA depois do push e de um `git fetch` novo. Nenhuma rotina desta matriz mudou de classificação por causa desse deploy, ele só adicionou campos de observabilidade ao health.

Matriz canônica do universo real de rotinas do VIX Radar, produzida por auditoria direta
(Task Scheduler ao vivo, `RemoteTrigger list`, logs de produção, `git log`, código-fonte do
Worker), não por leitura de documentação anterior. Hierarquia de verdade aplicada: produção
real > vault > repositório > `SKILL.md` > histórico antigo. Onde a documentação antiga
divergia da produção, a produção venceu e a documentação foi corrigida na mesma sessão.

Ver [[03 - Estado Atual]] para o diário operacional contínuo. Este documento é a fotografia
estrutural do agendamento, não substitui o diário.

## Resumo executivo

Universo real: **13 rotinas locais** (Task Scheduler + 2 watchdogs) + **2 Claude Code
Routines remotas** + **5 GitHub Actions workflows** + **4 Cloudflare Cron Triggers internos
do Worker**. Nenhuma rodava fora desse universo confirmado.

### Classificação por rotina

| Rotina | Classificação |
|---|---|
| `vixradar-matinal` | LOCAL SOMENTE |
| `vixradar-noturno` | LOCAL SOMENTE |
| `vixradar-verificacao-async` (par local+remote) | **LOCAL + REMOTE** (dual real, provado 18/08) |
| `VIXRadar-AgendaSemanal` | LOCAL SOMENTE |
| `VIXRadar-Coleta-Volatilidade` | LOCAL SOMENTE |
| `VIXRadar-Export-Historico` | LOCAL SOMENTE |
| `VIXRadar-Reconciliacao-CVM` | LOCAL SOMENTE |
| `VIXRadar-Health-Watch` | LOCAL SOMENTE |
| `Szuchmacher-RetryVixMatinal`/`RetryVixNoturno` | LOCAL SOMENTE (watchdog) |
| VIX Radar — frescor diário | REMOTE, sem par local (não é fallback de nada, é a única implementação) |
| `VIXRadar-Ranking-Mensal` | **DESCONTINUAR** |
| canonical-test / daily-status-email / frescor-check / scan-emergencia / worker-tests | GITHUB ACTIONS |
| 4 crons internos do Worker (matinal/noturno/watchdog/agenda-build) | CLOUDFLARE CRON |

Nenhuma rotina se encaixa em REMOTE PRIMÁRIO ou LOCAL+REMOTE FALLBACK no sentido estrito
(remote como principal com local de reserva, ou o inverso) — o único par local+remote real
(verificação assíncrona) roda os dois **simultaneamente por desenho**, não em relação
primário/fallback, cobrindo janelas horárias diferentes.

Matinal e noturno avaliados e **mantidos locais de propósito**, conforme instrução original de
não forçar migração para Remote sem comparar custo e equivalência funcional: nenhum bug
encontrado, plano Max local é flat-rate (sessão interativa e rotina agendada não competem por
custo adicional, ver memória do projeto), e mover para Remote trocaria custo zero por custo
metrado sem ganho funcional correspondente. Nenhuma mudança faria sentido sem uma razão
concreta, que não apareceu na auditoria.

### Independência do PC do operador

**Independem do PC ligado:** os 2 Claude Code Routines remotos (verificação assíncrona remote
+ frescor diário), os 5 GitHub Actions workflows, os 4 Cloudflare Cron Triggers do Worker —
todos rodam em infraestrutura de nuvem (Anthropic/GitHub/Cloudflare).

**Necessariamente locais:** as 11 rotinas restantes (matinal, noturno, verificação assíncrona
local, agenda-semanal, coleta-volatilidade, export-historico, reconciliacao-cvm, health-watch,
os 2 watchdogs de retry) — todas chamam `claude` CLI local via credencial de assinatura do
desktop, ou dependem de `wrangler`/PowerShell local. Nenhuma tem caminho de execução que não
passe pela máquina do operador. A fila de verificação é a única com cobertura real quando o PC
está desligado, via o par remote.

### Duplicações eliminadas

**Zero duplicações ativas encontradas.** O sistema já tinha os guards corretos antes desta
sessão (tasks nativas `Disabled` para matinal/noturno/verificação, mutex nas rotinas
PowerShell). O único risco de duplicação real seria alguém reabilitar essas três tasks — não
foi feito, e o guard segue intacto. O novo script da agenda-semanal também ganhou mutex
(`Global\vixradar-agenda-semanal`) que não existia antes.

### Riscos residuais

- RESOLVIDO 19/08 (madrugada): auditoria geral encontrou os 24 `.ps1` + 4 `SKILL.md` (2
  versionados + 2 vivos fora do repo) desta tabela ainda hardcodando `FREQUENTE\Monitoramento de
  Credito`, sobrevivendo à inversão de junction descrita acima. Corrigido e testado ao vivo
  (`monitor-tasks.ps1`, `retry-vixradar.ps1`), guarda nova `scripts/lint-legacy-path.ps1`. Não
  muda nenhuma classificação desta matriz, só fecha a lacuna que a inversão de junction deixou.
  Detalhe em `PENDENCIAS.md`.
- P2: `monitor-tasks.ps1` com diagnóstico específico da AgendaSemanal preso a exit code
  antigo — catch-all genérico cobre, só perde precisão da mensagem.
- P2: linha `ROTINA_RESUMO` padronizada só na agenda-semanal, as outras 5 rotinas estáveis
  mantêm formato de log próprio (retrofit em sessão separada, `task_12edfa2c`).
- Baixo: `VIXRadar-AgendaSemanal` nunca teve confirmação viva de que 03:00 (citado em versões
  antigas do README) foi horário real de produção — mantido 22:00, sem evidência de que 03:00
  tenha existido de fato, então não é regressão, é documentação antiga possivelmente já errada.
- Nenhum risco de segurança residual identificado: nenhuma credencial nova criada, nenhum
  segredo exposto, `REMOTE_VERIFICACAO_KEY` continua com escopo restrito e não foi tocada além
  da correção de cron.

Achados que exigiram correção nesta sessão:

1. **`VIXRadar-AgendaSemanal` morta em silêncio.** O runner genérico subia o Claude com
   `--tools 'WebSearch,WebFetch'` (substitui o toolset, não soma) contra uma `SKILL.md` que
   mandava o próprio modelo rodar `curl.exe`. Sem shell, a rotina não conseguia falar com o
   Worker, mas o wrapper gravava `FIM: concluido` com exit 0 do mesmo jeito. Confirmado ao
   vivo: 20 emissores com calendário trimestral vencido e `atualizado_em:null` (Equatorial,
   CEMIG, Eletrobras, Engie, entre outros). Corrigido com wrapper dedicado
   (`scripts/run_vixradar_agenda_semanal.ps1`), mesmo desenho que já funciona em
   `run_vixradar_verificacao_async.ps1`: PowerShell fala com o Worker, o modelo só pesquisa.
2. **`VIXRadar-Ranking-Mensal` não existe no Task Scheduler.** `CLAUDE.md` e
   `routines/README.md` afirmavam rotina ativa; `Get-ScheduledTask` real devolve zero
   resultados. Sem log desde 11/07. Decisão do usuário: descontinuar formalmente em vez de
   recriar, documentação corrigida, script e `SKILL.md` mantidos em quarentena (não apagados).
3. **Segunda Remote Routine não documentada.** Além da verificação assíncrona (já hardened na
   sessão anterior), existe `VIX Radar — frescor diário` (`trig_01B4dbLeSg8NpnMLjkBUXs1N`,
   23:00 BRT), disparando `frescor-check.yml`/`canonical-test.yml` e reportando estado. Rodava
   sem estar em nenhum documento operacional.
4. **Cron da verificação remota estava errado desde a criação (mesmo dia, 18/08).** O
   `ROUTINES-CLOUD.md` sempre prometeu 02:00/14:00 BRT, mas o `cron_expression` real no
   trigger era `20 10,18 * * *` **sem converter fuso** (a mesma string do cron local colada
   direto), ou seja `07:20`/`15:20` BRT de fato — 3h antes de cada execução local, cobrindo a
   janela errada. Corrigido via `RemoteTrigger update` para `0 5,17 * * *` UTC.
5. **`ROUTINES-CLOUD.md` de matinal e noturno descreviam rotinas remotas que nunca foram
   criadas**, instruindo uso de `ROUTINE_API_KEY` (privilégio total) num ambiente hipotético.
   Marcados ÓRFÃO/ESPECULATIVO, não apagados.
6. **Suposição própria corrigida antes de agir.** A primeira leitura desta auditoria
   classificou o disparo duplo (domingo+quarta) da `AgendaSemanal` como drift de registro sem
   decisão por trás. Falso — o vault (`03 - Estado Atual.md`, 14/08) e o comentário
   `CALVAL-V2 (regra 9)` em `api/src/worker.js` confirmam que foi decisão deliberada: o motivo
   `revalidar_proximo` (trimestre em ≤7 dias sem confirmação) precisa de cadência mais curta
   que semanal. O trigger foi preservado sem alteração; só a ação (script) foi repontada.

## Matriz final por rotina

| Rotina | Função | Modo anterior | Modo final | Local | Remote | GitHub/CF | Idempotente | Credencial | Última prova | Resultado | Rollback | Status |
|---|---|---|---|:-:|:-:|:-:|---|---|---|---|---|---|
| `vixradar-matinal` | Top 15 EWS, análise diária | Claude Desktop (cron `0 10 * * 1-5`) | Não alterado | ✓ | — | — | Presumido pelo desenho anterior, não reauditado nesta sessão | `ROUTINE_API_KEY` | Log 18/08: `FIM: matinal 20/20 processados. CRITICO=2 RELEVANTE=13 ECO=5` | OK | Reabilitar task nativa `VIXRadar-Matinal` (hoje `Disabled` de propósito, guarda anti-duplicata) | NÃO ALTERADO |
| `vixradar-noturno` | Varredura dos 103 emissores | Claude Desktop (cron `0 18 * * *`) | Não alterado | ✓ | — | — | Presumido pelo desenho anterior, não reauditado | `ROUTINE_API_KEY` | Log 18/08: `FIM: noturno concluido. Total do dia 103/103` | OK | Reabilitar task nativa `VIXRadar-Noturno` (`Disabled` de propósito) | NÃO ALTERADO |
| `vixradar-verificacao-async` (local) | Drena fila de verificação adversarial | Claude Desktop (cron `20 10,18 * * *`) | Não alterado (hardened na sessão anterior, FASE 1) | ✓ | — | — | **Sim, provado**: reserva atômica via Durable Object (CONCORVERIF1) | `ROUTINE_API_KEY` | Log 18/08 18h28-18h37: dual-execução real com a remote, fila 26→0, `protecao_ativa:true` | OK | Reabilitar task nativa `VIXRadar-Verificacao-Async` | VALIDADO (herdado da FASE 1) |
| VIX Radar — Verificação Async Remote | Mesma fila, cobre janela sem PC ligado | 02:00/14:00 BRT nominal, cron real 07:20/15:20 BRT (bug) | Cron corrigido para 02:00/14:00 BRT real | — | ✓ | — | Sim, mesma reserva atômica do mecanismo local | `REMOTE_VERIFICACAO_KEY` (escopo restrito, CHAVEESCOPO1) | `RemoteTrigger update` confirmado, `next_run_at` recalculado para o horário certo | OK | `RemoteTrigger update` de volta ao cron anterior (registrado, reversível) | VALIDADO |
| VIX Radar — frescor diário | Dispara Actions, reporta staleness | Rodava sem documentação | Documentado nesta sessão, sem alteração de código | — | ✓ | dispara `frescor-check.yml` + `canonical-test.yml` | Sim, read-only (só lê Actions e reporta) | OAuth da sessão remota (sem `routine_key`) | Histórico de runs verdes consecutivos de `frescor-check.yml` (indireto, não disparado ao vivo nesta sessão) | OK (prova indireta) | N/A, não foi alterada | VALIDADO COM RESSALVA |
| `VIXRadar-AgendaSemanal` | Calendário trimestral, top 20 stale | `run_claude_routine.ps1` catálogo genérico, `--tools` sem Bash | `scripts/run_vixradar_agenda_semanal.ps1` dedicado | ✓ | — | — | **Sim, por construção**: sempre requery `listar_calendario_stale`, só posta o que achou, nunca marca sem escrever | `ROUTINE_API_KEY` | Teste controlado ao vivo 18/08 21:56 BRT: `FIM: agenda-semanal \| stale_inicial=20 atualizados=8 pulados=12 mismatch=0 erros=0 lotes=3 tokens=552390` + `ROTINA_RESUMO\|vixradar-agenda-semanal\|local\|2026-08-19T00:38:41Z\|2026-08-19T00:56:41Z\|OK\|8\|0\|12\|v4.9.198`. Confirmado fora do script: `listar_calendario_stale` devolveu os 8 emissores com `atualizado_em:"2026-08-19"` (escrita real em KV, não simulada) | OK — exit 0, 8/20 atualizados, hard cap tratado explicitamente (não truncou silenciosamente) | `Action` da task repontada de volta ao runner genérico (`run_claude_routine.ps1 -RoutineId vixradar-agenda-semanal`) + `git revert` do commit desta sessão | VALIDADO |
| `VIXRadar-Coleta-Volatilidade` | Cotações + volatilidade no KV | Task Scheduler, sem LLM | Não alterado | ✓ | — | — | Sim, upsert por data | `ADMIN_PASSWORD` (DPAPI, não `routine_key`) | Log 18/08: `FIM: coleta_volatilidade OK` | OK | N/A | NÃO ALTERADO |
| `VIXRadar-Export-Historico` | Exporta estado do KV para `data/historico/` | Task Scheduler, sem LLM | Não alterado | ✓ | — | — | Sim, snapshot por data + commit automático escopado | `CLOUDFLARE_API_TOKEN` (wrangler, leitura) | Log 18/08: `FIM: ok - 3 arquivos ... (179s, modo delta, 0 avisos)`, commit `fe69ae6` confirmado | OK | N/A | NÃO ALTERADO |
| `VIXRadar-Reconciliacao-CVM` | Reconcilia IPE CVM vs estado semanal | Task Scheduler, sem LLM | Não alterado | ✓ | — | — | Sim, ciclo idempotente por natureza | `CLOUDFLARE_API_TOKEN` (com fallback OAuth) | Log 17/08: `FIM: ok - 13 documentos severos, 2 emissores casados, 0 divergencias` | OK | N/A | NÃO ALTERADO |
| `VIXRadar-Health-Watch` | Vigia de health fora de sessão, alerta e-mail | Task Scheduler, Seg-Sex 08-20h/15min | Documentado pela primeira vez nesta tabela, sem alteração | ✓ | — | — | Sim, cooldown de reenvio (`ReenvioMin`) | Lê health público (sem credencial) + `ADMIN_PASSWORD` para envio de e-mail | Task `Ready`, `LastTaskResult=0`, execução a cada 15 min confirmada no Scheduler | OK | N/A | NÃO ALTERADO |
| `Szuchmacher-RetryVixMatinal` / `RetryVixNoturno` | Watchdog: relança matinal/noturno se sem `FIM:` válido | Task Scheduler | Não alterado | ✓ | — | — | Sim, checa log do dia + lock de 3h da skill antes de disparar | Nenhuma direta (invoca `run_claude_routine.ps1`, que usa `ROUTINE_API_KEY`) | **Corrigido 19/08:** a prova anterior citada aqui (log 17/08 matinal, relançou 13:30, `RETRY EXIT: 0`) era o **retry falso**, não evidência de acerto — a matinal já tinha entregue 19/19 e o parser não reconheceu a linha `FIM:`. Prova válida atual: noturno 17/08 e 18/08 21:30, `OK: log do dia tem FIM valido, entrega feita` (evento 201 nos dois dias) | OK (noturno). Matinal: parser corrigido em `ad06ad4` + 19/08, formato da linha `FIM:` fixado no `SKILL.md` da matinal | N/A | REVALIDADO 19/08 |
| `VIXRadar-Ranking-Mensal` | Monitor mensal de ranking SEO | Task Scheduler nominal (nunca confirmado ao vivo) | Descontinuada | — | — | — | N/A | N/A | Task inexistente no Scheduler (`Get-ScheduledTask` retorna zero), último log 11/07 | Nunca rodou pelo menos desde 11/07 | Script e `SKILL.md` preservados em quarentena, `scripts/register-ranking-mensal-task.ps1` recria se decisão for revertida | OBSOLETO |
| GitHub Actions (5 workflows) | `canonical-test` (6/6h), `daily-status-email` (diário), `frescor-check` (diário), `scan-emergencia` (fallback diário), `worker-tests` (push/PR em `api/**`) | — | Não alterado | — | — | ✓ | Sim, todos read-only ou append (issue diária) | Token do GitHub Actions (implícito) | `gh run list`: últimos runs verdes, `worker-tests` verde no deploy v4.9.198 | OK | N/A | NÃO ALTERADO |
| Cloudflare Cron Triggers (Worker, 4) | Matinal/noturno/watchdog/agenda-build internos ao Worker (`wrangler.toml`) | — | Não alterado | — | — | ✓ | Sim, idempotente por desenho (reconstrução de `agenda:eventos:v1` etc.) | N/A (interno ao Worker) | `wrangler.toml:637-642` confirmado, já documentado em `CLAUDE.md` | OK | N/A | NÃO ALTERADO |

Fora de escopo desta auditoria (mesma máquina, projetos diferentes): `RadarQuant-ScanDiario`
(`radar-quant-brasil`), demais tasks `Szuchmacher-*` que servem outros sistemas (briefing,
fechamento diário, agenda macro do site institucional).

## Nota de fechamento — `VIXRadar-AgendaSemanal`

Duas tentativas de teste controlado ao vivo contra produção nesta sessão.

**Tentativa 1** (20:44 BRT) abortou no lote 2/5 com `claude CLI nao autenticado` — coincide no
tempo com o usuário atingindo o limite de uso da própria conta Claude durante a sessão, não um
bug do wrapper novo. Mesmo assim provou a propriedade central da correção: falha real virou
`EXITCODE=7` + alerta ao admin (`Send-VixRoutineAlert`) + `pulados=17` corretamente reportado,
nunca mais `FIM: concluido` silencioso com exit 0 do jeito que a versão antiga fazia. 3
emissores foram atualizados de verdade (Equatorial, CEMIG, Eneva); Eletrobras corretamente não
escreveu nada por falta de dado (`SEM_DATA`, comportamento correto, não inventa trimestre).

**Tentativa 2** (21:38 BRT, após reset de quota do usuário) completou limpa: `EXITCODE=0`,
3 lotes processados (12 emissores), `atualizados=8 pulados=12 mismatch=0 erros=0`, hard cap de
token atingido e tratado explicitamente (`HARD CAP pre-lote`, sem truncar silenciosamente — os
12 restantes ficam corretamente marcados para a próxima execução, não perdidos). Linha
`ROTINA_RESUMO` no formato exato pedido pelo usuário presente e correta. Confirmado
independentemente do próprio script: nova consulta a `listar_calendario_stale` mostra os 8
emissores com `atualizado_em:"2026-08-19"` — escrita real em produção, não simulada.

Achado lateral, não é bug: os 8 emissores atualizados continuam aparecendo como
`motivo:"confirmar_divulgacao"` na lista de stale mesmo após a atualização. Investigado no
código-fonte (`api/src/worker.js:4415-4451`) — existe um processo diário separado, interno ao
Worker (o "confronto diário com a publicação efetiva no CVM" do comentário `CALVAL-V2 regra 9`),
que só promove `status:"agendado"` para `status:"divulgado"` quando encontra o documento real
da CVM confirmando a divulgação efetiva. A rotina semanal confirma a DATA agendada; esse outro
processo confirma, em cadência própria, SE a divulgação de fato aconteceu. Camadas
independentes por desenho, não uma correção pendente desta sessão.

Produção pós-execução: health `ok:true kv:true telemetria:true sentry_ok:true
verificador_ok:true admin_email_ok:true`, v4.9.198. Task `VIXRadar-AgendaSemanal` repontada
para `scripts/run_vixradar_agenda_semanal.ps1`; `Trigger` (domingo+quarta 22:00, `DaysOfWeek=9`)
confirmado intacto antes e depois do repontamento. Remote Routine de verificação assíncrona
confirmada com `cron_expression:"0 5,17 * * *"` e `next_run_at` coerente com 02:00/14:00 BRT.

**Status final: VALIDADO.**

## Semântica de entrega e de retry

Regra de governança fixada em 2026-09-04 (FEEDRETRO1 Fase 3, tag `DEFERIDO-NAO-E-ENTREGA1`).
Ela não existia escrita em lugar nenhum, e a ausência dela produziu um comportamento errado
que passou despercebido: o ledger tratava emissor adiado por orçamento como emissor feito.

Uma rotina de varredura fecha cada emissor com uma linha de ledger no formato
`OK|empresa|tier|classe|n_eventos|submit|status|n_avanco_data`. O campo `status` é o que
decide, e ele tem três valores com significados diferentes:

| `status` | O que aconteceu | Conta como entrega? | Volta na próxima invocação? |
|---|---|---|---|
| `ANALISADO` | Emissor pesquisado e submetido | Sim | Não |
| `SKIP` | Avaliado pelo plano e submetido sem busca, de propósito | **Sim** | Não |
| `DEFERIDO` | Adiado pelo teto de tokens, nunca chegou a ser analisado | **Não** | **Sim** |

As cinco regras que decorrem disso:

1. **`DEFERIDO` não conta como entrega concluída para efeito de idempotência.** Emissor
   adiado continua pendente e a próxima invocação vai enxergá-lo como trabalho a fazer.
   Antes de 04/09 o regex de `Get-VixLedgerEmissoresNaJanela` parava no nome do emissor e
   nunca lia o `status`, então adiado e analisado contavam igual.
2. **`DEFERIDO` não dispara retry por si só.** Adiar por teto de tokens é o comportamento
   planejado do sistema, não uma falha. Um ledger com cauda adiada e sem erro é um ledger
   saudável, e `Test-VixLedgerEntregueNaJanela` continua deliberadamente sem transformar
   cauda adiada em motivo de relançamento.
3. **`SKIP` continua contando como processado.** O emissor foi avaliado pelo plano, o
   sistema decidiu que ele não precisava de busca naquele ciclo, e a submissão aconteceu.
   Isso é trabalho concluído, não trabalho pulado.
4. **A cauda adiada é retomada pela próxima invocação normal**, seja a segunda invocação da
   mesma janela, seja a rotina do dia seguinte, onde ela volta priorizada
   (`motivo=deferred_prioritario` no plano do Worker). Não existe mecanismo especial de
   recuperação de cauda, e não precisa existir.
5. **Retry continua reservado a falha real de execução ou de entrega.** Rotina que morreu,
   que não escreveu ledger, que ficou abaixo do mínimo por erro. Nunca cap operacional
   planejado. Misturar as duas coisas relançaria a noturna quase toda noite, porque adiar
   por teto é o normal e não a exceção, e o custo por token seria real.

A distinção entre a regra 1 e a regra 2 é o ponto fino e vale repetir: **adiado deixa de
contar como feito, mas não passa a contar como falha.** Ele muda o que uma invocação que já
ia acontecer vai processar, e não muda a decisão de lançar uma invocação nova.

Prova de duas pontas em `scripts/test-idempotencia-janela.ps1` (31 asserts). Casos G e H
cobrem exatamente esta matriz: ledger com 58 `ANALISADO` mais 45 `DEFERIDO` na janela devolve
45 pendentes com prova reversa de que a regra antiga devolvia zero; ledger com 103
`ANALISADO` devolve zero pendentes; caso I confirma `SKIP` contando como entrega; caso J
garante que ledger antigo, de antes deste formato, não é reprocessado retroativamente.

## Referências

- Auditoria completa: `routines/README.md` (fonte operacional canônica, versionada)
- Contrato do endpoint `listar_calendario_stale`/`atualizar_calendario_emissor`:
  `api/src/worker.js`, função `listarEmissoresCalendarioStale` (comentário `CALVAL-V2 regra 9`)
- Script novo: `scripts/run_vixradar_agenda_semanal.ps1`
- Diário operacional: [[03 - Estado Atual]]
