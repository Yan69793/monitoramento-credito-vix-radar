# 70 — Auditoria Completa 2026-08-08

Executada 08/08/2026 ~19h20 BRT. Sábado. Escopo: produção, drift repo/vault, rotinas agendadas, segredos.
Nada foi alterado, deployado ou commitado nesta auditoria. Apenas leitura.

---

## Portão de verificação (saída real colada)

```
$ curl https://radar-credito-api.prospects-intel.workers.dev
{"ok":true,"versao":"v4.9.188","ts":"2026-08-08T22:15:52.762Z",
 "bindings":{"kv":true,"rate_limiter":true,"telemetria":true},
 "providers_configurados":"2/2","admin_email_ok":true,"sentry_ok":true,"verificador_ok":true}
HTTP:200 TEMPO:0.758s

$ curl https://api.vixradar.com          → idem, HTTP 200, 0.973s
$ curl https://vixradar.com              → HTTP 200
$ curl https://vixradar.com/version.json → {"version":"v202.2","deployed_at":"2026-08-06T23:01:11Z"}
$ curl https://radar-credito.pages.dev   → HTTP 200
```

Produção está saudável. Worker v4.9.188, frontend v202.2, ambos batem com o último commit
(`d8fb4a6 chore(frontend): deploy v202.2 em producao`). `app/deploy_zip/index.html` é
byte-idêntico ao HTML servido em produção (693.675 bytes). **Não há drift de deploy.**

---

## Achados por severidade

### CRÍTICO 1 — `routine_key` continua em texto puro, em mais arquivos do que o incidente ROUTINEKEY-PLAIN1 registrou

O CLAUDE.md diz que o valor foi redigido nos 4 arquivos vivos em 07/08 e que a chave
**não foi rotacionada**. A remediação foi incompleta. Encontrei duas chaves distintas,
ambas em texto puro:

| Onde | Fingerprint (sha256, 12 chars) | Rastreado no git? |
|---|---|---|
| `logs/routines/rk.tmp` (44 bytes, de 06/08) | `85dafb715051` | não (`logs/` ignorado) |
| `logs/routines/submit_{gpa,kora,raizen,oncoclinicas}.json` | `85dafb715051` | não |
| `scripts/azul_payload.json` | `85dafb715051`* | não |
| `scripts/_archive/ipad-matinal.md` (3 ocorrências) | `b532fb303863` | **SIM, no HEAD** |
| `scripts/_archive/ipad-noturno.md` (4 ocorrências) | `b532fb303863` | **SIM, no HEAD** |

*fato:* `[Environment]::GetEnvironmentVariable('ROUTINE_API_KEY','User')` tem 43 caracteres.
`rk.tmp` tem 44 bytes (43 + newline). **`rk.tmp` é a chave ativa, em claro, no disco.**

*fato:* o valor `b532fb…` está commitado e sincronizado com o GitHub. O repositório é
privado (GET não autenticado devolve 404), o que limita o raio, mas o valor está no
histórico do git e não sai com um simples `rm`.

*hipótese:* `b532fb…` é uma chave anterior, já sem uso. Não testei nenhuma das duas contra
o Worker — testar seria autenticar contra produção, e não faço isso sem pedido.

*risco:* enquanto a chave ativa estiver em claro no disco e a rotação não acontecer,
qualquer processo local, backup, sync de nuvem ou transcript exporta o segredo que autentica
todas as rotinas contra o Worker.

**Recomendação:** rotacionar. É a decisão que o próprio CLAUDE.md deixou pendente desde
07/08 e o custo dela só sobe. A rotação toca toda rotina que autentica — matinal, noturna,
verificação async, export, replay — então precisa de janela e de um checklist, não de um
comando avulso.

---

### CRÍTICO 2 — A rotina noturna de hoje morreu no meio e nada avisou

```
2026-08-08 18:07:42 INICIO: noturno 103 emissores (sessao agendada Claude Desktop)
2026-08-08 18:07:42 GUARD_OK: VIXRadar-Noturno Disabled
2026-08-08 18:07:42 HEALTH: ok=true versao=v4.9.188 ... providers=2/2
2026-08-08 18:07:42 PLANO: total=103 janela=2026-07-09..2026-08-08 SKIP=25 RAPIDA=69 APROFUNDADA=9
2026-08-08 18:08:05 OK|Engie Brasil Energia|SKIP|NENHUM|0|true
... (25 linhas, todas SKIP) ...
2026-08-08 18:08:17 OK|Grupo Mateus|SKIP|NENHUM|0|true
<fim do arquivo>
```

*fato:* último write no log às 18:08:17. Hora da checagem: 19:20:18. **71 minutos de silêncio.**
Nenhuma linha `FIM:`, nenhuma linha `ABORT:`. Nenhum processo iniciado às 18:07 sobrevive
(o processo mais antigo na máquina é de 18:53).

*fato:* 25 dos 103 emissores foram processados, e os 25 eram justamente os `SKIP` — os que
não custam chamada de LLM. **Zero dos 69 RAPIDA e zero dos 9 APROFUNDADA rodaram.** A varredura
de hoje cobriu 24% do universo e 0% do que exige análise.

*comparação:* em 07/08 a mesma rotina rodou 18:06→19:02 e fechou com `FIM: submit_ok=103 total_plano=103`.

*hipótese:* a sessão agendada do Claude Desktop foi encerrada logo depois de despachar os
SKIPs, provavelmente ao entrar no primeiro lote que exige LLM. Não consigo confirmar a causa
sem o transcript da sessão.

**Este é o gargalo estrutural, não o incidente em si.** Ver abaixo.

---

### CRÍTICO 3 — O monitoramento cobre exatamente as tarefas que não importam

`scripts/monitor-tasks.ps1` roda 07h e reporta `LastTaskResult != benigno` das tasks do
Task Scheduler. Mas as três rotinas que carregam o sistema — matinal, noturna, verificação
async — estão `Disabled` de propósito (guarda anti-duplicata) e o `LastTaskResult` delas está
congelado em 06/08. O próprio CLAUDE.md reconhece isso: *"o LastTaskResult delas não indica
saúde, quem indica é a linha `FIM:` no log"*.

**Só que nada lê a linha `FIM:`.** Procurei por qualquer verificação de "começou e não
terminou" nos scripts (`grep -E "sem FIM|nao terminou|incompleta|stall|travad"`): nenhum
resultado. O monitor confere código de saída de tarefas desligadas e ignora o log das que
realmente rodam.

O watchdog do Worker (01h UTC) monitora staleness de 6 heartbeats, incluindo `varredura_batch`.
*hipótese, não verificada a fundo:* o heartbeat mede recência da batida do agente, não cobertura
da varredura. Uma noturna que morre após 25 de 103 emissores pode deixar um heartbeat fresco
com cobertura de 24% e passar verde. Se for isso, o ponto cego é duplo — nem o monitor local
nem o watchdog remoto pegam execução parcial.

**Recomendação (alavancagem):** uma checagem que compare, no fim do dia, o `total_plano` da
linha `PLANO:` com o `submit_ok` da linha `FIM:` do mesmo log. Se não houver linha `FIM:`, ou
se `submit_ok < total_plano`, alerta. É baixo esforço e fecha o buraco que produziu os
incidentes de 04-06/08 e o de hoje. Não implementei nada — decisão sua.

---

### MÉDIO 1 — `VIXRadar-Ranking-Mensal` está documentado mas não existe

CLAUDE.md lista a tarefa como Task Scheduler, dia 1 às 11h30, SEO mensal.
`Get-ScheduledTask -TaskName '*Ranking*'` devolve **0 resultados**. No dia 1 de setembro
ela não vai rodar, e ninguém vai perceber, porque a documentação afirma que ela existe.

Inversamente, três tarefas rodam e não estão na tabela do CLAUDE.md: `VIXRadar-AgendaSemanal`,
`VIXRadar-Coleta-Volatilidade`, `VIXRadar-Reconciliacao-CVM`.

---

### MÉDIO 2 — `CLOUDFLARE_API_TOKEN` só existe no escopo do usuário

CLAUDE.md: *"variável de ambiente do sistema"*.
Realidade: `Machine: NAO` / `User: SIM len=53`. Idem `ROUTINE_API_KEY` (`User`, len=43).

Não bloqueia nada hoje, porque o deploy é disparado por você no seu próprio shell. Vira
bloqueio no dia em que qualquer coisa rodar como SYSTEM, como outro usuário, ou num runner —
e o erro vai aparecer como falha de autenticação no meio de um deploy, não como configuração
ausente no começo.

---

### MÉDIO 3 — A skill `radar-credito-privado` está grosseiramente desatualizada e induz erro

A skill que acabou de ser invocada para esta auditoria afirma:

| A skill diz | Realidade verificada |
|---|---|
| Worker v3.9.6 | **v4.9.188** |
| Frontend v61 | **v202.2** |
| OpenRouter é o provedor primário | saiu do cascade no v4.9.108 (CLAUDE.md) |
| ZIP do Pages = exatamente 3 arquivos | `deploy_zip/` tem 13 entradas, incl. `admin/`, `app/`, `manual/`, `apresentacao/`, `version.json` |
| `ADMIN_EMAIL` é hardcoded | movido para secret no incidente SECRETMISS1 |
| `ADMIN_PASSWORD: RadarAdmin@2026` | **senha de admin em texto puro dentro da skill** |

Uma sessão que confie nessa skill e não leia o CLAUDE.md vai montar o ZIP errado, procurar
OpenRouter que não existe mais e assumir versões três gerações atrás. A senha em claro é um
segundo segredo exposto, independente da `routine_key`.

---

### BAIXO 1 — Working tree suja: 96 arquivos, deploy travaria

`git status --porcelain` no Windows: **96 arquivos modificados**. São `CLAUDE.md` e ~95
`data/cotacoes/series/*.json` + `meta_volatilidade.json`, gerados pela coleta de volatilidade
das 17h.

O `deploy-worker.ps1` aborta com working tree suja. Ou seja: **um deploy de Worker hoje falha
no portão, sem tocar em nada** — o portão funciona, mas você descobre isso só quando tenta.
A coleta de volatilidade gera arquivos versionados a cada execução e ninguém commita.
Ou os artefatos entram no `.gitignore`, ou a coleta commita sozinha. Hoje é atrito diário.

### BAIXO 2 — Export histórico falha nas mesmas 2 chaves KV toda execução e reporta "0 avisos"

```
[2026-08-07 20:48:14]   kvget 'mercado:serie:lwsa':     exit=1 ... Failed to fetch
[2026-08-07 20:48:15]   kvget 'mercado:serie:ultrapar': exit=1 ... Failed to fetch
[2026-08-07 20:48:15] FIM: ok - 3 arquivos ... (194s, modo delta, 0 avisos)
```

Idêntico em 06/08. Duas séries falham de forma determinística e o log conclui `ok` com
`0 avisos`. LWSA e Ultrapar estão saindo do histórico sem que nada registre.

---

## Parece ruim mas está OK

- **`VIXRadar-Reconciliacao-CVM` com `LastTaskResult=1` desde 03/08.** Causa já diagnosticada e
  corrigida em 07/08 (`ConvertFrom-Json -AsHashTable` é parâmetro de PS 7 rodando sob 5.1). A task
  é semanal, o resultado fica congelado até 10/08. Documentado dentro do próprio `monitor-tasks.ps1`.
- **Matinal, Noturno e Verificação-Async `Disabled` no Task Scheduler.** É a guarda anti-duplicata
  desenhada. As linhas `GUARD_OK` nos logs de 07 e 08/08 confirmam que o script valida isso a cada run.
- **`LastTaskResult` 6 e 7 nessas três tasks.** Congelado desde 06/08, sem significado de saúde.
- **`providers_configurados: 2/2`.** Bate com o cascade pós-v4.9.108, não é degradação.
- **Ausência de matinal em 08/08.** Sábado. A matinal é Seg-Sex. Correto.
- **376 arquivos "modificados" vistos do sandbox Linux.** Artefato de CRLF vs LF na montagem.
  O número real, medido no Windows, é 96. Descartado.

---

## Auto-revisão: o que eu corrigiria antes de você publicar isto

Coisas que afirmei com menos base do que a redação sugere, e que eu não deixaria passar:

1. **Não testei nenhuma das duas `routine_key` contra o Worker.** A afirmação de que
   `85dafb…` é "a chave ativa" vem de coincidência de comprimento (43 chars na env var,
   44 bytes no arquivo), não de autenticação bem-sucedida. É evidência forte, não prova.
   Se você quiser certeza antes de rotacionar, o teste é um POST com ação inócua — mas isso
   é execução contra produção e eu não faço sem pedido explícito.

2. **O ponto cego do watchdog é hipótese, não fato.** Li o suficiente do `worker.js` para
   ver que os heartbeats são medidos por recência (`staleness_h`) e que `varredura_batch`
   bate heartbeat, mas não rastreei se algum caminho compara cobertura. Antes de agir em cima
   disso, vale ler `_watchdog` inteiro. O achado 3 sobre o monitor local, esse sim, é fato
   verificado por grep.

3. **Não sei por que a noturna morreu.** Descrevi o sintoma com precisão e rotulei a causa
   como hipótese. O transcript da sessão agendada do Claude Desktop resolveria, e ele não está
   no repositório — não achei caminho para auditá-lo daqui.

4. **Não auditei o agendamento das três rotinas principais.** Elas rodam por sessão agendada
   do Claude Desktop, mecanismo interno do app que não aparece no Task Scheduler (lá só existe
   `Szuchmacher-AgendaMacro-Claude`). O log prova que a noturna *disparou* às 18:07 hoje, então
   o agendamento funciona; o que não consigo verificar é se as três estão configuradas como
   você acredita.

5. **Não li o `worker.js` inteiro.** São ~17k linhas e eu inspecionei trechos dirigidos. Esta
   auditoria cobre produção, rotinas, drift e segredos. **Não** cobre qualidade de código,
   regressão de segurança no Worker, nem os incidentes da tabela do CLAUDE.md — se uma mudança
   recente reabriu STATELEAK1 ou RACEKV1, esta auditoria não veria.

6. **Não verifiquei se `scripts/azul_payload.json` tem o mesmo fingerprint** que marquei com
   asterisco na tabela — inferi pelo padrão dos outros arquivos de submit. Corrija ou confirme
   antes de citar essa linha.

---

## Prioridade sugerida

1. Rotacionar a `routine_key` e limpar `logs/routines/rk.tmp` + os `submit_*.json`. É o único
   achado com dano irreversível se vazar.
2. A checagem `PLANO: total` vs `FIM: submit_ok`. Menor esforço, maior alavancagem, fecha o
   buraco que já produziu três incidentes em cinco dias.
3. Reprocessar a varredura de hoje — 78 emissores ficaram sem análise, incluindo os 9 aprofundados.
4. Atualizar a skill `radar-credito-privado` ou desativá-la. Enquanto estiver assim, ela é uma
   armadilha para qualquer sessão futura.

O resto pode esperar.

---

# Execução — 08/08/2026, 19h30-19h45

## Correção de dois erros da própria auditoria

**A tabela do CRÍTICO 1 estava errada.** O item 6 da auto-revisão dizia que eu tinha inferido
o fingerprint de `scripts/azul_payload.json` em vez de medir. Medi. **Não são duas chaves
distintas, são três:**

| Arquivo | Fingerprint |
|---|---|
| `rk.tmp` + 4 `submit_*.json` | `85dafb715051` (era a ativa) |
| `ipad-matinal.md` + `ipad-noturno.md` (commitados) | `b532fb303863` |
| `azul_payload.json` | `6fa9d39fa94f` |

**Um consumidor da chave passou despercebido na auditoria:**
`.github/workflows/scan-emergencia.yml` linha 70 usa `secrets.ROUTINE_API_KEY`. A rotação
tem três destinos, não dois. Esquecer o terceiro deixaria a rede de segurança (fallback de
23:30 UTC quando o estado principal está stale) fora do ar sem alarme — a mesma classe de
falha que a auditoria mandou eliminar.

## Achado novo, encontrado durante a execução

`.git/index.lock` órfão de 0 bytes, criado 08/08 19:17. Travava o índice: todo `git add`
falhava. Removido (nenhum processo git ativo o detinha). Sem isso, nenhum commit funcionaria
e o diagnóstico seria "o hook não dispara" em vez de "o git não indexa".

## Feito

**1. Cópias em claro eliminadas do disco.** `logs/routines/rk.tmp` apagado (era a chave ativa,
43 caracteres nus). Chave redigida para `REDACTED_ROTACIONAR` em 7 arquivos: os 4
`submit_*.json`, `azul_payload.json` e os 2 `ipad-*.md`. Conteúdo analítico dos payloads
preservado. Varredura em `scripts/`, `routines/`, `logs/` e `.claude/`: zero ocorrências literais.

O HEAD do git ainda contém `b532fb303863` — mudei só a working tree, não commitei. A chave
entrou no histórico num commit único, `15647ef feat(api): v4.9.147 z-scores ANBIMA`.

**2. Gate 3 no pre-commit — a parte que impede reintrodução.** Roda sobre todo arquivo de
texto em staging, não só `.ps1`/`.js`, porque a chave vazou em `.md`, `.json`, `.sh` e `.py`.
Duas checagens: segredo literal, e script que grava a chave em arquivo (o padrão que criou
o `rk.tmp`). Mensagens ocultam o valor com `<VALOR-OCULTADO>`.

Validado contra a própria regra de que alarme sem teste é decoração:

| Caso | Esperado | Resultado |
|---|---|---|
| `"routine_key":"<28 chars>"` | reprova | exit 1, valor ocultado |
| `$env:ROUTINE_API_KEY \| Out-File rk.tmp` | reprova | exit 1 |
| `echo $ROUTINE_API_KEY > /tmp/rk.tmp` | reprova | exit 1 |
| `Set-Content rk.tmp -Value $env:ROUTINE_API_KEY` | reprova | exit 1 |
| `$env:` / `${{ secrets.X }}` / `<ROUTINE_API_KEY>` | passa | exit 0 |
| os 4 scripts de rotina reais | passa | exit 0 |
| os `ipad-*.md` já redigidos | passa | exit 0 |

Os três primeiros testes só passaram a valer depois de remover o `index.lock`: antes disso o
hook rodava com staging vazio e "passava" sem examinar nada. Primeira rodada de testes
descartada por isso.

**3. `scripts/rotate-routine-key.ps1`.** Rotação atômica nos três destinos, com quatro portões
antes de tocar em qualquer coisa (gh autenticado, secret existe no GitHub, wrangler enxerga o
Worker, produção com `ok:true`), rollback automático do Worker e do local se a validação falhar,
e fingerprint em vez de valor em todo log. Ordem: GitHub, Worker, local — GitHub primeiro porque
é inerte até a próxima execução, e a janela de indisponibilidade fica de segundos entre Worker e local.

Validado: parse limpo sob PowerShell 5.1, `lint-encoding` sem risco, aprovado pelo próprio Gate 3,
e `-WhatIf` abortando corretamente no portão 1.

## Não feito, e por quê

**A rotação em si.** `gh` está instalado (2.96.0) e não autenticado. `gh auth login` é fluxo
interativo, não roda nesta sessão. Rotacionar Worker e local sem o GitHub quebraria o
`scan-emergencia` hoje às 23:30 UTC, em silêncio. Trocar uma exposição conhecida por uma falha
silenciosa é o oposto do que a auditoria concluiu.

Destrava com dois comandos:

```powershell
gh auth login
pwsh ./scripts/rotate-routine-key.ps1 -WhatIf   # confere os portoes, nao muda nada
pwsh ./scripts/rotate-routine-key.ps1
```

**Purga do histórico do git.** Reescrita de histórico é destrutiva e força push num repo já
sincronizado. Depois da rotação a chave velha não vale mais nada, o que era o objetivo — a
purga vira higiene opcional, não urgência.

**Nada foi commitado nem deployado.** A working tree tem alterações suas anteriores
(`monitor-tasks.ps1`, `run_coleta_volatilidade.ps1`, `verify-rotinas-v2.ps1`, dois `.bak`) que
eu não misturaria num commit meu.
