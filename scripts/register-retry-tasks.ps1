# register-retry-tasks.ps1
# Registra as duas tasks de retry das rotinas VIX no Windows Task Scheduler:
#   Szuchmacher-RetryVixMatinal  Seg-Sex 13:30 BRT
#   Szuchmacher-RetryVixNoturno  Diario  21:30 BRT
# Ambas chamam scripts/retry-vixradar.ps1, que relanca a rotina do dia se o log
# nao tem linha FIM valida.
#
# POR QUE ESTE SCRIPT EXISTE (RETRYCFG1, 2026-08-19).
# As duas tasks nasceram em 17/08 criadas a mao, sem registrador. Foram as unicas
# do projeto criadas fora do padrao, e por isso as unicas que nasceram sem as tres
# configuracoes que todas as outras nove tem:
#
#   1. StartWhenAvailable      estava False. Disparo perdido com a maquina
#      desligada era descartado em silencio. Aconteceu em 18/08 16h23: a maquina
#      ficou fora das 03h42 as 16h14, o gatilho das 13h30 morreu e a task marcou
#      LastTaskResult 2147946720 (0x800710E0, ERROR_REQUEST_REFUSED). Este exato
#      codigo e a remediacao por StartWhenAvailable ja estavam documentados em
#      01_PROJETOS/Jarvis/AI_OPERATING_SYSTEM/06_RISCOS_E_DIVIDAS_TECNICAS.md, e
#      o mesmo fix ja tinha sido aplicado em 09/08 no Szuchmacher-MacroCron e no
#      Szuchmacher-AgendaAgent. So nao alcancou estas duas porque elas ainda nao
#      existiam.
#
#   2. DisallowStartIfOnBatteries e StopIfGoingOnBatteries estavam True. Em
#      bateria a task recusa iniciar, e se a energia cai no meio ela e morta.
#      E a outra metade da mesma remediacao documentada.
#
#   3. ExecutionTimeLimit estava PT72H, setenta e duas horas. Toda irma no
#      projeto usa minutos ou poucas horas. Combinado com MultipleInstances
#      IgnoreNew, uma instancia travada bloquearia os tres dias seguintes de
#      retry sem ninguem ver. Aqui vai 4 horas, mesmo teto que o
#      register-all-routines-scheduler.ps1 usa para rotina, e folgado sobre o
#      lock de 3h que a SKILL da rotina segura.
#
# Rodar este script e a unica forma suportada de recriar as duas tasks. Criar a
# mao de novo reintroduz os tres defeitos acima.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-retry-tasks.ps1"
# Requer elevacao (Register-ScheduledTask).

$ErrorActionPreference = 'Stop'

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\retry-vixradar.ps1'

if (-not (Test-Path $ScriptPath)) {
    throw "Script alvo nao encontrado: $ScriptPath"
}

# Configuracao unica para as duas. AllowStartIfOnBatteries e
# DontStopIfGoingOnBatteries sao os inversos das flags que vinham True.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4)

$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited

$tasks = @(
    @{
        Nome      = 'Szuchmacher-RetryVixMatinal'
        RoutineId = 'vixradar-matinal'
        Trigger   = (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At '13:30')
        Descricao = 'VIX Radar - retry da rotina matinal se o log do dia nao tem FIM valido (Seg-Sex 13:30 BRT)'
    },
    @{
        Nome      = 'Szuchmacher-RetryVixNoturno'
        RoutineId = 'vixradar-noturno'
        Trigger   = (New-ScheduledTaskTrigger -Daily -At '21:30')
        Descricao = 'VIX Radar - retry da rotina noturna se o log do dia nao tem FIM valido (diario 21:30 BRT)'
    }
)

foreach ($t in $tasks) {
    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '" -RoutineId ' + $t.RoutineId
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg

    $reg = Register-ScheduledTask -TaskName $t.Nome -TaskPath '\' `
        -Action $action -Trigger $t.Trigger `
        -Principal $principal -Settings $settings `
        -Description $t.Descricao `
        -Force

    Write-Output ("Task registrada: " + $reg.TaskName)
}

Write-Output ''
Write-Output '=== VERIFICACAO ==='
$falhas = 0
foreach ($t in $tasks) {
    $v = Get-ScheduledTask -TaskName $t.Nome
    $s = $v.Settings
    $okSWA = ($s.StartWhenAvailable -eq $true)
    $okBat = ($s.DisallowStartIfOnBatteries -eq $false) -and ($s.StopIfGoingOnBatteries -eq $false)
    $okLim = ($s.ExecutionTimeLimit -eq 'PT4H')
    if (-not ($okSWA -and $okBat -and $okLim)) { $falhas++ }
    Write-Output ("{0}" -f $t.Nome)
    Write-Output ("  StartWhenAvailable         = {0}  (esperado True)" -f $s.StartWhenAvailable)
    Write-Output ("  DisallowStartIfOnBatteries = {0}  (esperado False)" -f $s.DisallowStartIfOnBatteries)
    Write-Output ("  StopIfGoingOnBatteries     = {0}  (esperado False)" -f $s.StopIfGoingOnBatteries)
    Write-Output ("  ExecutionTimeLimit         = {0}  (esperado PT4H)" -f $s.ExecutionTimeLimit)
    Write-Output ("  State                      = {0}" -f $v.State)
    Write-Output ("  NextRunTime                = {0}" -f (Get-ScheduledTaskInfo -TaskName $t.Nome).NextRunTime)
}

if ($falhas -gt 0) {
    Write-Output ''
    Write-Output ("FALHA: {0} task(s) nao ficaram com a configuracao esperada." -f $falhas)
    exit 1
}

Write-Output ''
Write-Output 'OK: as duas tasks estao com StartWhenAvailable, tolerancia a bateria e teto de 4h.'
exit 0
