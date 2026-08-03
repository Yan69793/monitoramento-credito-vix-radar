# Rotinas Operacionais — VIX Radar (fonte canônica versionada)

> **Atualizado 2026-07-16.** As rotinas são executadas pelo **Windows Task Scheduler**
> via scripts PowerShell (`scripts/run_vixradar_*.ps1`), não mais pelo sistema de
> scheduled tasks do Claude Code Desktop (neutralizado em 08/07/2026 após incidente
> de duplicata e perda silenciosa de registro em reinstalações).
>
> Os arquivos `SKILL.md` nesta pasta são **referência documental e templates de prompt**
> usados pelos scripts. A Task Scheduler é a fonte de verdade para agendamento;
> os SKILL.md são a fonte de verdade para o contrato analítico.

## Tasks ativas no Windows Task Scheduler

| Task | Gatilho | Script | Função |
|------|---------|--------|--------|
| `VIXRadar-Matinal` | Seg-Sex 10h00 BRT | `run_vixradar_matinal_claude.ps1` | Top 15 por EWS, Haiku (lotes 6) + Sonnet (EWS>=38, lotes 4) |
| `VIXRadar-Noturno` | Diário 18h00 BRT | `run_vixradar_noturno_claude.ps1` | 103/103 emissores, Haiku primeiro (lotes 15) + Sonnet depois (lotes 11) |
| `VIXRadar-Verificacao-Async` | Diário 10:20 BRT | `run_vixradar_verificacao_async.ps1` | Dreno da fila `radar:verif_fila:{data}` (também acionado inline pós-matinal e pós-noturno) |
| `VIXRadar-Export-Historico` | Diário 20:45 BRT | `run_vixradar_export_historico.ps1` | Exporta estado preditivo do KV para `data/historico/` |
| `VIXRadar-Ranking-Mensal` | Dia 1, 11:30 BRT | `run_vixradar_ranking_mensal.ps1` | Monitor mensal de ranking SEO |
| ~~`VIXRadar-AgendaSemanal`~~ | ~~Dom 03:00~~ | ~~`run_claude_routine.ps1`~~ | **Desabilitada 16/07/2026** — skill neutralizada desde 14/07, task ficou ativa por omissão |
| `Szuchmacher-AgendaMacro-Claude` | Sex 07:07 BRT | `run_claude_routine.ps1 -RoutineId atualizar-agenda-macro-szuchmacher` | Calendário macro semanal de szuchmacher.com.br. Religada 02/08/2026 — motivo original do desligamento (14/07, disparo fantasma via cron interno do skill) deixou de existir em 08/07 quando o sistema de cron interno inteiro foi aposentado (ver histórico abaixo); ficou desligada por omissão até esta investigação, sem decisão registrada. Deploy exige aprovação humana explícita (SKILL.md Passo 6) — o pior caso de falha é a rotina parar pedindo aprovação, nunca publicar sozinha. |

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

As tasks do Windows são registradas via `Register-ScheduledTask` ou `schtasks /create`.
Consulte os scripts em `scripts/` para os comandos exatos de cada task.
Após recriar, validar com `Get-ScheduledTask -TaskName "VIXRadar-*"` e
registrar no Obsidian (`03 - Estado de Produção.md`).

## Histórico de mudanças

- **2026-08-02:** `Szuchmacher-AgendaMacro-Claude` religada (`Enable-ScheduledTask`). Investigação disparada por `monitor-tasks.ps1` acusando `LastTaskResult=267011` (nunca rodou) com `LastRunTime` no sentinela 1999. Causa raiz: task ficou `Enabled:False` desde a janela de endurecimento de 14–16/07 (mesmo padrão aplicado à `VIXRadar-AgendaSemanal`, ver linha acima), motivo documentado na frontmatter do próprio `SKILL.md` (disparo fantasma via cron interno). Esse cron interno foi aposentado por completo em 08/07 (ver nota abaixo) — o risco que motivou o desligamento não existe mais desde então, mas ninguém religou a task nos 19 dias seguintes, e ela nunca entrou nesta tabela. Nota: a instrução de reativação escrita no próprio SKILL.md ("restaurar cron 7 7 \* \* 5") está obsoleta — refere-se ao mecanismo de cron interno já morto; hoje `Enable-ScheduledTask` no Windows Task Scheduler é suficiente e é o único gatilho real.
- **2026-07-16:** README reescrito — migração Claude Code Desktop → Windows Task Scheduler documentada. Horários e modelos corrigidos. `VIXRadar-AgendaSemanal` desabilitada.
- **2026-06-15:** Criação original — incidente de perda de registro do agendador Claude Desktop.
