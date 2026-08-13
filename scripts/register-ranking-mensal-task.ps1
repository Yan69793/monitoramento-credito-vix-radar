# register-ranking-mensal-task.ps1
# Cria a task VIXRadar-Ranking-Mensal no Windows Task Scheduler.
# Roda dia 1 de cada mes as 11:30 (hora local BRT) - fora da janela matinal (10h00) e do cron de verificacao (10h20).
# Usa Register-ScheduledTask -Xml: New-ScheduledTaskTrigger nao suporta trigger mensal e o
# schtasks /TR quebra com caminho contendo espacos sob PowerShell 5.1 (quoting).
# Reversao: Unregister-ScheduledTask -TaskName 'VIXRadar-Ranking-Mensal' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-ranking-mensal-task.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\run_vixradar_ranking_mensal.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

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
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$ScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$task = Register-ScheduledTask -TaskName 'VIXRadar-Ranking-Mensal' -Xml $xml -Force

Write-Output "Task registrada: $($task.TaskName)"
Write-Output "Estado: $($task.State)"
$info = Get-ScheduledTaskInfo -TaskName 'VIXRadar-Ranking-Mensal'
Write-Output "Proxima execucao: $($info.NextRunTime)"
