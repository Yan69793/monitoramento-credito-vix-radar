# Estado do projeto — VIX Radar

Última atualização: 2026-09-04 (noite. Worker v4.9.240, frontend v202.39. **Plano FEEDRETRO1 ENCERRADO**, Fases 0 a 3. **CLAUDE-FREE-MIGRATION Fase A em andamento**: código commitado `37bf0ec`, CI verde, Gate 8 no pre-commit; portões do operador G1-G5/G7 abertos. Ver blocos abaixo)

> [!warning] 04/09 (noite) — CLAUDE-FREE-MIGRATION, Fase A: Claude deixou de ser infraestrutura.
> **Status:** CÓDIGO COMMITADO (`37bf0ec`), CI verde, Gate 8 no pre-commit; portões G1-G5/G7 do operador ABERTOS. **Data:** 2026-09-04. **Governança:** `CLAUDE_SUBSCRIPTION=FREE`, `CLAUDE_CODE=OPCIONAL/NÃO GARANTIDO`, `ANTHROPIC_API_PAYG=NÃO AUTORIZADO`, dependência operacional de Claude Code PROIBIDA. Produção (Worker/Cloudflare) INTOCADA por decisão; secret `ANTHROPIC_API_KEY` e cascade Anthropic-only do Worker seguem como residual documentado, correção é Fase B.
>
> **O que mudou no código (commit `37bf0ec`, testado T1-T9 e T11):** toda rotina LLM (`varredura`, matinal, noturno, `verificacao_async`, sentinela, `agenda_semanal`, `run_claude_routine` p/ `vixradar-*`, retries, sonda, libs auth/ambient) carrega a lib `scripts/lib/vixradar-llm-provider.ps1` e sai bloqueada sem provider habilitado. Config única em env User `VIXRADAR_LLM_PROVIDER`: ausente/`none` = bloqueado; `claude-manual` = Claude só com `-ForceClaude` manual (fora do scheduler); `deepseek`/`openrouter` = reservado Fase B, ainda bloqueado. Saída canônica: linha `BLOQUEADO_SEM_PROVIDER provider=<v> exit=86 gatilho=<script> motivo=...` e exit **86**. Determinísticas (`coleta-volatilidade`, `export-historico`, `reconciliacao-cvm`) intactas. Scheduler volta ao Task Scheduler nativo (as 3 tasks antes do CCD viram natives Enabled rodando o gate). Gate anti-regressão novo: `scripts/check-claude-free.ps1` + Gate 8 no pre-commit + `.github/workflows/claude-free.yml`.
>
> **Portões do operador ainda abertos (G1-G5, ações pendentes):**
> 1. **G1** setar `VIXRADAR_LLM_PROVIDER=none` em escopo User (`[Environment]::SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER','none','User')`).
> 2. **G2** desligar as 4 tasks do CCD no MCP `scheduled-tasks` (`vixradar-matinal`, `vixradar-noturno`, `vixradar-verificacao-async-11h`, `vixradar-verificacao-async-1845`) e pausar as 2 Remote Routines; conferir `nextRunAt` nulo.
> 3. **G3** (elevação) rodar `scripts/cutover-motor.ps1 -Acao Ativar` → 5 natives Enabled, 2 retries Disabled, `motor.json={"motor":"task-scheduler"}`.
> 4. **G4** observar 1 disparo real de cada rotina bloqueada: log com a linha canônica e exit 86, nenhuma chamada a claude nem escalação paga.
> 5. **G5** `monitor-tasks.ps1 -DryRun` e ciclos: `BLOQUEADO_SEM_PROVIDER esperado`, resultado ≠ 86 dispara 9006.
>
> **Enquanto G1-G3 não rodarem**, o scheduler segue no regime anterior (natives Disabled + CCD ativo), só que agora cada rotina LLM sai bloqueada 86 sem provider — mesmo o CCD disparando, nada de claude roda nem cobra. Detalhe completo, inventário A/B/C/D/E arquivo por arquivo e testes no fechamento da sessão e em `PENDENCIAS.md` (item CLAUDE-FREE-MIGRATION) + nota de auditoria `100 - CLAUDE-FREE-MIGRATION Fase A 2026-09-04.md` no vault.

> [!success] 04/09 (noite) — CLAUDE-FREE-MIGRATION Fase A, G0 e G6 fechados: código commitado e gate anti-regressão no ar.
> **Commit `37bf0ec`** (24 arquivos: 11 rotinas/libs gateadas + `vixradar-llm-provider.ps1` + `check-claude-free.ps1` + `claude-free.yml` + Gate 8 no pre-commit + docs), push em `main`. **CI `claude-free` verde** (run 33930018633, gate ✓ em 20s). **Gate 8 instalado** no pre-commit ativo (`install-hooks.ps1 -Force`; o commit inicial rodou o hook antigo sem Gate 8, validado depois: blobs do commit passam `check-claude-free.ps1` com exit 0, e a reintrodução de claude sem gate reprova com R1, exit 1). **T11 prod intocada:** `HTTP:200`, `ok:true`, `sentry_ok:true`, versão v4.9.240, `feed_fresco:true`. T10 e G1-G5/G7 seguem com o operador (dependem do estado pós-G3).

> [!success] 04/09 — FEEDRETRO1 encerrado formalmente. Do painel parado em 28/08 ao feed andando com guarda provada.
> **Estado em produção:** Worker `v4.9.240`, frontend `v202.39`, `feed_fresco:true`, `feed_evento_mais_novo:2026-09-03`, `feed_idade_du:1`, portão `HTTP:200 ok:true kv:true telemetria:true sentry_ok:true`.
>
> **Semântica de entrega e de retry, regra canônica.** Fixada em `Obsidian VIX Radar/10_Estado_Atual_Validado.md`, seção `## Semântica de entrega e de retry`. Resumo, sem duplicar a matriz: `DEFERIDO` **não** conta como entrega concluída para idempotência e **não** dispara retry por si só; `SKIP` **continua contando** como processado; a cauda `DEFERIDO` é retomada pela próxima invocação normal, priorizada como `deferred_prioritario` no plano do dia seguinte; o retry segue reservado a **falha real de execução ou de entrega**, nunca a cap operacional planejado. O ponto fino: adiado deixou de contar como feito, mas não passou a contar como falha.
>
> **Três defeitos apareceram durante a execução do plano e foram fechados dentro dele:** `CARTEIRA-PISO1` (gate de 103 travando a noturna nos dois motores após a entrada do 104º emissor), `FONTEDIVERG1` (fato de maio carimbado com data de hoje podendo certificar frescor) e `DRIFTRETRY1` (script de registro com os agendamentos das tasks de retry trocados em relação ao Scheduler vivo). Os dois primeiros foram achados pelo dry-run, não por revisão de código.
>
> **Provas do plano:** 254 testes vitest em 26 arquivos, 19 asserts na política de limite de sessão, 31 na idempotência por janela, lint limpo em 88 `.ps1` e 5 shell, dry-run do motor fim a fim com `exit 0`.

> [!info] 04/09 (manhã) — FEEDRETRO1 FASE 3: a noite deixa de ser perdida por limite de sessão.
> **Status:** FECHADO. Com isto o plano FEEDRETRO1 está completo. **Data da Versão:** 2026-09-04. **Origem do Registro:** medição do estado real antes de escrever cada item. **Condição de Obsolescência:** cai quando uma noite com limite de sessão real exercitar a espera e o log registrar `RETRY: limite de sessao da assinatura`.
>
> **Dois itens do plano já estavam prontos** (`ExecutionTimeLimit PT4H` e `MultipleInstances IgnoreNew`), feitos em 03/09, e não foram refeitos.
>
> **A causa raiz da noite perdida eram duas regex divergentes.** A do motor casa `hit your ... limit`, a da lib não, e a lib era quem autorizava a escalada. Em 03/09 às 21h38 a chave paga estava disponível e ninguém escalou. Agora o motor espera o reset real quando ele cabe no orçamento, e escala por uma função que não depende da regex quando esperar não resolve.
>
> **Teto de parede compartilhado**, porque o risco era a soma das esperas (pré-flight mais lote) estourar o `PT4H`. Dimensionado por medição: a noturna completa leva 26 a 48 min, não as ~2h que o comentário antigo assumia.
>
> **`DEFERIDO` deixou de contar como entrega** na idempotência por janela, então uma segunda invocação processa a cauda adiada em vez de sair em no-op. `SKIP` continua contando. `RECOVERY-JANELA1` portado para a matinal.
>
> **Achado por acidente:** `register-retry-tasks.ps1` tinha os agendamentos das duas tasks de retry **trocados** em relação ao que estava vivo, e rodá-lo inverteria matinal e noturna. Corrigido para a realidade antes de acrescentar o gatilho novo das **23:20 Seg-Sex**.
>
> **Fica com o operador:** fazer o retry *lançar* por causa de cauda adiada exigiria mudar a definição de entrega do vigia, o que relançaria a noturna quase toda noite. É decisão de custo, não foi feito.
>
> **Provas:** 19 asserts em `scripts/test-session-limit-policy.ps1` (inclui o incidente de 03/09 ponta a ponta) e 31 em `scripts/test-idempotencia-janela.ps1`. Os dois entraram no git nesta leva e passam a ser cobertos pelo lint.

> [!info] 04/09 (manhã) — FONTEDIVERG1 e CARTEIRA-PISO1 (v4.9.240): o dry-run da Fase 2 achou dois defeitos que a revisão de código não achou.
> **Status:** FECHADOS, em produção. **Data da Versão:** 2026-09-04. **Origem do Registro:** duas passagens de `run_vixradar_varredura.ps1 -DryRun -MaxEmissores 5`. **Condição de Obsolescência:** cai quando a primeira noturna real com o prompt novo fechar sem recriar fato de agosto.
>
> **A Fase 2 funciona.** No dry-run, 4 de 5 emissores devolveram `eventos: []` citando o fato que já está no estado (Braskem 28/08, Oncoclínicas 27/08, Oi 25/08, Raízen 25/08). A janela efetiva da Cemig caiu de 30 dias para 1.
>
> **CARTEIRA-PISO1.** A entrada da Usina Pampa Sul (commit `da4c2ba`) levou o plano de 103 para 104, e os dois motores exigiam exatamente 103. O headless abortou com `exit 5` (medido) e o CCD abortaria por instrução literal; três testes do Worker ficaram vermelhos pelo mesmo número mágico. O gate virou piso de 100 mais linha `CARTEIRA:` quando o total muda. Prova de duas pontas: 12 e 99 abortam, 100/103/104 seguem.
>
> **FONTEDIVERG1.** Na primeira passagem a Kora Saúde devolveu `data_evento: 2026-09-04` citando matéria cujo `article:published_time` é `2026-05-05`; na segunda o mesmo prompt acertou a data e devolveu `eventos: []`. O pré-verificador já marca esse caso (`_data_fonte_divergente`) e o aceita de propósito para os domínios de `_ehFonteConfitavelBloqueada`, que incluem InfoMoney, Valor, Exame, NeoFeed, Money Times, Seu Dinheiro, Braz Journal e Estadão. A fronteira do feed não lia a marca, então um fato velho com data de hoje deixaria `feed_fresco` verde. Agora há dois máximos, e só o certificável move a fronteira e o carimbo. Guardas: casos D e E em `api/test/health.test.mjs` e a regra de data nos cinco prompts.
>
> **Suíte:** 26 arquivos, 254 testes, verde. **Portão às 13:48Z:** `HTTP:200`, `versao:"v4.9.240"`, `ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`, `feed_fresco:true`, `feed_evento_mais_novo:"2026-09-03"`, `feed_idade_du:1`.

> [!info] 04/09 (madrugada) — FEEDRETRO1 FASE 2: a rotina passa a saber o que já sabemos (v4.9.238).
> **Status:** ENTREGUE e em produção. Fase 3 (resiliência de execução) segue aberta. **Data da Versão:** 2026-09-04. **Origem do Registro:** plano FEEDRETRO1 aprovado pelo operador, com quatro rodadas de correção dele. **Condição de Obsolescência:** cai quando a primeira noturna com o prompt novo fechar registrando `eventos_avanco_data`.
> **O que mudou.** O plano do Worker agora entrega, por emissor, `ultimo_evento_data`, `eventos_conhecidos` (até 10, com data, título e host) e `janela_delta_inicio` (última análise menos 2 dias, nunca antes da janela de 30 dias). Os 5 pontos de prompt (as duas SKILL.md do CCD, os dois templates de lote e o cabeçalho do `New-BatchPrompt`) passaram a exigir âncora de recência na primeira busca, proibir recriação de fato já conhecido mesmo com URL diferente, e tratar continuação de saga como evento novo com a data de agora. `receber_analise` devolve `n_eventos_avanco_data`, `n_chaves_novas`, `n_eventos_conhecidos`, `max_data_evento_antes`/`depois` e `descartes` por motivo.
> **Semântica corrigida durante a implementação, a pedido do operador:** `n_eventos_avanco_data` conta DATAS DISTINTAS que superam o máximo anterior, não eventos. Dois fatos legítimos na MESMA data nova contam 1, não 2. A primeira implementação contava eventos e teria dobrado, contradizendo o comentário que eu mesmo tinha escrito ao lado. Quem responde "quantos fatos novos" é `n_chaves_novas`, separado.
> **Prova em produção, logo após o deploy:** 103/103 emissores com `janela_delta_inicio`, 79/103 com `ultimo_evento_data` (os 24 sem são os que não têm evento salvo). CEMIG voltou `ultimo_evento_data=2026-09-03`, `janela_delta_inicio=2026-09-02` contra `janela_inicio=2026-08-05`, com 7 eventos conhecidos listados: a janela efetiva de busca caiu de 30 dias para 1 nesse emissor. Suíte 26 arquivos e 251 testes verde, com 5 casos novos cobrindo exatamente a semântica acima. Motor local: ledger com `n_avanco_data` no fim da linha (não desloca os índices que o watchdog lê), `FIM:` com `eventos_avanco_data`/`chaves_novas`/`descartados`, e a guarda `DESCARTADO|` portada do `repor-varredura.ps1`. Detalhe em `PENDENCIAS.md`.

> [!warning] 04/09 (madrugada) — FEEDRETRO1: o feed estava parado há 5 dias úteis com todo semáforo verde. Guarda corrigida, provada nas duas pontas, feed reposto.
> **Status:** Fases 1 e 0 FECHADAS (guarda no ar + reposição feita). Fases 2 e 3 do plano ABERTAS (rotina incremental e resiliência de execução). **Data da Versão:** 2026-09-04. **Origem do Registro:** reclamação direta do operador com print do painel às 01h14 BRT ("Evento mais recente 28 de agosto de 2026, 5 dias úteis atrás"), medição própria em Cloudflare Observability, logs de rotina de 28/08 a 04/09 e 14 buscas web com data verificada no HTML da fonte. **Condição de Obsolescência:** cai quando as Fases 2 e 3 entrarem e a primeira noturna com prompt de delta fechar registrando `eventos_avanco_data`.
> **A auditoria de 03/09 concluiu "feed correto, sem fato novo material" e essa conclusão estava errada.** Ela olhou a fonte CVM, onde de fato não havia Fato Relevante dos 103 na janela, mas havia quatro fatos de crédito materiais em imprensa entre 31/08 e 03/09: Eneva vendeu a Pecém II por R$ 839,2 mi (31/08), Gerdau ampliou a linha global para US$ 1,125 bi (31/08), AXIA aprovou duas emissões de R$ 1,5 bi cada (02/09) e a Cemig D fechou bookbuilding de R$ 2 bi (03/09). A rotina varreu os 103 toda noite e não trouxe nenhum. "A CVM não publicou" não é "não houve fato".
> **Causa raiz dupla.** Rotina: o prompt pede evento na janela de 30 dias e nada pergunta o que saiu desde a última análise, então o modelo devolve o fato mais relevante do mês, sempre o de agosto. Medido: os 17 itens que a noturna de 03/09 mandou à verificação eram todos de 05/08 a 28/08. Guarda: `painel_fresco` mede escrita, `avanco_feed` dizia `saudavel_sem_fato_novo` porque o feed estava no teto da CVM, e a régua de idade de evento tinha virado `::warning::` por decisão minha em 01/09. As três verdes ao mesmo tempo. O Worker não descartava nada (log de 01 a 04/09: FORA_JANELA=0, SEM_DATA=0, DATA_APROXIMADA=0, RUIDO=0, DATA_FUTURA=0, FONTE_INACESSIVEL=0, contra MERGE=54 e PRESERVADO=66).
> **Correção v4.9.237 + v202.37.** GET público expõe `feed_evento_mais_novo`, `feed_idade_du`, `feed_fresco` e `feed_ultimo_evento_novo_em`. O carimbo só avança quando a fronteira GLOBAL do feed (`estado.feed_frontier_data`) sobe de data, nunca por chave nova de fato conhecido (o dedup é por `data|empresa|host+path`, então a mesma notícia com outra URL entraria como nova). `frescor-check.yml` voltou a reprovar por idade de evento (`::error::` + `exit 1`), com `avanco_feed` como diagnóstico no texto. Rodapé do painel fica âmbar com "Sem fato novo há N dias úteis". `EVENTO_MAX_DU=2` inalterado, tudo fora de `_okHealth`.
> **Prova negativa (guarda no ar, feed ainda parado), exigida pelo operador antes de repor:** health `feed_fresco:false`, `feed_idade_du:5`; run `33844055516` do frescor-check REPROVOU com `##[error]Feed sem evento novo ha 5 dias uteis (limite 2) ... avanco_feed=saudavel_sem_fato_novo` e exit 1; rodapé âmbar `rgb(245,158,11)`. **Prova positiva (após reposição de 4 fatos, `submit_ok=4 de 4`, `removidos_pre_verificador=0`):** health `feed_evento_mais_novo:"2026-09-03"`, `feed_idade_du:1`, `feed_fresco:true`, `feed_ultimo_evento_novo_em:"2026-09-04T06:32:42.125Z"`; run `33844843116` PASSOU com `FRESCOR_OK ... evento_mais_novo=2026-09-03 idade_du=1 eventos=215`; rodapé verde. **Prova fina em produção:** o log registrou `FRONTEIRA_AVANCOU` uma única vez nas quatro submissões, só a Cemig (03/09), porque as outras três tinham data anterior. Guardas: 5 casos novos em `api/test/health.test.mjs`, suíte 26 arquivos e 246 testes verde. Detalhe em `PENDENCIAS.md`.

> [!warning] 03/09 (noite), auto mode do projeto configurado, e a chave de rotina foi achada em texto puro no `settings.local.json` e redigida.
> **Status:** AUTOMODE-SETUP1 fechado, ROUTINEKEY-PLAIN2 redigido e **rotação recusada pelo operador em 03/09 20h55 BRT**, AUTOMODE-SHELL1 com PowerShell já concedido às 4 tasks CCD às 20h57, faltando só a prova de execução agendada. **Data da Versão:** 2026-09-03 (atualizada 21h05 BRT). **Origem do Registro:** wizard `/auto-mode-setup` (duas propostas), decisão delegada pelo operador, e duas decisões diretas dele em 03/09 à noite. **Condição de Obsolescência:** o bloco cai quando a matinal de 04/09 fechar sem negação de permissão de PowerShell.
> `.claude/settings.json` do projeto (gitignored) ganhou `autoMode` mesclado das duas propostas, 25 linhas de ambiente, 9 allow, 11 soft_deny, 4 hard_deny, JSON validado. `.claude/settings.local.json` tinha o valor do `ROUTINE_API_KEY` em 21 regras de allow (curl antigos aprovados com a chave no corpo), mais `Bash(npx wrangler:*)`, 9 kills por PID e um `Enable-ScheduledTask 'VIXRadar-Matinal'`. Removidas 32 regras (266 para 234), backup com o valor redigido. O mesmo valor estava em 25 backups de prompt de junho e julho em `C:\Users\User\.claude\scheduled-tasks\backups\` (67 ocorrências), todos redigidos, arquivos vivos com zero. Mais 5 cópias em `.claude\worktrees\*`, limpas do mesmo jeito. Varredura final do repo inteiro, zero. Rotacionar a chave é a única correção real e **o operador recusou a rotação em 03/09 20h55 BRT**, a chave atual segue valendo por escolha dele, risco residual aceito e declarado, não reabrir como pendência de agente. **PowerShell concedido às 4 tasks agendadas do Claude Desktop em 03/09 20h57 BRT**, a pedido dele, por edição do `scheduled-tasks.json` (o MCP não tem campo de permissão), uma entrada `{ "toolName": "PowerShell" }` por task, e a edição sobreviveu a uma escrita do próprio app às 20:57:46, o que prova que o arquivo é read-modify-write. Falta provar efeito, a matinal de 04/09 às 10h06 é a primeira execução CCD depois disso. Allows crus `Bash`/`PowerShell` do settings do usuário continuam lá até essa prova. Detalhe em `PENDENCIAS.md`.

> [!info] 03/09 (noite), auditoria independente do feed parado em 28/08, refeita por medição própria. Conclusão B confirmada, nenhum fato material de 29/08 a 03/09 para os 103.
> **Status:** FECHADO como "feed correto, sem fato novo material". **Data da Versão:** 2026-09-03. **Origem do Registro:** missão `/vix-radar-general-audit` do operador, health público em v4.9.236, CSV bruto da CVM regenerado em 30/08, run `33723201815` do frescor-check, logs de 29/08 a 03/09, 11 buscas web. **Condição de Obsolescência:** cai no lote CVM de 06/09 ou quando RECOVERY-JANELA1 for tratado.
> `feed_max=2026-08-28` é o deferimento judicial da recuperação extrajudicial da Braskem, o CSV bruto tem zero Fato Relevante dos 103 com data a partir de 29/08 (o único do período é de SPE fora da carteira, com ano 3026 digitado errado), o próprio Worker calculou `saudavel_sem_fato_novo` com `teto_elegivel=2026-08-28`, e a verificação aprovou 16 itens hoje, todos datados até 28/08. Nenhum backfill, deploy ou data forçada. Detalhe por fonte e por estágio em `PENDENCIAS.md`.
> Dois resíduos novos, também em `PENDENCIAS.md`. **RECOVERY-JANELA1 (P2), CORRIGIDO na mesma noite, sem deploy.** A recuperação matinal das 09h fechou o ledger do dia e a noturna das 18h15 saiu por idempotência sem gravar nada, porque o Passo 4 da skill julgava por dia civil enquanto vigia e `painel_fresco` julgam por janela (>= 18:00). Fix, idempotência por janela na `SKILL.md` da noturna (CCD store) usando helpers novos em `scripts/lib/vixradar-watchdog.ps1` (`Get-VixJanelaInicioRotina`, `Get-VixLedgerEmissoresNaJanela`, mesma régua do vigia), guarda `scripts/test-idempotencia-janela.ps1` 20/20 no PS 5.1 com prova reversa (regra antiga dá 0 pendentes no caso real, a nova dá 103), lint OK, `test-retry-janela.ps1` 14/14. Rodado contra o log real de hoje às 18:48, `naJanela=0 foraDaJanela=103`. Efeito, o retry das 21h30 agora faz a passada da noite de verdade (45 deferidos FULL, analisados da manhã como SKIP) em vez de alertar falso, e o `painel_fresco` das 01h30 fica satisfeito. **SENTINELA-DIVIDA1 (P3), aberto**, o portão da sentinela ignora os deferidos da noturna, 17 emissores sem análise desde 31/08.

> [!warning] 03/09 — INCIDENTE-FRESHNESS2 (v4.9.236): painel parado 12h41 em 11:09 BRT com `ok:true`. Causa nas ROTINAS, não no dado.
> **Status:** FECHADO. Código, testes, gate adversarial de causa, gate adversarial de produção e agente refutador final todos concluídos; deploy confirmado em produção; 8 resíduos declarados, nenhum bloqueante · **Data da Versão:** 2026-09-03 · **Origem do Registro:** evidência visual do operador (02/09 ~23:50 BRT, aba anônima) + medição ao vivo (DOM, `op=state`, headers, Cloudflare Observability, transcripts das sessões agendadas, `%TEMP%\wsprobe_err_*`) · **Condição de Obsolescência:** cai quando a agenda das rotinas mudar (o SLA de `painel_fresco` deriva dela) ou quando `FERIADOS_B3_2026/2027` precisarem de renovação (ver resíduo 8).
>
> **Deploy CONFIRMADO.** `deploy-worker.ps1` travou 3 vezes antes de completar: 1ª tentativa deu EPERM num processo `npm ci` anterior que não tinha morrido de verdade (matei o PID e retentei); 2ª tentativa terminou com `node_modules` incompleto (`@sentry/cloudflare ausente`) depois de 16 min de warnings `TAR_ENTRY_ERROR ENOENT` em cascata — causa raiz identificada por medição: Windows Defender (`MsMpEng.exe`) com scan em tempo real ativo, competindo por I/O com a extração em massa do `npm ci` (`node_modules` tinha só 1,2 MB quando devia ter centenas); apaguei `node_modules` (diretório gerado, seguro remover) e a 3ª tentativa completou em 14 min. Portão de verificação colado às 14:47Z: `HTTP:200`, `ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`, `versao:"v4.9.236"`, `painel_atualizado_em:"2026-09-03T14:17:01.697Z"`, `painel_idade_min:30`, `painel_fresco:true`. Commit automático do próprio script: `20f8a25 chore(worker): deploy v4.9.236 em producao`. Se o Windows Defender continuar causando isso em deploys futuros, a correção de raiz (excluir `api/node_modules` do scan em tempo real) é decisão do operador, não algo que o agente deva fazer sozinho.
>
> **Recuperação operacional (independente do deploy do Worker).** A escrita do estado ( `receber_analise`/`confirmar_verificacao`) já existe em v4.9.235, então a recuperação da noturna pode ter sucesso mesmo sem o deploy. Medido agora via Cloudflare Observability (`POST /` total, 03/09 08:00Z-14:05Z): 979 requisições, concentradas em duas janelas — 12:00Z-12:37Z (~404, compatível com a recuperação manual da madrugada) e 13:07Z-13:44Z (~562, compatível com o horário exato da matinal diária, 10:06 BRT = 13:06Z). Volume real bem maior que o número citado numa nota anterior desta mesma sessão ("42 POSTs"); a contagem de 42 media só uma fatia mais estreita da chamada interna, não o tráfego `POST /` total. `op=state` exige JWT de usuário e não foi lido diretamente nesta verificação (regra: nunca manusear credencial pelo chat); a convergência de horário com a agenda conhecida das rotinas é a prova aceita, mesmo padrão já usado no restante deste incidente (3 provas indiretas convergentes, ver seção de riscos do plano).
>
> **Não confundir com o INCIDENTE-FRESHNESS1 (bloco abaixo).** Aquele era sobre `last_event_at=28/08` e continua correto: sem fato material novo, o feed fica parado por construção. Este é sobre `updated_at`, o carimbo de quando a ROTINA escreveu: ele parou em `2026-09-02T14:09:28.138Z` (11:09 BRT, verificação das 11h) e nada escreveu nas 12h41 seguintes.
>
> **Cadeia medida, camada por camada.** DOM (`_vixCarimboDoPainel`, `app/index.html:3779`) = API (`op=state`, `updated_at`) = KV (blob semanal) = última escrita real. Cache descartado por medição: sem `[cache]` no `wrangler.toml`, sem Cache API em `op=state`, sem `cf-cache-status` nem `Age` na resposta, HTML de produção byte-idêntico ao repo. Observability: 49 POSTs ao `estado-semana.internal` até 14:09:31Z e **zero** depois, até 03:25Z.
>
> **Três elos.** (1) noturna das 18h05 interrompida às 18:12:14 (`[Request interrupted by user]`), depois de montar os 21 lotes e antes de qualquer submit. (2) retry das 21:30 abortou como "WebSearch indisponivel", quando a causa real era 429 de limite de sessão com reset 70 min depois (prova crua em `%TEMP%\wsprobe_err_3956.txt`); não esperou, não alertou. (3) mesmo sem o 429 não entregaria: `--tools WebSearch,WebFetch` é allowlist e tirava PowerShell, Bash, Read, Write e Agent da skill (AGENDASEM-CAUSA1 de novo; medido em 19/08, relançamento com exit 0 em 1m54s e zero submits). **Quarto elo:** nenhuma camada media a idade do painel (`ok` mede serviço, `avanco_feed` mede a fonte CVM, heartbeat `varredura_local` tolera 26h e a matinal o havia renovado).
>
> **Correções (commit `43f99f6`, v4.9.236).** Política de 429 (decisão do operador): assinatura primeiro, espera pelo reset REAL extraído do erro até 120 min, chave paga só como contingência com `ALERTA_AUTH` + e-mail, nunca fora de limite de assinatura, nunca em escopo User. Linha headless fail-closed: `--tools default` + `--permission-mode dontAsk` + `--allowedTools` explícito + `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`, com sonda nova (`Test-VixHeadlessTools`) que roda o CLI real e exige shell, leitura, escrita, subagente e busca ANTES de a rotina começar. Entrega julgada pelo ledger `OK|` dentro da janela da rotina, nunca por exit code, com realerta depois do relançamento. No Worker, `painel_atualizado_em`/`painel_idade_min`/`painel_fresco`/`painel_regra`/`painel_exigido_desde`, SLA derivado da agenda real (matinal prazo 10:36 exige ≥10:00; noturna prazo 01:30 exige ≥18:00 do dia útil anterior), fora do `ok` (HEALTHSPLIT1), com `canonical-test.yml` reprovando o run em `painel_fresco=false`.
>
> **Provas de teste.** 241 testes vitest em 26 arquivos (+8 de `painel_fresco`, incluindo os dois cenários de feriado B3 do FERIADOB3-PAINEL1) e 85 asserts em 3 suítes PowerShell (48+14+23), todos verdes na última rodada desta sessão e reproduzidos de forma independente pelo agente refutador final. Duas pontas com o CLI REAL: linha nova passa a sonda headless; linha antiga reprova por falta de `PowerShell/Bash, Read, Write, Edit, Agent(Task)`, mesmo defeito de 02/09. Prova de recuperação operacional: ver bloco "Recuperação operacional" acima. **Prova de produção CONFIRMADA:** portão de verificação às 14:47Z respondeu `versao:"v4.9.236"`, `painel_fresco:true` (ver bloco "Deploy" acima).
>
> **Gate do agente refutador final: PASS.** Reproduziu causa raiz, correções e testes do zero (sem herdar nada da sessão), atacando cada achado com medição própria; rodou antes do deploy completar, então não viu o `versao:"v4.9.236"` ao vivo, mas validou tudo que o deploy dependia (código, testes, bundle). Nenhum achado anterior foi derrubado; achou 2 resíduos novos (janela de ~8 dias em que `painel_fresco` regride para `null`; `_ehFeriadoB3` sem cobertura a partir de 2028) e uma imprecisão de contagem de testes, todos corrigidos em `PENDENCIAS.md`. Achado fora de escopo (chip separado, `task_9d7b157f`): `scripts/register-all-routines-scheduler.ps1` aponta `VIXRadar-AgendaSemanal` para um `RoutineId` que não existe mais no catálogo — a task viva no Scheduler está correta hoje, o script quebraria se rodado de novo.
>
> **Resíduos declarados** (8 no total, detalhe em `PENDENCIAS.md`): retry da invocação principal ainda não 429-aware; virada de meia-noite ainda parte o ledger entre dois arquivos; `monitor-tasks.ps1` ainda não usa a função de janela compartilhada; frontend com dois pontos frágeis pré-existentes (bootstrap sobrescreve o prefixo do carimbo; fallback `|| new Date()`); lag de detecção do SLA de ~7h20-7h30; janela de 8 dias em que `painel_fresco` vira `null`; `_ehFeriadoB3` sem cobertura a partir de 2028. Nenhum bloqueia o fechamento.
>
> **Commits desta sessão (nenhum empurrado para `origin/main` ainda):** `43f99f6` (primeira leva A1-A6/B1-B4), `8fbfa95` (correções pós-gate: feriado B3, regex 429, guard PT4H, cache-control, fix de data de teste), `20f8a25` (deploy automático do script, inclui o bundle `api/v4.9.236.js`). Push é decisão do operador.

> [!info] 03/09 — INCIDENTE-FRESHNESS1 encerrado: painel em 28/08 está CORRETO (sem fato novo material 29/08–02/09).
> **Status:** fechado como "feed correto, sem fato novo material" · **Data da Versão:** 2026-09-03 · **Origem do Registro:** medição de Produção (`admin_health_check` via DPAPI) + fonte crua CVM (`data/cvm/ipe_2026/ipe_cia_aberta_2026.csv`) + varredura WebSearch autenticada de imprensa/rating.
>
> **Hipóteses refutadas nesta sessão:** (1) "nada persistiu" — falso, `estado_semanal.updated_at=2026-09-02T14:09:28Z`; (2) "falha de atribuição CVM" — falso, os docs com `data_referencia` 29/08–01/09 são Calendário/Assembleia de empresas fora da carteira (Meliuz, Enjoei, Cruzeiro do Sul; nenhuma nos 103), quarentena correta (fail-closed).
>
> **Fatos medidos:** CVM lote de 30/08 entrega `Data_Entrega` até 2026-08-29; 585 docs com `data_referencia ≥29/08` (442 Calendário, 96 Assembleia, 1 Fato Relevante corrompido `REF=3026-03-30` de Águas do Rio 1 SPE não monitorada); **0 Fato Relevante/rating material de 29/08–02/09 para os 103**. `feed_max=28/08 == teto comparável elegível` → `avanco_feed=saudavel_sem_fato_novo` CORRETO. Varredura WebSearch autenticada (imprensa + rating, executada 03/09): sem evento material novo no período; Braskem 31/08 (SEC 6-K) já persistido via PREVERIFSEC1 v4.9.232.
>
> **Decisão:** NÃO forçar atualização de data (proibido inventar evento). Nenhum backfill/patch/deploy necessário. `last_event_at` permanece `2026-08-28` até a fonte ter fato novo legítimo; próximo lote CVM previsto 06/09.


> [!info] 02-03/09 — Auditoria read-only (sem achado bloqueante novo) + instrumentação RUN429DGN1 para destravar o wait-and-continue do 429.
> **Status:** vigente · **Data da Versão:** 2026-09-03 · **Origem do Registro:** pedido do operador: auditoria geral `/vix-radar-general-audit` + decisão (op. 2) sobre o abort do pre-flight por 429 de session limit.
>
> **Versões reais medidas ao vivo:** Worker `v4.9.235` (`ok:true`, `sentry_ok:true`, `verificador_ok:true`, `admin_email_ok:true`, `fonte_externa_ok:true`, `cvm_fonte_ok:true`) e Frontend `v202.36`. Sem drift contra o `main` real do toml (`v4.9.235.js`); o comentário de cabeçalho do `wrangler.toml` ainda diz "v4.9.232" — só o comentário está atrasado.
>
> **Auditoria read-only executada:** veracidade de UI limpa (0 bloqueantes; termos Emissores/Críticos/Relevantes/Sem alertas coerentes com o glossário; `app/index.html` == `deploy_zip`); suíte `vitest` 233/233 em 26 arquivos; `node --check` do Worker ok. Lacunas declaradas (não reabertas): XSS em `renderEventoCard`, RACEKV do blob semanal, WCAG manual/CWV em lab.
>
> **Owner do abort do pre-flight por 429 PROVADO:** `scripts/run_claude_routine.ps1:150-155` emite `ERRO PRE-FLIGHT: WebSearch indisponivel` + `ABORTANDO` + `exit 5` a partir do booleano de `Test-VixWebSearchProbe` (`scripts/lib/vixradar-ambient-check.ps1`). A sonda descartava `$code` e o texto de erro do `claude -p --tools WebSearch`. Produção logou o abort em `logs/routines/vixradar-noturno_20260902.log` L582-585. Qualquer 429 de session limit caía no mesmo `false` e era reportado como "busca fora do ar".
>
> **RUN429DGN1 (03/09, script local, SEM deploy):** `Test-VixWebSearchProbe` passou a gravar, quando a sonda falha, arquivo `wsprobe_diag_<timestamp>_<pid>.log` na `%TEMP%` com `code=` + stdout + stderr sanitizados (redige `sk-ant-*`, `Bearer`, vars Anthropic/ROUTINE_KEY). Retorno booleano e abort/exit5 intocados. Provado nas duas pontas com stub (sucesso → 0 diag; falha 429 → diag com code=429 + instante de reset preservado, sem segredo). O caminho de sucesso não gera diagnóstico.
>
> **PENDENTE (próximo passo, depende de amostra real):** o wait-and-continue (op. 2) do 429 exige o texto do erro de session limit que o `claude -p` devolve (dele sai o instante de reset). Nenhum 429 real estava registrado em logs/transcripts lidos, então o formato não era verificável. **Regra: o PRÓXIMO 429 real deixará `wsprobe_diag_*.log` na `%TEMP%` — recolher essa amostra e então implementar o wait-until-reset com teto (senão cai no retry existente), corrigindo o rótulo "WebSearch indisponivel" ao distinguir 429 de indisponibilidade real.** Não chumbar horário de reset como constante até ver o formato real.

> [!info] 01/09 (desta sessão) — PREVERIFSEC1 fechado no v4.9.232, sessão de fechamento dos 5 resíduos.
> **Status:** vigente · **Data da Versão:** 2026-09-01 · **Origem do Registro:** fechamento da sessão anterior (Braskem/sec.gov, submit_ok enganoso, cruzamento da quarentena, cron, fonte intradiária). Todos os 5 pontos fechados abaixo.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.232.
>
> **PREVERIFSEC1 (Braskem/sec.gov, v4.9.232).** O pré-verificador descartava o evento CRÍTICO da Braskem de 31/08 (recuperação extrajudicial, Form 6-K da SEC) com `ok:true` mas `n_eventos:0`, porque a SEC retorna 403 a User-Agent genérico e o acervo não reconhecia `sec.gov` como fonte confiável. Caído no ramo "fonte inacessível", o 6-K era descartado em silêncio. Fix mínimo e distinto: novo conjunto `DOMINIOS_FONTE_OFICIAL_DOCUMENTOS` (SEC, CVM, B3, BCB, IN, Anbima) separado de agência de rating, e helper `_ehFonteConfitavelBloqueada` que cobre ambos. O evento só é aceito dentro da janela de 30 dias e SEMPRE com `_verif_forcar=true` (verificação adversarial obrigatória). NÃO é bypass genérico: fonte não confiável, SEC fora da janela e evento sem data_evento continuam descartados. `validarDatasFontes` ganhou `_fetchOverride` (só teste) para reproduzir o 403 real. Guarda `api/test/pre-verificador-sec-gov.test.mjs`, 8 testes, prova de 3 pontas. Deploy `deploy-worker.ps1 -Version v4.9.232`, commits `46f809c`/`d25d6c5`/`66b8b74`, push OK. Portão `ok:true versao:v4.9.232 kv:true telemetria:true sentry_ok:true`.
>
> **SUBMITOK-ENGANOSO1.** O resumo da noturna misturava submit aceito com emissor analisado. O ledger `OK|` do SKILL.md ganhou o 6º campo `SKIP|ANALISADO|DEFERIDO`, e o Passo 11 exige `analisados=/skip=/deferidos=/submits_aceitos=` mantendo `Total do dia N/103`. Regra explícita: submit aceito ≠ emissor analisado; o número honesto de análise é o total de `ANALISADO`. Guarda `scripts/check-ledger-noturno.ps1`: formato antigo reprova (exit 1), caso real de 31/08 (50/22/31/103) passa (exit 0). Orçamento/cap/rotação intocados.
>
> **Cruzamento dos 1.439 documentos sem dono = COMPORTAMENTO ESPERADO.** O acervo CVM tem 2252 docs, 1439 sem dono em 383 entidades, cobertura 36,1%. Cruzado contra os 103: NENHUMA entidade de maior volume pertence ao universo por CNPJ; todos os 99 CNPJs primários dos 103 estão no cadastro CVM (a régua de atribuição captura os 103); único CNPJ de família fora é JBS N.V. (estrangeira). Os 4 sem CNPJ primário (Oi, Nexa, Pan, Votorantim) são cobertos por família ou aliases de nome. Nenhuma correção de atribuição necessária — sem falha real. Guarda `scripts/check-quarentena-emissores.mjs`. Métrica 36,1% preservada no health (é diagnóstico, não ponto de correção).
>
> **Cron da noturna (descrição).** Frontmatter do SKILL.md corrigido de `(diario 18h BRT)` para `(diario 10h BRT)`. `cronExpression="0 10 * * *"` não foi tocado; estado persistido do agendamento confirmado no arquivo `scheduled-tasks.json` (`enabled:true`, `cronExpression:"0 10 * * *"`, `lastRunAt 2026-08-31T13:05:31Z` = 10:05 BRT). Nota de precisão: o arquivo prova o estado PERSISTIDO, não o scheduler vivo (`nextRunAt` computado pelo processo) — o vivo foi observado na sessão AVANCOFEED1 via MCP (`nextRunAt:2026-09-01T13:05:24Z`, ver abaixo), já que o MCP `scheduled-tasks` não estava no catálogo desta execução.
>
> **Fonte intradiária = LIMITAÇÃO ACEITA COM CONDIÇÃO DE REABERTURA.** Não implementada. Condição de reabertura: fonte intradiária confiável APROVADA + credencial disponível (Download Múltiplo CVM exige credencial ausente; RAD por reCAPTCHA a não contornar; dadosdemercado exige Bearer pago). Movida para decisão/roadmap, fora dos bugs desta tarefa.

> [!info] 01/09 (madrugada) — AVANCOFEED1 no v4.9.231 e cron da noturna de volta às 10h. Duas frentes, nenhuma terceira.
> **Status:** vigente · **Data da Versão:** 2026-09-01 · **Origem do Registro:** pedido do operador depois do diagnóstico do feed parado em 28/08. Escopo travado em duas correções: reverter o horário da noturna e criar a guarda de avanço. Deploys `v4.9.229` → `v4.9.230` → `v4.9.231`, commits `6e0dda8`/`90e8612`, `70d3dbc`/`df85c52`, `cc22e20`/`caffe43`, push OK.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.231 ou quando o cron da noturna mudar de novo.
>
> **Cron da noturna: `0 8 * * *` → `0 10 * * *`, revertido antes de disparar uma vez sequer.** A mudança para 08h entrou no config em 31/08 18:50 e passou a valer no restart de 31/08 23:07, mas o primeiro disparo seria hoje 01/09 08:05 BRT e a reversão foi feita 01:44. Medido: `lastRunAt 2026-08-31T13:05:31Z` (10:05 BRT) é do cron velho. Motivo da reversão: 08h BRT é antes da B3 abrir e antes de CVM e imprensa publicarem o dia, e a noturna é a única passada que cobre os 103 (a matinal cobre top 20 por EWS). Rodar mais cedo não perde fato do dia anterior, mas joga fora as poucas horas de fato do próprio dia. Não tinha relação com o feed parado.
>
> **Descoberta operacional: a alteração pelo MCP `scheduled-tasks` vale na hora, sem restart.** INVERSAO-CD1 continua valendo para EDIÇÃO MANUAL do `scheduled-tasks.json`, que só é lido na ativação do app. `update_scheduled_task` é outro caminho: grava no store e reprograma o scheduler vivo. Prova de duas pontas na mesma sessão, sem tocar em processo nenhum: antes `cronExpression:"0 8 * * *"` / `nextRunAt:"2026-09-01T11:05:24Z"`, depois `cronExpression:"0 10 * * *"` / `nextRunAt:"2026-09-01T13:05:24Z"`, e o arquivo em disco reescrito às 01:44:41 com `0 10 * * *`. `nextRunAt` não existe no arquivo, é computado pelo processo vivo, então a mudança do valor prova que o app rodando aplicou. Restart não foi feito porque não era necessário, e derrubaria a sessão.
>
> **AVANCOFEED1 (v4.9.229 a v4.9.231).** `checks.avanco_feed` no health diário. Compara o teto do feed (`MAX(data_evento)`) com o teto da fonte e com a cadência esperada dela, em vez de contar dias sem evento. Seis estados: `saudavel_sem_fato_novo`, `fonte_parada`, `aguardando_varredura`, `pipeline_nao_persistiu`, `sem_evento_datado`, `fonte_indeterminada`. Alertam apenas `pipeline_nao_persistiu` e `sem_evento_datado`. O gate antigo (`evento_mais_novo.idade_du > 2`) reprovaria hoje mesmo um estado saudável e virou `::warning::`, porque imprensa e rating publicam todo dia útil e feed longo parado ainda merece olhada, só não reprova sozinho.
>
> **Duas correções vieram da própria medição, não de revisão de código.** A v4.9.230 nasceu ao validar a v4.9.229 contra produção: o health devolve `cvm_fonte_last_modified:"2026-08-30"`, data pura, e usar isso cru como instante de chegada do lote vira 00:00Z, o que faria a varredura de domingo 13:05Z contar como "rodou depois do lote" e acusar o pipeline por uma janela que ele não teve. Referência só com data passou a valer fim do dia. A v4.9.231 nasceu da PRIMEIRA EXECUÇÃO REAL da guarda (run `33472230172`, 05:05Z), que reprovou com `teto_fonte=2026-08-31` contra `feed_max=2026-08-28`: o número estava certo e a conclusão errada, porque o acervo inteiro (2252 documentos) inclui 1439 sem dono entre os 103 e documentos com data de referência no futuro, os dois já filtrados por `costurarCvmEmEventos`. A guarda estava usando régua diferente da do pipeline que vigia. Passou a decidir pelo teto ELEGÍVEL.
>
> **Prova em produção, duas pontas, saída crua.** Reprova (run `33472230172`, código pré-v4.9.231): `##[error]AVANCO DO FEED REPROVADO (pipeline_nao_persistiu)`, exit 1. Aceita (run `33472592026`, v4.9.231): `AVANCO_FEED estado=saudavel_sem_fato_novo feed_max=2026-08-28 teto_elegivel=2026-08-28 teto_acervo=2026-08-31 max_data_entrega=2026-08-28 dentro_da_cadencia=true escreveu_apos_lote=true referencia_lote=2026-08-30T23:59:59.000Z proxima_prevista=2026-09-06 docs=2252 elegiveis=813 sem_dono=1439 data_futura=0` e `FRESCOR_OK`, conclusão success. Portão canônico: `HTTP:200 TEMPO:0.171s`, `ok:true versao:v4.9.231 kv:true telemetria:true sentry_ok:true`. Suíte 22 arquivos / 188 testes.
>
> **Confirmação do diagnóstico do feed.** `teto_elegivel = 2026-08-28 = feed_max`. O feed está no teto do que o pipeline pode publicar. O próximo lote da CVM é 06/09 (`proxima_prevista`), então o painel pode legitimamente não andar por documento de CVM até lá.
>
> **Número que apareceu de brinde e não é desta frente:** 1439 dos 2252 documentos do acervo estão sem dono entre os 103 emissores, cobertura de atribuição 36,1%. Sai agora no payload (`fonte_documentos_sem_dono`) e no log do frescor-check. Não foi investigado aqui.

> [!info] 01/09 (madrugada) — v4.9.228 DEPLOYADO: os 4 achados da auditoria geral de 01/09 fechados, nenhuma frente nova aberta.
> **Status:** superado pelo v4.9.231 (mesma madrugada) · **Data da Versão:** 2026-09-01 · **Origem do Registro:** correção pedida pelo operador sobre a nota 98 (`Obsidian VIX Radar/98 - Auditoria Geral 2026-09-01.md`), escopo travado nos 4 achados P3/P4. Deploy via `deploy-worker.ps1 -Version v4.9.228`, commit de código `e44cd7c`, commit de deploy `8ac3e0e`, push OK.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.228.
>
> Portão pós-deploy, saída real: `HTTP:200 TEMPO:0.162s`, `ok:true fonte_externa_ok:true versao:v4.9.228 kv:true rate_limiter:true telemetria:true admin_email_ok:true sentry_ok:true verificador_ok:true`. Suíte local 21 arquivos / 167 testes verdes (era 19/158 antes; os dois arquivos novos somam 9).
>
> **DISJUNTORHOUSEKEEP1 (P3-2, era DISJUNTOR1).** O disjuntor de custo diário abortava o cron matinal e o noturno inteiros, com `return` no despacho. Premissa herdada da era pré-delegação: hoje `VARREDURA_CRON_AI_ENABLED=false`, a varredura é marcada `pulado/delegado_claude_tiered_v2` e esses crons só fazem housekeeping. Como o teto é alimentado pelo gasto das rotinas locais, um dia caro na máquina do operador abortava aqui o `sync_cvm` e o `healthcheck_diario`, que são os dois sinais que o watchdog e o frescor leem. O alarme emudecia no dia ruim, mesmo modo de falha do FIX(N1) da v4.9.163 um nível acima. Gate movido para dentro do ramo de varredura (`_cronDisjuntorBloqueia`, lista fechada `_RAMOS_CRON_COM_LLM`), fail-open de leitura preservado. Medição que sustenta a lista: os call sites de LLM no caminho do cron estão todos em `executarVarreduraMatinal` e `executarVarreduraBatchComFila`; newsletter, pipeline preditivo e healthcheck diário não têm nenhum. Guarda: `api/test/disjuntor-cron.test.mjs`, 6 testes, prova reversa medida (`AssertionError: sync_cvm: expected true to be false`).
>
> **LOGINTIMING1 (P4-1).** `handleLogin` tinha três tempos para a mesma mensagem genérica. Medido contra o código antigo: inexistente 124ms, senha_errada 45ms, pendente 10ms, rejeitado 11ms. Todo caminho de falha passa a rodar um PBKDF2 (hash real ou `HASH_DUMMY_LOGIN`) e a sair pelo mesmo ponto com o mesmo jitter de 80-200ms; medido depois: 155/140/170/140ms. Os ramos `pendente` e `rejeitado` entraram porque eram o vazamento mais forte, respondiam sem hash e sem atraso. Mensagem genérica e rate limit de auth intactos. Guarda: `api/test/login-timing.test.mjs`, 3 testes, com controle positivo de login válido.
>
> **P3-1 e P3-3, só documentação, sem deploy.** Governança da skill `/vix-radar-general-audit` e de `references/audit-matrix.md` em v4.9.228 / v202.35 medidos ao vivo, com nota de que checar a condição de obsolescência é parte do passo 3 da própria auditoria. `CLAUDE.md` corrigido de 6 para 7 heartbeats do watchdog (`verificacao_async` entrou em `expectedAgents` em 18/08 por HEARTBEATVERIF1 e a doc não acompanhou), com os limites de staleness registrados.
>
> **Frontend não foi tocado e não está em drift.** Medido em 01/09: `app/index.html` `CACHE_VERSION="v202.35"` = `app/deploy_zip/version.json` = `https://vixradar.com/version.json` (`v202.35`, `deployed_at 2026-08-30T10:57:18Z`). Os 8 módulos de `app/js` batem por hash com os de `app/deploy_zip/app/js`, e o `index.html` bate por conteúdo (difere só por CRLF contra LF). Sem deploy de Pages nesta sessão, por não haver mudança de frontend.

> [!warning] 31/08 — CVMNOVOSDEAD1 DEPLOYADO no v4.9.226: `cvm_novos` estava zerado para os 103 emissores todo dia, desde 25/08. CVM volta a promover emissor sozinha, sem depender de imprensa.
> **Status:** vigente · **Data da Versão:** 2026-08-31 · **Origem do Registro:** auditoria pedida pelo operador depois da rotina noturna, achado ao investigar por que nenhuma promoção para APROFUNDADA veio de documento CVM. Deploy via `deploy-worker.ps1 -Version v4.9.226`, commit `9acd814`, push OK; commit anterior `3c88bb4` (código + testes + changelog WRCGL1).
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.226.
>
> **CVMNOVOSDEAD1 (bug estrutural, dois defeitos independentes).** `_cvmNovosEfetivo` aplicava o corte por
> data SEMPRE (não só no bootstrap), contra o dia civil da ÚLTIMA VARREDURA, que roda diariamente. A fonte
> CVM (`ipe_cia_aberta`) é semanal, publica aos domingos com `Data_Entrega` no máximo até a sexta-feira
> anterior. Medido em produção 31/08: `since` (dia da varredura anterior) = 30/08, máximo `data_entrega`/
> `data_referencia` do lote inteiro (103 emissores, duas colunas independentes) = 28/08. 28 < 30 para todo
> mundo, `cvm_novos=0` estrutural, não específico daquele dia. Segundo defeito, independente: `receber_analise`
> só chamava `marcarCvmVistos` se o corpo trouxesse `cvm_ids_analisados`, e nenhuma rotina jamais mandou (o
> plano expõe `cvm_novos_ids`, nome diferente) — `radar:cvm_vistos` nunca foi escrito para nenhum dos 103
> desde que SENTINELA1 existe (25/08). Os dois juntos mantiveram `cvm_delta_*`/`cvm_overnight_*` como caminho
> morto: toda promoção de hoje veio do bypass de imprensa (FONTELATENCIA1), nunca de documento CVM.
> **Fix:** corte por data só no bootstrap (`vistosIds` vazio); pós-bootstrap, identidade de protocolo basta.
> `receber_analise` deriva `cvm_ids_analisados` sozinho quando o cliente não manda (auto-cura, não depende de
> nenhum `SKILL.md` de rotina lembrar do campo). `SKILL.md` do noturno e da matinal (fora do repo, scheduled
> tasks locais) atualizados para mandar o campo explícito também.
>
> **CNPJVALIDA1, mesma sessão.** 5 subsidiárias reguladas da Neoenergia (Coelba, Celpe, Cosern, Elektro Redes,
> Afluente Transmissão) confirmadas ATIVO no `cad_cia_aberta.csv` vivo da CVM, adicionadas a
> `CNPJ_FAMILIA_CVM`, mesmo padrão CEMIG/Energisa. Prova em produção: Neoenergia foi de 0 para 1 documento no
> plano logo após o deploy. Banco Pan comentado como CANCELADA (30/03/2026, cancelamento voluntário) — CNPJ já
> correto, zero documento é a empresa saindo do regime, não falha de atribuição. Nexa Resources e Banco
> Votorantim confirmados sem registro Cia Aberta em nenhuma forma (ativa ou cancelada) no cadastro vivo —
> já tinham exceção declarada em `scripts/check-emissores-cadastro.mjs` desde 24/08, nada a corrigir.
>
> **Fonte intradiária oficial da CVM: avaliada e bloqueada só por credencial, não por impossibilidade técnica.**
> Correção sobre o registro original desta sessão: o **Download Múltiplo de Companhias** da CVM suporta
> automação e janela de até 24h, mas exige credencial própria da CVM que não existe neste ambiente — não é o
> mesmo bloqueio de RAD (`rad.cvm.gov.br`, reCAPTCHA v3/v2, bot-detection que não se contorna sob nenhuma
> instrução) nem o de `dadosdemercado.com.br` (Bearer token pago, ausente, conferido via `wrangler secret
> list`). Fica registrado como oportunidade futura de verdade, bloqueada só pela credencial ausente — sem
> solicitar ou gerar credencial nesta sessão. Arquitetura de detecção segue em duas camadas por ora: semanal
> (agora funcional) + imprensa (enriquecimento). Item aberto: avaliar o Download Múltiplo com credencial
> própria da CVM quando o operador decidir obtê-la.
>
> **Horário da rotina noturna: alterado no config, CONFIRMADO ATIVO pós-restart (31/08 tarde).** `cronExpression` do scheduled task
> `vixradar-noturno` mudou de `0 10 * * *` para `0 8 * * *` em
> `%APPDATA%\Claude\claude-code-sessions\...\scheduled-tasks.json` (backup feito antes,
> `scheduled-tasks.backup-20260831-122707.json`). Por INVERSAO-CD1, a edição só passa a valer depois de
> reiniciar o Claude Desktop — ação do operador, fora do alcance de qualquer agente, e não feita nesta sessão
> porque derrubaria a própria sessão em andamento. Até o restart, a rotina continua disparando às 10h00 BRT.
>
> **RESOLVIDO 31/08 (tarde), pós-restart.** Restart do Claude Desktop feito pelo operador. Confirmado via
> `list_scheduled_tasks`: `vixradar-noturno` carregado com `cronExpression:"0 8 * * *"`, `enabled:true`,
> próximo disparo `2026-09-01T11:05:24Z` (08h05 BRT). `lastRunAt` ainda reflete a execução de hoje às 10h05
> BRT, sob o cron anterior ao restart. Primeiro disparo real no novo horário só ocorre amanhã, fora do escopo
> desta checagem; watchdogs existentes cobrem eventual atraso.
>
> **Prova do deploy (regra 5, duas pontas):** health em produção `ok=true, versao=v4.9.226, kv=true,
> rate_limiter=true, telemetria=true, sentry_ok=true, verificador_ok=true, admin_email_ok=true,
> cvm_fonte_ok=true, providers_configurados="2/2"`, HTTP 200 em `api.vixradar.com` e
> `radar-credito-api.prospects-intel.workers.dev`. Suíte local 153/153 verde (18 arquivos, 8 testes novos com
> prova reversa: 3/8 falham contra o código anterior). 4 guardas locais de CNPJ/cadastro verdes após a edição
> (`check-alias-coerencia`, `check-metricas-curadas`, `check-emissores-cnpj`, `check-cnpj-familia`). git: local
> e remoto em `9acd814`, working tree limpo, bundle `api/v4.9.226.js` com `WORKER_VERSAO = "v4.9.226"`.

> [!info] 31/08 — VERIFCACHE-ROUNDTRIP1 + FALLBACKTTL1 DEPLOYADOS no v4.9.225: veredicto APROVADO_CORRIGIDO em cache já não vira rejeição no reenvio, e o cache de último recurso sobrevive a 1 dia sem varredura.
> **Status:** vigente · **Data da Versão:** 2026-08-31 · **Origem do Registro:** deploy via `deploy-worker.ps1 -Version v4.9.225`, commit `d88c293`, push OK; commits anteriores `78a0807` (código + teste + docs) e `774874f` (changelog WRCGL1).
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.225 (não há frontend neste deploy).
>
> **VERIFCACHE-ROUNDTRIP1 (bug):** o guard de entrada de `aplicarCorrecaoVerificador` (`worker.js`) exigia
> `veredicto.veredicto === "CORRIGIR"` cru, mas a própria função renomeia o campo para
> `"APROVADO_CORRIGIDO"` antes de a rotina gravar o objeto em cache (`confirmar_verificacao` grava
> DEPOIS da mutação). No ciclo seguinte a rotina reenvia o objeto literal do cache, o guard fechava a
> porta e o evento aprovado-com-correção era retratado do painel (medido em produção 27/08, Simpar).
> **Fix:** o guard aceita o round-trip (`veredicto_original === "CORRIGIR"` além de `veredicto === "CORRIGIR"`),
> o que identifica exatamente o objeto que a própria função gravou; correções são re-aplicadas ao evento
> fresco e o reenvio aprova de forma idempotente. Teste de duas pontas novo em
> `api/test/verif-cache-roundtrip.test.mjs`.
>
> **FALLBACKTTL1 (30/08):** `fallback:{empresa}` com `expirationTtl` 86400→86400*3 (72h) na escrita e corte de
> idade 24h→48h na leitura, coordenados. Dia sem varredura (28/08) não apaga mais o fallback dos 103 emissores
> nem os eventos Tier1/FR de ADR-040 (mesma chave). VOLTTL1: TTL ≥ 2× o intervalo de escrita.
>
> **Prova do deploy (regra 5, duas pontas):** health em produção `ok=true, versao=v4.9.225, kv=true,
> rate_limiter=true, telemetria=true, sentry_ok=true, verificador_ok=true, admin_email_ok=true,
> cvm_fonte_ok=true, providers_configurados="2/2"`, HTTP 200 em `api.vixradar.com` e
> `radar-credito-api.prospects-intel.workers.dev`. Validação do script: `DEPLOY OK - producao em v4.9.225, repo e
> GitHub sincronizados.` Suíte local 145/145 verde (18 arquivos). git: local e remoto em `d88c293`, working tree
> limpo, bundle `api/v4.9.225.js` com `WORKER_VERSAO = "v4.9.225"`.
>
> **Lacuna registrada, não fechada:** FALLBACKTTL1 sem teste automatizado para o par
> `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte` (ver entrada 30/08 em `PENDENCIAS.md`).

> [!info] 30/08 (noite) — CCDOFFLINE1: causa raiz do buraco de 28/08 medida, o Claude Desktop não reabre sozinho depois de reboot do Windows.
> **Status:** ABERTO, ação só do operador (1 toggle do Windows). · **Data da Versão:** 2026-08-30 · **Origem do Registro:** investigação pedida em sessão a partir da observação nova de mais cedo hoje ("sexta 28/08 sem log, causa a apurar"), medição via `Get-WinEvent` (System/Application), `AppxManifest.xml` do pacote MSIX, registro de `Run`/Startup/Scheduled Tasks · **Condição de Obsolescência:** cai quando o toggle "Iniciar automaticamente" estiver ligado para o Claude e sobreviver a um reboot real sem intervenção manual.
>
> A máquina ficou ligada o tempo todo em 28/08 (uptime contínuo medido, refuta sono/desligamento). Windows Update
> forçou um reboot duplo às 03:01-03:03 BRT (KB5120998 + KB5122385, instalação e reboot correlacionados no log).
> O Claude Desktop (MSIX) tem `StartupTask` declarado no manifesto mas `Enabled="false"`, e nada mais no Windows
> reabre o app depois de reboot (sem entrada em `Run`, `RunOnce`, pasta Startup ou Scheduled Tasks). O CCD que
> dispara noturno/matinal/verificação (achado em INVERSAO-CD1) só avalia cron com o app de pé, então ~36h sem
> nenhum agendamento sendo sequer avaliado, não só pulado. Os watchdogs `Szuchmacher-RetryVixNoturno/Matinal`
> detectaram e documentaram corretamente que o caso está fora do alcance deles. Correção: Configurações →
> Aplicativos → Inicialização → Claude → `On`, fora do alcance de qualquer agente (config de sistema). Detalhe
> completo, evidência linha a linha e proposta de guarda adicional em `PENDENCIAS.md` (CCDOFFLINE1).

> [!info] 30/08 (noite) — FALLBACKTTL1 corrigido no código (2 linhas, não 1), aguardando deploy.
> **Status:** vigente, não deployado · **Data da Versão:** 2026-08-30 · **Origem do Registro:** execução do item aberto em 29/08 (noite), leitura completa dos dois lados de `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte` · **Condição de Obsolescência:** cai quando deployado em produção e validado.
>
> O fix de 1 linha proposto em 29/08 (só o `expirationTtl`) não resolvia o sintoma: a leitura
> (`buscarCacheUltimoResorte`) tem corte de idade próprio, independente do TTL do KV, que continuaria recusando
> servir qualquer coisa com mais de 24h. Fix real: `expirationTtl: 86400 → 86400*3` na escrita **e**
> `idadeHoras > 24 → > 48` na leitura, coordenados. Sobrevive a 1 dia inteiro sem varredura sem piorar nada para
> quem recebe o fallback (piso de confiança já saturava em 0,3 antes disso). Suíte local `143/143` verde. Detalhe
> em `PENDENCIAS.md` (FALLBACKTTL1).

> [!info] 30/08 (noite) — CLAUDE.md corrigido: o fato da Fitch/CSN citado em SUBSTRINGDONO1 estava errado, sem relação com código ou deploy.
> **Status:** vigente · **Data da Versão:** 2026-08-30 · **Origem do Registro:** sessão de avaliação da Exa (exa.ai) como segunda fonte de ingestão para o Radar, três buscas de backtest rodadas no playground, uma delas trouxe o relatório completo da Fitch (espelhado em `api.mziq.com`, já que `fitchratings.com` bloqueia crawler) e confirmação por busca web independente ·
> **Condição de Obsolescência:** não expira, é correção factual permanente.
>
> A linha de SUBSTRINGDONO1 no `CLAUDE.md` dizia "a CSN foi rebaixada pela Fitch de B para CCC+ em 31/07". Os três dados
> estavam errados. Não houve rebaixamento, a Fitch **afirmou** o rating em BB e só revisou o outlook de estável para
> negativo, a mudança nunca chegou perto de B ou CCC+, e a data da ação foi 04/08, não 31/07 (o relatório foi datado
> "Fitch Ratings - New York - 04 Aug 2025" no corpo do texto). Corrigido no `CLAUDE.md`. A narrativa do incidente em si
> (documento de grupo econômico indo para o emissor errado) continua válida e não foi tocada, só o fato usado para
> ilustrá-la.
>
> **Achado paralelo, ainda não decidido:** o mesmo relatório cobre CSN, CSN Mineração, CSN Inova Ventures, CSN Resources
> e CEEE-G num documento só. Se a Exa for integrada como fonte, o `_donoDocumentoCVM` (que responde "de quem é este
> documento") vai precisar aceitar múltiplos donos para um documento, coisa que ele não faz hoje. Isso é decisão de
> modelo de dado, não ajuste pontual, e não deve ser feito por baixo antes de discutir. Nenhum código foi alterado
> nesta sessão, é achado de teste manual no playground da Exa fora do sistema de produção.

> [!info] 30/08 (tarde) — PISODIFF1 DEPLOYADO (Worker v4.9.224 + frontend v202.35): o card mostra a gravidade real dentro do grupo pisado.
> **Status:** vigente · **Data da Versão:** 2026-08-30 · **Origem do Registro:** deploy v4.9.224 validado em produção (portão HTTP 200, `ok/telemetria/kv/sentry_ok` true, `versao:v4.9.224`), deploy v202.35 validado (version.json apex `v202.35`, `CACHE_VERSION` no HTML, card `Score sem piso` servido no apex), suíte vitest 143/143 · **Condição de Obsolescência:** cai quando o Worker passar do v4.9.224 e o frontend do v202.35.
>
> **PISODIFF1 (decisão do operador, 30/08).** O piso EWS (61 para RJ/default ativo) colava três empresas em situações bem diferentes na mesma nota, Raízen, Oncoclínicas e Oi em 66 (piso crítico 61 + padrão de deterioração +5). A solução escolhida foi o card duplo: o score com piso continua no destaque e o contrafactual honesto `score_calculado` (sinais reais + bônus, sem piso) aparece abaixo como `Score sem piso: N`. O ranking (`op=ews`) desempata scores iguais por `score_calculado` desc, então o grupo pisado ordena por gravidade dos sinais, não por ordem de lista. A escada de piso por severidade (61/70/78) ficou como P2, depende de fonte estruturada de severidade e não foi implementada agora.
>
> Correção no caminho do deploy: o bump manual de `CACHE_VERSION` para v202.35 não tinha alcançado os `?v=` dos imports, recaída do CACHEBUMP1, pego pelo gate 3.4 do próprio `deploy-pages.ps1`. Revertido e refeito via `bump-cache-version.ps1`, que alinha os 5 pontos juntos.

> [!info] 30/08 (manhã) — frontend v202.34 DEPLOYADO, AGENDASEM-TRAVA1 com causa medida (reboot, não o lote 3).
> **Status:** vigente · **Data da Versão:** 2026-08-30 · **Origem do Registro:** deploy validado em produção (apex e www em `v202.34`, `deployed_at 2026-08-30T10:22:53Z`, HTML e módulo servido em `?v=202.34`), medições ao vivo (`Get-ScheduledTaskInfo`, `Get-WinEvent` Kernel-Power, health do Worker) ·
> **Condição de Obsolescência:** cai quando o frontend passar do v202.34 e quando o monitor julgar a AgendaSemanal pela cadência real dela.
>
> **Frontend v202.34 no ar.** Produção estava em `v202.33` desde 25/08, cinco dias atrás do repo, e o trabalho de 29/08
> (EWSFLOOR1, MATERIALSAT1, BRIEFDEDUP1) estava commitado e parado no disco. Nenhum documento registrava essa defasagem.
> Deploy pelo `deploy-pages.ps1`, 7 gates verdes, commit `cc6f7ff` empurrado. Os 15 imports de `app/js` no `deploy_zip`
> saíram de `?v=202.33` para `?v=202.34`. **TOKENCHAT1 remedido no caminho:** o `CLOUDFLARE_API_TOKEN` instalado tomou
> `Authentication error [code: 10000]` na API de Pages, e o deploy só passou porque existe sessão OAuth do wrangler nesta
> máquina, renovada em 30/08 01h41. Deploy de Pages hoje depende de um humano ter logado no navegador, qualquer caminho
> não interativo falha.
>
> **AGENDASEM-TRAVA1: o lote 3 está inocente.** O lote 3 começou 26/08 22:14:44 e o Kernel-Power 109 (transição de
> desligamento) mais o 577 (reinicialização iniciada pelo sistema) entraram 22:16:27 e 22:16:29. `0x40010004` é processo
> morto de fora, e as duas hipóteses de timeout caem por medição (`ExecutionTimeLimit=PT4H`, wrapper sem guarda própria).
> E não foram 3 dias de falha: `DaysOfWeek=9` é domingo **e** quarta, a falha foi uma só (quarta 26/08), a janela seguinte
> é 30/08 22h e `NumberOfMissedRuns=0`. O `idade=3d ESCALADO` do monitor é releitura do mesmo `LastTaskResult` congelado.
> Mesmo defeito de leitura do SENTINELA-DIAPERDIDO1. Corrigidas junto as duas linhas de resumo que diziam "Dom 22h00"
> (`CLAUDE.md` e `routines/README.md`), que contradiziam a nota longa do próprio `routines/README.md`. Detalhe e guarda
> exigida na `PENDENCIAS.md`.

> [!info] 30/08 (madrugada) — AGENDA401 DEPLOYADO no v4.9.223, RECONCILE-CVM404 corrigido no código, SENTINELA-DIAPERDIDO1 refutado por medição.
> **Status:** vigente · **Data da Versão:** 2026-08-30 · **Origem do Registro:** deploy v4.9.223 validado em produção (portão HTTP 200, `ok/telemetria/kv/sentry_ok` true), medições ao vivo (task Sentinela via `Get-ScheduledTaskInfo`, logs das rotinas, suíte vitest local, dry-run da reconciliação) ·
> **Condição de Obsolescência:** cai quando AGENDASEM-TRAVA1 fechar.
>
> AGENDA401 (P1) **DEPLOYADO no v4.9.223** (`26aba9c`): `op=calendario` liberado sem JWT (`api/src/worker.js:17627`), teste
> anônimo de duas pontas em `api/test/agenda-validacao.test.mjs` (10/10 verdes). Prova em produção 30/08 02:51 BRT:
> `GET /?op=calendario` sem token → `ok:true`, 103 emissores, 81 com calendário; `?op=calendario&escopo=agenda&horizonte=90` → `ok:true`.
> RECONCILE-CVM404 (P2): `scripts/predictive/reconciliar_ipe_cvm.ps1` ganhou fallback de catálogo CKAN no 404 e checagem de
> magic PK antes do extract, validado parse 5.1, lint (RISCO 0) e dry-run (exit 0). O ZIP 2026 já voltou ao ar pela CVM
> (medido 25/08), então segunda 31/08 deve seguir o caminho canônico; o fallback fica como defesa e como mensagem estruturada
> `fonte_ausente_no_catalogo` se o catálogo não conhecer o ano.
> SENTINELA-DIAPERDIDO1 (P1 do 93): **refutado por medição.** 29/08 é sábado e a task roda só Seg-Sex (`DaysOfWeek=62`),
> `LastRun=28/08` (sexta) 17:55, `NumberOfMissedRuns=0`, e o log de 28/08 existe com 18 linhas `FIM:` (cadência :25/:55 correta).
> Não houve dia útil perdido; as auditorias 93/95 erraram o dia da semana ao chamar 29/08 de "sexta". Mesmo assim o vigia
> defensivo entrou (`scripts/lib/vixradar-watchdog.ps1` + ramo no `monitor-tasks.ps1`), prova de duas pontas 4/4, e o monitor
> real saiu `ROTINA OK: VIXRadar-Sentinela (entrega) | 2026-08-28 execucoes_com_fim=18`.
> **Observação nova (fora do plano):** sexta 28/08 não tem log nem da matinal nem da noturna (os logs pulam de 27/08 pra 29/08)
> e as duas rodaram só no sábado 29/08 à tarde. O monitor já sinaliza a matinal (9001). Detalhe na PENDENCIAS.

> [!info] 29/08 (noite) — segunda auditoria geral do dia com trabalho v4.9.222 em voo. 3 achados novos, todos registrados.
> **Status:** vigente · **Data da Versão:** 2026-08-29 · **Origem do Registro:** auditoria `/vix-radar-general-audit` (noite),
> medições ao vivo (health, Scheduler, event log, suíte local) · **Condição de Obsolescência:** cai quando
> SENTINELA-DIAPERDIDO1, AGENDASEM-TRAVA1 e FALLBACKTTL1 fecharem na PENDENCIAS.
>
> Correção de estado: o merge da `fix/silent-green-2026-08-27` **já chegou em `main`/`origin/main`**
> (`ab2622f` e `a1c5283` contidos em `origin/main`, medido), então o pré-check do scan-emergencia e a
> notificação do frescor-check já valem no cron. O que este arquivo dizia de manhã ("merge pendente") caducou.
>
> Achados novos, detalhe na PENDENCIAS: **P1 SENTINELA-DIAPERDIDO1** (Sentinela não executou nenhuma vez na
> sexta 29/08, âncora 09h25/09h55 perdida no sono da máquina mata a cadeia de repetição do dia, task toda verde,
> nenhum vigia cobre); **P2 AGENDASEM-TRAVA1** (AgendaSemanal morta no lote 3 desde 26/08, exit 0x40010004,
> monitor escalando há 3 dias sem dono); **P2 FALLBACKTTL1** (`fallback:{empresa}` com TTL de 24h, o gap de
> 28/08 apagou o cache de último recurso dos 103, viola a regra VOLTTL1). Adendo no WATCHDOG-NAOINICIOU1: a
> única tentativa real do alerta novo falhou por conexão (transporte testado ok depois, recomendada retentativa).
>
> **P1 REPOSIC1 CORRIGIDO — feed preso em 25/08 tinha uma terceira causa além da CVM: 28/08 não teve varredura
> e a passada de 29/08 re-ancorou o desenvolvimento em fato antigo.** Reposição executada e verificada em
> produção (Braskem 28/08 CRÍTICO, Oncoclínicas 27/08 CRÍTICO, Multiplan 27/08 ECO, Petrobras 26/08 ECO, max
> `data_evento` 25/08 → 28/08). Guarda = skill nova `/repor-varredura` + `scripts/repor-varredura.ps1` +
> prompt anti-ancoragem. Dois achados de busca mostraram por que data sai da fonte, nunca do resumo: "Moody's
> reafirma Petrobras 27/08" era artigo de 2015 e "Fitch eleva Petrobras 26/08" era de 2025, o Worker rejeitou
> a primeira corretamente. Detalhe na PENDENCIAS.
>
> Trabalho em voo de outra sessão (plano v4.9.222, Fases 1.1 a 1.3) revisado sem tocar: EWSFLOOR1 (piso como
> metadado), MATERIALSAT1 (boost de tag amortecido no CRITICO) e BRIEFDEDUP1 (dedup do top 10 do briefing),
> com bump v202.34 já sincronizado no deploy_zip do index. Suíte local com o código em voo: **141/141 em 17
> arquivos** (inclui os 3 testes novos untracked). Nota de revisão registrada: `score_calculado` não inclui o
> bônus de +5 do "Padrão de deterioração", então o contrafactual "sem piso" subestima em 5 pontos quando
> nSinaisRisco>=3; e os 4 módulos de `app/js` ainda divergem do `deploy_zip` (o `deploy-pages.ps1` sincroniza
> no deploy, conferir o gate 3.4).

> [!info] 29/08 (tarde) — auditoria geral fechada, P0, P1, P2 e P3 corrigidos na branch `fix/silent-green-2026-08-27`.
> **Status:** vigente · **Data da Versão:** 2026-08-29 · **Origem do Registro:** sessão de correção
> após auditoria `/vix-radar-general-audit` (29/08) ·
> **Condição de Obsolescência:** cai quando a branch chegar a `main` e o cron rodar com as guardas novas.
>
> Diagnóstico do feed: o painel não mentiu. Não existe evento datado >= 26/08 em produção
> (re-probe: TOTAL 496, MAX `2026-08-25`, 0 eventos depois). A noturna de 29/08 varreu 103/103
> mas deferiu 60 emissores da cauda por orçamento de tokens. Próxima atualização natural:
> publicação da CVM em 30/08.
>
> P0 `SCANFALLBACK-MORTO1`: secret `ANTHROPIC_API_KEY` criado pelo operador e pré-check de
> secrets no `scan-emergencia.yml` (`ab2622f`). P1 `WATCHDOG-NAOINICIOU1`: `retry-vixradar.ps1`
> alerta via `notificar_rotina` e sai 1 no dia sem log (`5acbca2`), efetivo local. P2
> `FRESCORNOTIFY1`: `frescor-check.yml` ganhou passo `if: failure()` de notificação (`a1c5283`).
> P3: docs commitados (CLAUDE.md, ARQUITETURA-TECNICA, recado `92 - Vistoria Feed Noticias`).
> Portão: HTTP 200, `ok:true`, v4.9.221.
> ~~**Ação pendente do operador:** merge da branch em `main` para P0 e P2 valerem no cron.~~
> **Feito: o merge chegou em `main`/`origin/main` (medido na auditoria da noite de 29/08), guardas ativas no cron.**
> `VERIFCACHE-ROUNDTRIP1` segue ABERTO (exige deploy).

> [!info] 26/08 (tarde) — deploy v4.9.221: TTL de `cvm:documentos` unificado e telemetria de atribuição CVM ligada.
> **Status:** vigente · **Data da Versão:** 2026-08-26 · **Origem do Registro:** deploy validado
> contra produção v4.9.221, health ao vivo (`ok=true`, `kv=true`, `telemetria=true`, `sentry_ok=true`) ·
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.221.
>
> Auditoria geral achou dois P2, confirmados por revisor independente e corrigidos nesta versão.
> `cvm:documentos` tinha TTL de 14 dias na escrita manual de admin e 30 no caminho automático,
> o fix do v4.9.210 tinha alcançado só um dos dois (CVMTTL1). Agora é uma constante única,
> `CVM_DOCUMENTOS_TTL_SEG`, nos dois call sites.
> E a telemetria de atribuição CVM era cega por construção: a meta grava cobertura, descartados
> e último sync ok, mas o leitor não lia, e o health devolvia zeros no verde (ATRIBTEL1). O elo
> meta→health foi ligado, medido ao vivo: `cvm_atribuicao_por_cnpj:793`, `quarentena:1333`,
> `cobertura_pct:37,3`, `cvm_fonte_ultimo_sync_ok_em` datado. A guarda do SUBSTRINGDONO1 deixou
> de ser cega.
> Testes: suíte 128/128, alvo 61/61. Commits `91246e1`, `e3d3490`, `2e45676` (deploy, pushado),
> `08dd511` (PENDENCIAS fechado), `933825f` (governança da skill em v4.9.221).

> [!info] 25/08 (noite) — horários invertidos e nasce a varredura pontual. Worker **v4.9.217**.
> **Status:** vigente · **Data da Versão:** 2026-08-25 · **Origem do Registro:** medido
> contra produção v4.9.216, `Get-ScheduledTask` ao vivo, suíte 117/117 ·
> **Condição de Obsolescência:** cai quando o mecanismo de agendamento do Claude Desktop
> mudar, ou quando existir ação de sync da CVM com escopo de rotina.
>
> A varredura completa dos 103 passa a rodar às **10h** e o top 15 às **18h**. Os nomes
> das rotinas ficaram invertidos de propósito, ao ler log vá pelo horário. Motivo: ao
> meio-dia, 88 dos 103 tinham dado da noite anterior, e fato relevante sai depois do
> fechamento. Vigias de retry trocados junto (13h30 e 21h30), senão o sistema relançaria
> rotina à toa todo dia útil.
>
> Três defeitos achados ao medir, todos corrigidos no v4.9.216. Documento entregue no
> mesmo dia civil de uma varredura nunca contava como novo, e isso já mordia o top 15.
> `_last_scanned_at` é instante UTC e `data_entrega` é dia civil BRT, e entre 21h e
> meia-noite a comparação errava (RELOGIO3H1 de novo). E a janela fixa de 16h do gatilho
> da matinal morreria calada com a rotina às 18h.
>
> Rotina nova `VIXRadar-Sentinela`, duas vezes por hora aos :25 e :55, dias úteis 09h25
> a 17h55. Analisa só quem tem gatilho duro, teto de 8 emissores e 120k tokens, e na
> maioria das execuções sai em 0 token. Achado que ela expôs de imediato: **34 emissores
> parados na fila de deferidos** por teto. A causa apareceu ao rodar a rotina duas vezes
> e comparar as listas: a bandeira `_token_cap_deferred` ligava e nunca desligava, então
> emissor deferido uma vez virava FULL permanente na noturna, gastando 9 rodadas de busca
> todo dia e realimentando o próprio deferimento (DEFERGRUDA1, corrigido no v4.9.217).
> A CVM também repôs o arquivo que sumiu em 23/08, publicado às 07h58 e ingerido só às
> 12h30.

> [!warning] 24/08 (4ª rodada) — a noturna antecipada rodou inteira e o painel não andou.
> `FIM: tokens=390287 submit_ok=70 submit_fail=0 silent_fail=0 deferred=15 criticos=10`,
> fila de verificação drenada até zerar, 12 aprovados e 3 rejeitados. Mesmo assim o fato
> mais recente continua 20/08. Não é ausência de fato: a Braskem protocolou recuperação
> extrajudicial hoje e o sistema não pegou. Falha de detecção com contraexemplo
> confirmado. A rodada rendeu 5 defeitos, 2 no Worker e 3 no script da noturna, todos
> corrigidos e commitados em `2928a74`. Os do Worker aguardam autorização de deploy.

> [!info] 24/08 (3ª rodada) — carteira corrigida e noturna antecipada.
> AES Brasil saiu (incorporada pela Auren, que já estava nos 103) e a Braskem
> entrou, no dia em que pediu recuperação extrajudicial. Total segue 103, Worker
> em **v4.9.212**. Braskem declarada nas três pontas de alias de saída, aplicando
> a lição do NOMEMORTO1 na entrada em vez de descobrir depois. A rodada noturna
> foi antecipada para as 15h58 a pedido do operador, para medir de uma vez o
> CAPRESERVA1, o NOMEMORTO1 e o contador do CVMDURA1, que nunca rodaram juntos.

> [!warning] 24/08 (2ª varredura) — parte do buraco nunca foi da CVM.
> A Eletrobras virou AXIA ENERGIA em 10/11/2025 e os documentos dela **estavam
> gravados** no KV, invisíveis: três tabelas de alias que precisavam concordar e
> não concordavam. Nove meses de emissor exibido como `sem_eventos`. Mesma
> família, a Sabesp ficava órfã por acento no nome. Worker em **v4.9.211**:
> Eletrobras 0 → 28 documentos, Sabesp 0 → 11, órfãos 2 → 1. Aliases novos para
> MOTIVA (ex-CCR) e SERENA (ex-Omega). Guarda semanal na nuvem conferindo os 103
> contra o cadastro vivo da CVM, com prova das duas pontas dentro do próprio CI.
> 62 testes passando. Quatro emissores seguem sem registro ativo, tolerados com
> motivo declarado, aguardando decisão do operador.

> [!warning] 24/08 — painel travado em 20/08: a fonte da CVM morreu em silêncio.
> `ipe_cia_aberta_2026.zip` sumiu do servidor da CVM em 23/08 (404, listagem só até
> 2025.zip, catálogo CKAN ainda anunciando). `cvm:documentos` congelou em 15/08, as
> rotinas perderam o gatilho primário de evento e passaram a reciclar imprensa velha.
> As 3 rotinas rodaram normalmente nos dias 21, 22 e 23, 103 emissores varridos toda
> noite. Worker em **v4.9.210** com CVMURL404, CVMMETAWIPE1, CVMDURA1 e VOLTTL1:
> falha dura de fetch deixa de ser tratada como cadência semanal, escala para o `ok`
> agregado após 4 syncs falhos, e o `frescor-check.yml` passa a nomear o campo sem
> depender do Health-Watch (desligado desde 21/08). Cap da noturna com reserva para a
> fila aprofundada (CAPRESERVA1), que vinha sendo deferida inteira. 55 testes passando.
> **A CVM ainda não repôs o arquivo**, então a ingestão de Fato Relevante segue parada
> e os eventos dependem só de imprensa e RAD até lá.

> [!success] 24/08 — sessão anterior fechada. SACFALSA-RESIDUO e CACHEBUMP1 resolvidos e
> commitados. 3 commits em main (`6b4b34d` Gate 6/SACFALSA, `2af4c82` CACHEBUMP1,
> `3e0691c` nota 90). Gate 6 do pre-commit agora reprova só a frase órfã da causa
> falsa do vitest (marcador de refutação na janela ±3). O `bump-cache-version.ps1`
> daí de bater no copy/UI (âncora em CACHE_VERSION= e ?v=) e de colidir `?v=202.3`
> com `?v=202.30` (lookahead), com teste de regressão. Cinco regras permanentes de
> auditoria adicionadas ao CLAUDE.md. WORKTREE12 fechado na continuação: 4 das 6
> worktrees do Claude Code eram checkout parado sem valor (removidas), 2 tinham
> trabalho real (RETRY-PROP1 em `deploy-worker.ps1` + extensão de `ROTINA_RESUMO`
> em 2 rotinas), fundido a mão em cima do main atual e commitado, as 2 worktrees
> removidas depois. Push feito.

Leia este arquivo antes de começar qualquer trabalho, seja qual for o agente.
Atualize a data e os itens abertos ao fechar uma sessão que mudou o estado.
Não duplique conteúdo do CLAUDE.md nem do README.md: aqui fica só o ponto de
partida com os ponteiros.

## O que é

Sistema de inteligência de crédito privado com IA que monitora 103 emissores de
renda fixa no Brasil e classifica eventos por criticidade (CRÍTICO / RELEVANTE /
ECO / RUÍDO). O backend roda 100% em Cloudflare (Worker + KV + DO + Analytics
Engine), mas o cérebro de IA é local: scripts PowerShell agendados no Windows
Task Scheduler chamam o Claude CLI e enviam o resultado ao Worker por POST
autenticado com `routine_key`.

## Estado em 2026-08-22

Produção em Worker v4.9.208 e frontend v202.30. Os cinco achados P3 da
auditoria geral foram fechados. O changelog do Worker recuperou as versões
v4.9.196 a v4.9.208 e ganhou um portão obrigatório. O frontend passou a contar
emissores no pulso e a declarar a janela de 30 dias no card. O fluxo de Pages
agora só carimba `version.json` depois que todos os portões passam.

O painel de eventos agora declara o horário de atualização da base separado da
data do último evento. Em 21/08, as rotinas concluíram 103/103 sem encontrar
fato com aquela data, e a tela só mostrava o último fato de 20/08. A mudança
evita que ausência de fato novo pareça falha de atualização.


## Estado em 2026-08-21

Deploys do dia: v202.22 (hotfix de sintaxe) e v202.23 (copy da landing). Causa do
hotfix: a edicao AUTONOMIAOFF1 deixou dois tokens orfaos nos blocos 6 e 8 do
index.html e o painel ficou degradado desde o deploy de 21/08 01:40Z. Health do
Worker nunca acusaria, o defeito era parse de JS no frontend. Fix em d5bb5b8,
deploys 9794d82 e 5c77254, validados e com push. Landing corrigida de
"100 emissores" para "103 emissores" (4 pontos), alinhando com TOTAL_EMISSORES=103.
Pacote comercial para o Luciano pronto em
E:\Diretorio\Claude\apresentacao-luciano-2026-08-21 (mensagem, 2 PDFs, video 9:16).
Segue aberto: CLOUDFLARE_API_TOKEN sem permissao de Pages (CREDOAUTH1), o deploy
cai no OAuth do wrangler.

Noite de 21/08 (sessao multi-provedor, Claude Desktop sem creditos): as tres
rotinas do dia rodaram por contrato HTTP direto (verificacao 23/23, matinal 19/19,
noturna 103/103, health ok:true, ver nota 87 do vault). Em seguida, sessao de
frontend: refresh de dados ao voltar para a aba (visibilitychange/pageshow chamam
carregarResultadosCompartilhados, throttle de 60s) e rodada de melhorias mobile
auditada com Lighthouse. Deploys v202.24 (refresh, continha SyntaxError corrigido
em v202.25), v202.26 (contraste, labels, alvos de toque, ranking EWS empilhado),
v202.27 (aria-labels dos filtros, bottom nav escondida com drawer aberto), v202.28
(drawer fechado invisivel). Final: A11y 100, Best Practices 100, SEO 100 no
Lighthouse mobile. Restam CLS ~0.16-0.43 (varia entre rodadas) e itens da
categoria agentic browsing (llms.txt, agent-accessibility-tree). Ver nota 88.
## Estado em 2026-08-18

Segundo o CLAUDE.md (hardened 2026-07-25) e o README: produção em Worker v4.9.198
(confirmado ao vivo em 2026-08-18 via health check) e frontend v202.10 (confirmado
em 2026-08-15), 103 emissores em 13 setores. A migração KV→DO está em andamento
com o KV ainda como fonte da verdade (dual-write com fail-open: um DO quebrado não
derruba o sistema, mas a migração pode parar em silêncio). A rotação da
`routine_key` segue como decisão pendente do usuário. O CLAUDE.md não tem seção
formal de pendências; cada item aberto está resumido em "Itens abertos" abaixo,
com o detalhe no CLAUDE.md.

Hoje, 17/08: criado o retry automático com as tasks Szuchmacher-RetryVixNoturno
(21:30) e Szuchmacher-RetryVixMatinal (13:30), script `scripts/retry-vixradar.ps1`,
e o `monitor-tasks.ps1` ganhou regras de cota e guard. Matinal do dia rodou via
sessão agendada (19/19 emissores, 6 CRITICO), detalhe no vault
`Obsidian VIX Radar/03 - Estado Atual.md`.

Hoje, 18/08: primeira prova ao vivo de dual-execução na fila de verificação
adversarial — a sessão local (Claude Desktop) e a nova Claude Code Routine remote
drenaram a mesma fila `radar:verif_fila` em paralelo, com reserva atômica
confirmada (`protecao_ativa:true`, CONCORVERIF1). Fila de 26 itens foi para 0: a
sessão local processou 6 (4 reaproveitados via `cache_hits` sem busca nova, 2
verificados do zero contra fonte primária CVM — Movida e Aegea Saneamento), a
remote já tinha reservado e processado os outros 20 cerca de 11 minutos antes.
Health final voltou `ok:true` e `verificador_ok:true` (a fila drenada derruba o
`verificador_ok:false` sozinha, sem reinício). Corrigida na mesma sessão a
documentação do contrato de `confirmar_verificacao` (contagens vêm aninhadas em
`resultado{}`, não na raiz) e a regra de reaproveitamento de `cache_hits`, ver
`routines/README.md` e o `SKILL.md` da rotina `vixradar-verificacao-async`.
Nenhuma alteração de código nem deploy nesta sessão, só documentação.

Ainda em 18/08, à noite, a junction NTFS do projeto foi invertida. O caminho físico
canônico passou a ser `E:\Diretorio\Claude\Monitoramento de Credito`, e
`E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito` virou junction legado de
compatibilidade apontando para ele. Antes era o contrário. Rodou por script
transacional com rollback automático, preflight que barra a operação se qualquer
processo tiver working directory dentro da árvore, e baseline capturado em runtime
na mesma execução, sem nenhum valor de referência gravado no código. A validação
fechou com 43890 arquivos, 5787 pastas, delta zero de bytes, HEAD
`a3462c29ef5066a0e92c80932e1ed6f22a238d06` preservado, 12 worktrees íntegros e as 12
tarefas agendadas resolvendo seus scripts. Log em
`%TEMP%\mdc-inversao-20260818-193245.log`.

Duas tentativas anteriores falharam porque sessão do Claude Code viva no diretório
arrasta cerca de trinta processos filhos que herdam o working directory e seguram a
raiz, e é por isso que o preflight passou a existir.

A migração fechou na mesma noite. Das 12 tarefas agendadas que referenciam o projeto,
as 8 que ainda usavam o caminho legado foram reapontadas para o canônico preservando
ação, argumentos, trigger, usuário e privilégio. O `VIXRadar-Health-Watch` só aceitou
a mudança sob execução elevada, por usar logon S4U, e a primeira tentativa sem
elevação abortou e reverteu sozinha. O worktree `quizzical-nightingale-0c534b` foi
normalizado com `git worktree repair` apontando o caminho canônico, então o `.git`
dele, o `gitdir` no repo principal e o `worktree list --porcelain` deixaram de citar
FREQUENTE. A alteração local que esse worktree carregava foi preservada intacta.

O `FREQUENTE\Monitoramento de Credito` continua existindo como junction, mas agora só
por compatibilidade. Nenhuma tarefa, worktree ou metadado do git depende mais dele.

Ainda 18/08, à noite: FASE 2 de governança das rotinas fechada. Achado principal: a
`VIXRadar-AgendaSemanal` estava morta em silêncio desde antes de 10/08 (rodava sem shell,
gravava `FIM: concluido` sem fazer nada, 20 emissores com calendário trimestral vencido em
produção). Corrigida com `scripts/run_vixradar_agenda_semanal.ps1` dedicado, validado com dois
testes ao vivo contra produção (o primeiro interrompido pelo limite de uso da própria conta do
usuário durante a sessão, com falha corretamente reportada em vez de mascarada; o segundo
limpo, exit 0, 8/20 emissores atualizados, confirmado fora do script via nova consulta a
`listar_calendario_stale`). Também corrigidos: `VIXRadar-Ranking-Mensal` descontinuada
formalmente (task não existe no Scheduler há 5+ semanas), segunda Remote Routine não
documentada (`VIX Radar — frescor diário`) trazida para `routines/README.md`, cron da
verificação assíncrona remota corrigido (estava 3h fora do horário prometido desde a criação
no mesmo dia, string do cron local colada sem converter fuso), `ROUTINES-CLOUD.md` de
matinal/noturno marcados órfão/especulativo. Matriz completa das 13 rotinas locais + 2 remotas
+ 5 GitHub Actions + 4 Cloudflare Cron em
`Obsidian VIX Radar/10_Estado_Atual_Validado.md`. Na verificação de fechamento, mais um achado:
`retry-vixradar.ps1` e `monitor-tasks.ps1` tinham o mesmo regex que não reconhecia a frase real
"N/N emissores processados" da matinal, causou um retry falso em 17/08 (rotina já tinha
entregue, watchdog relançou à toa); corrigido nos dois arquivos, commit `ad06ad4`. Health
final: `ok:true kv:true telemetria:true sentry_ok:true verificador_ok:true`, v4.9.198.

Auditoria geral readonly (23h50, skill `vix-radar-general-audit`) achou que a migração da
junction acima fechou a Action das 12 tarefas e o worktree, mas não alcançou o conteúdo interno:
26 `.ps1` (incluindo `run_claude_routine.ps1`, todos os `run_vixradar_*.ps1`,
`monitor-tasks.ps1` e os `register-*-task.ps1`) mais `matinal/SKILL.md` e `noturno/SKILL.md`
continuam com `$ProjectRoot`/`$VixRoot` hardcoded em `FREQUENTE\Monitoramento de Credito`. Não
quebra hoje (a junction resolve), mas contradiz a afirmação "nada depende mais dele" logo acima
e é o tipo de lacuna que convida alguém a remover a junction achando que é seguro. Detalhe e
correção proposta em `PENDENCIAS.md` (P1, 18/08 23h50). Também achado: saída de dry-run do
Ranking-Mensal (descontinuado nesta sessão) ficou untracked por falta de padrão no
`.gitignore` (P3, mesma nota). Nenhum achado nas camadas de segurança/frontend/perf/a11y —
confirmado sem mudança em `app/` desde a auditoria desta manhã (nota 85).

Ainda 19/08, madrugada: fechada a lacuna acima. Os 24 `.ps1` e os 2 `SKILL.md` versionados
corrigidos, mais os mesmos 2 `SKILL.md` vivos fora do repo (`C:\Users\User\.claude\scheduled-tasks\
vixradar-{matinal,noturno}\`, achado novo durante a correção, é o arquivo que a sessão agendada do
Claude Desktop realmente lê). Testado ao vivo, não só parse: `monitor-tasks.ps1` rodado de
verdade leu os logs de 18/08 no caminho canônico (`submit_ok=103` noturno, `submit_ok=20`
matinal); `retry-vixradar.ps1` rodado para as duas rotinas resolveu o caminho do dia 19/08
corretamente. Guarda nova: `scripts/lint-legacy-path.ps1`, Gate 5 do pré-commit, reprova
reintrodução do caminho legado em `.ps1`/`SKILL.md` de rotina. Junto, P3 do dry-run do
Ranking-Mensal fechado (`.gitignore` + arquivos removidos). Detalhe completo em `PENDENCIAS.md`.

Em 19/08, madrugada: auditoria fechada de retries, watchdogs e monitoramento. O
`Szuchmacher-RetryVixMatinal` recusado em 18/08 16h23 teve a causa determinada por evidência, não
por inferência de exit code: evento 153 (agendamento perdido), máquina desligada das 03h42 às
16h14, gatilho das 13h30 perdido, task sem `StartWhenAvailable`. Impacto zero, a matinal rodou às
16h34 pelo catch-up da própria sessão do Claude Desktop e entregou 20/20. Fato novo, o event log
`Microsoft-Windows-TaskScheduler/Operational` está habilitado (16.676 registros), ao contrário do
que o vault registrava em 27/07, então esse tipo de incidente passou a ser apurável. Achado
corrigido: a matinal escreveu três formatos diferentes da linha `FIM:` em quatro dias porque o
`SKILL.md` dela, ao contrário do noturno, nunca exigiu formato fixo, e a variante de 15/08
(`FIM: 19 emissores processados`, sem denominador) geraria retry falso. Formato agora exigido nas
duas cópias do `SKILL.md` da matinal, mais denominador opcional no parser de
`retry-vixradar.ps1`/`monitor-tasks.ps1`. Testado ponta a ponta com o script real, mais controle
negativo. `VIXRadar-Health-Watch` e `Szuchmacher-RetryVixNoturno` validados sem achado. Detalhe em
`PENDENCIAS.md`.

Ainda 19/08, madrugada: investigado relato do usuário de que o Painel de Eventos em produção
mostra 14/08 como data mais recente do feed. Primeira rodada (01h35) achou causa provável sem
prova direta, mais um achado separado (histórico de EWS achatado). Segunda rodada (/caveman,
02h30-03h10) provou, corrigiu, testou e deployou os dois problemas de ponta a ponta.

**P0-1 RESOLVIDO — dedup de eventos.** A hipótese inicial ("qualquer manchete parecida em 45 dias
colide") era forte demais, teste executável com a função real mostrou que só colide quando a
diferença é a palavra "nova" (removida por design) ou quando a redação do analista se repete
quase verbatim. `_isDupSemantico`/`_normTituloDedup` (`app/index.html`) não removem mais
`novo/nova`, não truncam mais em 70 caracteres, e a identidade de duplicata agora prioriza
`fonte_primaria`, senão exige mesmo `data_evento` exato (não mais janela de 45 dias). Em colisão
real, sobrevive o evento mais novo. Deploy Pages v202.11, confirmado ao vivo (código novo,
CACHE_VERSION e `?v=` dos módulos admin alinhados, pego pelo GATE 3.4 do próprio
`deploy-pages.ps1`). Teste `scripts/test-dedup-eventos.mjs`, 8 casos + ordenação, roda direto
contra o `index.html` real.

**P0-2 RESOLVIDO — histórico de EWS não acumulava.** Duas causas, não uma: HISTFLAT1
(`executarPipelinePreditivo` pulava a leitura do histórico real inteira quando chamado com
`skip_hist_persist:true`, o único caller assim é o endpoint admin/smoke, que sobrescrevia
`predictive_v1:latest`, a mesma chave dos crons, com um snapshot achatado) e HISTFLAT2 (achada
pela prova em produção do fix 1, que ainda mostrava hist_len=1: a chave real é gravada em
minúsculo por `kvEwsHistKey`, mas o lookup em memória usava o case original da empresa, miss
silencioso em QUALQUER chamador, inclusive os crons que sempre tinham a leitura ligada). Deploy
Worker v4.9.199 depois v4.9.200. Prova em produção: `hist_len` foi de uniforme 1 para uniforme 2
nos 103 emissores (o "2" é esperado, só há 1 ponto real persistido até agora, a série volta a
crescer dia a dia sem histórico retroativo inventado). Testes em CI, `api/test/predictive-hist.test.mjs` —
a primeira versão do teste mascarava o HISTFLAT2 por seedar a chave errada, corrigida.

Detalhe completo, causa raiz, commits e prova de cada um em `PENDENCIAS.md`.

Ainda 19/08, manhã: o usuário reportou que o feed **continua** parando em 14/08 mesmo depois dos
dois fixes acima. Auditoria geral provou que o painel está certo e o dado é que parou. Varredura
nos 103 emissores dá `MAX data_evento = 2026-08-14` e `MAX data_entrega CVM = 2026-08-15`. A causa
primária é externa, a CVM parou de publicar: IPE, FRE e ITR em `dados.cvm.gov.br` estão com
`Last-Modified: Sun, 16 Aug 2026`, três dias parados, e o arquivo real baixado e parseado com o
mesmo código do Worker não tem nenhuma entrega em 17 nem 18/08. O parser de ZIP do
`syncCVMAutomatico` foi testado contra o arquivo real e está correto, não é bug nosso.

A causa agravante é interna e é o achado que importa: **nenhuma guarda deste sistema mede frescor de
dado, todas medem se o escritor rodou**. O `heartbeat:sync_cvm` ficou verde o apagão inteiro, o
`frescor-check.yml` valida `updated_at` e contagem de empresas (que seguem verdes com conteúdo
reciclado), o cron carimba `sync_cvm = ok` sem checar o retorno de `syncCVMAutomatico`, o carimbo
"Atualizado em 19 de agosto" na tela é `new Date()` do navegador, e a tira de fontes do rodapé é
HTML estático com classe `ok` fixa, que mostrou "CVM RAD" verde durante o apagão. Nenhuma correção
foi aplicada, todas exigem deploy. Prova, evidência bruta e as 5 correções propostas em
`PENDENCIAS.md`.

Ainda 19/08, ao meio-dia: as duas P0 foram implementadas e deployadas com autorização do
usuário. Worker v4.9.201 leva o CVMFRESCOR1, a idade da fonte CVM carimbada a cada sync e
contando no `_okHealth`, mais os dois crons passando a checar o retorno do
`syncCVMAutomatico` em vez de só verificar se ele explodiu. A primeira leitura do health em
produção expôs uma falha do próprio fix, sem cron nenhum tendo rodado o motivo vinha
`sem_meta` e o health ficaria vermelho por até 12h a cada deploy, o que é justamente o tipo
de alarme falso que ensina todo mundo a ignorar alarme. Corrigido no v4.9.202 derivando a
idade da chave `cvm:documentos` que já existia, com backfill gravado uma vez só e
precedência garantida para a meta real. Junto foram ajustados o `deploy-worker.ps1`, que
abortaria o passo 5 deixando produção nova com o repo declarando versão velha, e o
`canonical-test.yml`, cuja mensagem de erro nomeava três fatores todos verdes. CI verde com
35 testes. O health hoje volta `ok:false` com
`cvm_fonte_motivo:"fonte_parada_ha_3_dias_uteis"`, e isso é o comportamento pretendido, a
fonte está parada mesmo.

Ainda 19/08, tarde: usuário pediu para checar manualmente se realmente não houve notícia de crédito nos
103 emissores em 17 e 18/08. Busca dirigida (nome a nome nos 5 maiores riscos, depois os 98 restantes em
9 lotes por setor) achou 3 indícios que pareciam reais. Dois, Cosan e Vibra Energia, se confirmaram como
falso alarme depois de cruzar contra o estado real do sistema: a "notícia de 17/08" da Cosan era imprensa
comentando um Fato Relevante que a CVM já tinha divulgado em 14/08, que o sistema já tinha capturado com a
data certa, e a Vibra teve resultado forte, corretamente triado como baixa materialidade (ECO), não omissão.
O terceiro indício, um voto de privatização da Copasa supostamente em 17/08 na Assembleia de Minas Gerais,
parecia gap real (EWS baixo demais para acionar o cross-check regulatório) até eu verificar a data na fonte
oficial da ALMG antes de gravar qualquer coisa em produção: a votação foi em **17/12/2025**, oito meses
antes, sem ligação com agosto de 2026. O resumo da própria ferramenta de busca tinha colado o dia certo no
mês errado, mesmo padrão já visto com outro emissor na mesma investigação. Nenhum evento foi criado para a
Copasa, nada foi registrado como achado, porque não havia achado. Resultado líquido depois de checar os 103,
nenhuma notícia de crédito material perdida nesses dois dias, o carimbo novo (CARIMBOFAKE1, acima) está
dizendo a verdade.

Mesmo sem caso comprovado, o usuário autorizou reforço preventivo no prompt de busca das duas rotinas
(matinal e noturno, as 4 cópias, 2 versionadas + 2 vivas fora do repo): nova dimensão R7 (estrutura
societária, privatização, mudança de controle, intervenção legislativa ou regulatória), porque o vocabulário
de R2 (rating, dívida, default, covenant) não cobre naturalmente esse tipo de notícia e R6 só dispara com
EWS≥20, deixando emissor de risco baixo nos setores regulados sem cross-check algum. Escopo restrito a
Energia Elétrica, Saneamento e Transportes e Logística, para não dobrar o custo de busca dos outros dois
terços dos emissores. R2 e R6 saíram intocados. A justificativa original (Copasa) e sua retratação ficaram
documentadas dentro do próprio SKILL.md, commit `54ef874`, para a próxima sessão não reabrir a mesma
investigação do zero achando que existe evento perdido de verdade.

Na mesma sessão, estrutura de pastas resolvida. A junction legada
`E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito` foi removida depois de preflight com 0
tarefas agendadas, 0 worktrees e `lint-legacy-path.ps1` 70/70 OK; alvo validado sem perda (44923
arquivos, 1799312500 bytes, HEAD `fa191b5`, tree limpo) e `FREQUENTE\` intacta com os outros 13
projetos. As 5 skills `vix-radar-*` estavam duplicadas como stubs de ~300 bytes em
`C:\Users\User\.claude\skills\` apontando por texto para o conteúdo real em
`E:\Diretorio\Claude\.claude\skills\`, o que quebrou de verdade nesta sessão (o script obrigatório
da auditoria falhou com `MODULE_NOT_FOUND` na primeira chamada). Stubs trocados por junctions.
Ainda em 18/08, mais tarde: padronizada a linha `ROTINA_RESUMO|nome|modo|inicio|fim|
resultado|processados|erros|pendentes|versao` em 5 rotinas que já funcionavam (matinal,
noturno, coleta-volatilidade, export-historico, reconciliacao-cvm), sem tocar a lógica
interna de nenhuma, só acrescentando a linha logo depois do `FIM:` já existente de cada
uma. Formato espelha o que `run_vixradar_agenda_semanal.ps1` já usa (única rotina
reescrita nesta sessão, corrigindo bug real de execução silenciosa sem Bash). Testado
com execução real controlada: export-historico e reconciliacao-cvm rodaram inteiros em
`-DryRun` real, coleta-volatilidade rodou de verdade forçando o branch de falha (sem
tocar produção). O branch de sucesso de coleta-volatilidade e os scripts matinal/noturno
completos não têm modo seguro de teste (rodá-los gastaria tokens Claude reais e gravaria
em produção fora do agendamento), então foram validados isolando o código exato inserido
contra dados fixture cobrindo os cenários OK/PARCIAL/FALHA. Os 5 arquivos passam no
parser PS 5.1 e no `lint-encoding.ps1` do projeto. `verificacao-async` e `ranking-mensal`
ainda não têm a linha `ROTINA_RESUMO`.

## Como verificar

Portão de verificação do CLAUDE.md, antes de declarar tarefa concluída:

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`.
A suíte vitest só roda local após `cd api && npm ci` (o deploy roda
`npm ci --omit=dev` e apaga o vitest; medido 20/08/2026, NÃO é Smart App Control,
detalhe no CLAUDE.md).

## Onde está o resto

- Caminho físico canônico do projeto: `E:\Diretorio\Claude\Monitoramento de Credito`. O `FREQUENTE\Monitoramento de Credito` é junction legado de compatibilidade, use o canônico em caminho novo
- `CLAUDE.md` (protocolo operacional, deploy, incidentes) e `README.md`
- `scripts/` (deploy e automações) e `routines/` (`README.md` é a fonte da verdade do agendamento)
- `logs/routines/` (saúde real das rotinas, linha `FIM:` no log)
- `api/` (fonte viva: `api/src/worker.js`; bundles `v4.*.js` são artefatos gerados) e `app/` (frontend, `index.html`)
- Worker `radar-credito-api` em `api.vixradar.com` e Pages `radar-credito` em `vixradar.com`
- Vault `Obsidian VIX Radar/` (memória canônica: `00 - Índice (MOC).md`, `03 - Estado Atual.md`, `PENDENCIAS.md`)
- `producao/` é legado desconectado, nunca deployar

## Itens abertos

- **04\09 (noite), CLAUDE-FREE-MIGRATION Fase A, código pronto, 5 ações do operador pendentes (G1-G5):** Claude deixou de ser infraestrutura (operador sem Pro/Max, PAYG não autorizado). O código da Fase A está no disco e testado: rotinas LLM com gate de provider `BLOQUEADO_SEM_PROVIDER`/exit 86, monitor fail-closed (9006), scheduler volta ao nativo, gate anti-regressão (`check-claude-free.ps1` + Gate 8 + workflow). **O que falta é ação do operador, não código:** G1 setar `VIXRADAR_LLM_PROVIDER=none` em User; G2 desligar as 4 tasks CCD + pausar 2 Remote no MCP; G3 rodar `cutover-motor.ps1 -Acao Ativar` (elevação); G4 observar 1 disparo de cada rotina bloqueada; G5 validar monitor. Depois disto, G6 (commitar migração + CI verde) e G7 (portão final). Detalhe completo no bloco Fase A no topo, em `PENDENCIAS.md` e na nota de auditoria `100 - CLAUDE-FREE-MIGRATION Fase A 2026-09-04.md` do vault.
- **04\09, Fase B futura (decisão do operador, registrada sem executar):** reescrita do motor de análise para provider novo (DeepSeek/OpenRouter, chaves já em env User, não inventar chave, não criar serviço pago). Provider configurado mas motor não migrado ⇒ ainda BLOQUEADO. Também fica para Fase B: remover o residual Anthropic do Worker (cascade + secret `ANTHROPIC_API_KEY` + `consulta_empresa`), hoje intocado por decisão de produção.
- **01\09 (noite), AUDITORIA DE ROTINAS, decisão do operador pendente (ROTINAS-SOBREPOSICAO1, nota 99):** 27 gatilhos em 5 mecanismos (Claude Desktop, Task Scheduler, Worker cron, GitHub Actions, Routines remotas) medidos um a um, nenhum alterado. Achados: o e-mail `[VixRadar] Health ALERTA` das 22h é falso todo dia desde 24/08 porque `cascade_analise` segue em `expectedAgents` (`worker.js:19471`) e só é batido pela cascata do Worker, desligada (`worker.js:19400`); o e-mail do `Monitor-Tasks` das 07h reporta tasks de outros projetos e `LastTaskResult` congelado (01/09: `Szuchmacher-AgendaAgent` e `Szuchmacher-FechamentoDiario`, nenhum do VIX); a noturna analisou 33/103 em 01/09 (`deferidos=69` com `198351/700000` gastos, pela regra de reserva da aprofundada) enquanto 12 emissores foram analisados 2x no dia (matinal + aprofundada) e 31 ficaram deferidos em 31/08 e 01/09; 4 drenos agendados da fila de verificação, a remota das 14h acha `total:0` há 4 dias e a das 18h45 saiu com `submit_ok=0` por claimante ad hoc `local-manual-forcado`; `CLOUDFLARE_API_TOKEN` ausente em User, Machine e processo (`whoami` = OAuth). Recomendação em 8 itens na nota. Detalhe em `Obsidian VIX Radar/99 - Auditoria de Rotinas e Sobreposicoes 2026-09-01.md` e `PENDENCIAS.md`
- **01\09, RESOLVIDO (AVANCOFEED1, v4.9.231):** o painel podia ficar dias parado com todo semáforo verde, e o único gate que media isso reprovava por "N dias úteis sem evento" mesmo quando a fonte estava no mesmo teto. `checks.avanco_feed` passa a comparar teto do feed contra teto elegível da fonte e cadência dela. Prova de duas pontas em produção nos runs `33472230172` (reprova) e `33472592026` (aceita). Detalhe em `PENDENCIAS.md`
- **01\09, RESOLVIDO (cron da noturna):** `vixradar-noturno` de volta a `0 10 * * *`, revertido antes do primeiro disparo em 08h. `nextRunAt` recomputado pelo app vivo para `2026-09-01T13:05:24Z`. Detalhe em `PENDENCIAS.md`
- **01\09, FRENTE ESTRUTURAL ABERTA (fonte intradiária de Fato Relevante):** o lote IPE da CVM é semanal e publica aos domingos com `Data_Entrega` até a sexta anterior, então existe uma janela cega de até 7 dias por construção da fonte. Medido em 01/09: `cvm_fonte_proxima_prevista=2026-09-06`. NÃO implementada nesta sessão, por decisão de escopo. Depende de credencial e de validação de cobertura, não de código: `dadosdemercado.com.br` exige Bearer token pago ausente, o Download Múltiplo da CVM exige credencial própria da CVM que não existe neste ambiente, e o RAD está fora por reCAPTCHA. Decisão do operador, não do agente. Detalhe em `PENDENCIAS.md`
- **01\09, REGISTRADO SEM CORRIGIR (semântica de `submit_ok`):** `submit_ok=103` na linha `FIM:` da noturna conta SUBMISSÃO, não análise, e mascara a cobertura real quando há DEFERIDOS. Medido em 31/08: 50 analisados, 22 SKIP, 31 DEFERIDOS por cap de sessão (`realizado=681137` de 700000), e mesmo assim a linha final disse `submit_ok=103`. Quem lê o log conclui cobertura total. Não corrigido aqui de propósito, para não misturar frente. Detalhe em `PENDENCIAS.md`
- **01\09, OBSERVAÇÃO NOVA (não investigada):** 1439 dos 2252 documentos do acervo CVM estão sem dono entre os 103 emissores, cobertura de atribuição 36,1%. Agora visível em `checks.avanco_feed.fonte_documentos_sem_dono` e no log do frescor-check. Apareceu ao construir a guarda, não foi apurado
- **01/09, RESOLVIDOS E DEPLOYADOS (v4.9.228):** os 4 achados da auditoria geral de 01/09. `DISJUNTORHOUSEKEEP1` (P3-2, teto de custo não barra mais housekeeping do cron), `LOGINTIMING1` (P4-1, tempo uniforme nos quatro caminhos de falha do login), governança da skill `/vix-radar-general-audit` + `audit-matrix` em v4.9.228, e `CLAUDE.md` de 6 para 7 heartbeats. Portão verde em `v4.9.228`, suíte 167/167, commits `e44cd7c` (código) e `8ac3e0e` (deploy). Nenhuma quinta frente aberta: os P3/P4 não viraram pretexto para melhoria oportunista. Detalhe em `PENDENCIAS.md`
- **30/08 (noite), P1 ABERTO, AÇÃO SÓ DO OPERADOR (CCDOFFLINE1):** causa raiz do buraco de 28/08 medida. A máquina nunca dormiu nem desligou naquele dia (uptime contínuo 28/08 03:02:39 → 29/08 14:34:47, dois marcos `EventLog 6013` batem exato). O gatilho foi Windows Update (KB5120998 + KB5122385, duplo reboot 03:01-03:03 medido por correlação instalação→reboot). A causa estrutural é que o Claude Desktop (MSIX) não reabre sozinho depois de reboot, e o CCD (INVERSAO-CD1) só avalia cron com o app de pé: `AppxManifest.xml` declara `StartupTask Enabled="false"`, sem entrada em `Run`/`RunOnce`/Startup folder/Scheduled Tasks. ~36h sem CCD vivo, por isso `recordedSkips` não tem nada registrado (não é "viu e pulou", é "não estava lá"). Os watchdogs `Szuchmacher-RetryVixNoturno/Matinal` viram o buraco e documentaram a própria impotência (`SEM LOG... fora do alcance deste watchdog`), não é bug neles. **Correção é 1 toggle do Windows** (Configurações → Aplicativos → Inicialização → Claude → On), fora do alcance de qualquer agente por regra permanente (configuração de sistema), só o operador liga. Guarda de vigia adicional (checar `Get-Process Claude` como sinal isolado) proposta e não construída, pede autorização à parte. Detalhe em `PENDENCIAS.md`
- **RESOLVIDO E DEPLOYADO 31/08, v4.9.225 (FALLBACKTTL1 + VERIFCACHE-ROUNDTRIP1):** os dois fixes entraram em produção juntos na v4.9.225, portão validado (health `ok=true, versao=v4.9.225, kv=true, telemetria=true, sentry_ok=true, verificador_ok=true`, HTTP 200 nos dois domínios), suíte local 145/145 verde, git sincronizado em `d88c293`. **FALLBACKTTL1:** `buscarCacheUltimoResorte` tem corte de idade próprio (`idadeHoras > 24`) independente do TTL do KV; fix em 2 linhas coordenadas (`expirationTtl: 86400 → 86400*3` na escrita, `idadeHoras > 24 → > 48` na leitura), TTL de armazenamento com margem acima do corte de serviço. Sobrevive a 1 dia inteiro sem varredura (caso de 28/08), sem piorar nada para quem recebe fallback velho (piso de confiança já saturava em 0,3). **VERIFCACHE-ROUNDTRIP1:** veredicto `APROVADO_CORRIGIDO` gravado em cache voltava como rejeição no reenvio e retratava o evento do painel; o guard de `aplicarCorrecaoVerificador` exigia `veredicto === "CORRIGIR"` cru, mas a própria função renomeia o campo antes de gravar no cache. Fix: guard aceita o round-trip (`veredicto_original === "CORRIGIR"`), correções reaplicadas ao evento fresco de forma idempotente. Teste novo `api/test/verif-cache-roundtrip.test.mjs` (duas pontas). **Lacuna não fechada:** FALLBACKTTL1 sem teste automatizado para o par `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte`. Detalhe em `PENDENCIAS.md`
- **30/08, ABERTO P2 (PISODIFF1-ESTRUTURAL1):** piso EWS pisado em 61 para todo RJ/default ativo, sem diferenciar gravidade. Mitigado no v4.9.224/v202.35 pelo card duplo (`Score sem piso: N` sob o score final) e pelo desempate do ranking por `score_calculado` desc. A solução estrutural, escada de piso por severidade dentro do CRITICO (ex. 61/70/78), fica registrada sem implementar: exige fonte estruturada de severidade da RJ (sub-tags da cascade: `default-consumado`, `rj-homologada`, `re-ativa`), nunca tabela manual sem proveniência (classe RESEARCHDOWN1, a `_RJ_FLOOR` já carrega a dívida). Detalhe em `PENDENCIAS.md`
- **30/08, CORRIGIDO (SYNCDOC-MUDO1, P3, sem deploy):** metade do `scripts/sync-version-docs.ps1` não casava nada e ele não avisava. Os 2 blocos que miravam o `CLAUDE.md` estavam mortos desde `49471e0` (25/07), que removeu a tabela de versão de lá 8 dias depois do script nascer, e o `Update-File` confundia "já sincronizado" com "âncora inexistente" num `$false` só, imprimindo `Docs sincronizados: <só o que mudou>` sem reclamar do resto. Blocos do `CLAUDE.md` aposentados (`README.md` vira a única tabela de versão viva), os 4 alvos restantes viraram declarações nomeadas e a pergunta passou a ser `[regex]::Matches().Count`, com estado `AVISO: ALVO DE SINCRONIA AUSENTE` em amarelo. Avisa e não aborta no deploy de propósito (passo 5.5 roda com produção publicada e git não commitado), `exit 1` só sob `-Strict`. Prova de duas pontas medida contra o código pré-correção, lint RISCO 0, runtime 5.1 e pwsh 7. Detalhe em `PENDENCIAS.md`
- **30/08, REFUTADO por medição (SENTINELA-DIAPERDIDO1, P1 do 93):** 29/08 é sábado e a task roda só Seg-Sex (`DaysOfWeek=62`). Medido ao vivo: `LastRun=28/08` (sexta) 17:55, `NumberOfMissedRuns=0`, log `vixradar-sentinela_20260828.log` existe com 18 linhas `FIM:`. Não houve dia útil perdido, as auditorias 93/95 chamaram sábado de "sexta". Vigia defensivo implementado mesmo assim no `monitor-tasks.ps1` (`scripts/lib/vixradar-watchdog.ps1`, dot-source), prova de duas pontas 4/4, monitor real `ROTINA OK: VIXRadar-Sentinela (entrega) | 2026-08-28 execucoes_com_fim=18`. Detalhe em `PENDENCIAS.md`
- **30/08, RESOLVIDO (AGENDA401, P1, v4.9.223):** agenda pública de resultados morta por 401 cru no visitante. `op=calendario` liberado sem JWT (`api/src/worker.js:17627`), teste anônimo de duas pontas em `api/test/agenda-validacao.test.mjs` (10/10 verdes), deploy v4.9.223 validado em produção: `GET /?op=calendario` sem token → `ok:true` (103 emissores, 81 com calendário), `escopo=agenda` idem. Sem mudança de frontend. Detalhe em `PENDENCIAS.md`
- **30/08, CORRIGIDO (RECONCILE-CVM404, P2):** reconciliação local ia falhar de novo com o ZIP 2026 fora do ar. `reconciliar_ipe_cvm.ps1` agora usa `$NowBrt.Year`, consulta o catálogo CKAN da CVM no 404 (mesmo espelho do Worker v4.9.209/210) e só extrai após checagem de magic PK. Validação: parse 5.1, lint RISCO 0, dry-run exit 0. O ZIP 2026 voltou pela CVM em 25/08, então segunda 31/08 deve usar o caminho canônico; o fallback fica como defesa. Detalhe em `PENDENCIAS.md`
- **30/08, RESOLVIDO (SEXTA-SEM-ROTINA1, causa = CCDOFFLINE1):** sexta 28/08 não tem log nem da matinal nem da noturna (os logs pulam de 27/08 pra 29/08). Causa medida em 30/08 noite: Windows Update reiniciou a máquina às 03:01-03:04 (KB5120998 + KB5122385), o Claude Desktop (MSIX) não reabre sozinho após reboot, e o CCD só avalia cron com o app de pé, então noturno + matinal + verificação ficaram ~36h sem agendamento sequer avaliado. O monitor já sinaliza `VIXRadar-Matinal (entrega) 9001` (alvo 28/08), como projetado. Correção pendente é 1 toggle do operador ("Iniciar automaticamente" para o Claude). Detalhe em `PENDENCIAS.md` (CCDOFFLINE1).
- **30/08, CAUSA MEDIDA, segue P2 ABERTO na guarda (AGENDASEM-TRAVA1):** a AgendaSemanal não morreu por defeito do lote 3, a máquina reiniciou por baixo dela. Lote 3 iniciado 26/08 22:14:44, Kernel-Power 109 e 577 (transição de desligamento e reinicialização iniciada pelo sistema) às 22:16:27 e 22:16:29, `0x40010004` = processo morto de fora. Timeout descartado nas duas pontas (`ExecutionTimeLimit=PT4H`, wrapper sem guarda). E não foram 3 dias de falha: `DaysOfWeek=9` = domingo e quarta, houve **uma** falha (quarta 26/08), `NextRunTime=30/08 22:00`, `NumberOfMissedRuns=0`, e o `idade=3d ESCALADO` é releitura do mesmo `LastTaskResult` congelado. **Guarda entregue na mesma manhã.** A AgendaSemanal entrou no vigia de entrega por log do `monitor-tasks.ps1`, com cadência real (`diasPermitidos = @('Sunday','Wednesday')`) na lib `vixradar-watchdog.ps1`, que também deixou de ter o cálculo de alvo duplicado entre a prova e produção. Prova de duas pontas 9/9, parse 5.1 e lint RISCO 0, e o monitor real agora emite `ROTINA SEM ENTREGA: VIXRadar-AgendaSemanal (entrega) | 2026-08-26 log existe mas sem linha FIM:`, nomeando a janela cobrada. Segue aberto só o dreno dos 12 emissores stale. Próximo passo: ler a linha `FIM:` de `logs/routines/vixradar-agenda-semanal_20260830.log` na manhã de 31/08. Detalhe em `PENDENCIAS.md`
- **29/08 (noite), P2 ABERTO (FALLBACKTTL1):** `fallback:{empresa}` com `expirationTtl: 86400` (worker.js:15845); o dia 28/08 sem varredura apagou o cache de último recurso dos 103 emissores, violando a regra VOLTTL1 (TTL >= 2x o intervalo). Fix de 1 linha, exige deploy, candidato ao v4.9.222 junto com o VERIFCACHE-ROUNDTRIP1. Detalhe em `PENDENCIAS.md`
- **RESOLVIDO 29/08 (REPOSIC1):** o feed preso em 25/08 tinha três causas, e a terceira era nossa e sem guarda: 28/08 não teve varredura e a passada de 29/08 re-ancorou o desenvolvimento em fato antigo em vez de criar evento datado na janela. Reposição executada (Braskem 28/08 CRÍTICO, Oncoclínicas 27/08 CRÍTICO, Multiplan 27/08 ECO, Petrobras 26/08 ECO), max `data_evento` 25/08 → 28/08 confirmado. Guarda = skill `/repor-varredura` (`.claude/skills/repor-varredura/`, registrada no router) + `scripts/repor-varredura.ps1` + `scripts/repor-varredura-prompt.md` com regra anti-ancoragem e verificação de data real na fonte. Detalhe em `PENDENCIAS.md`
- **29/08 (tarde), P0/P1/P2/P3 da auditoria geral fechados na branch `fix/silent-green-2026-08-27`** (merge em `main` confirmado na noite de 29/08, guardas já valem no cron)**:** `SCANFALLBACK-MORTO1` (secret `ANTHROPIC_API_KEY` criado pelo operador + pré-check de secrets, `ab2622f`), `WATCHDOG-NAOINICIOU1` (`retry-vixradar.ps1` alerta e sai 1 no dia sem log, `5acbca2`, efetivo local), `FRESCORNOTIFY1` (`frescor-check.yml` com passo `if: failure()` de notificação, `a1c5283`), P3 docs. Feed diagnosticado como verdadeiro: sem evento >= 26/08 em produção (MAX 25/08, TOTAL 496). **Pendente:** merge em `main` para P0 e P2 valerem no cron. `VERIFCACHE-ROUNDTRIP1` segue ABERTO (exige deploy). Detalhe em `PENDENCIAS.md`
- **ATUALIZADO 26/08 (INVERSAO-CD1, P1), scheduler real achado e alterado, ativação é BLOQUEIO EXTERNO.** O fechamento de 25/08 dizia "sem superfície programável" e estava errado: o agendamento dos três vive no CCD store `%APPDATA%\Claude\claude-code-sessions\<conta>\<device>\scheduled-tasks.json`, lido pelo app só no initialize, não no Cowork nem no Task Scheduler. Quatro provas: (1) `cronExpression` bate com os horários observados; (2) `lastRunAt` casa com o `INICIO:` dos logs (matinal 15:08Z→12:09 BRT, noturno 21:56Z→18:57 BRT, verif 21:56Z); (3) `main.log` do app mostra o CCD disparando a sessão com o cron e `missed` (catch-up que explica os atrasos de 12:08/18:56); (4) o Cowork responde "not initialized" e as tasks nativas estão `Disabled` de propósito. **Alteração aplicada 26/08, backup `scheduled-tasks.json.bak-20260826`:** `vixradar-matinal` `0 18 * * 1-5` (18h Seg-Sex), `vixradar-noturno` `0 10 * * *` (10h diário), a verificação passou de um cron cartesiano para **duas tasks independentes**: `vixradar-verificacao-async-11h` `0 11 * * *` (11h00) e `vixradar-verificacao-async-1845` `45 18 * * *` (18h45), clonadas do original (SKILL.md + ROUTINES-CLOUD.md em pasta própria, hash idêntico). Sai o disparo espúrio das 11h45 e das 18h00 que o cartesiano introduzia. Estado final: `vixradar-matinal` `0 18 * * 1-5`, `vixradar-noturno` `0 10 * * *`, verificação 11h00 e 18h45. JSON validado, 6 tasks, IDs únicos, as 4 sessões VIX `enabled:true`. **Ação manual mínima, urgente:** o processo do app (`claude.exe` PID 10756) está vivo desde **25/08 18:56**, só lê o arquivo na ativação, e o próximo dispatch em memória (matinal às 10h de hoje) grava o snapshot velho por cima do arquivo. Reiniciar o Claude Desktop **antes das 10h BRT de hoje** para carregar as 4 sessões novas; a sessão que editou roda hospedada por ele e não pode reiniciá-lo. Depois do restart, conferir o próximo `INICIO:` no log. Preservados: `VIXRadar-Matinal/Noturno/Verificacao-Async` `Disabled`, Sentinela habilitada, `Szuchmacher-RetryVixNoturno` 13h30 e `Szuchmacher-RetryVixMatinal` 21h30. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- **RESOLVIDO 25/08 (SENTINELA-SYNC1, Worker v4.9.220 + script):** o SLA passa a contar **da publicação na CVM** até a análise sair. O bloqueio era de credencial, não de arquitetura, e a solução já existia na máquina: cofre DPAPI `CurrentUser` em `api/.admin_credencial.dat`, lido por `api/Get-VixAdminCredential.ps1`, já usado por seis scripts vivos. Reusar não cria segredo novo. Quando o `HEAD` acusa `Last-Modified` novo, a Sentinela manda o Worker reingerir na hora via `admin_sync_cvm_auto`. `zip_last_modified` só avança no estado quando o sync volta `ok`, então falha não consome o gatilho. Sem cofre a rotina **não aborta**, registra o atraso medido e segue com o acervo atual. Prova ao vivo: detectou publicação de 961 min atrás, sincronizou em 5 segundos (`documentos=2126 empresas=506`) e planejou, contra as até 4h32 de espera pelo cron
- **RESOLVIDO 25/08 (STATUSGRUDA1, Worker v4.9.220):** `_status` sofria o mesmo descarte do DEFERGRUDA2 no ramo "semana nova sem evento, semana velha com evento". Ele descreve a última varredura, não o acervo de eventos, então o registro mais recente manda. Dano concreto: o `inconclusivo_stale_breakout` do noturno, que existe para quebrar loop de cobertura incompleta, ficava cego. `_motivo` viaja junto por só fazer sentido ao lado do `_status` que o gerou. Conteúdo continua vindo da semana velha, com teste travando isso. Guarda: 3 testes novos, os 3 falham contra o código anterior
- **`VIXRadar-Sentinela` HABILITADA 25/08 23h30**, depois das três condições passarem: (1) `submit_ok` limpa deferred, 31 emissores analisados e 0 permanecem, cobrindo os dois caminhos da mescla; (2) o plano não reapresenta emissor concluído, medido sobre a fila completa e não sobre a janela de 8, eram 13 sob v4.9.218 e são 0 sob v4.9.219; (3) o backlog converge, trajetória **34 → 29 → 11 → 3 → 0** com aritmética exata nas últimas execuções e nenhuma entrada nova, e a execução seguinte sai no portão com `tokens=0`. Próxima execução 26/08 09h25
- **RESOLVIDO e DEPLOYADO 25/08 (DEFERGRUDA3, Worker v4.9.219):** fechado o DEFERGRUDA2, a fila pontual ainda não convergia. Medição da fila **completa** (`teto=200`, custo zero) sob v4.9.218: 29 candidatos, sendo 11 deferidos e **18 inconclusivos**, e dos 20 emissores já analisados com `submit_ok` **13 voltaram**, nenhum por deferido, todos por inconclusivo. Mecânica determinística: a pontual analisa em lote Haiku com ~2 buscas e o tier FULL exige `_coberturaMin=7`, então **toda** análise dela grava `_status:"INCONCLUSIVO"`, e com inconclusivo no gatilho a rotina reapresentava o próprio trabalho. Correção de 1 linha, `inconclusivo` sai do filtro da pontual: gatilho passa a ser só fato novo (documento da CVM) ou dívida (análise barrada pelo teto). Quem cuida do inconclusivo continua sendo o ramo `inconclusivo_stale_breakout` do plano noturno, e há teste travando isso para não virar órfão. Prova em produção: fila completa 29 → **11, todos `deferido`**, e 0 dos 20 analisados reaparecem por qualquer gatilho. Lição: janela pequena esconde laço, só apareceu ao medir a fila inteira por composição de gatilho em vez da janela de 8 que a rotina consome
- **RESOLVIDO e DEPLOYADO 25/08 (DEFERGRUDA2, Worker v4.9.218):** o DEFERGRUDA1 estava certo e não bastava, porque o problema era a **leitura**, não a escrita. Leitura crua das 3 chaves que a mescla consome, com o VLI já analisado com `submit_ok`: `radar:estado:2026-W35` (corrente) `eventos=0 _token_cap_deferred=undefined`, `radar:estado:2026-W34` `eventos=1 _token_cap_deferred=true`. Ou seja a semana corrente já estava limpa. `receber_analise` escreve em **uma** chave, a da semana corrente. `montarPlanoRotina` lê **três** via `carregarEstadoMultiSemana(env, 3)` e mescla da mais velha para a mais nova, e o ramo "semana nova sem evento, semana velha com evento" devolve o objeto da semana **velha** corrigindo apenas `_last_scanned_at`. Daí o sintoma exato: `horas_stale=0,1` com `deferido=true`. A Copel não sofria porque a semana corrente dela tem evento e cai no ramo de dedup, que espalha o registro novo. Correção de 2 linhas só no ramo culpado, `_token_cap_deferred` passa a vir sempre do registro mais recente, por ser estado de agendamento e não de conteúdo. Guarda com 3 testes novos, os 3 falham contra o código anterior, suíte 122/122. **Prova em produção com custo zero:** logo após o deploy, sem nenhuma análise nova, os quatro emissores presos sumiram do plano pontual e os candidatos caíram de 33 para 31. Observado e não corrigido de propósito: `_status` sofre o mesmo descarte nesse ramo, mas alimenta promoção de tier e tem alcance maior que esta pendência
- **RESOLVIDO e DEPLOYADO 25/08 (DEFERGRUDA1, Worker v4.9.217, correção parcial, ver DEFERGRUDA2):** a bandeira `_token_cap_deferred` ligava e nunca desligava. Os cinco ramos de `persistirResultadoCompartilhadoInterno` faziam `if (payload... === true) X = true` sem `else`, e os ramos de `sem_eventos` reaproveitam o objeto anterior em vez de reconstruí-lo, então a bandeira sobrevivia a qualquer análise real. O DEFERREDREC1-FIX de 15/08 colocou a escrita e esqueceu o apagamento. **Achado rodando, não lendo:** o `modo=pontual` devolveu os mesmos 8 emissores em duas execuções seguidas, sendo 4 deles já analisados com `ok:true` na primeira. Dano além da rotina nova, e antigo: emissor deferido uma vez virava FULL permanente no tiering da noturna, gastando 9 rodadas de busca todo dia e realimentando o próprio deferimento. É a explicação do backlog de 34, e liga direto com PASSOCUSTO1. Fix `else delete` nos 5 ramos, guarda com prova das duas pontas (1 dos 15 testes falha contra o código anterior), suíte 119/119
- **RESOLVIDO 25/08 (SENTINELA-HANG1):** timeout real no `claude -p`, com morte da árvore. `Start-Process` com os três fluxos em arquivo dá o `WaitForExit(ms)` e de quebra elimina o deadlock clássico de pipe, onde `stderr` enche, o filho bloqueia escrevendo e o pai bloqueia lendo `stdout`. Teto por lote é o que sobra do teto da execução, piso de 4 min. No estouro, `taskkill /T /F` mata a árvore, porque `claude.exe` é lançador e o trabalho real está no `node` filho. Sem re-disparo imediato de propósito: lote que estourou o relógio estoura de novo e gastaria o teto duas vezes, então quem reexecuta é o backlog, com os emissores intactos. Prova com árvore real: `ANTES pai vivo=True filho vivo=True`, `WaitForExit(3000ms) devolveu False`, `DEPOIS pai vivo=False filho vivo=False`
- **ABERTO 25/08 (DEFERIDO-BACKLOG1, P3, observação):** com o DEFERGRUDA1 corrigido o backlog de 34 deve drenar sozinho, uma análise real por emissor. Vale conferir em uma semana se `pontual_candidatos` estabiliza perto de zero. Se não estabilizar, o teto de 700k da noturna é que está apertado para 103 emissores, e aí é decisão de orçamento, não de código
- **RESOLVIDO e DEPLOYADO 25/08 (SENTINELA1, Worker v4.9.216):** três defeitos achados ao preparar a inversão de horários, todos com prova das duas pontas. (1) Documento entregue no mesmo dia civil de uma varredura nunca contava como novo, porque `_cvmNovosDesde` comparava `YYYY-MM-DD`. Já mordia o top 15, analisado duas vezes ao dia. Agora "novo" é protocolo da CVM ausente de `radar:cvm_vistos:{empresa}`. (2) RELOGIO3H1 de novo, segunda ocorrência, medida ao vivo às 22h12: `_last_scanned_at` é instante UTC e `data_entrega` é dia civil BRT, e entre 21h e meia-noite a data UTC já virou, então documento entregue hoje aparecia como anterior a uma varredura de minutos atrás. `_diaCivilBRT` normaliza os dois lados. (3) O gatilho `cvm_overnight` da matinal usava janela fixa de 16h e morreria calado com a rotina às 18h, porque a conta daria 02h do mesmo dia. Passou a usar `cvmNovos`. Mais o `modo:"pontual"`, recorte do plano noturno por gatilho duro com teto 8 e excedente declarado em vez de cortado em silêncio. A marcação em `cvm_vistos` só acontece no `receber_analise` bem-sucedido, então análise que falha não consome o gatilho. Guarda `api/test/sentinela-pontual.test.mjs`, 13 testes, **6 falham contra o código anterior** (prova reversa medida). Suíte completa 117/117, 14 arquivos
- RESOLVIDO e DEPLOYADO 25/08 (SUBSTRINGDONO1, Worker v4.9.215, commit `ef3a5f4`): documento da CVM ia para o emissor errado. Medido em produção sobre 776 documentos: dos 28 entregues à Oi, 4 eram dela, o resto era Três Tentos, Saneamento de Goiás, Sequoia, Ecoponte e Equatorial Goiás, casando por substring dentro de SEQU(OI)A, AGR(OI)NDUSTRIAL, G(OI)AS e NITER(ÓI). A CSN recebia os 6 documentos da CSN Mineração, outro emissor. Pior, CSN e Copasa nunca tiveram alias e a CVM as registra como "CIA SIDERURGICA NACIONAL" e "COMPANHIA DE SANEAMENTO DE MINAS GERAIS", então documento nenhum delas entrava no KV: a Fitch rebaixou a CSN de B para CCC+ em 31/07, o relatório foi protocolado em 05/08, e a rotina caiu para imprensa com 15 documentos disponíveis no IPE. **A causa raiz não era o operador de comparação, era a pergunta**: enquanto cada emissor perguntasse "este documento contém meu nome?", N emissores respondiam sim ao mesmo tempo. Fase 1, árbitro único `_donoDocumentoCVM` com âncora de início de palavra e termo mais longo vencendo. Fase 2, a atribuição passou a usar **CNPJ** (a CVM publica `CNPJ_Companhia` na coluna 0 e o Worker nunca tinha lido), com `CNPJ_PRIMARIO_EMISSOR` (ITR/balanço) e `CNPJ_FAMILIA_CVM` (holding + 46 subsidiárias em 26 emissores) separados de propósito para a família não vazar no primário. Nome virou exceção (entidade estrangeira com CNPJ zerado) e caminho de compatibilidade (registro antigo sem o campo). O sync parou de descartar em silêncio, grava o CNPJ, e o que não tem dono vai para fila de revisão (`admin_cvm_quarentena`) em vez do limbo. Teto de 4000 documentos com número medido (a janela real dá 2175 docs / 0,82 MB contra limite de 25 MB do KV), descartando os sem dono primeiro e gravando a contagem. Cobertura no health, fora do `ok` agregado (lição do HEALTHSPLIT1). Reconciliadas as 8 divergências entre `scripts/emissores-cnpj.mjs` e `scripts/predictive/cnpj_emissores.json`, decisão do operador manteve o canônico em Omega (SERENA ENERGIA) e TIM (TIM S.A.). Guardas com prova de 2 pontas: `api/test/cvm-atribuicao.test.mjs` (28 testes, 7 falham contra o código anterior), `check-emissores-cnpj.mjs` estendida para reconciliar as 4 cópias de CNPJ, `check-cnpj-familia.mjs` nova reproduzindo e reprovando o buraco original da CSN. Suíte 104 testes, 13 arquivos, CI verde. Produção validada no portão. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 25/08 (TOKENCHAT1, P1, uma ação do operador): o `CLOUDFLARE_API_TOKEN` instalado ainda é o antigo, sem `Cloudflare Pages: Edit`, e por isso o `deploy-pages.ps1` cai no OAuth do wrangler. O substituto foi criado mas **não foi instalado** na variável. Medido em 25/08, não presumido: o token instalado continua **vivo** (`wrangler secret list` exit 0, 22 secrets listados), então rotina agendada e deploy de Worker não quebraram. Achado no caminho e já corrigido no `CLAUDE.md`: a variável vive em escopo `User`, não `Machine` como o arquivo declarava, o que gerou instrução errada de instalar com elevação. Um token foi colado no chat nesta sessão e revogado em seguida, mesma família do ROUTINEKEY-PLAIN1. Comando de instalação e detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 25/08 (PASSOCUSTO1, commit `f144d49`): a skill do noturno foi reescrita para orçar por lote, não por emissor. Medido na rodada de 25/08 (4 lotes: `rapida_1=199815 rapida_2=162612 rapida_3=147565 aprofundada_1=208325`, total 718k): **boot fixo ~130k por lote domina, marginal ~2–13k por emissor**. O texto antigo (9,5k/emissor rápida, 13k aprofundada) levava a multiplicar lotes achando que economiza e cortava a cauda de EWS alto. A reescrita traz `custo = 130000 x lotes + 5000 x emissores`, lote da aprofundada até 16 (limite de contexto, não de custo), fila ordenada por EWS desc antes de lotear, e reserva do custo da aprofundada calculada antes da rápida. Cap mais rigoroso que a recomendação original: **700k é teto de decisão, 725k é só folga de overshoot de lote já disparado**. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO e DEPLOYADO 24/08 (EMAILSILENT1, Worker v4.9.214, commit `db2842e`): falha de envio de e-mail transacional era invisível por construção. Quatro `catch {}` vazios em volta da Resend e um `console.error` solto, então aprovar alguém devolvia `ok:true` tivesse a mensagem saído ou não, e a única fonte autoritativa era o painel da Resend, fora do sistema. Motivador: `joao.tavano@mirabaud.com.br` aprovado sem forma interna de saber se o e-mail chegou. A varredura dos 16 call sites achou dois erros na lista original, `handleSolicitarReset` já tinha `console.error` e `handleAdminRejeitar` tinha o defeito e não estava citado. Corrigidos os 5 caminhos cujo destinatário é o usuário final. `enviarEmailRastreado` centraliza e nunca lança, a aprovação continua valendo se o e-mail falhar. Rastro em KV `email_envio:{email}:{ts}` com TTL de 90 dias, consulta por `admin_email_envios` cruzando com bounce e complaint. `solicitar_reset` mantém resposta genérica de propósito, anti-enumeração. Guarda `api/test/email-falha-silenciosa.test.mjs`, 7 testes, prova de duas pontas medida contra o código pré-correção. Suíte em 76 testes, 12 arquivos, CI `Worker Tests` verde em `db2842e`. Produção validada no portão e por sonda, `admin_email_envios` sem senha devolve 403 onde o código antigo devolvia 401. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 24/08 (EMAILSILENT1 resíduo, P3): os dois envios de notificação ao admin em `handleRegistrar` (cadastro novo e reenvio com dedup de 24h) seguem fora do helper. Não são silenciosos, têm `console.log` mais evento de Analytics Engine, mas ficam sem rastro por destinatário e sem alerta na Sentry. Segundo item, `enviarResend` devolve o objeto único quando sobra 1 resultado, então lote de 2 com 1 falha retorna forma indistinguível de envio único bem-sucedido, o que engana quem for instrumentar os call sites de lote
- RESOLVIDO 24/08 (CURADORIA1, Marco 1): os quatro cards de risco da Braskem apareciam vazios com "Pendente" no dia do protocolo de recuperação extrajudicial. Não era falha de coleta. `METRICAS_CURADAS` é tabela curada à mão dentro de `app/index.html`, e o commit `b13b605` da troca de carteira mexeu só no backend. Medido: carteira 103, curadas 101, e Braskem fora até do menu, enquanto a AES Brasil já fora da carteira seguia nos dois. Braskem, Tupy e Itaú Unibanco ganharam card com número de fonte primária, o schema ganhou `as_of`/`source_date`/`metric_type`, o placeholder deixou de prometer "Cobertura · ICSD" (métrica que nenhum emissor tem) e o painel passou a exibir a idade do dado. Guarda nova `scripts/check-metricas-curadas.mjs` no CI, três pontas provadas. Frontend v202.32 (v202.31 corrigida no mesmo dia, a idade do card usava Math.round e exibia "ontem" para fonte do proprio dia). **VERIFICADO DE FORMA INDEPENDENTE** em `main` `54030f2` por outra sessão, sem editar nada: guarda sai `EXIT=0` com 103/103/103, 412 cards, 12 com o trio de campos (`{"itr":9,"evento_credito":1,"rating":2}`), zero card sem fonte, valores conferidos no literal. Uma ressalva de leitura, no commit da guarda (`cc39280`) as etapas de guarda ficaram `skipped` e não passaram, a prova real está no run do v202.32 (`235f739`) onde as três rodaram `success`. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 24/08 (CURADORIA1 Marco 2, P2): os 101 emissores herdados seguem sem datação legível por máquina, 257 das 404 células declaram 4T25 em agosto de 2026. Aparecem como pendência declarada na guarda e ainda não reprovam. Andou em 24/08 com a primeira recuração de fato, a Unidas, e a pendência caiu de 400 para 396 cards. O card de Rating da Unidas virou o primeiro caso do EXCECAO-FRESCOR1, terceiro estado para card recurado cuja data é real mas está fora da janela, declarado e nomeado na saída da guarda em vez de sumir dentro dos herdados. A régua de ITR reprovaria todos hoje, o trimestre exigido é 2026-03-31. Recuração é lote próprio. Achado no caminho e já corrigido: o card de Rating do Vamos exibia AAA(bra) com perspectiva estável, quando a Fitch rebaixou para AA+(bra) com perspectiva negativa em 28/08/2024
- CORRIGIDO NO CÓDIGO, DEPLOY PENDENTE (BRASKEMDETECT1, P1, fechado 31/08): a Braskem protocolou recuperação extrajudicial em 24/08, US$ 10,9 bi reestruturados, e o sistema não pegou. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch de 17/08, não o protocolo do mesmo dia. O painel segue com 20/08 como fato mais recente. Duas causas somadas, o ZIP da CVM em 404 desde 23/08 tirou o gatilho primário, e a busca de imprensa sozinha não alcançou o protocolo. Liga na decisão pendente sobre fonte alternativa. **Adendo 19h48:** o print do operador mostra o protocolo já na timeline da Braskem, card CRÍTICO de 2026-08-24 com fonte `braziljournal.com` e cabeçalho "Analisado às 15:09", ou seja o evento entrou por imprensa depois da auditoria e o painel não está mais cego para ele. A causa raiz continua de pé e não há guarda de captura, então a pendência segue aberta, mas o enunciado "o sistema não pegou" caducou. Não confirmado no servidor nesta sessão, `op=state` exige autenticação (HTTP 401). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`. **Fechamento 31/08:** corrigido no código, não deployado. A query de imprensa R5 e a R3 da newsletter agora incluem "extrajudicial", `PALAVRAS_CRITICAS` ganhou o termo nas duas formas (com e sem acento), e `emitirAlertaTier1` promove o evento extrajudicial a `recuperacao-judicial`. Guarda `api/test/gatilho-recuperacao.test.mjs` (5 testes, prova das duas pontas). Deploy pendente de autorização: `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.227`
- RESOLVIDO 24/08 (SENDASGPA1 + RELOGIO3H1, commit `2928a74`, deploy `acf920d`): dois defeitos corrigidos e em produção desde 24/08 17:44 BRT (v4.9.213, validado por loop de 1 min). Alias contraditório entregava documento do Assaí para o Pão de Açúcar, e `_last_scanned_at` nascia 3h no passado para todo emissor com evento, inflando o gate de frescor. Guardas novas com prova das duas pontas, `scripts/check-alias-coerencia.mjs` e `api/test/relogio-varredura.test.mjs`. Suíte em 69 testes, 11 arquivos, CI verde. Produção em v4.9.213
- RESOLVIDO 24/08 (CALIB3 + ORDEMRAPIDA1 + SHADOWFALSOVERDE1, commit `2928a74`): três defeitos no script da noturna, achados observando a rodada rodar. A calibragem de token que eu havia colocado de manhã estava 4x alta e deferiu 15 emissores à toa, a fila rápida não era ordenada por risco apesar do comentário afirmar que era, e `parse_fail` do shadow saía rotulado `match` em 22 de 70 comparações. Não precisa de deploy, vale na próxima execução. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (CARTEIRA-24AGO1): AES Brasil saiu da carteira, Braskem entrou. Total segue 103, Worker v4.9.212, commit `b13b605`. Restam 3 emissores sem registro ativo na CVM, tolerados com motivo declarado na guarda (Banco Pan, Banco Votorantim, Nexa Resources). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (era ABERTO, NOMEMORTO1): eram 4 emissores sem registro ativo na CVM, tolerados com motivo declarado em `scripts/check-emissores-cadastro.mjs`. AES Brasil (incorporada pela Auren, fundir ou remover), Banco Pan e Banco Votorantim (fecharam capital, seguem emissores de dívida sem protocolo IPE), Nexa Resources (Luxemburgo via BDR, exceção permanente). Nenhum gera documento IPE, evento só por imprensa
- RESOLVIDO 24/08 (cobertura): Braskem entrou na carteira em v4.9.212
- RESOLVIDO 24/08 (NOMEMORTO1 + ACENTOMATCH1): emissor renomeado ficava cego por defeito de tabela de alias, nove meses no caso da Eletrobras. Worker v4.9.211, commit `e55d68d`, 62 testes. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 25/08 (CVMURL404, fecha por resolução externa): o ZIP `ipe_cia_aberta_2026.zip` voltou ao ar. Log da noturna de 25/08: `cvm_fonte_ok=true cvm_idade_dias=0`, relatório confirma `cvm_fonte_idade_dias:0, last_modified 25/08, falhas_consecutivas:0`. O sync voltou sozinho como previsto no bloco, e a ingestão de Fato Relevante está ativa de novo — só detecção e alerta foram necessários, nenhuma correção nossa. Entre 23/08 e 25/08 a fonte esteve fora: evento novo dependeu de imprensa e RAD. Ver o adendo "Aberto, decisão do operador" em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (CVMURL404, CVMMETAWIPE1, CVMDURA1, VOLTTL1, CAPRESERVA1, CALIB2): auditoria do painel travado em 20/08. Worker v4.9.209 e v4.9.210 em produção, 55 testes passando, commits `c0167cd`, `1572279`. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (WORKTREE12, continuação): das 6 worktrees do Claude Code, 4 eram checkout parado sem valor (removidas), 2 tinham trabalho real nunca commitado. RETRY-PROP1 (retry com backoff na validação pós-deploy do `deploy-worker.ps1`, commit `604c600`) e a extensão de `ROTINA_RESUMO` pras 2 rotinas que faltavam no cherry-pick de 21/08 (`run_vixradar_ranking_mensal.ps1`, `run_vixradar_verificacao_async.ps1`), ambos fundidos a mão em cima do `main` atual porque os arquivos-base tinham divergido. Achado no caminho, não corrigido por estar fora do escopo: `ranking-mensal` usa `$ErrorActionPreference = 'Stop'`, mas a rotina está OBSOLETA (task não existe mais). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 22/08 (WRCGL1, PULSOEVENTO1, JANELACARD1, ESTADOSTALE1, WORKTREE22 e DEPLOGGATE-JSON1): auditoria fechada, deploy v202.29 validado, memória canônica atualizada e fluxo de Pages protegido contra carimbo falso antes da publicação. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 22/08 (DATAATUALIZACAO1): frontend v202.30 deixa explícita a atualização real da base, separada da data do último evento. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`

- RESOLVIDO 21/08 01h40 (AUTONOMIAOFF1): frontend sem nenhuma verificação autônoma de rede, decisão do operador. Saíram os quatro timers que consultavam o servidor, rate meter a cada 2 min, auto-update a cada 3 min, anomalias a cada 30 min e status da ribbon a cada 60 s. Status e dados agora só na carga inicial e em gatilho do usuário. Frontend em v202.21. Detalhe no CLAUDE.md
- RESOLVIDO 21/08 01h50 (HEALTHWATCH-OFF1): vigia de health a cada 15 min desativado no Task Scheduler por decisão do operador. A task existe e está `Disabled`, o script `watch-vixradar-health.ps1` continua no repo, reversível com `Enable-ScheduledTask -TaskName "VIXRadar-Health-Watch"`. Alerta de queda continua via `canonical-test` a cada 6h e `frescor-check` diário
- RESOLVIDO 21/08 23h15 (TICKERPERIMETRO1 + ANOMSCHEMA1 + FONTELATENCIA1): as três decisões do operador assinadas e implementadas. Mapa de tickers classificado (95 entradas, 91 elegíveis, 4 inelegíveis, fonte em cada uma, commit `bae552b`), detector de anomalia de taxa indicativa recalibrado sem o `/100` e testado contra o schema real da fonte, promoção por imprensa no Worker com motivo `imprensa_recente_7d` e na skill da noturna. Worker em v4.9.208, 48 testes em 10 arquivos passando, commit `5283636`
- RESOLVIDO 21/08 01h35, DEPLOYADO: os três commits do dia subiram com o operador presente. Worker em v4.9.207 (`810dc2c`, segurança) e Pages em v202.20 (`6d657f8`, perf e acessibilidade) mais `806f2c7` (docs). O gate 3.4 do Pages reprovou duas vezes antes de subir, uma pelo `?v=` dos módulos admin desalinhado (CACHEBUMP1) e uma por arquivos gerados sujos, e abortou sem publicar nas duas, que é o comportamento esperado. Validação pós-deploy em produção: `ok:true`, `versao:v4.9.207`, `version.json v202.20`, `CACHE_VERSION v202.20` no apex
- NOVO 20/08 19h20 (MANIFESTOFRAGIL1, P3): o `status/allclear-manifesto.json` indexa cada frase de ausência junto com o HTML e o estilo inline, então trocar a cor de um texto faz a mesma frase reprovar como NOVA. Aconteceu hoje com duas frases na correção de contraste. Falso positivo de segurança, fragilidade real de projeto. Detalhe em `PENDENCIAS.md`
- NOVO 20/08 19h20 (DEDUPON2 + FEEDRERENDER1, P2): `_isDupSemantico` deduplica O(n²) sobre todos os eventos no boot e em todo refresh, e `_v201Refresh` reconstrói 30 dias de feed a cada evento. Medidos e reais, deixados de fora de propósito por exigirem refactor com risco de regressão. Detalhe em `PENDENCIAS.md`
- RESOLVIDO 24/08 (SACFALSA-RESIDUO, P3): a causa falsa do Smart App Control corrigida nos 3 arquivos vivos que a carregavam (`api/test/agenda-validacao.test.mjs`, `scripts/test-frescor-cvm.mjs` e `status/ESTADO.md`), substituída pela causa real (`npm ci --omit=dev` no deploy apaga o vitest). `test-frescor-cvm.mjs` mantido, cobre o cálculo de dias úteis em Node cru (31 casos). Guarda: gate no `scripts/hooks/pre-commit` reprova "Smart App Control" em staging fora de `Obsidian VIX Radar/` e `docs/archived/`. As notas de auditoria datadas (82, 85) e as entradas antigas de PENDENCIAS ficam intactas como registro histórico. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`.
- NOVO 20/08 19h20 (WORKTREE12, P3): 12 worktrees registradas, incluindo de Codex e Traycer, e 6 commits nunca empurrados. Um deles, `3d593d6` (ORF3D593D6), é trabalho real: aplica limpo nos 5 scripts, conflita só em `status/ESTADO.md:75`. Detalhe em `PENDENCIAS.md`
- Rotação da `routine_key`, decisão pendente do usuário, detalhe no incidente ROUTINEKEY-PLAIN1 do CLAUDE.md
- Migração KV→DO em andamento com KV ainda como fonte da verdade; auditar `console.warn` atrás de `[DO][dual-write]`/`[DO][read]`, detalhe no CLAUDE.md
- CORRIGIDO 20/08 19h: `npm test` RODA local. A causa antiga escrita aqui (Smart App Control bloqueando `workerd.exe`) foi refutada por medição, `VerifiedAndReputablePolicyState=0` e nenhum evento de CodeIntegrity citando workerd. O que acontece é que `deploy-worker.ps1` roda `npm ci --omit=dev` e apaga o vitest. Rode `npm ci` dentro de `api/` e a suíte sobe: 8 arquivos, 44 testes. Detalhe no CLAUDE.md
- Deploy de `producao/` é proibido, regrediria o frontend para v30/v40, detalhe no CLAUDE.md
- RESOLVIDO 19/08 09h15 (RETRYCFG1): as duas tasks de retry eram as únicas do projeto sem script de registro e nasceram sem as guardas que as outras nove têm. Tinham `StartWhenAvailable=False` (disparo perdido descartado em silêncio, causa do erro de 18/08), recusa de início na bateria, e `ExecutionTimeLimit` de 72h contra minutos das irmãs. Corrigidas e verificadas pelo novo `scripts/register-retry-tasks.ps1`. O alerta do monitor só some às 13h30, quando a task rodar, porque re-registrar não zera `LastTaskResult`. Detalhe em `PENDENCIAS.md`
- P2, não bloqueante: `monitor-tasks.ps1` tem diagnóstico específico para `VIXRadar-AgendaSemanal` preso ao exit code antigo (1); o script novo usa 2-8, catch-all genérico ainda pega qualquer falha como erro, só perde a mensagem específica. Detalhe em `routines/README.md`
- RESOLVIDO 21/08 (ORF3D593D6): retrofit da linha `ROTINA_RESUMO` em matinal/noturno/coleta-volatilidade/export-historico/reconciliacao-cvm resgatado por cherry-pick do commit `3d593d6`, que ficou 3 dias preso numa worktree e nunca tinha chegado ao remoto
- RESOLVIDO 19/08 00h10: os 24 `.ps1` + 4 `SKILL.md` (2 versionados + 2 vivos fora do repo) corrigidos, testados ao vivo (`monitor-tasks.ps1` e `retry-vixradar.ps1` rodados de verdade), guarda nova `scripts/lint-legacy-path.ps1` (Gate 5 do pre-commit). Detalhe em `PENDENCIAS.md`
- RESOLVIDO 19/08 03h10 (DEDUP1): feed do Painel de Eventos parado em 14/08. Dedup semântica do frontend descartava atualização real de saga longa quando a única diferença textual era "nova" ou quando a redação do analista se repetia quase verbatim. Corrigido, testado (`scripts/test-dedup-eventos.mjs`), deployado v202.11, confirmado ao vivo. Detalhe em `PENDENCIAS.md`
- RESOLVIDO 19/08 03h10 (HISTFLAT1+2): histórico de EWS não acumulava, `hist_len` preso em 1 para os 103 emissores. Duas causas (gate de leitura + mismatch de case na chave), corrigidas em sequência porque a primeira sozinha não bastou — a prova em produção pegou isso. Deploy Worker v4.9.199 depois v4.9.200, confirmado ao vivo (`hist_len` 1→2 uniforme). Detalhe em `PENDENCIAS.md`
- RESOLVIDO 19/08 12h07 (CVMFRESCOR1 + 1b): as duas P0 de frescor implementadas e em produção, Worker v4.9.201 depois v4.9.202. A idade da fonte CVM entra no `_okHealth` e os crons passaram a checar o retorno do `syncCVMAutomatico`. Health hoje volta `ok:false` com `cvm_fonte_motivo:"fonte_parada_ha_3_dias_uteis"`, que é o comportamento pretendido, a fonte está parada de verdade. `deploy-worker.ps1` e `canonical-test.yml` ajustados para não apontar o dedo para o fator errado. CI verde, 35 testes. Detalhe em `PENDENCIAS.md`
- RESOLVIDO 19/08 12h37 (EVENTOFRESCOR1 + FONTESFAKE1 + CARIMBOFAKE1): as três P1/P2 restantes fechadas, Worker v4.9.203 e frontend v202.12. Achado no caminho: a busca das rotinas não está quebrada, o feed reporta corretamente "evento mais material da janela de 30 dias" (o resultado do 2T26, 12-14/08), não "o que mudou desde ontem", e é essa lacuna de produto, somada ao apagão da CVM, que produziu o congelamento. Health diário ganhou `checks.evento_mais_novo`, o `frescor-check.yml` passou a gatear a idade dele em vez de `updated_at`, a tira de 7 fontes decorativas foi removida (só 2 tinham sinal real), e o carimbo "Atualizado em" mostra a idade do dado em dias úteis. Confirmado ao vivo via DOM (`status-left` com 0 filhos) e via health de produção. Decisão de produto (materialidade vs delta) e investigação de fonte alternativa à CVM ficaram registradas, não aplicadas. Detalhe em `PENDENCIAS.md`
- RESOLVIDO 19/08 09h00: junction legada `FREQUENTE\Monitoramento de Credito` removida com preflight e validação de integridade; 5 skills `vix-radar-*` deduplicadas (stubs em `C:` trocados por junctions para o conteúdo real em `E:`)
- NOVO 19/08, ainda não resolvido: 3 falhas de cobertura sem diagnóstico prévio (blackout de rotina em 13/08, matinal ausente em 14/08, noturno de 16/08 parado em 15/103 com lock órfão). Não eram a causa dos dois bugs acima, mas seguem sendo buracos reais de cobertura, fora do escopo desta sessão de fix
- NOVO 19/08 19h, ainda não resolvido: rotina noturna (103/103 no ledger, sem falha) mediu o custo real do lote via subagente pela primeira vez nesta arquitetura, ~14,6k tokens/emissor contra os ~9,5k calibrados na skill em 18/08. Hard cap de 700k estourou já na wave A (3 lotes RAPIDA = 658k). RAPIDA lote 4+5 (18 emissores) e a fila APROFUNDADA inteira (11 emissores de maior EWS, incl. Oncoclínicas, Oi, Raízen, CSN, Dasa) foram deferidos sem busca própria; os mesmos 11 já tinham passado pela aprofundada da matinal (10h), então o dia não ficou cego, só perdeu o delta noturno. CSN corrigida manualmente (achado cruzado no lote de CSN Mineração: Fitch rebaixou CSN de B para CCC+ em 31/07). Detalhe no log `logs/routines/vixradar-noturno_20260819.log`. Também achado no caminho: POST via Python urllib toma 403 do Cloudflare em api.vixradar.com (curl.exe e PowerShell passam). Vale o operador decidir se recalibra o orçamento (subir hard cap) ou reordena a fila (APROFUNDADA antes de RAPIDA, já que é a que cobre o maior risco)
- RESOLVIDO 20/08 15h50 (VOLTTL1 + VOLLOG1 + HEALTHWATCH3): investigação de "o sistema não foi atualizado". O feed parado é apagão da fonte, não bug nosso, o ZIP do IPE da CVM está com `Last-Modified: Sun, 16 Aug 2026 10:00:36 GMT`, 4 dias úteis, e o `cvm_fonte_ok:false` está certo em derrubar o `ok` agregado. As rotinas rodaram (matinal 20/20 às 10h21, verificação-async 16 eventos às 10h37, evento mais novo 18/08). Por baixo, três defeitos que ninguém tinha visto: a chave `cotacoes:volatilidade:v1` sumiu de produção porque o upload de 19/08 falhou e o TTL de 86400 era igual ao intervalo da rotina (republicada, TTL para 259200); o wrapper da coleta descartava a saída do uploader e logava só `exit=1` (agora despeja no log); o vigia de health alertava `ok=False` de 15 em 15 min sem citar a causa (agora nomeia o campo vermelho, testado ao vivo). Detalhe em `PENDENCIAS.md`
- RESOLVIDO 21/08 (DRIVERMORTO1): decisão assinada pelo operador, coletar `market_cap` em vez de remover os drivers. 3 dos 6 drivers do score preditivo nunca produziram nada em produção. `merton_dd` está `null` nos 103 emissores em todos os exports desde 11/07, porque o gate exige `market_cap` e nenhuma das duas fontes lidas tem esse campo. `momentum` e `mercado` também zerados. Mitigante, `predictive_v1` é lab interno e não chega ao cliente. Guarda já no ar (`scripts/check-drivers-preditivos.ps1`, ligado no export diário). Destravado pelo mapa TICKERPERIMETRO1 (95 entradas, commit `bae552b`). Próximo passo: construir o pipeline de coleta de `market_cap`
- RESOLVIDO 20/08 17h00 (CVMCADENCIA1 + HEALTHSPLIT1 + SPREADUNIDADE1 + MOJIBAKEORIGEM1): Worker v4.9.204 e frontend v202.15. A premissa "a CVM parou de publicar", escrita em 19/08 e repetida duas vezes hoje, é falsa. O ramo `CIA_ABERTA/DOC` tem cadência semanal declarada e publica aos domingos, então o limiar de 2 dias úteis fazia o health ficar vermelho toda quarta-feira. Virou regra de ciclo perdido, alerta só após dois ciclos semanais. Frescor de fonte externa saiu do `ok` agregado e ganhou `fonte_externa_ok` com canal de alerta próprio, porque 13 consumidores tratam `ok` como liveness e um deles abortava a rotação da chave. Achado P0 no caminho: o card do painel dizia "Spread ANBIMA" e carimbava " bps" sobre taxa indicativa em % a.a., Petrobras aparecia como "6,98 bps" para o cliente, erro de fator 100 sob nome errado, corrigido. Painel ganhou aviso de frescor com cadência da fonte e próxima publicação prevista, confirmado ao vivo. Detalhe em `PENDENCIAS.md`
- NOVO 20/08 17h00, fila aberta com tag e critério de pronto em `PENDENCIAS.md`: ~~TICKERPERIMETRO1~~ ✅21\08 (mapa classificado, commit `bae552b`), ~~DRIVERMORTO1~~ ✅21\08 (decisão: coletar market_cap, coleta a construir), ~~ANOMSCHEMA1~~ ✅21\08 (recalibrado sem o `/100`, testado contra schema real), SPREADUNIDADE1 resíduo (renomear o campo no KV), PUBDATA1 (`data_publicacao_fonte` em 0/74 eventos), FEEDNOVIDADES1 (aba Novidades, parada até PUBDATA1), FONTELATENCIA1 (fonte de baixa latência é decisão do operador), BANNERMORTO1 (o banner de aviso nunca pintou para ninguém, inline `display:none` vence a folha de estilo), ~~CACHEBUMP1~~ ✅24/08 (âncora e lookahead no `bump-cache-version`, teste de regressão)
- RESOLVIDO 20/08 21h15 (janela de manutenção, 7 achados): Worker v4.9.203 para v4.9.206, frontend v202.12 para v202.19, 30 commits. Achado principal, cinco superfícies diferentes (painel EWS da home, pulso do monitor, briefing, painel ANBIMA, os 5 mo-card) tratavam "não consegui ler" como "medi zero" e afirmavam a carteira inteira normal sem nunca ter lido a base, corrigidas com a mesma guarda `_semLeitura`/`detector_operacional` e confirmadas ao vivo numa sessão autenticada via CDP (6 a 7 críticos e 42 a 54 relevantes reais, nada de "tudo normal"). SPREADSERIE1 corrigido, a série de mercado misturava ponto-base do provedor legado com percentual do atual no mesmo z-score. Banner de aviso ao usuário, morto desde sempre por CSS inline vencendo a folha de estilo, religado e provado 6 de 6. Duas ferramentas novas de guarda permanente, `check-frontend-allclear.mjs` (57 frases de ausência classificadas em manifesto versionado) e `audit-ui-live.mjs` (inventário do DOM ao vivo via CDP, 62 superfícies, achou o ROTULOEVENTO1 que o regex antigo nunca veria). Rollback documentado em `_backup-janela-20260820/ROLLBACK.md`, não versionado. Detalhe em `PENDENCIAS.md`
- NOVO 20/08 21h15, não executado: Bloco D (segurança, performance, acessibilidade, OWASP LLM), Bloco E (TICKERPERIMETRO1, ANOMSCHEMA1, CACHEBUMP1, varredura do CLAUDE.md, revisão do commit `a4a0b47` de sessão paralela) e Bloco F (documento de decisão sobre FONTELATENCIA1 e DRIVERMORTO1) ficaram para a próxima sessão, a atual encerrou na reabertura da janela
