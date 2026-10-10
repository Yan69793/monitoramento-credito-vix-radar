# Compatibilidade legada. O entrypoint canonico e run_vixradar_matinal.ps1.
param([switch]$Force,[switch]$DryRun,[int]$MaxEmissores=0,[switch]$SimularTokenVencido,[switch]$ForceClaude)
& (Join-Path $PSScriptRoot 'run_vixradar_matinal.ps1') -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido -ForceClaude:$ForceClaude
exit $LASTEXITCODE
