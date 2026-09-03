# test-wsprobe-diagnostic.ps1 - prova de duas pontas de Test-VixWebSearchProbe (RUN429DGN1).
# Cobre: (1) sucesso -> $true e nenhum diag; (2) falha 429 -> $false e diag com code/stdout/stderr;
# (3) sanitizacao obrigatoria de 'sk-', 'Bearer' e vars de auth. Usa stub claude.cmd, sem tocar API
# (nenhum pedido real, nenhum token gasto). A lib chama '& claude', entao o stub entra no topo do PATH
# de um processo filho pwsh isolado. ASCII puro, PowerShell 5.1. Exit 0 = todos os asserts OK.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

# Auth real exige credencial; no-op local isola o alvo (captura + decisao binaria da sonda).
function Set-VixClaudeAuthEnv { }

# ---------------------------------------------------------------------------
$tmp = Join-Path $env:TEMP ('wsprobe_test_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # stub: modo ok -> exit 0 com valor numerico; modo 429 -> stdout+stderr com reset e secrets
    $stub = @'
@echo off
set "S1=sk-"
set "S2=ant-api03-FAKESECRETVALUE123456789"
set "B1=abcd"
set "B2=1234..."
if not "%TEST_MODE%"=="429" goto ok
echo error: 429 session limit reset em 2026-09-03T01:40:22Z standard output
echo error: 429 API session limit, reset em 2026-09-03T01:40:22Z 1>&2
echo debug env: %S1%%S2% 1>&2
echo debug Bearer %B1%%B2% 1>&2
exit /b 429
:ok
echo 12345.67
exit /b 0
'@
    Set-Content -LiteralPath (Join-Path $tmp 'claude.cmd') -Value $stub -Encoding Ascii
    # PATH do processo para que & claude resolva o stub (diretorio temp primeiro).
    $env:PATH = $tmp + ';' + $env:PATH
    # Fail-loud: se claude NAO resolver o stub, aborta em vez de arriscar tocar o binario real.
    $cmdClaude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $cmdClaude -or $cmdClaude.Source -notlike ($tmp + '\*')) {
        Write-Host 'FALHA_preamble: stub claude nao esta no topo do PATH; abortando sem tocar o binario real.'
        exit 2
    }

    $diagDir = $env:TEMP
    Remove-Item -Path (Join-Path $diagDir 'wsprobe_diag_*.log') -Force -ErrorAction SilentlyContinue

    # Caso 1: sucesso -> true, nenhum diag
    Write-Host '=== 1. sucesso -> $true e nenhum diag ==='
    Remove-Item Env:\TEST_MODE -ErrorAction SilentlyContinue
    $r1 = Test-VixWebSearchProbe
    Assert ($r1 -eq $true) ('retorno sucesso=' + $r1)
    $diags1 = @(Get-ChildItem -Path $diagDir -Filter 'wsprobe_diag_*.log' -ErrorAction SilentlyContinue)
    Assert ($diags1.Count -eq 0) ('sucesso nao gera diag (gerou ' + $diags1.Count + ')')

    # Caso 2: falha 429 -> false e diag com code/stdout/stderr
    Write-Host '=== 2. falha 429 -> $false e diag com code/stdout/stderr ==='
    $env:TEST_MODE = '429'
    $antes = @(Get-ChildItem -Path $diagDir -Filter 'wsprobe_diag_*.log' -ErrorAction SilentlyContinue | ForEach-Object Name)
    $r2 = Test-VixWebSearchProbe
    Assert ($r2 -eq $false) ('retorno falha=' + $r2)
    $diags2 = @(Get-ChildItem -Path $diagDir -Filter 'wsprobe_diag_*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $antes })
    Assert ($diags2.Count -eq 1) ('falha gera >=1 diag (gerou ' + $diags2.Count + ')')
    $conteudo = ''
    if ($diags2.Count -eq 1) {
        $conteudo = Get-Content -LiteralPath $diags2[0].FullName -Raw -Encoding UTF8
    }
    Assert ($conteudo -match 'code=429') 'diag registra exit code 429'
    Assert ($conteudo -match 'session limit reset em 2026-09-03T01:40:22Z standard output') 'diag preserva stdout (com instante de reset)'
    Assert ($conteudo -match 'session limit, reset em 2026-09-03T01:40:22Z') 'diag preserva stderr (com instante de reset)'

    # Caso 3: sanitizacao dos padroes sensiveis
    Write-Host '=== 3. sanitizacao obrigatoria (sem secret no diag) ==='
    Assert (-not ($conteudo -match 'FAKESECRETVALUE123456789')) 'secret sk-ant redigido (nao vaza literal)'
    Assert ($conteudo -match '<REDIGIDO>') 'marca de redacao presente no diag'
    Assert (-not ($conteudo -match 'Bearer abcd1234')) 'Bearer redigido (nao vaza literal)'
}
finally {
    Remove-Item Env:\TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    # Limpa artefatos legitimamente criados pelo run (stderr temp e diag do caso 429)
    # para o teste nao deixar residuo na TEMP de quem roda no CI.
    Remove-Item -Path (Join-Path $env:TEMP 'wsprobe_*.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP 'wsprobe_diag_*.log') -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
