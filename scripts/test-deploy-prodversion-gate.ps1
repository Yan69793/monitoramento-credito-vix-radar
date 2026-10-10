<#
.SYNOPSIS
  Prova de regressao do FAILCLOSED1 (2026-10-10): o gate anti-regressao do
  deploy-pages.ps1 ABORTA quando nao consegue ler a versao de producao, em vez
  de prosseguir em silencio.

.DESCRIPTION
  Caso real: um checkout limpo e velho (v202.60) com a rede fora publicava por
  cima de producao mais nova - regredindo versao E conteudo (reintroduzindo o
  bloco de abril de 2026). O gate anti-regressao e a UNICA barreira que compara
  repo x producao, e ele se desligava sozinho no catch ("Prosseguindo sem o
  gate anti-regressao"). Isso e fail-open num caminho de publicacao.

  Este teste roda a FUNCAO REAL (dot-source de
  scripts/lib/vixradar-deploy-prodversion.ps1, a mesma que o deploy-pages.ps1
  carrega) e confere a fiacao do deploy-pages.ps1. Nao usa rede, credenciais,
  app/ nem producao.

.EXAMPLE
  powershell.exe -NoProfile -File scripts/test-deploy-prodversion-gate.ps1
  exit 0 = passa (5 casos + fiacao do deploy-pages.ps1)
#>
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"

$root   = $PSScriptRoot                      # scripts/
$lib    = Join-Path (Join-Path $root "lib") "vixradar-deploy-prodversion.ps1"
$deploy = Join-Path $root "deploy-pages.ps1"

if (-not (Test-Path $lib))    { Write-Host "FALHA lib nao encontrada: $lib"; exit 1 }
if (-not (Test-Path $deploy)) { Write-Host "FALHA deploy-pages.ps1 nao encontrado: $deploy"; exit 1 }

. $lib

if (-not (Get-Command Resolve-VixProdVersionGate -ErrorAction SilentlyContinue)) {
  Write-Host "FALHA funcao Resolve-VixProdVersionGate nao carregada pelo dot-source"
  exit 1
}

$pass = $true
function Check($cond, $okMsg, $failMsg) {
  if ($cond) { Write-Host "OK   $okMsg" } else { Write-Host "FALHA $failMsg"; $script:pass = $false }
}

# --- Caso 1: leitura OK => prossegue com a versao lida ----------------------
$c1 = Resolve-VixProdVersionGate -FetchedVersion "v202.62" -FetchError ""
Check ($c1.Ok -and $c1.Version -eq "v202.62" -and -not $c1.Forcado) `
  "caso 1 (producao lida v202.62) PROSSEGUE com a versao" `
  "caso 1 deveria prosseguir com Version=v202.62"

# --- Caso 2: falha de leitura SEM -Offline => ABORTA ------------------------
$c2 = Resolve-VixProdVersionGate -FetchedVersion "" -FetchError "The remote name could not be resolved"
Check (-not $c2.Ok -and $c2.Bloqueio) `
  "caso 2 (leitura falhou, sem -Offline) ABORTA [fail-closed]" `
  "caso 2 deveria ABORTAR quando nao le producao - este e o bug FAILCLOSED1"

# --- Caso 3: falha de leitura COM -Offline => prossegue, marcado Forcado -----
$c3 = Resolve-VixProdVersionGate -FetchedVersion "" -FetchError "timeout" -Offline
Check ($c3.Ok -and $c3.Forcado -and -not $c3.Version) `
  "caso 3 (leitura falhou, com -Offline) PROSSEGUE marcado Forcado" `
  "caso 3 deveria prosseguir com Forcado=$true e Version vazia"

# --- Caso 4: version.json sem campo 'version', SEM -Offline => ABORTA -------
$c4 = Resolve-VixProdVersionGate -FetchedVersion "" -FetchError ""
Check (-not $c4.Ok -and $c4.Bloqueio -match "campo 'version'") `
  "caso 4 (version.json sem o campo 'version', sem -Offline) ABORTA" `
  "caso 4 deveria ABORTAR quando o campo 'version' vem vazio"

# --- Caso 5: version.json sem campo 'version', COM -Offline => prossegue ----
$c5 = Resolve-VixProdVersionGate -FetchedVersion "" -FetchError "" -Offline
Check ($c5.Ok -and $c5.Forcado) `
  "caso 5 (version.json sem o campo 'version', com -Offline) PROSSEGUE" `
  "caso 5 deveria prosseguir com Forcado=$true"

# --- Fiacao: deploy-pages.ps1 usa a funcao e nao tem mais o fail-open -------
$scriptTxt = [System.IO.File]::ReadAllText($deploy)
$usaFuncao = $scriptTxt.Contains("Resolve-VixProdVersionGate")
$carregaLib = $scriptTxt.Contains("vixradar-deploy-prodversion.ps1")
$temOffline = $scriptTxt -match '\[switch\]\$Offline'
$failOpenAntigo = $scriptTxt.Contains("Prosseguindo sem o gate anti-regressao")
Check ($usaFuncao -and $carregaLib -and $temOffline -and -not $failOpenAntigo) `
  "deploy-pages.ps1: usa a funcao, carrega a lib, expoe -Offline e nao tem mais o fail-open" `
  "fiacao do deploy-pages.ps1 (usa=$usaFuncao lib=$carregaLib offline=$temOffline failopenAntigo=$failOpenAntigo)"

if ($pass) {
  Write-Host ""
  Write-Host "TESTE FAILCLOSED1: OK (sem producao legivel o deploy aborta; -Offline libera consciente)"
  exit 0
} else {
  Write-Host ""
  Write-Host "TESTE FAILCLOSED1: FALHOU"
  exit 1
}
