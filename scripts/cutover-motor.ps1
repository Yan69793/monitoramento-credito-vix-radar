# cutover-motor.ps1 - liga ou desliga o motor Task Scheduler das tres rotinas do VIX Radar
# (MOTOR1), de forma atomica e reversivel. PowerShell 5.1, ASCII puro, exit code real.
#
#   -Acao Ativar      snapshot exato das 5 tasks -> horarios/settings/enabled do motor novo -> motor.json
#   -Acao Reverter    restaura as 5 tasks do ultimo snapshot (definicao exportada) e o motor.json como estava
#   -Acao Estado      so imprime o estado atual das 5 tasks e do motor.json
#   -WhatIf           imprime o que faria e nao escreve NADA (nem snapshot, nem log, nem motor.json)
#   -SimStateFile     modelo JSON das tasks: NADA toca o Task Scheduler real (testes)
#   -Snapshot         snapshot especifico para Reverter (default: o mais novo do diretorio de trabalho)
#   -SemPreCondicoes  pula as pre-condicoes (so simulacao/teste)
#
# As 5 tasks: VIXRadar-Matinal, VIXRadar-Noturno, VIXRadar-Verificacao-Async (motor novo, Enabled)
# e Szuchmacher-RetryVixMatinal/Noturno (desabilitados no Ativar, definicao intacta). O snapshot
# guarda a definicao completa de cada uma (Export-ScheduledTask no real, o modelo no sim), entao
# Reverter devolve exatamente o que havia, inclusive os retries.
# O lado Claude Desktop (4 tasks do CCD store) nao e feito aqui: depende do MCP scheduled-tasks e
# sai como checklist no fim. Exit: 0 ok | 1 erro | 2 pre-condicao reprovada | 3 snapshot ausente

param(
    [ValidateSet('Ativar', 'Reverter', 'Estado')][string]$Acao = 'Estado',
    [switch]$WhatIf,
    [string]$SimStateFile,
    [string]$Snapshot,
    [switch]$SemPreCondicoes,
    [switch]$ProvaGuardaSim,
    [switch]$NoExit
)

$ErrorActionPreference = 'Continue'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$MonDir      = Join-Path $ProjectRoot 'logs\monitor-tasks'
$RotinasDir  = Join-Path $ProjectRoot 'logs\routines'
$Ts          = Get-Date -Format 'yyyyMMdd_HHmmss'
$Sim         = [bool]$SimStateFile
$WorkDir     = $MonDir
if ($Sim) {
    if (-not (Test-Path $SimStateFile)) { Write-Host ('ERRO: SimStateFile ausente: ' + $SimStateFile); exit 1 }
    $WorkDir = Split-Path (Resolve-Path $SimStateFile).Path -Parent
}
$MotorFile = Join-Path $WorkDir 'motor.json'
$LogFile   = Join-Path $WorkDir ('cutover-motor_' + (Get-Date -Format 'yyyyMMdd') + '.log')

# Guarda estrutural do modo sim (02/09): os cmdlets do Task Scheduler sao redefinidos como
# funcoes que estouram. Um caminho errado dentro deste script nao consegue tocar o scheduler
# real por acidente, e o teste prova a guarda pelos dois lados (-ProvaGuardaSim chama
# Get-ScheduledTask de proposito e tem que morrer aqui).
if ($Sim) {
    foreach ($__cmd in @('Get-ScheduledTask', 'Set-ScheduledTask', 'Export-ScheduledTask', 'Register-ScheduledTask',
                         'Enable-ScheduledTask', 'Disable-ScheduledTask', 'Unregister-ScheduledTask', 'Get-ScheduledTaskInfo')) {
        $null = New-Item -Path ('Function:\' + $__cmd) -Value ([scriptblock]::Create("throw 'PROIBIDO em modo sim: $__cmd'")) -Force
    }
}

$Tasks = @('VIXRadar-Matinal', 'VIXRadar-Noturno', 'VIXRadar-Verificacao-Async', 'Szuchmacher-RetryVixMatinal', 'Szuchmacher-RetryVixNoturno')
# DaysOfWeek 62 = seg(2)+ter(4)+qua(8)+qui(16)+sex(32). Retries: Triggers nulo = so o Enabled muda.
$Desejado = @{
    'VIXRadar-Matinal'            = @{ Enabled = $true;  Triggers = @(@{ Tipo = 'Daily';  Hora = '10:06'; DaysOfWeek = $null }); ExecutionTimeLimit = 'PT4H' }
    'VIXRadar-Noturno'            = @{ Enabled = $true;  Triggers = @(@{ Tipo = 'Weekly'; Hora = '18:05'; DaysOfWeek = 62 });   ExecutionTimeLimit = 'PT4H' }
    'VIXRadar-Verificacao-Async'  = @{ Enabled = $true;  Triggers = @(@{ Tipo = 'Daily';  Hora = '11:03'; DaysOfWeek = $null }, @{ Tipo = 'Daily'; Hora = '19:15'; DaysOfWeek = $null }); ExecutionTimeLimit = 'PT45M' }
    'Szuchmacher-RetryVixMatinal' = @{ Enabled = $false; Triggers = $null; ExecutionTimeLimit = $null }
    'Szuchmacher-RetryVixNoturno' = @{ Enabled = $false; Triggers = $null; ExecutionTimeLimit = $null }
}
$CcdTasks = @('vixradar-matinal', 'vixradar-noturno', 'vixradar-verificacao-async-11h', 'vixradar-verificacao-async-1845')
$MotorFiles = @('scripts/run_vixradar_varredura.ps1', 'scripts/run_vixradar_noturno_claude.ps1', 'scripts/run_vixradar_matinal_claude.ps1',
    'scripts/run_vixradar_verificacao_async.ps1', 'scripts/lib/vixradar-claude-auth.ps1', 'scripts/lib/vixradar-custo.ps1',
    'scripts/lib/vixradar-watchdog.ps1', 'scripts/lib/vixradar-ambient-check.ps1', 'scripts/monitor-tasks.ps1', 'scripts/cutover-motor.ps1')

function Write-Log([string]$m) {
    $l = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $m
    try { Write-Host $l } catch { }
    if (-not $WhatIf) { try { Add-Content -Path $LogFile -Value $l -Encoding UTF8 } catch { } }
}
function ConvertTo-Canon($obj) { return ($obj | ConvertTo-Json -Depth 10 -Compress) }
function Get-DiasSemana([int]$mask) {
    $nomes = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
    $bits = @(1, 2, 4, 8, 16, 32, 64)
    $out = @()
    for ($i = 0; $i -lt 7; $i++) { if (($mask -band $bits[$i]) -ne 0) { $out += $nomes[$i] } }
    return $out
}
# Vista normalizada, a mesma para real e sim: e o que Reverter compara para provar restauracao identica.
function Get-View($m) {
    $trs = @()
    foreach ($tr in @($m.Triggers)) {
        if ($null -eq $tr) { continue }
        $dow = $null
        if ($null -ne $tr.DaysOfWeek -and ('' + $tr.DaysOfWeek) -ne '') { $dow = [int]$tr.DaysOfWeek }
        $trs += [ordered]@{ Tipo = [string]$tr.Tipo; Hora = [string]$tr.Hora; DaysOfWeek = $dow; Enabled = [bool]$tr.Enabled }
    }
    return [ordered]@{
        Nome = [string]$m.Nome; Enabled = [bool]$m.Enabled; Triggers = $trs
        ExecutionTimeLimit = [string]$m.ExecutionTimeLimit; StartWhenAvailable = [bool]$m.StartWhenAvailable
        MultipleInstances = [string]$m.MultipleInstances; RestartCount = [int]$m.RestartCount; RestartInterval = [string]$m.RestartInterval
        Principal = [string]$m.Principal; Actions = @(@($m.Actions) | ForEach-Object { [string]$_ })
    }
}

# ---- provedor REAL (Task Scheduler) ----
function Get-ModelReal([string]$n) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction Stop
    $trs = @()
    foreach ($tr in @($t.Triggers)) {
        $tipo = [string]$tr.CimClass.CimClassName
        $tipo = $tipo -replace '^MSFT_Task', '' -replace 'Trigger$', ''
        $hora = ''
        if ($tr.StartBoundary) { $hora = ([datetime]$tr.StartBoundary).ToString('HH:mm') }
        $dow = $null
        if ($tr.PSObject.Properties['DaysOfWeek']) { $dow = [int]$tr.DaysOfWeek }
        $trs += [ordered]@{ Tipo = $tipo; Hora = $hora; DaysOfWeek = $dow; Enabled = [bool]$tr.Enabled }
    }
    return [ordered]@{
        Nome = $n; Enabled = [bool]$t.Settings.Enabled; Triggers = $trs
        ExecutionTimeLimit = [string]$t.Settings.ExecutionTimeLimit; StartWhenAvailable = [bool]$t.Settings.StartWhenAvailable
        MultipleInstances = [string]$t.Settings.MultipleInstances; RestartCount = [int]$t.Settings.RestartCount; RestartInterval = [string]$t.Settings.RestartInterval
        Principal = ([string]$t.Principal.UserId + '/' + [string]$t.Principal.LogonType + '/' + [string]$t.Principal.RunLevel)
        Actions = @(@($t.Actions) | ForEach-Object { ([string]$_.Execute + ' ' + [string]$_.Arguments).Trim() })
    }
}
function Export-RawReal([string]$n) { return [string](Export-ScheduledTask -TaskName $n -ErrorAction Stop) }
function Restore-RawReal([string]$n, [string]$xml) { Register-ScheduledTask -TaskName $n -Xml $xml -Force -ErrorAction Stop | Out-Null }
function Set-DesejadoReal([string]$n, $d) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction Stop
    if ($null -ne $d.Triggers) {
        $novos = @()
        foreach ($tr in @($d.Triggers)) {
            $at = [datetime]::ParseExact($tr.Hora, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($tr.Tipo -eq 'Weekly') { $novos += New-ScheduledTaskTrigger -Weekly -DaysOfWeek (Get-DiasSemana $tr.DaysOfWeek) -At $at }
            else { $novos += New-ScheduledTaskTrigger -Daily -At $at }
        }
        $t.Triggers = $novos
        $t.Settings.ExecutionTimeLimit = $d.ExecutionTimeLimit
        $t.Settings.StartWhenAvailable = $true
        Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
    }
    if ($d.Enabled) { Enable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
}

# ---- provedor SIM (modelo JSON, nunca toca o scheduler) ----
$script:SimState = $null
function Read-Sim { $script:SimState = Get-Content $SimStateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save-Sim { $script:SimState | ConvertTo-Json -Depth 10 | Set-Content $SimStateFile -Encoding UTF8 }
function Get-ModelSim([string]$n) {
    $m = $script:SimState.tasks.$n
    if ($null -eq $m) { throw ('task simulada ausente: ' + $n) }
    return ($m | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
}
function Export-RawSim([string]$n) { return (Get-ModelSim $n | ConvertTo-Json -Depth 10 -Compress) }
function Restore-RawSim([string]$n, [string]$raw) { $script:SimState.tasks.$n = ($raw | ConvertFrom-Json) }
function Set-DesejadoSim([string]$n, $d) {
    $m = $script:SimState.tasks.$n
    if ($null -eq $m) { throw ('task simulada ausente: ' + $n) }
    if ($null -ne $d.Triggers) {
        $trs = @()
        foreach ($tr in @($d.Triggers)) { $trs += [pscustomobject]@{ Tipo = $tr.Tipo; Hora = $tr.Hora; DaysOfWeek = $tr.DaysOfWeek; Enabled = $true } }
        $m.Triggers = $trs
        $m.ExecutionTimeLimit = $d.ExecutionTimeLimit
        $m.StartWhenAvailable = $true
    }
    $m.Enabled = [bool]$d.Enabled
}

function Get-Model([string]$n) { if ($Sim) { return Get-ModelSim $n } else { return Get-ModelReal $n } }
function Export-Raw([string]$n) { if ($Sim) { return Export-RawSim $n } else { return Export-RawReal $n } }
function Restore-Raw([string]$n, [string]$raw) { if ($Sim) { Restore-RawSim $n $raw } else { Restore-RawReal $n $raw } }
function Set-Desejado([string]$n, $d) { if ($Sim) { Set-DesejadoSim $n $d } else { Set-DesejadoReal $n $d } }

# ---- pre-condicoes (so real) ----
function Test-PreCondicoes {
    $falhas = @()
    try {
        $h = Invoke-RestMethod -Uri 'https://radar-credito-api.prospects-intel.workers.dev' -TimeoutSec 30
        $v = [string]$h.versao
        $vOk = $false
        if ($v -match '^v(\d+)\.(\d+)\.(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]; $c = [int]$Matches[3]
            $vOk = ($a -gt 4) -or ($a -eq 4 -and $b -gt 9) -or ($a -eq 4 -and $b -eq 9 -and $c -ge 235)
        }
        if ($h.ok -eq $true -and $vOk) { Write-Log ('PRECOND OK: health ok=true versao=' + $v) } else { $falhas += ('health ok=' + $h.ok + ' versao=' + $v + ' (exige >= v4.9.235)') }
    } catch { $falhas += ('health inacessivel: ' + $_.Exception.Message) }
    # CLAUDE-FREE-MIGRATION (2026-09-04): o cutover passou a depender do provider de LLM, nao
    # da credencial Claude. O operador decide o provider (G1) ANTES de ativar o motor: qualquer
    # valor setado em escopo User (none, claude-manual ou provider de Fase B) significa decisao
    # tomada. Com o valor setado, as rotinas LLM que o Task Scheduler disparar rodam o gate e
    # saem exit 86 com BLOQUEADO_SEM_PROVIDER visivel no log. Sem o valor, o registro User de
    # VIXRADAR_LLM_PROVIDER fica vazio e o script aborta antes de tocar em qualquer task.
    $provUser = ([string][Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'User')).Trim()
    if ($provUser.Length -gt 0) { Write-Log ('PRECOND OK: VIXRADAR_LLM_PROVIDER User=' + $provUser) } else { $falhas += 'VIXRADAR_LLM_PROVIDER ausente do escopo User (roda: [Environment]::SetEnvironmentVariable(''VIXRADAR_LLM_PROVIDER'',''none'',''User''))' }
    $locks = @(Get-ChildItem $RotinasDir -Filter ('vixradar-*_' + (Get-Date -Format 'yyyyMMdd') + '.lock') -File -ErrorAction SilentlyContinue)
    if ($locks.Count -eq 0) { Write-Log 'PRECOND OK: nenhum lock do dia' } else { $falhas += ('lock vivo: ' + (($locks | ForEach-Object { $_.Name }) -join ', ')) }
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='claude.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'run_vixradar|claude -p|sentinela' })
    if ($procs.Count -eq 0) { Write-Log 'PRECOND OK: nenhum processo de rotina' } else { $falhas += ('processo de rotina vivo: ' + (($procs | ForEach-Object { $_.ProcessId }) -join ',')) }
    $sujos = @(git -C $ProjectRoot status --short -- $MotorFiles 2>$null)
    if ($sujos.Count -eq 0) { Write-Log 'PRECOND OK: git limpo nos arquivos do motor' } else { $falhas += ('git sujo no motor: ' + ($sujos -join ' | ')) }
    foreach ($n in $Tasks) { if (-not (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue)) { $falhas += ('task ausente: ' + $n) } }
    return $falhas
}

# ---- acoes ----
function Show-Estado {
    foreach ($n in $Tasks) { Write-Log ('ESTADO ' + $n + ': ' + (ConvertTo-Canon (Get-View (Get-Model $n)))) }
    if (Test-Path $MotorFile) { Write-Log ('ESTADO motor.json: ' + ((Get-Content $MotorFile -Raw -Encoding UTF8) -replace '\s+', ' ')) }
    else { Write-Log 'ESTADO motor.json: ausente (motor claude-desktop por default)' }
}
function Invoke-Ativar {
    if (-not $Sim -and -not $SemPreCondicoes) {
        $f = @(Test-PreCondicoes)
        if ($f.Count -gt 0) {
            foreach ($x in $f) { Write-Log ('PRECOND FALHA: ' + $x) }
            if (-not $WhatIf) { Write-Log 'ABORT: pre-condicao reprovada, nada alterado'; return 2 }
            Write-Log 'WHATIF: Ativar seria abortado pelas pre-condicoes acima'
        }
    }
    $modoTxt = 'real'
    if ($Sim) { $modoTxt = 'sim' }
    $snap = [ordered]@{ ts = $Ts; modo = $modoTxt; motor_json_existia = (Test-Path $MotorFile); motor_json_conteudo = $null; tasks = [ordered]@{} }
    # SNAPJSON-ETS1 (04/09): o cast [string] e obrigatorio. Get-Content devolve a string embrulhada em
    # PSObject com PSPath/PSDrive/PSProvider, e o ConvertTo-Json -Depth 10 do snapshot caminha
    # PSDrive.Provider.ImplementingType... em crescimento exponencial: o segundo Ativar (motor.json
    # ja existente) ficou 100% CPU e 3,8 GB de RAM sem terminar, em 3 harnesses diferentes. No
    # primeiro Ativar o campo e $null, por isso nunca apareceu. Prova de duas pontas em
    # test-cutover-motor.ps1 (A2) e no diag da sessao de 04/09.
    if ($snap.motor_json_existia) { $snap.motor_json_conteudo = [string](Get-Content $MotorFile -Raw -Encoding UTF8) }
    foreach ($n in $Tasks) {
        $m = Get-Model $n
        $snap.tasks[$n] = [ordered]@{ view = (Get-View $m); raw = (Export-Raw $n) }
        Write-Log ('ANTES ' + $n + ': ' + (ConvertTo-Canon $snap.tasks[$n].view))
    }
    $snapFile = Join-Path $WorkDir ('cutover-snapshot_' + $Ts + '.json')
    if ($WhatIf) { Write-Log ('WHATIF: gravaria snapshot ' + $snapFile) }
    else { $snap | ConvertTo-Json -Depth 10 | Set-Content $snapFile -Encoding UTF8; Write-Log ('SNAPSHOT ' + $snapFile) }
    foreach ($n in $Tasks) {
        $d = $Desejado[$n]
        $txt = 'Enabled=' + $d.Enabled
        if ($null -ne $d.Triggers) { $txt += ' Triggers=' + (ConvertTo-Canon $d.Triggers) + ' ExecutionTimeLimit=' + $d.ExecutionTimeLimit + ' StartWhenAvailable=True' } else { $txt += ' (definicao intacta)' }
        if ($WhatIf) { Write-Log ('WHATIF ' + $n + ' -> ' + $txt) }
        else { Set-Desejado $n $d; Write-Log ('APLICADO ' + $n + ' -> ' + $txt) }
    }
    if ($Sim -and -not $WhatIf) { Save-Sim }
    $motor = [ordered]@{ motor = 'task-scheduler'; desde = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); snapshot = (Split-Path $snapFile -Leaf) }
    if ($WhatIf) { Write-Log ('WHATIF: gravaria ' + $MotorFile + ' ' + (ConvertTo-Canon $motor)) }
    else {
        $motor | ConvertTo-Json | Set-Content $MotorFile -Encoding UTF8
        Write-Log ('MOTOR ' + (ConvertTo-Canon $motor))
        foreach ($n in $Tasks) { Write-Log ('DEPOIS ' + $n + ': ' + (ConvertTo-Canon (Get-View (Get-Model $n)))) }
    }
    Write-Log ('PASSO MANUAL (MCP scheduled-tasks): update_scheduled_task enabled:false em ' + ($CcdTasks -join ', '))
    return 0
}
function Invoke-Reverter {
    $snapFile = $Snapshot
    if (-not $snapFile) {
        $c = @(Get-ChildItem $WorkDir -Filter 'cutover-snapshot_*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
        if ($c.Count -eq 1) { $snapFile = $c[0].FullName }
    }
    if (-not $snapFile -or -not (Test-Path $snapFile)) { Write-Log 'ABORT: snapshot ausente, nada a reverter'; return 3 }
    $snap = Get-Content $snapFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Log ('SNAPSHOT ' + $snapFile + ' modo=' + $snap.modo + ' ts=' + $snap.ts)
    if (([string]$snap.modo -eq 'sim') -ne $Sim) { Write-Log 'ABORT: snapshot de modo diferente (sim x real), nada alterado'; return 3 }
    foreach ($n in $Tasks) {
        $raw = [string]$snap.tasks.$n.raw
        if (-not $raw) { Write-Log ('ABORT: snapshot sem definicao de ' + $n); return 3 }
        if ($WhatIf) { Write-Log ('WHATIF ' + $n + ' <- restaurar definicao do snapshot') }
        else { Restore-Raw $n $raw; Write-Log ('RESTAURADO ' + $n) }
    }
    if ($Sim -and -not $WhatIf) { Save-Sim }
    if ($WhatIf) {
        if ($snap.motor_json_existia) { Write-Log 'WHATIF: motor.json voltaria ao conteudo anterior' } else { Write-Log 'WHATIF: motor.json seria removido (nao existia antes)' }
    } else {
        if ($snap.motor_json_existia) { Set-Content -Path $MotorFile -Value ([string]$snap.motor_json_conteudo) -Encoding UTF8 -NoNewline }
        else { Remove-Item $MotorFile -Force -ErrorAction SilentlyContinue }
        Write-Log ('MOTOR restaurado: existia_antes=' + $snap.motor_json_existia + ' existe_agora=' + (Test-Path $MotorFile))
    }
    $rc = 0
    if (-not $WhatIf) {
        foreach ($n in $Tasks) {
            $agora = ConvertTo-Canon (Get-View (Get-Model $n))
            $antes = ConvertTo-Canon (Get-View $snap.tasks.$n.view)
            $ig = ($agora -eq $antes)
            Write-Log ('RESTAURACAO ' + $n + ' identica=' + $ig)
            if (-not $ig) { $rc = 1; Write-Log ('  antes=' + $antes); Write-Log ('  agora=' + $agora) }
        }
    }
    Write-Log ('PASSO MANUAL (MCP scheduled-tasks): update_scheduled_task enabled:true em ' + ($CcdTasks -join ', '))
    return $rc
}

$rc = 1
try {
    if ($Sim) { Read-Sim }
    Write-Log ('INICIO cutover-motor acao=' + $Acao + ' whatif=' + [bool]$WhatIf + ' sim=' + $Sim + ' workdir=' + $WorkDir)
    if ($ProvaGuardaSim) {
        # So teste: em modo sim isto tem que estourar na guarda; fora do sim e recusado sem executar.
        if (-not $Sim) {
            Write-Log 'ERRO: -ProvaGuardaSim so e aceito com -SimStateFile'
            if ($NoExit) { Write-Output '__CUTOVER_EXIT=1'; return }
            exit 1
        }
        $null = Get-ScheduledTask -TaskName 'VIXRadar-Matinal'
        Write-Log 'ERRO: a guarda do modo sim NAO estourou'
        exit 1
    }
    switch ($Acao) {
        'Estado'   { Show-Estado; $rc = 0 }
        'Ativar'   { $rc = Invoke-Ativar }
        'Reverter' { $rc = Invoke-Reverter }
    }
    Write-Log ('FIM cutover-motor acao=' + $Acao + ' exit=' + $rc)
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message + ' | ' + $_.ScriptStackTrace)
    $rc = 1
}
if ($NoExit) {
    Write-Output ('__CUTOVER_EXIT=' + $rc)
    return
}
exit $rc
