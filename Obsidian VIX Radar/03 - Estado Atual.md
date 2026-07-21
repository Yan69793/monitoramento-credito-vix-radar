---
data: 2026-07-21
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 21/07 — Worker v4.9.170 + frontend v201.83. Preditivo lab interno, gate unificado, UI limpa. Ver [[66 - Preditivo lab interno 2026-07-21]].

## Versões

| Componente | Versão | Health |
|---|---|---|
| Worker | **v4.9.170** | `ok:true`, kv/telemetria/verificador ok |
| Frontend | **v201.83** | `CACHE_VERSION=v201.83` |
| Git | `0ded699` (+ worker `6ac1f2f`) | prod alinhada |

## Cobertura

| Métrica | Valor |
|---|---|
| Emissores | 103 (universo) |
| Matinal 21/07 | submit_ok=18, dreno verif ok |
| Noturno 20/07 | submit_ok=103 no run real; metrics JSON zerado no skip 18h (METRICSZERO1) |
| Criticos (matinal) | Oncoclínicas, GPA, Cosan, CSN |

## Tasks Scheduler

| Task | Trigger | Status recente |
|---|---|---|
| VIXRadar-Matinal | 10h seg-sex | 21/07 10:00 Result 0 |
| VIXRadar-Noturno | 18h diario | 20/07 18:00 Result 0 (skip idempotente); proximo 21/07 18:00 |
| VIXRadar-Coleta-Volatilidade | ~17h | 21/07 13:29 Result 0, mas cotacoes sucesso=0 (VOLFEED1) |
| VIXRadar-Verificacao-Async | 10:20 | 21/07 Result 0 |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok |
| RATE_LIMITER_DO | ok |
| RADAR_USAGE_EVENTS | ok |
| ESTADO_SEMANA_DO | declarado + usado no bundle (nao exposto no health publico) |
| Providers | 2/2 (Resend + Anthropic) |

## Pendências ativas (topo)

Ver [[PENDENCIAS.md]]. Topo pos auditoria 65:

| P | Item |
|---|---|
| P1 | MERTONLIVE1 — driver invisivel com score movendo |
| P2 | VOLFEED1 — coleta sobe com 0 cotacoes novas |
| P2 | METRICSZERO1, VERIFQ-ORFAO1, VERIFINJ1, DEDUPFILA1, ROUTINEKEY-PLAIN1, SPF1, FOCUSTRAP1 |

---

*Snapshot gerado em 2026-07-21 (auditoria geral tarde). Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
