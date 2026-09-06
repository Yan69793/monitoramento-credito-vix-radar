# test-monitor-provider-gate.ps1 - regressao do gate de provider visto pelo monitor.
# Isolado: nao le Scheduler, nao toca logs, estado, rede ou variaveis User/Machine.

$ErrorActionPreference = 'Continue'
$ProviderLib = Join-Path $PSScriptRoot 'lib\vixradar-llm-provider.ps1'
$Monitor = Join-Path $PSScriptRoot 'monitor-tasks.ps1'
$script:okN = 0
$script:falN = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        $script:okN++
        Write-Host ('  OK    ' + $Msg)
    } else {
        $script:falN++
        Write-Host ('  FALHA ' + $Msg)
    }
}

$originalProvider = $env:VIXRADAR_LLM_PROVIDER
try {
    . $ProviderLib
    $gate = Get-Command 'Test-VixLlmProviderPermiteRotina' -ErrorAction SilentlyContinue
    $violation = Get-Command 'Test-VixLlmGateViolacao' -ErrorAction SilentlyContinue
    Assert ($null -ne $gate) 'a lib expoe a decisao canonica de provider para rotinas'
    Assert ($null -ne $violation) 'a lib expoe a decisao canonica de violacao 9006'

    if ($gate -and $violation) {
        $env:VIXRADAR_LLM_PROVIDER = 'openrouter'
        $openRouterBloqueado = -not (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado $true)
        Assert (-not $openRouterBloqueado) 'openrouter com adapter habilitado e permitido'
        Assert (-not (Test-VixLlmGateViolacao -ProviderBloqueado $openRouterBloqueado -ExitCode 7 -BenignCodes @(0))) 'openrouter permitido com exit normal diferente de 86 nao gera 9006'

        $env:VIXRADAR_LLM_PROVIDER = 'none'
        $bloqueado = -not (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado $true)
        Assert ($bloqueado) 'provider ausente e bloqueado'
        Assert (Test-VixLlmGateViolacao -ProviderBloqueado $bloqueado -ExitCode 7 -BenignCodes @(0)) 'provider bloqueado com exit diferente de 86 gera 9006'
        Assert (-not (Test-VixLlmGateViolacao -ProviderBloqueado $bloqueado -ExitCode 86 -BenignCodes @(0))) 'provider bloqueado com exit 86 e esperado'
    }

    $monitorText = Get-Content -LiteralPath $Monitor -Raw -Encoding UTF8
    Assert ($monitorText -match 'Test-VixLlmProviderPermiteRotina') 'monitor usa a decisao canonica da lib'
} finally {
    $env:VIXRADAR_LLM_PROVIDER = $originalProvider
}

Write-Host ('RESULTADO: ok=' + $script:okN + ' falhas=' + $script:falN)
if ($script:falN -gt 0) { exit 1 }
exit 0
