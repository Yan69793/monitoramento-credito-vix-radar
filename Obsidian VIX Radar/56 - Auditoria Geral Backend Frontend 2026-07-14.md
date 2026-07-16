# Auditoria Geral — VIX Radar (2026-07-14)

Auditoria de engenharia multi-camada: backend Worker, frontend Pages, segurança, performance, acessibilidade, confiabilidade e produto/domínio. 3 agentes em paralelo + checks manuais.

## Veredito

Sistema **funcional mas com débito técnico acumulado**. v4.9.156 deployado corrige 16 bugs do loop SKIP do setor financeiro. 2 P0 críticos permanecem: TOKENEST1 (estimativa de tokens 6x abaixo do real) e PRNG1 (Math.random em decisão de segurança). 4 fixes de v4.9.151/v4.9.152 codificados mas não deployados. Frontend sem drift de deploy, mas com XSS potencial em dados de IA e sem CSP. Noturna de hoje em execução (disparo manual) — setor Financeiro sendo escaneado pela primeira vez em meses.

---

## Top riscos

| Sev | Área | Achado | Evidência | Ação |
|---|---|---|---|---|
| **P0** | Rotina | TOKENEST1: estimativa 40k/emissor vs real 241k/emissor (6x). Matinal 14/07: 966k tokens para 4/15 emissores | `matinal_metrics_20260714.json` | Recalibrar $TokenPerEmitterSonnet >= 80k |
| **P0** | Worker | PRNG1: Math.random() em deveVerificar (já foi "corrigido" em v4.9.112, regrediu) | `v4.9.156.js:9805` | Trocar por crypto.getRandomValues |
| **P0** | Worker | RACEKV1: persistirResultadoCompartilhado sem lock KV | `v4.9.156.js:7507-7631` | DO serializer por semana (design nota 54) |
| **P0** | Seg | Token CF vivo `f3e3d6b4...` após remoção do secret do Worker | Nota 03 (14/07 manhã) | Operador revogar no painel CF |
| **P1** | Frontend | 401 em qualquer endpoint derruba sessão global (sem debounce/retry) | `app/index.html:5538,5890,6033` | Adicionar retry + debounce no poll |
| **P1** | Frontend | XSSEVT1: innerHTML com dados de IA sem esc() em renderEventoCard/alertas_mercado | `app/index.html:~24774` (bundled) | Aplicar esc() + avaliar CSP |
| **P1** | Worker | admin_senha embedada em HTML da página admin_mercado | `v4.9.156.js:11853-11855` | Migrar para JWT |
| **P1** | Worker | health-dashboard aceita senha via GET querystring | `v4.9.156.js:5160` | Migrar para POST+JWT |
| **P1** | Worker | 4 fixes codificados (HDASH1, RLADMIN1, ANOMPROMO1) não deployados | v4.9.151/v4.9.152 | Merge no bundle corrente |
| **P1** | Worker | MIG1 + CHUNK1: fixes no disco há 30h+ sem commit | `git diff --stat scripts/` | Commitar |

---

## Backend

### wrangler.toml
- `main=v4.9.156.js`, `compatibility_date=2026-06-16`, `nodejs_compat` — OK
- Bindings: KV + DO + Analytics Engine — todos declarados e ativos
- `[observability]` enabled (`head_sampling_rate=1`) — OK
- 4 crons configurados — OK
- `VARREDURA_CRON_AI_ENABLED=false` — confirmado
- ADMIN_EMAIL hardcoded em `[vars]` — P2 (deveria ser secret)
- ROUTINE_API_KEY não declarado (setado via `wrangler secret put`) — OK

### Segurança de código
- Nenhum secret hardcoded no bundle (JWT, API keys, passwords — todos via env)
- JWT HS256 com SubtleCrypto, `verificarJWT` em ~40 call sites — OK
- CORS com allowlist (4 origens), sem wildcard — OK
- `innerHTML` zero no Worker bundle — OK
- Comparação de admin_senha com `!==` (não constant-time) em ~60 call sites — P2
- Rate limiter fail-open (3 cenários: binding ausente, DO erro, body malformed) — P2
- 5 catch blocks vazios sem logging — P2
- `console.log` com emails de usuários (5 instâncias) — P2

### Confiabilidade
- `persistirResultadoCompartilhado`: sem lock KV (RACEKV1) — P0, design pronto
- `verificarDisjuntorDiario`: fail-open em erro de KV — P2
- `ctx.waitUntil` usado corretamente com error handlers — OK
- `carregarEstadoMultiSemana` em 23 call sites — OK
- `sem_eventos` derivação correta (tier-aware, INCONCLUSIVO preserva dados) — OK
- `receber_analise` com case-insensitive canonicalization (CASEKEY1) — OK
- Telemetria abrangente: 50+ eventos (registro, login, análise, admin, custos) — OK
- 283 catch blocks em 16k linhas (~1.7%) — aceitável para este escopo

---

## Frontend

### Deploy e versões
- `app/index.html` ≡ `app/deploy_zip/index.html` (binary-identical) — OK
- `version.json`: v201.75 (app + deploy_zip idênticos) — OK
- Admin scripts: `?v=201.69` (levemente atrás do main v201.75, intencional)

### CSS
- Regra global `strong`: `font-weight:600` sem `color` — OK
- Overrides scoped com color (.ph-card, .ews-disclaimer, .com-author-label) — OK
- `--text-mute` (#4E6070 em #001020, 3.1:1) falha WCAG AA — P2
- Textos com opacidade baixa (footer, links auxiliares) falham WCAG AA — P2

### Auth e requests
- JWT em `Authorization: Bearer` — OK
- Admin senha em `sessionStorage`, POST body (não URL) — OK
- **401 mata sessão global sem debounce** — P1 (poll de 60s pode derrubar usuário ativo)
- `postAdmin` duplicado em modules.js e shared.js — P3

### UX
- Loading states: skeletons com shimmer, spinners — OK
- Empty states: 11 padrões cobrindo todos os painéis — OK
- Error states: estruturados com `.erro-banner`, `.com-status-erro` — OK
- Mobile: 40+ breakpoints, safe-area, drawer navigation — OK
- Dark mode: `prefers-color-scheme:dark` — OK
- `prefers-reduced-motion` em 6+ locais — OK

### XSS
- v201 feed module: `innerHTML` com dados de IA sem `esc()` — P1 (XSSEVT1)
- Intel module: `_mkEl` + `createTextNode` (XSS-safe) — OK
- Admin modules: função `esc()` presente e usada — OK
- CSP: omitida intencionalmente (_headers) — P2 (sem barreira de contenção)

### Performance
- HTML: 694KB (SPA monolítico) — P3
- Google Fonts: render-blocking (sem padrão `media="print" onload`) — P2
- Admin scripts: síncronos no final do body — P3 (não bloqueiam first paint)
- `version.json`: cache-bust com `?t=Date.now()` — OK
- 60s poll sem guarda anti-overlap — P2

### Acessibilidade
- 25+ `aria-label`, 4 `aria-labelledby`, roles corretos — OK
- `tabindex`: apenas valores 0 (sem manipulação manual) — OK
- Esc key handling para modais — OK
- Focus trap: ausente em modais (`role="dialog"`) — P2 (WCAG 2.4.3)
- Auto-focus em login, ausente em admin overlay — P3

---

## Produto/Domínio

### Cobertura
- EMISSORES_LISTA: 103/103 — OK
- SETOR_DE_EMPRESA: 103/103 (100%) — OK
- CRITICIDADE_SETOR: 13/13 setores (100%) — OK
- Setor Financeiro (9 emissores): todos LIGHT ou AUDIT na noturna de hoje — OK

### Materialidade
- `_classificarMaterialidadeOperacional`: correto (FIN1 presente) — OK
- `_temEventoMaterialRecente`: date windows corretos — OK
- `enriquecerEvento`: setorWeight + materialidade clamp — OK

### Rotinas
- Noturna 14/07 em execução: 45/103 (44%), 159k tokens, 2 CRITICOS
- Matinal 14/07: TOKENEST1 (966k tokens, 4/15, 11 deferred)
- Verificação async: fila vazia, saudável

### Pendências cross-reference
- 4 fixes de v4.9.151/v4.9.152 não deployados — P1
- MIG1 + CHUNK1 + RETRYDROP1: no disco, não commitados — P1
- XSSEVT1, CSP, focus trap, SPF1: abertos — P1/P2
- RACEKV1: design pronto, deploy pendente — P0

---

## Próximos passos

| Pri | Ação |
|---|---|
| **P0** | Recalibrar $TokenPerEmitterSonnet para 80k+ nos scripts matinal/noturno |
| **P0** | Trocar Math.random por crypto.getRandomValues em deveVerificar (PRNG1) |
| **P0** | Operador revogar token CF vivo no painel Cloudflare |
| **P1** | Commitar MIG1 + CHUNK1 (5 scripts no working tree) |
| **P1** | Aplicar esc() em renderEventoCard (XSSEVT1) |
| **P1** | Adicionar retry+debounce no 401 handler do frontend |
| **P1** | Merge HDASH1, RLADMIN1, ANOMPROMO1 no bundle corrente |
| **P2** | CSP mínima em staging |
| **P2** | Focus trap em modais |
| **P2** | Corrigir contraste de --text-mute e textos low-opacity |
