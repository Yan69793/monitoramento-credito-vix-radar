# 130 - Tarefas apagadas do Agendador, PDFs da CVM e resiliência (21/10/2026)

Estado: correções locais feitas e testadas, **sem commit, sem push, sem deploy**. Nenhuma rotina foi executada por este trabalho.

## Causa → correção → prova

| Causa comprovada | Correção local | Prova |
|---|---|---|
| Às 21:03:08 `NT AUTHORITY\System` apagou `VIXRADAR-NOTURNO` e `VIXRADAR-SENTINELA` (evento 141 do Agendador), e os scripts `preflight-and-run.ps1` e `run_vixradar_noturno.ps1` sumiram do disco no mesmo segundo. **Autor não provado.** Havia instalação do Avast (Cleanup/TuneUp) ativa nesse minuto e quatro tarefas do Defender foram apagadas 26 s antes, mas os logs do Avast são cifrados e a auditoria de segurança do Windows está desligada. | Restauração das tarefas (autorizada) e dos scripts (`git restore`). | `Get-ScheduledTask` mostrou as duas Ready, próximas execuções 22/10 09:25 e 18:05. |
| O Monitor-Tasks só percorre tarefas que existem. Tarefa apagada não gerava alerta. | `TAREFAAUSENTE1`: `lib/vixradar-tarefas-esperadas.ps1` + bloco em `monitor-tasks.ps1` (erro 9009) quando o motor é o Agendador. | `test-tarefa-ausente.ps1` 7/7. Ponta ruim: o monitor do HEAD não contém a função. Regressões do monitor 32/32, 28/28, 22/22. |
| A Matinal e a Noturna seguravam o mutex da Sentinela até o fim da execução (aquisição dupla, solta uma vez). A Noturna esperou 25 min. | `MUTEXVAZADO1`, commit local `2d5a20e`. | `test-mutex-sentinela-liberado.ps1` 3/3, duas pontas. |
| Execução morta antes do FIM não deixa linha de fechamento nem metrics, e o CUSTO_DIA contava 0 (noturno=0 com cerca de 1,1 M tokens gastos). | `CUSTOSEMFIM1` em `Get-VixRotinaLogConsumo` (soma os `LOTE_FECHADO` do trecho sem FIM; é um piso, o FIM real fica cerca de 30% acima). | `test-custosemfim1.ps1` 5/5. Contra o `vixradar-custo.ps1` do HEAD: caso da execução morta dá 0 e o cenário de 21/10 dá 70.000 em vez de 370.000. `test-custofim1-15out.ps1` 8/8. |
| O WebFetch do modelo recebe o PDF do ENET como binário (7, 11 e 11 anotações por dia em 19, 20 e 21/10) e a família F3 cai para busca web. | `CVMPDF1`: `lib/vixradar-cvm-pdf.ps1` baixa com `curl.exe --http1.1` e extrai com `pdftotext`. Campo `texto_extraido` dentro de `cvm_documentos`. **Desligado por padrão** (`VIXRADAR_CVM_PDF_TEXTO=1` liga). Allowlist do host do ENET, fail-open. | Download real do protocolo 1578010: 116.715 bytes, 10.257 caracteres legíveis (a primeira tentativa truncou, exit 56, por isso há segunda tentativa). `test-cvm-pdf-texto.ps1` 13/13 e `-Rede` OK. **Não validado de ponta a ponta numa rotina**, porque nenhuma rotina manual foi executada. |

## Fato novo que explica os 24 pendentes
`VIXRADAR_COBERTURA_DIARIA` está vazia, então a cobertura diária roda em modo SOMBRA (COBDIARIA1): grava o ledger e o relatório, mas **não coloca o pendente na frente da fila**. Os 24 emissores PENDENTE_IA do dia (notícia nova, tier SKIP no plano) ficaram registrados e sem análise. Ligar a variável é decisão do operador e custa tokens (cerca de 24 × 113 mil a 250 mil por dia).
`VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter` está ativa no ambiente. Se a assinatura falhar, a rotina pode desviar para OpenRouter (pago). Não foi acionado por este trabalho.

## Rollback
Pasta `E:\Diretorio\Claude\BACKUPS\operacional\vix-radar\cvmpdf1-custosemfim1-tarefaausente1-20261021\`:
- `*.pre.ps1` e `*.pos.ps1` (arquivo sem e com minhas alterações) e `rollback-minhas-alteracoes.diff.txt` (só as minhas linhas).
- `arquivos-novos-apagar-no-rollback.txt` lista os 5 arquivos novos.
- Os três arquivos editados também têm alterações de outras sessões. **Não usar `git restore` neles**, aplicar o diff reverso ou remover os blocos marcados `CVMPDF1`, `CUSTOSEMFIM1`, `TAREFAAUSENTE1`.
- CVMPDF1 sozinho se desliga sem tocar em arquivo: não definir `VIXRADAR_CVM_PDF_TEXTO`.
- Tarefas recriadas: `Unregister-ScheduledTask -TaskName VIXRadar-Noturno` e `VIXRadar-Sentinela`, e apagar os wrappers `task_114BF3CDBF4B8AFFD629.vbs` e `task_6F3250D742A0779A867C.vbs`.

## Arquitetura recomendada (operar com o PC desligado)
Não existe prova de que a assinatura Claude funcione em infraestrutura remota (termos de uso e limite de sessão não verificados). Por isso a proposta não migra a análise.

1. **Plano de controle na Cloudflare (já existe parcialmente).** O Worker já tem o plano (`listar_plano_rotina`), a fila de verificação, `deferred_prioritario`, heartbeats e o watchdog das 22:00. Acrescentar: heartbeat do executor local com alerta "executor offline" em horas (hoje são 26 h), e lease por emissor (reservar, confirmar, expirar) para retomada idempotente por qualquer executor.
2. **Camada determinística remota, sem LLM.** Mover a triagem de notícias (RSS) e a priorização para o Worker. Com o PC desligado o sistema continuaria sabendo quem tem fato novo e ordenaria a fila por risco, materialidade e idade da análise. Custo marginal quase nulo.
3. **Execução de IA local, como hoje**, na assinatura (custo fixo, qualidade conhecida, fontes primárias, escalação e controles de evidência preservados).
4. **Contingência remota só para críticos**, depois de autorização: Haiku com busca nativa (já existe no cascade do Worker) ou OpenRouter, para emissores com EWS alto ou termo crítico, marcando `provedor` e **nunca substituindo** análise local válida. Resultado incompleto continua INCONCLUSIVO (fail-closed).
5. **Máquina sempre ligada** (nobreak no PC atual, ou um segundo host) só depois de testar se o token longevo da assinatura roda lá, dentro dos termos.

Custo, ordem de grandeza (preços de lista que conheço, **não verificados hoje**): a carga de 21/10 foi cerca de 3,7 M tokens de trabalho (cerca de 45% saída). Migrar tudo para API paga daria na casa de US$ 35 por dia (cerca de US$ 1.000 por mês). A contingência só dos críticos (10 emissores por dia) ficaria perto de US$ 5 por dia com Sonnet e menos com Haiku.

## Rodada 2 (22/10/2026): confronto com a auditoria adversarial do DeepSeek
Auditoria lida de `E:\Downloads\Texto colado(20261022-021820).txt` (fora do repositório). Correções locais, **sem commit, sem deploy, nenhuma rotina executada**.

| Item | Causa comprovada | Correção | Prova |
|---|---|---|---|
| F6 provedor falso | `$fonteProvedor = 'openrouter'` era o default para tudo que não é codex. Medido nos logs de 21/10: 294 fontes com `openrouter:` e 0 com `claude:`. | `PROVENIENCIA1`: rótulo vem do provider que executa; `claude` entra na allowlist (exige HTTP 2xx); o orquestrador reescreve o provedor e guarda `provedor_declarado`. | `test-proveniencia1.ps1` 45 verificações, 0 falhas (inclui fallback, retry, três horários, modos estrito e janela e C5). |
| F7 timestamp inventado | Medido: 271 de 361 timestamps (75%) caem fora de qualquer janela de execução do dia (a auditoria falou em 100% da amostra). O validador só exigia campo não vazio. | Horário fora da janela medida do lote é reescrito com o horário do orquestrador (`timestamp_declarado` preservado). Sem janela medida, o campo é esvaziado e o portão recusa (fail-closed). | Mesmo teste, fixture do lote de 20:14Z a 22:22Z. 429 e provedor desconhecido continuam recusados. |
| F5 saldo_dia=0 | A conta do dia estava certa: a auditoria somou 2.204.668 e **esqueceu a Agenda (631.910)**, o real era 2.836.578 contra teto 2.600.000, circuito aberto. O defeito é outro: a cobertura diária ignorava `SEM_TETO=1` (o motor ignora o circuito) e o motivo `primario_indisponivel_claude_desligado` não dizia a causa. | `CAPACIDADE1`: `Get-VixCapacidadePrimario` aplica a mesma regra do motor e a linha `COBDIARIA_CAPACIDADE` passa a trazer disjuntor, circuito, sem_teto, margem, reserva e motivo. | `test-capacidade1.ps1` 38 verificações, 0 falhas (inclui C1 e o SEM_TETO por provider efetivo). Codex e OpenRouter continuam com teto. |
| F11 custo concorrente | A Noturna lia a Matinal em curso como 0 porque só o FIM entrava na conta. | `CUSTOSEMFIM1` já conta os lotes da execução em curso (caso F do teste). | `test-custosemfim1.ps1` 7 verificações. |
| F2/F3 morte e relançamento | **Causa fechada pela evidência que a auditoria não tinha:** a exclusão da tarefa (evento 141, 21:03:08) encerra a instância em execução; o relançamento das 21:40:43 foi o `Start-ScheduledTask` autorizado depois que as tarefas foram recriadas (wrappers reescritos às 21:40:27). Um lote morto antes de qualquer submit não produz nada que se possa salvar. | `PROGRESSO1`: `<rotina>_progresso_<data>.jsonl` (início, fechamento, retomada) e linha `RETOMADA` no log quando a instância anterior morreu com lote em voo. Não decide o que analisar (o plano do Worker continua decidindo). | `test-progresso1.ps1` 14 verificações, com processo filho morto por `Stop-Process`. |
| F1 mutex | Corrigido na rodada 1. Guarda geral nova varre todos os `scripts\*.ps1` atrás do padrão que vazou. | Teste ampliado. | `test-mutex-sentinela-liberado.ps1` 6 verificações. A homologação em campo é a Sentinela de 22/10 09:25. |
| F8 PDF | Integração do `CVMPDF1` ao payload testada. | `test-cvmpdf-integracao.ps1` 9 verificações (flag desligada, ligada, falha, allowlist). | Continua desligado por padrão. |

Não corrigido, por exigir decisão, deploy ou alterar prompt/modelo: F4/R1 (campo de cobertura no health do Worker), F9 (48% é cobertura de atribuição de 9 mil documentos a 104 emissores; a auditoria a chama de restrição estrutural, não está provado), F10 (selo de driver morto na UI), F12 (status da Agenda com `pulados>0`), F13 (alarme de validade do EWS 2.0), F14 (preflight de 9 min), F15 (pacote EWS 2.0 duplicado), F16 (Matinal promove Sonnet no passe barato, altera modelo).

Rollback da rodada 2: `BACKUPS\operacional\vix-radar\proveniencia1-capacidade1-progresso1-20261022\` (`rollback-rodada2.diff.txt`, snapshots e lista de arquivos novos). Marcadores no código: PROVENIENCIA1, CAPACIDADE1, PROGRESSO1, CUSTOSEMFIM1, CVMPDF1, TAREFAAUSENTE1.

## Rodada 3 (22/10/2026): revisão de PROVENIENCIA1 e CAPACIDADE1 e auditoria do DeepSeek
Divergências minhas, comprovadas e corrigidas localmente (sem commit, sem rotina real):
- **Provider após fallback:** `Invoke-ClaudeBatch` passou a devolver `ProviderExecutado`, `IniUtc` e `FimUtc`, e a origem é resolvida por emissor (principal ou retry).
- **Três horários:** `timestamp` original preservado; `consultado_em` só com horário declarado dentro da janela da invocação; `registrado_em` é o horário de processamento e nunca vira prova; sem prova a fonte é recusada pelo portão (fail-closed). Modo `janela` opcional (`VIXRADAR_PROVENIENCIA_MODO=janela`, não definido hoje, o padrão é estrito).
- **SEM_TETO:** vale só para o provider efetivo claude-subscription. Desvio de boot para OpenRouter não herda a assinatura da env. O fallback pago por lote exige teto normal com margem.
- **C1 (DeepSeek D1):** o fallback pago também é bloqueado quando o custo do dia não é mensurável ou o campo falta. Prova com dado real: metrics ilegível dá `mensuravel=False` com circuito fechado, caso em que a regra antiga liberaria o pago.
- **C5 (DeepSeek D6):** o payload enviado ao Worker carrega `_provider_executado` e o ledger grava `provider` (executado) e `provider_configurado`. O rótulo `provedor` do perfil, que o Worker já consome, não foi alterado.

Medição que pesa na decisão: nos logs de 21/10, 0 das fontes do modelo em 63 emissores tinham horário dentro da janela da invocação (o modelo escreve 13:00Z e 00:00Z redondos). No modo estrito a próxima rodada real reprova toda fonte do modelo. Recomendação: modo janela até o prompt receber o horário real (mudança de prompt, precisa de aval).

Auditoria do DeepSeek, ponto a ponto: D1, D2, D3, D6 e D4 procedem (D1 e D6 corrigidos agora; D3 e D4 dependem da decisão do modo de prova; D5 é latente, a ponte DeepSeek venceu em 26/09). D7 estava errado: a pasta `proveniencia2-capacidade2-20261022` cobre a rodada 3 e o teste ajustado. Falta provar o rollback aplicando e revertendo numa cópia.
## Rodada 4 (22.10.2026 02:51): 24 pendentes de IA e 4 rechecagens inconclusivas
Sem commit, sem deploy, nenhuma rotina executada, Agendador e variaveis intocados.

- **4 rechecagens = 1 de verdade (RECHECKLIQUIDO1, corrigido local).** Bradesco, VLI e MRS cairam no portao de ausencia na rodada barata (divergencia IA x coletor), foram retidos para a escalada e fecharam RESOLVIDO no FULL da mesma noite (22:33). O contador `cobertura_deferidos` so somava disparos, entao `pendentes_obrigatorios=4` e o Agendador gravou exit 10 enquanto o contrato do dia dizia `contrato_inconclusivo=1`. Agora a conta usa o estado final por emissor (`Update-VixRecheckExecucao`); o numero antigo segue no log como `recheck_eventos`. Prova: `scripts/test-recheck-liquido1.ps1` 18/18 em PS 5.1, com replay do log real (disparos=4, final=1, bate com o contrato) e ponta ruim contra o HEAD. Regressoes: cobertura-contrato 29/29, triado-merge 11/11, cobertura-escalada 96/96, cobertura-recuperacao 72/72, lint-encoding e check-claude-free exit 0. Rollback: `BACKUPS\operacional\vix-radar\recheckliquido1-20261022-024856\`.
- **A unica inconclusiva real e a Itausa**: 2 de 10 buscas degradadas (PDF do ENET ilegivel e 403 no acionista.com.br). O portao BUSCADEGRADADA1-FIX (decisao do operador de 09/09) proibe sem_eventos com qualquer degradada, mesmo com fallback ok na familia. Nao afrouxei. O caminho que resolve sem perder qualidade e ligar `VIXRADAR_CVM_PDF_TEXTO=1` (CVMPDF1), decisao do operador.
- **24 PENDENTE_IA = 23 tier SKIP do plano + Itausa.** Com `VIXRADAR_COBERTURA_DIARIA` vazia a cobertura diaria fica em SOMBRA e nao coloca pendente na fila. O motivo `primario_indisponivel_claude_desligado` era falso (SEM_TETO ignora o circuito), ja corrigido por CAPACIDADE1. Sem ligar o modo, nenhum patch de codigo analisa esses 24; ligar custa cerca de 23 x 112 mil tokens por dia da assinatura.
- **Fallback desabilitado:** `claude_fallback=0` na linha COBDIARIA_CAPACIDADE e coerente, a assinatura respondeu o dia todo (`auth_escalou=nenhum`, `falhas_provider=0`). Nao e causa.
- **Agendador x execucao real:** Noturno 10 (PARCIAL por 4, real 1, corrigido acima). Verificacao-Async 6 na das 19:15 (2 pareceres com confianca abaixo de 0,8, Oncoclinicas e Oi), drenados pela execucao das 19:27 com OK. O Agendador guarda so a execucao agendada, o dreno seguinte nao aparece la. Sem mudanca de codigo.
### Rodada 4, ativacoes (22.10.2026 02:59, autorizadas pelo operador nesta sessao)
- `VIXRADAR_COBERTURA_DIARIA=1` (User) pelo script oficial. Recibo 9/9 depois de mover uma trava orfa da Noturna de 19/10 (PID 24936 morto) que reprovava o check 7c do `test-vixfix-20261006.ps1`. Rollback: `cobertura-diaria-ativacao.ps1 -Acao Reverter`.
- `VIXRADAR_CVM_PDF_TEXTO=1` (User). `Test-VixCvmPdfTextoHabilitado` devolve True, `pdftotext` encontrado no Git. `test-cvm-pdf-texto` e `test-cvmpdf-integracao` com 0 falhas. Rollback: apagar a variavel.
- Nenhuma rotina executada. Homologacao em campo: Matinal de 22/10 10:06.