# Auditoria Completa — VIX Radar (2026-06-18)

Data: 2026-06-18T00:50Z | Invocação: `/vix-radar-audit`
Escopo: pós-deploy Worker **v4.9.139** (newsletter direcionada) + Frontend **v201.63** estável

Método: [[13 - Metodo de Vistoria Operacional]] | Auditoria anterior: [[19 - Auditoria Completa 2026-06-17 (pós v201.63)]]

---

## Síntese executiva

Sistema **saudável e operacional**. Produção: Worker **v4.9.139** (`ok:true`, `telemetria:true`, `verificador_ok:true`, `providers_configurados:"2/2"`) e Pages **v201.63**. Auth fail-closed confirmado. Cobertura canônica **103/103** emissores. Verificador Haiku ativo. Telemetria write OK via `tel_test`.

Drift **documental/repo** (não operacional): Obsidian/MOC e `03 - Estado` ainda citam v4.9.134–136; git **dirty** com bundles v4.9.130–139 untracked e `wrangler.toml` em v4.9.139 à frente do último commit (`d61840f` = v4.9.137).

**Veredito:** operacional. Sem incidente técnico bloqueante.

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker bundle local | v4.9.139 (`api/v4.9.139.js`) | v4.9.139 | Nenhum no deploy ativo ✅ |
| `api/wrangler.toml` main | `v4.9.139.js` | — | Alinhado ✅ |
| Worker git | bundle **untracked** (`v4.9.139.js`) | — | Não versionado ⚠️ |
| Frontend `app/version.json` | v201.63 | v201.63 | Nenhum ✅ |
| Frontend apex | — | v201.63 (`deployed_at: 2026-06-17T21:26:52Z`) | Nenhum ✅ |
| CI `EXPECTED_WORKER` (working tree) | v4.9.139 | v4.9.139 | Alinhado localmente ✅ |
| Git `origin/main` | `d61840f` (msg v4.9.137) | v4.9.139 | Deploy à frente do commit ⚠️ |
| Obsidian `03 - Estado` Worker | v4.9.134 | v4.9.139 | Documentação defasada ⚠️ |
| Obsidian MOC Worker | v4.9.136 | v4.9.139 | Documentação defasada ⚠️ |

**Health público — evidência bruta (2026-06-18T00:50:18Z):**

`https://api.vixradar.com/`:
```json
{"ok":true,"versao":"v4.9.139","ts":"2026-06-18T00:50:18.393Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
```

**Pages `version.json`:**
```json
{"version":"v201.63","deployed_at":"2026-06-17T21:26:52Z"}
```

**HTML servido:** `CACHE_VERSION="v201.63"`; `window._VIX_LAYOUT_VERSAO="v201.63"` ✅

---

## Incidentes abertos

| ID | Status | Detalhe |
|---|---|---|
| Sessão expira ~1s (Eduardo) | **RESOLVIDO** | v201.63 — JWT em GETs autenticados |
| Eduardo Meyer recadastro | **RESOLVIDO** | KV removido 2026-06-17; `users:index` 24 usuários; ausente em `admin_listar` |
| Deliverability e-mail | **RESOLVIDO** | SPF `-all`, DMARC `p=quarantine` ([[17 - Email Relatorio e Deliverability 2026-06-17]]) |

---

## Achados

### CRÍTICO

Nenhum nesta passagem.

### ALTO

Nenhum nesta passagem.

### MÉDIO

1. **Documentação defasada** — `00 - Índice (MOC).md` cita v4.9.136; `03 - Estado de Produção` cita v4.9.134. Evidência: health `versao:"v4.9.139"`.
2. **Repo dirty pós-deploy** — `git status`: `api/wrangler.toml`, `api/v4.9.134.js` modificados; `api/v4.9.130.js`–`v4.9.139.js` untracked; último commit `d61840f` não cobre v4.9.138–139.
3. **Bundle Worker não versionado** — `api/v4.9.139.js` existe localmente mas está untracked (risco em clone limpo).
4. **Deploy à frente do git** — produção em v4.9.139; último commit descreve v4.9.137.

### BAIXO

1. **`listar_emissores_prioritarios top_n=103` → 83** — comportamento esperado por staleness baixo pós-varredura; não indica gap de cobertura (documentado em auditorias anteriores).
2. **Logs `[tel] falha ao gravar: Invalid URL string`** — 5 eventos em 24h no Observability; `tel_test` atual retorna `write_result.ok:true` (possível request com URL inválida em path secundário).
3. **Erros tel em `new URL(request.url)`** — `api/v4.9.139.js:5095`; falha silenciosa com `console.error`, não derruba request principal.

---

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` health | ✅ 200 | `ok:true`, `versao:v4.9.139`, `telemetria:true`, `verificador_ok:true` |
| `POST {}` anônimo | ✅ 401 | `{"ok":false,"erro":"Autenticação necessária."}` |
| `GET ?op=state` sem JWT | ✅ 401 | idem |
| CORS preflight vixradar.com | ✅ 204 | `Access-Control-Allow-Origin: https://vixradar.com`, `Allow-Credentials: true` |
| `admin_health_check` | ✅ 200 | `anthropic:true`, `resend:true`, `kv:true`, `telemetria:true`, `worker_version:v4.9.139` |
| `tel_test` | ✅ 200 | `ok:true`, `binding_presente:true`, `write_result.ok:true` |
| `admin_verificar_evento` smoke | ✅ 200 | `ok:true`, `quarentenados:1` (evento sintético — verificador vivo) |
| `listar_todos_emissores` | ✅ 103 | `{"ok":true,"total":103,...}` |
| `dados_para_analise` CEMIG | ✅ 200 | `ok:true`, `janela_inicio:2026-05-18`, `cvm_documentos` populado |
| `listar_emissores_prioritarios` | ✅ 83/103 | staleness baixo — esperado |
| Pages `CACHE_VERSION` | ✅ v201.63 | HTML servido |
| CSS `<strong>` global | ✅ | `app/index.html:2621` — só `font-weight:600`, sem `color` |
| `receber_analise` path | ✅ | `api/v4.9.139.js:14839-14841` — `_raEvs` + `sem_eventos = _raEvs.length === 0` |
| Bindings wrangler | ✅ | `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS`; `[observability] enabled=true` |

---

## Bloco C — Worker (workers-best-practices)

| Item | Status | Evidência |
|---|---|---|
| `observability` | ✅ | `api/wrangler.toml:97-99` `enabled=true`, `head_sampling_rate=1` |
| Analytics Engine binding | ✅ | `RADAR_USAGE_EVENTS`; health `telemetria:true` |
| Secrets via env | ✅ | sem fallback `JWT_SECRET="radar"` no bundle v4.9.139 |
| Cron triggers versionados | ✅ | 4 crons em `wrangler.toml:102-107` |
| `ctx.waitUntil` | ✅ | `api/v4.9.139.js:15051+` — agenda build pós-response |
| `receber_analise` ingestão | ✅ | validação `validarEVerificar` antes de `sem_eventos` |
| Providers legados | ✅ | `admin_health_check`: `openrouter/gemini/perplexity:false` (esperado pós-v4.9.108) |

---

## Bloco F — Rotinas e cobertura

| Item | Evidência |
|---|---|
| Lista canônica | `listar_todos_emissores` → **103** |
| Priorização pós-scan | `listar_emissores_prioritarios top_n=103` → **83** (staleness) |
| Amostra CEMIG | `dados_para_analise` retorna CVM na janela 30d |
| Estado semanal KV | `admin_health_check` → `weeks_loaded:["2026-W25","2026-W24"]`, `empresas_com_dados:130` |
| Crons | matinal `30 15`, noturno `30 21`, watchdog `0 1`, agenda `0 4` UTC |

---

## Lacunas

| Item | Motivo |
|---|---|
| `receber_analise` smoke POST | Sem payload versionado em `testing/` no repo |
| Playwright UI E2E | Browser MCP ocupado (`already in use`) — não coletou snapshot |
| Scan 103/103 `_last_scanned_at` individual | Amostra CEMIG via `dados_para_analise` retorna CVM, não snapshot KV completo |
| Propagação `tel_test` no AE | Instrução do endpoint pede ~60s + `action=uso visao=debug` — não aguardado nesta passagem |

---

## Próximos passos

| Prioridade | Ação |
|---|---|
| ~~**P1**~~ | ~~Commitar v4.9.139~~ **FEITO** — `e7ce539` |
| ~~**P1**~~ | ~~Docs Obsidian~~ **FEITO** — MOC + `03 - Estado` |
| ~~**P1**~~ | ~~Limpeza repo~~ **FEITO** — `de77e82` |
| **P2** | Investigar `[tel] Invalid URL string` — verificar callers que passam `request` sintético |
| **P3** | Versionar payloads smoke `receber_analise` em `testing/` para auditorias futuras |

## Encerramento de sessão (2026-06-18)

- Working tree limpo; commits `e7ce539` + `de77e82`
- Produção validada: Worker v4.9.139, Frontend v201.63, health OK