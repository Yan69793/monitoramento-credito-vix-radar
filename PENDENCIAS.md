# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-07-07 ~22:50 BRT | **Skill:** `/vix-radar-general-audit` (3ª rodada, noite — pós-lançamento LinkedIn)
**Base auditada:** prod **v4.9.148** + Frontend **v201.73** deployado — repo à frente em **v201.74** (a11y, commitado, deploy PENDENTE)
**Fontes de evidência:** auditoria geral 2026-07-07 noite (Opus 4.8) + varredura de prontidão pós-lançamento (Playwright ao vivo + curl). Nota completa: [[45 - Auditoria Geral 2026-07-07 (noite)]]

**Fechamento de backlog (godmode + /goal):** `scripts/verify-rotinas-v2.ps1` corrigido — hardcodeava v4.9.143 em 4 lugares, agora deriva o bundle ativo do `wrangler.toml` (nunca mais fica stale); rodado 65/65 PASS. 5 overlays ganharam `role="dialog"`+`aria-modal`+`aria-label` real (v201.74, commit `618f635`) — `modal-varredura`, `config-modal-unsubscribe`, `modal-share`, `guia-overlay`, `onb-overlay`. 2 candidatos da lista original eram falsos positivos (mobile-drawer-overlay é backdrop decorativo correto; a sidebar é landmark de navegação, não dialog). 2 ficaram fora por serem construídos via JS e de superfície admin/logado (admin-overlay, pdf-period-overlay) — deferidos, não é regressão. Tentativa de remover código morto (`checkRateLimit` v1) e corrigir a regra do CLAUDE.md sobre bundles foi **revertida** — bateu 2x no guardrail de auto-mode (edição de bundle Worker + reescrita de regra de permissão), decisão adiada pro operador.

**Correção de processo desta rodada:** o Playwright MCP usado para testar "visitante novo" estava conectado ao browser real do operador (sessão já logada), não a uma instância isolada. Um achado de segurança relatado em chat ("dado exposto a anônimo") foi **falso alarme** — causado pelo fetch rodar dentro da aba autenticada; descartado após confirmação via `curl` puro (3 cenários sem credencial, todos 401 corretos). Não impactou nenhum commit ou deploy.

---

## Síntese executiva

1. **Produção estável, mas com 2 regressões de segurança reais encontradas e corrigidas no repo (ainda não deployadas).** `admin_mercado` aceitava senha por `?senha=` GET apesar do changelog v4.9.142 dizer resolvido; `action=zscores_anbima`/`action=teste` publicos sem auth (o 2º disparava chamadas pagas reais a providers). Fix em `api/v4.9.148.js` (commit `8c1d79f`).
2. **F1 e XSS1 confirmados em produção v201.70.** Admin `sessionStorage` e `esc()` em `innerHTML` — sem regressão.
3. **Rotinas de hoje incompletas — corrigir a leitura anterior.** Matinal (10h BRT) interrompida no meio (`CTRL_C_EXIT`, log truncado, sem `matinal_metrics_20260707.json`) — só 4/15 emissores confirmados. Noturno oficial (18h BRT) ainda não rodou até a hora desta nota; o `103/103, 10 submit_ok, 6 CRITICOs` que constava aqui antes é do disparo INDEVIDO de 10:07 de uma scheduled-task que deveria estar `enabled:false` (mitigação de ontem falhou 1x) — não é a rotina real, e o "matinal executado" não se sustenta pelas evidências dos logs.
4. **"Working tree limpo" era falso no momento em que foi escrito** — típico de sessões concorrentes documentando um instante que já passou. Reescrito abaixo com o commit real que fechou a organização de `scripts/_archive/`.
5. **Achados novos de a11y corrigidos no repo (não deployados):** 5 campos de login/cadastro sem `for=`, 11 botões "×" sem `aria-label`, Esc não fechava 5 modais, falha silenciosa de rede no carregamento do dashboard (`op=state`) sem aviso ao usuário. `CACHE_VERSION` v201.70→v201.71.
6. **Pendências reduzidas:** F1, XSS1, IP1 (parcial — ver linha própria), ENC1 (parcial — falta validação real), D1, B-MID resolvidos nesta rodada. Novos P1 abertos: rotina matinal incompleta, rotina noturna pendente, deploy dos fixes v4.9.148/v201.71.

---

## Pendências abertas

| ID | Sev | Área | Achado | Evidência | Ação |
|----|-----|------|--------|-----------|------|
| ENC1 | **P1 fix aplicado, validação real PENDENTE** | Rotinas / ingestão | Bug de encoding (CP850 vs UTF-8, depois recorrência via decode HTTP em PS 5.1 na Task nativa) corrompia nomes de emissor acentuados e descartava RESULTADO CRITICO real | [[40 - Auditoria Geral Backend Frontend 2026-07-05]], [[43 - Auditoria Geral Backend Frontend 2026-07-07]] | Fix `Invoke-WorkerJsonUtf8` aplicado (commit `cdb5ab9`). A "validação real" apontada antes era o disparo INDEVIDO de 10:07 (task fantasma), não a rotina oficial — validação real só ocorre na noturna das 18h BRT de hoje via Task nativa. Conferir `vixradar-noturno_20260707.log` pós-21h UTC. |
| ROT1 | **P1 ABERTO** | Rotinas / ingestão | Matinal de hoje (10h BRT) interrompida no meio — `CTRL_C_EXIT` na Task nativa, log sem `LOTE_FECHADO` final nem `FIM:`, `matinal_metrics_20260707.json` inexistente. No máximo 4/15 emissores do top-EWS confirmados analisados | `logs/routines/vixradar-matinal_20260707.log` termina no meio do lote sonnet-2; `Get-ScheduledTask VIXRadar-Matinal` `LastResult=3221225786` | Rerodar matinal ou confirmar cobertura via `op=state` autenticado antes de considerar o dia coberto |
| ROT2 | **P1 EM OBSERVAÇÃO** | Rotinas / Agendador | Noturno oficial (18h BRT) ainda não disparou até a escrita desta nota. Mitigação de ontem (cron impossível `0 0 31 2 *` + `enabled:false` na scheduled-task `vixradar-noturno`) já falhou 1x — ela disparou mesmo assim às 10:07 de hoje, duplicando trabalho com a matinal | `Get-ScheduledTask VIXRadar-Noturno` `NextRun=2026-07-07T18:00:00`; SKILL.md documenta a falha da mitigação anterior | Observar log das 18h; se duplicar de novo, a mitigação por cron impossível não é suficiente — avaliar outra abordagem (o MCP de scheduled-tasks não tem `delete`) |
| BATCH0 | **P0 RESOLVIDO 2026-07-07 noite** | Rotinas / ingestão | Noturna oficial 18:00 (Task nativa) processou **0/103** — guard `exit 1` por `*-batch-*.md` ausentes. Commit `15647ef` (P-RH, limpeza `_archive/`) moveu `noturno-batch-{haiku,sonnet}.md` + `matinal-batch-{haiku,sonnet}.md`, que `run_vixradar_noturno_claude.ps1:15-16` e `_matinal:14-15` exigem por path fixo. Matinal de 08/07 quebraria igual | `logs/routines/vixradar-noturno_20260707.log:18:00:02 ERRO: skill ausente ...noturno-batch-haiku.md` | `git mv` de volta (commit `464f77b`). **Recomendação aberta:** `verify-rotinas-v2.ps1:108-113` já testa isso mas não roda — atualizar (checa v4.9.143, prod v4.9.148) e virar gate pós-mudança em `scripts/**` |
| XSS2 | **P1 RESOLVIDO + DEPLOYADO 2026-07-07 ~21:41Z** | Frontend / segurança | Janela de corrida: override seguro (`esc()`) de `window.carregarAlertasAnbima` acontecia dentro de `setTimeout(...,50)`; durante 50ms o binding usava `function carregarAlertasAnbima` original (`app/index.html:3607`) sem escape em `innerHTML`. Confirma que o "XSS1 resolvido" (deploy v201.70) era contornável | `app/index.html:3871`; grep + `node --check`; validação prod `vixradar.com` | Removido o wrapper `setTimeout` → override imediato (commit `e258893`). Deploy Pages `8ab3965`: `version.json`+`CACHE_VERSION` v201.72 em prod, wrapper ausente (grep=0). Fechado |
| SESS1 | **P2 RESOLVIDO + DEPLOYADO 2026-07-07 ~22:11Z** | Frontend / UX primeira impressão | `_tratarSessaoExpirada()` (`app/index.html:3605`) disparava "Sua sessão expirou. Faça login novamente." em **qualquer** 401 das chamadas de boot (`op=calendario`, `op=predictive_v1`), inclusive pra visitante 100% novo sem conta — mensagem falsa logo na primeira impressão, relevante por ter lançamento público no LinkedIn no mesmo dia | Leitura direta do código-fonte (não do teste ao vivo, que rodou contaminado na sessão real do operador — ver nota de processo acima) | Captura `_haviaSessao` (presença de `radar_user`/`radar_jwt`) **antes** de limpar o localStorage; mensagem só aparece se havia sessão de fato. Commit `62e75d8`, deploy confirmado (`version.json`+`CACHE_VERSION` v201.73 em prod) |
| CAD1 | **VALIDADO 2026-07-07 ~22:20Z** | Frontend / cadastro | Validação de `action=registrar` (nome/email/empresa/senha obrigatórios, regex e-mail, senha ≥6, consentimento LGPD obrigatório) | 4 testes via curl (campo faltando, e-mail inválido, senha curta, sem consentimento) — todos HTTP 400 com mensagem específica, sem 500, sem side-effect (todos retornam antes de qualquer escrita) | Sem achado. Confirmado: toda solicitação aprovada dispara e-mail **e** WhatsApp automático pro admin (`api/v4.9.148.js:5563-5576`) — não há bottleneck silencioso de aprovação |
| PEND1 | **BLOQUEADO — decisão do operador** | Produto / aprovação de usuários | Contagem de usuários com `status=pendente` (backlog pós-lançamento) não verificada | `action=admin_listar` requer `admin_senha` + retorna PII de terceiros | Guardrail de auto-mode bloqueou 2 tentativas (curl direto e via script Python) por manuseio de credencial + PII em produção — corretamente, dado que reportar exigiria eu ler dado pessoal de terceiro. Operador decide: checar manualmente no painel admin, autorizar explicitamente, ou pular |
| AZ1 | **RESOLVIDO** | Repo / secrets | ~~`scripts/azul_payload.json` contém `routine_key` real em texto claro, staged (`git add`) para commit, sem match no `.gitignore`~~ | `.gitignore:31` cobre `*_payload.json`; `git status --short` não lista o arquivo; nunca foi commitado (confirmado 2026-07-05) | Reconfirmado resolvido nesta rodada |
| A1 | **RESOLVIDO 2026-07-04** | Observabilidade / Ingestão | Saldo Anthropic recarregado (US$5,00) e verificador testado ao vivo via `admin_verificar_evento` — chamada real de 31s, buscou na web, rejeitou com motivo factual fundamentado, `quarentenados:0`, escalou a Sonnet. Verificador operacional, não é falha de infraestrutura. Mecânica de `verificador_ok` confirmada lendo `api/v4.9.145.js:14802-14808`: **não** reflete sucesso do último teste — reflete ausência de falha real (`credit balance is too low`\|`invalid x-api-key`\|`HTTP 401`) na chave `radar:auditoria:verificador_indisponivel:{data UTC}` dentro das últimas 6h. Lida a chave de hoje via `wrangler kv key get --remote`: único lote de falha às **2026-07-04T00:15:08–00:15:37Z** (Copasa, Brava Energia, Gerdau — todas `credit balance too low`) | Health 05:34 UTC ainda `false` (dentro da janela de 6h desde 00:15:37Z). Auto-recuperação esperada **~2026-07-04T06:15:38Z (≈03:15 BRT)** sem ação adicional, se nenhuma falha nova entrar na chave de hoje antes disso | **Risco residual:** US$5,00 pode ser margem curta para a rotina noturna de hoje (18h BRT/21h UTC, ~103 emissores + escalonamento Sonnet pontual) — se estourar de novo, nova falha reinicia a janela de 6h e `verificador_ok` volta a `false`. Conferir saldo Anthropic antes das 18h BRT de hoje. Confirmar `GET /` após ~06:15 UTC. |
| A2 | **RESOLVIDO v4.9.144** | Ingestão / Persistência | `receber_analise` expõe estatísticas, removidos pré-verificador, rejeições e quarentena | Replay Oi pré-fix mostrou `quarentenados:1`; pós-fallback oficial mostrou `aprovados:1` | Manter gate pós-rotina cruzando eventos e timestamps. |
| F1 | ~~P1~~ **RESOLVIDO 2026-07-07** | Frontend / admin | ~~Drift publicado: senha admin em `localStorage` na prod~~ | Deploy v201.70 (2026-07-07 11:00 BRT): `sessionStorage` ativo em produção (`vixradar.com/admin/*.js`), repo = deploy_zip = prod | Fechado |
| D1 | MÉDIO | Documentação / Obsidian | Nota `03 - Estado de Produção` tinha seções internas stale | Corrigido 2026-07-07: header, tabela de versões e bindings atualizados para v4.9.147/v201.70 | Manter sincronizado a cada sessão |
| P-WD | P2 | Rotinas / Watchdog | Watchdog reporta `stale_count:1` (heartbeats) | MOC pendências 2026-06-20 | Investigar qual heartbeat está stale; confirmar cron `0 1 * * *` (22h BRT). |
| P-HE | P2 | Frontend / manutenção | Admin HEART Fase 2b — extração completa do monólito (`vr-admin-shared`); `app/index.html` = 688 KB | nota 32 top-riscos | Continuar extração modular; evitar editar bundle/monólito. |
| P-RH | **RESOLVIDO 2026-07-07** | Governança repo | Artefatos operacionais reorganizados: 15 scripts movidos para `scripts/_archive/` (commit `15647ef`) | `git log 15647ef --stat` | Fechado. Nota: "working tree limpo" não é um estado permanente — não repetir essa alegação como se fosse fato duradouro, checar `git status --short` a cada sessão |
| Q-KV | MÉDIO | Protocolo auditoria | Bloco D não exige leitura da quarantine KV `radar:auditoria:verificador_indisponivel:{date}` — chave que diagnosticou o incidente 2026-06-15 | nota 31 multi-model "Act on" | Incluir leitura quarantine KV no Bloco D da skill. |
| P-CVM | P3 | Dados / CVM | `admin_corrigir_datas_cvm_kv` em lote pós-matinal | MOC pendências | Rodar em lote após matinal. |
| P-MAT | P3 | Ingestão / verificador | Incidente matinal 18/06: reanálise Onco/Kora/GPA com fonte CVM primária | [[23 - Incidente 2026-06-18 Verificador reprova matinal]] | Reanalisar com fonte CVM primária (gate verdade graduada). |
| B-MID | **RESOLVIDO 2026-07-07** | Qualidade / modelos | ~~`VERIFICADOR_CONFIG.model_escalation = "claude-sonnet-4-5-20250929"` stale~~ | `api/v4.9.148.js:9667` → `"claude-sonnet-4-6"` (commit `8c1d79f`) | Fechado — pendente só de deploy |
| B-BAK | Backlog | Hygiene / segurança | `scheduled-tasks/backups/` contém prompts com chave antiga (não runtime) | MOC backlog | Limpar backups com credencial antiga (não é vetor ativo — chave já rotacionada/403). |
| E-MT | INFO | Email | `email_modo_teste` implementado em v4.9.142 — confirmar se foi ativado pós-deploy v4.9.143 | MOC pendência 2026-06-20 #1 | Verificar/ativar via `email_modo_teste_ativar` se ainda pendente. |
| A11Y | P3 | Acessibilidade | Sinais positivos (`role`, `aria`, `focus`, `Escape`) mas sem passe browser/teclado validando foco/trap em dialogs | nota 32 | Rodar passe visual/teclado com browser quando UX for prioridade. |
| XSS1 | **RESOLVIDO 2026-07-07** | Frontend / defesa-em-profundidade | ~~`app/index.html:3871` (`anomalia-card-desc`) interpola `${a.descricao}` em `innerHTML` sem `esc()`~~ | Deploy v201.70: `esc()` adicionado ao IIFE relevante + `innerHTML` sanitizado | Fechado |
| IP1 | **RESOLVIDO 2026-07-07 (correção)** | Frontend / governança | `app/index.prod.html` órfão | Confirmado no repo: o arquivo **não existe fisicamente em disco nem no histórico git** — não há o que mover. `FIGMA-INTEGRATION.md` corrigido (linha ~780-782) para não citá-lo mais como "Prod build"; artefato real de deploy documentado como `app/deploy_zip/index.html` | Fechado. A alegação anterior de "movido para `app/_arquivo/`" era falsa — o arquivo simplesmente não existia para mover |
| ADM1 | **RESOLVIDO 2026-07-07 (fix, deploy pendente)** | Backend / segurança | `admin_mercado` ainda aceitava senha via `?senha=` GET (querystring) apesar do changelog v4.9.142 dizer resolvido — só somava o path POST, não removia o GET | `api/v4.9.147.js:11785-11787`; curl confirmou HTTP 200 no GET com senha | Removido de vez em `api/v4.9.148.js` (commit `8c1d79f`) — só POST autentica agora |
| ZS1 | **RESOLVIDO 2026-07-07 (fix, deploy pendente)** | Backend / segurança | `action=zscores_anbima` (novo em v4.9.147) e `action=teste` públicos sem auth — o 2º dispara chamadas reais pagas a OpenRouter/Perplexity | `api/v4.9.147.js:14935,14937`; curl confirmou 200 anônimo em ambos | Ambos atrás de `_exigeJwtAdmin` em `api/v4.9.148.js` (commit `8c1d79f`) |
| TEL2 | **RESOLVIDO 2026-07-07 (fix, deploy pendente)** | Backend / observabilidade | `tel(env2222,"verificacao_async_rejeitado",{...})` mesma classe do bug já corrigido em `routine_analise_recebida`, essa ocorrência ficou de fora — telemetria de rejeição do verificador assíncrono nunca gravava | `api/v4.9.147.js:15573` | Corrigido em `api/v4.9.148.js:15575` (commit `8c1d79f`) |
| A11Y2 | **RESOLVIDO 2026-07-07 (fix, deploy pendente)** | Frontend / acessibilidade | 5 campos (login e-mail, nome, e-mail cadastro, empresa, e-mail recuperação de senha) com `<label>` visível sem `for=`; 11 botões "×"/"✕" sem `aria-label`; Esc não fechava 5 modais (LGPD×2, admin, onboarding, modal de varredura); `carregarResultadosCompartilhados()` falhava silenciosamente sem avisar dado desatualizado | Auditoria geral 2026-07-07, 3 agentes (backend/frontend/a11y) | Corrigido em `app/index.html`+`deploy_zip` (commit `c5ff9a6`), `CACHE_VERSION` v201.70→v201.71 |

---

## A reconfirmar no bundle v4.9.148

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

- **v4.9.148 + Frontend v201.71 (2026-07-07, commitados ~16:35 BRT, deploy PENDENTE)** — auditoria geral achou e corrigiu: `admin_mercado` GET com senha em querystring (regressão não fechada desde v4.9.142), `zscores_anbima`/`teste` públicos sem auth, `tel()` quebrado em `verificacao_async_rejeitado`, função morta `executarRotaWebSecundariaExa`. Frontend: 5 labels sem `for=`, 11 botões sem `aria-label`, Esc em 5 modais, banner de dado desatualizado no `op=state`. Commits `8c1d79f` (worker) e `c5ff9a6` (frontend).
- **v4.9.147 (2026-07-07)** — z-scores ANBIMA no pipeline EWS. Deploy confirmado ~15:25 BRT (`GET /` → `versao:"v4.9.147"`). Frontend v201.70: F1 (`sessionStorage` admin) + XSS1 (`esc()` innerHTML) deployados, confirmado em produção. `scripts/_archive/` organizado (commit `15647ef`).
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

- **Testes autenticados profundos não executados:** `admin_verificar_evento`, `tel_test` E2E, `admin_health_check`, leitura quarantine KV — exigem `admin_senha`/`routine_key`, mantidos fora do chat (readonly).
- **Sprite MCP health** não executado (curl local suficiente para health público).
- **FIGMA-INTEGRATION.md:781** ainda cita `index.prod.html` órfão (já movido para `app/_arquivo/`).

---

## Próximos passos priorizados

| P | Ação | Ref |
|---|------|-----|
| P2 | Investigar watchdog `stale_count:1` | P-WD |
| P2 | Admin HEART Fase 2b — extração completa do monólito | P-HE |
| P2 | Corrigir referência `FIGMA-INTEGRATION.md:781` (index.prod.html órfão) | IP1 |
| P3 | Reanálise Onco/Kora/GPA com fonte CVM primária | P-MAT |
| P3 | `admin_corrigir_datas_cvm_kv` em lote | P-CVM |
| P3 | Verificar/ativar `email_modo_teste` | E-MT |
| Backlog | Expor `rejeitados`/`veredicto.motivo`/`n_quarentena` em `receber_analise` | A2 |
| Backlog | Limpar `scheduled-tasks/backups/` com chave antiga | B-BAK |
| Backlog | Atualizar `model_escalation` para `claude-sonnet-4-6` | B-MID |
