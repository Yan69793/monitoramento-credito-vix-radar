# upload_volatilidade_kv.ps1, Sobe dados de volatilidade para o KV do Worker
# Uso: powershell.exe -NoProfile -File ./scripts/upload_volatilidade_kv.ps1 [-AdminSenha $senha]
# Pré-requisito: collect_cotacoes.ps1 já rodou (data/cotacoes/meta_volatilidade.json existe)
#
# Monta payload { emissores: { "Nome": { vol_anualizada, market_cap } }, selic_anual }
# e faz PUT em cotacoes:volatilidade:v1 via endpoint admin do Worker.

param(
    [string]$AdminSenha = $null,
    [string]$MetaFile = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent $PSScriptRoot
if (-not $MetaFile) { $MetaFile = Join-Path $ROOT 'data\cotacoes\meta_volatilidade.json' }
$tickersFile = Join-Path $ROOT 'data\cotacoes\tickers_emissores.json'

if (-not (Test-Path $MetaFile)) {
    Write-Host "ERRO: $MetaFile não encontrado. Rode collect_cotacoes.ps1 primeiro."
    exit 1
}

if (-not $AdminSenha) {
    $helper = Join-Path $ROOT 'api\Get-VixAdminCredential.ps1'
    if (Test-Path $helper) {
        $AdminSenha = & $helper -AsPlainText 2>$null
        if (-not $AdminSenha) { Write-Host "AVISO: DPAPI retornou vazio, tentando env var ADMIN_PASSWORD" }
    }
    if (-not $AdminSenha -and $env:ADMIN_PASSWORD) { $AdminSenha = $env:ADMIN_PASSWORD }
}
if (-not $AdminSenha) {
    Write-Host "ERRO: Senha admin nao encontrada. Passe -AdminSenha, configure ADMIN_PASSWORD env var, ou verifique api/.admin_credencial.dat"
    exit 1
}

$metaRaw = Get-Content $MetaFile -Raw | ConvertFrom-Json
$tickersRaw = Get-Content $tickersFile -Raw | ConvertFrom-Json

# Construir payload para KV
$emissoresPayload = @{}
$comVol = 0
$semVol = 0

foreach ($prop in ($metaRaw.emissores | Get-Member -MemberType NoteProperty)) {
    $emissor = $prop.Name
    $dados = $metaRaw.emissores.$emissor
    $tickerInfo = $tickersRaw.emissores.$emissor

    if (-not $dados.vol_anualizada) {
        $semVol++
        continue
    }

    # Tentar obter market cap da série de preços (último close)
    $ticker = $dados.ticker -replace '\.SA$', ''
    $seriesFile = Join-Path $ROOT "data\cotacoes\series\$ticker.json"
    $mktCap = $null
    if (Test-Path $seriesFile) {
        $series = Get-Content $seriesFile -Raw | ConvertFrom-Json
        $lastRow = $series.rows | Select-Object -Last 1
        $regularMarketPrice = $series.regularMarketPrice
        if ($regularMarketPrice -and $regularMarketPrice -gt 0) {
            $mktCap = $regularMarketPrice # preço; market cap real = preço x shares outstanding
        }
    }

    $emissoresPayload[$emissor] = [PSCustomObject]@{
        ticker = $dados.ticker
        vol_anualizada = $dados.vol_anualizada
        rows = $dados.rows
        market_cap = $mktCap
    }
    $comVol++
}

# Selic atual ~13.75% (jul/2026), pode ser atualizado via BCB API
$selicAnual = 0.1375

$payload = [PSCustomObject]@{
    schema_v = 1
    gerado_em = (Get-Date).ToString('o')
    selic_anual = $selicAnual
    total_com_volatilidade = $comVol
    total_sem_volatilidade = $semVol
    emissores = $emissoresPayload
}

$payloadJson = $payload | ConvertTo-Json -Depth 4 -Compress
$payloadSizeKB = [Math]::Round($payloadJson.Length / 1KB, 1)
Write-Host "Payload: $payloadSizeKB KB | Emissores com vol: $comVol | Sem vol: $semVol"
Write-Host "Selic: $($selicAnual*100)% a.a."
Write-Host ""

# Upload via admin endpoint
Write-Host "Enviando para KV (cotacoes:volatilidade:v1)..."
$body = @{
    admin_senha = $AdminSenha
    action = "admin_kv_put"
    key = "cotacoes:volatilidade:v1"
    value = $payloadJson
    ttl = 86400  # 24h, re-rodar diariamente com o collector
} | ConvertTo-Json -Compress

try {
    $response = Invoke-RestMethod -Uri "https://api.vixradar.com/" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 30
    if ($response.ok) {
        Write-Host "OK, volatilidade publicada no KV (TTL 24h)"
    } else {
        Write-Host "ERRO: $($response.erro)"
    }
} catch {
    Write-Host "ERRO HTTP: $_"
}

Write-Host ""
Write-Host "Top 10 por volatilidade:"
$emissoresPayload.GetEnumerator() |
    Sort-Object { $_.Value.vol_anualizada } -Descending |
    Select-Object -First 10 |
    ForEach-Object { "  $($_.Key): $([Math]::Round($_.Value.vol_anualizada*100,1))%" }
