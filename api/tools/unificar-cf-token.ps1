#Requires -Version 5.1
<#
  Valida token unificado Cloudflare (DNS + Workers) e persiste em CLOUDFLARE_API_TOKEN (User).
  Uso: .\tools\unificar-cf-token.ps1 -Token 'cfut_...'
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Token
)

$ErrorActionPreference = 'Stop'
$AccountId = '7ac79fb1030e4e81115ef33c21a9b070'
$ZoneId = 'ea770942bf861c70bc0ce783c4ece5fa'
$Headers = @{ Authorization = "Bearer $Token" }

function Test-Cf {
  param([string]$Label, [scriptblock]$Call)
  try {
    $r = & $Call
    if ($r.success -eq $false) { throw ($r.errors | ConvertTo-Json -Compress) }
    Write-Host "[ok] $Label"
    return $true
  } catch {
    Write-Host "[falha] $Label -> $($_.Exception.Message)"
    return $false
  }
}

$verify = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/user/tokens/verify' -Headers $Headers
if (-not $verify.success) { throw 'Token invalido' }
Write-Host "Token id: $($verify.result.id)"

$zone = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/zones?name=vixradar.com' -Headers $Headers
Write-Host "Permissoes zona: $($zone.result[0].permissions -join ', ')"

$dnsOk = Test-Cf 'DNS read' { Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?per_page=1" -Headers $Headers }
$workerOk = Test-Cf 'Workers list' { Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts" -Headers $Headers }

if (-not ($dnsOk -and $workerOk)) {
  Write-Host ''
  Write-Host 'Token ainda nao unificado. No dashboard, adicione ao MESMO token DNS:' -ForegroundColor Yellow
  Write-Host '  - Account > Workers Scripts > Edit'
  Write-Host '  - Account > Workers KV Storage > Edit'
  Write-Host '  - Account > Workers Routes > Edit'
  Write-Host '  - Zone > Zone > Read (vixradar.com) — ja deve existir'
  return
}

[Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN', $Token, 'User')
$env:CLOUDFLARE_API_TOKEN = $Token
Write-Host ''
Write-Host 'CLOUDFLARE_API_TOKEN atualizado (escopo User).' -ForegroundColor Green
Write-Host 'Abra novo terminal ou reinicie o IDE para propagar.'

Set-Location (Split-Path $PSScriptRoot -Parent)
npx wrangler whoami 2>&1 | Select-Object -First 8