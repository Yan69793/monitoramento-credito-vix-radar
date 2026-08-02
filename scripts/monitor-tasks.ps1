# monitor-tasks.ps1 — Alerta de falha silenciosa em Task Scheduler
# Roda diario 07h BRT, varre tasks do workspace, reporta LastTaskResult != benigno.
# ASCII puro (roda no powershell.exe 5.1 sem risco de parse).
param(
    [switch]$Quiet,          # suprime output se nenhum erro encontrado
    [switch]$SendEmail,      # envia e-mail se houver erros (requer monitor_send_email.py)
    [string]$WhitelistFile   # JSON externo de whitelist (opcional)
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VixRoot   = 'E:\Diretorio\Claude\Monitoramento de Credito'
$LogDir    = Join-Path $VixRoot 'logs\monitor-tasks'
$DateTag   = Get-Date -Format 'yyyyMMdd'
$LogFile   = Join-Path $LogDir "monitor_$DateTag.log"
$ErrFile   = Join-Path $LogDir "erros_$DateTag.json"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    if (-not $Quiet) { Write-Host $line }
    # LOGLOCK1-REC (2026-07-24): backoff exponencial + fallback file com PID
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                $fallbackFile = ([regex]::Replace($LogFile, '\.log$', "_fallback_$pid.log"))
                Write-Host "FALHA Write-Log ($i tentativas), fallback: $fallbackFile — $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Host "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

# Whitelist de LastTaskResult benignos
# 0            = sucesso (exit 0 ou return)
# 267009       = 0x41301 = SCHED_S_TASK_RUNNING (task ainda executando quando verificada — falso positivo)
$BenignCodes = @(0, 267009)

# Whitelist customizada (JSON externo, merge)
if ($WhitelistFile -and (Test-Path $WhitelistFile)) {
    try {
        $custom = Get-Content $WhitelistFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($custom.benignCodes) {
            $BenignCodes += $custom.benignCodes
            Write-Log "Whitelist carregada: $WhitelistFile (+$($custom.benignCodes.Count) codigos)"
        }
    } catch {
        Write-Log "AVISO: whitelist invalida - $($_.Exception.Message)"
    }
}

# Prefixos de tasks do workspace
$Prefixes = @('Szuchmacher-', 'VIXRadar-', 'Monitor-', 'PME-', 'YanOS_')

# Prefixos de projetos pessoais/externos (reportar como warning, nao erro)
$ExternalPrefixes = @('Monitor-Panerai-', 'PME-Codex-')

# Tasks conhecidas como falso-positivo documentado (comentario no codigo explicando)
$KnownFalsePositives = @{
    'VIXRadar-Matinal' = @{
        code = 6
        reason = 'exit 6 falso documentado no codigo (2026-07-13). Verificar se persiste > 7d.'
        graceDays = 7
    }
}

Write-Log '=== MONITOR TASK SCHEDULER ==='
Write-Log "Whitelist benigna: $($BenignCodes -join ', ')"

$erros = @()
$warnings = @()
$ok = 0
$skipped = 0

$allTasks = Get-ScheduledTask | Where-Object {
    $name = $_.TaskName
    $hit = $false
    foreach ($p in $Prefixes) {
        if ($name -like "$p*") { $hit = $true; break }
    }
    $hit
}

Write-Log "Tasks escaneadas: $($allTasks.Count)"

foreach ($task in $allTasks) {
    $name = $task.TaskName
    try {
        $info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
    } catch {
        Write-Log "WARN: info indisponivel para $name - $_"
        $skipped++
        continue
    }

    $code = $info.LastTaskResult
    $lastRun = $info.LastRunTime

    # Pula benignos
    if ($code -in $BenignCodes) {
        $ok++
        continue
    }

    # Verifica falso-positivo conhecido
    if ($KnownFalsePositives.ContainsKey($name)) {
        $kfp = $KnownFalsePositives[$name]
        if ($code -eq $kfp.code) {
            $ageDays = ((Get-Date) - $lastRun).Days
            if ($ageDays -le $kfp.graceDays) {
                Write-Log "INFO: $name exit=$code (falso-positivo conhecido, dia $ageDays/$($kfp.graceDays))"
                $skipped++
                continue
            }
            # Excedeu periodo de graca - escala para warning
            $warnings += [ordered]@{
                task = $name; code = $code; lastRun = $lastRun.ToString('yyyy-MM-dd HH:mm')
                reason = "falso-positivo conhecido ha $ageDays dias (> $($kfp.graceDays)d) - reavaliar"
            }
            continue
        }
    }

    # Staleness check: tasks que nao rodaram no periodo esperado. Roda mesmo quando
    # LastTaskResult=0, porque o que importa aqui e que a task NAO EXECUTOU, nao que a
    # ultima execucao falhou. Matinal 01/08 nao rodou e ninguem viu porque o codigo de
    # saida da ultima execucao bem-sucedida (31/07) era 0.
    $staleHours = $null
    $staleMsg = ''
    $dailyTasks = @{
        'VIXRadar-Noturno'            = @{ hours = 18; weekdays = $false }
        'VIXRadar-Matinal'            = @{ hours = 10; weekdays = $true  }
        'VIXRadar-Coleta-Volatilidade' = @{ hours = 17; weekdays = $false }
        'VIXRadar-Export-Historico'   = @{ hours = 20; weekdays = $false }
        'VIXRadar-Verificacao-Async'  = @{ hours = 10; weekdays = $false }
    }
    if ($dailyTasks.ContainsKey($name)) {
        $cfg = $dailyTasks[$name]
        $now = Get-Date
        $hoursSince = [Math]::Round(($now - $lastRun).TotalHours, 1)
        # Tarefa rodou hoje? LastRun no mesmo dia do calendario.
        $rodouHoje = ($lastRun.Date -eq $now.Date)
        # Se nao rodou hoje e o horario previsto ja passou (com 2h de graca), flag.
        # Monitor roda as 07:00, entao para tarefas das 18:00 ou 20:45, a checagem
        # cai sobre ontem: se a ultima execucao foi antes de ontem, faltou um ciclo.
        $esperadoHoje = ($now.Hour -ge ($cfg.hours + 2))
        if (-not $rodouHoje -and $esperadoHoje) {
            $ontemFoiDiaUtil = $true
            if ($cfg.weekdays) {
                $ontem = $now.AddDays(-1)
                $ontemFoiDiaUtil = ($ontem.DayOfWeek -notin 'Saturday', 'Sunday')
            }
            if ($ontemFoiDiaUtil) {
                $staleHours = $hoursSince
                $staleMsg = "nao rodou no ciclo esperado (ultimo ha ${hoursSince}h, periodo ~24h)"
            }
        }
    }
    # Stale com exit code benigno e o caso mais perigoso: task simplesmente nao
    # disparou e ninguem percebeu (Matinal 01/08). Reportar como warning distinto.
    if ($staleHours -and $code -in $BenignCodes) {
        $warnings += [ordered]@{
            task = $name; code = $code; codeHex = '0x{0:X}' -f $code
            lastRun = $lastRun.ToString('yyyy-MM-dd HH:mm'); ageDays = $ageDays
            script = $scriptPath; reason = $staleMsg
        }
        continue
    }

    # Classifica severidade
    $ageDays = ((Get-Date) - $lastRun).Days
    $action = $task.Actions | Select-Object -First 1
    $scriptPath = if ($action.Arguments -match '-File\s+"([^"]+)"') { $Matches[1] }
                  elseif ($action.Arguments -match '-File\s+([^\s]+\.ps1)') { $Matches[1] }
                  else { 'desconhecido' }

    # Verifica se eh projeto externo/pessoal
    $isExternal = $false
    foreach ($ep in $ExternalPrefixes) {
        if ($name -like "$ep*") { $isExternal = $true; break }
    }

    $entry = [ordered]@{
        task       = $name
        code       = $code
        codeHex    = '0x{0:X}' -f $code
        lastRun    = $lastRun.ToString('yyyy-MM-dd HH:mm')
        ageDays    = $ageDays
        script     = $scriptPath
    }

    if ($isExternal) {
        $entry.reason = 'PROJETO EXTERNO/PESSOAL - verificar manualmente se necessario'
        $warnings += $entry
    } elseif ($code -eq 2147942402) {
        # 0x80070002 = ERROR_FILE_NOT_FOUND em runtime (script movido/renomeado)
        $entry.reason = 'SCRIPT AUSENTE (file-not-found em runtime)'
        $warnings += $entry
    } elseif ($code -eq 1 -and $name -eq 'VIXRadar-AgendaSemanal') {
        # Credit balance too low no claude -p (quota de assinatura Claude Code)
        $entry.reason = 'Credit balance too low (assinatura Claude Code)'
        $warnings += $entry
    } elseif ($code -ne 0) {
        $entry.reason = "exit code $code nao-benigno"
        $erros += $entry
    }
}

# Sumario
Write-Log ''
Write-Log "=== SUMARIO ==="
Write-Log "OK: $ok"
Write-Log "Erros: $($erros.Count)"
Write-Log "Warnings: $($warnings.Count)"
Write-Log "Skipped (falso-positivo conhecido): $skipped"

# Persiste erros em JSON
$report = [ordered]@{
    timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    erros     = $erros
    warnings  = $warnings
    okCount   = $ok
}

$report | ConvertTo-Json -Depth 4 | Set-Content -Path $ErrFile -Encoding UTF8

if ($erros.Count -gt 0) {
    Write-Log ''
    Write-Log '=== ERROS ENCONTRADOS ==='
    foreach ($e in $erros) {
        Write-Log "  $($e.task) | exit=$($e.code) ($($e.codeHex)) | $($e.lastRun) | $($e.script)"
    }
}

if ($warnings.Count -gt 0) {
    Write-Log ''
    Write-Log '=== WARNINGS ==='
    foreach ($w in $warnings) {
        Write-Log "  $($w.task) | exit=$($w.code) | $($w.lastRun) | $($w.reason)"
    }
}

# Alerta por e-mail se houver erros e -SendEmail ativado
if ($SendEmail -and $erros.Count -gt 0) {
    $sendScript = Join-Path $VixRoot 'scripts\monitor_send_email.py'
    if (Test-Path $sendScript) {
        $errJson = $ErrFile
        $py = (Get-Command python -ErrorAction SilentlyContinue).Source
        if (-not $py) { $py = 'python' }
        try {
            & $py $sendScript $errJson
            Write-Log "Alerta enviado por e-mail"
        } catch {
            Write-Log "AVISO: falha ao enviar e-mail: $_"
        }
    } else {
        Write-Log "AVISO: $sendScript ausente - sem envio de e-mail"
    }
}

Write-Log '=== FIM ==='

if ($erros.Count -eq 0) {
    exit 0
} else {
    # Sai com contagem de erros (capped em 255) para o Task Scheduler ver
    $exitCode = [Math]::Min($erros.Count, 255)
    exit $exitCode
}
