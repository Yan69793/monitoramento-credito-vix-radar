# Arquitetura VIX Radar

Retrato do sistema em 26/08/2026. Worker de produção `v4.9.221`, frontend `v202.33`.
Todo número aqui foi medido em comando rodado ou lido direto do arquivo citado.

## 1. O que o sistema faz

Monitoramento de risco de crédito privado de 103 emissores brasileiros. O sistema
ingere documentos regulatórios da CVM, cotações e imprensa, roda análise por LLM
sobre cada emissor, calcula um score de alerta antecipado (EWS), verifica a análise
contra fonte externa antes de publicar, e serve o resultado num painel web com
alerta por e-mail. A lista canônica de emissores é uma constante no próprio Worker,
`EMISSORES_LISTA` em `api/src/worker.js:3798-3913`, 103 entradas.

## 2. Topologia

O sistema tem três planos, e o segundo é o que ninguém descobre lendo o repositório.

| Plano | Onde roda | O que faz |
|---|---|---|
| Borda | Cloudflare | Worker `radar-credito-api` em `api.vixradar.com`, Pages `radar-credito` em `vixradar.com`, KV, 5 Durable Objects, Analytics Engine |
| Cérebro | Máquina Windows do operador | Sessões agendadas do Claude Desktop e Windows Task Scheduler disparando o Claude CLI, que faz a análise pesada e devolve por POST |
| Fontes | Externo | CVM (bulk IPE), ANBIMA, provedores de cotação, API Anthropic, Resend, Sentry |

A inferência cara não roda na nuvem. Roda local, na assinatura do operador, e o
acoplamento entre os dois lados é um POST JSON autenticado por chave compartilhada.
Se a máquina local para, o painel continua servindo dado velho sem erro nenhum.

## 3. Backend

`api/src/worker.js`, arquivo único de 19.858 linhas e 1,02 MB. É um monolito
deliberado, sem framework, com bundling pelo esbuild do Wrangler.

**Roteamento.** Misto. Três rotas por path (`/resend_webhook`, `/admin/promote`,
`/s/{slug}`). Todo o resto entra por `__coreFetch` e despacha por parâmetro. GET usa
querystring `op=` com 17 valores válidos declarados em `_OPS_VALIDAS`, mais um
punhado de `action=`. POST usa `body.action`, com 94 ramos. As famílias são
auth e reset, admin de usuários, CVM, e-mail e newsletter, mercado e anomalias,
telemetria de UI, contrato de rotina, calendário, share e favoritos.

**Autenticação.** Três regimes coexistem no mesmo endpoint.

- JWT HS256 assinado com `JWT_SECRET` via WebCrypto, TTL de 12 horas, lido apenas do
  header `Authorization: Bearer` desde que o cookie foi removido. Senha de usuário em
  PBKDF2 com 100 mil iterações e SHA-256.
- Senha de administrador comparada contra `env.ADMIN_PASSWORD` em texto claro, em
  cerca de 52 handlers.
- Chave de rotina, `body.routine_key` conferida contra `ROUTINE_API_KEY`. Existe uma
  segunda chave, `REMOTE_VERIFICACAO_KEY`, com escopo restrito às três actions de
  verificação. Ela viaja no corpo JSON, não em header, ao contrário do que a
  documentação interna afirmava.

**Rate limiting.** `RateLimiterDO` guarda a janela de timestamps no storage SQLite do
Durable Object e aplica três camadas. Anônimo em 3 por minuto, 10 por meia hora e 30
por dia. Tenant `vix_core` em 5, 25 e 150. Tenant `mirabaud` em 10, 50 e 300. Leitura
e auth falham abertas, operação crítica falha fechada. Requisição com senha admin
correta pula o check inteiro, senha errada entra no throttle como crítica.

**Durable Objects.** Cinco classes, todas SQLite. `RateLimiterDO` (migration v1),
`EstadoSemanaDO` (v2), e `EmissorDO`, `UsuarioDO` e `ConfigDO` (v3). `EstadoSemanaDO`
serializa gravação por encadeamento de promises, correção do incidente de race
condition. As três de v3 fazem parte de uma migração KV para DO ainda em andamento.

**Dados.** Um namespace KV, `RADAR_KV`, id `c6805b8d8a7b468e9f854ab4f91fb93a`. O
estado vive em `radar:estado:{semanaISO}` com TTL de 35 dias, um blob por semana
carregando os 103 emissores. Leitura usa `carregarEstadoMultiSemana`, com a janela
escolhida por call site, 2, 3 ou 5 semanas, e 5 predominando nos 23 pontos de
chamada. Mescla da mais velha para a mais nova com dedup semântico de evento.
Escrita sempre na semana corrente. Outros prefixos relevantes são
`cvm:documentos` (30 dias), `radar:verif:{hash}` (30 dias), `radar:custo:{data}` (90
dias), `email_envio:{email}:{ts}` e `bounce:{email}:{ts}` (90 dias), `user:{email}`,
`heartbeat:{agente}` (7 dias).

**Crons do Worker.** Quatro. `30 15 * * *` matinal, `30 21 * * *` noturno,
`0 1 * * *` watchdog de heartbeat de 6 agentes, `0 4 * * *` build da agenda. Matinal e
noturno fazem sync CVM, recálculo de anomalias, sync ANBIMA e pipeline preditivo. O
noturno ainda dispara newsletter, relatório diário e health check.

## 4. Frontend

Uma página, `app/index.html`, com 6.975 linhas e 719 KB. Dentro dela, 178 KB de CSS
inline e 485 KB de JavaScript inline. Não há bundler, não há build step, não há suíte
de teste. É HTML servido direto pelo Pages.

Fora do arquivo existem 8 módulos ES em `app/js`, carregados por um único
`<script type="module">` apontando para `admin-bootstrap.js`. Eles cobrem só o painel
administrativo, entre roteador por hash das abas, wrapper de fetch com retry e
backoff, e as telas de engajamento e métricas. Existe uma cópia legada em IIFE em
`app/admin/` que ninguém carrega.

Versionamento por `CACHE_VERSION`, hoje `v202.33`. O valor aparece em 15 pontos dentro
de `app/js` como querystring dos imports, e `app/_headers` força `no-cache` para
`app/js/*` porque import relativo não herda o sufixo de versão.

A navegação principal alterna `display` de seções, não usa rota. Só o admin tem
roteador por hash. O JWT fica em `localStorage` sob a chave `radar_jwt` e é injetado
por um monkey-patch global de `window.fetch` que carimba o header em qualquer chamada
para o domínio da API. A senha admin fica em `sessionStorage`.

Timer autônomo de rede foi removido do app principal por decisão explícita. Sobrou um
disparo único 30 segundos após o load, checando `version.json`, e um `setInterval` de
5 minutos dentro do módulo de engajamento do admin, que ainda chama a rede sozinho.

Design system com dourado `#B7985D` sobre navy `#001020`, tipografia em DM Sans,
Cormorant Garamond e Inter carregadas do Google Fonts. Não há Content-Security-Policy,
consequência do JavaScript inline. Os `<script>` carregam um `nonce` fixo que, sem CSP,
não faz nada.

## 5. Camada de IA

O cascade multi-provedor não existe mais. Hoje é Anthropic puro. Gemini e OpenRouter
foram removidos do código, Perplexity sobrou como caminho legado que só ativa se a
chave estiver presente. O health reporta `providers_configurados: 2/2`, e os dois são
Resend e Anthropic.

Análise no Worker usa `claude-haiku-4-5-20251001` com a ferramenta de busca web,
teto de 4 mil tokens de saída, timeout de 55 segundos e duas tentativas. O verificador
adversarial começa em Haiku e escala para `claude-sonnet-4-6` quando a confiança fica
abaixo de 0,7.

A varredura pesada é local. A noturna cobre os 103 emissores em duas filas, rápida em
lotes de até 15 e aprofundada em lotes de até 16, com orçamento modelado como
`130.000 x lotes + 5.000 x emissores`, alvo de 500 mil tokens e teto de decisão em 700
mil. A matinal cobre o top 15 por EWS, Sonnet em grupos de 4 para EWS maior ou igual a
38 e Haiku em grupos de 6, alvo de 120 mil e teto de 180 mil. O que não couber no
orçamento é diferido e submetido depois. O Claude CLI é chamado com
`--permission-mode bypassPermissions` e retry com backoff.

O contrato entre os dois lados são cinco actions. `listar_todos_emissores`,
`listar_emissores_prioritarios`, `listar_plano_rotina`, `dados_para_analise` e
`receber_analise`. Análise aceita passa por sanitização, validação do nome contra
`EMISSORES_LISTA` e pode cair numa fila de verificação assíncrona antes de virar fato
publicado.

## 6. Ingestão CVM

O gatilho primário de evento é o ZIP bulk de comunicados IPE da CVM, baixado nos dois
crons diários, validado por assinatura `PK`, descompactado dentro do Worker com
`DecompressionStream` e gravado em `cvm:documentos`.

A atribuição de documento a emissor foi reescrita para usar CNPJ como chave primária.
Documento com CNPJ declarado na tabela de famílias é atribuído direto. CNPJ presente
mas não declarado vai para quarentena, fail-closed por decisão do operador. Só quando
o CNPJ está ausente cai o árbitro por nome, que usa âncora de início de palavra e
termo mais longo como desempate.

Medido em produção hoje, 793 documentos atribuídos por CNPJ, zero por nome, 1.333 em
quarentena, cobertura de 37,3%.

## 7. Observabilidade

Sentry embrulha o Worker inteiro com `Sentry.withSentry`, amostragem de traces em 10%
e coleta de PII desligada em todos os eixos, incluindo corpo de requisição, headers,
cookies e entrada e saída de LLM. Analytics Engine grava no dataset
`radar_usage_events`, indexado por e-mail, com evento, empresa, rota, categoria de
user agent, hash de IP, tempo de resposta e status.

O health em `GET /` agrega bindings, secrets críticos, verificador e degradação da
fonte CVM. O campo `ok` mede a plataforma, o frescor da fonte externa vive em
`fonte_externa_ok` e não reprova o portão, porque a CVM publica em cadência semanal.

Seis workflows no GitHub Actions fecham o cerco. Health canônico a cada 6 horas com
checagem de drift entre repositório e produção, e-mail de status diário, checagem de
frescor, varredura de emergência quando o estado fica stale, guarda semanal do
cadastro de emissores contra o arquivo da CVM, e a suíte `vitest` em push que toque
`api/**`.

## 8. Dívida técnica e risco aberto

Isto é o que um especialista precisa saber antes de opinar.

**Monolito.** 19.858 linhas num arquivo, com o changelog do projeto morando em 900
linhas de comentário no `wrangler.toml`. Funciona e é testável, mas o custo de
navegação é alto e o raio de explosão de qualquer mudança é o sistema inteiro.

**Senha admin em texto claro.** A comparação é igualdade simples de string contra a
variável de ambiente, sem hash e sem tempo constante. O bypass de rate limit depende
dessa mesma comparação.

**CSP ausente.** Consequência do inline de 474 KB de JS. O `nonce` presente nos scripts
dá aparência de proteção sem entregar nenhuma.

**Migração KV para DO possivelmente parada.** Escrita é dual e leitura cai de volta
para o KV em silêncio quando o DO falha. Não existe métrica pública dizendo qual
fração das leituras veio do DO. O sistema não quebra, e é exatamente por isso que a
migração pode estar congelada sem sinal.

**Estado semanal como blob único.** Os 103 emissores numa chave só. Cresce por
construção e serializa gravação concorrente por fila em Durable Object.

**Chave de rotina exposta e não rotacionada.** Foi encontrada em texto puro em
arquivos de skill em 07/08, redigida nos arquivos vivos, mas preservada em backups e
transcripts append-only. A rotação segue pendente por decisão do operador.

**Cobertura de atribuição CVM em 37,3%.** A quarentena fail-closed protege contra
atribuir documento ao emissor errado, o que já aconteceu, mas 1.333 documentos estão
parados nela.

**Testes não rodam local.** O fluxo de deploy instala com `--omit=dev`, então `vitest`
não existe na máquina. A validação real acontece no CI.

**Documentação interna com dois pontos desatualizados**, ambos corrigidos aqui. O
cascade não é mais multi-provedor, e a chave de rotina não viaja em header.

## 9. Onde olhar primeiro

| Pergunta | Arquivo |
|---|---|
| Como o backend decide qualquer coisa | `api/src/worker.js`, função `__coreFetch` |
| Bindings, migrations, crons, changelog | `api/wrangler.toml` |
| Como o frontend fala com a API | `app/index.html` (patch de `window.fetch`) e `app/js/api.js` |
| Como a análise é gerada e o que ela custa | `routines/claude-desktop/*/SKILL.md` e `scripts/run_vixradar_*.ps1` |
| O que quebrou antes e como foi fechado | tabela de incidentes no `CLAUDE.md` do repositório |
