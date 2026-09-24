# register-ranking-mensal-task.ps1
# Cria a task VIXRadar-Ranking-Mensal no Windows Task Scheduler, JA apontada para o guarda
# scripts\preflight-and-run.ps1 (GUARD-REG1, 2026-09-24). Mesmo contrato de guarda do
# register-reconciliacao-cvm-task.ps1, com a montagem centralizada na lib
# scripts/lib/vixradar-task-guard.ps1.
# Roda dia 1 de cada mes as 11:30 (hora local BRT) - fora da janela matinal (10h00) e do cron de verificacao (10h20).
# Usa Register-ScheduledTask -Xml: New-ScheduledTaskTrigger nao suporta trigger mensal e o
# schtasks /TR quebra com caminho contendo espacos sob PowerShell 5.1 (quoting).
# NOTA: a task VIXRadar-Ranking-Mensal e OBSOLETA (AGENTS.md). O registrador continua guardado
# para que, se for recriada, nao nasca desprotegida.
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Ranking-Mensal' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-ranking-mensal-task.ps1"
#      powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-ranking-mensal-task.ps1" -DryRun
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_vixradar_ranking_mensal.ps1'
$TaskName    = 'VIXRadar-Ranking-Mensal'
$Guarda      = Join-Path $ProjectRoot 'scripts\preflight-and-run.ps1'
$LogPattern  = 'logs\routines\vixradar-ranking_{yyyyMMdd_HHmmss}.log'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }
. (Join-Path $ProjectRoot 'scripts\lib\vixradar-task-guard.ps1')
# Sem o guarda na arvore o registrador RECUSA (fail-closed): nao existe registro sem guarda.
Assert-VixGuardPath -Guarda $Guarda | Out-Null

# Formato identico ao Get-ArgumentoGuarda de scripts/apply-preflight-tasks.ps1. O XML tem de
# receber a linha escapada, porque o parser le o argumento como texto XML.
$Argument    = Get-VixGuardArgument -Guarda $Guarda -Target $ScriptPath -Name $TaskName -LogPattern $LogPattern
$ArgumentXml = [System.Security.SecurityElement]::Escape($Argument)

$userId = "$env:USERDOMAIN\$env:USERNAME"
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>VIX Radar - monitor mensal de ranking SEO (vixradar.com vs concorrentes; alerta de ultrapassagem)</Description>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-08-01T11:30:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByMonth>
        <DaysOfMonth>
          <Day>1</Day>
        </DaysOfMonth>
        <Months>
          <January /><February /><March /><April /><May /><June />
          <July /><August /><September /><October /><November /><December />
        </Months>
      </ScheduleByMonth>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userId</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$ArgumentXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@

if ($DryRun) {
    Write-Output '--- DRYRUN: nada foi registrado ---'
    Write-Output ('task     : ' + $TaskName)
    Write-Output ('argument : ' + $Argument)
    Write-Output ('trigger  : mensal dia 1 as 11:30 (ScheduleByMonth)')
    Write-Output ('limit    : PT30M')
    Write-Output ('principal: ' + $userId + ' / InteractiveToken / LeastPrivilege')
    $falhas = Test-VixGuardAction -Nome $TaskName -Argument $Argument
    if ($falhas -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhas + ' falha(s)'); exit 1 }
    Write-Output 'DRYRUN OK'
    exit 0
}

$task = Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force

# Leitura de volta: registro que nao e conferido nao conta como registrado.
$lida = Get-ScheduledTask -TaskName $TaskName
$argLida = [string](@($lida.Actions)[0]).Arguments
if ($argLida -ne $Argument) {
    throw ('leitura de volta diferente do esperado. esperado: ' + $Argument + ' | lido: ' + $argLida)
}

Write-Output "Task registrada e conferida no guarda: $($task.TaskName)"
Write-Output "Estado: $($task.State)"
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Output "Proxima execucao: $($info.NextRunTime)"
