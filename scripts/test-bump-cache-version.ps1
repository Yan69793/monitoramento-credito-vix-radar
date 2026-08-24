<#
.SYNOPSIS
  Prova de regressao do CACHEBUMP1: o par v202.3 contra ?v=202.30.

.DESCRIPTION
  CACHEBUMP1 (20/08, terceira ocorrencia): o bump-cache-version.ps1
  reescreve o app/index.html de 700 KB e teve dois defeitos de comportamento
  na Replace-InFile:
    1. trocava "v<n>.<n>" entre aspas em QUALQUER lugar (copy/UI/changelog),
       sem ancora nenhuma;
    2. colisao de substring: versao corrente v202.3, $oldNum=202.3, casava
       dentro de ?v=202.30 e produzia ?v=203.10 (aqui 203.100 no exemplo).
  Este teste roda o SCRIPT REAL (nao uma copia da funcao) contra uma bancada
  isolada sob scripts/_tmp_bump_test/, com um fixture minimo que contem:
    - CACHE_VERSION="v202.3"                 (deve virar v203.1)
    - src="admin-bootstrap.js?v=202.3"       (deve virar ?v=203.1)
    - src="outro-asset.js?v=202.30"          (outra versao: NAO pode mudar)
    - copy/UI  o painel parou no "v202.3"   (NAO pode mudar)
  E o script deve bumpar para v203.1 sem criar ?v=203.10 nem ?v=203.100.

.DESCRIPTION nota
  Regra de ouro (same as test-frescor-cvm.mjs): extrair/rodar o codigo real,
  nunca reescrever copia. Aqui rodamos o bump-cache-version.ps1 de verdade
  dentro da bancada, resolvendo o root pelos paths fisicos.

.EXAMPLE
  powershell.exe -NoProfile -File scripts/test-bump-cache-version.ps1
  exit 0 = passa (troca correta + colisao nao acontece + copy intocada)
#>
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot   # scripts/ (onde vive o bump-cache-version.ps1)
$bench = Join-Path $root "_tmp_bump_test\bump2"
$appDir = Join-Path $bench "app"
$scrDir = Join-Path $bench "scripts"

# preflight: exclui qualquer residuo de rodada anterior
if (Test-Path $bench) { Remove-Item -Recurse -Force $bench }

try {
  # cria a bancada dentro do try: se qualquer passo falhar no meio, o finally
  # abaixo garante a limpeza (foi a falta disso que deixou residuo na raiz antes).
  New-Item -ItemType Directory -Force -Path $appDir | Out-Null
  New-Item -ItemType Directory -Force -Path $scrDir | Out-Null

  $fixture = @"
<!DOCTYPE html>
<!-- copy/UI que NAO pode mudar: o painel tinha congelado no "v202.3" e ninguem viu -->
<html>
<head><meta name="app-ver" content="v202.3"></head>
<body>
<script src="admin-bootstrap.js?v=202.3"></script>
<script src="outro-asset.js?v=202.30"></script>
<script src="raro.js?v=v202.3"></script>
<script>const CACHE_VERSION="v202.3";window.CACHE_VERSION="v202.3";</script>
</body>
</html>
"@
  $idxPath = Join-Path $appDir "index.html"
  [IO.File]::WriteAllText($idxPath, $fixture, (New-Object System.Text.UTF8Encoding($false)))

  # roda o SCRIPT REAL na bancada (copiado para que $PSScriptRoot aponte pra la)
  Copy-Item (Join-Path $root "bump-cache-version.ps1") (Join-Path $scrDir "bump-cache-version.ps1")
  $scriptOut = & (Join-Path $scrDir "bump-cache-version.ps1") -NewVersion v203.1 2>&1 | Out-String
  Write-Host $scriptOut

  $out = [IO.File]::ReadAllText($idxPath)
  $pass = $true

  # Ponta 1: troca correta acontece
  if ($out.Contains('CACHE_VERSION="v203.1"')) { Write-Host "OK   CACHE_VERSION bumpou para v203.1" } else { Write-Host "FALHA CACHE_VERSION nao bumpou"; $pass = $false }
  if ($out.Contains('?v=203.1'))               { Write-Host "OK   ?v= legitimo bumpou para 203.1" } else { Write-Host "FALHA ?v= legitimo nao bumpou"; $pass = $false }

  # Ponta 2: colisao NAO acontece (so um asset, o ?v=202.30 de outra versao)
  if ($out.Contains('?v=202.30'))              { Write-Host "OK   ?v=202.30 (outra versao) preservado" } else { Write-Host "FALHA ?v=202.30 foi tocado"; $pass = $false }
  if (-not $out.Contains('?v=203.10'))         { Write-Host "OK   sem ?v=203.10 (colisao nao produz)"; } else { Write-Host "FALHA colisao produziu ?v=203.10"; $pass = $false }
  if (-not $out.Contains('?v=203.100'))        { Write-Host "OK   sem ?v=203.100 (colisao nao produz)"; } else { Write-Host "FALHA colisao produziu ?v=203.100"; $pass = $false }

  # Ponta 1b: copy/UI intocada (o "v202.3" fora de CACHE_VERSION/?v=)
  if ($out.Contains('no "v202.3"'))            { Write-Host "OK   copy/UI com \"v202.3\" preservada" } else { Write-Host "FALHA copy/UI foi tocada"; $pass = $false }

  # Ponta 3: caso raro ?v=v202.3 (com "v") vira ?v=v203.1, SEM barra invertida
  if ($out.Contains('?v=v203.1'))              { Write-Host "OK   ?v=v202.3 bumpou para ?v=v203.1 (sem barra)" } else { Write-Host "FALHA ?v=v202.3 nao bumpou"; $pass = $false }

  # Fecha a CLASSE do erro: nenhuma barra invertida na saida. Se um valor escapado
  # (ex. 203\.1) entrar na substituicao, a barra aparece aqui, nao so a instancia.
  if (-not $out.Contains('\'))                 { Write-Host "OK   saida sem nenhuma barra invertida" } else { Write-Host "FALHA saida contem barra invertida (valor escapado entrou na substituicao)"; $pass = $false }
} finally {
  # garantia: limpa a bancada mesmo com falha no meio (try/finally)
  if (Test-Path $bench) { Remove-Item -Recurse -Force $bench }
  # remove tambem a pasta-mae se tiver sobrado vazia
  $tmpRoot = Join-Path $root "_tmp_bump_test"
  if (Test-Path $tmpRoot) {
    $sobras = Get-ChildItem $tmpRoot -Force -ErrorAction SilentlyContinue
    if (-not ($sobras -and $sobras.Count -gt 0)) { Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue }
  }
}

if ($pass) {
  Write-Host ""
  Write-Host "TESTE CACHEBUMP1: OK (troca correta + colisao nao acontece + copy intocada)"
  exit 0
} else {
  Write-Host ""
  Write-Host "TESTE CACHEBUMP1: FALHOU"
  exit 1
}
