---
name: vix-radar-audit
description: >
  VIX Radar auditoria operacional do sistema, incluindo vistoria completa ou quick audit
  de Worker, Pages, wrangler, KV/DO, auth/CORS, telemetria, verificador, rotinas Claude,
  drift repo/producao e monitoramento em loop de 40 segundos ate estabilizar ou terminar
  o processo observado. Use quando o usuario pedir auditoria completa, vistoria
  operacional, auditar sistema, pos-deploy, pos-incidente, validar producao, checar drift,
  loop de health, verificacao em 40 segundos, readonly audit, ou antes de encerrar sessao
  com mudanca de codigo/deploy. Tambem use quando a data de atualizacao estiver antiga,
  presa ou divergente, ou quando for preciso provar cobertura recente dos 103 emissores.
  Nao usar para carteiras nem briefing rapido.
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
7. **ACK não prova atualização** — `ok:true`/`submit_ok:true` não prova que `_last_scanned_at` avançou; medir os 103 emissores após toda rotina.

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
- **`--loop-40s`:** repetir health público a cada 40s; só encerrar quando o processo/rotina observada terminar ou quando o operador interromper.

---

## Loop 40s — monitoramento até término

Use quando o operador pedir "verificação em loop de 40 segundos", "loop do code" ou equivalente.

1. Confirmar o alvo observado: por padrão, `https://api.vixradar.com/`; se o usuário mencionar processo local, coletar também `Get-Process`/`Get-CimInstance Win32_Process` filtrando pelo nome relevante.
2. Executar ciclos de 40s registrando horário BRT, HTTP, tempo total, `versao`, `ok`, `kv`, `telemetria`, `verificador_ok`.
3. Não considerar "qualquer Codex vivo" como critério de bloqueio, pois a própria sessão mantém processos `Codex/codex`. Se não houver alvo local inequívoco, usar saúde de produção + instrução explícita do operador como critério.
4. Se qualquer ciclo falhar, coletar bruto: resposta, HTTP, erro de rede, tempo, e repetir uma vez antes de concluir incidente.
5. Ao final, registrar a tabela curta em `Obsidian VIX Radar/03 - Estado de Produção.md`; se houve falha, criar nota de auditoria/incidente no vault.

Comando base:

```powershell
$url='https://api.vixradar.com'
while ($true) {
  $ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
  $resp = curl.exe -s $url -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
  "--- LOOP 40s / $ts ---"
  $resp
  Start-Sleep -Seconds 40
}
```

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
- Executar `scripts/audit-routine-staleness.ps1` desta skill. Gate saudável: `total=103`, `stale_24h_real=0`, `presos_data=0` e timestamp máximo dentro do SLA. `stale_24h_inconclusivo` (emissor com `_status:"INCONCLUSIVO"`, clock pausado de propósito pelo mecanismo FIN1 até promoção a tier FULL — desde v4.9.159) **não** conta para o gate nem para severidade ALTO; é staleness intencional, não achado.
- Cruzar: `listar_todos_emissores` (103) vs plano completo; amostra de `dados_para_analise` é evidência complementar, nunca substitui o gate dos 103.
- Semana KV atual (`semanaISO`) e janela 30 dias

### Data antiga ou presa

1. Receber a data reclamada em `-StuckDate YYYY-MM-DD` (ex.: `2026-06-26`).
2. Rodar o verificador antes de qualquer correção e guardar o JSON bruto.
3. Diferenciar `data_evento` (data do fato), `timestamp/_last_scanned_at` (data da análise) e `estado.updated_at` (última escrita no KV). Não corrigir o campo errado.
4. Após reprocessar, rodar novamente. Não fechar se qualquer emissor permanecer em `stale_24h_real` ou `presos_data`.
5. Não avançar timestamp com payload fictício. Cobertura curta deve ser marcada explicitamente como inconclusiva e eventos só entram com fonte profunda verificável.

---

## Severidade dos achados

| Nível | Critério |
|---|---|
| **CRÍTICO** | Ingestão cega, perda de dados, credencial inválida, drift prod/repo no bundle ativo |
| **ALTO** | Telemetria off, verificador off, auth fail-open, cron quebrado |
| **ALTO** | Data de análise presa, qualquer emissor `stale_24h_real` (exclui `stale_24h_inconclusivo`), ou relatório 103/103 sem prova de `_last_scanned_at` |
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
