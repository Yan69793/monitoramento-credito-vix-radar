---
data: 2026-08-06
tipo: indice
tags: [vix-radar, moc, indice, mapa]
status: ativo
---

# VIX Radar — Indice (MOC)

Mapa do vault. Atualizado 2026-08-31 BRT.

## Estado atual

| Componente | Versao |
|---|---|
| Worker | v4.9.228 |
| Frontend | v202.35 |
| Health | `ok:true`, kv/rate_limiter/telemetria true, verificador_ok:true, providers 2/2, admin_email_ok:true, sentry_ok:true (31/08, HTTP 200, TEMPO 0.23s) |
| Cobertura | Rotinas de 21/08 executadas por sessão multi-provedor: verificação 23/23, matinal 19/19 e noturna 103/103. O frontend v202.35 separa a data do último evento da data de atualização da base, para deixar explícito que a rotina pode concluir sem fato novo. **Worker em v4.9.228 desde 01/09** (os 4 achados P3/P4 da auditoria geral de 01/09 fechados: DISJUNTORHOUSEKEEP1, LOGINTIMING1, governança da skill e contagem de heartbeats no CLAUDE.md; nota 98). Antes, v4.9.227 desde 31/08 (BRASKEMDETECT1 fechado, nota 97). Sessão 24/08: SACFALSA-RESIDUO e CACHEBUMP1 fechados e commitados (3 commits, nota 90). Ver [[87 - Fechamento Rotinas 2026-08-21]], [[88 - Sessao Frontend Mobile 2026-08-21]], [[89 - Auditoria Geral 2026-08-22]], [[90 - Auditoria Geral 2026-08-24]] e [[97 - Fechamento BRASKEMDETECT1 e Deploy v4.9.227 2026-08-31]]. |

Ver [[03 - Estado Atual]] para snapshot completo. Pendencias em [[PENDENCIAS.md]].

## Notas por categoria

### Estado e infraestrutura

| Nota | Descrição |
|---|---|
| [[03 - Estado Atual]] | Snapshot de produção (versões, health, tasks, pendências) |
| [[03a - Changelog]] | Log cronológico de incidentes e deploys (julho 2026) |
| [[03b - Infraestrutura]] | Bindings, crons, CORS, segurança, auth, cascade AI |
| [[04c - Histórico de Versões Worker]] | Histórico completo de deploys do Worker |
| [[05 - Histórico de Versões Frontend]] | Histórico completo de deploys do Frontend |

### Auditorias recentes (julho 2026)

| Nota | Data | Tipo |
|---|---|---|
| [[89 - Auditoria Geral 2026-08-22]] | 22/08 | Geral readonly: nucleo sem achado (auth fail-closed, veracidade UI batendo com o glossario, drift zero, health verde). 5 P3 novos: WRCGL1, PULSOEVENTO1, JANELACARD1, ESTADOSTALE1, WORKTREE22 |
| [[90 - Auditoria Geral 2026-08-24]] | 24/08 | Geral readonly pos-deploy v4.9.208/v202.30: saude do nucleo (portao 200 ok:true, 3 probes auth fail-closed, veracidade UI batendo com o glossario, drift zero, CRLF 317 arquivos = ruido, diff -w 0). Observacoes: fonte_externa_ok:false (cadencia CVM, nao incidente) e main ahead 2 de origin. Zero P0/P1/P2 novos |
| [[91 - Auditoria Operacional 2026-08-24]] | 24/08 | Operacional pos v4.9.212: health ok:true, auth 401 fail-closed, drift zero, guarda cadastro two-way OK. **Achado novo ALTO: RELOGIO3H1** (_last_scanned_at 3h no passado infla horas_stale; gate de cobertura deu falso ALTO, cobertura real 103/103) |
| [[92 - Vistoria Feed Noticias 2026-08-29]] | 29/08 | Recado readonly do relato "noticias paradas desde 25/08": feed correto (MAX data_evento 25/08 via op=state), causa externa esperada (CVM quiet desde 25/08, proxima publicacao 30/08) + gap interno 28/08 (app do Claude Desktop fechado, WATCHDOG-NAOINICIOU1). Catch-up rodando. Follow-up: re-probe op=state apos noturna de hoje |
| [[95 - Auditoria Geral 2026-08-30 (madrugada)]] | 30/08 | Segunda auditoria do dia (madrugada): nucleo saudavel, achados novos AGENDA401 (agenda publica morta, 401 cru) e RECONCILE-CVM404 (reconciliacao ia falhar de novo com ZIP 2026 fora), mais confirmacoes de SENTINELA-DIAPERDIDO1 e AGENDASEM-TRAVA1 do 93. FALLBACKTTL1 e VERIFCACHE-ROUNDTRIP1 ficam para o v4.9.222 |
| [[94 - Reposicao de Varredura e Skill REPOSIC1 2026-08-30]] | 30/08 | Sessao de fechamento da skill `/repor-varredura` (REPOSIC1): skill + script + prompt anti-ancoragem + payloads commitados (`a2e011d`, `985e3e5`, sem push). Reposicao verificada em producao (Braskem max data_evento 28/08). Fix no caminho: `submit_ok` passou a medir evento persistido, nao POST aceito |
| [[97 - Fechamento BRASKEMDETECT1 e Deploy v4.9.227 2026-08-31]] | 31/08 | Fechamento da pendencia BRASKEMDETECT1 (protocolo extrajudicial da Braskem 24/08 nao alcancado pela imprensa): query R5/R3 com "extrajudicial", PALAVRAS_CRITICAS nas duas formas, emitirAlertaTier1 promove a tag. Guarda gatilho-recuperacao.test.mjs (5 testes), suite 158/158. Deploy v4.9.227, portao verde, commits dddb009/bb1ec65/af2abb1/ea5dfdb |
| [[96 - Backlog task-observer 2026-08-30]] | 30/08 | Revisao do backlog do task-observer (12 observacoes OPEN de 17 a 24/08): consolidacao por skill (auditoria, ysz-superpowers, relatorio-diario-szuchmacher, frontend-design), 8 regras de coleta/correcao no Windows para a auditoria, propostas de atualizacao de skill aguardando aprovacao. Nenhuma skill alterada |
| [[87 - Fechamento Rotinas 2026-08-21]] | 21/08 | Execucao manual das 3 rotinas do dia (Claude Desktop sem creditos): verificacao 23/23, matinal 19/19, noturna 103/103, health ok:true |
| [[88 - Sessao Frontend Mobile 2026-08-21]] | 21/08 | Frontend: refresh de dados ao voltar para a aba, rodada mobile auditada com Lighthouse (A11y 100, BP 100, SEO 100), deploys v202.24-v202.28, SyntaxError v202.24 corrigido em v202.25 |
| [[86 - Rotacao routine_key e envelope noturno 2026-08-18]] | 18/08 | Execucao: rotacao da routine_key nos 3 destinos (P1 fechado), envelope do noturno recalibrado, ROTA1, pre-flight fixes, graphify-out ignorado |
| [[85 - Auditoria Geral e Preditiva 2026-08-18]] | 18/08 | Geral + preditiva readonly: Merton 0/103 (market_cap nunca coletado), P3s de governanca e a11y |
| [[81 - Auditoria Geral e incidentes 2026-08-13]] | 13/08 | Geral: AUTHWEEK1 (cascade parado), GHWL1 (secret GH divergente), XSS v100 fechado, BOM fechado |
| [[68 - Avaliação Claude Fable 5 para Otimização do Sistema (2026-07-26)]] | 26/07 | Pesquisa, Fable 5 nao recomendado para producao, fix compliance na politica de privacidade |
| [[67 - Auditoria Geral 2026-07-25]] | 25/07 | Geral, drift FE v201.88 + VERSAO3X recorrente + notas 65/66 ausentes do MOC |
| [[66 - Preditivo lab interno 2026-07-21]] | 21/07 | Decisao: preditivo so interno, pesquisa/backtest |
| [[65 - Auditoria Geral 2026-07-21-tarde]] | 21/07 | Geral pos-deploy v4.9.168/v201.81, OPENROUTERVIVO, Merton |
| [[64 - Auditoria Geral 2026-07-21]] | 21/07 | Geral 4 camadas, 2 P1 novos (ADMINXSS1, VOLTASK1) + Merton confirmado |
| [[62 - Auditoria Completa e Correcoes 2026-07-20]] | 20/07 | Auditoria + correções (F002, F014, INGEST-GAP1) |
| [[63 - Recovery e Deploy 2026-07-20]] | 20/07 | Recovery pós INGEST-GAP1 + deploy v4.9.167 |
| [[60 - Pesquisa e Ideias, Proveniência de Fonte e Ground Truth CVM 2026-07-16]] | 16/07 | Pesquisa CVM + proveniência |
| [[59 - Incidente RESEARCHDOWN1 (Oncoclinicas CRITICO rebaixado) 2026-07-15]] | 15/07 | Incidente classificação |
| [[58 - Auditoria Completa 2026-07-15]] | 15/07 | Auditoria operacional |
| [[57 - Auditoria Geral (Addendum IA-LLM e Runtime Workers) 2026-07-14]] | 14/07 | IA/LLM + Workers runtime |
| [[56 - Auditoria Geral Backend Frontend 2026-07-14]] | 14/07 | Auditoria geral |
| [[55 - Auditoria Completa 2026-07-14]] | 14/07 | Auditoria operacional |
| [[54 - Auditoria Geral Backend Frontend 2026-07-13]] | 13/07 | CHUNK1 + 3 P1 (XSS, rate limiter, health-dashboard) |
| [[53 - Auditoria Completa 2026-07-13]] | 13/07 | Matinal parada 3 dias, migração assinatura |
| [[52 - Auditoria Completa 2026-07-12]] | 12/07 | Auditoria semanal (ALRT1, SPF1) |
| [[51 - Pesquisa Preditivo v2 2026-07-11]] | 11/07 | Preditivo + Altman + exporter |
| [[50 - Análise Competitiva e Baseline SEO 2026-07-11]] | 11/07 | SEO + competitivo + Ranking-Mensal |
| [[49 - Avaliação Fable 5 e Guards Refusal 2026-07-10]] | 10/07 | Fable 5 vs Sonnet, guards de refusal |
| [[48 - Auditoria Verificador Async 2026-07-10]] | 10/07 | Script verificador async |
| [[47 - Auditoria Completa 2026-07-09 (v2)]] | 09/07 | Stale 3 emissores |
| [[46 - Auditoria Completa 2026-07-09]] | 09/07 | Painel sem notícias desde 06/07 |
| [[45 - Auditoria Geral 2026-07-07 (noite)]] | 07/07 | Auditoria noite |
| [[44 - Auditoria Geral Backend Frontend 2026-07-07 (tarde)]] | 07/07 | admin_mercado GET, XSS, a11y, tel() |
| [[43 - Auditoria Geral Backend Frontend 2026-07-07 (manhã)]] | 07/07 | Bundles untracked, encoding, drift XSS/F1 |
| [[42 - Auditoria Geral Backend Frontend 2026-07-06]] | 06/07 | F1 localStorage, script untracked |
| [[41 - Auditoria Completa 2026-07-06]] | 06/07 | Noturno duplicado (colisão tasks) |
| [[40 - Auditoria Geral Backend Frontend 2026-07-05]] | 05/07 | Bug encoding CP850 (P0) |
| [[39 - Auditoria Completa 2026-07-04]] | 04/07 | Health-gate bloqueou noturna (0/103) |
| [[38 - Auditoria Geral Backend Frontend 2026-07-04]] | 04/07 | 3 P1 resolvidos, secret routine_key |
| [[37 - Auditoria Geral Backend Frontend 2026-07-03]] | 03/07 | 3 P1 scripts rotina |
| [[36 - Auditoria Completa 2026-07-03]] | 03/07 | Saudável, cleanup bug |
| [[35 - Auditoria Completa 2026-07-02]] | 02/07 | Rotinas paradas 9 dias (P0) |

### Pesquisas e análises

| Nota | Data | Tema |
|---|---|---|
| [[68 - Avaliação Claude Fable 5 para Otimização do Sistema (2026-07-26)]] | 26/07 | Reavaliacao Fable 5 (segue nao recomendado), correcao de arquitetura de IA desatualizada, proposta de piloto shadow-mode |
| [[60 - Pesquisa e Ideias, Proveniência de Fonte e Ground Truth CVM 2026-07-16]] | 16/07 | CVM ground truth, CNPJ matching |
| [[51 - Pesquisa Preditivo v2 2026-07-11]] | 11/07 | Roadmap preditivo, Altman Z''-EM |
| [[50 - Análise Competitiva e Baseline SEO 2026-07-11]] | 11/07 | Concorrência, SERP, preços |
| [[49 - Avaliação Fable 5 e Guards Refusal 2026-07-10]] | 10/07 | Model evaluation |

### Incidentes

| Nota | Data | Incidente |
|---|---|---|
| [[77 - Post-Mortem verificador_ok e Proposta canonical-test.yml 2026-08-11]] | 11/08 | Fila de verificação travada por ambiente contaminado (05/08), gap de observabilidade no canonical-test.yml ainda aberto — mesmo padrão se repetiu 11/08 |
| [[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]] | 27/07 | Deploy quebrado por UTF-8 sem BOM, mais sintaxe PS7 em script rodado pelo 5.1, guarda no pre-commit |
| [[63 - Recovery e Deploy 2026-07-20]] | 20/07 | INGEST-GAP1 recovery |
| [[59 - Incidente RESEARCHDOWN1 (Oncoclinicas CRITICO rebaixado) 2026-07-15]] | 15/07 | Classificação incorreta |
| [[23b - Incidente 2026-06-18 Verificador reprova matinal]] | 18/06 | Verificador falso-positivo |

### Referência e métodos

| Nota | Descrição |
|---|---|
| [[13 - Metodo de Vistoria Operacional]] | Protocolo `/vix-radar-audit` |
| [[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]] | Regra: todo `.ps1` tem que parsear no `powershell.exe` 5.1. Guarda em `scripts/lint-encoding.ps1` mais pre-commit |
| [[11 - Runbook Deploy Cloudflare Pages]] | Deploy do frontend |
| [[10 - Oportunidades de Melhoria (2026-06-11)]] | Backlog de melhorias |
| [[08 - Análise de Risco e Arquitetura de Confiabilidade]] | Matriz de risco, pipeline |
| [[07 - Evolução do Sistema de Classificação e Prompts]] | Histórico de tiers e prompts |

### Design e features

| Nota | Descrição |
|---|---|
| [[23a - Admin HEART Modular v201.66]] | Painel admin modular |
| [[17 - Email Relatorio e Deliverability 2026-06-17]] | E-mail, SPF, DMARC, newsletter |
| [[16 - Design P16 P17 Agenda e Relatorio]] | Agenda semanal + relatório diário |

### Rotinas e monitoramento

| Nota | Descrição |
|---|---|
| [[84 - Rotina Matinal 2026-08-15]] | Matinal 15/08: 19/19 (retry pós troca de modelo), 3 CRITICOs (Oncoclínicas, Kora Saúde, CSN) |
| [[34 - Rotina Matinal 2026-06-22]] | Execução matinal |
| [[Rotina Noturna 2026-08-14]] | Noturna 14/08: 103/103, 5 CRITICOs, cap de tokens estourado |
| [[30 - Monitor CRITICOs 2026-06-20]] | Rastreamento de críticos |
| [[29 - Rotina Noturna 2026-06-20]] | Execução noturna |
| [[27 - Otimizacao Tokens Rotina Noturna]] | Otimização de tokens |
| [[22 - Sprite Health Check]] | Health via VM Sprite |
| [[20 - Monitoramento Loop 2026-06-17]] | Loop de monitoramento |

### Auditorias junho 2026 (arquivo referencial)

| Nota | Data |
|---|---|
| [[26b - Auditoria Completa 2026-07-01]] | 01/07 |
| [[25a - Auditoria Completa 2026-06-30]] | 30/06 |
| [[25b - Deploy Readiness v4.9.142]] | 30/06 |
| [[24 - Auditoria Completa 2026-06-18 (pós v4.9.141)]] | 18/06 |
| [[21 - Auditoria Completa 2026-06-18]] | 18/06 |
| [[19 - Auditoria Completa 2026-06-17 (pós v201.63)]] | 17/06 |
| [[18 - Auditoria Completa 2026-06-17]] | 17/06 |
| [[15 - Auditoria Completa 2026-06-16 (v2)]] | 16/06 |
| [[14 - Auditoria Completa 2026-06-16]] | 16/06 |
| [[12 - Auditoria Completa 2026-06-14]] | 14/06 |
| [[09 - Auditoria 2026-06-10 (Pendências)]] | 10/06 |
| [[04a - Auditoria 2026-06-07]] | 07/06 |
| [[04b - Auditoria 2026-06-08]] | 08/06 |

Ver também: [[26a - Auditoria Completa 2026-06-18 (caveman)]], [[31 - Auditoria Completa 2026-06-20]], [[32 - Auditoria Geral Backend Frontend 2026-06-20]], [[33 - Auditoria Geral 2026-06-22]].

### Subdiretórios

| Pasta | Conteúdo |
|---|---|
| `SEO/` | Ranking SEO mensal |
| `rotinas/` | Logs de execução de rotinas |
| `Reconciliacao-CVM/` | Reconciliação CNPJ vs CVM |
| `_Arquivo/` | Notas históricas e stubs arquivados |

## Skills do projeto

Fonte: `.claude/skills/` no repo. Ver `CLAUDE.md` para lista completa.

| Skill | Função |
|---|---|
| `vix-radar-audit` | Auditoria operacional multi-camada |
| `vix-radar-general-audit` | Auditoria backend/frontend + segurança |
| `vix-radar-session-briefing` | Briefing de estado atual |
| `vix-radar-next-steps` | Product advisor (P0-P3) |
| `vix-radar-predictive` | Motor preditivo de crédito |
| `workers-best-practices` | Anti-patterns Cloudflare Workers |

## Arquivos externos ao vault

| Arquivo | Localizacao | Funcao |
|---|---|---|
| `CLAUDE.md` | Root do projeto | Instrucoes do agente + deploy |
| `PROMPTS-RADAR.md` | Root do projeto | Prompts do sistema |
| `README.md` | Root do projeto | Documentacao publica |

---

*Vault recriado em 2026-06-07. Reorganizado em 2026-07-20 (split do 03, frontmatter YAML, correção de duplicatas).*
