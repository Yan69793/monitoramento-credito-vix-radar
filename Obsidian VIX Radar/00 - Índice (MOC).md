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
- [[13 - Metodo de Vistoria Operacional]]
- [[14 - Auditoria Completa 2026-06-16]]

## Versões confirmadas (última sessão: 2026-06-16 — auditoria + v4.9.112 + skills)

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.113** (prod = repo) | DEPLOYADO 2026-06-16 — Version ID de4fa8f8; hotfix regressão admin_mercado |
| Frontend `vixradar.com` | **v201.51** (prod = repo) | DEPLOYADO 2026-06-13 02:20Z |
| `ANTHROPIC_API_KEY` | — | ROTACIONADO 2026-06-16 18:22Z — `verificador_ok:true` confirmado em v4.9.112 |
| Cascade AI | — | claude-haiku-analise apenas (Pulso manual); Claude Opus via rotinas agendadas |
| vixradar-noturno | — | top_n:103 confirmado — cobre todos os 103 emissores por staleness/EWS |

## Pendências abertas (atualizado 2026-06-16 — pós-v4.9.112)

1. ~~**SEGURANÇA** — chave Anthropic exposta em chat 2026-06-16~~ **RESOLVIDO** — rotacionada 2026-06-16 (pós-sessão); `verificador_ok:true` confirmado
2. **CRÍTICO** — OpenRouter 402 **com saldo $76** (billing/add-on) — investigar no painel; sistema em haiku-only
3. **ALTO** — `ADMIN_EMAIL` hardcoded no bundle → mover para `env.ADMIN_EMAIL` (v4.9.113+)
4. **MÉDIO** — Push do branch `audit/reconcile-prod-2026-06-01` para remote
5. **MÉDIO** — P16: Agenda de Divulgação semanal (design pendente — ver memory)
6. **MÉDIO** — P17: Relatório diário automático (design pendente)

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
