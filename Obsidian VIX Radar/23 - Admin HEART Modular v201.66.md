# Admin HEART Modular — v201.66

Data: 2026-06-18 | Fase 1 concluída (módulo externo + aba Hoje)

## Objetivo

Refatorar o painel admin em módulos sem extrair o monólito do `index.html`, conectar aos endpoints existentes e expor métricas **HEART** (Happiness, Engagement, Adoption, Retention, Task Success) com visual inspirado em Linear/Vercel.

## Arquitetura

| Artefato | Caminho | Papel |
|---|---|---|
| Core admin (legado) | `app/index.html` | Overlay `#admin-overlay`, abas Usuários/Engajamento/Métricas/Sistema/Flags RE |
| Módulo HEART | `app/admin/vr-admin-modules.js` | Patch de `abrirAdmin`, `adminAutenticar`, `adminAbaAtiva`; injeta aba **Hoje** |
| Deploy | `scripts/deploy-pages.ps1` | Copia `app/admin/` → `deploy_zip/admin/` |

## Endpoints conectados (aba Hoje)

- `POST action=admin_listar` — lista usuários
- `POST action=uso` (`visao: overview` + `retencao`) — telemetria
- `GET /` — health Worker
- `GET ?action=heartbeats` — JWT admin
- `POST action=relatorio_dry_run` — preview e-mail semanal

## HEART — fórmulas v1

| Letra | Métrica | Cálculo |
|---|---|---|
| H | Happiness | ativos 7d / aprovados (+ bônus se retenção >50%) |
| E | Engagement | média(logins + consultas) 30d, cap 100 |
| A | Adoption | aprovados / total cadastros |
| R | Retention | com eventos 30d / aprovados |
| T | Task success | consultas / aberturas (ou 75 se só consultas) |

## UX (Linear/Vercel)

- Dark ops, `tabular-nums`, grid denso sem card-grid clichê
- Tabela saúde por usuário com alerta inativos >30d
- Heartbeats + dry-run inline

## Fase 2 — concluída (v201.67)

| Módulo | Arquivo | Função |
|---|---|---|
| Shared | `vr-admin-shared.js` | `postAdmin`, skeleton, design tokens |
| Engajamento | `vr-admin-engajamento.js` | Wrapper `usoCarregar` + CSS polish + auto-refresh 5min |
| Métricas | `vr-admin-metricas.js` | Wrapper `adminCarregarMetricas` + skeleton |

## Fases pendentes

### Fase 2b — Extração completa (P1)
- Mover corpo de `usoCarregar`/`m()` do monólito para módulo (risco alto)
- Sparklines HEART 7d (requer endpoint histórico ou cache local)

### Fase 3 — concluída (v201.68)

- Reengajamento 1-click: `newsletter_envio_direcionado` por usuário ou lote (max 25)
- Sparklines HEART: histórico local `vr_heart_history_v1` (14 snapshots)
- Polish overlay: `vr-admin-fase3.js` (blur, tabs, motion reduzida)

### Fase 3b — roadmap (P2)
- Gamificação leve (streak login)
- Sparklines server-side (telemetria histórica)
- Benchmark Awwwards completo no overlay

## Validação pós-deploy

```powershell
curl.exe -s https://vixradar.com/version.json
curl.exe -s https://vixradar.com/admin/vr-admin-modules.js | Select-String "VRAdmin"
# Admin: Ctrl+Shift+A → senha → aba Hoje carrega KPIs
```

## Next-steps semanal (2026-06-18)

```
VIX RADAR — PRÓXIMOS PASSOS (2026-06-18)

PRIORIDADE P0 (crítico/bloqueante):
→ Nenhum — Worker ok, frontend v201.66 deployado, auth fail-closed OK

PRIORIDADE P1 (alto impacto, baixo risco):
→ Deploy Fase 2 admin — extrair Engajamento/Métricas para módulos + skeleton — desbloqueia manutenção do monólito — ~4h
→ Versionar bundle Worker v4.9.139 no git — clone limpo quebra deploy — ~30min
→ Investigar watchdog stale_count:1 — heartbeats com agente parado — ~1h

PRIORIDADE P2 (melhoria/roadmap):
→ Fase 3 HEART — reengajamento 1-click para 9 inativos >30d — produto — ~1 dia
→ Sparklines HEART 7d — requer série histórica telemetria — ~1 dia
→ Polish Awwwards overlay admin — /awwwards-vix-radar — ~4h

QUICK WINS (< 1h, sem risco):
• Commit git: index.html v201.66 + admin/ + deploy-pages.ps1
• Validar aba Hoje em produção (Ctrl+Shift+A → Hoje → KPIs carregam)
```