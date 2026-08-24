<#
.SYNOPSIS
  Alinha os pontos de cache version do frontend num unico passo: CACHE_VERSION,
  o <script src> do index.html e todos os imports ?v= no bundle JS.

.DESCRIPTION
  CACHEBUMP1 (20/08, terceira ocorrencia): o alinhamento manual do ?v=
  a cada deploy Pages quebrou o painel tres vezes seguidas. O deploy-pages.ps1
  aborta no gate 3.4 se os pontos divergirem, mas o correto e essa troca ser
  um comando unico, nao um lembrete.

  Este script le a versao corrente, calcula a proxima (auto) ou aceita a nova
  por parametro, e substitui ?v=<antiga> por ?v=<nova> em:
    - app/index.html            (<script src> + CACHE_VERSION + window.CACHE_VERSION)
    - app/deploy_zip/index.html (copia de deploy, mantem espelho)
    - app/js/admin-bootstrap.js (imports admin + api + router)
    - app/js/admin-router.js, app/js/api.js

  O script e idempotente: se a versao alvo ja estiver nos pontos, nada muda.

.EXAMPLE
  pwsh ./scripts/bump-cache-version.ps1 -NewVersion v203.1
  pwsh ./scripts/bump-cache-version.ps1           # ++ a partir da atual
#>
[CmdletBinding()]
param(
  [string]$NewVersion
)

$ErrorActionPreference = "Stop"

$root     = Split-Path -Parent $PSScriptRoot
$paths    = @(
  (Join-Path $root "app/index.html"),
  (Join-Path $root "app/deploy_zip/index.html"),
  (Join-Path $root "app/js/admin-bootstrap.js"),
  (Join-Path $root "app/js/admin-router.js"),
  (Join-Path $root "app/js/api.js")
)
# Modulos admin adicionais que carregam ?v= (se existirem no bundle)
foreach ($m in @("shared","modules","engajamento","metricas","fase3")) {
  $p = Join-Path $root "app/js/admin/$m.js"
  if (Test-Path $p) { $paths += $p }
}
$paths = $paths | Sort-Object -Unique

# --- 1. Descobrir versao corrente e alvo -------------
$indexPath = Join-Path $root "app/index.html"
$current   = $null
if (Test-Path $indexPath) {
  $raw = [IO.File]::ReadAllText($indexPath)
  $m = [regex]::Match($raw, 'CACHE_VERSION=["'']?v([0-9]+)\.([0-9]+)[^0-9]')
  if ($m.Success) {
    $current = "v$($m.Groups[1].Value).$($m.Groups[2].Value)"
  }
}
if (-not $current) {
  throw "Nao achei CACHE_VERSION=v<N>.<N> em app/index.html. Algo estranho, aborto."
}

if (-not $NewVersion) {
  $mm  = [regex]::Match($current, 'v([0-9]+)\.([0-9]+)')
  $nn  = [int]$mm.Groups[1].Value
  $sub = [int]$mm.Groups[2].Value + 1
  $NewVersion = "v$nn.$sub"
}

if ($NewVersion -notmatch '^v[0-9]+\.[0-9]+$') {
  throw "Versao invalida '$NewVersion'. Use o formato v<N>.<N> (ex.: v203.1)."
}
if ($NewVersion -eq $current) {
  Write-Host "Ja esta em $current, nada a alterar." -ForegroundColor DarkGray
  return
}

# --- 2. Substituir em cada arquivo -------------------
$oldVer = $current
$newVer = $NewVersion
$changed = @()

function Replace-InFile {
  param([string]$Path, [string]$Old, [string]$New)
  if (-not (Test-Path $Path)) { return $false }
  $before = [IO.File]::ReadAllText($Path)
  # Nucleo numerico sem o "v" (para ?v=<num>). Ex.: "202.30" a partir de "v202.30"
  $oldNum = ($Old -replace '^v', '')
  $newNum = ($New -replace '^v', '')
  # Escapa o ponto para nao casar "qualquer char" na regex.
  # So o lado do PADRAO precisa de escape; a substituicao usa o valor literal.
  $oldRe   = [regex]::Escape($Old)
  $oldNumRe = [regex]::Escape($oldNum)
  # CACHE_VERSION=<ver> entre aspas, ancorado no prefixo CACHE_VERSION= (nao a
  # troca generica de aspas): so o literal CACHE_VERSION="v202.30" muda, nada
  # de copy/UI/changelog que guarde v<n>.<n> entre aspas.
  $after = [regex]::Replace($before, 'CACHE_VERSION="' + $oldRe + '"', 'CACHE_VERSION="' + $New + '"')
  # ?v=<num> sem o "v", com lookahead (?![0-9]) para nao ser prefixo de outra
  # versao (202.3 NAO casa 202.30). Corrige a colisao de substring.
  $after = [regex]::Replace($after, '(\?v=)' + $oldNumRe + '(?![0-9])', '${1}' + $newNum)
  # ?v=v<n>.<n> (raro, mantem simetria) com o mesmo lookahead.
  $after = [regex]::Replace($after, '(\?v=)' + $oldRe + '(?![0-9.])', '${1}' + $New)
  if ($after -ne $before) {
    $enc = New-Object System.Text.UTF8Encoding($true)   # BOM, como o resto do projeto
    [IO.File]::WriteAllText($Path, $after, $enc)
    return $true
  }
  return $false
}

foreach ($p in $paths) {
  if (Replace-InFile $p $oldVer $newVer) { $changed += $p.Replace($root, "") }
}

if ($changed.Count -eq 0) {
  Write-Host "Nenhum arquivo tinha '$oldVer' para trocar. Confira se a versao alvo ja esta aplicada." -ForegroundColor Yellow
  return
}

Write-Host "Cache bump $oldVer -> $newVer" -ForegroundColor Cyan
$changed | ForEach-Object { Write-Host "  + $_" }
