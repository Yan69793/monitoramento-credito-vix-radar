# register-vixradar-tasks.ps1 — registra VIXRadar-Matinal e VIXRadar-Noturno no Task Scheduler
# DEPRECATED 2026-07-23 (REGDRIFT1): register-all-routines-scheduler.ps1 é o script canônico.
#   Motivo: RestartCount, LogonType Interactive, WorkingDirectory, battery flags desde o início,
#   e registra TODAS as 6 rotinas em vez de só 2. Este script foi corrigido pontualmente em
#   20/07 (battery + StartWhenAvailable) mas não ganhou as features de resiliência do outro.
#   Manter como referência de configuração mínima; não usar para registro de tasks novas.
# Execute como Administrador uma vez.

# REGDRIFT1-FIX (auditoria 2026-08-15): guarda dura. Rodar este script re-habilitaria
# VIXRadar-Matinal/Noturno, que hoje rodam por sessao agendada do Claude Desktop com a
# task nativa mantida Disabled como guarda anti-duplicata. O registrador canonico
# (register-all-routines-scheduler.ps1) reproduz o estado Disabled e cobre as 6+ rotinas.
throw 'REGDRIFT1: registrador legado desativado. Use pwsh scripts/register-all-routines-scheduler.ps1'
#
# FIX 2026-07-20 (auditoria geral): faltavam -AllowStartIfOnBatteries/-DontStopIfGoingOnBatteries,
# unicas entre TODOS os scripts register-*-task.ps1 do projeto sem essas flags (comparado com
# register-all-routines-scheduler.ps1, register-export-historico-task.ps1,
# register-reconciliacao-cvm-task.ps1, register-verificacao-async-task.ps1,
# register-ranking-mensal-task.ps1 — todos com AllowStartIfOnBatteries+DontStopIfGoingOnBatteries
# ou o equivalente XML). Confirmado ao vivo (Export-ScheduledTask): VIXRadar-Matinal e
# VIXRadar-Noturno, as DUAS rotinas mais criticas do sistema (100% da ingestao diaria dos 103
# emissores), estavam com DisallowStartIfOnBatteries=true/StopIfGoingOnBatteries=true — se a
# maquina estivesse rodando na bateria no horario do trigger (10h/18h BRT), a rotina nao
# iniciava (ou parava no meio) sem nenhum log, sem alerta. Nao aplicado ainda ao Task Scheduler
# vivo (rodar este script como Administrador reaplica o registro com a config corrigida) —
# mudanca so no script-fonte, para o operador decidir quando reexecutar.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent $PSScriptRoot
$PWSHCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$PWSH = if ($PWSHCmd) { $PWSHCmd.Source } else { $null }
if (-not $PWSH) { $PWSH = 'pwsh' }

$tasks = @(
    @{
        Name       = 'VIXRadar-Matinal'
        Script     = Join-Path $ROOT 'scripts\run_vixradar_matinal_claude.ps1'
        Hour       = 10
        Minute     = 0
        DaysOfWeek = 'Monday','Tuesday','Wednesday','Thursday','Friday'
        TimeLimit  = 240
    },
    @{
        Name       = 'VIXRadar-Noturno'
        Script     = Join-Path $ROOT 'scripts\run_vixradar_noturno_claude.ps1'
        Hour       = 18
        Minute     = 0
        DaysOfWeek = 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
        TimeLimit  = 240
    }
)

foreach ($t in $tasks) {
    $action   = New-ScheduledTaskAction -Execute $PWSH `
        -Argument "-NonInteractive -WindowStyle Hidden -File `"$($t.Script)`""
    $trigger  = New-ScheduledTaskTrigger -Weekly `
        -DaysOfWeek $t.DaysOfWeek `
        -At "$($t.Hour):$($t.Minute.ToString('D2'))"
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $t.TimeLimit) `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    if (Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
        Write-Host "REMOVIDA task existente: $($t.Name)"
    }

    Register-ScheduledTask `
        -TaskName    $t.Name `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -RunLevel    Highest `
        -Description "VIX Radar — gerado automaticamente" | Out-Null

    Write-Host "REGISTRADA: $($t.Name) @ $($t.Hour):$($t.Minute.ToString('D2'))"
}

Write-Host ""
Write-Host "Verificar com:"
Write-Host "  Get-ScheduledTask | Where-Object TaskName -like 'VIXRadar-*' | Select TaskName, State, NextRunTime"
