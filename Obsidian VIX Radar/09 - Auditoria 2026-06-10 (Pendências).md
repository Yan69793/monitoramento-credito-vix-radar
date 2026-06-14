---
title: Auditoria de Pendências — 2026-06-10
date: 2026-06-10
tags:
  - auditoria
  - pendencias
  - repeat-run
status: concluída
aliases:
  - Auditoria Junho 2026
  - PENDENCIAS 2026-06-10
---

# Auditoria de Pendências — 2026-06-10

Tipo: **repeat-run** (baseline: [[04 - Auditoria 2026-06-08|2026-06-08]], P01–P22).
Executada: 2026-06-10T21:00–22:30Z (aprox).
Branch: `audit/reconcile-prod-2026-06-01`.
Snapshot de produção: `docs/auditorias/prod-worker-2026-06-10.js` (717 KB, 15.635 linhas).

Relatório completo: `PENDENCIAS.md` (root do repo).

---

## Resultado do Drift (G1)

> [!warning] Drift detectado — mesmo número de versão, builds diferentes
> - **Prod**: 717 KB / 15.635 linhas — build na máquina `User` (wrangler via npx)
> - **Repo** `api/v4.9.102.js`: 676 KB / 14.431 linhas — build na máquina `szuch` (wrangler global)
> - **Versão**: ambos `v4.9.102` — sem drift funcional, apenas de artefato
> - **Sourcemap**: prod tem `v4.9.102.js.map` ✅ · repo tem `v4.9.99.js.map` ❌

---

## Afirmações do Operador vs Evidência

| Afirmação | Veredito |
|---|---|
| Cascade substituído por **Claude Opus** | **FALSO** — cascade ativo com `claude-haiku-4-5-20251001` (tier 2) |
| Guard de **8s** causa fallback nas LLMs | **FALSO** — 8s é só fetch HTML; LLMs têm 55s |
| Tarefa `radar-analise-diaria-19h` com senha errada | **NÃO ENCONTRADA** — 0 tasks via MCP |
| Cron boletim `0 21 * * 1-5` | **INCORRETO** — cron real é `30 21 * * *` (diário) |
| POST / anônimo funciona | **FALSO** — HTTP 401 "Autenticação necessária" |
| WAF exige User-Agent de navegador | **FALSO** — GET / retorna 200 com e sem UA |

---

## Achados Críticos (3)

> [!danger] N01 — OpenRouter 402: cascade parcialmente inoperante
> Todos os probes em `action=teste` retornaram HTTP 402 (sem créditos).
> Sistema rodando exclusivamente em `claude-haiku-4-5-20251001` via Anthropic API.
> **Ação imediata:** recarregar créditos OpenRouter ou promover haiku a tier primário.

> [!danger] P05* — CI 100% quebrado
> `.github/workflows/canonical-test.yml` faz POST anônimo → 401 e usa `EXPECTED_WORKER="4.9.100"` (prod é `v4.9.102`).
> Job falha em toda execução a cada 6h. Sistema de alerta de drift está morto.
> **Ação:** reescrever step de teste; atualizar `EXPECTED_WORKER`.

> [!danger] P15* — Cron duplo noturno (custo dobrado)
> Cron `0 2 * * *` (23h BRT) cai no pipeline noturno completo (100 emissores + newsletter), 2h30 após o principal `30 21 * * *`. Propósito não documentado. Dobra custo de API.
> **Ação:** documentar propósito ou remover do `[triggers]`.

---

## Reconciliação com Baseline P01–P22

| ID | Status anterior | Status atual | Observação |
|---|---|---|---|
| P01 | RESOLVIDO | RESOLVIDO | CORS www confirmado em produção |
| P02 | RESOLVIDO | RESOLVIDO | TENANT_DOMAIN_MAP corrigido |
| P03 | RESOLVIDO | RESOLVIDO | `ews_filter` presente |
| P04 | RESOLVIDO | RESOLVIDO | Security headers em produção |
| P05 | RESOLVIDO | **AGRAVADO** | CI 100% quebrado (401 + versão errada) |
| P06 | RESOLVIDO | RESOLVIDO | `WORKER_DEPLOY_NOTE` correto em prod |
| P07 | ABERTO | PARCIAL | Prod: sourcemap correto; repo: ainda `v4.9.99.js.map` |
| P08 | ABERTO | ABERTO | `__name` × 9 confirmado em prod (717 KB) |
| P09 | RESOLVIDO | RESOLVIDO | `WORKER_URL` corrigido |
| P10 | ABERTO | ABERTO | Comparação string ordinária em 8 call sites |
| P11 | ABERTO | ABERTO | `ADMIN_EMAIL` hardcoded confirmado em prod |
| P12 | ABERTO | ABERTO | `catch(e){}` vazio em `__fixCorsResp` |
| P13 | ABERTO | ABERTO | KV `list()` eventual consistency em comentários |
| P14 | RESOLVIDO | RESOLVIDO | `carregarEstadoMultiSemana` no health check |
| P15 | ABERTO | **AGRAVADO** | Double-run confirmado via código e crons |
| P16 | RESOLVIDO | RESOLVIDO | `VIXRADAR_STATE.md` criado |
| P17 | RESOLVIDO | RESOLVIDO | `2027-11-20` adicionado ao calendário B3 |
| P18 | ABERTO | ABERTO | Bundles acumulando em `api/` sem política |
| P19 | ABERTO | ABERTO | `account_id` e KV id hardcoded no toml |
| P20 | ABERTO | ABERTO | `express`/`openai` não usados em `package.json` |
| P21 | RESOLVIDO | RESOLVIDO | Vault Obsidian existe e está operante |
| P22 | ABERTO | ABERTO | `handleEmailAcao` usa `...CORS` estático |

**Resolvidos do baseline:** 12 de 22 (P01–P04, P06, P09, P14, P16, P17, P21)
**Novos achados nesta auditoria:** 18 (N01–N13 + variantes)
**Total desta auditoria:** 40 achados

---

## Achados Novos (Top)

| ID | Severidade | Descrição |
|---|---|---|
| N01 | Crítico | OpenRouter 402 — cascade inoperante |
| N02 | Alto | Bundle repo ≠ bundle prod (mesmo v4.9.102, builds diferentes) |
| N03 | Alto | XSS legacy `innerHTML` sem escaping no frontend |
| N04 | Médio | `worker_version = "v4.8.5"` hardcoded no health check |
| N05 | Médio | `ehAgenda` handler sem cron `0 4 * * *` correspondente |
| N06 | Médio | `CRITICIDADE_SETOR` com 6 chaves divergentes do `EMISSORES_MAP` |
| N07 | Médio | `ARQUIVO_PRE` com 2 eventos > 90 dias (Raízen, GPA) |
| N08 | Médio | `METRICAS_CURADAS` com dados 4T25 (6 meses de defasagem) |
| N09 | Médio | `CLAUDE.md` com paths incorretos (`worker/`, `index.html` raiz, 200→401) |
| N10 | Médio | Model IDs de geração anterior (`haiku-4-5-20251001`, `sonnet-4-5-20250929`) |

---

## Evidências Brutas

```
GET / health:
{"ok":true,"versao":"v4.9.102","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"3/3"}
HTTP 200 (com e sem User-Agent)

POST / anônimo: HTTP 401 {"ok":false,"erro":"Autenticação necessária."}
action=teste: openrouter 402 (sem créditos) · anthropic/haiku OK · resend OK
CORS apex ✅ · CORS www ✅ · CORS inválido: ACAO omitido ✅
SPF: include:send.resend.com presente ✅
DMARC: p=none; rua=mailto:dmarc@vixradar.com ✅
tel_test: binding_presente:true · write_result.ok:true ✅
```

---

## Próximos Passos

1. Recarregar créditos OpenRouter (N01 — **imediato**)
2. Corrigir CI: remover POST anônimo + atualizar `EXPECTED_WORKER="4.9.102"` (P05*)
3. Documentar ou remover cron `0 2 * * *` (P15*)
4. Corrigir `worker_version = "v4.8.5"` → `WORKER_VERSAO` (N04 — 5 minutos)
5. Alinhar chaves de `CRITICIDADE_SETOR` com `EMISSORES_MAP` (N06)

Ver [[03 - Estado de Produção]] para estado atual de produção.
