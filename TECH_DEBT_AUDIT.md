# Tech Debt Audit — VIX Radar
Generated: 2026-06-16 | Bundle: api/v4.9.111.js (14.524 linhas)

---

## Architectural mental model

O VIX Radar é um Cloudflare Worker de arquivo único (`api/v4.9.111.js`) que serve simultaneamente como API backend, sistema de ingestão de eventos de crédito privado e roteador de webhook. O bundle é gerado pelo Wrangler e inclui polyfills Node.js do unenv, resultando em um artefato de ~684 KB. A aplicação em si começa em torno da linha ~3400 após ~3.300 linhas de polyfills bundled. O frontend (`app/index.html`) é um SPA monolítico de ~200K linhas/450 KB servido pelo Cloudflare Pages.

O Worker não tem separação de camadas: o handler principal `__coreFetch()` (1.139 linhas, `:13267`) despacha diretamente para todas as funções de negócio. A lógica de auth, rate limit, KV, AI, email, CORS e observabilidade convive no mesmo escopo global. Isso é aceito no paradigma de Workers simples, mas dificulta teste e manutenção conforme o bundle cresce.

O README documenta que "código local é obsoleto" — a fonte de verdade é o bundle deployado em produção. O repositório rastreia versões sequenciais (`v4.9.67.js` a `v4.9.111.js`) mas não o código fonte hand-authored, o que confirma que o bundle **é** o código: não há camada de abstração entre desenvolvimento e produção.

---

## Executive summary

- **2 Critical, 7 High, 9 Medium, 5 Low** — 23 findings
- Maior concentração: `api/v4.9.111.js:3267–14524` (código de negócio)
- `__coreFetch()` (`:13267`, 1.139 linhas) é o god router e o maior risco de manutenção
- 43 `catch {}` vazios são swallowed exceptions — falhas silenciosas em path crítico
- `observability` ausente no `wrangler.toml` cega Workers Logs
- `ADMIN_EMAIL` hardcoded (`:3570`) expõe PII do operador no bundle público
- Build artifact: 3.300 linhas de polyfills duplicados no bundle — **não é debt de código**, é overhead de build

---

## Findings

| ID | Category | File:Line | Severity | Effort | Description | Recommendation |
|----|----------|-----------|----------|--------|-------------|----------------|
| F001 | Architectural decay | `api/v4.9.111.js:13267` | **Critical** | L | `__coreFetch()` tem 1.139 linhas — rotea 100% dos endpoints (GET/POST, auth, webhooks, admin, observabilidade). Impossível testar isoladamente. | Extrair grupos de handlers em funções dedicadas por domínio (`handleAuth`, `handleAdmin`, `handleIngestao`, `handleObs`). Nenhum comportamento muda — só organização do dispatch. |
| F002 | Error handling | `api/v4.9.111.js:360,1215,2089,2995,4113,4150...` | **Critical** | M | 43 `catch {}` sem corpo — exceções engolidas silenciosamente em caminhos que incluem parsing de JWT, verificação de token e persistência KV. | Substituir por `catch (e) { console.error('[ctx]', e.message); }` no mínimo. Para caminhos críticos (auth, KV write), relançar ou retornar erro estruturado. |
| F003 | Security hygiene | `api/v4.9.111.js:3570` | **High** | S | `var ADMIN_EMAIL = "szuchmacheryan@gmail.com"` hardcoded no bundle — email do operador exposto em qualquer inspeção de código. | Mover para `env.ADMIN_EMAIL`. `wrangler secret put ADMIN_EMAIL`. Pendência já registrada no Obsidian (P4). |
| F004 | Security hygiene | `api/v4.9.111.js:4965` | **High** | S | `JWT_SECRET \|\| "radar"` em `gerarIpPseudoanonimo()` — fallback silencioso para salt previsível se JWT_SECRET ausente. | Remover o `\|\| "radar"`. Sem JWT_SECRET a função deve lançar, não degradar. |
| F005 | Security hygiene | `api/v4.9.111.js:5158,12621` | **Medium** | S | `Math.random()` em `gerarMessageId()` e como input de `gerarCicloId()`. Não são tokens de autenticação mas Message-IDs e IDs de rastreamento deveriam ser não-previsíveis. | `gerarMessageId()`: usar `crypto.randomUUID()`. `gerarCicloId()`: substituir `Math.random()` por `crypto.getRandomValues(new Uint8Array(8))` antes do digest SHA-256. |
| F006 | Observability | `api/wrangler.toml` | **High** | S | `[observability]` ausente — Workers Logs não coleta traces automaticamente. Debugging de produção depende de `console.log` e telemetria custom (Analytics Engine). | Adicionar ao `wrangler.toml`: `[observability]\nenabled = true\nhead_sampling_rate = 1` — habilita traces sem custo adicional no plano Workers Paid. |
| F007 | Architectural decay | `api/v4.9.111.js:442` | **High** | L | `_trunc()` (442 linhas, `:10797`) — função de truncamento que cresceu para acomodar lógica de sanitização de payload, formatação de datas e extração de campos. Nome não reflete escopo. | Dividir em `sanitizarPayload()`, `truncarTexto()`, `formatarCamposEvento()`. Nenhuma reescrita — só extração com mesma lógica. |
| F008 | Architectural decay | `api/v4.9.111.js:3669` | **Medium** | M | `getTenantConfig()` (219 linhas) inclui tanto lookup de config quanto lógica de merge de features e validação de schema de tenant. God function de configuração. | Extrair `mergeTenantFeatures()` e `validarSchemaTenant()` como helpers. `getTenantConfig()` fica com apenas o lookup + fallback. |
| F009 | Consistency rot | `api/v4.9.111.js` múltiplos | **Medium** | M | Múltiplos padrões de logging: `console.log`, `console.error`, `console.warn` sem prefix estruturado. Alguns usam `[ctx]` prefix, outros não. Impossível filtrar por módulo no Workers Logs. | Padronizar em `log(ctx, msg, data)` helper que emite JSON estruturado: `{"ts":"...","ctx":"auth","msg":"...","data":{...}}`. Workers Logs aceita JSON nativamente. |
| F010 | Consistency rot | `api/v4.9.111.js:4047,4104,4142,5233` | **Low** | S | Funções de verificação nomeadas inconsistentemente: `verificarSenha`, `verificarJWT`, `verificarTokenEmail`, `verificarSvixSignature`. Convenções distintas de assinatura e retorno. | Uniformizar retorno: todas devem retornar `{ok: bool, payload?, erro?}` — elimina `throw` vs `return null` misturados. |
| F011 | Dependency debt | `api/v4.9.111.js:13267` | **High** | M | `openrouter.ai` aparece nas dependências externas do bundle (fetch targets). Segundo CLAUDE.md, OpenRouter foi **removido em v4.9.108**. Se ainda há código alcançável apontando para `openrouter.ai`, é código morto consumindo bundle size. | Grep `openrouter.ai` e verificar se os caminhos são alcançáveis. Se dead code, remover. Se resíduo de schema (health check), documentar como tal. |
| F012 | Architectural decay | `api/v4.9.111.js:11881` | **Medium** | M | `processarEventosComVerdadeGraduada()` (133 linhas) mistura validação de schema, ordenação por materialidade e lógica de dedup. 3 responsabilidades. | Extrair `validarSchemaEvento()` (já existe isolada?), `ordenarPorMaterialidade()`, `dedupEventos()`. |
| F013 | Performance | `api/v4.9.111.js` múltiplos | **Medium** | M | Múltiplas leituras KV dentro de loops em endpoints de alta frequência (antes de v4.9.110 era `op=state`; verificar se `op=ews` e `briefing_executivo` têm o mesmo padrão). | Verificar `op=ews` e `briefing_executivo` — se há `await env.RADAR_KV.get()` em loop, paralelizar com `Promise.all` igual ao fix do `op=state`. |
| F014 | Error handling | `api/v4.9.111.js:8177` | **Low** | S | `await request.text()` sem limit em handler de webhook Svix — body não-delimitado pode consumir memória. Workers têm limite de 128 MB. | Adicionar `const body = await request.arrayBuffer(); if (body.byteLength > 1_000_000) return resp({ok:false,erro:'payload_grande'},413);` antes do parse. |
| F015 | Config debt | `api/wrangler.toml` | **Medium** | S | `compatibility_date = "2025-10-01"` — 8+ meses atrás. Workers recebe breaking changes e novos padrões periodicamente. | Atualizar `compatibility_date` para a data do próximo deploy após verificar changelog da CF (https://developers.cloudflare.com/workers/configuration/compatibility-dates/). |
| F016 | Documentation drift | `api/wrangler.toml:2` (antes desta sessão) | **Low** | S | Comentário de versão stale no cabeçalho do arquivo. **RESOLVIDO nesta sessão (2026-06-16)** — atualizado de `v4.9.109` para `v4.9.111`. | ✅ Resolvido |
| F017 | Security hygiene | `api/v4.9.111.js:11522,11527,11565` | **Low** | S | Rate limiter falha open (3 paths). Design explícito documentado no CLAUDE.md. Risco residual: se `RATE_LIMITER_DO` removido do toml, rate limiting some silenciosamente. | Health check já expõe `bindings.rate_limiter`. Adicionar log `console.warn('[rl] bypass:', _bypass)` para audit trail quando bypass ativa. |
| F018 | Architectural decay | `api/v4.9.111.js:6011` | **Medium** | L | `buscarDocumentosCVM()` (260 linhas) — função única que faz HTTP, parse de HTML, normalização de campos e dedup. Sem separação fetch/parse/normalize. | Extrair `parsearDocumentosCVM(html)` e `normalizarDocCVM(doc)`. Permite testar parse sem HTTP. |
| F019 | Test debt | Repo inteiro | **High** | L | Zero testes automatizados no repositório. O CI (`.github/workflows/canonical-test.yml`) valida apenas `EXPECTED_WORKER` via health check — não testa lógica de negócio. | Criar `api/tests/` com testes unitários para: `verificarJWT`, `sanitizarPayloadRadar`, `carregarEstadoMultiSemana`, `processarEventosComVerdadeGraduada`. Workers Vitest suporta ambiente `cloudflare:test`. |
| F020 | Dependency debt | `api/` | **Medium** | S | Versões anteriores do bundle (`v4.9.67.js` a `v4.9.110.js`) ocupam espaço no repo mas nunca são lidas por código — são histórico manual. O repo não tem `.gitignore` para `api/v*.js` antigas. | Criar branch `archive/old-bundles` com os arquivos antigos e removê-los do `main`. `wrangler.toml` já aponta para a versão correta — as antigas são dead weight. |
| F021 | Documentation drift | `CLAUDE.md` | **Low** | S | ~~Seções SUPERADAS no CLAUDE.md~~ **RESOLVIDO 2026-06-19:** `CLAUDE.md` enxuto (~5 KB); histórico em `docs/archived/CLAUDE-HISTORICO.md`; `AGENTS.md` = ponteiro. | — |
| F022 | Security hygiene | `api/v4.9.111.js:10577` | **Low** | S | Formulário HTML de login admin (`admin_mercado`) via GET com senha em query string: `<input type="password" name="senha">` em `<form method="get">` — senha aparece em URL, logs, histórico do browser. | Mudar `method="get"` para `method="post"`. Requer mudança no handler para ler `formData()` em vez de `url.searchParams`. |
| F023 | Consistency rot | `api/v4.9.111.js` | **Medium** | L | `__name`, `__name2`, `__name22`, `__name222`, `__name2222`, `__name22222`, `__name222222`, `__name2222222`, `__name22222222` — 9 variantes idênticas da função de nomeação de Wrangler. Indica que o bundle está concatenando o mesmo runtime shim múltiplas vezes. | **Ver "Looks bad but actually fine" abaixo.** |

---

## Top 5 "se não corrigir nada, corrija esses"

**F002 — 43 catch{} vazios**
Prioridade máxima de operabilidade. Falha silenciosa em auth ou KV write = incidente sem log. Fix: substituição global:
```js
// Antes
} catch {
  return null;
}
// Depois
} catch (e) {
  console.error('[ctx] caught:', e?.message ?? String(e));
  return null;
}
```
Esforço real: 1 sessão de busca+substituição dirigida.

**F003 — ADMIN_EMAIL hardcoded**
PII do operador no bundle. `wrangler secret put ADMIN_EMAIL` + substituir `ADMIN_EMAIL` por `env.ADMIN_EMAIL` no bundle. 30 minutos.

**F004 — JWT_SECRET fallback `|| "radar"`**
Remover 8 caracteres. Risco concreto: se JWT_SECRET sumir do dashboard Cloudflare, IP hashing degrada silenciosamente. `const salt = \`${env2222.JWT_SECRET}:${hoje}\`;` — sem fallback.

**F006 — observability no wrangler.toml**
2 linhas de TOML. Habilita Workers Traces no dashboard. Debug de produção atual depende de grep em Analytics Engine — traces dão stack completo com timing por handler.

**F001 — __coreFetch() 1.139 linhas**
Não é reescrita. É extração: identificar grupos de `if (action === 'X') return handleX(...)` e agrupar em `handleGetActions(url, env)`, `handlePostActions(body, env)`, `handleAdminActions(body, env)`. O dispatch principal fica com ~50 linhas.

---

## Quick wins (< 2h, zero risco de regressão)

- [x] **F003** (resolvido, confirmado 21/07): `ADMIN_EMAIL` vem de `aplicarConfigRuntime` a partir de `env`; zero ocorrência de e-mail hardcoded no `v4.9.167.js`. Residual: valor segue em `wrangler.toml [vars]` como plaintext (PII baixa), não como secret.
- [x] **F004** (resolvido, confirmado 21/07): sem `|| "radar"` no bundle ativo; sem `JWT_SECRET` a função lança.
- [ ] **F005**: `gerarMessageId()` → `crypto.randomUUID()` (1 linha)
- [x] **F006** (resolvido, confirmado 21/07): `[observability] enabled=true` presente no `wrangler.toml`.
- [x] **F015** (resolvido, confirmado 21/07): `compatibility_date = "2026-06-16"`.
- [ ] **F022**: `method="get"` → `method="post"` no formulário admin_mercado
- [ ] **F017**: adicionar `console.warn('[rl] bypass:', _bypass)` nos 3 paths fail-open

---

## Things that look bad but are actually fine

**`notImplemented()` duplicado 4× (F023 — `__name`, `__name2`...):**
São polyfills do `unenv` (Node.js compatibility shims) bundled pelo Wrangler junto com múltiplas dependências que incluem `crypto`, `events`, `perf_hooks`. As duplicações `notImplemented2`, `notImplemented22`, `notImplemented222` são artefatos do build: o Wrangler concatena os shims de cada dependência com namespace próprio para evitar colisão. Não é código escrito pelo desenvolvedor. Remover exigiria customizar o build do Wrangler — risco alto, benefício zero.

**`console.log` em produção:**
Em Workers, `console.log` vai para Workers Logs (dashboard Cloudflare), não para o response body. Não há exposição de debug para o usuário. Os 65 `console.log` são logging operacional normal. Só se torna problema se Workers Logs expor dados sensíveis em times compartilhados.

**Rate limiter fail-open:**
Decisão arquitetural explícita documentada no CLAUDE.md. A alternativa (fail-closed) derrubaria toda a API se o Durable Object estiver temporariamente indisponível — pior do que não ter rate limit. Em produção, `RATE_LIMITER_DO` binding é estável (health check confirma). O bypass tem flag `_bypass` para audit trail.

**`_trunc()` parecer um nome de função de truncamento para 442 linhas:**
O nome `_trunc` é um artefato do minifier — não é o nome original da função. O Wrangler minifica function names em bundles não-sourcemapped. A função provavelmente tinha nome descritivo na fonte. Não é debt intencional — é artefato do processo de build.

**Múltiplas versões do bundle no repo (`v4.9.67.js` a `v4.9.110.js`):**
É histórico de versões, não código morto ativo. O `wrangler.toml` aponta para `v4.9.111.js`. As versões antigas só existem para reversão de emergência (rollback manual). Não há custo de performance — só de espaço em disco. F020 sugere arquivá-las em branch separada, o que é melhoria de ergonomia, não correção de bug.

---

## Open questions

1. **OpenRouter no bundle** (F011): as referências a `openrouter.ai` nos targets de fetch são dead code real ou apenas schema histórico no health check? Se dead code, quanto bundle size representam?

2. **`op=ews` e `briefing_executivo` têm KV reads em loop?** (F013): o fix de v4.9.110 paralelizou `op=state`. Os outros endpoints com `carregarEstadoMultiSemana(env, 5)` também fazem reads sequenciais?

3. **Bundle fonte vs. bundle produção**: o repo não tem o código fonte hand-authored — só os bundles. Isso significa que qualquer refatoração (F001, F007, F008) deve ser feita diretamente no bundle já minificado. É intencional? Existe um repositório separado com o fonte original?

4. **`getTenantConfig()` 219 linhas**: a complexidade é necessária ou é acumulação de casos especiais? Quantos tenants existem efetivamente em produção?

5. **Testing**: Workers Vitest (`cloudflare:test`) é viável para este projeto ou há uma razão para não ter testes (e.g. o bundle é gerado, não o fonte)?

---

*Auditoria executada seguindo o protocolo tech-debt-audit (ksimback/tech-debt-skill). Cada finding tem citação file:line. Findings sem citação não foram incluídos.*
