# test-monitor-dedup.ps1 - prova de duas pontas do MONITOR-PROJETOMISTO1 / MOTOR1.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test-monitor-dedup.ps1
# Cria dir temporario, nao toca producao, nao envia e-mail. ASCII puro (parse no 5.1).
# Roda as MESMAS funcoes que o monitor-tasks.ps1 usa (dot-source da lib vixradar-watchdog.ps1):
#   Select-ErrosParaEmail  dedup por (task, code, lastRun) com reportedAt/escalated
#   Get-PrefixosEscopo     escopo VIX x Site x Todos
#   Test-EntregaPorLog     -MinFim (verificacao: 2 drenos locais por dia util)
#   Get-VixAlertasAuth     ALERTA_AUTH conta, DRYRUN_ALERTA_AUTH nao
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\vixradar-watchdog.ps1')

$tmpRoot = Join-Path $env:TEMP ('vixradar-monitor-dedup-test_' + $PID)
if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot }
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$falhas = @()
$hoje = '2026-09-02'

function Erro([string]$task, [long]$code, [string]$lastRun, [bool]$escalated) {
    return [ordered]@{ task = $task; code = $code; codeHex = ('0x{0:X}' -f $code); lastRun = $lastRun; ageDays = 0; script = 'x'; reason = 'r'; escalated = $escalated; ageDaysFromFirst = 0; firstDetected = $hoje }
}

# ---------------------------------------------------------------------------
# 1. Dedup do e-mail
# ---------------------------------------------------------------------------
# Caso real 27 a 30/08: o mesmo 0x40010004 de um unico reboot gerou 4 e-mails.
$anterior = @{
    'VIXRadar-AgendaSemanal' = @{ firstDetected = '2026-08-27'; lastCode = 1073807364; lastSeen = '2026-09-01'; lastRun = '2026-08-26 22:00'; reportedAt = '2026-08-27'; escalated = $true }
}
$erros = @(
    (Erro 'VIXRadar-AgendaSemanal' 1073807364 '2026-08-26 22:00' $true),   # mesmo (code,lastRun), ja escalado -> persistente
    (Erro 'VIXRadar-Export-Historico' 5 '2026-09-01 20:45' $false),         # nunca reportado -> novo
    (Erro 'vixradar-noturno (auth)' 9004 '2026-09-02' $false)               # 9004 nunca deduplica -> novo
)
$sel = Select-ErrosParaEmail -Erros $erros -EstadoAnterior $anterior -HojeIso $hoje
if (@($sel.persistentes).Count -ne 1 -or $sel.persistentes[0].task -ne 'VIXRadar-AgendaSemanal') { $falhas += 'DEDUP PONTA RUIM: erro repetido (mesmo code+lastRun) deveria ser persistente, veio novos=' + @($sel.novos).Count + ' persistentes=' + @($sel.persistentes).Count }
else { Write-Host 'DEDUP PONTA RUIM OK: erro repetido virou persistente, nao dispara e-mail' }
if (@($sel.novos).Count -ne 2) { $falhas += 'DEDUP PONTA BOA: esperava 2 novos (export nunca reportado + 9004), veio ' + @($sel.novos).Count }
else { Write-Host 'DEDUP PONTA BOA OK: erro nunca reportado e 9004 entram como novos' }

# Escalada: mesmo erro, ontem sem escalar, hoje escalou -> escalado (um e-mail, uma vez).
$anterior2 = @{ 'T' = @{ firstDetected = '2026-08-31'; lastCode = 5; lastSeen = '2026-09-01'; lastRun = '2026-08-31 07:00'; reportedAt = '2026-08-31'; escalated = $false } }
$sel2 = Select-ErrosParaEmail -Erros @((Erro 'T' 5 '2026-08-31 07:00' $true)) -EstadoAnterior $anterior2 -HojeIso $hoje
if (@($sel2.escalados).Count -ne 1) { $falhas += 'ESCALADA: esperava 1 escalado, veio ' + @($sel2.escalados).Count }
else { Write-Host 'ESCALADA OK: erro que cruzou 48h entra uma vez como escalado' }
# Mesmo erro, ja escalado ontem -> persistente, nao repete.
$anterior3 = @{ 'T' = @{ firstDetected = '2026-08-30'; lastCode = 5; lastSeen = '2026-09-01'; lastRun = '2026-08-30 07:00'; reportedAt = '2026-08-30'; escalated = $true } }
$sel3 = Select-ErrosParaEmail -Erros @((Erro 'T' 5 '2026-08-30 07:00' $true)) -EstadoAnterior $anterior3 -HojeIso $hoje
if (@($sel3.persistentes).Count -ne 1) { $falhas += 'ESCALADA REPETIDA: ja escalado deveria ser persistente' }
else { Write-Host 'ESCALADA REPETIDA OK: escalado de ontem nao repete e-mail' }
# Mudou o lastRun (a task rodou de novo e falhou de novo) -> novo.
$sel4 = Select-ErrosParaEmail -Erros @((Erro 'T' 5 '2026-09-02 07:00' $false)) -EstadoAnterior $anterior3 -HojeIso $hoje
if (@($sel4.novos).Count -ne 1) { $falhas += 'LASTRUN NOVO: falha nova da mesma task deveria ser novo' }
else { Write-Host 'LASTRUN NOVO OK: mesma task, execucao nova falhando, volta a alertar' }

# ---------------------------------------------------------------------------
# 2. Escopo
# ---------------------------------------------------------------------------
$vix = Get-PrefixosEscopo 'VIX'
$site = Get-PrefixosEscopo 'Site'
$todos = Get-PrefixosEscopo 'Todos'
function Entra($cfg, [string]$nome) {
    $hit = $false
    foreach ($p in $cfg.prefixos) { if ($nome -like ($p + '*')) { $hit = $true; break } }
    if ($hit) { foreach ($x in $cfg.excluir) { if ($nome -like ($x + '*')) { $hit = $false; break } } }
    return $hit
}
# Caso real 01/09: AgendaAgent e FechamentoDiario (Szuchmacher-) no e-mail do VIX.
if (Entra $vix 'Szuchmacher-AgendaAgent') { $falhas += 'ESCOPO VIX: Szuchmacher-AgendaAgent nao pode entrar' } else { Write-Host 'ESCOPO VIX OK: task do site fica fora' }
if (-not (Entra $vix 'Szuchmacher-RetryVixNoturno')) { $falhas += 'ESCOPO VIX: Szuchmacher-RetryVixNoturno precisa entrar' } else { Write-Host 'ESCOPO VIX OK: retry do VIX entra' }
if (-not (Entra $vix 'VIXRadar-Sentinela')) { $falhas += 'ESCOPO VIX: VIXRadar-Sentinela precisa entrar' }
if (Entra $site 'Szuchmacher-RetryVixMatinal') { $falhas += 'ESCOPO SITE: retry do VIX nao pode entrar no Site' } else { Write-Host 'ESCOPO SITE OK: retry do VIX fica fora' }
if (Entra $site 'VIXRadar-Noturno') { $falhas += 'ESCOPO SITE: VIXRadar- nao pode entrar no Site' }
if (-not (Entra $site 'Szuchmacher-AgendaAgent')) { $falhas += 'ESCOPO SITE: Szuchmacher-AgendaAgent precisa entrar' }
if (-not (Entra $todos 'VIXRadar-Noturno') -or -not (Entra $todos 'Szuchmacher-AgendaAgent')) { $falhas += 'ESCOPO TODOS: precisa cobrir os dois' } else { Write-Host 'ESCOPO TODOS OK: legado cobre tudo' }

# ---------------------------------------------------------------------------
# 3. -MinFim (verificacao-async: 2 drenos locais por dia util)
# ---------------------------------------------------------------------------
$alvo = [datetime]'2026-09-01'
$logV = Join-Path $tmpRoot ('vixradar-verificacao-async_' + $alvo.ToString('yyyyMMdd') + '.log')
[System.IO.File]::WriteAllText($logV, "2026-09-01 11:04:34 INICIO: verificacao-async`n2026-09-01 11:07:01 FIM: verificacao-async local, fila drenada, pendentes=0", (New-Object System.Text.UTF8Encoding($false)))
$st1 = Test-EntregaPorLog -Alvo $alvo -LogDir $tmpRoot -Prefixo 'vixradar-verificacao-async' -Rotulo 'Verificacao-Async' -MinFim 2
if (-not $st1.motivo) { $falhas += 'MINFIM PONTA RUIM: 1 FIM com minimo 2 deveria reprovar' } else { Write-Host ('MINFIM PONTA RUIM OK: ' + $st1.motivo) }
[System.IO.File]::WriteAllText($logV, "2026-09-01 11:04:34 INICIO: verificacao-async`n2026-09-01 11:07:01 FIM: verificacao-async local, fila drenada, pendentes=0`n2026-09-01 19:17:10 INICIO: verificacao-async`n2026-09-01 19:20:00 FIM: verificacao-async local, fila drenada, pendentes=0", (New-Object System.Text.UTF8Encoding($false)))
$st2 = Test-EntregaPorLog -Alvo $alvo -LogDir $tmpRoot -Prefixo 'vixradar-verificacao-async' -Rotulo 'Verificacao-Async' -MinFim 2
if ($st2.motivo) { $falhas += 'MINFIM PONTA BOA: 2 FIM com minimo 2 deveria aceitar: ' + $st2.motivo } else { Write-Host ('MINFIM PONTA BOA OK: execucoes_com_fim=' + $st2.submitOk) }
# FIM_DRYRUN nao conta como FIM:
[System.IO.File]::WriteAllText($logV, "2026-09-01 11:04:34 INICIO`n2026-09-01 11:07:01 FIM_DRYRUN: verificacao-async dry-run`n2026-09-01 19:20:00 FIM_DRYRUN: verificacao-async dry-run", (New-Object System.Text.UTF8Encoding($false)))
$st3 = Test-EntregaPorLog -Alvo $alvo -LogDir $tmpRoot -Prefixo 'vixradar-verificacao-async' -Rotulo 'Verificacao-Async' -MinFim 2
if (-not $st3.motivo) { $falhas += 'MINFIM DRYRUN: FIM_DRYRUN nao pode contar como entrega' } else { Write-Host 'MINFIM DRYRUN OK: FIM_DRYRUN nao conta como entrega' }

# ---------------------------------------------------------------------------
# 4. ALERTA_AUTH x DRYRUN_ALERTA_AUTH
# ---------------------------------------------------------------------------
$dia = [datetime]'2026-09-02'
$logN = Join-Path $tmpRoot ('vixradar-noturno_' + $dia.ToString('yyyyMMdd') + '.log')
[System.IO.File]::WriteAllText($logN, "2026-09-02 12:58:00 DRYRUN_ALERTA_AUTH: noturno abortada no lote light-1 - teste`n2026-09-02 12:58:01 DRYRUN: alerta NAO enviado", (New-Object System.Text.UTF8Encoding($false)))
$a1 = @(Get-VixAlertasAuth -RotinasLogDir $tmpRoot -Dias @($dia))
if ($a1.Count -ne 0) { $falhas += 'AUTH DRYRUN: DRYRUN_ALERTA_AUTH nao pode virar 9004, veio ' + $a1.Count } else { Write-Host 'AUTH DRYRUN OK: teste nao vira incidente' }
[System.IO.File]::WriteAllText($logN, "2026-09-02 18:10:00 ALERTA_AUTH: noturno abortada no lote light-1 - limite de uso da assinatura atingido", (New-Object System.Text.UTF8Encoding($false)))
$a2 = @(Get-VixAlertasAuth -RotinasLogDir $tmpRoot -Dias @($dia))
if ($a2.Count -ne 1 -or $a2[0].rotina -ne 'vixradar-noturno') { $falhas += 'AUTH REAL: ALERTA_AUTH real precisa virar 9004' } else { Write-Host ('AUTH REAL OK: ' + $a2[0].linha) }

Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
if ($falhas.Count -gt 0) {
    Write-Host 'FALHAS:'
    foreach ($f in $falhas) { Write-Host ('  - ' + $f) }
    exit 1
}
Write-Host 'MONITOR DEDUP + ESCOPO + MINFIM + AUTH: prova de duas pontas OK'
exit 0
