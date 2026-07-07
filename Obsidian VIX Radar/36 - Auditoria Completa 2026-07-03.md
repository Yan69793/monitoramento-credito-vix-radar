# Auditoria Completa — VIX Radar (2026-07-03)

## Síntese executiva

Saudável. Nenhum crítico. Worker v4.9.143 e Frontend v201.69 sem drift repo/produção. Rotina noturna 02/07 fechou 103/103 emissores com submit_ok=true após reprocessamento manual de 24 emissores que tinham falha de schema (não de auth, ver [[rotinas/2026-07-02-noturno-v2]]).

**Atualização 03/07 (mesmo dia):** os 3 P1 de débito técnico abaixo (cleanup, schema docs, token parser) foram corrigidos e validados nesta sessão.

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker | `wrangler.toml main=v4.9.143.js`, `WORKER_VERSAO="v4.9.143"` | `GET /` → `versao:v4.9.143` | Não |
| Frontend | `app/index.html CACHE_VERSION="v201.69"` | `vixradar.com/version.json → v201.69` | Não |

## Incidentes abertos

1. ~~**P0** — `cleanup-rotina-artifacts.ps1` apaga log/metrics do próprio dia~~ **CORRIGIDO 03/07** — `Remove-IfStale` agora tem guard `if ($item.LastWriteTime.Date -eq (Get-Date).Date) { return }` antes de qualquer checagem de `-Aggressive`/cutoff. Arquivo modificado no dia corrente nunca mais é deletado, independente do modo.
2. ~~**P1** — Schema drift entre o payload que agentes Haiku/Sonnet montam e o schema real de `receber_analise`~~ **CORRIGIDO 03/07** — `scripts/noturno-batch-haiku.md` e `noturno-batch-sonnet.md` agora documentam o schema exato (`resultado` como objeto aninhado, confirmado em `api/v4.9.143.js:15244`), com exemplo de curl e aviso explícito de que 400 (`"empresa e resultado obrigatorios"`) é erro de schema, não de autenticação.
3. ~~**P1** — `Parse-TokensFromOutput` não lê `--output-format text` corretamente~~ **CORRIGIDO 03/07** — trocado para `--output-format json`; `Invoke-ClaudeBatch` agora parseia `.result` (texto) e `.usage` (input+output+cache_creation+cache_read) diretamente do envelope JSON da CLI. `Parse-TokensFromOutput` (função morta, regex nunca batia) removida. Validado com chamada real: `.result` e `.usage` retornam corretamente.
4. **P2 (aberto)** — `Invoke-ClaudeBatch` usa `--permission-mode bypassPermissions`; funciona dentro do scheduled task real, mas é bloqueado pelo classificador de auto mode quando chamado fora desse contexto (ex.: reprocessamento manual). Confirmado 03/07. Sem fix — mitigação: reprocessamento manual usa Agent tool (subagentes com permissão normal), não o PS1 direto.

## Achados

### CRÍTICO
Nenhum.

### ALTO
Nenhum.

### MÉDIO
- Repo com 15+ arquivos/pastas untracked não relacionados a este ciclo de trabalho (`FIGMA-INTEGRATION.md`, `app/design/`, `app/_arquivo/`, `terminals/`, `workspace.code-workspace`, scripts avulsos) — não afeta produção, mas gera ruído em `git status`. Não investigado a fundo nesta auditoria (fora do escopo do incidente da rotina).

### BAIXO
- 3 dos 4 itens em "Incidentes abertos" acima (schema drift, token parser, bypassPermissions) são débito técnico dos scripts de rotina, não do Worker/Frontend em produção.

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` health | `ok:true`, `versao:v4.9.143`, `kv:true`, `rate_limiter:true`, `telemetria:true`, `providers_configurados:2/2`, `verificador_ok:true` | HTTP 200, 0.117s |
| `POST {}` anônimo | Fail-closed | `{"ok":false,"erro":"Autenticação necessária."}` HTTP 401 |
| Frontend version.json vs repo | Idêntico | `v201.69` ambos os lados |
| CSS `<strong>` global | Sem `color` na regra bare — só seletores escopados (`.ph-card strong`, `.ews-disclaimer strong`, `.com-author-label strong`, `.ph-pill strong`) têm `color` | grep em `app/index.html` |
| Bindings wrangler.toml | `RADAR_KV`, `durable_objects.bindings` (rate limiter), `RADAR_USAGE_EVENTS` (Analytics Engine), `[observability]` — todos declarados | linhas 58-103 `api/wrangler.toml` |
| Cobertura rotina noturna 02/07 + reprocessamento 03/07 | 103/103 emissores com `submit_ok:true` | Ver [[rotinas/2026-07-02-noturno-v2]] |

## Lacunas

- `admin_health_check`, `admin_verificar_evento`, `dados_para_analise` (Bloco D avançado) não testados — exigem senha admin, não solicitada nesta rodada (escopo: fechar incidente da rotina noturna, não vistoria full de endpoints autenticados).
- `tel_test` não executado — telemetria já confirmada via `bindings.telemetria:true` no health público, considerado suficiente para este ciclo.
- Bloco F (cross-check `listar_todos_emissores` vs scan amostral) não executado — coberto indiretamente pelo fechamento 103/103 da rotina.

## Próximos passos

- **P2** — Documentar em `CLAUDE.md` ou no próprio script que reprocessamento manual fora do scheduled task deve usar Agent tool, não `Invoke-ClaudeBatch` com bypassPermissions.
- Monitorar a próxima execução noturna e confirmar no artefato de métricas: `submit_fail=0`, tokens conhecidos e preservação do log/metrics do próprio dia.
