# register-all-routines-scheduler.ps1 — Task Scheduler Windows (FALLBACK — exige PC ligado)
# Primario sem PC: Claude Code Routines Remote — scripts/register-cloud-routines.ps1 + REGISTRAR-CLOUD.md
#
# ESCOPO EXPLICITO (P2-SCHEDGUARD1, 2026-08-03):
#   Este script registra APENAS as 6 tasks listadas abaixo.
#   Tasks NAO cobertas por este script (use o registrador especifico de cada uma):
#     - VIXRadar-Monitor-Tasks     → scripts/register-monitor-tasks.ps1
#     - VIXRadar-Coleta-Volatilidade → scripts/register-coleta-volatilidade-task.ps1
#     - VIXRadar-Export-Historico  → scripts/register-export-historico-task.ps1
#     - VIXRadar-Reconciliacao-CVM → scripts/register-reconciliacao-cvm-task.ps1
#     - VIXRadar-Ranking-Mensal    → scripts/register-ranking-mensal-task.ps1
#
#   VIXRadar-Verificacao-Async PASSOU a ser coberto por este script (REGDRIFT1-FIX,
#   2026-08-15): registrada com Disabled = $true, guarda anti-duplicata com a sessao
#   Claude Desktop. O registrador dedicado (register-verificacao-async-task.ps1) foi
#   desativado com guarda dura, mesmo padrao do register-vixradar-tasks.ps1.
#
# ATENCAO: A linha Unregister-ScheduledTask em Register-OneTask zera o LastRunTime
# e a task perde o disparo do dia se o horario do trigger ja passou.
# Se hoje for dia de execucao e voce rodar depois do horario, a task NAO executara hoje.
param(
    [switch]$Remove,
    [switch]$Status,
    [switch]$RunNow,
    [string]$RunTask
)

$ErrorActionPreference = 'Continue'
# P2-SCHEDGUARD1: habilitar log operacional do Scheduler para rastrear remocoes futuras
try {
    $logOp = Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction SilentlyContinue
    if ($logOp -and -not $logOp.IsEnabled) {
        wevtutil sl 'Microsoft-Windows-TaskScheduler/Operational' /e:true
        Write-Host 'Log operacional do Task Scheduler habilitado (rastreamento de remocoes).' -ForegroundColor DarkGray
    }
} catch {
    Write-Host 'AVISO: nao foi possivel habilitar o log operacional do Task Scheduler.' -ForegroundColor Yellow
}
$Scripts = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts'
$Fechamento = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\scripts\run_fechamento_claude.ps1'
$Watchdog = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\scripts\briefing_watchdog.ps1'

$Tasks = @(
    @{
        Name        = 'VIXRadar-AgendaSemanal'
        Description = 'VIX Radar calendario resultados stale top 20'
        # AGENDASEM-CAUSA1 (2026-08-18): 'vixradar-agenda-semanal' foi removida do
        # catalogo generico de run_claude_routine.ps1 e tem wrapper dedicado. Apontar
        # para run_claude_routine.ps1 com -RoutineId vixradar-agenda-semanal cai no
        # ContainsKey($RoutineId) = false e sai com exit 2 sem rodar nada.
        Script      = Join-Path $Scripts 'run_vixradar_agenda_semanal.ps1'
        ArgList     = @()
        # CALVAL-V2 regra 9 (2026-08-14): revalidacao 2x/semana (Dom+Qua).
        DaysOfWeek  = 'Sunday,Wednesday'
        At          = '22:00'
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
        # REGDRIFT1-FIX (2026-08-15): roda por sessao agendada do Claude Desktop;
        # task nativa fica DISABLED como guarda anti-duplicata. O registrador
        # passa a reproduzir esse estado (antes era aplicado so a mao).
        Disabled    = $true
    },
    @{
        Name        = 'VIXRadar-Noturno'
        Description = 'VIX Radar noturno 103/103 orquestrado'
        Script      = Join-Path $Scripts 'run_vixradar_noturno_claude.ps1'
        ArgList     = @()
        DaysOfWeek  = $null
        At          = '18:00'
        Daily       = $true
        Disabled    = $true
    },
    @{
        Name        = 'VIXRadar-Verificacao-Async'
        Description = 'VIX Radar dreno fila verificacao (Claude Desktop)'
        Script      = Join-Path $Scripts 'run_vixradar_verificacao_async.ps1'
        ArgList     = @()
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '10:20'
        Daily       = $false
        Disabled    = $true
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
    # P2-SCHEDGUARD1: avisar se o re-registro acontece depois do horario do trigger do dia
    $agora = Get-Date
    $triggerTime = [datetime]::ParseExact($t.At, 'HH:mm', $null)
    $triggerHoje = Get-Date -Year $agora.Year -Month $agora.Month -Day $agora.Day -Hour $triggerTime.Hour -Minute $triggerTime.Minute -Second 0
    $diaSemana = $agora.DayOfWeek
    $ehDiaDeExecutar = $false
    if ($t.Daily) {
        $ehDiaDeExecutar = $true
    } elseif ($t.DaysOfWeek) {
        $dias = $t.DaysOfWeek -split ','
        $ehDiaDeExecutar = ($dias -contains $diaSemana.ToString())
    }
    if ($ehDiaDeExecutar -and $agora -gt $triggerHoje) {
        Write-Host ('ATENCAO: ' + $t.Name + ' perdera o disparo de hoje (' + $t.At + ' ja passou). A task sera recriada sem executar hoje.' ) -ForegroundColor Yellow
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

    # REGDRIFT1-FIX (2026-08-15): reproduz o estado Disabled das tasks de rotina
    # Claude Desktop apos o registro. Antes deste fix, nenhum script reproduzia
    # esse estado e re-registrar reabilitava a task, abrindo dupla execucao.
    # Revisao 15/08: Disable sem guarda falhava em silencio (ErrorActionPreference
    # Continue) e o script imprimia OK com a task reabilitada. Agora falha alto.
    if ($t.Disabled) {
        try {
            Disable-ScheduledTask -TaskName $t.Name -ErrorAction Stop | Out-Null
        } catch {
            throw ('registrada mas nao desabilitada: ' + $t.Name + ' (' + $_.Exception.Message + ')')
        }
    }
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