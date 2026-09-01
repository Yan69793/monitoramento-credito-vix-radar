---
data: 2026-08-24
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: saudavel-com-achado
---

# Estado Atual — VIX Radar

> [!info] 01/09 BRT — **Produção v4.9.232. PREVERIFSEC1: sec.gov aceita como fonte oficial de documento no pré-verificador; fechamento dos 5 resíduos da sessão anterior.** O evento CRÍTICO da Braskem de 31/08 (recuperação extrajudicial, Form 6-K da SEC) era descartado pelo pré-verificador com `ok:true` mas `n_eventos:0`, porque a SEC retorna 403 a User-Agent genérico e `sec.gov` não era reconhecido como fonte confiável. Fix distinto: novo conjunto `DOMINIOS_FONTE_OFICIAL_DOCUMENTOS` (SEC/CVM/B3/BCB/IN/Anbima) separado de agência de rating, helper `_ehFonteConfitavelBloqueada`, aceite só dentro da janela de 30d e sempre com `_verif_forcar=true`. Não é bypass genérico. Guarda `api/test/pre-verificador-sec-gov.test.mjs` (8 testes, prova de 3 pontas). Deploy `deploy-worker.ps1 -Version v4.9.232`, commit `66b8b74`, push OK. Também fechados nesta sessão: `SUBMITOK-ENGANOSO1` (ledger `OK|` com 6º campo e resumo analisados/skip/deferidos/submits), cruzamento dos 1.439 sem dono = COMPORTAMENTO ESPERADO (nenhuma correção de atribuição), cron da noturna com descrição corrigida para 10h, e fonte intradiária = LIMITAÇÃO ACEITA COM CONDIÇÃO DE REABERTURA.
> **Status:** vigente · **Data da Versão:** 2026-09-01 · **Origem do Registro:** fechamento da sessão anterior. Prova em duas pontas no `pre-verificador-sec-gov.test.mjs` e saída crua do portão `ok:true versao:v4.9.232 kv:true telemetria:true sentry_ok:true`.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.232.

> [!info] 01/09 BRT — **Produção v4.9.231. AVANCOFEED1: guarda de avanço do feed, e cron da noturna de volta às 10h.** O painel ficou parado em 28/08 de 28/08 a 01/09 com as três rotinas rodando e todo semáforo verde. Diagnóstico medido: o feed está no teto do que o pipeline pode publicar, `teto_elegivel = feed_max = 2026-08-28`, e o próximo lote da CVM é 06/09. O gate que existia media "N dias úteis sem evento" e reprovaria hoje mesmo esse estado saudável. `checks.avanco_feed` passa a comparar o teto do feed com o teto elegível da fonte e com a cadência dela: seis estados, e só `pipeline_nao_persistiu` e `sem_evento_datado` alertam. Cron `vixradar-noturno` revertido de `0 8 * * *` para `0 10 * * *` antes de disparar uma vez sequer, porque 08h BRT é antes da B3 abrir e antes de CVM e imprensa publicarem o dia. Deploys `v4.9.229` → `v4.9.230` → `v4.9.231`, commits `6e0dda8`/`90e8612`, `70d3dbc`/`df85c52`, `cc22e20`/`caffe43`, push OK.
> **Status:** vigente · **Data da Versão:** 2026-09-01 · **Origem do Registro:** pedido do operador depois do diagnóstico do feed parado. Duas correções vieram da própria medição, não de revisão de código: a `v4.9.230` porque `cvm_fonte_last_modified` vem sem hora e tomá-la como 00:00Z acusaria o pipeline por uma janela que ele não teve, e a `v4.9.231` porque a primeira execução real da guarda (run `33472230172`) reprovou usando o teto do acervo inteiro, inflado por 1439 documentos sem dono entre os 103 e por datas de referência no futuro, os dois já filtrados pelo `costurarCvmEmEventos`. Guarda `api/test/avanco-feed.test.mjs`, 21 testes, prova de duas pontas; suíte 188/188. Prova em produção nas duas pontas: run `33472230172` reprova com exit 1, run `33472592026` aceita com `saudavel_sem_fato_novo` e `FRESCOR_OK`. Portão `HTTP:200 ok:true versao:v4.9.231 kv:true telemetria:true sentry_ok:true`. Frontend intocado. Fonte intradiária e semântica de `submit_ok` ficaram REGISTRADAS sem correção, em [[PENDENCIAS]].
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.231 ou quando o cron da noturna mudar de novo.
>
> [!warning] 01/09 BRT — **Produção v4.9.228 (histórico). Os 4 achados da auditoria geral de 01/09 fechados, escopo travado.** `DISJUNTORHOUSEKEEP1`: o teto de custo diário abortava o cron matinal e o noturno inteiros, e desde a delegação da varredura ao Claude Desktop eles só fazem housekeeping, então um dia caro nas rotinas locais matava aqui o `sync_cvm` e o `healthcheck_diario`, os dois sinais que o watchdog e o frescor leem. O gate passou para dentro do ramo de varredura. `LOGINTIMING1`: o login tinha três tempos para a mesma mensagem genérica (medido antes: inexistente 124ms, senha errada 45ms, pendente 10ms, rejeitado 11ms; depois: 155/140/170/140ms). Deploy `deploy-worker.ps1 -Version v4.9.228`, commits `e44cd7c` e `8ac3e0e`, push OK.
> **Status:** vigente · **Data da Versão:** 2026-09-01 · **Origem do Registro:** correção pedida pelo operador sobre a nota [[98 - Auditoria Geral 2026-09-01]], limitada aos 4 achados P3/P4. Guardas `api/test/disjuntor-cron.test.mjs` (6 testes) e `api/test/login-timing.test.mjs` (3 testes), as duas com prova reversa medida, suíte 167/167. Portão pós-deploy `ok:true versao:v4.9.228 kv:true telemetria:true sentry_ok:true verificador_ok:true`, HTTP 200. Frontend intocado e sem drift, `v202.35` nas três pontas.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.228.
>
> [!warning] 31/08 BRT — **Produção v4.9.227 (histórico). BRASKEMDETECT1: gatilho de imprensa endurecido para recuperação extrajudicial.** R5 (e R3 da newsletter) agora incluem "extrajudicial", `PALAVRAS_CRITICAS` reconhece o termo nas duas formas e `emitirAlertaTier1` promove o evento à tag `recuperacao-judicial`. Deploy `deploy-worker.ps1 -Version v4.9.227`, commit `af2abb1`, push OK.
> **Status:** vigente · **Data da Versão:** 2026-08-31 · **Origem do Registro:** fechamento da pendência BRASKEMDETECT1 (protocolo da Braskem de 24/08, US$ 10,9 bi, que a imprensa não alcançou). Guarda `api/test/gatilho-recuperacao.test.mjs`, 5 testes, prova reversa medida, suíte 158/158.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.227.
>
> [!warning] 31/08 BRT — **Produção v4.9.226 (histórico). CVMNOVOSDEAD1: `cvm_novos` estava zerado para os 103 emissores todo dia desde 25/08.** CVM volta a poder promover emissor pra fila aprofundada sozinha, sem depender de imprensa.
> **Status:** vigente · **Data da Versão:** 2026-08-31 · **Origem do Registro:** auditoria pedida pelo operador depois da rotina noturna do dia, ao investigar por que nenhuma promoção veio de documento CVM (os 3 CRÍTICO do dia, Braskem/Oncoclínicas/Oi, vieram todos do bypass de imprensa FONTELATENCIA1). Deploy `deploy-worker.ps1 -Version v4.9.226`, commit `9acd814`, push OK.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.226.
>
> **Dois defeitos independentes, medidos, não hipóteses.** `_cvmNovosEfetivo` aplicava corte por data SEMPRE
> (não só no bootstrap), contra o dia civil da última varredura, que roda diariamente. A CVM (`ipe_cia_aberta`)
> publica semanalmente aos domingos, `Data_Entrega` no máximo até a sexta anterior. Medido em produção 31/08:
> `since`=30/08, máximo `data_entrega`/`data_referencia` do lote inteiro (103 emissores) = 28/08. Estrutural,
> não específico daquele dia — sob operação diária estável, essa comparação nunca teria como dar `cvm_novos>0`.
> Segundo defeito: `receber_analise` só marcava `radar:cvm_vistos` se o corpo trouxesse `cvm_ids_analisados`,
> e nenhuma rotina jamais mandou (o plano expõe `cvm_novos_ids`, nome diferente) — a chave nunca foi escrita
> para nenhum dos 103 desde que SENTINELA1 existe (25/08).
>
> **Fix:** corte por data só no bootstrap (`vistosIds` vazio); pós-bootstrap, identidade de protocolo basta,
> sem competir com o calendário da fonte. `receber_analise` deriva `cvm_ids_analisados` sozinho quando o
> cliente não manda (auto-cura, servidor não depende de nenhum `SKILL.md` de rotina lembrar do campo certo).
> `SKILL.md` do noturno e da matinal (scheduled tasks locais, fora do repo git) também atualizados.
> 153/153 no vitest, 8 testes novos com prova reversa (3/8 falham contra o código anterior).
>
> **CNPJVALIDA1, mesma sessão.** Neoenergia ganhou 5 subsidiárias reguladas em `CNPJ_FAMILIA_CVM` (Coelba,
> Celpe, Cosern, Elektro Redes, Afluente Transmissão), confirmadas ATIVO no `cad_cia_aberta.csv` vivo da CVM,
> mesmo domínio de e-mail de RI da holding, mesmo padrão já validado pra CEMIG/Energisa. Prova em produção:
> Neoenergia foi de 0 pra 1 documento no plano logo após o deploy. Banco Pan, Nexa Resources e Banco
> Votorantim confirmados como exceção real (Banco Pan cancelou registro de Cia Aberta em 30/03/2026; os
> outros dois nunca foram Cia Aberta, nenhuma forma, ativa ou cancelada, em nenhum nome testado) — já tinham
> exceção declarada em `scripts/check-emissores-cadastro.mjs` desde 24/08, nada pra corrigir de fato.
>
> **Fonte intradiária oficial: bloqueada só por credencial, não por impossibilidade técnica.** Correção sobre o
> registro original desta sessão: o **Download Múltiplo de Companhias** da CVM suporta automação e janela de
> até 24h, mas exige credencial própria da CVM ausente neste ambiente — bloqueio diferente do de RAD
> (reCAPTCHA v3/v2, bot-detection que não se contorna) e do de `dadosdemercado.com.br` (Bearer pago, ausente,
> `wrangler secret list` conferido, zero candidato). Fica como oportunidade real, não fechada, sem solicitar
> ou gerar credencial agora. Arquitetura segue em duas camadas por ora, semanal (agora funcional) + imprensa
> (enriquecimento).
>
> **Horário: mudado no config, ainda não ativo.** `cronExpression` de `vixradar-noturno` foi de `0 10 * * *`
> para `0 8 * * *` no `scheduled-tasks.json` (backup feito antes). Por INVERSAO-CD1 só vale depois de reiniciar
> o Claude Desktop, ação do operador — não feita nesta sessão porque derrubaria a própria sessão em andamento.
> Até lá a rotina continua em 10h00 BRT.
>
> Portão de duas pontas: health produção `ok:true versao:v4.9.226 kv:true telemetria:true sentry_ok:true
> cvm_fonte_ok:true`, 4 guardas locais de CNPJ/cadastro verdes pós-edição, git local=remoto em `9acd814`,
> working tree limpo.

> [!success] 25/08 noite BRT — **Produção v4.9.216.** Horários das varreduras invertidos e nasce a varredura pontual.
> **Status:** vigente · **Data da Versão:** 2026-08-25 · **Origem do Registro:** medido contra produção v4.9.216, `Get-ScheduledTask` ao vivo, `HEAD` no zip da CVM, suíte 117/117 · **Condição de Obsolescência:** cai quando o mecanismo de agendamento do Claude Desktop mudar, quando existir ação de sync da CVM com escopo de rotina, ou quando qualquer linha das tabelas de `routines/README.md` divergir do que o Task Scheduler responde.
>
> **A varredura completa dos 103 passa a rodar às 10h e o top 15 às 18h.** Os identificadores das rotinas ficaram invertidos em relação aos horários de propósito (`vixradar-noturno` roda de manhã), porque renomear tocaria nome de log, `-RoutineId` dos vigias, `monitor-tasks.ps1`, heartbeats do Worker e `expectedAgents`, para ganho de função zero. **Ao ler log, vá pelo horário, não pelo nome.** Motivo: ao meio-dia, 88 dos 103 emissores tinham dado da noite anterior, e fato relevante no Brasil sai principalmente depois do fechamento. Com a completa às 10h, o lote da noite anterior entra 15h depois em vez de 23h.
>
> **Três defeitos achados ao medir, corrigidos no v4.9.216, todos com prova das duas pontas.** (1) Documento entregue no mesmo dia civil de uma varredura nunca contava como novo (`_cvmNovosDesde` comparava `YYYY-MM-DD`); já mordia o top 15, analisado 2x ao dia. Agora "novo" é protocolo ausente de `radar:cvm_vistos:{empresa}`, marcado **só** no `receber_analise` bem-sucedido, então análise que falha não consome o gatilho. (2) **RELOGIO3H1 de novo, segunda ocorrência**, medida ao vivo às 22h12: `_last_scanned_at` é instante UTC e `data_entrega` é dia civil BRT, e entre 21h e meia-noite a data UTC já virou. `_diaCivilBRT` normaliza. (3) O gatilho `cvm_overnight` da matinal usava janela fixa de 16h e morreria calado com a rotina às 18h. Guarda `api/test/sentinela-pontual.test.mjs`, 13 testes, **6 falham contra o código anterior**.
>
> **Rotina nova `VIXRadar-Sentinela`**, duas vezes por hora aos :25 e :55, dias úteis 09h25 a 17h55. Detector barato na frente (portão pelo acervo que o Worker enxerga + backlog), análise cara atrás. Teto de 8 emissores e 120k tokens. Na maioria das execuções sai em 0 token. Os dois disparos por hora não são redundância: o segundo é a rede da colisão, e sem ele um choque com a varredura das 10h empurraria o caso para quase 2h.
>
> **Dois achados que ela expôs de imediato.** A CVM repôs o arquivo que sumiu em 23/08, publicado às **07h58** e ingerido só às **12h30**, 4h32 de atraso estrutural com todo semáforo verde. E o `modo=pontual` acusou **34 emissores parados na fila de deferidos** por teto de tokens, backlog que antes só era revisitado pela rotina do dia seguinte, que deferia de novo.
>
> **Pendências reais que sobraram:** as três sessões do Claude Desktop ainda estão nos horários antigos (ação de GUI do operador, INVERSAO-CD1), e a latência CVM-publica → Worker-ingere continua presa aos crons das 12h30 e 18h30 porque não existe ação de sync com escopo de `ROUTINE_API_KEY` (SENTINELA-SYNC1). Detalhe em [[PENDENCIAS.md]] e `routines/README.md`.

> [!success] 24/08 BRT — **Produção v4.9.213 / frontend v202.30.** CARTEIRA-24AGO1: AES Brasil sai (incorporada pela Auren), Braskem entra. **RELOGIO3H1 corrigido e deployado no mesmo dia da auditoria** (commit `2928a74`, v4.9.213 — loop de 1 min capturou o deploy ao vivo: c3 v4.9.212 → c4 v4.9.213). `_last_scanned_at` agora é UTC real no `receber_analise` (antes `obterAgoraBRT()` inflava `horas_stale` em 3h no ramo com evento); nova guarda `relogio-varredura.test.mjs` (3 testes, prova dos dois ramos). Em produção v4.9.213: `stale>=24h:0`, `max_horas:4.7`, dado recém-gravado reporta `h_stale:0`. Noturna 24/08 17:00 rodou 103/103 (`submit_ok=70`). **BRASKEMDETECT1 ABERTO P1:** Braskem protocolou recuperação extrajudicial 24/08 (US$ 10,9 bi reestruturados) e o sistema não pegou — ZIP CVM em 404 desde 23/08 tirou o gatilho primário e a busca de imprensa sozinha não alcançou o protocolo; depende de decisão de fonte alternativa (MZiQ). **CI verificado via `gh` (lacuna da auditoria fechada):** Worker Tests v4.9.213 verde com 69/69 (`relogio-varredura.test.mjs` 3/3), Cadastro dos Emissores verde, canonical-test verde nos 3 últimos slots. Lacuna restante: `cvm:documentos` em produção exige `ADMIN_PASSWORD` (não auditado nesta sessão). Detalhe: [[91 - Auditoria Operacional 2026-08-24]] e alinhamento em [[PENDENCIAS.md]] (RELOGIO3H1 RESOLVIDO EM PRODUÇÃO, BRASKEMDETECT1 ABERTO). Rotação da `routine_key` segue pendente (decisão do operador).

> [!success] 22/08 BRT — **Frontend v202.30.** A rotina de 21/08 processou os 103 emissores, mas não encontrou fato com `data_evento` em 21/08. A tela mostrava apenas o último evento de 20/08 e sugeria, de forma enganosa, que o painel não tinha sido atualizado. O carimbo agora mostra também o horário real da base, em BRT. Deploy validado no Pages.

> [!success] 22/08 BRT — **Auditoria fechada, produção v4.9.208 e v202.29.** WRCGL1 reconstruiu as 13 entradas ausentes do changelog do Worker e o deploy agora reprova versão sem registro. PULSOEVENTO1 e JANELACARD1 foram corrigidos no frontend e confirmados em produção. DEPLOGGATE-JSON1 moveu o carimbo real de `version.json` para depois de todos os gates, evitando data falsa quando o deploy é reprovado antes da publicação. Detalhe em [[89 - Auditoria Geral 2026-08-22]] e [[PENDENCIAS.md]].

> [!success] 21/08 23h30 BRT — **Duas ondas de correção fechadas, produção v4.9.208 e v202.21, 48 testes.** Noturna 20/08 rodou 103/103 com 5 críticos (Hapvida cautelar ANS 947 mil contratos, Oncoclínicas REX deferida, Oi caixa R$ 19,6 mi, Kora Saúde AGDs, CSN Fitch CCC+). Segurança: REGISTRO-ADMIN1 (e-mail do corpo não concede mais admin, teste de regressão provado nos dois sentidos), RATELIMIT-FAILOPEN1 com AUTHDISPO1 (login de cliente abre com alerta em falha do limiter, senha admin errada fecha). Frontend: contraste WCAG corrigido (pior caso foi de 1,74:1 para 5,57:1), timers de rede autônomos REMOVIDOS por decisão do operador (AUTONOMIAOFF1), vigia de 15 min desativado (HEALTHWATCH-OFF1), alerta de queda agora em até 6h. Decisões assinadas em DECISOES-OPERADOR-2026-08-20: FONTELATENCIA1 (promoção por imprensa `imprensa_recente_7d`, sem esperar ZIP semanal da CVM) e DRIVERMORTO1 (ANOMSCHEMA1 corrigido, sem o `/100` herdado de ponto-base; mapa TICKERPERIMETRO1 classificado, 95 entradas com fonte, 91 elegíveis, 4 inelegíveis). Commit órfão 3d593d6 resgatado por cherry-pick. Suite: 10 arquivos, 48 testes, incluindo correção de teste que quebrava por fuso depois das 21h. Pendências vivas: MANIFESTOFRAGIL1, DEDUPON2, FEEDRERENDER1, SACFALSA-RESIDUO, WORKTREE12. Próximo passo do Merton: pipeline de coleta de market_cap, destravado pelo mapa.

> [!success] 20/08 21h15 BRT — **Janela de manutenção: 7 P0/P1 de veracidade de UI + SPREADSERIE1.** Worker v4.9.203→206, frontend v202.12→19. Os P0 do dia: home pública dizia "todos dentro dos parâmetros normais" com cache nulo lido como zero, seis banners nunca renderizaram por inline `display:none`, spread ANBIMA exibido como " bps" sendo % a.a., mo-cards verdes com leitura falha. Guarda de frases de ausência generalizada para 57 frases com manifesto versionado.

> [!success] 17/08 11h42 BRT — **Matinal 17/08: 19/19 processados, 6 CRITICO, 7 RELEVANTE, 6 ECO, 0 SKIP/deferido/INCONCLUSIVO/falha.** Plano trouxe 19 de novo (mínimo por setor do v4.9.157, não é bug). Fila aprofundada (7): Oi, Oncoclínicas, Raízen, GPA, Kora Saúde, Light, CSN. A CSN teve a análise original perdendo o rebaixamento Fitch B→CCC+ de 31/07/2026, achado só na busca do próximo emissor da fila (CSN Mineração) e corrigido no mesmo run com reenvio contendo os dois eventos (rebaixamento + troca de US$1,007bi em bonds 2028→2030, cupom 6,75%→11%, liquidada 12/08). Demais CRITICO: Oi (quatro balanços atrasados sem data, reunião de esclarecimento 13/08), Oncoclínicas (RE deferida 04/08, adesão 37% de 50% necessário em 90 dias), Raízen (RE homologada 30/07, resultado 1T safra 26/27 em 13/08), GPA (term sheet de debênture aprovado 12/08, aguarda homologação), Hapvida (lucro ajustado -95,8% no 2T26, ação -33% no dia 13/08). RELEVANTE: Light (conversão de debênture R$1,66bi em 30/07, mira saída da RJ set-out/26), Aegea (aumento de capital R$2,1bi aprovado 28/07), Cosan (dívida líquida expandida -47% a/a, venda do terminal Porto São Luís), Tupy (reversão pra prejuízo no 2T26, alavancagem 4,02x→4,14x), Eneva (UTE Azulão I entrou em operação 04/08, alavancagem 2,8x→3,2x em um trimestre), MRV (prejuízo de R$626,3mi 2x acima do esperado, mas venda de ativos legado Resia deve cortar R$1,7bi de dívida), JBS (linha de crédito rotativo ampliada pra US$2,65bi, alavancagem 2,27x→3,1x puxada por dividendo). Todos os CRITICO/RELEVANTE com fonte primária CVM (Fato Relevante/Comunicado) ou imprensa especializada com slug específico, nenhum em domínio raiz ou homepage. Um erro próprio no meio da execução, `-ContentType` com typo no PowerShell do reenvio da CSN, autocorrigido no mesmo minuto (FAIL seguido de OK no log). Depois da rotina, Yan pediu conferência visual do card no site: não deu pra confirmar, a área logada exige senha (não digito, é regra fixa independente de quem autoriza) e a home pública só mostra um exemplo anonimizado de marketing ("snapshot sem nome de emissor real"), não os cards de verdade. `op=state` pela API retorna 401 sem JWT, e `dados_para_analise` via `routine_key` não é ação de leitura de card (400). Única confirmação possível foi a de escrita, `contexto_historico` do `listar_plano_rotina` atualizado com timestamp e acentuação intactos ("Oncoclínicas" sobreviveu ao round trip). Zero commit, zero deploy nesta sessão, único arquivo tocado foi o log da rotina (`logs/routines/`, gitignored). Health antes e depois: `ok:true kv:true telemetria:true sentry_ok:true verificador_ok:true`, v4.9.195.
> [!success] 17/08 05h10 BRT — **Continuação da sessão de 03h45: causa raiz do noturno de 16/08 achada, cobertura histórica medida, push de 3 commits destravado. Sem deploy.** Causa raiz do noturno de 16/08 (que a correção do FIMRUN21 desta mesma sessão expôs): não foi colisão de agendamento com a verificação assíncrona das 18h20, hipótese descartada porque 15/08 teve a mesma sobreposição sem incidente. A causa é a máquina reiniciando sozinha, `Rise Mode Temp CPU Driver R2.2.exe` travando repetidamente (dez vezes só em 16/08, padrão desde pelo menos 10/08) e cada crash puxando um restart do Windows junto, um deles às 18:36:52 caiu em cima do noturno em andamento, processo morto sem `ABORT` nem `ERRO FATAL`, lock órfão com PID 28448 nunca liberado. Cobertura real daquela noite ficou entre 15 e 45 de 103 emissores, confirmado (15) e reivindicado sem prova individual (mais 30). Medição de sete noites de log (09 a 16/08, faltando 13/08, incidente AUTHWEEK1 já conhecido) usando contagem de nome único de emissor em vez de confiar na linha `FIM:` mostrou: perda de dado real em uma noite de sete, e cegueira do monitor por linha `FIM:` ausente mesmo com o trabalho completo em outras duas noites (08/11 e 08/14, achado novo, separado do FIMRUN21). Conclusão registrada: não vale construir checkpoint automático diário, caro para um problema raro e de causa externa. Vale ensinar `monitor-tasks.ps1` a fazer a mesma contagem por nome único como fallback quando não achar `FIM:`, código puro, sem custo de token, recomendado e ainda não implementado. 16/08 era domingo, decisão foi deixar pro disparo natural de 17/08 18h05 BRT em vez de reprocessar na mão. Push: os 3 commits pendentes (`960b56c` de 16/08, mais `ed40757` e `2fc9216` desta sessão) travavam com 403 num token fine-grained sem escopo Contents, e ao tentar corrigir a permissão pelo GitHub a sessão pegou um incidente à parte, um `[Environment]::SetEnvironmentVariable('GH_TOKEN', ...)` rodado pelo usuário quebrou a variável duas vezes seguidas (primeiro com o placeholder literal, depois esvaziada), e o valor completo de um token fine-grained ficou exposto em texto puro no chat ao tentar corrigir, precisa ser regenerado por higiene quando for conveniente. A causa real do bloqueio não era a permissão nenhuma, `GH_TOKEN`, mesmo quebrado, tinha prioridade sobre uma credencial OAuth já autenticada e guardada no keyring do Windows (escopo `repo`, `read:org`, `gist`, `workflow`). Limpar `GH_TOKEN` destravou o push na hora. Mesma credencial keyring pode destravar a rotação da `routine_key`, parada desde 15/08 pelo mesmo tipo de bloqueio de PAT, ainda não tentado. Health no fechamento: `ok:true kv:true telemetria:true sentry_ok:true rate_limiter:true admin_email_ok:true verificador_ok:true`, v4.9.195, working tree limpo, `0 0` contra origin.
> [!success] 17/08 03h45 BRT — **Decisão de custo sob plano Max, portão com exit code real e 3 pendências fechadas por evidência. Sem deploy.** Custo: com Max, rotina local e sessão interativa são flat, trocar modelo delas economiza zero. Dólar real só vaza no cascade do Worker e na chave paga `VIXRADAR_ANTHROPIC_API_KEY`, que só entra quando a assinatura estoura o limite semanal (foi o que houve em 12/08, ~2M tokens, 223k cobrados). O recurso escasso é folga semanal de token, não dinheiro, e o dinheiro é sintoma. Logo a alavanca única é o envelope da noturna (cap de 700k estourando toda noite, ~70% acima do desenho), e o framework de medição custo por evento aprovado em USD otimiza a variável errada. Ergonomia: `scripts/portao-verificacao.ps1` novo, o portão agora sai com código 1 quando qualquer flag do health não vem `true` (o `curl -s` saía 0 com `ok:false`, mesmo modo de falha do `ADMIN_EMAIL` ausente por 3 dias), virou build task padrão no Ctrl+Shift+B, e `.vscode/tasks.json` ganhou verificar rotinas local e live, monitor de tasks, lint de encoding e drift do vault. FIMRUN21: `monitor-tasks.ps1` lia só a última linha `FIM:` do log e o noturno de 15/08 escreveu duas (run-1 com `103/103 processados`, run-2 com `Total do dia 103/103`), a segunda não casava com padrão nenhum e gerava 9001 falso desde 13/08, escondendo falha real. Agora varre todas as linhas e fica com o maior contador, validado contra o log de 15/08. Fechados por evidência: `express`/`openai` removidos do `api/package.json` (zero import no `api/`, `npm ci` revalidado), lint de encoding 63/63 OK sem `.ps1` sujo no working tree, e `top_n=15` devolvendo 19 é comportamento correto, não bug, o mínimo por setor do v4.9.157 (`worker.js:8953`) adiciona emissores depois do corte. Segue aberto: rotação da `routine_key` (trava no PAT), envelope da noturna, `ROUTINE_API_KEY` do scan-emergencia (workflow verde há 4 noites mas só no caminho no-op, a chave nunca é exercitada), token Pages:Edit. Health no fechamento: `ok:true kv:true telemetria:true sentry_ok:true rate_limiter:true admin_email_ok:true verificador_ok:true`, v4.9.195.
> [!info] 15/08 10h46 BRT — **Matinal 15/08: 19/19 emissores processados via retry manual (Claude Code) após troca de modelo, sessão original do Claude Desktop não concluiu.** Plano trouxe 19 emissores (não 15 esperado, seguido com aviso, pendência aberta). 3 CRITICO: Oncoclínicas (RE deferida 05/08, R$5,1bi), Kora Saúde (standstill debenturistas + rating em nível de default), CSN (Fitch rebaixou B→CCC+ em 31/07, dívida pode passar R$60bi). 9 RELEVANTE (destaque: Light pediu encerramento da recuperação judicial após aumento de capital de R$1,5bi), 4 ECO, 3 NENHUM. 0 SKIP, 0 deferido por cap de token (~36 buscas efetivas), 0 INCONCLUSIVO, 0 falha de submit. Achado transversal: contágio de rating no grupo Cosan (Cosan, Rumo e CSN todos com ação de rating citando estresse da Raízen). Executado num sábado sem guarda de fim de semana no script (retry explícito do usuário). Health `ok:true kv:true telemetria:true` estável antes e depois, v4.9.195. Detalhe: [[84 - Rotina Matinal 2026-08-15]].
> [!success] 15/08 08h45 BRT — **Auditoria geral profunda + deploy v4.9.195/v202.10 no ar, validado.** Worker: OPENROUTER-ORFAO1 (perplexity "removido", nivel normal, fim do alerta falso de providers desde 30/07), NOTIFYRL1 (notificar_rotina com rate limit + dedup + escape, probe 403 fail-closed em producao), DEFERREDREC1 (recuperacao dos DEFERRED por token cap com persistencia real, achado da revisao independente), DEDUPCLAIM1, TIMEOUT1, HEALTHWAIT1, TRILHALOG1, HEARTBEATLOG1, RESETPARSE1, PREDRL1, strip conservador. Frontend: LLMXSS1 (12 escapes) + Bearer no modulo vivo + cache-buster v202.10. Infra: rotinas do Claude Desktop versionadas em `routines/claude-desktop/` com drift check, registradores com guarda REGDRIFT1, watch-health com ROTINAGAP1 + HEALTHWATCH2, canonical-test fail-closed. CI Worker Tests verde no push (inclui providers-regressao). Drift zerado nos dois eixos. Rotacao da routine_key agendada para depois das 10:20 (depende do ajuste de permissao Secrets no PAT). Detalhe: [[83 - Auditoria Geral 2026-08-15]].
> [!success] 14/08 04h25 BRT — **Auditoria geral + execução completa das pendências. Worker v4.9.194 e frontend v202.9 no ar.** Worker: CUSTOBRAKE1 (disjuntor loga erro de KV em vez de engolir) + `action=notificar_rotina` (AUTHWEEK1, as 3 rotinas avisam o admin por email quando abortam por auth/limite semanal, probe 403 fail-closed). Frontend: card "Sem alertas" com denominador explícito, postAdmin com Bearer, cache-busting dos módulos ES alinhado em v202.9. Task `VIXRadar-AgendaSemanal` passou para Dom+Qua 22h (CALVAL-V2 regra 9). canonical-test.yml: pendência estava errada, o fix do post-mortem 77 já estava implementado (`15feb31`/`870b29f`). Diretórios estranhos movidos para fora do repo. Única pendência restante: token Pages:Edit (dashboard-only). Health: `ok:true verificador_ok:true` em v4.9.194. Detalhe: [[82 - Auditoria Geral 2026-08-14]] e [[PENDENCIAS.md]].
> [!success] 11/08 19h05 UTC — **Reorganização do working tree: 7 causas raiz corrigidas, 16 commits, push feito.** Repo tinha ~30 entradas de drift (8 modificadas, 22 não rastreadas) acumuladas desde 30/07. Causa raiz principal: `scripts/deploy-pages.ps1` publicava `app/js/**` via wrangler mas o `git add` do próprio script nunca incluía esse caminho (`GITADD-ASSETDIRS1`, segunda vez que essa classe de bug morde o script, primeira foi MODULE-MIG1 em 03/08). Também corrigido: `data/historico` e `data/reconciliacao` paravam de ser commitados manualmente há semanas apesar das rotinas seguirem rodando sozinhas, agora com auto-commit escopado (nunca `git add -A`, falha vira aviso sem derrubar a rotina). Rotina `VIXRadar-Reconciliacao-CVM` (Task Scheduler, seg 08h00 BRT) estava ativa há um mês sem estar documentada, corrigido em `CLAUDE.md` e `routines/README.md`. Novo Gate 4 não-bloqueante no pre-commit avisa arquivo parado na raiz. Diagnóstico do incidente de verificador_ok de 05/08 (3 rascunhos soltos na raiz) consolidado em [[77 - Post-Mortem verificador_ok e Proposta canonical-test.yml 2026-08-11]], com proposta de fix pro `canonical-test.yml` que ainda não foi implementada (item de backlog aberto no Jarvis). **Não verificado ainda:** o caminho real de commit das 2 rotinas automatizadas, só o desvio de DryRun foi testado ao vivo — conferir amanhã se aparece commit de historico pós-20h45 e de reconciliação pós-segunda 08h00. Health no fechamento: `ok:true verificador_ok:true`, drenou sozinho durante a sessão, sem relação com as mudanças. Detalhe completo: `01_PROJETOS/Jarvis/AI_OPERATING_SYSTEM/memoria_de_sessao/2026-08-11_vix-radar-reorganizacao-working-tree.md`.
> [!success] 11/08 20h47 BRT — **Deploy v4.9.190: VERIFSLA2 fecha janela cega do health.** Lookback de `listarFilaVerificacaoPendente` sobe de 2 para 7 dias, alinhando com a janela do sweep. P1 fechado.
> [!success] 12/08 15h49 BRT — **Deploy v4.9.191: ADMINRL-FIX1 encerra 429 do painel admin.** O painel admin disparava 4 POSTs em paralelo com `admin_senha` (tela Hoje) e o gate do RLADMIN2 (v4.9.164) classificava tudo como anonimo com burst de 3/60s. Resultado: 429 "Muitas varreduras em pouco tempo" a cada carregamento (reportado por screenshot 15:13 BRT, confirmado em Observability). Fix: `admin_senha` correta pula o `checkRateLimitV2`, senha errada continua throttled. Testes de regressao no CI (commit `c2b2d5f`, verde). Detalhe: [[79 - Incidente ADMINRL-FIX1 429 painel admin 2026-08-12]].
> [!success] 12/08 16h48 BRT — **Deploy v4.9.192 + v202.7: CALVAL-V2 valida fontes da Agenda de Resultados.** Datas erradas exibidas por dias/meses tinham causa raiz na ausencia total de validacao de fonte: rotina aceitava secundaria como oficial, merge cego sobrescrevia tudo, base estatica `estimado_historico` servia de fallback permanente e o overlay nao mostrava status nenhum. Agora: tier de fonte (RI/CVM/B3/corporativo/secundario, fail-closed), 5 status de validacao computados no Worker, oficial nunca sobrescrita por secundaria divergente (vira DIVERGENTE com registro), gate de publicacao (`confirmado` so com CONFIRMADO_*), auditoria de mudanca de data, alias AXIA Energia -> Eletrobras, confronto diario com publicacao efetiva no CVM, stale com motivos de revalidacao, selos no badge e no overlay. CI verde (9 testes novos + harness local). **Efeito esperado:** datas herdadas da base estatica aparecem como NAO CONFIRMADO ate a rotina revalidar com fonte primaria; a cobertura aparente cai no curto prazo de proposito. `verificador_ok:false` no health do fechamento e backlog pre-existente da fila de verificacao (5 itens >20h enfileirados 11/08 23h33Z), sem relacao com o deploy. Detalhe: [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]].

> [!info] 13/08 14h50 BRT — **Auditoria geral + execução.** Health segue `ok:false` (`verificador_ok:false`), canonical-test vermelho desde 13:41Z. Cascade de IA parado: assinatura no limite semanal (reseta 15/08 08h) e chave paga sem crédito (AUTHWEEK1). Frontend **v202.8 no ar** (XSS do Market Overview fechado). BOM dos .ps1 corrigido e commitado. Worker v4.9.193 commitado, deploy pendente do health verde. frescor-check/scan-emergencia cegos por secret GH divergente (GHWL1). Push bloqueado por credencial (8 commits locais). Zero solicitações pendentes (KV: 33 contas, 0 pendentes). Detalhe: [[81 - Auditoria Geral e incidentes 2026-08-13]].
> [!info] 12/08 17h10 BRT — **Auditoria geral (skill vix-radar-general-audit).** Veredito: sistema solido no nucleo (auth, CORS, rate limit, telemetria, deploy, CI, veracidade da UI), 2 P1 abertos: (1) fila de verificacao acumula porque o dreno diario drena menos do que a noturna enfileira, `verificador_ok:false` desde ~19h33Z e proximo canonical-test (01h15Z) deve acender vermelho e mandar email; (2) working tree com 12 `.ps1` sem BOM com acentos (a reescrita de caminhos para FREQUENTE removeu o BOM), risco de mojibake na proxima execucao PowerShell 5.1, precedente documentado no proprio `run_vixradar_noturno_claude.ps1:15`. Tambem: candidato a XSS armazenado no modulo Market Overview (`app/index.html:4051`, titulo LLM renderizado cru em innerHTML, P2) e tabelas de versao do vault atrasadas (corrigidas nesta auditoria). Detalhes e guardas propostas: [[PENDENCIAS.md]].
> [!warning] 10/08 13h39 UTC — **`canonical-test.yml` falhou (run `31393983894`, commit `151052d`). Causa: `verificador_ok:false` no health, kv/telemetria seguem `true`.** Frontend sem drift (prod=repo=v202.6). Mesmo padrao de fila de verificacao travada ja visto em 07/08 (ver `project_rotinas_nunca_abortam_por_ok_agregado`), o workflow de CI corretamente falha porque seu gate usa o `ok` agregado (diferente da rotina noturna, que ignora esse campo de proposito). Print de um segundo alerta, repo "VIXRADAR" commit `d22823f`, nao corresponde a nada no historico atual, provavelmente notificacao antiga do nome anterior do repo. **Correcao de memoria:** `gh` CLI esta instalado e autenticado localmente (`gh auth status` confirmou), ao contrario do que a nota anterior registrava. Usado para puxar este log direto do Actions.
> [!success] 06/08 02h15 — **Worker ok:true, verificador_ok:true. Incidente de 04-05/08 encerrado.** Fila de verificacao drenada (23 eventos, 14 aprovados, 9 rejeitados, 785k tokens). Guarda estrutural Assert-VixLibFunctions em producao nos 3 scripts, prevenindo reincidencia de call sites orfaos. Worker v4.9.187, commits `ea49418` `06cf4b7` `250e909`.
> [!warning] 05/08 — **Verificador async quebrado silenciosamente por 24h. Fila acumulou 23 eventos.** Causa raiz: commit `2b025b0` removeu `Get-VixModeloEnvInfo` e `-ModeloFixadoNaChamada` sem atualizar os call sites em `run_vixradar_verificacao_async.ps1`. Script morria com `CommandNotFoundException` apos OAuth, sem log de erro. Health so acusou quando a fila passou de 12h.
> [!warning] 04/08 — **Guarda ambiental bloqueou 3 execucoes do verificador async.** `ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro` no environment do processo (injetado pelo runtime do Claude Code) disparava falso-positivo no `Test-VixClaudeAmbienteLimpo`. Commits `b60d21c` e `2b025b0` tentaram corrigir, mas `2b025b0` introduziu o bug que derrubou o dia 05.
## Recuperacao 30/07 a 06/08

### 04-06/08 — Guarda ambiental, call sites orfaos e prevencao estrutural

O incidente teve duas fases. Na primeira (04/08), o `Test-VixClaudeAmbienteLimpo` passou a detectar `ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro` no ambiente do processo. Essa variavel e injetada pelo runtime do Claude Code a partir do `settings.json` e nao afeta `claude -p` (que usa `--model` explicito), mas a guarda nao sabia distinguir. Tres execucoes do verificador async cairam com `exit 6`. Os commits `b60d21c` e `2b025b0` (05/08 02:13) corrigiram a raiz: `Set-VixClaudeAuthEnv` passou a limpar as vars de modelo do processo, e `Test-VixClaudeAmbienteLimpo` deixou de inspecionar `settings.json.model`.

Na segunda fase (05/08), o commit `2b025b0` reverteu parte de `b60d21c` removendo `Get-VixModeloEnvInfo` e o parametro `-ModeloFixadoNaChamada`, mas **nao atualizou os call sites** em `run_vixradar_verificacao_async.ps1`. O script continuou chamando a funcao e o parametro inexistentes. Resultado: 4 execucoes no dia 05 morreram apos OAuth com `CommandNotFoundException`, sem log de erro. A fila acumulou 23 eventos sem ninguem verificar. O health check so acusou na madrugada de 06/08 quando os itens passaram de 12h.

A correcao veio em dois commits. `c4a498a` (depois `06cf4b7` no remote) removeu as chamadas orfas e adicionou preflight de credencial (ROUTINE_API_KEY validada antes do primeiro token de LLM). `3e7cbc6` (depois `250e909` no remote) adicionou `Assert-VixLibFunctions`: uma funcao chamada logo apos o dot-source das libs nos 3 scripts (matinal, noturno, verificacao) que valida que as funcoes esperadas existem. Se uma for removida sem atualizar os call sites, o script aborta com `exit 97` e mensagem diagnostica.

| Metrica | Valor |
|---|---|
| Worker health 06/08 02:15 | ok:true, verificador_ok:true, v4.9.187, HTTP 200, 0,72s |
| Verificador async 06/08 01:02 | Fila 23, aprovados 14, rejeitados 9, 785k tokens, exit 0 |
| Noturno 05/08 18:00 | submit_ok=103, submit_fail=0, 9 criticos (Azul, Cosan, Tupy, CSN Mineracao, Oi, Oncoclinicas, GPA, Raizen, Kora Saude), 558k tokens |
| Verificador async 05/08 (4 runs) | Todos falharam silenciosamente. Log: so INICIO + AUTH, sem processamento. |
| Verificador async 04/08 (3 runs) | Todos falharam com exit 6 (ambiente contaminado: ANTHROPIC_DEFAULT_SONNET_MODEL) |

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
| Worker | **v4.9.208** | `ok:true`: kv/rate_limiter/telemetria true, `admin_email_ok:true`, `sentry_ok:true`, `verificador_ok:true`, providers 2/2, HTTP 200 em 22/08. |
| Frontend | **v202.30** | Carimbo separa última atualização da base e último evento. `version.json` está alinhado com produção. |
| Git | v4.9.208 / v202.30 | `main` sincronizada com `origin/main` após os commits `d0a6331`, `a5d652b` e `307688f`. |

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

## Tasks Scheduler (estado real em 06/08 02h45 BRT)

| Task | Estado | LastRunTime (Scheduler) | Resultado | Proxima | Situacao |
|---|---|---|---|---|---|
| VIXRadar-Noturno | Ready | 05/08 18:00 | 0x0 (sucesso) | 06/08 18:00 | 103 submit, 9 criticos. Operacional. |
| VIXRadar-Matinal | Ready | — | — | 06/08 10:00 | Nao disparou 01/08 e 04/08 (tasks disabled). Proximo 06/08. |
| VIXRadar-Verificacao-Async | Ready | 06/08 01:02 | 0x0 (sucesso) | 06/08 10:20 | Fila drenada manualmente (23 eventos, 14 aprovados). Operacional. |

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
| Providers | 2/2 (Resend + Anthropic); OpenRouter saiu do cascade de analise de credito no v4.9.108 (OPENROUTERVIVO). **Correcao 11/08:** a frase anterior ("probes removidos do health") era imprecisa, `OPENROUTER_API_KEY` continua ativa e em uso para um probe de saldo/saude do Perplexity (`verificarSaldoOpenRouter`, `api/src/worker.js` ~13595-13597 e ~14894-14895), separado do cascade de analise que de fato nao usa mais OpenRouter. **ANTHROPIC_API_KEY ativa (35 chars, confirmada no ambiente), mas scripts apagavam antes do claude -p — corrigido 30/07.** |

## Pendencias ativas (topo)

Ver [[PENDENCIAS.md]]. Incidente 04-06/08 encerrado: fila drenada, 2 novas guardas (ROUTINE_API_KEY preflight + Assert-VixLibFunctions). Fila de pendencias atualizada 06/08 02h45.

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

## Guardas estruturais implementadas (06/08)

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
| Preflight ROUTINE_API_KEY | 8 | Chave de rotina rejeitada antes do 1o token LLM (05/08) | `ea49418` |
| Assert-VixLibFunctions | 97 | Funcao removida de lib sem atualizar call sites (05/08) | `250e909` |

---

*Snapshot gerado em 2026-08-06 02h45 BRT (12 guardas estruturais implementadas). Dias 28/07 a 06/08 documentados. Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*

*Reconciliado em 2026-08-11 21h40 BRT via auditoria geral de engenharia: rodape acima ficava desatualizado havia 5 dias apesar de callouts novos no topo do arquivo (arquivo era editado sem o rodape acompanhar). Health verificado ao vivo neste momento: `ok:true`, `versao:v4.9.190`, `verificador_ok:true`, `admin_email_ok:true`, `sentry_ok:true`, HTTP 200 em 1,79s. Corrigida tambem a linha de OpenRouter acima (Infra), que dizia probe removido do health quando na verdade so saiu do cascade de analise.*
