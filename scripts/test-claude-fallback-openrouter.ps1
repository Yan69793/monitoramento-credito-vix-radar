# test-claude-fallback-openrouter.ps1 - CLAUDEFALLBACK-OR1 (2026-09-22).
#
# Prova, offline e em PowerShell 5.1, a funcao pura que decide se a rotina pode desviar
# de Claude-assinatura para OpenRouter quando a assinatura nao responde: precedencia
# Process>User>Machine, valor exato 'openrouter' (case-insensitive, trim), qualquer outro
# valor ou ausencia = desligado. Nao testa o desvio em si (isso e coberto pelo fluxo de
# preflight e por test-quota-esgotada-failclosed.ps1 no ramo mid-lote), so a decisao.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-claude-fallback-openrouter.ps1

$ErrorActionPreference = 'Continue'
$script:okN = 0
$script:fal = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) }
    else { $script:fal++; Write-Host ('  FALHA ' + $msg) }
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-llm-provider.ps1')

function Limpar-Escopos {
    Remove-Item Env:\VIXRADAR_CLAUDE_FALLBACK_PROVIDER -ErrorAction SilentlyContinue
}

$userOriginal = [Environment]::GetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', 'User')
try {
    # === A: ausente em todo escopo = desligado ===
    Limpar-Escopos
    [Environment]::SetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', $null, 'User')
    Assert (-not (Get-VixClaudeFallbackOpenRouterHabilitado)) 'A1: sem a variavel em nenhum escopo, fallback desligado'

    # === B: Process = 'openrouter' liga, independente de User ===
    Limpar-Escopos
    [Environment]::SetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', $null, 'User')
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = 'openrouter'
    Assert (Get-VixClaudeFallbackOpenRouterHabilitado) 'B1: Process=openrouter liga o fallback'
    Limpar-Escopos

    # === C: case-insensitive e com espaco nas pontas ===
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = '  OpenRouter  '
    Assert (Get-VixClaudeFallbackOpenRouterHabilitado) 'C1: maiuscula/espaco nao impedem o match'
    Limpar-Escopos

    # === D: qualquer outro valor = desligado (nao e allowlist frouxa) ===
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = 'claude-subscription'
    Assert (-not (Get-VixClaudeFallbackOpenRouterHabilitado)) 'D1: valor que nao e openrouter fica desligado'
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = 'codex'
    Assert (-not (Get-VixClaudeFallbackOpenRouterHabilitado)) 'D2: codex nao ativa o fallback do Claude'
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = ''
    Assert (-not (Get-VixClaudeFallbackOpenRouterHabilitado)) 'D3: string vazia fica desligado'
    Limpar-Escopos

    # === E: precedencia Process > User (Process vence mesmo com User diferente) ===
    [Environment]::SetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', 'openrouter', 'User')
    $env:VIXRADAR_CLAUDE_FALLBACK_PROVIDER = 'nenhum'
    Assert (-not (Get-VixClaudeFallbackOpenRouterHabilitado)) 'E1: Process vazio-de-fato (valor invalido) nao cai para User'
    Limpar-Escopos
    Assert (Get-VixClaudeFallbackOpenRouterHabilitado) 'E2: sem Process, User=openrouter liga (precedencia documentada)'
    [Environment]::SetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', $null, 'User')

    # === F: parser valido e arquivo ASCII (regra do repo) ===
    $libPath = Join-Path $root 'lib\vixradar-llm-provider.ps1'
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $libPath).Path, [ref]$null, [ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) 'F1: vixradar-llm-provider.ps1 parseia sem erro no PS 5.1'
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $libPath).Path)
    $naoAscii = @($bytes | Where-Object { $_ -gt 0x7F }).Count
    Assert ($naoAscii -eq 0) 'F2: vixradar-llm-provider.ps1 continua ASCII puro (BOM nao exigido)'
}
finally {
    Limpar-Escopos
    [Environment]::SetEnvironmentVariable('VIXRADAR_CLAUDE_FALLBACK_PROVIDER', $userOriginal, 'User')
}

Write-Host ('RESULTADO: ok=' + $script:okN + ' falha=' + $script:fal)
if ($script:fal -gt 0) { exit 1 } else { exit 0 }
