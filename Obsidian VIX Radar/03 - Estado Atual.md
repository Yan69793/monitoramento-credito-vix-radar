---
data: 2026-07-20
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 20/07 16h00 BRT — Sistema 100% operacional. Ver [[63 - Recovery e Deploy 2026-07-20]].

## Versões

| Componente | Versão | Health |
|---|---|---|
| Worker | **v4.9.167** | `ok:true`, kv/telemetria/verificador ok |
| Frontend | **v201.80** | `CACHE_VERSION=v201.80`, sem drift |
| Git | `1842499` | pushado, `origin/main` sincronizado |

## Cobertura

| Métrica | Valor |
|---|---|
| Emissores | 103/103 |
| Stale | 0 |
| Último scan | 20/07 15:46 BRT (Matinal) |
| Críticos ativos | 7 (Oncoclínicas, Kora Saúde, Raízen, Oi, Cosan, +2) |

## Tasks Scheduler

| Task | Trigger | StartWhenAvailable | Status |
|---|---|---|---|
| VIXRadar-Matinal | 10h seg-sex | true | OK |
| VIXRadar-Noturno | 18h diário | true | OK |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok |
| RATE_LIMITER_DO | ok |
| RADAR_USAGE_EVENTS | ok |
| ESTADO_SEMANA_DO | ok |
| Providers | 2/2 (Resend + Anthropic) |

## Pendências ativas

Ver [[PENDENCIAS.md]] no root. Resumo:

| P | Item |
|---|---|
| P2 | SPF `send.vixradar.com` hardenizar para `-all` |
| P2 | FOCUSTRAP1 — focus trap em 8 modais |
| P3 | Consolidar ADMIN_SENHA / ADMIN_PASSWORD |
| P3 | Decidir script canônico de registro (REGDRIFT1) |

---

*Snapshot gerado em 2026-07-20. Para changelog completo: [[03a - Changelog]]. Para detalhes de infra: [[03b - Infraestrutura]].*
