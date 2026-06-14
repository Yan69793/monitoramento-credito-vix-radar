---
title: Runbook — Deploy Cloudflare Pages
date: 2026-06-11
tags:
  - vixradar
  - deploy
  - runbook
status: ativo
---

# Runbook — Deploy do Frontend (Cloudflare Pages)

Procedimento gravado para repetir o deploy do `vixradar.com` com um comando, sem colar token a cada vez.

## Deploy normal (caso comum)

```powershell
pwsh ./scripts/deploy-pages.ps1
```

O script (`scripts/deploy-pages.ps1`) faz tudo:
1. Lê `CACHE_VERSION` de `app/index.html`.
2. Sincroniza `app/index.html` → `app/deploy_zip/` (a raiz vence) e regenera `version.json` (deploy_zip + app).
3. Confere o bundle (4 arquivos: `index.html`, `_headers`, `_routes.json`, `version.json`).
4. Roda `wrangler pages deploy ./app/deploy_zip --project-name=radar-credito --branch=main`.
5. Valida produção: `version.json` apex == `CACHE_VERSION` e o HTML servido bate.

Saída esperada no fim: `DEPLOY OK — producao em vXXX.YY`.

> [!tip] Antes de deployar
> Garanta que o `CACHE_VERSION` em `app/index.html` foi incrementado se houve mudança de conteúdo — senão o detector de auto-update do cliente não dispara.

## Credencial (configurar uma vez, e a cada rotação)

O script lê `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID` de **variáveis de ambiente do Windows (User scope)**. O token **nunca** vai para arquivo do repo (regra inviolável).

Configurar/rotacionar:
```powershell
# Interativo (token oculto, não fica no histórico):
pwsh ./scripts/setup-deploy-credential.ps1
# Depois ABRA UM NOVO terminal para as variáveis ficarem visíveis.
```

- Project name: `radar-credito` · Branch: `main` · Account ID: `7ac79fb1030e4e81115ef33c21a9b070`.
- Escopos mínimos do token: **Pages Edit**, **Account Settings Read**, **User Details Read**.
- Rotacionar em: https://dash.cloudflare.com/profile/api-tokens

> [!warning] Segurança do token
> Nunca cole o token em chat nem em arquivo versionado. Se isso acontecer, rotacione imediatamente e rode `setup-deploy-credential.ps1` de novo. O token configurado em 2026-06-11 foi exposto em chat — pendente de rotação.

## Validação manual pós-deploy (se quiser conferir à mão)

```powershell
curl -s https://vixradar.com | Select-String 'CACHE_VERSION="v'
curl -s https://vixradar.com/version.json
curl -sI https://vixradar.com/version.json | Select-String -i cache-control   # no-cache, no-store, must-revalidate
```

## Notas

- **Worker ≠ Pages.** Este runbook cobre só o frontend (Pages). O Worker (`radar-credito-api`) é deployado à parte via `wrangler deploy` em `api/`.
- O `deploy_zip` é artefato gerado — se a raiz e o deploy_zip divergirem, a raiz vence (o script força isso).
- Histórico: deploy inaugural do fluxo em 2026-06-11 (v201.46, features P12+P13). Ver [[10 - Oportunidades de Melhoria (2026-06-11)]] e [[03 - Estado de Produção]].
