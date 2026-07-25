---
data: 2026-07-25
tipo: auditoria
tags: [vix-radar, auditoria-geral, backend, frontend, drift, seguranca]
status: ativo
---

# Auditoria Geral, VIX Radar, 2026-07-25

Rodada `/vix-radar-general-audit` em modo readonly. Nao reabre itens do `PENDENCIAS.md` (fila zerada desde 24/07). Cruzou `PENDENCIAS.md` antes de auditar.

## Veredito

Nucleo de producao saudavel: Worker v4.9.180, frontend v201.88, health `ok:true` (967ms), bindings kv/rate_limiter/telemetria ok, `verificador_ok:true`, `app/` = `deploy_zip/` sincronizados, POST anonimo 401, anti-enumeracao de login funcional, security headers presentes. Drift documental em 3 pontos (frontend v201.88 nao documentado, notas 65/66 ausentes do MOC, VERSAO3X recorrente no v4.9.181 em working tree). Working tree contem material de apresentacao institucional (Igor/Bradesco BBI) com endpoint `email_enviar` novo, nao deployado, dependente de cron para 27/07 09:57 BRT.

## Top riscos

| Sev | ID | Area | Achado | Evidencia | Acao |
|-----|----|------|--------|-----------|------|
| P1 | DRIFT-FE-67 | Governanca | Frontend v201.88 em producao, documentacao declara v201.87. Commit `38a3722` (AUTHBEARER1) deployado 24/07 22:01Z mas `03 - Estado Atual.md` e `CLAUDE.md` nao foram atualizados. | `curl -s https://vixradar.com/version.json` retorna `v201.88`; `03 - Estado Atual.md` linha 22 declara `v201.87` | Atualizar `03 - Estado Atual.md`, `CLAUDE.md` tabela de producao, e `00 - Indice (MOC).md` |
| P1 | DRIFT-MOC-67 | Governanca | Notas 65 (Auditoria Geral 2026-07-21-tarde) e 66 (Preditivo lab interno 2026-07-21) existem no disco mas estao ausentes do `00 - Indice (MOC).md`. MOC lista auditorias ate a 64. | `ls Obsidian VIX Radar/65*` e `66*` confirmam existencia; MOC linha 39-46 nao as referencia | Adicionar notas 65, 66 e 67 ao MOC |
| P2 | VERSAO3X-RECURRENT-67 | Deploy | v4.9.181.js declara `WORKER_VERSAO = "v4.9.180"`. Mesmo numero de versao com payload diferente (contem endpoint `email_enviar`). Regra "um numero por deploy, nunca reusa" nao foi seguida. Se deployado assim, producao reportaria v4.9.180 mas executaria codigo diferente do v4.9.180 original. | `grep WORKER_VERSAO api/v4.9.181.js` retorna `"v4.9.180"`; `grep email_enviar api/v4.9.181.js` confirma endpoint novo ausente no v4.9.180 original | Bump `WORKER_VERSAO` para "v4.9.181" antes do deploy. Adicionar check no `deploy-worker.ps1`: rejeitar se `WORKER_VERSAO` nao bater com nome do arquivo |
| P2 | CRON-PENDENTE-67 | Confiabilidade | Cron job `7132d3dd` agendado para 27/07 09:57 BRT depende do deploy do v4.9.181. Se o deploy nao ocorrer antes, o `email_enviar` nao existira em producao e o envio falhara. | `memory/2026-07-25-igor-apresentacao.md` linha 24; health confirma Worker em v4.9.180 (sem `email_enviar`) | Deployar v4.9.181 antes de 27/07 09:57 BRT ou reagendar o cron |
| P3 | COMPAT-DATE-67 | Backend | `compatibility_date = "2026-06-16"` (~5 semanas). Workers best practices recomendam manter atualizado. Sem processo de atualizacao periodica. | `api/wrangler.toml` linha 458 | Nao urgente. Atualizar a cada trimestre como rotina. |

## Backend

Worker v4.9.180 em producao (confirmado via health). Bindings no `wrangler.toml`: `RADAR_KV`, `RATE_LIMITER_DO`, `ESTADO_SEMANA_DO`, `RADAR_USAGE_EVENTS` — todos presentes. Route `api.vixradar.com` declarada. Crons ativos (4 triggers). `compatibility_date` 2026-06-16 com flag `nodejs_compat`. `[observability]` habilitado com `head_sampling_rate=1`.

Bundle v4.9.181 em working tree: 842,736 bytes, sintaxe OK (`node --check`), `WORKER_VERSAO = "v4.9.180"` (nao bumpado). Endpoint `email_enviar` (admin): valida `ADMIN_PASSWORD`, sanitiza destinatarios (regex email, cap 25), chama `enviarResend`. Sem call sites no frontend (uso exclusivo admin/cron). Sem risco de seguranca evidente: auth por senha admin, validacao de input, cap de destinatarios.

`ctx.waitUntil` presente no `scheduled()`: `agendaBuildPersistir` + bloco `async` para health check + sweep. Sem floating promises detectadas via inspecao de padrao.

`console.log` com referencia a `OPENROUTER_API_KEY`: so mensagem de circuito `"[CIRCUIT_BREAKER] Sem OPENROUTER_API_KEY, deixando passar"` — nao vaza valor, so cita nome da env var. Nenhum outro log de secret encontrado.

Health publico: `ok:true`, `versao:v4.9.180`, bindings `kv:true, rate_limiter:true, telemetria:true`, `providers_configurados:2/2`, `verificador_ok:true`. Tempo de resposta 967ms. Health nao mascara falhas: `_verificadorRealOk` checa quarentena de 6h (F002 corrigido em v4.9.175), `_filaVerifAtrasada` checa atraso >12h.

POST anonimo retorna 401 (`"Autenticacao necessaria."`). Login com credenciais invalidas retorna 400 generico (`"JSON invalido."`) — anti-enumeracao funcional (ENUM-LOGIN1). Cookie `radar_token` nao e mais setado (COOKIE-CLEAR1). Auth exclusivamente JWT Bearer.

`receber_analise`: sem verificacao direta neste modo readonly. Confirmado via grep que `carregarEstadoMultiSemana(env, 5)` e usado nos endpoints multi-semana.

## Frontend

Producao em v201.88 (AUTHBEARER1: injeta JWT no fetch wrapper, corrigindo regressao do COOKIE-CLEAR1 onde fetchs com `credentials:include` sem Authorization derrubavam a sessao). Confirmado via `version.json` (`deployed_at: 2026-07-24T22:01:35Z`).

`app/` = `deploy_zip/` sincronizados (diff vazio entre `index.html`).

Security headers (confirmados via `curl -I`): `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=()`.

Cache: `Cache-Control: no-cache, must-revalidate` em `/index.html`, `/`, `/version.json`. `no-store` removido (INDEXNOSTORE). `cf-cache-status: DYNAMIC`.

Sem CSP. Decisao documentada em `app/_headers` linha 7-9: "CSP NAO incluida de proposito: o index.html usa scripts/estilos inline pesados; uma CSP restritiva quebraria o app."

CSS `strong`: apenas seletores com escopo (`.ph-metric strong`, `.ph-card strong`, `.ews-disclaimer strong`, `.com-author-label strong`, `.cover-meta strong`, `.disclaimer strong`). Nenhuma regra global `strong { color: ... }`. Conforme politica.

Admin JS (5 modulos em `app/admin/`): `esc()` presente em `vr-admin-shared.js` e `vr-admin-modules.js`. User data (email, nome, status) escapada antes de `innerHTML` — ADMINXSS1/PDFXSS1 mitigados. `S.esc` usado como fallback em `vr-admin-metricas.js` e `vr-admin-engajamento.js`.

Pagina de apresentacao institucional (`/apresentacao`): 21 slides, 64KB, dark luxury theme, publicada em producao (HTTP 308 → 200). Material para Igor Giesteira (Bradesco BBI). Conta demo `demo@vixradar.com` ativa.

## Seguranca, performance e acessibilidade

**Seguranca:** Auth JWT Bearer sem cookie (CSRF mitigado). Rate limit em login/registrar/admin. Anti-enumeracao de usuarios. Senha admin nunca em URL (HDASH1-RES). Secrets rotacionados (Etapa 1 security fix 24/07). Campos `<>` rejeitados no registro (ADMINXSS1). `_headers` com HSTS preload + XFO + XCTO + Referrer-Policy + Permissions-Policy. Unica ausencia: CSP (decisao consciente, nao omissao).

**Performance:** HTML principal ~1MB (single-page app com todos os modulos inline). Cache com `no-cache, must-revalidate` (ETag/304 funcional). Sem medicao de Core Web Vitals em lab (lacuna — requer Playwright ou Lighthouse). `compatibility_date` de 5 semanas (aceitavel).

**Acessibilidade:** Toggles com `role="switch"` + `aria-checked` (TOGGLEA11Y1). Contraste `#8899AA` sobre `#0A1F33` = 6.05:1 (CONTRASTMUTED1). Focus trap em dialogs (FOCUSTRAP1). Lacuna: nao foi feito teste manual de navegacao por teclado nesta auditoria (modo readonly sem browser).

## IA generativa / cascade LLM

Caminho vivo: Claude Haiku (pulso manual) + Haiku/Sonnet (rotinas matinal/noturno) + Sonnet (verificador adversarial). Cobranca por assinatura OAuth (`ANTHROPIC_API_KEY` removida do ambiente do processo filho).

- **LLM01 (Prompt Injection):** VERIFINJ1 aplicado (v4.9.173): campos de evento envelopados em `"""` no prompt do verificador.
- **LLM02 (Sensitive Information):** Nenhum vazamento de secret em logs de prompt/output.
- **LLM03 (Supply Chain):** Modelos fixados por ID (`claude-haiku-4-5-20251001`, `claude-sonnet-4-6`).
- **LLM05 (Output Handling):** Parse com validacao de schema antes de persistir. `receber_analise` diferencia "sem eventos" de "erro de schema" (F002 corrigido).
- **LLM06 (Excessive Agency):** Newsletter com verificacao adicional. Admin actions exigem JWT ou senha.
- **LLM09 (Misinformation):** Verificador adversarial ativo (Sonnet) + amostragem 20% RELEVANTE. Fila `radar:verif_fila:{data}` com DO (VERIFQ-ORFAO1). Dreno pós-noturno 24/07: fila 14, aprovados 13, rejeitados 1, 0 refusals.
- **LLM10 (Unbounded Consumption):** Teto de tokens (500k target, 700k hard). DEDUPFILA1 + SKIP24H + VERIFCACHE1 ativos. `Credit balance is too low` ainda sem guarda automatica (P2 conhecido).

## Proximos passos

1. **P1** — Atualizar documentacao: `03 - Estado Atual.md` (FE v201.88), `CLAUDE.md` (tabela de producao), `00 - Indice (MOC).md` (notas 65, 66, 67).
2. **P2** — Corrigir `WORKER_VERSAO` no bundle v4.9.181.js para "v4.9.181" antes do deploy. Adicionar check de consistencia no `deploy-worker.ps1`.
3. **P2** — Deployar v4.9.181 antes de 27/07 09:57 BRT (cron de envio da apresentacao) ou reagendar o cron.
4. **P3** — Agendar revisao trimestral de `compatibility_date` no `wrangler.toml`.
5. **Lacunas** — Teste de navegacao por teclado no frontend, medicao de Core Web Vitals em lab, teste de carga no `ESTADO_SEMANA_DO`.

## Evidencia bruta (anexo)

- `git status --short`: M MEMORY.md, M api/v4.9.180.js, M api/wrangler.toml, ?? api/v4.9.181.js, ?? app/deploy_zip/apresentacao/, ?? docs/apresentacoes/, ?? memory/2026-07-25-igor-apresentacao.md
- `git log --oneline -30 -- api/*.js api/wrangler.toml app/index.html app/admin`: 30 commits, topo `38a3722 fix(frontend): AUTHBEARER1 (v201.88)`
- `curl -s https://api.vixradar.com/`: `{"ok":true,"versao":"v4.9.180","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"verificador_ok":true}` (HTTP 200, 967ms)
- `curl -s https://vixradar.com/version.json`: `{"version":"v201.88","deployed_at":"2026-07-24T22:01:35Z"}`
- `node --check api/v4.9.181.js`: exit 0
- `diff app/index.html app/deploy_zip/index.html`: sem saida (identicos)
- `grep WORKER_VERSAO api/v4.9.181.js`: `var WORKER_VERSAO = "v4.9.180"`
- `grep email_enviar api/v4.9.181.js`: presente (linha 16128)
- `curl -s -X POST https://api.vixradar.com/ -H "Content-Type: application/json" -d '{"action":"login","email":"teste@teste.com","senha":"123456"}'`: `{"error":"JSON invalido."}` (HTTP 400)
- `curl -s -X POST https://api.vixradar.com/ -H "Content-Type: application/json" -d '{}'`: `{"ok":false,"erro":"Autenticacao necessaria."}` (HTTP 401)
- `curl -sI https://vixradar.com/`: HSTS, XFO, XCTO, Referrer-Policy, Permissions-Policy presentes; Cache-Control `no-cache, must-revalidate`
- `ls api/v4.9.180.js api/v4.9.181.js`: ambos 842,736 bytes, timestamp identico (25/07 02:48)
- `ls Obsidian VIX Radar/65* Obsidian VIX Radar/66*`: existem, ausentes do MOC

---

*Auditoria executada em 2026-07-25 ~15:30 BRT. Modo readonly, zero alteracoes no sistema. Skill `vix-radar-general-audit` revisao 2026-07-21 (matriz + OPENROUTERVIVO).*
