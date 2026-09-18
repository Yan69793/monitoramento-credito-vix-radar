<#
.SYNOPSIS
  Verifica drift entre producao e repo para Worker e frontend do VIX Radar.

.DESCRIPTION
  Roda os mesmos checks do canonical-test.yml localmente. Consulta producao
  (Worker health + Pages version.json + HTML CACHE_VERSION) e compara com o
  estado do repo (wrangler.toml main + app/version.json). Sai com 0 se tudo
  bate, 1 se ha drift, 2 se houve erro na consulta.

  NAO faz deploy, NAO altera nada. Read-only, seguro rodar a qualquer momento.

.EXAMPLE
  pwsh ./scripts/check-drift.ps1
  pwsh ./scripts/check-drift.ps1 -Quiet
#>
[CmdletBinding()]
param(
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$toml   = Join-Path $root "api\wrangler.toml"
$verJson = Join-Path $root "app\version.json"

$fail = 0

function Write-Status($symbol, $message) {
  if (-not $Quiet) {
    $color = switch ($symbol) {
      'OK'  { 'Green' }
      'ERR' { 'Red' }
      'WARN' { 'Yellow' }
      default { 'White' }
    }
    Write-Host "[$symbol] $message" -ForegroundColor $color
  }
}

function Fail($message) {
  Write-Status 'ERR' $message
  $script:fail = 1
}

# ── Worker ────────────────────────────────────────────────────────────────

# 1. Versao no repo
if (-not (Test-Path $toml)) {
  Fail "wrangler.toml ausente: $toml"
  $expectedWorker = $null
} else {
  $tomlRaw = Get-Content $toml -Raw
  $m = [regex]::Match($tomlRaw, '(?m)^\s*main\s*=\s*"([^"]+)"')
  if ($m.Success) {
    $expectedWorker = $m.Groups[1].Value -replace '\.js$', ''
    Write-Status 'OK' "Repo Worker: $expectedWorker (wrangler.toml)"
  } else {
    Fail "Nao encontrei main em wrangler.toml"
    $expectedWorker = $null
  }
}

# 2. Versao em producao
try {
  $health = Invoke-RestMethod -Uri "https://api.vixradar.com/?_=$(Get-Date -Format 'yyyyMMddHHmmss')" -TimeoutSec 15 -Headers @{ "Cache-Control"="no-cache" }
  $prodWorker = $health.versao
  $prodOk = $health.ok
  $prodKv = $health.bindings.kv
  $prodTel = $health.bindings.telemetria

  Write-Status 'OK' "Producao Worker: $prodWorker (ok=$prodOk kv=$prodKv tel=$prodTel)"

  if (-not $prodOk) { Fail "Worker health ok=false" }
  if (-not $prodKv) { Fail "Binding KV ausente em producao" }
  if (-not $prodTel) { Fail "Binding telemetria ausente em producao" }

  if ($expectedWorker -and $prodWorker -ne $expectedWorker) {
    Fail "DRIFT Worker: producao=$prodWorker vs repo=$expectedWorker"
  } elseif ($expectedWorker) {
    Write-Status 'OK' "Worker: sem drift ($prodWorker)"
  }
} catch {
  Fail "Falha ao consultar Worker em producao: $_"
}

# ── Frontend ──────────────────────────────────────────────────────────────

# 3. Versao no repo
if (-not (Test-Path $verJson)) {
  Fail "app/version.json ausente"
  $expectedFrontend = $null
} else {
  $expectedFrontend = (Get-Content $verJson -Raw | ConvertFrom-Json).version
  if ($expectedFrontend) {
    Write-Status 'OK' "Repo Frontend: $expectedFrontend (app/version.json)"
  } else {
    Fail "app/version.json sem campo version"
  }
}

# 4. Versao em producao (version.json)
try {
  $prodVerJson = Invoke-RestMethod -Uri "https://vixradar.com/version.json?_=$(Get-Date -Format 'yyyyMMddHHmmss')" -TimeoutSec 15 -Headers @{ "Cache-Control"="no-cache" }
  $prodFrontend = $prodVerJson.version
  Write-Status 'OK' "Producao Frontend (version.json): $prodFrontend"

  if ($expectedFrontend -and $prodFrontend -ne $expectedFrontend) {
    Fail "DRIFT Frontend (version.json): producao=$prodFrontend vs repo=$expectedFrontend"
  } elseif ($expectedFrontend) {
    Write-Status 'OK' "Frontend version.json: sem drift ($prodFrontend)"
  }
} catch {
  Fail "Falha ao consultar version.json em producao: $_"
}

# 5. CACHE_VERSION no HTML de producao
try {
  $prodHtml = Invoke-RestMethod -Uri "https://vixradar.com/?_=$(Get-Date -Format 'yyyyMMddHHmmss')" -TimeoutSec 15 -Headers @{ "Cache-Control"="no-cache" }
  $m = [regex]::Match($prodHtml, 'CACHE_VERSION\s*=\s*"([^"]+)"')
  if ($m.Success) {
    $prodCache = $m.Groups[1].Value
    Write-Status 'OK' "Producao CACHE_VERSION: $prodCache"

    if ($expectedFrontend -and $prodCache -ne $expectedFrontend) {
      Fail "DRIFT CACHE_VERSION no HTML: producao=$prodCache vs esperado=$expectedFrontend"
    } elseif ($expectedFrontend) {
      Write-Status 'OK' "CACHE_VERSION: sem drift ($prodCache)"
    }
  } else {
    Fail "Nao encontrei CACHE_VERSION no HTML de producao"
  }
} catch {
  Fail "Falha ao consultar HTML de producao: $_"
}

# ── Documentacao (CFG-04) ─────────────────────────────────────────────────

# 6. Versao declarada na documentacao x versao canonica do repo.
# Este check e local e nao depende de rede: le a chave `main` de
# api/wrangler.toml (o bundle que sobe) e compara com as linhas de versao do
# Worker no README.md. Existe porque o drift ficou invisivel entre 16/09 e
# 18/09/2026 — o README parou no v4.9.255 enquanto o wrangler.toml andava para
# v4.9.257 por um commit que nao passou pelo deploy-worker.ps1, que e o unico
# lugar que roda o sync-version-docs.ps1. Quem consertava a doc era o deploy;
# contornado o deploy, nada percebia.
$checkVer = Join-Path $PSScriptRoot "check-version-drift.mjs"
if (-not (Test-Path $checkVer)) {
  Fail "check-version-drift.mjs ausente: $checkVer"
} else {
  try {
    $saidaVer = (& node $checkVer 2>&1 | Out-String).Trim()
    $exitVer  = $LASTEXITCODE
  } catch {
    $saidaVer = "$_"
    $exitVer  = 1
  }
  if ($exitVer -ne 0) {
    Fail $saidaVer
  } else {
    Write-Status 'OK' $saidaVer
  }
}

# ── Resultado ─────────────────────────────────────────────────────────────

if ($fail -eq 0) {
  Write-Host "`nDRIFT CHECK OK — producao e repo sincronizados." -ForegroundColor Green
  exit 0
} else {
  Write-Host "`nDRIFT CHECK FALHOU — reconciliacao necessaria." -ForegroundColor Red
  exit 1
}
