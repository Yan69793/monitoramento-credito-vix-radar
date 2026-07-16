# register-all-routines-scheduler.ps1 — Task Scheduler Windows (FALLBACK — exige PC ligado)
# Primario sem PC: Claude Code Routines Remote — scripts/register-cloud-routines.ps1 + REGISTRAR-CLOUD.md
param(
    [switch]$Remove,
    [switch]$Status,
    [switch]$RunNow,
    [string]$RunTask
)

$ErrorActionPreference = 'Stop'
$Scripts = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts'
$Fechamento = 'E:\Diretorio\Claude\relatorio-diario-szuchmacher\scripts\run_fechamento_claude.ps1'
$Watchdog = 'E:\Diretorio\Claude\relatorio-diario-szuchmacher\scripts\briefing_watchdog.ps1'

$Tasks = @(
    @{
        Name        = 'VIXRadar-AgendaSemanal'
        Description = 'VIX Radar calendario resultados stale top 20'
        Script      = Join-Path $Scripts 'run_claude_routine.ps1'
        ArgList     = @('-RoutineId', 'vixradar-agenda-semanal')
        DaysOfWeek  = 'Monday'
        At          = '03:00'
        Daily       = $false
    },
    @{
        Name        = 'VIXRadar-Matinal'
        Description = 'VIX Radar matinal tiered top 15'
        Script      = Join-Path $Scripts 'run_vixradar_matinal_claude.ps1'
        ArgList     = @()
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '10:00'
        Daily       = $false
    },
    @{
        Name        = 'VIXRadar-Noturno'
        Description = 'VIX Radar noturno 103/103 orquestrado'
        Script      = Join-Path $Scripts 'run_vixradar_noturno_claude.ps1'
        ArgList     = @()
        DaysOfWeek  = $null
        At          = '18:00'
        Daily       = $true
    },
    @{
        Name        = 'Szuchmacher-AgendaMacro-Claude'
        Description = 'Agenda macro szuchmacher.com.br via Claude SKILL'
        Script      = Join-Path $Scripts 'run_claude_routine.ps1'
        ArgList     = @('-RoutineId', 'atualizar-agenda-macro-szuchmacher')
        DaysOfWeek  = 'Friday'
        At          = '07:07'
        Daily       = $false
    },
    @{
        Name        = 'Szuchmacher-FechamentoDiario'
        Description = 'Fechamento mercado Szuchmacher 19h'
        Script      = $Fechamento
        ArgList     = @()
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '19:00'
        Daily       = $false
    },
    @{
        Name        = 'Szuchmacher-FechamentoWatchdog'
        Description = 'Watchdog fechamento 19h20 fallback'
        Script      = $Watchdog
        ArgList     = @()
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '19:20'
        Daily       = $false
    }
)

function New-TaskSettings {
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
        -RestartCount 1 -RestartInterval (New-TimeSpan -Minutes 15)
    return $s
}

function Register-OneTask($t) {
    if (-not (Test-Path $t.Script)) {
        throw ('Script ausente: ' + $t.Script)
    }
    Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false -ErrorAction SilentlyContinue

    $psArg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $t.Script + '"'
    if ($t.ArgList -and $t.ArgList.Count -gt 0) {
        $psArg += ' ' + (($t.ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    }
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArg -WorkingDirectory $Scripts

    if ($t.Daily) {
        $trg = New-ScheduledTaskTrigger -Daily -At $t.At
    } else {
        $dow = $t.DaysOfWeek -split ','
        $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dow -At $t.At
    }

    $user = if ($env:USERDOMAIN -and $env:USERNAME) { $env:USERDOMAIN + '\' + $env:USERNAME } else { $env:USERNAME }
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $desc = if ($t.Description) { $t.Description } else { $t.Name }
    Register-ScheduledTask -TaskName $t.Name -Action $act -Trigger $trg `
        -Settings (New-TaskSettings) -Principal $principal -Description $desc -Force | Out-Null
}

if ($Status) {
    Write-Host '=== Rotinas automaticas (Windows Task Scheduler) ===' -ForegroundColor Cyan
    foreach ($t in $Tasks) {
        try {
            $st = Get-ScheduledTask -TaskName $t.Name -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -TaskName $t.Name
            Write-Host ('  {0,-32} {1,-6} Next={2}' -f $t.Name, $st.State, $info.NextRunTime)
        } catch {
            Write-Host ('  {0,-32} AUSENTE' -f $t.Name) -ForegroundColor Yellow
        }
    }
    # Legado retry (opcional, one-shot)
    try {
        $r = Get-ScheduledTaskInfo -TaskName 'VIXRadar-Matinal-Retry'
        Write-Host ('  {0,-32} {1,-6} Next={2}' -f 'VIXRadar-Matinal-Retry', 'Ready', $r.NextRunTime)
    } catch { }
    return
}

if ($Remove) {
    foreach ($t in $Tasks) {
        Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host ('Removida: ' + $t.Name) -ForegroundColor Yellow
    }
    Unregister-ScheduledTask -TaskName 'VIXRadar-Matinal-Retry' -Confirm:$false -ErrorAction SilentlyContinue
    return
}

Write-Host '=== Registrando rotinas automaticas ===' -ForegroundColor Cyan
$fail = 0
foreach ($t in $Tasks) {
    try {
        Register-OneTask $t
        Write-Host ('OK ' + $t.Name + ' -> ' + $t.At + $(if ($t.Daily) { ' diario' } else { ' ' + $t.DaysOfWeek })) -ForegroundColor Green
    } catch {
        $fail++
        Write-Host ('FAIL ' + $t.Name + ': ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '  -> Execute este script no PowerShell do usuario (fora do sandbox) se Acesso negado.' -ForegroundColor Yellow
    }
}
if ($fail -gt 0) {
    Write-Host ("`n$fail task(s) falharam. Rode como usuario logado: pwsh -File `"$PSCommandPath`"") -ForegroundColor Yellow
}

# Remover retry orfao sem proxima execucao
Unregister-ScheduledTask -TaskName 'VIXRadar-Matinal-Retry' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host 'Limpo: VIXRadar-Matinal-Retry (one-shot obsoleto)' -ForegroundColor DarkGray

Write-Host ''
& $PSCommandPath -Status

if ($RunTask) {
    $match = $Tasks | Where-Object { $_.Name -eq $RunTask }
    if (-not $match) { throw "Task desconhecida: $RunTask" }
    $cmd = $match.Script
    if ($match.ArgList -and $match.ArgList.Count -gt 0) { & $cmd @($match.ArgList) } else { & $cmd }
}

if ($RunNow) {
    Write-Host 'Use -RunTask NomeDaTask para disparo manual de uma rotina.' -ForegroundColor Cyan
}