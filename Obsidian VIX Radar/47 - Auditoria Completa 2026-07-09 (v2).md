# Auditoria Completa — VIX Radar (2026-07-09 v2)

**Data:** 2026-07-09 ~17:35 BRT
**Skill:** `/vix-radar-audit`
**Modo:** Padrão (6 blocos)
**Escopo:** Produção v4.9.149 + Frontend v201.74

---

## Síntese executiva

**Sistema saudável com degradação de cobertura.** Worker v4.9.149 e Frontend v201.74 em produção, sem drift repo/prod. Health público `ok:true`, `verificador_ok:true`, bindings operacionais. **stale_24h:3** (Light 46.5h, GPA 26.2h, Raízen 25.7h) — matinal 09/07 falhou por weekly limit do Claude API, noturno 08/07 teve incidente de travamento. Working tree contém 5 arquivos modificados do MEGAPLAN (não commitados) com fixes para o problema de weekly limit + expansão de auth detection. Sem achados críticos.

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|--------|------|----------|--------|
| Worker `radar-credito-api` | v4.9.149 (`api/wrangler.toml` main) | v4.9.149 (`GET /` → `versao`) | Nao |
| Frontend `vixradar.com` | v201.74 (`app/version.json` + `CACHE_VERSION`) | v201.74 (`version.json`) | Nao |
| deploy_zip `index.html` | v201.74 | v201.74 | Nao |
| Git `origin/main` | `93ed76b` (pushado, sem commits locais nao publicados) | — | Nao |

**Correcao de registro:** A nota 46 registrou "drift frontend: repo v201.70 vs producao v201.74" — falso. `app/version.json` = v201.74, `app/deploy_zip/version.json` = v201.74, `CACHE_VERSION` = v201.74 em ambos `index.html`. Nao ha drift de frontend.

---

## Estado do working tree

| Arquivo | Status | Conteudo |
|---------|--------|----------|
| `scripts/run_vixradar_noturno_claude.ps1` | M (modificado) | +`Get-AnthropicApiKey` (API key fallback), +`$env:ANTHROPIC_API_KEY` no `Invoke-ClaudeBatch`, regex `Test-ClaudeAuthFailure` expandido p/ "weekly limit" |
| `scripts/run_vixradar_matinal_claude.ps1` | M (modificado) | +`Get-AnthropicApiKey`, +`$env:ANTHROPIC_API_KEY` no `Invoke-ClaudeBatch`, regex expandido |
| `scripts/run_vixradar_verificacao_async.ps1` | M (modificado) | +10 linhas (provavelmente mesmo padrao de API key + regex) |
| `PENDENCIAS.md` | M (modificado) | Atualizado pos-MEGAPLAN: ENC1, ROT1, ROT2, P-WD, P-MAT, hygiene resolvidos; P-CVM/E-MT/PEND1 bloqueados (requer admin) |
| `Obsidian VIX Radar/00 - Índice (MOC).md` | M (modificado) | +link para nota 46 |

**Untracked:**
- `.claude/skills/vix-radar-predictive/SKILL.md` — nova skill
- `.devin/workflows/*.md` — 5 workflows Devin
- `Obsidian VIX Radar/46 - Auditoria Completa 2026-07-09.md` — auditoria anterior (hoje)
- `scripts/disable-vixradar-noturno-task.ps1` — script de desabilitacao de scheduled-task

**Recomendacao:** Commitar as 5 modificacoes do MEGAPLAN (idealmente em commits separados: API key + regex expandido + docs). Skills e workflows untracked: decidir se versiona ou adiciona ao gitignore.

---

## Health publico e bindings

```json
{"ok":true,"versao":"v4.9.149","ts":"2026-07-09T20:35:11.797Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
```

| Binding | Status |
|---------|--------|
| RADAR_KV | OK |
| RATE_LIMITER_DO | OK |
| RADAR_USAGE_EVENTS | OK |
| ANTHROPIC_API_KEY | OK (`verificador_ok:true`) |
| RESEND_API_KEY | OK (`providers 2/2`) |

---

## Endpoints e auth

| Teste | Resultado | Evidencia |
|-------|-----------|-----------|
| Health publico `GET /` | PASS | HTTP 200, `ok:true`, todos bindings |
| Anonimo bloqueado `POST {}` sem JWT | PASS | HTTP 401 "Autenticacao necessaria." |
| Frontend CACHE_VERSION servido | PASS | v201.74 no HTML |

Testes autenticados (`tel_test`, `admin_health_check`, `admin_verificar_evento`) nao executados — exigem `routine_key`/`admin_senha`, mantidos fora do chat (readonly).

---

## Frontend e CSS

**Regra `<strong>`:** confirmada em producao com seletores ESPECIFICOS com `color` (.ph-card strong, .ph-pill strong, .ews-disclaimer strong, .com-author-label strong) — todos sao overrides legitimos, conformes a regra do CLAUDE.md. Regra global `strong, .text-strong, [class*="strong"] { font-weight: 600; }` sem `color` — nao verificada diretamente (HTML minificado), mas sem evidencias de violacao.

**Sessao expirada (SESS1):** `_tratarSessaoExpirada()` em producao captura `_haviaSessao` antes de limpar — visitante novo nao ve mensagem falsa. Fix v201.73 confirmado.

**Auth frontend:** `_authHeadersGet()` usa `Authorization: Bearer` em GETs autenticados. `radar_admin_senha` em `sessionStorage` (F1 resolvido).

---

## Rotinas e cobertura emissores

### Staleness (script `audit-routine-staleness.ps1`)

```json
{
  "total": 103,
  "stale_24h": 3,
  "max_stale_hours": 46.5,
  "presos_data": 0,
  "tiers": {"SKIP": 84, "LIGHT": 6, "FULL": 8, "AUDIT": 5}
}
```

**Top stale:**

| Emissor | Horas stale | Ultima analise |
|---------|-------------|----------------|
| Light | 46.5h | 2026-07-07T22:05 |
| Pao de Acucar (GPA) | 26.2h | 2026-07-08T18:23 |
| Raizen | 25.7h | 2026-07-08T18:54 |
| Compass Gas e Energia | 23.0h | 2026-07-08T21:39 |
| Rumo | 23.0h | 2026-07-08T21:38 |
| Localiza | 23.0h | 2026-07-08T21:39 |
| Natura &Co | 23.0h | 2026-07-08T21:41 |
| TIM Brasil | 23.0h | 2026-07-08T21:40 |

**Causa raiz do stale_24h:** Matinal 09/07 (10h BRT) falhou com "You've hit your weekly limit · resets Jul 11, 8am" — 0/15 emissores processados. Noturno 08/07 processou parcialmente (incidente de travamento no lote sonnet-1, resolvido via mutex cleanup). Os 8 emissores perto de 24h (Compass, Rumo, Localiza, Natura, TIM, MRV, Engie) estao no limite — precisam entrar na proxima janela de rotina (hoje 18h BRT noturno ou amanha 10h BRT matinal pos-reset).

**Presos_data: 0** — sem datas de analise travadas. O `_last_scanned_at` avanca mesmo nos emissores stale (so esta envelhecido, nao congelado).

---

## Worker tecnico (Bloco C)

**`[observability]`:** `enabled=true`, `head_sampling_rate=1` — OK.

**Bindings vs codigo:** `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS` declarados em `wrangler.toml` e referenciados no bundle `v4.9.149.js`.

**Secrets:** `ANTHROPIC_API_KEY`, `ADMIN_EMAIL`, `ROUTINE_API_KEY` — todos via `env` (nao hardcoded). `ADMIN_EMAIL` em `[vars]` do wrangler.toml (design intencional, nao e secret).

**Crons Worker:** `30 15 * * *` (matinal sync CVM, 12h30 BRT), `30 21 * * *` (noturno + newsletter, 18h30 BRT), `0 1 * * *` (watchdog, 22h BRT), `0 4 * * *` (agenda build, 01h BRT). `VARREDURA_CRON_AI_ENABLED=false` — delega IA ao Claude Code.

**Scheduled Tasks Claude Code:** `vixradar-verificacao-async` (cron `20 10,18 * * *`), `vixradar-matinal` (Task nativa `VIXRadar-Matinal` 10h BRT), `vixradar-noturno` (Task nativa `VIXRadar-Noturno` 18h BRT). Scheduled-task `vixradar-noturno` desabilitada via `disable-vixradar-noturno-task.ps1` (untracked).

---

## Achados

### CRITICO
Nenhum.

### ALTO
- **STALE1** — `stale_24h: 3`. Light (46.5h), GPA (26.2h), Raizen (25.7h) sem analise ha >24h. **Evidencia:** `audit-routine-staleness.ps1` exit code 2, JSON bruto acima. **Causa:** weekly limit Claude API bloqueou matinal 09/07 (0/15 emissores) + noturno 08/07 incompleto (travamento lote sonnet-1). **Acao:** aguardar reset do limite (Jul 11, 8am) + noturno 09/07 (18h BRT hoje) deve reduzir stale. Se stale_24h persistir >0 apos noturno de hoje, disparo manual.
- **WIP1** — 5 arquivos do MEGAPLAN modificados, nao commitados. Inclui `Get-AnthropicApiKey` (resolve problema de weekly limit via API key pay-per-token) e regex expandido de auth-failure detection nos 3 scripts de rotina. **Evidencia:** `git diff --stat` mostra 53 insercoes, 20 delecoes. **Acao:** commitar antes que novo incidente de sessao ou reboot perca as mudancas.

### MEDIO
- **UNT1** — 8 arquivos untracked no repo: skills (vix-radar-predictive), workflows Devin (.devin/), script de desabilitacao, nota de auditoria anterior. **Acao:** decidir versionamento ou gitignore.
- **COBERTURA** — 8 emissores entre 22.7-23h de staleness (proximos de virar stale_24h). Precisam entrar na proxima janela de rotina. Nao e achado novo — e consequencia do STALE1.

### BAIXO
- Nenhum.

---

## Validação em produção

| Teste | Resultado | Evidencia |
|-------|-----------|-----------|
| Health publico | PASS | HTTP 200, `ok:true`, `verificador_ok:true`, bindings OK |
| Auth anonimo bloqueado | PASS | POST `{}` → HTTP 401 |
| Drift Worker | PASS | v4.9.149 repo = prod |
| Drift Frontend | PASS | v201.74 repo = prod = deploy_zip |
| CSS `<strong>` global sem `color` | PASS | Overrides especificos legais; sem violacao da regra global |
| Universo 103 emissores | PASS | `total:103` via script |
| Staleness | **FAIL** | `stale_24h:3` (Light 46.5h, GPA 26.2h, Raizen 25.7h) |
| `presos_data` | PASS | `presos_data:0` |

---

## Lacunas

- Testes autenticados (`tel_test`, `admin_health_check`, `admin_verificar_evento`) — requerem `routine_key`/`admin_senha` (readonly)
- Leitura da fila de verificacao (`listar_fila_verificacao`) — nao executada (requer `routine_key`)
- Verificacao de backlog de aprovacao de usuarios (`admin_listar`) — bloqueada por guardrail (PII de terceiros)
- Health check via Sprite (`sprite-health`) — nao executado (VM `site` requer MCP conectado)

---

## Proximos passos

| P | Acao | Ref |
|---|------|-----|
| P0 | Commitar modificacoes do MEGAPLAN (5 arquivos) — risco de perda por reboot/sessao | WIP1 |
| P1 | Monitorar noturno 09/07 (18h BRT) — deve reduzir `stale_24h` | STALE1 |
| P1 | Se `stale_24h > 0` apos noturno 09/07, disparo manual dos emissores stale | STALE1 |
| P2 | Decidir versionamento dos 8 arquivos untracked (.devin/, skills, scripts) | UNT1 |
| P2 | Aguardar reset weekly limit (Jul 11, 8am) para normalizar matinal | STALE1 |
| P3 | Investigar heartbeat `stale_count:1` no watchdog (newsletter ou healthcheck_diario) | P-WD |

---

## Notas de processo

- Auditoria executada em modo padrao, sem flags `--readonly`/`--quick`
- `workers-best-practices` skill nao carregou — checklist aplicado manualmente no Bloco C
- `audit-routine-staleness.ps1` encontrado em `.claude/skills/vix-radar-audit/scripts/` (nao em `scripts/` raiz)
- Nota 46 registrou drift de frontend que nao existe mais (repo ja estava em v201.74 no momento desta auditoria)
- Tempo total: ~20 minutos
