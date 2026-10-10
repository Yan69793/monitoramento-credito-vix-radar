# run_vixradar_noturno.ps1 - entrypoint PowerShell provider-agnostic da rotina Noturna.
param(
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido,
    [switch]$ShadowDeepSeek,
    [switch]$ForceClaude
)
$ErrorActionPreference = 'Continue'
if ($ShadowDeepSeek) { Write-Host 'AVISO: -ShadowDeepSeek descontinuado no MOTOR1, ignorado.' }
$engine = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
if (-not (Test-Path $engine)) { Write-Host ('ERRO: motor ausente ' + $engine); exit 1 }
& $engine -Rotina noturno -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido -ForceClaude:$ForceClaude
exit $LASTEXITCODE
