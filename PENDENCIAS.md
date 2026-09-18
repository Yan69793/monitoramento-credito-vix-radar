# PENDENCIAS.md — auditoria de débito técnico do VIX Radar

Gerado em 18/09/2026 por auditoria estática (`/auditoria-pendencias`), read-only, sobre o commit `3c15fa8` da branch `mva-provider-agnostic`.
Repo: `E:\Diretorio\Claude\Monitoramento de Credito`.

**Este arquivo não é a fila operacional do projeto.** A fila viva continua em `Obsidian VIX Radar/PENDENCIAS.md` (3370 linhas) e o estado em `status/ESTADO.md`. O que está aqui é a varredura de débito técnico ancorada em código, datada. Onde um achado coincide com item já aberto na fila, ele aparece marcado como `ATUALIZADO` e aponta para o item, sem reabrir discussão.

---

## Estado de execução (atualizado 2026-09-18, mesmo dia da auditoria)

Esta seção descreve o **presente**. Tudo abaixo dela é o registro da varredura como ela foi escrita, e não foi reescrito.

Branch `mva-provider-agnostic`. **Tudo deployado e commitado em 18/09.** Produção em **v4.9.258** no Worker e **v202.43** no frontend, ambas com as correções. Commits `13f5573` (correções), `f2eff04` (bundle do Worker) e `a44da04` (frontend), todos empurrados para o origin.

### Fase 3, segurança de frontend — EM PRODUÇÃO desde 18/09

| Achado | Situação | Onde |
|---|---|---|
| FE-01 | EM PRODUÇÃO | `app/index.html` — e-mail do operador fora do HTML, gate por `role==="admin"` |
| FE-05 | EM PRODUÇÃO | `app/index.html` — `impacto_credito` escapado; escape `h` renomeado para `escaparHtml` em 3 definições e 85 pontos |
| FE-06 | EM PRODUÇÃO | `app/index.html` — catch vazio virou registro e banner "SEM LEITURA", **com a regra CSS que faltava** para ele aparecer |
| FE-07 | EM PRODUÇÃO | `app/index.html` — `_vlog/_vwarn/_vinfo`, zero `console.*` cru |
| FE-08 | EM PRODUÇÃO | `app/index.html` — `_lsGet`/`_lsSet` validam forma e registram falha |
| FE-09 | EM PRODUÇÃO | `app/index.html` — e-mail em `data-*` com listener delegado |
| FE-10 | EM PRODUÇÃO | `app/index.html` (3 pontos) e `api/src/worker.js` (regex de gravação ancorada + `escapeHtml` no render do relatório compartilhado) |
| FE-02, FE-04 | AINDA ABERTO | Não são código; fora do escopo executado |

**Achado novo, medido durante a execução e não previsto nesta auditoria:** o FE-10 tinha uma terceira ponta no lado servidor. O relatório compartilhado montava `<img src="${br.logo_data_url}">` sem escape, e a validação de gravação (`/^data:image\/(png|svg\+xml|jpeg|jpg);base64,/`, sem âncora de fim) aceitava `data:image/png;base64,x" onerror="alert(1)"`. O valor passava, era gravado no KV e quebrava o atributo na renderização — XSS que dispara ao abrir o documento compartilhado, sem clique. Corrigido nas duas camadas.

### Fase 1, deploy e falha silenciosa do provedor — EM PRODUÇÃO desde 18/09

| Achado | Situação | O que foi feito |
|---|---|---|
| CFG-01 | EM PRODUÇÃO | `wrangler` declarado em `dependencies` de `api/package.json` com versão **exata** (`4.118.0`), lock regenerado, guarda nova `scripts/lib/vixradar-wrangler-pin.ps1` ligada no `deploy-worker.ps1`, que passa a executar o binário local em vez de `npx` |
| LLM-01 | EM PRODUÇÃO | Resposta 200 sem bloco de texto virou erro de provedor nos dois caminhos, com contador próprio no KV e ponto no Analytics Engine |
| LLM-02 | EM PRODUÇÃO | Backoff exponencial com jitter, teto e número de tentativas explícito |
| LLM-03 | EM PRODUÇÃO | Política única (`_llmFetchComRetry`) consumida pela análise e pelo verificador |
| CFG-04 | EM PRODUÇÃO | README sincronizado (v4.9.258); detector `scripts/check-version-drift.mjs` ligado no `check-drift.ps1` e em job próprio do `canonical-test.yml` |
| SEC-01, SEC-02, SEC-04, TST-01, TST-03, CI-01 | AINDA ABERTO | São Fase 2 e Fase 4, não executadas |

### Duas correções ao texto da auditoria

1. **CFG-01, o diagnóstico estava parcialmente errado.** A auditoria afirmou que `npm ci --omit=dev` remove o wrangler e "o npx recorre à rede". Medido em 18/09/2026: o wrangler **sobrevivia** ao `--omit=dev`, porque `@sentry/cloudflare` (dependência de produção) declara `wrangler` como **peer opcional**, e o lock o marcava `devOptional: true`. O defeito real é outro e é pior de enxergar: a versão da ferramenta de deploy era governada por uma aresta de **terceiro**, não por declaração própria. Bastava o `@sentry/cloudflare` parar de declarar esse peer para o wrangler sumir da árvore e o `npx` baixar outra versão no meio do deploy. A recomendação final coincide; o motivo escrito não era o medido.

2. **A premissa sobre `api/.env` não se confirmou.** O arquivo **não contém uma chave** `sk-ant-...`. O valor de `ANTHROPIC_API_KEY` ali tem 61 caracteres, não começa com `sk-ant-`, não casa forma de chave e é um marcador de placeholder. Nenhum commit do histórico contém string com forma de chave completa. O arquivo é ignorado por `.gitignore:10` (`*.env`), nunca foi versionado, e não aparece em diff algum. Continua valendo como higiene que o `api/.env` exista com placeholders em vez de valores.

### Revisão adversarial, e o que ela achou

As correções da Fase 1 passaram por revisão adversarial por um agente que não as escreveu. Achou **uma regressão grave que eu tinha introduzido**, e mais três defeitos menores. Todos corrigidos e provados.

**A regressão grave: a correção do LLM-01 estava derrubando o pipeline inteiro.** O `catch` do cascade em `consulta_empresa` (`api/src/worker.js:22098`) chama `registrarFalhaProvider` sem condição, e essa função (`:18251`) abre o disjuntor do provedor depois de **3 falhas em 5 minutos**, por 600s. Com o circuito aberto, o laço do cascade passa a pular o provedor para **todas** as empresas seguintes. No código anterior isso não acontecia porque a resposta vazia não lançava: `extrairJSON("")` devolvia `null` e o laço seguia. Ao transformar resposta vazia em erro — que é o que o LLM-01 pede — eu passei a alimentar o disjuntor com um evento que não é de indisponibilidade. O efeito prático: três respostas vazias seguidas na varredura matinal paravam a produção de eventos de todas as demais empresas, sem sintoma. Era um estrago maior que o defeito que a correção veio consertar.

Correção: o erro de resposta vazia carrega a marca `__respostaVazia`, e o catch do cascade não registra falha de provedor para ele. Resposta 200 sem texto significa que o provedor respondeu — é problema de conteúdo, de uma empresa, não de disponibilidade. A visibilidade não se perde: `registrarRespostaVazia` continua contando no KV e no Analytics Engine, em canal próprio.

Prova de duas pontas, pelo caminho real com o provedor controlado: com a guarda, quatro chamadas com resposta vazia deixam `cb:aberto:claude-haiku-analise` e `cb:falhas:...` **nulos**, e quatro chamadas com 5xx **abrem** o circuito (o contraste que prova que o disjuntor não foi desligado). Sem a guarda, o mesmo teste falha com `expected { aberto: true, …(2) } to be null`.

**Os três defeitos menores, também corrigidos:**

1. `scripts/lib/vixradar-wrangler-pin.ps1` não estava na lista de arquivos protegidos pelo gate de working tree nem no `git add` do deploy (`scripts/deploy-worker.ps1`). O deploy rodaria uma versão não commitada da guarda e o commit não a levaria — o GitHub ficaria com um `deploy-worker.ps1` que faz dot-source de um arquivo inexistente. As duas listas foram corrigidas, e o teste agora confere isso.
2. O teste do portão passava **por engano**: ele conferia a presença dos textos, não a ordem. Medido: movendo o bloco inteiro do portão para depois da linha de deploy, todos os literais continuavam no arquivo, o deploy rodava sem portão nenhum e o teste terminava verde. O mesmo valia para trocar a execução por `npx wrangler@4.118.0 deploy`, que não casa o literal `npx wrangler deploy`. Agora o teste confere a **sequência** (dot-source < chamada < aborto < deploy), confere a linha de deploy inteira e confere as duas listas do item acima. As duas mutações foram reproduzidas e as duas reprovam com exit 1.
3. A leitura do corpo da resposta de erro ficava **fora** da janela do timeout: o `clearTimeout` acontecia antes do `r.text()`, então um 4xx com corpo que trava penduraria sem limite. O corpo passou a ser lido antes de desarmar o temporizador. No mesmo ajuste, a mensagem de 5xx voltou a conter `5xx` além do número — o classificador `verificarHealthProvider` casa `/PROVEDOR_INDISPONIVEL.*5xx/` e passaria a cair em `erro_desconhecido` se viesse só `503`.

**Dois pontos que o revisor levantou e eu deixei como estão, com o motivo:**

- **429 não honra `Retry-After`.** O código descarta o header e espera 2s e 4s. Quando o provedor pede 30s, insistir em 2s aumenta a pressão em vez de aliviar. Corrigir é ler o header e usar o maior valor entre ele e o backoff. Não fiz porque é mudança de política, não de defeito, e o mandato pedia cobrir 429 sem especificar o header.
- **O contador de resposta vazia perde contagem sob concorrência.** É `get` seguido de `put`, sem atomicidade, porque o KV não tem incremento. O helper `_gIncrementarCounter` que já existia tem o mesmo defeito, então é padrão da casa. O número serve para ver ordem de grandeza, não para contabilidade exata.

### Risco residual desta execução

- ~~A mudança do Worker não tem bundle publicado.~~ **FECHADO em 18/09:** bundle `v4.9.258.js` gerado, deployado e validado em produção (`versao: v4.9.258`, `ok:true`).
- `CFG-02` continua aberto e **piorou**: medido no health de 18/09, `cvm_atribuicao_cobertura_pct = 13.3` e `cvm_atribuicao_quarentena = 9943` (9811 na varredura da manhã de 18/09, 9889 às 19h, 9915 às 21h, 9943 ao fechar o dia). **Cresce ~30 por hora.** É a prioridade de 19/09.
- **Efeito de latência no caminho de falha do provedor, e este é o risco mais material da Fase 1.** A política única de retry passou a valer 3 tentativas para os dois caminhos. O verificador antes fazia **uma** tentativa; agora faz três. Pior caso medido com as constantes declaradas (`timeout` de 55s na análise e 60s no verificador, esperas de 2s e 4s com jitter de até 50%):

  | Caminho | Antes | Sem orçamento | Com orçamento (atual) |
  |---|---|---|---|
  | `chamarClaudeAnalise` | 113s (2 tentativas, espera fixa de 2s) | 174s | **120s** |
  | `chamarClaudeVerificador` | 60s (1 tentativa) | 189s | **120s** (2 tentativas no pior caso) |

  O `orcamento_ms: 120000` no `LLM_RETRY_CONFIG` é o teto de tempo da cadeia de tentativas de **uma chamada**, e cada tentativa tem o timeout limitado ao que sobra dele. Falha rápida (429, 5xx imediato) continua usando as três tentativas; o que o orçamento corta é a tentativa lenta. Sem ele o pior caso era decidido pelo produto `max_tentativas × timeout_ms`.

  Isso só se materializa quando o provedor **trava** (timeout), não quando ele recusa rápido. Na rota `consulta_empresa`, que tem cache de último recurso, o usuário espera esses segundos a mais antes de receber a análise de ontem.

  **O número que importa não é por chamada, é por empresa.** `verificarEventosBatch` processa `batch_size: 5` em laço sequencial e engole a falha por lote, então uma empresa com 15 eventos passa por 3 lotes: 180s no código antigo, **567s sem o orçamento** — o que estourava o teto de 540s da varredura sozinha, porque esse teto é conferido **entre empresas** e nunca dentro do retry — e **360s com o orçamento**, dentro do teto.

- **As unidades não são as mesmas para os dois caminhos.** A análise saiu de 113s para 120s: ficou ~7s mais lenta que o comportamento original, e esse é o preço consciente de ela agora repetir 429 e falha de transporte, que antes não repetia. O verificador dobrou (60s para 120s) e trocou isso por retentar, que antes não fazia nenhuma vez.
- O mesmo efeito aparece em `api/test/fallback-ttl.test.mjs`, que depende do caminho de falha para exercitar o cache: os dois testes passaram de menos de 5s para cerca de 8s. Nenhuma asserção mudou, e o timeout implícito de 5s do Vitest virou um explícito de 20s com o motivo escrito no arquivo.
- As cópias canônicas no vault Obsidian (`Obsidian VIX Radar/PENDENCIAS.md`) e em `status/ESTADO.md` **não** foram atualizadas; só este arquivo, que é o relatório da auditoria.
### Fechamento do dia 18/09

| Item | Situação |
|---|---|
| Worker | **v4.9.258 em produção**, `ok:true`, todos os bindings e o Sentry OK. Commits `13f5573` (correções) e `f2eff04` (bundle). |
| Frontend | **em produção com as correções**. Commit `a44da04`. Validado por conteúdo: 8 marcadores, produção e repo com 0 divergência. |
| FE-01, FE-05, FE-06, FE-07, FE-08, FE-09, FE-10 | FECHADOS e no ar. |
| CFG-01, LLM-01, LLM-02, LLM-03, CFG-04 | FECHADOS e no ar. |
| CFG-02 | **ABERTO**, cobertura 13,3% e quarentena 9.943. Prioridade de 19/09. |
| SEC-01, SEC-02, SEC-04, TST-01, TST-03, CI-01 | ABERTOS. São Fase 2 e Fase 4. |

**Riscos aceitos:** 429 sem `Retry-After`; contador de resposta vazia aproximado (KV sem incremento atômico). Ambos registrados no código e na seção acima.

**Fragilidade observada:** `api/test/login-timing.test.mjs` falhou uma vez sob suíte completa (3755ms) e passa 3/3 isolado. Teste sensível a carga, sem relação com o diff do dia. Fica anotado para não ser confundido com regressão.

**Guarda que ficou cega, para não repetir:** o `deploy-pages.ps1` detecta "conteúdo mudou sem bump de versão" comparando `app/index.html` com `app/deploy_zip/index.html`. Como a Fase 3 exigiu manter os dois sincronizados byte a byte, essa comparação deixou de acusar e o frontend subiu com `CACHE_VERSION` **v202.43 inalterada**. Sem impacto prático medido — o HTML é servido com `Cache-Control: no-cache, must-revalidate` — mas a guarda precisa de outro sinal.

**Não iniciar em 19/09 sem decisão:** ARQ-01 (extração por domínio no `__coreFetch`), JWT/auth (SEC-02), KV/DO estrutural (EST-01, EST-02).
### Riscos aceitos, com o motivo

- **429 não honra `Retry-After`.** Medido: o Worker não lê esse header em lugar nenhum do caminho Anthropic (o `retry_after_sec` que existe no arquivo é do rate limiter interno, em `checkRateLimitV2`). Quando o provedor pede 30s, o código insiste em 2s e 4s e faz até 3 requisições dentro da janela limitada em vez de 1 — o retry que existe para aliviar a pressão é o que a aumenta. Não corrigido por decisão de escopo: usar o maior valor entre o header e o backoff é mudança de política, não defeito, e o orçamento de tempo já limita o estrago a 3 requisições por chamada. Registrado no código, no ramo do 429.
- **O contador de resposta vazia é aproximado.** É `get` seguido de `put` porque o KV não tem incremento atômico: duas respostas vazias simultâneas podem contar uma. Serve para ordem de grandeza; quem precisar do número exato usa o ponto no Analytics Engine, que não perde o evento individual. O `_gIncrementarCounter` que já existia tem o mesmo defeito, então é padrão da casa. Não foi criada infraestrutura nova para isso. Registrado no código, na função.

### Sobre o `npx`, depois do fechamento

Restava uma aresta: as duas sondas de credencial do `deploy-worker.ps1` (passos 0 e 0.3) passavam pelo `npx` e rodavam **antes** do `npm ci`. Com `node_modules` ausente, o `npx` podia baixar um wrangler da rede. **Fechado.** O arquivo não tem mais `npx` em nenhuma linha executável: um gate novo no passo 0.0 garante que o binário declarado existe (instalando pelo lock se preciso) e confere a versão **antes de qualquer chamada ao wrangler**, e as duas sondas usam esse binário por parâmetro. Quatro mutações foram reproduzidas e reprovam o teste: gate movido para depois do deploy, gate movido para depois das sondas, deploy via `npx wrangler@4.118.0 deploy`, e sonda usando `npx`.

---

## Cobertura desta rodada, e seu limite

Seis escopos foram despachados em paralelo e todos os seis terminaram em falha, com `HTTP 402` no provedor configurado para delegação (OpenRouter, `config.yaml:110-113`, modelo `moonshotai/kimi-k2.5` com fallback em `z-ai/glm-5.3`, ou seja primário e fallback no mesmo provedor, pool em `last_status=exhausted / billing`). Dois desses subagentes escreveram o relatório em disco antes de morrer, então os arquivos foram recuperados depois e cada afirmação deles foi reconferida por leitura direta nesta sessão, com o resultado da reconferência em seção própria. Os quatro escopos restantes (segurança e auth, estado e KV e DO, cascade LLM com fonte CVM, scripts PowerShell) foram medidos direto do início ao fim, com comando e saída citados.

O que **não** foi medido nesta rodada, e não deve ser lido como ausência de problema: profundidade de cada handler administrativo do Worker, comportamento em runtime do dual-write KV/DO, a leitura linha a linha dos 15 pontos de `innerHTML` no frontend, e comportamento real do frontend no navegador. Onde a leitura não bastou para afirmar, o item está em Perguntas abertas, não na tabela.

---

## Síntese

1. `api/package.json` **não declara o wrangler**, e o deploy depende dele (`npm ci --omit=dev` seguido de `npx wrangler deploy`). Hoje ele só existe por dependência transitiva. É o achado com maior chance de quebrar produção sem aviso.
2. `chamarClaudeAnalise` devolve **string vazia como sucesso** quando a resposta do provedor vem sem bloco de texto. Falha de análise pode virar evento silencioso, mesma família do incidente FEEDRETRO1.
3. A cobertura de atribuição de documento da CVM ao emissor **caiu de 36,1% (01/09) para 13,2%**, medida no health de hoje, com 9811 documentos em quarentena. Não aparece como item aberto na fila.
4. Duas falhas de segurança medidas. O bypass de rate limit libera o caminho `auth` quando o binding do Durable Object falta, e o e-mail do usuário entra cru em cinco handlers inline do painel admin, com a validação do Worker barrando só `<` e `>`, o que deixa apóstrofo e parêntese passarem.
5. `README.md` declara Worker **v4.9.255** enquanto produção roda **v4.9.257** e o `wrangler.toml` já aponta para `v4.9.257.js`. O README é a única tabela de versão viva desde que SYNC-VERSION-DOCS aposentou a do CLAUDE.md.
6. JWT com **12h de validade e nenhum mecanismo de revogação**. Logout no cliente não invalida nada no servidor.
7. **133 bundles `api/v4.*.js` versionados, 117 MB dentro do git** e 165 no disco, para uma janela de rollback que ninguém sabe dimensionar. A política está escrita no `.gitignore`, então isto é preço aceito, não descuido.
8. O watchdog do Worker cobra **5 heartbeats** (`worker.js:22078`), o `CLAUDE.md` documenta **7**, e o `status/ESTADO.md` cita uma linha (`worker.js:19471`) que hoje contém código do briefing. Documento e código divergem nos três.
9. Nenhuma marcação `TODO`/`FIXME` real existe em código vivo, os scripts do Task Scheduler respeitam PowerShell 5.1 e o frontend publicado está byte a byte igual à fonte. A disciplina de execução do projeto é boa, o débito está em contrato e em observabilidade, não em bagunça.
10. `npm audit` acusa **4 vulnerabilidades altas** (`sharp` e `undici`), todas pela cadeia de build (`wrangler`/`miniflare`), nenhuma no runtime produtivo do Worker.

---

## Modelo mental da arquitetura

O sistema tem dois cérebros e uma ponte. Do lado Cloudflare, um Worker de arquivo único, `api/src/worker.js`, com cerca de 23.000 linhas, que é ao mesmo tempo API, ingestão de fonte externa, motor de verificação, emissor de e-mail e páginas administrativas. Ele guarda estado no KV `RADAR_KV` e migra, de forma incremental e silenciosa, para cinco Durable Objects, com dual-write e fallback de leitura. O frontend é um HTML de 7.026 linhas servido por Pages, sem build step, com módulos de admin carregados por query string de versão trocada à mão. Do lado da máquina do operador, rotinas PowerShell agendadas no Task Scheduler chamam um provedor de LLM e devolvem o resultado para o Worker por POST autenticado com `routine_key`.

Os dois lados se conhecem por contrato, não por import. Isso explica a maior parte dos achados abaixo, porque contrato sem teste é contrato que deriva, e o projeto compensa isso com documentação densa, o `CLAUDE.md` com 446 linhas de regras e um vault Obsidian com centenas de notas datadas. A documentação substituiu o compilador, e onde ela ficou para trás, o código é a verdade.

O que surpreende na Fase 1 é a assimetria. O rigor de execução é alto, com linter de encoding, hook de pre-commit que varre segredo no blob em staging, prova de duas pontas exigida por regra escrita, e CI com nove workflows. Ao mesmo tempo, não existe teste para o caminho em que o provedor responde vazio, o número de emissores oscila entre 103 e 104 a depender do documento, e o watchdog cobra um conjunto de agentes diferente do que a documentação declara. O projeto mede muito bem o que já quebrou uma vez, e mede pouco o que ainda não quebou.

---

## Tabela de achados

Status `NOVO` significa achado desta varredura com citação verificada agora. `ATUALIZADO` significa item já conhecido na fila do vault, com a situação remedida.

| ID | Categoria | Arquivo/Linha | Severidade | Esforço | Status | Descrição | Recomendação |
|---|---|---|---|---|---|---|---|
| ARQ-01 | Decadência arquitetural | `api/src/worker.js:19986-22018` | Alto | G | ATUALIZADO (F001 da auditoria de 16/06) | `__coreFetch` é o roteador único de tudo e cresceu de 1.139 linhas em junho para 2.033 agora (medido de 19986 até 22018, com o `scheduled` começando em 22024), com 108 comparações `action ===` espalhadas no arquivo. Nenhuma extração por domínio foi feita. Não muda comportamento, muda a capacidade de testar e de revisar. | Extrair por domínio em funções nomeadas (`handleAuth`, `handleAdmin`, `handleIngestao`, `handleObs`), mantendo o dispatch com poucas linhas. Fazer isso depois de estabilizar a migração KV para DO, para não misturar duas frentes. |
| CFG-01 | Dependency debt | `api/package.json:1-21`, `scripts/deploy-worker.ps1` | Alto | P | NOVO - EM PRODUCAO 18/09 | O wrangler não está declarado. `grep -c wrangler api/package.json` devolve 0, e `npm ls wrangler` mostra `wrangler@4.118.0` apenas transitivo de `@cloudflare/vitest-pool-workers` e `@sentry/cloudflare`. Como o deploy roda `npm ci --omit=dev` antes de `npx wrangler deploy`, a ferramenta de deploy depende de uma devDependency que o próprio `--omit=dev` remove, e o npx recorre à rede. | Declarar `wrangler` como dependência explícita de `api/package.json` com a versão que está em produção, e adicionar verificação de `npx wrangler --version` ao portão do deploy. |
| LLM-01 | Cascade LLM | `api/src/worker.js:8932` e `:14012` | Alto | P | NOVO - EM PRODUCAO 18/09 | `chamarClaudeAnalise` devolve `(data.content \|\| []).filter(c => c.type === "text").map(c => c.text).join("\n")` na linha 8932, e `chamarClaudeVerificador` faz o mesmo na 14012. Resposta 200 sem bloco de texto, por recusa, resposta só de ferramenta ou corpo truncado, vira string vazia e segue como sucesso. Não há contador de resposta vazia por provedor. | Tratar `texto.trim() === ""` como erro de provedor nos dois caminhos e contar a taxa de resposta vazia por modelo no Analytics Engine. |
| CFG-02 | Integração fonte externa | health 18/09/2026 19:52 UTC | Alto | G | NOVO | `cvm_atribuicao_cobertura_pct = 13.2` e `cvm_atribuicao_quarentena = 9811`, contra `36,1%` com 1439 de 2252 sem dono registrados em `status/ESTADO.md` em 01/09. Queda material em 17 dias, sem item aberto na fila com esse número. | Remedir com `admin_documentos_cvm` e abrir item. Se for material novo ainda em quarentena, a métrica precisa de janela. Se for regressão do árbitro `_donoDocumentoCVM`, é a família do SUBSTRINGDONO1. |
| SEC-01 | Rate limit e abuse | `api/src/worker.js:17972-17983` | Alto | P | ATUALIZADO (F017 da auditoria de 16/06) | `checkRateLimitV2` devolve `allowed:true` no caminho `auth` quando `env` ou `RATE_LIMITER_DO` faltam, marcando `_bypass` e disparando `_rlAlertaAuth`. Só o caminho `critica` é fail-closed. Com o binding removido, a proteção anti-brute-force do login desaparece em silêncio, e o único registro é o blob `rl_bypass_auth` em `api/src/worker.js:17960-17961`, que nenhum alerta lê. | Fazer `auth` falhar fechado ou elevar o bypass a `ok:false` no health, e ligar `rl_bypass_auth` a contador visível. |
| SEC-02 | Auth e JWT | `api/src/worker.js:4677` | Alto | M | NOVO | `exp: nowSec + 12 * 3600`, sem `jti`, sem denylist e sem versão de credencial. `verificarJWT` (`:4691`) só checa assinatura e expiração. Trocar a senha não derruba sessão viva e o logout é puramente local (`app/index.html:3522`). | Reduzir a validade e introduzir versão de credencial conferida na verificação, invalidando tokens antigos na troca de senha. |
| EST-01 | KV | `api/src/worker.js:4801, 4848, 5153, 5161, 7879, 9565` | Médio | M | NOVO | 103 escritas `RADAR_KV.put(` contra 83 `expirationTtl`. 55 escritas não declaram TTL na mesma linha, das quais 5 declaram na linha seguinte (`:5064`, `:5110`, `:5174`, `:6401`, `:6739`). O residual precisa de leitura caso a caso. Amostras: `users:index` (`:4801`, `:4848`), chave por usuário `k.name` (`:5153`, `:5161`), `CVM_FONTE_META_KEY` (`:7879`) e `key` (`:9565`). | Classificar cada escrita em durável por desenho ou volátil com TTL, e marcar no código a decisão, do mesmo modo que `CVM_DOCUMENTOS_TTL_SEG` faz. |
| LLM-02 | Cascade LLM | `api/src/worker.js:8913-8941` | Médio | P | NOVO - EM PRODUCAO 18/09 | Retry limitado a 2 tentativas com espera fixa de 2s, apenas para 5xx e timeout. O 429 lança `RATE_LIMIT` e sai da função sem tentar de novo (`:8924`). Não há backoff exponencial nem jitter. | Backoff exponencial com jitter para 429 e 5xx, com registro do motivo da última falha anexado ao resultado. |
| LLM-03 | Cascade LLM | `api/src/worker.js:13981-14030` | Médio | P | NOVO - EM PRODUCAO 18/09 | `chamarClaudeVerificador` faz uma tentativa única e não trata 429 nem 5xx como o de análise trata, apesar de usar o mesmo endpoint e os mesmos códigos. Duas políticas de resiliência para o mesmo provedor. | Extrair a política de retry e timeout para helper único consumido pelos dois caminhos, mantendo `VERIFICADOR_CONFIG.timeout_ms` (`:13802`, 60000) como parâmetro. |
| CFG-03 | Observabilidade | `api/src/worker.js:22078` contra `CLAUDE.md:370-376` | Médio | P | NOVO | A lista viva do watchdog tem 5 agentes (`sync_cvm`, `newsletter`, `healthcheck_diario`, `varredura_local`, `verificacao_async`). O `CLAUDE.md` documenta 7, incluindo `varredura_batch`, `varredura_matinal` e `cascade_analise`. O `status/ESTADO.md` cita `worker.js:19471` como o ponto da lista, e essa linha hoje contém código do construtor de briefing. | Alinhar documento e código, e trocar a citação por linha por citação por nome de função, que não envelhece. |
| CFG-04 | Documentation drift | `README.md:24`, `README.md:84` | Médio | P | NOVO - EM PRODUCAO 18/09 | README declara `v4.9.255.js` e "Worker v4.9.255 confirmada 2026-09-16". O `api/wrangler.toml:1412` aponta `main = "v4.9.257.js"` e o health devolve `versao: v4.9.257`. O README é a tabela de versão canônica desde que SYNC-VERSION-DOCS aposentou os blocos do CLAUDE.md. | Rodar `scripts/sync-version-docs.ps1` e incluir a conferência no portão de deploy, que já valida produção. |
| CFG-05 | Repo hygiene | `.gitignore:76-95`, `api/v4*.js` | Baixo | M | ATUALIZADO (F020 de junho) | 133 bundles versionados somando 117 MB no git, e 165 no disco somando 129 MB. Os 32 restantes existem por desenho e ficam invisíveis ao `git status` por regra explícita do `.gitignore`. O bloco em `.gitignore:76-95` tem racional escrito, o bundle é o artefato auditável e ignorar obrigava `git add -f` no deploy e produziu 8 dias de drift em julho. A política está certa e o custo é real. | Não é defeito, é decisão com preço. Se o clone ficar pesado demais, a saída que preserva a auditabilidade é manter no git só o `main` e o rollback declarado, e arquivar o resto em release tag. |
| SEC-03 | Inconsistência | `api/src/worker.js:3627-3634`, `:3653-3660`, `:19975-19977` | Baixo | P | NOVO | Três mecanismos de CORS no mesmo arquivo: helper com allowlist explícita, objeto estático com origem fixa, e reescrita do header depois da resposta. O comportamento de segurança está correto, sem curinga e com `Vary: Origin`. O débito é a divergência. | Consolidar em um caminho único e apagar os outros dois. |
| SEC-04 | Auth e contrato | `api/src/worker.js:21204, 21382-21430, 21592-21594` | Médio | M | ATUALIZADO (ROUTINEKEY-PLAIN1) | A autenticação de rotina compara string crua em pelo menos 8 handlers (`body.routine_key !== env.ROUTINE_API_KEY`), sem comparação de tempo constante, e a chave viaja no corpo do POST. | Comparar digest com `crypto.subtle.timingSafeEqual` e tratar a rotação como item próprio, já aberto na fila. |
| SEC-05 | Documentação | `api/src/worker.js:4150-4160` | Baixo | P | NOVO | `hashSenha` usa PBKDF2-SHA256 com 100.000 iterações e salt de 16 bytes, e o hash descartável de LOGINTIMING1 (`:4639`) equaliza o tempo de resposta. Nada aqui está errado. O que falta é o número estar declarado no `CLAUDE.md`, que hoje não registra o parâmetro de custo. | Documentar o parâmetro de custo junto da regra de auth, para uma mudança de iteração não passar despercebida. |
| FE-01 | Security hygiene | `app/index.html:3481`, `app/index.html:4081` | Médio | P | NOVO | O e-mail pessoal do operador está embutido no HTML público e usado como gate de administração no cliente (`window.isAdminSession` e o bloco `vr-audit`). É a mesma classe do ADMIN_EMAIL que saiu do Worker em SECRETMISS1, agora no frontend, que é servido sem autenticação. | Mover a decisão para o servidor, que já autoriza, e tirar o endereço do bundle público. |
| FE-02 | Auth e JWT | `app/index.html:3481`, `:3522`, `:3716` | Médio | M | NOVO | O JWT fica em `localStorage` (`radar_jwt`) e é anexado por um wrapper global de `fetch`. A escolha veio da migração CSRF-COOKIE1, de cookie para header, e é coerente com ela. O efeito colateral é que qualquer XSS passa a exfiltrar credencial, e a CSP é deliberadamente ausente no projeto. | Registrar o tradeoff como decisão viva e considerar cookie `HttpOnly` com `SameSite` mais proteção de CSRF por token, ou aceitar explicitamente o risco por escrito. |
| FE-03 | Processo de release | `app/js/admin-bootstrap.js:15` | Médio | P | NOVO | O cache-busting dos módulos de admin é manual. O comentário manda trocar `?v=<antiga>` por `?v=<nova>` em `app/js/**/*.js` e no HTML a cada subida de versão. Hoje `app/index.html` e `app/deploy_zip/index.html` estão idênticos (sha256 `a85427c5...`) e todos os arquivos de `app/js` batem com o zip, o que mostra que a prática está sendo seguida, e mostra também que não há teste que reprove quando não for. | Gerar o sufixo a partir de `CACHE_VERSION` em `deploy-pages.ps1`, ou adicionar verificação de igualdade entre as três cópias ao portão de deploy. |
| PS-01 | Config debt | `scripts/register-all-routines-scheduler.ps1:45-47`, `scripts/register-coleta-volatilidade-task.ps1:9`, `scripts/cobertura-por-emissor.ps1:22` | Médio | P | NOVO | Caminhos absolutos da máquina embutidos como valor padrão, incluindo dois que apontam para outro projeto (`E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\scripts\...`). Funciona nesta máquina e quebra em qualquer outra, ou se o projeto for renomeado. | Mover para parâmetro com padrão derivado de `$PSScriptRoot` e deixar o valor específico da máquina só na chamada. |
| PS-02 | Decadência | `scripts/run_vixradar_ranking_mensal.ps1` | Baixo | P | NOVO | O script existe e a rotina está declarada OBSOLETA desde 18/08 (`CLAUDE.md:279`, "task não existe"). Script vivo para rotina morta. | Remover o script ou marcar no cabeçalho que é histórico, seguindo a regra 4 do próprio projeto. |
| PS-03 | Observabilidade | `scripts/lib/vixradar-openrouter.ps1:247-372`, `scripts/lib/vixradar-preflight.ps1:66-79`, `scripts/monitor-tasks.ps1:4` | Baixo | P | ATUALIZADO | 8 `catch { }` vazios em `vixradar-openrouter.ps1`, 6 em `vixradar-preflight.ps1` e 4 em `monitor-tasks.ps1`. Lidos um a um, todos envolvem limpeza (`Stop`, `Dispose`, `taskkill`), onde engolir é o comportamento correto. O risco residual é que um deles, em `:362`, engole falha ao adicionar header de requisição, e ali silêncio esconde erro de contrato. | Anotar no `:362` que a falha é esperada, ou logar em nível de aviso. |
| EST-02 | KV e DO | `api/src/worker.js:22768-22800` | Médio | G | ATUALIZADO (migração KV para DO, `CLAUDE.md:155-185`) | O dual-write registra falha em `console.warn` e o fallback de leitura devolve o valor do KV sem erro. É desenho declarado, e é também a razão pela qual uma migração travada não aparece em nenhum painel, como o próprio `CLAUDE.md:176-185` admite. | Expor contador de falha do DO no health, que hoje não tem campo equivalente a `emissor_do_ok`. |
| EST-03 | Performance | `api/src/worker.js:9574-9590` | Baixo | P | NOVO | `carregarEstadoMultiSemana` faz as leituras semanais em `Promise.all`. Está correto. A ressalva é que o merge percorre semana a semana e reatribui `merged[emp]._last_scanned_at` em ramo separado, com histórico de correção (DEFERGRUDA2 em `:9590`), num trecho sem teste equivalente ao de estado. | Cobrir o merge multi-semana com teste de comportamento, incluindo o caso de semana velha com evento e semana nova sem. |
| TST-01 | Test debt | `api/test/` (39 arquivos) | Médio | M | NOVO | A cobertura por hot path é boa em auth, CVM, e-mail, rate limit, agenda e verificador. Os buracos medidos são o retorno vazio do provedor de análise (LLM-01), a convergência das duas vias de escrita de `cvm:documentos` (TTL 30d em `worker.js:7789`), o dual-write KV/DO e a sincronia entre `app/`, `app/js/` e `app/deploy_zip/`. Nenhum desses tem teste hoje. | Escrever os quatro testes nomeados, que são pequenos e determinísticos, e amarrá-los ao CI existente. |
| TST-02 | Test debt | `.github/workflows/` (9 workflows) | Baixo | P | NOVO | `canonical-test.yml` valida o campo `ok` agregado a cada 6h, o que está correto e é o que derruba o build quando `sentry_ok` ou `admin_email_ok` caem. O `frescor-check.yml` reprovou 3 de 8 runs recentes por régua de dias úteis, item já em aberto no vault. Nenhum gate cobre a versão do Worker contra o README. | Adicionar ao `canonical-test` a comparação entre `versao` do health e a tabela do README, que é exatamente o drift de CFG-04. |
| CFG-06 | Dependency debt | `api/package.json:8-14` | Médio | P | NOVO | `npm audit --omit=dev` aponta 4 vulnerabilidades altas, `sharp <0.35.4` (GHSA-g89c-p67h-r497) e `undici 7.0.0 a 7.28.0`, alcançadas por `miniflare` e `wrangler`. Nenhuma afeta o runtime produtivo do Worker, que só importa `@sentry/cloudflare`. | Atualizar `wrangler` e `@cloudflare/vitest-pool-workers`, que arrastam as duas, e reexecutar o audit no CI. |
| CFG-07 | Documentação | `CLAUDE.md:431` e `CLAUDE.md:272` | Baixo | P | NOVO | O `CLAUDE.md` fala em 103 emissores em pelo menos dois pontos (`confere os 103 contra cad_cia_aberta.csv`, `103 emissores varridos toda noite`), enquanto o `README.md:3` e o health declaram 104. | Escolher o número canônico e corrigir o documento, ou explicar a diferença se houver duas réguas de contagem. |
| CMV-01 | Integração fonte externa | `api/src/worker.js:7789` | Baixo | P | NOVO | `CVM_DOCUMENTOS_TTL_SEG = 30 dias` com comentário registrando que a via manual e a automática já divergiram uma vez (14 contra 30) e o fix cobriu só uma delas. O valor único resolve hoje, e o comentário é a única garantia de que continua resolvido. | Teste que exercite as duas vias e compare o `expirationTtl` efetivo. |
| CMV-02 | Cascade LLM | `api/src/worker.js:11291-11334, 11487-11541, 12328-12366` | Médio | G | NOVO | Quatro dos arrays de provedor têm entrada única Anthropic, e o log do break ainda usa os rótulos `cascade-break-v4963-sem sufixo` e `cascade-break-v4963-sufixo M`, nomes que só significam algo no regime de múltiplos provedores. Sem fallback real, indisponibilidade da Anthropic para a análise, como o `CLAUDE.md:333-335` já declara. | Não reescrever o cascade. Ao migrar para o provider de Fase B, reduzir os arrays a um ponto único de resolução e renomear os rótulos de log. |
| OBS-01 | Observabilidade | `api/src/worker.js:5795, 5852, 5892, 6204, 7136, 8276-8282, 8502, 8520` | Baixo | P | NOVO | Timeouts existem e estão bem postos em toda chamada externa, incluindo 30s para admin, 20s para catálogo e cadastro da CVM, 60s para o ENET e 55s para a análise. O que falta é a contagem de quantas dessas chamadas morrem por timeout num dia, que existe só como log. | Emitir métrica por tipo de falha de terceiro, separando timeout de erro de protocolo e de conteúdo vazio. |
| OBS-02 | Observabilidade | `api/src/worker.js:5443-5463` | Baixo | P | NOVO | O painel de health interno monta HTML por concatenação e exibe saldo do OpenRouter e probe ao vivo, sem escape em vários campos interpolados. Os valores vêm de API de terceiro, o que torna o caminho de injeção improvável, não impossível. | Aplicar a mesma função de escape usada no resto do arquivo nos campos interpolados. |
| FE-04 | Segurança | `app/index.html:3806` e `:7008` | Baixo | P | ATUALIZADO | Reconciliado nesta rodada. Os dois `document.write` escrevem em janela nova (`window.open`), e o HTML escrito sai de um bloco de 17.322 caracteres que escapa os campos de texto por `h()`, inclusive `h((e.titulo\|\|e.evento\|\|e.descricao\|\|"").slice(0,70))`, `h(g)`, `h(b)`, `h(f)` e `h(x)`. Das 56 interpolações do bloco, as únicas sem escape são `e._empresa` e `SETOR_DE[e._empresa]`, que saem do cadastro local de emissores. Não há caminho de dado não confiável até o sink. Permanece como débito de padrão, não como vulnerabilidade. | Trocar por `Blob` mais `URL.createObjectURL` quando o trecho for tocado por outro motivo, sem tratamento de urgência. |
| FE-05 | Segurança | `app/index.html:3791` (`renderEventoCard`) | Médio | P | ATUALIZADO | `renderEventoCard` escapa 16 valores por `h()`, definido em `app/index.html:3806` como `e=>String(e??"").replace(/[&<>"']/g, ...)`, e deixa um texto de evento passar cru, `${e.impacto_credito||""}` no bloco "Impacto para crédito". Também frágil por construção: `h` é variável de uma letra reatribuída 8 vezes no arquivo (`var h` sete, `const h` uma), então qualquer sombreamento futuro transforma o card inteiro em sink sem escape e nenhum teste reprova. | Escapar o `impacto_credito` e renomear o escape para `escaparHtml` com escopo único, eliminando as outras sete atribuições de `h`. |
| FE-09 | Segurança | `app/index.html:3807` (cinco pontos) | Alto | P | NOVO | XSS armazenado confirmado no painel admin. O e-mail do usuário entra cru em cinco handlers inline, `adminAprovar('${e.email}')`, `adminRejeitar('${e.email}')` e `adminToggleWhiteLabel('${e.email}', ...)`. O Worker valida e-mail com `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`, que aceita apóstrofo e parêntese, e o guarda adicional bloqueia apenas `<` e `>`. Um cadastro com e-mail `x'),alert(1),('y@z.com` passa nas duas validações e quebra o atributo, executando no clique do admin. O mesmo cartão escapa `h(e.email)` para exibição, o que mostra que o escape existe no arquivo e foi esquecido no handler. | Remover o e-mail do handler e passar índice ou usar `data-*` com listener delegado. Como mitigação imediata de servidor, restringir o e-mail a caracteres de endereço na validação de cadastro. |
| FE-10 | Segurança | `app/index.html:3806` e `:3931` | Médio | P | NOVO | `logo_data_url` do branding entra sem escape em dois pontos como `<img src="'+A+'">` e `i.innerHTML='<img src="'+e.logo_data_url+'" ...'`. Basta um `"` no valor para sair do atributo e injetar handler. A origem é o formulário de white-label e o `window.BRANDING` que vem do `tenant_config` gravado no servidor, então o conteúdo persiste e é renderizado de novo em cada sessão. Não fica Alto porque exige permissão de branding para escrever. | Escapar o valor com o mesmo `h()` usado no bloco, ou validar no servidor que `logo_data_url` casa com `data:image/(png\|jpeg\|svg+xml);base64,`. |
| FE-11 | Decadência | `app/admin/vr-admin-{modules,metricas,engajamento,shared}.js` e os espelhos em `app/deploy_zip/admin/` | Baixo | P | NOVO | Quatro arquivos são a versão IIFE anterior ao refactor de módulos ES, e a única referência viva a eles é o comentário de cabeçalho dos substitutos, `ES module refactor (was vr-admin-metricas.js IIFE)`. Nada os importa, `app/js/admin-bootstrap.js` carrega só `./admin/*.js`, e os oito arquivos continuam publicados pelo Pages e servidos por URL direta. Cerca de 69 KB de código morto, legível por qualquer visitante. | Apagar os oito arquivos, deixando o refactor v202.1 como registro no `CACHE_VERSION` e no histórico do git. |
| FE-06 | Tratamento de erro | `app/index.html:4082` | Baixo | P | NOVO | `.catch(function(){})` vazio no monitor de providers. Falha de rede no painel de status vira silêncio, e o painel fica sem indicação de que não leu. | Registrar a falha e marcar o painel como sem leitura, como o resto da interface já faz. |
| FE-07 | Higiene | `app/index.html` | Baixo | P | NOVO | 20 chamadas `console.*` no HTML servido em produção. `console.log` em Worker vai para Workers Logs, o mesmo não vale no navegador, onde o log fica visível e serve de mapa para quem quiser explorar a página. | Remover ou condicionar a um modo de depuração. |
| FE-08 | Tipo e contrato | `app/index.html:4271-4272` | Baixo | P | NOVO | `_lsGet` e `_lsSet` fazem `JSON.parse` e `JSON.stringify` em `localStorage` sem validar forma. Valor corrompido ou escrito por outra versão da página cai no fallback silencioso, e o sintoma aparece longe da causa. | Validar a forma esperada antes de usar, e tratar divergência como estado inválido explícito. |
| TST-03 | Test debt | `api/test/login-timing.test.mjs` | Médio | M | NOVO | O caminho de auth tem teste de tempo de resposta e de rate limit, e não tem teste de fluxo completo, de login a acesso protegido, passando por expiração e por troca de senha. É o par natural de SEC-02, porque é esse teste que provaria a invalidação de sessão. | Teste de integração registro, login, expiração, troca de senha, token antigo recusado. |
| CI-01 | Test debt | `.github/workflows/worker-tests.yml` | Médio | P | NOVO | O workflow roda `npm test` sem cobertura e sem threshold. A suíte pode passar verde cobrindo uma fração do arquivo, e nada no CI mostra qual. | Rodar com `--coverage` e falhar abaixo de um piso declarado. |
| ENV-01 | Config debt | `api/src/worker.js` (`MIGRATION_PHASE`) | Baixo | P | NOVO | A variável `MIGRATION_PHASE` é lida no Worker, aparece 2 vezes no arquivo, e não existe em `api/wrangler.toml` nem na documentação. Quem lê o repo não sabe que ela existe nem quais valores aceita. | Documentar a variável e seus valores, ou declará-la em `[vars]` se não for secret. |

---

## Auditoria dedicada da superfície XSS de `app/`

Rodada de 18/09/2026, sobre o commit `3c15fa8`. Somente leitura, nenhum arquivo de `app/` foi alterado.

**Método.** Inventário mecânico de todos os sinks em `app/`: `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, `createContextualFragment`, `srcdoc`, `insertAdjacentText`, `eval`, `new Function`, `setAttribute` de `on*`, `href` e `src`, e atribuição de `location`. Cinquenta arquivos varridos, excluindo `node_modules`, `app/_arquivo` e `app/tests/__screenshots__`. Os arquivos espelhados em `app/deploy_zip/` foram comparados por `sha256` antes de qualquer conclusão, sete pares, todos idênticos, então auditar a fonte cobre o que está publicado. O inventário também mostrou que `app/admin/vr-admin-modules.js`, `vr-admin-metricas.js`, `vr-admin-engajamento.js` e `vr-admin-shared.js` **não são espelhos** de `app/js/admin/*.js`, e sim a versão IIFE anterior ao refactor v202.1, hoje sem importador. Viraram FE-11.

**Números medidos.** 121 sinks no total, 105 em `app/index.html` e 16 nos seis arquivos de admin. Para cada um, a origem do dado e a neutralização foram determinadas por leitura individual do trecho, não por proximidade de padrão. Triagem automática levantou 49 candidatas, todas lidas uma a uma. Resultado, **8 ocorrências em 3 caminhos confirmados sem neutralização**, 41 candidatas descartadas por origem ou por escape, e 3 pontos declarados inconclusivos.

### Confirmados

| Caminho | Sink | Origem do dado | Neutralização | Severidade |
|---|---|---|---|---|
| `app/index.html:3807`, `onclick="adminAprovar('${e.email}')"`, `adminRejeitar('${e.email}')` e `adminToggleWhiteLabel('${e.email}', ...)`, cinco ocorrências | Atributo de evento inline em `innerHTML` | input do usuário, e-mail do cadastro, persistido no KV e devolvido pela lista de usuários do admin | nenhuma, e a validação do Worker em `api/src/worker.js` aceita apóstrofo e parêntese, bloqueando só `<` e `>`. O mesmo cartão escapa `h(e.email)` para exibir, o que prova que o escape foi esquecido no handler | Alto, XSS armazenado com clique do admin |
| `app/index.html:3806` e `:3931`, `<img src="'+logo_data_url+'">` | Atributo `src` montado por concatenação | input do operador de branding, persistido no `tenant_config` e reaplicado em toda sessão | nenhuma, um `"` no valor sai do atributo | Médio, exige permissão de branding |
| `app/index.html:3791`, `${e.impacto_credito\|\|""}` no card de evento | conteúdo de evento vindo do backend | API | nenhuma nesse campo. Os outros 16 campos do mesmo card passam por `h()` | Médio |

### Falsos positivos descartados, com o motivo

| Item | Por que não é vulnerabilidade |
|---|---|
| `renderEmpPanel`, `risk-strip`, `${e.label}`, `${e.value}`, `${e.ref}`, `${e.status}`, `app/index.html:3791` | `METRICAS_CURADAS` é literal escrito na própria página, medido por `METRICAS_CURADAS={"Equatorial Energia":[{label:...`, sem qualquer `fetch`. Origem local confiável |
| Command palette, `u(t.titulo,d)` em `:4199` | `u()` aplica `i()` em todos os cortes da string, e `i()` é `String(t\|\|"").replace(/[&<>"']/g, ...)`. Escapado |
| `renderTimeline`, `insertAdjacentHTML` em `:6260` | Usa `esc(window._vixScrubMoney(ev.titulo\|\|ev.evento...))`. Escapado |
| `renderHeartKpis`, `modules.js:255` e `vr-admin-modules.js:387` | Valores numéricos do heartbeat, rótulos estáticos |
| `adminFiltrar`, `'Nenhum usuário '+(i\|\|"")` em `:4199` | Medido, as únicas chamadas passam `null`, `'pendente'`, `'aprovado'` ou `'rejeitado'`, de botões. Não há campo de texto que alimente `i` |
| `document.write` em `:3806` e `:7008` | Bloco de 17.322 caracteres com 56 interpolações, os campos textuais passam por `h()`, e as duas únicas sem escape são `e._empresa` e `SETOR_DE[e._empresa]`, do cadastro local |
| `insertAdjacentHTML` em `:4182`, template do botão "Visão Geral" | HTML literal com um selo estático "NOVO" |
| `renderSidebar`, badges de severidade em `:3780` | Rotulos e `aria-label` literais, mais o nome do emissor do cadastro local |
| `${e.status}` em `class="admin-badge ${e.status}"` | Enum controlado pelo backend, sem caminho de usuário |
| `rows`, `totalText` e `feedHtml` em `:4645`, `:4678` e `:4699` | Datas, contadores e resultado de builders que escapam, `renderEventoCard` e `renderTimeline` |

### Inconclusivos

| Ponto | O que falta medir |
|---|---|
| `${f.empresa}`, `${f.desde}` e `${f.nota}` no painel de flags, `app/index.html:3807` | De qual endpoint vêm os flags e se `nota` aceita texto livre de operador. Sem caminho de usuário identificado, mas não li o handler |
| `${_d.erro}`, `${_d.erro\|\|"falha"}` e `(n.erro\|\|"desconhecido")`, `app/index.html:3807` | Mensagem de erro devolvida pelo próprio backend, sem escape. Se algum dia ecoar texto de entrada, vira reflexão |
| `${o[i.fator]\|\|i.fator}` em `renderEWSEmpresa`, `:3806` | O fallback é rótulo de fator vindo da decomposição da API. Rótulo desconhecido é renderizado cru |

---

## Top 5 prioridades absolutas

### 1. CFG-01, declarar o wrangler e provar no portão

O deploy de produção passa por uma ferramenta que o manifesto não declara.

```diff
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.20.1",
-   "vitest": "^4.1.10"
+   "vitest": "^4.1.10",
+   "wrangler": "4.118.0"
  }
```

E no portão do `deploy-worker.ps1`, antes do `npm ci`:

```powershell
$wv = (& npx wrangler --version) 2>&1
if ($LASTEXITCODE -ne 0 -or $wv -notmatch [regex]::Escape($WranglerEsperado)) {
  Write-Host "ABORTA: wrangler ausente ou em versao diferente de $WranglerEsperado"
  exit 1
}
```

Por que primeiro. É o único achado que pode derrubar o deploy inteiro, e a falha seria não determinística, dependente de a versão transitiva continuar existindo depois da atualização de outro pacote.

### 2. LLM-01, resposta vazia do provedor para de ser sucesso

```diff
-      return (data.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
+      const _texto = (data.content || []).filter((c) => c.type === "text").map((c) => c.text).join("\n");
+      if (!_texto.trim()) {
+        registrarMetricaProvider(env2222, { evento: "resposta_vazia", modelo });
+        throw new Error("PROVEDOR_INDISPONIVEL: resposta vazia");
+      }
+      return _texto;
```

Por que segundo. Uma observação sem sinal não é observação. O sistema já pagou esse preço uma vez, quando o provedor respondia e o pipeline aceitava, no incidente FEEDRETRO1.

### 3. CFG-02, apurar a queda de atribuição da CVM

Não há diff aqui, há medição que falta. O health de hoje diz 13,2% de cobertura com 9811 em quarentena, contra 36,1% registrado em 01/09. Rodar `admin_documentos_cvm` para uma amostra de emissores com documento sabidamente publicado e comparar com o acervo. Se a queda vier de material novo que ainda não passou pelo árbitro, a métrica precisa de janela e o item fecha. Se vier de regressão do `_donoDocumentoCVM`, é a mesma família do SUBSTRINGDONO1, que custou nove meses de documento da Eletrobras invisível.

### 4. SEC-01, fail-closed no caminho de login

```diff
-    if (criticidade === "auth") { _rlAlertaAuth(env2222, "do_binding_ausente", request); return { allowed: true, headers: {}, _bypass: "do_binding_ausente", _bypass_auth: true, ... }; }
-    return { allowed: false, headers: {}, _bypass: "do_binding_ausente", ..., retry_after_sec: 30 };
+    if (criticidade === "auth") { _rlAlertaAuth(env2222, "do_binding_ausente", request); return { allowed: false, headers: {}, _bypass: "do_binding_ausente", _bypass_auth: true, ..., retry_after_sec: 30 }; }
```

Por que quarto. Fail-open em leitura protege a disponibilidade do painel. Fail-open em login protege o quê. Se a decisão for manter, ela precisa estar escrita, e o bypass precisa aparecer no health, não só no Analytics Engine.

### 5. SEC-02, dar ao JWT uma forma de morrer

```diff
-  const body = b64urlEncode(JSON.stringify({ ...payload, iat: nowSec, exp: nowSec + 12 * 3600 }));
+  const body = b64urlEncode(JSON.stringify({ ...payload, iat: nowSec, exp: nowSec + 2 * 3600, cred: await versaoCredencial(env2222, payload.email) }));
```

Com a checagem em `verificarJWT` (`:4691`) recusando token cuja versão de credencial não bate com a atual, guardada no `USUARIO_DO` que já existe. Troca de senha passa a derrubar sessão viva, e o logout deixa de ser só uma limpeza de `localStorage`.

---

## Plano de execução priorizado

Nenhuma correção foi executada na sessão da varredura que escreveu este plano. O plano abaixo agrupa os 39 achados em cinco fases, na ordem de dependência e de risco, uma fase por deploy. Regra de aceite herdada do próprio projeto: prova de duas pontas, mostrando que a guarda reprova o caso ruim e aceita o caso bom, com a saída crua colada. Não misturar fase de Worker com fase de frontend no mesmo commit, senão o rollback fica ambíguo.

**Execução posterior, no mesmo dia:** as Fases 1 e 3 foram corrigidas, commitadas e deployadas em 18/09. O estado factual está em `## Estado de execução`, no topo deste arquivo. O plano abaixo permanece como foi escrito, e as fases 2, 4 e 5 seguem não iniciadas.

### Fase 1, deploy e falha silenciosa do provedor. Esforço P mais P

| Achado | Mudança | Prova de aceite |
|---|---|---|
| CFG-01 | Declarar `wrangler` em `api/package.json` com a versão que está em produção e conferir a versão no portão do `deploy-worker.ps1` antes do `npm ci` | `npm ci --omit=dev && npx wrangler --version` devolve a versão declarada, e o portão aborta quando a versão diverge, com as duas saídas coladas |
| LLM-01 | Tratar retorno sem bloco de texto como erro de provedor em `api/src/worker.js:8932` e `:14012`, com contador de resposta vazia | Teste novo com dois casos pelo caminho real, resposta com texto processa e resposta 200 sem texto falha com motivo, mais o contador visível na telemetria |
| LLM-02 e LLM-03 | Opcional nesta fase, se quiser um deploy só. Backoff com jitter na análise e política de retry única compartilhada com o verificador | Mesmos testes, com o tempo de espera parametrizado para não deixar a suíte lenta |

Risco da fase. Baixo. A mudança de contrato do provedor é a única que pode alterar comportamento em produção, e ela falha fechada, o que é o lado desejado. O deploy continua sendo o de sempre, `pwsh ./scripts/deploy-worker.ps1 -Version vX.Y.Z`.

### Fase 2, testes que travam o contrato acima e o que já existe sem prova. Esforço M mais M mais P

| Achado | Mudança | Prova de aceite |
|---|---|---|
| TST-01 | Testes para retorno vazio do provedor, convergência do TTL de `cvm:documentos`, dual-write KV e DO, e sincronia entre `app/`, `app/js/` e `app/deploy_zip/` | Suíte verde no CI, com os quatro nomes aparecendo na saída |
| CMV-01 | Teste que exercite as duas vias de escrita de `cvm:documentos` e compare o `expirationTtl` efetivo | Caso bom e caso ruim, o segundo falhando por TTL divergente |
| TST-03 | Teste de fluxo de auth completo, registro, login, expiração, troca de senha com token antigo recusado | Roda hoje marcando a falha esperada enquanto SEC-02 não é feito, e vira guarda depois |
| CI-01 | Cobertura no `worker-tests.yml` com piso declarado | CI publica a linha de cobertura e reprova abaixo do piso |

Por que depois da Fase 1. Teste sem contrato definido cristaliza o comportamento errado. A ordem inverte a tentação de escrever teste para o código que está prestes a mudar.

### Fase 3, segurança de frontend. Esforço P mais P mais P

| Achado | Mudança | Prova de aceite |
|---|---|---|
| FE-09 | Tirar o e-mail cru dos cinco handlers inline de `app/index.html:3807` e passar índice ou `data-*` com listener delegado. Enquanto isso não sobe, restringir a validação de cadastro no Worker aos caracteres válidos de endereço, o que fecha a porta de entrada sem tocar no frontend | Cadastro de teste com e-mail contendo apóstrofo e parêntese é recusado, e o painel admin lista, aprova e rejeita sem quebrar o atributo. Prova de duas pontas, o e-mail legítimo segue aceito |
| FE-10 | Escapar `logo_data_url` nos dois pontos e validar no servidor que o valor casa com `data:image/...;base64,` | Valor com aspas não sai do atributo e a imagem legítima continua aparecendo |
| FE-05 | Escapar `${e.impacto_credito}` no card e renomear o escape `h` para nome único, eliminando as outras sete atribuições | Evento de teste com `<script>` no `impacto_credito` renderiza como texto, e a busca por `\bh\b` como escape devolve zero |
| FE-01 | Tirar o e-mail do operador do HTML público, mantendo a autorização no servidor | `rg -c 'szuchmacheryan@gmail.com' app/` devolve 0 e o painel continua abrindo para quem tem permissão |
| FE-06, FE-07, FE-08 | Um catch vazio com log, 20 chamadas de console condicionadas, validação de forma nas duas funções de `localStorage` | Sem erro novo no console do navegador nas três telas principais |
| FE-02 | Não migrar agora. Registrar a decisão do JWT em `localStorage` no `CLAUDE.md`, com o motivo e o risco aceito | A decisão sai do campo tácito e passa a existir por escrito |
| FE-04 | Sem urgência, reconciliado como débito de padrão. O conteúdo dos dois `document.write` escapa os campos de texto | Entra junto de outra mudança naquele trecho, não como frente própria |

### Fase 4, separada, autenticação. Esforço M mais M

SEC-02, SEC-04, SEC-01 e TST-03 na ponta de guarda. Validade menor no JWT com versão de credencial conferida na verificação, comparação de tempo constante na `routine_key` e fail-closed no caminho `auth` do rate limit. Fica em fase própria por dois motivos. Toca as rotinas locais que autenticam com `routine_key`, então exige coordenar os dois lados do contrato, e a rotação da chave segue como decisão sua, aberta na fila do vault desde ROUTINEKEY-PLAIN1.

### Fase 5, separada, estrutural. Esforço G mais G

ARQ-01, extração por domínio em `__coreFetch`, com 2.033 linhas hoje. EST-02, contador de falha do DO no health. CMV-02, redução dos arrays de provedor quando a migração de provider da Fase B acontecer. CFG-05, política de janela de rollback. Nada disso corrige incidente em aberto, e tudo isso mexe em superfície ampla, então só depois das quatro primeiras fases estarem estáveis.

### Transversais, sem fase própria

Podem entrar em qualquer janela sem deploy de Worker: CFG-03, CFG-04 e CFG-07, que são texto contra código, PS-01, PS-02 e PS-03, que são scripts locais, SEC-03 e SEC-05, que são consolidação e documentação, ENV-01, OBS-01, OBS-02, EST-01, CFG-02, CFG-06 e FE-07.

---

## Ganhos rápidos

- [x] `CFG-04`, EM PRODUCAO 18/09: README sincronizado (v4.9.258) e detector `scripts/check-version-drift.mjs` ligado no gate. Registro original: rodar `scripts/sync-version-docs.ps1` e conferir a tabela do README contra `versao` do health. Uma linha, remove drift de versão visível a qualquer leitor.
- [ ] `CFG-03`, alinhar a lista do watchdog com o `CLAUDE.md`, ou corrigir o documento. Decidir qual é a régua antes de editar.
- [ ] `SEC-03`, apagar dois dos três caminhos de CORS. O helper com allowlist é o que deve ficar.
- [x] `LLM-02`, EM PRODUCAO 18/09: backoff exponencial com jitter. Registro original: trocar a espera fixa de 2s por backoff com jitter na análise.
- [ ] `SEC-05`, registrar no `CLAUDE.md` as 100.000 iterações de PBKDF2.
- [ ] `PS-02`, remover ou marcar como histórico o `run_vixradar_ranking_mensal.ps1`.
- [ ] `PS-03`, anotar a intenção do `catch` em `vixradar-openrouter.ps1:362`.
- [ ] `CFG-07`, escolher 103 ou 104 emissores como número canônico e corrigir o `CLAUDE.md`.
- [x] `FE-01`, EM PRODUCAO 18/09 (Fase 3): endereço fora do HTML público. Registro original: tirar o endereço pessoal do HTML público.

---

## Parece ruim mas está OK

**`catch { }` vazios nos scripts PowerShell.** São 8 em `vixradar-openrouter.ps1`, 6 em `vixradar-preflight.ps1`, 4 em `monitor-tasks.ps1`, e a leitura um a um mostra limpeza de recurso (`$ps.Stop()`, `$resp.Dispose()`, `taskkill` em processo já morto). Engolir ali é o comportamento correto, não preguiça. Só o `:362`, que engole falha ao adicionar header, merece nota.

**Rate limiter fail-open.** Decisão declarada, com o caminho `critica` já fail-closed e alerta por e-mail nos bypass. A crítica é só sobre o subcaminho de login, não sobre o desenho.

**`innerHTML` em 59 pontos do `app/index.html`.** O arquivo é minificado numa linha, com template literals longos e HTML por concatenação. Isso acende qualquer scanner, e não permite afirmar nada sem leitura linha a linha, que não foi feita. Nos módulos de admin, `app/js/admin/modules.js:306`, `metricas.js:33` e `engajamento.js:44` usam `esc()` nos dados de erro. Fica como pergunta aberta, não como achado.

**JWT em `localStorage`.** Veio da migração CSRF-COOKIE1, de cookie para header, e é coerente com a decisão. O risco de XSS é real e o tradeoff está registrado como FE-02, não como erro.

**Ausência de CSP.** Deliberada e documentada em `CLAUDE.md:446`, por causa dos scripts inline num HTML de 700 KB. Faz a decisão de `localStorage` doer mais, e continua sendo decisão.

**Cerca de 133 bundles `api/v4.*.js` no git.** Parece lixo e é histórico de reversão. Não é dead code alcançável e `pkg` nenhum os lê em runtime. Virou CFG-05 pelo tamanho, 117 MB no git e 129 MB no disco, não por correção.

**Retry fixo de 2s na análise.** É débil comparado a backoff, e funciona porque o provedor é único e responde rápido quando responde. Virou LLM-02 como melhoria, não como defeito.

**`__name`, `__name2` até `__name22222222`.** Polyfills do unenv concatenados pelo bundler. Já era assim na auditoria de junho (`TECH_DEBT_AUDIT.md:104`) e continua não sendo código do desenvolvedor.

**Os scripts do Task Scheduler violam nada de PowerShell 5.1.** Verificado. Nenhum ternário, `??` ou `?.` real fora de comentário, todos os wrappers declaram `$ErrorActionPreference = 'Continue'` e usam `exit`, e a varredura de BOM não acusou nenhum `.ps1` com caractere não-ASCII sem BOM. A regra do projeto nesse ponto está sendo cumprida.

**`carregarEstadoMultiSemana` com cinco leituras.** Usa `Promise.all` desde o fix de paralelização. O antigo F013 da auditoria de junho não se sustenta mais.

**133 bundles versionados e 32 fora do git.** Parece acúmulo sem critério, e é política escrita. O bloco `.gitignore:76-95` explica que ignorar os bundles obrigava `git add -f` no deploy e produziu 8 dias de drift entre repo e produção em julho, e que se o repo não sabe o que está no ar, não existe auditoria. Os 32 restantes são os superados, listados nominalmente, e ficam no disco para consulta local. O custo de 117 MB é o preço declarado dessa escolha. Virou CFG-05 como pergunta de política, não como defeito.

**`admin_senha` como input de `workflow_dispatch`.** Parece senha em texto livre em workflow, e o caminho tem `::add-mask::` na linha `.github/workflows/frescor-check.yml:38`, o input é opcional e vazio cai no `secrets.ADMIN_PASSWORD`. Comparado com `scan-emergencia.yml:78` e `daily-status-email.yml:73`, que mascaram do mesmo jeito, o padrão do repo é consistente.

---

## Perguntas abertas para o mantenedor

1. De onde vem a queda de cobertura de atribuição de 36,1% para 13,2%. Material novo em quarentena, mudança de metodologia de allowlist, ou regressão do árbitro.
2. A lista de 5 agentes no watchdog é a correta e o `CLAUDE.md` está otimista, ou o contrário. Qual das duas é a régua.
3. A janela de rollback real do Worker é qual. 133 bundles versionados em 117 MB pressupõem uma política que não está escrita em lugar nenhum.
4. O wrangler ficar fora do `package.json` foi decisão para não fixar versão no CI, ou descuido. Muda a correção de CFG-01.
5. O `catch` vazio de `vixradar-openrouter.ps1:362` esconde falha esperada ou erro de contrato silencioso.
6. O e-mail do operador no HTML público é aceito por ser ferramenta interna, ou é resíduo da fase anterior.
7. `103` e `104` emissores são réguas diferentes de contagem, ou o documento envelheceu.

---

## Procedência e reconferência dos relatórios de subagente

Dois dos seis subagentes morreram no passo final de resumo, depois de já terem escrito o arquivo de trabalho em disco. Foram recuperados de `C:\Users\User\AppData\Local\Temp\vixradar-audit-20260918\` e cada afirmação foi reconferida com comando próprio antes de entrar ou não nesta auditoria. Nada aqui foi aceito por auto-relato.

**Aceitos, depois de reconferidos.** Os achados FE-04 a FE-08, TST-03, CI-01 e ENV-01 entraram na tabela. A conclusão de que não há drift entre `app/` e `app/deploy_zip/` também entrou, e coincide com a minha medição independente por `sha256sum` e `diff`. O comando `npx wrangler deployments list` do relatório registra o deploy de `v4.9.257` em 18/09 17:48Z, coerente com o health que medí.

**Refutados, com a medição que derrubou cada um.**

| Afirmação do relatório | Medição que refuta |
|---|---|
| `@sentry/cloudflare` está em dependencies sem uso em runtime | `api/src/worker.js:8` tem `import * as Sentry from "@sentry/cloudflare"` e o arquivo menciona Sentry 26 vezes. O import é real e o bundler precisa dele desde SENTRY1 |
| `VARREDURA_CRON_AI_ENABLED` sem default seguro | `api/src/worker.js:12301` lê `String(env2222 && env2222.VARREDURA_CRON_AI_ENABLED \|\| "false")`. Ausente cai em `"false"`, que é o lado fechado |
| Não há evidência de `.gitignore` cobrindo os bundles | `.gitignore:76-95` documenta a política com racional e lista nominalmente os 32 bundles antigos que ficam só no disco. A ausência deles no `git status` é o efeito da regra, não falta de regra |
| Botões não semânticos em `app/index.html:5875-5882` | A linha 5875 é `bf.innerHTML` de um card de briefing, não um botão. Citação errada, achado descartado |
| `admin_senha` exposto como input de workflow sem máscara | `.github/workflows/frescor-check.yml:38` faz `echo "::add-mask::$admin_pwd"`, o input é opcional e vazio cai no secret. Risco residual mínimo, não virou achado |
| 165 bundles ocupando 96 MB | Ambos os números estavam parcialmente certos. 165 é o total no disco e 133 é o total versionado, 117 MB no git e 129 MB no disco. Corrigido em CFG-05 |
| Drift entre `README.md:28` e a versão publicada | Refutado. `README.md:28`, `app/index.html`, `app/version.json` e `app/deploy_zip/version.json` estão todos em `v202.43`. O drift de versão existe, e é o do Worker (`README.md:24` e `:84`), já em CFG-04 |

**Fechado depois desta rodada.** A contagem de testes estava certa nos dois lados. São 43 arquivos `.mjs` em `api/test` no total e 39 `*.test.mjs`, com 4 helpers de prefixo `_` e 13 arquivos em `fixtures/`, medido com `ls -1`. E a superfície de `innerHTML` foi fechada na passada dedicada de frontend, o resultado está na linha FE-05.

**Correção de contagem no log de observações.** Esta sessão escreveu seis entradas, numeradas de 44 a 49. O log tem 48 entradas no total, numeradas de 1 a 49, porque o número 12 está ausente da sequência. Medido com `grep -c '^### Observation [0-9]*:'` = 48 e maior número = 49.

---

## Apêndice. Itens da fila do vault cruzados nesta rodada

Não remedidos aqui. Ficam listados para o leitor não confundir ausência de medição com inexistência do problema.

| Item | Situação registrada | Observação desta auditoria |
|---|---|---|
| SCANFALLBACK-MORTO1 | Aberto até execução real com `prosseguir=true` e `Processados: 19/19` | Contrato já corrigido no código, prova continua dependendo de execução real |
| VERIFHORARIO1 | Aberto, falta decisão do operador | `CLAUDE.md` diz 11h03 e 19h15, `routines/README.md` diz 11h00 e 18h45 |
| ROUTINEKEY-PLAIN1 | Aberto, rotação não feita | Correlaciona com SEC-04 |
| CCDOFFLINE1 | Aberto, ação de 1 toggle do operador | Fora do alcance de agente por regra |
| PISODIFF1 | Aberto, solução estrutural não implementada | Depende de fonte estruturada de severidade da RJ |
| CURADORIA1 | Aberto, contagem 396 medida em 11/09 | Nada novo medido aqui |
| QUARENTENACOB1 | Aberto, código não validado por runner | Correlaciona com TST-01 |
| DRIVERMORTO1 | Sem fechamento desde 11/09 | Nada novo medido aqui |
| TOKENCHAT1 | Aberto, ação do operador | Relacionado a Pages:Edit |
| frescor-check reprovando | 3 de 8 runs recentes pela régua de dias úteis | Depende de decisão de produto |

---

## Comparação com a auditoria anterior (`TECH_DEBT_AUDIT.md`, 2026-06-16, bundle v4.9.111)

Os 23 achados de junho foram remedidos por leitura agora, um a um.

| ID junho | Assunto | Situação medida em 18/09/2026 |
|---|---|---|
| F001 | `__coreFetch` com 1.139 linhas | **Piorou.** Hoje tem 2.033 linhas em `api/src/worker.js:19986-22018`. Virou ARQ-01 |
| F002 | 43 `catch {}` vazios | **Resolvido.** `rg -c 'catch\s*\{\s*\}'` no `worker.js` devolve 4, e o SENTRY1 cobriu a captura de exceção |
| F003 | `ADMIN_EMAIL` hardcoded no Worker | **Resolvido no Worker, reencarnou no frontend.** `env.ADMIN_EMAIL` em uso, e o endereço pessoal segue no HTML público. Virou FE-01 |
| F004 | `JWT_SECRET \|\| "radar"` | **Resolvido.** `:4678`, `:4694`, `:4716` e `:4732` leem `env2222.JWT_SECRET` direto, sem fallback, e o health expõe `checks.jwt_secret` em `:19815` |
| F005 | `Math.random()` em `gerarMessageId` | **Resolvido.** Sobraram só o jitter de espera em `:4646`, 80 a 200 ms, e o sorteio de amostragem em `:13872`, ambos adequados |
| F006 | `[observability]` ausente | **Resolvido.** `api/wrangler.toml:1508-1509` com `enabled = true` |
| F015 | `compatibility_date` velho | **Resolvido quanto ao valor, e voltou a envelhecer.** Está `2026-06-16` em `api/wrangler.toml:1413`, três meses atrás. Mudar data de compatibilidade altera comportamento, então congelar é defensável, e a decisão não está escrita em lugar nenhum |
| F019 | Zero testes automatizados | **Parcialmente resolvido.** 39 arquivos `*.test.mjs` em `api/test/`, e o CI roda em push que toque `api/**`. Os buracos que restam estão em TST-01 |
| F020 | Bundles antigos ocupando o repo | **Piorou.** A nota de junho descrevia a faixa `v4.9.67` a `v4.9.111`, e hoje são 133 arquivos versionados somando 117 MB, com 165 no disco somando 129 MB. Virou CFG-05 |
| F022 | Formulário admin com `method="get"` | **Resolvido.** Nenhuma ocorrência de `<form ... method=get` no `worker.js` |
| F023 | `__name` duplicado por polyfill do unenv | **Segue valendo como não-débito**, pelo mesmo motivo de junho |

Nenhum achado de junho foi reaberto como novidade. O que a comparação mostra é assimétrico, e vale registrar. O que a auditoria de junho marcou como correção pontual foi corrigido e verificado, de F002 a F022. O que ela marcou como refatoração estrutural, F001 e F020, não só não foi feito como piorou de tamanho, e nesses dois o repo cresceu no sentido oposto ao da recomendação.

---

## Evidência crua

Commit auditado `3c15fa8`, `git status --short` com 0 linhas.

Portão de verificação em 18/09/2026 19:52 UTC:

```
{"ok":true,"fonte_externa_ok":true,"versao":"v4.9.257","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},
"providers_configurados":"2/2","admin_email_ok":true,"sentry_ok":true,"verificador_ok":true,"verif_orfaos_ativos":0,
"cvm_atribuicao_por_cnpj":760,"cvm_atribuicao_por_nome":736,"cvm_atribuicao_quarentena":9811,
"cvm_atribuicao_cobertura_pct":13.2,"feed_fresco":true,"feed_idade_du":0,"painel_fresco":true,"painel_idade_min":23}
HTTP:200 TEMPO:3.104007s
```

Ferramenta de deploy:

```
$ grep -c wrangler api/package.json
0
$ npm ls wrangler
api@ E:\Diretorio\Claude\Monitoramento de Credito\api
├─┬ @cloudflare/vitest-pool-workers@0.20.1
│ └── wrangler@4.118.0
└─┬ @sentry/cloudflare@10.69.0
  └── wrangler@4.118.0 deduped
```

Frontend sincronizado, medido por hash:

```
$ sha256sum app/index.html app/deploy_zip/index.html
a85427c5a572a0e9a51e165cf39711f3e341e29675d2276fb8965f63b21255ed *app/index.html
a85427c5a572a0e9a51e165cf39711f3e341e29675d2276fb8965f63b21255ed *app/deploy_zip/index.html
$ diff -q app/index.html app/deploy_zip/index.html   # exit=0
```

Artefato versionado:

```
$ git ls-files 'api/v4*.js' | wc -l
133
$ du -ch api/v4*.js | tail -1
129M    total
```

Churn de seis meses, os cinco maiores: `api/wrangler.toml` 193, `README.md` 134, `Obsidian VIX Radar/PENDENCIAS.md` 104, `app/deploy_zip/version.json` 99, `status/ESTADO.md` 98.

Marcações de trabalho pendente em código vivo: nenhuma. A única ocorrência é `api/tools/README_IMPORTAR_SERIE.md:49`, `TODO: validar contra arquivo real da B3`.

Providers do pool de credencial no momento da auditoria: `deepseek` e `nous` em `ok`, e `openrouter`, `anthropic`, `minimax`, `xai`, `opencode-go` e três contas `openai-codex` em `exhausted`. Foi o que derrubou quatro dos seis escopos desta varredura.
