---
data: 2026-07-27
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## Abertas (27/07 13h30)

> [!warning] Estado de task nao se afirma aqui
> Situacao de task do Scheduler mora em [[03b - Infraestrutura]], derivada de `Get-ScheduledTask`.
> Esta nota cita, nao redeclara. Em 27/07 tres itens daqui diziam "task removida" durante uma
> hora depois das tasks terem sido recriadas, porque as duas notas descreviam o mesmo estado
> sem nada amarrando uma na outra.

### P1 — RESOLVIDO 27/07 13h. Causa raiz do exit=1 ao invocar `claude -p` era o settings.json global, nao quota

**Origem:** Auditoria 27/07 12h09, causa raiz fechada na auditoria geral das 13h (ver [[69 - Auditoria Geral 2026-07-27]]).
**Descricao:** AgendaSemanal (03:00) e Matinal (10:00) falharam com exit=1, log truncado exatamente na chamada ao binario `claude`, stderr com 0 bytes.

**A hipotese anterior (quota/OAuth transitoria) estava ERRADA.** O probe manual das 12h09 respondeu porque rodou numa sessao interativa do app desktop, que sobrescreve `ANTHROPIC_BASE_URL` de volta para `api.anthropic.com`. O agendador nao tem esse override.

**Causa raiz confirmada:** `C:\Users\User\.claude\settings.json` foi alterado em **26/07 17:59** introduzindo um bloco `env` de roteamento DeepSeek:
```
ANTHROPIC_BASE_URL = https://api.deepseek.com/anthropic
ANTHROPIC_MODEL / DEFAULT_OPUS / DEFAULT_SONNET = deepseek-v4-pro
ANTHROPIC_DEFAULT_HAIKU_MODEL = deepseek-v4-flash
CLAUDE_CODE_SUBAGENT_MODEL = deepseek-v4-flash
model = deepseek-v4-pro
```
As rotinas chamam `claude -p --model claude-sonnet-4-6`. Num processo do Task Scheduler, que le o settings.json direto e sem override, isso enviava um modelo Claude para o endpoint da DeepSeek e o processo morria sem escrever stderr.

**Evidencia que isola a causa:** a Monitor-Tasks das 07:00, unica rotina que **nao** usa `claude -p`, rodou normalmente no mesmo dia. As duas que usam falharam. E o mesmo bloco quebrava todo subagente do Claude Code com "deepseek-v4-flash may not exist" (8 tentativas, 4 tipos de agente, 3 overrides de modelo, todas identicas).

**Correcao aplicada 27/07 ~13h:** bloco `env` e chave `model` removidos do settings.json. Backup em `settings.json.bak-20260727`. Hooks (PreToolUse, PostToolUse, Stop) e demais chaves preservados, validado por diff e parse JSON.

**Validacao executada:** probe `claude -p --model claude-sonnet-4-6` em processo `powershell.exe -NoProfile` com todas as variaveis `ANTHROPIC_*` e `CLAUDE_CODE_SUBAGENT_MODEL` explicitamente removidas, dependendo unicamente do settings.json: **exit 0**. Essa e exatamente a condicao do agendador.

**Acao remanescente:** (a) confirmar Noturno 27/07 18:00 com exit 0; (b) decidir se re-executa a matinal de hoje para recuperar a cobertura top-15 perdida; (c) o pedido original da pendencia continua valido e vira item proprio: `Invoke-ClaudeBatch` deveria ter um probe pre-voo que aborta com log claro em vez de morrer silencioso com stderr vazio, que foi o que tornou este diagnostico caro.
**Validacao:** log noturno 27/07 com exit 0 e submit_ok compativel com o universo.

### P2 — Probe pre-voo em `Invoke-ClaudeBatch` (falha silenciosa custou o diagnostico)

**Origem:** Desdobramento do P1 acima, 27/07.
**Descricao:** As duas rotinas morreram com stderr de 0 bytes e log truncado no meio. Nao havia nenhum sinal do que falhou. O diagnostico so foi possivel cruzando o timestamp do settings.json com a lista de tasks que usam ou nao `claude -p`.
**Acao:** antes do primeiro lote, invocar `claude -p` com prompt trivial e validar exit 0 mais envelope JSON. Se falhar, abortar a rotina com log nomeando o erro (modelo, endpoint, exit code) em vez de seguir para o lote e morrer sem rastro.
**Validacao:** simular endpoint invalido e confirmar que a rotina aborta com mensagem legivel.

### P3 — Limpar chaves ROUTINE_API_KEY mortas e corrigir o fallback que serve chave morta

**Origem:** Auditoria geral 27/07.
**Descricao:** A chave `mXE2...` (48 chars) aparece em 5 arquivos rastreados (`Obsidian VIX Radar/rotinas/2026-06-22-haiku-12.md`, `Obsidian VIX Radar/rotinas/2026-07-02-noturno-v2.md`, `scripts/_archive/ipad-matinal.md`, `scripts/_archive/ipad-noturno.md`, `scripts/dry-run-rotinas-v2.ps1`), no historico do git (`a065027`, `bc3b77d`) e em 21 entradas de permissao do `.claude/settings.local.json`.

**Severidade e P3, nao P1.** A chave foi testada contra producao e **retorna 403**: ja foi rotacionada na Etapa 1 de 24/07 (commit `dfa6854`). A chave ATIVA (`OdCB...`, 43 chars) foi verificada e **nao aparece** em nenhum arquivo rastreado, no historico do git, no settings.local.json, nos SKILL.md das scheduled-tasks nem no Action da AgendaSemanal. Nao ha credencial viva exposta e **nao ha necessidade de rotacao**.

**Bug real embutido, este sim merece correcao:** `Get-RoutineKey` nas 4 rotinas cai num fallback que le `C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md`, e esse arquivo contem a chave MORTA. Se `$env:ROUTINE_API_KEY` sumir (maquina nova, perfil resetado, task rodando com outro usuario), a rotina nao falha com erro claro: pega a chave morta e toma 403 em toda chamada. O fallback hoje e armadilha, nao rede de seguranca.
**Acao:** remover a chave morta dos 5 arquivos e dos SKILL.md; trocar o fallback por `throw` explicito. Historico do git pode ficar, a chave esta morta.

### P1 — A matinal reportou sucesso com 100% das buscas falhando, e gravou em producao

**Origem:** Incidente 27/07 13:32, causado por execucao manual a partir de sessao contaminada.

**O que aconteceu.** A matinal foi relancada as 13:17 a partir do shell de uma sessao do
Claude Code que ainda tinha as variaveis DeepSeek exportadas. Corrigir o `settings.json` em
disco nao limpa o ambiente de um processo ja em execucao. O `--model claude-sonnet-4-6`
explicito protegeu o modelo principal, entao os lotes fecharam normalmente, mas o
**WebSearch usa o alias Haiku default**, que estava em `deepseek-v4-flash`. Todas as rodadas
de busca falharam. Mesmo assim:

```
13:32:08 FIM: tokens=120638 sonnet=8 haiku=10 submit_ok=18 submit_fail=0
                deferred=0 criticos=3 auth_fail=0 silent_fail=0
```

18 emissores gravados em producao com **zero das 9 rodadas** do protocolo, incluindo CRITICO
para Oi, Kora Saude e Light, e `sem_eventos:true` para GPA e CSN sem nenhuma busca. Todo
indicador de saude da rotina ficou verde: `submit_fail=0`, `auth_fail=0`, `silent_fail=0`.

**Causa raiz, e nao e o DeepSeek.** O roteamento foi o gatilho. O defeito e que
**a rotina nao mede o que declara medir**. Linha 421 de `run_vixradar_matinal_claude.ps1`:

```
Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>
```

O contador `buscas` e **autodeclarado pelo modelo**, nao apurado pelo script. O lote
`sonnet-1` reportou `buscas=12` enquanto as 12 buscas retornavam
"WebSearch indisponivel (modelo deepseek-v4-flash)". A metrica de cobertura vem de quem
esta sendo medido. Nao existe guarda que compare `fontes_consultadas[].resultado` com um
padrao de falha antes de submeter.

**Terceira ocorrencia da mesma familia hoje.** Um rotulo afirmando algo que o codigo nunca
apurou:
1. Card "Cobertura 62%" no dashboard, media outra coisa. Corrigido.
2. `monitor-tasks.ps1` deduzindo "Credit balance too low" pelo nome da task. Aberto.
3. `buscas=N` na matinal, contando rodadas declaradas e nao rodadas bem-sucedidas. Este.

O detector de veracidade da UI criado hoje so cobre o caso 1, porque so olha HTML. Os casos
2 e 3 sao a mesma doenca em PowerShell. A auditoria precisa de um check equivalente para
metrica de rotina, ver [[69 - Auditoria Geral 2026-07-27]].

**Acao (3 partes, nenhuma opcional):**
1. **Pre-flight de ambiente** no inicio das 4 rotinas: abortar com exit distinto se
   `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL` ou `CLAUDE_CODE_SUBAGENT_MODEL` tiverem
   valor que nao seja modelo Anthropic conhecido. Falhar cedo e barato, 120k tokens nao.
2. **Probe de WebSearch** antes do primeiro lote, custo aproximado 2k tokens: se a busca nao
   voltar, abortar antes de qualquer submit em vez de degradar em silencio.
3. **Parar de confiar no contador do modelo.** O script deve contar
   `fontes_consultadas` cujo `resultado` **nao** case com
   `indispon[ií]vel|falha|erro|n[aã]o execut` e submeter esse numero. Se buscas efetivas for
   0 num tier FULL, marcar o emissor como INCONCLUSIVO em vez de gravar classificacao.

4. **Dar saida ao dia envenenado.** A trava de idempotencia (linhas 527-547) monta a lista de
   "ja processados" lendo as linhas `OK|<nome>` **do proprio arquivo de log do dia**. Isso
   protege contra disparo duplo, que era o objetivo, mas cria uma armadilha: uma execucao
   ruim marca os emissores como feitos e **nao existe forma suportada de reprocessar**. Foi
   exatamente o que aconteceu aqui, o relancamento das 13:38 pulou os 18 contaminados e so
   processou 3. A saida foi renomear o log na mao. Adicionar `-Force` que ignora a trava, ou
   melhor, gravar as linhas `OK|` com o tier e um marcador de cobertura efetiva, para que a
   trava pule apenas execucao com cobertura valida.

**Validacao:** rodar a matinal com `ANTHROPIC_DEFAULT_HAIKU_MODEL` propositalmente invalido
e obter aborto antes do primeiro submit, com exit code proprio, `submit_ok=0`. Rodar em
seguida com `-Force` e confirmar que reprocessa emissor ja marcado como OK.

### Remediacao do incidente, concluida 27/07 14:40

Duas tentativas foram necessarias. A primeira, as 13:38, foi **no-op nos contaminados**: a
trava de idempotencia leu as linhas `OK|` da execucao suja e pulou os 18, processando apenas
3 emissores que ainda nao tinham sido tocados. Foi assim que o defeito 4 acima apareceu.

A segunda, as 14:03, funcionou depois de rotacionar o log para
`logs\routines\vixradar-matinal_20260727_CONTAMINADO_1317.log` (renomeado, nao apagado: e a
evidencia do incidente). Resultado:

```
14:16:25 FIM: tokens=123782 sonnet=7 haiku=7 submit_ok=14 submit_fail=0
              deferred=0 criticos=6 auth_fail=0 silent_fail=0
```

**Verificacao de que a cobertura foi real desta vez**, e nao autodeclarada: 31 rodadas
registradas no log, **0 ocorrencias de "deepseek"**, e 0 rodadas com resultado de falha. O
unico hit do grep de falha era falso positivo do proprio grep, a palavra "encerrou" contem
"erro". As buscas voltaram com dado substantivo ("Fitch perspectiva negativa; alavancagem
5,7x", "covenant violado 2024", "57,49% creditos aderidos; projecao reducao R$2B").

**O sinal mais forte de que a diferenca e real esta no verificador adversarial:**

| Rodada | Fila | Aprovados | Rejeitados |
|---|---|---|---|
| Contaminada (13:32) | 5 | 1 | **4** |
| Reprocessada (14:16) | 8 | **6** | 2 |

O verificador retratou 4 dos 5 eventos da rodada sem busca, via `retratarEventoRejeitado`,
que remove o evento do estado publicado. Ou seja a camada de verificacao **fez o trabalho
dela** e limpou a maior parte do estrago dos CRITICOs antes mesmo do reprocessamento. O que
ela nao alcanca sao os ECO e RELEVANTE, que nao entram na fila de verificacao, e esses
dependiam do reprocessamento.

**Licao que fica, e nao e sobre o DeepSeek.** A rodada contaminada exibiu
`submit_fail=0 auth_fail=0 silent_fail=0` e `buscas=12`. Todo indicador verde. O unico lugar
do sistema que percebeu o problema foi o verificador adversarial, que e caro e roda depois.
Uma checagem de tres linhas comparando `fontes_consultadas[].resultado` contra um padrao de
falha teria abortado antes do primeiro submit, de graca. Ver acao 3.

**Custo do incidente:** 120638 tokens na rodada perdida, 575214 no dreno que verificou dado
ruim, 123782 no reprocessamento, 261945 no dreno seguinte. Ver [[project_rotina_ambiente_limpo]].

### P2 — VIXRadar-Reconciliacao-CVM: task recriada, exit 1 continua aberto

**Origem:** Diagnostico de rotinas 27/07. **Reescrito 27/07 13h30.**
**Estado real (medido):** task **existe**, Ready, gatilho segunda 08h00, proximo disparo
03/08 08:00. Registrada em 27/07 12:24:08. A parte "recriar" desta pendencia esta **feita**.
O texto anterior dizia "a task foi removida" em cima de uma task viva, ver
[[03 - Estado Atual]] secao "Releitura 27/07 13h30".
**O que sobra:** o `exit 1` do ultimo log de 21/07, que ja existia **antes** da remocao e
nunca foi diagnosticado. Recriar a task nao consertou isso, so garantiu que ela volte a
disparar. Sem reconciliacao correta, dados podem divergir dos protocolos CVM sem deteccao.
**Acao:** investigar e corrigir o exit 1. Rebaixado de P1 para P2 porque a task voltou a
existir e o proximo disparo real e so em 03/08, ha margem.
**Validacao:** log `logs\routines\vixradar-reconciliacao-cvm_*.log` de 03/08 com exit 0.

### P3 — VIXRadar-Coleta-Volatilidade: recriada, falta ver o primeiro disparo real

**Origem:** Diagnostico de rotinas 27/07. **Reescrito 27/07 13h30.**
**Estado real (medido):** task **existe**, Ready, gatilho diario 17h00, registrada em
27/07 12:23:51. Recriacao **feita**. O `LastRunTime` que o Scheduler mostra e 30/11/1999
porque re-registrar zera o historico, nao porque a rotina nunca rodou: o ultimo log real e
de 23/07.
**Correcao junto:** `run_coleta_volatilidade.ps1` linhas 29 e 39, `pwsh` trocado por
`powershell.exe`. Vale manter mesmo agora que o PowerShell 7 foi instalado nesta maquina,
porque a instalacao e via Store e o `pwsh` nao resolve no contexto do Task Scheduler. Ver
memoria `project_powershell_5_1_e_pwsh7`.
**Atencao, corrigido 27/07 ~13h20:** essa troca de interpretador, sozinha, **teria
derrubado o disparo das 17h00**. `collect_cotacoes.ps1` usava ternario (linha 164) e
`-MaximumRetryCount`, sintaxe que so existe no PS7, e `upload_volatilidade_kv.ps1` estava
sem BOM com travessao dentro de string: os dois falhavam no parse sob 5.1. Pior, falhariam
em **silencio**, porque o `try/catch` do chamador nao captura falha de processo filho, e a
rotina logaria "sucesso=" vazio e seguiria. Corrigido em `642e599`. Detalhe completo em
[[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]].
**Acao:** observar o disparo de hoje 17h00. Se falhar, a causa e outra, nao esta.
**Validacao:** `logs\routines\coleta_volatilidade_20260727*.log` existir com exit 0.

### P3 — VIXRadar-Export-Historico: recriada, falta ver o primeiro disparo real

**Origem:** Diagnostico de rotinas 27/07. **Reescrito 27/07 13h30.**
**Estado real (medido):** task **existe**, Ready, gatilho diario 20h45, registrada em
27/07 12:23:58. Recriacao **feita**. Backups pararam entre 22/07 e hoje, 5 dias sem export.
**Acao:** so observar o disparo de hoje 20h45.
**Validacao:** `logs\routines\vixradar-export_20260727*.log` existir com exit 0.

### P2 - Guard em register-all-routines-scheduler.ps1, o nome engana e o script derruba o disparo do dia

**Origem:** Revisao do diagnostico 27/07.
**Descricao:** Apesar do nome "all routines", o script declara apenas 6 tasks: VIXRadar-AgendaSemanal, VIXRadar-Matinal, VIXRadar-Noturno e as 3 Szuchmacher. Nao cobre Monitor-Tasks, Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM nem Ranking-Mensal, que sao justamente as que sumiram entre 23 e 24/07. Quem rodar o script achando que restaura tudo nao restaura nada disso.
Agravante: a linha 83 executa `Unregister-ScheduledTask` antes de registrar cada task. Isso zera o LastRunTime e faz a task perder o disparo do dia se o horario do trigger ja passou.
[Hipotese] E a causa provavel da matinal perdida em 24/07, sexta-feira: o script foi rodado depois das 10h e a task nasceu de novo sem executar. Com a Monitor-Tasks fora do ar, uma repeticao passa despercebida.
[Evidencia nova 27/07 13h30] O mecanismo esta confirmado como real, ainda que nao como causa daquele dia: as 3 tasks recriadas as 12:23 aparecem hoje com `LastRunTime` 30/11/1999 e `0x41303`, exatamente o efeito de zerar historico descrito acima. Ou seja, re-registro apaga o rastro de execucao e faz uma task com meses de historico parecer virgem.
Nao propor troca de script: REGDRIFT1 (resolvido 23/07) declarou este o registrador canonico justamente por ter config mais resiliente, e marcou `register-vixradar-tasks.ps1` como DEPRECATED. O problema aqui e escopo e efeito colateral, nao escolha de script.
[Encerrado por impossibilidade] O que removeu as tasks entre 23 e 24/07 nao sera apurado. O log `Microsoft-Windows-TaskScheduler/Operational` esta com `IsEnabled=False` nesta maquina, entao nao existe evento 141 gravado para consultar, independente de janela de retencao. Verificado em 27/07 13h30. Este script nao remove nenhuma delas, nem com `-Remove`, que so alcanca as 6 declaradas. Enquanto a causa for desconhecida, pode repetir.
**Acao:** (1) deixar o escopo explicito no cabecalho, listando as tasks nao cobertas e o registrador de cada uma; (2) emitir aviso na saida quando o re-registro acontecer depois do horario do trigger do dia; (3) habilitar o log operacional do Scheduler (`wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true`) para que uma proxima remocao seja rastreavel, ja que esta nao foi.
**Validacao:** Cabecalho e saida do script declaram o escopo e o efeito de perder o disparo. Rodar com `-Status` nao altera nada. Log operacional com `IsEnabled=True`.

### P2 — monitor-tasks.ps1 inventa a causa da falha da AgendaSemanal

**Origem:** Releitura do Scheduler 27/07 13h30.
**Descricao:** `scripts\monitor-tasks.ps1` linhas 158-160 tem a regra hardcoded:

```powershell
} elseif ($code -eq 1 -and $name -eq 'VIXRadar-AgendaSemanal') {
    $entry.reason = 'Credit balance too low (assinatura Claude Code)'
    $warnings += $entry
```

O script **nao le stderr, nao le log, nao consulta nada**. Ele deduz a causa pelo nome da
task e pelo codigo de saida, e ainda **rebaixa de ERRO para WARNING**. Resultado pratico
hoje: a falha das 03h00, que era roteamento DeepSeek no `settings.json`, foi reportada as
07h00 como problema de credito e saiu da lista de erros. O log da rotina tem 2 linhas e
nenhuma mencao a credito, a string veio inteira do monitor.
Qualquer falha futura da AgendaSemanal com exit 1, por qualquer motivo, vai receber o mesmo
rotulo errado e o mesmo rebaixamento.
**Causa raiz:** mesma familia do card "Cobertura" corrigido hoje, um rotulo afirmando algo
que o codigo nunca mediu. Aqui e pior que na UI: e uma guarda mentindo sobre o que guarda.
**Acao:** trocar a regra por leitura real. Se `logs\routines\*_<data>.log` ou o stderr
casarem com `credit balance is too low|invalid x-api-key|HTTP 401`, classificar assim. Se
nao casarem, reportar `exit 1 sem causa identificada` e manter como ERRO, nao warning.
Nunca inferir causa a partir do nome da task.
**Validacao:** rodar `monitor-tasks.ps1` contra a falha de hoje 03h00 e obter
"causa nao identificada" em ERROS, nao "Credit balance too low" em WARNINGS.

### P2 — Probe CLI antes da Noturno 18:00 + verificar pos-execucao

**Origem:** Auditoria 27/07 12h09.
**Descricao:** AgendaSemanal e Matinal falharam ao invocar `claude -p`. CLI funcional as 12:09, mas nao se sabe se o bloqueio volta as 18:00. A Noturno processa 103 emissores — e a rotina mais critica do dia.
**Acao:** Entre 17:00 e 17:55: executar probe `claude -p` com `--output-format json`, `--strict-mcp-config`, `--mcp-config`, mesmo modelo Sonnet. Se falhar, notificar e abortar preventivamente com diagnostico. Apos 18:00: monitorar log `logs\routines\vixradar-noturno_20260727.log`.
**Validacao:** Noturno com exit 0 e submit_ok nos 103 emissores.

### P3 — SHADOW1: Revisao manual do shadow Fable 5 apos 2-4 semanas

**Origem:** Sessao 26/07 pt6 (implementacao do piloto shadow mode).
**Descricao:** `Invoke-FableShadow` compara veredictos Sonnet vs Fable 5 para CRITICOs. Apos 2-4 semanas de operacao, revisar `logs/routines/verificacao_fable_shadow_*.json` e adjudicar manualmente casos `pendente_adjudicacao: true`. Se houver ao menos 1 caso confirmado de falso-negativo do Sonnet capturado pelo Fable 5, criterio DOCBILL1 atingido.
**Prazo:** ~10-24/08/2026.
**Acao:** Revisar arquivos shadow acumulados, adjudicar divergencias, decidir se troca modelo primario.
**Validacao:** DOCBILL1 atingido ou decisao documentada de manter Sonnet.

### P3 — VIXRadar-Ranking-Mensal: decidir se implementa ou remove de vez

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** Task nunca executou (LastRunTime 1999 na epoca em que existia). Continua removida
e **nao foi recriada** junto com as outras tres em 27/07 12:23. Confirmado em 27/07 13h30 pela
listagem completa de `Get-ScheduledTask -TaskPath '\'`: e a unica das quatro que sumiu entre 23
e 24/07 que segue ausente. Script `scripts\run_vixradar_ranking_mensal.ps1` e
`scripts\register-ranking-mensal-task.ps1` existem. Funcionalidade nunca foi entregue.
**Acao:** Decidir se implementa ou remove scripts e documentacao relacionados.
**Validacao:** Decisao documentada.

### P4 — Corrigir documentacao do vault sobre o dia 24/07

**Origem:** Diagnostico de rotinas 27/07.
**Descricao:** O vault registrava "24/07 sem log matinal no diretorio (fim de semana ou sem disparo no path de logs)". 24/07 foi sexta-feira, dia util. A task foi recriada nesse dia, o que explica a ausencia do log.
**Acao:** Ja corrigido no `03 - Estado Atual.md` em 27/07.
**Validacao:** Corrigido.

### P2, RESOLVIDO 27/07 16h45. Frescor da Ingestao voltou a passar apos ADMIN_PASSWORD atualizado no GitHub. Falta so a guarda contra o proximo drift

**Origem:** Usuario trouxe screenshot da falha do workflow "Frescor da Ingestao" #44 (27/07, commit `8bfc786`). Causa raiz apurada nesta sessao por leitura do bundle Worker, do workflow YAML e do historico git, sem acesso a GitHub Actions no momento do diagnostico.

**O que aconteceu.** O commit `dfa6854` (24/07, "rotaciona credenciais expostas, Etapa 1") trocou a senha ADMIN_PASSWORD no Cloudflare Worker via `scripts/apply-security-rotation.ps1`. Esse script atualiza o secret so no Cloudflare (`wrangler secret put ADMIN_PASSWORD`), nao existe em nenhum lugar do repo um passo ou script que atualize o secret equivalente no GitHub Actions. Os tres workflows que dependem de `secrets.ADMIN_PASSWORD` (`frescor-check.yml`, `daily-status-email.yml`, `scan-emergencia.yml`) continuaram enviando a senha antiga.

**Causa raiz confirmada por leitura de codigo.** O handler `admin_health_check` no Worker (`api/v4.9.181.js:16047`) so retorna `ok:false, erro:"Acesso negado"` em duas condicoes, senha vazia ou `admin_senha !== env.ADMIN_PASSWORD`. `wrangler secret list` confirmou que `ADMIN_PASSWORD` estava configurado no Worker, entao nao era ausencia de secret do lado Cloudflare. O commit `8bfc786`, do mesmo dia 27/07, corrigiu um bug real e separado, escaping de JSON quebrado quando a senha tinha caracter especial, mas nao mudava qual senha era enviada. A run #44 rodou exatamente nesse commit ja corrigido e falhou com a mesma mensagem, confirmando que o problema era o valor da senha, nao o encoding.

**Validado com evidencia real apos o usuario atualizar o secret.** Sessao ganhou acesso de leitura ao GitHub Actions via PAT fine-grained (`GH_TOKEN`, escopo Actions/Contents/Issues read-only, so este repo). Runs do `frescor-check.yml` via API:

| Run | Evento | Resultado |
|---|---|---|
| 45 | workflow_dispatch, 27/07 16h45 | sucesso |
| 44 | workflow_dispatch, 27/07 16h38 | falha |
| 43 | workflow_dispatch, 27/07 16h35 | falha |
| 42 | schedule, 27/07 05h28 | falha |
| 41 | schedule, 26/07 05h02 | falha |

Log real da run 45, `ok:true`, `empresas_com_dados:103`, `updated_at:2026-07-27T16:39:49.946Z`, `weeks_loaded:["2026-W31","2026-W30"]`, `anthropic:true`, `resend:true`, `telemetria:true`, idade do estado 0h, `FRESCOR: OK, 103 emissores com dados`.

**Risco que motivou o P1 original, ainda vale como licao.** `scan-emergencia.yml` usa o mesmo `admin_health_check` como gate de staleness e, ao receber `ok:false`, tratava como "nao consigo avaliar" e saia com warning (`exit 0`), sem falhar o job. Entre 24/07 e 27/07 16h45 o paraquedas que dispara varredura de emergencia esteve mudo sem alertar ninguem, porque a falha de senha se disfarcava de "nada a fazer". Nao verificado se `daily-status-email.yml` reportou vermelho nesse periodo, historico de Issues ainda nao consultado.

**Acao (o resto ja esta feito e validado):**
1. Guarda, ainda nao aplicada: acrescentar `.erro` e o status HTTP na saida `jq` de `frescor-check.yml` e `scan-emergencia.yml`, para o log de falha mostrar a causa real da API em vez de exigir leitura do bundle para descobrir.
2. Guarda, ainda nao aplicada: acrescentar um passo explicito de atualizar o secret do GitHub Actions dentro da propria `apply-security-rotation.ps1`, para a proxima rotacao de ADMIN_PASSWORD nao repetir este drift.
3. Opcional: revisar o Issue fixo do `daily-status-email.yml` entre 24 e 27/07 para confirmar se reportou vermelho, agora que ha acesso de leitura ao GitHub.

**Validacao:** feita. Run manual #45 com `ok:true` e `empresas_com_dados:103` no log, confirmado via API do GitHub, nao so inferido pelo codigo.

---

### P2 — Guarda para secret obrigatorio ausente. ADMIN_EMAIL sumiu por 3 dias e so a telemetria viu

**Origem:** Usuario relatou 27/07 que uma solicitacao de acesso nao gerou aviso nem por WhatsApp nem por e-mail. O relato em si tinha outra causa (item abaixo), mas a investigacao achou este defeito separado e ativo.

**Correcao ja aplicada 27/07 18h01:** secret `ADMIN_EMAIL` criado no Worker com `szuchmacheryan@gmail.com`, valor recuperado do commit `dfa6854` que o removeu. Confirmado em `wrangler secret list`. Health check segue `ok:true`. Nao exigiu deploy de codigo.

**O que aconteceu.** O commit `dfa6854` (24/07, rotacao Etapa 1, o mesmo que quebrou o ADMIN_PASSWORD do GitHub Actions) removeu `ADMIN_EMAIL` do `[vars]` do wrangler.toml, mas o secret correspondente nunca chegou a existir no Cloudflare. O `scripts/apply-security-rotation.ps1` tem o passo [4/6] que cria esse secret (linha 95) e aborta se falhar, entao a hipotese mais provavel e que o commit de codigo foi feito sem a execucao real do passo, ou com `-DryRun`. Nao apuravel em retrospecto.

**Efeito, confirmado por leitura de codigo e por telemetria.** `var ADMIN_EMAIL = ""` (`api/v4.9.181.js:3584`) nao tem valor reserva, e `aplicarConfigRuntime` so o preenche se `env.ADMIN_EMAIL` existir. Com a string vazia, `handleRegistrar` (`:5643`) chamava `enviarResend(..., [""], ...)`, o `.filter(Boolean)` de `enviarResend` (`:5448`) esvaziava o array e a linha seguinte lancava `"Sem destinatarios."`. A telemetria do ultimo cadastro real, 25/07 06:02:40, registra exatamente `registrar_email_admin_erro` com esse texto. O WhatsApp salvou aquele cadastro, enviado 2 segundos depois com HTTP 201.

**Alcance maior que o cadastro.** Com `ADMIN_EMAIL` vazio, `handleLogin` (`:5721`) nunca atribuia `role: "admin"` ao JWT, derrubando as rotas que dependem de `_exigeJwtAdmin` (`:5162`). O painel de aprovacao nao foi afetado porque `handleAdminAprovar` e `handleAdminListar` autenticam por `ADMIN_PASSWORD`, nao por JWT, e por isso o problema passou 3 dias despercebido.

**Causa raiz, e a mesma do item do GitHub Actions.** A rotacao de 24/07 mexeu em credencial em varios destinos e nada verifica, depois do fato, que cada destino ficou consistente. Some com um secret obrigatorio e o unico sinal e um evento de telemetria que ninguem le. O health check valida `RESEND_API_KEY` e os bindings, mas nao valida `ADMIN_EMAIL`.

**Acao, as guardas que faltam:**
1. Incluir `ADMIN_EMAIL` na condicao `_okHealth` do health check (`api/v4.9.181.js:15784`), do mesmo jeito que `RESEND_API_KEY` ja entra. Secret obrigatorio ausente passa a derrubar `ok:false` em vez de degradar em silencio. Exige deploy de Worker.
2. Acrescentar passo final em `apply-security-rotation.ps1` que roda `wrangler secret list` e compara com a lista esperada, falhando se faltar algum. Resolve a classe inteira, nao so este secret, e casa com a guarda 2 do item do GitHub Actions.

**Validacao pendente:** proximo cadastro real de usuario deve gerar e-mail ao admin sem `registrar_email_admin_erro` na telemetria.

---

### P2 — Cadastro de conta ja existente responde "aguarde aprovacao" e nao notifica ninguem

**Origem:** E a causa real do relato do usuario em 27/07. Diagnostico por telemetria do Analytics Engine.

**O que acontece.** Em `handleRegistrar` (`api/v4.9.181.js:5618-5619`), quando o e-mail ja existe com status `pendente` ou `aprovado`, o Worker responde `ok:true, "Solicitacao enviada. Aguarde aprovacao."` e retorna ali. As chamadas de notificacao ao admin ficam depois desse ponto, nas linhas 5643 (e-mail) e 5653 (WhatsApp), entao nada e enviado. Do lado tecnico esta certo, nao ha cadastro novo. Do lado da pessoa a mensagem mente, ela fica esperando uma aprovacao que nao existe, e o operador fica esperando um aviso que nunca seria disparado.

**Caso observado.** 27/07 14h31 BRT, tentativa com uma conta `aprovado` desde 11/06, telemetria `registrar_rejeitado` motivo `ja_aprovado` http 200. Foi o unico evento de cadastro nas 48h anteriores.

**Acao:** diferenciar a resposta. Conta `aprovado` deve receber "voce ja tem acesso, faca login" com atalho para recuperacao de senha. Conta `pendente` deve receber "sua solicitacao ja esta na fila" e, [Recomendacao] a avaliar, reenviar a notificacao ao admin com dedup por janela de tempo, porque hoje um reenvio legitimo apos falha de entrega nao tem como chegar. Exige deploy de Worker e ajuste no `app/index.html`.

**Nota de seguranca, ler antes de implementar.** Hoje a resposta e identica para conta inexistente, pendente e aprovada, o que evita enumeracao de usuarios. Ao diferenciar a mensagem na tela isso se perde. [Recomendacao] manter texto neutro na tela e resolver pelo e-mail ao dono da conta, ou exigir rate limit por IP nesse caminho antes de mudar o texto.

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
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Aguardando periodo de avaliacao (ver SHADOW1 em abertas, P3).

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Aguardando periodo de shadow (ver P3 SHADOW1).
**Descricao:** 1 caso confirmado de falso-negativo do Sonnet capturado pelo Fable 5 = criterio atingido = decidir troca do modelo primario.

---

*Atualizado em 2026-07-27 12h09 BRT (pos-auditoria: 2 itens fechados, 2 novos P1/P2, tasks recriadas). Fila aberta: 10 itens acionaveis (2 P1, 5 P2, 2 P3, 1 P4).*

---

## Adendo 28/07 — Registro canonico da auditoria tecnica completa

A auditoria de 28/07 consolidou os achados em registro canonico com IDs, taxonomia de certeza e rubrica P0-P3: `00-AUDITORIA-SISTEMA-COMPLETA.md` na raiz do repo (mais relatorios 01 a 04). Esta secao so aponta, o detalhe mora la. Itens ja existentes desta fila ganharam ID e continuam donos do proprio plano: OPS-001 (matinal autodeclarada, o P1 da matinal acima), OPS-003 (idempotencia, acao 4 do mesmo item), OPS-004 (monitor-tasks), SEC-002 (cadastro existente), SEC-003 (WhatsApp/StatusCallback), SEC-001 e ENC-001 (resolvidos com guarda).

Itens novos abertos pela auditoria (detalhe, evidencia e criterio de aceite no registro):

- **CAL-002 (P0 ATIVO)** — datas 2T26 de Bradesco e Vale divergem da fonte oficial e o dashboard exibe as erradas com selo de certeza. RI do Bradesco: divulgacao 05/08/2026 apos o fechamento (B3 e NYSE), videoconferencia 06/08, periodo de silencio 22/07 a 05/08; o sistema mostra 28/07 como AGENDADO, dia em que o banco esta formalmente impedido de divulgar. Vale: divulgacao 30/07/2026 apos o fechamento; o sistema mostra "Ultima divulgacao 24/07", resultado que oficialmente ainda nao saiu (o evento de 21/07 era producao e vendas). Petrobras: nao confirmada, segue exibida como AGENDADO sem respaldo. Contencao recomendada no relatorio 04 secao 1. Correcao e Gate C, nada executado.
- **CAL-001 (P1)** — data estimada exibida como AGENDADO na UI e como evento sem ressalva na agenda. E o mecanismo que transformou a extrapolacao errada de CAL-002 em afirmacao com selo de certeza, e que hoje faz o mesmo com as outras 18 estimativas do 2T26.
- **CAL-003 (P2)** — `op=calendario` ignora overrides de KV, so a agenda le o merge.
- **CAL-004 (P2)** — calendario congelado desde 2026-05-09, cobertura 20/103, staleness sem consumidor automatico. Taxa de erro medida da extrapolacao: 2 de 2 datas testadas contra RI oficial estavam erradas.
- **VOL-001 (P2)** — campo `market_cap` carrega preco por acao, guarda `> 100` invertida, Merton rodando com PL contabil sem contrato.
- **VOL-002 (P3)** — estimador de volatilidade (RMS nao centralizado) sem contrato, formula duplicada.
- **VOL-003 (P2)** — SELIC hardcoded 13,75% sem `as_of`, erro comprovado contra o BCB em 28/07 (meta 14,25%, efetiva 14,15%), e contradicao interna com "SELIC a 15%" no proprio bundle.
- **DEC-001 (decisao)** — definir o que "SELIC" significa no produto antes de escolher serie do BCB.
- **OPS-002 (P2)** — `run_coleta_volatilidade.ps1` nao propaga falha dos filhos nem le `$LASTEXITCODE`; cobertura 73/103 sem alerta.
- **CI-001 (P2)** — secret ausente encerra workflows de vigilancia com exit 0 por design; revisitar politica para runs agendadas.
- **CI-002 (P2)** — scan-emergencia sai limpo com `ok:false` (paraquedas mudo 24-27/07); frescor ja falha, o scan nao.
- **CI-003 (P3)** — rotacao multi-destino com passo GitHub manual sem verificacao pos-fato.

Este adendo adiciona 12 itens acionaveis (1 P0, 1 P1, 7 P2, 2 P3, 1 decisao) aos 11 da fila acima. Ordenacao e sequenciamento em `04-PLANO-CORRECAO-PRIORIZADO.md`. Nada executa sem Gate C.

*Adendo gravado em 2026-07-28, sessao da auditoria tecnica completa (Gate A). Ver [[71 - Auditoria Tecnica Completa 2026-07-28]].*
