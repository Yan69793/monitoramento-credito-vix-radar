# register-reconciliacao-cvm-task.ps1
# Cria a task VIXRadar-Reconciliacao-CVM no Windows Task Scheduler.
# Roda SEMANALMENTE as segundas-feiras 12:00 (hora local BRT). Era 08:00, herdado da epoca
# em que se supunha que so a serie A-1 existia (escrita no domingo ~07h BRT, medido uma vez
# em 12/07/2026, nota Obsidian 60). Medido em 21/09/2026: o zip do ANO CORRENTE e republicado
# pela CVM na segunda de manha e naquele dia so foi escrito as 08:53 BRT (Last-Modified
# 11:53:41Z) - a execucao das 08:00 pegou 404 e morreu com ERRO FATAL (exit 1). 12:00 fica
# depois dessa janela e tambem fora da janela matinal (10h00) e do cron de verificacao (10h20).
# O retry curto no download (RECONCILE-CVM404B, no proprio reconciliador) cobre atraso de
# minutos na republicacao.
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Reconciliacao-CVM' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-reconciliacao-cvm-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\predictive\reconciliar_ipe_cvm.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '12:00'
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
