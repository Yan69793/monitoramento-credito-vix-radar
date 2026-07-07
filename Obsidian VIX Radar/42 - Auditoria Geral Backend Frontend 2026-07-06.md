# Auditoria Geral — VIX Radar (2026-07-06)

Skill: `/vix-radar-general-audit`. Readonly. Complementa a nota [[41 - Auditoria Completa 2026-07-06]] (operacional/incidente).

## Veredito

Sistema **saudável**. Backend v4.9.146 com bindings, observabilidade e auth fail-closed corretos; frontend v201.69 sem drift de versão; sem secrets versionados. Dois achados P2 de drift/governança (F1 admin storage não deployado; script de produção untracked) e um P3 de limpeza. Nenhum P0/P1.

## Top riscos

| Sev | Área | Achado | Evidência | Ação |
|---|---|---|---|---|
| P2 | Frontend/Segurança | **F1 — admin storage drift**: prod serve `localStorage` p/ senha admin; repo já migrou p/ `sessionStorage` (não deployado no Pages) | prod `radar-admin-auth.js`: `const _pw=localStorage.getItem("radar_admin_senha")`; repo `app/admin/*.js` + `app/deploy_zip/admin/*.js`: 5× `sessionStorage`, 0× `localStorage` | Deploy Pages `app/deploy_zip/` (com autorização) |
| P2 | Governança | Script de produção **untracked**: `scripts/run_vixradar_verificacao_async.ps1` (drenador da fila de verificação, citado no CLAUDE.md) não está no git nem no `.gitignore` | `git check-ignore` → não ignorado; `git status` → `??` | `git add` + commit |
| P3 | Higiene | Imagem solta na raiz: `fechamento-20260703-full.jpeg` | `git status` `??` | mover/remover |

## Backend

- **Bindings OK:** `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS` declarados em `api/wrangler.toml`; `[observability]` presente.
- **Health real:** `GET /` `ok:true`, `versao:v4.9.146`, `kv/rate_limiter/telemetria:true`, `verificador_ok:true`, `providers 2/2`. Não mascara falha (verificador migrou p/ assinatura em v4.9.146; `verificador_ok` reflete fila atrasada >12h).
- **Auth fail-closed:** POST anônimo → HTTP 401.
- **Ingestão validada por cobertura:** run noturno canônico entregou 103/103 com conteúdo real (`stale_24h:0`, `max_stale:1.5h`) — `receber_analise` não gravou `sem_eventos` falso em massa. Lacuna: não inspecionei `v4.9.146.js` linha a linha nem rodei smoke de `receber_analise`.
- **Sem secrets versionados:** `git grep` p/ `ROUTINE_KEY=`, `sk-ant-`, `AIza…` = zero em arquivos tracked. `scripts/azul_payload.json` (AZ1 da nota 38) **não existe mais no git** → AZ1 resolvido. `ROUTINE_KEY` vive só em `scheduled-tasks/…/SKILL.md` (fora do repo).

## Frontend

- **Versão sem drift:** `app/index.html` e `app/deploy_zip/index.html` ambos `CACHE_VERSION="v201.69"`; prod `version.json v201.69`.
- **deploy_zip sincronizado** com `app/` (CACHE_VERSION idêntico).
- **CSS `strong` global limpo:** todas as regras com `color` têm seletor específico (`.ph-card strong`, `.ph-pill strong`, `.ews-disclaimer strong`, `.com-author-label strong`); nenhuma regra global `strong { color }`. Conforme regra inviolável do CLAUDE.md.
- **F1 (ver Top riscos):** repo consistente em `sessionStorage`, mas **produção ainda em `localStorage`** — o fix nunca foi ao Pages. Risco: senha admin persiste além do fechamento da aba, superfície maior a exfiltração via XSS. Defense-in-depth, P2.

## Segurança, perf e a11y

- **Segurança:** sem secret exposto no repo; auth fail-closed; F1 é o único item aberto (P2, defense-in-depth).
- **Perf/a11y:** não medidos nesta passada (sem browser/Lighthouse). Lacuna registrada — sem regressão de versão frontend desde a última medição (v201.69 estável).

## Próximos passos

1. **P2** — Deploy Pages do fix admin `sessionStorage` (fecha F1 em prod): `npx wrangler pages deploy ./app/deploy_zip --project-name=radar-credito`. Requer autorização + token Cloudflare.
2. **P2** — `git add scripts/run_vixradar_verificacao_async.ps1` + commit (evitar perda da cópia única).
3. **P3** — Remover/mover `fechamento-20260703-full.jpeg` da raiz.
4. **Lacuna** — Medir perf/a11y em navegador na próxima auditoria com browser; smoke de `receber_analise` se houver dúvida de ingestão.
