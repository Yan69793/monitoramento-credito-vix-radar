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

$hadFailure = $false
Write-Log 'INICIO: coleta_volatilidade'
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Log 'Etapa 1/2: collect_cotacoes.ps1'
try {
    $collectOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Collector -Dias 252 2>&1
    $collectExit = $LASTEXITCODE
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
        $uploadOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Uploader 2>&1
        $uploadExit = $LASTEXITCODE
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