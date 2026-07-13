# VIX Radar — Índice (MOC)

Vault recriado em 2026-06-07 durante auditoria completa.
Vault anterior estava ausente da nova estrutura de diretórios (`api/`, `app/`).

## Notas ativas

- [[03 - Estado de Produção]]
- [[04 - Auditoria 2026-06-07]]
- [[07 - Evolução do Sistema de Classificação e Prompts]]
- [[08 - Análise de Risco e Arquitetura de Confiabilidade]]
- [[09 - Auditoria 2026-06-10 (Pendências)]]
- [[10 - Oportunidades de Melhoria (2026-06-11)]]
- [[11 - Runbook Deploy Cloudflare Pages]]
- [[13 - Metodo de Vistoria Operacional]] — skill `/vix-radar-audit`
- [[14 - Auditoria Completa 2026-06-16]]
- [[15 - Auditoria Completa 2026-06-16 (v2)]]
- [[16 - Design P16 P17 Agenda e Relatorio]]
- [[17 - Email Relatorio e Deliverability 2026-06-17]]
- [[18 - Auditoria Completa 2026-06-17]]
- [[19 - Auditoria Completa 2026-06-17 (pós v201.63)]]
- [[20 - Monitoramento Loop 2026-06-17]]
- [[21 - Auditoria Completa 2026-06-18]]
- [[24 - Auditoria Completa 2026-06-18 (pós v4.9.141)]]
- [[25 - Deploy Readiness v4.9.142]]
- [[26 - Auditoria Completa 2026-06-18 (caveman)]]
- [[27 - Otimizacao Tokens Rotina Noturna]]
- [[29 - Rotina Noturna 2026-06-20]] — **7 CRITICOs**: Raízen PRE, Cosan, Kora Saúde, Oncoclínicas, Oi, GPA, Aegea (rating)
- [[30 - Monitor CRITICOs 2026-06-20]] — rastreamento contínuo dos 7 CRITICOs; atualizar a cada sessão
- [[31 - Auditoria Completa 2026-06-20]] — multi-model review (composer-2.5-fast); verificador_ok = key presence
- [[32 - Auditoria Geral Backend Frontend 2026-06-20]] — `/vix-radar-general-audit`; P1 drift admin `deploy_zip`/produção usa `localStorage` para senha admin
- [[33 - Auditoria Geral 2026-06-22]] — `/vix-radar-general-audit`; F1 confirmado resolvido em working tree (pendente commit); novos achados: N12 FERIADOS_B3_2028, B-MID2 model_escalation stale, P20 package.json cruft
- [[34 - Rotina Matinal 2026-06-22]] — 15 emissores; **5 CRITICOs**: Oi, Raízen, Kora Saúde, Oncoclínicas, GPA; Light RELEVANTE; exit 0
- [[35 - Auditoria Completa 2026-07-02]] — `/vix-radar-audit`; **CRÍTICO resolvido**: scheduler Claude Code zerado (2ª vez, mesmo padrão 15/06) — rotinas paradas 9 dias, 103/103 emissores stale; 5 tasks recriadas e validadas
- [[36 - Auditoria Completa 2026-07-03]] — `/vix-radar-audit`; saudável, sem drift. Rotina noturna 02/07 fechada 103/103 após reprocessar 24 emissores com falha de schema (mal-diagnosticada como auth). P0 aberto: cleanup apaga log/metrics do próprio dia
- [[37 - Auditoria Geral Backend Frontend 2026-07-03]] — `/vix-radar-general-audit`; saudável, sem P0. 3 P1 de débito técnico nos scripts de rotina (cleanup, schema docs, token parser)
- [[38 - Auditoria Geral Backend Frontend 2026-07-04]] — `/vix-radar-general-audit`; 3 P1 de ontem RESOLVIDOS (working tree, não commitados); novo P1: secret `routine_key` em `scripts/azul_payload.json` staged sem gitignore; P2 XSS defesa-em-profundidade `anomalia-card-desc`, `index.prod.html` órfão mal documentado
- [[39 - Auditoria Completa 2026-07-04]] — `/vix-radar-audit`; pós-deploy v4.9.146 (verificador assíncrono). **CRÍTICO resolvido**: health-gate de `run_vixradar_noturno_claude.ps1`/`run_vixradar_matinal_claude.ps1` bloqueava a rotina inteira por `verificador_ok` degradado — noturna de 03/07 processou 0/103 emissores por isso (`stale_24h:3` resultante). `.gitignore` corrigido (v4.9.144/145/146.js não eram commitáveis)
- [[40 - Auditoria Geral Backend Frontend 2026-07-05]] — `/vix-radar-general-audit` (OODA); **P0 novo**: bug de encoding (CP850 vs UTF-8) na captura do stdout do `claude -p` corrompe nomes de emissor acentuados e descarta RESULTADO CRITICO real (Raízen, Oncoclínicas confirmados) — corrigido nos 3 scripts de rotina, 2 registros repostos em produção. XSS1 e AZ1 (nota 38) confirmados resolvidos
- [[41 - Auditoria Completa 2026-07-06]] — `/vix-radar-audit`; saudável, sem drift. **Incidente resolvido**: noturno rodou DUPLICADO (Task nativa 18:00 + scheduled-task Claude Code) → colisão de handle no stderr date-tagged → 37 submits de cobertura mínima. Fix: stderr por-PID + mutex global + scheduled-task Claude Code desabilitada. Run canônico entregou 103/103 real (`stale_24h:0`, `max_stale:1.5h`)
- [[42 - Auditoria Geral Backend Frontend 2026-07-06]] — `/vix-radar-general-audit`; saudável, sem P0/P1. AZ1 (secret) confirmado resolvido. P2: **F1 confirmado ainda em prod** (admin `localStorage`, repo já em `sessionStorage`, fix não deployado); script `run_vixradar_verificacao_async.ps1` untracked. P3: jpeg solto na raiz
- [[43 - Auditoria Geral Backend Frontend 2026-07-07]] — `/vix-radar-general-audit` (manhã); P0 governança (bundles untracked) resolvido; agendador disparando tasks desabilitadas mitigado; recorrência do bug de encoding via Task nativa diagnosticada e corrigida; drift XSS/F1 invisível fechado com deploy v201.70
- [[44 - Auditoria Geral Backend Frontend 2026-07-07]] — `/vix-radar-general-audit` (tarde); achou e corrigiu no repo (deploy pendente): `admin_mercado` GET com senha em querystring (regressão não fechada desde v4.9.142), `zscores_anbima`/`teste` públicos sem auth (custo real), `tel()` quebrado, 6 campos + 11 botões sem nome acessível, 5 modais sem Esc, falha silenciosa no `op=state`. **Correção de registro**: "rotina 07/07 103/103" e "working tree limpo" alegados por sessão concorrente eram falsos — matinal real ficou incompleta, noturno oficial não tinha rodado
- [[46 - Auditoria Completa 2026-07-09]] — `/vix-radar-audit`; sistema saudável, v4.9.149/v201.74 em produção, sem drift worker. Drift frontend: repo v201.70 vs produção v201.74 (alegação incorreta — ver nota 47). Rotina noturna teve incidente de travamento (lote sonnet-1) - resolvido via cleanup de mutex/processos. Universo 103/103 confirmado.
- [[47 - Auditoria Completa 2026-07-09 (v2)]] — `/vix-radar-audit`; **stale_24h:3** (Light 46.5h, GPA 26.2h, Raízen 25.7h) — matinal 09/07 falhou por weekly limit Claude API. Sem drift Worker nem Frontend (v4.9.149/v201.74 alinhados repo=prod). Working tree com 5 arquivos MEGAPLAN pendentes de commit (Get-AnthropicApiKey + regex auth expandido).
- [[48 - Auditoria Verificador Async 2026-07-10]] — auditoria do script `run_vixradar_verificacao_async.ps1`: guards de refusal (Fable 5), fallback model, parsing, observabilidade. 3 falhas achadas e corrigidas pelo implementador. Veredito: correto no nucleo.
- [[49 - Avaliação Fable 5 e Guards Refusal 2026-07-10]] — avaliação `claude-fable-5` p/ o verificador: 2 testes reais vs Sonnet 4.6 (~USD 1,07), Fable sem ganho demonstrado, custo 2,3x-4,3x. **Decisão: modelo NÃO trocado** (critério de reversão documentado). Guards implementados no dreno: `stop_reason:refusal` + rawout + exit 8 + métrica `refusals` + `--fallback-model` condicional. Achado: `ANTHROPIC_API_KEY` no registro → dreno roda **metered**, não assinatura. Doc drift do `CLAUDE.md` corrigido ("Opus matinal" inexistente; "assinatura" no verificador; "matinal em correção separada" stale).
- [[50 - Análise Competitiva e Baseline SEO 2026-07-11]] — mapa competitivo com preços reais (Quantum Axis R$ 1.940-2.810/mês e Economatica ~R$ 2,8k via contratos públicos; Comdinheiro Basic+ R$ 249,90 vs Radar R$ 119/490), baseline SERP de 10 keywords em 2 instrumentos, 6 gaps de mercado, ameaças (Economatica IA/MCP, XP "Radar do Crédito Privado" na quase-marca). **Nova rotina**: task `VIXRadar-Ranking-Mensal` (dia 1, 11h30) — alerta de ultrapassagem de ranking; notas mensais em `SEO/Ranking SEO YYYY-MM.md`. Pendência SEO1: `RESEND_API_KEY` (User) para ativar o e-mail do alerta.
- [[51 - Pesquisa Preditivo v2 2026-07-11]] — pesquisa web (Jessen&Lando, Robeco, Moody's EWS Toolkit, LLM credit reviews) validando o roadmap v2 da skill `vix-radar-predictive`; achado central: **gargalo é retenção de dados** (KV com TTL evapora o histórico antes de virar dataset). Execução quick wins: exporter diário `VIXRadar-Export-Historico` (20h45, `data/historico/`), labels seed (`data/labels/eventos_credito.jsonl`), Worker **v4.9.150 no repo** (filtro de liquidez ativo, `spread_rel_setor` em shadow, features+`model_version` no payload, leitura de `fundamentals:altman:latest`) — **deploy pendente de aprovação**; Altman Z''-EM trimestral via CVM (`scripts/predictive/`).
- [[52 - Auditoria Completa 2026-07-12]] — auditoria semanal (8 etapas do operador); v4.9.150/v201.74 confirmados ao vivo, sem drift. **2 achados novos**: ALRT1 (`dispararAlertaCritico` sem filtro `prefs.newsletter`, confirmado ao vivo — ALTO) e SPF1 (`send.vixradar.com` ainda em softfail `~all` vs. domínio raiz hardenizado `-all` — MÉDIO). **CRED1**: `admin_senha` da sessão não autenticou contra produção, bloqueando parte da auditoria (saldo de providers + `EMAIL_ALERTAS_ENABLED` ao vivo).
- [[53 - Auditoria Completa 2026-07-13]] — **CRÍTICO**: `VIXRadar-Matinal` parada 3 dias (saldo Anthropic -US$1,21). **Correção (não commitada)**: 3 scripts migrados pay-per-token → assinatura Claude Code. DEF1: noturna 12/07 estourou hard cap (9 deferred). DRIFT1: `app/version.json` desatualizado. Nota: "v4.9.152" citado no corpo refere-se à versão dos *scripts* de rotina, não a um deploy de Worker — `api/wrangler.toml main` segue em `v4.9.150.js`, confirmado (sem `v4.9.151/152.js` no repo).
- [[54 - Auditoria Geral Backend Frontend 2026-07-13]] — `/vix-radar-general-audit`, rodou em paralelo à nota 53 (colisão de sessões documentada). **CHUNK1 (CRÍTICO, novo)**: causa raiz de DEF1 — `Split-IntoChunks` colapsa em lotes de 1 emissor quando a fila cabe em 1 chunk (bug de array-unwrapping PowerShell), reproduzido isoladamente e fix validado (`return ,$chunks`), não aplicado. 3 P1 novos: `op=health-dashboard` com senha admin via querystring GET, XSS confirmado em `renderEventoCard`/conteúdo de IA sem CSP, rate limiter fail-open sem cobertura em login/admin. 6 P2 (case-fold em `receber_analise` = causa raiz de PRED2, mutex ausente no dreno de verificação, cleanup agressivo apaga histórico, N+1 em `comparar`, focus trap ausente em modais confirmado ao vivo, `ADMIN_SENHA` paralelo a `ADMIN_PASSWORD`).
- `PENDENCIAS.md` (root) — **lista viva de pendências**, atualizada 13/07 ~06:40 BRT com os achados desta rodada (notas 53+54)
- [[22 - Sprite Health Check]] — skill `/sprite-health`, VM `site`
- [[23 - Admin HEART Modular v201.66]] — painel admin modular Fase 1
- [[23 - Incidente 2026-06-18 Verificador reprova matinal]] — gate verdade graduada (Onco/Kora)

## Versões confirmadas (última sessão: 2026-07-13 ~06:40 BRT — v4.9.150 em prod, sem drift Worker/Frontend)

> [!warning] Tabela abaixo (Worker v4.9.149/Frontend v201.74/"Opus matinal") está desatualizada — não foi corrigida nas últimas sessões. Fonte viva real: cabeçalho deste arquivo (topo), `PENDENCIAS.md` e `03 - Estado de Produção.md`. Produção confirmada em 2026-07-13: **Worker v4.9.150, Frontend v201.75**, sem drift. Nenhuma rotina usa Opus (drift de documentação, já registrado no `CLAUDE.md` do projeto).

**Produção (stale, ver aviso acima):** v4.9.149 (mesclarEventoVerificado + fix n_eventos=0); Frontend v201.74 (a11y 5 modais); rotina v2 tiered ativa; CI alinhado dinamicamente. Health: `ok:true`, `verificador_ok:true`.

| Componente | Versão | Status |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.149** (prod = repo local) | mesclarEventoVerificado; fix n_eventos=0; sem drift |
| Frontend `vixradar.com` | **v201.74** (prod = repo = deploy_zip) | 8/8 modais com role=dialog+aria-modal; sem drift |
| `ANTHROPIC_API_KEY` | — | ROTACIONADO 2026-06-16 18:22Z — `verificador_ok:true` confirmado |
| Cascade AI | — | Haiku (Pulso manual); Opus (matinal); Sonnet 4.6 (noturno 103/103) |
| vixradar-noturno | — | `listar_todos_emissores` 103/103 → `claude-sonnet-routine` (18h BRT) |
| Cobertura KV | — | **103/103** com `Última análise:` em `dados_para_analise` |

## Pendências abertas (atualizado 2026-06-18 — pós-v4.9.141)

1. ~~**SEGURANÇA** — chave Anthropic exposta em chat 2026-06-16~~ **RESOLVIDO** — rotacionada 2026-06-16 (pós-sessão); `verificador_ok:true` confirmado
2. ~~**CRÍTICO** — OpenRouter 402~~ **RESOLVIDO 2026-06-16** — causa real: `OPENROUTER_API_KEY` no Worker inválida (HTTP 401 na credits API, não 402 de billing). Secret removido via `wrangler secret delete`. Probe agora retorna `sem_chave_openrouter` (gracioso). Cache KV `status_providers` atualiza no próximo cron noturno.
3. ~~**ALTO** — `ADMIN_EMAIL` hardcoded no bundle~~ **RESOLVIDO 2026-06-16** — v4.9.115 usa `env.ADMIN_EMAIL` em runtime; bundle novo não contém e-mail literal em `var ADMIN_EMAIL`.
4. ~~**MÉDIO** — Push do branch `audit/reconcile-prod-2026-06-01` para remote~~ **SUPERADO/RESOLVIDO 2026-06-16** — branch não existe localmente; reconciliação estava em `main`. `main` pushado para `origin/main` até commit `b5e1c7c`.
5. ~~**MÉDIO** — P16~~ **ATIVO v4.9.121** — 16/20 overrides; routine `vixradar-agenda-semanal` registrada (`0 3 * * 1` BRT)
6. ~~**MÉDIO** — P17~~ **ATIVO v4.9.121** — semanal → 16 aprovados `frequencia=semanal`; PILOTO removido; `RELATORIO_DIARIO_ENABLED=1`
7. ~~**MÉDIO** — Deliverability SPAM~~ **RESOLVIDO 2026-06-17** — DNS `SPF -all` + `DMARC p=quarantine`; inbox test enviado (`relatorio_diario_teste` + `newsletter_teste`); dry-run 15 destinatários; envio massa no cron sexta fechamento B3

**Resolvidos anteriormente:** ~~cron `0 2 * * *` duplicado~~ (v4.9.109 — `0 4 * * *`); ~~`CLOUDFLARE_API_TOKEN` secret~~ (2026-06-11); P05* CI; P11 alerta favorito; N06 CRITICIDADE_SETOR.

**Resolvidos nesta sessão (2026-06-11):** P05* CI corrigido; fix Briefing EWS (v201.47, deployado); reconciliação Worker; P11 implementado (v4.9.103→v4.9.104); N06 display corrigido (v4.9.104); Engajamento erro melhorado (v201.48); validação online completa (Claude in Chrome, 02:07 BRT — nenhuma regressão); N06 cálculo corrigido (v4.9.105, `CRITICIDADE_SETOR` alinhado ao `EMISSORES_MAP`, teste 13/13 PASS); credenciais atualizadas (`memory/credenciais.md`).

**Resolvidos 2026-06-18 (auditoria 24):**
- ~~**v4.9.141** em produção~~ — CVM dates + SEC hardening; CI `EXPECTED_WORKER=v4.9.141`
- ~~**ROUTINE_API_KEY rotacionada**~~ — chave antiga retorna 403; rotinas scheduled-tasks + `replay-falhas.ps1` atualizados
- ~~**P1** — Limpar `settings.local.json` (refs `routine_key` antiga na allowlist Bash)~~
- ~~**P2** — Nota 13: `tel_test` documentado com `admin_senha`~~

**Resolvidos nesta sessão (2026-06-18 — v4.9.142 readiness):**
- ~~**P2** — `admin_mercado`: refactor auth POST~~ **RESOLVIDO v4.9.142** — form login usa `method="post"`; handler lê `formData`; fallback GET permanece como P2 residual (não bloqueante)
- ~~**gitignore v4.9.142.js**~~ **RESOLVIDO** — adicionado `!api/v4.9.142.js` linha 91
- ~~**CLAUDE.md podado**~~ **REVERTIDO** — `git checkout CLAUDE.md` restaurou protocolo completo
- **Email modo_teste** — IMPLEMENTADO v4.9.142; ativar pós-deploy via `email_modo_teste_ativar`

**Abertas (hygiene + produto — 2026-06-20):**
1. ~~**P0** — Deploy v4.9.142~~ **SUPERADO** — v4.9.143 em prod (2026-06-20); ativar `email_modo_teste` se ainda pendente
2. **P2** — Watchdog `stale_count:1` (heartbeats)
3. **P2** — Admin HEART Fase 2b — extração completa do monólito (`vr-admin-shared`)
4. **P3** — `admin_corrigir_datas_cvm_kv` em lote pós-matinal
5. **P3** — Incidente matinal 18/06: reanálise Onco/Kora/GPA com fonte CVM primária ([[23 - Incidente 2026-06-18 Verificador reprova matinal]])
6. **Backlog** — Expor `rejeitados` + `veredicto.motivo` no retorno de `receber_analise`
7. **Backlog** — `scheduled-tasks/backups/` com prompts de chave antiga (não runtime, limpar)
8. **Backlog** — N09/N10 (`CLAUDE.md` paths; model IDs no Worker)

Ver lista completa em `memory/sessao-2026-06-11-pendencias.md`.

## Skills VIX Radar (consolidadas no repo 2026-06-18)

Fonte única: `.claude/skills/` no projeto (versionadas no git). Global `~/.claude/skills` é fallback legado.

| Skill | Invocação | Categoria | Status |
|---|---|---|---|
| `vix-radar-session-briefing` | `/vix-radar-briefing` | Master briefing (versões + health + pendências) | ✅ `.claude/skills/vix-radar-session-briefing/` |
| `vix-radar-next-steps` | `/vix-radar-next-steps` | Product advisor (P0/P1/P2 + quick wins) | ✅ `.claude/skills/vix-radar-next-steps/` |
| `vix-radar-audit` | `/vix-radar-audit` | Auditoria completa multi-camada (readonly) | ✅ `.claude/skills/vix-radar-audit/` |
| `vix-radar-general-audit` | `/vix-radar-general-audit` | Auditoria geral backend/frontend + segurança/perf/a11y | ✅ `.claude/skills/vix-radar-general-audit/` |
| `workers-best-practices` | `/workers-best-practices` | Cloudflare Workers anti-patterns | ✅ `.claude/skills/workers-best-practices/` |
| `wrangler` | `/wrangler` | Deploy/bindings/cron Workers | ✅ `.claude/skills/wrangler/` |
| `sprite-health` | `/sprite-health` | Health check via VM Sprite `site` | ✅ `.claude/skills/sprite-health/` |
| `tech-debt-audit` | `/tech-debt-audit` | Dívida técnica (9 dimensões) | ⚠️ só global `~/.claude/skills/` |
| `insecure-defaults` | `/insecure-defaults` | Segurança JWT/CORS/hardcoded | ⚠️ só global `~/.claude/skills/` |

---

## Integração de arquivos recuperados (2026-06-10)

Arquivos recuperados do pendrive SanDisk via PhotoRec e integrados ao vault:

| Arquivo recuperado | Nota gerada | Conteúdo |
|---|---|---|
| `prompt-analista-senior-credito-privado.txt` | Nota 07 | Sistema de classificação ~v4.6 (3 tiers, Gemini direto) |
| `prompt-classificacao-eventos-ruido-eco.txt` | Nota 07 | Sistema de classificação ~v4.8 (4 tiers, ECO, OR+Gemini) |
| `doc-analise-risco-fallback-providers.txt` | Nota 08 | Matriz de risco, pipeline validação, observabilidade, deploy governance |
| `worker-debug-matcher-fontes-v4.9.69.txt` | — | Fragmento de CLAUDE.md; conteúdo já coberto, não integrado separadamente |
| `radar-threads-pedro-yan-fev-2026.txt` | — | **EXCLUÍDO — LGPD.** Contém dados pessoais de clientes. Não integrado. |
