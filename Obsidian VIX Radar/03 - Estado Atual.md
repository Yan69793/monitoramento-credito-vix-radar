---
data: 2026-08-02
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: saudavel
---

# Estado Atual — VIX Radar

> [!success] 02/08 20h18 — **Worker ok:true, verificador_ok:true. 4 guardas estruturais implementadas.** Pre-flight de ambiente (exit 6), probe WebSearch (exit 7), contador real de buscas + INCONCLUSIVO, parametro -Force para saida de dia envenenado. Monitor-Tasks le causa real em log. Export-Historico resolvido (token KV ok). Noturno 02/08 completo: 88/103 submit, 6 CRITICO (Rumo, Cosan, Oncoclinicas, GPA, Raizen, Kora Saude). Verificador async drenou 9 eventos (7 aprovados, 2 rejeitados, 255k tokens). Coleta-Volatilidade 5o dia consecutivo com exit 0. Export-Historico segue quebrado (token sem permissao Workers KV Storage). AgendaSemanal proximo disparo 22:00 hoje. Reconciliacao-CVM amanha 08:00.
> [!warning] 30/07 16h30 — **Worker ok:false, verificador_ok:false. Rotinas Claude paradas desde 29/07 10:00 por bug de OAuth no Task Scheduler.** Causa raiz encontrada e corrigida. Reprocessamento pendente.
> [!warning] 31/07 — **Incidente de API key 401.** Matinal e Noturno afetados. Emissores do dia ficaram com classificacao NENHUM. Causa raiz do 401 nao investigada (key simplesmente invalida naquele dia, voltou a funcionar 01/08).
## Recuperacao 30/07 a 02/08

### 30/07 — Correcao OAuth e primeiro reprocessamento

Apos a correcao dos 3 scripts as 16h30 (restauracao do `ANTHROPIC_API_KEY`), o sistema comecou a responder:

| Metrica | Valor |
|---|---|
| Worker health 16h22 | ok:false, verificador_ok:false |
| Worker health 17h42 (pos-correcao) | ok:true, verificador_ok:true |
| Matinal 16:12 (rerun manual) | sonnet-1 completo: Oncoclinicas CRITICO, Oi CRITICO, Kora Saude RELEVANTE, GPA RELEVANTE. 46k tokens. Processo interrompido apos lote 1 (4/18 emissores) |
| Noturno 18:00 | Completo. submit_ok=??, 3 CRITICO. Log de 83k, dreno verificador executado |
| Verificador async 16:29 | Fila 12, aprovados 9, rejeitados 3, 557k tokens. **verificador_ok flipou de false para true** |
| Verificador async 18:05 | Fila 12 (novos, do noturno), aprovados 11, rejeitados 1, 670k tokens. Fila zerada |
| Coleta-Volatilidade 17:02 | exit=0 (normalizada) |
| Export-Historico 01:46 | FALHOU: exit=0x1. **Nova falha, causa diferente.** |

### 31/07 — Incidente de API key 401

As rotinas do dia 31 foram afetadas por um incidente **diferente** do bug OAuth. O script detectou que a sessao OAuth estava expirada e caiu para pay-per-token, mas a API key em si estava invalida (401 API key is invalid). Todos os lotes Haiku e Sonnet falharam com 3 retries cada, e o fallback classificou os emissores como NENHUM com cobertura minima.

| Metrica | Valor |
|---|---|
| Matinal 10:00 | 19 emissores, 3 lotes (sonnet-1, sonnet-2, haiku-3). **Todos falharam com 401.** 0 analise real. Classificacao NENHUM para todos. |
| Noturno 18:00 | Iniciou 103 emissores. **Haiku-1 e Haiku-2 falharam com 401** (3 retries cada, 30 emissores com NENHUM). Script parece ter continuado com lotes restantes usando OAuth recuperada. |
| Coleta-Volatilidade 17:01 | exit=0 (normal) |
| Export-Historico 20:45 | FALHOU: mesmo erro de permissao KV Storage |
| Verificador async | Rodou mas metrics com 75 bytes (provavelmente fila vazia ou erro) |

**Causa raiz do 401, investigada 02/08:** O script tenta OAuth primeiro, falha, cai para `ANTHROPIC_API_KEY` obtida via `Get-AnthropicApiKey` (env var → registry User). Em 30/07 a key pay-per-token funcionou normalmente (momento da correcao OAuth). Em 31/07 a mesma key retornou 401. Em 01/08 e 02/08 o OAuth voltou a funcionar, entao o caminho da API key nao foi exercitado — nao sabemos se a key continua invalida ou foi um evento transitorio. [Risco] Se o OAuth expirar de novo, o sistema pode cair no mesmo 401. [Recomendacao] Validar a `ANTHROPIC_API_KEY` no registry e no env var, verificar creditos no console Anthropic, e considerar rodar `claude setup-token` para token longevo como backup do OAuth.

### 01/08 — Recuperacao parcial

| Metrica | Valor |
|---|---|
| **Matinal** | **NAO RODOU.** Sexta-feira dia util, deveria ter disparado 10:00. Sem log. Causa nao investigada. |
| Noturno 11:24 | Disparo duplo (11:24 e 11:26, colisao de trigger). Primeiro run abortou, segundo completou com OAuth funcional. 90k de log. submit_ok≈83, skip=20. Cobertura completa. |
| Verificador async 12:25 | Fila 7, aprovados 5, rejeitados 2, 230k tokens |
| Verificador async 18:02 | Fila vazia (zerada pelo run das 12:25) |
| Coleta-Volatilidade 17:02 | exit=0 |
| Export-Historico 20:45 | FALHOU: `CLOUDFLARE_API_TOKEN` sem permissao Workers KV Storage. **Erro persiste desde 30/07.** |

### 02/08 — Dia totalmente operacional

| Metrica | Valor |
|---|---|
| Worker health 19:00 | ok:true, verificador_ok:true, bindings todos true, providers 2/2. HTTP 200, 0,67s. |
| Noturno 18:00 | **Completo.** submit_ok=88, skip_ok=15, submit_fail=0, silent_fail=0. 494k tokens, 44min (2668s), 7 lotes (79 haiku + 9 sonnet). 6 CRITICO: Rumo (rebaixamento S&P brAAA→brAA+ CreditWatch negativo), Cosan (rebaixamento BB-→B+), Oncoclinicas, Pao de Acucar (GPA), Raizen, Kora Saude. |
| Verificador async 18:44 | **Completo.** Fila 9, aprovados 7, rejeitados 2, erros_parse 0, refusals 0. 255k tokens. Fila zerada. |
| Coleta-Volatilidade 17:01 | exit=0 (5o dia consecutivo normalizado) |
| Export-Historico 19:59 | **Resolvido.** Token Cloudflare atualizado (permissao Workers KV Storage concedida). Script corrigido para ler token do registry. Export 02/08 concluido: 103 emissores, 78 series, 4 arquivos, 199s, 0 avisos. |
| AgendaSemanal 22:00 | Pendente. Primeiro disparo apos falha de 27/07. |

> [!success] 28/07 23h33 — **Deploy v4.9.183 + v201.93.** Build deterministico, Merton/Selic corrigidos, CI fail-closed. Dia 28 totalmente operacional: matinal 14 submites (4 criticos), noturno 93 emissores, verificador async 2x (fila zerada, 1.5M tokens).
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

## Diagnostico 30/07 16h30 — Rotinas Claude paradas por OAuth expirado no Task Scheduler

**Causa raiz:** Tres scripts (`run_vixradar_matinal_claude.ps1`, `run_vixradar_noturno_claude.ps1`, `run_vixradar_verificacao_async.ps1`) apagavam `$env:ANTHROPIC_API_KEY` antes de invocar `claude -p`, forcando autenticacao OAuth. No Task Scheduler nao existe sessao interativa do desktop app — o token OAuth expira em ~24h e as rotinas morrem com exit 1 (stderr vazio) ou 0x40010004 (NativeCommandError). Padrao identico ao incidente de 27/07, mas a causa e diferente (nao era DeepSeek no settings.json).

**Correcao aplicada 30/07 ~16h30:** Descomentadas as 2 linhas que injetam `$env:ANTHROPIC_API_KEY` via `Get-AnthropicApiKey` (busca env var → registry User) e comentada a linha que nullificava. Pay-per-token restaurado, autenticacao passa a funcionar sem OAuth. Scripts alterados: matinal (linha 351-356), noturno (271-276), verificacao async (124-128). Sintaxe validada nos 3.

**O que ainda precisa acontecer:** Reprocessar a matinal de hoje (30/07, perdeu o disparo das 10:00) e o noturno de ontem (29/07, processou so 15 de ~93 emissores). O verificador async tambem nao rodou desde 28/07 10:38. A fila `radar:verif_fila:*` acumulou itens do noturno 29/07 (lote haiku-1, 15 emissores) e esta >12h stale, causando `verificador_ok:false`.

## Operacao 28/07 — Ultimo dia totalmente operacional

| Metrica | Valor |
|---|---|
| Worker | v4.9.182 (madrugada) / v4.9.183 (noite, deploy 23h33) |
| Frontend | v201.93 (deploy 21h53) |
| Matinal 28/07 10:00 | submit_ok=14, skip_ok=4, submit_fail=0, auth_fail=0, silent_fail=0, 165.672 tokens, 4 criticos (Oi, Raizen, Cosan, Rumo), 873s |
| Noturno 28/07 02:44 | 93 emissores processados (10 skip, ~83 analisados), 1 critico (Rumo — Moody's Ba3), metrics: submit_ok=0, skip_ok=10 |
| Verificador async 28/07 03:19 (pos-noturno) | Fila 8, aprovados 6, rejeitados 2, 581k tokens, shadow Fable 5: 1 comparacao, concordou |
| Verificador async 28/07 10:14 (pos-matinal) | Fila 17, aprovados 11, rejeitados 6, 949k tokens, shadow Fable 5: 3 comparacoes, 1 divergencia (fable_aprovou=0), teto 300k atingido |
| Noturno 28/07 18:00 (fallback) | Idempotente: tudo skip, 808 bytes de log |
| Coleta Volatilidade 28/07 17:01 | Log existe (284 bytes) |
| Export Historico 28/07 20:31 e 20:46 | Dois disparos, ambos com log |

## Operacao 29/07 — Inicio da falha em cascata

| Metrica | Valor |
|---|---|
| Matinal 29/07 10:00 | **FALHOU**: exit 0x1, log truncado com 9 linhas, morreu no lote sonnet-1, stderr 0 bytes |
| Coleta Volatilidade 29/07 17:00 | **FALHOU**: exit 0x1, log existe (414 bytes) mas Task Scheduler reporta falha |
| Noturno 29/07 18:00 | **FALHOU**: processou lote haiku-1 (15/15, 54k tokens, 0 criticos), morreu no haiku-2, exit 0x40010004. Stderr: “claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set” + NativeCommandError |
| Verificador async 29/07 | **NAO RODOU** — sem log |

## Operacao 30/07 — Falha continua (ate a correcao)

| Metrica | Valor |
|---|---|
| Export Historico 30/07 01:46 | **FALHOU**: exit 0x1 |
| Monitor-Tasks 30/07 07:00 | 8 erros detectados (4 VIX Radar + 3 Szuchmacher + 1 PME), exit 0x8. AgendaSemanal classificado incorretamente como “Credit balance too low” (bug P2 de 27/07 ativo) |
| Matinal 30/07 10:00 | **FALHOU**: exit 0x1, mesmo padrao — log com 9 linhas, morreu no lote sonnet-1, stderr 0 bytes |
| Health 30/07 16:22 | ok:false, verificador_ok:false (fila >12h ou quarentena no KV). Bindings saudaveis, admin_email_ok:true, providers 2/2 |

## Versoes

| Componente | Versao | Health |
|---|---|---|
| Worker | **v4.9.183** | `ok:false`, kv/rate_limiter/telemetria true, `admin_email_ok:true`, `verificador_ok:false`, providers 2/2. ok:false causado por verificador_ok:false (fila de verificacao >12h stale ou entrada de quarentena no KV). Bindings saudaveis. |
| Frontend | **v201.93** | `version.json` deployed_at 2026-07-28T21:53:12Z. Deploy junto com v4.9.183 no commit `12f2490`. |
| Git | v4.9.183 | main no commit `12f2490` (28/07). Working tree sujo: correcoes dos 3 scripts (OAuth→pay-per-token), skill files novos, volatilidade. PR #18 aberta. |

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

## Tasks Scheduler (estado real em 02/08 19h10 BRT)

| Task | Estado | LastRunTime (Scheduler) | Resultado | Proxima | Situacao |
|---|---|---|---|---|---|
| VIXRadar-Noturno | Ready | 02/08 18:00 | 0x0 (sucesso) | 03/08 18:00 | 88 submit + 15 skip, 6 criticos. Operacional. |
| VIXRadar-Matinal | Ready | 01/08 — | nao rodou | 03/08 10:00 | 01/08 nao disparou (sexta, dia util). Causa nao investigada. Proximo disparo 03/08. |
| VIXRadar-AgendaSemanal | Ready | 27/07 22:00 | 0x1 (falha) | 02/08 22:00 | Falhou 27/07 (DeepSeek no settings.json). Proximo disparo hoje 22:00. |
| VIXRadar-Coleta-Volatilidade | Ready | 02/08 17:00 | 0x0 (sucesso) | 03/08 17:00 | 5 dias consecutivos com exit 0. Normalizada. |
| VIXRadar-Export-Historico | Ready | 01/08 20:45 | 0x1 (falha) | 02/08 20:45 | Falhando desde 30/07: token sem permissao Workers KV Storage. |
| VIXRadar-Reconciliacao-CVM | Ready | nunca (1999) | 0x41303 | 03/08 08:00 | Nunca rodou desde recriacao em 27/07. Primeiro disparo real amanha. |
| VIXRadar-Verificacao-Async | Ready | 02/08 18:44 | 0x0 (sucesso) | 03/08 10:20 | Fila drenada (9 eventos, 7 aprovados). Operacional. |
| Monitor-Tasks | Ready | 02/08 07:00 | — | 03/08 07:00 | Funcionando. |

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
| Providers | 2/2 (Resend + Anthropic); OpenRouter probes removidos do health (OPENROUTERVIVO). **ANTHROPIC_API_KEY ativa (35 chars, confirmada no ambiente), mas scripts apagavam antes do claude -p — corrigido 30/07.** |

## Pendencias ativas (topo)

Ver [[PENDENCIAS.md]]. **Fila aberta: 10 itens acionaveis** (2 P1, 5 P2, 2 P3, 1 P4). Atualizado 27/07 13h30. Achado critico do dia: AgendaSemanal 03:00 e Matinal 10:00 falharam com mesmo padrao exit=1 ao invocar `claude -p`, processo morrendo com stderr de 0 bytes. Causa raiz confirmada e corrigida (roteamento DeepSeek no `settings.json`), ver analise de falha abaixo. [Validar] Noturno 18:00 e a confirmacao em escala.

## Checklist pos-rotina

Apos cada noturna (ou evento de producao significativo), verificar:

- [x] `03 - Estado Atual.md` — atualizado 02/08 19h10 (pos-Noturno, todas as rotinas)
- [x] `03a - Changelog.md` — atualizado 02/08 com noturnos 25-26/07 e 02/08
- [x] `03b - Infraestrutura.md` — tabela de gatilhos refeita 27/07 13h30 a partir do Scheduler
- [x] `00 - Indice (MOC).md` — atualizado 02/08 com status corrente
- [x] `CLAUDE.md` — atualizado com status de producao
- [x] `PENDENCIAS.md` — atualizado 02/08 com status real pos-recuperacao

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

## Guardas estruturais implementadas (02/08)

| Guarda | Exit | O que impede | Commits |
|---|---|---|---|
| Auth probe (chave paga) | 5 | Rotina iniciar com API key invalida (31/07) | `8f0b25b` |
| Pre-flight de ambiente | 6 | Agregador/modelo nao-Claude no env/settings.json (27/07) | `950f818` |
| Probe WebSearch | 7 | Buscas falhando silenciosamente, cobertura zero (27/07) | `41930d9` |
| Contador real de buscas | — | Modelo mentir sobre buscas, NENHUM com cobertura zero | `0c8d9ea` |
| INCONCLUSIVO (FULL + 0 buscas) | — | Dado nao verificavel entrar como classificacao | `0c8d9ea` |
| -Force (idempotencia) | — | Dia envenenado sem saida (27/07) | `75708fc` |
| Monitor: staleness | — | Task nao rodar e ninguem ver (01/08) | `8f0b25b` |
| Monitor: leitura real | — | Inventar causa de falha (Credit balance) | `e9068b8` |
| Export: pre-voo KV | 5 | Token sem permissao KV Storage (30/07-02/08) | `4bfab4e` |
| Export: token do registry | — | Env var herdado com token antigo | `4bfab4e` |

---

*Snapshot gerado em 2026-08-02 20h18 BRT (4 guardas estruturais implementadas). Dias 28/07 a 02/08 documentados. Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
