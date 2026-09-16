# apply-preflight-tasks.ps1 - re-aponta as 13 acoes de tarefa agendada para passar pelo guarda.
#
# ISTO E ATIVACAO, NAO PREPARACAO. NAO rode sem querer.
#   - Sem -Apply o script apenas LE o Task Scheduler e imprime o antes/depois. Nenhuma escrita.
#   - Com -Apply ele exige elevacao e reescreve SO a acao de cada tarefa (Set-ScheduledTask),
#     preservando trigger, principal, settings, WorkingDirectory e LastRunTime. Nao usa
#     Unregister/Register (que zerariam o LastRunTime e o disparo do dia) nem 'schtasks'.
#
# ANTES DE RODAR: os arquivos deste card tem de estar LANDADOS na arvore viva
#   scripts/preflight-and-run.ps1
#   scripts/lib/vixradar-preflight.ps1
#   scripts/lib/preflight-scan.ps1
# Se o guarda nao existir, este script recusa.
#
# USO
#   # 1) conferir o antes/depois, sem escrever nada:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Diretorio\Claude\Monitoramento de Credito\scripts\apply-preflight-tasks.ps1"
#
#   # 2) aplicar (janela elevada, PowerShell como Administrador):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Diretorio\Claude\Monitoramento de Credito\scripts\apply-preflight-tasks.ps1" -Apply
#
# REVERSAO: rodar de novo o registrador canonico de cada familia
#   scripts/register-all-routines-scheduler.ps1        (AgendaSemanal, Matinal, Noturno, Verificacao-Async, AgendaMacro)
#   scripts/register-monitor-tasks.ps1, register-coleta-volatilidade-task.ps1,
#   scripts/register-export-historico-task.ps1, register-reconciliacao-cvm-task.ps1,
#   scripts/register-retry-tasks.ps1, register-sentinela-task.ps1
# (todos eles ja roteiam pelo guarda neste mesmo patch)
#
# ESCOPO: as 13 acoes medidas em 16/09/2026 apontando para este repositorio. As duas em estado
# Disabled (Szuchmacher-RetryVixMatinal, VIXRadar-Health-Watch) ENTRAM: o guarda cobre a
# DEFINICAO da tarefa, nao o estado transitorio de habilitacao (decisao do operador sobre W2).
param(
    [string]$RepoRoot = 'E:\Diretorio\Claude\Monitoramento de Credito',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$Tarefas = @(
    @{ Nome = 'Monitor-Tasks';                  Script = 'scripts\monitor-tasks.ps1';                        Log = 'logs\monitor-tasks\monitor_{yyyyMMdd}.log';                        Args = @('-Quiet', '-SendEmail') }
    @{ Nome = 'Szuchmacher-AgendaMacro-Claude'; Script = 'scripts\run_claude_routine.ps1';                   Log = 'logs\routines\agenda-macro-szuchmacher_{yyyyMMdd}.log';            Args = @('-RoutineId', 'atualizar-agenda-macro-szuchmacher') }
    @{ Nome = 'Szuchmacher-RetryVixMatinal';    Script = 'scripts\retry-vixradar.ps1';                       Log = 'logs\routines\vixradar-matinal_{yyyyMMdd}.log';                    Args = @('-RoutineId', 'vixradar-matinal') }
    @{ Nome = 'Szuchmacher-RetryVixNoturno';    Script = 'scripts\retry-vixradar.ps1';                       Log = 'logs\routines\vixradar-noturno_{yyyyMMdd}.log';                    Args = @('-RoutineId', 'vixradar-noturno') }
    @{ Nome = 'VIXRadar-AgendaSemanal';         Script = 'scripts\run_vixradar_agenda_semanal.ps1';          Log = 'logs\routines\vixradar-agenda-semanal_{yyyyMMdd}.log';             Args = @() }
    @{ Nome = 'VIXRadar-Coleta-Volatilidade';   Script = 'scripts\run_coleta_volatilidade.ps1';              Log = 'logs\routines\coleta_volatilidade_{yyyyMMdd}.log';                 Args = @() }
    @{ Nome = 'VIXRadar-Export-Historico';      Script = 'scripts\run_vixradar_export_historico.ps1';        Log = 'logs\routines\vixradar-export_{yyyyMMdd_HHmmss}.log';              Args = @() }
    @{ Nome = 'VIXRadar-Health-Watch';          Script = 'scripts\watch-vixradar-health.ps1';                Log = 'logs\watch-health\watch_{yyyyMMdd}.log';                           Args = @() }
    @{ Nome = 'VIXRadar-Matinal';               Script = 'scripts\run_vixradar_matinal_claude.ps1';          Log = 'logs\routines\vixradar-matinal_{yyyyMMdd}.log';                    Args = @() }
    @{ Nome = 'VIXRadar-Noturno';               Script = 'scripts\run_vixradar_noturno_claude.ps1';          Log = 'logs\routines\vixradar-noturno_{yyyyMMdd}.log';                    Args = @() }
    @{ Nome = 'VIXRadar-Reconciliacao-CVM';     Script = 'scripts\predictive\reconciliar_ipe_cvm.ps1';       Log = 'logs\routines\vixradar-reconciliacao-cvm_{yyyyMMdd_HHmmss}.log';   Args = @() }
    @{ Nome = 'VIXRadar-Sentinela';             Script = 'scripts\run_vixradar_sentinela.ps1';               Log = 'logs\routines\vixradar-sentinela_{yyyyMMdd}.log';                  Args = @() }
    @{ Nome = 'VIXRadar-Verificacao-Async';     Script = 'scripts\run_vixradar_verificacao_async.ps1';       Log = 'logs\routines\vixradar-verificacao-async_{yyyyMMdd}.log';          Args = @() }
)

$Guarda = Join-Path $RepoRoot 'scripts\preflight-and-run.ps1'
if (-not (Test-Path -LiteralPath $Guarda)) {
    throw ('guarda ausente: ' + $Guarda + ' - lande os arquivos do patch antes de re-apontar tarefa')
}

function Get-ArgumentoGuarda {
    param($T)
    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Guarda + '"'
    $arg += ' -GuardTarget "' + (Join-Path $RepoRoot $T.Script) + '"'
    $arg += ' -GuardName ' + "'" + $T.Nome + "'"
    $arg += ' -GuardLogPattern "' + $T.Log + '"'
    foreach ($a in $T.Args) { $arg += ' ' + $a }
    return $arg
}

$modo = 'CONFERENCIA (nao escreve nada)'
if ($Apply) { $modo = 'APLICACAO' }

$admin = $false
try {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $admin = (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

Write-Host ('=== PREFLIGHT: re-apontamento das 13 acoes de tarefa - ' + $modo + ' ===') -ForegroundColor Cyan
Write-Host ('raiz   : ' + $RepoRoot)
Write-Host ('guarda : ' + $Guarda)
Write-Host ('elevado: ' + $admin)
Write-Host ''

if ($Apply -and -not $admin) {
    throw 'APLICACAO exige janela elevada (Set-ScheduledTask). Abra o PowerShell como Administrador.'
}

$falhas = 0
$pendentes = 0

foreach ($t in $Tarefas) {
    $task = Get-ScheduledTask -TaskName $t.Nome -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ('AUSENTE   ' + $t.Nome) -ForegroundColor Yellow
        $falhas++
        continue
    }
    $acaoAtual = @($task.Actions)[0]
    $argAtual = [string]$acaoAtual.Arguments
    $argNovo = Get-ArgumentoGuarda $t
    $jaOk = ($argAtual -eq $argNovo)

    Write-Host ('--- ' + $t.Nome + '  [' + $task.State + ']')
    Write-Host ('    atual : ' + $acaoAtual.Execute + ' ' + $argAtual)
    Write-Host ('    novo  : ' + $acaoAtual.Execute + ' ' + $argNovo)
    if ($jaOk) {
        Write-Host '    estado: JA APONTADO PARA O GUARDA' -ForegroundColor Green
    } else {
        $pendentes++
        Write-Host '    estado: PENDENTE' -ForegroundColor Yellow
    }

    if ($Apply -and -not $jaOk) {
        $parametros = @{ Execute = $acaoAtual.Execute; Argument = $argNovo }
        if ($acaoAtual.WorkingDirectory) { $parametros.WorkingDirectory = [string]$acaoAtual.WorkingDirectory }
        $novaAcao = New-ScheduledTaskAction @parametros
        Set-ScheduledTask -TaskName $t.Nome -Action $novaAcao | Out-Null
        # Leitura de volta: escrita que nao e conferida nao conta como aplicada.
        $depois = Get-ScheduledTask -TaskName $t.Nome
        $argDepois = [string](@($depois.Actions)[0]).Arguments
        if ($argDepois -eq $argNovo) {
            Write-Host '    aplicado e conferido na leitura de volta' -ForegroundColor Green
        } else {
            Write-Host '    FALHA: leitura de volta diferente do esperado' -ForegroundColor Red
            $falhas++
        }
    }
}

Write-Host ''
if ($Apply) {
    Write-Host ('aplicacao: ' + ($Tarefas.Count - $falhas - $pendentes) + ' ja estavam, ' + $pendentes + ' re-apontadas, ' + $falhas + ' falha(s)')
    if ($falhas -gt 0) { exit 1 }
    exit 0
}
Write-Host ('conferencia: ' + $pendentes + ' acao(oes) pendente(s) de re-apontamento, ' + $falhas + ' tarefa(s) ausente(s) de ' + $Tarefas.Count)
Write-Host 'para aplicar: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<este script>" -Apply   (janela elevada)'
if ($falhas -gt 0) { exit 1 }
exit 0
