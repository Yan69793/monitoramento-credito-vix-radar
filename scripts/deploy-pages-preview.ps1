#Requires -Version 7.0
<#
.SYNOPSIS
  Publica o bundle do Pages num ambiente de PREVIEW do Cloudflare (branch diferente de main),
  sem tocar a producao. O deploy-pages.ps1 fixa --branch=main, entao nao serve para preview.

.DESCRIPTION
  VXPREVIEW1 (2026-10-14). Por padrao NAO publica: sem -Publicar so valida e imprime o comando.
  Roda os mesmos gates do deploy oficial em modo -DryRun (sincroniza app/ -> app/deploy_zip,
  confere allowlist, ?v=, sintaxe JS e rotas admin) e so entao envia o MESMO deploy_zip para
  a branch de preview. Nao commita, nao faz push, nao altera version.json no repo.

  Preview do Pages usa o mesmo projeto e o mesmo Worker de producao (api.vixradar.com), entao
  o teste autenticado no preview le dados reais: use conta propria e nao grave nada.
  Producao so e alterada por scripts/deploy-pages.ps1 com autorizacao explicita.

.EXAMPLE
  pwsh ./scripts/deploy-pages-preview.ps1                      # valida e mostra o comando
  pwsh ./scripts/deploy-pages-preview.ps1 -Publicar            # envia para a branch ui-v2-preview
#>
[CmdletBinding()]
param(
  [string]$Branch = 'ui-v2-preview',
  [string]$ProjectName = 'radar-credito',
  [switch]$Publicar
)
$ErrorActionPreference = 'Stop'
if ($Branch -in @('main', 'master')) { throw "Branch '$Branch' e producao. Use scripts/deploy-pages.ps1 para isso." }
$root = Split-Path -Parent $PSScriptRoot
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'deploy-pages.ps1') -DryRun
if ($LASTEXITCODE -ne 0) { throw "Gates do deploy-pages.ps1 -DryRun reprovaram (exit $LASTEXITCODE). Nada foi enviado." }
$zip = Join-Path $root 'app/deploy_zip'
$cmd = "npx wrangler pages deploy `"$zip`" --project-name=$ProjectName --branch=$Branch --commit-dirty=true"
if (-not $Publicar) {
  Write-Host "`nGates OK. Para publicar o PREVIEW (nao altera producao):`n  $cmd" -ForegroundColor Cyan
  return
}
Write-Host "Publicando PREVIEW na branch '$Branch'..." -ForegroundColor Yellow
Invoke-Expression $cmd
if ($LASTEXITCODE -ne 0) { throw "wrangler pages deploy falhou (exit $LASTEXITCODE)" }
