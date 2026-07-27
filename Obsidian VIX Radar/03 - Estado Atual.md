---
data: 2026-07-27
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!warning] 27/07 12h09 — **Auditoria de rotinas: AgendaSemanal 03:00 exit=1, Matinal 10:00 exit=1. Ambas falharam ao invocar `claude -p`. Probe 12:09 mostra CLI funcional — bloqueio foi transitorio.** 3 tasks recriadas (Reconciliacao-CVM, Coleta-Volatilidade, Export-Historico). Worker saudavel. Risco imediato: Noturno 18:00 repetir falha. Detalhe: [[03 - Estado Atual#Diagnostico 27-07 12h09|Diagnostico 27/07 12h09]].
> [!success] 26/07 18h53 — **Noturno 26/07: submit_ok=90, skip_ok=13, submit_fail=0, 396.230 tokens, 3 criticos.** Criticos: Arteris, Oi, Oncoclinicas. Dreno verificacao async exit 0: fila 9, aprovados 6, rejeitados 3, 505.919 tokens. Shadow Fable 5: 1 comparacao (Arteris), ambos APROVADO, teto 300k atingido no lote 2 (319.582 acumulado).
> [!success] 25/07 18h56 — **Noturno 25/07: submit_ok=91, skip_ok=12, submit_fail=0, 377.238 tokens, 5 criticos.** Criticos: Aegea Saneamento, Kora Saude, Oi, Oncoclinicas, Raizen. Dreno verificacao async exit 0: fila 13, aprovados 8, rejeitados 5, 505.935 tokens.
> [!success] 26/07 — **Shadow mode Fable 5 ativado (piloto).** `Invoke-FableShadow` em `scripts/run_vixradar_verificacao_async.ps1`: chamada Fable 5 em paralelo ao Sonnet para eventos CRITICO, sem alterar veredicto real. Teto 300k tokens/execucao. Zero mudancas no Worker. Dados em `logs/routines/verificacao_fable_shadow_*.json`. Criterio DOCBILL1: revisao manual apos 2-4 semanas. Ver [[PENDENCIAS.md]] (SHADOW1, DOCBILL1).
> [!success] 25/07 16h00 — **Worker v4.9.181 + Frontend v201.88. Fila PENDENCIAS zerada.** v4.9.181: email_enviar (apresentacao Igor/Bradesco BBI), VERSAO3X fix (WORKER_VERSAO agora bate com nome do arquivo), guard no deploy-worker.ps1 (rejeita deploy se WORKER_VERSAO divergir do filename). Health: `ok:true`, `versao:v4.9.181`, 802ms. Cron 7132d3dd (27/07 09:57 BRT) agora coberto. Auditoria geral: [[67 - Auditoria Geral 2026-07-25]]. Detalhe: [[03a - Changelog]], [[PENDENCIAS.md]].
> [!success] 24/07 18h14 — **Noturno 24/07: submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens, 6 criticos.** Criticos: CSN, Kora Saude, Oi, Oncoclinicas, Pao de Acucar (GPA), Raizen. Dreno verificacao async exit 0: fila 14, aprovados 13, rejeitados 1, erros_parse 0, ~636k tokens.
> [!warning] 24/07 — **Matinal 24/07 nao disparou.** Task VIXRadar-Matinal foi recriada em 24/07 as 10:00 (StartBoundary do trigger). 24/07 era sexta-feira, dia util. O vault anterior registrava “fim de semana” incorretamente. Primeiro disparo da task recriada previsto para 27/07 as 10:00.
> [!success] 24/07 — **LOGLOCK1-REC resolvido.** Causa raiz: `FILE_ATTRIBUTE_PINNED` em 6177 itens (OneDrive). Flag removido + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID no `Write-Log` das 4 rotinas.
> [!success] 23/07 — Frontend v201.84: preview de link com `og:image` (1200x630). Worker v4.9.171–172 e FE v201.85 (FOCUSTRAP1) na cadeia do dia 23; superados pelo deploy 24/07.
> [!success] 23/07 10h15 — **Boletim diario reativado** (`RELATORIO_DIARIO_ENABLED` + `EMAIL_ALERTAS_ENABLED` no `[vars]`).
> [!info] 23/07 08h30 — Dashboard com eventos ate 21/07 naquele momento era ausencia de noticias novas, nao falha de ingestao (revalidar se o painel parecer “parado”).

## Versoes

| Componente | Versao | Health |
|---|---|---|
| Worker | **v4.9.181** | `ok:true`, kv/rate_limiter/telemetria true, `verificador_ok:true`, providers 2/2 |
| Frontend | **v201.88** | `CACHE_VERSION=v201.88`, `version.json` deployed_at 2026-07-24T22:01:35Z |
| Git | v4.9.181 | main, 4 arquivos modificados (shadow mode Fable 5, sem commit), working tree dirty |

## Cobertura

| Metrica | Valor |
|---|---|
| Emissores | 103 (universo) |
| Noturno 26/07 | submit_ok=90, skip_ok=13, submit_fail=0, 396.230 tokens (meta 500k, hard 700k sem hit), 3 criticos, ~41 min, dreno verif ok |
| Verificacao async 26/07 (pos-noturno) | fila 9, aprovados 6, rejeitados 3, erros_parse 0, refusals 0, 505.919 tokens, exit 0. Shadow Fable 5: 1 comparacao, concordou, teto 300k atingido |
| Noturno 25/07 | submit_ok=91, skip_ok=12, submit_fail=0, 377.238 tokens, 5 criticos, ~46 min, dreno verif ok |
| Verificacao async 25/07 (pos-noturno) | fila 13, aprovados 8, rejeitados 5, erros_parse 0, refusals 0, 505.935 tokens, exit 0 |
| Noturno 24/07 | submit_ok=103, skip_ok=0, submit_fail=0, 488.116 tokens (meta 500k, hard 700k sem hit), 6 criticos, ~51 min, dreno verif ok |
| Matinal 27/07 | FALHOU: exit=1, log truncado apos "Lote sonnet-1" (8 linhas), stderr vazio. 0 emissores processados |
| AgendaSemanal 27/07 | FALHOU: exit=1, log com 2 linhas (cleanup + INICIO), stderr vazio. 0 processado |
| Matinal 23/07 | submit_ok=15 (top 15 por EWS), 5 criticos, 150.912 tokens, dreno verif ok |
| Criticos noturno 26/07 | Arteris, Oi, Oncoclinicas |
| Criticos noturno 25/07 | Aegea Saneamento, Kora Saude, Oi, Oncoclinicas, Raizen |
| Criticos noturno 24/07 | CSN, Kora Saude, Oi, Oncoclinicas, Pao de Acucar (GPA), Raizen |

## Tasks Scheduler (estado real em 27/07 12h09 BRT, pos-auditoria e recriacao)

| Task | Estado | Ultima execucao | Resultado | Situacao |
|---|---|---|---|---|
| VIXRadar-Noturno | Ready | 26/07 18:00 | 0x0 (ok) | Proximo: 27/07 18:00. [Risco] pode falhar com mesmo padrao exit=1 |
| VIXRadar-Matinal | Ready | 27/07 10:00 | 0x1 (falha) | Morreu ao invocar claude -p. Log truncado apos "Lote sonnet-1". stderr vazio. Proximo: 28/07 10:00 |
| VIXRadar-AgendaSemanal | Ready | 27/07 03:00 | 0x1 (falha) | Log com 2 linhas, morreu ao invocar claude -p. Proximo: 03/08 03:00 |
| VIXRadar-Verificacao-Async | N/A (inline) | 26/07 18:53 | exit 0 | Executa inline pos-noturno e pos-matinal |
| VIXRadar-Coleta-Volatilidade | Ready | 23/07 17:02 | ultimo log ok | RECRIADA 27/07 ~12:09. Proximo: 28/07 17:00 |
| VIXRadar-Export-Historico | Ready | 22/07 20:47 | ultimo log ok | RECRIADA 27/07 ~12:09. Proximo: 27/07 20:45 |
| VIXRadar-Reconciliacao-CVM | Ready | 21/07 12:31 | ultimo exit 1 | RECRIADA 27/07 ~12:09. Proximo: 03/08 08:00 (segunda) |
| VIXRadar-Ranking-Mensal | REMOVIDA | Nunca | N/A | Decisao pendente: implementar ou remover de vez (P3) |
| Monitor-Tasks | Ready | 27/07 07:00 | 0x7 (funcional) | RECRIADA e funcional. Escaneou 12 tasks. Proximo: 28/07 07:00 |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok (health 27/07: kv:true) |
| RATE_LIMITER_DO | ok (health 27/07: rate_limiter:true) |
| RADAR_USAGE_EVENTS | ok (health 27/07: telemetria:true) |
| ESTADO_SEMANA_DO | declarado no `wrangler.toml` + usado no bundle (nao exposto no health publico) |
| Providers | 2/2 (Resend + Anthropic); probes OpenRouter removidos do health (OPENROUTERVIVO) |

## Pendencias ativas (topo)

Ver [[PENDENCIAS.md]]. **Fila aberta: 10 itens acionaveis** (2 P1, 5 P2, 2 P3, 1 P4). Atualizado 27/07 12h09 pos-auditoria. Achado critico: AgendaSemanal 03:00 e Matinal 10:00 falharam com mesmo padrao exit=1 ao invocar `claude -p`. Padrao consistente: processo morre sem erro no stderr, CLI funcional em probe manual 12:09. [Risco] Noturno 18:00 pode repetir.

## Checklist pos-rotina

Apos cada noturna (ou evento de producao significativo), verificar:

- [x] `03 - Estado Atual.md` — atualizado 27/07 12h09 (auditoria completa pos-matinal)
- [ ] `03a - Changelog.md` — atualizar com noturnos 25 e 26/07
- [ ] `03b - Infraestrutura.md` — so se mudou binding/cron (sem mudanca de binding)
- [x] `00 - Indice (MOC).md` — pendente atualizar com dados deste diagnostico
- [x] `CLAUDE.md` — tabela Producao em v4.9.181 / v201.88 (sem alteracao)
- [x] `PENDENCIAS.md` — atualizado 27/07 12h09 (2 itens fechados, novos achados)

Script de drift: `pwsh ./scripts/check-vault-drift.ps1` compara vault contra health ao vivo e reporta divergencias. Execute apos cada deploy ou se suspeitar de desalinhamento.

---

## Diagnostico 27/07 12h09 (auditoria completa)

Auditoria somente leitura executada em 27/07 apos falha da Matinal 10:00. Cobriu Scheduler state, logs, health check, CLI probe.

### Metodo

- `Get-ScheduledTask` + `Get-ScheduledTaskInfo` para VIXRadar-* e Monitor-*
- Leitura de `logs\routines\vixradar-agenda-semanal_20260727.log`, `logs\routines\vixradar-matinal_20260727.log`, `logs\routines\matinal_stderr_20260727_2888.txt`
- Leitura de `logs\monitor-tasks\monitor_20260727.log` e `erros_20260727.json`
- Health check do Worker com `curl.exe`
- Probe `claude -p` com modelo Sonnet e default

### Evidencias

**Tasks existentes (4):**
```
VIXRadar-AgendaSemanal  Ready  LastRun 27.jul.2026 03:00:00  0x1  NextRun 03.ago.2026 03:00:00
VIXRadar-Matinal        Ready  LastRun 27.jul.2026 10:00:00  0x1  NextRun 28.jul.2026 10:00:00
VIXRadar-Noturno        Ready  LastRun 26.jul.2026 18:00:01  0x0  NextRun 27.jul.2026 18:00:00
Monitor-Tasks           Ready  LastRun 27.jul.2026 07:00:00  0x7  NextRun 28.jul.2026 07:00:00
```

**Tasks removidas e recriadas em 27/07 ~12:09 (3):** VIXRadar-Coleta-Volatilidade, VIXRadar-Export-Historico, VIXRadar-Reconciliacao-CVM.

**Health Worker (27/07 12:09 BRT):** ver portao de verificacao abaixo.

### Analise de falha: AgendaSemanal 03:00 + Matinal 10:00

Ambas falharam com **mesmo padrao**: processo morre ao invocar `claude -p`, sem erro no stderr, sem linha de erro no log.

- **AgendaSemanal** (`run_claude_routine.ps1`): log tem 2 linhas (cleanup + INICIO). Sem linha "CLAUDE:" e sem "ERRO:". Processo morreu durante `$fullPrompt | & claude @claudeArgs 2>&1`.
- **Matinal** (`run_vixradar_matinal_claude.ps1`): log tem 8 linhas, para em "Lote sonnet-1 [claude-sonnet-4-6]: Oncoclinicas, Oi, Kora Saude, Pão de Açúcar (GPA)". Funcao `Invoke-ClaudeBatch` chamou `claude -p` com `--output-format json`, stderr redirecionado para arquivo (vazio, 0 bytes).
- **Probe 12:09**: `claude -p "pong"` respondeu normalmente com Sonnet. CLI funcional.
- **[Hipotese]** Erro transitorio de autenticacao/quota na API Anthropic via OAuth do Claude Code. A CLI tenta login OAuth, falha silenciosamente, e o wrapper PowerShell interpreta saida vazia + exit code do processo como falha.
- **[Risco]** Noturno 18:00 usa `run_vixradar_noturno_claude.ps1` com `Invoke-ClaudeBatch` — mesma funcao que falhou na Matinal. Se a condicao que causou o bloqueio entre 03:00 e 10:00 voltar, a Noturno falha tambem.

### Divergencias vault vs realidade (antes da correcao)

1. Vault dizia que AgendaSemanal nunca executou (LastRun 1999). [Fato] Executou 27/07 03:00, falhou exit=1.
2. Vault dizia que Monitor-Tasks estava REMOVIDA. [Fato] Task estava Ready, rodou 07:00 com exit=7.
3. Vault dizia que Matinal nunca executou (LastRun 1999). [Fato] Executou 27/07 10:00, falhou exit=1.
4. Vault listava 5 tasks removidas. [Fato] Eram 4: Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM, Ranking-Mensal. Monitor-Tasks ja estava recriada.
5. Vault dizia fila de pendencias com 8 itens. [Fato] Apos auditoria: 2 fechados, 2 novos, 10 abertos.

### Impacto acumulado

- **AgendaSemanal**: 0 emissores atualizados. Calendario de resultados stale desde 21/07 (6 dias). Top 20 por resultado proximo desatualizado.
- **Matinal**: 0 dos 15 emissores top-EWS processados. Cobertura matinal parada desde 23/07 (4 dias uteis).
- **Coleta-Volatilidade**: Scores de volatilidade desatualizados desde 23/07 (4 dias, 1 dia util).
- **Export-Historico**: Backups diarios parados desde 22/07 (5 dias).
- **Reconciliacao-CVM**: Sem reconciliacao desde 21/07 (6 dias). Dados podem divergir dos protocolos CVM sem deteccao.

---

*Snapshot gerado em 2026-07-27 ~12h09 BRT (auditoria completa, pos-falha Matinal). Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
