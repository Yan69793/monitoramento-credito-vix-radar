# register-reconciliacao-cvm-task.ps1
# Cria a task VIXRadar-Reconciliacao-CVM no Windows Task Scheduler.
# Roda SEMANALMENTE as segundas-feiras 08:00 (hora local BRT) - depois da publicacao do
# dataset IPE da CVM aos domingos (~07h BRT, medido uma vez em 12/07/2026, nota Obsidian 60)
# e fora da janela matinal (10h00) e do cron de verificacao (10h20).
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Reconciliacao-CVM' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-reconciliacao-cvm-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\predictive\reconciliar_ipe_cvm.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '08:00'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

$task = Register-ScheduledTask -TaskName 'VIXRadar-Reconciliacao-CVM' -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - reconciliador semanal: dataset oficial CVM IPE (RJ/RE/default/reestruturacao/inadimplencia) vs classificacao do Radar. Rede de seguranca deterministica contra miss de heuristica (nota Obsidian 60, RESEARCHDOWN1).' `
    -Force

Write-Output "Task registrada: $($task.TaskName)"
$info = Get-ScheduledTaskInfo -TaskName 'VIXRadar-Reconciliacao-CVM'
Write-Output "Proxima execucao: $($info.NextRunTime)"
