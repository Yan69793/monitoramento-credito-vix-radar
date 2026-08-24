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

# Continue (nao Stop): regra global e CLAUDE.md do VIX. Stop faz o Task Scheduler
# engolir falha e o healthcheck FALHA-002 so pegava scripts com python|node|claude.
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VixRoot   = 'E:\Diretorio\Claude\Monitoramento de Credito'
$LogDir    = Join-Path $VixRoot 'logs\monitor-tasks'
$DateTag   = Get-Date -Format 'yyyyMMdd'
$LogFile   = Join-Path $LogDir "monitor_$DateTag.log"
$ErrFile   = Join-Path $LogDir "erros_$DateTag.json"
$EstadoFile = Join-Path $LogDir 'estado.json'
# AIOSEXTRACT1 (2026-08-20): o AI_OPERATING_SYSTEM saiu de dentro do repo do
# Jarvis (01_PROJETOS\Jarvis\) e virou repo proprio na raiz do workspace. Era
# infra compartilhada morando dentro de um projeto especifico, o que impedia
# mover ou apagar o Jarvis sem quebrar esta rotina. Ver CLAUDE.md la.
$BacklogFile = 'E:\Diretorio\Claude\AI_OPERATING_SYSTEM\05_BACKLOG_E_PRIORIDADES.md'

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

# Prefixos de tasks do workspace (B4: MorningCall- e RadarQuant- entraram 2026-08-07)
$Prefixes = @('Szuchmacher-', 'VIXRadar-', 'Monitor-', 'PME-', 'YanOS_', 'MorningCall-', 'RadarQuant-')

# Prefixos de projetos pessoais/externos (reportar como warning, nao erro)
$ExternalPrefixes = @('Monitor-Panerai-', 'PME-Codex-')

# Tasks conhecidas como falso-positivo documentado (comentario no codigo explicando)
$KnownFalsePositives = @{
    'VIXRadar-Matinal' = @{
        code = 6
        reason = 'exit 6 falso documentado no codigo (2026-07-13). Verificar se persiste > 7d.'
        graceDays = 7
    }
    # Corrigido e validado 2026-08-07, mas a task e semanal (segunda 08h) e o
    # LastTaskResult=1 de 03/08 fica congelado ate 10/08. Causa era
    # ConvertFrom-Json -AsHashTable, parametro que so existe no PS 7, contra uma
    # task que roda powershell.exe 5.1. Fix ja no script (linha ~301).
    # Validado no runtime que falhava: powershell.exe -File ... -DryRun deu
    # exit 0 com 3/3 semanas lidas. Graca de 7d a partir de 03/08 cobre exatamente
    # ate a proxima execucao agendada, e escala se falhar de novo em 10/08.
    'VIXRadar-Reconciliacao-CVM' = @{
        code = 1
        reason = 'exit 1 de 03/08 e residuo de bug ja corrigido e validado em 07/08. Se persistir depois de 10/08, o fix nao pegou.'
        graceDays = 7
    }
    # exit 6 de 03/08 foi pre-flight abortando com ANTHROPIC_MODEL=deepseek-v4-pro[1m]
    # no ambiente, comportamento correto do guard. A variavel nao esta mais setada em
    # nenhum escopo e Test-VixClaudeAmbienteLimpo passa desde 07/08. A task e semanal
    # (domingo), entao o resultado fica congelado ate o proximo disparo.
    # NAO validado ao vivo, so o pre-flight foi. Se persistir depois do proximo
    # domingo, a causa e outra e precisa investigacao nova.
    'VIXRadar-AgendaSemanal' = @{
        code = 6
        reason = 'exit 6 de 03/08 era ambiente contaminado, resolvido em 07/08 mas nao validado ao vivo. Se persistir depois do proximo domingo, investigar de novo.'
        graceDays = 7
    }
}

# B1: State=Disabled aqui e GUARD OBRIGATORIO, nao pausa e nao corte de custo.
# A execucao das tres migrou para sessao agendada do Claude Desktop. Os scripts
# checam que a task nativa esta Disabled antes de rodar (ver GUARD_OK no log
# logs/routines/vixradar-verificacao-async_*.log). Reabilitar qualquer uma delas
# quebra o guard e dispara os dois caminhos no mesmo horario, que e exatamente o
# incidente de duplicata citado em routines/README.md.
# LastTaskResult destas tres esta congelado em 2026-08-06 e NAO significa nada.
# A entrega real e vigiada pelo bloco ROTINACEGA1 (linha FIM: no log da rotina).
$GuardedDisabled = @{
    'VIXRadar-Matinal' = @{
        reason = 'GUARD anti-duplicata. Execucao via sessao agendada Claude Desktop. NAO REABILITAR.'
        since  = '2026-08-06 ou depois (rodou pelo Task Scheduler em 06/08 11:31, logo o disable veio apos isso)'
    }
    'VIXRadar-Noturno' = @{
        reason = 'GUARD anti-duplicata. Execucao via sessao agendada Claude Desktop. NAO REABILITAR.'
        since  = '2026-08-06 ou depois (rodou pelo Task Scheduler em 06/08 18:00, logo o disable veio apos isso)'
    }
    'Szuchmacher-LeadNurture' = @{
        reason = 'Desligado em 08/08/2026 por falta de pipeline de entrada. logs/leads.jsonl tem so o lead de teste de 17/06, ja processado. Nao existe qualificador agendado. NAO REABILITAR sem antes criar a fonte de leads (ver 05_BACKLOG_E_PRIORIDADES.md).'
        since  = '2026-08-08'
    }
    'VIXRadar-Verificacao-Async' = @{
        reason = 'GUARD anti-duplicata. Execucao via sessao agendada Claude Desktop. NAO REABILITAR.'
        since  = '2026-08-06 ou depois (rodou pelo Task Scheduler em 06/08 18:20, logo o disable veio apos isso)'
    }
    'Szuchmacher-MacroCron' = @{
        reason = 'Desligado em ~10/08/2026: o cron nativo do Cloudflare (worker do site-producao) assumiu o macro. Pendencia do site-producao/CLAUDE.md, alvo de confirmacao 24/08. NAO REABILITAR enquanto o cron nativo nao estiver confirmado.'
        since  = '2026-08-10'
    }
}

Write-Log '=== MONITOR TASK SCHEDULER ==='
Write-Log "Whitelist benigna: $($BenignCodes -join ', ')"

$erros = @()
$warnings = @()
$deliberate = @()
$ok = 0
$skipped = 0

# Este script sai com exit = numero de erros encontrados (ver fim do arquivo).
# Escanear a propria task e circular: 6 erros as 07h viram LastTaskResult=6, que
# cai fora da whitelist benigna e vira um setimo erro no dia seguinte. Nao e
# falha de execucao, e a contagem de achados. O log e o e-mail ja informam isso.
$SelfTask = 'Monitor-Tasks'

$allTasks = Get-ScheduledTask | Where-Object {
    $name = $_.TaskName
    if ($name -eq $SelfTask) { return $false }
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
    $state = [string]$task.State

    # Calculado aqui, no topo do laco, e nao no meio. Antes disso o bloco de
    # staleness lia $ageDays e $scriptPath antes da atribuicao, entao herdava os
    # valores da task ANTERIOR do foreach e reportava o script errado.
    $ageDays = ((Get-Date) - $lastRun).Days
    $action = $task.Actions | Select-Object -First 1
    $scriptPath = if ($action.Arguments -match '-File\s+"([^"]+)"') { $Matches[1] }
                  elseif ($action.Arguments -match '-File\s+([^\s]+\.ps1)') { $Matches[1] }
                  else { 'desconhecido' }

    # B1: rotina migrada. Disabled aqui e guard esperado, nao falha.
    # Habilitada e o alarme, porque significa execucao dupla com o Claude Desktop.
    if ($GuardedDisabled.ContainsKey($name)) {
        $gd = $GuardedDisabled[$name]
        if ($state -eq 'Disabled') {
            $deliberate += [ordered]@{
                task       = $name
                state      = $state
                lastCode   = $code
                codeHex    = '0x{0:X}' -f $code
                lastRun    = $lastRun.ToString('yyyy-MM-dd HH:mm')
                reason     = $gd.reason
                since      = $gd.since
            }
            Write-Log "GUARD_OK: $name Disabled como esperado | LastResult=$code congelado, ignorar | $($gd.reason)"
            continue
        }
        # Sem este ramo a Noturno reabilitada passaria como sucesso, porque o
        # LastTaskResult dela esta congelado em 0 desde 06/08.
        $erros += [ordered]@{
            task    = $name
            code    = 9002
            codeHex = '0x232A'
            lastRun = $lastRun.ToString('yyyy-MM-dd HH:mm')
            ageDays = 0
            script  = 'guard de execucao dupla'
            reason  = "GUARD QUEBRADO: task esta $state e precisa estar Disabled. Roda em paralelo com a sessao agendada do Claude Desktop. Desabilitar imediatamente."
        }
        Write-Log "ERRO GUARD: $name esta $state e deveria estar Disabled. Risco de execucao dupla."
        continue
    }

    # 267011 = 0x41303 = SCHED_S_TASK_HAS_NOT_RUN. Ambiguo, nao entra na whitelist
    # estatica porque o mesmo codigo cobre dois estados opostos.
    # Com proximo disparo agendado, a task e nova e so nao chegou a hora dela.
    # Caso real: Szuchmacher-ColetaManchetes registrada 07/08/2026 06:59 (evento
    # 106 do agendador), primeiro disparo 12:30 do mesmo dia, reportada como erro
    # por 5 horas sem ter nada de errado.
    # Sem proximo disparo, a task nunca vai rodar e ai e falha real. Caso real:
    # Szuchmacher-AgendaMacro-Claude em 02/08, mesmo codigo, mas Enabled=False
    # desde julho.
    if ($code -eq 267011) {
        if ($null -ne $info.NextRunTime -and $info.NextRunTime -gt (Get-Date)) {
            Write-Log "PENDENTE: $name registrada e ainda sem 1a execucao, proximo disparo $($info.NextRunTime.ToString('yyyy-MM-dd HH:mm'))"
            $ok++
            continue
        }
        $erros += [ordered]@{
            task    = $name
            code    = $code
            codeHex = '0x{0:X}' -f $code
            lastRun = 'nunca'
            ageDays = 0
            script  = $scriptPath
            reason  = 'nunca executou E nao tem proximo disparo agendado. Conferir se esta Enabled e se o gatilho existe.'
        }
        Write-Log "ERRO: $name nunca executou e nao tem proximo disparo agendado."
        continue
    }

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

    # Classifica severidade ($ageDays, $action e $scriptPath vem do topo do laco)

    # COTA1 (2026-08-17): exit 1 por limite de assinatura Claude (weekly/session)
    # vira warning, nao erro. O cluster Szuchmacher falhou entre 11 e 14/08 com
    # 'hit your weekly/session limit' e o monitor escalou como falha persistente
    # de task. A task esta saudavel, a cota e causa externa e reseta sozinha.
    # O log de cada rotina confirma a causa (mesmo padrao do bloco AgendaSemanal).
    $cotaLogPattern = $null
    switch ($name) {
        'Szuchmacher-AgendaMacro-Claude' { $cotaLogPattern = Join-Path $VixRoot ('logs\routines\agenda-macro-szuchmacher_' + $lastRun.ToString('yyyyMMdd') + '.log') }
        'Szuchmacher-FechamentoDiario'   { $cotaLogPattern = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\logs\briefing_' + $lastRun.ToString('yyyyMMdd') + '.log' }
        'Szuchmacher-PreflightAnthropic' { $cotaLogPattern = 'E:\Diretorio\Claude\FREQUENTE\relatorio-diario-szuchmacher\logs\preflight_anthropic_' + $lastRun.ToString('yyyyMMdd') + '.log' }
        'Szuchmacher-BriefingMatinal'   { $cotaLogPattern = 'E:\Diretorio\Claude\FREQUENTE\Morning Call\briefing-interno\logs\briefing_' + $lastRun.ToString('yyyyMMdd') + '.log' }
        'Szuchmacher-BriefingWatchdog'  { $cotaLogPattern = 'E:\Diretorio\Claude\FREQUENTE\Morning Call\briefing-interno\logs\briefing_' + $lastRun.ToString('yyyyMMdd') + '.log' }
    }
    $cotaDetectada = $false
    $cotaTxt = ''
    if ($cotaLogPattern -and (Test-Path $cotaLogPattern)) {
        try {
            $cotaRaw = Get-Content $cotaLogPattern -Raw -Encoding UTF8 -ErrorAction Stop
            if ($cotaRaw -match 'hit your (weekly|session) limit') {
                $cotaDetectada = $true
                $cotaTxt = 'limite de assinatura Claude confirmado no log, task saudavel'
            } elseif ($cotaRaw -match 'PREFLIGHT CRITICO') {
                $cotaDetectada = $true
                $cotaTxt = 'preflight detectou e alertou por push/email, funcao cumprida (motivo no log)'
            } elseif ($name -eq 'Szuchmacher-BriefingWatchdog' -and $cotaRaw -match 'WATCHDOG: ALERTA') {
                $cotaDetectada = $true
                $cotaTxt = 'watchdog detectou briefing ausente e alertou o operador, funcao cumprida'
            } elseif ($name -eq 'Szuchmacher-BriefingMatinal' -and $cotaRaw -match 'ENVIADO OK') {
                $cotaDetectada = $true
                $cotaTxt = 'reprovado as 07h mas reenviado com sucesso no mesmo dia'
            } elseif ($name -eq 'Szuchmacher-BriefingMatinal' -and $cotaRaw -match 'REPROVADO') {
                $cotaDetectada = $true
                $cotaTxt = 'reprovado no portao de validacao, watchdog alertou o operador'
            }
        } catch { }
    }

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
    } elseif ($code -ge 1 -and $code -le 8 -and $name -eq 'VIXRadar-AgendaSemanal') {
        # 2026-08-21: run_vixradar_agenda_semanal.ps1 passou a usar exit 2-8 com
        # causa fixa por codigo. O mapa fecha a causa direto; o log so e lido
        # quando o codigo nao esta no mapa (ex: exit 1 antigo). Causa
        # identificada vira warning, nao identificada vira ERRO.
        $staleReason = $null
        switch ($code) {
            2 { $staleReason = 'exit 2 - claude.exe ausente' }
            3 { $staleReason = 'exit 3 - health do Worker inacessivel no preflight' }
            4 { $staleReason = 'exit 4 - ROUTINE_API_KEY indisponivel localmente' }
            5 { $staleReason = 'exit 5 - nenhuma credencial Claude disponivel' }
            6 { $staleReason = 'exit 6 - ambiente contaminado detectado' }
            7 { $staleReason = 'exit 7 - probe WebSearch falhou' }
            8 { $staleReason = 'exit 8 - ROUTINE_API_KEY rejeitada (403) ou listar_calendario_stale falhou' }
        }
        $rotinaLogDir = Join-Path $VixRoot 'logs\routines'
        $logPattern = Join-Path $rotinaLogDir ('vixradar-agenda-semanal_' + $lastRun.ToString('yyyyMMdd') + '.log')
        if (-not $staleReason -and (Test-Path $logPattern)) {
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
    } elseif (($code -eq 1 -or $code -eq 3) -and $cotaDetectada) {
        $entry.reason = $cotaTxt
        $warnings += $entry
    } elseif ($code -eq 2147946720) {
        # 0x800710E0 = ERROR_REQUEST_REFUSED: o agendador recusou iniciar a task.
        # Caso visto 16/08 (domingo) 20:22: catch-up de trigger perdido recusado,
        # script nem chegou a rodar. Em dia nao util a recusa nao tem custo.
        if ($lastRun.DayOfWeek -in 'Saturday', 'Sunday') {
            Write-Log "INFO: $name recusada pelo agendador em dia nao util ($($lastRun.ToString('yyyy-MM-dd HH:mm'))) - ignorada"
            $ok++
            continue
        }
        $entry.reason = 'recusada pelo agendador (ERROR_REQUEST_REFUSED) em dia util - investigar'
        $erros += $entry
    } elseif ($code -ne 0) {
        $entry.reason = "exit code $code nao-benigno"
        $erros += $entry
    }
}

# ---------------------------------------------------------------------------
# ROTINACEGA1 (2026-08-07): guarda de entrega das rotinas migradas.
#
# O loop acima vigia o Windows Task Scheduler. Matinal, Noturno e
# Verificacao-Async sairam de la entre 04 e 07/08/2026 e passaram a rodar no
# scheduler do Claude Desktop, com as tasks nativas mantidas Disabled de
# proposito. O vigia ficou apontado para um caminho que nao executa mais nada.
#
# Custou 4 dias. A noturna falhou em 03, 04, 06 e 07/08 por tres causas
# distintas (ambiente com modelo nao-Claude no settings.json, credencial Claude
# ausente, e portao de saude abortando por 'ok' agregado quando kv e telemetria
# estavam ambos true) e o monitor reportou OK nos quatro dias, porque a task
# nativa guardava LastTaskResult=0 da ultima vez que rodou antes de ser
# desabilitada. Heartbeat tambem nao pegou: heartbeat:varredura_batch fica
# fresco com status 'pulado' e o watchdog do Worker so mede idade, nao status.
#
# Este bloco nao olha task nenhuma. Olha a evidencia de entrega no log da
# rotina, a linha 'FIM:' com submit_ok, que so e escrita quando a execucao
# chega ao fim. Funciona igual se a rotina rodar pelo Windows, pelo Claude
# Desktop ou na mao.
# ---------------------------------------------------------------------------
$RotinasVigiadas = @(
    @{ nome = 'vixradar-noturno'; rotulo = 'VIXRadar-Noturno (entrega)'; hora = 18; diasUteis = $false; minSubmit = 90 },
    @{ nome = 'vixradar-matinal'; rotulo = 'VIXRadar-Matinal (entrega)'; hora = 10; diasUteis = $true;  minSubmit = 12 }
)
$RotinasLogDir = Join-Path $VixRoot 'logs\routines'

# ROTINACEGA2 (2026-08-19): fallback de entrega por contagem de nome unico.
#
# A linha FIM: e a evidencia primaria, mas ela e escrita pelo modelo no fim da
# sessao e ja faltou em dia inteiramente entregue: 11/08 e 14/08 fecharam 103 de
# 103 emissores sem nunca escreve-la. Nesses dias o vigia dizia "execucao nao
# chegou ao fim" e gerava 9001 com o trabalho todo feito, exatamente o tipo de
# alarme falso que faz o operador parar de ler o alerta.
#
# O ledger OK| e evidencia melhor que a linha de fecho: e escrito por emissor,
# logo apos cada submit confirmado, e nao depende do modelo lembrar de fechar.
# Calibragem conferida contra os 14 logs reais de matinal/noturno disponiveis em
# 19/08: em TODO log onde o contador do FIM: parseou, ele bate exatamente com a
# contagem de nome unico (19=19, 103=103, 20=20). Ou seja o fallback nao afrouxa
# o criterio, mede a mesma coisa por outro caminho.
#
# Dia resgatado pelo fallback NAO vira OK mudo. Vira aviso (9003), porque linha
# FIM: ausente continua sendo defeito real da rotina: o retry-vixradar.ps1 le o
# mesmo sinal e relancaria a rotina a toa.
function Get-VixEmissoresUnicos([string]$conteudo) {
    if (-not $conteudo) { return 0 }
    $vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($conteudo, '(?m)^[\d-]+ [\d:]+ OK\|([^|]+)\|')) {
        $nome = $m.Groups[1].Value.Trim()
        if ($nome) { [void]$vistos.Add($nome) }
    }
    return $vistos.Count
}

foreach ($rot in $RotinasVigiadas) {
    $agoraR = Get-Date
    # Alvo e o ultimo ciclo que ja deveria ter terminado. Com 2h de graca sobre o
    # horario agendado. Monitor roda 07:00, entao na pratica o alvo e sempre ontem.
    $alvo = $agoraR.Date
    if ($agoraR.Hour -lt ($rot.hora + 2)) { $alvo = $agoraR.Date.AddDays(-1) }
    if ($rot.diasUteis) {
        while ($alvo.DayOfWeek -eq 'Saturday' -or $alvo.DayOfWeek -eq 'Sunday') { $alvo = $alvo.AddDays(-1) }
    }
    $alvoTxt = $alvo.ToString('yyyy-MM-dd')
    $logRot  = Join-Path $RotinasLogDir ($rot.nome + '_' + $alvo.ToString('yyyyMMdd') + '.log')

    $motivoR   = $null
    $fallbackR = $null
    $submitOk  = -1

    if (-not (Test-Path $logRot)) {
        $motivoR = "$alvoTxt sem log de execucao, a rotina nao chegou a iniciar"
    } else {
        $conteudoR = ''
        try { $conteudoR = Get-Content $logRot -Raw -Encoding UTF8 -ErrorAction Stop } catch { $conteudoR = '' }
        # FIMREAL1 (2026-08-13): o regex antigo procurava 'submit_ok=N' no arquivo
        # inteiro e o formato da linha FIM mudou:
        #   ate ~08-11:  'FIM: submit_ok=103 total_plano=103'
        #   noturno:     'FIM: noturno 103/103 processados, 0 falhas de submit'
        #   matinal:     'FIM: matinal processados=19 falhas=0 ...'
        # Rotina ENTREGUE com formato novo caia em 'sem linha FIM' e gerava 9001
        # falso (noturno e matinal de 12 e 13/08 no backlog). Alem disso
        # 'SHADOW_FIM:' contem 'FIM:' como substring e era contada como conclusao
        # (08/08 nao tinha FIM real, so SHADOW_FIM).
        $fims = [regex]::Matches($conteudoR, '(?m)(?<!SHADOW_)FIM:\s*(.*?)\r?$')
        if ($fims.Count -eq 0) {
            $detalheR = 'sem linha FIM:, execucao nao chegou ao fim'
            if ($conteudoR -match 'ABORT')      { $detalheR = $detalheR + ', ABORT registrado' }
            if ($conteudoR -match 'ERRO FATAL') { $detalheR = $detalheR + ', ERRO FATAL registrado' }
            # ROTINACEGA2: antes de declarar 9001, conferir o ledger OK| (ver nota da
            # funcao acima). ABORT/ERRO FATAL no log nao anulam a contagem: o que decide
            # e quantos emissores tem submit confirmado, nao se houve susto no meio.
            $unicosR = Get-VixEmissoresUnicos $conteudoR
            if ($unicosR -ge $rot.minSubmit) {
                $submitOk  = $unicosR
                $fallbackR = "$detalheR, PORQUE o ledger OK| tem $unicosR emissores distintos com submit confirmado (minimo $($rot.minSubmit)): dia entregue, a rotina so nao escreveu a linha de fecho"
                $motivoR   = $null
            } else {
                $motivoR = "$alvoTxt $detalheR, e o ledger OK| confirma: so $unicosR emissores distintos com submit (minimo $($rot.minSubmit))"
            }
        } else {
            # FIMRUN21 (2026-08-17): o dia pode ter mais de uma execucao e so a
            # ULTIMA linha FIM era lida. Em 15/08 o noturno teve run-1 com
            # 'FIM: noturno 103/103 processados' e run-2 com
            # 'FIM: noturno run-2 11/11 emissores DEFERRED ... Total do dia 103/103
            # com analise real'. A linha do run-2 nao casa com nenhum padrao de
            # contador, entao submit_ok caia para -1 e gerava 9001 falso mesmo com
            # o dia entregue inteiro. Alerta ficou vermelho desde 13/08 escondendo
            # falha real. Agora varre TODAS as linhas FIM do dia e fica com o maior
            # contador, que e a semantica certa: o que importa e o total entregue
            # no dia, nao qual execucao escreveu a ultima linha.
            $linhaFim   = $fims[$fims.Count - 1].Groups[1].Value
            $linhaMelhor = ''
            $nFal       = -1
            $nFalMelhor = -1
            foreach ($m in $fims) {
                $linha = $m.Groups[1].Value

                # Denominador opcional no 3o padrao (2026-08-19): a matinal de 15/08
                # escreveu "FIM: 19 emissores processados", sem "/19". Nao casava com
                # nenhum dos 4 padroes e cairia em 9001 falso com o dia entregue.
                # Causa raiz (SKILL.md da matinal sem formato exigido) fechada junto.
                $mFim = [regex]::Match($linha, 'submit_ok=(\d+)')
                if (-not $mFim.Success) { $mFim = [regex]::Match($linha, 'Total do dia (\d+)/\d+') }
                if (-not $mFim.Success) { $mFim = [regex]::Match($linha, '(\d+)(?:/\d+)?(?:\s+\S+)?\s+processados') }
                if (-not $mFim.Success) { $mFim = [regex]::Match($linha, 'processados=(\d+)') }

                $mFal    = [regex]::Match($linha, '(\d+) falhas de submit|falhas=(\d+)')
                $nFalEsta = -1
                if ($mFal.Success) {
                    if ($mFal.Groups[1].Success) { $nFalEsta = [int]$mFal.Groups[1].Value }
                    else { $nFalEsta = [int]$mFal.Groups[2].Value }
                }
                if ($nFalEsta -gt $nFal) { $nFal = $nFalEsta }

                if ($mFim.Success) {
                    $valor = [int]$mFim.Groups[1].Value
                    if ($valor -gt $submitOk) {
                        $submitOk    = $valor
                        $linhaMelhor = $linha
                        $nFalMelhor  = $nFalEsta
                    }
                }
            }
            if ($linhaMelhor) { $linhaFim = $linhaMelhor }

            if ($submitOk -ge $rot.minSubmit -and $nFalMelhor -le 0) {
                # Dia entregue. Falha de uma execucao anterior corrigida por outra
                # nao derruba o dia, o que vale e a evidencia de entrega completa.
                $motivoR = $null
            } elseif ($nFal -gt 0) {
                $motivoR = "$alvoTxt FIM com falhas=$nFal"
            } elseif ($submitOk -lt 0) {
                # Mesmo fallback do ramo sem FIM: a linha existe mas nao carrega
                # contador que o cascade reconheca. O ledger OK| decide.
                $unicosR = Get-VixEmissoresUnicos $conteudoR
                if ($unicosR -ge $rot.minSubmit) {
                    $submitOk  = $unicosR
                    $fallbackR = "linha FIM sem contador reconhecido ($linhaFim), PORQUE o ledger OK| tem $unicosR emissores distintos com submit confirmado (minimo $($rot.minSubmit)): dia entregue"
                    $motivoR   = $null
                } else {
                    $motivoR = "$alvoTxt linha FIM sem contador reconhecido: $linhaFim, e o ledger OK| confirma: so $unicosR emissores distintos com submit (minimo $($rot.minSubmit))"
                }
            } elseif ($submitOk -lt $rot.minSubmit) {
                $motivoR = "$alvoTxt entrega parcial, submit_ok=$submitOk (minimo esperado $($rot.minSubmit))"
            }
        }
    }

    if ($motivoR) {
        Write-Log "ROTINA SEM ENTREGA: $($rot.rotulo) | $motivoR"
        $erros += [ordered]@{
            task    = $rot.rotulo
            code    = 9001
            codeHex = '0x2329'
            lastRun = "$alvoTxt (ciclo esperado)"
            ageDays = [int]((Get-Date).Date - $alvo).Days
            script  = $logRot
            reason  = $motivoR
        }
    } elseif ($fallbackR) {
        # Entregue, mas por evidencia secundaria. Aviso, nao erro: nao entra na
        # contagem do exit code (o dia foi entregue), e continua visivel para o
        # operador porque a linha FIM: ausente quebra o retry-vixradar.ps1 tambem.
        Write-Log "ROTINA OK (por ledger OK|, nao por FIM:): $($rot.rotulo) | $alvoTxt $fallbackR"
        $warnings += [ordered]@{
            task    = $rot.rotulo
            code    = 9003
            codeHex = '0x232B'
            lastRun = "$alvoTxt (ciclo esperado)"
            ageDays = [int]((Get-Date).Date - $alvo).Days
            script  = $logRot
            reason  = $fallbackR
        }
        $ok++
    } else {
        Write-Log "ROTINA OK: $($rot.rotulo) | $alvoTxt submit_ok=$submitOk"
        $ok++
    }
}

# ---------------------------------------------------------------------------
# B2: idade do erro (primeira deteccao persistida em estado.json)
# ---------------------------------------------------------------------------
$estado = @{ firstSeen = @{} }
if (Test-Path $EstadoFile) {
    try {
        $rawEst = Get-Content $EstadoFile -Raw -Encoding UTF8 -ErrorAction Stop
        $parsed = $rawEst | ConvertFrom-Json
        if ($parsed.firstSeen) {
            foreach ($p in $parsed.firstSeen.PSObject.Properties) {
                $estado.firstSeen[$p.Name] = @{
                    firstDetected = [string]$p.Value.firstDetected
                    lastCode      = [long]$p.Value.lastCode
                    lastSeen      = [string]$p.Value.lastSeen
                }
            }
        }
    } catch {
        Write-Log "AVISO: estado.json ilegivel, reiniciando - $($_.Exception.Message)"
    }
}

$hojeIso = (Get-Date).ToString('yyyy-MM-dd')
$tasksComErroHoje = @{}
$errosComIdade = @()
foreach ($e in $erros) {
    $tname = [string]$e.task
    $tasksComErroHoje[$tname] = $true
    $first = $hojeIso
    if ($estado.firstSeen.ContainsKey($tname) -and $estado.firstSeen[$tname].firstDetected) {
        $first = [string]$estado.firstSeen[$tname].firstDetected
    } elseif ($e.lastRun -match '(\d{4}-\d{2}-\d{2})') {
        # Primeira vez: se LastRun e razoavel (>= 2026), usa como firstDetected
        # (AgendaSemanal/CVM ja falhavam ha dias sem estado.json previo)
        $lrDay = $Matches[1]
        if ($lrDay -ge '2026-01-01' -and $lrDay -le $hojeIso) { $first = $lrDay }
    }
    $firstDate = $null
    try { $firstDate = [datetime]::ParseExact($first, 'yyyy-MM-dd', $null) } catch { $firstDate = (Get-Date).Date }
    $ageFromFirst = [int]((Get-Date).Date - $firstDate.Date).TotalDays
    if ($ageFromFirst -lt 0) { $ageFromFirst = 0 }

    $estado.firstSeen[$tname] = @{
        firstDetected = $first
        lastCode      = [long]$e.code
        lastSeen      = $hojeIso
    }

    $e2 = [ordered]@{}
    foreach ($k in $e.Keys) { $e2[$k] = $e[$k] }
    $e2['firstDetected'] = $first
    $e2['ageDaysFromFirst'] = $ageFromFirst
    $e2['escalated'] = ($ageFromFirst -ge 2)
    if ($e2['escalated']) {
        $motivoBase = if ($e2.Contains('reason')) { [string]$e2['reason'] } else { 'exit nao-benigno' }
        $e2['reason'] = "ESCALADO (>48h, desde $first): $motivoBase"
    }
    $errosComIdade += $e2
}
$erros = $errosComIdade

# Remove do estado erros que sumiram (limpeza)
$chavesRemover = @()
foreach ($k in @($estado.firstSeen.Keys)) {
    if (-not $tasksComErroHoje.ContainsKey($k)) { $chavesRemover += $k }
}
foreach ($k in $chavesRemover) { $estado.firstSeen.Remove($k) }

try {
    $estadoOut = [ordered]@{
        updated   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
        firstSeen = $estado.firstSeen
    }
    $estadoOut | ConvertTo-Json -Depth 5 | Set-Content -Path $EstadoFile -Encoding UTF8
} catch {
    Write-Log "AVISO: falha ao gravar estado.json - $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# B3: ponte para backlog (upsert por nome de task, secao Auto-monitor)
# ---------------------------------------------------------------------------
# LATCH1 (2026-08-24): a guarda era `$erros.Count -gt 0`. Com zero erro o bloco
# nao rodava e a tabela do ultimo dia com erro ficava congelada no backlog para
# sempre. Alarme que acende e nunca apaga.
#
# Caso medido: VIXRadar-Coleta-Volatilidade falhou uma unica vez em 21/08 17:02
# (BCB SGS 1178 devolveu HTTP 502) e voltou sozinha em 22/08. O monitor das
# 07h de 22/08 ainda leu o LastTaskResult=1 da vespera e gravou a linha. Em
# 23/08 nao havia erro nenhum, o bloco foi pulado, e a linha sobreviveu. Ficou
# tres dias no topo do backlog central como se fosse falha viva.
#
# Agora o bloco roda sempre que o marcador existe. Sem erro, escreve a tabela
# vazia com a data. Ausencia de erro passa a ser um fato registrado, e nao a
# ausencia de escrita.
#
# Nota de defasagem, nao e bug: o monitor roda 07h e varias tasks rodam de
# tarde. Falha noturna sempre aparece na manha seguinte e so limpa na outra.
if (Test-Path $BacklogFile) {
    try {
        $bl = Get-Content $BacklogFile -Raw -Encoding UTF8 -ErrorAction Stop
        $markerStart = '<!-- AUTO-MONITOR-START -->'
        $markerEnd   = '<!-- AUTO-MONITOR-END -->'
        $linhasAuto = @()
        $linhasAuto += ''
        $linhasAuto += '## Auto-monitor (gerado por monitor-tasks.ps1)'
        $linhasAuto += ''
        $linhasAuto += 'Erros persistentes detectados pelo Task Scheduler. Reescrito por inteiro a cada execucao.'
        $linhasAuto += "Ultima atualizacao: $hojeIso."
        $linhasAuto += ''
        if ($erros.Count -eq 0) {
            $linhasAuto += 'Nenhuma task com LastTaskResult nao-benigno nesta varredura.'
            $linhasAuto += ''
        }
        $linhasAuto += '| Task | Desde | Exit | Script | Motivo |'
        $linhasAuto += '|---|---|---|---|---|'
        foreach ($e in $erros) {
            $desde = if ($e.firstDetected) { $e.firstDetected } else { $hojeIso }
            $mot = if ($e.reason) { ($e.reason -replace '\|', '/') } else { '' }
            $scr = if ($e.script) { ($e.script -replace '\|', '/') } else { '' }
            $linhasAuto += "| $($e.task) | $desde | $($e.code) | ``$scr`` | $mot |"
        }
        $linhasAuto += ''
        $bloco = ($linhasAuto -join "`n")
        $section = "$markerStart`n$bloco`n$markerEnd"

        if ($bl -match [regex]::Escape($markerStart)) {
            $bl2 = [regex]::Replace($bl, [regex]::Escape($markerStart) + '[\s\S]*?' + [regex]::Escape($markerEnd), $section)
        } else {
            $bl2 = $bl.TrimEnd() + "`n`n" + $section + "`n"
        }
        if ($bl2 -ne $bl) {
            $bl2 | Set-Content -Path $BacklogFile -Encoding UTF8 -NoNewline
            Write-Log "Backlog atualizado (Auto-monitor): $BacklogFile"
        }
    } catch {
        Write-Log "AVISO: falha ao atualizar backlog - $($_.Exception.Message)"
    }
}

# Sumario
Write-Log ''
Write-Log "=== SUMARIO ==="
Write-Log "OK: $ok"
Write-Log "Erros: $($erros.Count)"
Write-Log "Warnings: $($warnings.Count)"
Write-Log "Deliberados (Disabled): $($deliberate.Count)"
Write-Log "Skipped (falso-positivo conhecido): $skipped"
Write-Log "Rotinas por evidencia de entrega (nao sao tasks do Scheduler, entram nas contagens acima): $($RotinasVigiadas.Count)"

# Persiste erros em JSON
$report = [ordered]@{
    timestamp  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    erros      = $erros
    warnings   = $warnings
    deliberate = $deliberate
    okCount    = $ok
}

$report | ConvertTo-Json -Depth 4 | Set-Content -Path $ErrFile -Encoding UTF8

if ($deliberate.Count -gt 0) {
    Write-Log ''
    Write-Log '=== DESLIGADOS DE PROPOSITO (nao contam como erro) ==='
    foreach ($d in $deliberate) {
        Write-Log "  $($d.task) | since=$($d.since) | LastResult=$($d.lastCode) | $($d.reason)"
    }
}

if ($erros.Count -gt 0) {
    Write-Log ''
    Write-Log '=== ERROS ENCONTRADOS ==='
    foreach ($e in $erros) {
        $idade = if ($null -ne $e.ageDaysFromFirst) { " idade=$($e.ageDaysFromFirst)d desde $($e.firstDetected)" } else { '' }
        $esc = if ($e.escalated) { ' ESCALADO' } else { '' }
        Write-Log "  $($e.task) | exit=$($e.code) ($($e.codeHex))$idade$esc | $($e.lastRun) | $($e.script)"
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
