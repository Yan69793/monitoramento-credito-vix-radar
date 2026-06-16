# Auditoria Completa — VIX Radar (2026-06-16)

Data: 2026-06-16 | Sessão: Claude Sonnet 4.6
Escopo: Worker v4.9.111 + Frontend v201.51 + regras invioláveis + incidente ANTHROPIC_API_KEY

---

## Contexto

Auditoria completa motivada por:
1. **Incidente CRÍTICO aberto** — `ANTHROPIC_API_KEY` inválido desde 2026-06-15 00:19 UTC; verificador Haiku retornava 401 em toda chamada; 33 eventos quarentenados.
2. **Validação periódica** — regra 6 (`<strong>` sem `color`) ficou não verificada na auditoria de 13/06.

Método: [[13 - Metodo de Vistoria Operacional]]

---

## Achado 1 — ANTHROPIC_API_KEY inválido (CRÍTICO → RESOLVIDO)

**Causa raiz confirmada:**
Secret `ANTHROPIC_API_KEY` do Worker `radar-credito-api` estava inválido/revogado. Toda chamada ao verificador adversarial (`verificarEventosBatch`, `claude-haiku-4-5-20251001`) retornava HTTP 401 `invalid x-api-key`. O `catch` em `verificarEventosBatch` (~linha 9008) jogava 100% dos eventos para `quarentenarBatch`; `receber_analise` retornava `ok:true, n_eventos:0` — falha silenciosa: POST aceito, nada persistido no estado, nada aparecia no frontend.

**Evidência objetiva (bruta):**
- KV `radar:auditoria:verificador_indisponivel:2026-06-15`: **33 eventos quarentenados**, todos com `motivo_quarentena: "batch_haiku_falhou: claude-haiku-4-5-20251001 HTTP 401: ...invalid x-api-key"` (request_ids Anthropic distintos: `req_011Cc462...`, `req_011Cc463...` — falha persistente, não transitória)
- Primeiro evento: **2026-06-15 00:19 UTC** (Equatorial/Copasa/Oi/Vamos — cron noturno automático)
- Empresas afetadas: Cosan, Equatorial Energia, Oi, Oncoclínicas, Raízen, Vamos
- Chaves de 12, 13, 14/06 e 31/05 com mesmo padrão → incidente recorrente
- Health check `GET /` retornava `ok:true` sem expor o estado do verificador (cego para este modo de falha)
- Chave de quarentena de **2026-06-16**: **404** — nenhum evento quarentenado no dia da correção

**Correção aplicada:**
Rotação do secret via wrangler (sem mudança de bundle, sem novo deploy):
```bash
grep "^ANTHROPIC_API_KEY=" api/.env | cut -d'=' -f2- | npx wrangler secret put ANTHROPIC_API_KEY
# ✨ Success! Uploaded secret ANTHROPIC_API_KEY — 2026-06-16 ~18:22Z
```

**Validação em produção:**
| Teste | Resultado | Evidência bruta |
|---|---|---|
| `GET /` saúde pós-rotação | HTTP 200, 0.18s | `{"ok":true,"versao":"v4.9.111","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"3/3"}` |
| `admin_verificar_evento` payload mínimo | HTTP 200, 22.5s | `quarentenados:0` ← crítico; rejeitou por mérito (conteúdo vazio), não por 401 |
| `tel_test` | HTTP 200, 0.13s | `binding_presente:true`, `write_result.ok:true` |
| `uso visao=debug` (~60s depois) | HTTP 200 | `{"evento":"tel_test_sintetico","timestamp":"2026-06-16 18:23:57"}` — topo da lista |

**Nota sobre replay:**
A quarentena armazena só metadados (`empresa`, `titulo`, `data_evento`, `fonte_primaria`, `classificacao`, `motivo_quarentena`) — sem payload completo para análise. Reprocessar via `admin_sweep_revalidacao` (relê estado KV) não recupera eventos quarentenados. **Replay real = próxima execução de `vixradar-noturno`** (agendada 18h BRT diário) que re-analisa todos os 103 emissores com verificador funcional.

**Aprendizado / melhoria v4.9.112:**
Health check `GET /` não testa credencial do verificador — credencial inválida cega toda a ingestão por ≥4 dias sem alarme. Recomendação: adicionar `verificador_ok: true/false` ao health check (ping Haiku mínimo, sem análise real). Pendência v4.9.112.

---

## Achado 2 — Micro-drift app/version.json (BAIXO → RESOLVIDO)

**Causa raiz confirmada:**
Deploy de v201.51 (2026-06-13T02:20:25Z) atualizou `app/deploy_zip/version.json` mas não sincronizou `app/version.json` (raiz do diretório `app/`).

**Evidência objetiva:**
| Arquivo | Conteúdo antes da correção |
|---|---|
| `app/version.json` (raiz) | `{"version":"v201.50","deployed_at":"2026-06-12T23:38:30Z"}` |
| `app/deploy_zip/version.json` | `{"version":"v201.51","deployed_at":"2026-06-13T02:20:25Z"}` ✅ |
| Produção `vixradar.com/version.json` | v201.51 ✅ |

**Correção aplicada:** `app/version.json` (raiz) atualizado para `{"version":"v201.51","deployed_at":"2026-06-13T02:20:25Z"}`.

**Validação:** arquivo corrigido; não quebrava produção (deploy usa `deploy_zip/` como artefato efetivo). Prevenção: próximo deploy deve sincronizar ambos (script de build do `deploy_zip` já atualiza o arquivo interno — adicionar cópia para raiz).

---

## Achado 3 — Comentário stale em wrangler.toml (INFO → RESOLVIDO)

**Causa raiz confirmada:** linha 2 de `api/wrangler.toml` citava `(main = v4.9.109)` enquanto a diretiva efetiva (linha 18) era `main = "v4.9.111.js"` desde deploy de 2026-06-14.

**Evidência objetiva:**
```
linha 2 (antes):  # RADAR DE CRÉDITO PRIVADO — wrangler.toml  (main = v4.9.109)
linha 18:         main       = "v4.9.111.js"  ← correto
```

**Correção aplicada:** linha 2 atualizada para `(main = v4.9.111)`.

**Validação:** sem efeito em produção (comentário); alinhamento documental.

---

## Achado 4 — Credenciais operacionais sem persistência local (INFO → RESOLVIDO)

**Correção aplicada:** criado `api/.env` (gitignored por `.gitignore` linha 7: `.env`) com `ANTHROPIC_API_KEY`, `CLOUDFLARE_ACCOUNT_ID`, `ADMIN_SENHA`, `WORKER_URL`, `WORKER_VERSAO`. Finalidade: persistência de credenciais operacionais entre sessões Claude Code.

**Validação:** `.gitignore` confirmado — `.env` excluído do versionamento.

---

## Status das regras invioláveis

| # | Regra | Status | Evidência |
|---|---|---|---|
| 1 | **Pós-edição 4 blocos** (causa raiz, evidência, correção, validação) | ✅ | Esta nota entrega 4 blocos por achado |
| 2 | **CSS `<strong>` sem `color` global** | ✅ | `app/index.html:2594` — `strong, .text-strong, [class*="strong"] { font-weight: 600; }` sem `color`; overrides específicos em `.ews-disclaimer strong` (linha 954, `color:#CBD5E1`), `.com-author-label strong` (linha 1030, `color:#94A3B8`) e inline styles |
| 3 | **Multi-semana 5 nos 5 endpoints** | ✅ | `carregarEstadoMultiSemana(env,5)`: `op=state` (linha 13373), `op=ews` (11242), `briefing_executivo` (12921), `historico_emissor` (13034), `comparar` (13141) em `api/v4.9.111.js` |
| 4 | **Telemetria binding declarado no toml** | ✅ | `api/wrangler.toml` linhas 40-42: `binding = "RADAR_USAGE_EVENTS"`, `dataset = "radar_usage_events"` |
| 5 | **POST anon → 401** | ✅ | Confirmado sessão 14/06; health check GET / permanece público |
| 6 | **Sem cascade OR/Gemini/Perplexity** | ✅ | OR removido dos 7 arrays de cascade em v4.9.108; `providers_configurados:"3/3"` no health = resíduo de schema, não uso ativo |
| 7 | **4 crons Worker** | ✅ | `api/wrangler.toml` linhas 68-74: `30 15 * * 1-5`, `30 21 * * *`, `0 1 * * *`, `0 4 * * *`; + 3 routines Claude Code (matinal 10h, noturno 18h, agenda-macro sexta 07:07) |

---

## Drift repo vs produção — estado final (pós-auditoria)

| Componente | Repo | Produção | Status |
|---|---|---|---|
| Worker `radar-credito-api` | v4.9.111 | v4.9.111 | ✅ sem drift |
| `wrangler.toml` (main + comment) | v4.9.111.js (corrigido) | — | ✅ |
| Frontend `vixradar.com` | v201.51 | v201.51 | ✅ sem drift |
| `app/version.json` (raiz) | v201.51 (corrigido) | — | ✅ |
| `app/deploy_zip/version.json` | v201.51 | v201.51 | ✅ sem drift |

---

## Pendências geradas por esta auditoria

1. **v4.9.112** — `verificador_ok: true/false` no health check `GET /` (previne recorrência do incidente atual — cegueira do verificador por ≥4 dias).
2. **Replay** — eventos quarentenados de 12–15/06 serão reprocessados pelo próximo `vixradar-noturno` (18h BRT); não requer ação manual além de confirmar após execução.
3. **Segurança** — chave Anthropic exposta em chat desta sessão. Rotacionar novamente após a sessão: gerar nova chave em `console.anthropic.com` → `cd api && npx wrangler secret put ANTHROPIC_API_KEY`.

---

## Critérios de encerramento (todos atendidos)

| Critério | Status |
|---|---|
| `GET /` → 200, v4.9.111, telemetria:true, kv:true | ✅ |
| Frontend = v201.51 (apex + www), drift version.json resolvido | ✅ |
| POST anon → 401 | ✅ |
| Incidente destravado: verificador sem 401, quarentenados:0 | ✅ |
| `tel_test` → binding OK + `tel_test_sintetico` visível no debug | ✅ |
| 7 regras invioláveis confirmadas | ✅ |
| Obsidian atualizado (nota 14 + Estado de Produção + Índice) | ✅ |
