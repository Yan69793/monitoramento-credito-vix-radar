# check-vault-drift.ps1 — Compara versoes do vault Obsidian contra health ao vivo
# Uso: pwsh ./scripts/check-vault-drift.ps1
# Exit 0: vault alinhado com producao
# Exit 1: drift detectado (versoes divergem)
# Exit 2: erro de conectividade ou parse (nao foi possivel verificar)

param(
    [switch]$Quiet    # suprime output, so exit code
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\.."
$VaultDir = "$ProjectRoot\Obsidian VIX Radar"
$EstadoAtual = "$VaultDir\03 - Estado Atual.md"

$HealthUrl = 'https://api.vixradar.com'
$FallbackUrl = 'https://radar-credito-api.prospects-intel.workers.dev'

# Health check
try {
    $health = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 15 -ErrorAction Stop
} catch {
    try {
        $health = Invoke-RestMethod -Uri $FallbackUrl -TimeoutSec 15 -ErrorAction Stop
    } catch {
        if (-not $Quiet) { Write-Host "DRIFT:ERRO — health inacessivel ($HealthUrl / $FallbackUrl)" }
        exit 2
    }
}

$liveWorker = $health.versao
$liveOk = $health.ok -eq $true

if (-not $liveWorker) {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO — health sem campo 'versao'" }
    exit 2
}

# Parse vault
if (-not (Test-Path $EstadoAtual)) {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO — arquivo nao encontrado: $EstadoAtual" }
    exit 2
}

$vaultContent = Get-Content -Raw $EstadoAtual -Encoding UTF8

# Extrai versoes da tabela markdown: | Worker | **v4.9.171** |
if ($vaultContent -match '\|\s*Worker\s*\|\s*\*{0,2}(v[\d.]+)\*{0,2}\s*\|') {
    $vaultWorker = $Matches[1]
} else {
    if (-not $Quiet) { Write-Host "DRIFT:ERRO — nao foi possivel extrair versao do Worker do vault" }
    exit 2
}

if ($vaultContent -match '\|\s*Frontend\s*\|\s*\*{0,2}(v[\d.]+)\*{0,2}\s*\|') {
    $vaultFrontend = $Matches[1]
} else {
    if (-not $Quiet) { Write-Host "DRIFT:AVISO — nao foi possivel extrair versao do Frontend do vault (nao critico)" }
    $vaultFrontend = $null
}

# Compara
$drift = $false

if ($liveWorker -ne $vaultWorker) {
    if (-not $Quiet) { Write-Host "DRIFT:Worker — vault: $vaultWorker | producao: $liveWorker" }
    $drift = $true
}

# Frontend: tenta extrair do health ou de https://vixradar.com/version.json
try {
    $versionJson = Invoke-RestMethod -Uri 'https://vixradar.com/version.json' -TimeoutSec 10 -ErrorAction SilentlyContinue
    $liveFrontend = $versionJson.version
    if ($liveFrontend -and $vaultFrontend -and $liveFrontend -ne $vaultFrontend) {
        if (-not $Quiet) { Write-Host "DRIFT:Frontend — vault: $vaultFrontend | producao: $liveFrontend" }
        $drift = $true
    }
} catch {
    # frontend check nao critico
}

if ($drift) {
    if (-not $Quiet) { Write-Host "DRIFT:CONFIRMADO — vault desatualizado. Atualizar $EstadoAtual e arquivos relacionados." }
    exit 1
}

if (-not $Quiet) { Write-Host "DRIFT:OK — vault alinhado com producao (Worker=$liveWorker, Frontend=$liveFrontend)" }
exit 0
