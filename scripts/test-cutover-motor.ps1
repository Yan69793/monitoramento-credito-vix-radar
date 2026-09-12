# test-cutover-motor.ps1 - prova de duas pontas do cutover-motor.ps1 SEM tocar o Task Scheduler real.
# Por padrao roda SO contra estado simulado em diretorio temporario (nenhum Get/Set/Export/Register-
# ScheduledTask, decisao do operador em 02/09): modelo JSON espelhando as 5 tasks reais medidas em
# 02/09/2026, antes -> Ativar -> Reverter com restauracao identica (inclusive os dois retries),
# idempotencia, Reverter sem snapshot, WhatIf simulado sem escrita, motor.json pre-existente
# restaurado byte a byte, e a guarda estrutural do modo sim provada pelos dois lados.
# -IncluirWhatIfReal (desligado por padrao) acrescenta o -WhatIf contra o scheduler real, que so le.
# PowerShell 5.1, ASCII puro. Exit 0 = todos os asserts OK.

param([switch]$IncluirWhatIfReal)
$ErrorActionPreference = 'Continue'
$Root   = Split-Path $PSScriptRoot -Parent
$Cut    = Join-Path $PSScriptRoot 'cutover-motor.ps1'
$MonDir = Join-Path $Root 'logs\monitor-tasks'
$Tasks  = @('VIXRadar-Matinal', 'VIXRadar-Noturno', 'VIXRadar-Verificacao-Async', 'Szuchmacher-RetryVixMatinal', 'Szuchmacher-RetryVixNoturno')
$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }
function Canon($o) { return ($o | ConvertTo-Json -Depth 10 -Compress) }
# Invoke-Cut executa a simulacao no processo do teste. O switch -NoExit preserva a CLI normal do
# script e devolve um marcador de exit somente para esta prova; nao ha filho, pipe ou scheduler real.
function Invoke-Cut([string[]]$Argumentos) {
    try {
        $splat = @{}
        for ($i = 0; $i -lt $Argumentos.Count; $i++) {
            $nome = [string]$Argumentos[$i]
            if (-not $nome.StartsWith('-')) { throw ('argumento sem nome: ' + $nome) }
            $chave = $nome.TrimStart('-')
            if (($i + 1) -lt $Argumentos.Count -and -not ([string]$Argumentos[$i + 1]).StartsWith('-')) {
                $i++
                $splat[$chave] = $Argumentos[$i]
            } else {
                $splat[$chave] = $true
            }
        }
        $splat['NoExit'] = $true
        $linhas = @(& $Cut @splat *>&1)
    } catch {
        return @{ exit = -1; out = ('ERRO Invoke-Cut: ' + $_.Exception.Message) }
    }
    $texto = ($linhas | Out-String -Width 400)
    $marcadores = @([regex]::Matches($texto, '__CUTOVER_EXIT=(\d+)'))
    if ($marcadores.Count -ne 1) {
        return @{ exit = -1; out = $texto }
    }
    return @{ exit = [int]$marcadores[0].Groups[1].Value; out = $texto }
}
function New-TaskModel($nome, $enabled, $trigs, $etl, $rc, $ri, $action) {
    return [ordered]@{ Nome = $nome; Enabled = $enabled; Triggers = $trigs; ExecutionTimeLimit = $etl; StartWhenAvailable = $true
        MultipleInstances = 'IgnoreNew'; RestartCount = $rc; RestartInterval = $ri; Principal = 'User/Interactive/Limited'; Actions = @($action) }
}
$base = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "E:\Diretorio\Claude\Monitoramento de Credito\scripts\'
$fixture = [ordered]@{ tasks = [ordered]@{
    'VIXRadar-Matinal'            = New-TaskModel 'VIXRadar-Matinal' $false @([ordered]@{ Tipo = 'Weekly'; Hora = '10:00'; DaysOfWeek = 62; Enabled = $true }) 'PT4H' 1 'PT15M' ($base + 'run_vixradar_matinal_claude.ps1"')
    'VIXRadar-Noturno'            = New-TaskModel 'VIXRadar-Noturno' $false @([ordered]@{ Tipo = 'Daily'; Hora = '18:00'; DaysOfWeek = $null; Enabled = $true }) 'PT4H' 1 'PT15M' ($base + 'run_vixradar_noturno_claude.ps1"')
    'VIXRadar-Verificacao-Async'  = New-TaskModel 'VIXRadar-Verificacao-Async' $false @([ordered]@{ Tipo = 'Daily'; Hora = '10:20'; DaysOfWeek = $null; Enabled = $true }, [ordered]@{ Tipo = 'Daily'; Hora = '18:20'; DaysOfWeek = $null; Enabled = $true }) 'PT30M' 0 '' ($base + 'run_vixradar_verificacao_async.ps1"')
    'Szuchmacher-RetryVixMatinal' = New-TaskModel 'Szuchmacher-RetryVixMatinal' $true @([ordered]@{ Tipo = 'Daily'; Hora = '13:30'; DaysOfWeek = $null; Enabled = $true }) 'PT4H' 0 '' ($base + 'retry-vixradar.ps1" -RoutineId vixradar-matinal')
    'Szuchmacher-RetryVixNoturno' = New-TaskModel 'Szuchmacher-RetryVixNoturno' $true @([ordered]@{ Tipo = 'Weekly'; Hora = '21:30'; DaysOfWeek = 62; Enabled = $true }) 'PT4H' 0 '' ($base + 'retry-vixradar.ps1" -RoutineId vixradar-noturno')
} }

$tmp = Join-Path $env:TEMP ('vixradar-cutover-test-' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$state = Join-Path $tmp 'estado.json'
$fixture | ConvertTo-Json -Depth 10 | Set-Content $state -Encoding UTF8
$antesTasks = Canon ((Get-Content $state -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)
Write-Host ('test-cutover-motor.ps1  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  tmp=' + $tmp)

Write-Host '=== A1 - Ativar simulado ==='
$r = Invoke-Cut @('-Acao', 'Ativar', '-SimStateFile', $state, '-SemPreCondicoes')
Assert ($r.exit -eq 0) ('Ativar sim exit=' + $r.exit)
$s = Get-Content $state -Raw -Encoding UTF8 | ConvertFrom-Json
$m = $s.tasks.'VIXRadar-Matinal'
Assert ($m.Enabled -eq $true -and @($m.Triggers).Count -eq 1 -and $m.Triggers[0].Tipo -eq 'Daily' -and $m.Triggers[0].Hora -eq '10:06' -and $m.ExecutionTimeLimit -eq 'PT4H') 'Matinal: Enabled, Daily 10:06, PT4H'
$n = $s.tasks.'VIXRadar-Noturno'
Assert ($n.Enabled -eq $true -and @($n.Triggers).Count -eq 1 -and $n.Triggers[0].Tipo -eq 'Weekly' -and $n.Triggers[0].Hora -eq '18:05' -and [int]$n.Triggers[0].DaysOfWeek -eq 62) 'Noturno: Enabled, Weekly seg-sex 18:05'
$v = $s.tasks.'VIXRadar-Verificacao-Async'
Assert ($v.Enabled -eq $true -and @($v.Triggers).Count -eq 2 -and $v.Triggers[0].Hora -eq '11:03' -and $v.Triggers[1].Hora -eq '19:15' -and $v.ExecutionTimeLimit -eq 'PT45M') 'Verificacao: Enabled, 11:03 e 19:15, PT45M'
foreach ($rt in @('Szuchmacher-RetryVixMatinal', 'Szuchmacher-RetryVixNoturno')) {
    $x = $s.tasks.$rt
    $orig = $fixture.tasks[$rt]
    Assert ($x.Enabled -eq $false) ($rt + ': Enabled=false')
    Assert ((Canon $x.Triggers) -eq (Canon $orig.Triggers) -and (Canon $x.Actions) -eq (Canon $orig.Actions) -and $x.ExecutionTimeLimit -eq $orig.ExecutionTimeLimit) ($rt + ': triggers, action e limite intactos')
}
$motorSim = Join-Path $tmp 'motor.json'
Assert ((Test-Path $motorSim) -and ((Get-Content $motorSim -Raw | ConvertFrom-Json).motor -eq 'task-scheduler')) 'motor.json simulado = task-scheduler'
Assert (@(Get-ChildItem $tmp -Filter 'cutover-snapshot_*.json').Count -eq 1) 'snapshot gravado (1)'
Assert ($r.out -match 'PASSO MANUAL \(MCP scheduled-tasks\): update_scheduled_task enabled:false') 'checklist do CCD impresso (enabled:false)'
$aposA1 = Canon ((Get-Content $state -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)

# SNAP-ORIGEM1 (12/09/2026): o Reverter SEM -Snapshot pega o snapshot MAIS NOVO. Como este teste
# roda Ativar duas vezes (A1 e A2, para provar idempotencia), o snapshot de A2 ja foi capturado
# com o estado ATIVADO por A1, entao reverter contra ele devolve o estado pos-Ativar e nao o
# original - era exatamente a causa dos dois asserts vermelhos aqui (medido: DEPOIS == pos-Ativar).
# O snapshot de A1 e o unico que representa o "antes" de verdade. Guardar o nome dele e passar
# explicito no A3 e o que faz o teste afirmar o que diz afirmar.
$snapOriginal = @(Get-ChildItem $tmp -Filter 'cutover-snapshot_*.json' -File | Sort-Object Name | Select-Object -First 1).FullName
Assert (-not [string]::IsNullOrEmpty($snapOriginal)) 'snapshot de origem (A1) localizado para o Reverter do A3'

# HAZARD OPERACIONAL (registrado, nao corrigido aqui): o mesmo efeito morde operador real. Quem
# roda `Ativar` duas vezes e depois `Reverter` sem -Snapshot volta para o estado da 2a ativacao,
# nao para o pre-cutover. O snapshot original continua no disco (o mais ANTIGO); usar
# `-Snapshot <caminho>` para desfazer o cutover de verdade. O log imprime qual snapshot foi usado.

Write-Host '=== A2 - Ativar de novo (idempotente) ==='
Start-Sleep -Seconds 1
$r = Invoke-Cut @('-Acao', 'Ativar', '-SimStateFile', $state, '-SemPreCondicoes')
Assert ($r.exit -eq 0) ('Ativar sim 2x exit=' + $r.exit)
$aposA2 = Canon ((Get-Content $state -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)
Assert ($aposA2 -eq $aposA1) 'estado identico apos o segundo Ativar'
Assert (@(Get-ChildItem $tmp -Filter 'cutover-snapshot_*.json').Count -eq 2) 'segundo snapshot gravado (2)'

Write-Host '=== A3 - Reverter simulado ==='
$r = Invoke-Cut @('-Acao', 'Reverter', '-SimStateFile', $state, '-SemPreCondicoes', '-Snapshot', $snapOriginal)
Assert ($r.exit -eq 0) ('Reverter sim exit=' + $r.exit)
$depoisTasks = Canon ((Get-Content $state -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)
Assert ($depoisTasks -eq $antesTasks) 'as 5 tasks voltaram byte a byte ao estado anterior (inclusive os retries)'
Assert (-not (Test-Path $motorSim)) 'motor.json simulado removido (nao existia antes)'
Assert (([regex]::Matches($r.out, 'identica=True')).Count -eq 5) 'RESTAURACAO identica=True nas 5 tasks'
Assert ($r.out -match 'update_scheduled_task enabled:true') 'checklist do CCD impresso (enabled:true)'

Write-Host '=== A4 - Reverter sem snapshot ==='
$tmp2 = Join-Path $tmp 'sem-snapshot'
New-Item -ItemType Directory -Force -Path $tmp2 | Out-Null
$state2 = Join-Path $tmp2 'estado.json'
$fixture | ConvertTo-Json -Depth 10 | Set-Content $state2 -Encoding UTF8
$r = Invoke-Cut @('-Acao', 'Reverter', '-SimStateFile', $state2, '-SemPreCondicoes')
Assert ($r.exit -eq 3) ('Reverter sem snapshot exit=' + $r.exit + ' (esperado 3)')
Assert ((Canon ((Get-Content $state2 -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)) -eq $antesTasks) 'estado intocado sem snapshot'

Write-Host '=== A5 - WhatIf simulado: nada muda, nada gravado ==='
$tmp3 = Join-Path $tmp 'whatif'
New-Item -ItemType Directory -Force -Path $tmp3 | Out-Null
$state3 = Join-Path $tmp3 'estado.json'
$fixture | ConvertTo-Json -Depth 10 | Set-Content $state3 -Encoding UTF8
$r = Invoke-Cut @('-Acao', 'Ativar', '-SimStateFile', $state3, '-SemPreCondicoes', '-WhatIf')
Assert ($r.exit -eq 0) ('Ativar -WhatIf sim exit=' + $r.exit)
Assert ($r.out -match 'WHATIF VIXRadar-Noturno ->' -and $r.out -match 'WHATIF: gravaria snapshot') 'WhatIf imprimiu o plano'
Assert ((Canon ((Get-Content $state3 -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)) -eq $antesTasks) 'estado simulado intocado pelo WhatIf'
Assert (@(Get-ChildItem $tmp3 -File).Count -eq 1) ('so o estado.json no diretorio (sem snapshot, motor.json ou log): ' + @(Get-ChildItem $tmp3 -File).Count + ' arquivo(s)')
$r = Invoke-Cut @('-Acao', 'Reverter', '-SimStateFile', $state3, '-SemPreCondicoes', '-WhatIf')
Assert ($r.exit -eq 3 -and @(Get-ChildItem $tmp3 -File).Count -eq 1) ('Reverter -WhatIf sem snapshot exit=' + $r.exit + ' e nada gravado')

Write-Host '=== A6 - motor.json pre-existente volta byte a byte ==='
$tmp4 = Join-Path $tmp 'motor-existente'
New-Item -ItemType Directory -Force -Path $tmp4 | Out-Null
$state4 = Join-Path $tmp4 'estado.json'
$fixture | ConvertTo-Json -Depth 10 | Set-Content $state4 -Encoding UTF8
$motor4 = Join-Path $tmp4 'motor.json'
$conteudoOriginal = '{"motor":"claude-desktop","nota":"gravado antes do cutover"}'
[System.IO.File]::WriteAllText($motor4, $conteudoOriginal, (New-Object System.Text.UTF8Encoding($false)))
$r = Invoke-Cut @('-Acao', 'Ativar', '-SimStateFile', $state4, '-SemPreCondicoes')
Assert ($r.exit -eq 0 -and ((Get-Content $motor4 -Raw | ConvertFrom-Json).motor -eq 'task-scheduler')) 'Ativar trocou motor.json para task-scheduler'
$r = Invoke-Cut @('-Acao', 'Reverter', '-SimStateFile', $state4, '-SemPreCondicoes')
$conteudoDepois = [System.IO.File]::ReadAllText($motor4)
Assert ($r.exit -eq 0 -and $conteudoDepois -eq $conteudoOriginal) ('Reverter devolveu o motor.json original byte a byte (len ' + $conteudoDepois.Length + ')')
Assert ((Canon ((Get-Content $state4 -Raw -Encoding UTF8 | ConvertFrom-Json).tasks)) -eq $antesTasks) 'tasks identicas tambem neste ciclo'

Write-Host '=== A7 - guarda estrutural do modo sim, duas pontas ==='
$saidas = @($r.out)
$r = Invoke-Cut @('-Acao', 'Estado', '-SimStateFile', $state4)
Assert ($r.exit -eq 0 -and -not ($r.out -match 'PROIBIDO em modo sim')) 'ponta boa: Estado sim roda sem tocar cmdlet nenhum do scheduler'
$r = Invoke-Cut @('-Acao', 'Estado', '-SimStateFile', $state4, '-ProvaGuardaSim')
Assert ($r.exit -eq 1 -and $r.out -match 'PROIBIDO em modo sim: Get-ScheduledTask') ('ponta ruim: chamada deliberada a Get-ScheduledTask em modo sim morreu na guarda (exit=' + $r.exit + ')')
$r = Invoke-Cut @('-Acao', 'Estado', '-ProvaGuardaSim')
Assert ($r.exit -eq 1 -and $r.out -match 'so e aceito com -SimStateFile' -and -not ($r.out -match 'ESTADO VIXRadar')) 'fora do sim a prova e recusada antes de consultar qualquer task'

if ($IncluirWhatIfReal) {
Write-Host '=== B - WhatIf contra o Task Scheduler REAL (so leitura; desligado por padrao) ==='
function Get-RealView([string]$nome) {
    $t = Get-ScheduledTask -TaskName $nome -ErrorAction Stop
    $trs = @()
    foreach ($tr in @($t.Triggers)) {
        $dow = ''
        if ($tr.PSObject.Properties['DaysOfWeek']) { $dow = '' + $tr.DaysOfWeek }
        $trs += ([string]$tr.CimClass.CimClassName + '|' + [string]$tr.StartBoundary + '|' + [string]$tr.Enabled + '|' + $dow + '|' + [string]$tr.Repetition.Interval)
    }
    return ([string]$t.State + '|' + [string]$t.Settings.Enabled + '|' + [string]$t.Settings.ExecutionTimeLimit + '|' + [string]$t.Settings.StartWhenAvailable + '|' + [string]$t.Settings.MultipleInstances + '|' + [string]$t.Settings.RestartCount + '|' + [string]$t.Settings.RestartInterval + '|' + [string]$t.Settings.WakeToRun + '|' + [string]$t.Principal.UserId + '|' + [string]$t.Principal.LogonType + '|' + (($t.Actions | ForEach-Object { [string]$_.Execute + ' ' + [string]$_.Arguments }) -join ';') + '|' + ($trs -join ';'))
}
$antesReal = @{}
foreach ($n in $Tasks) { $antesReal[$n] = Get-RealView $n }
$filesAntes = ((Get-ChildItem $MonDir -File | ForEach-Object { $_.Name + ':' + $_.Length }) | Sort-Object) -join ';'
$motorReal = Join-Path $MonDir 'motor.json'
$motorAntes = Test-Path $motorReal
$r1 = Invoke-Cut @('-Acao', 'Ativar', '-WhatIf')
Assert ($r1.exit -eq 0) ('Ativar -WhatIf real exit=' + $r1.exit)
Assert ($r1.out -match 'WHATIF VIXRadar-Noturno ->' -and $r1.out -match 'WHATIF: gravaria') 'Ativar -WhatIf imprimiu o plano sem aplicar'
Assert ($r1.out -match 'PRECOND') 'Ativar -WhatIf avaliou as pre-condicoes'
$r2 = Invoke-Cut @('-Acao', 'Reverter', '-WhatIf')
Assert ($r2.exit -eq 0 -or $r2.exit -eq 3) ('Reverter -WhatIf real exit=' + $r2.exit + ' (0 ou 3, sem alteracao)')
$r3 = Invoke-Cut @('-Acao', 'Estado', '-WhatIf')
Assert ($r3.exit -eq 0 -and ([regex]::Matches($r3.out, 'ESTADO ')).Count -ge 6) 'Estado -WhatIf listou as 5 tasks e o motor.json'
$difs = 0
foreach ($n in $Tasks) { if ((Get-RealView $n) -ne $antesReal[$n]) { $difs++; Write-Host ('  DIFERENCA em ' + $n) } }
Assert ($difs -eq 0) 'as 5 tasks reais identicas antes e depois dos WhatIf'
$filesDepois = ((Get-ChildItem $MonDir -File | ForEach-Object { $_.Name + ':' + $_.Length }) | Sort-Object) -join ';'
Assert ($filesDepois -eq $filesAntes) 'nenhum arquivo criado ou alterado em logs\monitor-tasks pelos WhatIf'
Assert ((Test-Path $motorReal) -eq $motorAntes) ('motor.json real inalterado (existe=' + $motorAntes + ')')
} else {
    Write-Host '=== B - WhatIf real NAO executado (padrao; ligar com -IncluirWhatIfReal) ==='
}

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
