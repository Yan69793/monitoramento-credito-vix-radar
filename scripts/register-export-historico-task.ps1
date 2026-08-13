# register-export-historico-task.ps1
# Cria a task VIXRadar-Export-Historico no Windows Task Scheduler.
# Roda DIARIAMENTE as 20:45 (hora local BRT) - depois do cron noturno do Worker (18:30 BRT:
# sync_anbima + zscores + pipeline preditivo) e do noturno local (18h) + dreno (18:20),
# garantindo que o dump capture o estado do proprio dia.
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Export-Historico' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-export-historico-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_vixradar_export_historico.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At '20:45'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 25)

$task = Register-ScheduledTask -TaskName 'VIXRadar-Export-Historico' -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - exporta estado preditivo do KV para data/historico (fundacao de dados do motor preditivo v2)' `
    -Force

Write-Output "Task registrada: $($task.TaskName)"
$info = Get-ScheduledTaskInfo -TaskName 'VIXRadar-Export-Historico'
Write-Output "Proxima execucao: $($info.NextRunTime)"
