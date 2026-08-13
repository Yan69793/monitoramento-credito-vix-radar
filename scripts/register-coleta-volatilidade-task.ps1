# register-coleta-volatilidade-task.ps1
# Cria a task VIXRadar-Coleta-Volatilidade no Windows Task Scheduler.
# Roda DIARIAMENTE as 17:00 (hora local BRT), apos fechamento do pregao, antes da noturna 18:00.
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Coleta-Volatilidade' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-coleta-volatilidade-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_coleta_volatilidade.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At '17:00'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$task = Register-ScheduledTask -TaskName 'VIXRadar-Coleta-Volatilidade' -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - coleta diaria de cotacoes Yahoo Finance + upload ao KV (scores de volatilidade para o dashboard)' `
    -Force

Write-Output "Task registrada: $($task.TaskName)"
$info = Get-ScheduledTaskInfo -TaskName 'VIXRadar-Coleta-Volatilidade'
Write-Output "Proxima execucao: $($info.NextRunTime)"
