# upload_volatilidade_kv.ps1 - publica volatilidade e Selic efetiva no KV do Worker.
[CmdletBinding()]
param(
    [string]$AdminSenha = $null,
    [string]$MetaFile = $null,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
# 'Continue' e obrigatorio em script do Task Scheduler: com 'Stop' o erro aborta
# antes do 'exit 1' final e a tarefa reporta LastTaskResult 0 (falha silenciosa).
$ErrorActionPreference = 'Continue'

$ROOT = Split-Path -Parent $PSScriptRoot
if (-not $MetaFile) { $MetaFile = Join-Path $ROOT 'data\cotacoes\meta_volatilidade.json' }
if (-not (Test-Path -LiteralPath $MetaFile)) {
    throw "Meta de volatilidade ausente: $MetaFile. Rode collect_cotacoes.ps1 primeiro."
}

if (-not $DryRun -and -not $AdminSenha) {
    $helper = Join-Path $ROOT 'api\Get-VixAdminCredential.ps1'
    if (Test-Path -LiteralPath $helper) {
        $AdminSenha = & $helper -AsPlainText 2>$null
    }
    if (-not $AdminSenha -and $env:ADMIN_PASSWORD) { $AdminSenha = $env:ADMIN_PASSWORD }
}
if (-not $DryRun -and -not $AdminSenha) {
    throw 'Senha admin ausente. Configure ADMIN_PASSWORD ou a credencial DPAPI.'
}

function Repair-Mojibake([string]$Value) {
    if (-not $Value -or $Value -cnotmatch '[ÃÂ]') { return $Value }
    $bytes = [Text.Encoding]::GetEncoding(1252).GetBytes($Value)
    return [Text.Encoding]::UTF8.GetString($bytes)
}

$metaRaw = Get-Content -LiteralPath $MetaFile -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $metaRaw.emissores) { throw 'Meta de volatilidade sem o objeto emissores.' }

$emissoresPayload = @{}
$comVol = 0
$semVol = 0
foreach ($prop in ($metaRaw.emissores | Get-Member -MemberType NoteProperty)) {
    $emissor = Repair-Mojibake $prop.Name
    $dados = $metaRaw.emissores.PSObject.Properties[$prop.Name].Value
    if ($null -eq $dados.vol_anualizada -or [double]$dados.vol_anualizada -le 0) {
        $semVol++
        continue
    }

    # Nao publicar preco por acao como market cap. Merton exige valor de mercado real.
    $emissoresPayload[$emissor] = [PSCustomObject]@{
        ticker = $dados.ticker
        vol_anualizada = [double]$dados.vol_anualizada
        rows = $dados.rows
    }
    $comVol++
}

# Taxa livre de risco: Selic efetiva anualizada, fonte oficial BCB SGS 1178.
# Resiliencia em 3 camadas: JSON -> CSV oficial -> ultimo valor oficial validado em cache local.
# O cache nunca mascara dado velho: fallback aceito por no maximo 3 dias uteis.
$selicJsonUrl = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs.1178/dados/ultimos/1?formato=json'
$selicCsvUrl = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs.1178/dados/ultimos/1?formato=csv'
$selicCacheFile = Join-Path $ROOT 'data\cotacoes\selic_sgs_1178_cache.json'
$selicMode = $null
$selicItem = $null
$cacheAgeBusinessDays = $null
$selicUltimoErro = $null
$selicMaxRetries = 4

function Get-BusinessAgeDays([DateTime]$FromDate, [DateTime]$ToDate) {
    if ($FromDate.Date -gt $ToDate.Date) { return -1 }
    $count = 0
    for ($d = $FromDate.Date.AddDays(1); $d -le $ToDate.Date; $d = $d.AddDays(1)) {
        if ($d.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { $count++ }
    }
    return $count
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Plano A: JSON oficial, com retry/backoff.
for ($tentativaSelic = 1; $tentativaSelic -le $selicMaxRetries; $tentativaSelic++) {
    try {
        $resp = Invoke-RestMethod -Uri $selicJsonUrl -TimeoutSec 30
        $candidate = @($resp)[0]
        if (-not $candidate -or -not $candidate.valor -or -not $candidate.data) {
            throw 'Resposta JSON sem data ou valor.'
        }
        $selicItem = $candidate
        $selicMode = 'PRIMARY_JSON'
        break
    } catch {
        $selicUltimoErro = $_.Exception.Message
        Write-Host "AVISO: BCB JSON tentativa $tentativaSelic/$selicMaxRetries falhou: $selicUltimoErro"
        if ($tentativaSelic -lt $selicMaxRetries) {
            $waitSelic = 5 * $tentativaSelic
            Start-Sleep -Seconds $waitSelic
        }
    }
}

# Plano B: mesma serie oficial via CSV.
if ($null -eq $selicItem) {
    try {
        $csvText = (Invoke-WebRequest -Uri $selicCsvUrl -TimeoutSec 30 -UseBasicParsing).Content
        $rows = @($csvText | ConvertFrom-Csv -Delimiter ';')
        $row = $rows | Select-Object -First 1
        if (-not $row -or -not $row.data -or -not $row.valor) { throw 'Resposta CSV sem data ou valor.' }
        $selicItem = [PSCustomObject]@{ data = [string]$row.data; valor = ([string]$row.valor).Replace(',', '.') }
        $selicMode = 'FALLBACK_CSV'
        Write-Host 'AVISO: Selic obtida pelo fallback CSV oficial do BCB.'
    } catch {
        $selicUltimoErro = $_.Exception.Message
        Write-Host "AVISO: fallback CSV BCB falhou: $selicUltimoErro"
    }
}

# Plano C: ultimo valor oficial validado, limitado a 3 dias uteis.
if ($null -eq $selicItem -and (Test-Path -LiteralPath $selicCacheFile)) {
    try {
        $cached = Get-Content -LiteralPath $selicCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $cacheDate = [DateTime]::ParseExact([string]$cached.data, 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $cacheAgeBusinessDays = Get-BusinessAgeDays $cacheDate (Get-Date)
        if ($cacheAgeBusinessDays -lt 0 -or $cacheAgeBusinessDays -gt 3) {
            throw "Cache Selic fora da tolerancia: $cacheAgeBusinessDays dias uteis."
        }
        $selicItem = [PSCustomObject]@{ data = [string]$cached.data; valor = [string]$cached.valor }
        $selicMode = 'FALLBACK_CACHE'
        Write-Host "AVISO: Selic usando cache oficial validado, idade=$cacheAgeBusinessDays dias uteis."
    } catch {
        $selicUltimoErro = $_.Exception.Message
        Write-Host "AVISO: cache Selic indisponivel/invalido: $selicUltimoErro"
    }
}
if ($null -eq $selicItem) {
    throw "Falha ao obter Selic SGS 1178 por JSON, CSV e cache seguro. Ultimo erro: $selicUltimoErro"
}

try {
    $selicPct = [decimal]::Parse([string]$selicItem.valor, [Globalization.CultureInfo]::InvariantCulture)
    if ($selicPct -le 0 -or $selicPct -ge 100) { throw "Valor fora de faixa: $selicPct" }
    $selicAnual = [double]($selicPct / 100)
    $selicDate = [DateTime]::ParseExact([string]$selicItem.data, 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $selicAgeDays = ((Get-Date).Date - $selicDate.Date).TotalDays
    if ($selicAgeDays -lt -1 -or $selicAgeDays -gt 10) { throw "Data Selic stale ou futura: $($selicItem.data)" }
    $selicAsOf = $selicDate.ToString('yyyy-MM-dd')
} catch {
    throw "Resposta invalida do BCB SGS 1178: $($_.Exception.Message)"
}

# Atualiza cache somente quando houve leitura direta oficial; DryRun nao altera estado persistente.
if (-not $DryRun -and $selicMode -in @('PRIMARY_JSON','FALLBACK_CSV')) {
    $cacheDir = Split-Path -Parent $selicCacheFile
    if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    [PSCustomObject]@{
        data = [string]$selicItem.data
        valor = [string]$selicItem.valor
        fonte = 'BCB_SGS_1178'
        capturado_em = (Get-Date).ToUniversalTime().ToString('o')
        modo = $selicMode
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $selicCacheFile -Encoding UTF8
}

$payload = [PSCustomObject]@{
    schema_v = 2
    gerado_em = (Get-Date).ToUniversalTime().ToString('o')
    selic_anual = $selicAnual
    selic_fonte = 'BCB_SGS_1178'
    selic_as_of = $selicAsOf
    selic_mode = $selicMode
    selic_cache_age_business_days = $cacheAgeBusinessDays
    total_com_volatilidade = $comVol
    total_sem_volatilidade = $semVol
    emissores = $emissoresPayload
}
$payloadJson = $payload | ConvertTo-Json -Depth 5 -Compress

# Invariantes que impedem a regressao de preco por acao como market cap.
if ($payloadJson -match '"market_cap"') { throw 'Payload invalido: market_cap nao pode vir do coletor de precos.' }
if ($payloadJson -cmatch '[ÃÂ]') {
    $idx = $payloadJson.IndexOf($Matches[0])
    $start = [Math]::Max(0, $idx - 30)
    $ctx = $payloadJson.Substring($start, [Math]::Min(100, $payloadJson.Length - $start))
    throw "Payload invalido: mojibake perto de: $ctx"
}
if (-not ($payload.selic_anual -gt 0 -and $payload.selic_anual -lt 1)) { throw 'Payload invalido: selic_anual fora de faixa.' }

Write-Host "PAYLOAD_OK emissores=$comVol sem_vol=$semVol selic=$selicAnual fonte=BCB_SGS_1178 as_of=$selicAsOf mode=$selicMode cache_age_bd=$cacheAgeBusinessDays"
if ($DryRun) {
    Write-Output $payloadJson
    exit 0
}

# VOLTTL1 (auditoria 2026-08-20): o TTL era 86400, exatamente o intervalo entre
# duas execucoes da rotina. Uma unica falha de upload apagava o dado de producao
# sem deixar rastro: em 19/08 17:02 o POST falhou, a escrita de 18/08 expirou as
# 17:01 e a chave sumiu (404 no wrangler kv key get). O pipeline preditivo le com
# .catch(() => null), entao rodou o dia inteiro sem volatilidade e sem reclamar.
# 3 dias dao folga para 2 falhas seguidas antes de perder o dado.
$KV_TTL_VOLATILIDADE = 259200
$body = @{
    admin_senha = $AdminSenha
    action = 'admin_kv_put'
    key = 'cotacoes:volatilidade:v1'
    value = $payloadJson
    ttl = $KV_TTL_VOLATILIDADE
} | ConvertTo-Json -Compress

$uploadOk = $false
$ultimoErro = $null
$maxRetries = 3
for ($tentativa = 1; $tentativa -le $maxRetries; $tentativa++) {
    try {
        $response = Invoke-RestMethod -Uri 'https://api.vixradar.com/' -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 30
        if ($response.ok) {
            $uploadOk = $true
            break
        }
        $ultimoErro = "Worker recusou publicacao (tentativa $tentativa): $($response.erro)"
        Write-Host "AVISO: $ultimoErro"
    } catch {
        $ultimoErro = "Falha HTTP (tentativa $tentativa): $($_.Exception.Message)"
        Write-Host "AVISO: $ultimoErro"
    }
    if ($tentativa -lt $maxRetries) {
        $wait = 10 * $tentativa
        Write-Host "retry em ${wait}s..."
        Start-Sleep -Seconds $wait
    }
}
if (-not $uploadOk) { throw "Falha ao publicar volatilidade apos $maxRetries tentativas. Ultimo erro: $ultimoErro" }
Write-Host ('UPLOAD_OK key=cotacoes:volatilidade:v1 ttl=' + $KV_TTL_VOLATILIDADE)