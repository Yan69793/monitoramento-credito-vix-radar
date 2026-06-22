# Auditoria Geral — VIX Radar (2026-06-22)

Skill: `/vix-radar-general-audit` — readonly. Base: Worker v4.9.143 (prod = repo), Frontend v201.69.

## Veredito

Sistema saudável. Health `GET /` HTTP 200, `v4.9.143`, `kv/rate_limiter/telemetria:true`, `verificador_ok:true`, `providers_configurados:2/2` (evidência 2026-06-22T07:20:27Z).

F1 (drift `localStorage`→`sessionStorage` nos módulos admin) **resolvido no working tree mas não commitado**. Nenhum P0. Dois novos achados P2/P3 (FERIADOS 2028, model_escalation stale).

## Achados novos

| ID | Sev | Área | Achado | Evidência |
|----|-----|------|--------|-----------|
| N12 | P2 | Backend | `FERIADOS_B3_2028` ausente em `ehDiaPregaoB3`; cobertura só 2026–2027 | `v4.9.143.js:10132–10201` |
| B-MID2 | P3 | Modelos | `VERIFICADOR_CONFIG.model_escalation = "claude-sonnet-4-5-20250929"` stale (sistema usa Sonnet 4.6) | `v4.9.143.js:9584` |
| P20 | P3 | Hygiene | `api/package.json` com `express@^5.2.1` e `openai@^6.33.0` sem uso pelo Worker | `api/package.json` |
| D2 | P3 | Docs | Cabeçalho `wrangler.toml:1` diz `main = v4.9.120`; correto é `v4.9.143` | `api/wrangler.toml:1` |

## Achados reconfirmados (herdados)

| ID | Sev | Status | Observação |
|----|-----|--------|------------|
| A1 | ALTO | Aberto | `verificador_ok: !!env.ANTHROPIC_API_KEY` — presença de chave, não ping vivo |
| A2 | ALTO | Aberto | `receber_analise` pode retornar `ok:true, n_eventos:0` silenciosamente |
| P-WD | P2 | Aberto | Watchdog `stale_count:1` — não investigado nesta passada |
| P-RH | P2 | Aberto | `deploy_zip/admin/*.js` modificados não commitados + muitos untracked |
| P10 | P3 | Aberto | `admin_senha !== ADMIN_PASSWORD` não constant-time (~20 endpoints) — risco prático baixo em Workers |
| A11Y | P3 | Aberto | Sem passe browser/teclado para foco/trap em dialogs |

## F1 resolvido (confirmado)

`app/deploy_zip/admin/vr-admin-shared.js` L96/104 e `vr-admin-modules.js` L21 usam `sessionStorage.getItem("radar_admin_senha")`. Deploy Pages `0f72c04b` (2026-06-21) está em produção. `radar_jwt`/`HEART_HIST_KEY` seguem `localStorage` (por design).

Pendente: commit isolado dos arquivos `deploy_zip/admin/*.js`.

## Conformidade regras invioláveis

- `strong { font-weight:600 }` sem `color` global ✅
- `carregarEstadoMultiSemana(env,5)` em todos os endpoints multi-semana ✅
- `RADAR_USAGE_EVENTS` binding declarado ✅
- `receber_analise` protegido por `ROUTINE_API_KEY` ✅
- `ADMIN_EMAIL` via `env` ✅
- Health sem dependência OpenRouter ✅

## Lacunas

- `admin_verificar_evento` + leitura quarantine KV não executados (readonly, sem credencial).
- Ingestão E2E (pipeline completo) não validada.
- Lighthouse/Core Web Vitals não medidos.
- `email_modo_teste` — estado atual não verificado.

## Próximos passos

| P | Ação |
|---|------|
| P1 | Commitar `deploy_zip/admin/*.js` em commit isolado (F1 fix) |
| P1 | Próxima sessão com credencial: `admin_verificar_evento` + quarantine KV do dia (A1) |
| P2 | Investigar watchdog `stale_count:1` (P-WD) |
| P2 | Triagem working tree (P-RH) |
| P3 | `VERIFICADOR_CONFIG.model_escalation` → `claude-sonnet-4-6` na próxima edição de bundle |
| P3 | Adicionar `FERIADOS_B3_2028` antes do fim de 2027 |
| P3 | Remover `express`/`openai` de `api/package.json` |
| P3 | Atualizar cabeçalho `wrangler.toml` |
