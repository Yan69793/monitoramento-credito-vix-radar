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

- **2026-07-16:** README reescrito — migração Claude Code Desktop → Windows Task Scheduler documentada. Horários e modelos corrigidos. `VIXRadar-AgendaSemanal` desabilitada.
- **2026-06-15:** Criação original — incidente de perda de registro do agendador Claude Desktop.
