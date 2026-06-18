# push-health.ps1 — publica health_vix.sh na Sprite VM site
# Uso: .\scripts\sprite\push-health.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$LOCAL = Join-Path $PSScriptRoot 'health_vix.sh'
$SPRITE = 'C:\Users\User\AppData\Local\Programs\Sprite\sprite.exe'

if (-not (Test-Path $LOCAL)) { Write-Error "Arquivo nao encontrado: $LOCAL" }
if (-not (Test-Path $SPRITE)) {
    $cmd = Get-Command sprite -ErrorAction SilentlyContinue
    if ($cmd) { $SPRITE = $cmd.Source } else { Write-Error "sprite.exe nao encontrado" }
}

Write-Host "Push health_vix.sh -> sprite site ..." -ForegroundColor Cyan
& $SPRITE file push -s site $LOCAL health_vix.sh
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Teste remoto:" -ForegroundColor DarkGray
& $SPRITE exec -s site -- sh health_vix.sh
exit $LASTEXITCODE