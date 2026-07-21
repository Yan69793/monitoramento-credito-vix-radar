# Auditoria Geral — VIX Radar (2026-07-07)

Skill: `/vix-radar-general-audit`. Readonly (nenhum deploy, nenhuma escrita em produção). Complementa [[42 - Auditoria Geral Backend Frontend 2026-07-06]]. Método: 3 subagentes (backend bundle, frontend, governança) + validação em tempo real (health, staleness, logs de rotina, agendador).

## Veredito

Sistema **degradado em governança e operação de rotinas, saudável em runtime**. Produção responde bem (Worker v4.9.146 `ok:true`, 103/103 emissores com `stale_24h:0`), e o bundle do Worker passou em todos os 32 controles críticos. Porém: o código-fonte da versão em produção está fora do controle de versão (P0), o agendador Claude Code está executando tasks **desabilitadas** (noturno disparou hoje 10:07, em paralelo com a matinal), o bug de encoding dado como corrigido em 05/07 **voltou a descartar um CRITICO real** (Raízen, noturno 06/07 via Task nativa), e há dois fixes de segurança do frontend (XSS `esc()` e senha admin em `localStorage`) que nunca chegaram a produção — um deles com drift invisível porque o conteúdo mudou sem bump de `CACHE_VERSION`.

## Top riscos

| Sev | Área | Achado | Evidência | Ação |
|---|---|---|---|---|
| P0 | Governança | Bundles `api/v4.9.144/145/146.js` **untracked** — fonte da versão em produção só existe no disco; whitelist do `.gitignore` também unstaged; 22 dias sem commit (+13k linhas) | `git ls-files "api/v4.9.14[456].js"` vazio; `git status` `??`; CI `EXPECTED_WORKER=v4.9.146` | `git add` bundles + `.gitignore` + commit imediato |
| P1 | Rotinas/Agendador | Agendador Claude Code **executa tasks com `enabled:false`**: `vixradar-noturno` (desabilitada 06/07, nota 41) rodou hoje **10:07 BRT** em paralelo com a matinal (~700k tokens duplicados); `fechamento-diario-szuchmacher` (desativada) rodou 06/07 19:08 BRT no cron dela | `list_scheduled_tasks`: noturno `enabled:false` + `lastRunAt 2026-07-07T13:07:23Z`; log `vixradar-noturno_20260707.log` início 10:07:35 | **MITIGADO 2026-07-07 ~10:32**: ambas neutralizadas via `update_scheduled_task` com cron impossível `0 0 31 2 *` + `enabled:false` (MCP não tem delete; SKILL.md preservado — fonte do ROUTINE_KEY p/ 7 scripts). `list_scheduled_tasks` pós-fix: sem `nextRunAt` nas duas. Confirmar amanhã ausência de disparo fantasma. [Hipótese da causa] catch-up de run perdido na abertura do app ignora `enabled:false` |
| P1 | Rotinas/Encoding | **Recorrência do P0 de 05/07 no caminho Task nativa**: noturno 06/07 18h gerou RESULTADO CRITICO da Raízen 2× (18:24 + retry 18:27) e descartou ambos — `OK|Raízen|FULL|NENHUM|0` (mojibake `RaÃ­zen` nas linhas WARN). O fix de encoding vale no contexto Claude Code (noturno de hoje mostra nomes corretos), mas não sob Task Scheduler nativo | `vixradar-noturno_20260706.log:18:24-18:27` | **CAUSA RAIZ CONFIRMADA + FIX APLICADO 2026-07-07**: Worker responde `application/json` SEM charset e a Task nativa roda `powershell.exe` 5.1, que decodifica a resposta como ISO-8859-1 — o plano chega corrompido EM MEMÓRIA e o match falha (o fix de 05/07 cobria só o stdout). Prova A/B em 5.1 real: nativa=`82,97,195,173,...` (RaÃ­zen) vs fix=`82,97,237,...` (Raízen). Helper `Invoke-WorkerJsonUtf8` (RawContentStream + decode UTF-8, body em bytes UTF-8) aplicado nos 3 scripts (plano matinal/noturno, fila/prompts e confirmar da verificação async). ParseFile 0 erros. Commit local. **Validação real: noturna 18h BRT de hoje (Task nativa)**. Recomendação de raiz p/ v4.9.147: `charset=utf-8` no Content-Type das respostas JSON do Worker |
| P1 | Segurança/Deploy | **Fix XSS não deployado com drift invisível**: produção v201.69 serve `${a.descricao}` sem `esc()`; working tree + deploy_zip têm o fix sob a MESMA `CACHE_VERSION` v201.69 | prod 678.419 bytes vs local 678.998; `prod.Contains('esc(a.descricao)')=False` | Bump `CACHE_VERSION` + deploy Pages (autorização). Regra nova: nunca alterar conteúdo sem bump |
| P2 | Frontend/Segurança | **F1 ampliado**: fix `sessionStorage` cobriu só `app/admin/*.js`; o HTML monolítico tem 2× `localStorage.getItem("radar_admin_senha")` no repo (`app/index.html` E `deploy_zip`) e em produção — o deploy recomendado ontem **não fecharia o F1** | grep: 2×/2× localStorage, 0× sessionStorage nos dois index.html; prod HTML idem | Editar as 2 ocorrências no `app/index.html`, sync deploy_zip, bump, deploy |
| P2 | Governança | Artefatos operacionais **staged**: `agent-tools/`, `terminals/` (logs com stacktrace), `workspace.code-workspace`, 7 PNGs `app/design/preview-p1/`, `diagnosticos/` (PNG 704KB untracked) | `git status` `A`; `git check-ignore` exit 1 | `.gitignore` + `git rm --cached` antes do commit de higiene |
| P2 | Governança | Pendências de ontem seguem abertas: `scripts/run_vixradar_verificacao_async.ps1` untracked (cópia única de script de produção); `app/index.prod.html` órfão v201.65 staged (IP1) | `git status` `??`/`A`; `PENDENCIAS.md:42` | `git add` script; remover/arquivar index.prod.html + corrigir `FIGMA-INTEGRATION.md:781` |
| P2 | Acessibilidade | 26 `<input>`, **0 `aria-label`** — login e admin só com `placeholder` (sem nome acessível; WCAG 2.2 A) | grep `app/index.html` | Adicionar `label`/`aria-label` nos campos de login + admin |

## Backend (bundle v4.9.146 — 32 controles OK)

- Multi-semana `carregarEstadoMultiSemana(env,5)` nos 5 endpoints (`state:14717`, `ews:12544`, `briefing:14333`, `historico:14360`, `comparar:14472`).
- `receber_analise`: eventos `deveVerificar()` → fila KV `radar:verif_fila:{data}` (TTL 7d); quando tudo vai à fila, `_raSkipPersist=true` + `sem_eventos=false` — **não grava ausência falsa** (`15417-15433`). `n_eventos:0` nos submits CRITICO das rotinas de hoje é comportamento esperado (pendente até o drain), não perda.
- `listar_fila_verificacao`/`confirmar_verificacao` com routine_key 403; `console.error` estruturado no catch (`15488`); `mesclarEventoVerificado` dedup+sort+cap40 (`7678-7691`).
- JWT_SECRET sem fallback (6 usos); ADMIN_EMAIL via env; CORS allowlist sem wildcard; RL fail-open com `console.warn`; telemetria `writeDataPoint` em ~10 pontos; health `ok` = KV+AE+Resend+verificador; `verificador_ok` inclui fila >12h e quarentena 6h; datas CVM sem fallback "hoje" silencioso.
- P3: `tel()` promise flutuante no fetch path sem `ctx.waitUntil`; call-site `15444` passa string onde `tel` espera `request` — datapoint `routine_analise_recebida` provavelmente nunca gravado. P3: código morto OpenRouter (`16008`). Informativo: `RATE_LIMITER_DO` fora do `ok` do health (design).

## Frontend

- **Sem drift local**: `app/index.html` ≡ `app/deploy_zip/index.html` (byte-idênticos, v201.69); módulos admin 100% sync (e `vr-admin-engajamento.js` em prod byte-igual ao repo).
- Auth OK: Bearer em GETs, sessão exige `radar_user`+`radar_jwt`, 401 de `rl_inspect` não derruba sessão, senha admin em POST body (0 casos em URL).
- CSS `strong` global só `font-weight` — regra inviolável respeitada.
- UX: 144 catch, retry/empty/loading com copy real; timestamp de atualização + disclaimer de dados.
- Perf produção: HTML 663KB bruto / **166KB comprimido**, TTFB 0,19s, total 0,23s; `no-store` coerente com estratégia de deploy. P3: Inter carregada 2× + 2 links Google Fonts render-blocking; `resize` sem debounce; 3 imgs sem width/height; `outline:none` ~20× sem `:focus-visible`.
- CI: valida Worker (`EXPECTED_WORKER=v4.9.146` ✅) mas **não valida frontend** (sem `EXPECTED_FRONTEND`) — lacuna que deixou o drift XSS invisível.

## Rotinas em tempo real (07/07)

- Staleness: `total:103`, `stale_24h:0`, `max_stale:16.2h` (Vibra) — cobertura íntegra apesar do `deferred=27` do noturno 06/07 (hard cap 700k atingido, `tokens=813678`).
- Matinal 10:00: 4 CRITICOs (Raízen 5ev, Oi, Oncoclínicas, Kora Saúde) `ok=true`; ressalva: log `Tokens lote=0 acum=0` — parser de tokens da matinal não capturou consumo (hard cap inoperante se persistir; verificar próxima matinal).
- Noturno anômalo 10:07 (task desabilitada): rodou em paralelo com a matinal, re-analisando os mesmos CRITICOs (Oncoclínicas, Oi, GPA, Raízen…) — trabalho e tokens duplicados; submits idempotentes (dedup no Worker) limitam o dano a custo/quota.
- Drain fila verificação (cron `20 10,18 * * *`): 06/07 rodou 2× (17:50 e 18:27, aprovados Light e Oi). Hoje: **disparou 10:26:54** com `verificador_ok=True` e **fila de 7 eventos** (Oncoclínicas, Oi, Raízen×2, Kora Saúde, Light×2) — confirma que os `n_eventos:0` das rotinas eram eventos pendentes na fila, não perda. Resultado final do lote a conferir no log `vixradar-verificacao-async_20260707.log`.

## Próximos passos

1. **P0** — Commit de resgate: `git add api/v4.9.144.js api/v4.9.145.js api/v4.9.146.js .gitignore scripts/run_vixradar_verificacao_async.ps1` + commit (antes, tirar do stage os artefatos do P2: `agent-tools/`, `terminals/`, PNGs, `workspace.code-workspace`, `app/index.prod.html`).
2. **P1** — ~~Deletar (não só desabilitar) `vixradar-noturno` e `fechamento-diario-szuchmacher` do agendador Claude Code~~ **FEITO 2026-07-07 ~10:32** (neutralizadas com cron impossível `0 0 31 2 *`; MCP sem delete; ver Top riscos). Restam: confirmar amanhã ausência de disparo fantasma; avaliar mesma neutralização para `atualizar-agenda-macro-szuchmacher` (também `enabled:false` com cron real de sexta 07:07).
3. **P1** — ~~Encoding no caminho Task nativa~~ **FIX APLICADO 2026-07-07** (commit `cdb5ab9`, ver Top riscos): helper `Invoke-WorkerJsonUtf8` nos 3 scripts, prova A/B em 5.1. Falta validação real na noturna 18h BRT de hoje (conferir ausência de `RaÃ­zen`/`NENHUM` falso no log) e, para a raiz, `charset=utf-8` no Worker (v4.9.147 futuro).
4. **P1** — Deploy Pages v201.70 (XSS `esc()` + F1 completo): **pronto no repo** (commit `739780a`; `app/index.html` editado — 2× senha admin → `sessionStorage`; deploy_zip byte-igual; `version.json` v201.70). **Aguardando confirmação do operador** para `npx wrangler pages deploy ./app/deploy_zip --project-name=radar-credito` (classificador exige aprovação explícita). Pós-deploy: validar `version.json`→v201.70, `esc(a.descricao)` presente e `sessionStorage` no HTML servido. Push `origin/main` também pendente de confirmação (4 commits locais: `a065027`, `fa9e694`, `739780a`, `cdb5ab9`).
5. **P2** — CI: adicionar `EXPECTED_FRONTEND` ao `canonical-test.yml`.
6. **P2** — a11y: `aria-label` nos inputs de login/admin.
7. **P3** — `tel()` call-site de rotina (assinatura errada), código morto OpenRouter, fonts duplicadas, `fechamento-20260703-full.jpeg`.
