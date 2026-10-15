# test-cobertura-diaria-ativacao.ps1 - IDEMEFETIVA1 (2026-10-15): a ativacao do controle diario so
# acontece depois de validada e sempre com rollback. Prova de duas pontas do portao de
# scripts\cobertura-diaria-ativacao.ps1, em escopo Process e caminhos temporarios: a variavel real
# do usuario (VIXRADAR_COBERTURA_DIARIA, escopo User) NUNCA e tocada por esta suite.
# ASCII puro, PowerShell 5.1 e 7.
$ErrorActionPreference = 'Continue'
$alvo = Join-Path $PSScriptRoot 'cobertura-diaria-ativacao.ps1'
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('cobdiaria_ativ_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$recibo = Join-Path $tmp 'recibo.json'
$bk = Join-Path $tmp 'backups'
New-Item -ItemType Directory -Force -Path $bk | Out-Null
$userAntes = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', 'User')

$script:okN = 0; $script:fal = 0
function Assert-Atv([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }
function Invoke-Ativacao([string[]]$Extra) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $alvo, '-Escopo', 'Process', '-ReciboPath', $recibo, '-BackupBase', $bk) + $Extra
    $o = @(& $ps51 @a 2>&1)
    $cod = $LASTEXITCODE
    $j = $null
    $ult = @($o | ForEach-Object { '' + $_ } | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if ($ult.Count -gt 0) { try { $j = $ult[0] | ConvertFrom-Json } catch { $j = $null } }
    return [pscustomobject]@{ Exit = $cod; J = $j; Txt = ($o -join "`n") }
}
$vig = @('run_vixradar_varredura.ps1', 'retry-vixradar.ps1', 'monitor-tasks.ps1', 'lib\vixradar-cobertura-diaria.ps1', 'lib\vixradar-cobertura.ps1', 'lib\vixradar-watchdog.ps1', 'lib\vixradar-custo.ps1')
function Write-Recibo([bool]$Ok, [string]$Quando, [string]$Estragar = '') {
    $h = [ordered]@{}
    foreach ($f in $vig) { $p = Join-Path $PSScriptRoot $f; if (Test-Path -LiteralPath $p) { $h[$f] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { $h[$f] = 'AUSENTE' } }
    if ($Estragar) { $h[$Estragar] = ('0' * 64) }
    $r = [ordered]@{ ok = $Ok; gerado_em = $Quando; hashes = $h }
    [IO.File]::WriteAllText($recibo, ($r | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
}
$agora = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host '=== recusa (ponta ruim) ==='
$r1 = Invoke-Ativacao @('-Acao', 'Ativar', '-Confirmar')
Assert-Atv (($r1.Exit -eq 1) -and ((@($r1.J.recusado) -join ',') -match 'sem_recibo_de_validacao')) 'A1 sem validacao: recusa, exit 1'
Write-Recibo $false $agora
$r2 = Invoke-Ativacao @('-Acao', 'Ativar', '-Confirmar')
Assert-Atv (($r2.Exit -eq 1) -and ((@($r2.J.recusado) -join ',') -match 'recibo_reprovado')) 'A2 validacao reprovada: recusa'
Write-Recibo $true $agora 'run_vixradar_varredura.ps1'
$r3 = Invoke-Ativacao @('-Acao', 'Ativar', '-Confirmar')
Assert-Atv (($r3.Exit -eq 1) -and ((@($r3.J.recusado) -join ',') -match 'codigo_mudou_depois_da_validacao')) 'A3 motor mudou depois da validacao: recusa'
Write-Recibo $true ((Get-Date).ToUniversalTime().AddHours(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'))
$r4 = Invoke-Ativacao @('-Acao', 'Ativar', '-Confirmar')
Assert-Atv (($r4.Exit -eq 1) -and ((@($r4.J.recusado) -join ',') -match 'recibo_com_mais_de_24h')) 'A4 validacao velha (30h): recusa'
Assert-Atv (@(Get-ChildItem -LiteralPath $bk -Directory).Count -eq 0) 'A5 nenhuma recusa gravou registro de ativacao'

Write-Host '=== aceita (ponta boa) e rollback ==='
Write-Recibo $true $agora
$r5 = Invoke-Ativacao @('-Acao', 'Ativar')
Assert-Atv (($r5.Exit -eq 0) -and [bool]$r5.J.simulado -and @(Get-ChildItem -LiteralPath $bk -Directory).Count -eq 0) 'B1 sem -Confirmar: so simula, nada gravado'
$r6 = Invoke-Ativacao @('-Acao', 'Ativar', '-Confirmar')
$viva = ((@($r6.J.recusado) -join ',') -match 'rotina_viva')
if ($viva) {
    Write-Host ('  N/A   B2..B4 rotina do dia viva agora (' + (@($r6.J.recusado) -join ',') + '): o portao recusou, como deve; ciclo de ativacao nao avaliado')
} else {
    Assert-Atv (($r6.Exit -eq 0) -and ('' + $r6.J.flag_depois.process) -eq '1') ('B2 validado e confirmado: ativa (process=' + $r6.J.flag_depois.process + ')')
    $regs = @(Get-ChildItem -LiteralPath $bk -Recurse -Filter 'estado_anterior.json')
    $reg = $null; if ($regs.Count -eq 1) { $reg = Get-Content -LiteralPath $regs[0].FullName -Raw | ConvertFrom-Json }
    Assert-Atv (($null -ne $reg) -and ($reg.escopo -eq 'Process') -and (-not [bool]$reg.existia)) 'B3 rollback gravado ANTES de mudar, com o valor anterior (ausente)'
    $r7 = Invoke-Ativacao @('-Acao', 'Reverter', '-Registro', $regs[0].FullName)
    Assert-Atv (($r7.Exit -eq 0) -and [bool]$r7.J.ok -and ($null -eq $r7.J.flag_depois.process)) 'B4 reverter restaura o estado anterior (ausente)'
}
$userDepois = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', 'User')
Assert-Atv ($userDepois -eq $userAntes) ('C1 variavel real (User) intocada pela suite: antes=[' + $userAntes + '] depois=[' + $userDepois + ']')

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + ' OK, ' + $script:fal + ' FALHA')
if ($script:fal -gt 0) { exit 1 }
exit 0
