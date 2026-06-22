# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-06-21 | **Skill:** `/vix-radar-audit` (documental + health + config)
**Base auditada:** Worker **v4.9.143** (prod = repo) + Frontend **v201.69** + `wrangler.toml` + health público
**Fontes de evidência:** auditorias frescas em v4.9.143 — Obsidian [[31 - Auditoria Completa 2026-06-20]], [[32 - Auditoria Geral Backend Frontend 2026-06-20]], [[00 - Índice (MOC)]], [[03 - Estado de Produção]]

---

## Síntese executiva

1. **Produção saudável no caminho público.** `GET /` em `api.vixradar.com` e `workers.dev`: `v4.9.143`, `ok:true`, `kv/rate_limiter/telemetria:true`, `providers_configurados:"2/2"`, `verificador_ok:true`. Sem drift de bundle (repo = prod = v4.9.143). Frontend `v201.69` (prod = repo).
2. **Ressalva metodológica permanente:** `verificador_ok:true` e o loop-40s comprovam **presença de secret/bindings**, não ingestão E2E. Mesma classe de cegueira do incidente 2026-06-15. Health verde ≠ pipeline de dados validado.
3. **P1 de frontend admin publicado:** `app/admin/*.js` (fonte) usa `sessionStorage` para `radar_admin_senha`, mas `app/deploy_zip/admin/*.js` **e produção** (`vixradar.com/admin/*.js`) ainda usam `localStorage`. Drift fonte↔deploy↔prod, com a versão menos segura no ar.
4. **Pendências de produto e hygiene** abertas (watchdog heartbeats, Admin HEART Fase 2b, exposição de `rejeitados` em `receber_analise`, working tree sujo).
5. **Acompanhamento operacional:** 7 CRITICOs da rotina noturna 2026-06-20 (conteúdo de crédito, não falha de sistema) — ver [[29 - Rotina Noturna 2026-06-20]] e [[30 - Monitor CRITICOs 2026-06-20]].

> **Evidência health (2026-06-21T19:41:39Z):** `{"ok":true,"versao":"v4.9.143","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}` — HTTP 200 em 0.107s.

---

## Pendências abertas

| ID | Sev | Área | Achado | Evidência | Ação |
|----|-----|------|--------|-----------|------|
| A1 | **ALTO** | Observabilidade / Ingestão | `verificador_ok` reporta **presença de chave**, não ping vivo ao Anthropic | `api/v4.9.143.js:14757` → `verificador_ok: !!env.ANTHROPIC_API_KEY` | Próxima auditoria completa: `admin_verificar_evento` obrigatório + leitura quarantine KV do dia. Considerar ping Haiku mínimo no health. |
| A2 | **ALTO** | Ingestão / Persistência | `receber_analise` pode retornar `ok:true` + `n_eventos:0` se o verificador rejeitar tudo; `persistirResultadoCompartilhado` preserva estado e atualiza `_last_scanned_at` mesmo em `sem_eventos:true` → dashboard parece "escaneado hoje" sem eventos novos | `persistirResultadoCompartilhado` L7538–7545; `receber_analise` L15260–15274 | Backlog: expor `rejeitados` + `veredicto.motivo` + `n_quarentena` no retorno de `receber_analise`. Pós-rotina: cruzar amostra CRITICO com delta KV. |
| ~~F1~~ | ~~P1~~ | Frontend / admin | ~~Drift publicado: senha admin em `localStorage` na prod~~ **RESOLVIDO 2026-06-21** — `deploy_zip/admin/*.js` sincronizado com fonte; deploy Pages `0f72c04b`; prod valida `sessionStorage` (`vixradar.com/admin/vr-admin-shared.js` L96/104, `vr-admin-modules.js` L21/563 — HTTP 200). `radar_jwt`/`HEART_HIST_KEY` seguem `localStorage` (fora do escopo, alinhado ao app) | — |
| D1 | MÉDIO | Documentação / Obsidian | Nota `03 - Estado de Produção` tem seções internas stale: tabela "Drift repo vs produção" (~L368) cita v4.9.118/v201.51; seção "Bindings" (~L226) cita `providers_configurados:"3/3"` (real é 2/2) | leitura direta da nota 03 | Stamp/deprecar seções antigas; header 2026-06-20 já está correto. Risco: auditor lê seção velha e conclui drift inexistente. |
| P-WD | P2 | Rotinas / Watchdog | Watchdog reporta `stale_count:1` (heartbeats) | MOC pendências 2026-06-20 | Investigar qual heartbeat está stale; confirmar cron `0 1 * * *` (22h BRT). |
| P-HE | P2 | Frontend / manutenção | Admin HEART Fase 2b — extração completa do monólito (`vr-admin-shared`); `app/index.html` = 688 KB | nota 32 top-riscos | Continuar extração modular; evitar editar bundle/monólito. |
| P-RH | P2 | Governança repo | Working tree sujo: muitas skills/scripts/artefatos untracked (`.claude/SKILLS-ROUTER.md`, skills novas, `agent-tools/`, `scripts/*`, `app/design/`) | `git status --short` | Separar skill/auditoria/Obsidian em commit próprio; classificar o restante antes de qualquer deploy. |
| Q-KV | MÉDIO | Protocolo auditoria | Bloco D não exige leitura da quarantine KV `radar:auditoria:verificador_indisponivel:{date}` — chave que diagnosticou o incidente 2026-06-15 | nota 31 multi-model "Act on" | Incluir leitura quarantine KV no Bloco D da skill. |
| P-CVM | P3 | Dados / CVM | `admin_corrigir_datas_cvm_kv` em lote pós-matinal | MOC pendências | Rodar em lote após matinal. |
| P-MAT | P3 | Ingestão / verificador | Incidente matinal 18/06: reanálise Onco/Kora/GPA com fonte CVM primária | [[23 - Incidente 2026-06-18 Verificador reprova matinal]] | Reanalisar com fonte CVM primária (gate verdade graduada). |
| B-MID | Backlog | Qualidade / modelos | Model IDs no Worker e paths em `CLAUDE.md` (N09/N10). `VERIFICADOR_CONFIG.model_escalation = "claude-sonnet-4-5-20250929"` stale (Sonnet 4.5; sistema usa 4.6) | `api/v4.9.143.js:9584` | Atualizar para `claude-sonnet-4-6` na próxima edição do bundle. |
| B-BAK | Backlog | Hygiene / segurança | `scheduled-tasks/backups/` contém prompts com chave antiga (não runtime) | MOC backlog | Limpar backups com credencial antiga (não é vetor ativo — chave já rotacionada/403). |
| E-MT | INFO | Email | `email_modo_teste` implementado em v4.9.142 — confirmar se foi ativado pós-deploy v4.9.143 | MOC pendência 2026-06-20 #1 | Verificar/ativar via `email_modo_teste_ativar` se ainda pendente. |
| A11Y | P3 | Acessibilidade | Sinais positivos (`role`, `aria`, `focus`, `Escape`) mas sem passe browser/teclado validando foco/trap em dialogs | nota 32 | Rodar passe visual/teclado com browser quando UX for prioridade. |

---

## A reconfirmar no bundle v4.9.143

Achados originados na auditoria 2026-06-10 contra o bundle **v4.9.102** (snapshot live). O bundle ativo mudou para v4.9.143; estes padrões **não foram reconfirmados** no bundle atual — confiança BAIXA, reauditar antes de agir:

| ID antigo | Padrão | Onde estava (v4.9.102) | Status |
|-----------|--------|------------------------|--------|
| N03 | `innerHTML` com dado externo sem escaping em render legado | `app/index.html:~3407` (anomalias-pre, renders legados) | Reconfirmar no `app/index.html` v201.69 |
| P10 | `admin_senha !== env.ADMIN_PASSWORD` (comparação não constant-time, 8 call sites) | prod:~12800 | Reconfirmar no bundle v4.9.143 |
| P13 | `handleHistoricoEmissor` usa `KV.list()` (eventual consistency ~60s) | prod:~14100 | Reconfirmar; migrar p/ doc único `comentarios:{empresa}` |
| P22 | `handleEmailAcao` usa objeto CORS estático em vez de `corsHeaders(request)` | prod:~7200 | Reconfirmar |
| P19 | `account_id` / KV `id` hardcoded em `wrangler.toml`; CLAUDE.md citava KV id divergente | `api/wrangler.toml:17,22` | Não são secrets; reconfirmar qual KV id é o de prod |
| P20 | `express`/`openai` em `dependencies` sem uso pelo Worker | `api/package.json:3-4` | **Reconfirmado 2026-06-22** — remover; sem risco runtime |
| N12 | `FERIADOS_B3_2028` ausente (`ehDiaPregaoB3` cobre só 2026/2027) | `api/v4.9.143.js:10132–10201` | **Reconfirmado 2026-06-22** — adicionar antes do fim de 2027 |

---

## Histórico resolvido (compacto)

- **v4.9.143 (2026-06-20)** — `listar_plano_rotina` (tiers SKIP/LIGHT/FULL/AUDIT) + `VARREDURA_CRON_AI_ENABLED=false` (delega IA ao Claude tiered). Em prod = repo, CI alinhado.
- **v4.9.142 (2026-06-18)** — `admin_mercado` auth POST (`method="post"` + `formData`); `email_modo_teste` implementado; gitignore `!api/v4.9.142.js`.
- **v4.9.141 (2026-06-18)** — CVM dates + security hardening; ROUTINE_API_KEY rotacionada (chave antiga → 403); `settings.local.json` limpo.
- **Incidente 2026-06-15 (RESOLVIDO 2026-06-16)** — `ANTHROPIC_API_KEY` inválida cegava o verificador → toda ingestão em quarentena. Secret rotacionado via `wrangler secret put`; `admin_verificar_evento` → `quarentenados:0`.
- **v4.9.115 (2026-06-16)** — `ADMIN_EMAIL` movido para `env` (removido do bundle); health sem dependência de OpenRouter (P11 antigo).
- **OpenRouter 402/401 (RESOLVIDO 2026-06-16)** — causa real: `OPENROUTER_API_KEY` inválida (não billing). Secret removido; probe retorna `sem_chave_openrouter` gracioso. Cascade externa obsoleta desde v4.9.108.
- **v4.9.109 (2026-06-14)** — N04 (`worker_version` hardcoded), N11 (catch CORS vazio → `console.error`), P15* (cron `0 2 * * *` duplicado → `0 4 * * *`), N09 (CLAUDE.md teste anônimo), P05* (CI `EXPECTED_WORKER`).
- **N09 (2026-06-19)** — `CLAUDE.md` reescrito (62 KB → 5 KB): paths `api/`/`app/`, vault correto, teste GET `/`, histórico arquivado.
- **CI canonical-test (RESOLVIDO)** — `EXPECTED_WORKER=v4.9.143`; POST anônimo corrigido. Era P05* "100% quebrado".
- **Drift de artefato v4.9.102 (SUPERADO)** — bundle ativo migrou para v4.9.143 (repo = prod).
- **P16/P17 (ATIVOS v4.9.121)** — Agenda de divulgação semanal + Relatório; deliverability SPF `-all`/DMARC `p=quarantine` (RESOLVIDO 2026-06-17).

Detalhe completo de cada resolução: notas de auditoria no vault Obsidian (14–32).

---

## Lacunas desta passada

- **Testes autenticados profundos não executados:** `admin_verificar_evento`, `tel_test` E2E, `admin_health_check`, leitura quarantine KV — exigem `admin_senha`/`routine_key`, mantidos fora do chat (readonly). Logo, ingestão E2E e verificador vivo **não validados** hoje.
- **Persistência dos 7 CRITICOs (2026-06-20)** não cruzada com `op=state` autenticado.
- **Bundle v4.9.143 não relido linha-a-linha** nesta passada (15.905 linhas); achados de código herdados do v4.9.102 ficam em "A reconfirmar".
- **Sprite MCP health** não executado (curl local suficiente para blocos A+B).

---

## Próximos passos priorizados

| P | Ação | Ref |
|---|------|-----|
| P0 | Próxima auditoria completa: `admin_verificar_evento` + leitura quarantine KV do dia (fechar lacuna A1) | nota 31 |
| P1 | Sincronizar `app/deploy_zip/admin/*.js` ← `app/admin/*.js`, redeploy Pages, validar `sessionStorage` em prod | F1 / nota 32 |
| P1 | Limpar seções stale na Obsidian 03 (drift ~L368, bindings 3/3 ~L226) | D1 |
| P2 | Backlog: expor `rejeitados`/`veredicto.motivo`/`n_quarentena` em `receber_analise` | A2 |
| P2 | Organizar working tree (commit separado skill/auditoria/Obsidian vs artefatos) | P-RH |
| P2 | Investigar watchdog `stale_count:1` | P-WD |
| P3 | Reanálise Onco/Kora/GPA com fonte CVM primária; `admin_corrigir_datas_cvm_kv` em lote | P-MAT / P-CVM |
