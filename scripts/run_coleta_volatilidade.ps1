# run_coleta_volatilidade.ps1 - rotina diaria: coleta cotacoes e publica o KV.
[CmdletBinding()]
param(
    [string]$Root = 'E:\Diretorio\Claude\Monitoramento de Credito'
)
Set-StrictMode -Version Latest
# 'Continue' e obrigatorio em script do Task Scheduler: com 'Stop' o erro aborta
# antes do 'exit 1' final e a tarefa reporta LastTaskResult 0 (falha silenciosa).
# O controle de falha aqui e o $hadFailure + exit explicito no fim.
$ErrorActionPreference = 'Continue'

$ROOT = $Root
$Collector = Join-Path $ROOT 'scripts\collect_cotacoes.ps1'
$Uploader = Join-Path $ROOT 'scripts\upload_volatilidade_kv.ps1'
$LogDir = Join-Path $ROOT 'logs\routines'
$LogFile = Join-Path $LogDir ("coleta_volatilidade_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    [Console]::WriteLine($line)
    $line | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

# COLETATETO1 (17/10/2026): em 16/10 o upload passou de 13 min e o Task Scheduler matou a
# task no limite de 15 min (LastTaskResult 0x40010004). A saida do filho ficava so em memoria,
# entao morreu junto: sem FIM, sem ROTINA_RESUMO, sem causa. Cada etapa agora roda com teto
# proprio (soma abaixo do limite da task) e com stdout/stderr gravados em arquivo enquanto roda.
function Invoke-ColetaEtapa([string]$Script, [string]$Argumentos, [int]$TetoSeg, [string]$Rotulo) {
    $base = Join-Path $LogDir ('coleta_{0}_{1}' -f $Rotulo, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $outFile = $base + '.out.txt'
    $errFile = $base + '.err.txt'
    $argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Script + '"'
    if ($Argumentos) { $argLine += ' ' + $Argumentos }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $p.Handle  # sem isto o ExitCode volta vazio no PS 5.1 depois do WaitForExit
    $terminou = $p.WaitForExit($TetoSeg * 1000)
    if (-not $terminou) {
        try { $p.Kill() } catch { }
        $null = $p.WaitForExit(10000)
    }
    $saida = @()
    foreach ($f in @($outFile, $errFile)) {
        if (Test-Path -LiteralPath $f) { $saida += @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue) }
    }
    $codigo = 124
    if ($terminou) { $codigo = [int]$p.ExitCode }
    return [pscustomobject]@{ Exit = $codigo; Timeout = (-not $terminou); Saida = $saida; Arquivo = $outFile }
}
$TetoColetorSeg = 420
$TetoUploaderSeg = 330

$hadFailure = $false
Write-Log 'INICIO: coleta_volatilidade'
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Log 'Etapa 1/2: collect_cotacoes.ps1'
try {
    $rc = Invoke-ColetaEtapa -Script $Collector -Argumentos '-Dias 252' -TetoSeg $TetoColetorSeg -Rotulo 'coletor'
    $collectOutput = $rc.Saida
    $collectExit = $rc.Exit
    if ($rc.Timeout) { throw ("collect_cotacoes.ps1 passou do teto de {0}s e foi encerrado; saida parcial em {1}" -f $TetoColetorSeg, $rc.Arquivo) }
    if ($collectExit -ne 0) { throw "collect_cotacoes.ps1 exit=$collectExit" }
    $collectOk = @($collectOutput | Select-String 'Sucesso: (\d+)').Count
    Write-Log "Coletor concluido; marcadores_sucesso=$collectOk"
} catch {
    $hadFailure = $true
    Write-Log "ERRO coletor: $($_.Exception.Message)"
}

if (-not $hadFailure) {
    Write-Log 'Etapa 2/2: upload_volatilidade_kv.ps1'
    try {
        $ru = Invoke-ColetaEtapa -Script $Uploader -Argumentos '' -TetoSeg $TetoUploaderSeg -Rotulo 'uploader'
        $uploadOutput = $ru.Saida
        $uploadExit = $ru.Exit
        if ($ru.Timeout) { throw ("upload_volatilidade_kv.ps1 passou do teto de {0}s e foi encerrado; saida parcial em {1}" -f $TetoUploaderSeg, $ru.Arquivo) }
        if ($uploadExit -ne 0) { throw "upload_volatilidade_kv.ps1 exit=$uploadExit" }
        if (-not ($uploadOutput | Select-String 'UPLOAD_OK')) { throw 'Uploader terminou sem confirmacao UPLOAD_OK.' }
        Write-Log 'Upload confirmado.'
    } catch {
        $hadFailure = $true
        Write-Log "ERRO upload: $($_.Exception.Message)"
        # VOLLOG1 (auditoria 2026-08-20): a linha acima sozinha registra so
        # "exit=1". A causa real (AVISO: Falha HTTP, Worker recusou publicacao,
        # payload invalido) fica em $uploadOutput e era descartada. Foi o que
        # aconteceu em 19/08: falha sem diagnostico possivel no dia seguinte.
        if ($uploadOutput) {
            foreach ($linha in @($uploadOutput)) {
                $txt = [string]$linha
                if ($txt.Trim()) { Write-Log ("  saida_uploader: " + $txt.Trim()) }
            }
        }
    }
} else {
    Write-Log 'Upload nao executado porque a coleta falhou.'
}

if ($hadFailure) {
    Write-Log 'FIM: coleta_volatilidade COM_FALHA'
    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log ('ROTINA_RESUMO|vixradar-coleta-volatilidade|local|' + $inicioIso + '|' + $fimIso + '|FALHA|0|1|0|')
    exit 1
}
Write-Log 'FIM: coleta_volatilidade OK'
$fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Log ('ROTINA_RESUMO|vixradar-coleta-volatilidade|local|' + $inicioIso + '|' + $fimIso + '|OK|2|0|0|')
exit 0