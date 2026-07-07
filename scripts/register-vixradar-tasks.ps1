# register-vixradar-tasks.ps1 — registra VIXRadar-Matinal e VIXRadar-Noturno no Task Scheduler
# Execute como Administrador uma vez.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent $PSScriptRoot
$PWSH = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $PWSH) { $PWSH = 'pwsh' }

$tasks = @(
    @{
        Name       = 'VIXRadar-Matinal'
        Script     = Join-Path $ROOT 'scripts\run_vixradar_matinal_claude.ps1'
        Hour       = 10
        Minute     = 0
        DaysOfWeek = 'Monday','Tuesday','Wednesday','Thursday','Friday'
        TimeLimit  = 240
    },
    @{
        Name       = 'VIXRadar-Noturno'
        Script     = Join-Path $ROOT 'scripts\run_vixradar_noturno_claude.ps1'
        Hour       = 18
        Minute     = 0
        DaysOfWeek = 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
        TimeLimit  = 240
    }
)

foreach ($t in $tasks) {
    $action   = New-ScheduledTaskAction -Execute $PWSH `
        -Argument "-NonInteractive -WindowStyle Hidden -File `"$($t.Script)`""
    $trigger  = New-ScheduledTaskTrigger -Weekly `
        -DaysOfWeek $t.DaysOfWeek `
        -At "$($t.Hour):$($t.Minute.ToString('D2'))"
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $t.TimeLimit) `
        -StartWhenAvailable

    if (Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
        Write-Host "REMOVIDA task existente: $($t.Name)"
    }

    Register-ScheduledTask `
        -TaskName    $t.Name `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -RunLevel    Highest `
        -Description "VIX Radar — gerado automaticamente" | Out-Null

    Write-Host "REGISTRADA: $($t.Name) @ $($t.Hour):$($t.Minute.ToString('D2'))"
}

Write-Host ""
Write-Host "Verificar com:"
Write-Host "  Get-ScheduledTask | Where-Object TaskName -like 'VIXRadar-*' | Select TaskName, State, NextRunTime"
