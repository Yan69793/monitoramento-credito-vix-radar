<#
.SYNOPSIS
  Deploy do frontend VIX Radar (Cloudflare Pages) — idempotente e validado.

.DESCRIPTION
  1. Sincroniza app/index.html -> app/deploy_zip/ (a raiz vence).
  2. Extrai CACHE_VERSION do index.html e regenera version.json (deploy_zip + app/).
  3. Confere que os 4 arquivos do bundle existem.
  4. Roda `wrangler pages deploy ./app/deploy_zip`.
  5. Valida em producao (vixradar.com): CACHE_VERSION, version.json apex+www.

  CREDENCIAL: le CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID de variaveis de
  ambiente. NUNCA hardcode token neste arquivo (regra inviolavel do projeto).
  Configure uma vez (User scope) com scripts/setup-deploy-credential.ps1 ou:
    [Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN','<token>','User')
    [Environment]::SetEnvironmentVariable('CLOUDFLARE_ACCOUNT_ID','<id>','User')

.EXAMPLE
  pwsh ./scripts/deploy-pages.ps1
  pwsh ./scripts/deploy-pages.ps1 -SkipValidation
#>
[CmdletBinding()]
param(
  [string]$ProjectName = "radar-credito",
  [string]$Branch = "main",
  [switch]$SkipValidation
)

$ErrorActionPreference = "Stop"
$root    = Split-Path -Parent $PSScriptRoot
$appDir  = Join-Path $root "app"
$zipDir  = Join-Path $appDir "deploy_zip"
$indexSrc = Join-Path $appDir "index.html"

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

# --- 0. Pre-requisitos ----------------------------------------------------
if (-not $env:CLOUDFLARE_API_TOKEN) {
  Fail "CLOUDFLARE_API_TOKEN ausente. Configure a variavel de ambiente (User scope) antes de deployar. Veja scripts/setup-deploy-credential.ps1."
}
if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
  Fail "CLOUDFLARE_ACCOUNT_ID ausente. Configure a variavel de ambiente (User scope)."
}
if (-not (Test-Path $indexSrc)) { Fail "Nao achei $indexSrc" }

# --- 1. CACHE_VERSION ------------------------------------------------------
$html = Get-Content $indexSrc -Raw
$m = [regex]::Match($html, 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"')
if (-not $m.Success) { Fail "Nao encontrei CACHE_VERSION em index.html" }
$ver = $m.Groups[1].Value
Write-Host "CACHE_VERSION detectada: $ver" -ForegroundColor Cyan

# --- 2. Sincroniza deploy_zip (raiz vence) ---------------------------------
Copy-Item -Force $indexSrc (Join-Path $zipDir "index.html")
foreach ($f in @("_headers","_routes.json","landing-demo.json")) {
  $srcF = Join-Path $appDir $f
  if (Test-Path $srcF) { Copy-Item -Force $srcF (Join-Path $zipDir $f) }
}
$adminSrc = Join-Path $appDir "admin"
$adminDst = Join-Path $zipDir "admin"
if (Test-Path $adminSrc) {
  if (Test-Path $adminDst) { Remove-Item -Recurse -Force $adminDst }
  Copy-Item -Recurse -Force $adminSrc $adminDst
  Write-Host "admin/ copiado para deploy_zip" -ForegroundColor Cyan
}
$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$verJson = "{`"version`":`"$ver`",`"deployed_at`":`"$ts`"}"
Set-Content -NoNewline -Path (Join-Path $zipDir "version.json") -Value $verJson
Set-Content -NoNewline -Path (Join-Path $appDir "version.json") -Value $verJson
Write-Host "deploy_zip sincronizado + version.json gerado ($ts)" -ForegroundColor Cyan

# --- 3. Confere o bundle (4 arquivos) --------------------------------------
foreach ($f in @("index.html","_headers","_routes.json","version.json","landing-demo.json")) {
  if (-not (Test-Path (Join-Path $zipDir $f))) { Fail "Bundle incompleto: falta $f em deploy_zip" }
}
foreach ($af in @("vr-admin-shared.js","vr-admin-modules.js","vr-admin-engajamento.js","vr-admin-metricas.js","vr-admin-fase3.js")) {
  if (-not (Test-Path (Join-Path $zipDir "admin\$af"))) {
    Fail "Bundle incompleto: falta admin/$af em deploy_zip"
  }
}

# --- 4. Deploy -------------------------------------------------------------
Write-Host "`nDeployando para Cloudflare Pages ($ProjectName / $Branch)..." -ForegroundColor Yellow
npx wrangler pages deploy "$zipDir" --project-name=$ProjectName --branch=$Branch --commit-dirty=true
if ($LASTEXITCODE -ne 0) { Fail "wrangler pages deploy falhou (exit $LASTEXITCODE)" }

# --- 5. Validacao em producao ----------------------------------------------
if ($SkipValidation) { Write-Host "`nValidacao pulada (-SkipValidation)." -ForegroundColor DarkGray; exit 0 }

Write-Host "`nValidando producao..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
$ok = $true
try {
  $vj = Invoke-RestMethod -Uri "https://vixradar.com/version.json?_=$([guid]::NewGuid())" -Headers @{ "Cache-Control"="no-cache" }
  if ($vj.version -eq $ver) { Write-Host "  version.json apex: $($vj.version) OK" -ForegroundColor Green }
  else { Write-Host "  version.json apex: $($vj.version) (esperado $ver)" -ForegroundColor Red; $ok = $false }
} catch { Write-Host "  Falha ao ler version.json: $_" -ForegroundColor Red; $ok = $false }
try {
  $page = Invoke-WebRequest -Uri "https://vixradar.com/?_=$([guid]::NewGuid())" -UseBasicParsing
  if ($page.Content -match "CACHE_VERSION=`"$([regex]::Escape($ver))`"") { Write-Host "  CACHE_VERSION no HTML: $ver OK" -ForegroundColor Green }
  else { Write-Host "  CACHE_VERSION no HTML divergente do esperado ($ver)" -ForegroundColor Red; $ok = $false }
} catch { Write-Host "  Falha ao ler index.html: $_" -ForegroundColor Red; $ok = $false }

if ($ok) { Write-Host "`nDEPLOY OK — producao em $ver" -ForegroundColor Green; exit 0 }
else { Write-Host "`nDEPLOY publicado mas validacao divergiu — investigar propagacao/cache." -ForegroundColor Red; exit 2 }
