# run_vixradar_matinal.ps1 - entrypoint PowerShell provider-agnostic da rotina Matinal.
param(
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido,
    [switch]$ForceClaude
)
$ErrorActionPreference = 'Continue'
$engine = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
if (-not (Test-Path $engine)) { Write-Host ('ERRO: motor ausente ' + $engine); exit 1 }
& $engine -Rotina matinal -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido -ForceClaude:$ForceClaude
exit $LASTEXITCODE
