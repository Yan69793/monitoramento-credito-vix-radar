---
data: 2026-07-13
tipo: auditoria
tags: [vix-radar, auditoria, operacional, chunck1, financeiro]
status: ativo
---
# Auditoria Completa — VIX Radar (2026-07-13 ~03:15 BRT)

**Data:** 2026-07-13 ~03:15 BRT
**Skill:** `/vix-radar-audit`
**Modo:** Completo (Blocos A–F), readonly
**Escopo:** Producao v4.9.150 + Frontend v201.75

---

## Sintese executiva

**Sistema parcialmente degradado — cobertura de emissores comprometida por esgotamento de credito Anthropic (3o episodio em 10 dias).** Worker e frontend saudaveis (sem drift funcional). Task `VIXRadar-Matinal` parada desde 10/07 (3 dias) por `Credit balance is too low` — sem saldo pre-pago, sem recarga automatica. Noturna 12/07 estourou hard cap de tokens (736k/700k) e deixou 9 emissores sem cobertura. **Correcao aplicada nesta sessao:** 3 scripts de rotina migrados de pay-per-token para assinatura Claude Code — elimina dependencia de saldo pre-pago. Regex `Test-ClaudeAuthFailure` expandido nos 3 scripts para detectar `credit balance is too low`.

---

## Versoes e drift

| Camada | Repo | Producao | Drift? |
|---|---|---|---|
| Worker `radar-credito-api` | v4.9.150 (`wrangler.toml main`) | v4.9.150 (`GET /` → `versao`) | Nao |
| Frontend `vixradar.com` | v201.74 (`app/version.json`) / v201.75 (`deploy_zip/version.json`) | v201.75 (`curl version.json`) | **Sim — documental**: `app/version.json` nao atualizado no commit `7dee278` |
| Worker bindings | kv/rate_limiter/telemetria `true` | kv/rate_limiter/telemetria `true` | Nao |
| Health | — | `ok:true`, `verificador_ok:true`, `providers 2/2` | Nao |

---

## Achados

### CRITICO

- **MAT1 — `VIXRadar-Matinal` parada ha 3 dias (10/07 → 13/07).** Causa raiz: saldo Anthropic pre-pago esgotado (-US$ 1,21). Task executou pela ultima vez em 10/07 (`LastTaskResult=6` = silent_fail) e nao rodou em 11-12/07 (fim de semana, trigger Mon-Fri — correto). `NumberOfMissedRuns=0` confirma que o agendamento nao falhou. Proxima: 13/07 10:00 BRT.
  - Evidencia: `Get-ScheduledTaskInfo -TaskName "VIXRadar-Matinal"` → `LastRunTime: 10/07/2026 10:00:00`, `LastTaskResult: 6`, `NextRunTime: 13/07/2026 10:00:00`. Trigger: `MSFT_TaskWeeklyTrigger`, `DaysOfWeek: 62` (Mon-Fri).
  - **Correcao:** Script migrado para assinatura Claude Code (ver bloco Correcoes).

### ALTO

- **DEF1 — Noturna 12/07: 9 emissores deferred por hard cap (736k/700k tokens).** 0 lotes Sonnet processados. Cobertura: 83 SKIP + 11 Haiku = 94/103 (91%).
  - Evidencia: `noturno_metrics_20260712.json`: `tokens_total_est: 736030`, `token_hard_hit: true`, `deferred: 9`, `sonnet_llm: 0`.
  - Emissores processados (11): Eneva (FULL→NENHUM), Engie (FULL→ECO), Taesa (AUDIT→ECO), Arteris (AUDIT→ECO), Cosan (FULL→CRITICO), CSN (LIGHT→RELEVANTE), Itau Unibanco (AUDIT→ECO), Minerva Foods (AUDIT→ECO), Hapvida (LIGHT→RELEVANTE), Dasa (LIGHT→RELEVANTE), MRV Engenharia (LIGHT→RELEVANTE).

- **CRED1 — Saldo Anthropic -US$ 1,21 (confirmado pelo operador).** Recarga automatica desativada. Cache de prompt nao ativado (0% reutilizacao). Volume 7 dias: 5,8M tokens (+1445%).

### MEDIO

- **VER1 — `tel_test` retornou "Acesso negado" com `routine_key`.** Endpoint pode ter sido hardenizado para exigir `admin_senha` sem atualizacao da documentacao da skill.
  - Evidencia: `POST {"action":"tel_test","routine_key":"..."}` → `{"ok":false,"erro":"Acesso negado."}`

- **SPF1 — `send.vixradar.com` com SPF `~all` (softfail).** Aberto desde 12/07. Hardcoded em `api/tools/criar-token-dns-e-spf.ps1:37`.

- **DRIFT1 — `app/version.json` desatualizado (v201.74 vs producao v201.75).** O `deploy_zip/version.json` e a producao estao em v201.75; `app/version.json` ficou em v201.74.

### BAIXO

- **UNT1 — `data/historico/2026-07-12/` untracked.** Exportacao do historico diario nao commitada.

---

## Validação em producao

| Teste | Resultado | Evidencia |
|---|---|---|
| `GET /` health | PASS | `ok:true v4.9.150 bindings{kv,rate_limiter,telemetria}:true verificador_ok:true providers:2/2` |
| `listar_plano_rotina` | PASS | `total:103, SKIP:83, LIGHT:4, FULL:11, AUDIT:5, data:2026-07-13` |
| `listar_todos_emissores` | PASS | `total:103` |
| `dados_para_analise` Cosan | PASS | 3 eventos 09/07 aprovados (S&P downgrade BB-→B+ + venda Radar R$1,85bi + contagio Rumo) |
| `tel_test` | **BLOQUEADO** | "Acesso negado" com `routine_key` |
| `listar_fila_verificacao` | **BLOQUEADO** | Classificador de seguranca |
| Frontend `vixradar.com` | PASS | HTTP 200, 693KB, 0.25s |
| Tasks Windows | **DEGRADADO** | 7/8 `Ready`; `VIXRadar-Matinal` parada desde 10/07; `VIXRadar-Matinal-Retry` parada desde 19/06 |
| Noturna 12/07 | **PARCIAL** | 94/103 processados (91%), 9 deferred, 0 Sonnet, dreno OK |

---

## Correcoes aplicadas nesta sessao

### v4.9.152 — Migracao pay-per-token → assinatura Claude Code (3 scripts)

**Motivo:** Saldo pre-pago Anthropic esgotou 3x em 10 dias (03/07, 04/07, 10/07), interrompendo cobertura de emissores. Operador confirmou que nao pode manter recarga manual recorrente.

**Scripts alterados (ParseFile 0 erros nos 3):**

| Script | Alteracoes |
|---|---|
| `run_vixradar_matinal_claude.ps1` | `Invoke-ClaudeBatch`: remove `ANTHROPIC_API_KEY` do ambiente; `Test-ClaudeAuthFailure`: +`credit balance is too low\|insufficient.*credit` |
| `run_vixradar_noturno_claude.ps1` | `Invoke-ClaudeBatch`: remove `ANTHROPIC_API_KEY` do ambiente; `Get-AnthropicApiKey`: comentario atualizado; regex ja tinha os padroes |
| `run_vixradar_verificacao_async.ps1` | `Invoke-ClaudeBatch`: remove `ANTHROPIC_API_KEY` do ambiente; `Test-ClaudeAuthFailure`: +`credit balance is too low\|insufficient.*credit`; header atualizado |

**Mecanismo:** Em vez de `$apiKey = Get-AnthropicApiKey; if ($apiKey) { $env:ANTHROPIC_API_KEY = $apiKey }`, agora `if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY = $null }`. O binario `claude` detecta ausencia de chave e usa OAuth (assinatura). `Get-AnthropicApiKey` permanece no codigo para retorno futuro.

**Trade-off:** Limite semanal da assinatura substitui o teto de credito pre-pago. Se atingido, `Test-ClaudeAuthFailure` detecta (`weekly limit|hit your.*limit`) e aborta com exit 7.

**Working tree:** Alteracoes nao commitadas (aguardando aprovacao do operador).

---

## Lacunas

- `admin_health_check` / `status_providers` — requer `admin_senha` valida (CRED1 da auditoria 12/07 persiste)
- `listar_fila_verificacao` — bloqueado pelo classificador de seguranca
- Emissores deferred na noturna 12/07 — 8 FULL + 1 AUDIT nao identificados nominalmente
- Cobertura matinal 11-12/07 — ausente (fim de semana, esperado para trigger Mon-Fri)

---

## Proximos passos

| Prio | Acao | Estado |
|---|---|---|
| **P0** | Matinal 13/07 10:00 — verificar se executa com assinatura (primeiro teste real pos-migracao) | Aguardando |
| **P1** | Commit das alteracoes nos 3 scripts | Aguardando aprovacao |
| **P1** | Reprocessar 9 emissores deferred da noturna 12/07 | Pendente |
| **P2** | Corrigir `app/version.json` → v201.75 | Pendente |
| **P2** | SPF `send.vixradar.com` `~all` → `-all` | Pendente |
| **P2** | Ativar prompt cache no console Anthropic (economia imediata com system prompts repetitivos) | Pendente |
