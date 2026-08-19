---
Status: Vigente
Data da Versão: 2026-08-18 (alinhada à produção, Worker v4.9.198)
Origem do Registro: Claude
Condição de Obsolescência: próxima auditoria completa de rotinas, ou quando qualquer linha desta matriz divergir do estado real confirmado em produção/Task Scheduler/Remote Routines
tags: [vix-radar, rotinas, governanca, fase-2, auditoria]
---

# Estado Atual Validado — Governança de Rotinas (FASE 2)

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
| `Szuchmacher-RetryVixMatinal` / `RetryVixNoturno` | Watchdog: relança matinal/noturno se sem `FIM:` válido | Task Scheduler | Não alterado | ✓ | — | — | Sim, checa log do dia + lock de 3h da skill antes de disparar | Nenhuma direta (invoca `run_claude_routine.ps1`, que usa `ROUTINE_API_KEY`) | Log 17/08 matinal: relançou às 13:30, `RETRY EXIT: 0` | OK | N/A | NÃO ALTERADO |
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

## Referências

- Auditoria completa: `routines/README.md` (fonte operacional canônica, versionada)
- Contrato do endpoint `listar_calendario_stale`/`atualizar_calendario_emissor`:
  `api/src/worker.js`, função `listarEmissoresCalendarioStale` (comentário `CALVAL-V2 regra 9`)
- Script novo: `scripts/run_vixradar_agenda_semanal.ps1`
- Diário operacional: [[03 - Estado Atual]]
