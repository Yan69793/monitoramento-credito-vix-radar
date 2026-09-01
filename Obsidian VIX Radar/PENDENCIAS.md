---
data: 2026-08-14
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## 01/09 (tarde) — FECHAMENTO DOS 5 RESÍDUOS DA SESSÃO (PREVERIFSEC1 deploy v4.9.232)

> Resumo da sessão de fechamento. Um deploy (`v4.9.232`), suíte 23 arquivos/196 testes, commits `46f809c`/`d25d6c5`/`66b8b74`, portão `ok:true versao:v4.9.232 kv:true telemetria:true sentry_ok:true`. Nenhum dos 5 itens abaixo ficou aberto. Os itens 2, 3 e 4 atualizam as entradas da sessão AVANCOFEED1 (madrugada) abaixo.

1. **PREVERIFSEC1 (Braskem/sec.gov) — CORRIGIDO E DEPLOYADO (v4.9.232).** O pré-verificador descartava o evento CRÍTICO da Braskem de 31/08 (recuperação extrajudicial, Form 6-K da SEC) com `ok:true` mas `n_eventos:0`, porque a SEC devolve 403 a User-Agent genérico e `sec.gov` não era fonte confiável. Fix distinto: `DOMINIOS_FONTE_OFICIAL_DOCUMENTOS` (SEC/CVM/B3/BCB/IN/Anbima) + `_ehFonteConfitavelBloqueada`; aceite só na janela de 30d, sempre `_verif_forcar`. Não é bypass genérico. `validarDatasFontes` ganhou `_fetchOverride` (só teste) para reproduzir o 403 real. Guarda `api/test/pre-verificador-sec-gov.test.mjs` (8 testes, prova de 3 pontas).
2. **Cron da noturna (descrição) — CORRIGIDO.** Frontmatter do SKILL.md: `(diario 18h BRT)` → `(diario 10h BRT)`. `cronExpression="0 10 * * *"` intocado. Estado persistido do agendamento confirmado no `scheduled-tasks.json` (`enabled:true`, `lastRunAt 2026-08-31T13:05:31Z`). Nota de precisão: o arquivo prova o estado PERSISTIDO, não o scheduler vivo — o `nextRunAt` computado pelo processo vivo já foi observado na sessão AVANCOFEED1 via MCP (linha 35 abaixo).
3. **SUBMITOK-ENGANOSO1 — CORRIGIDO (sem deploy de Worker, é doc de skill + guarda).** Ledger `OK|` com 6º campo `SKIP|ANALISADO|DEFERIDO`; resumo analisados/skip/deferidos/submits. Guarda `scripts/check-ledger-noturno.ps1`.
4. **1.439 documentos sem dono — COMPORTAMENTO ESPERADO.** 383 entidades, cobertura 36,1%; nenhuma de maior volume pertence aos 103; 99/99 CNPJs primários dos 103 no cadastro CVM. Guarda `scripts/check-quarentena-emissores.mjs`. Nenhuma correção.
5. **Fonte intradiária — LIMITAÇÃO ACEITA COM CONDIÇÃO DE REABERTURA.** Reabre com fonte confiável aprovada + credencial. Fora dos bugs, movida para roadmap.

---

## 01/09 (madrugada, 2ª sessão) — P2, RESOLVIDO E DEPLOYADO (AVANCOFEED1, v4.9.231) + cron da noturna revertido para 10h

> **Status:** RESOLVIDO E DEPLOYADO. Produção em `v4.9.231`, health `ok:true` medido em 01/09 05:00 UTC. Duas frentes, nenhuma terceira: fonte intradiária e semântica de `submit_ok` ficaram registradas abaixo SEM correção, de propósito.
> **Data da Versão:** 2026-09-01
> **Origem do Registro:** pedido do operador depois do diagnóstico do feed parado em 28/08. Deploys `v4.9.229` → `v4.9.230` → `v4.9.231`. Commits `6e0dda8`/`90e8612`, `70d3dbc`/`df85c52`, `cc22e20`/`caffe43`. Push OK.
> **Condição de Obsolescência:** cai quando o Worker passar do `v4.9.231`, quando o cron da noturna mudar de novo, ou quando entrar uma fonte intradiária que quebre a premissa de cadência semanal da CVM.

**Item 1, cron da noturna: `0 8 * * *` → `0 10 * * *`.** Revertido antes de disparar uma vez sequer. A mudança para 08h entrou no config em 31/08 18:50 e passou a valer no restart de 31/08 23:07, mas o primeiro disparo seria 01/09 08:05 BRT e a reversão foi às 01:44. Medido: `lastRunAt 2026-08-31T13:05:31Z` = 10:05 BRT, cron velho. Motivo: 08h BRT é antes da B3 abrir e antes de CVM e imprensa publicarem o dia, e a noturna é a única passada que cobre os 103 (a matinal cobre top 20 por EWS). Rodar mais cedo não perde fato do dia anterior, mas joga fora as poucas horas de fato do próprio dia. Não tinha relação com o feed parado, e isso foi medido antes de reverter.

**Descoberta operacional que corrige a leitura do INVERSAO-CD1.** A trava "editar o `scheduled-tasks.json` só vale depois de reiniciar o Claude Desktop" continua verdadeira para EDIÇÃO MANUAL do arquivo. Ela não vale para o caminho suportado, `update_scheduled_task` do MCP `scheduled-tasks`, que grava no store e reprograma o scheduler vivo. Prova de duas pontas, sem tocar em processo nenhum: antes `cronExpression:"0 8 * * *"` / `nextRunAt:"2026-09-01T11:05:24Z"`, depois `cronExpression:"0 10 * * *"` / `nextRunAt:"2026-09-01T13:05:24Z"`, arquivo em disco reescrito às 01:44:41 com `0 10 * * *`. `nextRunAt` não existe no arquivo, é computado pelo processo vivo, então o valor ter mudado prova que o app rodando aplicou. Restart não foi feito porque não era necessário e derrubaria a sessão.

**Item 2, AVANCOFEED1.** `checks.avanco_feed` no health diário compara o teto do feed (`MAX(data_evento)`) com o teto da fonte e com a cadência esperada dela, em vez de contar dias sem evento. Seis estados: `saudavel_sem_fato_novo`, `fonte_parada`, `aguardando_varredura`, `pipeline_nao_persistiu`, `sem_evento_datado`, `fonte_indeterminada`. Alertam apenas `pipeline_nao_persistiu` e `sem_evento_datado`.

**Achado que originou.** Entre 28/08 e 01/09 o painel ficou parado em 28/08 com as três rotinas rodando, `submit_ok=103` e todo semáforo verde. O único gate que media isso, `checks.evento_mais_novo`, dispara por "N dias úteis sem evento" (limite 2) e nunca pergunta se a FONTE tinha algo novo para dar. Em 02/09 ele reprovaria esse mesmo estado, que é saudável: o lote semanal publicado no domingo 30/08 só carrega documento até a sexta 28/08 e o próximo sai em 06/09. Alarme que toca sozinho é como alarme que não toca, foi assim que o CVMURL404 passou quatro dias invisível.

**Causa raiz.** A guarda de frescor media o SINTOMA (feed sem andar) sem medir a única coisa que decide se o sintoma é doença (a fonte ter andado). Família conhecida neste repo: EVENTOFRESCOR1 já tinha trocado `updated_at` por idade de evento pelo mesmo motivo, e parou um passo antes.

**Duas correções vieram da medição, não de revisão de código.** A `v4.9.230` nasceu ao validar a `v4.9.229` contra produção: o health devolve `cvm_fonte_last_modified:"2026-08-30"`, data pura, e usar isso cru como instante de chegada do lote vira 00:00Z, o que faria a varredura de domingo 13:05Z contar como "rodou depois do lote" e acusar o pipeline por uma janela que ele não teve. Referência só com data passou a valer fim do dia. A `v4.9.231` nasceu da PRIMEIRA EXECUÇÃO REAL da guarda (run `33472230172`), que reprovou com `teto_fonte=2026-08-31` contra `feed_max=2026-08-28`: número certo, conclusão errada. O acervo inteiro tem 2252 documentos, dos quais 1439 sem dono entre os 103 e alguns com data de referência no futuro, e os dois tipos já são filtrados por `costurarCvmEmEventos`. A guarda estava usando régua diferente da do pipeline que vigia, cobrando o impossível. Passou a decidir pelo teto ELEGÍVEL (com dono e com data já passada), mantendo o teto do acervo no payload como diagnóstico.

**Guarda sistêmica.** `api/test/avanco-feed.test.mjs`, 21 testes, prova de duas pontas: aceita o caso real de 01/09 e o de 02/09 que a régua antiga reprova (a régua antiga está reproduzida dentro do teste e é afirmada como reprovando), e reprova fonte à frente do feed com escrita de estado posterior ao lote. Suíte 22 arquivos / 188 testes. Regra generalizável para auditoria futura: **guarda de pipeline tem que usar exatamente a régua do pipeline que ela vigia, senão cobra o impossível e vira ruído.**

**Prova em produção, duas pontas, saída crua.** Reprova, run `33472230172` (código pré-`v4.9.231`): `##[error]AVANCO DO FEED REPROVADO (pipeline_nao_persistiu)`, exit 1. Aceita, run `33472592026` (`v4.9.231`): `AVANCO_FEED estado=saudavel_sem_fato_novo feed_max=2026-08-28 teto_elegivel=2026-08-28 teto_acervo=2026-08-31 max_data_entrega=2026-08-28 dentro_da_cadencia=true escreveu_apos_lote=true referencia_lote=2026-08-30T23:59:59.000Z proxima_prevista=2026-09-06 docs=2252 elegiveis=813 sem_dono=1439 data_futura=0`, `FRESCOR_OK`, conclusão success.

**Confirmação do diagnóstico do feed.** `teto_elegivel = 2026-08-28 = feed_max`. O feed está no teto do que o pipeline pode publicar hoje.

### Registrado nesta sessão SEM correção, de propósito

**FRENTE ESTRUTURAL, fonte intradiária de Fato Relevante — NÃO implementada.** O lote IPE da CVM é semanal e publica aos domingos com `Data_Entrega` até a sexta anterior, então existe janela cega de até 7 dias por construção da fonte. Medido em 01/09: `cvm_fonte_proxima_prevista=2026-09-06`. Depende de credencial e de validação de cobertura, não de código: `dadosdemercado.com.br` exige Bearer token pago ausente, o Download Múltiplo de Companhias da CVM suporta automação e janela de 24h mas exige credencial própria da CVM que não existe neste ambiente, e o RAD está fora por reCAPTCHA. Decisão do operador. Nada foi solicitado nem gerado nesta sessão. Não foi misturado com o AVANCOFEED1: a guarda mede a distância entre feed e fonte, ela não encurta a cadência da fonte. **FECHADO 01/09 (tarde): LIMITAÇÃO ACEITA COM CONDIÇÃO DE REABERTURA.** Condição de reabertura explícita: existência/aprovação de fonte intradiária confiável + credencial disponível. Não é mais bug desta sessão — foi movida para decisão/roadmap do operador (ver `status/ESTADO.md` e nota 98 apêndice). Nenhum código.

**SEMÂNTICA DE `submit_ok` — registrada, não corrigida.** `submit_ok=103` na linha `FIM:` da noturna conta SUBMISSÃO, não análise, e mascara a cobertura real quando há DEFERIDOS. Medido em 31/08: 50 analisados de verdade, 22 SKIP e 31 DEFERIDOS por cap de sessão (`ORCAMENTO: realizado=681137 ... restante=18863`, `DEFERIDOS: ok=31 falha=0 total=31 motivo=cap de sessao (681137/700000 realizados)`), e mesmo assim a linha final disse `submit_ok=103`. Quem lê o log conclui cobertura total. Mesma família do "verde silencioso", e por isso mesmo merece frente própria em vez de virar apêndice desta. Não tocada aqui. **CORRIGIDO 01/09 (tarde, SUBMITOK-ENGANOSO1):** o ledger `OK|` do SKILL.md da noturna ganhou o 6º campo `SKIP|ANALISADO|DEFERIDO` e o Passo 11 exige `analisados=/skip=/deferidos=/submits_aceitos=`, mantendo `Total do dia N/103`. Regra explícita: submit aceito ≠ emissor analisado; número honesto de análise é o total de `ANALISADO`. Guarda `scripts/check-ledger-noturno.ps1`: formato antigo reprova (exit 1), caso real 31/08 (50/22/31/103) passa (exit 0). Orçamento/cap/rotação intocados.

**OBSERVAÇÃO, não investigada.** 1439 dos 2252 documentos do acervo CVM estão sem dono entre os 103 emissores, cobertura de atribuição 36,1% (bate com `cvm_atribuicao_cobertura_pct` do health público). Apareceu ao construir o teto elegível. Agora fica visível em `checks.avanco_feed.fonte_documentos_sem_dono` e no log do frescor-check, então deixou de ser invisível, mas não foi apurada. **INVESTIGADO 01/09 (tarde): COMPORTAMENTO ESPERADO.** Cruzado contra os 103 por CNPJ primário + família: NENHUMA entidade de maior volume (383 no total, ~1030 dos 1439 docs nas 100 maiores) pertence ao universo; todos os 99 CNPJs primários dos 103 estão no cadastro CVM, então a régua de atribuição por CNPJ captura os 103; único CNPJ de família fora é JBS N.V. (estrangeira); Oi/Nexa/Pan/Votorantim cobertos por família ou aliases. Nenhuma correção de atribuição necessária. Guarda `scripts/check-quarentena-emissores.mjs`. Métrica 36,1% preservada no health (é diagnóstico, não ponto de correção).

---

## 01/09 (madrugada) — P3/P4, RESOLVIDOS E DEPLOYADOS: os 4 achados da auditoria geral de 01/09 fechados no v4.9.228

> **Status:** RESOLVIDO E DEPLOYADO. Produção em `v4.9.228`, health `ok:true` medido em 01/09 04:18 UTC. Nenhuma quinta frente aberta.
> **Origem do Registro:** auditoria geral `/vix-radar-general-audit` de 01/09, nota 98 no vault, quatro achados P3/P4.
> **Condição de Obsolescência:** cai quando `VARREDURA_CRON_AI_ENABLED` voltar a `true` (o disjuntor volta a agir de verdade e a lista `_RAMOS_CRON_COM_LLM` passa a ser o único filtro), ou quando o esquema de hash de senha mudar e `HASH_DUMMY_LOGIN` deixar de custar o mesmo que um hash real.

**P3-2 DISJUNTORHOUSEKEEP1 (era DISJUNTOR1) — corrigido.** Gate do disjuntor movido do despacho do cron para dentro do ramo de varredura, via `_cronDisjuntorBloqueia` com lista fechada `_RAMOS_CRON_COM_LLM = ["varredura_matinal","varredura_batch"]`. Housekeeping não cai mais no teto de custo. Fail-open de leitura preservado (CUSTOBRAKE1). Guarda: `api/test/disjuntor-cron.test.mjs`, 6 testes. Prova reversa medida contra a política antiga: `AssertionError: sync_cvm: expected true to be false`.

**P4-1 LOGINTIMING1 — corrigido.** Todo caminho de falha do `handleLogin` passa a pagar um PBKDF2 (hash real ou `HASH_DUMMY_LOGIN`) e sai pelo mesmo ponto com o mesmo jitter de 80-200ms. Latências mínimas medidas antes: inexistente 124ms, senha_errada 45ms, pendente 10ms, rejeitado 11ms. Depois: 155/140/170/140ms. Mensagem genérica e rate limit de auth intactos. Ramos `pendente` e `rejeitado` entraram na correção porque eram o vazamento mais forte dos quatro, respondendo sem hash e sem atraso. Guarda: `api/test/login-timing.test.mjs`, 3 testes com controle positivo de login válido.

**P3-1 governança da skill — corrigido.** `.claude/skills/vix-radar-general-audit/SKILL.md` e `references/audit-matrix.md` em `v4.9.228` / `v202.35`, data 01/09, medidos ao vivo. Os dois blocos ganharam a nota de que checar a condição de obsolescência é parte do passo 3 da própria auditoria, que foi exatamente o que não aconteceu em 01/09.

**P3-3 CLAUDE.md heartbeats — corrigido.** Watchdog monitora 7, não 6. `verificacao_async` entrou em `expectedAgents` em 18/08 (HEARTBEATVERIF1) e a doc não acompanhou. Os limites de staleness também ficaram registrados, porque não são iguais entre os agentes.

**Causa raiz comum aos quatro.** Nenhum deles nasceu de código errado no dia em que foi escrito. Os quatro são premissas que envelheceram sem que nada comparasse a premissa com o estado atual: o disjuntor herdou "o cron gasta LLM" da era pré-delegação, a skill herdou um número de versão de um deploy que aconteceu depois do snapshot, a doc herdou uma contagem de heartbeats anterior a HEARTBEATVERIF1, e o login herdou um atraso aplicado em um ramo só. Guarda contra a família: teste que trava a política (não só o valor) nos dois primeiros, e condição de obsolescência escrita dentro do artefato nos outros dois.

**Registro histórico do achado original, como escrito em 01/09 antes da correção:**

**Achado (P3-2 da auditoria de 01/09).** `_ehCronComLLM` (`api/src/worker.js:19164`) = `ehMatinal || ehNoturno`, e o disjuntor de custo diário (`verificarDisjuntorDiario`, L19167) aborta os dois. Desde a delegação ao Claude Desktop (`varredura_cron_ai=false`), esses crons não gastam LLM no Worker: a varredura é marcada `pulado/delegado_claude_tiered_v2` e o cron vira housekeeping puro (sync CVM, anomalias, ANBIMA, pipeline preditivo, newsletter, healthcheck diário). Se o teto de custo diário estourar por consumo das rotinas locais, o disjuntor aborta o `sync_cvm` e o `healthcheck_diario`, os dois sinais que watchdog e frescor usam. Risco plausível de silenciar a operação num dia de gasto alto, exatamente quando o operador está longe.

**Causa raiz.** A delegação da varredura ao Claude Desktop não revisou o gate de disjuntor, que herdou a premissa de que matinal/noturno gastam LLM.

**Correção proposta.** Estreitar o gate para os ramos que gastam LLM de verdade (hoje nenhum no Worker, ou só se `varredura_cron_ai=true`). Housekeeping nunca deve cair no disjuntor.

**Guarda sistêmica.** Checagem de auditoria "todo cron sob disjuntor gasta LLM de fato"; ou mover o gate para dentro do ramo de varredura.

---

## 31/08 (tarde) — P1, RESOLVIDO E DEPLOYADO (CVMNOVOSDEAD1 + CNPJVALIDA1): worker v4.9.226 em produção, CVM volta a ser sensor primário

> **Status:** RESOLVIDO DE FATO para o código. `cvm_novos` estava zerado para os 103 emissores todo dia desde 25/08 (SENTINELA1), dois defeitos independentes, os dois corrigidos e deployados. Horário da rotina mudado no config e CONFIRMADO ATIVO pós-restart do Claude Desktop: `vixradar-noturno` carregado com `cronExpression:"0 8 * * *"`, `enabled:true`, próximo disparo 2026-09-01 08h05 BRT (confirmado via `list_scheduled_tasks`). Fonte intradiária oficial: RAD segue tecnicamente bloqueada (reCAPTCHA); o **Download Múltiplo de Companhias** da CVM suporta automação e janela de até 24h mas exige credencial própria da CVM ausente no ambiente — fica como oportunidade futura, não impossibilidade técnica, nada solicitado nem gerado nesta sessão.
> **Data da Versão:** 2026-08-31
> **Origem do Registro:** pedido do operador após a rotina noturna do dia, investigando por que nenhuma promoção pra fila aprofundada veio de documento CVM (os 3 CRÍTICO do dia vieram todos do bypass de imprensa). Deploy via `deploy-worker.ps1 -Version v4.9.226`, commit `9acd814`, push OK. Commit de código+testes+changelog: `3c88bb4`.
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.226. Item de horário RESOLVIDO 31/08 (tarde): restart do Claude Desktop feito, `vixradar-noturno` confirmado carregado com `cronExpression:"0 8 * * *"` e `enabled:true`. Primeiro disparo real no novo horário só ocorre 2026-09-01 08h05 BRT; se escorregar, os vigias existentes (`monitor-tasks.ps1`, watchdogs) cobrem.

**Causa raiz nº1, `_cvmNovosEfetivo` corria atrás de fonte semanal com régua diária.** O corte por data comparava contra o dia civil da ÚLTIMA VARREDURA (diária), e a CVM (`ipe_cia_aberta`) só publica aos domingos, `Data_Entrega` no máximo até a sexta anterior. Medido em produção 31/08: `since`=30/08, máximo `data_entrega`/`data_referencia` do lote inteiro pros 103 = 28/08. `28 < 30` para todo mundo, sempre, estrutural — sob operação diária estável essa comparação nunca teria como devolver `cvm_novos>0` em nenhum dia da semana.

**Causa raiz nº2, independente, contrato de submissão nunca fechado.** `receber_analise` só chamava `marcarCvmVistos` quando o corpo do POST trazia `cvm_ids_analisados`. Nenhuma rotina (noturno nem matinal) jamais mandou esse campo — o plano expõe `cvm_novos_ids`, nome diferente, e ninguém percebeu que precisava ser copiado de um pro outro na submissão. `radar:cvm_vistos` nunca foi escrito para nenhum dos 103 desde que SENTINELA1 existe (25/08). As duas causas juntas mantiveram `cvm_delta_*`/`cvm_overnight_*` como caminho morto: toda promoção real dependia só do bypass de imprensa (FONTELATENCIA1, 21/08), que cobre apenas fato que também virou notícia dentro de 7 dias.

**Fix.** `_cvmNovosEfetivo`: corte por data só no BOOTSTRAP (`vistosIds` vazio, primeira marcação real do emissor); fora disso, identidade de protocolo basta, sem competir com o calendário da fonte. `receber_analise`: servidor deriva `cvm_ids_analisados` sozinho via a mesma função quando o cliente não manda (self-healing, não depende de nenhum `SKILL.md` lembrar do campo certo — corpo explícito, quando vier, continua tendo prioridade). `SKILL.md` do `vixradar-noturno` e `vixradar-matinal` (scheduled tasks locais, fora do repo git) também atualizados pra mandar o campo.

**Achado subordinado, atribuição CNPJ.** Rodado `scripts/check-cnpj-familia.mjs`: nenhum CNPJ plausível fora da família (não detecta Nexa/Votorantim porque nenhum dos dois tem alias de nome cadastrado — o script só propõe candidato por nome). Cruzamento direto contra `cad_cia_aberta.csv` VIVO da CVM (baixado ao vivo, não o snapshot de 25/08 do repo): **Neoenergia** tem CNPJ correto mas faltavam 5 subsidiárias reguladas (Coelba, Celpe, Cosern, Elektro Redes, Afluente Transmissão), todas ATIVO, mesmo domínio de e-mail de RI da holding, adicionadas em `CNPJ_FAMILIA_CVM` — prova em produção, Neoenergia foi de 0 pra 1 documento no plano logo após o deploy. **Banco Pan** tem CNPJ correto mas a Cia Aberta foi CANCELADA em 30/03/2026 (cancelamento voluntário) — zero documento é a empresa saindo do regime, não bug, comentário adicionado no código. **Nexa Resources** e **Banco Votorantim** confirmados sem registro Cia Aberta em NENHUMA forma (ativa ou cancelada), sob nenhum nome testado, no cadastro oficial vivo — já tinham exceção declarada em `scripts/check-emissores-cadastro.mjs` desde 24/08, nada a corrigir. **Camil Alimentos**: CNPJ correto, ATIVO, zero documento em 30 dias é ausência real de protocolo, saudável.

**Achado, fonte intradiária oficial da CVM: bloqueada só por credencial, correção sobre o registro original desta sessão.** Hierarquia pedida foi A) oficial intradiária, B) IPE semanal (reconciliação), C) imprensa (enriquecimento). O registro original desta entrada tratava A como tecnicamente inviável; está corrigido aqui: o **Download Múltiplo de Companhias** da CVM suporta automação e janela de até 24h, mas exige credencial própria da CVM que não existe neste ambiente — bloqueio de credencial ausente, não de impossibilidade técnica, e fica como **oportunidade futura real** quando o operador decidir obter essa credencial (nada solicitado nem gerado nesta sessão). Distinto dos outros dois caminhos avaliados: RAD (`rad.cvm.gov.br`) exige token reCAPTCHA v3/v2 explícito no próprio JS da tela de consulta — bot-detection deliberada, nunca contornar, sob nenhuma circunstância, esse sim sem caminho de automação legítimo. Terceiro `dadosdemercado.com.br` tem API viva e comprovadamente independente do lote semanal (já usado em 24/08 durante o CVMURL404), mas exige `Authorization: Bearer` pago; conferido `wrangler secret list` no Worker (só nomes, nunca valor) e não existe candidato. Portal de dados abertos da CVM só tem UM dataset pra Fato Relevante (`cia_aberta-doc-ipe`), é o mesmo IPE semanal já usado, sem variante mais granular. Por ora B (agora corrigido de verdade) + C seguem como os dois pilares reais; A fica registrada como próximo passo condicionado à credencial.

**Horário, mudado mas não ativo.** `cronExpression` do scheduled task `vixradar-noturno` foi de `0 10 * * *` para `0 8 * * *`, backup do `scheduled-tasks.json` feito antes (`scheduled-tasks.backup-20260831-122707.json`, hash conferido igual ao original antes da edição). Por INVERSAO-CD1 a mudança só passa a valer depois de reiniciar o Claude Desktop — ação do operador, não feita nesta sessão porque derrubaria a própria sessão em andamento (era literalmente a execução agendada do `vixradar-noturno` de hoje). ~~**Fica como item aberto**: confirmar depois do restart que a rotina disparou às 08h00 BRT e não escorregou como aconteceu em 29/08 (task rodou quase 5h atrasada naquele dia, sinal de que o mecanismo depende do app estar ativo no horário do cron, não só do número no JSON).~~
**RESOLVIDO 31/08 (tarde), pós-restart:** `list_scheduled_tasks` confirma `vixradar-noturno` carregado com `cronExpression:"0 8 * * *"`, `enabled:true`, `nextRunAt` 2026-09-01T11:05:24Z (08h05 BRT). `lastRunAt` ainda mostra a execução de hoje às 10h05 BRT, sob o cron anterior ao restart. Config ativa confirmada; o primeiro disparo real no novo horário só acontece amanhã, fora do escopo desta checagem.

**Guarda e prova do deploy (duas pontas, regra 5).**
- Prova reversa do fix, código: 8 testes novos em `api/test/sentinela-pontual.test.mjs`, 3/8 falham contra o código anterior pelo motivo certo (medido, `git stash` do worker.js só, suíte rodada, restaurado).
- Suíte local 153/153 verde (18 arquivos) após o fix.
- 4 guardas locais de CNPJ/cadastro rodadas depois da edição de `CNPJ_FAMILIA_CVM`: `check-alias-coerencia.mjs`, `check-metricas-curadas.mjs`, `check-emissores-cnpj.mjs`, `check-cnpj-familia.mjs`, todas `exit 0`.
- Health em produção pós-deploy: `ok:true versao:v4.9.226 kv:true telemetria:true sentry_ok:true verificador_ok:true admin_email_ok:true cvm_fonte_ok:true providers_configurados:"2/2"`, HTTP 200.
- Smoke read-only pós-deploy via `listar_plano_rotina`: `ok:true total:103`, Neoenergia com 1 documento (era 0 antes do deploy).
- git: local e remoto sincronizados em `9acd814`, working tree limpo, bundle `api/v4.9.226.js` com `WORKER_VERSAO = "v4.9.226"`.

---

## 31/08 (madrugada) — P2, RESOLVIDO E DEPLOYADO (FALLBACKTTL1 + VERIFCACHE-ROUNDTRIP1): worker v4.9.225 em produção, portão validado

> **Status:** RESOLVIDO DE FATO. Deploy v4.9.225 validado em produção na madrugada de 31/08, suíte local 145/145 verde. As entradas de 29/08 e 30/08 (FALLBACKTTL1) e 27/08 (VERIFCACHE-ROUNDTRIP1) abaixo registram as causas e correções; este é o fechamento do ciclo.
> **Data da Versão:** 2026-08-31
> **Origem do Registro:** deploy via `deploy-worker.ps1 -Version v4.9.225`, commit `d88c293`, push OK. Antes do deploy, commits `78a0807` (código + teste round-trip + docs) e `774874f` (changelog WRCGL1).
> **Condição de Obsolescência:** cai quando o Worker passar do v4.9.225 e o frontend não tiver pré-requisito por este deploy (este deploy tocou só o Worker, nenhum frontend).

**O que subiu no v4.9.225.**
- **FALLBACKTTL1:** `fallback:{empresa}` com `expirationTtl: 86400` → `86400*3` (72h) na escrita e corte de idade `idadeHoras > 24` → `> 48` na leitura (`buscarCacheUltimoResorte`), coordenados. O dia 28/08 sem varredura não apaga mais o fallback dos 103 emissores nem os eventos Tier1/FR preservados por ADR-040 (que dependem da mesma chave sobreviver entre escritas). Sem piora para quem recebe fallback velho (piso de confiança já saturava em 0,3 a partir de 24h). VOLTTL1: TTL ≥ 2× o intervalo de escrita.
- **VERIFCACHE-ROUNDTRIP1:** o guard de `aplicarCorrecaoVerificador` aceita o round-trip (`veredicto_original === "CORRIGIR"` além de `veredicto === "CORRIGIR"`). Veredicto `APROVADO_CORRIGIDO` em cache não volta mais como rejeição no reenvio e não retrata o evento do painel; correções são re-aplicadas ao evento fresco de forma idempotente. Teste de duas pontas novo em `api/test/verif-cache-roundtrip.test.mjs` (contra o código pré-fix a ponta ruim falha e a boa passa; com o fix as duas passam).

**Guarda e prova do deploy (duas pontas, regra 5).**
- Health em produção após o deploy: `ok=true, versao=v4.9.225, kv=true, rate_limiter=true, telemetria=true, sentry_ok=true, verificador_ok=true, admin_email_ok=true, cvm_fonte_ok=true, providers_configurados="2/2"`, HTTP 200 nos dois domínios (`api.vixradar.com` e `radar-credito-api.prospects-intel.workers.dev`).
- Validação do próprio script: `versao viva v4.9.225 OK, ok=True kv=true telemetria=true sentry_ok=true cvm_fonte_ok=True`, `DEPLOY OK - producao em v4.9.225, repo e GitHub sincronizados.`
- Suíte local 145/145 verde (18 arquivos) após o deploy, incluindo o teste round-trip.
- git: local e remoto sincronizados em `d88c293`, working tree limpo, bundle `api/v4.9.225.js` com `WORKER_VERSAO = "v4.9.225"`.

**Observação (lacuna registrada, não fechada):** FALLBACKTTL1 não tem teste automatizado para o par `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte` (ver entrada de 30/08). Fica como item futuro; o teste round-trip novo só cobre VERIFCACHE-ROUNDTRIP1.

---

## 30/08 (noite) — P1, ABERTO, AÇÃO SÓ DO OPERADOR (CCDOFFLINE1): causa raiz do buraco de 28/08 medida, Claude Desktop não reabre sozinho depois de reboot

> **Status:** ABERTO. Correção é 1 toggle do Windows, fora do alcance de qualquer agente (mexe em configuração de sistema). Ação do operador.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** investigação pedida em sessão (`/resolver-pendencias` → "ataca os dois"), a partir do item "OBSERVAÇÃO NOVA (fora do plano)" de 30/08 cedo que só constatava o buraco sem causa
> **Condição de Obsolescência:** cai quando o toggle "Iniciar automaticamente" estiver `On` para o Claude em Configurações → Aplicativos → Inicialização, e sobreviver a um reboot real sem intervenção manual

**A máquina nunca dormiu nem desligou em 28/08.** Refuta de saída a hipótese óbvia (sono, como em SENTINELA-DIAPERDIDO1). `Get-WinEvent` no log System mostra uptime contínuo de 28/08 03:02:39 até 29/08 14:34:47 (dois marcos `EventLog 6013` batem exato: 32241s às 12h00 de 28/08 e 118641s às 12h00 de 29/08, ambos derivam do mesmo boot). A máquina ficou ligada o tempo todo em que `noturno` (10h) e `matinal` (18h) deveriam ter disparado em 28/08. Não é causa de hardware nem de energia.

**O gatilho foi Windows Update, medido por correlação direta instalação→reboot.** `Microsoft-Windows-WindowsUpdateClient` no log System: `KB5120998` (Atualização Prévia 26200.9278) e `KB5122385` (.NET Framework Atualização Prévia) instalados com sucesso às 28/08 03:04:09, precedidos por dois ciclos de `Kernel-Power 109/577` (Action: Reboot, Motivo: Kernel API) às 03:01:19 e 03:02:18, cerca de 90s um do outro. Padrão clássico de update que pede dois reboots em sequência.

**A causa estrutural: o app Claude Desktop (pacote MSIX `Claude_1.40609.0.0_x64__pzs8sxrjxfjjc`) não reabre sozinho depois de reboot, e o CCD (o agendador que dispara noturno/matinal/verificação, achado em INVERSAO-CD1) só avalia cron enquanto esse app está de pé.** Evidência de quatro pontas, todas negativas:
1. `AppxManifest.xml` do pacote **declara** a capacidade: `<desktop:StartupTask TaskId="ClaudeStartup" Enabled="false" DisplayName="Claude" />`. O recurso existe, vem desligado.
2. `HKCU`/`HKLM` → `...\CurrentVersion\Run` e `RunOnce`: sem entrada para Claude (tem OneDrive, Notion, Docker Desktop, todos os apps de fundo do operador, exceto este).
3. Pasta Startup (`%APPDATA%\...\Startup` e a de todos os usuários): sem atalho do Claude.
4. `Get-ScheduledTask` varrida inteira por ação: nenhuma task do Windows lança `Claude.exe`.

Resultado: entre 28/08 03:03 e 29/08 ~14:50 BRT (**quase 36 horas**), o CCD não existiu como processo vivo para avaliar cron nenhum. Não é "viu e pulou", é "não estava lá para ver". Isso explica por que `recordedSkips` no `scheduled-tasks.json` não tem **nenhum** registro para `vixradar-noturno` nem `vixradar-matinal` nessa janela, só passou a existir (`reason: global_limit`, 3x) quando o app finalmente reabriu e tentou recuperar tudo de uma vez, 29/08 14:50-14:52 BRT. `matinal` conseguiu rodar nesse catch-up (`lastRunAt` 29/08 14:50:49Z), num sábado às 14h, horário e dia que o cron normal (`0 18 * * 1-5`) nunca produziria sozinho, prova de que foi recuperação atrasada e não disparo normal.

**Os watchdogs de Task Scheduler (`Szuchmacher-RetryVixNoturno`/`Matinal`) funcionaram exatamente como projetados e documentaram a própria impotência.** `retry-vixradar-noturno_20260828.log`: `SEM LOG: ...vixradar-noturno_20260828.log nao existe, rotina nao iniciou. Sem retry (fora do alcance deste watchdog).` Idêntico no de matinal. Eles cobrem "a rotina começou e falhou", não "o app que dispara a rotina nunca abriu". Não é bug neles, é um buraco de cobertura entre camadas que ninguém tinha nomeado até agora.

**Um segundo reboot em 29/08 14:34:52 precede o catch-up em ~15 min, gatilho exato não confirmado com a mesma certeza do primeiro** (a única instalação de update próxima, KB2267602 do Defender, terminou às 14:45:48, **depois** do reboot, então não é a causa direta medida deste; fica registrado como não resolvido, não como suposição).

**Correção.** Configurações do Windows → Aplicativos → Aplicativos instalados → Claude → Opções avançadas → "Iniciar automaticamente" → ligar. Alternativa equivalente: Configurações → Aplicativos → Inicialização → achar "Claude" → `On`. É o mesmo `StartupTask` do manifesto, hoje `Enabled="false"`; o toggle do Windows é o único jeito suportado de ligá-lo (é um app MSIX, não aceita ativação segura por edição direta de registro). Ação de configuração de sistema, fora do alcance de qualquer agente por regra permanente, só o operador liga.

**Causa raiz.** O app que hospeda o agendador das 4 sessões VIX (INVERSAO-CD1) nunca teve plano de sobrevivência a reboot. `Claude VM Service` (serviço Windows separado, Cowork) tem recuperação via SCM e reabriu sozinho nos três boots da janela (`CoworkVMService` "starting" nos Application logs às 03:02:01, 03:02:50 e 14:35:27). O app principal não tem equivalente, e ninguém tinha comparado os dois até esta sessão.

**Guarda sistêmica, proposta e não construída ainda (decisão do operador se quer agora).** Mesmo com o toggle ligado, nenhum vigia atual verifica "o Claude Desktop está de pé" como sinal isolado, só verifica "a rotina de hoje tem log". Um watchdog de Task Scheduler barato, no mesmo padrão de `retry-vixradar.ps1` (`scripts/lib/vixradar-watchdog.ps1`), rodando a cada poucas horas, checando `Get-Process -Name Claude` (WindowsApps) e alertando por email se ausente por mais que uma janela curta, fecharia o buraco de cobertura acima sem depender do toggle nunca falhar. Não implementado nesta sessão porque criar task nova no Scheduler é configuração persistente e pede autorização explícita à parte.

---

## 30/08 (noite) — P2, CORRIGIDO NO CÓDIGO, AGUARDANDO DEPLOY (FALLBACKTTL1): o fix de 1 linha proposto em 29/08 não resolvia o sintoma descrito, faltava a metade que importa

> **Status:** CORRIGIDO em `api/src/worker.js` (2 linhas, não 1), suíte local 143/143 verde, **não deployado**. Candidato a entrar no próximo bump de versão do Worker.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** execução do item FALLBACKTTL1 registrado em 29/08 (noite), leitura completa dos dois lados (escrita E leitura) de `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte` em `api/src/worker.js:15820-15880`
> **Condição de Obsolescência:** cai quando o Worker com este fix estiver deployado em produção e validado

**Correção da correção anterior.** O registro de 29/08 propôs `expirationTtl: 86400 * 3` (1 linha) e chamou de resolvido o padrão. Não é: `buscarCacheUltimoResorte` (`:15862-15871`) tem seu **próprio** corte de idade, `if (idadeHoras > 24) return null;`, calculado a partir de `_fallback_ts` e **independente** do TTL do KV. Alongar só o TTL de armazenamento não muda nada no que é servido ao usuário: o dado continuaria fisicamente vivo no KV por mais tempo, mas a função de leitura recusaria servir qualquer coisa com mais de 24h de qualquer forma, TTL maior ou não. O sintoma que a auditoria de 29/08 queria resolver (fallback inteiro sumindo depois de 1 dia sem varredura) **continuaria acontecendo** com o fix de 1 linha sozinho.

**Fix real, 2 linhas coordenadas:**
- `expirationTtl: 86400` → `86400 * 3` (72h) na escrita (`:15848` antes do comentário, hoje mais abaixo por causa do breadcrumb inserido)
- `idadeHoras > 24` → `idadeHoras > 48` na leitura (mesmo bloco, `buscarCacheUltimoResorte`)

TTL de armazenamento maior que o corte de serviço, de propósito, para sobrar margem física no KV acima do que a lógica aceita servir. Sobrevive a exatamente 1 dia inteiro sem varredura (o que 28/08 provou acontecer, ver CCDOFFLINE1 acima). O piso de confiança (`Math.max(0.3, 1 - idadeHoras * 0.04)`) já saturava em 0,3 a partir de 24h, então nada piora para quem recebe o fallback aos 30h ou 47h, só passa a existir fallback em vez de erro 503 puro quando o único problema foi 1 dia de rotina perdida. Efeito colateral bom: a preservação de eventos Tier1/Fato Relevante por 30 dias entre escritas (ADR-040, `:15822-15842`) também dependia da mesma chave sobreviver entre gravações, e também estava exposta ao mesmo apagão de 1 dia.

**Causa raiz.** A auditoria de 29/08 leu o lado da escrita e a regra geral VOLTTL1 (nascida de um incidente em chave diferente, `cotacoes:volatilidade:v1`, que não tem corte de idade no consumo) e generalizou o padrão sem ler o corpo da função de leitura deste caso específico. Contradiz a própria regra 3 do protocolo de auditoria deste projeto (julgar por comportamento, não por forma) ao propor a correção sem rastrear o consumo até o fim.

**Guarda sistêmica.** Nenhuma automática nova; a suíte de testes deste projeto não tem cobertura de `salvarCacheUltimoResorte`/`buscarCacheUltimoResorte` (confirmado, `grep -rl fallback test/` só acha `briefing-dedup` e `cvm-frescor`, nenhum dos dois testa este par de funções). Lacuna de teste registrada aqui como item futuro, não fechada nesta sessão.

---

## 30/08 (tarde) — P2, ABERTO (PISODIFF1-ESTRUTURAL1): piso EWS pisado em 61 para todo RJ/default, escada de severidade depende de fonte estruturada

> **Status:** ABERTO. Não implementar agora. O card duplo (v4.9.224, score final com piso + `Score sem piso: N` dos sinais reais) é a mitigação vigente.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** auditoria 29/08 (EWSFLOOR1), medição do piso 61 com fixture de produção (Raízen, Oncoclínicas e Oi em 66, o "53,2" da Light era estimativa de mão, valor real 50), decisão do operador 30/08 (delegada: card duplo agora, escada como pendência)
> **Condição de Obsolescência:** cai quando houver fonte estruturada de severidade da RJ e o piso escalonado dentro do CRITICO for implementado

O piso EWS garante score mínimo para emissor com RJ/default ativo, fail-closed nascido de STATELEAK1/RESEARCHDOWN1. A consequência medida: toda empresa com RJ/default ativo cai em 61 exato (ou 66 com o bônus +5 de 3+ sinais de risco), e a diferenciação real de gravidade vive só nos sinais de mercado. Três empresas em situações bem diferentes mostravam nota idêntica no card.

A alternativa estrutural, escada de piso por severidade (ex. 61/70/78 dentro do CRITICO), depende de fonte estruturada de severidade da RJ. Feita à mão repete a classe RESEARCHDOWN1, a tabela `_RJ_FLOOR` já carrega essa dívida (nota 60, `as_of`/`fonte_url` null).

**Ação proposta.** Sub-tags da cascade na geração do evento (`default-consumado`, `rj-homologada`, `re-ativa`) como fonte de severidade, nunca tabela manual sem proveniência. Até lá, o card duplo do v4.9.224 (score final + `Score sem piso`) e o desempate do ranking por `score_calculado` desc diferenciam a gravidade sem tocar na garantia.

---

## 30/08 (manhã) — P3, CORRIGIDO (SYNCDOC-MUDO1): metade do sincronizador de versão não casava nada, e ele não avisava

> **Status:** CORRIGIDO no worktree, sem deploy (mudança só de script e documentação). Validação: prova de duas pontas contra o código pré-correção, `lint-encoding.ps1` RISCO 0, runtime em `powershell.exe` 5.1 e em `pwsh` 7.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** saída real do deploy de v202.34 (`Docs sincronizados: README.md (frontend)`, sem menção a CLAUDE.md) + leitura de `scripts/sync-version-docs.ps1` + `git log -S` em `CLAUDE.md`
> **Condição de Obsolescência:** cai quando o próximo deploy imprimir o inventário completo dos alvos, cada um em um dos três estados (sincronizado, já sincronizado, ausente), sem alvo declarado fora da lista

O `scripts/sync-version-docs.ps1` roda no passo 5.5 do `deploy-worker.ps1` e do `deploy-pages.ps1` e declarava
quatro pontos de sincronia, dois no `README.md` e dois no `CLAUDE.md`. Os dois do `CLAUDE.md` não casavam nada.
Medido: o `CLAUDE.md` não tem nenhuma linha no formato `| Worker | **v4.9.XXX** | ... |` nem
`| Frontend | **vXXX.XX** | ... |` que as regex procuravam, e o deploy de v202.34 imprimiu exatamente
`Docs sincronizados: README.md (frontend)`, sem uma linha sobre o que não casou.

A causa do silêncio é a função `Update-File`, que devolvia `$false` quando o texto não mudava e o chamador
tratava `$false` como "nada a fazer". Só que dois casos muito diferentes produzem texto igual: **arquivo já
sincronizado** e **âncora que não existe mais**. Somados no mesmo `$false`, viram um `Docs sincronizados:` que
lista só o que mudou e cala sobre o resto. É o mesmo padrão de verde silencioso já combatido em MODULE-MIG1 e
ATRIBTEL1. Hoje não gerava dado stale, porque o `CLAUDE.md` não declara versão em lugar nenhum, mas a guarda
estava morta e o sistema não sabia.

**Correção.** Os dois blocos que miravam o `CLAUDE.md` foram aposentados: o `README.md` passa a ser a única
tabela de versão viva do repo. Os quatro alvos restantes viraram declarações nomeadas (nome + arquivo + regex +
substituição) num inventário no topo do script, e a pergunta de cada um deixou de ser "o texto mudou?" e passou
a ser "a âncora existe neste arquivo?", via `[regex]::Matches().Count`. Isso separa os três estados que antes
eram um só: `Docs sincronizados` (mudou), `Docs ja sincronizados, alvo presente e sem mudanca` (idempotente) e
`AVISO: ALVO DE SINCRONIA AUSENTE` em amarelo, nomeando o alvo. Junto veio o encoding fixado: leitura e escrita
por `System.IO.File` com `UTF8Encoding($false)` explícito, porque `Get-Content`/`Set-Content` sem `-Encoding`
mudam de default entre 5.1 (ANSI) e pwsh 7 (UTF-8), e sob 5.1 a seta e os acentos do bloco Fontes Vivas seriam
corrompidos na gravação.

**Causa raiz.** O script nasceu em `b804d21` (17/07/2026) mirando dois arquivos. Oito dias depois, `49471e0`
(25/07/2026, "hardening CLAUDE.md") removeu a tabela de versão do `CLAUDE.md` de propósito, e ninguém atualizou
o script. Trinta e seis dias de deploy com metade do sincronizador apontando para o vazio. A raiz não é a
remoção, que foi uma decisão boa, é o script não ter contrato entre o alvo que ele declara e o alvo que existe:
sem esse contrato, apagar uma linha da doc não tem como avisar quem dependia dela.

**Guarda (prova de duas pontas).** Sandbox isolado, mesma fixture de `README.md` com a linha da tabela
reformatada e o `CACHE_VERSION` deixado intacto de propósito, para provar que a guarda é por alvo e não
tudo ou nada.

Ponta ruim, código **pré-correção** (`git show HEAD:scripts/sync-version-docs.ps1`), com 2 dos 3 alvos de
frontend mortos (tabela do README reformatada + tabela do CLAUDE.md removida):

```
Docs sincronizados: README.md (frontend)
---- EXIT: 0 ----
```

Ponta ruim, código **corrigido**, mesma fixture:

```
Docs ja sincronizados, alvo presente e sem mudanca: README.md :: CACHE_VERSION (bloco Fontes Vivas)

AVISO: ALVO DE SINCRONIA AUSENTE. 1 ponto(s) da doc NAO foram atualizados:
  - README.md :: tabela Versoes em Producao, linha Frontend
  A regex do alvo nao casou nada. Ou a linha mudou de forma, ou saiu do arquivo.
  Conserte a linha OU remova o alvo de scripts/sync-version-docs.ps1.
  Alvo declarado que nunca casa e guarda morta, e guarda morta nao avisa quando a doc mente.
---- EXIT: 0 ----
```

O mesmo caso com `-Strict` termina em `-Strict ligado, saindo com codigo 1.` e `EXIT: 1`.

Ponta boa, `README.md` íntegro, `-Strict`, duas execuções seguidas provando que idempotência não vira ausência:

```
Docs sincronizados: README.md :: CACHE_VERSION (bloco Fontes Vivas), README.md :: tabela Versoes em Producao, linha Frontend
---- EXIT: 0 ----
Docs ja sincronizados, alvo presente e sem mudanca: README.md :: CACHE_VERSION (bloco Fontes Vivas), README.md :: tabela Versoes em Producao, linha Frontend
---- EXIT: 0 ----
```

Arquivos reais, versões de produção, sob `powershell.exe` 5.1, os 4 alvos confirmados presentes e o
`README.md` não foi tocado (`git status` só acusou o próprio script):

```
Docs ja sincronizados, alvo presente e sem mudanca: README.md :: comentario do bundle vivo (bloco Fontes Vivas), README.md :: tabela Versoes em Producao, linha Worker, README.md :: CACHE_VERSION (bloco Fontes Vivas), README.md :: tabela Versoes em Producao, linha Frontend
---- EXIT: 0 ----
```

`lint-encoding.ps1` no arquivo alterado: `RISCO : 0`, `Nenhum arquivo reprovado.`, exit 0. BOM UTF-8
(`EF BB BF`) preservado e CRLF puro, exigidos porque o script tem não-ASCII na regex do bloco Fontes Vivas.

**Decisão de projeto embutida.** No fluxo normal do deploy a guarda **avisa e não aborta**, de propósito: o passo
5.5 roda com produção já publicada e o git ainda não commitado, então abortar ali deixaria produção à frente do
repo, que é exatamente o drift descrito no cabeçalho do `deploy-worker.ps1`. O `exit 1` fica atrás do switch
`-Strict`, para teste e CI. Os `deploy-*.ps1` não passam `-Strict` e não foram alterados.

---

## 30/08 (madrugada) — P1, DEPLOYADO (AGENDA401, v4.9.223): agenda pública de resultados morta por 401 cru

> **Status:** DEPLOYADO no v4.9.223 (`26aba9c`, 30/08 02:51 BRT). Condição de obsolescência cumprida.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** auditoria 93/95 + leitura de `api/src/worker.js:17627-17631` e `:3646-3650` + `api/test/agenda-validacao.test.mjs` + validação em produção
> **Condição de Obsolescência:** caiu em 30/08, o Worker em produção aceita `GET /?op=calendario` sem token devolvendo `ok:true`

O overlay da agenda de resultados abre e exibe "Autenticação necessária." cru para qualquer visitante, e o badge de
próxima divulgação morre em silêncio. Causa: o frontend chama `GET /?op=calendario` sem `Authorization`
(`app/index.html:5034` e `:5206`), o Worker exigia JWT nessa rota (`api/src/worker.js:17627`) e lê token só de header
(`extractToken`, `:3646`), então o visitante anônimo não tem como autenticar. Não vaza PII: o handler (`:17649-17696`)
só lê KV (`agenda:eventos:v1`, `calendario:overrides:v1`) e monta payload público. Coberto pelo rate limit global do request.

**Correção.** Removido `|| op === "calendario"` do grupo que exige JWT (`api/src/worker.js:17627`). Sem mudança de frontend.

**Guarda (prova de duas pontas).** `api/test/agenda-validacao.test.mjs`: caso novo `SELF.fetch(".../?op=calendario", GET)`
sem nenhum header de auth responde 200 com `ok:true` (e o mesmo para `escopo=agenda`), e os casos com JWT seguem verdes.
Rodado: 10/10 verdes, exit 0. Validado em produção 30/08 02:51 BRT: `curl.exe "https://radar-credito-api.prospects-intel.workers.dev/?op=calendario"`
sem token → `ok:true`, `cobertura.total_emissores=103`, `com_calendario=81`; `?op=calendario&escopo=agenda&horizonte=90` → `ok:true`.

---

## 30/08 (madrugada) — P2, CORRIGIDO (RECONCILE-CVM404): reconciliação local ia falhar de novo com o ZIP 2026 fora do ar

> **Status:** CORRIGIDO. Validação: parse PS 5.1, `lint-encoding.ps1` RISCO 0, dry-run exit 0.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** auditoria 93/95 + leitura de `scripts/predictive/reconciliar_ipe_cvm.ps1` + dry-run em `data/reconciliacao/dryrun/reconciliacao_cvm_2026-08-30.json`
> **Condição de Obsolescência:** cai quando a reconciliação de segunda 31/08 completar sem `ERRO FATAL` de fonte

O script baixava o ZIP do IPE 2026 direto de `dados.cvm.gov.br` sem tratar 404 (o catch global vira `ERRO FATAL` + exit 1),
enquanto o Worker já tinha o fallback de catálogo desde o v4.9.209/210. Com o arquivo sumido (23/08, CVMDURA1), segunda
31/08 falharia de novo.

**Correção.** `$NowBrt.Year` no nome do arquivo; try/catch no download; em 404, consulta ao catálogo CKAN da CVM
(`package_show?id=cia_aberta-doc-ipe`, mesmo espelho do `resolverUrlZipPeloCatalogo` do Worker, `worker.js:7090-7105`) e
tentativa da URL anunciada; se o catálogo também não conhecer o ano, exit 1 com mensagem estruturada
`fonte_ausente_no_catalogo`. Checagem de magic PK (`50 4B`) antes do extract, impedindo extrair ZIP velho em cache.

**Causa raiz.** A regra CVMURL404 foi aplicada ao Worker e não alcançou o script local da reconciliação, que é o segundo
consumidor do mesmo arquivo.

**Guarda.** O dry-run roda o branch canônico; o monitor tem grace de 7 dias se o fallback falhar. Observar o log de
segunda 31/08 08h00. Nota: o ZIP 2026 **voltou ao ar** pela CVM em 25/08 (medido: ranged GET HTTP 206, magic PK, Last-Modified
25/08), então o caminho canônico deve bastar; o fallback fica como defesa.

---

## 30/08 (madrugada) — P2, ABERTO (SEXTA-SEM-ROTINA1, observação fora do plano): sexta 28/08 sem log da matinal nem da noturna

> **Status:** ABERTO, observação. Causa ainda não determinada.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** `ls logs/routines/vixradar-{matinal,noturno}_*.log` + saída real do `monitor-tasks.ps1`
> **Condição de Obsolescência:** cai quando a causa da ausência de 28/08 for determinada e houver guarda de cobertura diária

Os logs da matinal e da noturna pulam de 27/08 pra 29/08: não existe `vixradar-matinal_20260828.log` nem
`vixradar-noturno_20260828.log`. As duas rodaram só no sábado 29/08 à tarde (matinal 14:52 20/20, noturno 15:10 103/103),
fora dos horários nominais. O monitor já sinaliza a matinal (`VIXRadar-Matinal (entrega) 9001`, alvo 28/08). A noturna não
aparece no alvo atual porque roda diária e o monitor de domingo apontou pro sábado 29/08 (que rodou). O 28/08 sem varredura
já estava documentado no REPOSIC1 (causa 3 do feed preso); aqui o dado novo é que nem a matinal (Seg-Sex, 18h) rodou na sexta.

**Ação proposta.** Apurar nas sessões agendadas do Claude Desktop (`scheduled-tasks.json` + `main.log` do app) por que o
disparo de sexta não aconteceu, e considerar se a régua do monitor para a noturna precisa de um alvo fixo "dia útil anterior"
mesmo para rotina diária (para o buraco não sumir quando a rotina corre atrasada no dia seguinte).

---

## 29/08 (noite) — P1, REFUTADO em 30/08 (SENTINELA-DIAPERDIDO1): a Sentinela "perdeu a sexta 29/08"

> **Status:** REFUTADO em 30/08 (madrugada) por medição ao vivo. O vigia defensivo foi implementado mesmo assim e já cobre a classe.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** refutação = `Get-ScheduledTaskInfo` + calendário real + `ls logs/routines/`; vigia = `scripts/test-sentinela-watchdog.ps1` (4 pontas) + saída real do `monitor-tasks.ps1`
> **Condição de Obsolescência:** entrada mantida como registro da refutação; o vigia novo (`scripts/lib/vixradar-watchdog.ps1` + ramo `requerApenasLog` no `monitor-tasks.ps1`) cobre a classe "dia útil sem log"

Nenhuma execução em 29/08 (sexta, dia útil): 0 eventos da task no log Operational do Task Scheduler, contra 108 eventos no dia 28/08 (controle positivo do detector) e 1845 eventos de outras tasks registrados hoje no mesmo log. Não existe `vixradar-sentinela_20260829.log`. A task reporta `State Ready`, `LastRunTime 28/08 17:55`, `LastTaskResult 0`, `NextRunTime 31/08 09:25` e `NumberOfMissedRuns 0`, ou seja, tudo verde enquanto o dia inteiro se perdeu.

Mecânica. As duas triggers são semanais Seg-Sex com âncora às 09h25/09h55 e repetição `PT1H por PT8H` com `StopAtDurationEnd`, e `StartWhenAvailable=True`. A máquina dormiu depois das 07h (monitor rodou 07:00:03; o sinal local seguinte é o retry às 13:30:01) e as duas âncoras caíram no sono. A cadeia de repetição pertence à instância da âncora: âncora perdida, cadeia morta. A máquina estava comprovadamente acordada às 13:30 e das 14:35 em diante (reboot às 14:34), com os slots 13:55, 14:25, 15:25 a 17:55 pela frente, e nada disparou. O catch-up do `StartWhenAvailable` não ressuscitou a âncora e o scheduler nem contabilizou miss.

Impacto do dia: a varredura completa (atrasada, 13h30 a 15h10) deferiu 60 emissores da cauda por orçamento, e os slots da tarde que drenariam até 48 desses gatilhos de dívida (teto 8 por execução) não existiram. Não houve fato novo da CVM perdido (próxima publicação prevista 30/08), o que reduz o dano de hoje, não a classe.

**Causa raiz.** Trigger de âncora com repetição é frágil a sono e boot por desenho do Windows, e a Sentinela é a única rotina de produção sem vigia de entrega: o `retry-vixradar.ps1` cobre só noturno/matinal e o `monitor-tasks.ps1` das 07h avalia a entrega de ontem dessas duas. O caso "não rodou nenhuma vez no dia" não tem detector para ela, mesma família do WATCHDOG-NAOINICIOU1 fechado ontem para as irmãs.

**Correção proposta.** Incluir a Sentinela nas rotinas por evidência de entrega do `monitor-tasks.ps1` (dia útil sem `vixradar-sentinela_YYYYMMDD.log` = erro nomeado no sumário e no email) e avaliar segunda âncora de meio-dia (13h25/13h55) para sono matinal não custar o dia inteiro.

**Guarda exigida.** Prova de duas pontas do vigia novo: dia útil sem log reprova nomeando a rotina, dia com log aceita, saída crua colada.

**REFUTAÇÃO (medida em 30/08).** 29/08 é **sábado**, não sexta: 28/08 = sexta, 29/08 = sábado, 30/08 = domingo. A task
roda só Seg-Sex (`DaysOfWeek=62` = 2+4+8+16+32), `LastRun=28/08 17:55`, `NextRun=31/08 09:25`, `NumberOfMissedRuns=0`, e o
log `vixradar-sentinela_20260828.log` existe com 18 linhas `FIM:` (cadência :25/:55 da sexta, correta). A "0 execuções na
sexta 29/08" das auditorias 93/95 vem de chamar sábado de sexta: no sábado a Sentinela corretamente não roda. O próprio
`NumberOfMissedRuns=0` citado como agravante na evidência original era contraprova, não agravante. O monitor das 07h que
enquadrou o caso também errava o alvo se rodado no sábado: `Get-AlvoEntregaRotina` recua para a sexta quando o dia é fim de
semana, então o vigia não repete o falso positivo.

**Vigia defensivo (implementado, fora da necessidade original).** A classe "rotina de produção sem detector de entrega" segue
real, então o detector entrou: `scripts/lib/vixradar-watchdog.ps1` (funções `Get-AlvoEntregaRotina` e `Test-EntregaSentinela`,
dot-source pelo `monitor-tasks.ps1`), ramo `requerApenasLog` na lista `$RotinasVigiadas` (erro nomeado `VIXRadar-Sentinela
(entrega)`, código 9001, entra no estado.json/backlog/email). Prova de duas pontas em `scripts/test-sentinela-watchdog.ps1`:
dia útil sem log reprova nomeando a rotina, log+FIM aceita, log sem FIM reprova, segunda-feira recua pra sexta sem log reprova.
Saída real do monitor: `ROTINA OK: VIXRadar-Sentinela (entrega) | 2026-08-28 execucoes_com_fim=18`.

---

## 29/08 (noite) — P2, CAUSA MEDIDA em 30/08 (AGENDASEM-TRAVA1): AgendaSemanal morta no lote 3 desde 26/08, escalada pelo monitor há 3 dias e sem tratamento

> **Status:** CAUSA MEDIDA e GUARDA ENTREGUE em 30/08 (manhã). O lote 3 está inocente, a máquina reiniciou por baixo da rotina. Segue ABERTO só quanto aos 12 emissores stale não atualizados, que a janela de 30/08 22h deve drenar.
> **Data da Versão:** 2026-08-30
> **Origem do Registro:** registro original = `logs/monitor-tasks/monitor_20260829.log` e `logs/routines/vixradar-agenda-semanal_20260826.log`. Causa = `Get-WinEvent` Kernel-Power na janela 26/08 21h-02h, `Get-ScheduledTask` + `Get-ScheduledTaskInfo` ao vivo, grep de timeout no wrapper
> **Condição de Obsolescência:** cai quando o monitor julgar a AgendaSemanal pela cadência real dela (domingo e quarta) em vez de por dias corridos, e quando a rotina passar a marcar execução interrompida no meio

Em 26/08 22h (quarta, janela regular) a rotina rodou saudável até o meio: preflight ok, OAuth ok, lote 1 (Engie, Energisa, Copel, ISA) e lote 2 (Omega, Rumo, Simpar, Vamos) com 8 OK, e morreu ao iniciar o lote 3 (Santos Brasil, EcoRodovias, JSL, Embraer) às 22:14:44, sem linha `FIM:`, stderr de 0 bytes, exit `0x40010004` no Scheduler. 8 dos 20 emissores stale atualizados, 12 não. O `monitor-tasks.ps1` acusa e escala desde 27/08 (`idade=3d ESCALADO` no log de 29/08), com email diário ao operador, e ninguém fechou o item.

O padrão (morte no `claude -p` com stderr vazio) é o mesmo dos incidentes de 27 a 30/07, cujas causas variaram (settings contaminado, OAuth). A causa desta ocorrência não foi determinada.

**Correção proposta.** Observar a janela natural de domingo 30/08 22h. Se completar, fechar como transitório com o log colado. Se morrer de novo no lote 3, investigar o lote específico (payload/timeout) com o stderr redirecionado por lote, como a matinal já faz.

**Guarda existente.** O monitor já detecta e escala. O que faltou foi o elo monitor → fila de pendências: alerta repetido sem dono vira ruído (HEALTHWATCH3). Esta entrada é o elo.

**CAUSA MEDIDA (30/08 manhã). A máquina reiniciou por baixo da rotina, o lote 3 não tem defeito.** Cronologia crua, log da rotina contra o log de sistema:

```
2026-08-26 22:14:44  Lote agendasem-3: 4 empresa(s) - Santos Brasil, EcoRodovias, JSL, Embraer
2026-08-26 22:16:27  Kernel-Power 109: o gerenciador de energia do kernel iniciou uma transicao de desligamento
2026-08-26 22:16:29  Kernel-Power 577: o sistema esta preparado para uma reinicializacao iniciada pelo sistema Active
2026-08-26 22:16:53  Kernel-Power 172/125: conectividade em espera Disconnected, zona termal reenumerada
```

Um minuto e quarenta e três segundos dentro do lote. `0x40010004` é `DBG_TERMINATE_PROCESS`, processo morto de fora, não exceção e não estouro de orçamento. Descartadas as duas hipóteses de timeout: `ExecutionTimeLimit` da task é `PT4H`, então o Scheduler não matou aos 14 minutos, e o `run_vixradar_agenda_semanal.ps1` não tem nenhuma guarda própria (grep por `timeout`, `TimeoutSec`, `Wait-Process`, `Stop-Process`, `taskkill` não devolve nada). O texto do evento 577 é o do mecanismo de horário ativo do Windows Update.

O conteúdo do lote também não sustenta a hipótese de payload. Santos Brasil, EcoRodovias e JSL rodaram como lote 4 em 23/08 em 4min47 com `trimestres_count=1` cada, e o único item mais pesado do lote de 26/08 é a Embraer com dois trimestres pendentes. Nenhum `OK|` foi emitido porque o lote nem chegou ao fim da primeira empresa.

**A segunda afirmação do título também não se sustenta: não foram 3 dias de falha, foi 1 falha.** `DaysOfWeek=9` = domingo + quarta. A execução de 26/08 foi na quarta, e a janela seguinte é 30/08 (domingo), medido como `NextRunTime=08/30/2026 22:00:00` com `NumberOfMissedRuns=0`. Entre as duas não houve nenhuma oportunidade agendada, logo não houve execução falha nova. O `idade=3d ESCALADO` do monitor é releitura diária do mesmo `LastTaskResult` congelado, não contagem de falhas. Mesmo defeito de leitura do SENTINELA-DIAPERDIDO1 logo acima, e da mesma família do que a memória do projeto já registra: exit code de task mente, a evidência boa é a linha `FIM:` no log.

**Erro de documentação achado junto.** `CLAUDE.md:245` e `routines/README.md:84` declaram "Dom 22h00 BRT", e contradizem o próprio `routines/README.md:109-124`, que documenta domingo **e** quarta como decisão deliberada de 14/08/2026, amarrada à regra 9 do CALVAL-V2 e ao motivo `revalidar_proximo` (trimestre previsto em ≤7 dias sem confirmação precisa de cadência menor que semanal). As duas linhas de resumo foram corrigidas em 30/08. A nota longa já estava certa e não foi tocada.

**Causa raiz, duas somadas.** Primeira, a rotina não tem noção de ter sido interrompida: morre no meio, deixa 8 de 20 emissores atualizados e não grava marca nenhuma disso, então terminação externa (reboot, sono, atualização) fica indistinguível de defeito de código para quem lê depois. Segunda, o monitor julga uma rotina de duas execuções semanais com régua de dias corridos, então uma falha única vira alerta diário que parece agravamento. As duas juntas produziram um item de fila que aponta para o lugar errado, e foi o que quase custou uma sessão de caça a defeito no lote 3.

**Correção proposta.** No wrapper, gravar linha de interrupção quando o processo morre sem `FIM:` (o próprio wrapper não pode, quem detecta é a execução seguinte ao ver log anterior sem `FIM:`). No `monitor-tasks.ps1`, julgar a AgendaSemanal contra a janela agendada dela (`NextRunTime`/`LastRunTime` e `DaysOfWeek`), não contra dias corridos, reaproveitando o desenho do `Get-AlvoEntregaRotina` que já existe em `scripts/lib/vixradar-watchdog.ps1` para a Sentinela.

**Guarda exigida.** Prova de duas pontas: quarta ou domingo sem log com `FIM:` reprova nomeando a rotina, e segunda-feira depois de um domingo bem-sucedido aceita sem escalar. Saída crua colada, linha de resumo não conta.

**Próximo passo imediato.** A janela natural é hoje 30/08 22h. Ler `logs/routines/vixradar-agenda-semanal_20260830.log` e conferir a linha `FIM:` na manhã de 31/08. Sem reboot armado no momento da medição (`RebootPending_CBS`, `RebootRequired_WU` e `PendingFileRename` os três `False`, boot de 29/08 14:35), o que matou a de 26/08 não está engatilhado, o que não impede atualização nova chegar até lá.

**GUARDA ENTREGUE (30/08 manhã).** Uma correção de spec antes do código. O `ESCALADO` foi lido como sendo régua de dias corridos sobre a cadência e não é, é `ageDaysFromFirst`, tempo desde a primeira detecção, e está correto. Mexer nele quebraria o escalonamento de erro genuinamente persistente. O defeito real é mais estreito: a AgendaSemanal era julgada **só** pelo `LastTaskResult` do Scheduler, sem checagem de entrega por log, e `LastTaskResult` velho numa rotina de duas execuções semanais fica visualmente idêntico a rotina falhando todo dia, porque a linha nunca dizia qual era a janela cobrada. Foi esse o vetor da leitura errada.

Três mudanças, nenhuma toca produção nem exige deploy.

1. `scripts/lib/vixradar-watchdog.ps1`: `Get-AlvoEntregaRotina` ganhou `$DiasPermitidos`, um conjunto de dias, porque o eixo "dia útil" não serve para quem entrega no domingo. `$DiasUteis` segue como atalho de Seg-Sex e quem não passa nenhum dos dois não filtra dia. `Test-EntregaSentinela` virou `Test-EntregaPorLog` com `$Prefixo` e `$Rotulo`, já que a checagem "log do dia alvo tem `FIM:`" nunca teve nada de específico da Sentinela. O nome antigo ficou como atalho para não quebrar call site nem prova existente.
2. `scripts/monitor-tasks.ps1`: a AgendaSemanal entrou em `$RotinasVigiadas` com `diasPermitidos = @('Sunday','Wednesday')` e `hora = 22`. Achado de tabela no caminho, o cálculo do alvo estava **duplicado**, uma cópia na lib que a prova exercitava e outra inline no monitor que produção rodava. Guarda que não exercita o código do pipeline não é guarda (mesma classe do `DENOM_COMERC` em `check-emissores-cadastro.mjs`). Agora é a mesma função nos dois lados, que era a intenção declarada no cabeçalho da lib desde o início.
3. `scripts/test-sentinela-watchdog.ps1`: cinco casos novos, os quatro da Sentinela preservados como regressão.

**Prova de duas pontas, saída crua.** Parse 5.1 OK nos três arquivos, `lint-encoding.ps1` com RISCO 0 em 76 `.ps1`.

```
PONTA RUIM OK: 2026-08-18 sem log de execucao - a Sentinela nao chegou a iniciar na janela agendada
PONTA BOA OK: execucoes_com_fim=1
PONTA SEM-FIM OK: 2026-08-18 log existe mas sem linha FIM: - a Sentinela iniciou mas nenhuma execucao chegou ao fim
FIM-DE-SEMANA OK: 2026-08-21 sem log de execucao - a Sentinela nao chegou a iniciar na janela agendada
CADENCIA TERCA OK: alvo=2026-08-23 (Sunday)
CADENCIA SEXTA OK: alvo=2026-08-26 (Wednesday)
AGENDA PONTA RUIM OK: 2026-08-26 log existe mas sem linha FIM: - a AgendaSemanal iniciou mas nenhuma execucao chegou ao fim
AGENDA PONTA BOA OK: execucoes_com_fim=1
AGENDA SHADOW OK: 2026-08-23 log existe mas sem linha FIM: - a AgendaSemanal iniciou mas nenhuma execucao chegou ao fim
VIGIA SENTINELA + AGENDASEMANAL: prova de duas pontas OK
EXIT=0
```

As duas cadências são o caso que faltava. Na terça o alvo recua para o domingo 23/08 e não cobra log da segunda, dia em que a rotina não roda. Na sexta recua para a quarta 26/08 e não cobra a quinta. O `AGENDA SHADOW` cobre o `SHADOW_FIM:` do ROTINACEGA1, que a lookbehind da lib já tratava e nenhuma prova exercitava.

**Prova contra produção, com o script real.** `monitor-tasks.ps1` rodado sem `-SendEmail`, mesma execução que o Scheduler faz às 07h:

```
2026-08-30 07:46:21 ROTINA OK: VIXRadar-Noturno (entrega) | 2026-08-29 submit_ok=103
2026-08-30 07:46:21 ROTINA SEM ENTREGA: VIXRadar-Matinal (entrega) | 2026-08-28 sem log de execucao, a rotina nao chegou a iniciar
2026-08-30 07:46:21 ROTINA OK: VIXRadar-Sentinela (entrega) | 2026-08-28 execucoes_com_fim=18
2026-08-30 07:46:21 ROTINA SEM ENTREGA: VIXRadar-AgendaSemanal (entrega) | 2026-08-26 log existe mas sem linha FIM: - a AgendaSemanal iniciou mas nenhuma execucao chegou ao fim
  VIXRadar-AgendaSemanal (entrega) | exit=9001 (0x2329) idade=4d desde 2026-08-26 ESCALADO | 2026-08-26 (ciclo esperado) | ...\logs\routines\vixradar-agenda-semanal_20260826.log
```

O que mudou na prática é a linha nomear a data da janela cobrada, `2026-08-26`, em vez de deixar o leitor inferir de um `LastTaskResult` sem contexto. A entrada limpa sozinha na segunda 31/08 se a execução de hoje escrever `FIM:`, e não limpa se não escrever. Regressão coberta na mesma saída, as três rotinas antigas saíram idênticas ao conhecido, inclusive a Sentinela com `execucoes_com_fim=18` de 28/08 e a matinal reprovando 28/08, que é o SEXTA-SEM-ROTINA1 aberto.

**Nota sobre `idade=4d` num detector que nasceu hoje.** Não é defeito. `firstDetected` cai no ramo de `monitor-tasks.ps1:751` que deriva a data do campo `lastRun` quando não há estado anterior, comportamento posto de propósito e comentado no código justamente porque a AgendaSemanal já falhava antes de existir `estado.json`. A janela de 26/08 está mesmo sem entrega há 4 dias.

---

## 29/08 (noite) — P2, ABERTO (FALLBACKTTL1): o cache de último recurso expira em 24h e o dia 28/08 sem varredura provou o apagamento

> **Status:** ABERTO. Exige deploy de Worker (candidato a entrar no v4.9.222 junto com o VERIFCACHE-ROUNDTRIP1).
> **Data da Versão:** 2026-08-29
> **Origem do Registro:** auditoria geral 29/08 (noite), leitura de `api/src/worker.js:15817-15862` e varredura dos `expirationTtl: 86400`
> **Condição de Obsolescência:** cai quando o put de `fallback:` tiver TTL >= 2x o intervalo de gravação, com a regra VOLTTL1 citada no código

`salvarCacheUltimoResorte` grava `fallback:{empresa}` com `expirationTtl: 86400` (`api/src/worker.js:15845`) e existe leitura de recuperação (`:15862`). O escritor é a varredura diária. Em 28/08 não houve varredura nenhuma (gap já documentado no WATCHDOG-NAOINICIOU1), então as cópias de 27/08 expiraram ~24h depois e o fallback dos 103 emissores ficou vazio até a varredura de 29/08 ~15h. Agravante: o próprio bloco preserva eventos Tier1/Fato Relevante por 30 dias entre escritas (ADR-040, `:15822-15842`), lógica que depende da chave sobreviver entre escritas; com TTL igual ao intervalo, um único dia sem rotina apaga também os preservados.

A regra já existe: VOLTTL1 (20/08), TTL >= 2x o intervalo de gravação. O fix da época alcançou só `cotacoes:volatilidade:v1` (86400 → 259200). Os demais `expirationTtl: 86400` do Worker foram varridos nesta auditoria e são dedups e tokens de 24h intencionais (reenvio de email admin, `reset:`, `notificar_rotina`, relatório diário), sem violação.

**Correção proposta.** `expirationTtl: 86400 * 3` no put de `fallback:` (1 linha).

**Causa raiz.** A regra VOLTTL1 nasceu de um incidente e foi aplicada só ao caso do incidente, sem varredura dos outros puts alimentados por rotina diária.

**Guarda sistêmica.** Item permanente novo na matriz da skill de auditoria geral: varrer `expirationTtl` de 1 dia e casar cada um com a cadência do escritor (feito nesta sessão, ver `references/audit-matrix.md`).

---

## 29/08 (tarde) — P0, ABERTO (SCANFALLBACK-MORTO1): o fallback de varredura nunca rodou uma vez, e o histórico verde dele é do caminho que não faz nada

> **Status:** CORRIGIDO E NO AR EM MAIN desde 29/08 (auditoria da noite mediu: `git branch -r --contains ab2622f` devolve `origin/main`), pré-check ativo no cron. Falta só a primeira execução real com o gate aberto para fechar. Secret `ANTHROPIC_API_KEY` criado pelo operador em 29/08 e pré-check de secrets adicionado ao workflow (`ab2622f`).
> **Data da Versão:** 2026-08-29
> **Origem do Registro:** auditoria `/vix-radar-general-audit` em 29/08, medida em `gh run list` e `gh secret list` ao vivo
> **Condição de Obsolescência:** cai quando `scan-emergencia.yml` completar uma execução com o gate aberto

O `scan-emergencia.yml` existe para varrer quando a máquina local não varreu. Ele
mede a idade do estado, e só passa do portão se ela passar de 24h. Em 29/08 às
04h16 o portão abriu pela primeira vez na janela observável, `Idade do estado: 30h`,
`prosseguir=true`, e o passo seguinte morreu na hora:

```
##[error]ANTHROPIC_API_KEY ausente nos secrets do repo.
Fallback obrigatorio nao executado.
##[error]Process completed with exit code 1.
```

O secret não existe. `gh secret list` devolve duas linhas, `ADMIN_PASSWORD` e
`ROUTINE_API_KEY`, e mais nada. O `env:` do run confirma, `ROUTINE_API_KEY: ***`
e `ANTHROPIC_API_KEY:` vazio.

**O histórico verde é falso e a mecânica dele é simples.** As ~20 execuções com
`success` em agosto são todas do ramo em que o portão fecha. Em 28/08 07h01 o log
diz `Idade do estado: 9h`, `prosseguir=false`, o passo de scan é pulado por
`if: steps.gate.outputs.prosseguir == 'true'` e o workflow reporta sucesso sem
tocar em nada. Ou seja, o único dia em que o fallback foi de fato acionado é o
único dia em que ele falhou. Taxa de sucesso real: 0 de 1.

**Causa raiz.** O caminho de exceção nunca foi exercitado. O workflow tem dois
ramos e só o ramo inerte roda no dia a dia, então o CI publica verde por 3 semanas
enquanto o ramo que importa está quebrado desde sempre. É a mesma classe do
`EMAILSILENT1` e do `DRIVERMORTO1`, guarda que não roda no caminho que ela existe
para cobrir, com sinal de saúde vindo do outro caminho.

**Correção.** Criar o secret `ANTHROPIC_API_KEY` no repo (ação do operador, valor
nunca passa pelo chat nem pelo transcript).

**Guarda exigida.** Passo de pré-checagem no próprio workflow, antes do portão,
que reprove quando um secret exigido pelo ramo de exceção estiver ausente. Assim a
falta aparece todo dia no verde, não só no dia do incidente. Sem isso, o mesmo
defeito volta na próxima chave que o script passar a exigir.

---

## 29/08 (tarde) — P1, CORRIGIDO (WATCHDOG-NAOINICIOU1): rotina que não começa não tinha alerta nenhum, e o vigia reportava sucesso

> **Status:** CORRIGIDO em 29/08 (`5acbca2`), efetivo no Task Scheduler. Ramo de log inexistente agora emite alerta via `notificar_rotina` e sai 1. Prova de duas pontas medida: dia sem log depois do horário → `EXITCODE=1` com tentativa de alerta; dia com `FIM:` válido → `EXITCODE=0`.
> **Data da Versão:** 2026-08-29
> **Origem do Registro:** auditoria `/vix-radar-general-audit` em 29/08, `ls logs/routines/` e leitura de `scripts/retry-vixradar.ps1`
> **Condição de Obsolescência:** cai quando o ramo "log inexistente" emitir alerta em vez de sair 0

**Em 28/08 não houve varredura.** Nem noturna, nem matinal, nem verificação. Não
existe `vixradar-noturno_20260828.log`, nem `vixradar-matinal_20260828.log`, nem
`vixradar-verificacao-async_20260828.log`. Rodaram só as tasks do Task Scheduler,
agenda-macro, coleta de volatilidade, export e sentinela. Os 103 emissores
passaram o dia sem passada, e o painel não disse nada.

O vigia local viu e desistiu de propósito (`scripts/retry-vixradar.ps1:36`):

```powershell
if (-not (Test-Path $RotLog)) {
    Write-Log "SEM LOG: $RotLog nao existe, rotina nao iniciou. Sem retry (fora do alcance deste watchdog)."
    exit 0
}
```

`exit 0` faz o Task Scheduler marcar sucesso. Aconteceu em 28/08 13h30 (noturna),
28/08 21h30 (matinal) e de novo em 29/08 13h30 (noturna). Somado às tasks nativas
das três rotinas ficarem `Disabled` por desenho anti-duplicata, o caso "não
iniciou" não tem sinal em lugar nenhum do lado local.

**O detector que funcionou foi o `frescor-check.yml`**, que reprovou em 28/08
13h19 e 29/08 08h16 com `INGESTAO PARADA. Evento mais novo e de 2026-08-25, 3 dias
uteis atras (limite 2)`. Só que ele não tem passo de notificação, o workflow tem um
único step, então o alerta existe apenas como falha de Action. E o
`canonical-test` ficou verde o tempo todo, correto por desenho (HEALTHSPLIT1, o
`ok` mede o serviço), o que deixa o semáforo que o operador olha verde durante um
dia inteiro sem varredura.

**Causa raiz.** O vigia foi desenhado para "começou e travou" e o modo de falha
real virou "não começou", que apareceu junto com a migração do agendamento para as
sessões do Claude Desktop (INVERSAO-CD1). App fechado na hora do cron não deixa
rastro, e o vigia trata ausência de log como fora de escopo em vez de como o pior
caso.

**Correção proposta.** No ramo de log inexistente, distinguir "ainda não é hora" de
"passou da hora e não veio". Passado o horário previsto com folga, isso é falha, e
o script deve sair diferente de 0 e emitir alerta pelo mesmo canal do
`watch-vixradar-health.ps1`.

**Guarda exigida.** Prova de duas pontas, o vigia reprova no dia sem log depois do
horário e aceita no dia com `FIM:` válido, com a saída crua colada.

**Adendo 29/08 (noite), auditoria geral.** A única tentativa real de envio do alerta novo falhou. O log `retry-vixradar-noturno_20260829.log` registra às 15:19:06 `AVISO: falha ao alertar rotina faltante: Impossível conectar-se ao servidor remoto`, ou seja, o `exit 1` funcionou mas o email não saiu. O transporte em si está bom: `Invoke-WebRequest` GET em `https://api.vixradar.com/` sob `powershell.exe` 5.1 devolveu 200 nesta auditoria, então a falha foi transitória (provável janela pós-boot, reboot às 14:34). O bloco de alerta é uma tentativa única dentro de `try/catch`. Recomendação: 2 tentativas com pausa curta no bloco de alerta, e considerar entregue só quando um alerta real chegar (prova de entrega, não de tentativa).

---

## 29/08 (noite) — P2, CORRIGIDO (FRESCORNOTIFY1): o frescor-check reprovava e o aviso morria dentro do GitHub

> **Status:** CORRIGIDO E NO AR EM MAIN desde 29/08 (auditoria da noite mediu: `git branch -r --contains a1c5283` devolve `origin/main`), passo ativo no cron. Passo `Notificar queda de frescor` com `if: failure()`, mesma `action=notificar_rotina` do watch de health, dedup do Worker por rotina/dia (NOTIFYRL1), no máximo 1 email por dia. Prova de duas pontas em execução real segue pendente do primeiro gate que abrir.
> **Data da Versão:** 2026-08-29
> **Origem do Registro:** auditoria `/vix-radar-general-audit` em 29/08; o `frescor-check.yml` reprovou em 28/08 e 29/08 (evento mais novo de 25/08) e o passo único do workflow morreu sem canal de aviso
> **Condição de Obsolescência:** cai quando o passo de notificação enviar alerta numa falha real de frescor, com a saída do GitHub colada

O workflow reprovava com `INGESTAO PARADA` e ninguém ficava sabendo, o alerta existia só como falha de Action. Em 28/08 e 29/08 o operador descobriu por leitura manual do log, não por notificação.

**Causa raiz.** O workflow tinha um único step e nenhuma saída. A falha acionável estava lá, mas o aviso não saía do GitHub.

**Correção aplicada.** Passo que roda só em falha (`if: failure()`), re-deriva o detalhe do `admin_health_check` para nomear o campo (EVENTOFRESCOR1/HEALTHWATCH3) e chama `notificar_rotina` com `rotina=frescor-ingestao`. Verificado na sessão: YAML válido e contrato do Worker conferido (POST com chave errada → 403 `Acesso negado.`, a action existe e rejeita chave inválida, nenhum email enviado).

**Guarda exigida.** O `if: failure()` cobre a regressão: se o gate voltar a reprovar, o alerta sai. Prova de duas pontas em execução real fica pendente do primeiro gate que abrir depois do merge em main.

---

## 29/08 — P1, CORRIGIDO (REPOSIC1): dia perdido de varredura re-ancorou o desenvolvimento em fato antigo; nasce a skill de reposição

> **Status:** CORRIGIDO em 29/08. Reposição executada e verificada em produção (Braskem 28/08 CRÍTICO, Oncoclínicas 27/08 CRÍTICO, Multiplan 27/08 ECO, Petrobras 26/08 ECO). Guarda = skill nova `repor-varredura` + script + prompt anti-ancoragem, todos commitados.
> **Data da Versão:** 2026-08-29
> **Origem do Registro:** sessão de investigação do feed preso em 25/08, medição ao vivo via `dados_para_analise`
> **Condição de Obsolescência:** cai quando existir vigia que acuse dia útil sem varredura e a skill de reposição fizer parte do procedimento padrão pós-gap, com prova das duas pontas colada

O feed ficou preso em 25/08. Três causas somadas, medidas: (a) a CVM parou de publicar em 25/08 (ZIP 404, já tratado no CVMURL404); (b) as varreduras de 26 e 27/08 rodaram 103/103 mas ancoram evento pela data do **fato**, e os fatos novos encontrados (Oncoclínicas, Braskem) eram continuação de saga datada em 20 e 24/08, então nenhuma data nova entrou; (c) **28/08 não teve varredura nenhuma** (app do Claude Desktop fechado, WATCHDOG-NAOINICIOU1 nascido do mesmo gap).

A passada de 29/08 re-ancorou o desenvolvimento novo em fato antigo: em vez de caçar fatos datados na janela perdida, reapresentou a narrativa conhecida com a data velha. Esse é o defeito REPOSIC1, a **re-ancoragem**: a varredura voltou a rodar, o enredo avançou, e o feed não andou porque nenhum evento novo com data na janela foi criado.

A reposição foi feita como caçada dirigida com verificação de fonte real. Dois achados da busca mostraram por que a data tem que sair da fonte, nunca do resumo: "Moody's reafirma Petrobras 27/08" (pt.org.br) era artigo de 2015, e "Fitch eleva Petrobras 26/08" era de 2025. O Worker rejeitou a primeira corretamente. O fato real da Petrobras na janela (linha de crédito R$ 2,35 bi à Braskem, 26/08) entrou.

**Causa raiz.** O sistema tinha detector de "rotina não rodou" (nascendo, WATCHDOG-NAOINICIOU1) mas nenhum procedimento de "rotina não rodou, e agora?" A passada seguinte simplesmente continua de onde está, e o gap de dias fica sem fatos datados nele. A detecção sem reposição deixa o buraco permanentemente aberto.

**Correção aplicada.** Skill `repor-varredura` (`.claude/skills/repor-varredura/`): detecta o gap (logs sem `FIM:` + max `data_evento`), monta alvos de crédito datados na janela perdida com verificação de data real na fonte (regra de ouro anti-hallucination, `article:published_time`/`datePublished`/`<time datetime>` no HTML), submete via `receber_analise` pelo script `scripts/repor-varredura.ps1` e confirma que o max `data_evento` avançou. O prompt `scripts/repor-varredura-prompt.md` carrega a regra anti-ancoragem: evento vira do fato, não do enredo, nova decisão na saga vira evento datado na janela, nunca dobra no fato antigo.

**Guarda sistêmica.** A skill é o procedimento padrão pós-gap. Prova das duas pontas na própria reposição: antes, max `data_evento` 25/08; depois, 28/08, com os 4 eventos confirmados em `eventos_historicos`.

---

## 27/08 (manhã) — P2, ABERTO (VERIFCACHE-ROUNDTRIP1): veredicto APROVADO_CORRIGIDO em cache volta como rejeição e retrata o evento do painel

> **Status:** CORRIGIDO NO CÓDIGO EM 31/08, AGUARDANDO DEPLOY. O guard de entrada de `aplicarCorrecaoVerificador` agora aceita o round-trip (`veredicto_original === "CORRIGIR"` além de `veredicto === "CORRIGIR"`), teste de duas pontas novo em `api/test/verif-cache-roundtrip.test.mjs`. Suíte local 145/145 verde. Achado original medido em produção durante a rotina `verificacao-async` das 11h de 27/08. Reparo pontual do caso concreto (Simpar) já feito por reenvio na mesma execução, `resultado.aprovados:1`.
> **Data da Versão:** 2026-08-27
> **Origem do Registro:** rotina `vixradar-verificacao-async-11h`, fila de 20 itens, 10 com `cache_hits`
> **Condição de Obsolescência:** cai quando `confirmar_verificacao` aceitar `APROVADO_CORRIGIDO` como aprovação, com teste das duas pontas

O Worker grava no cache de verificação um veredicto que ele próprio não consegue reler. Quando o verificador devolve `CORRIGIR`, `aplicarCorrecaoVerificador` aplica a correção e **sobrescreve o campo**, `veredicto.veredicto_original = "CORRIGIR"` e `veredicto.veredicto = "APROVADO_CORRIGIDO"` (`api/src/worker.js:12141-12142`). Logo depois, o handler grava esse objeto já mutado no cache, `setCachedVerification(it.id, it.veredicto, env)` (`api/src/worker.js:18727`).

No ciclo seguinte a noturna regenera o mesmo evento, ele volta à fila, e o procedimento da rotina manda reenviar o veredicto em cache literalmente, sem gastar busca. Aí o objeto encontra duas portas fechadas em sequência (`api/src/worker.js:18714`):

```js
var _cvAprovado = it.veredicto.veredicto === "APROVADO" || aplicarCorrecaoVerificador(_cvEvento, it.veredicto);
```

A primeira compara com `"APROVADO"` exato e falha, o valor é `"APROVADO_CORRIGIDO"`. A segunda cai no guard de entrada da função (`api/src/worker.js:12112`), que exige `veredicto.veredicto !== "CORRIGIR" → return false`, condição que o próprio Worker destruiu ao renomear o campo antes de gravar. Resultado: `_cvAprovado = false`, o evento vai para `retratarEventoRejeitado` e some do estado do emissor, com `rejeitados++` e `retratados++`.

**Medido em produção, 27/08.** Item `2026-08-13|simpar|...`, cache com `veredicto:"APROVADO_CORRIGIDO"`, `veredicto_original:"CORRIGIR"`, `correcoes:{"titulo":"Alavancagem cai para 2,8 vezes, menor nivel desde o IPO de 2010"}`. Lote 4 devolveu `aprovados:2, rejeitados:2, retratados:2`, quando só um item do lote (Aegea 08-14) carregava rejeição de mérito. A conta da execução fechou em 17 aprovados e 3 rejeitados, contra 18 e 2 pretendidos. O evento aprovado com correção foi apagado do painel do emissor.

**Causa raiz.** O campo `veredicto` acumula dois papéis, decisão do auditor e histórico do que o Worker fez com ela. Ao gravar o resultado da mutação no mesmo campo que serve de chave de despacho na leitura, o objeto deixa de ser idempotente: escrever e reler não devolve o mesmo estado. O campo `veredicto_original` foi criado justamente para guardar o valor de entrada e nenhum leitor o consulta.

**Correção proposta (não aplicada, exige deploy).** Aceitar `APROVADO_CORRIGIDO` como aprovação na linha 18714, e no guard de `aplicarCorrecaoVerificador` considerar `veredicto.veredicto_original === "CORRIGIR"` além de `veredicto.veredicto === "CORRIGIR"`. A alternativa mais limpa é parar de sobrescrever o campo de decisão e gravar o desfecho num campo próprio.

**Guarda exigida.** Teste de round-trip em `api/test/` que submeta um veredicto `CORRIGIR` com `correcoes` válidas, leia de volta o que ficou no cache e reenvie esse objeto literal, assertando `aprovados:1, rejeitados:0, retratados:0`. Contra o código atual esse teste falha, é a ponta ruim. A ponta boa é o mesmo fluxo com veredicto `APROVADO` puro, que já passa hoje. Sem o teste de reenvio, qualquer evento que passe por correção continua sendo retratado um ciclo depois e ninguém vê, porque a resposta da rotina só devolve contagens agregadas.

---

## 26/08 (tarde) — P2, CORRIGIDO E DEPLOYADO no v4.9.221 (CVMTTL1): TTL de cvm:documentos divergente entre os dois caminhos de sync

> **Status:** CORRIGIDO E DEPLOYADO. v4.9.221 em produção em 26/08, deploy validado (`ok=true`, `kv=true`, `telemetria=true`, `sentry_ok=true`). Constante única `CVM_DOCUMENTOS_TTL_SEG` nos dois call sites.
> **Data da Versão:** 2026-08-26
> **Origem do Registro:** auditoria `/vix-radar-general-audit` em 26/08, confirmada por revisor independente (duas leituras de fonte, health ao vivo)
> **Condição de Obsolescência:** registro histórico de correção; torna a divergir se as duas escritas de `cvm:documentos` voltarem a usar literais diferentes

O fix do CVMURL404 (v4.9.210) subiu o TTL de `cvm:documentos` de 14 para 30 dias **só no caminho automático** (`syncCVMAutomatico`). O POST manual de admin (`handleSyncCVM`) continuou com 14 dias. Com a fonte semanal, 14 dias não cobrem dois ciclos, e uma fonte parada por duas semanas via caminho manual expirava a base no pior momento, que é justamente quando a via de emergência existe.

**Causa raiz:** a mesma política de vida de chave vivia em duas literais, e o fix de 10/08 alcançou só uma das duas. Nenhuma camada comparava as duas escritas da mesma chave.

**Correção:** constante única `CVM_DOCUMENTOS_TTL_SEG` (60×60×24×30) declarada ao lado de `CVM_FONTE_META_KEY`, usada nos dois call sites. A regra VOLTTL1 da matriz (TTL ≥ 2× intervalo de gravação) continua valendo como guarda de auditoria.

**Guarda:** constante compartilhada, o que torna divergência de TTL entre as duas vias uma contradição estrutural, não um número solto.

---

## 26/08 (tarde) — P2, CORRIGIDO E DEPLOYADO no v4.9.221 (ATRIBTEL1): telemetria de atribuição CVM cega por construção

> **Status:** CORRIGIDO E DEPLOYADO. v4.9.221 em produção, elo meta→health verificado ao vivo em 26/08: `cvm_atribuicao_por_cnpj:793`, `quarentena:1333`, `cobertura_pct:37,3`, `ultimo_sync_ok_em:26.ago..2026 15:30:43`.
> **Data da Versão:** 2026-08-26
> **Origem do Registro:** auditoria `/vix-radar-general-audit` em 26/08, confirmada por revisor independente (leitura do `avaliarFrescorCVM` + health ao vivo)
> **Condição de Obsolescência:** registro histórico de correção; cai se `cvm_atribuicao_cobertura_pct` ou `cvm_fonte_ultimo_sync_ok_em` voltarem a ficar nulos com a meta povoada

`avaliarFrescorCVM` nunca copiava `meta.cobertura` nem `meta.descartados_teto` para o `out`, e `out.ultimo_sync_ok_em` só existia no ramo de falha. A meta **tem** os dados: `gravarFonteCVMMeta` grava `cobertura`/`descartados_teto` e, no ramo ok, `ultimo_sync_ok_em = sincronizado_em`. O elo meta→health é que não existia. Medido em produção em 26/08: `cvm_atribuicao_por_cnpj:0`, `por_nome:0`, `quarentena:0`, `cobertura_pct:null`, `ultimo_sync_ok_em:null`, com ingestão e fonte verdes. A guarda do SUBSTRINGDONO1 (os campos `cvm_atribuicao_*`) era cega por construção, e não havia como saber se a ingestão de documentos avançou de verdade.

**Causa raiz:** o writer foi migrado para a meta (v4.9.210/215) e o leitor não acompanhou. A guarda de duas pontas do SUBSTRINGDONO1 validou o lado de atribuição mas nunca o lado de exposição, e o caso bom do teste seeda os dados e não os lê.

**Correção (só no leitor, o writer já grava certo):** `avaliarFrescorCVM` mapeia `meta.cobertura` → `out.cobertura`, `meta.descartados_teto` → `out.descartados_teto` e `out.ultimo_sync_ok_em = meta.ultimo_sync_ok_em || meta.sincronizado_em`. O `_cvmCob` do health já tem fallback defensivo e não muda.

**Guarda:** o caso bom de `cvm-frescor.test.mjs` agora seeda `cobertura {cnpj:500, nome:50, quarentena:5, sem_dono:20}` e `descartados_teto:12` e asserta que o health expõe 500/50/5, `cobertura_pct > 0`, `descartados_teto:12` e `ultimo_sync_ok_em` com data. Contra o código anterior, esses asserts falham. 61/61 testes passam com o fix.

---

## 26/08 (madrugada) — BLOQUEIO EXTERNO (INVERSAO-CD1): scheduler real achado, alteração aplicada, ativação depende do operador reiniciar o app

> **Status:** BLOQUEIO EXTERNO. A alteração de horário foi aplicada no arquivo do scheduler real, mas só entra em vigor quando o operador reiniciar o Claude Desktop (o arquivo é lido apenas na ativação do app, e a sessão que editou roda hospedada por ele, não pode reiniciá-lo)
> **Data da Versão:** 2026-08-26
> **Origem do Registro:** leitura do store CCD (`scheduled-tasks.json`), log do app (`main.log`) e logs das rotinas, cruzados com o Task Scheduler e o Cowork
> **Condição de Obsolescência:** cai quando a alteração estiver ativa (app reiniciado e os horários novos observados no log) ou quando o mecanismo de agendamento do Claude Desktop mudar

### O que era sabido e se mostrou errado

O fechamento de 25/08 registrou "sem superfície programável": buscas em `config.json`, no `Local Storage\leveldb` e no help do CLI não achavam agendamento, e o `RemoteTrigger list` só mostrava os triggers de nuvem. O fato novo que reabriu a auditoria: o Cowork (`mcp__scheduled-tasks`) **não contém** `vixradar-noturno`, `vixradar-matinal` nem `vixradar-verificacao-async`. E o mecanismo que de fato agenda os três não era nenhum dos dois.

### O executor real e a prova

O agendamento dos três vive no **CCD store**: `%APPDATA%\Claude\claude-code-sessions\<accountId>\<deviceId>\scheduled-tasks.json`. É lido pelo app só no initialize e persistido do mapa em memória com guarda de `_initCounter` (verificado no bundle `app.asar`). Quatro provas independentes:

1. `cronExpression` do arquivo bate com os horários observados nas execuções dos dias anteriores.
2. `lastRunAt` do arquivo casa com o `INICIO:` dos logs: matinal `15:08:06Z` → log `12:09` BRT, noturno `21:56:26Z` → log `18:57` BRT, verificação `21:56:26Z` → mesmo horário.
3. `main.log` do app mostra o CCD disparando a sessão com o cron e o campo `missed` (mecanismo de catch-up que explica os atrasos de 12:08/18:56 em vez dos horários exatos).
4. O Cowork responde "Scheduled tasks not initialized" e as tasks nativas do Task Scheduler (`VIXRadar-Matinal`, `VIXRadar-Noturno`, `VIXRadar-Verificacao-Async`) estão `Disabled` de propósito, como guarda anti-duplicata. Os retries (`Szuchmacher-RetryVixNoturno`, `Szuchmacher-RetryVixMatinal`) são outra coisa, são vigias de Task Scheduler.

### Alteração aplicada

Editado `scheduled-tasks.json` em 26/08, com backup `scheduled-tasks.json.bak-20260826` (4.467 bytes):

| Task | Cron antigo | Cron novo | Validação |
|---|---|---|---|
| `vixradar-matinal` | `0 10 * * 1-5` | `0 18 * * 1-5` | `enabled:true`, 18h Seg-Sex |
| `vixradar-noturno` | `0 18 * * *` | `0 10 * * *` | `enabled:true`, 10h diário |
| `vixradar-verificacao-async-11h` | (nova, ver original abaixo) | `0 11 * * *` | `enabled:true`, 11h00 |
| `vixradar-verificacao-async-1845` | (nova) | `45 18 * * *` | `enabled:true`, 18h45 |

O cron cartesiano `0,45 11,18 * * *` também disparava 11h45 e 18h00, horários indesejados. Ele foi substituído por **duas scheduled tasks independentes**, clonando o prompt e a configuração da original (`SKILL.md` e `ROUTINES-CLOUD.md` copiados para pasta própria de cada clone, hash idêntico ao original). Só id e cron diferem. Estado final dispara exatamente 11h00 e 18h45, sem 11h45 nem 18h00. JSON validado com `ConvertFrom-Json`, 6 tasks, IDs únicos, as 4 sessões VIX `enabled:true`. Backup do estado anterior com cartesiano: `scheduled-tasks.json.bak-cartesian-20260826`.

### Ação manual mínima (por isso BLOQUEIO EXTERNO)

Reiniciar o Claude Desktop **antes das 10h BRT de hoje**. O processo do app (`claude.exe` PID 10756) está vivo desde 25/08 18:56 e só lê o arquivo na ativação, então o snapshot em memória ainda é o cron original e o próximo dispatch (matinal às 10h de hoje) grava esse snapshot velho por cima do arquivo. Depois do restart as 4 sessões novas carregam e o próximo `INICIO:` do log confirma. Alternativa: trocar pelo UI de scheduled tasks do app. A sessão que editou roda hospedada pelo app e não pode reiniciá-lo.

### Preservado

`VIXRadar-Matinal`, `VIXRadar-Noturno`, `VIXRadar-Verificacao-Async` continuam `Disabled` no Task Scheduler. Sentinela habilitada. `Szuchmacher-RetryVixNoturno` 13h30 diário e `Szuchmacher-RetryVixMatinal` 21h30 Seg-Sex intactos. Nada de TOKENCHAT1, BRASKEMDETECT1, CURADORIA1, `routine_key`, KV→DO, P2/P3 ou achados laterais foi tocado.

---

## 25/08 (noite) — RESOLVIDO e DEPLOYADO (DEFERGRUDA1): a bandeira de deferido ligava e nunca desligava

> **Status:** RESOLVIDO. Worker v4.9.217 em produção, portão validado
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** achado **rodando** a Sentinela contra produção, não lendo código
> **Condição de Obsolescência:** PARCIAL. Ver o adendo abaixo, quatro emissores não limpam e a rotina Sentinela está `Disabled` por causa disso

O modo pontual devolveu os **mesmos 8 emissores em duas execuções seguidas** (VLI, Embraer, Nexa Resources, Even Construtora, Copel, Neoenergia, CPFL Energia, Comerc Energia), sendo que os quatro primeiros já tinham sido analisados e submetidos com `ok:true` na primeira. A varredura pontual entraria em laço, reanalisando os mesmos oito duas vezes por hora o dia inteiro.

**Causa.** Os cinco ramos de `persistirResultadoCompartilhadoInterno` faziam `if (payload._token_cap_deferred === true) X._token_cap_deferred = true` sem `else`. E os ramos de `sem_eventos` **reaproveitam o objeto anterior** em vez de reconstruí-lo, então a bandeira sobrevivia a qualquer análise real. O DEFERREDREC1-FIX de 15/08 colocou a escrita e não colocou o apagamento.

**O dano é maior que a rotina nova, e é antigo.** Emissor deferido uma vez virava FULL permanente no tiering da noturna, porque `deferred_prioritario` tem precedência sobre quase tudo. Gastava 9 rodadas de busca todo dia e realimentava o próprio deferimento. **Isso explica o backlog de 34.** Liga direto com PASSOCUSTO1: parte do estouro de teto da noturna era esse laço se pagando.

**Fix.** `else delete` nos cinco ramos. A bandeira significa "não foi analisado porque o teto bateu", então análise real tem que apagá-la. Submit de cap-deferred continua marcando normalmente. Guarda com prova das duas pontas, 1 dos 15 testes falha contra o código anterior. Suíte 119/119.

**Lição de método.** Este defeito não apareceu em nenhuma leitura de código nem em nenhum teste unitário. Apareceu na segunda execução real, comparando duas listas de alvos. Rodar duas vezes e comparar a saída é barato e pega classe de bug que revisão não pega.

### ADENDO, RESOLVIDO e DEPLOYADO (DEFERGRUDA2, Worker v4.9.218): a leitura ressuscitava a bandeira que a escrita já tinha apagado

> **Status:** RESOLVIDO. Worker v4.9.218 em produção
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** quatro execuções reais da Sentinela contra produção, mais leitura crua das 3 chaves `radar:estado:*` que a mescla consome
> **Condição de Obsolescência:** ATENDIDA. Cai se `carregarEstadoMultiSemana` mudar de contrato, ou se aparecer outro campo de controle sofrendo o mesmo descarte

**A prova crua, que inocenta o DEFERGRUDA1.** Com o VLI já analisado com `submit_ok`:

```
radar:estado:2026-W35 (corrente) VLI:   eventos=0 sem_eventos=true  _token_cap_deferred=undefined
radar:estado:2026-W34            VLI:   eventos=1 sem_eventos=false _token_cap_deferred=true
radar:estado:2026-W33            VLI:   eventos=0                   _token_cap_deferred=undefined
radar:estado:2026-W35 (corrente) Copel: eventos=1 sem_eventos=false _token_cap_deferred=undefined
radar:estado:2026-W34            Copel: eventos=0                   _token_cap_deferred=undefined
```

Na semana corrente a bandeira do VLI **já estava ausente**. A escrita funcionou. Quem trazia de volta era a leitura.

**Rastro de chaves.** `receber_analise` escreve em **uma** chave, `radar:estado:{semana corrente}`, via `chaveEstadoCompartilhado`. `montarPlanoRotina` lê **três**, com `carregarEstadoMultiSemana(env, 3)`, e mescla da mais velha para a mais nova. Para o VLI: W33 semeia, W34 tem evento e substitui trazendo a bandeira, e W35 chega sem evento e cai no ramo "semana nova sem evento, semana velha com evento", que devolve o objeto da **W34** corrigindo apenas `_last_scanned_at`. Daí o sintoma exato medido, `horas_stale=0,1` com `deferido=true`. A Copel não sofria porque a semana corrente dela tem evento e cai no ramo de dedup, que espalha o registro novo com `{ ...res }`.

**Causa real.** Não era `persistirResultadoCompartilhado`. Era `carregarEstadoMultiSemana` descartando em silêncio qualquer campo de controle gravado na semana nova, sempre que essa semana não tivesse evento.

**Correção, 2 linhas, só no ramo culpado.** `_token_cap_deferred` passa a vir sempre do registro mais recente, gravando se presente e apagando se ausente. É estado de agendamento, não de conteúdo. Os campos de conteúdo continuam vindo da semana velha de propósito, e há teste travando isso.

**Prova em produção, custo zero.** Logo após o deploy, sem nenhuma análise nova, VLI, Embraer, Nexa Resources e Even Construtora sumiram do plano pontual e os candidatos caíram de 33 para 31.

**Observado e não corrigido, de propósito.** `_status` sofre o mesmo descarte nesse ramo: a W35 do VLI diz `INCONCLUSIVO` e o plano exibia vazio. Não mexi porque `_status` alimenta promoção de tier e mudá-lo tem alcance bem maior que o desta pendência.

### ADENDO 2, RESOLVIDO e DEPLOYADO (DEFERGRUDA3, Worker v4.9.219): a pontual fabricava o próprio trabalho

> **Status:** RESOLVIDO. Worker v4.9.219 em produção
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** medido ao **provar** a convergência do DEFERGRUDA2 em vez de assumi-la
> **Condição de Obsolescência:** ATENDIDA. Cai se `_coberturaMin` mudar de forma que a pontual passe a produzir cobertura completa, ou se o ramo `inconclusivo_stale_breakout` do noturno sair

Fechado o DEFERGRUDA2, o backlog de deferidos caiu de 34 para 0 reincidentes, mas a fila pontual não convergia. Medição da fila **completa** (`teto=200`, custo zero) sob v4.9.218: 29 candidatos, sendo **11 deferidos e 18 inconclusivos**. E dos 20 emissores que a Sentinela já tinha analisado com `submit_ok`, **13 voltaram** — nenhum por deferido, todos por inconclusivo.

**Mecânica, e ela é determinística.** A pontual analisa em lote Haiku produzindo cerca de 2 buscas. O tier FULL exige `_coberturaMin = 7` em `persistirResultadoCompartilhadoInterno`. Logo **toda** análise da pontual grava `_status: "INCONCLUSIVO"`. Com `inconclusivo` no gatilho, a rotina reapresentava o próprio trabalho e nunca convergiria, independente do DEFERGRUDA2.

**Correção, 1 linha.** `inconclusivo` sai do filtro do modo pontual. O critério passa a ser o mesmo que já estava escrito para EWS e staleness: gatilho da pontual é **fato novo** (documento da CVM que ninguém olhou) ou **dívida** (análise que o teto de tokens impediu). "Rodou e não concluiu" é qualidade de cobertura e já tem dono, o ramo `inconclusivo_stale_breakout` do plano noturno, que promove a FULL depois de 48h. Há teste travando que esse dono continua funcionando, para o inconclusivo não virar órfão.

**Prova em produção.** Fila pontual completa caiu de 29 para **11, todos `deferido`**, zero inconclusivo. Dos 20 já analisados, **0 reaparecem por qualquer gatilho**.

**Lição, e é a mesma de antes com uma volta a mais.** O DEFERGRUDA2 fechou de verdade e ainda assim a rotina não convergia. Só apareceu porque fui medir a fila **inteira** por composição de gatilho, em vez de olhar a janela de 8 que a rotina consome. Janela pequena esconde laço.

### As três condições exigidas antes de habilitar a Sentinela, provadas

A task foi habilitada em 25/08 23h30, depois de as três passarem. Próxima execução 26/08 09h25.

**1. `submit_ok` limpa deferred em todos os casos.** 31 emissores analisados nas execuções 3 a 7. Zero permanecem deferidos. Cobre os dois caminhos da mescla, o de semana corrente com evento (Copel) e o sem evento (VLI), que era exatamente o que separava quem limpava de quem não limpava.

**2. O plano pontual não reapresenta emissor já concluído.** Medido sobre a fila completa, não sobre a janela de 8: dos 20 analisados até então, 13 reapareciam sob v4.9.218 e **0** reaparecem sob v4.9.219, por gatilho nenhum.

**3. O backlog converge a zero sem CVM nova.** Trajetória medida da fila completa: **34 → 29 → 11 → 3 → 0**. As últimas três execuções bateram a aritmética exata, 11 menos 8 igual a 3, 3 menos 3 igual a 0, sem nenhuma entrada nova. E a execução seguinte fecha o ciclo com custo zero:

```
23:29:53 PORTAO: acervo do Worker inalterado (2026-08-25) e sem backlog. Nada a fazer.
23:29:53 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=sem_novidade
```

Medido, com o Worker já em v4.9.217 nas duas execuções:

| Emissor | `status` antes | Analisado com `ok:true` | Bandeira limpou |
|---|---|---|---|
| Copel, Neoenergia, CPFL Energia, Comerc Energia | vazio | run 3, 22h46 | **sim** |
| Vibra, Compass, Iguá Saneamento, PRIO | `INCONCLUSIVO` | run 4, 22h56 | **sim** |
| VLI, Embraer, Nexa Resources, Even Construtora | vazio | run 3 **e** run 4 | **não** |

Os candidatos saíram de 34 para 33 e travaram. Os quatro últimos foram analisados duas vezes sob o código corrigido, com `submit_ok`, e continuam `deferido=True` com `horas_stale=0,1`. Não é propagação: quatro minutos e meio sem escrita nova e o quadro não mudou.

**Hipótese, não confirmada.** `montarPlanoRotina` lê com `carregarEstadoMultiSemana(env, 3)`, três semanas mescladas, enquanto `persistirResultadoCompartilhado` escreve só na semana corrente. A bandeira pode estar viva num registro de semana anterior que a mescla traz de volta. Família do STATELEAK1. **Isto é hipótese, não medição** — para confirmar, ler o registro cru de VLI em cada uma das 3 chaves de semana.

**Por que a Sentinela ficou desligada.** Com quatro das oito vagas presas e o backlog ligado, a rotina entraria em toda tentativa. Dezesseis execuções por dia a cerca de 70k tokens cada dá mais de um milhão de tokens por dia em trabalho repetido, o que atrapalharia a noturna e a matinal. O gatilho de documento novo da CVM funciona e é perda real ficar sem ele, mas não compensa esse custo. A task está registrada, com os dois gatilhos corretos, só `Disabled`.

**Contra-medida que já existe.** O `pending_streak` da Sentinela alerta no log a partir de 6 execuções seguidas com backlog, então este laço nunca seria silencioso.

---

## 25/08 (noite) — ABERTO P2 (SENTINELA-HANG1): lote pode ficar pendurado esperando rede

> **Status:** ABERTO, com mitigação parcial no ar
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** medido em duas execuções seguidas em 25/08, ambas travaram no segundo lote
> **Condição de Obsolescência:** fecha quando o invocador do `claude -p` tiver timeout próprio por lote, ou quando a causa (provável limite de taxa) for confirmada e tratada

Duas execuções ficaram 20+ minutos no segundo lote, com o processo `claude.exe` vivo e **1,5 segundo de CPU acumulado**, ou seja esperando rede, não trabalhando. Causa provável é limite de taxa da assinatura: a noturna rodou às 19h30 e eu disparei dois runs em quinze minutos.

**Mitigação já no ar.** Teto de relógio de 22 minutos por execução, conferido antes de cada lote. Um lote lento não empurra mais os seguintes, e quem não rodou fica deferido e volta pelo mesmo gatilho. O `ExecutionTimeLimit` de 40 min da task é o fundo de poço, e o mutex é liberado pelo sistema quando o processo morre.

**O que falta.** O teto não interrompe um `claude -p` já disparado, porque o `Invoke-ClaudeBatchSentinela` usa pipeline simples, sem timeout. A noturna tem o mesmo desenho e nunca precisou, mas a Sentinela roda 16 vezes por dia contra 1. Fechar isso exige trocar o pipeline por `System.Diagnostics.Process` com `WaitForExit(ms)`, mudança que merece teste próprio e não foi feita às 23h sem poder exercitar o caminho de timeout.

---

## 25/08 (noite) — RESOLVIDO e DEPLOYADO (SENTINELA-SYNC1, Worker v4.9.220 + script): o SLA passa a contar da publicação

> **Status:** RESOLVIDO
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** implementado e provado ao vivo contra produção
> **Condição de Obsolescência:** cai se `admin_sync_cvm_auto` mudar de contrato, ou se o cofre DPAPI for aposentado

O bloqueio anterior era de credencial, não de arquitetura: `admin_sync_cvm_auto` pede `admin_senha` e a rotina só tinha `ROUTINE_API_KEY`. **A senha admin já tinha um caminho seguro estabelecido nesta máquina** e eu não tinha olhado: cofre DPAPI `CurrentUser` em `api/.admin_credencial.dat`, lido por `api/Get-VixAdminCredential.ps1`, já usado por `upload_volatilidade_kv.ps1`, `monitor-tasks.ps1`, `watch-vixradar-health.ps1` e outros três. Reusar isso não cria segredo novo nem arquitetura paralela.

Agora, quando o `HEAD` acusa `Last-Modified` novo, a Sentinela manda o Worker reingerir na hora. **O SLA conta da publicação na CVM até a análise sair.**

Duas condições de disparo, e a segunda existe porque a primeira é cega a republicação no mesmo dia: o zip está à frente do que o Worker ingeriu, **ou** o `Last-Modified` mudou desde a última vez que a rotina agiu. `zip_last_modified` só avança no estado quando o sync volta `ok`, então falha não consome o gatilho.

**Degradação explícita, nunca aborto.** Sem cofre, a rotina registra o atraso medido e segue com o acervo atual, que é o comportamento anterior. Perder a sincronização não pode custar a varredura.

Prova ao vivo, com o estado forçado como uma publicação nova faria:

```
23:59:26 FONTE: zip da CVM publicado em Tue, 25 Aug 2026 10:58:47 GMT (ha 961 min). Worker ingeriu ate 2026-08-25. Sincronizando.
23:59:31 SYNC: CVM reingerida sob demanda. documentos=2126 empresas=506 last_modified=2026-08-25
23:59:31 PORTAO: entrando por acervo_novo.
23:59:54 PLANO: candidatos=0 selecionados=0 excedente=0 worker=v4.9.220
```

Detecta, sincroniza, planeja. Cinco segundos entre detectar e ingerir, contra as até 4h32 de espera pelo cron que a medição de 25/08 tinha exposto.

---

## 25/08 (noite) — RESOLVIDO (SENTINELA-HANG1): timeout real, com morte da árvore de processos

> **Status:** RESOLVIDO
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** medido em duas execuções travadas em 25/08, corrigido e provado com árvore de processos sintética
> **Condição de Obsolescência:** cai se o invocador voltar a usar pipeline sem timeout

O desenho antigo era `Get-Content | claude -p`, pipeline sem teto nenhum. Medido: dois lotes ficaram 20+ minutos com o processo vivo e ~1,5 segundo de CPU acumulado, esperando rede. O lote só morreria no `ExecutionTimeLimit` de 40 min da task, com o mutex preso até lá.

Agora `Start-Process` com os três fluxos redirecionados para **arquivo**, o que resolve duas coisas de uma vez. Dá o objeto de processo para `WaitForExit(ms)`, e elimina o deadlock clássico de pipe, onde o buffer de `stderr` enche, o filho bloqueia escrevendo e o pai bloqueia lendo `stdout`. Com arquivo, quem escreve é o sistema.

O teto por lote é o que sobra do teto da execução, com piso de 4 minutos para não nascer expirado. No estouro, `taskkill /T /F` mata a **árvore**: matar só o pai deixaria o `node` filho vivo, porque `claude.exe` é lançador e o trabalho real está no filho.

**Sem re-disparo imediato, de propósito.** Lote que estourou o relógio estoura de novo na sequência e gastaria o teto duas vezes. Quem reexecuta é o backlog, na próxima janela, com os emissores intactos e nada marcado em `cvm_vistos`.

Prova com árvore real, mesmo mecanismo do código:

```
pai PID=2964  filho PID=28796
ANTES  -> pai vivo=True  filho vivo=True
WaitForExit(3000ms) devolveu False   (False = estourou o teto)
DEPOIS -> pai vivo=False  filho vivo=False
```

---

## 25/08 (noite) — RESOLVIDO e DEPLOYADO (STATUSGRUDA1, Worker v4.9.220): `_status` seguia o mesmo descarte do deferido

> **Status:** RESOLVIDO
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** observado durante o DEFERGRUDA2 e deixado em aberto de propósito; fechado agora com a mesma regra conceitual
> **Condição de Obsolescência:** cai se `carregarEstadoMultiSemana` mudar de contrato

Mesmo ramo, mesmo descarte, outro campo. `_status` descreve a **última varredura**, "concluiu" ou "não concluiu", não o acervo histórico de eventos, então a semana velha não pode responder por ele. Medido junto com o DEFERGRUDA2: a W35 do VLI dizia `INCONCLUSIVO` e o plano exibia vazio.

O dano concreto: o `inconclusivo_stale_breakout` do plano noturno existe justamente para quebrar loop de cobertura incompleta, e ficava cego para esses emissores.

`_motivo` viaja junto porque só faz sentido ao lado do `_status` que o gerou. Deixar um explicando o outro de outra semana seria pior que apagar. Conteúdo (eventos, memos, `cobertura_nota`) continua vindo da semana velha, e há teste travando exatamente isso, para a correção não virar perda de histórico.

Guardas: 3 testes novos, os 3 falham contra o código anterior.

---

## 25/08 (noite) — BLOQUEIO EXTERNO P1 (INVERSAO-CD1): as três sessões do Claude Desktop ainda estão nos horários antigos

> **Status:** BLOQUEIO EXTERNO. Não existe superfície programável. Uma ação do operador, na interface do Claude Desktop
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** três provas independentes, abaixo
> **Condição de Obsolescência:** fecha quando o log do dia seguinte mostrar `INICIO` da varredura completa perto das 10h e `INICIO` do top 15 perto das 18h

**As três provas de que não há caminho por código.**

1. **Não está em disco.** As chaves de topo de `%APPDATA%\Claude\config.json` são 17 e nenhuma é de agendamento (`updaterLastSeenVersion`, `first_launch_at`, `locale`, `userThemeMode`, `oauth:tokenCache`, e assim por diante). Busca por `schedule|cron|vixradar|routine` em `Local Storage\leveldb`: **zero ocorrências**. `IndexedDB` vazio.
2. **Não está no CLI.** A lista completa de subcomandos do `claude` é `agents`, `auth`, `auto-mode`, `doctor`, `gateway`, `import`, `install`, `mcp`, `plugin`, `project`, `setup-token`, `ultrareview`. Busca por `schedul|cron|routine` no help inteiro: **ausente**.
3. **Não está na API de triggers.** `RemoteTrigger list` devolve o conjunto completo da conta (`has_more:false`). Só existem **2** triggers VIX habilitados, `VIX Radar — Verificação Async Remote` (`0 5,17 * * *`) e `VIX Radar — frescor diário` (`0 2 * * *`). **Nenhum** dos três agendamentos do Desktop aparece.

Migrar as três para `RemoteTrigger` resolveria por código, e foi descartado de propósito: trocaria o substrato de execução (nuvem em vez da máquina local com o Claude CLI), que é arquitetura paralela e escopo novo.

**Ação manual mínima exata**, três alterações na interface do Claude Desktop:

| Sessão | De | Para |
|---|---|---|
| `vixradar-noturno` (varredura completa dos 103) | 18h00 diário | **10h00 diário** |
| `vixradar-matinal` (top 15) | 10h00 Seg-Sex | **18h00 Seg-Sex** |
| `vixradar-verificacao-async` | 10h20, uma sessão | **11h00 e 18h45, duas sessões** |

Apagar o agendamento velho antes de criar o novo. Deixar os dois armados dispara a rotina duas vezes no mesmo dia.

Horários a colocar: `vixradar-noturno` (varredura completa dos 103) **10h00 diário**, `vixradar-matinal` (top 15) **18h00 Seg-Sex**, `vixradar-verificacao-async` em **duas** sessões, **11h00 e 18h45**.

**Apagar o agendamento velho antes de criar o novo.** Deixar os dois armados dispara a rotina duas vezes no mesmo dia.

**A segunda sessão de verificação não é enfeite.** Sem ela, tudo que a passada das 18h enfileira fica preso até o dia seguinte. A task desabilitada guarda dois triggers (10h20 e 18h20), o que indica que a cobertura dupla já foi o desenho original e se perdeu.

**O que já foi feito e não depende de você.** Os dois vigias de retry trocaram de horário: `Szuchmacher-RetryVixNoturno` para diário 13h30 e `Szuchmacher-RetryVixMatinal` para Seg-Sex 21h30. **Não há janela de risco entre uma coisa e outra**, porque `scripts/retry-vixradar.ps1:36-39` sai sem relançar quando o log do dia não existe. O que existe no intervalo é perda de cobertura, não relançamento à toa: enquanto os horários novos não entrarem, a varredura completa fica sem vigia.

---

## 25/08 (noite) — ABERTO P2 (SENTINELA-SYNC1): a Sentinela não alcança o trecho entre a CVM publicar e o Worker ingerir

> **Status:** ABERTO. Decisão do operador, exige mudança no Worker
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** medido em 25/08, `Last-Modified` do zip da CVM em `Tue, 25 Aug 2026 10:58:47 GMT` (07h58 BRT) contra crons do Worker às 12h30 e 18h30
> **Condição de Obsolescência:** fecha quando existir uma ação de sincronização da CVM autenticada por `ROUTINE_API_KEY`, ou quando a ingestão deixar de depender dos crons

A rotina Sentinela promete latência de até uma hora entre o **Worker ingerir** um documento e a análise sair. Ela **não** cobre o trecho anterior. Medido: a CVM republicou o arquivo às 07h58 e o Worker só ingeriu às 12h30. São 4h32 de atraso estrutural, todo dia, no sinal mais forte que o sistema tem, com todo semáforo verde.

**Por que não foi resolvido agora.** `admin_sync_cvm_auto` e `sync_cvm` exigem `admin_senha`, não `routine_key`. Dar a senha de admin a uma rotina agendada contraria o CHAVEESCOPO1, que existe justamente para credencial de rotina ter escopo mínimo. Criar uma ação nova com escopo de rotina é mudança de arquitetura e não foi improvisada dentro desta entrega.

A Sentinela faz `HEAD` no zip a cada execução e registra no log quando o arquivo está à frente do que o Worker ingeriu. Em duas semanas isso dá a distribuição real do atraso, e a decisão de criar a ação nasce de dado em vez de palpite.

---

## 25/08 (noite) — ABERTO P2 (DEFERIDO-BACKLOG1): 34 emissores parados na fila de deferidos

> **Status:** ABERTO. Observação, com mitigação parcial já no ar
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** `listar_plano_rotina modo=pontual` contra produção v4.9.216 devolveu `candidatos=34`, todos com motivo `deferred_prioritario`
> **Condição de Obsolescência:** fecha quando o campo `pontual_candidatos` ficar estável perto de zero por uma semana

Emissor deferido por teto de tokens marca `_token_cap_deferred` e deveria entrar prioritário na rotina seguinte. Na prática o dia seguinte defere de novo, então o backlog não drenava.

A Sentinela drena 8 por execução, então em tese ele some em poucos dias. Mas o número inicial sugere que o teto de 700k da noturna está apertado para 103 emissores, e isso é decisão de orçamento, não de código. Liga com PASSOCUSTO1.

---

## 25/08 (noite) — RESOLVIDO e DEPLOYADO (SENTINELA1): documento novo era detectado por data, e a data errada

> **Status:** RESOLVIDO. Worker v4.9.216 em produção desde 25/08 22h BRT, portão validado
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** achado ao preparar a inversão de horários; cada defeito medido contra produção ou contra o código pré-correção
> **Condição de Obsolescência:** ATENDIDA. Resta observar a primeira execução da Sentinela com gatilho real da CVM, quando `cvm_marcados` deixa de ser 0

**Defeito 1, o principal.** `_cvmNovosDesde` comparava `YYYY-MM-DD`, então documento entregue no **mesmo dia civil** de uma varredura nunca contava como novo. Isso já mordia o top 15 hoje, que é analisado duas vezes por dia: documento que entra pela manhã não promovia o emissor a FULL na passada da noite. Não cegava o painel, porque os documentos dos 30 dias seguem indo ao modelo em `cvm_documentos`, mas estragava a decisão de analisar raso ou fundo. E para a varredura pontual seria fatal, ela nunca dispararia.

Agora "novo" é protocolo da CVM ausente de `radar:cvm_vistos:{empresa}`, com `_cvmChaveDoc` como fallback quando o link não traz `numProtocolo`. O corte por data continua, só que estrito, então o delta em relação ao comportamento anterior é apenas "documentos entregues no dia da última varredura", tipicamente zero ou um por emissor. Sem pico de custo.

**Defeito 2, RELOGIO3H1 pela segunda vez.** `_last_scanned_at` é instante UTC e `data_entrega` é dia civil BRT. Cortar os 10 primeiros caracteres do instante compara data UTC contra data BRT, e entre 21h e meia-noite a data UTC já virou: documento entregue hoje aparecia como anterior a uma varredura de minutos atrás. Achado ao vivo, o teste falhou às 22h12 exatamente por isso. `_diaCivilBRT` normaliza os dois lados. **É a mesma família do bug de 24/08**, e reaparecer em outro ponto do arquivo diz que a distinção instante x dia civil merece regra, não correção pontual.

**Defeito 3, que a inversão criaria.** O ramo matinal usava janela fixa de 16h para detectar documento da madrugada. Com a matinal às 18h, a conta dá 02h do **mesmo** dia e, como a comparação era por data, `cvmOvernight` ficaria permanentemente vazio. O gatilho morreria calado. Passou a usar `cvmNovos`, que não depende do horário da execução.

**Marcação só após entrega.** `cvm_vistos` é escrito no `receber_analise` bem-sucedido, depois de `persistirResultadoCompartilhado`. Ler o plano não marca nada. Execução que morre no meio, estoura teto ou toma submit recusado deixa o gatilho intacto. Marcar na leitura perderia o evento calado, que é a família de EMAILSILENT1 e CVMURL404. União de conjunto, então reentrega é idempotente.

**Modo pontual.** Recorte do plano noturno por gatilho duro, com teto 8 e excedente declarado em `pontual_candidatos`/`pontual_excedente` em vez de cortado em silêncio. EWS e staleness **não** entram de propósito: já são cobertos pelas passadas diárias, e trazê-los faria a pontual virar uma terceira varredura cara disfarçada.

**Guarda.** `api/test/sentinela-pontual.test.mjs`, 13 testes, prova das duas pontas. Medida contra o código pré-correção: **6 dos 13 falham lá**. Suíte completa 117/117, 14 arquivos.

---

## 25/08 — RESOLVIDO e DEPLOYADO (SUBSTRINGDONO1): documento da CVM ia para o emissor errado, e dois emissores nunca recebiam nada

> **Status:** RESOLVIDO. Worker v4.9.215 em produção desde 25/08 17:18 BRT, commit `ef3a5f4`, portão validado
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** a rotina matinal de 25/08 entregou `cvm_documentos` contaminados para "Oi" e "CSN" no `listar_plano_rotina`
> **Condição de Obsolescência:** ATENDIDA em 25/08. Resta observar a primeira rodada do sync sob o código novo, quando `cvm_atribuicao_por_cnpj` no health deixa de ser 0 e a fila de quarentena passa a ter dado real

**O que estava acontecendo.** Cada emissor perguntava ao acervo "este documento contém meu nome?". É uma pergunta que vários emissores respondem sim ao mesmo tempo, então o mesmo documento tinha dois donos, e às vezes o dono errado. Medido em produção, no acervo real de 776 documentos:

- **Oi**: 28 documentos entregues, **4 eram dela**. Os outros 24 eram Três Tentos (10), Saneamento de Goiás (6), Sequoia (3), Ecoponte (3) e Equatorial Goiás (2). Nenhuma dessas empresas tem "Oi" como palavra. O que casava era a substring dentro de SEQU**OI**A, AGR**OI**NDUSTRIAL, G**OI**AS e NITER**ÓI**. O card da Oi podia exibir Fato Relevante da Três Tentos como evento dela.
- **CSN**: 6 documentos, **todos da CSN Mineração**, que é outro emissor da carteira, com outro CNPJ. Exatamente os mesmos que o plano entregava para "CSN Mineração".

**A segunda metade, que era pior.** A CSN nunca teve alias declarado. A CVM registra a companhia como `CIA SIDERURGICA NACIONAL` (CNPJ 33.042.730/0001-04, ATIVO), nome que não contém "CSN" em lugar nenhum, então o documento dela **nunca chegava nem a entrar** em `cvm:documentos`. A aparência de saúde vinha do defeito vizinho: o emissor exibia 5 documentos e ninguém percebia que eram da mineradora. Consequência concreta: a Fitch rebaixou a CSN de B para CCC+ em 31/07/2026, o relatório foi protocolado na CVM em 05/08, e havia 15 documentos da CSN no IPE desde 25/07, 3 deles Fato Relevante. A rotina caiu para imprensa com a fonte primária disponível o tempo todo.

**Terceiro caso, achado pela guarda nova.** A **Copasa** está no mesmo buraco. Razão social `COMPANHIA DE SANEAMENTO DE MINAS GERAIS` (CNPJ 17.281.106/0001-03, ATIVO), e o nome "COPASA" só existe no `DENOM_COMERC` do cadastro, campo que o `ipe_cia_aberta` não publica. São 271 documentos protocolados em 2026, 16 nos últimos 30 dias, nenhum jamais chegou ao emissor.

**Quarto achado, no caminho.** A tabela `SYNC_ALIAS_NOMES_CVM`, que decidia se a linha entrava no KV, divergia da tabela que decidia de quem o documento era. **Dasa, Natura, Vivo, TIM e Taesa** tinham alias na segunda e não na primeira: o sistema sabia de quem era o documento e o descartava na porta. Cinco emissores cegos pelo mesmo motivo da Eletrobras no NOMEMORTO1.

**Causa raiz.** Não é o `includes()`, é a pergunta. Enquanto a atribuição for "contém meu nome", ela é ambígua por construção e nenhuma quantidade de alias resolve. E manter três tabelas que precisam concordar garante que uma hora não concordem, que é o NOMEMORTO1 se repetindo pela terceira vez (a primeira foi a Eletrobras, a segunda o SENDASGPA1, onde a resposta certa vinha por ordem de inserção do `for..in`, ou seja, por sorteio).

**Correção.** Um árbitro só, `_donoDocumentoCVM`, que responde de quem o documento é:

- índice único montado das 3 tabelas de uma vez, então alias novo vale nas três pontas
- **âncora no início de palavra**, e só no início: o fim pode cair no meio da palavra, senão alias deliberadamente prefixo (`SENDAS DISTRIB` para `SENDAS DISTRIBUIDORA S.A.`, `MOVIDA PART`) para de funcionar e a correção troca um bug por outro
- **termo mais longo vence**, então `CSN MINERACAO` ganha de `CSN`
- os 4 call sites (leitor, ingestão, painel de cobertura e a ação de admin) passam a consultar o mesmo lugar
- `SYNC_ALIAS_NOMES_CVM` aposentada, medida como 100% redundante antes de remover
- aliases de CSN e Copasa declarados

**Delta medido, não estimado.** Sobre os 776 documentos de produção, mudam **exatamente 6 razões sociais**, as contaminadas, e nenhuma das outras 121. Oi vai de 28 para 4 documentos, CSN de 6 para 0 (e volta a receber os próprios no próximo sync, com o alias). Sobre o `ipe_cia_aberta_2026.csv` real, a ingestão sai de 144 para 130 empresas: saem 19 companhias que não são de ninguém, entram os 5 emissores cegos.

**Guardas, com prova das duas pontas.**

1. `api/test/cvm-atribuicao.test.mjs`, 17 testes. Contra o código pré-correção **7 falham**, nomeando o incidente (`expected [ 'CSN MINERAÇÃO S.A.' ] to deeply equal [ 'CIA SIDERURGICA NACIONAL' ]`, e a invariante de dono único acusando `[["EQUATORIAL GOIAS...",["Oi","Equatorial Energia"]],["CSN MINERAÇÃO S.A.",["CSN","CSN Mineração"]]]`). Com a correção, 17 passam. Inclui a invariante "um documento tem no máximo um dono", que teria pego o defeito sozinha.
2. `scripts/check-emissores-cadastro.mjs` ganhou uma segunda checagem. A antiga pergunta "existe companhia ativa que casa com este emissor?", e a CSN **passava** nela, porque casava com a CSN Mineração. A nova pergunta o contrário: "existe companhia ativa da qual este emissor seja o dono?". Julga só por `DENOM_SOCIAL`, deliberadamente, porque é o campo que o IPE publica. Com `DENOM_COMERC` junto a guarda aprovava a CSN por um nome que o pipeline nunca vê, medido. Roda semanal no `emissores-cadastro.yml`.

**Suíte:** 93 testes, 13 arquivos, todos passando.

**Fase 2, o nome deixou de decidir (25/08, mesma sessão).** A correção acima ainda não bastava: mesmo com âncora, `AGRO INDÚSTRIAS DO VALE SÃO FRANCISCO` e `VALE BONITO AGROPECUÁRIA` continuavam casando com o emissor Vale, porque VALE começa palavra nas duas. Âncora não salva quando o nome do emissor é palavra comum. A atribuição passou a usar CNPJ, que a CVM já publicava e o Worker nunca lia. Duas tabelas separadas de propósito, primário para ITR e família para IPE, porque a subsidiária protocola no CNPJ dela e juntar as duas faria o card de balanço ler ITR de distribuidora. Conferido contra o cadastro vivo: `37.663.076/0001-07`, que a tabela predictiva ainda chamava de AES Brasil, hoje é AUREN PARTICIPAÇÕES e entrou na família da Auren em vez de ser descartado como órfã.

**Deployado.** Worker v4.9.215 em produção em 25/08 17:18 BRT. Saída do portão: `{"ok":true,"versao":"v4.9.215","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"sentry_ok":true}`. Os campos `cvm_atribuicao_*` saem zerados até o primeiro sync sob o código novo, porque o meta ainda é o do sync anterior. Os 776 documentos já no KV não têm o campo de CNPJ e seguem atribuídos pelo nome, que é o caminho de compatibilidade previsto e testado, então o painel não esvazia.

---

## 25/08 — ABERTO P1 (uma ação do operador): token colado no chat, e o substituto criado mas não instalado (TOKENCHAT1)

> **Status:** o token exposto foi revogado. Falta **instalar** o substituto na variável de ambiente. Enquanto isso, Pages segue no fallback OAuth
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** o operador colou o valor de um token da Cloudflare direto na conversa, pedindo que o agente o instalasse
> **Condição de Obsolescência:** fecha quando `pwsh ./scripts/deploy-pages.ps1 -DryRun` imprimir `Credencial: CLOUDFLARE_API_TOKEN com acesso a Pages OK` em vez dos dois `AVISO:`

Um valor de token foi colado na conversa. O agente recusou usá-lo e recomendou revogação imediata, que foi feita. O registro fica porque **é a mesma família do ROUTINEKEY-PLAIN1**, e aquele caso mostra o custo de descobrir tarde: transcripts e backups são append-only, preservam o valor, e a chave de lá segue sem rotação até hoje porque rotacionar depois quebra toda rotina que autentica com ela. Aqui a exposição teve minutos e a revogação foi barata. A diferença entre os dois casos é só tempo de detecção.

**Por que o agente não gera nem instala token.** Duas razões independentes, e a segunda vale mesmo se a primeira cair. O MCP do Cloudflare carregado não tem ferramenta de criação, só `token_verify`. E criar token exige `User API Tokens: Edit`, que o token atual não tem, além de o valor secreto voltar uma única vez no corpo da resposta, que iria parar no contexto e no transcript. Seria fabricar o incidente em vez de resolvê-lo. O classificador de segurança bloqueou duas tentativas de leitura que tocavam a credencial, e estava certo nas duas.

**Estado medido em 25/08, não presumido.** O token instalado na variável **ainda é o antigo** e **continua vivo**: `wrangler secret list` devolve exit 0 e lista os 22 secrets do Worker. Ou seja, as rotinas agendadas e o deploy do Worker não quebraram. O que falta é só `Cloudflare Pages: Edit`, e por isso o `deploy-pages.ps1` segue caindo no OAuth do wrangler.

**A variável não está onde o CLAUDE.md dizia.** Medido: escopo `Machine` **ausente**, valor em escopo `User`. O `CLAUDE.md` afirmava "variável de ambiente do sistema", o que levou o agente a instruir instalação em `Machine` com elevação, desnecessariamente. Corrigido no `CLAUDE.md` na mesma sessão. As tarefas do Task Scheduler rodam sob esta conta e enxergam `User`, comprovado por o deploy do Worker e o Export-Historico funcionarem.

**O que falta, uma ação do operador:**

```powershell
$s = Read-Host 'Token novo' -AsSecureString
$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
try { [Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN', [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b), 'User') } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
```

Sem elevação, sem eco na tela, sem entrar no histórico do shell. Mesmo idioma do `api/Set-VixAdminCredential.ps1`, que já documenta esse padrão no repo. Depois reiniciar o terminal, porque processo aberto não relê ambiente.

**Guarda que já existe e não precisou ser criada.** As sondas `Test-CredencialWorkers` e `Test-CredencialPages` dentro dos próprios scripts de deploy já detectam e nomeiam a permissão faltante antes de tocar em qualquer coisa. Foi o que permitiu medir tudo acima sem adivinhar. O que faltava não era detecção, era o operador executar a troca.

---


## 25/08 — RESOLVIDO: skill da noturna reescrita para orçar por lote (PASSOCUSTO1)

> **Status:** RESOLVIDO. Skill atualizada no commit `f144d49` ("fix(noturno): recalibra lotes e fecha fallback CVM"); reescrita verificada em 25/08 lendo `routines/claude-desktop/noturno/SKILL.md`
> **Data da Versão:** 2026-08-25
> **Origem do Registro:** log da noturna de 25/08 (`logs/routines/vixradar-noturno_20260825.log`, linhas `DECISAO:` e `CUSTO:`), relatório da rodada para o operador
> **Condição de Obsolescência:** ATENDIDA em 25/08. A condição era reescrever Passo 6 + "Orçamento de tokens" para orçar por número de lotes; a skill foi reescrita e incorpora todos os pontos

**O que foi medido.** Sessão de 25/08, 103/103 no ledger, 54 analisados, 4 lotes de subagente:

```
CUSTO: rapida_1=199815 rapida_2=162612 rapida_3=147565 aprofundada_1=208325 total=718317 (cap 700k, estouro 2,6%)
```

- Boot fixo do subagente **~130k por lote**, domina o custo. Marginal por emissor dentro do lote **~2–13k** (registrado na linha `DECISAO:` do log).
- A skill orça 15k fixos + 9,5k/emissor (rápida) e 13k/emissor (aprofundada, "sem medição recente, revalidar"). Os dois estão errados **na forma**: o custo quase não escala com o número de emissores, escala com o número de lotes. Disparar um lote custa ~130k, tenha ele 1 ou 16 emissores.
- Consequência prática: seguir o texto atual leva a multiplicar lotes achando que economiza, e o corte de cap atinge justamente a cauda de EWS alto. Em 25/08, dois lotes de aprofundada (11+11, conforme a skill) gastariam ~130k a mais de partida e o cap cortaria Oi, Braskem e Raízen — três dos cinco CRITICO do dia. A rodada fundiu os 16 num lote só (desvio deliberado, registrado no log) e cobriu todos.

**Como a reescrita incorporou a recomendação.** Verificado lendo o `SKILL.md` atual:

- `custo = 130000 x numero_de_lotes + 5000 x numero_de_emissores`, com a tabela dos 4 lotes medidos em 25/08 e a análise de que é a **profundidade de busca** (nº de chamadas de ferramenta) que move o custo, não o tamanho do lote.
- Aprofundada de 11 → **até 16**; teto declarado como limite de contexto do subagente, não de custo, com a medição citada (16 emissores, 39 chamadas, 208k).
- Fila ordenada por `ews_score` desc **antes** de lotear, para o corte de orçamento cair na cauda de EWS 0-1.
- **Guarda que a recomendação não tinha:** reserva do custo da fila aprofundada calculada no início (`reserva_aprofundada = 130000 x lotes + 5000 x emissores`), e a fila rápida só dispara se sobrar cap acima da reserva ainda não executada — impede queimar o cap na rápida e deferir os EWS altos.
- Política de cap mais rigorosa que a recomendada (~5%): **700k é teto de decisão** (nunca disparar lote cuja estimativa passe disso), **725k é só a folga para overshoot de um lote já disparado**, porque o `subagent_tokens` só é conhecido depois. Tolerância ≠ permissão.

**Histórico da saga, para não recalibrar por emissor de novo.** 18/08 calibrou 9,5k/emissor → 19/08 medido 14,6k/emissor (registro abaixo) → 24/08 CALIB3: calibragem "4x alta" deferiu 15 à toa → 25/08: o modelo por emissor está errado na forma, não no fator. O fator certo é por lote. O "Contribuinte secundário" do bloco CVMURL404 (24/08) já tinha medido 25,2k/emissor na aprofundada e 12,3k na rápida — variações de um número que não é a variável certa.

---


## 24/08 (oitava rodada) — RESOLVIDO: card recurado e vencido ganha estado próprio (EXCECAO-FRESCOR1)

> **Status:** RESOLVIDO, commits `e7d40b7` e `35bc990`. CI verde no run `32802931668` com as 5 provas novas
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** P2 da auditoria independente de `ba8322a`, que pegou o card de Rating da Unidas mudo para a máquina
> **Condição de Obsolescência:** perde validade se a régua de 365d para rating for revista, ou quando o bloco passar de 15 exceções e o estopim disparar

Havia só dois estados. Card sem o trio caía no balde de pendência e não reprovava, card com o trio era julgado pela régua. Faltava o terceiro, "eu curei, a data é esta, e ela não passa".

Sem ele, quem cura um emissor e esbarra num card vencido tem duas saídas e as duas são ruins. Deixar o card mudo, e aí ele some dentro dos herdados fingindo que ninguém mexeu, ou inventar data mais nova. A primeira foi o que eu fiz no Rating da Unidas.

**Causa raiz.** O balde de pendência conflava dois significados, "nunca recurado" e "recurado e não passou". Enquanto todos os 400 eram do primeiro tipo isso não custava nada. No primeiro emissor recurado virou buraco, porque permite curar o que passa e silenciar o que não passa mantendo o agregado verde.

**Correção.** `EXCECOES_FRESCOR` espelha o `EXCECOES_COBERTURA` que já existia no mesmo arquivo. O que impede a exceção de virar um segundo silêncio: exige o trio completo no card (exceção suspende veredicto, nunca datação), é chaveada por `"Emissor / label"` e não por emissor, é impressa por nome em toda rodada com o veredicto que a régua deu, é contada separada, e a linha final de OK deixa de afirmar que todo card datado está no prazo quando há exceção viva. Exceção órfã por label renomeado reprova.

**Estopim.** Acima de 15 exceções a guarda avisa que o suspeito passa a ser a régua, não o card. Nasce de uma medição da auditoria: são 103 cards de Rating e só 2 datados dentro da janela. Os outros 100 estão **sem data**, que não é o mesmo que vencidos, então não dá para condenar os 365 dias ainda. Medido de fato: 1 vencido (Unidas, 419 dias) contra 2 aprovados. Se o bloco encher conforme a recuração avança, essa é a evidência para alargar a régua em vez de empilhar linha. Existe para não sonambular até 101 exceções achando que cada uma foi decisão consciente.

**Achado no caminho, P3a.** O relógio da guarda usava `new Date().toISOString()`, dia civil UTC, e entre 21h e 24h BRT imprimia o dia seguinte. É a lição do RELOGIO3H1 ao contrário. Lá o defeito foi usar BRT para **instante**, aqui era UTC para **dia civil**. As duas convivem, instante é UTC cru e dia civil é BRT.

**O CI reprovou a primeira tentativa, e o motivo vale registrar.** O runner do GitHub invoca `run:` como `bash -e {0}`, e `set -uo pipefail` dentro do script não desliga o `-e` herdado. `saida=$(comando); rc=$?` é atribuição simples, não condição de `if`, então sob `-e` o script aborta na hora em que o comando sai diferente de zero, antes do `rc=$?` e do `if` rodarem. As etapas antigas do arquivo escapam porque testam o comando direto na condição do `if`, que é isento. As 5 novas usavam o padrão errado e morriam mudas. Não doeu no teste local porque o script de prova roda sem `-e`. Corrigido com `set +e`/`set -e` em volta de cada captura, e reproduzido localmente com `bash -e` explícito sobre os 5 blocos extraídos do YAML antes de empurrar de novo.

**Aceite.** As duas guardas em exit 0, vitest 76 testes em 12 arquivos, e as 5 provas novas `success` no run `32802931668`, cada uma imprimindo sua linha. Pendência declarada caiu de 397 para 396, e o Rating da Unidas saiu do balde para a exceção nomeada.

---
## 24/08 (sétima rodada) — RESOLVIDO: Unidas decidida e primeira recuração de fato do Marco 2 (UNIDAS-CONTROLADORA1)

> **Status:** RESOLVIDO no repo, commit `ba8322a`. Frontend NÃO deployado, a mudança em `app/index.html` só vai ao ar no próximo deploy de Pages
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** decisão do operador sobre a única linha do `A_DECIDIR`, mais o achado de que os 4 cards da Unidas estavam factualmente errados
> **Condição de Obsolescência:** perde validade se a Unidas for reorganizada de novo, se a controladora deixar de protocolar ITR, ou quando sair ação de rating nova e o card de Rating puder ser datado

Duas companhias Unidas protocolam ITR do 2T26 e o nome não separa. A decisão do operador foi pela controladora, `UNIDAS LOCAÇÕES E SERVIÇOS S.A.` (75.609.123/0001-23), pelo critério que a tabela já aplica, vale quem emite a dívida que o radar acompanha. Dela são as séries públicas 12ª a 23ª com preço ANBIMA (ISIN BROVSADBS*, B3 OVSAA2), rating AA.br Moody's Local e AA(bra) Fitch, registrante CVM 53214. A `UNIDAS LOCADORA` (45.736.131) virou subsidiária integral no 3T23 e só emitiu as séries 1ª a 3ª, privadas e atreladas a CRI.

**Corroborado por dentro, não só pela fonte externa.** O próprio ITR mostra debêntures somando R$ 9,56 bi dos R$ 13,06 bi de dívida bruta consolidada em 2026-06-30. É a entidade que carrega o papel.

**O card estava factualmente errado, não só velho.** Os 4 diziam "Incorporada Localiza", "Fusão concluída 2022", "Via Localiza", fonte `Localiza · 2025`. Casamento por nome que ignorava a saída do grupo Localiza pelo Cade/Brookfield em 2022-23. Alavancagem exibia `N/A` e EBITDA exibia "Consolidado Localiza". Mesma família do NOMEMORTO1 e do SENDASGPA1, atribuição por nome apontando para a companhia errada.

**Números, todos derivados dos CSV da CVM** (`itr_cia_aberta_2026.zip` e `dfp_cia_aberta_2025.zip`, ambos Last-Modified 2026-08-23), nenhum digitado à mão:

| | |
|---|---|
| Dívida bruta (2.01.04 + 2.02.01) | R$ 13.055,3 mi |
| Caixa (1.01.01) | R$ 4.096,9 mi |
| **Dívida líquida** | **R$ 8.958,4 mi** |
| EBITDA LTM = 2S25 + 1S26, com 2S25 = FY2025 − 1S25 | **R$ 2.684,4 mi** |
| **Alavancagem** | **3,34x** |

EBITDA = EBIT (DRE 3.05) + D&A (DFC 6.01.01.02). Status `warn` na alavancagem porque 3,34x fica acima de todo par "ok" da carteira (Localiza 2,9x, Simpar 3,0x, Movida 2,6x, JSL 2,8x) e perto da régua de 3,5x que o card da Localiza cita como covenant do setor.

**Divergência registrada, não escondida.** A decisão do operador citava dívida bruta consolidada de R$ 12,5 bi. O ITR 2T26 diz R$ 13,06 bi com arrendamento IFRS 16, ou R$ 12,85 bi contando só empréstimos e debêntures. Não muda a decisão de qual companhia é, mas a citação externa e o demonstrativo não batem exatamente, provavelmente corte de data ou definição diferente na fonte de research. O card usa o ITR.

**Contrato da recuração aplicado.** `DT_REFER` 2026-06-30 vira `as_of`, `DT_RECEB` 2026-08-11 vira `source_date`, `metric_type` `itr`. Pendência declarada caiu de 400 para 397 cards.

**O card de Rating ficou como pendência declarada, de propósito.** *(Superado em 24/08 pelo EXCECAO-FRESCOR1, ver a entrada logo acima. O card passou a ser datado e a exceção é declarada e nomeada. O texto abaixo fica como registro do que se acreditava na hora.)* A ação de rating mais recente que a decisão cita é de jul/2025, fora da janela de 365 dias que `julgarFrescor` cobra de `metric_type: "rating"`. Datar com o trio reprovaria `check-metricas-curadas.mjs`, e inventar reafirmação mais nova seria pior. O valor AA.br fica visível com a data na fonte, sem o trio, até sair ação nova. **Isto é decisão pendente do operador:** ou aparece ação de rating dentro da janela, ou a régua de 365 dias precisa de tratamento para emissor cujo rating simplesmente não é reafirmado com essa frequência.

**`A_DECIDIR` ficou vazio**, mas o bloco continua existindo. É o destino de emissor novo sem decisão, e é o que permite a guarda reprovar "entrou na carteira e ninguém decidiu". Bloco vazio não é bloco desnecessário.

**Aceite, saída real colada na conversa.** `check-emissores-cnpj.mjs` exit 0 (99 com CNPJ, `a decidir: 0`), `check-metricas-curadas.mjs` exit 0 (397 pendentes), vitest 76 testes em 12 arquivos, e o `emissores-cadastro.yml` verde no commit `ba8322a`. A etapa que confronta os CNPJs contra o ITR vivo é `skipped` em push por desenho (só roda em `schedule`/`workflow_dispatch`), então foi disparada à mão no mesmo commit e passou com `conferidos no indice CVM: 99/99, razao social conferida contra o indice vivo`.

---

## 24/08 (sexta rodada) — RESOLVIDO: falha de envio de e-mail transacional era invisível por construção (EMAILSILENT1)

> **Status:** RESOLVIDO e DEPLOYADO. Worker v4.9.214 em produção desde 24/08 21:54 BRT, commit `db2842e`, merge `5768c3c`. Validado no portão (`ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`) e por sonda sem efeito colateral, `admin_email_envios` sem senha devolve 403 em produção, onde o código antigo devolvia 401. CI `Worker Tests` verde em `db2842e`, 12 arquivos
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** `joao.tavano@mirabaud.com.br` foi aprovado, o painel exibiu "João Tavano aprovado", e não havia forma interna de saber se o e-mail de aprovação chegou. A única fonte autoritativa era o painel da Resend, fora do sistema
> **Condição de Obsolescência:** perde validade se `enviarResend` deixar de devolver o `id` da Resend, ou se o rastro migrar de KV para DO na migração v5

Aprovar alguém devolvia `ok:true` tivesse a mensagem saído ou não. O admin lia "aprovado" e não tinha como distinguir aprovado-com-aviso de aprovado-sem-aviso. Recusa por domínio corporativo do destinatário é o desfecho mais provável e o mais invisível, porque acontece do lado de lá e nunca virava exceção aqui dentro.

**Causa raiz.** Quatro `catch {}` literalmente vazios em volta da chamada à Resend (`handleAdminAprovar`, `handleAdminRejeitar` e os dois ramos de `handleEmailActionConfirm`), mais um `console.error` solto em `handleSolicitarReset`. A informação para diagnosticar já existia e era descartada: `enviarResend` monta e devolve o `id` que a Resend gera, e nenhum dos 16 call sites de produção lia esse retorno. O único que aproveitava era `newsletter_teste`, que devolvia `resend_id` na resposta HTTP e não persistia.

**Medido.** Varredura dos 16 call sites de `enviarResend`, não a lista da auditoria. A lista original tinha dois erros: apontava `handleSolicitarReset` como `catch {}` vazio quando ele já tinha `console.error`, e não citava `handleAdminRejeitar`, que tinha o defeito idêntico. Corrigidos os cinco caminhos cujo destinatário é o usuário final.

**Correção.** `enviarEmailRastreado` centraliza os cinco envios e nunca lança, porque a ação primária (aprovar, rejeitar, gerar token) já aconteceu e continua valendo. Quatro canais, cada um com papel distinto: `console.error` para `wrangler tail`, Sentry para alerta que alcança o operador sem ninguém consultar nada, Analytics Engine para agregação, e KV para o rastro por destinatário. As respostas de aprovar e rejeitar ganharam `email_enviado`, `email_erro` e `resend_id`, com tri-estado deliberado (`null` é "não tentou", `false` é "tentou e falhou").

**Exceção deliberada em `solicitar_reset`.** A resposta continua idêntica nos dois desfechos. Contar ao chamador que o envio falhou revelaria que a conta existe e está aprovada, que é exatamente o que a mensagem genérica protege. Anti-enumeração vale mais que a conveniência do aviso, e o sinal de falha sai pelos canais do operador.

**LGPD.** A chave `email_envio:{email}:{ts}` usa o endereço em texto puro de propósito. Ele já está no mesmo namespace em `user:{email}` e `bounce:{email}:{ts}`, então hash não reduziria identificabilidade, só quebraria a correlação com bounce e a consulta por prefixo. O controle real é retenção, TTL de 90 dias igual ao do bounce, para que entrega e devolução expirem juntas. Não grava corpo da mensagem, IP nem user agent. Para a Sentry, que é terceiro, o endereço vai redigido e só o domínio segue como tag, preservando o bloco `dataCollection` fechado a dedo no SENTRY-PII1.

**Guarda sistêmica.** `api/test/email-falha-silenciosa.test.mjs`, 7 testes, roda no CI por `worker-tests.yml`. Prova de duas pontas medida: contra o código pré-correção os 7 falham, contra o corrigido os 7 passam. O determinismo vem de um `outboundService` em `vitest.config.mts` que intercepta só `api.resend.com` e decide pelo campo `to` do payload, porque este pacote (`@cloudflare/vitest-pool-workers` v0.20.x) não exporta mais `fetchMock` de `cloudflare:test`, só o tipo `MockAgent` sobrou no `.d.ts` sem implementação em `dist/`. Efeito colateral bom, a suíte parou de bater em `api.resend.com` de verdade a cada rodada de CI.

**Consulta.** Action admin `admin_email_envios` responde "o e-mail chegou?" por destinatário, cruzando os envios com os registros de bounce e complaint que o webhook da Resend já gravava. Devolve `retencao_dias` explícito porque lista vazia tem duas leituras, nunca enviamos ou o TTL levou, e confundir silêncio com ausência é o erro que abriu esta auditoria.

**Deixado aberto de propósito, P3.** Os dois envios de notificação ao admin (`handleRegistrar`, o de cadastro novo e o de reenvio com dedup de 24h) não passam pelo helper. Não são silenciosos, já têm `console.log` mais evento de Analytics Engine, e a audiência é outra, se falharem o admin simplesmente não vê a solicitação. Ficam sem rastro por destinatário e sem alerta na Sentry. Segundo item, `enviarResend` devolve o objeto único quando `resultados.length === 1`, então um lote de 2 em que 1 falhou retorna forma indistinguível de envio único bem-sucedido. Não afeta os cinco caminhos corrigidos, que são todos de 1 destinatário, mas engana quem for instrumentar os call sites de lote.

---

## 24/08 (quinta rodada) — RESOLVIDO (Marco 1): carteira trocada só no backend deixou a Braskem sem card de métrica (CURADORIA1)

> **Status:** Marco 1 resolvido e deployado. Marco 2 (recuração dos 101) ABERTO P2
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** print do operador mostrando os quatro cards de risco da Braskem vazios no dia do protocolo de recuperação extrajudicial. Investigação mediu `EMISSORES_LISTA` (`api/src/worker.js:3798`), `METRICAS_CURADAS` e `EMISSORES` (`app/index.html`), e comparou contra produção
> **Condição de Obsolescência:** perde validade quando o Marco 2 fechar e os 103 emissores tiverem `as_of`/`source_date`/`metric_type`, ou se `METRICAS_CURADAS` deixar de ser tabela curada à mão e passar a ser servida pelo Worker

O operador viu os cards de Alavancagem, Rating, Cobertura e EBITDA da Braskem com traço e "Pendente", no mesmo dia em que ela protocolou recuperação extrajudicial de US$ 10,9 bi, e leu como falha de coleta ligada ao evento. Não era. Esses cards nunca dependeram de evento, rotina, LLM ou CVM.

**Causa raiz.** `METRICAS_CURADAS` é objeto literal escrito à mão dentro de `app/index.html`, e o commit `b13b605` (`feat(carteira): AES Brasil sai, Braskem entra`, CARTEIRA-24AGO1) alterou `api/src/worker.js`, `api/wrangler.toml` e `scripts/check-emissores-cadastro.mjs` sem tocar em `app/index.html`. A carteira mudou só no backend. Nada no projeto comparava as três tabelas que precisam concordar, então a lacuna era silenciosa por construção. Mesma família do NOMEMORTO1, onde eram três tabelas de alias sem nada forçando concordância.

**Medido.** Carteira 103, curadas 101, menu 103 mas com o conjunto errado. Sem card: Braskem, Tupy, Itaú Unibanco. Órfã: AES Brasil, que também seguia no menu. Braskem não aparecia no menu em lugar nenhum. Produção idêntica ao repo (`CACHE_VERSION` v202.30).

**Defeitos de segunda ordem, achados na mesma medição.** (1) O placeholder exibia "Cobertura · ICSD", e "Cobertura" tem zero ocorrências como rótulo nos 101 curados, ou seja, o card vazio prometia métrica que o sistema não produz para ninguém. (2) A idade do dado não era legível por máquina, vivia dentro do texto livre de `fonte` tipo `"CVM · 4T25"`, e 257 das 404 células declaravam 4T25 em agosto de 2026, sem qualquer sinal de idade no painel. (3) Três cards do Vamos não tinham campo `fonte` nenhum, e ao buscar a fonte do Rating apareceu que o valor exibido estava factualmente errado, AAA(bra) com perspectiva estável quando a Fitch rebaixou para AA+(bra) com perspectiva negativa em 28/08/2024.

**Correção (Marco 1).** Braskem, Tupy e Itaú Unibanco ganharam os quatro cards com número de fonte primária (release 2T26 da Braskem de 14/08, ITR da Tupy de 06/08, 6-K do Itaú na SEC de 04/08, ações de rating da Fitch e da S&P). AES Brasil saiu do menu e do curado. Braskem entrou no menu em Petróleo, Gás e Combustíveis, que é onde o backend a coloca. Schema ganhou `as_of`, `source_date` e `metric_type`. Placeholder virou aviso honesto. Painel passou a exibir a idade do dado, e card sem datação exibe "idade não declarada" em vez de exibir nada. Rating do Vamos corrigido para AA+(bra).

**Guarda sistêmica.** `scripts/check-metricas-curadas.mjs`, offline, lê só `api/src/worker.js` e `app/index.html`, roda no CI em `.github/workflows/emissores-cadastro.yml`. Cinco checagens: cobertura de métrica (inclui órfã), cobertura de menu, integridade do trio de campos, fonte obrigatória, e frescor por tipo de métrica. Três pontas provadas no CI, reprova emissor sem card, reprova card com `as_of` vencido, e aceita o repo como está, porque guarda que reprova tudo passaria nas duas negativas parecendo sadia.

**Limite declarado da guarda, de propósito.** Ela não consegue reprovar "card velho porque saiu rating novo" nem "porque saiu evento crítico novo", já que lê arquivos estáticos. O único candidato a oráculo no repo, `data/labels/eventos_credito.jsonl`, foi medido e não serve, parou em 2026-07-31 e tem zero registros de Braskem, então aprovaria em silêncio justamente o caso que originou a guarda. Frescor ficou por prazo fixo por tipo, e a cláusula "imediato" é revisão manual, registrada no cabeçalho do script.

**Marco 2, em andamento.** Os emissores herdados seguem sem os três campos e aparecem como pendência declarada na saída da guarda. Não reprovam ainda. A régua de ITR reprovaria todos eles hoje, o trimestre exigido é 2026-03-31 e eles carregam 4T25. Andou em 24/08 com a Unidas, primeira recuração de fato: pendência declarada caiu de 400 para 397 cards. Ver a entrada UNIDAS-CONTROLADORA1 abaixo.

**Adendo 24/08, verificação independente da entrega.** Até aqui o fechamento do Marco 1 valia pela palavra da sessão que entregou. Medido de novo em `main` (`54030f2`) por outra sessão, sem editar nada, rodando a própria guarda e reextraindo as tabelas do disco. Confere. `check-metricas-curadas.mjs` sai `EXIT=0` com `Carteira (EMISSORES_LISTA): 103 | Com card (METRICAS_CURADAS): 103 | No menu (EMISSORES): 103` e 400 cards de pendência declarada. Total de 412 cards, que fecha em 103 × 4 e em 400 pendentes mais 12 datados. Zero card sem fonte, zero label "Cobertura". Trio de campos em 12 cards, distribuição `{"itr":9,"evento_credito":1,"rating":2}`. Braskem e Tupy presentes na carteira e no curado, AES Brasil ausente nos dois. Valores conferidos no literal, Braskem 6,74x `breach` e Rating `RD` com fonte `Fitch 17/08 · RE 24/08/2026`, Tupy 4,14x `warn` e `brAA` S&P mar/2026, Itaú Basileia 12,3% `ok` e ROE 24,3%. "idade não declarada" presente 2 vezes em `app/index.html`.

**Ressalva de leitura sobre a prova de CI, achada nessa verificação.** O run que falhou é o `cc39280`, o commit que introduziu a guarda, e a falha foi mesmo o passo do cadastro CVM (`ERRO: fetch failed`, `exit code 2`), download transitório. Só que naquele run **todas** as etapas de guarda ficaram `skipped`, não passaram, porque o passo anterior abortou o job. Então o commit da guarda não prova nada sobre ela. A prova está no run do v202.32 (`235f739`), onde as três rodaram com `success`, `Guarda tem que reprovar emissor sem card de metrica`, `Guarda tem que reprovar card com as_of vencido para o tipo` e `Guarda tem que aceitar o repo como esta`. O mérito não muda, a guarda está provada, mas quem ler rápido pode confundir "o CI do commit da guarda falhou" com "a guarda foi exercitada ali". Não foi.

**Armadilha para o próximo que auditar esta tabela.** `EMISSORES_LISTA` guarda o nome com escape unicode, `Ita\xFA Unibanco`, e `METRICAS_CURADAS` guarda `Itaú Unibanco` cru. Comparar os dois sem desescapar acusa o Itaú como órfão da carteira, divergência que não existe. A guarda faz certo, tem `desescapar()` em `scripts/check-metricas-curadas.mjs:53`. Script de conferência ad hoc que copie só o recorte e esqueça o desescape reproduz o falso positivo, e foi o que aconteceu na primeira passada desta verificação. Mesma família do ACENTOMATCH1, acento quebrando comparação de nome, agora do lado de quem audita em vez do lado do sistema.

---

## 24/08 (quarta rodada) — CORRIGIDO NO CÓDIGO, DEPLOY PENDENTE: Braskem protocolou recuperação extrajudicial e o sistema não pegou (BRASKEMDETECT1)

> **Status:** CORRIGIDO NO CÓDIGO, DEPLOY PENDENTE. Ver fechamento de 31/08 ao final da entrada
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** auditoria operacional de 24/08 ([[91 - Auditoria Operacional 2026-08-24]]), comparando o protocolo do dia contra o que a noturna das 16h trouxe
> **Condição de Obsolescência:** perde validade quando existir fonte de Fato Relevante independente do ZIP `ipe_cia_aberta_2026.zip`, ou quando a CVM repuser o arquivo e a ingestão voltar a disparar por protocolo

A Braskem protocolou recuperação extrajudicial em 24/08, US$ 10,9 bi reestruturados. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch de 17/08, não o protocolo do mesmo dia. O painel segue com 20/08 como fato mais recente. Contraexemplo confirmado: falha de detecção, não ausência de fato.

**Causa raiz (duas, somadas).** (1) O ZIP `ipe_cia_aberta_2026.zip` da CVM está em 404 desde 23/08 (CVMURL404), o que tirou o gatilho primário de evento. (2) A busca de imprensa sozinha não alcançou o protocolo. A detecção depende demais de uma fonte só, e o fallback não cobre protocolo de recuperação judicial/extrajudicial fora do IPE.

**Impacto.** Cliente pago não vê o evento de crédito mais grave do dia.

**Correção.** Fonte alternativa para Fato Relevante/protocolos (MZiQ, avaliado na frente 2) ou fallback de busca que cubra recuperação judicial/extrajudicial. Decisão pendente do operador.

**Guarda sistêmica.** Não existe ainda. Proposta: gatilho de detecção para eventos de recuperação judicial/extrajudicial a partir de fonte que não dependa do ZIP da CVM; teste com contraexemplo fixo (protocolo da Braskem de 24/08).

**Status:** CORRIGIDO NO CÓDIGO, DEPLOY PENDENTE. Ver fechamento de 31/08 ao final da entrada.

**Adendo 24/08 19h48, sem apagar o diagnóstico acima.** O print do operador, tirado às 19h48 na sessão do CURADORIA1, mostra o protocolo na timeline da Braskem: card CRÍTICO, "Conselho aprova pedido de recuperacao extrajudicial para reestruturar US$ 10,9 bilhoes", `IMPRENSA`, data 2026-08-24, fonte `braziljournal.com`, com o cabeçalho "Analisado às 15:09" e 2 eventos identificados. Ou seja, o evento entrou por imprensa em alguma rodada posterior à noturna das 16h que originou este registro, e o painel deixou de estar cego para ele. Isso **não fecha** a pendência: a causa raiz continua de pé, a detecção segue dependendo do ramo de imprensa porque o ZIP da CVM está em 404 (CVMURL404), e não há guarda que garanta a captura na próxima vez. O que muda é o enunciado "o sistema não pegou", que era verdade na hora da auditoria e não é mais. Não foi possível confirmar pelo servidor nesta sessão, `op=state` exige autenticação e devolveu HTTP 401. Confirmar com o operador antes de reclassificar.

**Fechamento 31/08, sem apagar o diagnóstico acima.** Decisão do operador: caminho gratuito, endurecer o gatilho de imprensa em vez de pagar fonte alternativa. O ZIP da CVM voltou (medido 30/08), então o gatilho primário está de pé de novo, e a lacuna que restava era o fallback.

**Correção.** Três pontos em `api/src/worker.js`:

- Query R5 da análise (e R3 da newsletter) passou a incluir `extrajudicial`, o termo que faltava para a busca alcançar protocolo de recuperação extrajudicial.
- `PALAVRAS_CRITICAS` ganhou `recuperacao extrajudicial` e `recuperação extrajudicial`. Era o buraco determinístico: a substring `recuperacao judicial` não existe dentro de `recuperacao extrajudicial`, então a promoção automática de `aplicarRegrasNegocio` não disparava mesmo que o evento chegasse classificado abaixo de CRITICO.
- `emitirAlertaTier1` passou a taguear `recuperacao-judicial` também para `extrajudicial`, então o EWS pontua os dois com o mesmo peso (25 pts).

**Guarda sistêmica.** `api/test/gatilho-recuperacao.test.mjs`, contraexemplo fixo (protocolo da Braskem de 24/08). Prova de duas pontas medida com a função real exportada (`aplicarRegrasNegocio`): extrajudicial RELEVANTE vira CRITICO com `_promovido_automaticamente:true`, a variante acentuada idem, `recuperacao judicial` segue funcionando (sem regressão), e fora da janela de 30 dias continua descartado. Prova reversa embutida: contra o código antigo os dois primeiros casos falham porque o evento fica RELEVANTE.

**Estado.** Correção pronta em `api/src/worker.js` e teste criado, ainda **não deployado**. Deploy fica no `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.XXX`, que exige autorização explícita e valida em produção antes de commitar. Enquanto não deployar, o comportamento em produção não mudou.

---

## 24/08 (auditoria operacional) — RESOLVIDO EM PRODUÇÃO (v4.9.213): `_last_scanned_at` gravado 3h no passado infla o gate de cobertura (RELOGIO3H1)

Achado da auditoria operacional de 24/08 ([[91 - Auditoria Operacional 2026-08-24]]). O gate de cobertura apareceu ALTO com 4 emissores "stale" (Simpar 25.1h, SLC Agrícola 25.1h, Bradesco 24.9h, Totvs 24.9h), mas o log da noturna de 23/08 tem `FIM: ... 103/103` (18:33:29) e os 4 foram cobertos naquele dia (OK|FULL). Ou seja: falso incidente.

**Causa raiz.** `obterAgoraBRT()` retorna `new Date(Date.now() - 3*36e5)` — desloca o epoch 3h para trás. Isso é correto para derivar o **dia civil** BRT (`hoje`), mas no `receber_analise` (worker.js:17781) o `_last_scanned_at` é gravado com `_raAgoraBRT.toISOString()` como se fosse o **instante da varredura**. Na leitura `_parseHorasStale` (worker.js:9464) compara contra `Date.now()` cru, então toda varredura parece 3h mais velha. Reproduzido: dado recém-gravado reporta `horas_stale` = 3h.

**Correção.** Gravar `_last_scanned_at` como `new Date().toISOString()` (UTC real) e usar `obterAgoraBRT()` apenas para `_raSemana`/`_raHoje`/`_raJanelaInicio` (objetos que não viram timestamp comparável). Alternativa: `new Date(_raAgoraBRT.getTime() + 3*36e5).toISOString()`.

**Guarda sistêmica (falta hoje).** Teste que falha se `horas_stale` de um dado recém-gravado via `receber_analise` não for `0`. Nenhum teste hoje compara `_last_scanned_at` com o relógio real; `obterAgoraBRT` foi tratado como fuso só no caminho de **data** (FUSOTESTE1), não como instante de varredura. Proposta de revisão de skill: o checklist da matriz passa a incluir "todo timestamp gravado que será comparado com o relógio real deve ser UTC puro".

**Correção aplicada (24/08 17h, commit `2928a74`).** `_last_scanned_at` passa a ser `new Date().toISOString()` no `receber_analise`, e o fallback de `persistirResultadoCompartilhadoInterno` deixa de herdar `payload.timestamp` e usa o instante real de persistência. O `timestamp` continua em BRT de propósito, porque dele sai o dia civil da janela. A distinção que faltava é essa: data e relógio não são a mesma coisa.

**Correção ao diagnóstico acima, sem apagá-lo.** O defeito é real e foi confirmado, mas os quatro emissores citados como evidência provavelmente não eram sintoma dele. Simpar e os demais vieram `sem_eventos` na varredura, e esse ramo do `persistirResultadoCompartilhado` sempre gravou UTC real. Os 25,1h deles são cadência diária honesta, não os 3h. A assinatura verdadeira só aparece comparando os dois ramos lado a lado, e é o que mantinha o defeito invisível: metade da carteira sempre reportou certo.

**Medição de produção, antes da correção, 24/08 17:17 BRT.** Mesma rodada noturna, três minutos entre os submits:

| Emissor | Evento na rodada | `horas_stale` |
|---|---|---|
| Light, Aegea, CSN, Hapvida | com evento | 3,40 |
| Rumo, Simpar | sem evento | 0,40 |

**Guarda sistêmica (existe agora).** `api/test/relogio-varredura.test.mjs`, 3 testes. Prova reversa executada: com o bug reinjetado os testes 1 e 3 falham com `expected 3 to be less than 0.5` e o 2, do emissor sem evento, passa nos dois. O terceiro teste prende a simetria entre os dois ramos, não só os valores, porque foi a assimetria que escondeu o defeito.

**Status:** RESOLVIDO EM PRODUÇÃO. Deploy v4.9.213 validado ao vivo por loop de 1 min (vix-radar-audit): c3 17:43 BRT `ver=v4.9.212`, c4 17:44 `ver=v4.9.213`, estável pós-deploy. `listar_plano_rotina` em v4.9.213: `total:103`, `max_horas:4.7`, `stale>=24h:0`; `Engie _last_scanned_at=2026-08-24T20:47 h_stale:0` (dado recém-gravado reporta 0, não 3h). Timestamps antigos gravados com a 212 (rodada das ~16h, ramo sem_eventos) tinham valor honesto, dentro do limite — não estouram mais o gate.

---

## 24/08 (quarta rodada) — RESOLVIDO: documento do Assaí aparecendo no Pão de Açúcar (SENDASGPA1)

A própria rotina noturna anotou o sintoma no meio da varredura: `Docs CVM do emissor Pão de Açúcar (GPA) têm empresa_cvm=SENDAS DISTRIBUIDORA S.A.`. Sendas é a razão social do Assaí (ASAI3), cindido do GPA (PCAR3) em 2021, e os dois estão na carteira como emissores separados.

**Causa raiz.** `SYNC_ALIAS_TO_EMPRESA` tinha três chaves quase iguais, `SENDAS DISTRIB` e `SENDAS DISTRIBUIDORA S/A` para o Assaí e `SENDAS DISTRIBUIDORA` para o GPA. A do meio está errada desde sempre, mas ficou dormente porque os consumidores antigos varrem a tabela com `for..in` e param no primeiro match, e `SENDAS DISTRIB` vem antes. O resultado saía certo por ordem de inserção, não por acerto. A derivação `SYNC_EMPRESA_TO_ALIASES` do NOMEMORTO1, do mesmo dia, coleta todos os aliases de cada emissor e não tem essa proteção. Foi ela que acordou a contradição.

Na mesma varredura apareceram duas chaves mortas na tabela privada do leitor, a duplicata `ISA Energia Brasil`, e o ACENTOMATCH1 outra vez: as chaves `Itau Unibanco` e `Itausa` estavam sem acento contra emissor acentuado, e o lookup é por chave exata. O fallback sem acento salvava `ITAU UNIBANCO`, mas `BANCO ITAU` ficava perdido.

**Guarda sistêmica.** `scripts/check-alias-coerencia.mjs` reprova alias contido em outro alias apontando para emissor diferente, alias apontando para emissor fora da carteira, e chave do leitor que não é nome de emissor. Entrou em `emissores-cadastro.yml` com injeção do bug real. Prova das duas pontas executada nos três casos.

A lição que passa dos aliases: numa tabela consultada por substring, duas chaves onde uma está contida na outra só podem apontar para o mesmo destino. Se apontam para destinos diferentes, o resultado depende da ordem de iteração de quem consulta, e cada consumidor novo é um sorteio.

**Status:** RESOLVIDO EM PRODUÇÃO, commit `2928a74`, deploy `acf920d` (v4.9.213), validado por loop de 1 min.

---

## 24/08 (quarta rodada) — RESOLVIDO: três defeitos no script da noturna, achados observando a rodada rodar

**CALIB3, calibragem de token 4x alta.** A CALIB2 da manhã de 24/08 saiu da linha `CUSTO:` do log de 23/08, escrita pela sessão do Claude Desktop, que mede o contexto inteiro do subagente. O `$stats.tokens_total` do script mede outra coisa. Comparar número de duas réguas diferentes deferiu 15 emissores à toa às 16h24. Números novos, medidos na régua do próprio script resolvendo o sistema com os dois lotes aprofundados de hoje: Sonnet 11.500 por emissor e boot 14.469, que confirma de forma independente os 15.000 já usados. Haiku 3.800, cobrindo o pior lote observado. A rodada fechou em 390.287 contra teto de 700.000, então o teto não precisa subir. Corrige o que eu havia dito antes, que faltava orçamento.

**ORDEMRAPIDA1, fila rápida não era ordenada por risco.** O comentário do CAPRESERVA1 afirmava que ela já vinha ordenada por EWS desc. Era falso, só a aprofundada tinha `Sort-Object`. Enquanto o cap nunca cortava a rápida ninguém notou, mas no momento em que cortou o corte caiu em quem calhou de estar no meio da lista. Agravante: o cap usava `continue`, então pulou o lote de 15 e deixou passar o de 13 logo atrás. Agora as duas filas ordenam pelo mesmo critério e o cap defere toda a cauda da fila, por fila e não global.

**SHADOWFALSOVERDE1, `parse_fail` lido como concordância.** O `divTag` só distinguia DIVERGE de match, e sem classificação do DeepSeek não há divergência a detectar, então ausência de comparação saía rotulada `match`. Foram 22 de 70 na rodada de hoje, quase um terço do lote. Ausência de comparação agora tem rótulo próprio, `sem_comparacao`.

**Status:** RESOLVIDO, commit `2928a74`. Vale na próxima execução da noturna, não precisa de deploy.

---

## 24/08 (quarta rodada) — ABERTO: fato relevante da Braskem de 24/08 não foi detectado

A Braskem protocolou recuperação extrajudicial em 24/08, reestruturação de US$ 10,9 bilhões, com 90 dias de proteção contra execuções. É o evento de crédito mais material do dia na carteira. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch para RD de 17/08, não o protocolo de hoje.

Consequência prática: o painel continua com 20/08 como fato mais recente. O intervalo 21 a 24/08 é sexta, fim de semana e hoje, dois dias úteis, mas a ausência não é honesta, é falha de detecção com contraexemplo confirmado.

**Duas causas somadas.** O `ipe_cia_aberta_2026.zip` da CVM está em 404 desde 23/08 (CVMURL404), então o gatilho primário de fato relevante não existe. E a busca de imprensa da rotina, sozinha, não alcançou o protocolo do mesmo dia. A Braskem entrou na carteira horas antes da rodada, com `contexto_historico` vazio.

**Status:** ABERTO. Liga direto na decisão pendente sobre fonte alternativa de fato relevante, Dados de Mercado (token pago, API viva) ou adaptador MZiQ (grátis, cobertura não provada).

---

## 24/08 (terceira rodada) — RESOLVIDO: carteira corrigida, AES Brasil sai e Braskem entra (CARTEIRA-24AGO1)

Fechamento das decisões que a guarda de cadastro levantou, mais uma correção de cobertura que apareceu na varredura de fontes.

**AES Brasil saiu.** Foi incorporada pela Auren Energia, que já estava nos 103. Manter as duas contava o mesmo risco de crédito duas vezes e deixava um emissor permanentemente sem evento, porque não existe mais nada para achar. Nenhum registro AES está ativo na CVM, `AES TIETÊ ENERGIA S.A` consta CANCELADA por elisão por incorporação desde 2021. O histórico das semanas antigas fica intacto, ela só deixa de ser varrida daqui pra frente. Os aliases órfãos saíram de `SYNC_ALIAS_TO_EMPRESA` e de `TOKENS_ROBUSTOS_ANBIMA`, e a exceção saiu da guarda.

**Braskem entrou.** `BRASKEM S.A.`, CNPJ 42.150.391/0001-70, ATIVO na CVM. Protocolou fato relevante de pedido de recuperação extrajudicial aprovado pelo Conselho hoje, 24/08 às 09h38, e estava fora da carteira justamente no dia do evento mais material do ano dela. Foi declarada nas três pontas de alias de uma vez, mais o mapa de setor em `Petróleo, Gás e Combustíveis`, que é a lição do NOMEMORTO1 aplicada na entrada do emissor em vez de descoberta nove meses depois.

Total segue 103. Worker em v4.9.212, commit `b13b605`.

**Os outros três ficam, com motivo escrito.** Banco Pan e Banco Votorantim fecharam capital e seguem emissores de dívida sem protocolo IPE. Nexa Resources é de Luxemburgo, listada via BDR, e nunca foi companhia aberta na CVM. Continuam nos 103 e continuam como exceção declarada em `scripts/check-emissores-cadastro.mjs`. Evento deles só vem de imprensa e rating, o que é piso de cobertura conhecido, não falha de ingestão.

### Como a Braskem foi achada, que é o ponto que interessa

Não foi auditando o código. Apareceu enquanto eu media se a Dados de Mercado tinha fato relevante mais novo que o nosso, e o primeiro item da lista pública deles era a Braskem de hoje. Ou seja, a lacuna de cobertura só ficou visível porque olhei uma fonte externa e comparei com a nossa. Vale como método, não como acaso: comparar a carteira contra um agregador de mercado de vez em quando encontra emissor faltando de um jeito que nenhuma varredura interna encontra, porque internamente tudo parece consistente.

---

## 24/08 (segunda varredura) — RESOLVIDO: emissor renomeado ficava cego nove meses (NOMEMORTO1)

Nasceu de uma pergunta do operador. Depois de eu fechar o diagnóstico dizendo que não havia o que fazer do nosso lado, ele insistiu que sempre pegou os dados na CVM e que tinha que ter solução. Refiz a varredura e ele estava certo: parte do buraco nunca foi da CVM.

**O achado.** A Eletrobras virou AXIA ENERGIA em 10/11/2025, tickers ELET3/ELET5/ELET6 para AXIA3/AXIA5/AXIA6. Os documentos dela **estavam gravados** em `cvm:documentos` como `AXIA ENERGIA S.A.` e `AXIA ENERGIA NORDESTE S.A.`, e `buscarDocumentosCVM("Eletrobras")` devolvia zero. Nove meses de emissor exibido com `sem_eventos`, que na tela do cliente se lê como ausência de fato.

**Causa raiz.** Três tabelas de alias que precisavam concordar e não concordavam. `SYNC_ALIAS_NOMES_CVM` decidia se a linha da CVM entrava no KV, `SYNC_ALIAS_TO_EMPRESA` decidia de qual emissor era, e `buscarDocumentosCVM` tinha cópia própria e incompleta para decidir o que procurar. O documento entrava pela primeira, era atribuído pela segunda e sumia na terceira. A Auren só escapou porque alguém lembrou de repetir `CESP` nas três.

**Segundo bug, mesma família (ACENTOMATCH1).** O alias da Sabesp está escrito `CIA SANEAMENTO BASICO ESTADO SAO PAULO` e a CVM publica `CIA SANEAMENTO BÁSICO ESTADO SÃO PAULO`. `String.includes` é literal, então o documento ficava órfão, sem nenhum emissor reclamando.

**Terceiro achado, cruzando os 103 com `cad_cia_aberta.csv`.** Nem `CCR` nem `OMEGA` têm registro na CVM, nem cancelado. Quem existe e está ATIVO é a sucessora: `MOTIVA INFRAESTRUTURA DE MOBILIDADE S.A.` (mesmo CNPJ 02.846.056/0001-97) e `SERENA ENERGIA S.A.`. Nenhum alias declarado para as duas.

**Medido contra o `cvm:documentos` de produção, antes e depois:**

```
Eletrobras        0 -> 28 documentos
Sabesp            0 -> 11 documentos
documentos órfãos 2 ->  1
```

### Correção (Worker v4.9.211, commit `e55d68d`)

- O leitor deriva os termos de `SYNC_ALIAS_TO_EMPRESA` (novo `SYNC_EMPRESA_TO_ALIASES`) em vez de manter cópia. Alias novo passa a valer nas três pontas de uma vez, sem ninguém precisar lembrar.
- Comparação de nome de empresa contra fonte externa é sempre sem acento, dos dois lados, na ingestão e na leitura.
- Aliases novos para MOTIVA e SERENA.
- `admin_documentos_cvm`, somente leitura, responde o que o sistema enxerga para um emissor e com quais aliases. É a observabilidade cuja falta deixou o bug durar nove meses.

### Guarda sistêmica

`scripts/check-emissores-cadastro.mjs` confere os 103 contra o cadastro vivo da CVM. Exceção precisa ser declarada com motivo e data, senão reprova. Roda toda segunda em `.github/workflows/emissores-cadastro.yml`, na nuvem, deliberadamente fora da máquina local, porque o vigia local equivalente foi desligado em 21/08 e a fonte ficou escura quatro dias sem ninguém ver.

O próprio workflow prova as duas pontas. Isso não é zelo decorativo: a primeira versão da guarda **aprovou** um emissor inventado chamado "Ferrovia Fantasma Renomeada", porque o casamento por prefixo de 8 caracteres batia no meio de `FERROVIA CENTRO-ATLANTICA`. Sem a prova do lado ruim, ela teria entrado no repo parecendo funcionar.

### Aberto, decisão do operador

Quatro emissores sem registro ativo na CVM, hoje tolerados com motivo declarado. Nenhum gera documento IPE, então evento deles só pode vir de imprensa e rating. É piso de cobertura conhecido, não falha de ingestão.

- **AES Brasil**, incorporada pela Auren Energia. Fundir com Auren ou remover dos 103.
- **Banco Pan**, fechou capital, `BANCO PAN SA` consta CANCELADA.
- **Banco Votorantim**, sem registro como companhia aberta.
- **Nexa Resources**, companhia de Luxemburgo listada via BDR, nunca foi companhia aberta na CVM. Exceção permanente.

Fica também a pergunta de cobertura levantada na primeira varredura: a Braskem pediu recuperação extrajudicial em 24/08 e não está nos 103.

---

## 24/08 — RESOLVIDO: painel travado em 20/08, fonte da CVM morta em silêncio (CVMURL404)

Sintoma que o operador viu: o painel não mostrava nenhum fato, notícia ou evento depois de 20/08, com hoje sendo 24/08.

**As rotinas não pararam.** Rodaram nos dias 21, 22 e 23, varreram os 103 emissores em todas as noites (`_last_scanned_at: 2026-08-23` nos 103) e submeteram normalmente. O estado da semana W34 em produção tem 154 eventos, 0 pendentes de verificação, e o `data_evento` mais novo é `2026-08-20`. O painel estava dizendo a verdade.

**A causa é a fonte.** Em 23/08 a CVM removeu `ipe_cia_aberta_2026.zip` do servidor. Medido na auditoria: `HTTP 404` no arquivo do ano corrente, listagem do diretório indo só até `2025.zip`, e o catálogo CKAN ainda anunciando o recurso com `last_modified 2026-08-17T08:01:16`. O portal está vivo (`CAD` regenerado em 24/08 04:21 GMT, `ipe_cia_aberta_2025.zip` regenerado em 24/08 08:01). Não é o caso CVMCADENCIA1 de cadência semanal, é queda do arquivo do ano corrente, do lado da CVM. O zip de 2025 não carrega linha de 2026, então não havia fallback pronto em A-1.

Consequência: `cvm:documentos` congelou em `Data_Entrega 2026-08-15`, as rotinas perderam o gatilho primário de evento e a análise passou a reciclar o mesmo acervo de imprensa já conhecido. O volume decaiu antes de zerar, 68 eventos datados de 12 a 14/08 contra 17 datados de 18 a 20/08.

**Por que ninguém viu.** Três camadas falharam ao mesmo tempo. `avaliarFrescorCVM` tratava um 404 duro com a tolerância de 2 ciclos semanais (14 dias) criada para cadência, então `ok` agregado ficou `true` e o `canonical-test` verde. O caminho de erro de `gravarFonteCVMMeta` sobrescrevia a meta inteira e apagava `max_data_entrega`, então o health devolvia `cvm_fonte_idade_dias:null` e nem dava para saber há quanto tempo a fonte estava escura. E o `VIXRadar-Health-Watch`, único canal que alertava em `fonte_externa_ok`, está `Disabled` desde 21/08, um dia depois da fonte congelar. O gate de evento do `frescor-check.yml` só acusaria em 26/08, porque o fim de semana não conta dia útil e o limite é 2.

**Contribuinte secundário.** O cap de token da noturna deferiu a fila APROFUNDADA inteira em 22/08 (19 emissores, entre eles Oncoclínicas, Oi, Raízen, GPA, Light, CSN, Hapvida, Dasa) e 31 emissores em 23/08. Custo real medido em 23/08 é 25,2k por emissor na aprofundada e 12,3k na rápida, contra 13k e 9,5k calibrados. A fila rápida consumia 673k dos 700k e a aprofundada não disparava.

### Correção (Worker v4.9.209 e v4.9.210, commits `c0167cd`, `1572279`)

- **CVMURL404**: o ano do ZIP sai do relógio BRT em vez de cravado no código, que também consertava um bug latente de virada de ano, e em 404 a URL é reperguntada ao catálogo CKAN. Não resolvendo em nenhuma via, motivo `fonte_ausente_no_catalogo`.
- **CVMMETAWIPE1**: `gravarFonteCVMMeta` faz merge no caminho de erro, preserva `max_data_entrega` e `last_modified_iso`, e passa a contar `falhas_consecutivas` e `ultimo_sync_ok_em`. Como o wipe do incidente aconteceu antes do fix subir, o v4.9.210 acrescentou fallback que deriva a idade de `cvm:documentos` quando a meta de falha não tem data nenhuma.
- **CVMDURA1**: falha dura (`http_4xx/5xx`, exceção, arquivo ausente, ZIP inválido) derruba `fonte_externa_ok` na hora e escala para o `ok` agregado após `CVM_FONTE_MAX_FALHAS = 4` syncs falhos seguidos, ou seja 2 dias de crons. `CVM_FONTE_MAX_CICLOS` continua sendo o dono do caso "arquivo presente e velho".
- **VOLTTL1** aplicado a `cvm:documentos`: TTL de 14 para 30 dias, porque a chave só é reescrita em sync bem-sucedido e o lote útil da CVM é semanal.
- **CAPRESERVA1 e CALIB2** em `run_vixradar_noturno_claude.ps1`: reserva de orçamento para a fila aprofundada calculada antes do primeiro token, e calibragem pelo custo medido. A fila rápida continua rodando primeiro, porque inverter a ordem já zerou o Haiku em 09/07, mas agora bate num cap reduzido.
- **Alerta**: `frescor-check.yml` passa a checar a fonte e nomear o campo específico (HEALTHWATCH3), rodando na nuvem sem depender do Health-Watch local.

### Causa raiz e guarda

Causa raiz: o sistema tratava "fonte respondeu velho" e "fonte não respondeu" como o mesmo evento, medidos pela mesma régua de 14 dias. A régua estava certa para o primeiro caso e cega para o segundo. Somado a isso, o único alerta que cobria a fonte tinha sido desligado 2 dias antes por outra razão, e o caminho de erro destruía a evidência necessária para diagnosticar.

Guarda sistêmica: 8 testes novos em `api/test/cvm-frescor.test.mjs` travando o contrato nas duas pontas, falha dura reprovando e sync bom aceitando; bloco novo no `frescor-check.yml` que roda diário na nuvem e cita o campo; escalada automática para o `ok` agregado, que reacende `canonical-test` e `daily-status-email` sem depender de máquina ligada.

### Aberto, decisão do operador

A CVM ainda não repôs `ipe_cia_aberta_2026.zip`. Enquanto não repuser, a ingestão de Fato Relevante segue parada e os eventos dependem só de imprensa e RAD. Escopo decidido nesta sessão: **não construir fonte de ingestão nova**, detectar e alertar. Quando a CVM repuser, o sync volta sozinho. Se passar de 4 syncs falhos, o `ok` agregado cai e o alerta dispara.

**Adendo 25/08, sem apagar o diagnóstico acima — a fonte voltou.** O log da noturna de 25/08 registra `cvm_fonte_ok=true cvm_idade_dias=0`, e o relatório da rodada confirma `cvm_fonte_idade_dias:0, last_modified 25/08, falhas_consecutivas:0`. A CVM repôs o ZIP do ano corrente; o sync voltou sozinho, como previsto neste bloco, e a ingestão de Fato Relevante está ativa de novo. Nenhuma correção nossa foi necessária, só a detecção e o alerta que já existiam. O item CVMURL404 fecha por resolução externa.

---

## 24/08 (continuação) — RESOLVIDO: 2 fixes órfãos em worktree resgatados (WORKTREE12)

Das 6 worktrees do Claude Code, 4 eram checkout parado (BOM removido + caminho revertido para o legado `FREQUENTE\`, mesmo commit `e7f70d1` nas 4, sem nada de valor, removidas). As outras 2 tinham trabalho real nunca commitado, extraído a mão porque os arquivos-base já tinham divergido de `main` desde que as worktrees pararam de ser atualizadas.

### RETRY-PROP1 — validação pós-deploy falso-negativa em propagação lenta da borda

`deploy-worker.ps1` abortava com sleep fixo de 4s + tentativa única quando a propagação da Cloudflare demorava mais que isso. Incidente real no deploy do v4.9.196: produção já respondia a versão nova ~8s depois do script já ter abortado com `wrangler.toml` sujo e sem commit. Corrigido na worktree `quizzical-nightingale-0c534b` (base `6011d9a`), que não conhecia os gates HEALTHSPLIT1/CVMCADENCIA1 que entraram em `main` depois (`9b017af`). Fundido a mão em cima do `main` atual, não copiado por cima, os dois pontos não se sobrepõem no arquivo. Retry com backoff (60s, passo de 5s) substitui o sleep fixo, e `Fail-PosDeploy` documenta o caminho de recuperação explícito (commit manual ou `git checkout` do toml) em todo ponto de falha depois do passo 4 já ter tido sucesso, inclusive nos gates HEALTHSPLIT1/CVMCADENCIA1. Parse PS 5.1 e `lint-encoding.ps1` limpos. Commit `604c600`.

### ROTINA_RESUMO — 2 rotinas que faltavam no retrofit de 21/08 (ORF3D593D6)

O cherry-pick de 21/08 (ver `RESOLVIDO 21/08 (ORF3D593D6)` no `ESTADO.md`) trouxe a linha `ROTINA_RESUMO` pra matinal/noturno/coleta-volatilidade/export-historico/reconciliação-cvm, mas o commit original (`3d593d6`) tinha working tree com mais 2 arquivos nunca commitados: `run_vixradar_ranking_mensal.ps1` e `run_vixradar_verificacao_async.ps1`, esta última ainda ativa no Task Scheduler do Claude Desktop. Extraído da worktree `interesting-brahmagupta-4a7254`, reaplicado a mão porque `main` tinha divergido nos dois arquivos desde então (`82f5a0d`, migração de caminho canônico, 1 linha cada, sem sobreposição com os pontos de inserção do log). Parse PS 5.1 e `lint-encoding.ps1` limpos.

Achado no caminho, **não corrigido** por estar fora do escopo desta extração: `run_vixradar_ranking_mensal.ps1` linha 20 usa `$ErrorActionPreference = 'Stop'`, o mesmo anti-padrão que o `CLAUDE.md` documenta como causa de perda silenciosa de exit code no Task Scheduler (`adc9dbf`, `run-daily-scan.ps1`). Risco reduzido, a tabela de rotinas do `CLAUDE.md` marca `VIXRadar-Ranking-Mensal` como **OBSOLETO**, task não existe mais no Scheduler, então não há disparo agendado pra engolir o erro. Fica como pendência caso a rotina volte a ser agendada.

As duas worktrees removidas depois do commit. `3d593d6` (branch `claude/interesting-brahmagupta-4a7254`) e `2317dcd` (branch `claude/quizzical-nightingale-0c534b`) seguem alcançáveis pelos branches, só o diretório de trabalho saiu.

---

## 24/08 — RESOLVIDO: auditoria geral readonly, nucleo sem achado

Auditoria `vix-radar-general-audit` (`[[90 - Auditoria Geral 2026-08-24]]`). Portão de produção 200 com `ok:true` completo. Veracidade da UI batendo com o glossário nos 3 termos reservados (Emissores/Críticos/Relevantes + Sem alertas com janela declarada). Auth fail-closed nos 3 probes (state 401, receber_analise 403, login 401 genérico). Drift zero: prod v4.9.208/v202.30 = HEAD, os 317 arquivos "modificados" são só CRLF (`git diff -w` = 0). Nenhum P0/P1/P2 novo.

Observações (não reprovam o portão):
- **Fonte `CVM CIA_ABERTA/DOC` intermitente** — `fonte_externa_ok:false`, `cvm_fonte_motivo:ultimo_sync_falhou:http_404`, `ciclos_perdidos:null`. É fonte SEMANAL (domingos), domínio CVMCADENCIA1. 24/08 = segunda pós-domingo sem lote pode ser cadência, não incidente. Confirmar contra ramos `INF_DIARIO`/`CAD` antes de abrir qualquer coisa.
- **`main` local ahead 2 de `origin`** — só os `chore(data): historico 2026-08-22/23`. Push na próxima sessão.

---

## 22/08 (madrugada BRT) — RESOLVIDO: auditoria geral readonly e fechamento dos achados

Auditoria `vix-radar-general-audit` completa (detalhe: [[89 - Auditoria Geral 2026-08-22]]). Núcleo sem achado: auth fail-closed, veracidade da UI batendo com o glossário, drift zero, health verde completo. Itens novos abaixo.

### P3 — DATAATUALIZACAO1: painel confundia último evento com atualização da base — RESOLVIDO 22/08

Em 22/08, a tela declarava “Evento mais recente 20 de agosto”, embora a rotina de 21/08 tivesse concluído 103/103. A ausência de fato novo em 21/08 era legítima, mas o painel não dizia quando a base havia sido atualizada. **RESOLVIDO 22/08, deploy v202.30.** O carimbo agora mostra “Painel atualizado em [data e hora BRT]” e preserva a data independente do último evento.

### P3 — WRCGL1: changelog do wrangler.toml parado em v4.9.195 — RESOLVIDO 22/08

O cabeçalho do `api/wrangler.toml` declara `main = v4.9.195` na linha 2 e a última entrada de changelog é v4.9.195. O `main` real é `v4.9.208.js`. Zero entradas para v4.9.196 a v4.9.208. A verdade do deploy (main + bundle) está certa, mas o changelog-como-verdade que a skill de auditoria usa não registra 13 versões. Evidência: `rg "v4\.9\.20[0-9]" api/wrangler.toml` retorna 1, só o main. O `deploy-worker.ps1` não tem nenhuma menção a changelog, ou seja, nada reprova subir versão sem entrada. **RESOLVIDO 22/08, commit `9b017af`.** Treze entradas escritas, reconstruidas dos commits de git e desta fila. Gate novo no `deploy-worker.ps1` reprova deploy sem entrada de changelog para a versao que sobe.

### P3 — PULSOEVENTO1: pulso do Market Overview chama emissor de evento — RESOLVIDO 22/08

`app/index.html:4173`. O ramo crítico do pulso diz "Mercado com N emissores sob atenção crítica" (certo), o ramo relevante diz "N eventos relevantes em acompanhamento" contando `relevantesAtivos`, que é Set de EMISSORES. Termo reservado do glossário com grandeza trocada, irmão pequeno do ROTULOEVENTO1. **RESOLVIDO 22/08, deploy v202.29.** Pulso agora diz "N emissores em acompanhamento", confirmado no HTML servido em producao.

### P3 — JANELACARD1: card "Sem alertas" sem declaração de janela — RESOLVIDO 22/08

`app/index.html:4181`. O sub declara denominador ("X de Y emissores") mas não a janela fixa de 30 dias. O glossário manda declarar, ainda mais por estar ao lado do toggle 7D/30D que não o afeta. O fix de 14/08 (v202.9) dizia incluir "· 30 dias" e a string final não tem. **RESOLVIDO 22/08, deploy v202.29.** Sub do card diz "X de Y emissores · 30 dias", confirmado em producao.

### P3 — ESTADOSTALE1: seção "Versoes" do 03-Estado Atual parada em v4.9.194/v202.9 — RESOLVIDO 22/08

`03 - Estado Atual.md:159-161`. Topo do arquivo já declara v4.9.208/v202.28. Mesmo padrão de rodapé que não acompanha, reconciliado em 11/08 e voltou. **RESOLVIDO 22/08.** Seção atualizada para v4.9.208/v202.29/git `02c2157`.

### P3 — WORKTREE22: working tree sujo da sessão de 21/08 — RESOLVIDO 22/08

MOC + ESTADO modificados, notas [[87 - Fechamento Rotinas 2026-08-21]] e [[88 - Sessao Frontend Mobile 2026-08-21]] untracked, `main` ahead 1 de `origin/main` (`50384b3`, dado do historico). **RESOLVIDO 22/08.** Commits `9b017af`, `afbdc46`, `69a64dd`, `02c2157` enviados, main em sincronia com origin/main.

### P3 — DEPLOGGATE-JSON1: falha em gate do deploy-pages deixa version.json carimbado — RESOLVIDO 22/08

Observado em 22/08: gate 3.2 reprovou o deploy, mas `app/version.json` ficou com `deployed_at` do passo 2 sobre uma publicação que não aconteceu. **RESOLVIDO 22/08.** O passo 2 agora grava `deployed_at:null` durante o sync e todos os gates. O carimbo real nasce somente no passo 4, imediatamente antes do Wrangler. Se o envio falhar, DEPLOYTS1 volta o valor para `null`.

### Observação de design, não achado — DPA2SEMANAS1

`dados_para_analise` usa `carregarEstadoMultiSemana(env2222, 2)` (`worker.js:17473`). O contexto histórico entregue à rotina cobre só 2 semanas, eventos de 15 a 30 dias ficam invisíveis para o modelo. A dedup do Worker (data_evento|empresa|fonte_base) mitiga re-narração. Registrar, não mudar sem decisão do operador.

---

## 20/08 (19h20 BRT) — RESOLVIDO: 2 P1 de segurança, 6 P1 de perf/a11y, dívida de docs

Segunda janela do dia, depois da reabertura para clientes. Auditoria dos blocos D,
E e F mais a rotina noturna. Nada foi deployado, decisão do operador: mudança de
autenticação sobe com ele presente. Commits `810dc2c`, `6d657f8`, `806f2c7`.

**REGISTRO-ADMIN1 (P1, corrigido).** `handleRegistrar` derivava autoridade do
e-mail no corpo da requisição, que nunca é verificado. `isAdmin` comparava com
`ADMIN_EMAIL` e a conta nascia `aprovado` + `white_label`, e como `handleLogin`
calcula `roleFinal` pelo mesmo e-mail, quem soubesse o endereço do admin
registrava com senha própria e recebia JWT de admin sem nunca saber a
`ADMIN_PASSWORD`.

A contenção era acidental. Só o early return de `status === "aprovado"` barrava o
`putUser`. Com a conta ausente, ou com status `rejeitado`, que não tem early return
e cai no `putUser` sobrescrevendo o `senha_hash`, o vetor abria. Lido no KV de
produção: a conta existe como `aprovado` desde 04/04, então estava fechado por
estado e não por código.

Registro passa a nascer sempre pendente. A via legítima não muda,
`handleAdminAutoLogin` segue criando e aprovando a conta admin, gateado por
`admin_senha === env.ADMIN_PASSWORD`. A autoridade saiu do e-mail e ficou no
secret. Teste de regressão em `api/test/registro-admin.test.mjs`, provado nos dois
sentidos: com asserts do comportamento antigo, os dois falham, login devolve 401
em vez de 200.

**RATELIMIT-FAILOPEN1 (P1, corrigido) e AUTHDISPO1 (decisão do operador).** Os
três bypass de `checkRateLimitV2` devolviam `allowed:true`, então a queda do
binding apagava o rate limit de tudo, inclusive varredura que gasta LLM por
chamada. Criticidade agora é explícita, default `"critica"` fail-closed.

O `AUTHDISPO1` é a parte que exigiu decisão. Fechar tudo trocaria brute force por
indisponibilidade de login para cliente pagante, e o `catch` de `do_erro` pega
qualquer exceção, inclusive timeout transitório. O gate de auth separa os dois
casos que cobre: senha admin errada fecha (o operador com a senha certa pula o
check antes), login de cliente comum abre com `console.error` e telemetria
`rl_bypass_auth`, para o incidente ser curto e visível.

**A11YCONTRASTE1 e mais 5 P1 de frontend (corrigidos).** Contraste WCAG com três
substituições sistemáticas, `#6b7280` e `#64748B` para `#94A3B8`, `#374151` para
`#7C8C9E`. O pior valor antigo era 1,74:1 em texto de 9 a 14 px, contra o mínimo
de 4,5:1. As cores novas dão 5,57:1 e 6,17:1 calculados pela fórmula. Junto:
guard de aba oculta nos timers (o `_v201Poll` batia na API a cada 60 s para
sempre em segundo plano), debounce nos dois filtros de texto, navegação por
teclado nos clicáveis que eram `div` com `onclick`, informação não cromática no
`sev-dot` da sidebar, e `aria-live` onde não havia nenhum.

**Dívida de documentação (corrigida).** A causa raiz do "vitest não roda" estava
errada há tempo: culpava Smart App Control bloqueando `workerd.exe`. Medido,
`VerifiedAndReputablePolicyState=0`, SAC desligado, nenhum evento de CodeIntegrity
menciona workerd. A causa real é `npm ci --omit=dev` no deploy apagando as
devDeps. Com `npm ci` em `api/`, a suíte roda: 8 arquivos, 44 testes.

Junto: `worker.js` tem 18.597 linhas e não 17k, a migração v3 não está em
`wrangler.toml:561`, o gate de working tree confere 4 arquivos e não a árvore
inteira, o ponteiro do `AGENTS.md` apontava para arquivo não versionado, e a regra
de `.gitignore` para `setup-deploy-credential.ps1` era ilusória porque o arquivo é
trackeado desde `201ebda`.

### Abertos desta janela

**MANIFESTOFRAGIL1 (P3).** O `status/allclear-manifesto.json` indexa cada frase de
ausência junto com o HTML e o estilo inline. Trocar `color:#6b7280` por `#94A3B8`
fez duas frases idênticas aparecerem como NOVAS e reprovarem a guarda. Falso
positivo de segurança, mas fragilidade real: qualquer mudança de CSS quebra o
manifesto e obriga atualização manual. **Pronto quando** a chave for derivada só do
texto visível, sem estilo nem tag.

**DEDUPON2 e FEEDRERENDER1 (P2, diagnosticados, fora de escopo de propósito).** O
`_isDupSemantico` deduplica O(n²) sobre todos os eventos, no boot e em todo
refresh, com `normalize('NFD')` mais cascata de regex por evento. E o
`_v201Refresh` reconstrói 30 dias de feed a cada evento novo, cada card com cerca
de 13,8 KB de string HTML. Os dois são reais e medidos, mas exigem refactor com
risco de regressão. **Pronto quando** houver janela dedicada, não colada no fim de
outra.

**ORF3D593D6 (P2).** O commit `3d593d6`, que padroniza a linha `ROTINA_RESUMO` em 5
rotinas locais, nunca chegou ao remoto. Vive só na branch
`claude/interesting-brahmagupta-4a7254`. Testado: aplica limpo nos 5 scripts,
conflita apenas em `status/ESTADO.md:75`, porque 13 commits desde 18/08 reescreveram
o parágrafo vizinho. O trabalho segue relevante, o `ESTADO.md:262` registra o
retrofit como P2 aberto. **Pronto quando** o cherry-pick for feito e a branch
apagada.

**SACFALSA-RESIDUO (P3).** **RESOLVIDO 24/08.** Correção: a causa falsa do Smart App Control foi substituída pela causa real nos 3 arquivos vivos que a carregavam, `api/test/agenda-validacao.test.mjs:8`, `scripts/test-frescor-cvm.mjs:3` e `status/ESTADO.md:292` (que contradizia a própria linha 321, já refutada por medição em 20/08). Causa raiz: a crença de que o vitest não rodava por Smart App Control nasceu sem medição e gerou artefatos de código e de documentação que se propagaram por comentários, teste e estado vivo; a medição de 20/08 (VerifiedAndReputablePolicyState=0, nenhum evento CodeIntegrity cita workerd) refutou a premissa, mas a correção havia sido aplicada só no `worker-tests.yml` e numa linha do ESTADO, deixando resíduos. O `test-frescor-cvm.mjs` foi mantido porque cobre o cálculo de dias úteis em Node cru (31 casos) sem subir Worker. Guarda: gate no `scripts/hooks/pre-commit` reprova o blob em staging contendo "Smart App Control" fora de `Obsidian VIX Radar/` e `docs/archived/`. As notas de auditoria datadas (82, 85) e entradas antigas deste arquivo ficam intactas como registro histórico.

**WORKTREE12 (P3).** Doze worktrees registradas, incluindo de Codex e Traycer, e
seis commits nunca empurrados. Cinco são duplicata ou ancestral já absorvido, um é
o ORF3D593D6 acima. É a fábrica de commit órfão do projeto. O Bloco E propôs um
hook `pre-push` que aborta quando `HEAD..origin/main` não está vazio, o que pegaria
o caso do commit sanduichado de hoje. **Pronto quando** o hook existir e as
worktrees mortas forem podadas.

### Rotina noturna do dia

103/103 no ledger, zero falha de submit, zero silent fail, zero faltante de parse,
1 degradado para INCONCLUSIVO pela guarda de cobertura (B3 S.A., zero buscas
efetivas). Distribuição: 43 NENHUM, 27 ECO, 27 RELEVANTE, 5 CRÍTICO.

### Deploy do dia, com o operador presente

Subiu em 21/08 01h35: Worker v4.9.207 (REGISTRO-ADMIN1, RATELIMIT-FAILOPEN1,
AUTHDISPO1) e Pages v202.20 (contraste, aba oculta, debounce, teclado, aria-live).
O gate 3.4 reprovou duas vezes antes de publicar, desalinhamento do `?v=` nos
módulos admin (o CACHEBUMP1 de novo) e version.json sujo de tentativa anterior, e
abortou sem publicar nas duas. Validação pós-deploy colada no ESTADO.md.

### AUTONOMIAOFF1, decisão do operador

O operador mandou remover toda verificação autônoma do frontend que não esteja
cadastrada no sistema. Em 21/08 01h40 saíram os quatro timers que consultavam o
servidor: rate meter a cada 2 min, auto-update a cada 3 min, anomalias a cada 30
min e status da ribbon a cada 60 s. Também saiu o loop do watchdog local, que era
stub vazio. Restaram só timers locais sem rede (relógio, merge de anomalias
pre-carregadas, contagem regressiva), a carga inicial e os gatilhos de evento do
usuário (visibilitychange, pageshow, clique). Frontend em v202.21. A regra foi
escrita no CLAUDE.md para não voltar num refactor.

Críticos: Hapvida (cautelar da ANS barrando reajuste e rescisão em 947 mil
contratos), Oncoclínicas (recuperação extrajudicial deferida), Oi (gestor judicial
alerta caixa de R$ 19,6 milhões), Kora Saúde (AGDs reestruturam escritura da 2ª
emissão), CSN (Fitch rebaixa para CCC+).

A rodada R7, que entrou como cobertura preventiva sem caso comprovado, produziu o
primeiro achado real: Cade aprovando a aquisição de 30% da Copasa pela Equatorial,
mudança de controle em saneamento, vocabulário que R2 e R6 não alcançam.

Anotação de conformidade: 3 emissores da fila aprofundada (Rumo, Simpar, Dasa)
vieram ECO com 1 evento, e a skill especifica `eventos=[]` para ECO e NENHUM.
Direção segura, evento registrado com classificação conservadora. Zero casos do
inverso, que seria CRÍTICO ou RELEVANTE sem evento.

---

## 20/08 (21h15 BRT) — RESOLVIDO: janela de manutenção, 7 P0/P1 de veracidade de UI + SPREADSERIE1

Continuação da auditoria de 17h00. Worker foi de v4.9.203 a v4.9.206, frontend de
v202.12 a v202.19, 30 commits. Achados e correções, do mais grave ao mais leve:

**SPREADSERIE1 (P1).** A série `mercado:serie:*` atravessa uma troca de provedor
em abril sem tratamento: pontos legados em ponto-base (Oi 8873) misturados com
pontos `anbima_publico` em percentual (Oi 9,75) no mesmo cálculo estatístico.
`anbima:zscores` saía com 71 dos 73 emissores no mesmo `z_spread` de -0,55, sinal
sem sentido. Corrigido com corte por `fonte` antes de qualquer estatística
histórica, aplicado em `calcularZScoresANBIMA`, `handleSerie` e
`detectarAnomaliasEmpresa`. Campo renomeado para `taxa_indicativa_pct`, com
`spread_bps` mantido como alias por leitura dupla. Confirmado: não chega à tela
do cliente nem a e-mail, é lab interno.

**ZEROINDISPONIVEL1 (P0), a classe de bug do dia.** Cinco superfícies diferentes
tratavam "não consegui ler o dado" como "medi zero", afirmando saúde da carteira
sem nunca ter lido a base:
- painel EWS da home pública dizia "Todos os emissores monitorados estão dentro
  dos parâmetros normais" com `ewsRankingCache === null`;
- pulso do monitor operacional ficava verde com "Mercado em estabilidade" com
  `resultados` vazio;
- briefing e painel de eventos diziam "Nenhum alerta de mercado ativo" a partir
  de um detector que nunca dispara (ANOMSCHEMA1, ver abaixo);
- painel ANBIMA tinha check verde "Nenhuma anomalia detectada" mesmo com zero
  debêntures analisadas na amostra;
- os 5 `mo-card` do monitor (Críticos, Relevantes, Sem alertas) calculavam
  `(103-0-0)/103*100 = 100%` com chip verde quando `resultados` vazio, mesmo
  depois do pulso ao lado já ter sido corrigido para dizer "sem leitura".

Todos os cinco corrigidos com a guarda `_semLeitura` (ou equivalente no Worker,
`detector_operacional`), confirmados ao vivo em produção via CDP numa sessão
autenticada real. Achado real medido nessa sessão: 6 a 7 eventos críticos e
42 a 54 relevantes em 25 emissores na janela de 7 dias úteis, muito longe do
"tudo normal" que a home pública afirmava até esta rodada.

**SPREADUNIDADE1 (P0, rodada anterior, confirmado ao vivo nesta).** Card do
painel do emissor dizia "Spread ANBIMA ... bps" sobre taxa indicativa em % a.a.
Confirmado com dado real em produção: Oi mostrando "9.75% a.a." depois do fix,
não mais "9,75 bps".

**BANNERMORTO1 (P3).** Os 6 tipos de aviso ao usuário (erro_worker,
erro_conexao, dados_desatualizados, sem_chaves, sem_perplexity, sem_gemini)
nunca renderizavam, `style="display:none"` inline vencia a regra de CSS.
Corrigido, os 6 provados um a um em produção com prova de DOM (`display:block`,
altura 30px).

**ROTULOEVENTO1 (P2).** Cabeçalho do painel dizia "6 críticos" contando EVENTO
ao lado de "25 emissores com sinal" contando EMISSOR, mesmo termo do glossário
("Críticos") usado com grandeza diferente lado a lado. Corrigido para "N eventos
críticos (7d)".

**MOJIBAKEORIGEM1 (P3, rodada anterior).** `Get-Content` sem `-Encoding` no
`collect_cotacoes.ps1` corrompia nome acentuado, escondido em produção pelo
`Repair-Mojibake` do uploader mas causava diff falso em auditoria.

**Guarda sistêmica desta rodada.** `scripts/check-frontend-allclear.mjs`
substituiu a versão de 3 frases fixas por varredura de toda frase de ausência do
arquivo (57 encontradas), com manifesto versionado
(`status/allclear-manifesto.json`) e guardas amarradas por regex a frase
específica, não OR cego. Provado nos dois sentidos com 3 cenários de regressão
sintética. `scripts/audit-ui-live.mjs` substitui a inspeção por regex
(`audit-ui-metrics.mjs`, que só via 5 métricas) por inventário do DOM ao vivo via
CDP contra sessão autenticada real, com baseline versionado
(`status/ui-baseline.json`, 62 superfícies). Foi essa ferramenta que achou o
ROTULOEVENTO1.

**Rollback.** `_backup-janela-20260820/ROLLBACK.md` documenta o procedimento e
tem export de 6 chaves KV + 78 séries de mercado, tirado antes da janela. Não
versionado, fica só no disco local.

**Não executado nesta sessão, ordem original do operador previa isso para depois
da reabertura:** Bloco D (segurança do Worker, performance, acessibilidade,
OWASP LLM Top 10), Bloco E (TICKERPERIMETRO1 classificado, ANOMSCHEMA1
corrigido, CACHEBUMP1 automatizado, varredura do CLAUDE.md, revisão do commit
`a4a0b47` de sessão paralela), Bloco F (documento de decisão FONTELATENCIA1 e
DRIVERMORTO1, sem implementar). Seguem na fila abaixo, sem mudança de status.

---

## 20/08 (17h00 BRT) — ABERTO: fila da auditoria geral, com tag e critério de pronto

Tudo que a auditoria de 20/08 diagnosticou e **não** consertou. Cada item fecha com
o critério de pronto explícito, para a próxima sessão não precisar redescobrir o
escopo. Os itens resolvidos na mesma sessão estão na entrada de baixo.

### P1 — TICKERPERIMETRO1: mapa de tickers com perímetro errado, bloqueia market_cap

`data/cotacoes/tickers_emissores.json` declara 94 emissores listados para um universo
de 103, número alto demais para uma carteira de crédito privado. O próprio arquivo se
contradiz, o `_descricao` diz "Apenas emissores listados com capital aberto" e o
`_nota` diz "~68 dos 103 emissores são listados". Uma das duas está velha.

Pior que a contagem, há entradas apontando para entidade diferente da emissora.
`Compass Gás e Energia` aponta para `CMPC3.SA`, que é de outra companhia. `MRS
Logística` usa `MRSA6B.SA`, papel de balcão sem liquidez de tela. `Itaúsa` com
`ITSA4` é holding pura, enquanto quem emite dívida no grupo é o banco. `Compass` é
subsidiária da Cosan, que já tem `CSAN3` no mesmo mapa. Não fiz a classificação
completa das 94 entradas e não afirmo contagem que não apurei.

Isso é **pré-requisito bloqueante** de qualquer coleta de `market_cap` para Merton.
Com perímetro trocado, Merton mede equity da mãe contra dívida da filha e entrega
número plausível e errado, que é pior que o `null` de hoje.

**Pronto quando:** as 94 entradas estiverem classificadas uma a uma como emissora
própria, controladora ou relacionada, com a fonte da classificação registrada; as
relacionadas removidas ou marcadas como inelegíveis para Merton; e o `_nota`
reconciliado com o `_descricao`.

**RESOLVIDO 21/08, commit `bae552b`.** As 95 entradas (94 mais a Cielo, que faltava)
estão classificadas uma a uma com fonte no próprio arquivo. 91 elegíveis, 4
inelegíveis. Correções apuradas: Compass usa PASS3 desde o IPO de maio/2026 e não
CMPC3, MRS é balcão sem liquidez, Itaúsa é holding, Omega virou Serena e deslistou,
Iguá não negocia. Coleta de `market_cap` para Merton fica destravada, mas o pipeline
de coleta em si continua sendo o próximo passo do DRIVERMORTO1.

### P2 — DRIVERMORTO1: 3 dos 6 drivers do score nunca produziram valor

Diagnóstico real de cada um, corrigindo o que a sessão anterior tinha suposto.

`merton` está `null` nos 103 emissores em todos os exports desde 11/07/2026. O gate
em `worker.js:14074` exige `mktCap`, e nem `fundamentals:altman:latest` (DFP da CVM,
balanço puro, 0 ocorrências de `market_cap` em 99 empresas) nem
`cotacoes:volatilidade:v1` (que se recusa a publicar preço por ação como market cap,
de propósito e com razão) fornecem. Bloqueado por TICKERPERIMETRO1.

`momentum` exige `velocity_delta >= 2` sobre a série `ews:hist:{empresa}`. As 103
chaves existem, mas o conteúdo é raso e plano. `ews:hist:oi` tem 3 pontos, 18, 19 e
20/08, todos com score 66. A série só começou em 18/08, quando o HISTFLAT2 consertou
o casamento de chave em minúsculo. Duas causas somadas, série curta demais para
janela de 7 dias e score preso no piso estrutural.

`mercado` exige `spread_score >= 10`, que vem de `spreadScoreDeAnomalias` lendo
`mercado:anomalias:ativas`. Essa chave em produção tem 4 bytes, `{}`. Não é falta de
código nem de dado, ver ANOMSCHEMA1 logo abaixo.

Atenuante que baixa a severidade, `predictive_v1` é lab interno (`user_facing:false`)
e não chega à tela do cliente.

**Pronto quando:** cada um dos 3 estiver com fonte de dado no ar e cobertura maior
que zero medida por `scripts/check-drivers-preditivos.ps1`, **ou** removido do
`scorePreditivoRuleV1` e da lista `DRIVERS_DECLARADOS` do mesmo script. Driver
declarado que nunca dispara faz o modelo parecer mais rico do que é.

### P2 — ANOMSCHEMA1: detectores de anomalia desalinhados com o schema anbima_publico

`recalcularTodasAnomalias` tem escritor, tem 8 call sites e roda por cron
(`worker.js:17751` e `17800`). A entrada existe, 78 chaves `mercado:serie:*` frescas.
Ainda assim o resultado é `{}`, e são dois motivos empilhados.

Três dos quatro detectores são estruturalmente impossíveis com a fonte atual. O de
volume exige `ultimo.volume != null`, o de iliquidez lê `negocios` e `volume`, o de
concentração lê `maior_negocio`. Nenhum desses campos existe no registro
`anbima_publico`. Existiam na fonte antiga, o export de série ainda mostra registros
de março de 2026 com `volume:2628917` e `negocios:16`. A fonte trocou de provedor e
os detectores nunca foram adaptados.

O quarto, de spread, morre por unidade. O código faz
`deltaPP = Math.abs(ultimo.spread_bps - media) / 100` contra `SPREAD_LIMIAR_PP: 1`.
Com Aegea variando de 4,51 para 4,53, o delta é 0,0002 pontos percentuais contra
limiar de 1. Precisaria de variação de 100 unidades de um dia para o outro. E como o
SPREADUNIDADE1 mostrou, o campo carrega percentual, não ponto-base, então o `/100`
está errado por construção.

**Pronto quando:** os 3 detectores sem campo estiverem desligados explicitamente ou
reescritos para o schema `anbima_publico`; o de spread recalibrado para a unidade
real; e existir teste que reprove se `mercado:anomalias:ativas` ficar `{}` por N dias
consecutivos com séries frescas no KV.

**RESOLVIDO 21/08, commit `5283636`, em produção v4.9.208.** Os três detectores sem
campo ficaram marcados como desligados de propósito, o de taxa indicativa compara em
ponto percentual direto, sem o `/100` herdado do provedor antigo. Teste novo em
`api/test/anomalias-schema.test.mjs` semeia a série no formato real da fonte e exige
que um salto de 2,75 p.p. dispare, o que falharia contra o código antigo. A parte do
vigia que faltava, alertar `mercado:anomalias:ativas` vazio com séries frescas, fica
registrada como MELHORIA futura no `check-drivers-preditivos.ps1`, não bloqueia.

### P2 — SPREADUNIDADE1 (resíduo): renomear o campo e corrigir os consumidores restantes

A parte P0 foi corrigida hoje, ver entrada de baixo. Sobra o que é migração.

O campo no KV continua se chamando `spread_bps` guardando taxa indicativa em % a.a.
Renomear é migração de chave em 78 séries mais o parser mais o endpoint `op=serie`.
O card de anomalia do frontend ainda concatena `spread_atual_bps + " bps"`, hoje
inócuo porque `mercado:anomalias:ativas` é `{}`, mas volta a mentir junto com o
ANOMSCHEMA1. O dataset de DEMO tem `spread_atual_bps:387` e `612`, valores em bps
reais e internamente coerentes, que ficam como estão.

**Pronto quando:** o campo tiver nome que diga a grandeza e a unidade, todos os
consumidores acompanharem, e o card de anomalia não puder ressuscitar com o sufixo
errado.

### P2 — PUBDATA1: data_publicacao_fonte nunca foi populado

Medido nos 74 eventos vivos do estado da semana W34: `data_evento` preenchido em
74/74, `data_publicacao_fonte` preenchido em **0/74**. O campo existe no schema desde
sempre e nunca recebeu valor. Sem ele não dá para ordenar por "apareceu agora", só
por data do fato, que é outra coisa.

**Pronto quando:** o pipeline preencher o campo no `receber_analise` e a taxa de
preenchimento passar de 80% numa amostra de 30 dias.

### P3 — FEEDNOVIDADES1: aba Novidades, parada por decisão

Aprovada em conceito e adiada de propósito. Depende de PUBDATA1, senão a aba nasce
ordenando por data do fato com cara de ordenar por novidade. A ordenação atual do
feed é severidade primeiro e data só como desempate
(`{CRITICO:0,RELEVANTE:1,ECO:2}` e `localeCompare` no desempate), o que prende o topo
da tela no cluster de resultados do 2T26 até ele sair da janela de 30 dias.

**Pronto quando:** PUBDATA1 fechar e o aviso de frescor (entregue hoje) tiver rodado
uma semana em produção sem reclamação.

### P3 — FONTELATENCIA1: fonte de baixa latência é decisão de produto

O ramo `CIA_ABERTA/DOC` da CVM é semanal e publica aos domingos. Isso é lento demais
para monitoramento de crédito, e o caso Casas Bahia prova a defasagem: fato relevante
de recuperação judicial protocolado em 16/08, comunicado em 18/08, e a última linha
da companhia dentro do ZIP é de 10/08.

Alternativas com custo. RAD interativo (`rad.cvm.gov.br`) é a fonte de baixa latência
real, custo é scraping de ASPX com viewstate e captcha em algumas rotas, manutenção
alta. B3 publica fatos relevantes de listadas com latência de horas, cobertura menor
que a CVM. Nenhuma das duas é recomendada antes de o operador decidir se a latência
semanal é problema de negócio ou só incômodo.

**Pronto quando:** o operador decidir, e a decisão estiver escrita aqui com a razão.

**RESOLVIDO 21/08, decisão assinada no `DECISOES-OPERADOR-2026-08-20.md`, commit
`5283636`, em produção v4.9.208.** Recomendação aceita: sem scraping do RAD. O Worker
promove para FULL com motivo `imprensa_recente_7d` emissor com evento
CRITICO/RELEVANTE dos últimos 7 dias, e a skill da noturna manda esse motivo para a
fila aprofundada. A checagem pontual no RAD continua só no gate de evento de RJ,
default e rebaixamento.

### P3 — BANNERMORTO1: o banner de aviso nunca pintou para ninguém

`<div id="banner" style="display:none">` tem estilo inline, e a regra
`#banner.visible { display: block }` é de folha de estilo, que perde para inline.
Verificado ao vivo em produção: a classe `visible` está aplicada, o texto está no
elemento, `computed display` é `none` e a altura é 0. Removendo o inline via console,
o elemento aparece com 31px.

Consequência dupla. O falso "Serviço temporariamente indisponível" nunca chegou ao
cliente, que é a boa notícia. E os avisos legítimos (`erro_conexao`,
`dados_desatualizados`, `sem_chaves`) também nunca chegaram, que é a ruim.

Religar exige cuidado de ordem: o gatilho já foi corrigido hoje para depender só de
liveness, mas os outros 5 tipos de aviso nunca foram vistos por usuário nenhum.

**Pronto quando:** os 6 tipos de aviso tiverem sido revisados um a um quanto a texto
e gatilho, o inline `display:none` sair, e existir teste de DOM que confirme
visibilidade real.

### P3 — CACHEBUMP1: alinhamento manual do `?v=` a cada deploy Pages

Terceira vez seguida. Os commits `01ff325` e `4276504` do v202.12 fizeram o mesmo, e
hoje o gate 3.4 do `deploy-pages.ps1` reprovou duas vezes até os 4 módulos admin
serem alinhados à mão. O bump do `CACHE_VERSION` no `index.html` não propaga sozinho
para os imports em `app/js/`.

**RESOLVIDO 24/08.** Dado o `bump-cache-version.ps1` (o script existe e altera os
pontos de cache), o foco virou os TRÊS defeitos de comportamento da `Replace-InFile`
que ele carregava, que o tornavam perigoso num `index.html` de 700 KB:
(1) trocava `"v<n>.<n>"` entre aspas em QUALQUER lugar (copy/UI/changelog), sem âncora;
(2) colisão de substring — versão `v202.3` casava dentro de `?v=202.30` e produzia
`?v=203.10`; (3) a substituição do caso `?v=v<n>.<n>` usava `$newRe` (o valor JÁ
[regex]::Escape()'d) em vez do literal `$New`, o que inseriria `v203\.1` com barra
invertida na saída. Correção em `scripts/bump-cache-version.ps1`: troca genérica de
aspas removida (CACHE_VERSION muda só via regex ancorada no prefixo
`CACHE_VERSION="`), `?v=` com negative lookahead `(?![0-9])` (sem prefixo de outra
versão), e substituição do caso `?v=v<n>.<n>` passou a usar `$New` literal (só o lado
PADRÃO escapa; o lado SUBSTITUIÇÃO usa o valor). `$newRe`/`$newNumRe` removidas por
ficarem órfãs. **Causa raiz (ampliada):** o defeito (3) nasceu de acreditar que
substituição de [regex]::Replace exige o mesmo escape do padrão — não exige — e
passou porque o teste só cobria a instância (`?v=202.30`), nunca a classe (barra
invertida na saída via variável escapada). **Guarda:** `scripts/test-bump-cache-version.ps1`
roda o real numa bancada isolada (`scripts/_tmp_bump_test/bump2`, criada e limpa pelo
próprio teste) e agora também asserta (a) `?v=v202.3` → `?v=v203.1` sem barra e
(b) a saída NÃO contém NENHUMA barra invertida — asserção que fecha a classe do
erro, não só a instância. Validado: parse PS 5.1 (`lint-encoding.ps1` OK 1/RISCO 0 p/
ambos), BOM único, teste verde exit 0 (8x OK, incl. `?v=v202.3⇒?v=v203.1 (sem barra)`
e `saida sem nenhuma barra invertida`).

---

## 20/08 (17h00 BRT) — RESOLVIDO: CVMCADENCIA1, HEALTHSPLIT1, SPREADUNIDADE1, MOJIBAKEORIGEM1

**CVMCADENCIA1 (P1).** A premissa "a CVM parou de publicar", escrita em 19/08 e
repetida por mim duas vezes em 20/08, é falsa. O ramo `CIA_ABERTA/DOC` tem cadência
**semanal declarada** na página do dataset e publica aos domingos. Evidência:
`ipe_cia_aberta_2026.zip` e o de 2025, corrente e A-1, regerados no mesmo domingo
16/08 com 1 minuto de diferença, e o domingo anterior também. O portal segue vivo,
`FI/DOC/INF_DIARIO` e `CIA_ABERTA/CAD` foram regerados em 20/08 de madrugada. E a CVM
segue recebendo protocolo, Casas Bahia protocolou em 16 e 18/08.
*Correção:* `CVM_FONTE_MAX_DU = 2` virou regra de ciclo perdido, alerta só após dois
ciclos semanais sem publicar, ou seja 14 dias corridos. *Causa raiz:* medir fonte de
cadência 7 dias com régua de 2 dias úteis fazia o health ir a vermelho toda quarta ou
quinta, previsivelmente. *Guarda:* 3 testes novos em `cvm-frescor.test.mjs` (4 dias
passa, 13 dias passa com 1 ciclo perdido, 14 dias reprova) e o fato da cadência
registrado na skill `vix-radar-general-audit`.

**HEALTHSPLIT1 (P1).** Frescor de fonte de terceiro saiu do `ok` agregado e foi para
`fonte_externa_ok`. *Causa raiz:* `ok` tem 13 consumidores que o tratam como
liveness, entre eles `rotate-routine-key.ps1` que **aborta** a rotação da chave,
`scan-emergencia.yml` que dispara varredura, 4 workflows de CI e o banner da tela.
Nenhum tem ação útil diante de "a CVM publica aos domingos". *Guarda:* canal de
alerta próprio no `watch-vixradar-health.ps1` com reenvio de 48h, e o inventário dos
13 consumidores registrado no `CLAUDE.md`.

**SPREADUNIDADE1 (P0).** O card do painel do emissor dizia "Spread ANBIMA" e
carimbava " bps" num valor que é taxa indicativa em % a.a. Medido em produção:
Petrobras aparecia como "6,98 bps", CSN como "20,08 bps", Aegea como "4,53 bps". Erro
de fator 100 na unidade sob nome que nem era o da grandeza. *Causa raiz:*
`worker.js:12584` empurra `r.taxa_indicativa`, coluna 6 do arquivo público de
debêntures da ANBIMA, para dentro de um campo chamado `spread_bps`. Nome do campo
mentindo desde a ingestão, e a tela repetindo a mentira. *Correção:* rótulo virou
"Taxa indicativa ANBIMA", valor recebe "% a.a." e o delta " p.p.". Resíduo de
migração fica no SPREADUNIDADE1 acima.

**MOJIBAKEORIGEM1 (P3).** `collect_cotacoes.ps1` lia `tickers_emissores.json` sem
`-Encoding`, e o 5.1 usa a página ANSI por padrão. Arquivo UTF-8 sem BOM virava
mojibake e era carimbado em `meta_volatilidade.json`. *Causa raiz:* a rede
(`Repair-Mojibake` no uploader) escondeu o problema por meses, produção nunca viu
nome errado. O custo aparecia em outro lugar, comparação por nome entre os dois
arquivos errava em silêncio, e um diff da auditoria acusou 33 falhas onde o número
real era 21. *Guarda:* `-Encoding UTF8` nos dois `Get-Content` do script, artefato em
disco reparado, e `Repair-Mojibake` mantido como rede, não como conserto.

---

## 20/08 (15h50 BRT) — PARCIAL: por que o feed parece congelado, e o que estava quebrado por baixo

Pergunta de origem: "o sistema nao foi atualizado". Investigacao encontrou uma causa externa e
tres defeitos internos que ninguem tinha visto, dois deles corrigidos nesta sessao.

**A causa do feed parado nao e bug nosso.** O arquivo bulk da CVM parou de ser publicado:
`Last-Modified: Sun, 16 Aug 2026 10:00:36 GMT` no
`https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip`, 4 dias uteis
atras. O `cvm_fonte_ok:false` no health publico esta certo e derrubando o `ok` agregado de
proposito. As rotinas rodaram normalmente: matinal 20/20 hoje as 10h21, verificacao-async 16
eventos submetidos as 10h37, evento mais novo em producao de 18/08 (`idade_du:2`, no limite).
O que o usuario ve como "parado" e a soma do apagao da CVM com a lacuna de produto ja registrada
em 19/08 (o feed mostra o evento mais material da janela de 30 dias, nao o delta do dia).

**VOLTTL1 (P2, corrigido).** A chave `cotacoes:volatilidade:v1` sumiu de producao. O upload de
19/08 17:02 falhou (`upload_volatilidade_kv.ps1 exit=1`, `LastTaskResult 1` na
`VIXRadar-Coleta-Volatilidade`) e o TTL era 86400, exatamente o intervalo entre duas execucoes.
A escrita de 18/08 expirou as 17:01 e a chave passou a responder 404 no
`wrangler kv key get --remote`. O pipeline preditivo le com `.catch(() => null)`, entao rodou o
dia inteiro sem volatilidade, sem log e sem alerta.
*Correcao:* chave republicada agora (`UPLOAD_OK`, 73 emissores, Selic 0,139 as_of 2026-08-19) e
TTL para 259200. *Causa raiz:* TTL igual ao intervalo de gravacao nao deixa folga para uma unica
falha. *Guarda:* item permanente na skill `vix-radar-general-audit` exigindo TTL >= 2x o intervalo
de gravacao para toda chave alimentada por rotina agendada.

**VOLLOG1 (P2, corrigido).** O `run_coleta_volatilidade.ps1` capturava a saida do uploader em
`$uploadOutput` e no `catch` logava so `ERRO upload: ... exit=1`. As linhas `AVISO:` com o motivo
real eram descartadas, entao a falha de 19/08 ficou sem diagnostico possivel. *Correcao:* o
`catch` agora despeja a saida capturada no log. *Guarda:* item permanente na skill para auditar
todo wrapper de rotina que chame script filho.

**HEALTHWATCH3 (P3, corrigido).** O `watch-vixradar-health.ps1` so lia `ok`, `verificador_ok` e
`versao` do health. O e-mail e o log diziam `ok=False verificador_ok=True` e nada mais, por 3 dias
seguidos de 15 em 15 minutos, sem citar `cvm_fonte_ok`. *Correcao:* o snapshot passou a carregar
`kv`, `telemetria`, `sentry_ok`, `admin_email_ok` e `cvm_fonte_ok` + motivo, e o alerta nomeia o
campo vermelho. Testado ao vivo: `DEGRADADO: ok=False versao=v4.9.203 CAUSA: cvm_fonte_ok=false
(fonte_parada_ha_4_dias_uteis)`. *Guarda:* item permanente na skill exigindo que alerta automatico
nomeie o campo, nunca so o agregado.

**DRIVERMORTO1 (P2, diagnosticado, decisao do operador pendente).** 3 dos 6 drivers declarados em
`scorePreditivoRuleV1` nunca produziram nada em producao. `merton_dd` esta `null` nos 103
emissores em **todos** os exports desde 11/07/2026 (checado em 2026-07-11, 07-12, 07-13, 08-13,
08-16, 08-18, 08-19 e no snapshot ao vivo de hoje). O gate em `worker.js:14074` exige `mktCap`, e
as duas fontes possiveis nao tem esse campo: `fundamentals:altman:latest` vem da DFP da CVM
(balanco, 0 ocorrencias de `market_cap` em 99 empresas) e `cotacoes:volatilidade:v1` se recusa a
publicar preco por acao como market cap, de proposito e com razao. `momentum` e `mercado` tambem
ficam em zero (`velocity_delta` 0 com `tem_serie:false`, `spread_score` 0). Isso contradiz a
premissa MERTONLIVE1 da skill de auditoria, que afirmava que Merton movia score em producao.
*Mitigante:* `predictive_v1` e lab interno (`user_facing:false`), nao chega na tela do cliente.
*Guarda ja aplicada:* `scripts/check-drivers-preditivos.ps1` mede cobertura por driver no export
diario, reprova driver novo com cobertura zero, e foi ligado no
`run_vixradar_export_historico.ps1`. A premissa errada foi corrigida na skill.
*Decisao pendente do operador:* ou entra uma fonte de `market_cap` (acoes em circulacao x preco,
dado que hoje nao e coletado) e os 3 drivers passam a valer, ou eles saem do codigo. Manter
driver declarado que nunca dispara faz o modelo parecer mais rico do que e.

---

## 19/08 (09h15 BRT) — RESOLVIDO: RETRYCFG1, as duas tasks de retry nasceram sem as guardas do projeto

Achado pela varredura de pendencias do workspace (`/resolver-pendencias`), nao por incidente novo.

O monitor acusava `Szuchmacher-RetryVixMatinal` com `LastTaskResult 2147946720` desde 18/08. Esse
codigo e `0x800710E0` (ERROR_REQUEST_REFUSED), e tanto o codigo quanto a remediacao ja estavam
documentados em `AI_OPERATING_SYSTEM/06_RISCOS_E_DIVIDAS_TECNICAS.md:72` (extraido de dentro do
repo do Jarvis para a raiz do workspace em 20/08/2026)
("condicao de energia / maquina suspensa, flags de bateria + `StartWhenAvailable`"). O mesmo fix ja
tinha sido aplicado em 09/08 no `Szuchmacher-MacroCron` e no `Szuchmacher-AgendaAgent`.

A sessao da madrugada de hoje acertou a causa por evidencia (evento 153, maquina desligada das 03h42
as 16h14, gatilho das 13h30 perdido) mas parou antes de aplicar a correcao.

**Causa raiz.** As duas tasks de retry nasceram em 17/08 criadas a mao. Sao as **unicas** do projeto
sem script de registro: as outras nove tem, e todas as nove setam `StartWhenAvailable`. Fix aplicado
a instancias, nao ao padrao, entao a task criada depois nasceu sem ele.

**Tres defeitos, nao um** (o dump da configuracao expos os outros dois):

| Configuracao | Estava | Agora | Por que importa |
|---|---|---|---|
| `StartWhenAvailable` | `False` | `True` | Disparo perdido era descartado em silencio |
| `DisallowStartIfOnBatteries` / `StopIfGoingOnBatteries` | `True` / `True` | `False` / `False` | Em bateria a task recusa iniciar, e morre se a energia cai no meio |
| `ExecutionTimeLimit` | `PT72H` | `PT4H` | 72h com `MultipleInstances IgnoreNew`: uma instancia travada bloquearia os 3 dias seguintes de retry sem ninguem ver. Toda irma no projeto usa minutos ou poucas horas |

**Guarda sistemica:** `scripts/register-retry-tasks.ps1`, que faltava. Reproduz as duas tasks com a
configuracao correta e **verifica o resultado no fim**, saindo 1 se qualquer campo divergir. XML das
duas versoes antigas salvo em `%TEMP%\retrytasks_bk_20260819-091356\` antes de mexer.

**Prova (saida real do script):**
```
Szuchmacher-RetryVixMatinal
  StartWhenAvailable         = True  (esperado True)
  DisallowStartIfOnBatteries = False  (esperado False)
  StopIfGoingOnBatteries     = False  (esperado False)
  ExecutionTimeLimit         = PT4H  (esperado PT4H)
  NextRunTime                = 19.ago.2026 13:30:00
Szuchmacher-RetryVixNoturno
  ... idem, NextRunTime = 19.ago.2026 21:30:00
OK: as duas tasks estao com StartWhenAvailable, tolerancia a bateria e teto de 4h.
```

**O alerta do monitor continua vermelho ate 13h30 de hoje, e isso esta certo.** Re-registrar nao zera
`LastTaskResult`, so uma execucao bem-sucedida zera. Rodar a task agora (09h15) seria pior: a matinal
so roda as 10h, o retry nao acharia linha `FIM` do dia e relancaria a rotina uma hora antes da hora,
gastando cota e colidindo com a sessao agendada. O bloco `<!-- AUTO-MONITOR-START -->` do backlog
central e regenerado pelo `monitor-tasks.ps1`, entao nao adianta riscar a linha la a mao.

**Nao confundir com um quarto item:** `Szuchmacher-RetryVixNoturno` estava com `LastTaskResult 0`, ou
seja nunca falhou, mas carregava exatamente os mesmos tres defeitos de configuracao. Foi corrigido
junto por isso, nao por ter dado erro.

---

## 19/08 (08h30-09h00 BRT) — ABERTO: feed segue em 14/08, causa e apagao da CVM + cegueira de frescor

Usuario reportou que, mesmo apos os fixes DEDUP1 e HISTFLAT1+2 da madrugada, o Painel de Eventos
continua parando em 14/08. Auditoria geral (`vix-radar-general-audit`) provou que **o painel esta
correto** e o problema e de dado, nao de renderizacao.

### Prova, varredura nos 103 emissores canonicos via `dados_para_analise`
```
MAX data_entrega CVM  (103 emissores) = 2026-08-15
MAX data_evento estado (103 emissores) = 2026-08-14
emissores sem doc CVM na janela 30d = 26
emissores sem evento no estado      = 44
```
Script em `scratchpad/probe-frescor.ps1`, detalhe por emissor em `scratchpad/frescor-por-emissor.txt`.

### CAUSA RAIZ 1 (externa) — a CVM parou de publicar em 16/08
```
CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:00:36 GMT
CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:03:19 GMT
CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:46:07 GMT
CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv            Last-Modified: Wed, 19 Aug 2026 04:15:42 GMT
```
IPE, FRE e ITR parados ha 3 dias no servidor da propria CVM. So o CAD (cadastro) segue atualizando.
Baixado o ZIP real e rodado o mesmo parser do Worker contra ele (`scratchpad/test-cvm-zip.mjs`):
```
descomprimido OK: 13290631 bytes
MAX Data_Entrega no arquivo da CVM: 2026-08-16
linhas por Data_Entrega >= 13/08: {"2026-08-14":332,"2026-08-13":358,"2026-08-15":6,"2026-08-16":4}
```
Zero entrega em 17 e 18/08, dias uteis. **O parser de ZIP do `syncCVMAutomatico` esta correto**, nao
e ZIP64, nao tem data descriptor, `compSize` do local header bate, descompressao limpa em 1,1s.
Hipotese de estouro de CPU no laco `String.fromCharCode` tambem descartada, 670ms local.

### CAUSA RAIZ 2 (interna) — nenhuma guarda mede frescor de dado, todas medem se o escritor rodou
- `heartbeat:sync_cvm` = `{"status":"ok","ts":"2026-08-18T21:30:56.564Z"}`. Verde durante o apagao.
- `api/src/worker.js:17506` e `:17550` fazem `await syncCVMAutomatico(env)` e carimbam `"ok"` **sem
  checar o retorno**. A funcao devolve `{ok:false}` (nao lanca) em fetch !ok, arquivo nao-ZIP e
  metodo nao-Deflate. Buraco latente, nao foi o caminho de hoje, mas mascararia falha real.
- `.github/workflows/frescor-check.yml` valida `estado_semanal.updated_at` e
  `empresas_com_dados >= 50`. Os dois ficam verdes com conteudo reciclado porque a rotina escreve
  todo dia. Nunca olha idade do evento mais novo nem idade da fonte.

### Consequencia observada — a rotina recicla fato velho
Log `logs/routines/vixradar-noturno_20260818.log`:
```
2026-08-18 18:17:13 ANOTA_rapida_1: CEMIG|Duas emissoes novas em 14/08/2026, 16a da Cemig D e 13a da Cemig GT...
2026-08-18 18:17:16 OK|CEMIG|FULL|RELEVANTE|1|true
```
Rodou em 15, 17 e 18/08, submeteu 1 evento cada vez, e a CEMIG segue com 2 eventos, o mais novo de
14/08. A dedup do Worker funciona. O que ela deduplica e o modelo re-narrando a mesma noticia porque
o `cvm_documentos` entregue a ele tambem parou em 14/08.

### Veracidade da UI — 2 achados novos
- **"Atualizado em 19 de agosto de 2026"** e `new Date()` do navegador (`app/index.html`, funcao de
  relogio do dashboard), nao timestamp de dado. Nunca pode ficar velho, por definicao.
- **Tira de fontes do rodape e decoracao pura.** `st-cvm`, `st-anbima`, `st-b3`, `st-fitch`,
  `st-moodys` aparecem **uma unica vez cada** no arquivo, dentro do HTML estatico com
  `class="status-item ok"` fixo. Nenhum codigo le ou altera em runtime. "CVM RAD" ficou verde
  durante 3 dias de apagao real da CVM.
- Script obrigatorio `audit-ui-metrics.mjs`: `0 bloqueante(s), 9 informativo(s)`.

### Achado menor
`heartbeat:cascade_analise` nao existe no KV. E o `stale_count:1` que o `watchdog_diario` reportou
em `2026-08-19T01:00:51.106Z`.

### As duas P0 — RESOLVIDAS e em producao (v4.9.201 depois v4.9.202)

**P0-1 CVMFRESCOR1, a idade da fonte entra no health.** `syncCVMAutomatico` passou a
carimbar `cvm:fonte_meta` com o `Last-Modified` do servidor da CVM e a maior `Data_Entrega`
do arquivo INTEIRO, medida antes de qualquer filtro de emissor (se medisse so os 103, um dia
em que a CVM publicou normalmente mas nenhum emissor nosso protocolou pareceria fonte
parada). `avaliarFrescorCVM` decide por dias uteis, fim de semana nao conta, limite de 2 du.
Fail-closed: meta ausente, ilegivel, sem data ou de sync que falhou nao conta como fresca.
`cvm_fonte_ok` entrou no `_okHealth` pelo mesmo criterio do SECRETMISS1 e do SENTRY1.

**P0-2, os crons passam a checar o retorno.** `worker.js` linhas do bloco matinal e noturno
so verificavam se `syncCVMAutomatico` explodiu. A funcao devolve `{ok:false}` sem lancar em
fetch !ok, arquivo nao-ZIP e metodo nao-Deflate, entao a CVM poderia devolver HTML de erro
por uma semana com heartbeat verde. Agora o retorno decide o heartbeat, e o heartbeat de
sucesso carrega `documentos`, `last_modified` e `max_data_entrega`.

**CVMFRESCOR1b, falha do proprio fix, achada na primeira leitura em producao.** Com o gate
valendo e nenhum cron tendo rodado, o motivo vinha `sem_meta` e o health ficaria vermelho por
ate 12h a CADA deploy. Alarme falso recorrente treina quem olha a ignorar o alarme, que e o
mecanismo por tras dos 5 dias congelados. Corrigido derivando a idade de `cvm:documentos`,
que ja existia, com backfill gravado uma unica vez e marcado `origem:"backfill_documentos"`.
Precedencia testada: meta real sempre ganha do backfill, porque o backfill mede so os 103
emissores e o `Last-Modified` mede o arquivo inteiro.

**Efeito colateral tratado, `deploy-worker.ps1`.** O passo 5 fazia `Fail` em `ok=false`.
Com o gate novo, todo deploy durante apagao da CVM abortaria com o codigo ja no ar e o repo
declarando a versao velha, que e o drift que esse passo existe para impedir. Agora ele
distingue health degradado por falha do deploy de health degradado por fonte externa. Provado
na saida real do v4.9.202: `AVISO: ok=false causado SOMENTE por cvm_fonte_ok=false. Fonte CVM
parada ha 3 dias uteis. Prosseguindo com o commit.`

**Efeito colateral tratado, `canonical-test.yml`.** A mensagem de erro nomeava
`admin_email_ok`, `sentry_ok` e `verificador_ok`, todos true, mandando quem investigasse
procurar secret quebrado. Agora le `cvm_fonte_ok`, `cvm_fonte_idade_du` e `cvm_fonte_motivo`,
nomeia o fator caido e, quando ele e o unico, manda conferir o `Last-Modified` do
`ipe_cia_aberta` antes de mexer em codigo. Guarda extra: se o campo sumir do health, o run
falha, o que pega tanto remocao do gate quanto deploy regredido.

`frescor-check.yml` foi conferido e NAO quebra: ele chama `admin_health_check`, que roda
`executarHealthCheckDiario` com `ok` proprio, independente do `_okHealth`.

**Prova em producao (v4.9.202, 2026-08-19T12:07:37Z):**
```
{"ok":false,"versao":"v4.9.202","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},
"admin_email_ok":true,"sentry_ok":true,"verificador_ok":true,"cvm_fonte_ok":false,
"cvm_fonte_idade_du":3,"cvm_fonte_motivo":"fonte_parada_ha_3_dias_uteis"}
```
```
cvm:fonte_meta = {"ok":true,"max_data_entrega":"2026-08-15","documentos":715,"origem":"backfill_documentos"}
```
`ok:false` aqui e o comportamento pretendido, nao regressao. A fonte esta parada de verdade,
e agora o sistema diz isso em vez de fingir saude.

**Guardas:** `api/test/cvm-frescor.test.mjs` (12 casos, CI verde, 35 testes no total) e
`scripts/test-frescor-cvm.mjs` (31 casos, roda local porque o Smart App Control bloqueia
`workerd` nesta maquina). Os dois exercitam codigo extraido do `worker.js` real, nunca copia.
Endpoints novos `admin_sync_cvm_auto` e `admin_frescor_cvm`, porque ate aqui nao havia como
rodar nem auditar o `syncCVMAutomatico` fora dos dois crons.

### As tres P1/P2 — RESOLVIDAS e em producao (Worker v4.9.203, frontend v202.12)

**Achado de investigacao, antes de listar as correcoes.** A busca das rotinas NAO
esta quebrada. Amostra do noturno de 18/08 mostra achado real, variado, com data
e numero (Engie Fitch elevou IDR em 10/08, Energisa vendeu 5 transmissoras em
12/08, Auren prejuizo R$ 379,1mi no 2T26), e classificacao com distribuicao
normal entre os dias (3-6 CRITICO, 16-26 RELEVANTE). O problema real: o pipeline
responde "qual o evento mais MATERIAL da janela de 30 dias", nao "o que mudou
desde ontem". Para a maioria dos emissores isso e o resultado do 2T26,
divulgado 12-14/08, entao o modelo reporta a mesma coisa corretamente todo dia
ate aparecer algo maior, e a dedup do Worker colapsa as repeticoes no feed. A
CVM parada tirou a unica fonte que traria fato novo com data nova; as duas
causas juntas produziram o congelamento. Item 5 (materialidade vs delta) fica
registrado como mudanca de produto, nao aplicado, ver abaixo.

**EVENTOFRESCOR1, health diario mede idade do evento (P1).** Novo
`checks.evento_mais_novo` em `executarHealthCheckDiario`: data do evento mais
recente entre os 103 emissores, idade em dias uteis, total de eventos, veredicto
`fresco`. Mesmo limite de 2 du da fonte CVM. Reusa `_cvmDiasUteisApos` em vez de
reimplementar calendario.

**`frescor-check.yml` gateia o campo novo (P1).** O Action so validava
`updated_at` (hora da GRAVACAO) e `empresas_com_dados`, os dois ficam verdes com
conteudo reciclado porque a rotina escreve todo dia. Foi por isso que ele passou
verde a semana inteira do incidente. Agora aborta se `idade_du > limite_du`, com
mensagem mandando conferir `cvm_fonte_ok` do health publico antes de cacar bug,
porque quando os dois estao vermelhos a causa e a mesma.

Validacao sem credencial: simulado localmente em node contra o formato real de
resposta (`scratchpad/simula-frescor.mjs`), 4 casos incluindo o caso real do
incidente (escritor fresco, evento de 3 du) abortando como esperado. O
`workflow_dispatch` manual falhou por `ADMIN_PASSWORD` vazio no disparo via
`gh workflow run`, mas o secret existe no repo desde 13/08 (`gh secret list`) e
o `schedule` de hoje 02h42 UTC ja tinha rodado verde com ele antes deste fix.
Anomalia pontual do disparo manual, nao do secret nem do codigo; nao investigada
a fundo por ser tangencial. Confirmar no proximo `schedule` (diario 01:37 UTC).

**FONTESFAKE1, tira de 7 fontes removida (P1).** Era HTML estatico com
`class="status-item ok"` fixa, cada id (`st-cvm`, `st-anbima`, `st-b3`,
`st-fitch`, `st-sp`, `st-moodys`, `st-austin`) aparecia uma unica vez no arquivo
inteiro, nenhum codigo lia ou escrevia em runtime. Nao virou dinamica: das 7 o
sistema so tem sinal real de 2 (CVM via `cvm_fonte_ok`, ANBIMA via heartbeat
`sync_anbima` com `data_arquivo`), as outras 5 nao tem integracao monitorada.
Duas reais ao lado de cinco decorativas continuaria enganando. Confirmado ao
vivo via DOM: `status-left` com 0 filhos, `getElementById("st-cvm")` retorna
null em producao.

**CARIMBOFAKE1, "Atualizado em" mostra idade do dado (P2).** Era
`new Date().toLocaleDateString(...)`, relogio do navegador, nunca podia ficar
velho por definicao. Nova funcao `_vixCarimboDeDados` calcula local no
frontend (sem round-trip ao Worker) a data do `data_evento` mais recente em
`resultados` e a idade em dias uteis: "Evento mais recente 14 de agosto de 2026
(3 dias uteis atras)". Sem dado carregado (home publica), so declara a janela,
nao inventa carimbo — confirmado ao vivo, `dash-data` mostra so
`"Janela: 30 dias"` na home sem sessao.

**Efeito colateral tratado: GATE 3.4 achou drift de `?v=` em 4 camadas.**
Bump do `CACHE_VERSION` para v202.12 exigiu alinhar nao so o
`admin-bootstrap.js` (memoria conhecida, DEDUP1 ja tinha esse padrao) mas
tambem os 3 submodulos que ele reexporta (`engajamento.js`, `metricas.js`,
`modules.js` importam `shared.js` com querystring propria). Corrigido em
commit separado depois que o gate reprovou pela segunda vez, varredura final
cobriu TODO `app/`, nao so os arquivos que o gate apontou.

**Prova em producao:**
```
{"ok":false,"versao":"v4.9.203",...,"cvm_fonte_ok":false,"cvm_fonte_idade_du":3,
"cvm_fonte_motivo":"fonte_parada_ha_3_dias_uteis"}
```
```
version.json = {"version":"v202.12","deployed_at":"2026-08-19T12:36:04Z"}
DOM: status-left innerHTML="" children=0 stCvmExiste=false
DOM (home, sem sessao): dash-data.textContent="Janela: 30 dias"
```

### Ainda aberto

| Sev | Item | Nota |
|---|---|---|
| Decisao de produto | Materialidade vs delta: o feed hoje mostra "evento mais material da janela de 30d", nao "o que mudou desde ontem". E a causa de fundo do congelamento, junto com o apagao da CVM. Separar as duas perguntas no prompt das rotinas e mudanca de produto, nao bug — nao aplicado sem decisao do operador | Ver secao acima |
| Investigacao, maior esforco | Dependencia do arquivo batch `ipe_cia_aberta_2026.zip` da CVM, que provou atrasar 3 dias. Portal RAD e superfice em tempo real, caminho alternativo nao investigado | Abrir como item separado |
| P3 | `heartbeat:cascade_analise` nao existe no KV, e o `stale_count:1` do watchdog | Investigar se o agente foi renomeado ou morreu |

### Lacuna honesta
Nao foi provado que houve evento de credito material em 17 ou 18/08 que o sistema perdeu. A busca
web nao devolveu nada datado desses dias. O que esta medido e que **nenhum evento posterior a 14/08
entrou no estado**. Nao ha evidencia de que o WebSearch das rotinas esteja quebrado.

### Estrutura de pastas, resolvido na mesma sessao
- Junction legada `E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito` **removida**. Preflight
  confirmou 0 tarefas agendadas, 0 worktrees e `lint-legacy-path.ps1` com 70/70 OK antes de mexer.
  Alvo validado depois, 44923 arquivos e 1799312500 bytes identicos ao baseline, HEAD `fa191b5`
  preservado, working tree limpo. `FREQUENTE\` continua intacta com os outros 13 projetos.
- As 5 skills `vix-radar-*` estavam duplicadas: stubs de 250 a 325 bytes em
  `C:\Users\User\.claude\skills\` apenas apontando texto para o conteudo real em
  `E:\Diretorio\Claude\.claude\skills\`. Isso quebrou de verdade nesta sessao, o
  `audit-ui-metrics.mjs` falhou com `MODULE_NOT_FOUND` na primeira chamada porque o diretorio-base
  anunciado era o do stub. Stubs trocados por junctions apontando para o conteudo real.

---

## 19/08 (01h35-03h10 BRT) — RESOLVIDO: painel de eventos parado em 14/08 + historico de EWS achatado

Usuario reportou o Painel de Eventos em vixradar.com mostrando 14/08 como a data mais recente do
feed cronologico, apesar do cabecalho "atualizado em 19 de agosto" e da janela de 7 dias uteis
(11-19/08) exibindo 38 relevantes / 7 criticos / 24 emissores com sinal. Investigacao (01h35)
achou a causa provavel do feed sem prova direta e, de passagem, um segundo problema no bloco
preditivo (hist_len sempre 1). Sessao de fix (/caveman, 02h30-03h10) provou, corrigiu, testou e
deployou os dois. Hierarquia de verdade aplicada: producao (version.json + comportamento real)
antes de Obsidian: as duas hipoteses do achado inicial precisaram de correcao a luz da prova, ver
secoes "correcao sobre o achado inicial" abaixo de cada bug.

### Confirmado — infraestrutura saudavel agora
Portao de verificacao: `ok:true kv:true telemetria:true sentry_ok:true verificador_ok:true`, v4.9.198.

### Confirmado — 3 falhas de cobertura entre 13 e 16/08, nenhuma documentada antes desta sessao
- **13/08 (quinta), blackout total.** Nenhum log de matinal nem de noturno existe para essa data
  em `logs/routines/`. Nao e log malformado, e ausencia completa, a rotina nao deixou rastro.
- **14/08 (sexta), matinal ausente.** O noturno de 14/08 rodou completo (log com conteudo real,
  CRITICO em Oncoclinicas/Oi/Raizen, `DEFERIDOS=13 FALHA=0 TOTAL=13`), mas nao ha log de matinal
  nesse dia, apesar de ser dia util com agendamento 10h BRT.
- **16/08 (sabado), noturno morreu no meio.** `vixradar-noturno_20260816.log` tem 1,3KB contra
  6-17KB dos demais dias: processou 15 de 103 emissores (LOTE R3), parou em "Aguardando R4 R5 R6
  R7" sem escrever `FIM:`, e deixou `vixradar-noturno_20260816.lock` sem limpar. A linha `HEALTH`
  no inicio do log ja mostrava `verificador_ok=false`, consistente com o modo de falha conhecido
  da fila de verificacao (SLA de 12h). 88 de 103 emissores ficaram sem qualquer analise no dia.

Nos dias entre essas falhas (15/08, 17/08, 18/08) o noturno rodou 103/103 com saida substantiva,
nao vazia, entao o pipeline nao ficou morto o periodo inteiro.

### DESCARTADO — cache do navegador
Usuario reabriu em aba anonima (sessao limpa, login refeito) e o feed continua parando em 14/08.
Nao e cache stale nem estado de sessao.

### DESCARTADO — rotina parada como causa
As rotinas de 15, 17 e 18/08 rodaram e submeteram com sucesso. A matinal de 18/08 fechou
`FIM: matinal 20/20 processados. CRITICO=2 RELEVANTE=13 ECO=5 ... submits_falhos=0`, com
`OK|Oi|FULL|CRITICO|1|true`, `OK|Oncoclinicas|FULL|RELEVANTE|1|true`, `OK|CSN|LIGHT|CRITICO|1|true`
entre outros. O noturno de 18/08 fechou `Total do dia 103/103`. Ou seja, o pipeline entregou
conteudo nesses dias e mesmo assim nada disso aparece no feed.

### CONFIRMADO — evento novo existe no dado depois de 14/08
Comparacao dos snapshots diarios de `data/historico/*/predictive.json` (gravados pela rotina de
export, 20h45) entre 14/08 e 18/08: 37 emissores mudaram `event_count`, sendo 20 com aumento —
Pao de Acucar (GPA) 10->13, CSN 11->14, Hapvida 2->5, Eneva 6->9, Dasa 4->6, JBS 4->6, CEMIG 1->2,
entre outros. Soma total de eventos 245 -> 254. O contador tem janela rolante (alguns cairam), mas
aumento so acontece com evento entrando. Logo, ha evento posterior a 14/08 gravado no estado.

Corroboracao externa: o Term Sheet das novas debentures do GPA foi aprovado por credores em
13/08 e o resultado 2T26 da Oncoclinicas saiu em 14/08 (prejuizo de R$ 475,7 mi), consistente com
o aumento de `event_count` desses dois nomes. Braskem, que teve rating cortado para RD pela Fitch
nessa janela, **nao** e emissor monitorado (zero ocorrencias em `api/src/worker.js`), entao nao
conta como perda de cobertura.

### P0-1 RESOLVIDO — DEDUP1, dedup semantica do frontend colapsava saga continua

**Correcao sobre o achado das 01h35:** a hipotese original ("qualquer titulo parecido dentro de
45 dias colide") era forte demais. Teste executavel com a funcao real extraida do arquivo (nao
reescrita, ver `scripts/test-dedup-eventos.mjs`) mostrou que manchetes de capitulo novo de uma
mesma saga normalmente NAO colidem, so 2 de 6 casos construidos colidiam de fato: republicacao
identica (esperado, dedup correta) e uma nota de analista template repetida verbatim, ou um par
onde a UNICA diferenca era a palavra "nova" (que a normalizacao removia por design). O mecanismo
real e mais estreito que o suspeitado, mas real: qualquer atualizacao cuja unica marca textual de
novidade seja "novo/nova", ou cuja redacao de analista se repita quase verbatim (comum neste
sistema, ver `ANOTA_rapida` nos logs de rotina), colide e o evento novo e descartado.

`_isDupSemantico`/`_normTituloDedup` (`app/index.html`, bloco minificado do `<head>`) tratavam
como duplicata qualquer titulo normalizado igual dentro de 45 dias, e a normalizacao removia
`novo|nova|novos|novas` (sinal temporal) alem de truncar em 70 caracteres.

**Fix (commits `60234fa`, `d818780`, `ae57327`, `32fcdb6`):**
- `novo/nova/novos/novas` nao e mais removido da normalizacao.
- Truncamento de 70 caracteres eliminado (compara string normalizada inteira).
- Identidade de duplicata agora prioriza `fonte_primaria` (URL sem query) quando disponivel;
  senao exige MESMO `data_evento` (dia exato, nao mais janela de 45 dias) + titulo normalizado
  igual.
- `_v201Coletar` ordena por `data_evento` desc antes de dedupar: numa colisao real, sobrevive o
  evento mais novo, nao o primeiro que chegou.
- `CACHE_VERSION` v202.10->v202.11, e as 15 referencias `?v=202.10` em `app/js/admin-bootstrap.js`
  + 3 submodulos alinhadas (pego pelo GATE 3.4 do proprio `deploy-pages.ps1`, nao verificado a
  mao).

**Teste:** `scripts/test-dedup-eventos.mjs` (nao ha suite para `app/`, script standalone que
extrai a funcao DIRETO do `index.html` real, nunca copia solta). 8 casos + ordenacao, verde:
republicacao real / mesma fonte / intradia matinal+noturno continuam deduplicando; capitulo de
saga, comunicado com "nova", rating novo, restatement em dia diferente, empresas distintas
passam a sobreviver.

**Prova em producao (v202.11, 2026-08-19T06:04:51Z):** `curl vixradar.com/` contem literalmente
o `_isDupSemantico` novo, `CACHE_VERSION="v202.11"` ao vivo, `admin-bootstrap.js` servindo
`shared.js?v=202.11`. Prova do dado real do usuario (evento que ANTES sumia agora aparecendo no
feed autenticado) nao foi possivel nesta sessao: exige sessao logada do usuario, que este agente
nao tem e nao deve simular. Se quiser fechar 100%, `JSON.stringify(resultados)` no console do
painel logado confirma.

### P0-2 RESOLVIDO — HISTFLAT1+2, historico de EWS nunca acumulava

Nos 8 snapshots de `data/historico/*/predictive.json` (11 a 18/08), `hist_len` era **1 para os
103 emissores, todos os dias**, zerando `velocity_delta`, `direction` (`sem_historico`) e
`confianca_nivel` (`muito_baixa`) no universo inteiro. Duas causas independentes, achadas em
sequencia porque a primeira sozinha nao resolveu (prova em producao pos-deploy 1 ainda mostrava
hist_len=1, o que forcou a segunda rodada de diagnostico):

**HISTFLAT1** (`api/src/worker.js:13804` `executarPipelinePreditivo`): a LEITURA de
`ews:hist:{empresa}` ficava atras do mesmo gate `persistHist` que decide se um ponto NOVO e
gravado. O unico caller com `opts` (`admin_executar_predictive`, usado por
`scripts/smoke-preditivo-lab.ps1`) chama com `skip_hist_persist:true`, entao pulava a leitura
inteira: historico tratado como vazio SO NESSA CHAMADA. Esse payload achatado ia para
`predictive_v1:latest`, a MESMA chave que os crons matinal/noturno (`scheduled()`, sem opts)
escrevem 2x/dia com ponto real, entao uma chamada admin/smoke depois do ultimo cron do dia
sobrescrevia o snapshot correto. Fix: leitura roda sempre, so `persistirHistEwsBatch` (escrita de
ponto novo) continua condicionada a `persistHist` (commit `297841e`, deploy v4.9.199).

**HISTFLAT2**, achada pela prova em producao do fix acima (hist_len continuava 1 apos o deploy):
`kvEwsHistKey` (`worker.js:13539`) grava a chave com `empresa.toLowerCase().trim()`. `histMap` e
populado decodificando essa mesma chave (fica minusculo), mas era lido com `histMap[empresa]`
usando o case original de `EMISSORES_LISTA` (ex. "Oncoclínicas", com maiuscula). Miss de lookup
silencioso: `histRaw` sempre `[]`, em QUALQUER chamador, inclusive os crons que sempre leram
(HISTFLAT1 nunca afetava esse caminho). Esta era a causa real por tras dos 8 dias observados, o
HISTFLAT1 era necessario mas nao suficiente. A escrita nunca teve esse bug, ela normaliza
internamente. Fix: lookup usa a mesma normalizacao da escrita (commit `53f2930`, deploy v4.9.200).

**Teste:** `api/test/predictive-hist.test.mjs`, integracao via `SELF.fetch`/`env` (CI, Miniflare
bloqueado localmente pelo Smart App Control) + formula pura de acumulacao validada em Node puro
(dia N->1, N+1->2, N+2->3, reprocessar N+2 continua 3 sem duplicar, dia anterior intacto,
ordenacao cronologica, gap de um dia nao apaga serie). A primeira versao do teste seedava a chave
`ews:hist:` com o case ORIGINAL da empresa (nao com `kvEwsHistKey` real) e por isso teria passado
mesmo com o HISTFLAT2 presente, mascarando o bug — corrigido para seedar exatamente como o codigo
real grava antes de confiar nele.

**Prova em producao (v4.9.200):** `smoke-preditivo-lab.ps1 -ExpectWorker v4.9.200` -> `SMOKE
PASSED` (7/7). Consulta direta pos-deploy: `hist_len` uniforme **2** para os 103 emissores
(antes: uniforme 1), `direction` `sem_historico` -> `estavel`. O "2" (nao um numero maior) reflete
que so ha 1 ponto real persistido ate agora (a serie so volta a crescer daqui pra frente, dia a
dia, com os proximos crons; nao existe historico retroativo para reconstruir com seguranca, entao
nenhum foi inventado).

### Achado menor — export ainda grava pelo caminho legado
`vixradar-export_20260818_204501.log` fecha com `3 arquivos em E:\Diretorio\Claude\FREQUENTE\
Monitoramento de Credito\data\historico\2026-08-18`, o caminho da junction legado. Nao quebra
porque a junction resolve, mas e sobrevivente da migracao de 18/08 e o `lint-legacy-path.ps1` nao
pegou, provavelmente por ser string montada em runtime e nao literal no `.ps1`.

## 19/08 (00h20 BRT) — auditoria de retries, watchdogs e monitoramento

Escopo fechado: só retry/watchdog/monitor. Produção como fonte de verdade (Task Scheduler ao vivo,
event log `Microsoft-Windows-TaskScheduler/Operational`, logs reais, execução real dos scripts).

### FATO NOVO — o event log do Task Scheduler está HABILITADO

`Get-WinEvent -ListLog` retorna `IsEnabled:True`, 16.676 registros. O `03 - Estado Atual.md`
(bloco de 27/07) afirma o contrário, que o log estava `IsEnabled=False` e que por isso a
investigação de quem removeu tasks entre 23 e 24/07 estava "encerrada por impossibilidade, não
por conclusão". Essa premissa não vale mais. Não reabri o caso de julho (fora do escopo desta
auditoria), mas fica registrado que hoje **é apurável** por evento 141.

### RESOLVIDO — causa exata do `Szuchmacher-RetryVixMatinal` recusado em 18/08 16:23

Não foi falha de execução nem do script. Evidência direta, evento **153** às 16:23:38: "o
Agendador não iniciou a tarefa porque não tinha sua agenda". Cadeia completa, toda medida:
a máquina desligou 18/08 03:42:14 (evento 13) e só voltou 16:14:33 (evento 12); o gatilho do
watchdog é 13h30 seg-sex, com a máquina desligada; a task **não** tem `StartWhenAvailable`,
então o agendador recusou o disparo atrasado e gravou `0x800710E0` (ERROR_REQUEST_REFUSED).
Não houve evento 201 para ela nesse dia, confirmando que nunca executou.

**Impacto real: zero.** A janela das 10h da matinal também caiu com a máquina desligada, e a
matinal só rodou às 16h34 (catch-up da própria sessão agendada do Claude Desktop, 20 min depois
do retry recusado), entregando 20/20 às 16h50. E mesmo se o watchdog tivesse rodado às 13h30,
não faria nada: sem log do dia ele sai por `SEM LOG ... fora do alcance deste watchdog`.

`monitor-tasks.ps1` classificar isso como erro **está correto**, não é ruído: em dia útil, um
watchdog que não disparou merece olhar. Ele pediu investigação, a investigação foi feita, a causa
é externa e benigna. Nada a corrigir aqui.

### Limitação conhecida (não é bug, decisão do usuário) — cobertura do watchdog com máquina desligada

Dia de máquina desligada na janela inteira não tem cobertura de watchdog nenhuma, por dois
motivos somados: (1) sem `StartWhenAvailable`, o disparo atrasado é recusado; (2) o próprio
script declara `SEM LOG → fora do alcance deste watchdog` quando a rotina nunca começou. Ligar
`StartWhenAvailable` **não** teria mudado o 18/08 (cairia em SEM LOG do mesmo jeito). Quem cobre
esse cenário hoje é o catch-up da sessão do Claude Desktop, que foi o que de fato salvou o dia.
Mudança não aplicada de propósito, não havia bug e a correção não resolveria o cenário.

### RESOLVIDO — parser de `FIM:` da matinal, 4o formato não reconhecido (causa raiz fechada)

Teste controlado aplicando o parser real contra os 14 logs reais de matinal/noturno disponíveis
achou 3 que produziriam retry falso. Dois são a P2 já aberta (11/08 e 14/08, noturno completo sem
escrever `FIM:`). O terceiro é novo: matinal 15/08 escreveu `FIM: 19 emissores processados`, sem
denominador, e nenhum dos 4 padrões casava.

Causa raiz: assimetria entre as duas skills. Depois do incidente de 17/08 o `SKILL.md` do noturno
passou a **exigir** o formato exato da linha `FIM:`; o da matinal nunca ganhou essa exigência.
Resultado, três formatos em quatro dias (`19/19 emissores processados`, `20/20 processados`,
`19 emissores processados`). Corrigir só o regex seria perseguir sintoma.

Correção: Passo 12 do `SKILL.md` da matinal agora exige `FIM: matinal <N>/<TOTAL> processados.`,
igual ao Passo 11 do noturno, nas duas cópias (versionada e viva fora do repo). Guarda: o
denominador virou opcional no 3o padrão do cascade, em `retry-vixradar.ps1` e `monitor-tasks.ps1`,
cobrindo log já escrito e drift futuro.

Teste real, ponta a ponta, com o script de produção: log de teste com a forma exata do 15/08 →
`OK: log do dia tem FIM valido, entrega feita`, exit 0 (antes daria retry falso). Controle
negativo com contador 3, abaixo do mínimo 12 → não entrou no ramo de entregue, caiu na guarda de
frescor. Log de teste removido. Regressão: `monitor-tasks.ps1` segue lendo noturno 103 e matinal
20 de 18/08.

### RESOLVIDO 19/08 (00h30 BRT) — P2 `monitor-tasks.ps1` não detectava rotina completa sem linha `FIM:`

Fallback por contagem de nome único implementado nos dois arquivos que leem o mesmo sinal
(`monitor-tasks.ps1` e `retry-vixradar.ps1`), não só no primeiro. Faltar nos dois teria deixado
o monitor avisar corretamente enquanto o retry ainda relançava a rotina inteira à toa, exatamente
o incidente caro de 17/08 se repetindo por outro caminho.

Calibragem: conferido contra os 14 logs reais de matinal/noturno disponíveis em 19/08, em todo
log onde o contador do `FIM:` parseava, ele batia exatamente com a contagem de nome único
(19=19, 103=103, 20=20). O fallback mede a mesma coisa por uma evidência mais confiável, o ledger
`OK|` é escrito por emissor logo após cada submit confirmado, não depende do modelo lembrar de
fechar o log.

Dia resgatado pelo fallback não vira `OK` mudo no `monitor-tasks.ps1`: vira aviso (novo código
`9003`), porque a linha `FIM:` ausente continua sendo defeito real de alguma execução, mesmo com
o dia entregue.

Testado com o script de produção real via cópia com `$VixRoot` redirecionado para sandbox (não
mock, o mesmo código, só a raiz trocada): 3 cenários no `monitor-tasks.ps1` (sem `FIM:` e ledger
suficiente → aviso 9003 dia OK; sem `FIM:` e ledger insuficiente → 9001 erro real; `FIM:` presente
sem contador reconhecível e ledger suficiente → aviso 9003). E 2 controles no
`retry-vixradar.ps1` com log real (não sandbox, arquivo de teste criado e removido em seguida):
positivo, 103 no ledger sem `FIM:` → não relança, exit 0; negativo, 15 no ledger (mínimo 90) → não
confirma entrega, não sai pelo ramo de sucesso. Regressão contra os logs reais de 18/08
(`FIM:` presente e válido nos dois): resultado idêntico ao de antes da mudança, `submit_ok=103`
noturno e `20` matinal, fallback nem é exercitado.

---

## 18/08 (23h50 BRT) — auditoria geral (skill vix-radar-general-audit, pos-FASE 2)

Auditoria readonly focada no que mudou apos as notas 85/86 e a inversao da junction (mesma
noite). Escopo: drift de codigo/rotina de hoje, veracidade da UI (script obrigatorio), governanca
de artefatos. Nao re-derivou seguranca/frontend/perf/a11y (sem mudanca desde a nota 85 desta
manha, confirmado por `git log --since` em `app/`). Detalhe completo pedido ao agente na sessao;
resumo dos achados novos abaixo.

### RESOLVIDO 19/08 (00h10 BRT) — P1 migracao da junction nos scripts e SKILL.md

Inventario refeito por busca direta (nao so o achado da auditoria): 24 `.ps1` + 2 `SKILL.md`
versionados (`matinal`, `noturno`) + os mesmos 2 `SKILL.md` vivos fora do repo em
`C:\Users\User\.claude\scheduled-tasks\vixradar-{matinal,noturno}\` (achado novo, nao estava no
inventario original, e o SKILL.md que a sessao agendada do Claude Desktop realmente le).
`register-all-routines-scheduler.ps1` e `monitor-tasks.ps1` tinham linhas adicionais com
`FREQUENTE\relatorio-diario-szuchmacher\...` e `FREQUENTE\Morning Call\...`, de outros projetos,
deixadas intocadas de proposito. `gen-dashboard.ps1` (root, gitignorado, fora do repo) corrigido
tambem, script local sem rastreamento git. Frase do `noturno/SKILL.md:109` que mandava "usar
sempre o caminho FREQUENTE" reescrita nos dois lugares (versionado e vivo) para citar o caminho
antigo sem soletra-lo por extenso (evita falso-positivo no lint novo).

Teste real, nao so parse: `lint-encoding.ps1` 66/66 OK. `monitor-tasks.ps1` executado ao vivo,
achou os logs de 18/08 no caminho canonico e leu `submit_ok=103` (noturno) e `submit_ok=20`
(matinal) corretamente, prova que o `$VixRoot` corrigido resolve de verdade. `retry-vixradar.ps1`
executado ao vivo para as duas rotinas, resolveu o caminho do log do dia 19/08 corretamente (log
ainda nao existe, rotina de hoje nao comecou, comportamento esperado). Achado incidental do teste,
sem relacao com este fix: `Szuchmacher-RetryVixMatinal` foi recusado pelo Task Scheduler
(`ERROR_REQUEST_REFUSED`) as 18/08 16:23, dia util, mas a matinal completou normal no horario
certo, sem impacto real. Nao investigado a fundo, fora do escopo deste item.

Guarda nova: `scripts/lint-legacy-path.ps1`, Gate 5 do pre-commit (`scripts/hooks/pre-commit`,
hooks reinstalados com `install-hooks.ps1 -Force`), reprova qualquer `.ps1` ou `SKILL.md` de
`routines/claude-desktop/*/` que reintroduza o caminho legado, com `$Allowlist` explicita para
excecao documentada. So cobre o repo, nao os `SKILL.md` vivos fora dele, limitacao conhecida e
registrada no proprio script. `references/audit-matrix.md` da skill de auditoria ganhou secao
"Watchdogs locais de rotina" cobrindo o padrao.

Junction NAO removida nesta rodada, como pedido: continua existindo, so passa a nao ter mais
nenhum consumidor operacional conhecido puxando por ela.

---

### P1 (fechado acima) — Migracao da junction (18/08 a noite) nao alcancou 26 scripts nem 2 SKILL.md das rotinas

A inversao da junction (`status/ESTADO.md`, 18/08 noite) reapontou a Action das 12 tarefas do
Task Scheduler para o caminho fisico canonico `E:\Diretorio\Claude\Monitoramento de Credito`, e
fechou dizendo "nenhuma tarefa, worktree ou metadado do git depende mais" do `FREQUENTE`. Isso e
verdade so para Action/worktree/git. Por dentro, 26 arquivos `.ps1` (incluindo
`run_claude_routine.ps1`, todos os `run_vixradar_*.ps1`, todos os `register-*-task.ps1` e o
proprio `monitor-tasks.ps1`) continuam com `$ProjectRoot`/`$VixRoot` hardcoded no caminho
`FREQUENTE\Monitoramento de Credito`. Nao quebra hoje porque a junction ainda existe e resolve, mas
e exatamente o cenario que a doc de fechamento convida alguem a criar (achar que nada depende mais
dela e remover). Se isso acontecer, praticamente toda a camada operacional cai ao mesmo tempo,
incluindo os watchdogs que deveriam acusar a falha.

Agravante: `routines/claude-desktop/noturno/SKILL.md:109` instrui ativamente o sentido errado hoje
("o caminho antigo `E:\Diretorio\Claude\Monitoramento de Credito` ainda funciona por junction, mas
e fragil - usar sempre o caminho FREQUENTE") — verdade antes da inversao de hoje, invertido agora.
`matinal/SKILL.md` tem a mesma referencia ao caminho FREQUENTE. `verificacao-async/SKILL.md` (FASE
1, referencia de qualidade) nao tem esse problema.

CLAUDE.md e README.md (raiz do projeto) nao mencionam FREQUENTE, o problema fica contido na camada
de scripts/rotina, nao vazou para a documentacao mais lida.

**Correcao:** atualizar os 26 `$ProjectRoot`/`$VixRoot` para o caminho canonico e reescrever a
linha 109 de `noturno/SKILL.md` (e a equivalente em `matinal/SKILL.md`) para parar de recomendar
FREQUENTE. Nao aplicado nesta auditoria (readonly, mudanca abrange a camada operacional inteira,
decisao de quando/como fica com o usuario).
**Causa raiz:** a migracao teve um passo para Action de tarefa e um para worktree/git, mas nenhum
passo varreu o conteudo interno dos scripts nem os SKILL.md pela mesma string de caminho — uma
quarta superficie que ninguem cobriu porque a junction mascarava o sintoma.
**Guarda sistemica proposta:** check automatizado (candidato a pre-flight ou lint, molde de
`lint-encoding.ps1`) que reprova qualquer `.ps1` versionado ou `SKILL.md` de rotina Claude Desktop
com `FREQUENTE\Monitoramento de Credito` hardcoded fora de allowlist explicita. Nao implementado
ainda, proposta registrada aqui e no `references/audit-matrix.md` da skill de auditoria.

### P3 — Saida de dry-run do Ranking-Mensal (descontinuado) ficou untracked sem padrao de .gitignore

`Obsidian VIX Radar/SEO/Ranking SEO 2026-08 (dryrun).md` e `scripts/seo/ranking_state.dryrun.json`
(ambos gerados 18/08 22h22, claramente durante a propria investigacao que decidiu descontinuar
`VIXRadar-Ranking-Mensal`) sao untracked. O projeto ja tem o padrao para isso (`data/reconciliacao/
dryrun/`, `data/historico/.dryrun/` no `.gitignore`), so nao foi generalizado para este caminho —
primeira vez que esta rotina roda em modo dry-run. Como o script fica em quarentena (nao apagado),
qualquer novo teste manual repete o ruido. **Correcao:** adicionar `scripts/seo/*.dryrun.json` e
o padrao equivalente em `Obsidian VIX Radar/SEO/*(dryrun)*.md` ao `.gitignore`, ou apagar os dois
arquivos (zero valor operacional, decisao de descontinuar ja documentada em local com evidencia
melhor). Nao aplicado nesta auditoria, fica para o usuario escolher.

### Confirmado (sem achado novo) — subsistemas de hoje

`CHAVEESCOPO1` (`REMOTE_VERIFICACAO_KEY` existe como secret vivo em producao, confirmado via
`wrangler secret list`, escopo restrito as 3 acoes de verificacao confirmado por leitura direta do
codigo), `CONCORVERIF1` (reserva atomica, fail-open documentado e correto) e `HEARTBEATVERIF1`
(agente `verificacao_async` no watchdog, limite 16h) auditados por leitura de diff + evidencia de
producao em `status/ESTADO.md`. Nenhum binding novo em `wrangler.toml` hoje. `references/
audit-matrix.md` da skill `vix-radar-general-audit` (revisao anterior 27/07, defasada) atualizado
com os 3 subsistemas + secao nova "Watchdogs locais de rotina" cobrindo o par
`retry-vixradar.ps1`/`monitor-tasks.ps1` e o risco de regex de `FIM:` divergente entre os dois
(mesma causa do retry falso de 17/08, ja corrigido, commit `ad06ad4`). Script obrigatorio de
veracidade de UI (`audit-ui-metrics.mjs`) rodado: exit 0, 0 bloqueante, 3 termos reservados
conferidos manualmente contra o glossario, todos batendo.

---

## 18/08 — execução: rotação da routine_key + envelope + limpeza (detalhe: [[86 - Rotacao routine_key e envelope noturno 2026-08-18]])

### RESOLVIDO 18/08 — P1 rotação da routine_key

Chave rotacionada nos 3 destinos (GitHub Actions criado, Worker, env User). Validação: 200 com a nova, 403 com inválida. Guarda nova ROTA1: os 3 scripts de rotina hidratam a chave do registro User sempre, processo longevo não manda mais chave morta. O secret nunca existiu no GitHub (C2 confirmado com evidência: repo tinha só ADMIN_PASSWORD), portão do script ajustado para criar.

### RESOLVIDO 18/08 — P2 envelope da noturna (recalibração, sem deploy)

Estimativa do envelope recalibrada para o custo medido (9,5k/emissor na rápida) na skill viva e na cópia versionada. Regra dura anti-replay de subagente adicionada (o vazamento de 142k do 17/08). Efeito real será medido no noturno de 18/08.

### RESOLVIDO 18/08 — P3 graphify-out versionado

`graphify-out/` no .gitignore + `git rm -r --cached`. Working tree sem o ruído da ferramenta.

### RESOLVIDO 18/08 — Pre-flight: 4 scripts vivos com P0

gen-dashboard (BOM), cf-token-status e build-worker (Stop→Continue + exit), collect_cotacoes (Stop→Continue, roda no Task Scheduler).

### RESOLVIDO 18/08 — Drift das skills do Desktop

Noturno e matinal sincronizadas da viva para a versionada. Verificacao-async em dia.

### P2 — ANTHROPIC_API_KEY continua ausente no GitHub Actions

O scan-emergencia usa `secrets.ANTHROPIC_API_KEY` no passo que faz a varredura real, e esse secret também não existe no repo. ROUTINE_API_KEY foi criada na rotação, mas o fallback de emergência segue morto de fato: morreria no primeiro fetch de LLM exatamente no dia em que precisasse rodar. Decidir: criar o secret com a chave paga local, ou remover o passo LLM do workflow.

### P3 — ~20 scripts de ferramenta com ErrorActionPreference Stop

register-*, deploy-pages, lint-encoding, check-drift, check-vault-drift, dry-run, verify-rotinas-v2, atualizar_altman_cvm, seed_labels, install-hooks, skills-audit, push-health, criar-token-dns, unificar-cf-token, apply-security-rotation, disable-vixradar-noturno-task, register-coleta/export/monitor/ranking/reconciliacao, run_vixradar_ranking_mensal, fix_task_coleta_volatilidade, skills-verify-tokens. Nenhum roda no Task Scheduler (os que rodam foram corrigidos: collect_cotacoes, matinal, noturno, verificacao). Correção em lote com parse PS 5.1 de cada um, sessão dedicada.

### P4 — Worktrees órfãos de outras ferramentas poluem o pre-flight recursivo

`git worktree list` mostra 1 do Codex (C:\Users\User\.codex\worktrees), 5 do Traycer e 4 do Claude no caminho antigo (E:\Diretorio\Claude\Monitoramento de Credito\.claude\worktrees, que agora é junction para FREQUENTE). Os .ps1 dessas cópias entram no scan recursivo do pre-flight e geram P0 fantasma. Remover os sem mudança (`git worktree remove`) ou excluir paths de worktrees do scan.

### P4 — check-desktop-orquestrador-drift.ps1 não alertou o drift das skills

O drift noturno (19,4k vs 15,6k bytes) e o da matinal estavam lá há dias sem alerta. Rever por que o check não pegou (agendamento? comparação por hash errado?).

### RESOLVIDO nesta sessão de auditoria — Merton DD 0/103 (ver [[85 - Auditoria Geral e Preditiva 2026-08-18]])

Não resolvido na execução, permanece P2 com o plano de correção descrito na nota 85. Listado aqui para não se perder entre os blocos.

---

## 18/08 — auditoria geral + preditiva (readonly, detalhe: [[85 - Auditoria Geral e Preditiva 2026-08-18]])

### P2 — Merton DD nunca roda em producao (0/103 emissores)

`predictive_v1:latest` (run 17/08): `merton_dd` null em todos os emissores, driver `merton` nunca aparece. Causa: `market_cap` vazio no Altman e na volatilidade (nenhuma coleta preenche; o gate do codigo exige `market_cap > 0` de proposito). Codigo do modelo correto, Fase A de dados incompleta. Correcao: coletar market cap (cotacao x n. de acoes) ou declarar Merton em stand-by. Guarda: contador `com_merton` no payload do pipeline.

### P3 — graphify-out versionado sem .gitignore

Cache de tooling gerando 14 entradas de ruido no working tree a cada execucao. Adicionar `graphify-out/` ao .gitignore.

### P3 — email do admin hardcoded no frontend (app/index.html:4079)

Revelacao do item "Painel Admin" no cmdk por comparacao literal com o email. O JWT ja carrega `role:admin`; trocar a comparacao pelo role.

### P3 — divs clicaveis sem role/tabindex no Market Overview

mo-table-row e mo-heatmap-row nao sao alcancaveis por teclado. Adicionar role="button" + tabindex + handler de teclado, ou trocar por `<button>`.

### P3 — card "Sem alertas" sem declaracao de janela no proprio card

O indicador tem janela fixa de 30 dias ao lado do toggle 7D/30D do grafico; o glossario manda declarar. Trocar o sub para "X de Y emissores · 30 dias".

---

## 17/08 — sessão de custo/benefício e limpeza de fila (sem deploy)

### RESOLVIDO 17/08 — P2 express/openai órfãos no package.json (C3)

Zero import ou require de `express`/`openai` em todo o `api/`. Removidos com `npm uninstall`, `api/package.json` fica só com `@sentry/cloudflare` em dependencies. `npm ci` revalidado, árvore com os 3 pacotes esperados. Efeito só na próxima publicação, nada em produção mudou.

### RESOLVIDO 17/08 — P2 ~25 .ps1 sem commit, 12 reprovados no lint

Pendência estava vencida. `lint-encoding.ps1` varreu 63 arquivos, 63 OK, 0 risco, e o working tree não tem `.ps1` modificado. Foi fechado pelo commit `9764a3d` (18 arquivos regravados com BOM) e ficou aberto na fila por falta de reconciliação.

### RESOLVIDO 17/08 — P3 listar_plano_rotina devolveu 19 para top_n=15

Não é bug. `selecionarEmissoresPrioritarios` corta em `topN` e depois o mínimo por setor do v4.9.157 (`api/src/worker.js:8953`) adiciona emissores dos setores sem cobertura, senão setor com EWS perto de zero nunca entra no top-N. Na matinal de 15/08 isso somou 4. Contrato descreve `top_n` como se fosse teto, e ele é piso. Corrigir a redação do contrato, não o código.

### RESOLVIDO 17/08 — FIMRUN21, alerta 9001 falso do monitor desde 13/08

`monitor-tasks.ps1` lia só a última linha `FIM:` do log da rotina. O noturno de 15/08 escreveu duas, run-1 com `FIM: noturno 103/103 processados` e run-2 com `FIM: noturno run-2 11/11 emissores DEFERRED ... Total do dia 103/103 com analise real`. A segunda não casava com nenhum padrão de contador, `submit_ok` caía para -1 e disparava 9001 mesmo com o dia entregue inteiro. Vermelho crônico desde 13/08 escondendo sinal verdadeiro. Fix varre todas as linhas `FIM:` do dia e fica com o maior contador, mais padrão novo para `Total do dia N/M`. Validado contra o log real de 15/08, resultado `submitOk=103`, sem alerta.

### RESOLVIDO 17/08 — Portão de verificação saía verde com o sistema doente

A task do VS Code chamava `curl.exe -s` direto, que sai com código 0 mesmo quando o health responde `ok:false`. Novo `scripts/portao-verificacao.ps1` parseia o JSON e sai com 1 se qualquer flag obrigatória não vier `true`, cobrindo os 4 do CLAUDE.md mais `rate_limiter`, `admin_email_ok` e `verificador_ok`. Achado durante o próprio teste: `kv` e `telemetria` moram dentro de `bindings`, não na raiz, a primeira versão reprovava um health saudável. Portão virou build task padrão, Ctrl+Shift+B. `.vscode/tasks.json` ganhou verificar rotinas local e live, monitor de tasks, lint de encoding e drift do vault, que eram o braço do agendador faltando.

### P2 — Envelope da noturna, agora é a alavanca única de custo

Com plano Max a rotina local é flat, trocar modelo dela economiza zero. Dólar real só aparece quando a assinatura estoura o limite semanal e a execução cai na chave paga `VIXRADAR_ANTHROPIC_API_KEY`. O cap de 700k estourando toda noite (~70% acima do desenho) é o que consome a folga semanal. Recalibrar o envelope ou fixar modelo da fila rápida deixa de ser afinação e vira o item de maior retorno da fila inteira.

### P2 — ROUTINE_API_KEY do scan-emergencia continua não validada

Workflow verde nas 4 últimas noites (última 16/08 23:45), mas o log mostra só a checagem de idade do estado (`Idade do estado: 2h`) e saída pelo caminho no-op. A chave nunca é exercitada, então o verde não prova nada. Falharia exatamente no dia em que o fallback precisasse rodar. Validar por `workflow_dispatch` forçado ou junto da rotação.

---

## Abertas (15/08 — auditoria geral profunda)

Detalhe: [[83 - Auditoria Geral 2026-08-15]]. Plano completo: `C:\Users\User\.claude\plans\graceful-soaring-hopper.md`.

### RESOLVIDO 15/08 — Deploy v4.9.195 + v202.10 (correções locais da auditoria)

Worker v4.9.195 e frontend v202.10 no ar e validados em produção (commits `f4b8780`..`5175a97`). Health verde com todos os sub-checks, providers com perplexity "removido" e nivel normal, drift zerado, CI Worker Tests verde no push. Fecha OPENROUTER-ORFAO1 (alerta falso desde 30/07) e LLMXSS1 em produção.

### P1 — Rotação da routine_key (bloqueio de PAT pode ter caído em 17/08, não testado)

Chave redigida em 15/08 de `~/.claude/scheduled-tasks/gen_workflow.py` + `vixradar-noturno-v2.js` (com backup), mas cópias históricas em backups/transcripts seguem existindo e a chave não foi rotacionada. `rotate-routine-key.ps1` cobre os 3 destinos (Worker secret, GitHub Actions secret, env User da máquina). Bloqueava porque o `GH_TOKEN` ativo era um PAT fine-grained sem permissão de Secrets. Em 17/08, resolvendo um bloqueio parecido no `git push` (ver item abaixo), achamos que existe uma credencial OAuth já autenticada no keyring do Windows com escopo `repo` clássico, que inclui gerenciar secret de repositório, e que `GH_TOKEN` (mesmo vazio) segue tendo prioridade sobre ela. Não tentamos rodar `rotate-routine-key.ps1` ainda com esse keyring ativo, mas é candidato forte a destravar sem precisar mexer em PAT nenhum. Ao concluir, reiniciar o Claude Desktop antes da noturno 18:00 para a sessão absorver o env novo.

### RESOLVIDO 17/08 — P1 push de 3 commits bloqueado por credencial (regressão do incidente já documentado em 13/08)

`git push` reprovava com 403, PAT fine-grained sem escopo Contents. Ajustar a permissão do token pelo GitHub não bastou, e no meio da correção o usuário rodou `[Environment]::SetEnvironmentVariable('GH_TOKEN', ...)` duas vezes com erro, primeiro gravando o placeholder literal `cole-o-token-aqui`, depois esvaziando a variável, e colou o valor completo de um token fine-grained em texto puro no chat ao tentar corrigir. Achado real: a trava nunca foi permissão, `GH_TOKEN`, mesmo quebrado, tinha prioridade sobre uma credencial OAuth já autenticada e guardada no keyring do Windows (escopo `repo`, `read:org`, `gist`, `workflow`), suprimindo ela. Limpar `GH_TOKEN` (`$null` em escopo User) destravou o push na hora, sem gerar token novo. Os 3 commits (`960b56c`, `ed40757`, `2fc9216`) estão em `origin/main`, working tree limpo, `0 0` de diferença.

### P3 — Token fine-grained "Token name" exposto em texto puro no chat

Durante a correção acima, o valor completo desse token (o mesmo que teve a permissão Contents ajustada para Read/write) foi colado no chat pelo usuário. Não está mais em uso, `GH_TOKEN` foi removido e o push passou a usar o keyring, mas o valor ficou exposto no histórico da conversa. Regenerar ou apagar esse token específico por higiene quando for conveniente, sem urgência operacional.

### P2 — monitor-tasks.ps1 não detecta rotina completa sem linha FIM:

Achado na medição de cobertura de 17/08 (ver `03 - Estado Atual.md`, callout 05h10): 08/11 e 08/14 fecharam 103 de 103 emissores sem nunca escrever `FIM:` no log, um caminho de conclusão legítimo que o FIMRUN21 não cobre. Hoje isso cai em "sem linha FIM, execução não chegou ao fim" mesmo com o trabalho completo. Fix recomendado, ainda não implementado: quando não achar `FIM:`, `monitor-tasks.ps1` fazer fallback pra a mesma contagem por nome único de emissor usada na medição manual, antes de declarar 9001. Código puro, sem custo de token.

### P3 — routines/README.md descreve top_n como teto, e ele é piso

Achado junto do item RESOLVIDO do `top_n=15` devolvendo 19 (ver acima). O comportamento está correto, `selecionarEmissoresPrioritarios` garante mínimo por setor depois do corte. A correção pendente é só de redação em `routines/README.md`, ainda não editada.

### P2 — Orçamento da noturna (A1)

Cap de 700k estoura toda noite (~70% acima do desenho). Recalibrar envelope ou fixar modelo da fila rápida. A recuperação mecânica do defer (P1-2) foi RESOLVIDA nesta meta (DEFERREDREC1 com persistência real do flag nos 5 ramos).

### P2 — Validar ROUTINE_API_KEY do scan-emergencia no GitHub (C2)

Chave possivelmente morta desde 03/08; se morta, o fallback de emergência falha exatamente quando deveria rodar. Coberto junto da rotação.

### P2 — express/openai do package.json (C3)

Remover dependências não usadas no próximo ciclo de deploy.

### P3 — listar_plano_rotina devolveu 19 emissores para top_n=15 solicitado (matinal 15/08)

Plano da matinal de 15/08 trouxe `total=19` em vez dos 15 esperados pelo contrato (0 SKIP, 10 LIGHT, 9 FULL, 0 AUDIT). Rotina prosseguiu processando os 19 sem erro. Verificar se `top_n` está sendo respeitado na composição do plano no Worker, ou se a contagem por tier ignora o limite quando não há SKIP suficiente para completar a diferença. Detalhe: [[84 - Rotina Matinal 2026-08-15]].

### RESOLVIDO nesta meta (aguardando deploy): P1 matinal sem alarme, P1 governança do orquestrador, P2 REGDRIFT1, P2 timeouts de cron, P2 falso-verde CI

ROTINAGAP1 no watch-vixradar-health (alerta por rotina faltante com dedup por nome), 7 arquivos do Claude Desktop versionados em `routines/claude-desktop/` + `check-desktop-orquestrador-drift.ps1`, guarda dura nos 2 registradores legados + Disabled reproduzido no register-all, AbortSignal.timeout nos 6 fetches de cron, canonical-test fail-closed no rate_limiter.

---

## Abertas (13/08 — auditoria geral + execução)

### P0 — PARCIALMENTE RESOLVIDO: cascade de IA (AUTHWEEK1). Assinatura no limite semanal, chave paga recarregada

**Estado:** OAuth 429 "weekly limit, resets Aug 15, 8am" segue valendo para a assinatura. Chave paga `VIXRADAR_ANTHROPIC_API_KEY` **recarregada pelo operador 13/08 15h12** e validada (sonda exit 0). Dreno de 13/08 15h16-15h27 rodou por pay-per-token (11 eventos, 9 aprovados, 2 rejeitados, 223k tokens), health voltou a `ok:true`. Rotinas funcionam via chave paga até o reset de 15/08 08h BRT.

**Causa raiz:** três drenos de verificação em 12/08 (~2M tokens) + noturno completo estouraram o limite semanal da assinatura. A pendência de 04/08 ("recarregar crédito da chave paga") ficou 9 dias aberta.

**Guarda proposta:** notificação quando a sonda detectar 429 de limite semanal (a sonda já detecta, falta notificar).

### P1 — RESOLVIDO: secret ADMIN_PASSWORD do GitHub Actions (GHWL1)

**Estado:** gh reautenticado via OAuth (escopos repo/read:org/gist) após autorização do operador no device flow. Secret `ADMIN_PASSWORD` atualizado no GitHub Actions com a credencial recuperada do DPAPI local. Validação: run manual do frescor-check. Guarda nova: `scripts/check-gh-actions-health.ps1` (commit `f82872d`) + aviso reforçado no `apply-security-rotation.ps1`.

### P1 — RESOLVIDO: push bloqueado por credencial

**Estado:** origem era o token fine-grained sem Contents write (403). OAuth novo resolveu. Merge do `cbda7d1` (sessão paralela) feito, conflito do PENDENCIAS resolvido mantendo as duas visões. Push completo após este commit.

### P1 — FECHADO: BOM UTF-8 nos scripts

35 .ps1 varridos, 18 regravados com BOM byte a byte, parse PS 5.1 64/64 OK. Commit `9764a3d`. Pre-flight confirmou 0 EM DASH sem BOM nos scripts vivos.

### P2 — FECHADO e DEPLOYADO: XSS Market Overview (frontend + worker)

Frontend v202.8 no ar (escape nos 4 pontos do módulo v100). Worker **v4.9.193 no ar** com strip de HTML em `titulo`/`empresa` no `sanitizarPayloadRadar`. Deploy validado: `ok=true kv=true telemetria=true sentry_ok=true`, versão viva v4.9.193.

### Solicitações de acesso

1 nova solicitação 13/08 15h12 (WhatsApp admin enviado 1s depois, sem erro de email), já aprovada. KV: 34 usuários, 0 pendentes.

Detalhe completo: [[81 - Auditoria Geral e incidentes 2026-08-13]].

---

## Abertas (13/08 — pos v4.9.192 / CALVAL-V2, sessão paralela)

### Status geral

Reconciliado nesta sessao (checkout estava ~40 commits atras, atualizado via `git pull`). Todo o bloco anterior (04/08 a 11/08, ver "Fechadas — bloco 04-11/08" abaixo) esta **RESOLVIDO**. Rastreamento de pendencias havia migrado informalmente para notas de auditoria avulsas (77, 79, 80) sem consolidacao central; este bloco reconsolida os 6 itens reais em aberto hoje.

### P2 — ~25 scripts `.ps1` de rotina modificados sem commit, 12 reprovados pelo lint-staged

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Paths FREQUENTE + BOM alterados na sessao de 11/08 — sintaxe PS 6/7 em scripts que rodam sob PS 5.1 e BOM removido. Fora do escopo do CALVAL-V2, precisa sessao dedicada.

### P2 — canonical-test.yml: fix do post-mortem 77 nunca implementado

**Origem:** post-mortem 77 (05/08, verificador_ok). Correcao proposta para o workflow ficou em backlog aberto (item Jarvis), nao entrou no repo.

### P2 — Fila de verificacao >20h no fechamento do deploy CALVAL-V2 (12/08 23:33Z) — validar

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. 5 itens enfileirados 11/08 23:33Z cruzaram o SLA de 20h (VERIFSLA1) as 19:33Z de 12/08, derrubando `verificador_ok` no fechamento do deploy. Backlog pre-existente da fila (teto de token), sem relacao com CALVAL. O dreno async de 13/08 10:20 BRT deveria ter zerado — **nao confirmado em log ainda**. Conferir.

### P3 — CLOUDFLARE_API_TOKEN sem permissao Pages:Edit

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Deploy de Pages caiu para OAuth do wrangler (aviso do proprio `deploy-pages.ps1`). Adicionar a permissao Cloudflare Pages: Edit ao token.

### P3 — Rotina agenda-semanal rodando 1x/semana, regra pede 2x

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Regra 9 do CALVAL-V2 exige revalidacao 2x/semana (Dom+Qua) para cumprir plenamente. Aumentar frequencia da task local.

### P3 — postAdmin sem Authorization: Bearer

**Origem:** [[79 - Incidente ADMINRL-FIX1 429 painel admin 2026-08-12]]. Backlog registrado, ainda nao implementado.

---

## Fechadas (14/08 — execução das pendências da auditoria)

Worker v4.9.194 e frontend v202.9 no ar, commits `f8bcf7c`..`08e2557` pushed.

### RESOLVIDO — P0 AUTHWEEK1: guarda de notificação implementada

Novo `action=notificar_rotina` no Worker (auth routine_key, email ao admin via Resend) + `Send-VixRoutineAlert` na lib `vixradar-claude-auth.ps1`, chamado nos 3 pontos de abort por auth (matinal, noturno, verificacao-async) e validado no `Assert-VixLibFunctions`. Probe em producao: 403 com chave invalida, fail-closed confirmado. O reset da assinatura (15/08 08h) segue como evento externo; a partir de agora qualquer estouro de limite semanal notifica o admin na hora.

### RESOLVIDO — P2 canonical-test.yml: fix ja estava implementado

A pendencia estava errada. `canonical-test.yml:58-60` ja le `admin_email_ok`/`sentry_ok`/`verificador_ok` individuais (commits `15feb31` e `870b29f`) e as linhas 111-117 nomeiam o fator que caiu. Nada a implementar, item fechado por evidencia.

### RESOLVIDO — P3 agenda-semanal 2x/semana (CALVAL-V2 regra 9)

Task `VIXRadar-AgendaSemanal` atualizada no Scheduler: de Monday para Sunday+Wednesday 22h00 (DaysOfWeek=9), proximo disparo 16/08. `register-all-routines-scheduler.ps1` atualizado junto para a re-registracao nao reverter.

### RESOLVIDO — P3 postAdmin sem Authorization: Bearer

`app/admin/vr-admin-shared.js` agora usa `authHeaders()` (Bearer quando ha JWT local) + `admin_senha` no body. Deployado em v202.9.

### RESOLVIDO — P3 "Cobertura ANBIMA" terceiro sentido

Termo "Cobertura ANBIMA" adicionado ao `glossario-dominio.md` como termo qualificado proprio (disponibilidade da serie no arquivo de precos diario ANBIMA para um emissor), com a regra de nunca usar "Cobertura" simples para esse sentido.

### RESOLVIDO — P3 disjuntor de custo catch mudo (CUSTOBRAKE1)

`verificarDisjuntorDiario` agora loga `console.error` quando a leitura do KV falha, em vez de engolir. Deployado em v4.9.194.

### RESOLVIDO — P3 card "Sem alertas" sem denominador

Card do Market Overview agora declara "X de Y emissores". Deployado em v202.9.

### RESOLVIDO — P3 diretorios untracked

`Operacoes-Recorrentes/` (Trading View, repo proprio) movido para `FREQUENTE\Operacoes-Recorrentes\`, posicao de irmao dos projetos. `docs/entrevista-ff/` (material Financial Finesse) movido para `FREQUENTE\Emprego (1)\Finance\entrevista-ff\`. Working tree limpo.

---

## Abertas (14/08 — execução das pendências da auditoria)

### P3 — CLOUDFLARE_API_TOKEN sem Pages:Edit

Verificado em 14/08: token ativo mas `pages/projects` devolve Authentication error. A API do Cloudflare nao cria nem edita permissoes de token existente (dashboard-only). Passo manual: em https://dash.cloudflare.com/profile/api-tokens, criar token novo com "Cloudflare Pages: Edit" (zona/account `7ac79fb1030e4e81115ef33c21a9b070`) e gravar como `CLOUDFLARE_API_TOKEN` no registro User. Enquanto isso o deploy-pages segue funcional pelo fallback OAuth do wrangler (usado no deploy de hoje).

---

## Fechadas — bloco 04-11/08 (P0/P1/P2), RESOLVIDO

**Marcado resolvido em:** 13/08. Todos os itens abaixo foram superados por deploys subsequentes (Worker v4.9.186 -> v4.9.192, frontend v201.9x -> v202.7). Ja constavam RESOLVIDO individualmente no corpo original desta nota; consolidados aqui como historico, sem status ativo.

- **P0 — Verificador async quebrado por call sites orfaos (05/08):** corrigido 06/08, `Assert-VixLibFunctions` no ar.
- **P0 — Guarda ambiental bloqueando verificador async (04/08):** corrigido 06/08.
- **P1 — VERIFSLA1/VERIFSLA2, lookback do health 2 -> 7 dias:** deploy v4.9.190, 11/08.
- **P3 — Senha demo rotacionada:** 11/08.
- **P0 — Painel admin morto em producao desde 03/08 (modulos ES truncados):** deploy publicado 09/08 (v202.6), superado por v202.7.
- **P1 — Worker v4.9.187 (VALIDFIX1) aguardando deploy:** publicado, Worker avancou ate v4.9.192.
- **P0 — Credito zerado API Anthropic, rotinas paradas (04/08):** rotinas normalizadas a partir de 06/08, guardas estruturais no ar.
- **P1 — settings.json DeepSeek causando exit=1 no `claude -p` (27/07):** corrigido, guarda de ambiente permanente.
- **P2 — Probe pre-voo `Invoke-ClaudeBatch`:** 02/08.
- **P3 — Chaves ROUTINE_API_KEY mortas:** 03/08.
- **P1 — Matinal reportava sucesso com buscas falhando:** 02/08, 4 guardas aplicadas.
- **P2 — VIXRadar-Reconciliacao-CVM (bug PS 5.1):** 03/08.
- **P3 — VIXRadar-Coleta-Volatilidade:** 02/08.
- **P2 — VIXRadar-Export-Historico (token KV):** 02/08.
- **P2 — Guard em register-all-routines-scheduler.ps1:** 03/08.
- **P2 — monitor-tasks.ps1 inventava causa de falha:** 02/08.
- **P2 — Probe CLI antes da Noturno 18:00:** 02/08.
- **P3 — SHADOW1 (Fable 5):** 03/08, Sonnet mantido, shadow encerrado.
- **P3 — VIXRadar-Ranking-Mensal:** 03/08, decisao: remover.
- **P2 — Frescor da Ingestao / ADMIN_PASSWORD desatualizado no GitHub (27/07):** 27/07 16h45.
- **P2 — ADMIN_EMAIL ausente 3 dias, so telemetria viu:** 27/07 19h57, 2 guardas aplicadas (SECRETMISS1).
- **P2 — Cadastro de conta existente nao notificava admin:** 03/08.

---

## Fechadas (historico recente)

### P2 - Verificar se AgendaSemanal e Matinal se repetem sem erro apos falha da AgendaSemanal 27/07 03:00

**Fechado em:** 27/07 12:09.
**Descricao:** Confirmado: Matinal 10:00 repetiu o mesmo padrao de falha. Ambas morreram ao invocar `claude -p` com exit=1, log truncado, stderr vazio. Substituido pelo P1 "Investigar e corrigir causa raiz do exit=1".

### P2 - Verificar primeiro disparo da Matinal (27/07 10:00)

**Fechado em:** 27/07 12:09.
**Descricao:** Task disparou as 10:00 conforme previsto. Porem falhou com exit=1 (mesmo padrao da AgendaSemanal). Log `vixradar-matinal_20260727.log` com 8 linhas, truncado em "Lote sonnet-1". 0 emissores processados. Substituido pelo P1 de investigacao de causa raiz.

### Consolidar os dois PENDENCIAS.md

**Fechado em:** 27/07 (commit `76720a7`).
**Descricao:** Opcao A executada. `PENDENCIAS.md` da raiz (31 KB, fila aberta zero, conferido antes de mover) movido via `git mv` para `Obsidian VIX Radar\_Arquivo\PENDENCIAS (historico ate 2026-07-26).md`, com aviso de congelamento no topo. `Obsidian VIX Radar\PENDENCIAS.md` (este arquivo) passou a ser o canonico rastreado no git. `README.md` e `PROMPTS-RADAR.md` corrigidos, a linha 5 deste ultimo dizia que o arquivo da raiz vencia o Obsidian em conflito, isso teria virado instrucao falsa se nao corrigido.

### Monitor-Tasks — Registrador criado, task recriada e primeiro disparo validado

**Fechado em:** 27/07 07:04.
**Descricao:** `scripts\register-monitor-tasks.ps1` criado e executado. Task Ready no Scheduler, trigger diario 07:00. Primeiro disparo real confirmado: rodou 27/07 07:00:00, exit=7, `logs\monitor-tasks\monitor_20260727.log` (1863 bytes) e `erros_20260727.json` (4344 bytes) gerados. Exit 7 nao e falha do vigia, e a contagem de 7 tasks de terceiros (Szuchmacher-*, nao VIX Radar) com LastTaskResult nao-benigno que ele escaneou e reportou corretamente, exatamente a funcao para a qual foi recriado. Escaneou 12 tasks no total, 3 OK, 7 erros, 2 warnings (incluindo o achado novo da AgendaSemanal, ver P2 acima). `Get-ScheduledTaskInfo` confirma proxima execucao 28/07 07:00:00.

### SHADOW1 — Implementacao do piloto shadow mode Fable 5

**Fechado em:** 26/07.
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Encerrado 03/08 (ver bloco acima) — Sonnet mantido.

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Encerrado 03/08. Shadow Fable 5 avaliado (8 comparacoes, 0 falso-negativo do Sonnet capturado) — criterio nao atingido, Sonnet mantido como modelo primario.

---

*Atualizado em 2026-08-13 (reconciliacao pos-checkout: bloco 04-11/08 fechado, consolidados 6 itens reais em aberto vindos das notas 77/79/80).*

*Anterior: 2026-08-06 02h45 BRT (incidente 04-06/08 encerrado, fila drenada).*

*Anterior: 2026-08-04 12h BRT (auditoria geral: P0 do painel admin e P1 do Worker corrigidos no repo, os dois aguardando deploy).*

*Anterior: 2026-08-03 18h30 BRT (fila ZERADA: 4 P2 + 1 P4 + 2 P3 resolvidos. Shadow encerrado, Sonnet mantido. Ranking-Mensal: remover. Sessao SESSION-CLEANUP1 concluida.)*
