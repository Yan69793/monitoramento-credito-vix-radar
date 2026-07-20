#Requires -Version 5.1
<#
.SYNOPSIS
  Cria API Token Cloudflare com DNS Edit (zona vixradar.com) e publica SPF em send.vixradar.com.

.DESCRIPTION
  O CLOUDFLARE_API_TOKEN atual so tem worker:edit + zone:read — nao edita DNS nem tokens.
  Este script usa Global API Key + Email (perfil Cloudflare) para:
    1) Criar token "VIX Radar DNS+Workers" com DNS Edit + Workers (zona vixradar.com)
    2) Criar TXT SPF em send.vixradar.com se ausente

.PARAMETER Email
  Email da conta Cloudflare.

.PARAMETER GlobalApiKey
  Global API Key (My Profile > API Tokens > Global API Key).

.PARAMETER SkipTokenCreate
  Apenas cria o registro SPF usando credenciais informadas (token ja com DNS Edit).

.PARAMETER ApiToken
  Token existente com Zone DNS Edit (alternativa a Global API Key para passo SPF).
#>
param(
  [Parameter(Mandatory = $false)]
  [string]$Email,
  [Parameter(Mandatory = $false)]
  [string]$GlobalApiKey,
  [switch]$SkipTokenCreate,
  [string]$ApiToken
)

$ErrorActionPreference = 'Stop'
$AccountId = '7ac79fb1030e4e81115ef33c21a9b070'
$ZoneId = 'ea770942bf861c70bc0ce783c4ece5fa'
$ZoneName = 'vixradar.com'
# SPF1 (PENDENCIAS.md): softfail ~all trocado para hardfail -all, alinhando com o dominio raiz
# vixradar.com (ja -all). Nota: Ensure-SpfRecord abaixo so CRIA o registro se ausente - se
# send.vixradar.com ja tem o TXT antigo (~all) publicado, rodar este script NAO atualiza o
# valor ao vivo (a funcao ve "ja existe" e sai sem PATCH/PUT). Atualizar o registro existente
# exige edicao manual no painel Cloudflare DNS ou uma chamada dns_records PATCH dedicada -
# fora do escopo desta correcao (mudanca de DNS de producao exige aprovacao do operador).
$SpfContent = 'v=spf1 include:amazonses.com -all'

function Invoke-CfApi {
  param(
    [string]$Method,
    [string]$Uri,
    [object]$Body = $null,
    [hashtable]$Headers
  )
  $params = @{
    Method  = $Method
    Uri     = $Uri
    Headers = $Headers
  }
  if ($null -ne $Body) {
    $params['ContentType'] = 'application/json'
    $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
  }
  return Invoke-RestMethod @params
}

function Get-AuthHeadersFromGlobalKey {
  if (-not $Email -or -not $GlobalApiKey) {
    $Email = Read-Host 'Cloudflare Email'
    $sec = Read-Host 'Global API Key' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try {
      $GlobalApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
  }
  return @{
    'X-Auth-Email' = $Email
    'X-Auth-Key'   = $GlobalApiKey
    'Content-Type' = 'application/json'
  }
}

function Get-BearerHeaders {
  param([string]$Token)
  if (-not $Token) { $Token = Read-Host 'API Token com Zone DNS Edit' }
  return @{
    Authorization  = "Bearer $Token"
    'Content-Type' = 'application/json'
  }
}

function Ensure-SpfRecord {
  param([hashtable]$Headers)
  $list = Invoke-CfApi -Method GET -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?type=TXT&name=send.$ZoneName" -Headers $Headers
  if (-not $list.success) { throw "Falha ao listar DNS: $($list.errors | ConvertTo-Json -Compress)" }
  if ($list.result.Count -gt 0) {
    Write-Host "[ok] SPF ja existe em send.$ZoneName : $($list.result[0].content)"
    return $list.result[0]
  }
  $create = Invoke-CfApi -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records" -Headers $Headers -Body @{
    type    = 'TXT'
    name    = 'send'
    content = $SpfContent
    ttl     = 3600
    proxied = $false
    comment = 'Resend return-path SPF'
  }
  if (-not $create.success) { throw "Falha ao criar SPF: $($create.errors | ConvertTo-Json -Compress)" }
  Write-Host "[ok] SPF criado: send.$ZoneName -> $SpfContent"
  return $create.result
}

if (-not $SkipTokenCreate) {
  $gHeaders = Get-AuthHeadersFromGlobalKey
  Write-Host 'Buscando permission groups...'
  $groups = Invoke-CfApi -Method GET -Uri 'https://api.cloudflare.com/client/v4/user/tokens/permission_groups' -Headers $gHeaders
  if (-not $groups.success) { throw 'Global API Key invalida ou sem acesso a permission groups.' }

  $wanted = @(
    'Zone DNS Edit',
    'Zone Read',
    'Workers Scripts Edit',
    'Workers KV Storage Edit',
    'Account Settings Read'
  )
  $picked = @()
  foreach ($g in $groups.result) {
    if ($wanted -contains $g.name) { $picked += @{ id = $g.id; name = $g.name } }
  }
  if (-not ($picked | Where-Object { $_.name -eq 'Zone DNS Edit' })) {
    throw 'Permission group Zone DNS Edit nao encontrado.'
  }

  $tokenName = "VIX Radar DNS+Workers $(Get-Date -Format 'yyyy-MM-dd')"
  $policy = @{
    effect = 'allow'
    permission_groups = @($picked | ForEach-Object { @{ id = $_.id } })
    resources = @{
      "com.cloudflare.api.account.zone.$ZoneId" = '*'
      "com.cloudflare.api.account.$AccountId" = '*'
    }
  }

  Write-Host "Criando token: $tokenName"
  $created = Invoke-CfApi -Method POST -Uri 'https://api.cloudflare.com/client/v4/user/tokens' -Headers $gHeaders -Body @{
    name = $tokenName
    policies = @($policy)
  }
  if (-not $created.success) { throw "Falha ao criar token: $($created.errors | ConvertTo-Json -Compress)" }

  $newToken = $created.result.value
  Write-Host ''
  Write-Host '=== NOVO TOKEN (copie agora — so aparece uma vez) ===' -ForegroundColor Green
  Write-Host $newToken
  Write-Host ''
  Write-Host 'Atualize a variavel de ambiente (PowerShell permanente):'
  Write-Host "[Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN', '<token>', 'User')"
  Write-Host ''

  $bearer = Get-BearerHeaders -Token $newToken
  Ensure-SpfRecord -Headers $bearer | Out-Null
} else {
  $headers = if ($ApiToken) { Get-BearerHeaders -Token $ApiToken } else { Get-BearerHeaders }
  Ensure-SpfRecord -Headers $headers | Out-Null
}

Write-Host ''
Write-Host 'Validacao:'
Resolve-DnsName -Name "send.$ZoneName" -Type TXT -Server 1.1.1.1 -ErrorAction SilentlyContinue | Format-List Name, Strings