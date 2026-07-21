---
data: 2026-07-20
tipo: indice
tags: [vix-radar, moc, indice, mapa]
status: ativo
---

# VIX Radar — Índice (MOC)

Mapa do vault. Atualizado 2026-07-20 16h30 BRT.

## Estado atual

| Componente | Versão |
|---|---|
| Worker | v4.9.167 |
| Frontend | v201.80 |
| Health | `ok:true`, verificador ok |
| Cobertura | 103/103 emissores, 0 stale |

Ver [[03 - Estado Atual]] para snapshot completo. Pendências em [[PENDENCIAS.md]] (root do projeto).

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
| [[60 - Pesquisa e Ideias, Proveniência de Fonte e Ground Truth CVM 2026-07-16]] | 16/07 | CVM ground truth, CNPJ matching |
| [[51 - Pesquisa Preditivo v2 2026-07-11]] | 11/07 | Roadmap preditivo, Altman Z''-EM |
| [[50 - Análise Competitiva e Baseline SEO 2026-07-11]] | 11/07 | Concorrência, SERP, preços |
| [[49 - Avaliação Fable 5 e Guards Refusal 2026-07-10]] | 10/07 | Model evaluation |

### Incidentes

| Nota | Data | Incidente |
|---|---|---|
| [[63 - Recovery e Deploy 2026-07-20]] | 20/07 | INGEST-GAP1 recovery |
| [[59 - Incidente RESEARCHDOWN1 (Oncoclinicas CRITICO rebaixado) 2026-07-15]] | 15/07 | Classificação incorreta |
| [[23b - Incidente 2026-06-18 Verificador reprova matinal]] | 18/06 | Verificador falso-positivo |

### Referência e métodos

| Nota | Descrição |
|---|---|
| [[13 - Metodo de Vistoria Operacional]] | Protocolo `/vix-radar-audit` |
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
| [[34 - Rotina Matinal 2026-06-22]] | Execução matinal |
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

| Arquivo | Localização | Função |
|---|---|---|
| `PENDENCIAS.md` | Root do projeto | Lista viva de pendências priorizadas |
| `CLAUDE.md` | Root do projeto | Instruções do agente + deploy |
| `PROMPTS-RADAR.md` | Root do projeto | Prompts do sistema |
| `README.md` | Root do projeto | Documentação pública |

---

*Vault recriado em 2026-06-07. Reorganizado em 2026-07-20 (split do 03, frontmatter YAML, correção de duplicatas).*
