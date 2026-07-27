# register-monitor-tasks.ps1
# Cria a task Monitor-Tasks no Windows Task Scheduler.
# Roda DIARIAMENTE as 07:00 (hora local BRT) - varre as tasks do workspace
# (prefixos Szuchmacher-, VIXRadar-, Monitor-, PME-, YanOS_) e reporta
# LastTaskResult nao-benigno em logs\monitor-tasks\. E o vigia de falha
# silenciosa das demais rotinas (ver MONITORCEGO1, Obsidian PENDENCIAS.md).
# Sem este registrador, "recriar a task Monitor-Tasks" nao era um comando
# unico - o script monitor-tasks.ps1 sempre existiu, mas nao tinha task.
#
# -SendEmail nao e usado aqui: exige scripts\monitor_send_email.py, que
# nao existe no repo nesta data. Adicionar '-SendEmail' ao ArgList abaixo
# se/quando esse script for criado.
#
# Reversao: Unregister-ScheduledTask -TaskName 'Monitor-Tasks' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-monitor-tasks.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\monitor-tasks.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Quiet"
$trigger = New-ScheduledTaskTrigger -Daily -At '07:00'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$task = Register-ScheduledTask -TaskName 'Monitor-Tasks' -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - vigia diario de falha silenciosa no Task Scheduler: varre tasks Szuchmacher-/VIXRadar-/Monitor-/PME-/YanOS_ e reporta LastTaskResult nao-benigno (MONITORCEGO1).' `
    -Force

Write-Output "Task registrada: $($task.TaskName)"
$info = Get-ScheduledTaskInfo -TaskName 'Monitor-Tasks'
Write-Output "Proxima execucao: $($info.NextRunTime)"
