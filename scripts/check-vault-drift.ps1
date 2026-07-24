# check-vault-drift.ps1 - Compara versoes do vault Obsidian contra health ao vivo
# Uso: powershell -NoProfile -File ./scripts/check-vault-drift.ps1
# Exit 0: vault alinhado com producao
# Exit 1: drift detectado (versoes divergem)
# Exit 2: erro de conectividade ou parse (nao foi possivel verificar)
# Mensagens em ASCII para Windows PowerShell 5.1 (evita quebra por encoding).

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."
$VaultDir = Join-Path $ProjectRoot "Obsidian VIX Radar"
$EstadoAtual = Join-Path $VaultDir "03 - Estado Atual.md"

$HealthUrl = 'https://api.vixradar.com'
$FallbackUrl = 'https://radar-credito-api.prospects-intel.workers.dev'

$liveFrontend = $null

try {
    $health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 15 -ErrorAction Stop
} catch {
    try {
        $health = Invoke-RestMethod -Uri $FallbackUrl -TimeoutSec 15 -ErrorAction Stop
    } catch {
        if (-not $Quiet) { Write-Host "DRIFT:ERRO - health inacessivel ($HealthUrl / $FallbackUrl)" }
        exit 2
    }
}

$liveWorker = $health.versao
$liveOk = $health.ok -eq $true

if (-not $liveWorker) {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO - health sem campo versao" }
    exit 2
}

if (-not (Test-Path $EstadoAtual)) {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO - arquivo nao encontrado: $EstadoAtual" }
    exit 2
}

$vaultContent = Get-Content -Raw $EstadoAtual -Encoding UTF8

if ($vaultContent -match '\|\s*Worker\s*\|\s*\*{0,2}(v[\d.]+)\*{0,2}\s*\|') {
    $vaultWorker = $Matches[1]
} else {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO - nao foi possivel extrair versao do Worker do vault" }
    exit 2
}

if ($vaultContent -match '\|\s*Frontend\s*\|\s*\*{0,2}(v[\d.]+)\*{0,2}\s*\|') {
    $vaultFrontend = $Matches[1]
} else {
    if (-not $Quiet) { Write-Host "DRIFT:AVISO - nao foi possivel extrair versao do Frontend do vault (nao critico)" }
    $vaultFrontend = $null
}

$drift = $false

if ($liveWorker -ne $vaultWorker) {
    if (-not $Quiet) { Write-Host "DRIFT:Worker - vault: $vaultWorker | producao: $liveWorker" }
    $drift = $true
}

try {
    $versionJson = Invoke-RestMethod -Uri 'https://vixradar.com/version.json' -TimeoutSec 10 -ErrorAction SilentlyContinue
    $liveFrontend = $versionJson.version
    if ($liveFrontend -and $vaultFrontend -and $liveFrontend -ne $vaultFrontend) {
        if (-not $Quiet) { Write-Host "DRIFT:Frontend - vault: $vaultFrontend | producao: $liveFrontend" }
        $drift = $true
    }
} catch {
    # frontend check nao critico
}

if ($drift) {
    if (-not $Quiet) { Write-Host "DRIFT:CONFIRMADO - vault desatualizado. Atualizar Estado Atual e arquivos relacionados." }
    exit 1
}

if (-not $Quiet) {
    $feLabel = if ($liveFrontend) { $liveFrontend } else { 'n/d' }
    Write-Host "DRIFT:OK - vault alinhado com producao (Worker=$liveWorker, Frontend=$feLabel)"
}
exit 0
