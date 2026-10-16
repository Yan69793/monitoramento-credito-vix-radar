# Prova local da allowlist. Sem credenciais, rede ou publicacao.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\vixradar-pages-bundle-gate.ps1')
$bench = Join-Path $PSScriptRoot ('_tmp_pages_bundle_' + [guid]::NewGuid().ToString('N'))
$expectedRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
$bench = [IO.Path]::GetFullPath($bench)
if (-not $bench.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Bancada fora do diretorio scripts.'
}
function Put-Fixture([string]$Relative) {
  $file = Join-Path $bench $Relative
  $parent = Split-Path -Parent $file
  $null = New-Item -ItemType Directory -Force -Path $parent
  [IO.File]::WriteAllText($file, 'fixture sem dados reais')
}
try {
  $null = New-Item -ItemType Directory -Path $bench
  foreach ($file in @('index.html','_headers','app\js\api.js','manual\index.html','apresentacao\index.html')) { Put-Fixture $file }
  if (@(Get-VixPagesUnexpectedFiles $bench).Count -ne 0) { throw 'Pacote legitimo foi bloqueado.' }
  Write-Host 'OK pacote legitimo PASSA'
  foreach ($file in @('index.html.logo-backup-20260930','.env','app\js\api.js.bak','app\js\extra.js','manual\backup.html')) {
    Put-Fixture $file
    $unexpected = @(Get-VixPagesUnexpectedFiles $bench)
    if ($unexpected.Count -ne 1 -or $unexpected[0] -cne $file.Replace('\','/')) { throw "Arquivo indevido nao bloqueado: $file" }
    Write-Host "OK arquivo indevido BLOQUEIA $file"
    Remove-Item -LiteralPath (Join-Path $bench $file) -Force
  }
  $null = New-Item -ItemType Junction -Path (Join-Path $bench 'manual\link') -Target (Join-Path $bench 'app')
  if (@(Get-VixPagesUnexpectedFiles $bench) -cnotcontains 'manual/link') { throw 'Junction nao foi bloqueada.' }
  Write-Host 'OK junction BLOQUEIA'
  # Remove apenas a junction, sem seguir o destino durante a limpeza.
  [IO.Directory]::Delete((Join-Path $bench 'manual\link'))
  Write-Host 'TESTE ALLOWLIST PAGES: PASS'
} finally {
  if (Test-Path -LiteralPath $bench) { Remove-Item -LiteralPath $bench -Recurse -Force }
}
