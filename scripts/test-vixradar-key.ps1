# test-vixradar-key.ps1 - regressao da chave dedicada do VIX Radar e headers do POST.
#
# Cobre a precedencia VIXRADAR_OPENROUTER_API_KEY > OPENROUTER_API_KEY e os headers
# constantes do POST (HTTP-Referer e X-Title). OFFLINE: nenhuma rede, chaves FAKE so
# para exercitar o caminho de codigo, nunca vao a stdout.
#
# Regra de seguranca (INC-2026-08-20): nenhuma chave real em literal, nenhum segredo
# em argumento de linha de comando. As chaves FAKE ficam so em escopo Process.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-vixradar-key.ps1
#      pwsh -NoProfile -File scripts\test-vixradar-key.ps1
#
# Precedencia regressa (2026-09-10): rotinas fora do VIX Radar seguem usando so a
# OPENROUTER_API_KEY; o fallback garante que nada deixe de funcionar sem a dedicada.

$ErrorActionPreference = 'Continue'
$script:falhas = 0
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-openrouter.ps1')

function Assert-True([bool]$cond, [string]$name) {
    if ($cond) { Write-Host ('PASS ' + $name) }
    else { Write-Host ('FAIL ' + $name); $script:falhas++ }
}

try {
    # ---- T1: com as duas definidas, vence a chave dedicada VIXRADAR_OPENROUTER_API_KEY ----
    $env:VIXRADAR_OPENROUTER_API_KEY = 'or-fake-vix-' + $PID
    $env:OPENROUTER_API_KEY = 'or-fake-gen-' + $PID
    $k1 = Get-VixOpenRouterApiKey
    Assert-True ($k1 -eq $env:VIXRADAR_OPENROUTER_API_KEY) 'T1 precedencia: vence a dedicada VIXRADAR_OPENROUTER_API_KEY'
    Assert-True ($k1 -ne $env:OPENROUTER_API_KEY) 'T1 precedencia: OPENROUTER_API_KEY nao e usada quando a dedicada existe'

    # ---- T2: sem a dedicada, o fallback OPENROUTER_API_KEY continua funcionando ----
    $gen = $env:OPENROUTER_API_KEY
    Remove-Item Env:\VIXRADAR_OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    $k2 = Get-VixOpenRouterApiKey
    Assert-True ($k2 -eq $gen) 'T2 fallback: sem a dedicada, OPENROUTER_API_KEY e usada'

    # ---- T3: sem nenhuma chave em escopo, devolve vazio ----
    # Maquina pode ter OPENROUTER_API_KEY real em escopo User/Machine; a ausencia total e
    # simulada travando a resolucao de env (sem rede), mesmo tecnica do teste de adapter.
    Remove-Item Env:\VIXRADAR_OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    function Get-VixOpenRouterEnv([string]$Name) { return '' }
    $k3 = Get-VixOpenRouterApiKey
    Assert-True ($k3 -eq '') 'T3 ausente: vazio quando nao ha nenhuma chave'
    . (Join-Path $root 'lib\vixradar-openrouter.ps1')

    # ---- T4: headers constantes do POST presentes e sem a chave ----
    $env:VIXRADAR_OPENROUTER_API_KEY = 'or-fake-vix-hdr-' + $PID
    $env:OPENROUTER_API_KEY = 'or-fake-gen-hdr-' + $PID
    $hdrs = Get-VixOpenRouterHttpHeaders
    Assert-True ($hdrs.Contains('HTTP-Referer')) 'T4 header: HTTP-Referer presente'
    Assert-True ($hdrs['HTTP-Referer'] -eq 'https://vixradar.com') 'T4 header: HTTP-Referer=https://vixradar.com'
    Assert-True ($hdrs.Contains('X-Title')) 'T4 header: X-Title presente'
    Assert-True ($hdrs['X-Title'] -eq 'VIX Radar - Scheduler') 'T4 header: X-Title=VIX Radar - Scheduler'
    Assert-True ($hdrs.Contains('X-OpenRouter-Metadata')) 'T4 header: X-OpenRouter-Metadata presente'
    Assert-True ($hdrs['X-OpenRouter-Metadata'] -eq 'enabled') 'T4 header: X-OpenRouter-Metadata=enabled'
    Assert-True (-not $hdrs.Contains('Authorization')) 'T4 seguranca: Authorization nao vive no dict header'
    $valeNaoChave = $true
    foreach ($e in $hdrs.GetEnumerator()) { if (('' + $e.Value) -match 'or-fake') { $valeNaoChave = $false } }
    Assert-True $valeNaoChave 'T4 seguranca: nenhum valor de header e a chave (nada de segredo vaza)' 
}
finally {
    Remove-Item Env:\VIXRADAR_OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue
}

Write-Host ('RESULTADO: ' + $script:falhas + ' falha(s)')
if ($script:falhas -gt 0) { exit 1 }
exit 0