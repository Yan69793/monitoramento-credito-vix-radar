# Design P16 / P17 — Agenda de Divulgação e Relatório Diário

Data: 2026-06-16 | Status: **implementado v4.9.119** (deploy 2026-06-16, CF Version ID `37d691d4`)

> Nota de numeração: no MOC, P16/P17 referem-se a **produto** (agenda + relatório). Em notas antigas, "P16" também nomeou flags `em_reestruturacao` (já implementado em v4.9.107). Este documento trata apenas agenda de divulgação e relatório diário.

---

## Estado atual (já em produção)

| Peça | Onde | Status |
|---|---|---|
| Build agenda 90d | `agendaBuildPersistir` em `api/v4.9.118.js` | ✅ implementado |
| Cron diário | `0 4 * * *` (01h BRT) em `api/wrangler.toml` | ✅ ativo desde v4.9.109 |
| KV destino | `agenda:eventos:v1` (TTL 3d) | ⏳ aguarda 1ª execução pós-deploy ou rebuild manual |
| Fontes | `CALENDARIO_RESULTADOS_V1` + `mercado:serie` (vencimentos ANBIMA) + `cvm:documentos` | ✅ |
| Frontend | `#agenda-overlay` lê KV via Worker | ✅ v201.51 |
| Rebuild manual | `GET /?op=admin_agenda_rebuild` + header `x-admin-password` | ✅ |
| Newsletter diária | cron `30 21 * * *` (18h30 BRT) | ✅ Resend |

**Conclusão:** a infraestrutura de agenda **não está vazia** — o gap P16 original (`admin:agenda_divulgacao` vazio, cron inexistente) foi **superado** em v4.9.109. O que falta é **enriquecimento** e **rotina de atualização de calendário de resultados**.

---

## P16 — Agenda de Divulgação (escopo refinado)

### Objetivo de produto

Manter datas de divulgação trimestral dos 103 emissores atualizadas com mínimo de chamadas API, alimentando `CALENDARIO_RESULTADOS_V1` e, por cascata, `agenda:eventos:v1`.

### Proposta

**Routine Claude Opus:** `vixradar-agenda-semanal`

| Campo | Valor |
|---|---|
| Cron | `0 6 * * 1` (segunda 03h BRT) + jitter ~+8min |
| Modelo | Claude Opus (rotina agendada, mesmo padrão matinal/noturno) |
| Escopo | Emissores com `trimestres[].data_prevista` ausente ou `ultima_atualizacao` > 7 dias |
| Batch | 15–20 emissores/semana (rotação — cobre universo em ~5–7 semanas) |
| Fontes | Sites RI, CVM RAD, B3 (sem API paga) |
| Output | JSON `{ empresa, trimestres: [{ periodo, data_prevista, horario, fonte }] }` |
| Push | Novo endpoint Worker `action=atualizar_calendario_emissor` (routine_key) → merge em KV `calendario:emissor:{slug}` ou patch in-memory `CALENDARIO_RESULTADOS_V1` persistido |

**Pós-push:** cron `0 4 * * *` já reconstrói `agenda:eventos:v1` automaticamente.

### Esforço estimado

| PR | Conteúdo | Esforço |
|---|---|---|
| 1 | Endpoint `atualizar_calendario_emissor` + KV schema | Médio |
| 2 | SKILL.md `vixradar-agenda-semanal` + `create_scheduled_task` | Baixo |
| 3 | Frontend: badge "calendário stale" no admin (opcional) | Baixo |

### Critérios de aceite

- Após 2 semanas de routine, `cobertura_build.com_resultado` ≥ 60% dos 103 emissores no payload `agenda:eventos:v1`
- Nenhuma chamada Anthropic no cron Worker (só na routine semanal)
- Rebuild manual continua funcionando sem routine

---

## P17 — Relatório Diário Automático

### Objetivo de produto

E-mail HTML diário (dias úteis) com snapshot do briefing executivo — eventos críticos/relevantes do dia, top EWS, agenda 7d — sem exigir login no dashboard.

### Proposta

**Opção A (recomendada):** estender cron existente `30 21 * * *`

Fluxo no Worker após newsletter atual:

1. Montar payload interno reutilizando lógica de `handleBriefingExecutivo` (já existe)
2. Renderizar template HTML Resend (novo `templates/relatorio_diario.html` embutido no bundle ou KV)
3. Enviar para destinatários com `prefs.newsletter !== false` e `prefs.frequencia` ∈ `diario|semanal` (novo valor `diario`)
4. Dedup KV `relatorio:enviado:{YYYY-MM-DD}` (mesmo padrão `newsletter:enviada:{hoje}`)

**Opção B (alternativa):** routine Claude gera narrativa — **rejeitada** (custo Opus diário desnecessário; dados já estruturados no Worker).

### Conteúdo do e-mail (MVP)

| Seção | Fonte |
|---|---|
| Resumo | total eventos 24h, críticos, relevantes |
| Top 5 alertas EWS | `handleEWS` |
| Eventos novos por emissor favorito do usuário | se `EMAIL_ALERTAS_FAVORITOS=1` |
| Agenda 7d | slice de `agenda:eventos:v1` |
| Link CTA | `https://vixradar.com` + deep-link briefing |

### Esforço estimado

| PR | Conteúdo | Esforço |
|---|---|---|
| 1 | `executarRelatorioDiario(env)` + template HTML | Médio |
| 2 | Hook no cron `30 21 * * *` (flag `RELATORIO_DIARIO_ENABLED`) | Baixo |
| 3 | Frontend: toggle "Relatório diário" em config (prefs `relatorio_diario`) | Baixo |

### Critérios de aceite

- E-mail enviado 1×/dia útil até 18h35 BRT (margem pós-noturno 18h)
- "Setores cobertos" usa `SETOR_DE_EMPRESA` (fix N06 já em v4.9.105+)
- Kill-switch `RELATORIO_DIARIO_ENABLED` secret (default off até validação)

---

## Priorização sugerida

| ID | Item | Impacto | Esforço | Ordem |
|---|---|---|---|---|
| P16 | Routine semanal calendário | Médio | Médio | 1º |
| P17 | Relatório diário HTML | Alto | Médio | 2º |

---

## Atualização memory

Marcar em `memory/sessao-2026-06-11-pendencias.md`: P16/P17 passam de "design pendente" para "design em [[16 - Design P16 P17 Agenda e Relatorio]] — implementação pendente".