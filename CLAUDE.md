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

## Arquitetura de IA (revisada 2026-07-10 contra os scripts reais)

Cascade OpenRouter → Gemini → Perplexity **obsoleta desde v4.9.108**. Nenhuma rotina usa Opus — registro anterior ("Opus matinal") era drift de documentação.

| Caminho | Modelo | Trigger |
|---------|--------|---------|
| Pulso manual | `claude-haiku-4-5-20251001` (Anthropic API) | Usuário no frontend |
| Matinal (top 15 por EWS) | `claude-haiku-4-5-20251001` (chunks de 6) + `claude-sonnet-4-6` (emissores com EWS >= 38, chunks de 4) — `run_vixradar_matinal_claude.ps1` | Task nativa Windows `VIXRadar-Matinal` 10h00 BRT (scheduled-task Claude Code duplicada foi neutralizada 08/07) |
| Noturno (103/103) | `claude-haiku-4-5-20251001` (tier ultra) + `claude-sonnet-4-6` — `run_vixradar_noturno_claude.ps1` | Task nativa Windows 18h00 BRT (mutex `Global\vixradar-noturno-v2` contra duplicata) |
| Verificador adversarial (CRITICO + amostra 20% RELEVANTE) | `claude-sonnet-4-6` via `claude -p` — desde v4.9.146. **Cobrança:** com `ANTHROPIC_API_KEY` no registro (User), roda **por token (metered)**, não por assinatura — assinatura é só fallback se a chave sumir. Avaliação de troca para `claude-fable-5` feita em 10/07: **não trocado** (sem ganho demonstrado, custo 2,3x-4,3x; critério de reversão na nota 49) | Fila KV `radar:verif_fila:{data}` drenada por 3 gatilhos: Task Scheduler `VIXRadar-Verificacao-Async` (10:20 BRT, trigger único) + dreno inline pós-matinal + dreno inline pós-noturno. Guardas nas 3 rotinas: auth-failure (exit 7 + abort, matinal incluída desde 08/07); dreno também detecta `stop_reason:refusal` (classificador Fable 5 — exit 8, rawout, métrica `refusals`, `--fallback-model` condicional preparado, 10/07). Gap conhecido: `Credit balance is too low` ainda não abortável (P2, incidente 10/07 10h). Ver `03 - Estado de Produção.md`, notas 48 e 49. |

Campos `openrouter`/`gemini`/`perplexity` no health são resíduo de schema — não indicam uso ativo.

`chamarClaudeVerificador`/`verificarEventosBatch` (chamada paga direta à API Anthropic) seguem existindo só para `admin_verificar_evento`/`admin_sweep_revalidacao` (diagnóstico manual) — não fazem mais parte do caminho principal de ingestão (`receber_analise`) desde v4.9.146.

## Produção atual (fonte: Obsidian `03 - Estado de Produção.md`)

| Componente | Produção | Repo local | URL |
|------------|----------|------------|-----|
| Worker | **v4.9.165** | `api/wrangler.toml` → **v4.9.165.js** (sincronizado automaticamente em 18/07 contra o health de produção) | https://api.vixradar.com |
| Frontend | **v201.78** | `app/index.html` → **v201.78** (sincronizado automaticamente em 19/07) | https://vixradar.com |
| Deploy Worker | `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.160` | — | — |
| Deploy Pages | `pwsh ./scripts/deploy-pages.ps1` | — | — |

Sem drift repo/prod (reconciliado 15/07, canonical-test verde após 8 dias vermelho — ver nota de sessão). v4.9.150 = diff pendente de 10/07 (normalizarMojibake no read path + briefing com fix porSetor) + preditivo quick wins (filtro de liquidez ativo, `spread_rel_setor` shadow, features+`model_version` no payload `predictive_v1:latest`, leitura null-safe de `fundamentals:altman:latest`). Rotinas locais novas: `VIXRadar-Export-Historico` (diária 20h45 — fundação de dados preditiva, `data/historico/`) e `VIXRadar-Ranking-Mensal` (dia 1, 11h30 — alerta de ultrapassagem SEO). Ver notas 50 e 51 do vault.

**Deploy é pelos scripts, não na mão.** `deploy-worker.ps1` e `deploy-pages.ps1` deployam, validam produção e **commitam/pusham** numa tacada. **RESOLVIDO em `a2e7d84`:** `api/v4.*.js` saiu do `.gitignore` — o bundle deployado é auditável no repo, sem allowlist manual e sem precisar de `-f`. Foi a ausência dessa linha que deixou produção chegar a v4.9.159 com o repo declarando v4.9.154 e o canonical-test 8 dias vermelho (07/07 a 15/07); não reintroduzir o ignore. Se precisar deployar cru, o passo depois é só `git add api/<versao>.js api/wrangler.toml && git commit && git push`.

**Atenção Wrangler 4.x:** `--no-autoconfig` obrigatório — sem isso, o Wrangler detecta `E:\Diretorio\Claude\dashboard` como projeto e ignora `wrangler.toml`. Os scripts já passam a flag.

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
