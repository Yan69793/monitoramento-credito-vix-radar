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
  [switch]$SkipValidation,
  [switch]$SkipGit
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
# NAO sai daqui: o passo 6 (sync com o git) precisa rodar mesmo sem validacao,
# senao -SkipValidation reintroduz o drift que este script existe para evitar.
$ok = $true
if ($SkipValidation) {
  Write-Host "`nValidacao pulada (-SkipValidation)." -ForegroundColor DarkGray
} else {

Write-Host "`nValidando producao..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
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

}  # fim do else de -SkipValidation

if (-not $ok) { Write-Host "`nDEPLOY publicado mas validacao divergiu — investigar propagacao/cache. NADA commitado." -ForegroundColor Red; exit 2 }

# --- 5.5 Sincroniza a versao declarada em CLAUDE.md/README.md --------------
# Mesmo racional do deploy-worker.ps1: sem isto a doc so atualiza se alguem
# lembrar depois do deploy.
& (Join-Path $PSScriptRoot "sync-version-docs.ps1") -FrontendVersion $ver

# --- 6. Sync com o git -----------------------------------------------------
# O version.json e GERADO por este script (passo 2). Sem commitar, o repo fica
# declarando a versao anterior enquanto producao ja avancou, e o canonical-test
# acusa drift de frontend. Foi exatamente o que aconteceu com v201.75 (deploy
# 13/07, repo em v201.74 ate 15/07). O deploy so termina quando o GitHub sabe.
if ($SkipGit) {
  Write-Host "`nGit pulado (-SkipGit)." -ForegroundColor DarkGray
  Write-Host "ATENCAO: producao esta em $ver e o repo NAO sabe. O canonical-test vai acusar drift ate voce commitar." -ForegroundColor Yellow
  exit 0
}

Write-Host "`nSincronizando o git..." -ForegroundColor Yellow
Push-Location $root
try {
  git add "app/version.json" "app/deploy_zip/version.json" "app/index.html" "app/deploy_zip/index.html" "CLAUDE.md" "README.md"
  if ($LASTEXITCODE -ne 0) { Fail "git add falhou (exit $LASTEXITCODE)." }

  $staged = git diff --cached --name-only
  if (-not $staged) {
    Write-Host "  Nada a commitar (repo ja sincronizado)." -ForegroundColor DarkGray
  } else {
    git commit -m "chore(frontend): deploy $ver em producao"
    if ($LASTEXITCODE -ne 0) { Fail "git commit falhou (exit $LASTEXITCODE)." }
    Write-Host "  commit criado" -ForegroundColor Green
  }

  git push origin HEAD
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nDEPLOY OK mas o PUSH FALHOU — o GitHub ainda nao sabe que producao esta em $ver." -ForegroundColor Red
    Write-Host "O canonical-test vai acusar drift ate o push passar. Resolva e rode: git push origin HEAD" -ForegroundColor Red
    exit 3
  }
  Write-Host "  push OK" -ForegroundColor Green
} finally {
  Pop-Location
}

Write-Host "`nDEPLOY OK — producao em $ver, repo e GitHub sincronizados." -ForegroundColor Green
exit 0
