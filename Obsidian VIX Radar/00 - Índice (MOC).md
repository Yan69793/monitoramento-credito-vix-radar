# VIX Radar — Índice (MOC)

Vault recriado em 2026-06-07 durante auditoria completa.
Vault anterior estava ausente da nova estrutura de diretórios (`api/`, `app/`).

## Notas ativas

- [[03 - Estado de Produção]]
- [[04 - Auditoria 2026-06-07]]
- [[07 - Evolução do Sistema de Classificação e Prompts]]
- [[08 - Análise de Risco e Arquitetura de Confiabilidade]]
- [[09 - Auditoria 2026-06-10 (Pendências)]]
- [[10 - Oportunidades de Melhoria (2026-06-11)]]
- [[11 - Runbook Deploy Cloudflare Pages]]
- [[13 - Metodo de Vistoria Operacional]] — skill `/vix-radar-audit`
- [[14 - Auditoria Completa 2026-06-16]]
- [[15 - Auditoria Completa 2026-06-16 (v2)]]
- [[16 - Design P16 P17 Agenda e Relatorio]]
- [[17 - Email Relatorio e Deliverability 2026-06-17]]
- [[18 - Auditoria Completa 2026-06-17]]
- [[19 - Auditoria Completa 2026-06-17 (pós v201.63)]]
- [[20 - Monitoramento Loop 2026-06-17]]
- [[21 - Auditoria Completa 2026-06-18]]
- [[24 - Auditoria Completa 2026-06-18 (pós v4.9.141)]]
- [[25 - Auditoria Completa 2026-06-30]] — ⛔ DRIFT prod v4.9.143 vs repo v4.9.141
- [[22 - Sprite Health Check]] — skill `/sprite-health`, VM `site`
- [[23 - Admin HEART Modular v201.66]] — painel admin modular Fase 1
- [[23 - Incidente 2026-06-18 Verificador reprova matinal]] — gate verdade graduada (Onco/Kora)

## Versões confirmadas (última sessão: 2026-06-18 — v4.9.141 + v201.69 prod)

> ⛔ **2026-06-30 — DRIFT ATIVO:** produção em **v4.9.143** (CI canonical-test run #59, 2026-06-29T20:11Z), repo em **v4.9.141**. Bundles v4.9.142/143 **não commitados**. P0 reconciliar. Ver [[25 - Auditoria Completa 2026-06-30]].

**Git:** `main` com v4.9.140/141 commitados; `ROUTINE_API_KEY` rotacionada 2026-06-18.

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.141** (prod) | CVM dates + SEC hardening; health `ok:true`, `verificador_ok:true`; CI `EXPECTED_WORKER=v4.9.141` |
| Frontend `vixradar.com` | **v201.69** (prod = repo) | Admin HEART modular; senha admin em `sessionStorage` |
| `ANTHROPIC_API_KEY` | — | ROTACIONADO 2026-06-16 18:22Z — `verificador_ok:true` confirmado |
| Cascade AI | — | Haiku (Pulso manual); Opus (matinal); Sonnet 4.6 (noturno 103/103) |
| vixradar-noturno | — | `listar_todos_emissores` 103/103 → `claude-sonnet-routine` (18h BRT) |
| Cobertura KV | — | **103/103** com `Última análise:` em `dados_para_analise` |

## Pendências abertas (atualizado 2026-06-18 — pós-v4.9.141)

1. ~~**SEGURANÇA** — chave Anthropic exposta em chat 2026-06-16~~ **RESOLVIDO** — rotacionada 2026-06-16 (pós-sessão); `verificador_ok:true` confirmado
2. ~~**CRÍTICO** — OpenRouter 402~~ **RESOLVIDO 2026-06-16** — causa real: `OPENROUTER_API_KEY` no Worker inválida (HTTP 401 na credits API, não 402 de billing). Secret removido via `wrangler secret delete`. Probe agora retorna `sem_chave_openrouter` (gracioso). Cache KV `status_providers` atualiza no próximo cron noturno.
3. ~~**ALTO** — `ADMIN_EMAIL` hardcoded no bundle~~ **RESOLVIDO 2026-06-16** — v4.9.115 usa `env.ADMIN_EMAIL` em runtime; bundle novo não contém e-mail literal em `var ADMIN_EMAIL`.
4. ~~**MÉDIO** — Push do branch `audit/reconcile-prod-2026-06-01` para remote~~ **SUPERADO/RESOLVIDO 2026-06-16** — branch não existe localmente; reconciliação estava em `main`. `main` pushado para `origin/main` até commit `b5e1c7c`.
5. ~~**MÉDIO** — P16~~ **ATIVO v4.9.121** — 16/20 overrides; routine `vixradar-agenda-semanal` registrada (`0 3 * * 1` BRT)
6. ~~**MÉDIO** — P17~~ **ATIVO v4.9.121** — semanal → 16 aprovados `frequencia=semanal`; PILOTO removido; `RELATORIO_DIARIO_ENABLED=1`
7. ~~**MÉDIO** — Deliverability SPAM~~ **RESOLVIDO 2026-06-17** — DNS `SPF -all` + `DMARC p=quarantine`; inbox test enviado (`relatorio_diario_teste` + `newsletter_teste`); dry-run 15 destinatários; envio massa no cron sexta fechamento B3

**Resolvidos anteriormente:** ~~cron `0 2 * * *` duplicado~~ (v4.9.109 — `0 4 * * *`); ~~`CLOUDFLARE_API_TOKEN` secret~~ (2026-06-11); P05* CI; P11 alerta favorito; N06 CRITICIDADE_SETOR.

**Resolvidos nesta sessão (2026-06-11):** P05* CI corrigido; fix Briefing EWS (v201.47, deployado); reconciliação Worker; P11 implementado (v4.9.103→v4.9.104); N06 display corrigido (v4.9.104); Engajamento erro melhorado (v201.48); validação online completa (Claude in Chrome, 02:07 BRT — nenhuma regressão); N06 cálculo corrigido (v4.9.105, `CRITICIDADE_SETOR` alinhado ao `EMISSORES_MAP`, teste 13/13 PASS); credenciais atualizadas (`memory/credenciais.md`).

**Resolvidos 2026-06-18 (auditoria 24):**
- ~~**v4.9.141** em produção~~ — CVM dates + SEC hardening; CI `EXPECTED_WORKER=v4.9.141`
- ~~**ROUTINE_API_KEY rotacionada**~~ — chave antiga retorna 403; rotinas scheduled-tasks + `replay-falhas.ps1` atualizados
- ~~**P1** — Limpar `settings.local.json` (refs `routine_key` antiga na allowlist Bash)~~
- ~~**P2** — Nota 13: `tel_test` documentado com `admin_senha`~~

**Abertas (hygiene + produto — 2026-06-18):**
1. **P2** — `admin_mercado`: refactor auth POST (senha ainda em query string GET)
2. **P2** — Watchdog `stale_count:1` (heartbeats)
3. **P2** — Admin HEART Fase 2b — extração completa do monólito (`vr-admin-shared`)
4. **P3** — `admin_corrigir_datas_cvm_kv` em lote pós-matinal
5. **P3** — Incidente matinal 18/06: reanálise Onco/Kora/GPA com fonte CVM primária ([[23 - Incidente 2026-06-18 Verificador reprova matinal]])
6. **Backlog** — Expor `rejeitados` + `veredicto.motivo` no retorno de `receber_analise`
7. **Backlog** — `scheduled-tasks/backups/` com prompts de chave antiga (não runtime, limpar)
8. **Backlog** — N09/N10 (`CLAUDE.md` paths; model IDs no Worker)

Ver lista completa em `memory/sessao-2026-06-11-pendencias.md`.

## Skills VIX Radar (consolidadas no repo 2026-06-18)

Fonte única: `.claude/skills/` no projeto (versionadas no git). Global `~/.claude/skills` é fallback legado.

| Skill | Invocação | Categoria | Status |
|---|---|---|---|
| `vix-radar-session-briefing` | `/vix-radar-briefing` | Master briefing (versões + health + pendências) | ✅ `.claude/skills/vix-radar-session-briefing/` |
| `vix-radar-next-steps` | `/vix-radar-next-steps` | Product advisor (P0/P1/P2 + quick wins) | ✅ `.claude/skills/vix-radar-next-steps/` |
| `vix-radar-audit` | `/vix-radar-audit` | Auditoria completa multi-camada (readonly) | ✅ `.claude/skills/vix-radar-audit/` |
| `workers-best-practices` | `/workers-best-practices` | Cloudflare Workers anti-patterns | ✅ `.claude/skills/workers-best-practices/` |
| `wrangler` | `/wrangler` | Deploy/bindings/cron Workers | ✅ `.claude/skills/wrangler/` |
| `sprite-health` | `/sprite-health` | Health check via VM Sprite `site` | ✅ `.claude/skills/sprite-health/` |
| `tech-debt-audit` | `/tech-debt-audit` | Dívida técnica (9 dimensões) | ⚠️ só global `~/.claude/skills/` |
| `insecure-defaults` | `/insecure-defaults` | Segurança JWT/CORS/hardcoded | ⚠️ só global `~/.claude/skills/` |

---

## Integração de arquivos recuperados (2026-06-10)

Arquivos recuperados do pendrive SanDisk via PhotoRec e integrados ao vault:

| Arquivo recuperado | Nota gerada | Conteúdo |
|---|---|---|
| `prompt-analista-senior-credito-privado.txt` | Nota 07 | Sistema de classificação ~v4.6 (3 tiers, Gemini direto) |
| `prompt-classificacao-eventos-ruido-eco.txt` | Nota 07 | Sistema de classificação ~v4.8 (4 tiers, ECO, OR+Gemini) |
| `doc-analise-risco-fallback-providers.txt` | Nota 08 | Matriz de risco, pipeline validação, observabilidade, deploy governance |
| `worker-debug-matcher-fontes-v4.9.69.txt` | — | Fragmento de CLAUDE.md; conteúdo já coberto, não integrado separadamente |
| `radar-threads-pedro-yan-fev-2026.txt` | — | **EXCLUÍDO — LGPD.** Contém dados pessoais de clientes. Não integrado. |
