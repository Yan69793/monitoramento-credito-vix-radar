---
data: 2026-10-14
tipo: auditoria
tags: [vix-radar, deploy, seguranca, provider, retry, sentinela, testes, producao]
status: fechado
---

# 109 - Publicacao das correcoes validadas (PUBLICACAO-14OUT1) - 2026-10-14

Sessao de fechamento a partir de `HEAD=origin/main=11f8a23` (checkpoint FINAL-14OUT1).
Escopo: fechar os itens que dependiam de codigo, publicar o Worker pelo fluxo oficial e
validar em producao. Nada de auditoria reiniciada, nenhum token de rotina consumido, nenhum
teto, cap, agendamento ou credencial alterado. Evidencia crua em `status/ESTADO.md`;
fila de acoes em [[PENDENCIAS]].

## O que foi publicado

| Item | Estado antes | Estado depois | Prova |
|---|---|---|---|
| RLADMIN4 (rate limit no formulario `admin_mercado`) | no working tree, nao deployado | **em producao** (`v4.9.267`) | 4 POSTs `form-urlencoded` com senha errada no mesmo IP: `200`, `200`, `200`, **`429` com `_rate_limit.camada=burst`, `retry_after_sec=60`** |
| CODEXFALLBACK-OR1 nas 5 rotinas | 3 das 5 (varredura matinal/noturna + sentinela) | **5 de 5** (faltavam `verificacao_async` e `agenda_semanal`) | `test-codex-fallback-openrouter` 58/58, Parte 4 nova com as duas pontas |
| RETRY-COBERTURA1, ORCAMENTOFIN1, KVOUTPUT1 | implementados, nao publicados | **publicados** | `test-retry-janela` 46/46, `test-orcamento-sentinela` 67/67, `test-reconciliacao-kvput` 16/16 |
| `test-preflight-429.ps1` | VERMELHA (baseline desde 12/09) | **VERDE 48/48** | causa real: sonda classificava o reset do 429 contra o relogio real e o preflight decidia esperar com relogio injetado (41 dias de diferenca medidos) |
| `test-headless-tools.ps1` | VERMELHA (baseline desde 12/09) | **VERDE 19/19** | causa real: o `param` de `Test-VixHeadlessTools` estava depois de um `if`; no PowerShell 5.1 a assinatura nao existia e a funcao rodava sem os argumentos |
| `scripts/tests-baseline.json` | 2 falhas declaradas | **baseline vazio** | as duas suites ficaram verdes; remocao por edicao explicita |

## Producao (medida, nao inferida)

- `versao: v4.9.267`, `ok:true`, `kv:true`, `rate_limiter:true`, `telemetria:true`,
  `sentry_ok:true`, `verificador_ok:true`, `admin_email_ok:true`, `cvm_fonte_ok:true`,
  `feed_fresco:true`, `painel_fresco:true`.
- Campos novos vivos no health (prova de que o bundle publicado os tem):
  `verif_fila_pendentes:0`, `verif_fila_mais_antiga_h:0`, `verif_fila_atrasada:false`,
  `api_disponivel:true`, `painel_analise_fresca:true`,
  `painel_ultima_analise_em:2026-10-14T04:35:04.523Z`, `painel_emissores_deferidos:85`.
- `cvm_ingestao_linhas_fonte`/`aceitos`/`ignorados`/`identidade_ok` = `null`: a meta do sync
  ainda e legado (a identidade independente so existe depois de um sync com o writer novo).
  `null` e o resultado correto - a regra e nunca verde falso; o proximo sync da CVM popula.
- POST anonimo em acao mutante: **403** `{"ok":false,"erro":"Acesso negado."}` (autorizacao
  aplicada; nenhum `admin_*` executavel sem chave de rotina).
- Frontend sem drift: `app/index.html` e `app/version.json` = `v202.63`, producao
  `version.json` = `v202.63` (`deployed_at 2026-10-10T11:37:00Z`). Pages nao foi tocado.
- Scheduler (`Get-ScheduledTask`): Matinal `Ready` 14/10 10:06, Noturno `Ready` 14/10 18:05,
  Sentinela `Ready` 14/10 09:25, Verificacao-Async `Ready` 14/10 11:03, Reconciliacao-CVM
  `Ready` 19/10 12:00, Export `Ready` 14/10 20:45, Retry noturno `Ready`.

## Cobertura real de 13/10 (2 de 104), decomposta

A noturna de 13/10 17:50 fechou `Total do dia 104/104 (ledger analisados=2 skip=12
deferidos=90)`. A decomposicao, do proprio log:

- **2** confirmados em fonte primaria (`analisados_execucao=2`, `submit_ok=2`, `tokens=356612`);
- **12** `skip` - emissores ja analisados no mesmo dia por outra rotina (`CREDITO_DIA`);
- **90** `deferidos_cap` por **orcamento** (`cap_efetivo=700000` contra ~178k por emissor FULL);
- **0** falha de processamento (`silent_fail=0`, `deferidos_provider=0`,
  `lotes_nao_processados=0`, `buscas=8`, `dreno_exit=0`);
- a **triagem deterministica nao estava ativa** naquela execucao (`COLETOR_PS: ativo=False`,
  `triagem_material=0`), entao nao houve revogacao por triagem;
- **2** pendentes de recheck de cobertura (`CBA`, `Omega Energia`) em `cobertura_20261013.json`.

Ou seja: a lacuna e de **orcamento de tokens por dia**, nao de triagem, deferimento indevido
ou falha. Cobertura integral por IA em fonte primaria exigiria ~11,7M/dia contra teto de
2,6M; nenhum teto foi alterado nesta sessao.

## Falso OK que nao se repete

`ROTINA_RESUMO|vixradar-matinal|...|OK|4|0|17|v4.9.266` (execucao de 13/10 14:02) e o falso OK
medido: OK com 17 emissores deferidos por teto. Ele e anterior a regra unica de desfecho
(`Get-VixResultadoRotina`), que ja roda desde a noturna das 17:50 do mesmo dia
(`COBERTURA_RESULTADO: PARCIAL motivo=pendentes_obrigatorios=92`). Zero `resultado=OK` com
`pendentes_obrigatorios>0` nos logs de 13/10.

## Achado de ambiente que travava commit (nao e do produto)

`git commit` ficava pendurado **dentro do hook** (nenhum gate reprovava): a Gate 3 do
`pre-commit` materializa cada blob com `git cat-file blob :<path>`, e o `git cat-file`
bloqueava no IPC de um `git fsmonitor--daemon` (PID 9852, de 13/10) enquanto o commit
mantinha o indice. Rodando o hook fora do commit, os mesmos 36 arquivos passam em segundos
(`HOOK_EXIT=0`), o que isolou a causa na interacao commit+daemon. Contorno usado, **sem
desabilitar hook nenhum**: `GIT_CONFIG_COUNT/KEY_0/VALUE_0` = `core.fsmonitor=false` no
escopo do processo. Fica registrado como pendencia de ambiente (o daemon deve ser encerrado
ou o `core.fsmonitor` revisto), porque o proximo commit de outra sessao encontra o mesmo
estado por padrao.

## Release

- Backup logico com manifesto SHA256: `E:\Diretorio\Claude\BACKUPS\operacional\vix-radar\final-14out1-20261014-015740`
  (31 arquivos, 0 divergencias).
- Commit de codigo: `502f878` (36 arquivos) - testes do Worker, correcoes de script,
  suites e baseline, docs.
- Commit do deploy: `8d648a6` (`chore(worker): deploy v4.9.267 em producao`), bundle
  `api/v4.9.267.js` + `api/wrangler.toml` + `README.md`.
- Push `11f8a23..8d648a6` em `main` (publico).
- Rollback: `main = "v4.9.266.js"` no `api/wrangler.toml` + `deploy-worker.ps1 -Version v4.9.266`
  (o bundle da versao anterior esta no repo). Efeito: perde RLADMIN4 e os campos novos do
  health; nao perde dado.

## Testes

- `api` (vitest): **51 arquivos, 510/510 verde**.
- `scripts/run-all-tests.ps1`: **51 suites, 51 verdes, 0 vermelhas** (baseline vazio).
- `lint-encoding`: 157 `.ps1` + 5 shell, RISCO 0, nenhum reprovado.
- `check-claude-free`: exit 0.
- Suites desta sessao em Windows PowerShell 5.1 **e** pwsh 7: `test-codex-fallback-openrouter`
  58/58, `test-preflight-429` 48/48, `test-headless-tools` 19/19, `test-verificacao-codex`
  falhas=0, `test-reconciliacao-kvput` 16/16, `test-orcamento-sentinela` 67/67,
  `test-retry-janela` 46/46, `test-cobertura-analitica` 133 OK, `test-sentinela-watchdog` OK,
  `test-vixfix-20261006` 30/30.
- `Test-VixWebSearchProbe`/`Test-VixHeadlessTools` mantem o gate CLAUDE-FREE: nenhuma suite
  desbloqueou o caminho Claude em producao; o provider declarado vale so no processo do teste.

## Pendente de runtime (nao antecipado)

Matinal 14/10 10:06, Sentinela 14/10 09:25 (`SEM_ORCAMENTO`/exit 0), Export 14/10 20:45
(`LastTaskResult=0`, `data/historico/2026-10-14`), Reconciliacao CVM 19/10 12:00
(`LastTaskResult=0`). Criterios no bloco de `status/ESTADO.md` desta sessao.
