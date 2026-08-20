---
data: 2026-08-14
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

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
