# revert-landing.ps1 — desativa landing estendida VIX Radar
# Uso: pwsh ./scripts/revert-landing.ps1
# Preview: https://vixradar.com/?landing=classic

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$index = Join-Path $root 'app\index.html'

if (-not (Test-Path $index)) { throw "Nao encontrado: $index" }

$html = Get-Content $index -Raw -Encoding UTF8
$new = $html -replace 'window\.VIX_LANDING_EXTENDED\s*=\s*true', 'window.VIX_LANDING_EXTENDED = false'

if ($html -eq $new) {
    if ($html -match 'VIX_LANDING_EXTENDED\s*=\s*false') {
        Write-Host 'Landing ja esta em modo classic.' -ForegroundColor Yellow
    } else {
        throw 'VIX_LANDING_EXTENDED nao encontrado em app/index.html'
    }
    return
}

Set-Content -Path $index -Value $new -Encoding UTF8 -NoNewline
Write-Host 'VIX_LANDING_EXTENDED = false' -ForegroundColor Green
Write-Host 'Deploy: pwsh ./scripts/deploy-pages.ps1' -ForegroundColor Cyan