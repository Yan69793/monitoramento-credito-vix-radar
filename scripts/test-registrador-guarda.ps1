# test-registrador-guarda.ps1 - prova do contrato de guarda dos registradores (GUARD-REG1).
#
# O que este teste prova, e so isso:
#   1. a Action montada pelos registradores e o MESMO formato de apply-preflight-tasks.ps1
#      (igualdade exata de string, que e como o apply compara);
#   2. a forma ANTES do patch (Action apontando para a rotina) e reprovada pelos tokens;
#   3. ausencia do guarda falha FECHADO, pela mesma funcao que a producao usa;
#   4. fail-closed de ponta a ponta: o registrador real, com a raiz trocada por uma raiz
#      temporaria SEM o guarda, RECUSA; com o guarda presente, o DryRun aprova;
#   5. a lib do guarda nao escreve no Task Scheduler (nenhum cmdlet de escrita no fonte);
#   6. os 9 registradores tem -DryRun, usam o contrato e nao montam Action literal sem guarda;
#   7. o -DryRun de cada registrador roda e sai 0 sem registrar nada.
#
# Nao registra, nao altera, nao dispara task, nao usa rede. Escreve so em %TEMP% e apaga no fim.
# ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'
$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib\vixradar-task-guard.ps1')

$guarda = Join-Path $scriptDir 'preflight-and-run.ps1'
$guardaReal = Assert-VixGuardPath -Guarda $guarda

Write-Host '=== 1. a Action montada e o mesmo formato de apply-preflight-tasks.ps1 ==='
$alvoColeta = Join-Path $scriptDir 'run_coleta_volatilidade.ps1'
$esperado = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $guardaReal + '"' +
    ' -GuardTarget "' + $alvoColeta + '"' +
    " -GuardName 'VIXRadar-Coleta-Volatilidade'" +
    ' -GuardLogPattern "logs\routines\coleta_volatilidade_{yyyyMMdd}.log"'
$arg = Get-VixGuardArgument -Guarda $guardaReal -Target $alvoColeta -Name 'VIXRadar-Coleta-Volatilidade' -LogPattern 'logs\routines\coleta_volatilidade_{yyyyMMdd}.log'
Assert ($arg -eq $esperado) 'Get-VixGuardArgument reproduz o formato do apply por igualdade exata'
Assert ($arg.StartsWith('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "')) 'a Action comeca no powershell.exe e vai direto para o guarda'
Assert (@(Get-VixGuardArgumentFaltas -Argument $arg).Count -eq 0) 'Action com guarda tem os 3 tokens obrigatorios'

$comArgs = Get-VixGuardArgument -Guarda $guardaReal -Target (Join-Path $scriptDir 'retry-vixradar.ps1') -Name 'Szuchmacher-RetryVixMatinal' -LogPattern 'logs\routines\vixradar-matinal_{yyyyMMdd}.log' -ExtraArgs @('-RoutineId', 'vixradar-matinal')
Assert ($comArgs -like '*-GuardLogPattern "logs\routines\vixradar-matinal_{yyyyMMdd}.log" -RoutineId vixradar-matinal') 'argumento funcional entra depois do -GuardLogPattern, como no apply'
Assert ($comArgs -notlike '*-RoutineId*vixradar-matinal*-GuardLogPattern*') 'argumento funcional nao fura a frente do guarda'

Write-Host ''
Write-Host '=== 2. a forma ANTES do patch (Action apontando para a rotina) e reprovada ==='
$antes = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $alvoColeta + '"'
$faltasAntes = @(Get-VixGuardArgumentFaltas -Argument $antes)
Assert ($faltasAntes.Count -eq 4) ('a forma antiga reprova pelos 4 tokens (faltas=' + $faltasAntes.Count + ')')
Assert ($faltasAntes -contains 'sem preflight-and-run.ps1') 'a reprovacao nomeia a ausencia do guarda'
Assert ($faltasAntes -contains 'sem -GuardTarget') 'a reprovacao nomeia o -GuardTarget ausente'

Write-Host ''
Write-Host '=== 3. ausencia do guarda falha FECHADO na funcao que a producao usa ==='
$recusouVazio = $false
try { Assert-VixGuardPath -Guarda '' | Out-Null } catch { $recusouVazio = $true }
Assert $recusouVazio 'Assert-VixGuardPath recusa caminho vazio'
$inexistente = Join-Path $env:TEMP 'yan-guard-inexistente-preflight-and-run.ps1'
$recusouAusente = $false
try { Assert-VixGuardPath -Guarda $inexistente | Out-Null } catch { $recusouAusente = $true }
Assert $recusouAusente 'Assert-VixGuardPath recusa guarda inexistente (nao passa em silencio)'
$recusouMensagem = ''
try { Assert-VixGuardPath -Guarda $inexistente | Out-Null } catch { $recusouMensagem = $_.Exception.Message }
Assert ($recusouMensagem -match 'guarda ausente') 'a recusa nomeia o guarda ausente'

Write-Host ''
Write-Host '=== 4. fail-closed de ponta a ponta no registrador, em raiz temporaria ==='
# Fixture: o MESMO registrador real, com $ProjectRoot trocado por uma raiz temporaria. O nome da
# task tambem e trocado para nao depender do estado do Agendador desta maquina (nenhuma task real
# e lida nem escrita; em CI o nome real estaria ausente e o resultado seria o mesmo).
$tmp = Join-Path $env:TEMP ('yan-guard-test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'scripts\lib') | Out-Null
    Copy-Item -LiteralPath (Join-Path $scriptDir 'lib\vixradar-task-guard.ps1') -Destination (Join-Path $tmp 'scripts\lib\vixradar-task-guard.ps1')
    Set-Content -LiteralPath (Join-Path $tmp 'scripts\run_coleta_volatilidade.ps1') -Value '# stub de alvo para o fixture' -Encoding ASCII

    $src = Get-Content -LiteralPath (Join-Path $scriptDir 'register-coleta-volatilidade-task.ps1') -Raw -Encoding UTF8
    $mut = $src -replace "\`$ProjectRoot = '.*'", ("`$ProjectRoot = '" + $tmp + "'")
    $mut = $mut -replace 'VIXRadar-Coleta-Volatilidade', 'VIXRadar-GuardFixture-Reg'
    Assert ($mut -ne $src) 'fixture: a raiz e o nome do registrador foram trocados pelos temporarios'
    $mutPath = Join-Path $tmp 'register-coleta-volatilidade-task.ps1'
    Set-Content -LiteralPath $mutPath -Value $mut -Encoding ASCII

    # VERMELHO: raiz sem o guarda. O registrador tem de recusar e sair nao-zero.
    $saidaVermelha = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $mutPath -DryRun *>&1 | Out-String)
    $rcVermelho = $LASTEXITCODE
    Assert ($rcVermelho -ne 0) ('registrador RECUSA sem o guarda (exit=' + $rcVermelho + ')')
    Assert ($saidaVermelha -match 'guarda ausente') 'a recusa do registrador nomeia o guarda ausente'
    Assert ($saidaVermelha -notmatch 'DRYRUN OK') 'sem o guarda nao ha DRYRUN OK'

    # VERDE: com o guarda presente, o MESMO registrador monta a Action e aprova.
    Copy-Item -LiteralPath $guarda -Destination (Join-Path $tmp 'scripts\preflight-and-run.ps1')
    $saidaVerde = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $mutPath -DryRun *>&1 | Out-String)
    $rcVerde = $LASTEXITCODE
    Assert ($rcVerde -eq 0) ('com o guarda presente o DryRun aprova (exit=' + $rcVerde + ')')
    Assert ($saidaVerde -match 'DRYRUN OK') 'a saida aprovada traz DRYRUN OK'
    Assert ($saidaVerde -match 'preflight-and-run\.ps1') 'a Action do DryRun passa pelo guarda'
} finally {
    if (Test-Path -LiteralPath $tmp) { [System.IO.Directory]::Delete($tmp, $true) }
}

Write-Host ''
Write-Host '=== 5. a lib do guarda nao escreve no Task Scheduler ==='
$srcLib = Get-Content -LiteralPath (Join-Path $scriptDir 'lib\vixradar-task-guard.ps1') -Raw -Encoding UTF8
Assert ($srcLib -notmatch 'Register-ScheduledTask|Set-ScheduledTask|Unregister-ScheduledTask|Start-ScheduledTask|Enable-ScheduledTask|Disable-ScheduledTask') 'a lib nao usa nenhum cmdlet de escrita no Agendador'
Assert ($srcLib -notmatch 'Invoke-WebRequest|Invoke-RestMethod|Send-MailMessage') 'a lib nao usa rede nem e-mail'

Write-Host ''
Write-Host '=== 6. os 9 registradores usam o contrato e tem -DryRun ==='
$registradores = @(
    'register-all-routines-scheduler.ps1',
    'register-coleta-volatilidade-task.ps1',
    'register-export-historico-task.ps1',
    'register-monitor-tasks.ps1',
    'register-ranking-mensal-task.ps1',
    'register-reconciliacao-cvm-task.ps1',
    'register-retry-tasks.ps1',
    'register-sentinela-task.ps1',
    'watch-vixradar-health.ps1'
)
Assert ($registradores.Count -eq 9) ('escopo do patch: 9 registradores (achados=' + $registradores.Count + ')')

foreach ($nome in $registradores) {
    $caminho = Join-Path $scriptDir $nome
    if (-not (Test-Path -LiteralPath $caminho)) { Assert $false ($nome + ' existe'); continue }
    $src = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8

    $errosParse = $null
    [System.Management.Automation.Language.Parser]::ParseFile($caminho, [ref]$null, [ref]$errosParse) | Out-Null
    Assert (@($errosParse).Count -eq 0) ($nome + ': parseia no powershell.exe 5.1')

    Assert ($src -match '\$DryRun') ($nome + ': tem modo DryRun')
    Assert ($src -match 'preflight-and-run\.ps1') ($nome + ': cita o guarda')
    # Os 3 tokens aparecem literais no canonico (bloco inline) ou na chamada da lib (os demais).
    $declaraTokens = ($src -match 'Get-VixGuardArgument') -or (($src -match '-GuardTarget') -and ($src -match '-GuardName') -and ($src -match '-GuardLogPattern'))
    Assert $declaraTokens ($nome + ': declara os 3 tokens de guarda')

    # Fail-closed no proprio registrador, pela lib ou pelo bloco inline do canonico.
    $failClosed = ($src -match 'Assert-VixGuardPath') -or ($src -match 'Test-Path -LiteralPath\s+\$Guarda')
    Assert $failClosed ($nome + ': recusa quando o guarda nao esta na arvore')

    # Nenhuma Action literal sem guarda: o argumento tem de vir de variavel montada pelo contrato.
    Assert (-not ($src -match 'New-ScheduledTaskAction[^\r\n]*-Argument\s+"')) ($nome + ': nao monta Action literal sem guarda')
    Assert (-not ($src -match '<Arguments>-NoProfile')) ($nome + ': nao monta Arguments XML sem guarda')
}

Write-Host ''
Write-Host '=== 7. o -DryRun de cada registrador roda e prova a Action sem registrar nada ==='
# O que esta secao prende e a ESTRUTURA da Action (o guarda e os 3 tokens) e a ausencia de falha
# de token: isso nao depende da maquina. O exit 0 depende do Agendador LOCAL - se a task viva
# existir apontando para outro caminho (outro clone, outra maquina), a comparacao acusa diferenca
# de ambiente e isso e reportado como diferenca de maquina, nao como defeito do registrador.
# Teste que fica vermelho por estado da maquina e ruido, nao gate.
# register-all cria tambem 2 tasks de OUTRO repositorio (isentas por construcao): so entra no
# DryRun desta suite quando aqueles alvos existem na maquina.
$dryRuns = @(
    'register-coleta-volatilidade-task.ps1',
    'register-export-historico-task.ps1',
    'register-monitor-tasks.ps1',
    'register-ranking-mensal-task.ps1',
    'register-reconciliacao-cvm-task.ps1',
    'register-retry-tasks.ps1',
    'register-sentinela-task.ps1',
    'watch-vixradar-health.ps1'
)
$difereMaquina = 0
foreach ($nome in $dryRuns) {
    $caminho = Join-Path $scriptDir $nome
    $saida = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $caminho -DryRun *>&1 | Out-String)
    $rc = $LASTEXITCODE
    Assert ($saida -match 'preflight-and-run\.ps1') ($nome + ' -DryRun monta a Action passando pelo guarda')
    Assert ($saida -match "-GuardTarget .+ -GuardName '.+' -GuardLogPattern ") ($nome + ' -DryRun monta os 3 tokens na Action')
    Assert (-not ($saida -match 'FALHA ')) ($nome + ' -DryRun nao reprova nenhum token de guarda')
    if ($rc -eq 0) {
        Assert ($saida -match 'DRYRUN OK') ($nome + ' -DryRun sai 0 com DRYRUN OK')
    } else {
        $soDiferencaDeMaquina = ($saida -match 'task viva: .+ DIFERENTE do esperado') -and ($saida -notmatch 'FALHA ')
        Assert $soDiferencaDeMaquina ($nome + ' -DryRun so reprovou por diferenca da task viva local (exit=' + $rc + ')')
        if ($soDiferencaDeMaquina) { $difereMaquina++ }
    }
}
$alvoFechamento = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\scripts\run_fechamento_claude.ps1'
$alvoWatchdog = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\scripts\briefing_watchdog.ps1'
if ((Test-Path -LiteralPath $alvoFechamento) -and (Test-Path -LiteralPath $alvoWatchdog)) {
    $saidaAll = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'register-all-routines-scheduler.ps1') -DryRun *>&1 | Out-String)
    $rcAll = $LASTEXITCODE
    Assert (([regex]::Matches($saidaAll, 'guarda   : preflight-and-run\.ps1')).Count -eq 5) 'register-all guarda as 5 tasks do repositorio'
    Assert (([regex]::Matches($saidaAll, 'guarda   : ISENTO')).Count -eq 2) 'register-all declara as 2 isentas (alvo em outro repositorio)'
    Assert (-not ($saidaAll -match 'FALHA ')) 'register-all DryRun nao reprova nenhum token de guarda'
    if ($rcAll -eq 0) {
        Assert ($saidaAll -match 'DRYRUN OK') 'register-all -DryRun sai 0 com DRYRUN OK'
    } else {
        $soDiferencaAll = ($saidaAll -match 'task viva: .+ DIFERENTE do esperado') -and ($saidaAll -notmatch 'FALHA ')
        Assert $soDiferencaAll ('register-all -DryRun so reprovou por diferenca da task viva local (exit=' + $rcAll + ')')
        if ($soDiferencaAll) { $difereMaquina++ }
    }
} else {
    Write-Host '  PULADO register-all DryRun: alvos de outro repositorio ausentes nesta maquina (nao e falha)'
}
if ($difereMaquina -gt 0) {
    Write-Host ('  NOTA: ' + $difereMaquina + ' registrador(es) acusaram a task viva local apontando para outro caminho; a estrutura da Action foi aprovada em todos.')
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
