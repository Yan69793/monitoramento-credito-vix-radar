# Otimizacao Tokens Rotina Noturna

**Data:** 2026-06-19  
**Status:** **v4.9.143 em produção** — `verify-rotinas-v2.ps1 -Live` 0 falhas (2026-06-19)  
**Contexto:** duplicação AI (Claude 18h + Worker cron 18:30) e 824 buscas/noturno.

---

## Diagnóstico (causa raiz)

| Horário BRT | Canal | Escopo | Custo |
|-------------|-------|--------|-------|
| 10h | Claude `vixradar-matinal` | top 15, 9 rodadas | alto |
| 12:30 | Worker cron | top 30 Haiku | **duplicado** |
| 18h | Claude `vixradar-noturno` | 103×9 rodadas | **~824 buscas** |
| 18:30 | Worker cron | 103 Haiku + newsletter | **duplicado** |

`dados_para_analise` já traz `cvm_documentos` — R1 web é redundante.

---

## Arquitetura v2 (implementada)

### Divisão de papéis

- **Worker cron:** sync CVM, ANBIMA, newsletter, health — **sem** `executarVarreduraMatinal` / `executarVarreduraBatchComFila` quando `VARREDURA_CRON_AI_ENABLED=false`.
- **Claude scheduled:** análise tiered via `listar_plano_rotina` (1 call vs 103× `dados_para_analise`).

### Tiers

| Tier | % típico | Buscas | Quando |
|------|----------|--------|--------|
| SKIP | ~60–70% | 0 | scan <24h, sem delta CVM, EWS baixo |
| LIGHT | ~20% | 3–4 | EWS médio ou stale 2d |
| FULL | ~15% | 6–8 | EWS≥50, CVM novo, stale>5d, materialidade alta |
| AUDIT | 5/dia | 6–8 | SKIP promovido rotativo (recall) |

R1 omitida — CVM vem do Worker no plano.

### Endpoint novo

`action=listar_plano_rotina` + `modo=matinal|noturno` + `routine_key`

Retorna: `emissores[]` com `tier`, `rodadas`, `cvm_documentos`, `contagem_tiers`, `buscas_estimadas`, `economia_pct`.

### Artefatos

| Arquivo | Função |
|---------|--------|
| `api/v4.9.143.js` | `montarPlanoRotina`, flag cron |
| `api/wrangler.toml` | `VARREDURA_CRON_AI_ENABLED=false` |
| `scheduled-tasks/_shared/rotina-v2-core.md` | regras tiers |
| `vixradar-matinal/SKILL.md` | top 15 tiered |
| `vixradar-noturno/SKILL.md` | 103/103 ledger |
| `scripts/verify-rotinas-v2.ps1` | validação local + `-Live` |

---

## Economia esperada

- **Noturno legado:** 103 × 8 = 824 buscas
- **Noturno v2:** ~80–150 buscas (estimativa; depende de delta CVM/EWS do dia)
- **Matinal legado:** 15 × 9 = 135 buscas
- **Matinal v2:** ~30–60 buscas

---

## Métricas live (2026-06-19 pós-deploy)

| Modo | Tiers | Buscas | Economia |
|------|-------|--------|----------|
| Matinal (15) | SKIP 4 / LIGHT 5 / FULL 6 | 57/120 | 53% |
| Noturno (103) | SKIP 29 / LIGHT 44 / FULL 25 / AUDIT 5 | 351/824 | 57% |

`varredura_cron_ai=false` confirmado em prod.

## Agendamento durável (Windows Task Scheduler)

| Task | Horário | Script |
|------|---------|--------|
| `VIXRadar-Matinal` | 10:00 seg-sex | `scripts/run_vixradar_matinal_claude.ps1` |
| `VIXRadar-Noturno` | 18:00 diário | `scripts/run_vixradar_noturno_claude.ps1` |

Registrar: `.\scripts\register-vixradar-scheduler.ps1`  
Logs: `logs/routines/vixradar-{matinal,noturno}_YYYYMMDD.log`

Substitui `CronCreate` session-only do Claude CLI. Worker cron mantém sync CVM/ANBIMA/newsletter 18:30.

## Gate concluído

1. ~~Deploy v4.9.143~~ ✅
2. ~~`verify-rotinas-v2.ps1 -Live`~~ ✅
3. ~~Dry-run 3 tiers~~ ✅ (`dry-run-rotinas-v2.ps1`)
4. ~~Task Scheduler durável~~ ✅ (`register-vixradar-scheduler.ps1`)

---

## Mitigações (inalteradas)

- EWS alto → FULL obrigatório
- AUDIT 5/dia em SKIP
- CRITICO exige URL verificável
- Newsletter 18:30 intacto no cron noturno