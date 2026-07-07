# Landing estendida VIX Radar — como reverter

## Modos

| Modo | Ativação |
|------|----------|
| **classic** (padrão) | `window.VIX_LANDING_EXTENDED = false` — splash animado |
| **extended** | `?landing=extended` ou botão "Veja como funciona" na splash |
| Cadastrado (JWT) | Entra direto no painel — ignora landing |
| **P1** (demo JSON + mobile) | `window.VIX_LANDING_P1 = true` |
| Preview local | `pwsh ./scripts/preview-landing.ps1` — **sem deploy** |
| Preview URL | `?landing=extended` · `?p1=0` desliga P1 |

## Fluxo

1. Visitante vê splash clássica → "Acessar sistema" abre login inline
2. "Ainda não conhece?" → landing estendida enxuta (`?landing=extended`)
3. Usuário com `radar_jwt` + `radar_user` → painel direto, sem splash

## Preview antes do deploy

```powershell
cd "E:\Diretorio\Claude\Monitoramento de Credito"
pwsh ./scripts/preview-landing.ps1
```

Abrir no navegador:
- http://localhost:8765/ — splash clássica (padrão)
- http://localhost:8765/?landing=extended — landing enxuta + P1
- http://localhost:8765/?landing=extended&p1=0 — landing sem demo JSON

## Reverter P1

```powershell
pwsh ./scripts/revert-landing-p1.ps1
```

## Reverter

```powershell
cd "E:\Diretorio\Claude\Monitoramento de Credito"
pwsh ./scripts/revert-landing.ps1
pwsh ./scripts/deploy-pages.ps1
```

## Deploy

```powershell
pwsh ./scripts/deploy-pages.ps1
```

## Arquivos

- `app/index.html` — seções P0 + CSS inline + switch
- `app/_arquivo/landing-classic-snapshot-2026-06-18.html` — backup
- `scripts/revert-landing.ps1` — toggle para classic

## Compliance

- Disclaimer CVM no rodapé da landing estendida
- Card demo marcado como "Exemplo ilustrativo"
- Planos sem promessa de retorno