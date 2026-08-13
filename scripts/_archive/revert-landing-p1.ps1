# revert-landing-p1.ps1 — desativa P1 (demo JSON + animação mobile)
$ErrorActionPreference = 'Stop'
$index = Join-Path (Split-Path -Parent $PSScriptRoot) 'app\index.html'
$html = Get-Content $index -Raw -Encoding UTF8
$new = $html -replace 'window\.VIX_LANDING_P1\s*=\s*true', 'window.VIX_LANDING_P1 = false'
if ($html -eq $new) {
    if ($html -match 'VIX_LANDING_P1\s*=\s*false') { Write-Host 'P1 ja desativado.' -ForegroundColor Yellow }
    else { throw 'VIX_LANDING_P1 nao encontrado' }
    return
}
Set-Content $index -Value $new -Encoding UTF8 -NoNewline
Write-Host 'VIX_LANDING_P1 = false — preview: ?landing=extended&p1=0' -ForegroundColor Green
Write-Host 'Deploy somente apos validar preview local.' -ForegroundColor Cyan