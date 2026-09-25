# Regression test: DeepSeek 402 must never inherit OpenRouter -> Claude fallback.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-llm-provider.ps1')

$motor = Join-Path $root 'run_vixradar_varredura.ps1'
$linha = Get-Content $motor | Where-Object { $_ -match '^\$script:VixOpenRouterFallbackAnthropic\s*=' } | Select-Object -First 1
if (-not $linha) { throw 'assignment VixOpenRouterFallbackAnthropic not found' }

function Test-Case([string]$provider, [bool]$esperado) {
    $env:VIXRADAR_LLM_PROVIDER = $provider
    $script:VixUsaOpenRouter = Test-VixUsaLlmAdapterHttp
    $__anthropicFallbackProvider = 'claude-subscription'
    Invoke-Expression $linha
    $obtido = [bool]$script:VixOpenRouterFallbackAnthropic
    if ($obtido -ne $esperado) { throw "provider=$provider esperado=$esperado obtido=$obtido" }
    Write-Host "PASS provider=$provider fallback_claude=$obtido"
}

Test-Case 'deepseek' $false
Test-Case 'openrouter' $true
Test-Case 'claude-subscription' $false
Write-Host 'RESULTADO: PASS - DeepSeek nao herda fallback OpenRouter -> Claude'
exit 0
