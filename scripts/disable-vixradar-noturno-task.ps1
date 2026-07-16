# disable-vixradar-noturno-task.ps1
# Desabilita scheduled-task VIXRadar-Noturno para evitar duplicação com Task nativa
# Execute como Administrador

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = "VIXRadar-Noturno"

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "Task '$taskName' não encontrada."
        exit 0
    }

    if ($task.State -eq "Disabled") {
        Write-Host "Task '$taskName' já está desabilitada."
        exit 0
    }

    Disable-ScheduledTask -TaskName $taskName
    Write-Host "Task '$taskName' desabilitada com sucesso."
    exit 0
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
    exit 1
}
