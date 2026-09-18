---
data: 2026-09-18
tipo: auditoria
tags: [vix-radar, auditoria, operacional, incidente]
status: degradado
---

# Auditoria Completa — VIX Radar (2026-09-18)

Modo readonly, bloco A a F. Nada foi editado em código, nada deployado, nenhum secret tocado.

## Síntese executiva

Produção de pé e sem drift entre o bundle ativo e o repo. Por baixo, o pipeline de ingestão está degradado há uma semana e o gate de CI não vê isso. **75 de 104 emissores sem análise há mais de 24h**, o mais antigo em 2026-09-16 21:10. O sync da CVM está bloqueado desde 14/09 por guarda de encolhimento, então o feed não ganha evento novo desde 16/09. A noturna não completa desde 16/09 e em 17/09 abortou antes do primeiro lote por falta de credencial Claude. Classificação geral: **degradado**, sem P0 de superfície.

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker | `api/wrangler.toml:1385` → `main = "v4.9.255.js"`, `WORKER_VERSAO = "v4.9.255"` no bundle (1.231.708 bytes, mtime 16/09 23:24) | `versao = "v4.9.255"` | Não |
| Frontend | `app/version.json` = `v202.43`, `CACHE_VERSION="v202.43"` no `index.html` | `https://vixradar.com/version.json` = `v202.43` | Não |
| Branch canônica | `origin/main` = `35c337f`, wrangler `v4.9.254.js` | produção roda `v4.9.255` | **Sim, por desenho da migração MVA** |

Branch de trabalho: `mva-provider-agnostic`, HEAD `a0d432b` (SEARCHBUDGET1). Está **31 commits à frente de `origin/main`** e **11 commits à frente do próprio remote** (`origin/mva-provider-agnostic`), ou seja 11 commits locais não pushados. Árvore suja com 8 entradas (4 docs, `scripts/monitor-tasks.ps1`, `scripts/register-retry-tasks.ps1`, mais `comparativo-dryrun-pro-flash.md` e `scratch/` não rastreados).

## Incidentes abertos

1. **Emissores sem análise (ALTO).** Gate `audit-routine-staleness.ps1`: `total=104`, `stale_24h_total=81`, `stale_24h_real=75`, `stale_24h_inconclusivo=6`, `max_stale_hours=43.3`, `stale_24h_real` mais antigo com `Ultima analise: 2026-09-16T21:10`. `presos_data=0`. Tiers do plano: SKIP 4, LIGHT 40, FULL 60, AUDIT 0.
2. **Sync da CVM bloqueado (ALTO).** Health: `cvm_fonte_ok=false`, `cvm_fonte_motivo="ultimo_sync_falhou:enet_encolhimento_bloqueado"`, `cvm_fonte_falha_dura=true`, `cvm_fonte_idade_du=4`, `cvm_fonte_last_modified="2026-09-14"`, `cvm_fonte_ultimo_sync_ok_em="2026-09-18T15:31:29.899Z"`, `cvm_fonte_proxima_prevista=null`. Guarda em `api/src/worker.js:8575` (`if (candidatos.length < piso) throw new Error("enet_encolhimento_bloqueado")`). Sentinela de hoje, quatro execuções: `PORTAO: acervo do Worker inalterado (2026-09-14) e sem backlog. Nada a fazer.`
3. **Noturna sem completar desde 16/09 (ALTO).** `logs/monitor-tasks/monitor_20260918.log` traz `VIXRadar-Noturno | exit=5 (0x5) idade=7d desde 2026-09-11 ESCALADO`. A de 17/09 abortou em `18:05:52 ERRO FATAL: nenhuma credencial Claude disponivel (...) Abortando antes do primeiro lote.` A de 18/09 ainda não rodou (18:05 BRT).
4. **Painel fora da regra de frescor (MÉDIO).** `painel_fresco=false`, `painel_atualizado_em="2026-09-18T04:44:31.772Z"` (01:44 BRT), `painel_exigido_desde="2026-09-18T13:00:00.000Z"`, `painel_idade_min=703`, regra `matinal (diaria exceto feriado B3, prazo 10:36 BRT, exige >= 10:00 do mesmo dia)`. A matinal das 10:06 rodou com `Idempotencia: 23 emissores ja processados hoje, pulando` e `METRICSZERO1: metrics preservado (execucao atual zerada por idempotencia)`, então não reescreveu o painel.

## Achados

### CRÍTICO

Nenhum. Superfície HTTP 200, auth fail-closed, sem secret hardcoded, sem drift de bundle ativo.

### ALTO

- **75/104 emissores fora do SLA de 24h.** Evidência: saída bruta do gate acima. Causa encadeada medida nos logs: `vixradar-noturno_20260916.log` com `deferidos=45 deferidos_auth=45 motivo_deferimento=limite_sessao_assinatura lotes_nao_processados=2`; `vixradar-matinal_20260916.log` com `analisados=0 deferidos=23 deferidos_cap=23 motivo_deferimento=cap_efetivo`; `vixradar-matinal_20260917.log` com `analisados=16 deferidos=7 deferidos_cap=7`; noturna de 17/09 abortada. A rotina roda, a maior parte do plano é deferida, e o plano de 104 não fecha em um dia com o orçamento atual.
- **Sync da CVM bloqueado por encolhimento.** Ver incidente 2. A guarda está fazendo o trabalho dela (bloquear payload menor que o piso em vez de aplicar). Falta decisão humana sobre se o encolhimento é a janela da CVM rolando ou regressão de fonte.
- **Noturna escalada há 7 dias.** Ver incidente 3.

### MÉDIO

- **Gate da skill de auditoria com `103` fixo.** `skills/vix-radar-audit/scripts/audit-routine-staleness.ps1:36` usa `$healthy = ($items.Count -eq 103 -and ...)`. São **104 emissores**, então esse gate nunca fecha verde, mesmo com zero stale. O número 103 também aparece em `05_BACKLOG` e no texto da skill.
- **Rótulo de deferimento contradiz os contadores.** `vixradar-matinal_20260918.log` (execução das 01:30) fecha com `motivo_deferimento=cap_efetivo` e `deferidos_cap=0 deferidos_auth=0`. O rótulo aponta cap sem nenhum deferimento contado como cap, que é a mesma classe de defeito que o COBERTURAAUTH1/DRENOMUDO1 fechou em 15/09.
- **CI verde com pipeline degradado.** `Frescor da Ingestao` verde em 18/09 (`run 35315482610`), 17/09 (`35190542995`), 16/09 (`35064702646`) e 15/09 (`34937776611`), com falha só em 14/09 (`34815715468`). O gate mede frescor de evento no feed, não staleness de análise por emissor, então 75 emissores parados não o movem.

### BAIXO

- 11 commits locais não pushados na `mva-provider-agnostic`, com produção rodando código que só existe nessa branch.
- `cvm_atribuicao_cobertura_pct=null` e `reconciliacao_zip_ok=false` no health, os dois sem motivo preenchido.

## Validação em produção

| Teste | Método | Resultado | Evidência |
|---|---|---|---|
| Health público | `GET https://radar-credito-api.prospects-intel.workers.dev/` | http=200, 0,34s | `ok:true`, `versao:v4.9.255`, `bindings:{kv:true,rate_limiter:true,telemetria:true}`, `providers_configurados:"2/2"`, `sentry_ok:true`, `verificador_ok:true`, `admin_email_ok:true` |
| Auth anônimo | `POST {}` sem JWT | http=401 | `{"ok":false,"erro":"Autenticação necessária."}` |
| Frontend prod | `GET https://vixradar.com/version.json` | 200 | `v202.43`, igual ao repo |
| Gate dos emissores | `audit-routine-staleness.ps1` (autenticado pelo próprio script) | `ok:false` | `total:104`, `stale_24h_real:75`, `max_stale_hours:43.3`, `presos_data:0` |
| Config do Worker | `api/wrangler.toml` | ok | `[observability] enabled=true`, bindings `RADAR_KV`, `RATE_LIMITER_DO`, `ESTADO_SEMANA_DO`, `EMISSOR_DO`, `USUARIO_DO`, `CONFIG_DO`, `RADAR_USAGE_EVENTS` declarados |
| Secret hardcoded | grep por `sk-ant-`, `sk-or-v1-`, `ANTHROPIC_API_KEY=`, `ROUTINE_API_KEY=` no bundle ativo | 0 ocorrência | contagem, sem imprimir valor |

## Lacunas

- Não fiz chamadas autenticadas adicionais (`tel_test`, `admin_health_check`, `dados_para_analise`). A regra global proíbe segredo em argumento de linha de comando, e o gate do plano autenticado do próprio script da skill cobre a cobertura dos 104, que é a pergunta mais forte. O `admin_health_check` fica como teste não coletado.
- Não rodei a varredura do checklist `workers-best-practices` no código do Worker. O bloco C ficou no nível de configuração e invariantes (bindings, observabilidade, fail-closed, ausência de secret).
- Não medi `semanaISO` do KV nem a janela de 30 dias por dentro.
- Não exercitei a noturna de hoje, que roda às 18:05 BRT e é o teste que diz se o caminho OpenRouter cobre a rotina completa.

## Próximos passos

- **P0** Decidir o encolhimento da CVM. Enquanto o sync estiver bloqueado, nenhum documento novo entra e o feed não anda.
- **P0** Fechar o buraco de cobertura. O plano de 104 não fecha com o orçamento atual e a maior parte é deferida por cap ou por limite de sessão. Enquanto isso, o SLA de 24h por emissor não é atingível.
- **P1** Confirmar se a noturna de hoje (18/05 BRT) completa no caminho novo. Se completar, a noturna de 17/09 fica como último dia perdido.
- **P1** Corrigir o `103` do gate da skill de auditoria para 104, senão o gate nunca fecha verde e mascara o sinal real.
- **P1** Investigar o rótulo `cap_efetivo` com contadores zerados na matinal de 18/09.
- **P2** Avaliar se o gate de CI deve passar a olhar staleness por emissor, porque hoje ele fica verde com 75 emissores parados.

## Correções aplicadas na mesma sessão

- **Gate da skill (103 → 104).** `audit-routine-staleness.ps1` passou a usar `$EmissoresEsperados = 104` com comentário de manutenção, e o `SKILL.md` e o `agents/openai.yaml` acompanharam. Aceite medido: o gate voltou a reprovar pelo motivo certo, `total=104` e `stale_24h_real=75`, sem o falso negativo do número fixo.
- **Rótulo de deferimento.** `run_vixradar_varredura.ps1` ganhou `$motivoDeferimentoEfetivo`, que vira `nenhum` quando a execução não deferiu nada, no FIM e no metrics. Antes, execução ociosa por idempotência saía com `motivo_deferimento=cap_efetivo` ao lado de `deferidos_cap=0`, como na matinal de 18/09. Aceite: `test-varredura-defeitos.ps1` 44 pass / 0 fail, parse PS 5.1 limpo.
- **Gate de CI por emissor.** `frescor-check.yml` ganhou o bloco EMISSORSTALE1, que consulta `listar_plano_rotina`, ignora `INCONCLUSIVO` e dispara warning com qualquer emissor acima de 24h e erro com mais de metade da carteira. As cinco expressões `jq` foram rodadas contra a resposta real de produção: 104 emissores, 75 acima de 24h, 6 inconclusivos, máximo 43,6h, mais antigo Ultrapar com última análise em 16/09 21:10. O passo de alerta passou a nomear a carteira no e-mail. **Só entra em vigor quando chegar em `main`, porque o agendado roda lá.**
- **Diagnóstico do bloqueio da CVM.** `api/src/worker.js` passou a gravar `diagnostico` no meta de FALHA do sync (documentos anteriores, candidatos, piso, piso bootstrap e dinâmico, universo, válidos do portal, tamanho do ZIP e do portal). O bloqueio de hoje saiu sem número nenhum e por isso exigiu arqueologia. Aceite: suíte do Worker 371/371. **Precisa de build e deploy para valer, e não foi deployado.**

## Resolução do bloqueio da CVM, medida em produção

Duas tentativas, a segunda só existiu porque a primeira instrumentou. O `v4.9.256` subiu com o `PISOORFAO1` e o diagnóstico novo no meta de falha, e o sync **continuou bloqueado**. O diagnóstico gravado respondeu na hora:

```
documentos_anteriores = 441   candidatos = 759   validos_portal = 10510
piso = 961   piso_modo = bootstrap   piso_dinamico = 0
metodologia_id presente na meta? False
```

O meta de FALHA era gravado sem `metodologia_id`, então a leitura seguinte concluía `mesma=false`, zerava o piso relativo e caía no bootstrap de 961. O bloqueio se realimentava pelo próprio meta e nunca destravava sozinho. Corrigido no `v4.9.257` com duas partes, `gravarFonteCVMMeta` preserva a metodologia em falha e `mesma` vale quando a meta não registra id mas existe base com documento. Metodologia registrada e diferente continua não comparável.

**Confirmado em produção depois do deploy do `v4.9.257`, sync disparado pelo cofre DPAPI em 18/09 17:50Z:** `sync.ok:true`, `documentos:759`, `lotes_ok:4`, `portal_only:318`, `zip_only:24`, `gate_reconciliacao:aprovado`, `max_data_entrega:2026-09-18`. Meta no KV: `ok:true`, `piso_documentos:308`, `piso_modo:"dinamico"`, `piso_bootstrap:961`, `piso_dinamico:308`. Health: `cvm_fonte_ok:true`, `cvm_fonte_motivo:"ok"`, `cvm_fonte_falha_dura:false`, `cvm_fonte_idade_du:0`.

O feed em si (`feed_evento_mais_novo` em 16/09) avança quando as rotinas processarem os documentos novos, o que é a noturna de hoje e a sentinela.

## O que a medição do CVM mostrou

O piso que reprovou é `max(961, 0.7 × 441) = 961`, porque `CVM_ENET_UNIVERSO_MEDIDO = 1374`. A base guardada tem 441 documentos com datas de 14/08 a 14/09, e a tentativa de hoje produziu 441 candidatos, abaixo do piso por construção. A fonte está sã: o ZIP do ano responde 200 com 1.612.874 bytes e `Last-Modified` de 14/09, listado no catálogo CKAN, e o portal devolve 7.616 registros válidos nos 35 dias da janela antes do filtro de carteira. O que não fecha é como o sync passou em 14/09 com um piso de 961 e deixou uma base de 441. As hipóteses vivas são o ZIP sobrescrevendo `cvm:documentos` com um subconjunto menor e a janela de 35 dias encolhendo com fonte quieta. A instrumentação acima existe para que a próxima ocorrência responda isso em uma leitura de KV, sem arqueologia.

