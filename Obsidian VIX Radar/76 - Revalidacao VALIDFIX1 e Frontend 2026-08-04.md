---
data: 2026-08-04
tipo: auditoria
tags: [vix-radar, auditoria, revalidacao, validfix1, frontend, pos-deploy]
status: ativo
escopo: revalidacao pos-deploy dos P0/P1 abertos na nota 75 (VALIDFIX1 + MODULE-MIG1)
---

# Revalidacao — VALIDFIX1 + Frontend v202.2 (2026-08-04)

Continuidade da [[75 - Auditoria Geral 2026-08-04]]. Modo readonly. Nenhum deploy nesta passagem.
Operador pediu retomada pelos curls de VALID1. A prova mostrou que **os deploys ja tinham sido feitos** antes desta sessao.

## Veredito

**Os dois itens de deploy da nota 75 estao fechados em producao.**

- Worker **v4.9.187** (health duplo ok:true, bindings verdes, 0,14–0,30s)
- Frontend **v202.2** (`version.json` + `CACHE_VERSION` no HTML + 8/8 JS com parse OK)
- VALIDFIX1 comprovado na matriz HTTP (415 fail-closed + CORS no 415)
- Working tree limpo nos paths de produto (so `?? data/historico/2026-08-03/` e `?? docs/superpowers/`)

P0 de credito Anthropic / OAuth: **fechado por confirmacao do operador em 04/08 ~12h35** ("ja tiramos do sistema"). Nao reabrir sem evidencia nova de falha de rotina.

## Versoes e drift

| Camada | Repo | Producao | Drift? |
|---|---|---|---|
| Worker | `wrangler.toml` main=`v4.9.187.js`, HEAD `4487fc3` | `versao:v4.9.187` em workers.dev e api.vixradar.com | Nao |
| Frontend | `app/version.json` v202.2 | v202.2, deployed_at 2026-08-04T15:11:19Z | Nao |
| CACHE_VERSION HTML | — | `v202.2` no apex | Nao |

## Matriz VALID1 / VALIDFIX1 (ao vivo)

Comandos base (PowerShell, `curl.exe`):

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
curl.exe -s -X POST https://api.vixradar.com/ -H "Content-Type:" --data-binary '{"action":"status_providers"}' -w "`nHTTP:%{http_code}`n"
curl.exe -s -D - -o NUL -X POST https://api.vixradar.com/ -H "Origin: https://vixradar.com" -H "Content-Type: text/plain" -d "x"
```

| # | Teste | Resultado | HTTP |
|---|---|---|---|
| H1 | GET workers.dev health | ok:true, v4.9.187, kv/rl/tel true, providers 2/2, admin_email_ok, sentry_ok, verificador_ok | 200, 0.14s |
| H2 | GET api.vixradar.com health | idem | 200, 0.30s |
| V1 | POST sem Content-Type + body JSON | `{"ok":false,"erro":"Content-Type deve ser application/json"}` | **415** |
| V2 | POST Content-Type text/plain | mesmo erro | **415** |
| V3 | POST application/json `{}` | `Autenticacao necessaria.` (passou do VALID1, parou no auth) | **401** |
| V4 | 415 + Origin https://vixradar.com | ACAO refletido, credentials true, headers CT/Auth, methods GET POST OPTIONS | **415** com CORS |
| V5 | OPTIONS preflight | 204 + mesmos headers CORS | **204** |
| V6 | POST `application/json; charset=utf-8` `{}` | passa VALID1, para no auth | **401** |
| V7 | POST sem body e sem CT | handler responde JSON invalido (sem corpo declarado, VALID1 nao dispara) | **400** |
| V8 | 415 + Origin evil.example | **sem** `Access-Control-Allow-Origin` (allowlist intacta) | **415** |

**Conclusao VALIDFIX1:** fail-open do `if (ct && ...)` morto. Ausencia e tipo errado com corpo caem em 415. CORS aplicado via `_respValidacao` so para origin allowlisted. Charset no Content-Type aceito.

## Frontend MODULE-MIG1 (pos-deploy)

| Asset prod | size | node --check |
|---|---|---|
| admin-bootstrap.js | 1427 | OK |
| api.js | 9416 | OK |
| shared.js | 7149 | OK |
| modules.js | 20933 | OK |
| admin-router.js | 6331 | OK |
| engajamento.js | 4328 | OK |
| metricas.js | 2232 | OK |
| fase3.js | 2289 | OK |

HTML apex referencia `admin-bootstrap.js?v=202.2` e `CACHE_VERSION="v202.2"`.

Commits de caminho: `ee9a941` (fecha truncamentos) → `e182774` (gates deploy) → `5411f47`/`420938b` (v202.2 em prod).

## Git

```
4487fc3 chore(worker): deploy v4.9.187 em producao
420938b chore(frontend): deploy v202.2 em producao
694c433 fix(worker): VALIDFIX1 ...
ee9a941 fix(frontend): fecha 7 truncamentos ...
```

`git status --short`: so untracked de historico/docs superpowers. Sem diff pendente nos paths de Worker/Pages.

## O que continua aberto (nao retestado a fundo nesta passagem)

1. **P0 credito Anthropic / OAuth rotinas** — trava matinal/noturno/verificador CLI. Fora do escopo HTTP VALID1.
2. Itens P2/P3 da nota 75 que nao exigiam deploy imediato: orfaos `api/src/logging.js` + `validation.js`, adocao LOG1, documentar `MIGRATION_PHASE`.
3. Painel admin **autenticado** no browser (login real) nao rodado. A prova de parse + HTTP 200 dos 8 modulos fecha o bug de truncamento, nao prova cada botao do admin.

## Achados desta revalidacao

### CRITICO / ALTO
Nenhum novo. Os P0/P1 de deploy da nota 75 fecharam.

### INFO
PENDENCIAS ainda descrevia "aguardando deploy" com Worker v4.9.186. Atualizado nesta passagem para refletir o estado real de producao.

## Proximos passos

1. Opcional: smoke autenticado do painel admin (Hoje, heartbeats, HEART) com login real.
2. P2 residual da 75 (orfaos em `api/src/`, LOG1) quando sobrar janela, sem urgencia de prod.
3. Cobertura dos 9 FULL de alto EWS so se ainda faltar no KV (nao e o P0 de auth).

---

*Revalidacao 2026-08-04 ~12:30 BRT. Readonly. Evidencia bruta via curl.exe + node --check em assets baixados de vixradar.com.*
