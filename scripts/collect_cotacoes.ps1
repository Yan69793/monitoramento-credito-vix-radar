# collect_cotacoes.ps1 — Coleta séries históricas de cotações B3 via Yahoo Finance
# Uso: pwsh ./scripts/collect_cotacoes.ps1 [-Dias 252] [-OutputDir data/cotacoes]
# Yahoo Finance v8 API é gratuita, sem autenticação.
# Dados são cacheados por ticker em JSON individual.

param(
    [int]$Dias = 504,          # ~2 anos de pregões
    [string]$OutputDir = $null,
    [switch]$Force             # Re-coleta mesmo se cache < 24h
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ROOT = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $ROOT 'data\cotacoes' }
$tickersFile = Join-Path $OutputDir 'tickers_emissores.json'
$seriesDir   = Join-Path $OutputDir 'series'
$metaFile    = Join-Path $OutputDir 'meta_volatilidade.json'

if (-not (Test-Path $tickersFile)) {
    Write-Host "ERRO: $tickersFile não encontrado. Execute a partir do root do projeto."
    exit 1
}

$tickersMap = Get-Content $tickersFile -Raw | ConvertFrom-Json
$emissores = $tickersMap.emissores
$total = ($emissores | Get-Member -MemberType NoteProperty).Count
Write-Host "Emissores listados com ticker: $total de 103"
Write-Host "Output: $seriesDir"
Write-Host ""

New-Item -ItemType Directory -Force -Path $seriesDir | Out-Null

$sucesso = 0
$falha = 0
$skipped = 0

$meta = @{}

foreach ($prop in ($emissores | Get-Member -MemberType NoteProperty)) {
    $emissor = $prop.Name
    $tickerRaw = $emissores.$emissor.ticker
    $ticker = $tickerRaw -replace '\.SA$', ''
    $outFile = Join-Path $seriesDir "$ticker.json"

    # Cache: skip if file < 24h old (unless -Force)
    if (-not $Force -and (Test-Path $outFile)) {
        $age = (Get-Date) - (Get-Item $outFile).LastWriteTime
        if ($age.TotalHours -lt 24) {
            $skipped++
            continue
        }
    }

    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${ticker}.SA?range=2y&interval=1d&includePrePost=false"
    try {
        Write-Host -NoNewline "  $emissor ($ticker.SA)... "
        $response = Invoke-RestMethod -Uri $url -TimeoutSec 30 -MaximumRetryCount 2 -RetryIntervalSec 2
        $result = $response.chart.result[0]
        if (-not $result -or -not $result.timestamp) {
            Write-Host "SEM DADOS"
            $falha++
            continue
        }

        $timestamps = $result.timestamp
        $quotes = $result.indicators.quote[0]
        $adjclose = if ($result.indicators.adjclose) { $result.indicators.adjclose[0].adjclose } else { $null }

        $rows = @()
        for ($i = 0; $i -lt $timestamps.Count; $i++) {
            $close = $quotes.close[$i]
            $adj = if ($adjclose -and $adjclose[$i]) { $adjclose[$i] } else { $close }
            if ($close -eq $null) { continue }

            $rows += [PSCustomObject]@{
                date  = (Get-Date "1970-01-01").AddSeconds($timestamps[$i]).ToString('yyyy-MM-dd')
                open  = $quotes.open[$i]
                high  = $quotes.high[$i]
                low   = $quotes.low[$i]
                close = $close
                adjclose = $adj
                volume = $quotes.volume[$i]
            }
        }

        $metaTick = $result.meta
        $mktPrice = if ($metaTick.PSObject.Properties.Name -contains 'regularMarketPrice') { $metaTick.regularMarketPrice } else { $null }
        $prevClose = if ($metaTick.PSObject.Properties.Name -contains 'previousClose') { $metaTick.previousClose } else { $mktPrice }
        $granularity = if ($result.meta.PSObject.Properties.Name -contains 'dataGranularity') { $result.meta.dataGranularity } else { $null }
        $currency = if ($metaTick.PSObject.Properties.Name -contains 'currency') { $metaTick.currency } else { 'BRL' }
        $payload = [PSCustomObject]@{
            ticker = "$ticker.SA"
            emissor = $emissor
            currency = $currency
            regularMarketPrice = $mktPrice
            previousClose = $prevClose
            dataGranularity = $granularity
            fetched_at = (Get-Date).ToString('o')
            rows = $rows
        }

        $payload | ConvertTo-Json -Depth 4 -Compress | Set-Content $outFile -Encoding UTF8
        $n = $rows.Count

        # Calcular volatilidade anualizada (252 pregões)
        if ($n -ge 60) {
            $retornos = @()
            for ($j = 1; $j -lt [Math]::Min($n, $Dias + 1); $j++) {
                $p0 = $rows[$j-1].adjclose
                $p1 = $rows[$j].adjclose
                if ($p0 -gt 0 -and $p1 -gt 0) {
                    $retornos += [Math]::Log($p1 / $p0)
                }
            }
            if ($retornos.Count -ge 30) {
                $std = [Math]::Sqrt(($retornos | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum / $retornos.Count)
                $volAnual = [Math]::Round($std * [Math]::Sqrt(252), 6)
            } else {
                $volAnual = $null
            }
        } else {
            $volAnual = $null
        }

        $meta[$emissor] = [PSCustomObject]@{
            ticker = "$ticker.SA"
            rows = $n
            vol_anualizada = $volAnual
        }

        Write-Host "$n barras, vol=$($volAnual ? "$([Math]::Round($volAnual*100,2))%" : 'N/A')"
        $sucesso++
    }
    catch {
        Write-Host "ERRO: $_"
        $falha++
    }
}

$metaObj = [PSCustomObject]@{
    gerado_em = (Get-Date).ToString('o')
    total_listados = $total
    sucesso = $sucesso
    falha = $falha
    cache_skip = $skipped
    emissores = $meta
}

$metaObj | ConvertTo-Json -Depth 3 | Set-Content $metaFile -Encoding UTF8

Write-Host ""
Write-Host "=== RESUMO ==="
Write-Host "Sucesso: $sucesso | Falha: $falha | Cache skip: $skipped | Total: $total"
Write-Host "Meta: $metaFile"
if ($sucesso -gt 0) {
    $comVol = ($meta.Values | Where-Object { $_.vol_anualizada }).Count
    Write-Host "Com volatilidade: $comVol de $sucesso"
}
