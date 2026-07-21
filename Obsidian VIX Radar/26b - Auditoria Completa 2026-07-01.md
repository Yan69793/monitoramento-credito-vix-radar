# Auditoria Completa — VIX Radar (2026-07-01)

Data: 2026-07-01T05:32Z | Invocação: `/vix-radar-audit` (sessão remota iPad; usuário reportou "última notícia 23/06")
Método: [[13 - Metodo de Vistoria Operacional]] | Anterior: [[25 - Auditoria Completa 2026-06-30]]

---

## Síntese executiva

Worker **saudável na nuvem**, mas o **produto está degradado**: a **ingestão de notícias está congelada desde 23/06** (~8 dias). Evidência: screenshots do usuário mostram o timeline de eventos parado em 23/06 (Kora Saúde), com hoje = 01/07. Causa raiz: **a varredura de notícias roda como Scheduled Task do Claude Code no PC do operador — não no Worker** — e o PC está offline (usuário no iPad, "sem acesso ao PC"). O health verde do Worker mascarou isso. Persiste também o **drift v4.9.143 (prod) × v4.9.141 (repo)** da auditoria 25.

**Veredito:** infraestrutura OK; pipeline de valor (notícias frescas) **cego**.

---

## Restrição de ambiente

Sessão remota com egresso bloqueado (403) para `api.vixradar.com` / `vixradar.com`. Health ao vivo obtido via **CI GitHub Actions** (fora do bloqueio). Endpoints autenticados e leitura de KV não acessíveis daqui (sem secret `ADMIN_PASSWORD`).

---

## Versões e drift

| Camada | Repo | Produção (live) | Drift? |
|---|---|---|---|
| Worker bundle | v4.9.141 (`api/wrangler.toml main`) | **v4.9.143** | ⛔ prod à frente (2 versões) — bundles 142/143 não commitados |
| CI `EXPECTED_WORKER` | v4.9.141 | v4.9.143 | ⚠️ warning a cada run |
| Frontend | v201.69 (`app/version.json`) | v201.69 (repo; prod não verificável) | Repo consistente |

Evidência live (CI canonical run #65, 2026-07-01T02:02:22Z): `Produção saudável.` + `##[warning]Worker drift. Esperado v4.9.141, produção em v4.9.143.`

---

## Health de produção (live, CI 2026-07-01T02:02Z)

Gate do `canonical-test.yml` faz `exit 1` se HTTP≠200 / ok≠true / kv≠true / telemetria≠true. Run #65 **success** ⇒ HTTP 200, `ok:true`, `kv:true`, `telemetria:true`, `rate_limiter:true`, Worker v4.9.143. Runs #50–#65: sucesso contínuo.

---

## Achados

### CRÍTICO

**A1 — Ingestão de notícias congelada desde 23/06 (produto cego).**
- **Evidência (bruta):** screenshots do usuário (2026-07-01 02:02/02:09 BRT) — timeline de eventos do dashboard tem como item mais recente **23/06 (Kora Saúde, "Assembleia Geral de Debenturistas", fonte rad.cvm.gov.br)**; nada entre 24/06 e 01/07. Rodapé exibe "Sistema operacional" (verde) — enganoso.
- **Causa raiz confirmada (documental):** `routines/README.md` (fonte canônica versionada): *"As rotinas `vixradar-matinal` e `vixradar-noturno` são Scheduled Tasks do Claude Code (desktop), NÃO crons do Cloudflare Worker."* A varredura (9 rodadas WebSearch/emissor → `POST receber_analise`) depende do **PC do operador ligado com Claude desktop**. O usuário está **no iPad, sem acesso ao PC** → nenhuma varredura desde ~23/06 → nenhum evento novo persistido.
- **Por que o Worker fica verde:** health/telemetria/KV/EWS-recalc rodam na nuvem, independentes do PC. Só a geração de eventos (WebSearch) é desktop. Daí EWS scores atualizam (Oi 66, Onco 61) mas o feed de eventos congela.
- **Modo de falha conhecido reincidente:** README documenta que reinstalação do Claude desktop zera o agendador silenciosamente (incidente 2026-06-15). Alternativa à hipótese "PC desligado".
- **Descartado:** gate rejeitando tudo por 7 dias — improvável; o evento Kora 23/06 passou com fonte CVM primária, logo o gate funciona.
- **Impacto:** o núcleo do produto (alerta de crédito fresco) está sem atualização há ~8 dias, e isso ficou invisível porque nenhum monitor cobria frescor de ingestão (corrigido nesta sessão — ver Mitigação).

### CRÍTICO (herdado — auditoria 25)

**A2 — Drift source control prod/repo.** Produção v4.9.143; repo v4.9.141; bundles 142/143 não commitados. Risco: `wrangler deploy` do repo regride prod 143→141. Recuperação pendente.

### MÉDIO
- `EXPECTED_WORKER` e `03 - Estado` citam v4.9.141 (atualizar só após recuperar bundle 143).
- `admin_mercado` senha em query string (herdado).

---

## Mitigação implementada nesta sessão (2026-06-30 → 07-01)

Para nunca mais o frescor congelar sem alerta:
1. **Workflow `frescor-check.yml`** (GitHub Actions, na `main`): consulta `admin_health_check` (`empresas_com_dados` + `updated_at`) e `admin_custo` (gasto do dia) via `api.vixradar.com` — fora do bloqueio de egresso.
2. **Agenda diária** 22:37 BRT + **gate de frescor**: FALHA (exit 1) se cobertura < 50/103 ou estado > 48h → **GitHub envia email automático** ao dono. Alerta hands-off de "notícias paradas".
3. **Trigger de sessão** "VIX Radar — frescor diário" (`trig_01B4dbLeSg8N…`, 02:00 UTC): puxa o resultado e entrega print HTML no chat.
4. **Bloqueio:** os passos 1–2 só produzem dados reais quando o secret **`ADMIN_PASSWORD`** existir no repo (só o dono pode criar; senha nunca em chat/código). Até lá, o run sai limpo (exit 0) — confirmado no frescor run #2 (2026-07-01T02:02Z): `Sem senha disponivel`.

---

## Validação em produção (live)

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` health (via CI #65) | ✅ v4.9.143, saudável | `Produção saudável.` 2026-07-01T02:02:22Z |
| Bindings kv/telemetria/rate_limiter | ✅ true | gate CI passou |
| Frescor (frescor run #2) | ⚠️ sem dados | `Sem senha disponivel` (secret ausente) |
| Ingestão de eventos | ⛔ congelada 23/06 | screenshots do usuário |

---

## Verificações estáticas (sem achados)

- **Worker v4.9.141.js:** `[observability]` on; RADAR_KV (277)/RATE_LIMITER_DO (8)/RADAR_USAGE_EVENTS (26, `writeDataPoint`) declarados+usados; zero segredos literais; `carregarEstadoMultiSemana` 32×.
- **Frontend:** regra CSS global `<strong>` = `font-weight:600` sem `color` (linha 2699); `CACHE_VERSION`=`version.json`=v201.69.

---

## Lacunas

1. **Confirmação objetiva da causa A1** — exige `admin_custo` histórico (gasto zero pós-23/06) ou `list_scheduled_tasks` no PC. Ambos indisponíveis daqui (secret / desktop).
2. **Estado do agendador desktop** — não inspecionável desta sessão remota.
3. **Conteúdo dos bundles 142/143** — ~753KB via Cloudflare MCP, excede contexto.

---

## Próximos passos

| P | Ação |
|---|---|
| **P0** | **Religar a varredura:** ligar o PC com Claude desktop (tasks voltam a disparar 18h/9h). Se sumiram do agendador, reinstalar de `routines/`. |
| **P0** | Criar secret `ADMIN_PASSWORD` no GitHub → ativa o alerta automático de frescor (email + print diário). |
| **P0** | Reconciliar drift: recuperar bundle v4.9.143, commitar `api/v4.9.143.js`, apontar `wrangler.toml`, bumpar `EXPECTED_WORKER`. |
| **P1** | **Durável:** tirar a varredura da dependência do PC (rodar scan em agendador que não dependa da máquina do operador ligada). Elimina a classe inteira de incidente. |
| P2 | Guard anti-drift no CI/pre-deploy. |
