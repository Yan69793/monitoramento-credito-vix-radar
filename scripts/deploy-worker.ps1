<#
.SYNOPSIS
  Deploy do Worker VIX Radar (Cloudflare Workers) — atomico com o git.

.DESCRIPTION
  Colapsa em um comando o ritual de 4 passos que gerava drift repo/producao:
    1. Confere pre-requisitos e gera o bundle a partir de api/src/worker.js.
    2. Aponta api/wrangler.toml main -> o bundle desta versao.
    3. Roda `wrangler deploy` (com --no-autoconfig, obrigatorio neste repo).
    4. Valida producao (GET /): versao viva == esperada, bindings kv/telemetria.
    5. Sincroniza o git: add do bundle + wrangler.toml (+ CLAUDE.md/README.md se
       sync-version-docs.ps1 os alterou), commit e push.

  POR QUE O PASSO 5 EXISTE: api/v4.*.js nao e mais ignorado pelo git (a regra
  de allowlist manual saiu do .gitignore em 17/07), mas o commit do bundle
  continua manual porque so deve acontecer DEPOIS do deploy validado — nunca
  antes. Entre 08/07 e 15/07, quando o bundle nascia invisivel ao git, isso
  produziu 8 dias de canonical-test vermelho: producao em v4.9.158/159 e o
  repo declarando v4.9.154. O deploy so termina quando o GitHub sabe o que
  esta no ar. Ver Obsidian notas 25/26 e o guard anti-drift do canonical-test.

  ORDEM IMPORTA: o git so e tocado DEPOIS do deploy validado. Se o deploy
  falhar, o repo nao passa a declarar uma versao que nao esta no ar.

  CREDENCIAL: le CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID de variaveis de
  ambiente. NUNCA hardcode token neste arquivo (regra inviolavel do projeto).

.EXAMPLE
  pwsh ./scripts/deploy-worker.ps1 -Version v4.9.160
  pwsh ./scripts/deploy-worker.ps1 -Version v4.9.160 -SkipGit
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$WorkerName = "radar-credito-api",
  [switch]$SkipGit,
  [switch]$SkipValidation
)

$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$apiDir = Join-Path $root "api"
$toml   = Join-Path $apiDir "wrangler.toml"

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host "AVISO: $msg" -ForegroundColor Yellow }

# Compara duas versoes de Worker (v4.9.NNN). Retorna -1, 0 ou 1.
function Compare-WorkerVersion($a, $b) {
  $na = [int]($a -replace '^v4\.9\.', '')
  $nb = [int]($b -replace '^v4\.9\.', '')
  if ($na -lt $nb) { return -1 }
  if ($na -gt $nb) { return 1 }
  return 0
}

# --- 0. Pre-requisitos -----------------------------------------------------
if (-not $env:CLOUDFLARE_API_TOKEN) {
  Fail "CLOUDFLARE_API_TOKEN ausente. Configure a variavel de ambiente (User scope). Veja scripts/setup-deploy-credential.ps1."
}
if (-not (Test-Path $toml)) { Fail "Nao achei $toml" }

# Aceita 'v4.9.160' ou 'v4.9.160.js'
$ver    = $Version -replace '\.js$', ''
$bundle = "$ver.js"
$bundlePath = Join-Path $apiDir $bundle
$buildScript = Join-Path $PSScriptRoot "build-worker.ps1"
if (-not (Test-Path $buildScript)) { Fail "Build do Worker ausente: $buildScript" }

# --- 0.1 GATE ANTI-REGRESSAO: versao em producao ---------------------------
# Consulta o health publico ANTES do deploy. Se producao estiver em versao
# mais nova que a que estamos subindo, aborta — deploy regrediria producao.
# Isto fecha o cenario: alguem deploya v4.9.184, voce esta com o repo em
# v4.9.183, faz deploy e regride sem saber.
$healthUrl = "https://api.vixradar.com/?_=$(Get-Date -Format 'yyyyMMddHHmmss')"
try {
  $prodHealth = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 10 -Headers @{ "Cache-Control" = "no-cache" }
  $prodVersion = $prodHealth.versao
  if ($prodVersion) {
    $cmp = Compare-WorkerVersion $ver $prodVersion
    if ($cmp -lt 0) {
      Fail "PRODUCAO ESTA A FRENTE DO REPO. Producao=$prodVersion, voce esta tentando deployar $ver. Recupere o bundle de producao via Cloudflare MCP, commite e so entao faca novo deploy. NAO deploye — regrediria producao."
    }
    if ($cmp -eq 0) {
      Warn "Producao ja esta em $prodVersion — deploy e no-op. Use -SkipValidation se for re-deploy intencional."
    }
    Write-Host "Gate pre-deploy: producao=$prodVersion, deploy=$ver OK" -ForegroundColor Green
  } else {
    Warn "Nao foi possivel extrair versao de producao do health endpoint. Prosseguindo sem o gate anti-regressao."
  }
} catch {
  Warn "Falha ao consultar health de producao ($healthUrl): $_. Prosseguindo sem o gate anti-regressao."
}

# --- 0.2 GATE WORKING TREE: sem alteracoes nao commitadas ------------------
# Arquivos que o deploy vai alterar ou commitar precisam estar limpos.
# Se houver sujeira, o commit do passo 5 embaralharia mudancas nao relacionadas
# com o deploy, ou pior: commitaria pela metade.
$trackedFiles = @(
  "api/src/worker.js",
  "api/wrangler.toml",
  "scripts/build-worker.ps1",
  "scripts/deploy-worker.ps1"
)
$dirty = git diff --name-only -- $trackedFiles 2>$null
if ($dirty) {
  $dirtyList = ($dirty | ForEach-Object { "  $_" }) -join "`n"
  Fail "Working tree sujo nos arquivos do deploy. Faça commit ou stash antes de deployar:`n$dirtyList"
}
# Staged mas nao commitados tambem trava (git diff --cached).
$stagedDirty = git diff --cached --name-only -- $trackedFiles 2>$null
if ($stagedDirty) {
  $stagedList = ($stagedDirty | ForEach-Object { "  $_" }) -join "`n"
  Fail "Arquivos staged mas nao commitados. Commit ou unstage antes de deployar:`n$stagedList"
}
Write-Host "Gate working tree: limpo" -ForegroundColor Green

# api/src/worker.js e a fonte canonica. O artefato versionado nunca e editado a mao.
& $buildScript -Version $ver
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bundlePath)) {
  Fail "Build do Worker falhou ou nao gerou $bundlePath"
}

$sizeKB = [math]::Round((Get-Item $bundlePath).Length / 1KB)
Write-Host "Bundle: $bundle ($sizeKB KB)" -ForegroundColor Cyan

# --- 1. Check WORKER_VERSAO bate com nome do arquivo (VERSAO3X guard) -------
# Regra: "um numero por deploy, nunca reusa". Se WORKER_VERSAO dentro do bundle
# nao bater com o nome do arquivo, o health publico mente sobre qual codigo esta
# rodando — incidente recorrente (21/07 e 25/07). Este check trava o deploy.
$matchLine = Select-String -Path $bundlePath -Pattern 'var WORKER_VERSAO = "v[\d.]+"' | Select-Object -First 1
if ($matchLine) {
  $m = [regex]::Match($matchLine.Line, '"v([\d.]+)"')
  if ($m.Success) {
    $bundleWorkerVersao = "v" + $m.Groups[1].Value
    if ($bundleWorkerVersao -ne $ver) {
      Fail "WORKER_VERSAO no bundle (`"$bundleWorkerVersao`") nao bate com o nome do arquivo ($ver). Corrija o WORKER_VERSAO no bundle antes de deployar (VERSAO3X)."
    }
    Write-Host "WORKER_VERSAO: $bundleWorkerVersao (confere com arquivo)" -ForegroundColor DarkGray
  }
} else {
  Write-Host "AVISO: nao foi possivel extrair WORKER_VERSAO do bundle (formato mudou?)." -ForegroundColor Yellow
}

# --- 2. Aponta wrangler.toml main ------------------------------------------
$tomlRaw = Get-Content $toml -Raw
$m = [regex]::Match($tomlRaw, '(?m)^(\s*main\s*=\s*")([^"]+)(")')
if (-not $m.Success) { Fail "Nao encontrei a chave 'main' em $toml" }
$mainAtual = $m.Groups[2].Value

if ($mainAtual -ne $bundle) {
  $tomlNovo = [regex]::Replace($tomlRaw, '(?m)^(\s*main\s*=\s*")([^"]+)(")', "`${1}$bundle`${3}")
  Set-Content -NoNewline -Path $toml -Value $tomlNovo
  Write-Host "wrangler.toml main: $mainAtual -> $bundle" -ForegroundColor Cyan
} else {
  Write-Host "wrangler.toml main ja aponta $bundle" -ForegroundColor DarkGray
}

# --- 3. Deploy -------------------------------------------------------------
# --no-autoconfig obrigatorio: sem ele o Wrangler 4.x detecta outro diretorio
# como projeto e ignora este wrangler.toml.
Write-Host "`nDeployando Worker ($WorkerName / $bundle)..." -ForegroundColor Yellow
Push-Location $apiDir
try {
  npx wrangler deploy $bundle --config wrangler.toml --no-autoconfig --compatibility-flags nodejs_compat --name $WorkerName
  $deployExit = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($deployExit -ne 0) { Fail "wrangler deploy falhou (exit $deployExit). wrangler.toml foi alterado mas NADA foi commitado." }

# --- 4. Validacao em producao ----------------------------------------------
if ($SkipValidation) {
  Write-Host "`nValidacao pulada (-SkipValidation)." -ForegroundColor DarkGray
} else {
  Write-Host "`nValidando producao..." -ForegroundColor Yellow
  Start-Sleep -Seconds 4
  try {
    $h = Invoke-RestMethod -Uri "https://api.vixradar.com/?_=$([guid]::NewGuid())" -Headers @{ "Cache-Control" = "no-cache" }
  } catch {
    Fail "Falha ao ler o health de producao: $_"
  }

  if ($h.versao -ne $ver) {
    Fail "Versao viva=$($h.versao), esperada=$ver. Deploy nao propagou ou foi para outro Worker. NAO commitado."
  }
  Write-Host "  versao viva: $($h.versao) OK" -ForegroundColor Green

  if (-not $h.ok) { Fail "Health ok=false — producao degradada apos o deploy." }
  # Telemetria e regra inviolavel do projeto (binding RADAR_USAGE_EVENTS).
  if (-not $h.bindings.kv)         { Fail "Binding kv ausente apos o deploy." }
  if (-not $h.bindings.telemetria) { Fail "Binding de telemetria ausente — painel de Engajamento cego." }
  Write-Host "  ok=true kv=true telemetria=true" -ForegroundColor Green
}

# --- 4.5 Sincroniza a versao declarada em CLAUDE.md/README.md --------------
# Sem isto, o bundle e o wrangler.toml ficam corretos mas a doc continua
# declarando a versao anterior ate alguem lembrar de editar a mao — foi
# assim que CLAUDE.md e README.md divergiram da producao mais de uma vez.
& (Join-Path $PSScriptRoot "sync-version-docs.ps1") -WorkerVersion $ver

# --- 5. Sync com o git -----------------------------------------------------
if ($SkipGit) {
  Write-Host "`nGit pulado (-SkipGit)." -ForegroundColor DarkGray
  Write-Host "ATENCAO: producao esta em $ver e o repo NAO sabe. O canonical-test vai acusar drift ate voce commitar:" -ForegroundColor Yellow
  Write-Host "  git add api/$bundle api/wrangler.toml CLAUDE.md README.md && git commit && git push" -ForegroundColor Yellow
  exit 0
}

Write-Host "`nSincronizando o git..." -ForegroundColor Yellow
Push-Location $root
try {
  # Sem -f: api/v4.*.js saiu do .gitignore, o bundle e rastreado normalmente.
  # CLAUDE.md/README.md entram so se sync-version-docs.ps1 os alterou; git add
  # em arquivo sem mudanca nao staga nada.
  git add "api/$bundle" "api/src/worker.js" "api/wrangler.toml" "scripts/build-worker.ps1" "scripts/deploy-worker.ps1" "CLAUDE.md" "README.md"
  if ($LASTEXITCODE -ne 0) { Fail "git add falhou (exit $LASTEXITCODE)." }

  $staged = git diff --cached --name-only
  if (-not $staged) {
    Write-Host "  Nada a commitar (repo ja sincronizado)." -ForegroundColor DarkGray
  } else {
    git commit -m "chore(worker): deploy $ver em producao"
    if ($LASTEXITCODE -ne 0) { Fail "git commit falhou (exit $LASTEXITCODE)." }
    Write-Host "  commit criado" -ForegroundColor Green
  }

  git push origin HEAD
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nDEPLOY OK mas o PUSH FALHOU — o GitHub ainda nao sabe que producao esta em $ver." -ForegroundColor Red
    Write-Host "O canonical-test vai acusar drift ate o push passar. Resolva e rode: git push origin HEAD" -ForegroundColor Red
    exit 3
  }
  Write-Host "  push OK" -ForegroundColor Green
} finally {
  Pop-Location
}

Write-Host "`nDEPLOY OK — producao em $ver, repo e GitHub sincronizados." -ForegroundColor Green
exit 0
