# Auditoria Completa — VIX Radar (2026-07-02)

Skill `/vix-radar-audit`. Base: última auditoria [[33 - Auditoria Geral 2026-06-22]] + `PENDENCIAS.md` (2026-06-21).

## Síntese executiva

**Atualizado após bloco D autenticado.** Health público segue verde (Worker v4.9.143 = repo = prod, frontend v201.69 = repo = deploy_zip = prod, sem drift). Porém bloco D revelou **CRÍTICO real, não cosmético**: `list_scheduled_tasks` retornou vazio — as 5 scheduled tasks (incl. `vixradar-noturno`/`vixradar-matinal`) estavam desregistradas do agendador Claude Code, mesmo padrão do incidente 2026-06-15 (reinstalação zera o registro; SKILL.md sobrevive órfão em disco). Consequência: ingestão automática parada há **9 dias** — `estado_semanal.updated_at` e `contexto_historico` de todos os 103 emissores travados em `2026-06-23`; `listar_plano_rotina` retornou **103/103 em tier FULL** (`horas_stale:219.6` = 9,15 dias), 0 em SKIP/LIGHT. **Corrigido nesta sessão**: as 5 tasks foram recriadas via `register-all-routines.ps1` + `create_scheduled_task` (runbook `REGISTRAR-TODAS.md`); `list_scheduled_tasks` confirma 5/5 `enabled:true` com `nextRunAt` coerente. Próxima execução automática da noturna: 2026-07-03 ~18h05 BRT — ainda não fecha o gap retroativo de 9 dias (decisão de rodar catch-up manual em aberto com o operador, custo ~500k tokens).

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker `radar-credito-api` | v4.9.143 (`wrangler.toml:50`) | v4.9.143 (`GET /` workers.dev) | Nenhum ✅ |
| Frontend `vixradar.com` | v201.69 (`CACHE_VERSION` em `app/index.html:3598`) | v201.69 (`version.json`) | Nenhum ✅ |
| `app/index.html` vs `app/deploy_zip/index.html` | 6603 linhas | 6603 linhas, `diff` vazio | Nenhum ✅ |

## Incidentes abertos

**NOVO — Ingestão automática parada 9 dias (2026-06-23 → 2026-07-02), RESOLVIDO nesta sessão** — ver CRÍTICO abaixo. 7 CRITICOs de conteúdo (rotina noturna 20/06) seguem em acompanhamento separado — ver [[30 - Monitor CRITICOs 2026-06-20]] (não é falha de sistema, é conteúdo de crédito).

## Achados

### CRÍTICO

- **Scheduler Claude Code zerado — rotinas matinal/noturno/agenda-semanal/fechamento/macro fora do ar há ≥9 dias.** Evidência bruta: `list_scheduled_tasks` → `"No scheduled tasks found"` (antes da correção). `dados_para_analise` CEMIG → `"contexto_historico":"Última análise: 2026-06-23"`. `admin_health_check` → `estado_semanal.updated_at:"2026-06-23T22:06:37.578Z"`. `listar_plano_rotina` → `"contagem_tiers":{"SKIP":0,"LIGHT":0,"FULL":103,"AUDIT":0}`, todos os 103 emissores com `"horas_stale":219.6` (~9,15 dias), `"motivos":["stale_5d"]`. Causa raiz: mesma classe do incidente 2026-06-15 (nota `03`, linha ~253) — reinstalação/atualização do Claude Desktop apaga o registro interno do agendador; os `SKILL.md` sobrevivem órfãos em `C:\Users\User\.claude\scheduled-tasks\`.
  - **Correção aplicada:** `pwsh register-all-routines.ps1` (gera manifest + backup) seguido de `create_scheduled_task` para as 5 tasks (`vixradar-noturno` 18h diário, `vixradar-matinal` 10h seg-sex, `vixradar-agenda-semanal` 03h segunda, `fechamento-diario-szuchmacher` 19h seg-sex, `atualizar-agenda-macro-szuchmacher` 07:07 sexta), prompts lidos integralmente dos `SKILL.md` em disco.
  - **Validação:** `list_scheduled_tasks` pós-correção → 5/5 `enabled:true`, `nextRunAt` coerente (noturno `2026-07-03T21:05Z`≈18:05 BRT; matinal `2026-07-03T13:06Z`≈10:06 BRT; agenda-semanal `2026-07-06T06:00Z`≈03:00 BRT seg; fechamento `2026-07-03T22:07Z`≈19:07 BRT; macro `2026-07-03T10:15Z`≈07:15 BRT sex).
  - **Pendência residual:** gap retroativo de 9 dias (23/06–02/07) não é preenchido automaticamente — próxima execução da noturna só cobre a partir de hoje. Decisão de disparar catch-up manual (`Run now` na task, custo ~500k tokens) em aberto com o operador.
  - **Recomendação de hardening:** este é o **segundo** ocorrência do mesmo modo de falha (15/06 e agora). Considerar alerta automatizado (ex.: healthcheck do Worker comparando `estado_semanal.updated_at` contra limiar de N horas e notificando se stale) em vez de depender de auditoria manual para detectar.

### ALTO

Nenhum novo. Reconfirmar A1/A2 de `PENDENCIAS.md` (verificador_ok = presença de chave, não ping vivo; `sem_eventos:true` atualiza `_last_scanned_at`) fica para próxima auditoria — parcialmente mitigado pelo achado CRÍTICO acima, que também demonstrou o mesmo modo de cegueira silenciosa (health `ok:true` não detectou o scheduler zerado).

### MÉDIO

- **Working tree sujo com artefatos novos não rastreados** desde commit `d796738` (22/06) — evidência: `git status --short` lista `FIGMA-INTEGRATION.md`, `Obsidian VIX Radar/rotinas/`, `agent-tools/`, `app/_arquivo/`, `app/design/`, `app/index.prod.html`, `app/landing-demo.json`, `scripts/azul_payload.json`, `scripts/fix-kora-scan.py`, `scripts/install-project-dev-skills.ps1`, `scripts/ipad-*.md`, `scripts/preview-landing.ps1`, `scripts/register-vixradar-tasks.ps1`, `scripts/revert-landing*.ps1`, `terminals/`, `workspace.code-workspace`. Nenhum destes está no caminho de deploy (`app/deploy_zip/`), sem risco de produção — mas commit/triagem pendente.
- **`app/index.prod.html`** (687 KB, datado 18/06) é artefato solto na raiz de `app/`, fora de `deploy_zip/` e `_arquivo/`. Não referenciado por scripts de deploy (grep confirma apenas ocorrências internas de `CACHE_VERSION`). Risco baixo, mas nome ambíguo (`.prod.`) pode confundir deploy manual futuro — mover para `app/_arquivo/` ou remover.
- Nota `03 - Estado de Produção.md` modificada localmente (não commitada) — não avaliado o diff nesta rodada (fora do escopo quick); mesma nota já tinha seções internas stale registradas em `PENDENCIAS.md` item D1.

### BAIXO

Nenhum novo.

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` (workers.dev) | `ok:true` | `{"ok":true,"versao":"v4.9.143","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}` HTTP 200, 0.204s |
| `POST /` anônimo | 401 fail-closed | `{"ok":false,"erro":"Autenticação necessária."}` HTTP 401 |
| `GET vixradar.com/version.json` | v201.69 | HTTP 200 |
| CSS `<strong>` global | sem `color` | `app/index.html:2699-2701` — só `font-weight:600` ✅ |
| `tel_test` (admin_senha) | `binding_presente:true`, `write_result.ok:true` | HTTP 200 |
| `admin_health_check` | `kv/anthropic/resend/telemetria/jwt_secret:true` | HTTP 200; revelou `estado_semanal.updated_at` stale (ver CRÍTICO) |
| `dados_para_analise` (CEMIG) | CVM documentos até 26/06 corretos; `contexto_historico` stale | HTTP 200 |
| `listar_plano_rotina` | 103/103 FULL, `horas_stale:219.6` | HTTP 200 — evidência-chave do CRÍTICO |
| `list_scheduled_tasks` (antes) | vazio | confirmou causa raiz |
| `list_scheduled_tasks` (depois) | 5/5 `enabled:true` | confirmou correção |

## Lacunas

- `admin_verificar_evento` (verificador vivo, sintético) **não executado** nesta rodada — priorizado o achado do scheduler.
- `receber_analise` smoke (mutação real em produção) **não executado** — decisão consciente de não escrever em KV de emissor real sem confirmação do operador.
- Quarantine KV `radar:auditoria:verificador_indisponivel:{data}` não lida — pendência Q-KV de `PENDENCIAS.md` segue sem cobertura no protocolo padrão.
- Watchdog `stale_count:1` não reinvestigado.
- Admin HEART Fase 2b: não verificado progresso.
- Catch-up retroativo dos 9 dias sem varredura: não disparado (decisão de custo pendente com operador).

## Próximos passos

- **P0 (resolvido nesta sessão)** — ~~Scheduler zerado~~ 5 tasks recriadas e validadas.
- **P1** — Decidir com operador: disparar `vixradar-noturno` manualmente agora (catch-up ~500k tokens) ou aceitar que o gap de 9 dias só é coberto incrementalmente a partir da próxima execução automática (amanhã 18h BRT).
- **P1** — Hardening: alerta automatizado para scheduler zerado (2ª ocorrência do mesmo modo de falha) — não depender de auditoria manual.
- **P1** — Triar working tree: separar artefatos de deploy (nenhum) de hygiene (mover `app/index.prod.html`, decidir sobre `agent-tools/`, `terminals/`, `scripts/*.ps1` avulsos — commit ou `.gitignore`).
- **P2** — Ler quarantine KV do dia para fechar Q-KV.
- **P3** — Resolver diff pendente em `03 - Estado de Produção.md` (commit ou revert).
