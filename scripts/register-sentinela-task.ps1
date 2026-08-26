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

$ErrorActionPreference = 'Continue'

$ScriptPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_sentinela.ps1'
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERRO: script nao encontrado em $ScriptPath" -ForegroundColor Red
    exit 1
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

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

$task = Register-ScheduledTask -TaskName 'VIXRadar-Sentinela' -TaskPath '\' `
    -Action $action -Trigger @($trigger25, $trigger55) `
    -Principal $principal -Settings $settings `
    -Description 'Varredura pontual por gatilho (SENTINELA1). Consulta listar_plano_rotina modo=pontual e analisa so emissores com documento CVM nao entregue a analise, deferidos por teto ou inconclusivos. Teto 8 emissores / 120k tokens. Na maioria das execucoes sai em 0 token.' `
    -Force

if ($task) {
    Write-Host 'VIXRadar-Sentinela registrada.' -ForegroundColor Green
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
