# register-verificacao-async-task.ps1
# DEPRECATED 2026-08-15 (REGDRIFT1-FIX): a task VIXRadar-Verificacao-Async roda por
# sessao agendada do Claude Desktop (Seg-Sex 10:20 BRT) e a task nativa fica DISABLED
# como guarda anti-duplicata. O registrador canonico (register-all-routines-scheduler.ps1)
# reproduz esse estado. Rodar este script reabilitaria a task com DOIS triggers diarios
# (10:20 e 18:20), abrindo execucao dupla do dreno de fila contra a sessao Desktop.
# Guarda dura abaixo.
throw 'REGDRIFT1: registrador dedicado desativado. Use pwsh scripts/register-all-routines-scheduler.ps1'
#
# Conteudo abaixo preservado como referencia (inalcancavel).
#
# Cria a task VIXRadar-Verificacao-Async no Windows Task Scheduler.
# Roda 10:20 e 18:20 BRT diariamente — mesma janela do cron original do Claude Code.
# Exige admin (Register-ScheduledTask).
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-verificacao-async-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_vixradar_verificacao_async.ps1'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$trigger1 = New-ScheduledTaskTrigger -Daily -At '10:20'
$trigger2 = New-ScheduledTaskTrigger -Daily -At '18:20'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

$task = Register-ScheduledTask -TaskName 'VIXRadar-Verificacao-Async' -TaskPath '\' `
    -Action $action -Trigger $trigger1, $trigger2 `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar — drena fila de verificacao assincrona (pos-matinal e pos-noturno)' `
    -Force

Write-Output "Task registrada: $($task.Name)"
Write-Output "Triggers: $($task.Triggers.Count)"
Write-Output "Status: $($task.State)"
