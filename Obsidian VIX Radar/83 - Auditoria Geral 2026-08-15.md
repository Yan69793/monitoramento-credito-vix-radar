---
data: 2026-08-15
tipo: auditoria
tags: [vix-radar, auditoria-geral, seguranca, xss, secrets]
status: ativo
---

# 83 — Auditoria Geral Profunda 2026-08-15

Protocolo de 25 fases + prompt otimizado (Downloads). 7 frentes read-only com orçamento + revisor de diff independente + validação pessoal de todo P0/P1 no código. Revisão independente do diff completo concluída 15/08: veredito "pronto para deploy" com 1 crítica, 2 importantes e menores — todos tratados abaixo antes do deploy.

## Veredito

Saudável no núcleo (auth, CORS, rate limit, health, veracidade da UI), com 1 P0 e 3 P1 encontrados, todos corrigidos localmente. O fix de recuperação de DEFERRED (P1-2) foi invalidado pela revisão independente e reimplementado com persistência real do flag. Nada deployado antes do pré-flight verde; produção segue v4.9.194/v202.9 com health verde até o deploy v4.9.195/v202.10.

## Achados principais

- **P0 (CORRIGIDO LOCAL, com errata)**: routine_key em texto puro fora do repo, em `~/.claude/scheduled-tasks/gen_workflow.py` (RKEY hardcoded) e `vixradar-noturno-v2.js` (14 literais), consumida por `scripts/replay-criticos.ps1`. Redigido em 15/08. **Errata da própria redação**: a primeira substituição interpolou `$env:ROUTINE_API_KEY` dentro do comentário de redação, regravando o valor da chave no próprio comentário (14 ocorrências); corrigido em seguida, varredura final confirmou zero resíduos nos arquivos e backups redigidos. replay-criticos agora lê `$env:ROUTINE_API_KEY`. ROTAÇÃO DA CHAVE EM EXECUÇÃO NA META (3 destinos: Worker secret, GitHub Actions secret, env User da máquina), dependia de permissão Secrets no token gh.
- **P1 (CORRIGIDO LOCAL)**: OPENROUTER-ORFAO1 — call site órfão `chamarOpenRouter` (worker.js:14015) desde v4.9.180 gerava ReferenceError engolido, probe do Perplexity sempre `erro_desconhecido`, nível de alerta de providers >= amarelo com email falso desde 30/07. Fix: perplexity vira status "removido" (alinhado ao OPENROUTER-DEAD).
- **P1 (CORRIGIDO LOCAL)**: NOTIFYRL1 — `notificar_rotina` nasceu sem rate limit, sem dedup e com `body.html` cru no Resend; com a chave não rotacionada, era bombardeio de inbox + injeção de HTML. Fix: checkRateLimitV2 + dedup por rotina/dia no KV + escape no corpo E no assunto (o escape do assunto entrou na revisão).
- **P1 (CORRIGIDO LOCAL)**: LLMXSS1 — `fontes_consultadas` (query/resultado/cobertura_nota), `alertas_mercado` (tipo/descricao/limiar) e outros campos de LLM interpolados SEM escape em innerHTML (aba de buscas, alertas, estados vazios, anomalias ANBIMA, linha de tabela). Cadeia: XSS → `radar_jwt` (localStorage) + `radar_admin_senha` (sessionStorage). Fix: h() em 12 pontos + feed v201 (href com scheme check + aria-label escapado).
- **P1 (CORRIGIDO LOCAL, pós-revisão)**: DEFERREDREC1 — a recuperação dos DEFERRED por cap de tokens não funcionava: o flag `_token_cap_deferred` era montado no ledger do cliente mas morria na persistência (nenhum dos ramos do sem_eventos copiava do payload para o objeto gravado), então `_foiDeferido` era sempre false e a promoção FULL inalcançável. A revisão independente achou; fix: propagação do flag nos 5 ramos do persist; a análise real seguinte sobrescreve e limpa o flag sozinha.
- **P1 (CORRIGIDO LOCAL)**: matinal 13-14/08 perdida sem alarme — sessão Claude Desktop não disparou e o monitor-tasks trata task Disabled como esperado. Fix: ROTINAGAP1 no watch-vixradar-health (alerta via notificar_rotina com nome próprio por rotina faltante, se a rotina esperada não deixou log após o horário).
- **P1 (CORRIGIDO LOCAL, governança)**: o orquestrador real de produção é o SKILL.md do Claude Desktop, não o repo. Fix: 7 arquivos do Desktop versionados em `routines/claude-desktop/` + `scripts/check-desktop-orquestrador-drift.ps1` (exit 0 verificado).
- **P2 (CORRIGIDO LOCAL)**: HEALTHWAIT1 (self-healing do health sem ctx.waitUntil), TRILHALOG1 e HEARTBEATLOG1 (catches mudos em trilha/heartbeat), RESETPARSE1 (JSON.parse sem try), PREDRL1 (senha admin por GET sem throttle + oráculo), strip conservador do sanitizador, Bearer no módulo admin VIVO (o fix de 14/08 tinha ido pro arquivo legado morto), canonical-test falso-verde no rate_limiter, TIMEOUT1 (AbortSignal.timeout em 6 fetches externos: CVM ZIP, Resend, Twilio, OpenRouter, AE SQL), DEDUPCLAIM1 (claim de dedup da newsletter movido para depois dos filtros e liberado no catch, fim do bloqueio de 1h com motivo mentiroso), REGDRIFT1-FIX (registradores: guarda dura no legado e no dedicado do Verificacao-Async, estado Disabled reproduzido com falha alta no register-all), HEALTHWATCH2 (versão esperada derivada do wrangler.toml + janela de 10 min pós-edite do toml para não alarmar falso durante deploy).
- **P2/P3 (REGISTRADO)**: ver K1-K6, I1-I6, N5-N8, A1-A9 no plano da sessão.

## Correções locais aplicadas (sem commit, sem deploy)

`api/src/worker.js` (NOTIFYRL1, OPENROUTER-ORFAO1, HEALTHWAIT1, TRILHALOG1, HEARTBEATLOG1, RESETPARSE1, PREDRL1, strip conservador, TIMEOUT1, DEDUPCLAIM1, DEFERREDREC1 com os 5 ramos, escape de assunto), `app/index.html` (12 escapes + CACHE_VERSION v202.10), `app/js/admin/shared.js` (Bearer), `app/js/admin-bootstrap.js` (cache-busters v202.10), `.github/workflows/canonical-test.yml` (RL gate fail-closed), `api/wrangler.toml` (changelog 191-195, main v4.9.195), `PROMPTS-RADAR.md` + skill `vix-radar-general-audit` (docs), `scripts/replay-criticos.ps1` (env var), `scripts/watch-vixradar-health.ps1` (HEALTHWATCH2 + ROTINAGAP1 com ifs independentes), `scripts/register-all-routines-scheduler.ps1` (Disabled nas 3 tasks de rotina + guarda no Disable), `scripts/register-verificacao-async-task.ps1` e `scripts/register-vixradar-tasks.ps1` (guarda dura REGDRIFT1), `scripts/check-desktop-orquestrador-drift.ps1` (novo), `routines/claude-desktop/` (novo, 7 arquivos), redação de 2 arquivos fora do repo com backup. Novo teste: `api/test/providers-regressao.test.mjs` (OPENROUTER-ORFAO1 + NOTIFYRL1).

Validações: node --check no worker (exit 0, após todas as edições inclusive pós-revisão), 27 scripts inline do index.html parse OK, lint-encoding 61/61, check-drift 0, check-desktop-orquestrador-drift exit 0, BOMs preservados nos .ps1 com acento, watch-health ASCII puro, health verde ao vivo.

## Próximo passo

Deploy v4.9.195 (worker) + v202.10 (frontend) autorizado pela meta, plano completo em `C:\Users\User\.claude\plans\graceful-soaring-hopper.md`. CI roda o teste novo no push.
