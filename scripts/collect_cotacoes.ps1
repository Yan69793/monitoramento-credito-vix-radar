# collect_cotacoes.ps1, Coleta séries históricas de cotações B3 via Yahoo Finance
# Uso: powershell.exe -NoProfile -File ./scripts/collect_cotacoes.ps1 [-Dias 252] [-OutputDir data/cotacoes]
# Yahoo Finance v8 API é gratuita, sem autenticação.
# Dados são cacheados por ticker em JSON individual.

param(
    [int]$Dias = 504,          # ~2 anos de pregões
    [string]$OutputDir = $null,
    [switch]$Force             # Re-coleta mesmo se cache < 24h
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ROOT = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $ROOT 'data\cotacoes' }
$tickersFile = Join-Path $OutputDir 'tickers_emissores.json'
$seriesDir   = Join-Path $OutputDir 'series'
$metaFile    = Join-Path $OutputDir 'meta_volatilidade.json'

if (-not (Test-Path $tickersFile)) {
    Write-Host "ERRO: $tickersFile não encontrado. Execute a partir do root do projeto."
    exit 1
}

# MOJIBAKEORIGEM1 (auditoria 2026-08-20). Este Get-Content nao tinha -Encoding.
# No powershell.exe 5.1 o default nao e UTF-8, e a pagina de codigo ANSI do
# sistema (Windows-1252 aqui). O tickers_emissores.json e UTF-8 SEM BOM, entao
# nao havia como o 5.1 adivinhar, e cada byte multibyte virava dois caracteres:
# "Raizen" com i acentuado saia como RaA-til-...zen, "Itausa" idem. O nome
# corrompido seguia para dentro de meta_volatilidade.json, que era gravado em
# UTF-8 e carimbava a corrupcao no disco de forma permanente.
# O upload_volatilidade_kv.ps1 tem Repair-Mojibake e por isso a producao nunca
# viu nome errado, o que escondeu o problema. Mas qualquer comparacao por nome
# entre os dois arquivos errava em silencio: na auditoria de hoje um diff acusou
# 33 falhas de coleta onde o numero real era 21, e so bateu quando a chave da
# comparacao virou o ticker, que e ASCII.
# Repair-Mojibake fica onde esta, como rede. O conserto e aqui, na leitura.
$tickersMap = Get-Content $tickersFile -Raw -Encoding UTF8 | ConvertFrom-Json
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

    # Cache: skip if file < 24h old (unless -Force), but still populate meta from cached data
    if (-not $Force -and (Test-Path $outFile)) {
        $age = (Get-Date) - (Get-Item $outFile).LastWriteTime
        if ($age.TotalHours -lt 24) {
            $skipped++
            try {
                # MOJIBAKEORIGEM1: mesmo motivo do Get-Content la de cima. Este
                # le de volta um arquivo que o proprio script gravou em UTF-8.
                $cached = Get-Content $outFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $cachedRows = $cached.rows
                $n = $cachedRows.Count
                if ($n -ge 60) {
                    $retornos = @()
                    $limit = [Math]::Min($n, $Dias + 1)
                    for ($j = 1; $j -lt $limit; $j++) {
                        $p0 = $cachedRows[$j-1].adjclose
                        $p1 = $cachedRows[$j].adjclose
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
            } catch {
                # Cache file corrupt/unreadable, will be re-fetched next run
            }
            continue
        }
    }

    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${ticker}.SA?range=2y&interval=1d&includePrePost=false"
    try {
        Write-Host -NoNewline "  $emissor ($ticker.SA)... "
        # -MaximumRetryCount/-RetryIntervalSec so existem no PS 6.1+; este laco reproduz
        # o mesmo comportamento sob powershell.exe 5.1, que e quem roda no Task Scheduler.
        $response = $null
        for ($tentativa = 0; $tentativa -le 2; $tentativa++) {
            try {
                $response = Invoke-RestMethod -Uri $url -TimeoutSec 30
                break
            } catch {
                if ($tentativa -eq 2) { throw }
                Start-Sleep -Seconds 2
            }
        }
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

        $volTxt = if ($volAnual) { "$([Math]::Round($volAnual*100,2))%" } else { 'N/A' }
        Write-Host "$n barras, vol=$volTxt"
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
Write-Host "Cobertura: $($sucesso + $skipped) de $total emissores no meta"
Write-Host "Meta: $metaFile"
$comVol = ($meta.Values | Where-Object { $_.vol_anualizada }).Count
Write-Host "Com volatilidade: $comVol de $($meta.Count)"
if ($falha -gt 0 -and ($sucesso + $skipped) -lt ($total - $falha)) {
    Write-Host "AVISO: $($total - $falha - $sucesso - $skipped) emissores sem cobertura (nem cache nem fetch)"
}
if (($sucesso + $skipped) -lt ($total - $falha)) {
    exit 2
}
exit 0
