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

## Otimização de custo da rotina noturna (03/07, sessão da tarde)

Aplicadas mudanças de redução de custo (ver plano completo em `C:\Users\User\.claude\plans\ticklish-orbiting-liskov.md`), medidas empiricamente antes de implementar (4 agentes de medição): boot de cada `claude -p` caiu de ~33,9k para ~11-13,6k tokens (flags `--tools`, `--strict-mcp-config`, `--setting-sources project`, `--exclude-dynamic-system-prompt-sections`); submit migrou do agente pro PS1 (protocolo `RESULTADO|`/`LOTE_RESUMO|`, sem curl no agente); buscas condicionais (R6 só com sinal); gate pré-evento (URL primária + janela); chunks Sonnet 8→11, Haiku 12→15; retry parcial de lote falho.

**Gap corrigido:** 10 emissores do lote `haiku-8` de 02/07 (nunca processados, falha silenciosa) foram reprocessados — 10/10 OK, 0 crítico, 3 RELEVANTE (Copasa, Brava Energia, Gerdau — M&A/CADE) quarentenados pelo verificador do Worker, pendentes de validação manual no painel admin.

**Revisão adversarial (workflow, 3 lentes) encontrou 3 bugs BLOQUEIA reais nas mudanças, todos corrigidos e revalidados com teste real antes de fechar:**

1. `$ErrorActionPreference='Stop'` global + redirect de stderr do `claude -p` fazia QUALQUER aviso benigno do CLI (comum em binários Node, mesmo com exit 0) lançar exceção terminante e derrubar a rotina inteira a partir daquele lote, sem gravar métricas nem log de fim. Fix: `$ErrorActionPreference='Continue'` isolado dentro de `Invoke-ClaudeBatch`, com try/catch/finally.
2. Match de emissor por nome (`.ContainsKey`) quebrava com diferença de acentuação (ex.: agente normaliza "Iguá" → "Igua"), causando retry desnecessário ou FAIL falso. Fix: `Get-NomeNormalizado` (remove diacríticos) usado nos dois lados do match.
3. O protocolo novo (`RESULTADO|`) não pedia `memo_acontecimento`/`memo_importancia_credito`/`memo_monitorar` por evento — esses campos alimentam tanto o card exibido ao usuário quanto o `contexto_historico` que a rotina de amanhã recebe (api/v4.9.143.js:8193/8645). Sem eles, todo evento novo da rotina noturna virava um card vazio e o contexto histórico nunca melhorava. Fix: schema e os 2 skills md agora exigem os 3 memos para CRITICO/RELEVANTE.

Também corrigidos (IMPORTANTE): emissor sem RESULTADO após retry agora recebe submit mínimo de cobertura (`classificacao_geral:NENHUM` + nota explícita) em vez de ficar sem nenhum registro na semana; threshold do gate R6 ajustado de 25→20 (referência: `ROTINA_EWS_LIGHT=30` do Worker) com nota de que é provisório até 3 noites de telemetria; doc legada `C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md` atualizada para não contradizer o protocolo novo.

**Achados não corrigidos (baixo risco, registrados para acompanhamento):** custo de `server_tool_use.web_search_requests` não é somado no total de tokens reportado (subestima custo real, não afeta execução); `cleanup-rotina-artifacts.ps1` ainda apaga o stderr do dia anterior no ciclo seguinte (aceitável — debug transitório).

**Validação:** sintaxe PS1 limpa; teste real de invocação com as flags novas confirmou boot ~11-13k tokens; parser completo (`Get-ParsedResultados`/`Get-ResultadoEmissor`) validado com saída real do CLI incluindo nome acentuado e evento com os 3 memos preenchidos.
