# Estado do projeto — VIX Radar

Última atualização: 2026-08-24 (agente: Claude Opus 5)

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

- RESOLVIDO e DEPLOYADO 24/08 (EMAILSILENT1, Worker v4.9.214, commit `db2842e`): falha de envio de e-mail transacional era invisível por construção. Quatro `catch {}` vazios em volta da Resend e um `console.error` solto, então aprovar alguém devolvia `ok:true` tivesse a mensagem saído ou não, e a única fonte autoritativa era o painel da Resend, fora do sistema. Motivador: `joao.tavano@mirabaud.com.br` aprovado sem forma interna de saber se o e-mail chegou. A varredura dos 16 call sites achou dois erros na lista original, `handleSolicitarReset` já tinha `console.error` e `handleAdminRejeitar` tinha o defeito e não estava citado. Corrigidos os 5 caminhos cujo destinatário é o usuário final. `enviarEmailRastreado` centraliza e nunca lança, a aprovação continua valendo se o e-mail falhar. Rastro em KV `email_envio:{email}:{ts}` com TTL de 90 dias, consulta por `admin_email_envios` cruzando com bounce e complaint. `solicitar_reset` mantém resposta genérica de propósito, anti-enumeração. Guarda `api/test/email-falha-silenciosa.test.mjs`, 7 testes, prova de duas pontas medida contra o código pré-correção. Suíte em 76 testes, 12 arquivos, CI `Worker Tests` verde em `db2842e`. Produção validada no portão e por sonda, `admin_email_envios` sem senha devolve 403 onde o código antigo devolvia 401. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 24/08 (EMAILSILENT1 resíduo, P3): os dois envios de notificação ao admin em `handleRegistrar` (cadastro novo e reenvio com dedup de 24h) seguem fora do helper. Não são silenciosos, têm `console.log` mais evento de Analytics Engine, mas ficam sem rastro por destinatário e sem alerta na Sentry. Segundo item, `enviarResend` devolve o objeto único quando sobra 1 resultado, então lote de 2 com 1 falha retorna forma indistinguível de envio único bem-sucedido, o que engana quem for instrumentar os call sites de lote
- RESOLVIDO 24/08 (CURADORIA1, Marco 1): os quatro cards de risco da Braskem apareciam vazios com "Pendente" no dia do protocolo de recuperação extrajudicial. Não era falha de coleta. `METRICAS_CURADAS` é tabela curada à mão dentro de `app/index.html`, e o commit `b13b605` da troca de carteira mexeu só no backend. Medido: carteira 103, curadas 101, e Braskem fora até do menu, enquanto a AES Brasil já fora da carteira seguia nos dois. Braskem, Tupy e Itaú Unibanco ganharam card com número de fonte primária, o schema ganhou `as_of`/`source_date`/`metric_type`, o placeholder deixou de prometer "Cobertura · ICSD" (métrica que nenhum emissor tem) e o painel passou a exibir a idade do dado. Guarda nova `scripts/check-metricas-curadas.mjs` no CI, três pontas provadas. Frontend v202.32 (v202.31 corrigida no mesmo dia, a idade do card usava Math.round e exibia "ontem" para fonte do proprio dia). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 24/08 (CURADORIA1 Marco 2, P2): os 101 emissores herdados seguem sem datação legível por máquina, 257 das 404 células declaram 4T25 em agosto de 2026. Aparecem como pendência declarada na guarda (400 cards) e ainda não reprovam. A régua de ITR reprovaria todos hoje, o trimestre exigido é 2026-03-31. Recuração é lote próprio. Achado no caminho e já corrigido: o card de Rating do Vamos exibia AAA(bra) com perspectiva estável, quando a Fitch rebaixou para AA+(bra) com perspectiva negativa em 28/08/2024
- ABERTO 24/08 (BRASKEMDETECT1, P1): a Braskem protocolou recuperação extrajudicial em 24/08, US$ 10,9 bi reestruturados, e o sistema não pegou. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch de 17/08, não o protocolo do mesmo dia. O painel segue com 20/08 como fato mais recente. Duas causas somadas, o ZIP da CVM em 404 desde 23/08 tirou o gatilho primário, e a busca de imprensa sozinha não alcançou o protocolo. Liga na decisão pendente sobre fonte alternativa. **Adendo 19h48:** o print do operador mostra o protocolo já na timeline da Braskem, card CRÍTICO de 2026-08-24 com fonte `braziljournal.com` e cabeçalho "Analisado às 15:09", ou seja o evento entrou por imprensa depois da auditoria e o painel não está mais cego para ele. A causa raiz continua de pé e não há guarda de captura, então a pendência segue aberta, mas o enunciado "o sistema não pegou" caducou. Não confirmado no servidor nesta sessão, `op=state` exige autenticação (HTTP 401). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (SENDASGPA1 + RELOGIO3H1, commit `2928a74`, deploy `acf920d`): dois defeitos corrigidos e em produção desde 24/08 17:44 BRT (v4.9.213, validado por loop de 1 min). Alias contraditório entregava documento do Assaí para o Pão de Açúcar, e `_last_scanned_at` nascia 3h no passado para todo emissor com evento, inflando o gate de frescor. Guardas novas com prova das duas pontas, `scripts/check-alias-coerencia.mjs` e `api/test/relogio-varredura.test.mjs`. Suíte em 69 testes, 11 arquivos, CI verde. Produção em v4.9.213
- RESOLVIDO 24/08 (CALIB3 + ORDEMRAPIDA1 + SHADOWFALSOVERDE1, commit `2928a74`): três defeitos no script da noturna, achados observando a rodada rodar. A calibragem de token que eu havia colocado de manhã estava 4x alta e deferiu 15 emissores à toa, a fila rápida não era ordenada por risco apesar do comentário afirmar que era, e `parse_fail` do shadow saía rotulado `match` em 22 de 70 comparações. Não precisa de deploy, vale na próxima execução. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (CARTEIRA-24AGO1): AES Brasil saiu da carteira, Braskem entrou. Total segue 103, Worker v4.9.212, commit `b13b605`. Restam 3 emissores sem registro ativo na CVM, tolerados com motivo declarado na guarda (Banco Pan, Banco Votorantim, Nexa Resources). Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- RESOLVIDO 24/08 (era ABERTO, NOMEMORTO1): eram 4 emissores sem registro ativo na CVM, tolerados com motivo declarado em `scripts/check-emissores-cadastro.mjs`. AES Brasil (incorporada pela Auren, fundir ou remover), Banco Pan e Banco Votorantim (fecharam capital, seguem emissores de dívida sem protocolo IPE), Nexa Resources (Luxemburgo via BDR, exceção permanente). Nenhum gera documento IPE, evento só por imprensa
- RESOLVIDO 24/08 (cobertura): Braskem entrou na carteira em v4.9.212
- RESOLVIDO 24/08 (NOMEMORTO1 + ACENTOMATCH1): emissor renomeado ficava cego por defeito de tabela de alias, nove meses no caso da Eletrobras. Worker v4.9.211, commit `e55d68d`, 62 testes. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
- ABERTO 24/08 (CVMURL404, P1, depende da CVM): `ipe_cia_aberta_2026.zip` continua 404 no servidor da CVM desde 23/08. Enquanto não voltar, não entra Fato Relevante nem Comunicado ao Mercado, e o evento novo depende só de imprensa e RAD. O Worker já detecta e alerta: `cvm_fonte_falha_dura`, `cvm_fonte_idade_dias` e `cvm_fonte_degrada_servico` no health público, e `frescor-check.yml` nomeando o campo. Após 4 syncs falhos seguidos o `ok` agregado cai e o `canonical-test` fica vermelho. Nada a fazer do nosso lado além de acompanhar. Detalhe em `Obsidian VIX Radar/PENDENCIAS.md`
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
