# test-locks-overlap.ps1 - prova de duas pontas do item 3 da Fase 4 (MOTOR1).
# ASCII puro (parse no powershell.exe 5.1). Nao submete nada ao Worker.
#
# O que este teste prova, com saida crua:
#   A. mutex proprio da rotina ocupado  -> runner sai ABORT em 0 token
#   B. lock de arquivo do dia tocado agora -> runner sai ABORT em 0 token
#   C. mutex da sentinela ocupado + lock fresco -> runner loga AGUARDANDO sentinela,
#      espera, loga "sentinela livre apos Ns" e so entao bate no lock (0 token)
#   D. lock de sessao tocado ha menos de 30 min -> sentinela sai ABORT_COLISAO
#   E. lock sem toque ha 45 min -> sentinela loga LOCK_ABANDONADO e segue
#   F. (-ComTokens) lock envelhecido -> runner loga LOCK_ABANDONADO, depois LOCK_OK
#      ANTES de PLANO, e conclui um dry-run de 1 emissor
#
# Os casos A a E nao gastam token: o runner aborta antes da inicializacao de auth e a
# sentinela aborta antes do portao de rede. O caso F custa um lote LIGHT de 1 emissor e
# fica atras de -ComTokens de proposito.
#
# O teste NUNCA deixa lock para tras: cada caso limpa no finally e o passo final reprova
# se sobrar arquivo .lock do dia. Um lock esquecido cegaria a sentinela por 30 min e
# abortaria a noturna real.

param(
    [switch]$ComTokens
)

$ErrorActionPreference = 'Continue'

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptsDir  = Join-Path $ProjectRoot 'scripts'
$LogDir      = Join-Path $ProjectRoot 'logs\routines'
$DateTag     = Get-Date -Format 'yyyyMMdd'
$Runner      = Join-Path $ScriptsDir 'run_vixradar_varredura.ps1'
$Sentinela   = Join-Path $ScriptsDir 'run_vixradar_sentinela.ps1'
$LockNoturno = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '.lock')
$LogNoturno  = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '.log')
$LogSentinela = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')

$script:Falhas = 0
$script:Casos  = 0

function Write-Cabecalho([string]$Titulo) {
    Write-Output ''
    Write-Output ('=== ' + $Titulo + ' ===')
}

function Get-LogPos([string]$Path) {
    # Numero de linhas do log agora. Chamar ANTES de disparar a rotina.
    if (-not (Test-Path $Path)) { return 0 }
    return @(Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue).Count
}

function Get-LogTail([string]$Path, [int]$DesdeLinha) {
    # Devolve as linhas anexadas a partir de $DesdeLinha (leitura posicional, sem corrida
    # de relogio: o log tem resolucao de 1 s e o Get-Date tem fracao, comparar por tempo
    # derrubava a linha escrita no mesmo segundo do disparo e reprovava assert boa).
    if (-not (Test-Path $Path)) { return @() }
    $linhas = @(Get-Content $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    $saida = New-Object System.Collections.Generic.List[string]
    for ($i = $DesdeLinha; $i -lt $linhas.Count; $i++) { $saida.Add($linhas[$i]) }
    return $saida.ToArray()
}

function Assert-Contem([string[]]$Linhas, [string]$Padrao, [string]$Rotulo) {
    $script:Casos++
    $achou = $false
    foreach ($l in $Linhas) { if ($l -match $Padrao) { $achou = $true; break } }
    if ($achou) {
        Write-Output ('  OK  ' + $Rotulo)
    } else {
        Write-Output ('  FALHA  ' + $Rotulo + ' (padrao nao encontrado: ' + $Padrao + ')')
        $script:Falhas++
    }
    return $achou
}

function Assert-NaoContem([string[]]$Linhas, [string]$Padrao, [string]$Rotulo) {
    $script:Casos++
    $achou = $false
    foreach ($l in $Linhas) { if ($l -match $Padrao) { $achou = $true; break } }
    if (-not $achou) {
        Write-Output ('  OK  ' + $Rotulo)
    } else {
        Write-Output ('  FALHA  ' + $Rotulo + ' (padrao apareceu e nao devia: ' + $Padrao + ')')
        $script:Falhas++
    }
    return (-not $achou)
}

function Start-SeguraMutex([string]$Nome, [int]$Segundos) {
    # Job em processo proprio segurando o mutex nomeado. Mutex Global e visivel entre
    # processos da mesma sessao, que e exatamente o cenario real (Task Scheduler + sessao).
    return Start-Job -ScriptBlock {
        param($n, $s)
        $m = New-Object System.Threading.Mutex($false, $n)
        $pego = $m.WaitOne(5000)
        Start-Sleep -Seconds $s
        if ($pego) { $m.ReleaseMutex() }
        $m.Dispose()
    } -ArgumentList $Nome, $Segundos
}

function Wait-MutexOcupado([string]$Nome, [int]$TimeoutSeg) {
    # Espera o job realmente pegar o mutex antes de disparar o runner (sem isto o teste
    # vira corrida e da falso negativo).
    $fim = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $fim) {
        $m = New-Object System.Threading.Mutex($false, $Nome)
        $livre = $m.WaitOne(0)
        if ($livre) { $m.ReleaseMutex() }
        $m.Dispose()
        if (-not $livre) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Remove-LockDeTeste {
    if (Test-Path $LockNoturno) { Remove-Item $LockNoturno -Force -ErrorAction SilentlyContinue }
}

function New-LockDeTeste([int]$IdadeMin) {
    "source=test-locks-overlap.ps1`npid=$PID`nidade_simulada_min=$IdadeMin" |
        Set-Content -Path $LockNoturno -Encoding UTF8
    if ($IdadeMin -gt 0) {
        (Get-Item $LockNoturno).LastWriteTime = (Get-Date).AddMinutes(-1 * $IdadeMin)
    }
}

Write-Output ('test-locks-overlap.ps1  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ComTokens=' + $ComTokens)
Write-Output ('runner=' + $Runner)
Write-Output ('lock alvo=' + $LockNoturno)

if (Test-Path $LockNoturno) {
    Write-Output 'ABORTADO: ja existe lock do dia para a noturna. Uma execucao real pode estar viva.'
    exit 2
}

# --- Caso A: mutex proprio ocupado -----------------------------------------
Write-Cabecalho 'CASO A - mutex Global\vixradar-noturno-v2 ocupado por outro processo'
$jobA = Start-SeguraMutex 'Global\vixradar-noturno-v2' 45
if (-not (Wait-MutexOcupado 'Global\vixradar-noturno-v2' 20)) {
    Write-Output '  FALHA  o job auxiliar nao conseguiu segurar o mutex'
    $script:Falhas++
} else {
    $t0 = Get-LogPos $LogNoturno
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno -DryRun -MaxEmissores 1 | Out-Null
    $exitA = $LASTEXITCODE
    $tailA = Get-LogTail $LogNoturno $t0
    Write-Output ('  exit=' + $exitA)
    foreach ($l in $tailA) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailA 'ABORT: outra instancia da noturno ja esta em execucao \(mutex ocupado\)' 'runner abortou pelo mutex proprio' | Out-Null
    Assert-NaoContem $tailA 'LOCK_OK|INICIO:' 'nao chegou a criar lock nem a iniciar (0 token)' | Out-Null
    $script:Casos++
    if ($exitA -eq 0) { Write-Output '  OK  exit 0 (abort limpo, nao e erro de task)' } else { Write-Output ('  FALHA  exit ' + $exitA + ' (esperado 0)'); $script:Falhas++ }
}
Stop-Job $jobA -ErrorAction SilentlyContinue | Out-Null
Remove-Job $jobA -Force -ErrorAction SilentlyContinue | Out-Null

# --- Caso B: lock do dia tocado agora --------------------------------------
Write-Cabecalho 'CASO B - lock do dia tocado agora (outra execucao viva)'
try {
    New-LockDeTeste 0
    $t0 = Get-LogPos $LogNoturno
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno -DryRun -MaxEmissores 1 | Out-Null
    $exitB = $LASTEXITCODE
    $tailB = Get-LogTail $LogNoturno $t0
    Write-Output ('  exit=' + $exitB)
    foreach ($l in $tailB) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailB 'ABORT: lock vixradar-noturno_.*\.lock tocado ha .* min \(outra execucao viva\)' 'runner abortou pelo lock vivo' | Out-Null
    Assert-NaoContem $tailB 'LOCK_OK' 'nao sobrescreveu o lock alheio' | Out-Null
} finally {
    Remove-LockDeTeste
}

# --- Caso C: mutex da sentinela ocupado ------------------------------------
Write-Cabecalho 'CASO C - mutex da sentinela ocupado: runner espera e so entao segue'
$jobC = Start-SeguraMutex 'Global\vixradar-sentinela-v1' 40
if (-not (Wait-MutexOcupado 'Global\vixradar-sentinela-v1' 20)) {
    Write-Output '  FALHA  o job auxiliar nao conseguiu segurar o mutex da sentinela'
    $script:Falhas++
    Stop-Job $jobC -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $jobC -Force -ErrorAction SilentlyContinue | Out-Null
} else {
    try {
        # Lock fresco de proposito: depois de liberar a sentinela o runner tem que parar
        # no lock, provando a ORDEM (espera de mutex primeiro, lock depois) sem gastar token.
        New-LockDeTeste 0
        $t0 = Get-LogPos $LogNoturno
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno -DryRun -MaxEmissores 1 | Out-Null
        $exitC = $LASTEXITCODE
        $tailC = Get-LogTail $LogNoturno $t0
        Write-Output ('  exit=' + $exitC)
        foreach ($l in $tailC) { Write-Output ('  | ' + $l) }
        Assert-Contem $tailC 'AGUARDANDO sentinela: mutex Global\\vixradar-sentinela-v1 ocupado' 'runner esperou pela sentinela' | Out-Null
        Assert-Contem $tailC 'sentinela livre apos \d+s' 'runner registrou a liberacao' | Out-Null
        Assert-Contem $tailC 'ABORT: lock vixradar-noturno_.*\.lock tocado ha' 'so depois avaliou o lock (ordem correta)' | Out-Null
    } finally {
        Remove-LockDeTeste
        Stop-Job $jobC -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $jobC -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- Caso D: sentinela contra lock vivo ------------------------------------
Write-Cabecalho 'CASO D - sentinela com lock de sessao tocado ha menos de 30 min'
try {
    New-LockDeTeste 5
    $t0 = Get-LogPos $LogSentinela
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Sentinela | Out-Null
    $exitD = $LASTEXITCODE
    $tailD = Get-LogTail $LogSentinela $t0
    Write-Output ('  exit=' + $exitD)
    foreach ($l in $tailD) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailD 'ABORT_COLISAO: lock de sessao vixradar-noturno ativo ha' 'sentinela recuou pelo lock vivo' | Out-Null
    Assert-Contem $tailD 'FIM: sentinela sem gatilho. tokens=0' 'saiu em 0 token' | Out-Null
} finally {
    Remove-LockDeTeste
}

# --- Caso E: sentinela contra lock abandonado ------------------------------
Write-Cabecalho 'CASO E - sentinela com lock sem toque ha 45 min (crash/reboot)'
try {
    New-LockDeTeste 45
    $t0 = Get-LogPos $LogSentinela
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Sentinela | Out-Null
    $exitE = $LASTEXITCODE
    $tailE = Get-LogTail $LogSentinela $t0
    Write-Output ('  exit=' + $exitE)
    foreach ($l in $tailE) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailE 'LOCK_ABANDONADO: vixradar-noturno sem toque ha' 'sentinela ignorou o lock abandonado' | Out-Null
    Assert-NaoContem $tailE 'ABORT_COLISAO: lock de sessao' 'nao abortou por colisao' | Out-Null
} finally {
    Remove-LockDeTeste
}

# --- Caso F: runner assume lock abandonado (custa 1 lote) ------------------
if ($ComTokens) {
    Write-Cabecalho 'CASO F - runner assume lock abandonado e cria o proprio (LOCK_OK antes de PLANO)'
    try {
        New-LockDeTeste 45
        $t0 = Get-LogPos $LogNoturno
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno -DryRun -MaxEmissores 1 | Out-Null
        $exitF = $LASTEXITCODE
        $tailF = Get-LogTail $LogNoturno $t0
        Write-Output ('  exit=' + $exitF)
        foreach ($l in $tailF) { Write-Output ('  | ' + $l) }
        Assert-Contem $tailF 'LOCK_ABANDONADO: vixradar-noturno_.*\.lock sem toque ha' 'runner assumiu o lock abandonado' | Out-Null
        Assert-Contem $tailF 'LOCK_OK: vixradar-noturno_.*\.lock criado' 'runner criou o proprio lock' | Out-Null
        # Ordem: LOCK_OK tem que vir ANTES da primeira linha de plano.
        $idxLock = -1; $idxPlano = -1
        for ($i = 0; $i -lt $tailF.Count; $i++) {
            if ($idxLock -lt 0 -and $tailF[$i] -match 'LOCK_OK:') { $idxLock = $i }
            if ($idxPlano -lt 0 -and $tailF[$i] -match 'Plano \{|PLANO') { $idxPlano = $i }
        }
        $script:Casos++
        if ($idxLock -ge 0 -and $idxPlano -ge 0 -and $idxLock -lt $idxPlano) {
            Write-Output ('  OK  LOCK_OK (linha ' + $idxLock + ') antes de PLANO (linha ' + $idxPlano + ')')
        } else {
            Write-Output ('  FALHA  ordem LOCK_OK/PLANO (lock=' + $idxLock + ' plano=' + $idxPlano + ')')
            $script:Falhas++
        }
    } finally {
        Remove-LockDeTeste
    }
} else {
    Write-Cabecalho 'CASO F - pulado (rode com -ComTokens; custa um lote LIGHT de 1 emissor)'
}

# --- Higiene final ---------------------------------------------------------
Write-Cabecalho 'HIGIENE - nenhum lock do dia pode sobrar'
$script:Casos++
if (Test-Path $LockNoturno) {
    Write-Output ('  FALHA  sobrou ' + $LockNoturno)
    $script:Falhas++
} else {
    Write-Output '  OK  nenhum lock do dia para a noturna'
}

Write-Output ''
Write-Output ('RESULTADO: ' + ($script:Casos - $script:Falhas) + '/' + $script:Casos + ' asserts OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
