# register-monitor-tasks.ps1
# Cria as tasks Monitor-Tasks (escopo VIX, 07:00) e Monitor-Tasks-Site (escopo Site, 07:05)
# no Windows Task Scheduler. Cada uma varre so as tasks do proprio projeto e reporta
# LastTaskResult nao-benigno em logs\monitor-tasks\ (MONITORCEGO1, MONITOR-PROJETOMISTO1).
#
# GUARD-REG1 (2026-09-24): as duas tasks nascem apontadas para scripts\preflight-and-run.ps1,
# com o mesmo contrato de guarda de register-reconciliacao-cvm-task.ps1 e a montagem na lib
# scripts/lib/vixradar-task-guard.ps1. Nao dependem mais de apply-preflight-tasks.ps1 -Apply.
#
# MONITORCEGO2 (2026-08-02): -SendEmail RELIGADO. O envio passa pelo action=email_enviar
# do Worker (ver monitor-tasks.ps1).
# MONITOR-PROJETOMISTO1 (2026-09-02): o e-mail "VIX Radar - N task(s) com falha" carregava
# tasks de outros projetos (01/09: AgendaAgent e FechamentoDiario). Agora sao dois vigias,
# um por escopo, e o e-mail so sai com erro novo ou escalado (dedup em estado.json).
#
# Reversao: Unregister-ScheduledTask -TaskName 'Monitor-Tasks' -Confirm:$false
#           Unregister-ScheduledTask -TaskName 'Monitor-Tasks-Site' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-monitor-tasks.ps1"
#      powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-monitor-tasks.ps1" -DryRun
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\monitor-tasks.ps1'
$Guarda      = Join-Path $ProjectRoot 'scripts\preflight-and-run.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }
. (Join-Path $ProjectRoot 'scripts\lib\vixradar-task-guard.ps1')

# LogonType Interactive e obrigatorio para o -SendEmail funcionar: a senha admin
# vem do DPAPI em escopo CurrentUser (api\Get-VixAdminCredential.ps1) e so
# decripta com o perfil do usuario carregado. Trocar para S4U ou Password quebra
# o alerta em silencio, que e exatamente o que estamos consertando.
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# GUARD-REG1: o ExtraArgs de Monitor-Tasks nao repete -Escopo VIX de proposito. O default de
# monitor-tasks.ps1 ja e VIX e o argumento tem de bater por igualdade exata com o que o
# apply-preflight-tasks.ps1 espera (Args=@('-Quiet','-SendEmail')), senao o apply veria drift e
# re-apontaria a task. Comportamento identico: o SufixoEscopo so muda fora de VIX.
$defs = @(
    @{ Name = 'Monitor-Tasks';      At = '07:00'; Escopo = 'VIX';  LogPattern = 'logs\monitor-tasks\monitor_{yyyyMMdd}.log';       ExtraArgs = @('-Quiet', '-SendEmail');                    Desc = 'VIX Radar - vigia diario de falha silenciosa no Task Scheduler, escopo VIX (VIXRadar-, Monitor-, Szuchmacher-RetryVix*), entrega por log das rotinas, ALERTA_AUTH e circuito de custo (MONITORCEGO1, MONITOR-PROJETOMISTO1).' },
    @{ Name = 'Monitor-Tasks-Site'; At = '07:05'; Escopo = 'Site'; LogPattern = 'logs\monitor-tasks\monitor_Site_{yyyyMMdd}.log'; ExtraArgs = @('-Quiet', '-SendEmail', '-Escopo', 'Site'); Desc = 'Vigia diario de falha silenciosa no Task Scheduler, escopo Site (Szuchmacher-, MorningCall-, RadarQuant-, PME-, YanOS_), sem as tasks do VIX Radar (MONITOR-PROJETOMISTO1).' }
)

$falhas = 0
foreach ($d in $defs) {
    # Sem o guarda na arvore o registrador RECUSA (fail-closed): nao existe registro sem guarda.
    Assert-VixGuardPath -Guarda $Guarda | Out-Null
    $argument = Get-VixGuardArgument -Guarda $Guarda -Target $ScriptPath -Name $d.Name -LogPattern $d.LogPattern -ExtraArgs $d.ExtraArgs
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
    $trigger = New-ScheduledTaskTrigger -Daily -At $d.At

    if ($DryRun) {
        Write-Output '--- DRYRUN: nada foi registrado ---'
        Write-Output ('task     : ' + $d.Name)
        Write-Output ('execute  : ' + $action.Execute)
        Write-Output ('argument : ' + $action.Arguments)
        Write-Output ('trigger  : ' + $trigger.CimClass.CimClassName + ' StartBoundary=' + $trigger.StartBoundary)
        Write-Output ('limit    : ' + $settings.ExecutionTimeLimit)
        Write-Output ('principal: ' + $principal.UserId + ' / ' + $principal.LogonType + ' / ' + $principal.RunLevel)
        $falhas += Test-VixGuardAction -Nome $d.Name -Argument $argument
        continue
    }

    $task = Register-ScheduledTask -TaskName $d.Name -TaskPath '\' `
        -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description $d.Desc -Force

    # Leitura de volta: registro que nao e conferido nao conta como registrado.
    $lida = Get-ScheduledTask -TaskName $d.Name
    $argLida = [string](@($lida.Actions)[0]).Arguments
    if ($argLida -ne $argument) {
        throw ('leitura de volta diferente do esperado. esperado: ' + $argument + ' | lido: ' + $argLida)
    }

    Write-Output "Task registrada e conferida no guarda: $($task.TaskName) (escopo $($d.Escopo), $($d.At))"
    $info = Get-ScheduledTaskInfo -TaskName $d.Name
    Write-Output "  Proxima execucao: $($info.NextRunTime)"
}

if ($DryRun) {
    if ($falhas -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhas + ' falha(s)'); exit 1 }
    Write-Output 'DRYRUN OK'
    exit 0
}
