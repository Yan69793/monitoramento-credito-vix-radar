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
#   CLAUDE-FREE-MIGRATION (2026-09-04, Fase A): Matinal, Noturno e Verificacao-Async
#   voltam a ser tasks nativas ENABLED, executadas pelo Task Scheduler como motor unico.
#   Nao existe mais sessao agendada do Claude Desktop guardando duplicata: o proprio script
#   de cada rotina carrega o gate de provider (BLOQUEADO_SEM_PROVIDER, exit 86) e, sem
#   provider habilitado, sai bloqueado sem tocar em claude. O registro canoneiro destas 5
#   (3 rotinas + 2 retries) e o scripts/cutover-motor.ps1: este registrador so expressa UM
#   trigger por task e nao cobre os retries, entao NAO reproduz o estado pos-Fase-A completo
#   (a Verificacao-Async real tem dois triggers, 11:03 e 19:15). Para reconstruir o scheduler
#   das rotinas LLM, rodar cutover-motor.ps1; este arquivo segue valido para AgendaSemanal e
#   para o cluster Szuchmacher. A secao "Status" abaixo nao lista Sentinela nem retries.
#
# ATENCAO: A linha Unregister-ScheduledTask em Register-OneTask zera o LastRunTime
# e a task perde o disparo do dia se o horario do trigger ja passou.
# Se hoje for dia de execucao e voce rodar depois do horario, a task NAO executara hoje.
param(
    [switch]$Remove,
    [switch]$Status,
    [switch]$RunNow,
    [switch]$DryRun,
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
# GUARD-REG1 (2026-09-24): contrato unico de guarda em scripts/lib/vixradar-task-guard.ps1,
# o mesmo de register-reconciliacao-cvm-task.ps1. Toda task deste repositorio nasce apontada
# para $Guarda e nao depende mais de apply-preflight-tasks.ps1 -Apply rodar depois.
# EXCECAO: Szuchmacher-FechamentoDiario/Watchdog apontam para OUTRO repositorio. O guarda recusa
# alvo fora da arvore varrida (preflight-and-run.ps1), entao essas duas ficam fora do guarda e
# marcadas com Guarda=$false na tabela; nao ha protecao possivel com este contrato.
$Guarda = Join-Path $Scripts 'preflight-and-run.ps1'
. (Join-Path $Scripts 'lib\vixradar-task-guard.ps1')

$Tasks = @(
    @{
        Name        = 'VIXRadar-AgendaSemanal'
        Description = 'VIX Radar calendario resultados stale top 20'
        # AGENDASEM-CAUSA1 (2026-08-18): 'vixradar-agenda-semanal' foi removida do
        # catalogo de run_claude_routine.ps1. Wrapper dedicado, invocado direto
        # (sem -RoutineId, sem parametros - o script nao declara bloco param()).
        Script      = Join-Path $Scripts 'run_vixradar_agenda_semanal.ps1'
        ArgList     = @()
        Guarda      = $true
        LogPattern  = 'logs\routines\vixradar-agenda-semanal_{yyyyMMdd}.log'
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
        Guarda      = $true
        LogPattern  = 'logs\routines\vixradar-matinal_{yyyyMMdd}.log'
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '10:00'
        Daily       = $false
    },
    @{
        Name        = 'VIXRadar-Noturno'
        Description = 'VIX Radar noturno 103/103 orquestrado'
        Script      = Join-Path $Scripts 'run_vixradar_noturno_claude.ps1'
        ArgList     = @()
        Guarda      = $true
        LogPattern  = 'logs\routines\vixradar-noturno_{yyyyMMdd}.log'
        DaysOfWeek  = $null
        At          = '18:00'
        Daily       = $true
    },
    @{
        Name        = 'VIXRadar-Verificacao-Async'
        Description = 'VIX Radar dreno fila verificacao (motor nativo)'
        Script      = Join-Path $Scripts 'run_vixradar_verificacao_async.ps1'
        ArgList     = @()
        Guarda      = $true
        LogPattern  = 'logs\routines\vixradar-verificacao-async_{yyyyMMdd}.log'
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '10:20'
        Daily       = $false
    },
    @{
        Name        = 'Szuchmacher-AgendaMacro-Claude'
        Description = 'Agenda macro szuchmacher.com.br via adapter OpenRouter'
        Script      = Join-Path $Scripts 'run_vixradar_agenda_macro_szuchmacher.ps1'
        ArgList     = @()
        Guarda      = $true
        LogPattern  = 'logs\routines\agenda-macro-szuchmacher_{yyyyMMdd}.log'
        DaysOfWeek  = 'Friday'
        At          = '07:07'
        Daily       = $false
    },
    @{
        Name        = 'Szuchmacher-FechamentoDiario'
        Description = 'Fechamento mercado Szuchmacher 19h'
        Script      = $Fechamento
        ArgList     = @()
        Guarda      = $false
        DaysOfWeek  = 'Monday,Tuesday,Wednesday,Thursday,Friday'
        At          = '19:00'
        Daily       = $false
    },
    @{
        Name        = 'Szuchmacher-FechamentoWatchdog'
        Description = 'Watchdog fechamento 19h20 fallback'
        Script      = $Watchdog
        ArgList     = @()
        Guarda      = $false
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
    # GUARD-REG1: a Action nasce apontando para o guarda. O argumento e montado com o MESMO
    # contrato de apply-preflight-tasks.ps1, para os dois concordarem por igualdade exata de
    # string e nao existir apply posterior obrigatorio.
    if ($t.Guarda) {
        # Sem o guarda na arvore o registrador RECUSA (fail-closed): nao existe registro sem guarda.
        Assert-VixGuardPath -Guarda $Guarda | Out-Null
        $psArg = Get-VixGuardArgument -Guarda $Guarda -Target $t.Script -Name $t.Name -LogPattern $t.LogPattern -ExtraArgs $t.ArgList
    } else {
        # EXCECAO documentada: alvo fora do repositorio varrido. preflight-and-run.ps1 recusa
        # alvo fora da arvore por construcao, entao estas duas continuam na chamada direta.
        $psArg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $t.Script + '"'
        if ($t.ArgList -and $t.ArgList.Count -gt 0) {
            $psArg += ' ' + (($t.ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        }
    }
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArg -WorkingDirectory $Scripts

    if ($DryRun) {
        # Write-Host (informacao) e nao Write-Output: o retorno desta funcao tem de ser SO o
        # numero de falhas, senao o chamador soma texto e reprova o DryRun por engano.
        $trgLabel = 'Daily ' + $t.At
        if (-not $t.Daily) { $trgLabel = 'Weekly ' + $t.DaysOfWeek + ' ' + $t.At }
        Write-Host '--- DRYRUN: nada foi registrado ---'
        Write-Host ('task     : ' + $t.Name)
        Write-Host ('execute  : ' + $act.Execute)
        Write-Host ('argument : ' + $act.Arguments)
        Write-Host ('trigger  : ' + $trgLabel)
        if (-not $t.Guarda) {
            Write-Host ('guarda   : ISENTO - alvo fora do repositorio varrido (o guarda recusa): ' + $t.Script)
            return 0
        }
        Write-Host 'guarda   : preflight-and-run.ps1'
        return (Test-VixGuardAction -Nome $t.Name -Argument $psArg)
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

    # Leitura de volta: registro que nao e conferido nao conta como registrado. Vale so para as
    # tasks guardadas; as isentas (fora do repo) nao tem string de guarda com que comparar.
    if ($t.Guarda) {
        $lida = Get-ScheduledTask -TaskName $t.Name
        $argLida = [string](@($lida.Actions)[0]).Arguments
        if ($argLida -ne $psArg) {
            throw ('leitura de volta diferente do esperado para ' + $t.Name + '. esperado: ' + $psArg + ' | lido: ' + $argLida)
        }
    }

    # CLAUDE-FREE-MIGRATION (2026-09-04, Fase A): nenhuma task registrada aqui carrega mais
    # Disabled = $true (Matinal/Noturno/Verificacao-Async sao o motor nativo Enabled, com o
    # gate de provider dentro do proprio script). O ramo abaixo fica como guarda generica
    # para task futura que precise nascer desligada, e falha alto se o Disable nao pegar.
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

if ($DryRun) {
    Write-Output '=== DRYRUN: nenhuma task foi registrada, removida ou disparada ==='
    $falhasDry = 0
    foreach ($t in $Tasks) {
        try {
            $falhasDry += [int](Register-OneTask $t)
        } catch {
            $falhasDry++
            Write-Output ('FALHA ' + $t.Name + ': ' + $_.Exception.Message)
        }
    }
    Write-Output ''
    if ($falhasDry -gt 0) { Write-Output ('DRYRUN REPROVADO: ' + $falhasDry + ' falha(s)'); exit 1 }
    Write-Output ('DRYRUN OK: ' + $Tasks.Count + ' task(s) conferidas, nenhuma escrita no Task Scheduler')
    exit 0
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