# register-reconciliacao-cvm-task.ps1
# Cria a task VIXRadar-Reconciliacao-CVM no Windows Task Scheduler, JA apontada para o
# guarda scripts\preflight-and-run.ps1 (GUARD-CVM1, 2026-09-24).
# Roda SEMANALMENTE as segundas-feiras 12:00 (hora local BRT). Era 08:00, herdado da epoca
# em que se supunha que so a serie A-1 existia (escrita no domingo ~07h BRT, medido uma vez
# em 12/07/2026, nota Obsidian 60). Medido em 21/09/2026: o zip do ANO CORRENTE e republicado
# pela CVM na segunda de manha e naquele dia so foi escrito as 08:53 BRT (Last-Modified
# 11:53:41Z) - a execucao das 08:00 pegou 404 e morreu com ERRO FATAL (exit 1). 12:00 fica
# depois dessa janela e tambem fora da janela matinal (10h00) e do cron de verificacao (10h20).
# O retry curto no download (RECONCILE-CVM404B, no proprio reconciliador) cobre atraso de
# minutos na republicacao.
#
# GUARD-CVM1 (2026-09-24): este registrador montava a acao chamando o script da rotina direto,
# entao a task nascia desprotegida e o re-apontamento para o guarda so acontecia depois, quando
# alguem rodava scripts/apply-preflight-tasks.ps1 -Apply numa janela elevada. Recriar a task
# pelo caminho canonico (este script) voltava ao estado vulneravel. Agora o registrador:
#   - monta o MESMO argumento de apply-preflight-tasks.ps1 (Get-ArgumentoGuarda), para os dois
#     concordarem por igualdade exata de string e nao existir apply posterior obrigatorio;
#   - recusa se scripts/preflight-and-run.ps1 nao existir na arvore (mesmo preflight do apply);
#   - confere a acao na leitura de volta depois de registrar.
# -DryRun nao registra nada: monta a acao, imprime e compara com a task viva.
#
# REVERSAO: Unregister-ScheduledTask -TaskName 'VIXRadar-Reconciliacao-CVM' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-reconciliacao-cvm-task.ps1"
#      powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-reconciliacao-cvm-task.ps1" -DryRun
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$TaskName    = 'VIXRadar-Reconciliacao-CVM'
$Guarda      = Join-Path $ProjectRoot 'scripts\preflight-and-run.ps1'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\predictive\reconciliar_ipe_cvm.ps1'
$LogPattern  = 'logs\routines\vixradar-reconciliacao-cvm_{yyyyMMdd_HHmmss}.log'

if (-not (Test-Path -LiteralPath $Guarda)) {
    throw ('Guarda ausente: ' + $Guarda + ' - lande scripts/preflight-and-run.ps1 antes de registrar a task.')
}
if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

# Formato identico ao Get-ArgumentoGuarda de scripts/apply-preflight-tasks.ps1: o apply
# compara por igualdade exata de string, entao qualquer drift aqui faria a task ser
# re-apontada de novo e o registrador voltaria a ser fonte divergente.
$Argument  = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Guarda + '"'
$Argument += ' -GuardTarget "' + $ScriptPath + '"'
$Argument += ' -GuardName ' + "'" + $TaskName + "'"
$Argument += ' -GuardLogPattern "' + $LogPattern + '"'

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $Argument
$trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '12:00'
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

if ($DryRun) {
    Write-Output '--- DRYRUN: nada foi registrado ---'
    Write-Output ('task     : ' + $TaskName)
    Write-Output ('execute  : ' + $action.Execute)
    Write-Output ('argument : ' + $action.Arguments)
    Write-Output ('trigger  : ' + $trigger.CimClass.CimClassName + ' DaysOfWeek=' + $trigger.DaysOfWeek + ' StartBoundary=' + $trigger.StartBoundary)
    Write-Output ('limit    : ' + $settings.ExecutionTimeLimit)
    Write-Output ('principal: ' + $principal.UserId + ' / ' + $principal.LogonType + ' / ' + $principal.RunLevel)

    $falhas = 0
    if ($action.Arguments -ne $Argument) { Write-Output 'FALHA acao montada difere do argumento esperado'; $falhas++ }
    if ($action.Arguments -notlike '*preflight-and-run.ps1*') { Write-Output 'FALHA acao nao passa pelo guarda'; $falhas++ }
    foreach ($obrig in @('-GuardTarget', '-GuardName', '-GuardLogPattern')) {
        if ($action.Arguments -notlike ('*' + $obrig + '*')) { Write-Output ('FALHA acao sem ' + $obrig); $falhas++ }
    }
    if ([string]$trigger.DaysOfWeek -ne '2') { Write-Output 'FALHA trigger nao e segunda-feira (DaysOfWeek=2)'; $falhas++ }
    if ([string]$settings.ExecutionTimeLimit -ne 'PT20M') { Write-Output 'FALHA ExecutionTimeLimit diferente de PT20M'; $falhas++ }

    $viva = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($viva) {
        $argViva = [string](@($viva.Actions)[0]).Arguments
        if ($argViva -eq $Argument) {
            Write-Output 'task viva: igual ao esperado (apply-preflight-tasks.ps1 nao teria o que corrigir)'
        } else {
            Write-Output 'task viva: DIFERENTE do esperado'
            Write-Output ('  viva    : ' + $argViva)
            Write-Output ('  esperado: ' + $Argument)
            $falhas++
        }
    } else {
        Write-Output 'task viva: ausente (nada para comparar)'
    }

    if ($falhas -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhas + ' falha(s)'); exit 1 }
    Write-Output 'DRYRUN OK'
    exit 0
}

$task = Register-ScheduledTask -TaskName $TaskName -TaskPath '\' `
    -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'VIX Radar - reconciliador semanal: dataset oficial CVM IPE (RJ/RE/default/reestruturacao/inadimplencia) vs classificacao do Radar. Rede de seguranca deterministica contra miss de heuristica (nota Obsidian 60, RESEARCHDOWN1).' `
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
