# monitor-tasks.ps1 - Alerta de falha silenciosa em Task Scheduler
# Roda diario 07h BRT, varre tasks do workspace, reporta LastTaskResult != benigno.
# ASCII puro (roda no powershell.exe 5.1 sem risco de parse).
param(
    [switch]$Quiet,          # suprime output se nenhum erro encontrado
    [switch]$SendEmail,      # envia e-mail se houver erros (via action=email_enviar do Worker)
    [string]$WhitelistFile,  # JSON externo de whitelist (opcional)
    [string]$To = 'szuchmacheryan@gmail.com',        # destinatario do alerta
    [string]$WorkerUrl = 'https://api.vixradar.com/' # endpoint do action=email_enviar
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
                Write-Host "FALHA Write-Log ($i tentativas), fallback: $fallbackFile, $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Host "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

# Whitelist de LastTaskResult benignos
# 0            = sucesso (exit 0 ou return)
# 267009       = 0x41301 = SCHED_S_TASK_RUNNING (task ainda executando quando verificada, falso positivo)
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
        # Antes hardcoded como 'Credit balance too low'. Agora le o log real
        # para determinar a causa. Se nao encontrar evidencia, reporta como
        # 'causa nao identificada' e mantem como ERRO (nao warning).
        $staleReason = $null
        $rotinaLogDir = Join-Path $VixRoot 'logs\routines'
        $logPattern = Join-Path $rotinaLogDir ('vixradar-agenda-semanal_' + $lastRun.ToString('yyyyMMdd') + '.log')
        if (Test-Path $logPattern) {
            try {
                $logContent = Get-Content $logPattern -Raw -Encoding UTF8 -ErrorAction Stop
                if ($logContent -match 'credit balance is too low|Credit balance too low|insufficient.*credit|quota exceeded') {
                    $staleReason = 'Credit balance too low (confirmado no log)'
                } elseif ($logContent -match 'invalid x-api-key|invalid.*api.key|HTTP 401|401.*Unauthorized|authentication_error') {
                    $staleReason = 'API key invalida (confirmado no log)'
                } elseif ($logContent -match 'ANTHROPIC_BASE_URL|deepseek|agregador') {
                    $staleReason = 'roteamento de agregador detectado no log'
                }
            } catch { }
        }
        if ($staleReason) {
            $entry.reason = $staleReason
            $warnings += $entry
        } else {
            $entry.reason = 'exit 1 sem causa identificada (log nao contem padrao conhecido)'
            $erros += $entry
        }
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
#
# MONITORCEGO2 (2026-08-02): daqui saia uma chamada para
# scripts\monitor_send_email.py, que nunca existiu no repo. O vigia de falha
# silenciosa falhava em silencio. Pior, register-monitor-tasks.ps1 nem passava
# -SendEmail, entao o caminho estava desligado e nao so quebrado. Hoje as 07:00
# a task saiu com LastTaskResult=5 (cinco falhas detectadas) e ninguem soube.
#
# Agora usa action=email_enviar do proprio Worker (api\src\worker.js), com
# admin_senha lida do DPAPI via api\Get-VixAdminCredential.ps1. Sem dependencia
# de Python nova e sem espalhar RESEND_API_KEY pela maquina.
#
# RISCO ACEITO 1: usa credencial de admin humano num caller automatizado,
# misturando os dois niveis que o projeto normalmente separa (admin_senha vs
# routine_key). O endpoint email_enviar so aceita admin_senha, entao nao ha
# alternativa sem mexer no Worker.
# RISCO ACEITO 2: o alerta depende do Worker estar de pe. Se o que quebrou for o
# proprio Worker, o alarme cai junto. Opcao B, documentada e nao adotada, e
# chamar a Resend direto como faz .github\workflows\daily-status-email.yml, o
# que exigiria uma API key dedicada guardada nesta maquina.
#
# Todo o bloco vive dentro de try/catch: falha de e-mail nunca pode derrubar o
# monitor nem mascarar o exit code com a contagem de erros reais.
if ($SendEmail -and $erros.Count -gt 0) {
    try {
        $credScript = Join-Path $VixRoot 'api\Get-VixAdminCredential.ps1'
        if (-not (Test-Path $credScript)) { throw "credencial ausente: $credScript" }
        $adminSenha = & $credScript -AsPlainText
        if (-not $adminSenha) { throw 'Get-VixAdminCredential.ps1 devolveu vazio' }

        $linhas = ''
        foreach ($e in $erros) {
            $linhas += '<tr><td>' + $e.task + '</td><td>' + $e.code + ' (' + $e.codeHex + ')</td><td>' + $e.lastRun + '</td><td>' + $e.reason + '</td><td>' + $e.script + '</td></tr>'
        }
        $html = '<h2>VIX Radar - falha em task agendada</h2>' +
                '<p>' + $erros.Count + ' task(s) com LastTaskResult nao-benigno na maquina ' + $env:COMPUTERNAME + '.</p>' +
                '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-family:sans-serif;font-size:13px">' +
                '<tr><th>Task</th><th>Exit</th><th>Ultima execucao</th><th>Motivo</th><th>Script</th></tr>' +
                $linhas + '</table>' +
                '<p>Warnings nesta rodada: ' + $warnings.Count + '. Relatorio completo em ' + $ErrFile + '</p>'

        $payload = @{
            action       = 'email_enviar'
            admin_senha  = $adminSenha
            assunto      = 'VIX Radar - ' + $erros.Count + ' task(s) com falha'
            html         = $html
            destinatario = $To
        }
        # Bytes UTF-8 na ida e decode UTF-8 explicito na volta: o Worker responde
        # application/json SEM charset e o PS 5.1 assumiria ISO-8859-1, corrompendo
        # acento (P0 nota 43, 2026-07-07). Mesmo padrao de Invoke-WorkerJsonUtf8.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 6 -Compress))
        $resp = Invoke-WebRequest -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30 -UseBasicParsing
        $data = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
        if ($data.ok) {
            Write-Log "Alerta enviado por e-mail para $To ($($data.destinatarios) destinatario(s))"
        } else {
            Write-Log "AVISO: Worker recusou o envio: $($data.erro)"
        }
    } catch {
        # 403 (senha errada) e o modo de falha mais provavel e a mensagem generica
        # do PS nao diz nada util. Le o corpo da resposta quando existir.
        $detalhe = ''
        try {
            $r = $_.Exception.Response
            if ($r -and $r.GetResponseStream) {
                $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
                $detalhe = ' | corpo: ' + $sr.ReadToEnd()
                $sr.Close()
            }
        } catch { }
        Write-Log "AVISO: falha ao enviar alerta por e-mail: $($_.Exception.Message)$detalhe"
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
