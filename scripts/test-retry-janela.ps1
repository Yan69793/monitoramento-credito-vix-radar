# test-retry-janela.ps1 - prova de duas pontas do julgamento de entrega por janela
# (INCIDENTE-FRESHNESS2, A4/H). Parte 1: Test-VixLedgerEntregueNaJanela isolada
# (lib/vixradar-watchdog.ps1). Parte 2: retry-vixradar.ps1 fim a fim, com
# -RunnerOverride/-LogDirOverride/-SemAlerta (nenhum toca producao, nenhum POST
# real, nenhum token gasto - o "relancamento" e um stub .ps1). ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$tmp = Join-Path $env:TEMP ('vixretryjanela_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # ============================================================
    Write-Host '=== Parte 1: Test-VixLedgerEntregueNaJanela (unitario) ==='
    $dataLog = Get-Date -Year 2026 -Month 9 -Day 3 -Hour 0 -Minute 0 -Second 0

    Write-Host '--- 1a: FIM as 01:30 (antes da janela 18:00) nao confirma ---'
    $c1 = "2026-09-03 01:30:00 FIM: noturno concluido. Total do dia 103/103. submits_aceitos=103`n"
    $r1 = Test-VixLedgerEntregueNaJanela -Conteudo $c1 -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($r1.Entregue -eq $false) ('1a: Entregue=false (obtido ' + $r1.Entregue + ')')

    Write-Host '--- 1b: FIM as 19:00 (depois da janela) com contagem suficiente confirma ---'
    $c2 = "2026-09-03 19:00:00 FIM: noturno concluido. Total do dia 103/103. submits_aceitos=103`n"
    $r2 = Test-VixLedgerEntregueNaJanela -Conteudo $c2 -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($r2.Entregue -eq $true) ('1b: Entregue=true (obtido ' + $r2.Entregue + ')')
    Assert ($r2.FimComContagemSuficiente -eq $true) '1b: FimComContagemSuficiente=true'

    Write-Host '--- 1c: FIM as 19:00 SEM contagem parseavel nao basta sozinho ---'
    $c3 = "2026-09-03 19:00:00 RUNNER_FIM: claude exit 0 (entrega e julgada pelo ledger OK|, nao por este exit code)`n"
    $r3 = Test-VixLedgerEntregueNaJanela -Conteudo $c3 -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($r3.Entregue -eq $false) ('1c: Entregue=false, RUNNER_FIM sozinho nao prova entrega (obtido ' + $r3.Entregue + ')')
    Assert ($r3.LedgerNaJanela -eq 0) '1c: ledger vazio'

    Write-Host '--- 1d: ledger OK| suficiente dentro da janela confirma, mesmo sem FIM: ---'
    $sb = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le 91; $i++) { [void]$sb.AppendLine('2026-09-03 18:1' + ($i % 10) + ':00 OK|Emissor' + $i + '|FULL|ECO|0|True') }
    $r4 = Test-VixLedgerEntregueNaJanela -Conteudo $sb.ToString() -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($r4.Entregue -eq $true) ('1d: Entregue=true so por ledger (obtido ' + $r4.Entregue + ', ledger=' + $r4.LedgerNaJanela + ')')

    Write-Host '--- 1e: mesmo ledger, mas TODO carimbado antes da janela, nao conta ---'
    $sb2 = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le 91; $i++) { [void]$sb2.AppendLine('2026-09-03 02:1' + ($i % 10) + ':00 OK|Emissor' + $i + '|FULL|ECO|0|True') }
    $r5 = Test-VixLedgerEntregueNaJanela -Conteudo $sb2.ToString() -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($r5.Entregue -eq $false) ('1e: Entregue=false, ledger de madrugada nao conta para janela 18:00 (obtido ' + $r5.Entregue + ', ledger=' + $r5.LedgerNaJanela + ')')

    Write-Host '--- 1f: janela da matinal (10:00), FIM as 10:30 com 12/19 confirma ---'
    $c6 = "2026-09-03 10:30:00 FIM: matinal 12/19 processados.`n"
    $r6 = Test-VixLedgerEntregueNaJanela -Conteudo $c6 -DataLog $dataLog -JanelaHora 10 -MinimoLedger 12
    Assert ($r6.Entregue -eq $true) ('1f: matinal 12/19 as 10:30 confirma (obtido ' + $r6.Entregue + ')')

    # ============================================================
    Write-Host '=== Parte 2: retry-vixradar.ps1 fim a fim (stub, sem rede, sem token) ==='
    $retryScript = Join-Path $PSScriptRoot 'retry-vixradar.ps1'
    $logDirTeste = Join-Path $tmp 'logs'
    New-Item -ItemType Directory -Force -Path $logDirTeste | Out-Null
    $dataTag = Get-Date -Format 'yyyyMMdd'

    function New-VixStubRunner([string]$Comportamento) {
        # Comportamento 'escreve_ledger': grava 90 OK| + RUNNER_FIM dentro da janela e sai 0.
        # Comportamento 'sem_ledger': so grava RUNNER_FIM (sem nenhum OK|) e sai 0 -
        # reproduz o defeito real de 19/08 (exit 0 sem nenhum submit).
        # Carimbo FIXO (18:3x de hoje, dentro da janela do noturno), nao o relogio
        # real - o teste tem que dar o mesmo resultado a qualquer hora do dia.
        $dataFmt = Get-Date -Format 'yyyy-MM-dd'
        $p = Join-Path $tmp ('stub_runner_' + $Comportamento + '.ps1')
        $body = @"
param([string]`$RoutineId, [string]`$Fallback429 = 'ChavePaga')
`$logFile = '$($logDirTeste -replace "'", "''")\' + `$RoutineId + '_$dataTag.log'
`$ts = '$dataFmt 18:30:00'
"@
        if ($Comportamento -eq 'escreve_ledger') {
            $body += "`n" + @'
for ($i = 1; $i -le 91; $i++) {
    Add-Content -Path $logFile -Value ($ts + ' OK|Emissor' + $i + '|FULL|ECO|0|True') -Encoding UTF8
}
Add-Content -Path $logFile -Value ($ts + ' RUNNER_FIM: claude exit 0 (entrega e julgada pelo ledger OK|, nao por este exit code)') -Encoding UTF8
exit 0
'@
        } else {
            $body += "`n" + @'
Add-Content -Path $logFile -Value ($ts + ' RUNNER_FIM: claude exit 0 (entrega e julgada pelo ledger OK|, nao por este exit code)') -Encoding UTF8
exit 0
'@
        }
        Set-Content -LiteralPath $p -Value $body -Encoding UTF8
        return $p
    }

    Write-Host '--- 2a: relancamento SEM ledger (exit 0) -> alerta, exit 1 ---'
    Remove-Item -Path (Join-Path $logDirTeste '*') -Force -ErrorAction SilentlyContinue
    $stubSemLedger = New-VixStubRunner 'sem_ledger'
    # Log do dia ja existe (parado ha mais de 15 min), simulando "SEM ENTREGA" antes do retry.
    $logInicial = Join-Path $logDirTeste ('vixradar-noturno_' + $dataTag + '.log')
    $tsAntigo = (Get-Date).AddMinutes(-30).ToString('yyyy-MM-dd HH:mm:ss')
    Set-Content -LiteralPath $logInicial -Value ($tsAntigo + ' INICIO: noturno 103 emissores (sessao agendada Claude Desktop)') -Encoding UTF8
    (Get-Item $logInicial).LastWriteTime = (Get-Date).AddMinutes(-30)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $retryScript -RoutineId vixradar-noturno -RunnerOverride $stubSemLedger -LogDirOverride $logDirTeste -SemAlerta | Out-Null
    $exit2a = $LASTEXITCODE
    Assert ($exit2a -eq 1) ('2a: retry-vixradar.ps1 sai exit 1 quando relancamento nao entrega (obtido ' + $exit2a + ')')
    $retLog2a = Join-Path $logDirTeste ('retry-vixradar-noturno_' + $dataTag + '.log')
    $conteudoRet2a = Get-Content -LiteralPath $retLog2a -Raw -Encoding UTF8
    Assert ($conteudoRet2a -match 'SEM ENTREGA APOS RELANCAMENTO') '2a: log do retry registra SEM ENTREGA APOS RELANCAMENTO'
    Assert ($conteudoRet2a -match 'ALERTA \(SemAlerta') '2a: alerta foi acionado (suprimido so pelo -SemAlerta do teste)'

    Write-Host '--- 2b: relancamento COM ledger >= 90 -> sem alerta, exit 0 ---'
    Remove-Item -Path (Join-Path $logDirTeste '*') -Force -ErrorAction SilentlyContinue
    $stubComLedger = New-VixStubRunner 'escreve_ledger'
    Set-Content -LiteralPath $logInicial -Value ($tsAntigo + ' INICIO: noturno 103 emissores (sessao agendada Claude Desktop)') -Encoding UTF8
    (Get-Item $logInicial).LastWriteTime = (Get-Date).AddMinutes(-30)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $retryScript -RoutineId vixradar-noturno -RunnerOverride $stubComLedger -LogDirOverride $logDirTeste -SemAlerta | Out-Null
    $exit2b = $LASTEXITCODE
    Assert ($exit2b -eq 0) ('2b: retry-vixradar.ps1 sai exit 0 quando o ledger confirma (obtido ' + $exit2b + ')')
    $retLog2b = Join-Path $logDirTeste ('retry-vixradar-noturno_' + $dataTag + '.log')
    $conteudoRet2b = Get-Content -LiteralPath $retLog2b -Raw -Encoding UTF8
    Assert ($conteudoRet2b -match 'ENTREGA CONFIRMADA apos relancamento') '2b: log do retry registra ENTREGA CONFIRMADA'
    Assert (-not ($conteudoRet2b -match 'ALERTA \(SemAlerta')) '2b: nenhum alerta acionado (entrega confirmada)'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
