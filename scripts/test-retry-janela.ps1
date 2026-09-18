# test-retry-janela.ps1 - prova de duas pontas do julgamento de entrega por janela
# (INCIDENTE-FRESHNESS2, A4/H). Parte 1: Test-VixLedgerEntregueNaJanela isolada
# (lib/vixradar-watchdog.ps1). Parte 2: retry-vixradar.ps1 fim a fim, com
# -RunnerOverride/-LogDirOverride/-SemAlerta (nenhum toca producao, nenhum POST
# real, nenhum token gasto - o "relancamento" e um stub .ps1). Parte 3: destino do
# relancamento por rotina (prova por AST, sem executar). Parte 4 (PROVIDERRETRY1,
# 17/09): o gate de provider do retry nas duas pontas - openrouter segue adiante
# ate o julgamento de ledger/janela, none continua no-op canonico exit 0 - e o
# gate legado so-Claude fica proibido de voltar a decidir o retry (incidente: a
# varredura de 17/09 ficou sem recuperacao porque ele no-opou com exit 0).
# ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')

# Fixture de provider: o retry tem o gate de provider ANTES do julgamento por janela
# (lib/vixradar-llm-provider.ps1). Maquina sem VIXRADAR_LLM_PROVIDER - o windows-latest do CI,
# por exemplo - cai no no-op BLOQUEADO_SEM_PROVIDER exit 0, e esta suite mediria o gate em vez
# do julgamento que ela existe para provar. Fixa claude-subscription apenas no
# escopo DESTE processo, herdado pelos processos filhos; registro nenhum e tocado,
# e o valor original volta no finally. Claude permanece o fixture das Partes 1 a 3
# porque e o unico provider que passa tanto pelo gate legado quanto pelo canonico,
# e o objeto destas partes e o JULGAMENTO de janela, nao o gate (o gate tem prova
# propria na Parte 4). Mesma pratica de test-monitor-provider-gate.ps1.
$providerOriginal = $env:VIXRADAR_LLM_PROVIDER
$env:VIXRADAR_LLM_PROVIDER = 'claude-subscription'

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

    Write-Host '--- 1g: FIM_INVALIDO (trabalho zero) como ultima marcacao -> nao entregue, mesmo com ledger >= 90 ---'
    $sbg = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le 91; $i++) { [void]$sbg.AppendLine('2026-09-03 18:1' + ($i % 10) + ':00 OK|Emissor' + $i + '|LIGHT|INCONCLUSIVO|0|true|ANALISADO') }
    [void]$sbg.AppendLine('2026-09-03 18:59:00 FIM_INVALIDO: noturno INVALIDO (trabalho zero). Total do dia 104/104. analisados=87 buscas=0 tokens=0')
    $rg = Test-VixLedgerEntregueNaJanela -Conteudo $sbg.ToString() -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($rg.Entregue -eq $false) ('1g: Entregue=false, FIM_INVALIDO invalida ledger fabricado (obtido ' + $rg.Entregue + ', ledger=' + $rg.LedgerNaJanela + ')')

    Write-Host '--- 1h: FIM_INVALIDO seguido de FIM real -> entregue (ultima marcacao vence) ---'
    $sbh = New-Object System.Text.StringBuilder
    for ($i = 1; $i -le 91; $i++) { [void]$sbh.AppendLine('2026-09-03 18:1' + ($i % 10) + ':00 OK|Emissor' + $i + '|FULL|ECO|0|True') }
    [void]$sbh.AppendLine('2026-09-03 18:30:00 FIM_INVALIDO: noturno INVALIDO (trabalho zero). Total do dia 104/104. analisados=87 buscas=0 tokens=0')
    [void]$sbh.AppendLine('2026-09-03 19:00:00 FIM: noturno concluido. Total do dia 103/103. submits_aceitos=103')
    $rh = Test-VixLedgerEntregueNaJanela -Conteudo $sbh.ToString() -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
    Assert ($rh.Entregue -eq $true) ('1h: Entregue=true, FIM real posterior reseta a marcacao INVALIDO (obtido ' + $rh.Entregue + ')')

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

    # ============================================================
    # Parte 3: MOTORRETRY1 - o retry relanca o MOTOR, por rotina.
    # Antes relancava run_claude_routine.ps1 (SKILL do Claude Desktop), que e o
    # caminho legado morto desde o MOTOR1. Prova extraida por AST para nao
    # executar o script (executar de verdade relancaria a rotina).
    Write-Host '=== Parte 3: MOTORRETRY1 - destino do relancamento por rotina ==='
    $tokensR = $null; $errorsR = $null
    $astR = [System.Management.Automation.Language.Parser]::ParseFile($retryScript, [ref]$tokensR, [ref]$errorsR)
    Assert ($errorsR.Count -eq 0) ('3a: retry-vixradar.ps1 faz parse sem erro (obtido ' + $errorsR.Count + ')')
    $defRunner = $astR.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-VixRetryRunner' }, $true) | Select-Object -First 1
    Assert ($null -ne $defRunner) '3b: funcao Get-VixRetryRunner existe'
    if ($defRunner) {
        # A funcao extraida depende de $VixRoot, que vive no escopo do script; o teste
        # fornece o mesmo valor (raiz do repo) para poder chama-la isolada.
        $VixRoot = Split-Path $PSScriptRoot -Parent
        Invoke-Expression $defRunner.Extent.Text
        $dNot = Get-VixRetryRunner 'vixradar-noturno' $null
        $dMat = Get-VixRetryRunner 'vixradar-matinal' $null
        $dStub = Get-VixRetryRunner 'vixradar-noturno' 'C:\tmp\stub.ps1'
        Assert ((Split-Path $dNot.Path -Leaf) -eq 'run_vixradar_noturno_claude.ps1') ('3c: noturno relanca o wrapper do motor (obtido ' + $dNot.Path + ')')
        Assert ((Split-Path $dMat.Path -Leaf) -eq 'run_vixradar_matinal_claude.ps1') ('3d: matinal relanca o wrapper do motor (obtido ' + $dMat.Path + ')')
        Assert ($dNot.PassaRoutineId -eq $false -and $dMat.PassaRoutineId -eq $false) '3e: wrapper do motor nao recebe -RoutineId (a rotina esta fixada nele)'
        Assert ($dStub.Path -eq 'C:\tmp\stub.ps1' -and $dStub.PassaRoutineId -eq $true) '3f: -RunnerOverride vence o mapa e mantem -RoutineId (compativel com o stub desta suite)'
        Assert ((Test-Path -LiteralPath $dNot.Path) -and (Test-Path -LiteralPath $dMat.Path)) '3g: os dois wrappers apontados existem no repo'
    }
    $chamadaRunner = $astR.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.CommandElements.Count -gt 0 -and $n.CommandElements[0].Extent.Text -eq 'powershell.exe' }, $true)
    Assert ($chamadaRunner.Count -ge 1) '3h: o retry invoca powershell.exe em algum ponto'

    # ============================================================
    # Parte 4: PROVIDERRETRY1 (17/09) - gate de provider do retry, duas pontas.
    # Incidente: com provider openrouter (o efetivo do operador desde 17/09), o gate
    # legado so-Claude devolvia $false e o retry virava no-op silencioso exit 0 - a
    # varredura do dia ficava sem recuperacao e nenhuma linha acusava (o exit 0
    # enganava o monitor). O retry tem que decidir pelo gate canonico
    # Test-VixLlmProviderPermiteRotina, o mesmo do motor e do monitor. Cada ponta roda
    # o retry REAL com stub inerte (so exit 0, nao escreve nada) e -SemAlerta: nenhum
    # POST, nenhum token, nenhum relancamento real. Diretorio proprio por provider
    # porque o log do retry e por Append-Content (rodadas anteriores somariam).
    Write-Host '=== Parte 4: PROVIDERRETRY1 - gate de provider do retry (duas pontas) ==='
    $stubInerteP4 = Join-Path $tmp 'stub_runner_inerte.ps1'
    Set-Content -LiteralPath $stubInerteP4 -Value "param([string]`$RoutineId, [string]`$Fallback429 = 'ChavePega')`nexit 0" -Encoding UTF8
    function Invoke-RetryP4([string]$Provider) {
        # Roda o retry real de novo com o provider da vez; log da rotina parado ha
        # 30 min (SEM ENTREGA), como na Parte 2. Devolve exit + log do retry.
        $env:VIXRADAR_LLM_PROVIDER = $Provider
        $dirRun = Join-Path $tmp ('p4_' + $Provider)
        New-Item -ItemType Directory -Force -Path $dirRun | Out-Null
        $logRotRun = Join-Path $dirRun ('vixradar-noturno_' + $dataTag + '.log')
        Set-Content -LiteralPath $logRotRun -Value ($tsAntigo + ' INICIO: noturno 103 emissores (fixture Parte 4)') -Encoding UTF8
        (Get-Item $logRotRun).LastWriteTime = (Get-Date).AddMinutes(-30)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $retryScript -RoutineId vixradar-noturno -RunnerOverride $stubInerteP4 -LogDirOverride $dirRun -SemAlerta | Out-Null
        $retLogRun = Join-Path $dirRun ('retry-vixradar-noturno_' + $dataTag + '.log')
        $saida = [pscustomobject]@{ Exit = $LASTEXITCODE; Log = (Get-Content -LiteralPath $retLogRun -Raw -Encoding UTF8) }
        return $saida
    }

    Write-Host '--- 4a: provider openrouter -> gate passa, segue ate o julgamento e o relancamento ---'
    $r4a = Invoke-RetryP4 'openrouter'
    Assert ($r4a.Exit -eq 1) ('4a: openrouter sai exit 1 quando o relancamento nao entrega (obtido ' + $r4a.Exit + ')')
    Assert (-not ($r4a.Log -match 'BLOQUEADO_SEM_PROVIDER')) '4a: openrouter NAO emite BLOQUEADO_SEM_PROVIDER (a linha do incidente 17/09)'
    Assert (-not ($r4a.Log -match 'no-op, nao relanca')) '4a: openrouter NAO sai pelo no-op de provider'
    Assert ($r4a.Log -match 'RETRY EXIT:') '4a: openrouter chegou ao relancamento de verdade'
    Assert ($r4a.Log -match 'SEM ENTREGA APOS RELANCAMENTO') '4a: re-verificacao pos-relancamento rodou (julgamento por janela, nao por exit)'

    Write-Host '--- 4b: provider none -> no-op canonico, exit 0, sem regressao ---'
    $r4b = Invoke-RetryP4 'none'
    Assert ($r4b.Exit -eq 0) ('4b: none sai exit 0 (no-op limpo, obtido ' + $r4b.Exit + ')')
    Assert ($r4b.Log -match 'BLOQUEADO_SEM_PROVIDER provider=none') '4b: linha canonica BLOQUEADO_SEM_PROVIDER com provider=none'
    Assert ($r4b.Log -match 'no-op, nao relanca') '4b: motivo registra o no-op'
    Assert ($r4b.Log -match 'provider nao configurado') '4b: motivo e o canonico do provider ausente'
    Assert (-not ($r4b.Log -match 'RETRY EXIT:')) '4b: nenhum relancamento sob provider none'

    Write-Host '--- 4c: provider claude-manual sem -ForceClaude -> no-op canonico (Fase A preservada) ---'
    $r4c = Invoke-RetryP4 'claude-manual'
    Assert ($r4c.Exit -eq 0) ('4c: claude-manual sai exit 0 (no-op, obtido ' + $r4c.Exit + ')')
    Assert ($r4c.Log -match 'Claude manual exige -ForceClaude') '4c: motivo exige forca manual explicita (scheduler nunca passa)'

    Write-Host '--- 4d: estatico - o gate legado nao decide mais o retry ---'
    $srcRetry = Get-Content -LiteralPath $retryScript -Raw -Encoding UTF8
    Assert (-not ($srcRetry -match 'Test-VixLlmPermiteClaude')) '4d: gate legado so-Claude removido da decisao do retry (reprova o defeito de 17/09)'
    Assert ($srcRetry -match 'Test-VixLlmProviderPermiteRotina') '4d: retry usa o gate canonico (mesma decisao do motor e do monitor)'
    Assert ($srcRetry -match 'vixradar-openrouter\.ps1') '4d: retry carrega o adapter OpenRouter antes do gate (openrouter exige adapter presente)'
}
finally {
    $env:VIXRADAR_LLM_PROVIDER = $providerOriginal
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
