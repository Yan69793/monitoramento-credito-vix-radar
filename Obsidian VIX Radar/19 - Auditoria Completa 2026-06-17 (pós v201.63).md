# Auditoria Completa — VIX Radar (2026-06-17)

Data: 2026-06-17T21:30Z | Invocação: `/vix-radar-audit` (readonly)
Escopo: pós-deploy Pages **v201.63** (fix sessão JWT) + Worker prod **v4.9.134**

Método: [[13 - Metodo de Vistoria Operacional]] | Auditoria anterior: [[18 - Auditoria Completa 2026-06-17]]

---

## Síntese executiva

Sistema **saudável e operacional**. Produção: Worker **v4.9.134** (`ok:true`, `telemetria:true`, `verificador_ok:true`, `providers_configurados:"2/2"`) e Pages **v201.63** (apex = www). Auth fail-closed confirmado. Cobertura canônica **103/103** emissores. Incidente Eduardo (logout ~1s) **corrigido** em v201.63.

Drift **documental/CI** (não operacional): `EXPECTED_WORKER` CI ainda v4.9.131; Obsidian/MOC parcialmente defasados; repo **dirty** (v201.63 + wrangler v4.9.134 não commitados).

**Veredito:** operacional. Sem incidente técnico ativo bloqueante.

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker bundle local | v4.9.134 (`api/v4.9.134.js`) | v4.9.134 | Nenhum no deploy ativo ✅ |
| `api/wrangler.toml` main | `v4.9.134.js` | — | Alinhado ✅ |
| Worker git | bundle **gitignored** | — | Não versionado ⚠️ |
| Frontend `app/version.json` | v201.63 | v201.63 | Nenhum ✅ |
| Frontend apex/www | — | v201.63 (`deployed_at: 2026-06-17T21:26:52Z`) | Nenhum ✅ |
| CI `EXPECTED_WORKER` | v4.9.131 | v4.9.134 | **Drift** ⚠️ |
| Git `origin/main` | `131b1fd` | — | Working tree **dirty** (deploy v201.63 local) ⚠️ |
| Obsidian `03 - Estado` Worker | v4.9.131 (tabela) | v4.9.134 | Documentação defasada ⚠️ |

**Health público — evidência bruta (2026-06-17T21:29:41Z):**

`https://radar-credito-api.prospects-intel.workers.dev/` e `https://api.vixradar.com/`:
```json
{"ok":true,"versao":"v4.9.134","ts":"2026-06-17T21:29:41.339Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
```

**Pages `version.json`:**
```json
{"version":"v201.63","deployed_at":"2026-06-17T21:26:52Z"}
```
`Cache-Control: no-cache, no-store, must-revalidate` ✅ | apex = www ✅

---

## Incidentes abertos

| ID | Status | Detalhe |
|---|---|---|
| Sessão expira ~1s (Eduardo) | **RESOLVIDO** | v201.63 — JWT em `?op=state`, `anomalias`, `ews`, favoritos |
| Deliverability e-mail | **PENDENTE** | DMARC `p=none`, SPF `~all`; inbox test pendente ([[17 - Email Relatorio e Deliverability 2026-06-17]]) |

---

## Achados

### CRÍTICO

Nenhum nesta passagem.

### ALTO

Nenhum nesta passagem.

### MÉDIO

1. **CI drift Worker** — `.github/workflows/canonical-test.yml` `EXPECTED_WORKER=v4.9.131`; produção em v4.9.134. Evidência: health `versao:"v4.9.134"` vs CI linha 65.
2. **Documentação defasada** — `00 - Índice (MOC).md` ainda cita v4.9.131 + v201.54; `03 - Estado de Produção` tabela Worker ainda v4.9.131 (frontend já v201.63).
3. **Repo dirty pós-deploy** — `git status`: `app/index.html`, `app/version.json`, `app/deploy_zip/*`, `api/wrangler.toml`, Obsidian modificados; último commit `131b1fd` não inclui v201.63 nem wrangler v4.9.134.
4. **Bundle Worker gitignored** — `api/v4.9.134.js` existe localmente mas não está no git (risco de perda em clone limpo).

### BAIXO

1. **`listar_emissores_prioritarios top_n=103` → 80** — comportamento esperado por staleness baixo pós-varredura; não indica gap de cobertura (documentado em auditorias anteriores).
2. **`tel_test` / `admin_verificar_evento` não exercitados** — exigem `admin_senha`; retorno 403 sem credencial = fail-closed correto.

---

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` health | ✅ 200 | `ok:true`, `versao:v4.9.134`, `telemetria:true`, `verificador_ok:true` |
| `POST {}` anônimo | ✅ 401 | `{"ok":false,"erro":"Autenticação necessária."}` |
| `GET ?op=state` sem JWT | ✅ 401 | idem |
| `GET ?op=anomalias` sem JWT | ✅ 401 | idem |
| CORS preflight vixradar.com | ✅ 204 | `Access-Control-Allow-Origin: https://vixradar.com`, `Allow-Credentials: true` |
| `listar_todos_emissores` | ✅ 103 | `{"ok":true,"total":103,...}` |
| `dados_para_analise` CEMIG | ✅ 200 | `ok:true`, `janela_inicio:2026-05-18`, `cvm_documentos` populado |
| Pages `CACHE_VERSION` | ✅ v201.63 | HTML servido com `CACHE_VERSION="v201.63"` |
| Fix JWT no deploy | ✅ | `deploy_zip/index.html` contém `_authHeadersGet` em `?op=anomalias` e `carregarResultadosCompartilhados` |
| CSS `<strong>` global | ✅ | `app/index.html:2621` — só `font-weight:600`, sem `color` |
| `receber_analise` path | ✅ | `api/v4.9.134.js:14797-14799` — `_raEvs` + `sem_eventos = _raEvs.length === 0` |
| Bindings wrangler | ✅ | `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS`; `[observability] enabled=true` |

---

## Bloco C — Worker (workers-best-practices)

| Item | Status | Evidência |
|---|---|---|
| `observability` | ✅ | `api/wrangler.toml:92-94` |
| Analytics Engine binding | ✅ | `RADAR_USAGE_EVENTS` declarado; health `telemetria:true` |
| Secrets via env | ✅ | `JWT_SECRET`, `ADMIN_PASSWORD`, `ANTHROPIC_API_KEY` — sem fallback `"radar"` no bundle |
| Cron triggers versionados | ✅ | 4 crons em `wrangler.toml:97-102` |
| `receber_analise` ingestão | ✅ | validação antes de persistir; `_last_scanned_at` setado L14806 |

---

## Lacunas

| Item | Motivo |
|---|---|
| `tel_test` write end-to-end | Requer `admin_senha` (não exposta em auditoria readonly) |
| `admin_verificar_evento` Haiku vivo | Idem — 403 sem senha confirma gate, não o verificador |
| `admin_health_check` interno | Idem |
| `receber_analise` smoke POST | Sem payload de teste versionado em `testing/` no repo |
| Playwright UI login E2E | Escopo readonly HTTP; fix v201.63 validado por código + version.json |
| Scan 103/103 `_last_scanned_at` individual | Amostra CEMIG/Petrobras/Vale/Oi via `dados_para_analise` retorna contexto CVM, não snapshot KV completo |

---

## Resolução pós-auditoria (2026-06-17T21:32Z)

| Achado | Status | Evidência |
|---|---|---|
| CI drift v4.9.131 | **RESOLVIDO** | `canonical-test.yml` `EXPECTED_WORKER=v4.9.134` |
| Repo dirty | **RESOLVIDO** | commit `fix: v201.63 JWT + worker v4.9.134 + CI` |
| Bundle gitignored | **RESOLVIDO** | `!api/v4.9.134.js` no `.gitignore` + arquivo versionado |
| Docs defasados | **RESOLVIDO** | MOC + `03 - Estado` atualizados |
| `tel_test` lacuna | **RESOLVIDO** | `ok:true`, `binding_presente:true`, `write_result.ok:true` |
| `admin_verificar_evento` lacuna | **RESOLVIDO** | `ok:true`, verificador ativo (`quarentenados:1` no smoke) |
| `listar_emissores_prioritarios` | **DOCUMENTADO** | nota no `canonical-test.yml` (staleness ≠ gap) |
| `DEVELOPMENT.md` senha stale | **RESOLVIDO** | removido `RadarAdmin@2026`; aponta `memory/credenciais.md` |

## Próximos passos

| Prioridade | Ação |
|---|---|
| **P1** | Eduardo: login de novo (não recadastrar se já aprovado) |
| **P2** | Deliverability: DMARC `p=quarantine`, inbox test pré-envio sexta |