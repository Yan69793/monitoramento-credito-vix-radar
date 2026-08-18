<#
.SYNOPSIS
  Gera deterministicamente o artefato versionado do Worker a partir de api/src/worker.js.

.DESCRIPTION
  O Worker legado foi recuperado como uma baseline pre-empacotada.
  Nunca edite api/v4.*.js diretamente; altere api/src/worker.js e rode este script.

  SENTRY1 (v4.9.184): a linha antiga desta secao dizia que o Wrangler "deve
  publicar com no_bundle=true". Isso nunca foi configurado (nem no toml nem na
  CLI) e agora esta proibido: o bundle tem import real de @sentry/cloudflare que
  so resolve com o esbuild padrao do Wrangler ligado. Ver nota no wrangler.toml.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot
$apiDir = Join-Path $projectRoot 'api'
$sourcePath = Join-Path $apiDir 'src\worker.js'
$normalizedVersion = $Version -replace '\.js$', ''

if ($normalizedVersion -notmatch '^v4\.9\.\d+$') {
  throw "Versao invalida: $Version. Esperado v4.9.NNN"
}
if (-not (Test-Path -LiteralPath $sourcePath)) {
  throw "Fonte canonica ausente: $sourcePath"
}

$sourceText = [System.IO.File]::ReadAllText($sourcePath)
$placeholderCount = ([regex]::Matches($sourceText, [regex]::Escape('__WORKER_VERSION__'))).Count
if ($placeholderCount -ne 1) {
  throw "Fonte deve conter exatamente um __WORKER_VERSION__; encontrado: $placeholderCount"
}
if ($sourceText -match '(?m)^//# sourceMappingURL=') {
  throw 'Fonte contem sourceMappingURL orfao; remova antes de gerar o artefato.'
}

$artifactText = $sourceText.Replace('__WORKER_VERSION__', $normalizedVersion)
$artifactPath = Join-Path $apiDir ($normalizedVersion + '.js')
[System.IO.File]::WriteAllText($artifactPath, $artifactText, (New-Object System.Text.UTF8Encoding($false)))

& node --check $artifactPath
if ($LASTEXITCODE -ne 0) {
  throw "node --check falhou para $artifactPath"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash
Write-Host "ARTEFATO_OK path=$artifactPath sha256=$hash"
exit 0