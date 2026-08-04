---
data: 2026-08-04
tipo: auditoria
tags: [vix-radar, auditoria, frontend, worker, module-mig1, valid1]
status: ativo
escopo: backend Worker v4.9.186 + frontend v201.93/v202.1 + seguranca + veracidade UI + perf + a11y
---

# Auditoria Geral — VIX Radar (2026-08-04)

Skill: `vix-radar-general-audit`. Modo readonly, nenhum deploy, nenhum secret tocado.

## Veredito

**Degradado.** O Worker esta saudavel e validado em producao (`ok:true`, `v4.9.186`, todos
os bindings verdes, 0,76s). O frontend nao esta: a migracao MODULE-MIG1 (commit `2c6c09a`,
03/08) publicou tres modulos ES com truncamento de sintaxe e removeu do `index.html` os
cinco scripts classicos que eles substituiriam. O resultado e que **toda a camada de
modulos do painel admin esta morta em producao desde 03/08**, sem nenhum sinal no health,
no `canonical-test` ou no `version.json`.

Camadas cobertas com evidencia: repo/governanca, Worker (bindings, crons, auth de rotina,
VALID1, LOG1, MIGRA-DO1), frontend (drift, modulos, cache), veracidade da UI (script +
conferencia manual dos 3 termos reservados), seguranca (grep dirigido + teste HTTP vivo),
performance (Navigation Timing real), a11y (amostra DOM na home), rotinas PowerShell (lint
+ diff). Lacunas declaradas ao final.

## Top riscos

| Sev | Area | Achado | Evidencia | Correcao | Causa raiz | Guarda sistemica |
|---|---|---|---|---|---|---|
| **P0** | Frontend | 3 modulos ES truncados quebram todo o bootstrap admin em producao | `import('/app/js/admin-bootstrap.js')` no navegador em `https://vixradar.com` retorna `SyntaxError: Unexpected token 'export'`; `window.VRAdmin` e `window.VRAdminShared` = `undefined` | Fechar os 3 corpos de funcao truncados (`api.js:98`, `admin/shared.js:68`, `admin/modules.js:177`) e revalidar com `node --check` | Nenhuma etapa do caminho commit→deploy parseia JS do frontend. O `deploy-pages.ps1` confere existencia de arquivo, nunca sintaxe | Gate `node --check` sobre todo `app/js/**/*.js` e `app/admin/*.js` no `deploy-pages.ps1` (passo 3) e no pre-commit hook |
| **P0** | Deploy | `deploy-pages.ps1` nao sincroniza `app/js/` para `deploy_zip/` | `scripts/deploy-pages.ps1:110-122` copia `index.html`, `_headers`, `_routes.json`, `landing-demo.json`, `robots.txt` e `admin/`. `app/js/` ausente | Acrescentar `app/js` ao bloco de sync recursivo, junto com `admin/` | MODULE-MIG1 criou uma arvore nova de assets e commitou nas duas copias na mao. O script nunca soube dela | Sync dirigido por lista de diretorios versionada, com `Fail` se `app/` tiver subpasta de asset fora da lista |
| **P1** | Deploy | Gate do passo 3 valida so os 5 arquivos `vr-admin-*.js` **obsoletos** | `deploy-pages.ps1:133-137` | Trocar a lista pelos modulos vivos (`app/js/admin-bootstrap.js`, `api.js`, `admin/*.js`) | Lista hardcoded que ninguem atualizou na migracao | Derivar a lista dos `src=`/`import` do proprio `index.html`, nao de constante |
| **P1** | Frontend | `CACHE_VERSION` nunca subiu para `v202.1`; producao e repo seguem em `v201.93` com HTML novo | `curl https://vixradar.com/version.json` → `v201.93`; HTML de producao contem `src="app/js/admin-bootstrap.js?v=202.1"` | Bumpar `CACHE_VERSION` e redeployar pelo script | O deploy nao passou pelo `deploy-pages.ps1` (`deployed_at:null` no `version.json`, e nenhum commit `chore(frontend): deploy`) | `Fail` no script quando o HTML referenciar `?v=X` divergente da `CACHE_VERSION` |
| **P1** | Seguranca | VALID1 e fail-open: POST **sem** header `Content-Type` passa direto | `curl -X POST -H "Content-Type:" ... https://api.vixradar.com/` → HTTP 400 (chegou no handler). Com `text/plain` → HTTP 415 | Tratar ausencia como invalida em POST/PUT/PATCH com body | `if (ct && ...)` em `src/worker.js:39` — string vazia e falsy, entao header ausente pula a checagem inteira | Teste de contrato no `canonical-test.yml` cobrindo os 3 casos (ausente, errado, correto) |
| **P1** | Rotinas | `vixradar-claude-auth.ps1` reprova no lint de encoding e esta dot-sourced pelas 3 rotinas | `scripts/lint-encoding.ps1` → `REPROVA ... [nao-ASCII sem BOM (5.1 le como ANSI)]`, 53/54 OK | Trocar os 2 travessoes das linhas 96 e 104 por virgula/hifen ASCII | Regra de humanizacao do CLAUDE.md global proibe travessao, e o texto entrou em comentario de codigo. O pre-commit lint so roda no commit, o arquivo ja esta no disco sendo lido em runtime | Rodar `lint-encoding.ps1` tambem no inicio de cada rotina (ja existe `Test-VixClaudeAmbienteLimpo`, e o lugar natural) |
| **P2** | Seguranca | Respostas 415 e 413 do VALID1 saem sem headers CORS | `curl -H "Origin: https://vixradar.com" -H "Content-Type: text/plain"` → 415 sem `Access-Control-Allow-Origin`; mesma requisicao valida → 400 com os 4 headers CORS | Passar `_valErr` pelo mesmo wrapper de CORS do resto | `_validateInput` retorna direto de `__coreFetch` (`src/worker.js:15463`), antes do ponto onde o CORS e aplicado | Teste que exige `Access-Control-Allow-Origin` em toda resposta com `Origin` conhecido |
| **P2** | Repo | `api/src/logging.js` e `api/src/validation.js` sao copias orfas que ja divergem do `worker.js` | Nada importa os dois arquivos. `validation.js:27` loga `"VALID1: payload excede..."`, `worker.js:45` loga `"payload excede..."`. `logging.js` define `_logInfo`, que nao existe no `worker.js` | Deletar os dois, ou transformar em modulos realmente importados pelo build | Criados no commit **de frontend** `2c6c09a`, depois do codigo ja estar inline no `worker.js`. Nasceram como documentacao e viraram fonte falsa | `build-worker.ps1` deve falhar se existir arquivo em `api/src/` que nao seja `worker.js` nem esteja no grafo de import |
| **P3** | Worker | LOG1 entregue e nao adotado | `_logInfo` e `_logError`: **0** call sites. `_logWarn`: 1 (dentro do proprio VALID1). `console.log/warn/error` no worker: **163** | Migrar por lote, comecando pelos caminhos de erro, ou reclassificar LOG1 como parcial no changelog | Feature entrou no numero de versao (`v4.9.186`) sem criterio de adocao | Meta explicita no changelog (ex.: "N call sites migrados") e contagem no proximo audit |
| **P3** | Rotinas | `run_vixradar_noturno_claude.ps1:131` dot-source de arquivo **untracked** | `scripts/lib/vixradar-noturno-shadow-deepseek.ps1` aparece em `git status` como `??` | Commitar a lib ou envolver o dot-source em `Test-Path` | Experimento shadow criado direto no disco, sem passar pelo git | Guard no `verify-rotinas-v2.ps1`: todo dot-source de rotina precisa estar rastreado |

## Backend Worker

`v4.9.186` em producao, igual ao `main` do `wrangler.toml`. Sem drift de versao. Health
publico: `ok:true`, `kv:true`, `rate_limiter:true`, `telemetria:true`, `providers 2/2`,
`admin_email_ok:true`, `sentry_ok:true`, `verificador_ok:true`, HTTP 200 em 0,76s.

Bindings conferidos no `wrangler.toml` e vivos no codigo: `RADAR_KV`, `RATE_LIMITER_DO`,
`ESTADO_SEMANA_DO`, `RADAR_USAGE_EVENTS`, mais os tres novos de MIGRA-DO1 (`EMISSOR_DO`,
`USUARIO_DO`, `CONFIG_DO`, migration `v3`). Route `api.vixradar.com` e os 4 crons intactos.

**MIGRA-DO1 esta corretamente em fase 0.** `_faseMigracao` le `MIGRATION_PHASE` e cai em
`"0"` quando o secret nao existe, entao os DOs novos recebem escrita zero. Os seis helpers
`_kvPutDual*`/`_kvGetDual*` tem call sites reais (7, 7, 5, 5, 6, 10 ocorrencias), nao sao
codigo morto. A escrita no KV acontece sempre antes do dual-write, e a falha do DO so gera
`console.warn` — fail-open deliberado e coerente com o padrao do RACEKV1.

Ponto de atencao: `MIGRATION_PHASE` so existe como comentario em `src/worker.js:17246`. Nao
esta no `wrangler.toml`, no `CLAUDE.md` nem no vault. Quem virar a chave para `"1"` amanha
nao tem runbook.

**VALID1** esta vivo e comprovado em producao, com os dois defeitos da tabela acima. Vale
registrar que o valor de protecao CSRF se mantem mesmo com o fail-open, porque form HTML
sempre manda um `Content-Type` (e portanto cai no ramo bloqueado). O que passa e cliente
programatico sem header, que nao e o vetor CSRF classico.

Auth de rotina: `body.routine_key !== env.ROUTINE_API_KEY` em 10 handlers, sempre
fail-closed. Nenhum fallback literal para `JWT_SECRET`, `ADMIN_PASSWORD` ou chave de API.
`Math.random` aparece 2 vezes, ambas em jitter/sampling, nenhuma em geracao de token.

## Frontend

O achado central esta na tabela. O padrao e sempre o mesmo, um corpo de funcao cortado no
meio de uma expressao seguido direto por `/* comentario */` e o proximo `export function`.

**Correcao ao numero publicado na primeira versao desta nota.** Eram **sete** truncamentos,
nao tres. O `node --check` para no primeiro erro de cada arquivo, entao a contagem inicial
media arquivos quebrados, nao funcoes perdidas. So apareceram todos na leitura linha a linha
durante o conserto. Isso muda a leitura do incidente: nao foi um corte acidental em tres
pontos, foi um padrao sistematico de escrita truncada ao longo de um commit inteiro.

| Arquivo | Linha | Funcao cortada | O que faltava |
|---|---|---|---|
| `app/js/api.js` | 98 | `fetchWithRetry` | corpo do `catch (err) {`, fechamento do `for`, `throw lastError` final |
| `app/js/admin/shared.js` | 68 | `skeletonBlock` | concatenacao termina em `+` solto, faltava fechar o `for` e o `return` |
| `app/js/admin/shared.js` | 99 | `wrapWhenReady` | faltava fechar o `if`, o `setTimeout` de retry, `return false` e a chamada `attempt()` |
| `app/js/admin/modules.js` | 177 | `renderUserHealth` | terminava em `.join('');` sem `return`, sem a tabela e sem o `<thead>` |
| `app/js/admin/modules.js` | 214 | `sendReengage` | `finally {` vazio, faltava reabilitar o botao |
| `app/js/admin/modules.js` | 294 | `loadHoje` | faltava fechar o `forEach`, o `catch` de erro e a funcao |
| `app/js/admin/modules.js` | 349 | `injectStyles` | faltava `document.head.appendChild(s)` e o fechamento |

Os `app/admin/vr-admin-*.js` pre-migracao continuavam no repo e serviram de fonte fiel para
reconstruir seis dos sete. So o `fetchWithRetry` do `api.js` nao tinha antecessor, por ser
codigo novo, e foi reconstruido a partir do contrato da propria funcao e validado com teste
de comportamento nos quatro caminhos (404 sem retry, erro de rede com backoff, sucesso,
abort do chamador).

Os outros cinco (`admin-bootstrap.js`, `admin-router.js`, `admin/engajamento.js`,
`admin/metricas.js`, `admin/fase3.js`) passam em `node --check`. Como ES module resolve o
grafo inteiro antes de executar qualquer coisa, um so arquivo quebrado derruba os oito.

O que o painel admin perdeu em producao: aba Hoje (`injectHojeTab`, `initTabHoje`,
`loadHoje`), KPIs HEART (`calcHeart`, `renderHeartKpis`, historico em localStorage), saude
de usuario (`renderUserHealth`), **render dos heartbeats do watchdog** (`renderHeartbeats`),
reengajamento por email (`sendReengage`), e os modulos de engajamento, metricas e polish de
fase 3. O `renderHeartbeats` doi mais que os outros: e a leitura visual dos 6 heartbeats que
o watchdog vigia.

Mitigacao que ja existe sem ninguem ter planejado: os cinco `vr-admin-*.js` antigos seguem
servidos em `https://vixradar.com/admin/` com HTTP 200. So nao estao mais referenciados pelo
HTML. Se a urgencia for maior que o apetite de corrigir os modulos, restaurar as cinco tags
`<script src="admin/vr-admin-*.js">` devolve o painel na hora.

`app/index.html` e `app/deploy_zip/index.html` estao byte a byte identicos (700396 bytes).
Os `.js` de `app/js/` e `app/deploy_zip/app/js/` tambem. A sincronia manual foi feita certo,
o problema e que ela foi manual.

## Veracidade da UI

`audit-ui-metrics.mjs` rodou com **exit 0**: nenhum encoding de severidade incoerente, 9
cores de familia fixa sobre valor interpolado (informativo), 5 metricas no inventario, 3
rotulos reservados a conferir.

Conferencia manual dos 3, contra `references/glossario-dominio.md`:

- **Emissores** = `Object.values(EMISSORES).reduce((a,b)=>a+b.length,0)`. Universo monitorado. Confere.
- **Criticos** = `c.size`, onde `c = new Set(criticos.map(e=>e.empresa))`. Emissores distintos com evento CRITICO. Confere.
- **Relevantes** = `d.size`, onde `d = new Set(relevantes.filter(e=>!c.has(e.empresa)).map(e=>e.empresa))`. Exclui os ja criticos, exatamente como o glossario manda. Confere.

O card **Sem alertas** continua correto apos UISEMANTICA1:
`((totalEmissores - criticosAtivos - relevantesAtivos) / totalEmissores * 100).toFixed(0)`,
com as mesmas faixas (>=90 / >=70) governando cor do numero e do chip. A correcao de
2026-07-27 sobreviveu a todos os deploys desde entao.

Existe um `saudeMedia = ((setores - setoresComProblema)/setores*100)` calculado no mesmo
bloco, que e setorial e nao emissorial. Ele **nao** alimenta o card. Se um dia alguem
precisar exibi-lo, precisa de rotulo proprio, nunca "Sem alertas".

Regra CSS do `strong`: nenhuma regra global com `color`. As 6 encontradas sao todas escopadas
(`.ph-metric strong`, `.ph-pill strong`, `.ews-disclaimer strong`, `.com-author-label strong`,
`.cover-meta strong`, `.disclaimer strong`). Regra respeitada.

## Seguranca, perf e a11y

Seguranca ja coberta acima. Nada de secret hardcoded, nada de fallback inseguro, auth de
rotina fail-closed.

Performance, medida com Navigation Timing real em `https://vixradar.com`: 165 KB
transferidos, 700 KB decodificados, `domInteractive` 117 ms, `domContentLoaded` 120 ms,
`loadEventEnd` 131 ms, 29 recursos, 27 scripts inline, 3 externos. Melhor do que o tamanho
do HTML sugere. Nada aqui e P0 nem P1.

A11y, amostra na home: `lang="pt-BR"` presente, 31 inputs e **zero** sem nome acessivel, 201
botoes e **zero** sem nome acessivel, 8 dialogs e todos com `aria-modal`. Duas ressalvas
menores: nao existe skip link (WCAG 2.4.1, nivel A) numa pagina com navegacao pesada, e a
home tem 3 elementos `<h1>`.

## IA generativa / cascade LLM

`sem_eventos` continua com o contrato forte no prompt: a REGRA 2 exige `cobertura_nota`
preenchido com o resultado de cada uma das 9 rodadas, e a REGRA 3 proibe assumir ausencia
sem as rodadas documentadas. Isso e o que sobrou do incidente de 27/07, e esta no lugar.

`carregarEstadoMultiSemana` aparece 24 vezes: 15 com janela 5, 5 com 3, 3 com 2 e 1 com
argumento variavel. A skill manda conferir que os endpoints multi-semana usem 5 — a maioria
usa, mas as 8 chamadas com 2 ou 3 nao foram rastreadas ate o endpoint. Fica como lacuna.

`retratarEventoRejeitado` presente (8 ocorrencias), fila `radar:verif_fila:{data}` viva,
`verificador_ok:true` no health. Verificador adversarial segue no caminho critico.

Sobre o **shadow DeepSeek** novo (`scripts/lib/vixradar-noturno-shadow-deepseek.ps1`, 15 KB,
untracked): li o cabecalho e a arquitetura e ela e defensavel. E shadow-only, nunca submete
ao Worker, reclassifica com as mesmas fontes que o Claude ja usou, e le a chave de
`DEEPSEEK_API_KEY`/`VIXRADAR_DEEPSEEK_API_KEY`, que nao colidem com as variaveis vigiadas
pelo `Test-VixClaudeAmbienteLimpo`. Nao e uma repeticao do incidente de 27/07. O problema e
so de governanca: esta untracked e dot-sourced sem guarda.

## Rotinas e working tree

Working tree sujo: 7 arquivos modificados (177 insercoes, 32 delecoes), quase todos na
camada de rotinas, mais 2 scripts novos untracked e `data/historico/2026-08-03/` e
`docs/superpowers/` sem rastreio.

Um item do diff merece leitura antes de commitar. `Set-VixClaudeAuthEnv` passou a fazer
`[Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User')` e o mesmo
para `ANTHROPIC_API_KEY`, ou seja, **apaga as duas variaveis do registro do usuario** a cada
invocacao de lote. O comentario assume isso ("sera removido permanentemente do registro
User"). E uma decisao coerente com o historico de contaminacao por agregador, mas e mutacao
persistente de estado da maquina disparada por rotina desatendida, e vai quebrar em silencio
qualquer outra ferramenta do perfil que dependa dessas duas variaveis. A chave paga do
projeto (`VIXRADAR_ANTHROPIC_API_KEY`) tem nome proprio e sobrevive.

## Cobertura desta auditoria

| Camada | Coberta | Metodo | Lacuna |
|---|---|---|---|
| Repo e governanca | Sim | `git status`, `git log`, `git show --stat` | — |
| Worker: bindings, crons, versao | Sim | `wrangler.toml` + health publico | — |
| Worker: VALID1 / LOG1 / MIGRA-DO1 | Sim | leitura de `src/worker.js` + 4 testes HTTP vivos | — |
| Worker: auth e secrets | Parcial | grep dirigido, teste de `routine_key` por leitura | `wrangler secret list` nao executado |
| Frontend: drift e modulos | Sim | diff repo x producao, `node --check` nos 8 modulos, import dinamico no navegador | — |
| Veracidade da UI | Sim | `audit-ui-metrics.mjs` (exit 0) + conferencia manual dos 3 termos | — |
| Performance | Sim | Navigation Timing real | LCP/INP/CLS de campo, p75 mobile |
| A11y | Parcial | amostra DOM na home | teclado, foco, contraste, admin e modais |
| IA / cascade | Parcial | prompt de `sem_eventos`, verificador, fila | prompt injection nao testado de forma adversarial |
| Multi-semana | Parcial | contagem de `carregarEstadoMultiSemana` | 8 chamadas com janela 2 ou 3 nao rastreadas ate o endpoint |
| Floating promises / estado global | Nao | so contagem de `waitUntil` (2) | 880 KB exigem AST, nao grep. Nao afirmar nada aqui |
| Painel admin autenticado | Nao | — | exige login, nao feito em modo readonly |
| GitHub Actions | Nao | — | sem acesso local ao GitHub ([[project_github_sem_acesso]]) |

Esta auditoria nao prova ausencia de bug. Ela cobriu as camadas acima com os metodos
acima, e o que ficou de fora esta declarado.

## Achado que so apareceu no conserto (VERCMP1)

`Compare-FrontendVersion`, o gate anti-regressao do `deploy-pages.ps1`, comparava versao
concatenando os digitos. `v202.1` virava `2021` e `v201.93` virava `20193`, entao o script
concluia que producao estava **a frente** do repo e abortava o deploy correto com a mensagem
"NAO deploye, regrediria producao".

```
ERRO: PRODUCAO ESTA A FRENTE DO REPO. Producao=v201.93, voce esta tentando deployar v202.1.
```

Isso quebra sempre que o minor muda de quantidade de digitos, ou seja, em **todo bump de
major**. Ficou latente desde que a funcao foi escrita porque o frontend passou dezenas de
deploys dentro da faixa `v201.x`, todos com minor de dois digitos, onde a concatenacao por
acaso da o resultado certo. A auditoria estatica nao pegou. So apareceu no primeiro `-DryRun`
depois de bumpar `CACHE_VERSION` para `v202.1`.

Corrigido comparando componente a componente, com 6 casos de teste incluindo o par que
falhava. Licao para a matriz da skill: gate de comparacao numerica precisa de caso de teste
com quantidade de digitos diferente, senao ele passa a vida inteira certo por coincidencia.

## Proximos passos

1. **P0** — fechar os 3 truncamentos, `node --check` nos 8 modulos, bumpar `CACHE_VERSION` para `v202.1` e deployar pelo `deploy-pages.ps1`. Se a pressa for grande, restaurar as 5 tags antigas primeiro e corrigir os modulos depois.
2. **P0** — acrescentar `app/js` ao sync do `deploy-pages.ps1` **antes** do item 1, senao a correcao nao chega em producao pelo caminho oficial.
3. **P1** — gate `node --check` sobre `app/js/**/*.js` no `deploy-pages.ps1` e no pre-commit. Esta e a guarda que fecha a causa raiz.
4. **P1** — trocar a lista obsoleta `vr-admin-*.js` do passo 3 do deploy pelos modulos vivos.
5. **P1** — VALID1: tratar `Content-Type` ausente como invalido e passar 415/413 pelo wrapper de CORS.
6. **P1** — corrigir os 2 travessoes de `vixradar-claude-auth.ps1` e commitar as 177 linhas pendentes das rotinas.
7. **P2** — deletar `api/src/logging.js` e `api/src/validation.js`, ou coloca-los no grafo de build.
8. **P3** — commitar `vixradar-noturno-shadow-deepseek.ps1` ou guardar o dot-source com `Test-Path`; documentar `MIGRATION_PHASE`; decidir o destino do LOG1.

## Mudancas na skill propostas por esta auditoria

A matriz (`references/audit-matrix.md`) nao tem nenhum item sobre **sintaxe de asset
frontend**. Ela cobre versionamento, cache, auth headers, estados vazios e XSS, e assumiu
que codigo publicado ao menos parseia. Proposta de item permanente na secao "Frontend
Pages": rodar `node --check` em todo `.js` referenciado pelo `index.html` e, quando o HTML
usar `type="module"`, provar o carregamento com `import()` dinamico no navegador contra
producao. O grep e a leitura nao pegam isso, so o parser pega.

Segunda proposta: a matriz assume que `deploy_zip/` reflete `app/`. A partir de MODULE-MIG1
isso deixou de ser garantido pelo script. Item novo: conferir que toda subpasta de asset em
`app/` aparece no bloco de sync do `deploy-pages.ps1`.

---

*Auditoria executada em 2026-08-04, modo readonly. Nenhum deploy, nenhum secret alterado,
nenhum arquivo do sistema modificado.*
