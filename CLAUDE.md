# Protocolo Operacional — VIX Radar (hardened 2026-07-25)

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
Nunca `wrangler deploy` direto. O script faz 5 passos atômicos: build do src,
aponta `wrangler.toml main`, deploy com `--no-autoconfig`, valida GET / em produção,
e só então git add/commit/push. Token Cloudflare é variável de ambiente do sistema.

### Pages
```
pwsh ./scripts/deploy-pages.ps1
```
Sincroniza `app/index.html` → `app/deploy_zip/`, regenera `version.json`, confere
os 4 arquivos do bundle, deploy, valida em produção.

### Regras invioláveis de deploy
- Wrangler 4.x: sempre `--no-autoconfig`. Sem isso detecta `E:\Diretorio\Claude\dashboard` como projeto e ignora `wrangler.toml`.
- Fonte do Worker: `api/src/worker.js` (17k linhas). Bundles `api/v4.*.js` são artefatos gerados — nunca editar diretamente, publicar com `no_bundle=true`.
- Fonte do frontend: `app/index.html` (CACHE_VERSION no header). Sincronizar `app/deploy_zip/` antes do deploy.
- Git commit só depois de deploy validado em produção (anti-drift).
- `CLOUDFLARE_API_TOKEN` é variável de ambiente do sistema, nunca no repo.

### Bindings obrigatórios
`RADAR_KV` (KV `c6805b8d8a7b468e9f854ab4f91fb93a`), `RATE_LIMITER_DO` (RateLimiterDO),
`ESTADO_SEMANA_DO` (EstadoSemanaDO, SQLite com migration v2), `RADAR_USAGE_EVENTS`
(Analytics Engine). Não remover bindings.

## Rotinas do Task Scheduler (fonte da verdade: `routines/README.md`)

Estes scripts PowerShell chamam o Claude CLI localmente. Todos usam `routine_key` para
autenticar contra o Worker. A chave nunca está versionada.

| Tarefa | Frequência | Script | Escopo |
|---|---|---|---|
| `VIXRadar-Matinal` | Seg-Sex 10h00 BRT | `run_vixradar_matinal_claude.ps1` | Top 15 por EWS |
| `VIXRadar-Noturno` | Diário 18h00 BRT | `run_vixradar_noturno_claude.ps1` | 103 emissores |
| `VIXRadar-Verificacao-Async` | Diário 10h20 BRT | `run_vixradar_verificacao_async.ps1` | Fila `radar:verif_fila:{data}` |
| `VIXRadar-Export-Historico` | Diário 20h45 BRT | — | Exporta estado |
| `VIXRadar-Ranking-Mensal` | Dia 1, 11h30 | — | SEO mensal |

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

- `canonical-test.yml`: health check GET / a cada 6h (valida ok, kv, rate_limiter, telemetria, providers)
- `daily-status-email.yml`: status diário via Issue + email Resend (não depende de MCP/OAuth)
- `frescor-check.yml`: diário 01:37 UTC, staleness da ingestão
- `scan-emergencia.yml`: fallback 23:30 UTC quando estado principal stale

## Portão de verificação

Antes de declarar qualquer tarefa concluída, execute:
```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```
Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`.
Cole a saída real na resposta. Se falhar ou não puder executar, diga explicitamente.
Nunca declare "funcionando" sem a saída colada.

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

Se uma mudança nova toca em auth, KV, estado multi-semana ou input de usuário,
conferir se não reabre um desses.

## CSS e frontend

- `<strong>`: sem `color` global, só `font-weight`. Cor por seletor específico.
- Design system: gold `#B7985D`, navy `#001020`, fontes DM Sans + Cormorant Garamond + Inter.
- Copyright Szuchmacher Consultoria Ltda (INPI). CACHE_VERSION no header de `app/index.html`.
- CSP deliberadamente ausente (scripts inline no HTML de 700 KB).
