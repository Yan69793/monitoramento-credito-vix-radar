# Protocolo Operacional — VIX Radar (hardened 2026-07-25)

## Estado do projeto

Página canônica de estado, legível por qualquer agente (não só Claude): `status/ESTADO.md`. Ler antes de começar sessão de trabalho, atualizar a data e os itens ao fechar uma sessão que mudou o estado.

## Pendências abertas

Esta seção existe como **ponteiro**, não como lista. A fila real vive em dois
arquivos e duplicar aqui só criaria uma terceira versão para divergir. Ela foi
criada em 19/08/2026 porque a varredura de workspace (`scan-pendencias.ps1`, da
skill `resolver-pendencias`) procura exatamente por este cabeçalho, e sem ele o
VIX Radar saía invisível do raio-x de pendências dos 20 projetos, mesmo tendo
itens abertos.

1. **Fila detalhada, com causa raiz e prova** — `Obsidian VIX Radar/PENDENCIAS.md`. É o canônico desde 2026-07-27, ordenado por data, cada item fecha com correção, causa raiz e guarda sistêmica.
2. **Resumo do estado e itens abertos em uma tela** — `status/ESTADO.md`, seção `## Itens abertos`. É o que ler primeiro ao começar sessão.
3. **Decisões pendentes do operador, não do agente** — rotação da `routine_key` (incidente ROUTINEKEY-PLAIN1, detalhado abaixo neste arquivo) e migração KV→DO, que segue com o KV como fonte da verdade e fallback silencioso de leitura.

Ao fechar um item, atualizar os dois primeiros. Não trazer a lista para cá.

## Comunicação

- Toda resposta neste projeto aplica a skill `/humanizer` antes de ser entregue.
- Sem linguagem de programador no texto explicativo. Traduzir para o que aquilo significa na prática, nunca usar termo técnico como enfeite.
- Resposta sempre bem resumida, direto ao ponto.
- Isso não se aplica a evidência técnica exigida em outra regra deste arquivo (por exemplo a saída colada no `Portão de verificação`, comando, caminho de arquivo, valor numérico). Essas ficam literais. A regra acima é sobre a prosa ao redor, não sobre apagar prova.

## Memória canônica

Vault Obsidian: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\`
Começar por `00 - Índice (MOC).md` e `03 - Estado Atual.md`.
Se conflito chat vs Obsidian: Obsidian prevalece.
Nunca deixar informação crítica só no chat — gravar no Obsidian ao final.

Repo: `monitoramento-credito-vix-radar.git` (branch `main`).
Remote: `https://github.com/Yan69793/monitoramento-credito-vix-radar`.

## Arquitetura híbrida (isto não está em arquivo nenhum, absorver)

O backend está no Cloudflare (Worker + KV + DO + Analytics Engine), mas o cérebro de
IA roda na máquina Windows local do operador. As rotinas de varredura, verificação e
análise são scripts PowerShell disparados pelo Windows Task Scheduler, que chamam o
Claude CLI localmente e enviam o resultado para o Worker por POST autenticado com
`routine_key`.

Isso significa que este repositório tem dois lados que sessão nenhuma descobre sozinha:

1. **Lado Cloudflare** — `api/` e `app/`, deploy via scripts, bindings em `wrangler.toml`
2. **Lado Task Scheduler** — scripts em `scripts/` e `routines/`, agendamento documentado em `routines/README.md`

Os dois lados se comunicam pelo contrato de rotina (POST para `https://api.vixradar.com`
com header `X-Routine-Key`). Se um lado quebrar, o sistema para.

### Diretórios fora do fluxo operacional

`producao/`, `_historico/`, `archive/`, `vixradar/`, `research/` não fazem parte do
sistema vivo. `producao/` em especial contém uma versão estática e desconectada
(v30/v40) do frontend, sem JWT, KV, DO, Analytics Engine ou cascade de IA. Deployar
esse diretório regrediria produção de v4.9.x para v30 (ver `producao/ATENCAO-NAO-DEPLOYAR.md`).
As fontes vivas são só `api/` e `app/`.

## Domínios

| Domínio | O que serve | Projeto Cloudflare |
|---|---|---|
| `vixradar.com` | Frontend (Landing + Admin) | Pages `radar-credito` |
| `api.vixradar.com` | API Worker | Worker `radar-credito-api` |

## Deploy

### Worker
```
pwsh ./scripts/deploy-worker.ps1 -Version v4.9.XXX
```
Nunca `wrangler deploy` direto. O script faz 6 passos atômicos: build do src,
aponta `wrangler.toml main`, `npm ci` em `api/`, deploy com `--no-autoconfig`, valida
GET / em produção, e só então git add/commit/push. Token Cloudflare é variável de
ambiente do sistema.

Antes de tudo isso rodam três portões que abortam sem tocar em nada: versão de
produção não pode estar à frente do repo, working tree tem que estar limpo nos 4
arquivos trackeados que o deploy altera (`api/src/worker.js`, `api/wrangler.toml`,
`scripts/build-worker.ps1`, `scripts/deploy-worker.ps1`; sujeira fora desses quatro
não trava o gate), e o secret `SENTRY_DSN` tem que existir no Worker. O terceiro
existe porque `sentry_ok`
entrou no `_okHealth` — sem o secret, o deploy subiria e a validação falharia
depois, deixando produção nova e repo declarando a versão velha.

### Pages
```
pwsh ./scripts/deploy-pages.ps1
```
Sincroniza `app/index.html` → `app/deploy_zip/`, regenera `version.json`, confere
os 4 arquivos do bundle, deploy, valida em produção.

### Regras invioláveis de deploy
- Wrangler 4.x: sempre `--no-autoconfig`. Sem isso detecta `E:\Diretorio\Claude\dashboard` como projeto e ignora `wrangler.toml`.
- Fonte do Worker: `api/src/worker.js` (cerca de 18,6k linhas em agosto de 2026). Bundles `api/v4.*.js` são artefatos gerados, nunca editar diretamente.
- **Nunca ligar `no_bundle = true` nem passar `--no-bundle`.** Esta linha já mandou o contrário e estava errada: `no_bundle` nunca foi configurado, o esbuild do Wrangler sempre esteve ativo. Desde SENTRY1 (v4.9.184) o bundle tem import real de npm (`@sentry/cloudflare`) que só resolve com o bundler ligado. Desligar quebra o deploy seguinte.
- `api/package.json` e `api/package-lock.json` são versionados e `deploy-worker.ps1` roda `npm ci` antes do deploy. Sem `node_modules`, o import não resolve.
- Fonte do frontend: `app/index.html` (CACHE_VERSION no header). Sincronizar `app/deploy_zip/` antes do deploy.
- Git commit só depois de deploy validado em produção (anti-drift).
- `CLOUDFLARE_API_TOKEN` é variável de ambiente do sistema, nunca no repo.

### Bindings obrigatórios
`RADAR_KV` (KV `c6805b8d8a7b468e9f854ab4f91fb93a`), `RATE_LIMITER_DO` (RateLimiterDO),
`ESTADO_SEMANA_DO` (EstadoSemanaDO, SQLite com migration v2), `RADAR_USAGE_EVENTS`
(Analytics Engine). Não remover bindings.

### Secrets que derrubam o health se sumirem
`RESEND_API_KEY`, `ADMIN_EMAIL` (SECRETMISS1) e `SENTRY_DSN` (SENTRY1) entram no
`_okHealth`. Os dois últimos são validados por formato, não só por presença: string
vazia ou valor truncado também derruba. Some um deles, o health vai a `ok:false`,
o `canonical-test` fica vermelho em até 6h e o dono recebe email. Foi assim que o
`ADMIN_EMAIL` ficou 3 dias ausente com o painel verde.

## Migração KV→DO (v5, em andamento, KV ainda é fonte da verdade)

Três Durable Objects novos substituem progressivamente chaves KV por domínio.
A migração é incremental: os DOs já existem em produção, as classes estão no
bundle, e os call sites usam dual-write (escreve no DO e no KV, console.warn
se o DO falhar) e read-fallback (tenta DO primeiro, cai para KV se falhar).
Hoje o KV ainda é a fonte da verdade porque o fallback de leitura é
automático e silencioso.

| DO | Instância | Dados |
|---|---|---|
| `EMISSOR_DO` | 1 por emissor (`idFromName`) | Séries, flags, `ews_hist`, features, alertas, comentários |
| `USUARIO_DO` | 1 por usuário (`idFromName`) | Perfil, favoritos, análises privadas (dados LGPD isolados) |
| `CONFIG_DO` | Singleton (`_global`) | Calendário, providers, tenant, anomalias, eventos (baixa concorrência) |

Padrão de roteamento: `_rotearParaEmissorDO(env, empresa, op, args)`,
`_rotearParaUsuarioDO`, `_rotearParaConfigDO`, análogo ao
`_rotearParaEstadoSemanaDO` que já existe. FIFO promise chain (RACEKV1 fix)
em todos. Migração v3 no bloco `[[migrations]]` com `tag = "v3"` e
`new_sqlite_classes = ["EmissorDO", "UsuarioDO", "ConfigDO"]` em `api/wrangler.toml`.

Fail-open controlado: se o DO falha na escrita, o KV é atualizado normalmente
e o `console.warn` registra o evento. Se o DO falha na leitura, o valor do KV
é retornado sem erro para o chamador. Isso significa que um DO quebrado não
derruba o sistema, mas também significa que a migração pode não estar
progredindo e ninguém vê.

Para auditar: conferir `wrangler secret list` (os DOs não precisam de secrets),
checar os 3 bindings no health indireto (não há campo público `emissor_do_ok`
ainda), e inspecionar `console.warn` nos logs do Worker atrás de `[DO][dual-write]`
ou `[DO][read]` que indicam DO inalcançável repetido.

## Testes

```
cd api && npm install && npm test
```
Roda `vitest run` contra `@cloudflare/vitest-pool-workers`, que sobe o Worker de
verdade (`api/src/worker.js`) num runtime workerd local via Miniflare, usando
`api/wrangler.test.jsonc` (config isolada, sem account_id nem bindings reais, nunca
toca produção). Um teste isolado: `npx vitest run test/health.test.mjs`.

`test/health.test.mjs` automatiza o `Portão de verificação` abaixo (ok/kv/telemetria/
admin_email_ok/sentry_ok/verificador_ok). `test/rate-limit.test.mjs` cobre o `RATE_LIMITER_DO`.

**Não roda local nesta máquina com o `node_modules` do fluxo de deploy.** O
`deploy-worker.ps1` roda `npm ci --omit=dev`, então `vitest` não existe e o `npm test`
falha com "'vitest' não é reconhecido como um comando interno ou externo". Para rodar
local, instalar as devDeps com `npm ci` dentro de `api/`. A causa antiga (Smart App
Control bloqueando `workerd.exe`, Event Log CodeIntegrity id 3077/3033) foi refutada
em 20/08/2026: `VerifiedAndReputablePolicyState=0` (SAC desligado) e nenhum evento
CodeIntegrity menciona `workerd`. O caminho comprovado de teste segue sendo o CI
(`worker-tests.yml`, dispara em push/PR que toque `api/**`).
Sem lint configurado no repo, não inventar um.

`app/` (frontend) não tem `package.json`, build step nem suíte de teste, é HTML/CSS/JS
servido direto, validado manualmente ou pelo `Portão de verificação`.

## Rotinas agendadas (fonte da verdade: `routines/README.md`)

Estes scripts PowerShell chamam o Claude CLI localmente. Todos usam `routine_key` para
autenticar contra o Worker. A chave nunca está versionada.

**O agendamento está dividido em dois mecanismos, e confundi-los causa execução
dupla.** As três primeiras rodam por sessão agendada do Claude Desktop e têm a
task homônima do Windows Task Scheduler mantida `Disabled` de propósito, como
guarda anti-duplicata verificada pelo próprio script (`GUARD_OK` no log). Nunca
reabilitar essas três. O `LastTaskResult` delas está congelado desde 06/08/2026 e
não indica saúde, quem indica é a linha `FIM:` no log em `logs/routines/`.

| Tarefa | Mecanismo | Frequência | Script | Escopo |
|---|---|---|---|---|
| `VIXRadar-Matinal` | Claude Desktop, task `Disabled` | Seg-Sex 10h00 BRT | `run_vixradar_matinal_claude.ps1` | Top 15 por EWS |
| `VIXRadar-Noturno` | Claude Desktop, task `Disabled` | Diário 18h00 BRT | `run_vixradar_noturno_claude.ps1` | 103 emissores |
| `VIXRadar-Verificacao-Async` | Claude Desktop, task `Disabled` | Diário 10h20 BRT | `run_vixradar_verificacao_async.ps1` | Fila `radar:verif_fila:{data}` |
| `VIXRadar-AgendaSemanal` | Task Scheduler | Dom 22h00 BRT | `run_vixradar_agenda_semanal.ps1` | Calendário trimestral, top 20 stale |
| `VIXRadar-Coleta-Volatilidade` | Task Scheduler | Diário 17h00 BRT | — | Cotações + volatilidade no KV |
| `VIXRadar-Export-Historico` | Task Scheduler | Diário 20h45 BRT | — | Exporta estado |
| `VIXRadar-Reconciliacao-CVM` | Task Scheduler | Seg 08h00 BRT | — | Reconcilia IPE CVM vs estado |
| `VIXRadar-Health-Watch` | Task Scheduler | Seg-Sex 08h-20h, 15/15min | — | Vigia de health, alerta e-mail |
| `VIXRadar-Ranking-Mensal` | **OBSOLETO** (task não existe) | — | — | SEO mensal, descontinuada 18/08/2026, ver `routines/README.md` |

Duas Claude Code Routines remotas (nuvem, fora do Task Scheduler) também existem:
verificação async (02h/14h BRT) e frescor diário (23h BRT). Detalhe e trigger IDs em
`routines/README.md`.

A matinal usa Haiku em lotes de 6 + Sonnet para EWS≥38 em lotes de 4.
A noturna varre os 103 emissores: Haiku lotes de 15 + Sonnet lotes de 11.
Disjuntores de custo LLM barram matinal/noturno se estouro; watchdog e agenda rodam sempre.

Scripts de suporte relevantes: `monitor-tasks.ps1`, `verify-rotinas-v2.ps1`,
`dry-run-rotinas-v2.ps1`, `replay-criticos.ps1`, `replay-falhas.ps1`,
`register-all-routines-scheduler.ps1`, `collect_cotacoes.ps1`,
`upload_volatilidade_kv.ps1`, `check-drift.ps1`, `check-vault-drift.ps1`,
`lint-encoding.ps1`, `install-hooks.ps1`.

## PowerShell 5.1 — regras de compatibilidade

Os scripts do Task Scheduler rodam no `powershell.exe` 5.1. Isto quebra se não for
respeitado (o pre-commit hook reprova, e com razão):

- Arquivo `.ps1` com caractere não-ASCII precisa de BOM UTF-8 (`EF BB BF`) no primeiro byte. Sem BOM, PowerShell 5.1 interpreta como ANSI e corrompe acentos.
- Nunca usar operadores do PowerShell 7+: sem ternário (`$a ? $b : $c`), sem null-coalescing (`??`), sem null-conditional (`?.`).
- `$ErrorActionPreference = 'Continue'`, nunca `'Stop'` (senão o Task Scheduler engole o erro e morre silencioso).
- Variáveis de ambiente: `$env:VAR`, nunca `export`.

O hook `scripts/hooks/pre-commit` linta o blob em staging com `git cat-file`, não o
working tree. Instalar com `scripts/install-hooks.ps1`. Emergência: `git commit --no-verify`.

## Cascade de IA

Provedores configurados no Worker: Claude Haiku 4.5 (manual Pulso), Haiku + Sonnet 4.6
(lotes nas rotinas), Gemini (fallback), Perplexity (busca). OpenRouter saiu do cascade
no v4.9.108. Chaves de API em secrets do Cloudflare, nunca no repo.

A máquina local usa o Claude CLI (conta Szuchmacher) para análise e verificação.
O contrato de rotina expõe: `listar_todos_emissores`, `listar_emissores_prioritarios`,
`listar_plano_rotina`, `dados_para_analise`, `receber_analise`.

## Multi-semana

Endpoints `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor`, `comparar`
usam `carregarEstadoMultiSemana(env, 5)`. Escrita na semana corrente. Cuidado com
`EstadoSemanaDO`: usa FIFO promise chain com fail-open (fix RACEKV1), não assumir
atomicidade de gravação sem conferir.

## Cron Triggers (Worker)

| Horário UTC | Horário BRT | Função |
|---|---|---|
| 15:30 | 12:30 | Matinal |
| 21:30 | 18:30 | Noturno |
| 01:00 | 22:00 | Watchdog (heartbeats de 6 agentes) |
| 04:00 | 01:00 | Agenda build |

Watchdog monitora staleness de 6 heartbeats: `sync_cvm`, `varredura_batch`,
`varredura_matinal`, `newsletter`, `healthcheck_diario`, `cascade_analise`.
Roda mesmo com disjuntor de custo ativo.

## GitHub Actions

- `canonical-test.yml`: health check GET / a cada 6h (valida ok, kv, rate_limiter, telemetria, providers). Gate usa o campo `ok` agregado, então cai se `verificador_ok`, `sentry_ok` ou `admin_email_ok` ficarem `false`, mesmo com `kv`/`telemetria` saudáveis
- `daily-status-email.yml`: status diário via Issue + email Resend (não depende de MCP/OAuth)
- `frescor-check.yml`: diário 01:37 UTC, staleness da ingestão
- `scan-emergencia.yml`: fallback 23:30 UTC quando estado principal stale
- `worker-tests.yml`: suíte `vitest` em push/PR que toque `api/**`, ver `## Testes`

## Portão de verificação

Antes de declarar qualquer tarefa concluída, execute:
```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```
Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`.
Cole a saída real na resposta. Se falhar ou não puder executar, diga explicitamente.
Nunca declare "funcionando" sem a saída colada.

**`ok` mede o serviço, não a fonte (HEALTHSPLIT1, v4.9.204, 20/08/2026).** Entre
19 e 20/08 o `ok` também carregava o frescor da fonte da CVM, e isso apagava o
único sinal acionável que ele tinha. `ok:false` voltou a significar plataforma
degradada de verdade, coisa com correção do nosso lado. Frescor de terceiro vive
agora em `fonte_externa_ok`, com canal de alerta próprio no
`watch-vixradar-health.ps1` e reenvio de 48h.

`fonte_externa_ok:false` **não** reprova o portão. Ele só vai a false depois de
dois ciclos semanais perdidos, porque o ramo `CIA_ABERTA/DOC` da CVM tem cadência
semanal declarada e publica aos domingos (CVMCADENCIA1). Ver
`cvm_fonte_ciclos_perdidos`, `cvm_fonte_cadencia` e `cvm_fonte_proxima_prevista`
na resposta. Fonte com 4 dias úteis no meio da semana é o comportamento normal
dela, não incidente, e a régua antiga de 2 dias úteis fazia o painel ficar
vermelho toda quarta-feira.

## Histórico de incidentes (para não repetir)

Incidentes documentados no changelog do `wrangler.toml` e no vault Obsidian.
Lista parcial dos que têm correção estrutural:

| Tag | O que foi | Fix |
|---|---|---|
| SECRETMISS1 | `ADMIN_EMAIL` exposto como var, não secret | Movido para secret |
| ADMINXSS1 | Página admin sem escaping | Sanitização de output |
| STATELEAK1 | Estado vazava entre semanas | Isolamento por chave de semana |
| RACEKV1 | Race condition na gravação do estado | FIFO promise chain + fail-open |
| VERIFINJ1 | Injeção via parâmetro de verificação | Validação de assinatura Svix |
| CSRF-COOKIE1 | Auth por cookie vulnerável a CSRF | Migrado para JWT no header |
| EMAILGET1 | Email actionable por GET | Migrado para POST com token |
| SENTRY1 | Worker sem captura de exceção; 167 try/catch mudos | `Sentry.withSentry` no export, `sentry_ok` no `_okHealth`, gate de secret no deploy |
| ROUTINEKEY-PLAIN1 | `routine_key` em texto puro em `SKILL.md`/`ROUTINES-CLOUD.md` das rotinas cloud (Claude Desktop). Comentário "chave removida do disco 2026-07-24" ficou ao lado do valor literal, remoção não tinha coberto esses arquivos. Achado de novo em 07/08/2026 em 4 arquivos vivos (verificacao-async, noturno, matinal, export-historico), fora dezenas de backups e transcripts históricos que preservam o valor por serem append-only. | Valor redigido nos 4 arquivos vivos em 07/08. Chave em si **não foi rotacionada**, continua válida — rotação é decisão pendente do usuário, afeta toda rotina que autentica com ela. |
| ADMINRL-FIX1 | Gate RLADMIN2 (v4.9.164) mandava para `checkRateLimitV2` qualquer request com `admin_senha`, inclusive o painel admin legítimo que dispara 4 POSTs em paralelo com a senha certa (tela Hoje). Estourava burst anônimo de 3/60s e o painel exibia 429. Incidente 12/08 15:13 BRT. | v4.9.191: `admin_senha === ADMIN_PASSWORD` pula o check. Brute force continua throttled (senha errada segue no check). Testes em `api/test/rate-limit.test.mjs`. |
| CALVAL-V2 | Agenda de Resultados exibia datas erradas por dias/meses: sem validação de fonte (secundária valia como oficial), merge cego, base estática `estimado_historico` como fallback e overlay sem status. 12/08. | v4.9.192 + v202.7: tier de fonte fail-closed, 5 `status_validacao` computados no Worker, oficial nunca sobrescrita por secundária divergente, gate `confirmado` no build da agenda, auditoria de mudança de data, aliases, confronto diário com CVM, selos no frontend. Testes `api/test/agenda-validacao.test.mjs` + harness local. Nota 80. |

Se uma mudança nova toca em auth, KV, estado multi-semana ou input de usuário,
conferir se não reabre um desses.

## CSS e frontend

- `<strong>`: sem `color` global, só `font-weight`. Cor por seletor específico.
- Design system: gold `#B7985D`, navy `#001020`, fontes DM Sans + Cormorant Garamond + Inter.
- Copyright Szuchmacher Consultoria Ltda (INPI). CACHE_VERSION no header de `app/index.html`.
- CSP deliberadamente ausente (scripts inline no HTML de 700 KB).
