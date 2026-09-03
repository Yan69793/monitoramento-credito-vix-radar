# retry-vixradar.ps1 - Retry automatico das rotinas VIX (noturno/matinal)
# quando a execucao via Claude Desktop nao entrega (sem linha FIM: valida no
# log do dia). ASCII puro (Task Scheduler, powershell.exe 5.1).
#
# Contexto (17/08/2026): as rotinas migraram do Task Scheduler para sessoes
# agendadas do Claude Desktop. A sessao entra em idle no meio do cascade e a
# rotina morre sem rastro (noturno 16/08, matinal 14/08). Este script roda via
# Task Scheduler apos a janela agendada e, se o log do dia nao tem FIM valido,
# relanca a rotina via claude CLI usando run_claude_routine.ps1 (o pre-flight
# dele limpa o ambiente que quebrou o CLI em 04/08 e sonda WebSearch antes de
# rodar). Agenda REAL (revertida 01/09, nome e horario batem de novo):
# RetryVixMatinal roda 13:30, RetryVixNoturno roda 21:30. A frase antiga sobre
# "nome invertido" descrevia o regime de 25/08 a 01/09, ja encerrado.
#
# Seguranca contra duplicata: a SKILL da rotina (Passo 0) tem lock de 3h e
# mutex. Execucao Desktop ainda viva segura o lock, o retry aborta limpo.
#
# INCIDENTE-FRESHNESS2 (03/09/2026): entrega passou a ser julgada dentro da
# JANELA REAL da rotina (Test-VixLedgerEntregueNaJanela), nunca pelo exit code
# do relancamento - a noturna de 02/09 provou por que: o retry das 21:30
# abortou por 429 sem esperar o reset real e sem alertar, e um relancamento
# anterior (matinal 19/08) tinha saido exit 0 em 1m54s sem nenhum submit,
# porque a linha antiga do runner tirava o shell da skill (ver A3 em
# run_claude_routine.ps1). O relancamento agora e reverificado do mesmo jeito
# e alerta se nao entregou, seja qual for o exit code.
param(
    [Parameter(Mandatory)]
    [ValidateSet('vixradar-noturno', 'vixradar-matinal')]
    [string]$RoutineId,
    [string]$WorkerUrl = 'https://api.vixradar.com/',
    # Testabilidade (scripts/test-retry-janela.ps1): aponta o relancamento para
    # um stub em vez do runner real. Nunca usado em producao (default = runner
    # real do repo).
    [string]$RunnerOverride,
    [string]$LogDirOverride,
    # Testabilidade: nao faz o POST real de alerta (so loga o que teria sido
    # enviado). Nunca usado em producao.
    [switch]$SemAlerta
)

$ErrorActionPreference = 'Continue'

$VixRoot     = 'E:\Diretorio\Claude\Monitoramento de Credito'
$Runner      = if ($RunnerOverride) { $RunnerOverride } else { Join-Path $VixRoot 'scripts\run_claude_routine.ps1' }
$LogDir      = if ($LogDirOverride) { $LogDirOverride } else { Join-Path $VixRoot 'logs\routines' }
$LibDir      = Join-Path $VixRoot 'scripts\lib'
$Watchdog    = Join-Path $LibDir 'vixradar-watchdog.ps1'
$ClaudeAuth  = Join-Path $LibDir 'vixradar-claude-auth.ps1'
$DateTag     = Get-Date -Format 'yyyyMMdd'
$RotLog      = Join-Path $LogDir ($RoutineId + '_' + $DateTag + '.log')
$RetLog      = Join-Path $LogDir ('retry-' + $RoutineId + '_' + $DateTag + '.log')
# Janela real da rotina (BRT), mesma regua do SLA de painel_fresco no Worker
# (PAINEL_SLA): noturno seg-sex 18:00, matinal diaria 10:00.
$JanelaHora  = if ($RoutineId -eq 'vixradar-matinal') { 10 } else { 18 }
$MinimoLedger = if ($RoutineId -eq 'vixradar-matinal') { 12 } else { 90 }

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $RetLog -Value $line -Encoding UTF8
    Write-Host $line
}

if (Test-Path -LiteralPath $Watchdog) { . $Watchdog } else { Write-Log "AVISO: $Watchdog ausente" }
$temClaudeAuth = $false
if (Test-Path -LiteralPath $ClaudeAuth) {
    try { . $ClaudeAuth; $temClaudeAuth = $true } catch { Write-Log "AVISO: dot-source $ClaudeAuth falhou: $_" }
} else { Write-Log "AVISO: $ClaudeAuth ausente" }

function Send-VixRetryAlerta([string]$Motivo) {
    if ($SemAlerta) { Write-Log ('ALERTA (SemAlerta, POST suprimido): ' + $Motivo); return }
    $rk = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if (-not $rk) { $rk = $env:ROUTINE_API_KEY }
    if (-not $rk) { Write-Log 'AVISO: ROUTINE_API_KEY ausente do escopo User, alerta nao enviado'; return }
    if ($temClaudeAuth -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
        $ok = Send-VixRoutineAlert -Rotina ('retry-' + $RoutineId) -Motivo $Motivo -RoutineKey $rk -WorkerUrl $WorkerUrl
        if ($ok) { Write-Log 'ALERTA ROTINA enviado (dedup do Worker limita a 1/dia por rotina)' }
        return
    }
    # Fallback sem a lib de auth (POST direto, mesmo formato de sempre).
    try {
        $p = @{ action = 'notificar_rotina'; routine_key = $rk; rotina = ('retry-' + $RoutineId); motivo = $Motivo }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($p | ConvertTo-Json -Compress))
        Invoke-WebRequest -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30 -UseBasicParsing | Out-Null
        Write-Log 'ALERTA ROTINA enviado (dedup do Worker limita a 1/dia por rotina)'
    } catch {
        Write-Log ('AVISO: falha ao alertar rotina: ' + $_.Exception.Message)
    }
}

# WATCHDOG-NAOINICIOU1 (auditoria 2026-08-29): rotina que nao iniciou era
# silencio total (exit 0), e o gap de 28/08 (app do Claude Desktop fechado)
# passou sem alerta nenhum. O retry roda DEPOIS da janela da rotina, entao log
# ausente no horario do retry significa sessao que nao disparou. Vira falha +
# alerta via action=notificar_rotina (mesmo canal do watch-vixradar-health.ps1,
# ROTINAGAP1), com dedup do Worker por rotina/dia (NOTIFYRL1). Sem relancamento:
# app fechado nao vai entregar de novo; o alerta e a acao correta.
if (-not (Test-Path $RotLog)) {
    $motivo = 'Rotina ' + $RoutineId + ' nao deixou log ate ' + (Get-Date -Format 'HH:mm') + ' BRT (janela do dia ja passou). Sessao Claude Desktop pode nao ter disparado (app fechado ou cron perdido).'
    Write-Log "SEM LOG: $RotLog nao existe, rotina nao iniciou. ALERTA."
    Send-VixRetryAlerta $motivo
    exit 1
}

# INCIDENTE-FRESHNESS2 (A4/H, 03/09/2026): FIM:/RUNNER_FIM: e o ledger OK| so
# contam dentro da JANELA REAL da rotina do dia (Test-VixLedgerEntregueNaJanela,
# lib/vixradar-watchdog.ps1, compartilhada com monitor-tasks.ps1). Substitui os
# dois parsers antigos (regex de contador no FIM: + fallback por nome unico no
# ledger): a causa raiz de ambos continua coberta (FIMREAL cobria formato
# variavel do FIM:, ROTINACEGA2 cobria dia entregue sem linha de fecho), mas
# agora nenhuma linha fora da janela agendada conta como prova de entrega -
# sem isto, uma dry-run de madrugada ou uma recuperacao manual anterior no
# MESMO arquivo de log podia mascarar a falta de entrega da execucao real.
$conteudo = Get-Content $RotLog -Raw -Encoding UTF8
$dataLog = [datetime]::ParseExact($DateTag, 'yyyyMMdd', $null)
$julgamento = Test-VixLedgerEntregueNaJanela -Conteudo $conteudo -DataLog $dataLog -JanelaHora $JanelaHora -MinimoLedger $MinimoLedger
if ($julgamento.Entregue) {
    Write-Log ("OK: entrega confirmada dentro da janela (ledger=" + $julgamento.LedgerNaJanela + "/" + $MinimoLedger + " fim_na_janela=" + $julgamento.FimComContagemSuficiente + "). Nada a fazer.")
    exit 0
}
Write-Log ("Ledger na janela (>= " + $JanelaHora.ToString('00') + ":00 BRT) tem " + $julgamento.LedgerNaJanela + " emissor(es) distinto(s), minimo " + $MinimoLedger + ", fim_na_janela=" + $julgamento.FimComContagemSuficiente + " - nao confirma entrega.")

# Execucao Desktop pode estar viva e lenta. Se o log mexeu nos ultimos 15 min,
# a rotina esta em andamento agora. O lock da skill decidiria no Passo 0, mas
# nao gastamos um run inteiro para descobrir.
$idadeMin = ((Get-Date) - (Get-Item $RotLog).LastWriteTime).TotalMinutes
if ($idadeMin -lt 15) {
    Write-Log "VIVA: log atualizado ha $([int]$idadeMin) min, execucao em andamento. Pulo."
    exit 0
}

Write-Log "SEM ENTREGA: log parado ha $([int]$idadeMin) min. Relancando $RoutineId via claude CLI."
# Nao passa -TaskInicio pela linha de comando de proposito: DateTime
# serializado/reparseado atraves de processo filho e sensivel a locale (esta
# maquina usa pt-BR). O runner usa o proprio default (inicio dele mesmo), que
# ja cobre o caso real - o trabalho deste script antes daqui e de segundos,
# nao minutos, entao a diferenca contra o inicio real da task e desprezivel
# perto do teto de 220 min (INCIDENTE-FRESHNESS2, A3).
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -RoutineId $RoutineId
$exit = $LASTEXITCODE
Write-Log "RETRY EXIT: $exit"

# INCIDENTE-FRESHNESS2 (A4, condicao do COO): exit code do relancamento NAO
# prova entrega (19/08: matinal saiu exit 0 sem submit nenhum, causa raiz agora
# corrigida em A3, mas o julgamento por exit code continuaria fragil a
# qualquer defeito futuro do mesmo tipo). Reconfere pelo MESMO ledger/janela
# de antes do relancamento, e alerta sempre que nao entregou - mesmo com
# exit 0.
$conteudoPos = Get-Content $RotLog -Raw -Encoding UTF8
$julgamentoPos = Test-VixLedgerEntregueNaJanela -Conteudo $conteudoPos -DataLog $dataLog -JanelaHora $JanelaHora -MinimoLedger $MinimoLedger
if ($julgamentoPos.Entregue) {
    Write-Log ("ENTREGA CONFIRMADA apos relancamento (ledger=" + $julgamentoPos.LedgerNaJanela + "/" + $MinimoLedger + " fim_na_janela=" + $julgamentoPos.FimComContagemSuficiente + ", exit=" + $exit + ").")
    exit 0
}
$ultimaLinha = (($conteudoPos -split "`r?`n") | Where-Object { $_ -match 'ERRO|RUNNER_FIM|ABORTANDO' } | Select-Object -Last 1)
$motivoFalha = 'Relancamento de ' + $RoutineId + ' nao confirmou entrega (exit=' + $exit + ', ledger=' + $julgamentoPos.LedgerNaJanela + '/' + $MinimoLedger + '). Ultima linha relevante: ' + $ultimaLinha
Write-Log ('SEM ENTREGA APOS RELANCAMENTO: ' + $motivoFalha)
Send-VixRetryAlerta $motivoFalha
exit 1
