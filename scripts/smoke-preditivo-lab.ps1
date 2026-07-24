<#
.SYNOPSIS
  Smoke do lab preditivo (nao user-facing): gate HTTP + artefato KV.

.DESCRIPTION
  1. Health: versao Worker esperada.
  2. GET ?op=predictive_v1 sem auth -> 401 + lab_interno.
  3. GET com token lixo -> 401.
  4. Se ADMIN_PASSWORD disponivel (env ou api/.env ADMIN_PASSWORD):
     - GET com x-admin-password -> 200 (ou not_found) + lab_interno
     - POST admin_executar_predictive -> regenera KV, model_version lab
     - GET de novo confirma model_version / lab_interno
  5. admin_auto_login + JWT admin (mesmo password) -> GET predictive_v1 200

  Nunca imprime a senha. Exit 0 se checks obrigatorios passam; exit 1 se falha.
  Checks admin sao "soft-skip" se nao houver senha (exit 0 com aviso).

.EXAMPLE
  pwsh ./scripts/smoke-preditivo-lab.ps1
  $env:ADMIN_PASSWORD='***'; pwsh ./scripts/smoke-preditivo-lab.ps1
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = "https://api.vixradar.com",
  [string]$ExpectWorker = "v4.9.170"
)

$ErrorActionPreference = "Stop"
$fail = 0
function Ok($m) { Write-Host "OK  $m" -ForegroundColor Green }
function Bad($m) { Write-Host "FAIL $m" -ForegroundColor Red; $script:fail++ }
function Info($m) { Write-Host "INFO $m" -ForegroundColor DarkGray }

function Get-AdminPassword {
  if ($env:ADMIN_PASSWORD) { return $env:ADMIN_PASSWORD }
  $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) "api\.env"
  if (-not (Test-Path $envFile)) { return $null }
  foreach ($line in Get-Content $envFile -Encoding UTF8) {
    if ($line -match '^\s*ADMIN_PASSWORD\s*=\s*(.+)\s*$') {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  # 2026-07-24: migrado para DPAPI. Tenta helper, fallback ADMIN_PASSWORD env var.
  $helper = Join-Path (Split-Path -Parent $PSScriptRoot) 'api\Get-VixAdminCredential.ps1'
  if (Test-Path $helper) {
    $pwd = & $helper -AsPlainText 2>$null
    if ($pwd) { return $pwd }
  }
  if ($env:ADMIN_PASSWORD) { return $env:ADMIN_PASSWORD }
  return $null
}

Write-Host "=== smoke preditivo lab @ $BaseUrl ===" -ForegroundColor Cyan

# 1 Health
try {
  $h = Invoke-RestMethod -Uri $BaseUrl -Method Get -TimeoutSec 20
  if ($h.versao -eq $ExpectWorker -and $h.ok -eq $true) { Ok "health versao=$($h.versao)" }
  else { Bad "health inesperado: versao=$($h.versao) ok=$($h.ok) (esperado $ExpectWorker)" }
} catch {
  Bad "health request: $($_.Exception.Message)"
}

# 2 no auth
try {
  $r = Invoke-WebRequest -Uri "$BaseUrl/?op=predictive_v1" -Method Get -TimeoutSec 20 -SkipHttpErrorCheck
  $body = $r.Content | ConvertFrom-Json
  if ($r.StatusCode -eq 401 -and $body.lab_interno -eq $true) { Ok "GET predictive_v1 sem auth -> 401 lab_interno" }
  else { Bad "GET sem auth status=$($r.StatusCode) lab=$($body.lab_interno)" }
} catch {
  Bad "GET sem auth: $($_.Exception.Message)"
}

# 3 fake JWT
try {
  $r = Invoke-WebRequest -Uri "$BaseUrl/?op=predictive_v1" -Method Get -TimeoutSec 20 -SkipHttpErrorCheck -Headers @{ Authorization = "Bearer fake.token.here" }
  if ($r.StatusCode -eq 401) { Ok "GET predictive_v1 JWT lixo -> 401" }
  else { Bad "GET JWT lixo status=$($r.StatusCode)" }
} catch {
  Bad "GET JWT lixo: $($_.Exception.Message)"
}

$pwd = Get-AdminPassword
if (-not $pwd) {
  Info "ADMIN_PASSWORD ausente: checks admin skipped (set env ADMIN_PASSWORD ou api/.env)"
  if ($fail -gt 0) { exit 1 }
  Write-Host "SMOKE PARTIAL (public OK, admin skipped)" -ForegroundColor Yellow
  exit 0
}

# 4 password header
try {
  $r = Invoke-WebRequest -Uri "$BaseUrl/?op=predictive_v1" -Method Get -TimeoutSec 30 -SkipHttpErrorCheck -Headers @{ "x-admin-password" = $pwd }
  $body = $r.Content | ConvertFrom-Json
  if ($r.StatusCode -eq 200 -and $body.lab_interno -eq $true -and ($body.ok -eq $true -or $body.source -eq "not_found")) {
    Ok "GET predictive_v1 x-admin-password -> $($r.StatusCode) auth_via=$($body.auth_via) model=$($body.model_version)"
  } else {
    Bad "GET x-admin-password status=$($r.StatusCode) ok=$($body.ok) erro=$($body.erro)"
  }
} catch {
  Bad "GET x-admin-password: $($_.Exception.Message)"
}

# 5 regenerate pipeline
try {
  $payload = @{ action = "admin_executar_predictive"; admin_senha = $pwd } | ConvertTo-Json -Compress
  $r = Invoke-WebRequest -Uri $BaseUrl -Method Post -TimeoutSec 120 -SkipHttpErrorCheck -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload))
  $body = $r.Content | ConvertFrom-Json
  if ($r.StatusCode -eq 200 -and $body.ok -eq $true -and $body.lab_interno -eq $true) {
    Ok "POST admin_executar_predictive -> ok com_score=$($body.com_score) model=$($body.model_version) auth_via=$($body.auth_via)"
    if ($body.model_version -notmatch 'lab_interno') { Bad "model_version sem lab_interno: $($body.model_version)" }
    if ($body.user_facing -ne $false) { Bad "user_facing deveria ser false" }
  } else {
    Bad "POST executar status=$($r.StatusCode) ok=$($body.ok) erro=$($body.erro)"
  }
} catch {
  Bad "POST executar: $($_.Exception.Message)"
}

# 6 re-read KV
try {
  $r = Invoke-WebRequest -Uri "$BaseUrl/?op=predictive_v1" -Method Get -TimeoutSec 30 -SkipHttpErrorCheck -Headers @{ "x-admin-password" = $pwd }
  $body = $r.Content | ConvertFrom-Json
  if ($r.StatusCode -eq 200 -and $body.ok -eq $true -and $body.lab_interno -eq $true -and $body.model_version -match 'lab_interno') {
    Ok "KV predictive_v1:latest model=$($body.model_version) total=$($body.total_emissores) com_score=$($body.com_score)"
  } else {
    Bad "re-read KV status=$($r.StatusCode) model=$($body.model_version)"
  }
} catch {
  Bad "re-read KV: $($_.Exception.Message)"
}

# 7 JWT admin path
try {
  $loginBody = @{ action = "admin_auto_login"; admin_senha = $pwd } | ConvertTo-Json -Compress
  $rLogin = Invoke-WebRequest -Uri $BaseUrl -Method Post -TimeoutSec 30 -SkipHttpErrorCheck -ContentType "application/json" -Body ([System.Text.Encoding]::UTF8.GetBytes($loginBody))
  $login = $rLogin.Content | ConvertFrom-Json
  if ($rLogin.StatusCode -eq 200 -and $login.token) {
    $r = Invoke-WebRequest -Uri "$BaseUrl/?op=predictive_v1" -Method Get -TimeoutSec 30 -SkipHttpErrorCheck -Headers @{ Authorization = "Bearer $($login.token)" }
    $body = $r.Content | ConvertFrom-Json
    if ($r.StatusCode -eq 200 -and $body.lab_interno -eq $true -and $body.auth_via -eq "jwt_admin") {
      Ok "GET predictive_v1 JWT admin -> 200 auth_via=jwt_admin"
    } else {
      Bad "JWT admin GET status=$($r.StatusCode) via=$($body.auth_via) erro=$($body.erro)"
    }
  } else {
    Bad "admin_auto_login falhou status=$($rLogin.StatusCode)"
  }
} catch {
  Bad "JWT admin path: $($_.Exception.Message)"
}

if ($fail -gt 0) {
  Write-Host "SMOKE FAILED ($fail)" -ForegroundColor Red
  exit 1
}
Write-Host "SMOKE PASSED" -ForegroundColor Green
exit 0
