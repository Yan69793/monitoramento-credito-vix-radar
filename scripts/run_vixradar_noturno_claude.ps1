# Compatibilidade legada. O entrypoint canonico e run_vixradar_noturno.ps1.
param([switch]$Force,[switch]$DryRun,[int]$MaxEmissores=0,[switch]$SimularTokenVencido,[switch]$ShadowDeepSeek,[switch]$ForceClaude)
& (Join-Path $PSScriptRoot 'run_vixradar_noturno.ps1') -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido -ShadowDeepSeek:$ShadowDeepSeek -ForceClaude:$ForceClaude
exit $LASTEXITCODE
