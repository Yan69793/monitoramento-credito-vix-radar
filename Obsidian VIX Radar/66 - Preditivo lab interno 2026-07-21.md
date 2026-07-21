---
data: 2026-07-21
tipo: decisao
tags: [vix-radar, preditivo, merton, produto]
status: ativo
---

# Preditivo lab interno (2026-07-21)

## Decisao

Operador: tirar o sistema preditivo do produto; manter rodando por baixo so para gerar dados (research, export historico, backtest futuro).

## Estado deployado

| Camada | Versao | Commit |
|---|---|---|
| Worker | v4.9.170 | (pos polish unificacao gate) |
| Frontend | v201.83 | dead code + CSS removidos, sem boot fetch |

## Politica de acesso (unificada v4.9.170)

`_exigeLabPreditivoAdmin` cobre:
- GET `?op=predictive_v1`
- POST `action=admin_executar_predictive`

Aceita **JWT admin** OU **ADMIN_PASSWORD** (`body.admin_senha` | query | `x-admin-password` | `X-Admin-Auth`).

## Smoke / testes

```powershell
node scripts/test-lab-preditivo-policy.mjs
pwsh ./scripts/smoke-preditivo-lab.ps1
# com admin: $env:ADMIN_PASSWORD='...' ; pwsh ./scripts/smoke-preditivo-lab.ps1
```

## O que continua

- Pipeline nos crons matinal/noturno
- Merton + rule + logistic no score de lab
- `predictive_v1:latest` no KV + export historico
- EWS / eventos / rotinas de analise

## O que saiu do produto

- UI painel (bloco, CSS, hint, fetch no boot)
- Leitura HTTP por usuario comum

## Rollback

`main = "v4.9.169.js"` + frontend v201.82 (ou 168/81 se quiser pre-lab).
