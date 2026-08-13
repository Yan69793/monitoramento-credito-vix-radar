# preview-landing.ps1 — abre landing local SEM deploy
# Uso: pwsh ./scripts/preview-landing.ps1
# URLs:
#   http://localhost:8765/                           (splash clássica — padrão)
#   http://localhost:8765/?landing=extended          (landing enxuta + P1)
#   http://localhost:8765/?landing=extended&p1=0     (landing sem demo JSON)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app  = Join-Path $root 'app'
$port = 8765

Copy-Item -Force (Join-Path $app 'index.html') (Join-Path $app 'deploy_zip\index.html') -ErrorAction SilentlyContinue

Write-Host "`nPreview local VIX Radar (sem deploy)" -ForegroundColor Cyan
Write-Host "  Splash (padrao): http://localhost:$port/" -ForegroundColor Green
Write-Host "  Landing enxuta:  http://localhost:$port/?landing=extended" -ForegroundColor Green
Write-Host "  Sem demo JSON:   http://localhost:$port/?landing=extended&p1=0" -ForegroundColor Green
Write-Host "`nCtrl+C para encerrar.`n" -ForegroundColor DarkGray

Set-Location $app
python -m http.server $port