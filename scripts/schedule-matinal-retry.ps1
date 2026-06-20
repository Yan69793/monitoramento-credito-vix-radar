# schedule-matinal-retry.ps1 - Disparo unico pos-reset limite Claude (~6:10 BRT)
param(
    [string]$At = '06:15',
    [switch]$RunNow,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Runner = Join-Path $Root 'run_vixradar_matinal_claude.ps1'
$TaskName = 'VIXRadar-Matinal-Retry'

if ($Remove) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host ('Removida: ' + $TaskName) -ForegroundColor Yellow
    return
}

if ($RunNow) {
    & $Runner
    return
}

$parts = $At.Split(':')
$hour = [int]$parts[0]
$minute = [int]$parts[1]
$when = Get-Date -Hour $hour -Minute $minute -Second 0
if ((Get-Date) -ge $when) {
    Write-Host ('Horario ' + $At + ' ja passou hoje. Use -RunNow.') -ForegroundColor Yellow
    exit 1
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
$psArg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Runner + '"'
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArg
$trg = New-ScheduledTaskTrigger -Once -At $when
Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Force | Out-Null

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ('OK ' + $TaskName + ' agendada para ' + $info.NextRunTime) -ForegroundColor Green
Write-Host ('Task automatica 10:00 mantida: VIXRadar-Matinal') -ForegroundColor Cyan