---
data: 2026-10-14
tipo: auditoria
tags: [vix-radar, rotinas, provider, retry, sentinela, reconciliacao, export]
status: aberto
---

# 108 - Finalizacao dos 6 problemas de 13/10 (FINAL-14OUT1) - 2026-10-14

Sessao de finalizacao a partir de `HEAD=origin/main=11f8a23`. Nada commitado, deployado,
agendado ou executado; nenhum token externo consumido; nenhum teto, cap, credencial ou
agendamento alterado. Estado detalhado e evidencias cruas em `status/ESTADO.md`; pendencias
com prioridade em [[PENDENCIAS]].

## Os seis problemas, causa e desfecho

| # | Problema | Causa comprovada | Desfecho |
|---|---|---|---|
| 1 | Codex sem fallback para OpenRouter | o provedor ativo e `codex` (medido: `VIXRADAR_LLM_PROVIDER` `User=[codex]`) e era o unico dos tres sentidos de failover sem desvio | CODEXFALLBACK-OR1 implementado em `vixradar-llm-provider.ps1` + varredura (matinal/noturna) + sentinela. **Inerte**: `VIXRADAR_CODEX_FALLBACK_PROVIDER` vazio |
| 2 | Noturna PARCIAL, retry `exit=6`, zero analise, mas `ENTREGA CONFIRMADA` | `Test-VixLedgerEntregueNaJanela` lia o `ledger analisados=` do DIA antes das contagens de execucao e ignorava `resultado=` | RETRY-COBERTURA1: contagens de execucao com precedencia + `resultado=FALHA` nunca e entrega + retry distingue `CONCLUIU SEM RECUPERAR` de entrega confirmada |
| 3 | Sentinela `exit=10` | orcamento do dia consumido (17.112 disponiveis contra 156.293 de custo por emissor): nenhum lote disparou e a execucao saiu `PARCIAL`, estado de "rodou e entregou parte" | ORCAMENTOFIN1: desfecho virou funcao pura `Get-VixSentinelaResultado`; trabalho zero + deferido por orcamento = `SEM_ORCAMENTO`/exit 0 |
| 4 | Reconciliacao CVM `exit=3` | `Invoke-WranglerKVPut` nao capturava o stdout do wrangler: o retorno era um ARRAY e `$kvCode -ne 0` dava verdadeiro sempre. O put deu `OK 200` (log do wrangler de 12/10) | KVOUTPUT1: stdout para arquivo, `return [int]$code`, `\| Out-Null` nos dois helpers. **Sem perda de dado** |
| 5 | Export `LastTaskResult=267014` | pre-voo do KV travou 26 min (20:45:12 -> 21:11:11) e o Agendador encerrou pela PT25M; o script sobreviveu, concluiu `FIM: ok` e commitou | KVTIMEOUT1 ja commitado em `11f8a23`; runtime pendente em 14/10 20:45 |
| 6 | Verificacao geral | - | Portao de verificacao ao vivo `HTTP:200`, `ok:true`, `sentry_ok:true`, `verificador_ok:true`, `feed_fresco:true`; repo e producao sem drift (`v4.9.266` / `v202.63`) |

## O que o HTTP 200 esconde (medido, nao inferido)

- `painel_fresco:true` mede a ESCRITA do estado, nao a analise concluida: em 14/10 as 04:29Z
  estava `true` com `painel_idade_min:454`, e a cobertura real do dia 13/10 foi 2 de 104.
  O campo que mede analise (`painel_analise_fresca`, ANALISEVSSCRITA1) esta no working tree e
  nao foi deployado.
- A Sentinela de 13/10 consumiu 302.888 do proprio limite diario (320.000) em DUAS execucoes,
  as duas anteriores ao cap de 170.000; as outras 9 execucoes do dia nao puderam disparar.

## Testes

`run-all-tests.ps1`: 51 suites, 49 verdes, 2 vermelhas do baseline declarado
(`test-headless-tools`, `test-preflight-429`). Suites novas/tocadas verdes em Windows
PowerShell 5.1 e pwsh 7: `test-codex-fallback-openrouter` 37/37, `test-reconciliacao-kvput`
16/16, `test-orcamento-sentinela` 67/67, `test-retry-janela` 46/46, `test-cobertura-analitica`
133/133, `test-sentinela-watchdog` OK, `test-vixfix-20261006` 30/30, `test-cobertura-escalada`
96/96, `test-varredura-defeitos` 50/50, `test-mva-failover-quota-backlog` 77/77,
`test-quota-esgotada-failclosed` 64/64. `lint-encoding` RISCO 0 (157 `.ps1` + 5 shell),
`check-claude-free` exit 0.

## PENDENTE_VALIDACAO_RUNTIME

Matinal 14/10 10:06, Sentinela 14/10 09:25, Export 14/10 20:45 e Reconciliacao CVM 19/10 12:00.
Nenhum resultado antecipado: o que valida e a execucao agendada, com o criterio declarado em
`status/ESTADO.md`.
