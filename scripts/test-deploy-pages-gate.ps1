<#
.SYNOPSIS
  Prova de regressao do DRIFT-CONTEUDO1 (2026-09-08): o gate fail-closed do
  deploy-pages.ps1 que aborta deploy quando app/index.html diverge de
  deploy_zip/index.html com CACHE_VERSION identica.

.DESCRIPTION
  Caso real: mudancas D2 (06/09/2026) entraram no repo app/index.html sob o
  rotulo v202.42 e a producao seguiu servindo o bundle anterior (sem D2) com o
  MESMO v202.42. Quem compara so a versao conclui "sem drift" e o sync do
  deploy-pages.ps1 apagaria a divergencia antes de qualquer gate enxergar.
  O gate roda ANTES do sync e so bloqueia o par perigoso:

    1. conteudo diferente + CACHE_VERSION igual     => BLOQUEIA (drift)
    2. conteudo diferente + CACHE_VERSION diferente => PASSA (bump em voo;
       o sync do passo 2 publica o conteudo novo sob o rotulo novo)
    3. conteudo igual (mesmo com EOL diferente)     => PASSA

  Este teste roda a FUNCAO REAL (dot-source de
  scripts/lib/vixradar-pages-content-gate.ps1, a mesma que o deploy-pages.ps1
  carrega) contra uma bancada isolada sob scripts/_tmp_pages_gate_test/.
  Nao toca app/, deploy_zip nem producao.

.EXAMPLE
  powershell.exe -NoProfile -File scripts/test-deploy-pages-gate.ps1
  exit 0 = passa (3 casos + EOL + wiring do deploy-pages.ps1)
#>
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$root   = $PSScriptRoot                      # scripts/
$bench  = Join-Path $root "_tmp_pages_gate_test"
$lib    = Join-Path (Join-Path $root "lib") "vixradar-pages-content-gate.ps1"
$deploy = Join-Path $root "deploy-pages.ps1"

if (-not (Test-Path $lib))    { Write-Host "FALHA lib nao encontrada: $lib"; exit 1 }
if (-not (Test-Path $deploy)) { Write-Host "FALHA deploy-pages.ps1 nao encontrado: $deploy"; exit 1 }

. $lib

if (-not (Get-Command Get-VixPagesContentDrift -ErrorAction SilentlyContinue)) {
  Write-Host "FALHA funcao Get-VixPagesContentDrift nao carregada pelo dot-source"
  exit 1
}

$pass = $true

function New-Fixture($dir, $name, $conteudo, $versao, [switch]$Crlf) {
  $linha = '<script>const CACHE_VERSION="' + $versao + '";window.CACHE_VERSION="' + $versao + '";</script>'
  $corpo = $conteudo
  $texto = $linha + "`n" + $corpo
  if ($Crlf) { $texto = $texto -replace "`n", "`r`n" }
  $path = Join-Path $dir $name
  [System.IO.File]::WriteAllText($path, $texto)
  return $path
}

try {
  if (Test-Path $bench) { Remove-Item -Recurse -Force $bench }
  New-Item -ItemType Directory -Force -Path $bench | Out-Null

  # --- Caso 1: conteudo diferente + mesma versao => BLOQUEIA --------------
  $p1a = New-Fixture $bench "caso1a.html" "conteudo A do repo (D2)" "v202.42"
  $p1b = New-Fixture $bench "caso1b.html" "conteudo B do deploy_zip (sem D2)" "v202.42"
  $d1  = Get-VixPagesContentDrift -IndexPath $p1a -ZipIndexPath $p1b
  if ($d1 -and $d1.cacheVersion -eq "v202.42") {
    Write-Host "OK   caso 1 (conteudo diferente + mesma versao) BLOQUEIA"
  } else {
    Write-Host "FALHA caso 1 deveria acusar drift (conteudo diferente + mesma versao)"
    $pass = $false
  }

  # --- Caso 2: conteudo diferente + versao diferente => PASSA -------------
  $p2a = New-Fixture $bench "caso2a.html" "conteudo A do repo (D2)" "v202.43"
  $p2b = New-Fixture $bench "caso2b.html" "conteudo B do deploy_zip (sem D2)" "v202.42"
  $d2  = Get-VixPagesContentDrift -IndexPath $p2a -ZipIndexPath $p2b
  if ($null -eq $d2) {
    Write-Host "OK   caso 2 (conteudo diferente + versao diferente) PASSA"
  } else {
    Write-Host "FALHA caso 2 nao deveria acusar drift (bump em voo)"
    $pass = $false
  }

  # --- Caso 3: conteudo igual => PASSA ------------------------------------
  $p3a = New-Fixture $bench "caso3a.html" "mesmo conteudo" "v202.42"
  $p3b = New-Fixture $bench "caso3b.html" "mesmo conteudo" "v202.42"
  $d3  = Get-VixPagesContentDrift -IndexPath $p3a -ZipIndexPath $p3b
  if ($null -eq $d3) {
    Write-Host "OK   caso 3 (conteudo igual) PASSA"
  } else {
    Write-Host "FALHA caso 3 nao deveria acusar drift (conteudo igual)"
    $pass = $false
  }

  # --- Caso 3b: conteudo igual com EOL diferente (CRLF x LF) => PASSA ------
  $p4a = New-Fixture $bench "caso4a.html" "mesmo conteudo com quebra" "v202.42"
  $p4b = New-Fixture $bench "caso4b.html" "mesmo conteudo com quebra" "v202.42" -Crlf
  $d4  = Get-VixPagesContentDrift -IndexPath $p4a -ZipIndexPath $p4b
  if ($null -eq $d4) {
    Write-Host "OK   caso 3b (conteudo igual, EOL CRLF x LF) PASSA"
  } else {
    Write-Host "FALHA caso 3b nao deveria acusar drift (diferenca so de EOL)"
    $pass = $false
  }

  # --- Wiring: deploy-pages.ps1 carrega a lib e aborta ANTES do sync --------
  $scriptTxt = [System.IO.File]::ReadAllText($deploy)
  $idxMarker = $scriptTxt.IndexOf("DRIFT_CONTEUDO_MESMA_VERSAO")
  $idxSync   = $scriptTxt.IndexOf("# --- 2. Sincroniza")
  $idxLib    = $scriptTxt.IndexOf("vixradar-pages-content-gate.ps1")
  if ($idxMarker -gt 0 -and $idxSync -gt $idxMarker -and $idxLib -gt 0 -and $idxLib -lt $idxSync) {
    Write-Host "OK   deploy-pages.ps1: gate DRIFT_CONTEUDO_MESMA_VERSAO antes do sync, lib carregada"
  } else {
    Write-Host "FALHA wiring do deploy-pages.ps1 (marcador=$idxMarker sync=$idxSync lib=$idxLib)"
    $pass = $false
  }
} finally {
  if (Test-Path $bench) { Remove-Item -Recurse -Force $bench }
}

if ($pass) {
  Write-Host ""
  Write-Host "TESTE DRIFT-CONTEUDO1: OK (bloqueia drift de conteudo com mesma versao; bump e conteudo igual passam)"
  exit 0
} else {
  Write-Host ""
  Write-Host "TESTE DRIFT-CONTEUDO1: FALHOU"
  exit 1
}
