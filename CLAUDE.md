# Protocolo Operacional — VIX Radar

Fonte única de instruções do projeto. Histórico de versões antigas: `docs/archived/CLAUDE-HISTORICO.md`.

## Memória canônica

Vault Obsidian (ler primeiro em tarefas relevantes):

`E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\`

Começar por `00 - Índice (MOC).md` e `03 - Estado de Produção.md`.

Repo: `monitoramento-credito-vix-radar.git` (branch `main`). Única cópia ativa: `E:\Diretorio\Claude\Monitoramento de Credito\`.

## Regra central

Nunca deixar informação crítica só no chat. Ler Obsidian no início; gravar no Obsidian ao final de etapas relevantes (incidentes, deploys, decisões, pendências, validações).

Se conflito chat vs Obsidian: Obsidian prevalece, salvo evidência nova a registrar imediatamente.

## Modo expert (default)

- Implementar e validar — não só listar comandos para o usuário
- Profundidade staff; sem tutorial básico nem fluff
- Perguntar antes de inventar dados
- Proibido: jailbreak, `--dangerously-skip-permissions` como rotina

### Skills — roteamento leve

**Descoberta:** ler `.claude/SKILLS-ROUTER.md` → `pwsh -File scripts/skills-index.ps1` → carregar 1 `SKILL.md` só após match.

| Invocação | Uso |
|-----------|-----|
| `/vix-radar-briefing` | Abrir sessão |
| `/sprite-health` | Health pós-deploy (com curl local) |
| `/vix-radar-audit` | Auditoria (`--quick` por default) |
| `/vix-radar-next-steps` | Priorização backlog |
| `/wrangler` + `/workers-best-practices` | Deploy Worker |
| `/ODDA` | Incidente urgente |

Skills locais em `.claude/skills/` (não depender de `~/.claude/skills`).

### Health check — dupla validação

| Cenário | Ação |
|---------|------|
| Deploy/edição Worker, Pages, binding | curl local + Sprite `sh health_vix.sh` |
| Auditoria ou incidente | idem |
| Consulta rápida | só curl local |

Sprite MCP: `exec_command` → `sprite=site`, `command=sh health_vix.sh`. Repo: `scripts/sprite/health_vix.sh`.

Esperado: `HTTP:200`, `ok:true`, `telemetria:true`, `kv:true`, `verificador_ok:true`.

## Pós-edição obrigatório

Após mudança em código, config, deploy, Worker, Pages, KV, DO, provider ou frontend — entregar:

1. Causa raiz confirmada
2. Evidência objetiva
3. Correção aplicada
4. Validação em produção

Proibido: encerrar sem artefato bruto; assumir Pages = Worker publicado; afirmar correção sem teste real.

## Regras invioláveis

**CSS `<strong>`:** sem `color` global — só `font-weight`. Cor por seletor específico se necessário.

**Multi-semana:** endpoints `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor`, `comparar` usam `carregarEstadoMultiSemana(env, 5)`. Escrita continua na semana corrente.

**Telemetria:** binding `RADAR_USAGE_EVENTS` obrigatório no `api/wrangler.toml`. Pós-deploy: `GET /` → `telemetria:true`; `action=tel_test` com admin.

## Teste padrão (health público)

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`. POST anônimo retorna 401 desde v4.9.x.

## Arquitetura de IA (2026-06)

Cascade OpenRouter → Gemini → Perplexity **obsoleta desde v4.9.108**.

| Caminho | Modelo | Trigger |
|---------|--------|---------|
| Pulso manual | `claude-haiku-4-5-20251001` (Anthropic API) | Usuário no frontend |
| Lote 103 emissores | Opus matinal (top 15) + Sonnet noturno | Scheduled Tasks |
| Verificador adversarial (CRITICO + amostra RELEVANTE) | Assíncrono via Claude Code (assinatura), `claude-sonnet-4-6` — desde v4.9.146 | Fila KV `radar:verif_fila:{data}` drenada por scheduled task `vixradar-verificacao-async` (script pronto em `scripts/run_vixradar_verificacao_async.ps1`, registro da task ainda pendente) |

Campos `openrouter`/`gemini`/`perplexity` no health são resíduo de schema — não indicam uso ativo.

`chamarClaudeVerificador`/`verificarEventosBatch` (chamada paga direta à API Anthropic) seguem existindo só para `admin_verificar_evento`/`admin_sweep_revalidacao` (diagnóstico manual) — não fazem mais parte do caminho principal de ingestão (`receber_analise`) desde v4.9.146.

## Produção atual (fonte: Obsidian `03 - Estado de Produção.md`)

| Componente | Produção | Repo local | URL |
|------------|----------|------------|-----|
| Worker | **v4.9.146** | `api/wrangler.toml` → `v4.9.146.js` (deploy 2026-07-04) | https://api.vixradar.com |
| Frontend | **v201.69** | `app/index.html` + `app/deploy_zip/version.json` | https://vixradar.com |
| Deploy Worker | `cd api && npx wrangler deploy` | — | — |
| Deploy Pages | `npx wrangler pages deploy ./app/deploy_zip --project-name=radar-credito` | — | — |

Drift: conferir Obsidian antes de cada sessão — repo pode estar à frente ou atrás de produção.

**Não editar** bundles em `api/v4.9.*.js` diretamente — são artefatos Wrangler. Fonte viva do frontend: `app/index.html` → sincronizar `app/deploy_zip/` antes do deploy.

Diretórios legados (não deployar): `producao/`, `_historico/`, `archive/`, `vixradar/`.

## Stack resumido

| Feature | Status |
|---------|--------|
| Anthropic Haiku (pulso) | Ativo |
| Scheduled Tasks (matinal/noturno) | Ativo |
| KV `RADAR_KV` + DO `RateLimiterDO` | Ativo |
| Telemetria Analytics Engine | Ativo — não remover binding |
| JWT + CORS allowlist | Ativo |
| Newsletter Resend | Ativo |
| Cascade OR/Gemini/Perplexity | Obsoleto |

## Deploy Pages — checklist

1. Sincronizar `app/deploy_zip/` a partir de `app/index.html`, `_headers`, `_routes.json`
2. Regenerar `version.json` com `CACHE_VERSION` atual
3. Validar: `curl -s https://vixradar.com/version.json` e `CACHE_VERSION` no HTML

Token Cloudflare: variável de ambiente do sistema — nunca no repo. Ver Obsidian `VIX Radar - Deploy Cloudflare Pages.md`.

## OODA (incidentes)

Observe (logs, health, diff) → Orient (≥2 hipóteses) → Decide (ação reversível, ~70% confiança) → Act → re-Observe.

Ação irreversível: mais dados antes de agir.
