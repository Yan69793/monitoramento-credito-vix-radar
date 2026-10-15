# cobertura-diaria-ativacao.ps1 - liga/desliga o controle diario (COBDIARIA1) SO depois de validado.
#
# IDEMEFETIVA1 (2026-10-15). O controle diario (VIXRADAR_COBERTURA_DIARIA=1) poe o obrigatorio do
# dia na frente da fila, reserva o cap da matinal contra noturna que atravessa a meia-noite e
# alerta o incidente de fechamento. A correcao do incidente de 14/10 (DEFERIDO travando a fila) NAO
# depende dele: ela vale sempre. Este script existe para que a ativacao do controle seja um passo
# separado, provado e reversivel, e nunca uma edicao manual de variavel.
#
# Acoes:
#   -Acao Status    le o valor atual (Process/User/Machine) e o ultimo recibo de validacao
#   -Acao Validar   roda as suites que cobrem o motor e o controle em powershell.exe 5.1 (o
#                   runtime do Agendador), o lint de encoding e o check-claude-free, e grava um
#                   recibo com o hash de cada arquivo validado. Nao muda nada.
#   -Acao Ativar    exige -Confirmar, recibo verde com menos de 24h, os MESMOS hashes do recibo (o
#                   codigo nao mudou depois da validacao) e nenhuma rotina do dia viva. Grava o
#                   valor anterior para rollback e so entao poe User=1. Sem -Confirmar, so mostra.
#   -Acao Reverter  restaura o valor anterior do ultimo registro de ativacao (ou de -Registro).
# Nunca executa rotina, nunca chama IA, nunca toca Worker, credencial, teto ou cap.
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue. Saida final: uma linha JSON.
# Exit: 0 ok | 1 recusado/reprovado | 2 erro interno.
param(
    [ValidateSet('Status', 'Validar', 'Ativar', 'Reverter')][string]$Acao = 'Status',
    [switch]$Confirmar,
    [string]$Registro = '',
    [int]$TimeoutSuiteSec = 600,
    # So para teste: escopo Process e caminhos isolados provam o ciclo sem tocar a variavel real.
    [ValidateSet('User', 'Process')][string]$Escopo = 'User',
    [string]$ReciboPath = '',
    [string]$BackupBase = ''
)

$ErrorActionPreference = 'Continue'
$ScriptsDir = $PSScriptRoot
$Root = Split-Path $ScriptsDir -Parent
$LogDir = Join-Path $Root 'logs\routines'
$Flag = 'VIXRADAR_COBERTURA_DIARIA'
if (-not $ReciboPath) { $ReciboPath = Join-Path $LogDir 'cobertura_diaria_validacao.json' }
if (-not $BackupBase) { $BackupBase = Join-Path (Split-Path $Root -Parent) 'BACKUPS\operacional\vix-radar' }
$Suites = @('test-idempotencia-entrega-efetiva.ps1', 'test-cobertura-diaria.ps1', 'test-cobertura-fallback-claude.ps1', 'test-cobertura-orcamento-14out.ps1',
    'test-cobertura-recuperacao.ps1', 'test-retry-janela.ps1', 'test-idempotencia-janela.ps1', 'test-triagem-ativa-14out.ps1', 'test-vixfix-20261006.ps1')
$Vigiados = @('run_vixradar_varredura.ps1', 'retry-vixradar.ps1', 'monitor-tasks.ps1', 'lib\vixradar-cobertura-diaria.ps1', 'lib\vixradar-cobertura.ps1',
    'lib\vixradar-watchdog.ps1', 'lib\vixradar-custo.ps1')

function Write-Saida($Obj, [int]$Codigo) {
    Write-Host ($Obj | ConvertTo-Json -Compress -Depth 6)
    exit $Codigo
}
function Get-ValorFlag {
    return [ordered]@{
        process = [Environment]::GetEnvironmentVariable($Flag, 'Process')
        user = [Environment]::GetEnvironmentVariable($Flag, 'User')
        machine = [Environment]::GetEnvironmentVariable($Flag, 'Machine')
    }
}
function Get-HashVigiados {
    $h = [ordered]@{}
    foreach ($f in $Vigiados) {
        $p = Join-Path $ScriptsDir $f
        if (Test-Path -LiteralPath $p) { $h[$f] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { $h[$f] = 'AUSENTE' }
    }
    return $h
}
function Read-Recibo {
    if (-not (Test-Path -LiteralPath $ReciboPath)) { return $null }
    try { return (Get-Content -LiteralPath $ReciboPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Get-RotinasVivas {
    $vivas = @()
    $libLock = Join-Path $ScriptsDir 'lib\vixradar-lock.ps1'
    if (-not (Test-Path -LiteralPath $libLock)) { return @('lib_lock_ausente') }
    . $libLock
    $tag = Get-Date -Format 'yyyyMMdd'
    foreach ($lk in @(Get-ChildItem -LiteralPath $LogDir -Filter ('*_' + $tag + '.lock') -File -ErrorAction SilentlyContinue)) {
        try { $st = Test-VixRotinaAtiva -LockPath $lk.FullName -AbandonoMin 0; if ($st.ativa) { $vivas += $lk.Name } } catch { $vivas += ($lk.Name + ':ilegivel') }
    }
    return $vivas
}

if ($Acao -eq 'Status') {
    $r = Read-Recibo
    Write-Saida ([ordered]@{ acao = 'Status'; flag = (Get-ValorFlag); recibo = $(if ($null -ne $r) { [ordered]@{ ok = $r.ok; gerado_em = $r.gerado_em } } else { $null }); hashes_atuais_batem = $(if ($null -ne $r) { ((Get-HashVigiados | ConvertTo-Json -Compress) -eq ($r.hashes | ConvertTo-Json -Compress)) } else { $false }) }) 0
}

if ($Acao -eq 'Validar') {
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $res = @()
    $okTudo = $true
    foreach ($s in $Suites) {
        $p = Join-Path $ScriptsDir $s
        if (-not (Test-Path -LiteralPath $p)) { $res += [ordered]@{ suite = $s; exit = -1; ok = $false; resumo = 'ausente' }; $okTudo = $false; continue }
        $outF = [IO.Path]::GetTempFileName(); $errF = [IO.Path]::GetTempFileName()
        $proc = Start-Process -FilePath $ps51 -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $p + '"')) -NoNewWindow -PassThru -RedirectStandardOutput $outF -RedirectStandardError $errF
        # PS 5.1: sem ler o Handle logo apos o inicio, ExitCode volta vazio (medido 15/10: as 9
        # suites verdes sairam "exit=" e o recibo reprovou). Falha fechada, mas falsa.
        $null = $proc.Handle
        $terminou = $proc.WaitForExit($TimeoutSuiteSec * 1000)
        if (-not $terminou) { try { $proc.Kill() } catch { } }
        $cod = -2; if ($terminou) { $proc.WaitForExit(); $cod = $proc.ExitCode }
        $txt = ''; try { $txt = [IO.File]::ReadAllText($outF) } catch { }
        Remove-Item -LiteralPath $outF, $errF -ErrorAction SilentlyContinue
        $ult = @(($txt -split "`r?`n") | Where-Object { $_ -match 'RESULTADO|OK,|FALHA|passed|failed' } | Select-Object -Last 1)
        $ok = ($terminou -and $cod -eq 0)
        if (-not $ok) { $okTudo = $false }
        $res += [ordered]@{ suite = $s; exit = $cod; ok = $ok; resumo = ('' + ($ult -join '')).Trim() }
    }
    $lintAlvos = @($Vigiados | ForEach-Object { Join-Path $ScriptsDir $_ }) + @((Join-Path $ScriptsDir 'cobertura-diaria-ativacao.ps1'))
    # Um arquivo por chamada: array de [string[]] nao atravessa `-File` (medido: so o primeiro chega).
    $lintExit = 0
    foreach ($la in $lintAlvos) {
        & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'lint-encoding.ps1') -Path $la | Out-Null
        if ($LASTEXITCODE -ne 0) { $lintExit = $LASTEXITCODE }
    }
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptsDir 'check-claude-free.ps1') | Out-Null
    $cfExit = $LASTEXITCODE
    if ($lintExit -ne 0 -or $cfExit -ne 0) { $okTudo = $false }
    $recibo = [ordered]@{ ok = $okTudo; gerado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); runtime = 'powershell.exe 5.1'; suites = $res; lint_encoding_exit = $lintExit; check_claude_free_exit = $cfExit; hashes = (Get-HashVigiados) }
    try { [IO.File]::WriteAllText($ReciboPath, ($recibo | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false))) } catch { Write-Saida ([ordered]@{ acao = 'Validar'; ok = $false; erro = ('recibo nao gravado: ' + $_.Exception.Message) }) 2 }
    foreach ($r in $res) { Write-Host ('  ' + $(if ($r.ok) { 'OK   ' } else { 'FALHA' }) + ' ' + $r.suite + ' exit=' + $r.exit + ' ' + $r.resumo) }
    Write-Host ('  lint-encoding exit=' + $lintExit + ' check-claude-free exit=' + $cfExit)
    Write-Saida ([ordered]@{ acao = 'Validar'; ok = $okTudo; recibo = $ReciboPath; suites_ok = @($res | Where-Object { $_.ok }).Count; suites_total = $res.Count }) $(if ($okTudo) { 0 } else { 1 })
}

if ($Acao -eq 'Ativar') {
    $motivos = @()
    $r = Read-Recibo
    if ($null -eq $r) { $motivos += 'sem_recibo_de_validacao' }
    else {
        if (-not [bool]$r.ok) { $motivos += 'recibo_reprovado' }
        $idade = 999
        try { $idade = ((Get-Date).ToUniversalTime() - [datetime]::Parse(('' + $r.gerado_em), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalHours } catch { }
        if ($idade -gt 24) { $motivos += 'recibo_com_mais_de_24h' }
        if (((Get-HashVigiados) | ConvertTo-Json -Compress) -ne ($r.hashes | ConvertTo-Json -Compress)) { $motivos += 'codigo_mudou_depois_da_validacao' }
    }
    $vivas = @(Get-RotinasVivas)
    if ($vivas.Count -gt 0) { $motivos += ('rotina_viva:' + ($vivas -join ',')) }
    $antes = Get-ValorFlag
    if ($motivos.Count -gt 0) { Write-Saida ([ordered]@{ acao = 'Ativar'; ok = $false; recusado = $motivos; flag = $antes }) 1 }
    if (-not $Confirmar) { Write-Saida ([ordered]@{ acao = 'Ativar'; ok = $true; simulado = $true; faria = ($Escopo + ' ' + $Flag + ': ' + $antes[$Escopo.ToLowerInvariant()] + ' -> 1'); flag = $antes; aviso = 'sem -Confirmar nada foi alterado' }) 0 }
    $dir = Join-Path $BackupBase ('cobdiaria-ativacao-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $reg = [ordered]@{ flag = $Flag; escopo = $Escopo; valor_anterior = $antes[$Escopo.ToLowerInvariant()]; existia = ($null -ne $antes[$Escopo.ToLowerInvariant()]); gravado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); recibo = $ReciboPath; hashes = (Get-HashVigiados) }
        [IO.File]::WriteAllText((Join-Path $dir 'estado_anterior.json'), ($reg | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    } catch { Write-Saida ([ordered]@{ acao = 'Ativar'; ok = $false; erro = ('registro de rollback nao gravado, nada alterado: ' + $_.Exception.Message) }) 2 }
    [Environment]::SetEnvironmentVariable($Flag, '1', $Escopo)
    $depois = Get-ValorFlag
    $okA = ($depois[$Escopo.ToLowerInvariant()] -eq '1')
    Write-Saida ([ordered]@{ acao = 'Ativar'; ok = $okA; flag_antes = $antes; flag_depois = $depois; rollback = (Join-Path $dir 'estado_anterior.json'); reverter = 'powershell.exe -NoProfile -File scripts\cobertura-diaria-ativacao.ps1 -Acao Reverter' }) $(if ($okA) { 0 } else { 2 })
}

if ($Acao -eq 'Reverter') {
    $p = $Registro
    if (-not $p) {
        $ult = @(Get-ChildItem -LiteralPath $BackupBase -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name.StartsWith('cobdiaria-ativacao-') } | Sort-Object Name | Select-Object -Last 1)
        if ($ult.Count -gt 0) { $p = Join-Path $ult[0].FullName 'estado_anterior.json' }
    }
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { Write-Saida ([ordered]@{ acao = 'Reverter'; ok = $false; erro = 'registro de ativacao nao encontrado'; flag = (Get-ValorFlag) }) 1 }
    $reg = $null
    try { $reg = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Saida ([ordered]@{ acao = 'Reverter'; ok = $false; erro = ('registro ilegivel: ' + $_.Exception.Message) }) 2 }
    $antes = Get-ValorFlag
    $escReg = 'User'; if ((''+$reg.escopo) -eq 'Process') { $escReg = 'Process' }
    if ([bool]$reg.existia) { [Environment]::SetEnvironmentVariable($Flag, ('' + $reg.valor_anterior), $escReg) } else { [Environment]::SetEnvironmentVariable($Flag, $null, $escReg) }
    $depois = Get-ValorFlag
    $okR = $(if ([bool]$reg.existia) { $depois[$escReg.ToLowerInvariant()] -eq ('' + $reg.valor_anterior) } else { $null -eq $depois[$escReg.ToLowerInvariant()] })
    Write-Saida ([ordered]@{ acao = 'Reverter'; ok = $okR; registro = $p; flag_antes = $antes; flag_depois = $depois }) $(if ($okR) { 0 } else { 2 })
}
