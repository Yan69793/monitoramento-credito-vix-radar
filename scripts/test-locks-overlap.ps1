# test-locks-overlap.ps1 - prova de duas pontas do item 3 da Fase 4 (MOTOR1).
# ASCII puro (parse no powershell.exe 5.1). Nao submete nada ao Worker.
#
# O que este teste prova, com saida crua:
#   A. mutex proprio da rotina ocupado  -> execucao real sai ABORT em 0 token
#   B. lock de arquivo do dia tocado agora -> execucao real sai ABORT em 0 token
#   C. mutex da sentinela ocupado + lock fresco -> execucao real loga AGUARDANDO sentinela,
#      espera, loga "sentinela livre apos Ns" e so entao bate no lock (0 token)
#   D. lock de sessao tocado ha menos de 30 min -> sentinela sai ABORT_COLISAO
#   E. lock sem toque ha 45 min -> sentinela loga LOCK_ABANDONADO e segue
#   F. (-ComTokens) lock envelhecido -> runner loga LOCK_ABANDONADO, depois LOCK_OK
#      ANTES de PLANO, e conclui um dry-run de 1 emissor
#   G. probe (-DryRun) com lock fresco no nome DELE (sufixo _dryrun_<PID>): aborta no proprio
#      lock, nao cria nem toca o lock real, nao escreve uma linha no log do dia (artefatos
#      separados), e o nome do probe nunca e igual ao nome do real.
#   H. lock REAL fresco + probe: o probe consulta o lock real ANTES do proprio e sai ABORT no
#      lock real, sem boot de provider, sem rede e sem token (regra do operador, 10/09).
#   I. lock de probe fresco + execucao REAL: a execucao real ignora o lock de probe,
#      prossegue, cria o PROPRIO lock (LOCK_OK no leaf real) e so para no guarda seguinte,
#      antes do boot do provider (sem rede e sem token). O corte deterministico aqui e o
#      -SimularTokenVencido, que sobe por um caminho de aborto desenhado para nao submeter.
#
# Os casos A a E nao gastam token: o runner aborta antes do boot do provider e a sentinela
# aborta antes do portao de rede. O caso F custa um lote LIGHT de 1 emissor e fica atras de
# -ComTokens de proposito. Os casos G, H e I tambem nao gastam token: os dois primeiros param
# no lock e o terceiro para no guarda do -SimularTokenVencido, todos antes de qualquer rede.
#
# A partir de 10/09 (DRYRUN-PROBE1) o probe -DryRun usa log e lock proprios
# (vixradar-<rotina>_<data>_dryrun_<PID>.log/.lock) e consulta o lock real antes de executar,
# entao os casos A, B e C rodam a execucao REAL (sem -DryRun), que continua abortando antes de
# qualquer chamada de rede em cada guarda.
#
# O teste NUNCA deixa lock para tras: cada caso limpa no finally e o passo final reprova
# se sobrar arquivo .lock do dia. Um lock esquecido cegaria a sentinela por 30 min e
# abortaria a noturna real.
#
# ZERO RASTRO NO LOG REAL (10/09): os casos que rodam processo real (A, B, C, I no motor; D e E
# na sentinela) escrevem no log do DIA. A suite roda dentro de um try/finally que restaura byte a
# byte o log do dia do noturno, o log do dia da sentinela, o lock do dia (conteudo e mtime) e
# apaga os transcripts criados pela propria suite, e um passo final prova a equivalencia com o
# estado pre-teste (hash SHA256). Casos de probe (-DryRun) escrevem em log proprio do PID.

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

# DRYRUN-PROBE1 (10/09): o probe -DryRun escreve log e lock com o PID no nome. O teste descobre
# o PID do filho por Start-Process -PassThru e le exatamente os artefatos dele, sem tocar no log
# nem no lock da execucao real.
function Get-LogDoProbe([int]$ProcId) { return (Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '_dryrun_' + $ProcId + '.log')) }
function Get-LockDoProbe([int]$ProcId) { return (Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '_dryrun_' + $ProcId + '.lock')) }

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
    [void]$achou
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
    [void](-not $achou)
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
    # D1 (12/09): Get-VixLockState exige pid vivo E inicio_utc igual ao StartTime do processo.
    # Sem o campo, o lock de teste vira LOCK_ORFAO_INICIO_INVALIDO, o runner prossegue e apaga
    # o lock alheio - que e exatamente o que este caso prova que nao pode acontecer. O lock
    # real escreve o mesmo campo, entao a fixture tem que reproduzir o formato real.
    $inicioUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    "source=test-locks-overlap.ps1`npid=$PID`ninicio_utc=$inicioUtc`nidade_simulada_min=$IdadeMin" |
        Set-Content -Path $LockNoturno -Encoding UTF8
    if ($IdadeMin -gt 0) {
        (Get-Item $LockNoturno).LastWriteTime = (Get-Date).AddMinutes(-1 * $IdadeMin)
    }
}

# --- ISOLAMENTO DOS CASOS REAIS (10/09) ------------------------------------
# Os casos A, B, C e I rodam a execucao REAL, e os casos D e E rodam a sentinela real: os dois
# motores escrevem no log do DIA. Nenhum caso deste teste pode deixar rastro nesses arquivos.
# O snapshot guarda bytes, mtime e hash do log do dia (noturno e sentinela) e do lock do dia,
# mais a lista de transcripts que ja existiam; o finally da suite restaura tudo (inclusive
# quando um caso falha) e o passo de verificacao prova a equivalencia byte a byte. Casos de
# probe (-DryRun) nao entram aqui: eles escrevem em log proprio ja carimbado com o PID.
$LogNoturnoDia   = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '.log')
$LogSentinelaDia = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')
$GlobsTranscript = @('noturno_transcript_' + $DateTag + '_*.txt', 'sentinela_transcript_' + $DateTag + '_*.txt')

function Get-HashArquivo([string]$Path) {
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $fs = [System.IO.File]::OpenRead($Path)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($fs))) } finally { $fs.Dispose(); $sha.Dispose() }
    } catch { return '' }
}

function Get-NomesTranscript {
    $nomes = @()
    foreach ($g in $GlobsTranscript) {
        $nomes += @(Get-ChildItem $LogDir -Filter $g -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    return $nomes
}

function New-SnapshotDia {
    $snap = @{ Arquivos = @(); Transcripts = (Get-NomesTranscript) }
    foreach ($p in @($LogNoturnoDia, $LogSentinelaDia, $LockNoturno)) {
        $item = @{ Path = $p; Existe = (Test-Path $p); Bytes = $null; Mtime = $null; Hash = '' }
        if ($item.Existe) {
            $item.Bytes = [System.IO.File]::ReadAllBytes($p)
            $item.Mtime = (Get-Item $p).LastWriteTime
            $item.Hash  = Get-HashArquivo $p
        }
        $snap.Arquivos += , $item
    }
    return $snap
}

function Restore-SnapshotDia($snap) {
    foreach ($item in $snap.Arquivos) {
        if ($item.Existe) {
            try {
                [System.IO.File]::WriteAllBytes($item.Path, $item.Bytes)
                try { (Get-Item $item.Path).LastWriteTime = $item.Mtime } catch { }
            } catch { }
        } elseif (Test-Path $item.Path) {
            Remove-Item $item.Path -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($g in $GlobsTranscript) {
        foreach ($f in @(Get-ChildItem $LogDir -Filter $g -File -ErrorAction SilentlyContinue)) {
            if ($snap.Transcripts -notcontains $f.Name) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Test-RestauracaoDia($snap) {
    $problemas = @()
    foreach ($item in $snap.Arquivos) {
        $folha = Split-Path $item.Path -Leaf
        $existe = Test-Path $item.Path
        if ($item.Existe -ne $existe) {
            $problemas += ($folha + ': existencia mudou (antes=' + $item.Existe + ' agora=' + $existe + ')')
            continue
        }
        if ($item.Existe -and ((Get-HashArquivo $item.Path) -ne $item.Hash)) {
            $problemas += ($folha + ': conteudo nao voltou identico')
        }
    }
    $novos = @()
    foreach ($n in (Get-NomesTranscript)) { if ($snap.Transcripts -notcontains $n) { $novos += $n } }
    if ($novos.Count -gt 0) { $problemas += ('transcripts novos: ' + ($novos -join ', ')) }
    $script:Casos++
    if ($problemas.Count -eq 0) {
        Write-Output '  OK  artefatos reais do dia restaurados: log noturno, log sentinela e lock identicos ao pre-teste, zero transcript novo'
    } else {
        Write-Output ('  FALHA  restauracao incompleta: ' + ($problemas -join ' | '))
        $script:Falhas++
    }
}

Write-Output ('test-locks-overlap.ps1  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ComTokens=' + $ComTokens)
Write-Output ('runner=' + $Runner)
Write-Output ('lock alvo=' + $LockNoturno)

if (Test-Path $LockNoturno) {
    Write-Output 'ABORTADO: ja existe lock do dia para a noturna. Uma execucao real pode estar viva.'
    exit 2
}

# Feriado B3: os casos A, B e C rodam a execucao REAL, e nesse dia o motor sai no SKIP de
# feriado ANTES dos guardas de mutex/lock (linha ~700 do motor). Rodar aqui daria 3 falhas
# falsas. A lista e lida do proprio fonte do motor, sem copia paralela para divergir.
$__blocoFeriados = [regex]::Match((Get-Content -Raw $Runner), "(?s)\`$feriados = @\((.*?)\)").Groups[1].Value
$__feriadosMotor = @([regex]::Matches($__blocoFeriados, '\d{4}-\d{2}-\d{2}') | ForEach-Object { $_.Value })
if ($__feriadosMotor -contains (Get-Date).ToString('yyyy-MM-dd')) {
    Write-Output ('PULADO: hoje e feriado B3 no motor (' + $__feriadosMotor.Count + ' datas lidas de ' + (Split-Path $Runner -Leaf) + '). A execucao real sai no SKIP antes dos guardas.')
    exit 0
}

# ISOLAMENTO (10/09): daqui ate o finally no fim do arquivo, os casos rodam processos REAIS
# (motor e sentinela) que escrevem no log do dia. O snapshot e tirado ANTES do primeiro caso e
# o finally restaura tudo, inclusive se um caso falhar. A indentacao dos casos NAO foi mexida ao
# entrar neste try de proposito, para o diff ficar legivel; o PowerShell nao exige indentacao.
$snapDia = New-SnapshotDia
try {

# --- Caso A: mutex proprio ocupado -----------------------------------------
Write-Cabecalho 'CASO A - mutex Global\vixradar-noturno-v2 ocupado por outro processo'
$jobA = Start-SeguraMutex 'Global\vixradar-noturno-v2' 45
if (-not (Wait-MutexOcupado 'Global\vixradar-noturno-v2' 20)) {
    Write-Output '  FALHA  o job auxiliar nao conseguiu segurar o mutex'
    $script:Falhas++
} else {
    $t0 = Get-LogPos $LogNoturno
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno | Out-Null
    $exitA = $LASTEXITCODE
    $tailA = Get-LogTail $LogNoturno $t0
    Write-Output ('  exit=' + $exitA)
    foreach ($l in $tailA) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailA 'ABORT: outra instancia da noturno ja esta em execucao \(mutex ocupado\)' 'runner abortou pelo mutex proprio'
    Assert-NaoContem $tailA 'LOCK_OK|INICIO:' 'nao chegou a criar lock nem a iniciar (0 token)'
    $script:Casos++
    if ($exitA -eq 0) { Write-Output '  OK  exit 0 (abort limpo, nao e erro de task)' } else { Write-Output ('  FALHA  exit ' + $exitA + ' (esperado 0)'); $script:Falhas++ }
}
Stop-Job $jobA -ErrorAction SilentlyContinue | Out-Null
Remove-Job $jobA -Force -ErrorAction SilentlyContinue | Out-Null

# --- Caso B: lock do dia tocado agora (execucao real) ----------------------
Write-Cabecalho 'CASO B - lock do dia tocado agora: execucao REAL aborta e nao apaga o lock alheio'
try {
    New-LockDeTeste 0
    $t0 = Get-LogPos $LogNoturno
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno | Out-Null
    $exitB = $LASTEXITCODE
    $tailB = Get-LogTail $LogNoturno $t0
    Write-Output ('  exit=' + $exitB)
    foreach ($l in $tailB) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailB 'ABORT: lock vixradar-noturno_.*\.lock pid=\d+ LOCK_VIVO \(outra execucao viva\)' 'execucao real abortou pelo lock vivo'
    Assert-NaoContem $tailB 'LOCK_OK' 'nao sobrescreveu o lock alheio'
    $script:Casos++
    if (Test-Path $LockNoturno) {
        Write-Output '  OK  lock alheio continua no lugar (execucao real nao apaga lock vivo de terceiro)'
    } else {
        Write-Output '  FALHA  a execucao real apagou o lock alheio'
        $script:Falhas++
    }
} finally {
    Remove-LockDeTeste
}

# --- Caso C: mutex da sentinela ocupado ------------------------------------
Write-Cabecalho 'CASO C - mutex da sentinela ocupado: execucao real espera e so entao segue'
$jobC = Start-SeguraMutex 'Global\vixradar-sentinela-v1' 40
if (-not (Wait-MutexOcupado 'Global\vixradar-sentinela-v1' 20)) {
    Write-Output '  FALHA  o job auxiliar nao conseguiu segurar o mutex da sentinela'
    $script:Falhas++
    Stop-Job $jobC -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $jobC -Force -ErrorAction SilentlyContinue | Out-Null
} else {
    try {
        # Lock fresco de proposito: depois de liberar a sentinela a execucao real tem que parar
        # no lock, provando a ORDEM (espera de mutex primeiro, lock depois) sem gastar token.
        New-LockDeTeste 0
        $t0 = Get-LogPos $LogNoturno
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno | Out-Null
        $exitC = $LASTEXITCODE
        $tailC = Get-LogTail $LogNoturno $t0
        Write-Output ('  exit=' + $exitC)
        foreach ($l in $tailC) { Write-Output ('  | ' + $l) }
        Assert-Contem $tailC 'AGUARDANDO sentinela: mutex Global\\vixradar-sentinela-v1 ocupado' 'runner esperou pela sentinela'
        Assert-Contem $tailC 'sentinela livre apos \d+s' 'runner registrou a liberacao'
        Assert-Contem $tailC 'ABORT: lock vixradar-noturno_.*\.lock pid=\d+ LOCK_VIVO' 'so depois avaliou o lock (ordem correta)'
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
    Assert-Contem $tailD 'ABORT_COLISAO: lock de sessao vixradar-noturno ativo ha' 'sentinela recuou pelo lock vivo'
    Assert-Contem $tailD 'FIM: sentinela sem gatilho. tokens=0' 'saiu em 0 token'
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
    Assert-Contem $tailE 'LOCK_ABANDONADO: vixradar-noturno sem toque ha' 'sentinela ignorou o lock abandonado'
    Assert-NaoContem $tailE 'ABORT_COLISAO: lock de sessao' 'nao abortou por colisao'
} finally {
    Remove-LockDeTeste
}

# --- Caso F: probe assume o proprio lock (custa 1 lote) --------------------
if ($ComTokens) {
    Write-Cabecalho 'CASO F - probe com lock real envelhecido: cria o proprio lock e nao consome o real'
    $lockProbeF = $null
    $logProbeF  = $null
    try {
        New-LockDeTeste 45
        $realAntesF = (Get-Item $LockNoturno).LastWriteTime
        $procF = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Runner + '"'), '-Rotina', 'noturno', '-DryRun', '-MaxEmissores', '1') -PassThru -WindowStyle Hidden
        $logProbeF  = Get-LogDoProbe $procF.Id
        $lockProbeF = Get-LockDoProbe $procF.Id
        $procF.WaitForExit(900000) | Out-Null
        $exitF = -1; try { $exitF = $procF.ExitCode } catch { }
        $tailF = Get-LogTail $logProbeF 0
        Write-Output ('  exit=' + $exitF + '  probe_pid=' + $procF.Id)
        foreach ($l in $tailF) { Write-Output ('  | ' + $l) }
        Assert-Contem $tailF ('LOCK_OK: vixradar-noturno_' + $DateTag + '_dryrun_' + $procF.Id + '\.lock criado') 'probe criou o proprio lock (sufixo _dryrun_<PID>)'
        Assert-NaoContem $tailF 'LOCK_ABANDONADO' 'probe nao avalia nem consome o lock real'
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
        $script:Casos++
        if ((Test-Path $LockNoturno) -and ((Get-Item $LockNoturno).LastWriteTime -eq $realAntesF)) {
            Write-Output '  OK  lock real envelhecido intacto (probe nao tocou o arquivo)'
        } else {
            Write-Output '  FALHA  o probe alterou ou apagou o lock real'
            $script:Falhas++
        }
    } finally {
        Remove-LockDeTeste
        if ($lockProbeF -and (Test-Path $lockProbeF)) { Remove-Item $lockProbeF -Force -ErrorAction SilentlyContinue }
        if ($logProbeF -and (Test-Path $logProbeF) -and $script:Falhas -eq 0) { Remove-Item $logProbeF -Force -ErrorAction SilentlyContinue }
    }
} else {
    Write-Cabecalho 'CASO F - pulado (rode com -ComTokens; custa um lote LIGHT de 1 emissor)'
}

# --- Caso G: probe usa artefatos proprios (log/lock separados) -------------
# Regra do operador (10/09): DryRun usa log+lock proprios _dryrun_<PID> e nunca colide com o
# real; aqui NAO existe lock real, entao o probe consulta o proprio lock e para nele.
Write-Cabecalho 'CASO G - probe aborta no lock proprio e nao toca os artefatos reais'
$jobG = Start-SeguraMutex 'Global\vixradar-sentinela-v1' 90
if (-not (Wait-MutexOcupado 'Global\vixradar-sentinela-v1' 20)) {
    Write-Output '  FALHA  o job auxiliar nao conseguiu segurar o mutex da sentinela'
    $script:Falhas++
    Stop-Job $jobG -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $jobG -Force -ErrorAction SilentlyContinue | Out-Null
} else {
    $lockProbeG = $null
    $logProbeG  = $null
    try {
        $t0 = Get-LogPos $LogNoturno
        # Com a sentinela presa pelo job, o filho fica barrado ANTES do lock: janela
        # deterministica para o teste criar o lock no nome que ELE vai consultar (o PID dele).
        # START-PROC-QUOTE1 (10/09): -ArgumentList em array e juntado com espaco e SEM aspas, entao
        # o caminho do runner (que tem espacos) era cortado em "-File E:\...\Monitoramento" e o
        # powershell.exe filho morria no parse da linha de comando com exit -196608 (0xFFFD0000)
        # sem executar uma linha do motor. O caso media um processo que nunca rodou. Aspas
        # embutidas resolvem nos dois hosts (5.1 e 7.x), que juntam o array do mesmo jeito.
        $procG = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Runner + '"'), '-Rotina', 'noturno', '-DryRun', '-MaxEmissores', '1') -PassThru -WindowStyle Hidden
        $logProbeG  = Get-LogDoProbe $procG.Id
        $lockProbeG = Get-LockDoProbe $procG.Id
        Start-Sleep -Seconds 4
        "source=test-locks-overlap.ps1`nrotina=noturno`npid=$PID`ninicio_utc=$((Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'))`nidade_simulada_min=0" | Set-Content -Path $lockProbeG -Encoding UTF8
        # So DEPOIS do lock existir a sentinela e liberada: o filho nao pode passar dela antes.
        Stop-Job $jobG -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $jobG -Force -ErrorAction SilentlyContinue | Out-Null
        $procG.WaitForExit(180000) | Out-Null
        $exitG = -1; try { $exitG = $procG.ExitCode } catch { }
        $tailG = Get-LogTail $logProbeG 0
        Write-Output ('  exit=' + $exitG + '  probe_pid=' + $procG.Id)
        foreach ($l in $tailG) { Write-Output ('  | ' + $l) }
        Assert-Contem $tailG ('ABORT: lock vixradar-noturno_' + $DateTag + '_dryrun_' + $procG.Id + '\.lock pid=\d+ LOCK_VIVO') 'probe consultou o lock DELE (sufixo _dryrun_<PID>)'
        Assert-NaoContem $tailG 'LOCK_OK|INICIO:' 'probe saiu no lock, antes do boot do provider (0 token)'
        $script:Casos++
        $linhasDia = (Get-LogTail $LogNoturno $t0).Count
        if ($linhasDia -eq 0) {
            Write-Output '  OK  log do dia nao recebeu nenhuma linha do probe (log separado)'
        } else {
            Write-Output ('  FALHA  o probe escreveu ' + $linhasDia + ' linha(s) no log do dia')
            $script:Falhas++
        }
        $script:Casos++
        if (-not (Test-Path $LockNoturno)) {
            Write-Output '  OK  lock real nao foi criado nem tocado pelo probe'
        } else {
            Write-Output '  FALHA  apareceu lock real depois de uma execucao de probe'
            $script:Falhas++
        }
        $script:Casos++
        if ($lockProbeG -ne $LockNoturno -and $lockProbeG -like '*_dryrun_*') {
            Write-Output ('  OK  nome do lock do probe (' + (Split-Path $lockProbeG -Leaf) + ') != nome do lock real (' + (Split-Path $LockNoturno -Leaf) + ')')
        } else {
            Write-Output '  FALHA  nome do lock do probe colide com o nome do lock real'
            $script:Falhas++
        }
        $script:Casos++
        if ($exitG -eq 0) { Write-Output '  OK  exit 0 no probe (abort limpo)' } else { Write-Output ('  FALHA  exit ' + $exitG + ' (esperado 0)'); $script:Falhas++ }
    } finally {
        Remove-LockDeTeste
        if ($lockProbeG -and (Test-Path $lockProbeG)) { Remove-Item $lockProbeG -Force -ErrorAction SilentlyContinue }
        if ($logProbeG -and (Test-Path $logProbeG) -and $script:Falhas -eq 0) { Remove-Item $logProbeG -Force -ErrorAction SilentlyContinue }
        Stop-Job $jobG -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $jobG -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# --- Caso H: lock REAL fresco bloqueia o probe -----------------------------
# Regra do operador (10/09): probe consulta o lock real ANTES de executar e sai sem provider,
# sem rede e sem token quando houver execucao real viva.
Write-Cabecalho 'CASO H - lock REAL fresco: probe tambem bloqueia antes do provider'
try {
    New-LockDeTeste 0
    $realAntesH = (Get-Item $LockNoturno).LastWriteTime
    # START-PROC-QUOTE1 (10/09): mesmo defeito do caso G, mesma correcao.
    $procH = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Runner + '"'), '-Rotina', 'noturno', '-DryRun', '-MaxEmissores', '1') -PassThru -WindowStyle Hidden
    $logProbeH = Get-LogDoProbe $procH.Id
    $procH.WaitForExit(180000) | Out-Null
    $exitH = -1; try { $exitH = $procH.ExitCode } catch { }
    $tailH = Get-LogTail $logProbeH 0
    Write-Output ('  exit=' + $exitH + '  probe_pid=' + $procH.Id)
    foreach ($l in $tailH) { Write-Output ('  | ' + $l) }
    Assert-Contem $tailH ('ABORT: lock real vixradar-noturno_' + $DateTag + '\.lock pid=\d+ LOCK_VIVO \(execucao real viva\) - probe sai antes de provider/network/tokens') 'probe recuou pelo lock real, antes de provider/rede/token'
    Assert-NaoContem $tailH 'LOCK_OK|INICIO:|AUTH_MODO|MODELO_EFETIVO' 'probe nao chegou a boot de provider nem a criar lock'
    $script:Casos++
    if ((Test-Path $LockNoturno) -and ((Get-Item $LockNoturno).LastWriteTime -eq $realAntesH)) {
        Write-Output '  OK  lock real fresco intacto (probe nao tocou o arquivo)'
    } else {
        Write-Output '  FALHA  o probe alterou ou apagou o lock real'
        $script:Falhas++
    }
    $script:Casos++
    if ($exitH -eq 0) { Write-Output '  OK  exit 0 no probe bloqueado (abort limpo)' } else { Write-Output ('  FALHA  exit ' + $exitH + ' (esperado 0)'); $script:Falhas++ }
    if ($logProbeH -and (Test-Path $logProbeH) -and $script:Falhas -eq 0) { Remove-Item $logProbeH -Force -ErrorAction SilentlyContinue }
} finally {
    Remove-LockDeTeste
}

# --- Caso I: lock de probe fresco NAO bloqueia a execucao real -------------
# Regra do operador (10/09): execucao real consulta/cria somente o lock real e ignora lock de
# probe. A execucao real aqui e interrompida no guarda do -SimularTokenVencido, que existe
# justamente para nao submeter nada: ele fica DEPOIS do lock (LOCK_OK ja escrito) e ANTES do
# boot do provider, entao prova o "prossegue" sem rede e sem token.
Write-Cabecalho 'CASO I - lock de probe fresco: execucao REAL prossegue e para antes do provider'
try {
    $lockProbeFresco = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '_dryrun_' + $PID + '.lock')
    "source=test-locks-overlap.ps1`nrotina=noturno`npid=$PID`nidade_simulada_min=0" | Set-Content -Path $lockProbeFresco -Encoding UTF8
    $t0 = Get-LogPos $LogNoturno
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -Rotina noturno -SimularTokenVencido | Out-Null
    $exitI = $LASTEXITCODE
    $tailI = Get-LogTail $LogNoturno $t0
    Write-Output ('  exit=' + $exitI)
    foreach ($l in $tailI) { Write-Output ('  | ' + $l) }
    Assert-NaoContem $tailI ('ABORT: lock vixradar-noturno_' + $DateTag + '(_dryrun_\d+)?\.lock') 'lock de probe fresco NAO bloqueou a execucao real'
    Assert-Contem $tailI ('LOCK_OK: vixradar-noturno_' + $DateTag + '\.lock criado') 'execucao real prosseguiu e criou o PROPRIO lock'
    Assert-Contem $tailI 'ERRO: -SimularTokenVencido so e aceito com -DryRun' 'corte deterministico depois do lock (guarda anti-submissao real)'
    Assert-NaoContem $tailI 'AUTH_MODO|MODELO_EFETIVO|Health v4' 'sem boot de provider e sem rede (0 token)'
    $script:Casos++
    if ($exitI -eq 1) { Write-Output '  OK  exit 1 (guarda do -SimularTokenVencido, nao erro de task)' } else { Write-Output ('  FALHA  exit ' + $exitI + ' (esperado 1)'); $script:Falhas++ }
    Write-Output '  NOTA: a execucao real desta rodada passa pelo lock e para no guarda acima; o log do dia e o lock sao restaurados no finally da suite, sem rastro.'
} finally {
    Remove-LockDeTeste
    if (Test-Path $lockProbeFresco) { Remove-Item $lockProbeFresco -Force -ErrorAction SilentlyContinue }
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
$script:Casos++
$sobrasProbe = @(Get-ChildItem $LogDir -Filter ('vixradar-noturno_' + $DateTag + '_dryrun_*.lock') -ErrorAction SilentlyContinue)
if ($sobrasProbe.Count -eq 0) {
    Write-Output '  OK  nenhum lock de probe sobrou'
} else {
    Write-Output ('  FALHA  sobraram ' + $sobrasProbe.Count + ' lock(s) de probe: ' + (($sobrasProbe | ForEach-Object { $_.Name }) -join ', '))
    $script:Falhas++
}

} finally {
    # Restauracao dos artefatos reais do dia, SEMPRE: passando, falhando ou estourando excecao.
    # A checagem de higiene acima roda ANTES disto de proposito, para continuar flagrando um
    # lock de probe esquecido; a checagem abaixo prova a equivalencia byte a byte pos-restore.
    Restore-SnapshotDia $snapDia
    Test-RestauracaoDia $snapDia
}

Write-Output ''
Write-Output ('RESULTADO: ' + ($script:Casos - $script:Falhas) + '/' + $script:Casos + ' asserts OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
