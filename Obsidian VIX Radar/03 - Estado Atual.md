---
data: 2026-07-27
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 27/07 19h57 — **Worker v4.9.182 no ar. As duas guardas do ADMIN_EMAIL aplicadas.** (1) SECRETMISS1: `ADMIN_EMAIL` entra na condicao `_okHealth` e vira o campo publico `admin_email_ok`, validando formato e nao so presenca. Secret obrigatorio ausente passa a derrubar `ok:false` em vez de degradar em silencio, e como o `deploy-worker.ps1` aborta em `ok:false`, tambem trava deploy. Health pos-deploy: `ok:true`, `versao:v4.9.182`, `admin_email_ok:true`, 0,79s. Push `bce5ddc`. (2) `apply-security-rotation.ps1` ganhou o passo `[7/8]`, que roda `wrangler secret list` e aborta se faltar qualquer um dos 5 secrets obrigatorios, avisando sobre os 7 recomendados. Testado contra a saida real (19 secrets) e contra a ausencia simulada do `ADMIN_EMAIL`. Limite conhecido: nenhuma das duas vigia sozinha, dependem de alguem rodar o script ou ler o health. Detalhe: [[PENDENCIAS.md]].
> [!success] 27/07 18h01 — **Secret `ADMIN_EMAIL` restaurado. E-mail ao admin estava morto desde 24/07.** O commit `dfa6854` (rotacao Etapa 1) removeu `ADMIN_EMAIL` do `[vars]` do wrangler.toml e o secret nunca foi criado no Cloudflare. Como `var ADMIN_EMAIL = ""` nao tem valor reserva, todo e-mail ao admin lancava `"Sem destinatarios."` (telemetria confirma no cadastro de 25/07) e nenhum login recebia `role: "admin"` no JWT. O painel de aprovacao nao foi afetado porque autentica por `ADMIN_PASSWORD`, e foi por isso que passou 3 dias despercebido. Mesma raiz do drift do ADMIN_PASSWORD no GitHub Actions: a rotacao de 24/07 nao tem verificacao pos-fato de que cada destino ficou consistente. WhatsApp nunca falhou, 4 envios HTTP 201 em 30 dias. As duas guardas que faltavam foram aplicadas as 19h57, ver o callout acima.
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
| Worker | **v4.9.182** | `ok:true`, kv/rate_limiter/telemetria true, `admin_email_ok:true`, `verificador_ok:true`, providers 2/2 |
| Frontend | **v201.92** | `version.json` deployed_at 2026-07-27T15:43:21Z (12h43 BRT). Vault declarava v201.88 ate 20h; drift pego pelo `check-vault-drift.ps1`. O que mudou de v201.89 a v201.92 nao esta registrado em lugar nenhum do vault |
| Git | v4.9.182 | main sincronizado com o GitHub pelo deploy (`bce5ddc`, push ok). Working tree ainda sujo: guarda da rotacao, 2 workflows e shadow Fable 5 sem commit |

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

## Tasks Scheduler (estado real em 27/07 13h30 BRT, releitura direta da maquina)

| Task | Estado | LastRunTime (Scheduler) | Resultado | Proxima | Situacao |
|---|---|---|---|---|---|
| VIXRadar-Noturno | Ready | 26/07 18:00 | 0x0 (ok) | 27/07 18:00 | Teste real da correcao de roteamento em escala |
| VIXRadar-Matinal | Ready | 27/07 10:00 | 0x1 (falha) | 28/07 10:00 | Falhou as 10:00 ao invocar `claude -p`. Reexecutada manualmente 27/07 13:17, passou do ponto de morte |
| VIXRadar-AgendaSemanal | Ready | 27/07 03:00 | 0x1 (falha) | 27/07 22:00 | Log com 2 linhas, morreu ao invocar `claude -p`. Gatilho movido de seg 03h00 para seg 22h00 em 12h50 (`b6c8312`) |
| VIXRadar-Coleta-Volatilidade | Ready | nunca (1999) | 0x41303 | 27/07 17:00 | RECRIADA 27/07 12:23:51. Script corrigido: `pwsh` -> `powershell.exe` |
| VIXRadar-Export-Historico | Ready | nunca (1999) | 0x41303 | 27/07 20:45 | RECRIADA 27/07 12:23:58 |
| VIXRadar-Reconciliacao-CVM | Ready | nunca (1999) | 0x41303 | 03/08 08:00 | RECRIADA 27/07 12:24:08. Gatilho e seg 08h00, nao 12h32 |
| Monitor-Tasks | Ready | 27/07 07:00 | 0x7 | 28/07 07:00 | Existe e funciona. `0x7` e a **contagem de erros achados**, nao codigo de falha |
| VIXRadar-Verificacao-Async | nao e task | 26/07 18:53 | exit 0 | inline | Executa inline pos-noturno e pos-matinal. Nunca foi registrada |
| VIXRadar-Ranking-Mensal | nao existe | nunca | N/A | nenhuma | Confirmado ausente na listagem completa da raiz. Decisao pendente (P3) |

**Leia a coluna LastRunTime com cuidado.** Para as 3 tasks recriadas o Scheduler reporta
30/11/1999 e `0x41303` (SCHED_S_TASK_HAS_NOT_RUN) porque **re-registrar zera o historico da
task**, nao porque a rotina nunca rodou. Os logs em `logs\routines\` mostram execucoes reais
ate 23/07 (Coleta), 22/07 (Export) e 21/07 (Reconciliacao). Scheduler e log sao duas fontes
diferentes: a task e nova, a rotina nao e.

**Origem dos carimbos de recriacao:** `CreationTime` do arquivo XML em `C:\Windows\System32\Tasks\<nome>`,
que e reescrito a cada registro. Nao e estimativa.

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok (health 27/07: kv:true) |
| RATE_LIMITER_DO | ok (health 27/07: rate_limiter:true) |
| RADAR_USAGE_EVENTS | ok (health 27/07: telemetria:true) |
| ESTADO_SEMANA_DO | declarado no `wrangler.toml` + usado no bundle (nao exposto no health publico) |
| Providers | 2/2 (Resend + Anthropic); probes OpenRouter removidos do health (OPENROUTERVIVO) |

## Pendencias ativas (topo)

Ver [[PENDENCIAS.md]]. **Fila aberta: 10 itens acionaveis** (2 P1, 5 P2, 2 P3, 1 P4). Atualizado 27/07 13h30. Achado critico do dia: AgendaSemanal 03:00 e Matinal 10:00 falharam com mesmo padrao exit=1 ao invocar `claude -p`, processo morrendo com stderr de 0 bytes. Causa raiz confirmada e corrigida (roteamento DeepSeek no `settings.json`), ver analise de falha abaixo. [Validar] Noturno 18:00 e a confirmacao em escala.

## Checklist pos-rotina

Apos cada noturna (ou evento de producao significativo), verificar:

- [x] `03 - Estado Atual.md` — atualizado 27/07 13h30 (releitura do Scheduler)
- [ ] `03a - Changelog.md` — atualizar com noturnos 25 e 26/07
- [x] `03b - Infraestrutura.md` — tabela de gatilhos refeita 27/07 13h30 a partir do Scheduler
- [x] `00 - Indice (MOC).md` — pendente atualizar com dados deste diagnostico
- [x] `CLAUDE.md` — tabela Producao em v4.9.181 / v201.88 (sem alteracao)
- [x] `PENDENCIAS.md` — atualizado 27/07 13h30 (itens de task sincronizados com a realidade)

**Regra de sincronia (nova, 27/07):** mexeu em task do Scheduler, atualiza `03b - Infraestrutura`
**e** varre `PENDENCIAS.md` por item que afirme estado dessa task. Foi a falta disso que
deixou "task removida" escrito em cima de task viva por uma hora.

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

**Tasks removidas e recriadas em 27/07 (3):** VIXRadar-Coleta-Volatilidade (12:23:51),
VIXRadar-Export-Historico (12:23:58), VIXRadar-Reconciliacao-CVM (12:24:08). O carimbo
"~12:09" que constava aqui era o horario **da auditoria**, nao o do registro. Corrigido em
13h30 com o `CreationTime` real do XML de cada task.

**Health Worker (27/07 12:09 BRT):** ver portao de verificacao abaixo.

### Analise de falha: AgendaSemanal 03:00 + Matinal 10:00

Ambas falharam com **mesmo padrao**: processo morre ao invocar `claude -p`, sem erro no stderr, sem linha de erro no log.

- **AgendaSemanal** (`run_claude_routine.ps1`): log tem 2 linhas (cleanup + INICIO). Sem linha "CLAUDE:" e sem "ERRO:". Processo morreu durante `$fullPrompt | & claude @claudeArgs 2>&1`.
- **Matinal** (`run_vixradar_matinal_claude.ps1`): log tem 8 linhas, para em "Lote sonnet-1 [claude-sonnet-4-6]: Oncoclinicas, Oi, Kora Saude, Pão de Açúcar (GPA)". Funcao `Invoke-ClaudeBatch` chamou `claude -p` com `--output-format json`, stderr redirecionado para arquivo (vazio, 0 bytes).
- **Probe 12:09**: `claude -p "pong"` respondeu normalmente com Sonnet. CLI funcional.
- ~~**[Hipotese]** Erro transitorio de autenticacao/quota na API Anthropic via OAuth.~~
  **DESCARTADA em 27/07 13h.** O probe das 12:09 rodou em sessao interativa, que carrega o
  override de base URL do app desktop. Nao reproduzia a condicao do agendador.
- **[Fato] Causa raiz confirmada:** `~/.claude/settings.json` recebeu em 26/07 17:59 um bloco
  `env` de roteamento DeepSeek com todos os aliases de modelo trocados. Em runtime a base URL
  voltava para a Anthropic (sobrescrita pelo app), sobrando nomes de modelo DeepSeek batendo
  num endpoint que nao os conhece. Processos do Scheduler leem o `settings.json` sem esse
  override, entao `claude -p` morria com stderr de 0 bytes. Monitor-Tasks das 07:00, a unica
  rotina que nao usa `claude -p`, rodou normal. E isso que isola a causa.
- **[Fato] Correcao e validacao:** bloco removido, backup em `settings.json.bak-20260727`.
  Probe em processo limpo, com `ANTHROPIC_*` e `CLAUDE_CODE_SUBAGENT_MODEL` apagados,
  dependendo so do arquivo: exit 0. Matinal reexecutada 27/07 13:17 passou de `Lote sonnet-1`
  com `ok=4|fail=0`, exatamente a linha onde morria as 10:00.
- **[Validar]** Noturno 27/07 18:00 e o teste em escala (103 emissores, `Invoke-ClaudeBatch`).

### Divergencias vault vs realidade (antes da correcao)

1. Vault dizia que AgendaSemanal nunca executou (LastRun 1999). [Fato] Executou 27/07 03:00, falhou exit=1.
2. Vault dizia que Monitor-Tasks estava REMOVIDA. [Fato] Task estava Ready, rodou 07:00 com exit=7.
3. Vault dizia que Matinal nunca executou (LastRun 1999). [Fato] Executou 27/07 10:00, falhou exit=1.
4. Vault listava 5 tasks removidas. [Fato] Eram 4: Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM, Ranking-Mensal. Monitor-Tasks ja estava recriada.
5. Vault dizia fila de pendencias com 8 itens. [Fato] Apos auditoria: 2 fechados, 2 novos, 10 abertos.

### Releitura 27/07 13h30: "o vault diz removidas, mas elas existem"

Divergencia levantada apos a auditoria. **Resolvida: as tasks foram recriadas depois, o
diagnostico da madrugada estava certo quando foi escrito.** Nao houve erro de diagnostico.

Linha do tempo, cada carimbo medido e nao inferido:

| Hora | Evento | Fonte |
|---|---|---|
| 27/07 01:39 | Diagnostico da madrugada registra as tasks como removidas | commit `76720a7` |
| 27/07 12:09 | Auditoria confirma ausencia das 3 no Scheduler | `03 - Estado Atual` |
| 27/07 12:23:51 | `VIXRadar-Coleta-Volatilidade` registrada | `CreationTime` do XML |
| 27/07 12:23:58 | `VIXRadar-Export-Historico` registrada | `CreationTime` do XML |
| 27/07 12:24:08 | `VIXRadar-Reconciliacao-CVM` registrada | `CreationTime` do XML |
| 27/07 12:29 | Recriacao commitada | commit `04a8fef` |

O que ficou errado nao foi o diagnostico, foi a **propagacao**: `03 - Estado Atual` foi
atualizado com a recriacao, `PENDENCIAS.md` nao. Os itens la continuaram dizendo "task
removida" em cima de tasks vivas, com um deles se contradizendo no mesmo paragrafo. Quem
lesse a fila de pendencias iria recriar task que ja existe.

**Causa raiz:** duas notas descrevem o mesmo estado do Scheduler e nada as amarra. A
atualizacao de uma nao obriga a da outra.
**Guarda:** `03b - Infraestrutura` passa a ser a unica tabela de gatilhos, derivada do
`Get-ScheduledTask`, e `PENDENCIAS.md` deve citar situacao de task por referencia a ela em
vez de reafirmar estado por conta propria. Item de checklist adicionado abaixo.

**Nao apuravel:** o que removeu as tasks entre 23 e 24/07 continua sem explicacao. O log
`Microsoft-Windows-TaskScheduler/Operational` esta com `IsEnabled=False` nesta maquina, ou
seja nao existe registro de evento 141 para consultar. A acao de investigacao que constava
em `PENDENCIAS.md` esta encerrada por impossibilidade, nao por conclusao.

### Impacto acumulado

- **AgendaSemanal**: 0 emissores atualizados. Calendario de resultados stale desde 21/07 (6 dias). Top 20 por resultado proximo desatualizado.
- **Matinal**: 0 dos 15 emissores top-EWS processados. Cobertura matinal parada desde 23/07 (4 dias uteis).
- **Coleta-Volatilidade**: Scores de volatilidade desatualizados desde 23/07 (4 dias, 1 dia util).
- **Export-Historico**: Backups diarios parados desde 22/07 (5 dias).
- **Reconciliacao-CVM**: Sem reconciliacao desde 21/07 (6 dias). Dados podem divergir dos protocolos CVM sem deteccao.

---

*Snapshot gerado em 2026-07-27 12h09 BRT (auditoria completa, pos-falha Matinal), revisado em
13h30 BRT com releitura direta do Scheduler: carimbos de recriacao corrigidos, hipotese de
quota/OAuth descartada e substituida pela causa raiz confirmada, tabela de tasks refeita.
Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
