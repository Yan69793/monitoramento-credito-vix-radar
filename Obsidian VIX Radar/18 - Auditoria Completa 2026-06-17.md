# Auditoria Completa — VIX Radar (2026-06-17)

Data: 2026-06-17T02:48Z (BRT ~23:48 16/06) | Invocação: `/vix-radar-audit` (readonly)
Escopo: pós-deploy Worker v4.9.131 + Pages v201.54 (P15 timeline 90d)

Método: [[13 - Metodo de Vistoria Operacional]] | Auditoria anterior: [[15 - Auditoria Completa 2026-06-16 (v2)]]

---

## Síntese executiva

Sistema **saudável**. Produção em **v4.9.131** (Worker) e **v201.54** (Pages), alinhados ao `api/wrangler.toml` e `app/version.json`. Health público: `ok:true`, `telemetria:true`, `verificador_ok:true`, `providers_configurados:"2/2"`. Cobertura rotina: **103/103** emissores via `listar_todos_emissores`. Auth fail-closed (POST anônimo → 401). Regras invioláveis: multi-semana (5) nos endpoints críticos; binding `RADAR_USAGE_EVENTS` no wrangler; CSS `<strong>` global sem `color`.

**Veredito:** operacional. Sem incidente ativo. Drift documental em `03 - Estado de Produção` (versões antigas) e bundle `v4.9.131.js` fora do git (gitignored).

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker bundle | v4.9.131 (`api/v4.9.131.js` local) | v4.9.131 | Nenhum no deploy ativo ✅ |
| `api/wrangler.toml` main | `v4.9.131.js` | — | Alinhado ✅ |
| Worker git | `api/v4.9.131.js` **gitignored** | — | Bundle não versionado ⚠️ |
| Frontend `app/version.json` | v201.54 | v201.54 | Nenhum ✅ |
| Frontend apex/www | — | v201.54 (`deployed_at: 2026-06-17T02:40:04Z`) | Nenhum ✅ |
| CI `EXPECTED_WORKER` | v4.9.131 | v4.9.131 | Alinhado ✅ |
| Git `origin/main` | `131b1fd` | — | Limpo ✅ |

**Health público — evidência bruta (2026-06-17T02:48:04Z):**

`https://radar-credito-api.prospects-intel.workers.dev/`:
```json
{"ok":true,"versao":"v4.9.131","ts":"2026-06-17T02:48:04.605Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
```
HTTP 200, 0.08s

`https://api.vixradar.com/` — idêntico (`versao:"v4.9.131"`). HTTP 200, 0.22s

**Pages `version.json`:**
```json
{"version":"v201.54","deployed_at":"2026-06-17T02:40:04Z"}
```
`Cache-Control: no-cache, no-store, must-revalidate` ✅

---

## Incidentes abertos

Nenhum incidente técnico ativo nesta passagem. Pendências operacionais (não bloqueantes):

1. **Deliverability** — DMARC `p=none`, SPF `~all`; inbox test pendente; envio massa sex 19/06 18h30 BRT (ver [[17 - Email Relatorio e Deliverability 2026-06-17]])
2. **P15 cobertura temporal** — API `historico_emissor` usa KV multi-semana (5 semanas ~35d); UI P15 filtra 90d localmente + complemento `ARQUIVO_PRE` (by design, não bug)

---

## Achados

### CRÍTICO

Nenhum.

### ALTO

Nenhum.

### MÉDIO

- **Documentação `03 - Estado de Produção` defasada** — ainda cita v4.9.128 / v201.53; produção confirmada v4.9.131 / v201.54. Evidência: `GET /` + `version.json` acima. **Correção:** atualizada nesta auditoria.
- **Bundle Worker v4.9.131.js não versionado no git** — `git check-ignore` confirma `api/v4.9.131.js` coberto por `api/v4.*.js`; whitelist no `.gitignore` para até v4.9.129. `api/wrangler.toml` (main=v4.9.131.js) **está** versionado. Risco: recuperação de bundle depende de disco local ou Cloudflare, não do repo.
- **MOC SHA desatualizado** — `00 - Índice` citava `origin/main = 462bfa5`; HEAD real `131b1fd` (commit `chore: ignorar mcps/`). Corrigido nesta auditoria.

### BAIXO

- **`Math.random` residual** em `api/v4.9.131.js` (~L9163) no sample rate do verificador — não é path de segurança crítico; débito herdado v4.9.112.
- **Dashboard principal** mantém `JANELA_DIAS:30` no módulo market overview (`app/index.html` ~L3745); P15 timeline emissor usa `JANELA_DIAS=90` separado (`#p15-timeline-module`). Divergência intencional de escopo UI.

### OK (regras invioláveis)

- **Multi-semana:** `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor`, `comparar` usam `carregarEstadoMultiSemana(env, 5)` — confirmado em `api/v4.9.131.js` (grep linhas 11632, 13408, 13435, 13781-13782).
- **Telemetria binding:** `[[analytics_engine_datasets]]` `RADAR_USAGE_EVENTS` em `api/wrangler.toml` L59-62.
- **CSS strong:** `app/index.html:2594-2596` — só `font-weight: 600`, sem `color`. Overrides específicos (`.ews-disclaimer strong`, etc.) preservados.
- **CORS:** preflight `Origin: https://vixradar.com` → 204, `Access-Control-Allow-Origin: https://vixradar.com`.
- **Auth:** `POST /` sem JWT → `{"ok":false,"erro":"Autenticação necessária."}` HTTP 401.

---

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| Health `GET /` workers.dev | ✅ 200, v4.9.131, telemetria:true | JSON bruto acima |
| Health `GET /` api.vixradar.com | ✅ idêntico | JSON bruto acima |
| Pages version.json apex + www | ✅ v201.54 | curl 2026-06-17T02:48Z |
| POST anônimo análise | ✅ 401 fail-closed | `Autenticação necessária` |
| CORS preflight vixradar.com | ✅ 204 + Allow-Origin | curl OPTIONS |
| `listar_todos_emissores` | ✅ ok:true, total:103 | POST + routine_key |
| `dados_para_analise` Auren | ✅ ok:true, CVM docs na janela | requer `empresa`+`setor` |
| `tel_test` | ⏭️ não executado | exige `admin_senha` (403 com routine_key) |
| `admin_health_check` | ⏭️ não executado | exige `admin_senha` |
| `admin_verificar_evento` | ⏭️ não executado | exige credencial + custo API |
| `op=state` / `historico_emissor` JWT | ⏭️ não executado | readonly sem token de usuário |
| CI canonical-test | ✅ config alinhada | `EXPECTED_WORKER=v4.9.131` |

---

## Bloco C — Worker técnico (workers-best-practices)

| Item | Status | Evidência |
|---|---|---|
| `[observability] enabled` | ✅ | `api/wrangler.toml` L89-91 |
| Bindings KV / DO / Analytics | ✅ | wrangler.toml L46-62; health bindings true |
| Crons versionados | ✅ | 4 triggers L94-98 |
| `ADMIN_EMAIL` runtime | ✅ | bundle L3570 `ADMIN_EMAIL=""` + `aplicarConfigRuntime` |
| `JWT_SECRET` via env | ✅ | L4183+ usa `env2222.JWT_SECRET` |
| Custom domain api.vixradar.com | ✅ | wrangler routes L73-75 |
| v4.9.131 deliverability | ✅ deploy note | one-click unsubscribe POST; List-Unsubscribe HTTPS |

---

## Lacunas

1. `tel_test` + `action=uso visao=debug` — bloqueado: sem `ADMIN_PASSWORD` na sessão (readonly).
2. `admin_health_check` — idem.
3. Endpoints JWT (`op=state`, `historico_emissor` E2E) — sem token de usuário na sessão.
4. `admin_verificar_evento` smoke Haiku — evitado (custo + escrita).
5. CF Version ID do deploy v4.9.131 — não coletado via API nesta passagem.

---

## Próximos passos

| Prioridade | Ação |
|---|---|
| P0 | Nenhuma ação técnica bloqueante |
| P1 | Validar deliverability antes do envio massa sex 19/06 (DMARC, inbox test) |
| P1 | Whitelist `!api/v4.9.130.js` e `!api/v4.9.131.js` no `.gitignore` + commit bundle |
| P2 | Executar `tel_test` pós-próximo deploy com `admin_senha` (ritual AGENTS.md) |
| P2 | Atualizar MOC SHA após cada push (evitar drift 462bfa5 vs 131b1fd) |

---

## Causa raiz / correção / validação (mudanças recentes validadas)

| Mudança | Causa | Correção | Validação |
|---|---|---|---|
| v4.9.131 deliverability | mailto List-Unsubscribe inválido; footer genérico | POST one-click no Worker; footer por destinatário | Health v4.9.131 OK; código L3484, L5375, L13980 |
| v201.54 P15 | timeline emissor limitada a janela painel 30d | módulo `#p15-timeline-module` 90d via `historico_emissor` | prod version.json v201.54; módulo L5646+ |