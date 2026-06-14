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

## Versões confirmadas (última sessão: 2026-06-14 — deploy v4.9.109)

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.109** (prod = repo) | DEPLOYADO 2026-06-14 — Version ID 089135fe |
| Frontend `vixradar.com` | **v201.51** (prod = repo) | DEPLOYADO 2026-06-13 02:20Z |
| OpenRouter | — | **Removido do cascade** — saldo -$0.20; OR não mais usado para análise |
| Cascade AI | — | claude-haiku-analise apenas (Pulso manual); Claude Opus via rotinas agendadas |
| vixradar-noturno | — | top_n:103 confirmado — cobre todos os 103 emissores por staleness/EWS |

## Pendências abertas (atualizado 2026-06-14 — deploy v4.9.109)

1. **CRÍTICO** — OpenRouter 402 **com saldo $76** (billing/add-on) — investigar no painel; sistema em haiku-only
2. ~~**CRÍTICO** — Documentar ou remover cron `0 2 * * *`~~ — **RESOLVIDO 2026-06-14**: cron `0 4 * * *` = `agendaBuildPersistir` (calendário 90 dias → KV `agenda:eventos:v1`, TTL 3d)
3. ~~ALTO — `wrangler secret put CLOUDFLARE_API_TOKEN`~~ — **RESOLVIDO** (2026-06-11, token `vixradar-analytics-engine-read`, Account Analytics:Read, HTTP 200 c/ dados reais)
4. ALTO — `ADMIN_EMAIL` hardcoded no bundle → mover para `env.ADMIN_EMAIL`
6. MÉDIO — `CLAUDE.md` com paths incorretos (`worker/` → `api/`, teste POST → GET /)
7. MÉDIO — Push do branch `audit/reconcile-prod-2026-06-01` para remote
8. MÉDIO — P16: Agenda de Divulgação semanal (design pendente — ver memory)
9. MÉDIO — P17: Relatório diário automático (design pendente)

**Resolvidos nesta sessão (2026-06-11):** P05* CI corrigido; fix Briefing EWS (v201.47, deployado); reconciliação Worker; P11 implementado (v4.9.103→v4.9.104); N06 display corrigido (v4.9.104); Engajamento erro melhorado (v201.48); validação online completa (Claude in Chrome, 02:07 BRT — nenhuma regressão); N06 cálculo corrigido (v4.9.105, `CRITICIDADE_SETOR` alinhado ao `EMISSORES_MAP`, teste 13/13 PASS); credenciais atualizadas (`memory/credenciais.md`).

Ver lista completa em `memory/sessao-2026-06-11-pendencias.md`.

## Integração de arquivos recuperados (2026-06-10)

Arquivos recuperados do pendrive SanDisk via PhotoRec e integrados ao vault:

| Arquivo recuperado | Nota gerada | Conteúdo |
|---|---|---|
| `prompt-analista-senior-credito-privado.txt` | Nota 07 | Sistema de classificação ~v4.6 (3 tiers, Gemini direto) |
| `prompt-classificacao-eventos-ruido-eco.txt` | Nota 07 | Sistema de classificação ~v4.8 (4 tiers, ECO, OR+Gemini) |
| `doc-analise-risco-fallback-providers.txt` | Nota 08 | Matriz de risco, pipeline validação, observabilidade, deploy governance |
| `worker-debug-matcher-fontes-v4.9.69.txt` | — | Fragmento de CLAUDE.md; conteúdo já coberto, não integrado separadamente |
| `radar-threads-pedro-yan-fev-2026.txt` | — | **EXCLUÍDO — LGPD.** Contém dados pessoais de clientes. Não integrado. |
