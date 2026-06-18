---
name: vix-radar-audit
description: >
  VIX Radar auditoria completa do sistema. Invocado como /vix-radar-audit para vistoria
  multi-camada: Worker, Pages, wrangler, KV/DO, auth/CORS, telemetria, verificador,
  rotinas Claude e drift repo/producao. Segue Obsidian nota 13 + workers-best-practices.
  Use quando: auditoria completa, vistoria operacional, auditar sistema, pos-deploy,
  pos-incidente, validar producao, checar drift, readonly audit, antes de encerrar sessao
  com mudanca de codigo/deploy. NAO usar para carteiras (/verificar = verificacao-carteiras-v2)
  nem briefing rapido (/vix-radar-briefing).
argument-hint: "[--readonly] [--quick]"
---

# VIX Radar — Auditoria Completa do Sistema

Vistoria operacional multi-camada do VIX Radar. Protocolo canônico: `Obsidian VIX Radar/13 - Metodo de Vistoria Operacional.md`.

**Diferença das outras skills VIX Radar:**

| Skill | Escopo | Tempo |
|---|---|---|
| `/vix-radar-audit` | Auditoria completa com evidências | 5–20 min |
| `/vix-radar-briefing` | Health resumido | ~5s |
| `/vix-radar-next-steps` | Priorização pós-leitura vault | ~30s |

---

## Regras invioláveis da auditoria

1. **Fato ≠ interpretação** — separar evidência bruta de conclusão.
2. **`GET /` necessário, não suficiente** — health `ok:true` não prova verificador, ingestão nem telemetria end-to-end.
3. **Achado só com prova** — arquivo+linha, diff, HTTP bruto, chave KV, output de ferramenta.
4. **Lacunas explícitas** — se não coletou prova, registrar por quê (escopo, credencial, custo).
5. **Não inventar** — sem suposição de versão, deploy ou estado KV.
6. **Registrar no vault** — ao final, criar/atualizar nota `Obsidian VIX Radar/NN - Auditoria Completa YYYY-MM-DD.md` (nunca sobrescrever nota 13).

---

## Antes de começar — ler obrigatoriamente

1. `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\00 - Índice (MOC).md`
2. `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\03 - Estado de Produção.md`
3. Última auditoria no vault (`14 - Auditoria Completa *.md` ou `09/12 - Auditoria *.md`)
4. **Carregar skill** `workers-best-practices` — aplicar checklist Worker (bindings, secrets, `waitUntil`, promises, observabilidade)

Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`

---

## Modos

- **Padrão:** auditoria completa (6 blocos abaixo).
- **`--readonly`:** só coleta evidência; não edita código, não deploy, não secrets, não POST destrutivo.
- **`--quick`:** blocos A+B+D apenas (documental + health + config); pular testes autenticados profundos.

---

## Bloco A — Estado documental e repo

```powershell
cd 'E:\Diretorio\Claude\Monitoramento de Credito'
git status --short
git log -1 --oneline
```

Extrair e comparar:

| Camada | Onde olhar |
|---|---|
| Worker repo | `api/wrangler.toml` → `main`, `api/v4.*.js` → `WORKER_VERSAO` |
| Worker prod | `GET https://radar-credito-api.prospects-intel.workers.dev/` → `versao` |
| Frontend repo | `app/version.json`, `app/index.html` → `CACHE_VERSION` |
| Frontend prod | `https://vixradar.com/version.json` |

**Drift crítico:** `main` no wrangler ≠ bundle em prod; repo sujo com fix não commitado; `producao/` e `api/v4.9.*` untracked são legado — não contaminar conclusão.

---

## Bloco B — Health público e bindings

```powershell
curl.exe -s --max-time 10 'https://radar-credito-api.prospects-intel.workers.dev/'
```

Registrar bruto: `ok`, `versao`, `telemetria`, `bindings`, `providers_configurados`, `verificador_ok`.

**Interpretação mínima:**

- `telemetria:false` → perda de observabilidade
- `verificador_ok:false` → ingestão pode falhar silenciosamente (`n_eventos:0` com ACK 200)
- `providers_configurados` < esperado → provider ausente

---

## Bloco C — Worker técnico (`workers-best-practices`)

Auditar o bundle apontado por `wrangler.toml`:

- `[observability]` habilitado
- Bindings declarados vs uso no código (`RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS`)
- Secrets via env (nunca hardcoded) — `ADMIN_EMAIL`, `ANTHROPIC_API_KEY`, `ROUTINE_API_KEY`
- Anti-padrões: promises flutuantes, estado global por request, streaming incorreto
- **Path crítico `receber_analise`:** eventos validados persistem; `sem_eventos` deriva de `_raEvs.length`, não de schema legado

---

## Bloco D — Endpoints e ingestão

Testes em ordem de risco (preferir readonly):

| Teste | Método | O que prova |
|---|---|---|
| Health | `GET /` | Versão + bindings superficiais |
| Anônimo bloqueado | `POST {}` sem JWT | Auth fail-closed (401) |
| `tel_test` | `action=tel_test` + `routine_key` | Telemetria write |
| `admin_health_check` | `action=admin_health_check` + senha | Estado interno, `anthropic`, `resend` |
| `admin_verificar_evento` | payload mínimo | Verificador Haiku vivo (não 401) |
| `dados_para_analise` | emissor canônico | KV tem `_last_scanned_at`, CVM na janela |
| `receber_analise` smoke | JSON mínimo em `testing/` | `n_eventos` coerente com payload |

**ROUTINE_KEY:** em `C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md` (não repetir em chat).

**Armadilhas conhecidas:**

- ACK `ok:true` + `n_eventos:0` + `sem_eventos:true` com eventos no JSON → bug ingestão ou verificador rejeitou tudo
- Python `urllib` → 403 WAF; usar `curl.exe`
- `listar_emissores_prioritarios top_n=103` retorna menos que 103 quando staleness baixo — não é gap de cobertura

---

## Bloco E — Frontend e CORS

- `https://vixradar.com/version.json` vs repo
- Auth anônimo em rotas protegidas → 401
- Regra CSS inviolável (CLAUDE.md): `<strong>` global **sem** `color` — só `font-weight:600`; herda cor do pai. Overrides específicos (`.ews-disclaimer strong`, etc.) podem ter `color`. **Não** adicionar `color` na regra global.

---

## Bloco F — Rotinas e cobertura emissores

- Rotina noturna: `vixradar-noturno` — 103 emissores (`EMISSORES_LISTA` no Worker)
- Cruzar: `listar_todos_emissores` (103) vs scan recente via `dados_para_analise` amostra
- Semana KV atual (`semanaISO`) e janela 30 dias

---

## Severidade dos achados

| Nível | Critério |
|---|---|
| **CRÍTICO** | Ingestão cega, perda de dados, credencial inválida, drift prod/repo no bundle ativo |
| **ALTO** | Telemetria off, verificador off, auth fail-open, cron quebrado |
| **MÉDIO** | Documentação desatualizada, untracked sem impacto em prod |
| **BAIXO** | Débito técnico, legado em `producao/` |

---

## Formato de saída (obrigatório)

```markdown
# Auditoria Completa — VIX Radar (YYYY-MM-DD)

## Síntese executiva
[1–3 frases: saudável / degradado / crítico]

## Versões e drift
| Camada | Repo | Produção | Drift? |
...

## Incidentes abertos
...

## Achados
### CRÍTICO
- [achado] — evidência: [bruto]

### ALTO / MÉDIO / BAIXO
...

## Validação em produção
[tabela teste → resultado → evidência]

## Lacunas
[o que não foi testado e por quê]

## Próximos passos
[P0/P1 acionáveis]
```

Modo caveman permitido na síntese; achados exigem evidência reproduzível.

---

## Pós-auditoria — registrar no vault

1. Criar `Obsidian VIX Radar/NN - Auditoria Completa YYYY-MM-DD.md` (próximo número livre; nota 13 = método, não sobrescrever).
2. Atualizar `03 - Estado de Produção.md` se houve mudança de versão, incidente ou validação.
3. Atualizar `00 - Índice (MOC).md` — link para nova auditoria + pendências.

---

## Skills auxiliares (carregar conforme escopo)

| Skill | Quando |
|---|---|
| `workers-best-practices` | Sempre — bloco C |
| `insecure-defaults` | Secrets, auth, defaults fail-open |
| `web-perf` | Regressão frontend/Pages |
| `cloudflare` | Bindings, crons, deploy, WAF |
| `verification-before-completion` | Antes de declarar "auditoria concluída" |

---

## Quando invocar

- Após **qualquer** deploy Worker/Pages ou mudança em endpoint/auth/KV
- Após incidente (verificador 401, telemetria off, `sem_eventos` falso)
- Início de sessão longa quando briefing não basta
- Pedido explícito: "auditoria completa", "vistoria operacional", "auditar o sistema"

**Não invocar** para relatórios de carteira (`verificacao-carteiras-v2`) nem health de 5 segundos (`vix-radar-session-briefing`).