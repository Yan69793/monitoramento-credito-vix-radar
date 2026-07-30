# upload_volatilidade_kv.ps1 - publica volatilidade e Selic efetiva no KV do Worker.
[CmdletBinding()]
param(
    [string]$AdminSenha = $null,
    [string]$MetaFile = $null,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
# Falha fechada: sem dado atual da fonte primaria, nao publica taxa velha.
$selicUrl = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs.1178/dados/ultimos/1?formato=json'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $selicResp = Invoke-RestMethod -Uri $selicUrl -TimeoutSec 30
    $selicItem = @($selicResp)[0]
    if (-not $selicItem -or -not $selicItem.valor -or -not $selicItem.data) {
        throw 'Resposta SGS 1178 sem data ou valor.'
    }
    $selicPct = [decimal]::Parse([string]$selicItem.valor, [Globalization.CultureInfo]::InvariantCulture)
    if ($selicPct -le 0 -or $selicPct -ge 100) { throw "Valor fora de faixa: $selicPct" }
    $selicAnual = [double]($selicPct / 100)
    $selicDate = [DateTime]::ParseExact([string]$selicItem.data, 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $selicAgeDays = ((Get-Date).Date - $selicDate.Date).TotalDays
    if ($selicAgeDays -lt -1 -or $selicAgeDays -gt 10) { throw "Data Selic stale ou futura: $($selicItem.data)" }
    $selicAsOf = $selicDate.ToString('yyyy-MM-dd')
} catch {
    throw "Falha ao obter Selic efetiva no BCB SGS 1178: $($_.Exception.Message)"
}

$payload = [PSCustomObject]@{
    schema_v = 2
    gerado_em = (Get-Date).ToUniversalTime().ToString('o')
    selic_anual = $selicAnual
    selic_fonte = 'BCB_SGS_1178'
    selic_as_of = $selicAsOf
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

Write-Host "PAYLOAD_OK emissores=$comVol sem_vol=$semVol selic=$selicAnual fonte=BCB_SGS_1178 as_of=$selicAsOf"
if ($DryRun) {
    Write-Output $payloadJson
    exit 0
}

$body = @{
    admin_senha = $AdminSenha
    action = 'admin_kv_put'
    key = 'cotacoes:volatilidade:v1'
    value = $payloadJson
    ttl = 86400
} | ConvertTo-Json -Compress

try {
    $response = Invoke-RestMethod -Uri 'https://api.vixradar.com/' -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 30
} catch {
    throw "Falha HTTP ao publicar volatilidade: $($_.Exception.Message)"
}
if (-not $response.ok) { throw "Worker recusou publicacao: $($response.erro)" }
Write-Host 'UPLOAD_OK key=cotacoes:volatilidade:v1 ttl=86400'