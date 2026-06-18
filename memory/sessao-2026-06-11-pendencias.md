---
type: project
date: 2026-06-11
session: dd52ec52-6d88-4d70-8da8-92e1cfb9d7df
title: Pendências abertas após sessão 2026-06-11
status: pendente
---

# Pendências abertas — sessão 2026-06-11

## SEGURANÇA — FAZER ANTES DE TUDO

- [x] **ROTACIONAR TOKEN CLOUDFLARE** — **RESOLVIDO 2026-06-11** (sessão continuação).
  Token `vixradar-analytics-engine-read` criado; `CLOUDFLARE_API_TOKEN` aplicado ao Worker.
  Scripts `deploy-pages.ps1` / `setup-deploy-credential.ps1` operacionais.

## FASE 0 — Críticos operacionais (de 2026-06-10, abertos)

- [x] **N01 — RESOLVIDO 2026-06-16** — causa real: `OPENROUTER_API_KEY` inválida no Worker (HTTP 401 na credits API).
  Secret removido via `wrangler secret delete`; cascade sem OpenRouter desde v4.9.108; probe retorna `sem_chave_openrouter`.
- [x] **P05* — CORRIGIDO** (commit `04fc826`). CI `canonical-test.yml` reescrito para
  health check GET / (anônimo, 200) em vez do POST que dava 401. Valida ok/kv/telemetria;
  `EXPECTED_WORKER="v4.9.102"`. Validado: YAML parseia, pipeline extrai HTTP 200 de prod.
- [x] **P15* — RESOLVIDO 2026-06-16** — cron duplicado removido em v4.9.109 (`0 4 * * *` único).

## DEPLOY v201.47 — CONCLUÍDO

- [x] **Deploy v201.47** (fix Briefing EWS) — DEPLOYADO em produção 2026-06-11
  (commit `745e8cb`, deployment `44119551`). Evidência bruta: version.json apex+www
  v201.47, fix presente no bundle servido.

## VALIDAÇÃO CONCLUÍDA (verificação online 2026-06-11)

- [x] P12 (Comparar) + P13 (Briefing) verificados em produção por Claude in Chrome — OK
  (1 defeito achado e corrigido: seção EWS sumia quando vazia → v201.47)

## FIXES 2026-06-11 (continuação de sessão)

- [x] **N06 PARCIAL — RESOLVIDO (display)** (commit `0c80ade`). Worker v4.9.104:
  `handleBriefingExecutivo` e `handleCompararEmissores` agora usam
  `SETOR_DE_EMPRESA[emp]` como fonte primária do setor (canônico) em vez de
  `resultado.setor` bruto do KV (que continha nomes lowercase da cascade AI).
  Corrige: distribuicao_setorial no Briefing, setor no Comparar, "Setores cobertos: 0" no PDF.

- [x] **N06 CÁLCULO — RESOLVIDO em repo** (Worker v4.9.105, 2026-06-11).
  `CRITICIDADE_SETOR` realinhado às 13 chaves canônicas do `EMISSORES_MAP`.
  6 setores divergiam (48/103 emissores, ~47%, caíam no fallback 0.7 em
  `enriquecerEvento`): Transportes e Logística 0.85 (era "Infraestrutura e
  Transporte"), Financeiro 0.95 (era "Bancos e Financeiras"), Real Estate e
  Construção 0.7 (era "Imobiliário e Shoppings"), Petróleo, Gás e Combustíveis
  0.85 (era "Petróleo e Gás"), Telecom e Tecnologia 0.65 (era "Telecomunicações"),
  Locação de Veículos e Mobilidade 0.7 (não existia; neutro = fallback).
  Validação: `node --check` OK; `testing/test-n06-criticidade-setor.mjs` PASS
  (13/13 cobertos, zero órfãs); diff v4.9.104→v4.9.105 = 8 linhas (2 versão + 6 chaves).
  `wrangler.toml main = "v4.9.105.js"`. Deploy pendente (token).

- [x] **Engajamento admin — erro melhorado** (frontend v201.48, commit `0c80ade`).
  Painel agora exibe o erro real da resposta (`c._erro`) em vez da mensagem genérica.
  **AINDA ABERTO (configuração operacional)**: painel requer 2 secrets no Worker:
  1. `CLOUDFLARE_ACCOUNT_ID` — adicionado a `[vars]` no wrangler.toml (deploy pendente)
  2. `CLOUDFLARE_API_TOKEN` com permissão Analytics Engine Read:
     `cd api && npx wrangler secret put CLOUDFLARE_API_TOKEN`
  Sem esses secrets, handleUso retorna 500 e o painel fica inoperante.

- [x] **P16 — Agenda de Divulgação semanal (IMPLEMENTADO v4.9.119 — 2026-06-16)**
  Worker: KV `calendario:overrides:v1`, `listar_calendario_stale`, `atualizar_calendario_emissor`, merge em `agendaBuildPersistir`.
  SKILL: `~/.claude/scheduled-tasks/vixradar-agenda-semanal/` (cron `0 6 * * 1` — registrar no agendador Claude).

- [x] **P17 — Relatório semanal piloto (v4.9.120 — 2026-06-16)**
  Semanal dedup semanaISO; `RELATORIO_DESTINATARIOS_PILOTO=yan@szuchmacher.com.br`; `RELATORIO_DIARIO_ENABLED=1`.
  Piloto enviado `relatorio_diario_teste` ok. Remover secret piloto para abrir a usuários semanal.

## VALIDAÇÃO ONLINE 02:07 BRT (Claude in Chrome) — relatório completo

- [x] Verificação end-to-end em produção sobre v201.47 + v4.9.102: nenhuma regressão.
  Fix v201.47 (EWS sempre visível) CONFIRMADO. Briefing/Comparar/Visão Geral/painel
  emissor/toggle alertas — todos operacionais.
- Sintomas pendentes confirmados (resolvem com o deploy): setores lowercase +
  duplicados no Briefing (mineracao/energia/saude... vs canônicos), Auren "Outros"
  no Comparar, mensagem genérica no Engajamento (v201.48 ausente).
- Achado: `RadarAdmin@2026` REJEITADA em produção; senha vigente (sistema + admin)
  registrada em `memory/credenciais.md`. Skill `radar-credito-privado` desatualizada.

## DEPLOY CONCLUÍDO (2026-06-11 05:29Z)

- [x] Worker v4.9.105 — Version ID `c8e93a7a-8535-4c25-bedc-cc441d88b24f`
- [x] `EMAIL_ALERTAS_FAVORITOS` = "1" (P11 ativo)
- [x] Frontend v201.48 — deployment `8077def8`
- [x] `CLOUDFLARE_API_TOKEN` — CONFIGURADO (2026-06-11 sessão continuação)
  Token `vixradar-analytics-engine-read` criado via Cloudflare dashboard (Account Analytics:Read,
  escopo conta 7ac79fb1030e4e81115ef33c21a9b070). Secret aplicado ao Worker via wrangler.
  Validação: POST `{action:"uso",admin_senha,visao:"overview"}` → HTTP 200 com dados reais
  (587 admin_upsert_analise, 110 logins, etc.). Painel Engajamento operacional.

## FASE 2 — Produto (próximo sprint)

- [x] **P11 — RESOLVIDO 2026-06-11** — deploy v4.9.105+; `EMAIL_ALERTAS_FAVORITOS` = "1" ativo em produção.
- [ ] **P14** — Gráfico de série temporal por emissor (chaves `serie:` do KV existem, nunca visualizadas)
- [ ] **P15** — Histórico estendido na timeline (3 meses via `op=historico_emissor`, só mudança de frontend)

## TÉCNICAS — Backlog

- [ ] **T11** — Cache inteligente de análise recente (`radar:analise:{empresa}`, TTL 4-6h)
- [ ] **T12** — Dedup de requisições concorrentes (lock KV/DO durante cascade)
- [ ] **T13** — Custo por análise logado (tokens + USD por provider via `tel()`)
- [ ] **T14** — Feedback progressivo de análise (SSE/polling de status da cascade)
- [ ] **T15** — Backoff exponencial + timeout individual por provider na cascade

## DÍVIDA TÉCNICA

- [x] **N06** — RESOLVIDO 2026-06-11 — v4.9.105 deployado em produção (Version ID `c8e93a7a`).
- [x] **P11-sec — RESOLVIDO 2026-06-16 (v4.9.115)** — `ADMIN_EMAIL` removido do bundle novo (`var ADMIN_EMAIL=""`) e carregado por `env.ADMIN_EMAIL` em runtime via `aplicarConfigRuntime(env)` para `fetch` e `scheduled`; `NEWSLETTER_DESTINATARIOS` recalculado. Validação: deploy CF Version ID `9583e77a`, `GET /` HTTP 200 `ok:true` `versao:"v4.9.115"` `telemetria:true` `verificador_ok:true`.
- [ ] **N09** — Atualizar `CLAUDE.md` do projeto:
  - Paths `worker/` → `api/`, `index.html` raiz → `app/index.html`
  - Teste padrão: POST anônimo → GET `/` (anônimo retorna 200 agora)
- [ ] **N10** — Atualizar model IDs no Worker:
  - `claude-haiku-4-5-20251001` → `claude-haiku-4-5`
  - `claude-sonnet-4-5-20250929` → `claude-sonnet-4-6`
- [ ] **P18** — Decidir política de tracking de `archive/`, `docs/`, `research/`, `testing/`, `vixradar/`
- [x] **Git — item stale reclassificado e resolvido 2026-06-16** — branch `audit/reconcile-prod-2026-06-01` não existe localmente; reconciliação foi feita em `main`. `main` pushado para `origin/main` até commit `b5e1c7c`.
- [x] **Drift de artefato do Worker — RECONCILIADO** (2026-06-11). Snapshot de prod puxado
  via MCP comparado com `api/v4.9.102.js`: VEREDICTO equivalentes (só build/minificação
  difere; prod NÃO tem código a mais). Repo é base segura para editar. Snapshot gitignorado
  (`api/_prod_snapshot_*.js`). Ressalva: ambos são bundles minificados, sem fonte hand-authored.

## Atualização 2026-06-18 (hygiene pós-auditoria 24)

- [x] **ROUTINE_API_KEY rotacionada** — 2026-06-18; chave antiga 403; rotinas + `replay-falhas.ps1` atualizados
- [x] **Worker v4.9.141 em produção** — CVM dates + SEC hardening; CI `EXPECTED_WORKER=v4.9.141`
- [x] **Deliverability email** — RESOLVIDO 2026-06-17 (SPF/DMARC; ver nota 17)
- [x] **CI canonical-test** — RESOLVIDO 2026-06-11 (P05); alinhado v4.9.141 em 2026-06-18
- [x] **`.claude/settings.local.json`** — allowlist Bash sem refs `routine_key` antiga (2026-06-18)

## Estado em produção (snapshot 2026-06-18)

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.141** (prod = repo) | OK — `verificador_ok:true` |
| Frontend `vixradar.com` | **v201.69** | OK — Admin HEART modular |
| OpenRouter | — | Removido do cascade (v4.9.108+) |
| CI canonical-test | v4.9.141 | OK |
| ROUTINE_API_KEY | rotacionada 2026-06-18 | OK |

## O que foi entregue nesta sessão

- Levantamento de oportunidades T11-T15 / P11-P15
- P12 (Comparar emissores) + P13 (Briefing executivo) implementados em `app/index.html`
- Frontend bumped v201.45 → v201.46 e deployado em produção
- `scripts/deploy-pages.ps1` — deploy repetível sem colar token
- `scripts/setup-deploy-credential.ps1` — configuração/rotação de credencial
- `Obsidian VIX Radar/10 - Oportunidades de Melhoria (2026-06-11).md`
- `Obsidian VIX Radar/11 - Runbook Deploy Cloudflare Pages.md`
- `PENDENCIAS.md` — atualizado com T11-T15 e P11-P15
- **Continuação 2026-06-11 (sessão opus):**
  - Verificação online (Claude in Chrome) de P12/P13 em produção — 5/7 OK
  - Fix v201.47 (seção EWS sempre visível no Briefing) — DEPLOYADO
  - Reconciliação do Worker prod vs repo via MCP — equivalentes
  - P11 implementado (Worker v4.9.103) — DEPLOY PENDENTE de rotação de token + flag
  - Refinamento N01: OpenRouter 402 com saldo $76 (billing, não falta de crédito)
