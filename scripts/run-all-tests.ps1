# run-all-tests.ps1 - runner da suite de scripts/ (2026-09-12).
#
# Motivo: nao existia agregador. Nem o pre-commit nem o GitHub Actions rodavam os
# scripts/test-*.ps1, entao suites ficaram vermelhas por dias sem ninguem notar, e uma delas
# (test-busca-degradada) morria na extracao de funcao e escondia ~40 asserts verdadeiros.
# Suite que ninguem roda nao e suite, e decoracao.
#
# Contrato:
#   - enumera scripts/test-*.ps1 e executa cada um em PROCESSO separado, com timeout;
#   - compara o resultado com o baseline de falhas conhecidas (scripts/tests-baseline.json);
#   - exit 0 somente quando nenhuma suite fora do baseline esta vermelha;
#   - suite do baseline que ficou VERDE vira aviso de baseline obsoleto (nao falha): o baseline
#     so encolhe, por edicao explicita, nunca por acidente.
#
# Uso:
#   pwsh ./scripts/run-all-tests.ps1                 # roda tudo menos os pesados
#   pwsh ./scripts/run-all-tests.ps1 -Listar         # so lista, nao executa
#   pwsh ./scripts/run-all-tests.ps1 -IncluirPesados # inclui os que mexem em log/lock real
#   pwsh ./scripts/run-all-tests.ps1 -SoPadrao monitor
#
# PowerShell 5.1, ASCII puro (sem BOM necessario), $ErrorActionPreference Continue, exit real.
param(
    [switch]$Listar,
    [switch]$IncluirPesados,
    [int]$TimeoutSec = 300,
    [string]$SoPadrao
)

$ErrorActionPreference = 'Continue'
$ScriptsDir = $PSScriptRoot
$Root = Split-Path $ScriptsDir -Parent
$BaselineFile = Join-Path $ScriptsDir 'tests-baseline.json'

# Suites que NAO entram no gate por padrao. Motivo MEDIDO, nao precaucao:
#   test-locks-overlap: sobe o motor REAL quatro vezes (run_vixradar_varredura.ps1) e escreve
#   log/lock/transcript em logs\routines do dia. Leva ~7 min e deixa residuo se falhar no meio.
# Usa -IncluirPesados para rodar.
$Pesados = @{
    'test-locks-overlap.ps1' = 'sobe o motor real e escreve log/lock do dia em logs\routines'
}

function Get-Suites {
    $todas = @(Get-ChildItem -Path $ScriptsDir -Filter 'test-*.ps1' -File | Sort-Object Name)
    $out = @()
    foreach ($f in $todas) {
        if ($SoPadrao -and ($f.Name -notmatch $SoPadrao)) { continue }
        if ((-not $IncluirPesados) -and $Pesados.ContainsKey($f.Name)) { continue }
        $out += $f
    }
    return $out
}

function Read-Baseline {
    # Devolve @{ nome = motivo }. Ausente ou ilegivel vira baseline VAZIO, que e o padrao seguro:
    # sem baseline, qualquer suite vermelha reprova o gate. Nunca esconder falha por arquivo
    # faltando.
    $mapa = @{}
    if (-not (Test-Path $BaselineFile)) { return $mapa }
    try {
        $j = Get-Content $BaselineFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) {
            if ($p.Name -eq '_doc') { continue }
            $mapa[$p.Name] = [string]$p.Value.motivo
        }
    } catch {
        Write-Host ('AVISO: baseline ilegivel (' + $_.Exception.Message + ') - tratando como vazio.')
    }
    return $mapa
}

function Invoke-Suite {
    # Roda a suite em processo separado com timeout real. Nao deixa o runner pendurar numa suite
    # travada, nem herda exit code de outra.
    param([System.IO.FileInfo]$Arquivo, [int]$Segundos)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Arquivo.FullName + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $iniciou = $false
    try {
        $iniciou = $proc.Start()
    } catch {
        return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = -1; Saida = ('falha ao iniciar: ' + $_.Exception.Message); Timeout = $false }
    }
    if (-not $iniciou) {
        return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = -1; Saida = 'processo nao iniciou'; Timeout = $false }
    }
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $estourou = -not $proc.WaitForExit($Segundos * 1000)
    if ($estourou) {
        try { $proc.Kill() } catch { }
        try { $proc.WaitForExit(5000) | Out-Null } catch { }
    }
    $exit = -1
    if (-not $estourou) { $exit = $proc.ExitCode }
    $texto = ([string]$stdout + "`n" + [string]$stderr)
    return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = $exit; Saida = $texto; Timeout = $estourou }
}

function Get-ResumoSuite([string]$Texto) {
    # Ultima linha de resumo conhecida. Cada familia de suite usa um rotulo proprio; listar as
    # variantes aqui e o que permite resumir sem depender de um formato unico.
    foreach ($l in @(($Texto -split "`r?`n"))) {
        $t = ('' + $l).Trim()
        if ($t.StartsWith('RESULTADO')) { return $t }
    }
    if ($Texto -match '(?m)^\s*(PASS|OK)\s*') { return '(sem linha de resumo; executou assercoes)' }
    return '(sem linha de resumo)'
}

$baseline = Read-Baseline
$suites = @(Get-Suites)
$pesadosPulados = @()
if (-not $IncluirPesados) {
    foreach ($k in $Pesados.Keys) { $pesadosPulados += $k }
}

if ($Listar) {
    Write-Host ('Suite de scripts/ - ' + $suites.Count + ' arquivo(s)')
    foreach ($s in $suites) { Write-Host ('  ' + $s.Name) }
    foreach ($k in $pesadosPulados) { Write-Host ('  ' + $k + '   [PULADO: ' + $Pesados[$k] + ']') }
    if ($baseline.Count -gt 0) {
        Write-Host 'Baseline de falhas conhecidas:'
        foreach ($k in $baseline.Keys) { Write-Host ('  ' + $k + ' - ' + $baseline[$k]) }
    }
    exit 0
}

Write-Host '=== SUITE DE SCRIPTS ==='
Write-Host ('runner: ' + $suites.Count + ' suite(s) | timeout ' + $TimeoutSec + 's | baseline ' + $baseline.Count + ' falha(s) conhecida(s)')
Write-Host ''

$verdes = 0
$vermelhas = @()
$novas = @()
$baselineObsoleto = @()
$baselineConfirmado = @()

foreach ($s in $suites) {
    $t0 = Get-Date
    $r = Invoke-Suite -Arquivo $s -Segundos $TimeoutSec
    $dur = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $resumo = Get-ResumoSuite $r.Saida
    $rotulo = 'ok'
    $cor = 'OK  '
    if ($r.Timeout) {
        $rotulo = 'timeout'
        $cor = 'FAIL'
    } elseif ($r.Exit -ne 0) {
        $rotulo = 'falha'
        $cor = 'FAIL'
    }
    Write-Host ($cor + ' ' + $s.Name.PadRight(38) + ' ' + $resumo + '  [' + $dur + 's exit=' + $r.Exit + ']')

    $noBaseline = $baseline.ContainsKey($s.Name)
    if ($rotulo -eq 'ok') {
        $verdes++
        if ($noBaseline) { $baselineObsoleto += $s.Name }
    } else {
        $vermelhas += $s.Name
        if ($noBaseline) {
            $baselineConfirmado += $s.Name
        } else {
            $novas += $s.Name
            # Imprime as falhas reais da suite nova, para o operador nao precisar reabrir a saida.
            foreach ($l in @(($r.Saida -split "`r?`n"))) {
                $t = ('' + $l).Trim()
                if ($t -match '^(FALHA|FAIL)') { Write-Host ('       ' + $t) }
            }
        }
    }
}

Write-Host ''
Write-Host ('TOTAL: ' + $suites.Count + ' suite(s) | verde=' + $verdes + ' | vermelha=' + $vermelhas.Count)
if ($baselineConfirmado.Count -gt 0) {
    Write-Host ('  falha conhecida (baseline confirmado): ' + $baselineConfirmado.Count)
    foreach ($n in $baselineConfirmado) { Write-Host ('    - ' + $n + ' - ' + $baseline[$n]) }
}
if ($novas.Count -gt 0) {
    Write-Host ('  REGRESSAO NOVA (nao esta no baseline): ' + $novas.Count)
    foreach ($n in $novas) { Write-Host ('    - ' + $n) }
}
if ($baselineObsoleto.Count -gt 0) {
    Write-Host '  AVISO: baseline obsoleto, estas suites ja estao verdes e podem sair do arquivo:'
    foreach ($n in $baselineObsoleto) { Write-Host ('    - ' + $n) }
}
foreach ($k in $pesadosPulados) { Write-Host ('  PULADO (pesado): ' + $k + ' - ' + $Pesados[$k]) }

# Exit = regressoes novas. Suite que trava (exit 1 sem resumo) tambem conta, de proposito:
# vermelho visivel e melhor que verde falso.
if ($novas.Count -gt 0) { exit [Math]::Min($novas.Count, 255) }
exit 0
