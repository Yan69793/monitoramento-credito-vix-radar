# Auditoria Completa — VIX Radar (2026-06-30)

Data: 2026-06-30T01:05Z | Invocação: `/vix-radar-audit` (monitoramento + auditoria solicitado)
Ambiente: sessão remota Claude Code (web) — branch `claude/vixradar-monitoring-audit-k7i0bv`
Método: [[13 - Metodo de Vistoria Operacional]] | Anterior: [[24 - Auditoria Completa 2026-06-18 (pós v4.9.141)]]

---

## Síntese executiva

Sistema **operacional e saudável em produção** (HTTP 200, `ok:true`, KV, telemetria e rate_limiter ativos — evidência ao vivo via CI canonical-test 2026-06-29T20:11Z). **Porém há DRIFT de source control ativo (reincidência):** produção roda **v4.9.143**, mas o repositório está em **v4.9.141** — os bundles **v4.9.142 e v4.9.143 não foram commitados**. Risco concreto de **regressão silenciosa** no próximo `wrangler deploy` a partir do repo.

**Veredito:** produção saudável; governança de código degradada. P0 = reconciliar drift.

---

## Restrição de ambiente (lacuna metodológica importante)

Esta auditoria rodou em **sessão remota com política de egresso restritiva**. Os hosts de produção estão **bloqueados** para esta sessão:

- `radar-credito-api.prospects-intel.workers.dev` → `403 connect_rejected` (proxy)
- `api.vixradar.com` / `vixradar.com` → idem
- curl **e** WebFetch retornam 403 (policy denial, não contornável — confirmado em `/root/.ccr/README.md`).

**Consequência:** `GET /` direto, testes autenticados (`tel_test`, `admin_health_check`, `dados_para_analise`, `receber_analise` smoke) e validação frontend ao vivo **não puderam ser executados desta sessão**. Substitutos usados:

| Evidência ao vivo necessária | Substituto auditável usado |
|---|---|
| `GET /` health + versão prod | **Log do CI `canonical-test` run #59** (GitHub Actions, fora do bloqueio) — faz o `GET https://api.vixradar.com/` real |
| Worker existe / control plane | Cloudflare MCP `workers_get_worker` (id `eb5c98f7...`) |

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker bundle | **v4.9.141** (`api/wrangler.toml main`) | **v4.9.143** | ⛔ **SIM — prod à frente do repo (2 versões)** |
| Bundles no repo | máx `api/v4.9.141.js` | v4.9.142/143 ausentes | ⛔ source não commitada |
| CI `EXPECTED_WORKER` | v4.9.141 | v4.9.143 | ⚠️ emite `::warning::` a cada run |
| Obsidian `03 - Estado` | v4.9.141 | v4.9.143 | ⚠️ desatualizado |
| Frontend repo | v201.69 (`app/version.json`, `CACHE_VERSION`) | v201.69 (não verificável ao vivo nesta sessão) | Repo consistente; prod = **lacuna** |

**Evidência bruta do drift (CI run #59, job 84147221747, 2026-06-29T20:11:25Z):**
```
##[warning]Worker drift. Esperado v4.9.141, produção em v4.9.143.
Produção saudável.
```

---

## Health de produção (ao vivo, via CI 2026-06-29T20:11Z)

O step "Validate health" do `canonical-test.yml` faz `exit 1` se HTTP≠200, `ok`≠true, `kv`≠true ou `telemetria`≠true. Run **success** ⇒ todos verdadeiros ao vivo:

| Campo | Valor (ao vivo) | Fonte |
|---|---|---|
| HTTP | **200** | gate passou |
| `ok` | **true** | gate passou |
| `bindings.kv` | **true** | gate passou |
| `bindings.telemetria` | **true** (regra inviolável OK) | gate passou |
| `bindings.rate_limiter` | **true** | sem `::warning::` de RL no log |
| `versao` | **v4.9.143** | warning de drift |

Runs anteriores (#50–#59, 2026-06-27 a 06-29): **10/10 success**. Produção estável há ≥3 dias.

---

## Achados

### CRÍTICO

- **Drift source control prod/repo no bundle ativo (reincidência).** Produção em **v4.9.143**; repo em **v4.9.141**; bundles v4.9.142/143 **não existem no repo** (`ls api/v4.9.14[23].js` → not found) e **não há commit** mencionando-os (`git log --all | grep 4.9.14[23]` → vazio). Próximo `npx wrangler deploy` a partir de `api/wrangler.toml` (`main="v4.9.141.js"`) **regrediria produção de v4.9.143 → v4.9.141**, descartando silenciosamente as mudanças de 142/143. É exatamente o padrão de drift já documentado em 2026-06-01 e 2026-05-07.
  - **Evidência:** CI log run #59 (acima); `ls api/` topo = v4.9.141.js; `git log` sem 142/143.
  - **Lacuna:** o *conteúdo* das mudanças v4.9.142→143 é desconhecido desta sessão (bundle deployado ~753KB recuperável via Cloudflare MCP, mas não cabe no contexto). Hipótese plausível (não confirmada): itens de backlog da nota 23 (expor `rejeitados`; incluir Raízen em `EMISSORES`).

### MÉDIO

- **`CI EXPECTED_WORKER` e `03 - Estado de Produção` desatualizados** (citam v4.9.141). Devem ir para v4.9.143 **somente após** os bundles serem recuperados/commitados — atualizar o número antes de ter a fonte mascararia o drift.
- **`admin_mercado` senha em query string** (herdado da auditoria 24, P2). Refactor POST pendente.

### BAIXO

- **Frontend prod não verificável ao vivo** nesta sessão (host bloqueado). Repo consistente em v201.69; última confirmação ao vivo foi 2026-06-18 (auditoria 24).
- Itens de hygiene da nota 24 ainda abertos (`scheduled-tasks/backups/` com chave antiga; watchdog `stale_count`).

---

## Bloco C — Worker técnico (estático, sobre `api/v4.9.141.js`)

Auditoria do bundle apontado pelo `wrangler.toml` (não o deployado, que é v4.9.143 — ver lacuna):

| Item | Resultado | Evidência |
|---|---|---|
| `[observability] enabled` | ✅ true, `head_sampling_rate=1` | `wrangler.toml` |
| Binding `RADAR_KV` declarado+usado | ✅ 277 usos | grep |
| Binding `RATE_LIMITER_DO` declarado+usado | ✅ 8 usos | grep |
| Binding `RADAR_USAGE_EVENTS` declarado+usado | ✅ 26 usos, `writeDataPoint` presente | grep (regra inviolável de telemetria OK) |
| Secrets literais hardcoded | ✅ nenhum (`sk-ant`/`sk-or`/`AIza`/`xoxb` → 0) | grep |
| `carregarEstadoMultiSemana` (regra multi-semana) | ✅ 32 ocorrências | grep |
| Universo emissores | ✅ 103 (`EMISSORES_LISTA` 48 refs; noturno SKILL cita 103) | grep |

## Bloco E — Frontend (estático, `app/index.html`)

| Item | Resultado | Evidência |
|---|---|---|
| Regra CSS global `<strong>` **sem** `color` (inviolável) | ✅ `strong, .text-strong, [class*="strong"] { font-weight: 600; }` | linha 2699-2701 |
| Overrides específicos com color | ✅ permitidos (`.ews-disclaimer strong`, `.com-author-label strong`) | linhas 1059/1135 |
| `CACHE_VERSION` = `version.json` | ✅ ambos v201.69 | grep |

---

## Repo / git

- `git status --short` → **limpo** (working tree sem alterações na entrada).
- `git log -1` → `892ccca ci: remove workflow temporario run-matinal`.
- Branch de trabalho: `claude/vixradar-monitoring-audit-k7i0bv`.

---

## Lacunas (não testado e por quê)

1. **`GET /` direto, frontend ao vivo, endpoints autenticados** — host de produção bloqueado pela política de egresso desta sessão remota (403). Cobertos parcialmente pelo CI canonical-test (só health do Worker, não frontend nem ingestão profunda).
2. **Conteúdo de v4.9.142/143** — bundle deployado (~753KB) recuperável via Cloudflare MCP `workers_get_worker_code`, mas excede o orçamento de contexto; não inspecionado.
3. **`receber_analise` smoke / verificador Haiku vivo** — exige `ROUTINE_API_KEY`/`admin_senha` e POST autenticado a host bloqueado.
4. **Scan de staleness KV (cobertura real 103/103 ao vivo)** — depende de `dados_para_analise` autenticado.

---

## Próximos passos

| P | Ação | Detalhe |
|---|---|---|
| **P0** | **Reconciliar drift** | De uma sessão com acesso à Cloudflare (ou local com token): `wrangler` → recuperar bundle deployado v4.9.143 → salvar `api/v4.9.143.js` → `wrangler.toml main="v4.9.143.js"` → commitar. Snapshot bruto antes. |
| **P0** | Atualizar `EXPECTED_WORKER=v4.9.143` no CI **após** commitar o bundle | evita warning recorrente e re-arma a defesa anti-drift |
| P1 | Atualizar `03 - Estado de Produção` para v4.9.143 (após recuperar bundle) | |
| P1 | Confirmar diff v4.9.141→143 e documentar o que mudou | provável backlog nota 23 |
| P2 | `admin_mercado` → auth POST (senha fora da URL) | herdado |
| P2 | Validar frontend + endpoints autenticados de sessão com egresso liberado | fechar lacunas 1, 3, 4 |

---

## Nota de processo

Recomenda-se **bloquear `wrangler deploy` a partir de repo com drift detectado** (guard no CI ou pre-deploy hook que compara `main` do `.toml` com `versao` de `GET /`). O drift prod-à-frente-do-repo já reincidiu 3× (2026-05-07, 2026-06-01, 2026-06-30): a causa estrutural é deploy direto sem commit do bundle. Sem guard automatizado, vai repetir.
