#Requires -Version 5.1
<#
  Mostra status dos tokens Cloudflare (Workers + DNS) e indica se estao unificados.
#>
$ErrorActionPreference = 'Stop'
$AccountId = '7ac79fb1030e4e81115ef33c21a9b070'
$ZoneId = 'ea770942bf861c70bc0ce783c4ece5fa'

function Test-Token {
  param([string]$Label, [string]$Token)
  if (-not $Token) { return @{ label = $Label; present = $false } }
  $h = @{ Authorization = "Bearer $Token" }
  $verify = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/user/tokens/verify' -Headers $h
  $dnsOk = $false
  $workerOk = $false
  try {
    $d = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?per_page=1" -Headers $h
    $dnsOk = $d.success
  } catch { $dnsOk = $false }
  try {
    $w = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts" -Headers $h
    $workerOk = $w.success
  } catch { $workerOk = $false }
  return @{
    label = $Label
    present = $true
    id = $verify.result.id
    dns = $dnsOk
    workers = $workerOk
    unified = ($dnsOk -and $workerOk)
  }
}

$worker = [Environment]::GetEnvironmentVariable('CLOUDFLARE_API_TOKEN', 'User')
$dns = [Environment]::GetEnvironmentVariable('CLOUDFLARE_DNS_TOKEN', 'User')

$results = @(
  (Test-Token -Label 'CLOUDFLARE_API_TOKEN' -Token $worker)
  (Test-Token -Label 'CLOUDFLARE_DNS_TOKEN' -Token $dns)
)

$results | ForEach-Object {
  if (-not $_.present) {
    Write-Host "[ausente] $($_.label)"
    return
  }
  $flags = @()
  if ($_.dns) { $flags += 'dns' }
  if ($_.workers) { $flags += 'workers' }
  $state = if ($_.unified) { 'UNIFICADO' } else { 'parcial' }
  Write-Host "[$state] $($_.label) id=$($_.id) perms=$($flags -join '+')"
}

$anyUnified = $results | Where-Object { $_.unified }
if ($anyUnified) {
  Write-Host ''
  Write-Host 'Token unificado disponivel — use CLOUDFLARE_API_TOKEN para tudo.' -ForegroundColor Green
} else {
  Write-Host ''
  Write-Host 'Modo dual-token ativo: deploy/wrangler -> CLOUDFLARE_API_TOKEN | DNS -> CLOUDFLARE_DNS_TOKEN' -ForegroundColor Yellow
  Write-Host 'Para unificar: edite o token DNS no dashboard e adicione Workers Scripts/KV/Routes Edit.'
  Write-Host 'URL: https://dash.cloudflare.com/profile/api-tokens'
}