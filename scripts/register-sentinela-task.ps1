# register-sentinela-task.ps1 - registra VIXRadar-Sentinela no Windows Task Scheduler
#
# Status: vigente
# Data da Versao: 2026-08-25
# Origem do Registro: SENTINELA1, mesma sessao que criou run_vixradar_sentinela.ps1.
#   Idioma copiado de register-verificacao-async-task.ps1.
# Condicao de Obsolescencia: perde validade se a janela operacional da Sentinela
#   mudar, ou se a rotina for aposentada.
#
# Dois disparos por hora, aos :25 e aos :55, das 09h25 as 17h55, dias uteis.
# O segundo disparo NAO e redundancia: ele e a rede de seguranca da colisao. Se a
# tentativa das :25 encontrar uma rotina principal em execucao, ela aborta em 0
# token e a das :55 pega o caso 30 minutos depois, em vez de uma hora depois.
#
# Os horarios evitam de proposito os blocos das rotinas principais: varredura
# completa 10h00-10h40, verificacao 11h00, top 15 as 18h00, verificacao 18h45.
#
# Exige admin (Register-ScheduledTask).
#
# GUARD-REG1 (2026-09-24): a task nasce apontada para scripts\preflight-and-run.ps1, com o mesmo
# contrato de guarda de register-reconciliacao-cvm-task.ps1 e a montagem na lib
# scripts/lib/vixradar-task-guard.ps1. -DryRun prova a Action final sem registrar nada.
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_vixradar_sentinela.ps1'
$TaskName    = 'VIXRadar-Sentinela'
$Guarda      = Join-Path $ProjectRoot 'scripts\preflight-and-run.ps1'
$LogPattern  = 'logs\routines\vixradar-sentinela_{yyyyMMdd}.log'
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERRO: script nao encontrado em $ScriptPath" -ForegroundColor Red
    exit 1
}

. (Join-Path $ProjectRoot 'scripts\lib\vixradar-task-guard.ps1')
# Sem o guarda na arvore o registrador RECUSA (fail-closed): nao existe registro sem guarda.
try {
    Assert-VixGuardPath -Guarda $Guarda | Out-Null
} catch {
    Write-Host ('ERRO: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# Formato identico ao Get-ArgumentoGuarda de scripts/apply-preflight-tasks.ps1: o apply compara
# por igualdade exata de string, entao este registrador nao deixa correcao pendente para depois.
$Argument = Get-VixGuardArgument -Guarda $Guarda -Target $ScriptPath -Name $TaskName -LogPattern $LogPattern
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Argument

# Trigger semanal + repeticao: o cmdlet nao aceita -RepetitionInterval junto de
# -Weekly, entao a repeticao vem emprestada de um trigger -Once descartavel. E o
# idioma padrao para esse caso no PowerShell 5.1.
$diasUteis = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
$repeticao = (New-ScheduledTaskTrigger -Once -At '00:00' `
    -RepetitionInterval (New-TimeSpan -Hours 1) `
    -RepetitionDuration (New-TimeSpan -Hours 8)).Repetition

$trigger25 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $diasUteis -At '09:25'
$trigger25.Repetition = $repeticao
$trigger55 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $diasUteis -At '09:55'
$trigger55.Repetition = $repeticao

$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited

# MultipleInstances IgnoreNew e cinto; o mutex Global\vixradar-sentinela-v1 dentro
# do script e o suspensorio, porque cobre tambem execucao manual fora da task.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 40)

if ($DryRun) {
    Write-Output '--- DRYRUN: nada foi registrado ---'
    Write-Output ('task     : ' + $TaskName)
    Write-Output ('execute  : ' + $action.Execute)
    Write-Output ('argument : ' + $action.Arguments)
    Write-Output ('trigger  : 2x Weekly ' + $trigger25.StartBoundary + ' repete ' + $trigger25.Repetition.Interval + ' por ' + $trigger25.Repetition.Duration + ' dias=' + $trigger25.DaysOfWeek)
    Write-Output ('limit    : ' + $settings.ExecutionTimeLimit)
    Write-Output ('principal: ' + $principal.UserId + ' / ' + $principal.LogonType + ' / ' + $principal.RunLevel)
    $falhas = Test-VixGuardAction -Nome $TaskName -Argument $Argument
    if ($falhas -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhas + ' falha(s)'); exit 1 }
    Write-Output 'DRYRUN OK'
    exit 0
}

$task = Register-ScheduledTask -TaskName $TaskName -TaskPath '\' `
    -Action $action -Trigger @($trigger25, $trigger55) `
    -Principal $principal -Settings $settings `
    -Description 'Varredura pontual por gatilho (SENTINELA1). Consulta listar_plano_rotina modo=pontual e analisa so emissores com documento CVM nao entregue a analise, deferidos por teto ou inconclusivos. Teto 8 emissores / 120k tokens. Na maioria das execucoes sai em 0 token.' `
    -Force

# Leitura de volta: registro que nao e conferido nao conta como registrado.
if ($task) {
    $lida = Get-ScheduledTask -TaskName $TaskName
    $argLida = [string](@($lida.Actions)[0]).Arguments
    if ($argLida -ne $Argument) {
        Write-Host ('ERRO: leitura de volta diferente do esperado. esperado: ' + $Argument + ' | lido: ' + $argLida) -ForegroundColor Red
        exit 1
    }
}

if ($task) {
    Write-Host 'VIXRadar-Sentinela registrada e conferida no guarda.' -ForegroundColor Green
    Get-ScheduledTask -TaskName 'VIXRadar-Sentinela' | ForEach-Object {
        $_.Triggers | ForEach-Object {
            Write-Host ('  trigger ' + $_.StartBoundary + ' repete ' + $_.Repetition.Interval + ' por ' + $_.Repetition.Duration + ' dias=' + $_.DaysOfWeek)
        }
    }
} else {
    Write-Host 'ERRO: registro falhou.' -ForegroundColor Red
    exit 1
}
exit 0
