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

## Versões confirmadas (última sessão: 2026-06-17 — v4.9.134 + v201.63 prod = repo)

**Git:** `origin/main` = `131b1fd` (push 2026-06-17) — commits `83cf9d6` → `462bfa5` → `657b907` → `131b1fd`.

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.134** (prod = repo) | P14 op=serie; bundle versionado; CI alinhado |
| Frontend `vixradar.com` | **v201.63** (prod = repo) | Fix JWT sessão; deploy 2026-06-17T21:26:52Z |
| `ANTHROPIC_API_KEY` | — | ROTACIONADO 2026-06-16 18:22Z — `verificador_ok:true` confirmado |
| Cascade AI | — | Haiku (Pulso manual); Opus (matinal); Sonnet 4.6 (noturno 103/103) |
| vixradar-noturno | — | `listar_todos_emissores` 103/103 → `claude-sonnet-routine` (18h BRT) |
| Cobertura KV | — | **103/103** com `Última análise:` em `dados_para_analise` |

## Pendências abertas (atualizado 2026-06-16 — pós-v4.9.115)

1. ~~**SEGURANÇA** — chave Anthropic exposta em chat 2026-06-16~~ **RESOLVIDO** — rotacionada 2026-06-16 (pós-sessão); `verificador_ok:true` confirmado
2. ~~**CRÍTICO** — OpenRouter 402~~ **RESOLVIDO 2026-06-16** — causa real: `OPENROUTER_API_KEY` no Worker inválida (HTTP 401 na credits API, não 402 de billing). Secret removido via `wrangler secret delete`. Probe agora retorna `sem_chave_openrouter` (gracioso). Cache KV `status_providers` atualiza no próximo cron noturno.
3. ~~**ALTO** — `ADMIN_EMAIL` hardcoded no bundle~~ **RESOLVIDO 2026-06-16** — v4.9.115 usa `env.ADMIN_EMAIL` em runtime; bundle novo não contém e-mail literal em `var ADMIN_EMAIL`.
4. ~~**MÉDIO** — Push do branch `audit/reconcile-prod-2026-06-01` para remote~~ **SUPERADO/RESOLVIDO 2026-06-16** — branch não existe localmente; reconciliação estava em `main`. `main` pushado para `origin/main` até commit `b5e1c7c`.
5. ~~**MÉDIO** — P16~~ **ATIVO v4.9.121** — 16/20 overrides; routine `vixradar-agenda-semanal` registrada (`0 3 * * 1` BRT)
6. ~~**MÉDIO** — P17~~ **ATIVO v4.9.121** — semanal → 16 aprovados `frequencia=semanal`; PILOTO removido; `RELATORIO_DIARIO_ENABLED=1`
7. **MÉDIO** — Deliverability SPAM — v4.9.131 corrigiu one-click; DNS ainda `p=none` + SPF `~all` (manual no dashboard); inbox test pendente; envio massa **sex 19/06 18h30**

**Resolvidos anteriormente:** ~~cron `0 2 * * *` duplicado~~ (v4.9.109 — `0 4 * * *`); ~~`CLOUDFLARE_API_TOKEN` secret~~ (2026-06-11); P05* CI; P11 alerta favorito; N06 CRITICIDADE_SETOR.

**Resolvidos nesta sessão (2026-06-11):** P05* CI corrigido; fix Briefing EWS (v201.47, deployado); reconciliação Worker; P11 implementado (v4.9.103→v4.9.104); N06 display corrigido (v4.9.104); Engajamento erro melhorado (v201.48); validação online completa (Claude in Chrome, 02:07 BRT — nenhuma regressão); N06 cálculo corrigido (v4.9.105, `CRITICIDADE_SETOR` alinhado ao `EMISSORES_MAP`, teste 13/13 PASS); credenciais atualizadas (`memory/credenciais.md`).

Ver lista completa em `memory/sessao-2026-06-11-pendencias.md`.

## Skills VIX Radar (instaladas 2026-06-16)

| Skill | Invocação | Categoria | Status |
|---|---|---|---|
| `vix-radar-session-briefing` | `/vix-radar-session-briefing` | Master briefing (versões + health + pendências) | ✅ `~/.claude/skills/vix-radar-session-briefing/` |
| `vix-radar-next-steps` | `/vix-radar-next-steps` | Product advisor (P0/P1/P2 + quick wins) | ✅ `~/.claude/skills/vix-radar-next-steps/` |
| `tech-debt-audit` | `/tech-debt-audit` | Dívida técnica + arquitetura (9 dimensões, file:line) | ✅ `~/.claude/skills/tech-debt-audit/` |
| `insecure-defaults` | `/insecure-defaults` | Segurança (JWT fail-open, CORS, hardcoded creds, debug) | ✅ `~/.claude/skills/insecure-defaults/` |
| `workers-best-practices` | `/workers-best-practices` | Cloudflare Workers anti-patterns (wrangler, bindings) | ✅ pré-instalada |
| `vix-radar-audit` | `/vix-radar-audit` | Auditoria completa multi-camada (readonly) | ✅ `~/.claude/skills/vix-radar-audit/` |

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
