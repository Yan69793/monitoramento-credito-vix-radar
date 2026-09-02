# run_vixradar_matinal_claude.ps1 - wrapper da varredura MATINAL (topo FULL, diaria 10h06).
#
# MOTOR1 (2026-09-02): o corpo antigo (864 linhas, top 15, Haiku em lotes de 6 + Sonnet para
# EWS>=38 em lotes de 4) foi substituido pelo motor unico run_vixradar_varredura.ps1, perfil
# -Rotina matinal (top 20, tudo FULL em Sonnet, lotes de 4). Este arquivo existe porque o nome
# esta amarrado ao Task Scheduler (VIXRadar-Matinal), aos vigias (retry-vixradar.ps1,
# monitor-tasks.ps1) e aos logs (vixradar-matinal_<data>.log). O conteudo antigo segue no
# historico do git.
param(
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido
)
$ErrorActionPreference = 'Continue'
$engine = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
if (-not (Test-Path $engine)) { Write-Host ('ERRO: motor ausente ' + $engine); exit 1 }
& $engine -Rotina matinal -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido
exit $LASTEXITCODE
