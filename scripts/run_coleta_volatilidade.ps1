# run_coleta_volatilidade.ps1 — Rotina diária: coleta cotações Yahoo Finance + upload KV
# Registrada como VIXRadar-Coleta-Volatilidade (Task Scheduler)
# Horário: 17:00 BRT (após fechamento do pregão, antes da noturna 18:00)
# Pré-requisito: atualizar_altman_cvm.ps1 -Publicar deve rodar antes (semanal ou sob demanda)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = "E:\Diretorio\Claude\Monitoramento de Credito"
$Collector = Join-Path $ROOT "scripts\collect_cotacoes.ps1"
$Uploader  = Join-Path $ROOT "scripts\upload_volatilidade_kv.ps1"
$LogDir    = Join-Path $ROOT "logs\routines"
$LogFile   = Join-Path $LogDir "coleta_volatilidade_$(Get-Date -Format 'yyyyMMdd').log"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts $msg"
    [Console]::WriteLine($line)
    $line | Add-Content $LogFile -Encoding UTF8
}

Write-Log "INICIO: coleta_volatilidade"

# Etapa 1: Coletar cotações
Write-Log "Etapa 1/2: collect_cotacoes.ps1"
try {
    $collectOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Collector -Dias 252 2>&1
    $collectOk = ($collectOutput | Select-String "Sucesso: (\d+)" | ForEach-Object { $_.Matches.Groups[1].Value })
    Write-Log "Coletor: sucesso=$collectOk"
} catch {
    Write-Log "ERRO coletor: $_"
}

# Etapa 2: Upload ao KV
Write-Log "Etapa 2/2: upload_volatilidade_kv.ps1"
try {
    $uploadOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Uploader 2>&1
    $uploadOk = ($uploadOutput | Select-String "OK" | Measure-Object).Count
    Write-Log "Upload: ok=$uploadOk"
} catch {
    Write-Log "ERRO upload: $_"
}

Write-Log "FIM: coleta_volatilidade"
