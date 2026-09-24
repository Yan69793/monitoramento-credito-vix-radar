# register-coleta-volatilidade-task.ps1
# Cria a task VIXRadar-Coleta-Volatilidade no Windows Task Scheduler, JA apontada para o
# guarda scripts\preflight-and-run.ps1 (GUARD-REG1, 2026-09-24). Mesmo contrato de guarda do
# register-reconciliacao-cvm-task.ps1, com a montagem centralizada na lib
# scripts/lib/vixradar-task-guard.ps1: a task nasce protegida e nao depende de
# apply-preflight-tasks.ps1 -Apply rodar depois.
# Roda DIARIAMENTE as 17:00 (hora local BRT), apos fechamento do pregao, antes da noturna 18:00.
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Coleta-Volatilidade' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-coleta-volatilidade-task.ps1"
#      powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-coleta-volatilidade-task.ps1" -DryRun
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_coleta_volatilidade.ps1'
$TaskName    = 'VIXRadar-Coleta-Volatilidade'
$Guarda      = Join-Path $ProjectRoot 'scripts\preflight-and-run.ps1'
$LogPattern  = 'logs\routines\coleta_volatilidade_{yyyyMMdd}.log'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }
. (Join-Path $ProjectRoot 'scripts\lib\vixradar-task-guard.ps1')
# Sem o guarda na arvore o registrador RECUSA (fail-closed): nao existe registro sem guarda.
Assert-VixGuardPath -Guarda $Guarda | Out-Null

# Formato identico ao Get-ArgumentoGuarda de scripts/apply-preflight-tasks.ps1: o apply compara
# por igualdade exata de string, entao este registrador nao deixa correcao pendente para depois.
$Argument = Get-VixGuardArgument -Guarda $Guarda -Target $ScriptPath -Name $TaskName -LogPattern $LogPattern

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Argument
$trigger = New-ScheduledTaskTrigger -Daily -At '17:00'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

if ($DryRun) {
    Write-Output '--- DRYRUN: nada foi registrado ---'
    Write-Output ('task     : ' + $TaskName)
    Write-Output ('execute  : ' + $action.Execute)
    Write-Output ('argument : ' + $action.Arguments)
    Write-Output ('trigger  : ' + $trigger.CimClass.CimClassName + ' StartBoundary=' + $trigger.StartBoundary)
    Write-Output ('limit    : ' + $settings.ExecutionTimeLimit)
    Write-Output ('principal: ' + $principal.UserId + ' / ' + $principal.LogonType + ' / ' + $principal.RunLevel)
    $falhas = Test-VixGuardAction -Nome $TaskName -Argument $Argument
    if ($falhas -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhas + ' falha(s)'); exit 1 }
    Write-Output 'DRYRUN OK'
    exit 0
}

$task = Register-ScheduledTask -TaskName $TaskName -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - coleta diaria de cotacoes Yahoo Finance + upload ao KV (scores de volatilidade para o dashboard)' `
    -Force

# Leitura de volta: registro que nao e conferido nao conta como registrado.
$lida = Get-ScheduledTask -TaskName $TaskName
$argLida = [string](@($lida.Actions)[0]).Arguments
if ($argLida -ne $Argument) {
    throw ('leitura de volta diferente do esperado. esperado: ' + $Argument + ' | lido: ' + $argLida)
}

Write-Output "Task registrada e conferida no guarda: $($task.TaskName)"
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Output "Proxima execucao: $($info.NextRunTime)"
