# run_vixradar_noturno_claude.ps1 - wrapper da varredura NOTURNA (cauda LIGHT, seg-sex 18h05).
#
# MOTOR1 (2026-09-02): o corpo antigo (1027 linhas, fila Haiku + fila Sonnet + reserva da
# aprofundada + shadow DeepSeek) foi substituido pelo motor unico run_vixradar_varredura.ps1,
# perfil -Rotina noturno. Este arquivo existe porque o nome esta amarrado ao Task Scheduler
# (VIXRadar-Noturno), aos vigias (retry-vixradar.ps1, monitor-tasks.ps1) e aos logs
# (vixradar-noturno_<data>.log). O conteudo antigo segue no historico do git.
# -ShadowDeepSeek foi descontinuado (piloto de 24/08); aceito e ignorado com aviso.
param(
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido,
    [switch]$ShadowDeepSeek
)
$ErrorActionPreference = 'Continue'
if ($ShadowDeepSeek) { Write-Host 'AVISO: -ShadowDeepSeek descontinuado no MOTOR1, ignorado.' }
$engine = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
if (-not (Test-Path $engine)) { Write-Host ('ERRO: motor ausente ' + $engine); exit 1 }
& $engine -Rotina noturno -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido
exit $LASTEXITCODE
