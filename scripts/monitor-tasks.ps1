# monitor-tasks.ps1 - Alerta de falha silenciosa em Task Scheduler
# Roda diario 07h BRT, varre tasks do workspace, reporta LastTaskResult != benigno.
# ASCII puro (roda no powershell.exe 5.1 sem risco de parse).
param(
    [switch]$Quiet,          # suprime output se nenhum erro encontrado
    [switch]$SendEmail,      # envia e-mail se houver erros (via action=email_enviar do Worker)
    [string]$WhitelistFile,  # JSON externo de whitelist (opcional)
    [string]$To = 'szuchmacheryan@gmail.com',        # destinatario do alerta
    [string]$WorkerUrl = 'https://api.vixradar.com/', # endpoint do action=email_enviar
    # MONITOR-PROJETOMISTO1 (2026-09-02): escopo por projeto. VIX = so tasks do VIX Radar
    # (VIXRadar-, Monitor-, Szuchmacher-RetryVix*). Site = os projetos irmaos. Todos = legado.
    [ValidateSet('VIX', 'Site', 'Todos')][string]$Escopo = 'VIX',
    [switch]$DryRun,         # nao grava estado.json, nao toca o backlog, nao envia e-mail; loga o que faria
    [switch]$ForcarEmail     # envia e-mail mesmo sem erro novo (teste do canal)
)

# Continue (nao Stop): regra global e CLAUDE.md do VIX. Stop faz o Task Scheduler
# engolir falha e o healthcheck FALHA-002 so pegava scripts com python|node|claude.
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# SENTINELA-DIAPERDIDO1 (2026-08-30): lib de evidencia de entrega por log, dot-source.
# A logica mora aqui para o test-sentinela-watchdog.ps1 provar as duas pontas com a
# MESMA funcao que a producao usa.
. (Join-Path $ScriptDir 'lib\vixradar-watchdog.ps1')
. (Join-Path $ScriptDir 'lib\vixradar-custo.ps1')
# CLAUDE-FREE-MIGRATION (2026-09-04): fonte unica de provider de LLM das rotinas.
# Quando bloqueado (provider none, claude-manual sem forca manual, ou provider de Fase B
# reservado com motor nao migrado), as rotinas LLM do VIX saem exit 86 com a linha canonica
# BLOQUEADO_SEM_PROVIDER ANTES de qualquer auth/claude. Este monitor trata exit 86 como
# esperado nesse regime, suprime a vigilancia de entrega (nao ha entrega esperada) e troca
# por checagem de que o executor rodou o ciclo (sentinel no log do dia). Resultado != 86 de
# uma rotina que rodou DEPOIS do bloqueio e 9006 (violacao do gate). 9004 ALERTA_AUTH segue
# valendo: escalacao para chave paga vista em log prova que o corte falhou e vira erro.
. (Join-Path $ScriptDir 'lib\vixradar-llm-provider.ps1')
$LlmProvider   = Get-VixLlmProvider
$LlmBloqueado  = -not (Test-VixLlmPermiteClaude)
# Nomes das 5 tasks nativas de rotina LLM do VIX + nomes de log correspondentes (bloco
# ROTINACEGA1 abaixo usa os nomes de log). Sentinela pode sair exit 0 (sem alvos) e 86
# (com alvos bloqueado); 0 ja e benigno globalmente.
$BloqueadasSet = @('VIXRadar-Matinal', 'VIXRadar-Noturno', 'VIXRadar-Verificacao-Async', 'VIXRadar-Sentinela', 'VIXRadar-AgendaSemanal')
$BloqueadasLog = @('vixradar-noturno', 'vixradar-matinal', 'vixradar-verificacao-async', 'vixradar-sentinela', 'vixradar-agenda-semanal')
$VixRoot   = 'E:\Diretorio\Claude\Monitoramento de Credito'
$LogDir    = Join-Path $VixRoot 'logs\monitor-tasks'
$DateTag   = Get-Date -Format 'yyyyMMdd'
# Escopo VIX mantem os nomes legados (monitor_, erros_, estado.json); os outros ganham sufixo.
$SufixoEscopo = if ($Escopo -eq 'VIX') { '' } else { '_' + $Escopo }
$LogFile   = Join-Path $LogDir ('monitor' + $SufixoEscopo + "_$DateTag.log")
$ErrFile   = Join-Path $LogDir ('erros' + $SufixoEscopo + "_$DateTag.json")
$EstadoFile = Join-Path $LogDir ('estado' + $SufixoEscopo + '.json')
$MotorFile = Join-Path $LogDir 'motor.json'
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

# Prefixos de tasks por escopo (MONITOR-PROJETOMISTO1; lista legada = escopo Todos).
$EscopoCfg = Get-PrefixosEscopo $Escopo
$Prefixes = @($EscopoCfg.prefixos)
$PrefixesExcluir = @($EscopoCfg.excluir)

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

# MOTOR1 (2026-09-02): quando o cutover para o Task Scheduler estiver feito, motor.json diz
# {motor:"task-scheduler"} e as tres tasks passam a ser o motor real: Disabled vira erro
# 9002 (o Passo 0 de uma sessao Claude Desktop reativada as desabilita em silencio).
$MotorAtual = 'claude-desktop'
$MotorDesde = $null
if (Test-Path $MotorFile) {
    try {
        $mj = Get-Content $MotorFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($mj.motor) { $MotorAtual = [string]$mj.motor }
        # CLAUDE-FREE-MIGRATION: `desde` e o marco do regime bloqueado. Uma rotina do
        # $BloqueadasSet com LastTaskResult != 86 SO e violacao (9006) se a execucao que
        # produziu aquele resultado correu DEPOIS deste marco; resultado anterior e
        # historico congelado e vira "aguardando 1o ciclo" (evita tempestade na transicao).
        if ($null -ne $mj.desde) { $MotorDesde = [string]$mj.desde }
    } catch { Write-Log "AVISO: motor.json ilegivel - $($_.Exception.Message)" }
}
$MustBeEnabled = @{}
if ($MotorAtual -eq 'task-scheduler') {
    foreach ($t in @('VIXRadar-Matinal', 'VIXRadar-Noturno', 'VIXRadar-Verificacao-Async')) {
        $GuardedDisabled.Remove($t)
        $MustBeEnabled[$t] = 'MOTOR1: motor Task Scheduler ativo (logs\monitor-tasks\motor.json). Esta task e o motor real da rotina e precisa estar Enabled.'
    }
    # CLAUDE-FREE-MIGRATION (2026-09-04): os 2 retries sao desligados de proposito na Fase A.
    # Com a rotina base bloqueada por provider (BLOQUEADO_SEM_PROVIDER, exit 86), relancar nao
    # entrega e o retry-vixradar.ps1 ja vira no-op exit 0. Task Enabled aqui e guard quebrado.
    foreach ($t in @('Szuchmacher-RetryVixMatinal', 'Szuchmacher-RetryVixNoturno')) {
        $GuardedDisabled[$t] = @{
            reason = 'Retry desligado na Fase A (CLAUDE-FREE-MIGRATION 2026-09-04): rotina base bloqueada por provider, relancamento nao entrega e viraria falso SEM ENTREGA. Reativar na Fase B quando houver provider de LLM.'
            since  = '2026-09-04'
        }
    }
}

Write-Log '=== MONITOR TASK SCHEDULER ==='
Write-Log "Escopo: $Escopo | motor: $MotorAtual | dryrun: $DryRun"
Write-Log ("Provider LLM: " + $LlmProvider + " | bloqueado: " + $LlmBloqueado + " | exit 86 = BLOQUEADO_SEM_PROVIDER esperado")
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
    if ($name -like ($SelfTask + '*')) { return $false }
    $hit = $false
    foreach ($p in $Prefixes) {
        if ($name -like "$p*") { $hit = $true; break }
    }
    if ($hit) {
        foreach ($x in $PrefixesExcluir) { if ($name -like "$x*") { $hit = $false; break } }
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

    # MOTOR1: com o motor Task Scheduler ativo, a task nativa desabilitada e a rotina morta.
    if ($MustBeEnabled.ContainsKey($name) -and $state -eq 'Disabled') {
        $erros += [ordered]@{
            task    = $name
            code    = 9002
            codeHex = '0x232A'
            lastRun = $lastRun.ToString('yyyy-MM-dd HH:mm')
            ageDays = 0
            script  = $scriptPath
            reason  = "MOTOR DESLIGADO: task esta Disabled e o motor ativo e o Task Scheduler. Sem ela a rotina nao roda. Reabilitar (cutover-motor.ps1 -Acao Ativar) ou conferir se uma sessao Claude Desktop antiga a desligou. " + $MustBeEnabled[$name]
        }
        Write-Log "ERRO MOTOR: $name esta Disabled com motor task-scheduler ativo."
        continue
    }

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

    # CLAUDE-FREE-MIGRATION: rotina LLM nativa sob provider bloqueado. Exit 86 = canonico,
    # esperado, NAO e erro. Resultado != 86 de execucao que correu DEPOIS do `desde` do
    # motor.json (marco do corte) e 9006: o gate nao cortou, claude rodou por bypass, ou a
    # acao da task passou -ForceClaude. Codigo anterior ao marco e historico congelado do
    # regime antigo e nao e violacao: entra como "aguardando 1o ciclo" para nao incendiar a
    # transicao. Sem motor.json (motor claude-desktop, janela G1-G3) nenhuma destas roda pelo
    # Scheduler alem de Sentinela/Agenda, e codigo velho nao-bloqueado segue esse mesmo
    # caminho de aguardando. A calibracao fina e o gate G5 do plano.
    if ($LlmBloqueado -and ($BloqueadasSet -contains $name) -and $code -eq 86) {
        Write-Log "BLOQUEADO esperado: $name exit=86 ($scriptPath). Rotina bloqueada por design, sem entrega esperada."
        $ok++
        continue
    }
    if ($LlmBloqueado -and ($BloqueadasSet -contains $name) -and ($code -notin $BenignCodes) -and $code -ne 86) {
        $rodouNoBloqueio = $false
        if ($MotorDesde) {
            try { if ($lastRun -gt ([datetime]$MotorDesde)) { $rodouNoBloqueio = $true } } catch { }
        }
        if ($rodouNoBloqueio) {
            $erros += [ordered]@{
                task    = $name
                code    = 9006
                codeHex = '0x232E'
                lastRun = $lastRun.ToString('yyyy-MM-dd HH:mm')
                ageDays = $ageDays
                script  = $scriptPath
                reason  = 'VIOLACAO DO GATE: rotina LLM bloqueada por provider (' + $LlmProvider + ') rodou no regime bloqueado e nao saiu exit 86 (saiu ' + $code + '). Gate ausente/quebrado ou acao da task passou -ForceClaude. Conferir o log do dia e o gate no topo do run_vixradar_varredura.ps1.'
            }
            Write-Log "ERRO 9006: $name exit=$code sob provider bloqueado - gate nao cortou (deveria ser 86)."
            continue
        }
        Write-Log "AGUARDANDO 1o ciclo no regime bloqueado: $name LastResult=$code e de antes do bloqueio, nao e violacao."
        $ok++
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

    # ORDEM1 (2026-08-27): este bloco ficava DEPOIS do "Pula benignos" logo abaixo,
    # que faz `continue` para code 0/267009. A condicao `$staleHours -and $code -in
    # $BenignCodes` era portanto inalcancavel desde que nasceu (staleness 02/08,
    # pulo de benignos 16/07): o unico caso que ela existe para pegar, task que nao
    # rodou com LastTaskResult=0 congelado, nunca chegava aqui. Precisa vir ANTES.
    # Staleness check: tasks que nao rodaram no periodo esperado. Roda mesmo quando
    # LastTaskResult=0, porque o que importa aqui e que a task NAO EXECUTOU, nao que a
    # ultima execucao falhou. Matinal 01/08 nao rodou e ninguem viu porque o codigo de
    # saida da ultima execucao bem-sucedida (31/07) era 0.
    $staleHours = $null
    $staleMsg = ''
    # MOTOR1: as tres rotinas so chegam aqui com o motor Task Scheduler ativo (antes disso
    # o bloco GuardedDisabled faz continue e estas entradas eram codigo morto). Horarios do
    # regime revertido de 01/09: noturna seg-sex 18h05, matinal diaria 10h06, verificacao
    # 11h03 e 19h15 (o ultimo disparo do dia decide a staleness).
    $dailyTasks = @{
        'VIXRadar-Noturno'            = @{ hours = 18; weekdays = $true  }
        'VIXRadar-Matinal'            = @{ hours = 10; weekdays = $false }
        'VIXRadar-Coleta-Volatilidade' = @{ hours = 17; weekdays = $false }
        'VIXRadar-Export-Historico'   = @{ hours = 20; weekdays = $false }
        'VIXRadar-Verificacao-Async'  = @{ hours = 19; weekdays = $false }
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
    # WEEKLY1 (2026-08-27): mesma ideia do $dailyTasks, para cadencia semanal. Aqui
    # "faltou um ciclo" nao e "passou de 24h", e sim "a ultima ocorrencia prevista ja
    # venceu e o lastRun e anterior a ela".
    #
    # Motivo: $dailyTasks so cobre VIXRadar-*, todas diarias. As tres tasks do Site
    # rodam em dias fixos da semana e nao tinham cobertura nenhuma de staleness, entao
    # uma semana inteira pulada apareceria como LastTaskResult=0 congelado da execucao
    # anterior, sem nada sinalizando. Auditoria de 27/08/2026 nao encontrou nenhuma
    # ocorrencia real desse tipo, os logs agendados batem com o calendario previsto.
    # Isto e cobertura preventiva do mesmo buraco que a ORDEM1 acima destrava.
    $weeklyTasks = @{
        'Szuchmacher-AgendaAgent'        = @{ days = @('Sunday', 'Monday', 'Thursday'); hour = 8 }
        'Szuchmacher-MacroAgent'         = @{ days = @('Friday');                       hour = 18 }
        'Szuchmacher-AgendaMacro-Claude' = @{ days = @('Friday');                       hour = 7 }
    }
    if (-not $staleHours -and $weeklyTasks.ContainsKey($name)) {
        $wcfg = $weeklyTasks[$name]
        $now = Get-Date
        # Ocorrencia prevista mais recente que ja venceu, com 2h de graca, olhando no
        # maximo 7 dias para tras. Sem a graca o monitor das 07:00 acusaria a task das
        # 08:00 do mesmo dia como atrasada em todo dia previsto.
        $ultimaPrevista = $null
        for ($d = 0; $d -le 7; $d++) {
            $dia = $now.Date.AddDays(-$d)
            if ($wcfg.days -notcontains [string]$dia.DayOfWeek) { continue }
            $prevista = $dia.AddHours($wcfg.hour)
            if ($prevista.AddHours(2) -le $now) { $ultimaPrevista = $prevista; break }
        }
        if ($ultimaPrevista -and $lastRun -lt $ultimaPrevista) {
            $staleHours = [Math]::Round(($now - $lastRun).TotalHours, 1)
            $staleMsg = ("nao rodou no ciclo semanal esperado (previsto " +
                         $ultimaPrevista.ToString('yyyy-MM-dd HH:mm') +
                         ", ultimo ha ${staleHours}h)")
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
# MOTOR1 (2026-09-02, regime revertido em 01/09): noturna seg-sex 18h05 (a matinal e diaria,
# 10h06). A verificacao entrou como rotina vigiada: dois drenos locais por dia (11h03 e
# 19h15), entao dia util com menos de 2 FIM: e janela pulada.
$RotinasVigiadas = @(
    @{ nome = 'vixradar-noturno'; rotulo = 'VIXRadar-Noturno (entrega)'; hora = 18; diasUteis = $true;  minSubmit = 90 },
    @{ nome = 'vixradar-matinal'; rotulo = 'VIXRadar-Matinal (entrega)'; hora = 10; diasUteis = $false; minSubmit = 12 },
    @{ nome = 'vixradar-verificacao-async'; rotulo = 'VIXRadar-Verificacao-Async (entrega)'; rotuloCurto = 'Verificacao-Async'; hora = 19; diasUteis = $true; requerApenasLog = $true; minFim = 2 },
    # SENTINELA-DIAPERDIDO1: apontado 29/08, medido falso positivo (sabado, task so
    # Seg-Sex). Ultimo slot 17:55. Evidencia = log do dia util + FIM: (0 analises no dia
    # e legitimo). Logica na lib vixradar-watchdog.ps1.
    @{ nome = 'vixradar-sentinela'; rotulo = 'VIXRadar-Sentinela (entrega)'; rotuloCurto = 'Sentinela'; hora = 18; diasUteis = $true; requerApenasLog = $true },
    # AGENDASEM-TRAVA1 (30/08): ate aqui a AgendaSemanal so era julgada pelo LastTaskResult
    # do Scheduler. LastTaskResult velho numa rotina de 2x/semana fica visualmente igual a
    # rotina falhando todo dia, e foi assim que a falha unica da quarta 26/08 foi lida pelas
    # auditorias como "morta ha 3 dias". A execucao morreu por reboot da maquina no meio do
    # lote 3 (Kernel-Power 109 e 577 as 22:16:27 e 22:16:29, exit 0x40010004), deixando log
    # sem FIM:. Agora ha evidencia de entrega por log, ancorada na janela real da rotina
    # (domingo E quarta, DaysOfWeek=9), e a linha do erro nomeia a data da janela cobrada.
    @{ nome = 'vixradar-agenda-semanal'; rotulo = 'VIXRadar-AgendaSemanal (entrega)'; rotuloCurto = 'AgendaSemanal'; hora = 22; diasPermitidos = @('Sunday','Wednesday'); requerApenasLog = $true }
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
    # AGENDASEM-TRAVA1 (30/08): o calculo do alvo era duplicado aqui e na lib, e o
    # test-sentinela-watchdog.ps1 provava a versao da lib enquanto producao rodava esta
    # copia. Guarda que nao exercita o codigo do pipeline nao e guarda. Agora e a mesma
    # funcao nos dois lados, que era a intencao declarada no cabecalho da lib.
    $alvo = Get-AlvoEntregaRotina -Agora $agoraR -Hora $rot.hora -DiasUteis ([bool]$rot.diasUteis) -DiasPermitidos $rot.diasPermitidos
    $alvoTxt = $alvo.ToString('yyyy-MM-dd')
    $logRot  = Join-Path $RotinasLogDir ($rot.nome + '_' + $alvo.ToString('yyyyMMdd') + '.log')

    # CLAUDE-FREE-MIGRATION: provider bloqueado => esta rotina nao entrega de proposito, e a
    # vigilancia normal de entrega (FIM:/ledger) so geraria 9001 falso todo dia. O que prova
    # que o executor rodou o ciclo e a linha canonica BLOQUEADO_SEM_PROVIDER no log do dia,
    # gravada pelo gate antes de qualquer auth/claude. Entrega normal no mesmo dia (ex.:
    # matinal 10h entregue e provider setado a tarde) tambem conta como ciclo executado.
    # Log ausente OU sem nenhum dos dois = executor nao rodou: gate ausente, task desligada
    # ou script quebrou antes do gate. Fail-closed: vira 9001, nunca silencio.
    if ($LlmBloqueado -and ($BloqueadasLog -contains $rot.nome)) {
        $txtRot = ''
        if (Test-Path $logRot) { try { $txtRot = Get-Content $logRot -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } catch { $txtRot = '' } }
        $rodouBlq = ($txtRot -match 'BLOQUEADO_SEM_PROVIDER') -or ($txtRot -match '(?m)(?<!SHADOW_)FIM:') -or ((Get-VixEmissoresUnicos $txtRot) -ge 1)
        if ($rodouBlq) {
            Write-Log "ROTINA BLOQUEADA esperado: $($rot.rotulo) | $alvoTxt executor rodou o ciclo (sentinel ou entrega)"
            $ok++
        } else {
            Write-Log "ROTINA SEM EXECUCAO (provider bloqueado): $($rot.rotulo) | $alvoTxt log sem BLOQUEADO_SEM_PROVIDER nem entrega"
            $erros += [ordered]@{
                task    = $rot.rotulo
                code    = 9001
                codeHex = '0x2329'
                lastRun = "$alvoTxt (ciclo esperado)"
                ageDays = [int]((Get-Date).Date - $alvo).Days
                script  = $logRot
                reason  = "$alvoTxt sem BLOQUEADO_SEM_PROVIDER nem entrega no log: executor nao rodou o ciclo (task desligada, gate ausente ou script quebrou antes do gate)"
            }
        }
        continue
    }

    # SENTINELA-DIAPERDIDO1 (falso positivo medido 30/08): trigger-driven, 0 analises no dia e legitimo.
    # Evidencia de entrega = log do dia util + linha FIM: (rodou ao menos uma vez ate o
    # fim). Logica na lib vixradar-watchdog.ps1 para o test-sentinela-watchdog.ps1 provar
    # as duas pontas com a MESMA funcao da producao. Entra no sumario, no estado.json,
    # no backlog e no email exatamente como as irmas.
    if ($rot.requerApenasLog) {
        $minFimRot = 1
        if ($rot.minFim) { $minFimRot = [int]$rot.minFim }
        $stSent = Test-EntregaPorLog -Alvo $alvo -LogDir $RotinasLogDir -Prefixo $rot.nome -Rotulo $rot.rotuloCurto -MinFim $minFimRot
        $logRot  = $stSent.logPath
        $motivoR = $stSent.motivo
        $submitOk = $stSent.submitOk
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
        } else {
            Write-Log "ROTINA OK: $($rot.rotulo) | $alvoTxt execucoes_com_fim=$submitOk"
            $ok++
        }
        continue
    }

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
# MOTOR1 (2026-09-02): dois sinais que so existem nos logs das rotinas.
# 9004 ALERTA_AUTH: uma rotina escalou para a chave paga ou ficou sem credencial. Urgente,
#      nunca deduplicado, entra no topo da tabela.
# 9005 CIRCUITO_ABERTO: o circuito de custo do dia (lib vixradar-custo.ps1) fechou a margem.
# A linha CUSTO_DIA entra no log e no rodape do e-mail como informacao.
# ---------------------------------------------------------------------------
$custoLinhas = @()
if ($Escopo -ne 'Site') {
    $diasAuth = @((Get-Date).Date.AddDays(-1), (Get-Date).Date)
    foreach ($a in @(Get-VixAlertasAuth -RotinasLogDir $RotinasLogDir -Dias $diasAuth)) {
        Write-Log ("ALERTA_AUTH em " + $a.rotina + " " + $a.dia + ": " + $a.linha)
        $erros += [ordered]@{
            task    = ($a.rotina + ' (auth)')
            code    = 9004
            codeHex = '0x232C'
            lastRun = $a.dia
            ageDays = 0
            script  = $a.log
            reason  = ('ALERTA_AUTH: ' + $a.linha)
        }
    }
    try {
        $custoCfgM = Get-VixCustoConfig $RotinasLogDir
        foreach ($d in $diasAuth) {
            $c = Get-VixCustoDia $RotinasLogDir $d.ToString('yyyyMMdd') $custoCfgM
            $custoLinhas += $c.linha
            Write-Log $c.linha
            if ($c.circuito_aberto) {
                $erros += [ordered]@{
                    task    = 'CUSTO_DIA (circuito)'
                    code    = 9005
                    codeHex = '0x232D'
                    lastRun = $d.ToString('yyyy-MM-dd')
                    ageDays = 0
                    script  = (Join-Path $RotinasLogDir 'custo-config.json')
                    reason  = ('CIRCUITO_ABERTO: ' + $c.linha)
                }
            }
        }
    } catch { Write-Log ("AVISO: custo do dia nao calculado - " + $_.Exception.Message) }
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
                    lastRun       = [string]$p.Value.lastRun
                    reportedAt    = [string]$p.Value.reportedAt
                    escalated     = [bool]$p.Value.escalated
                }
            }
        }
    } catch {
        Write-Log "AVISO: estado.json ilegivel, reiniciando - $($_.Exception.Message)"
    }
}
# Copia do estado ANTES desta rodada: e contra ela que o dedup decide o que e novo.
$estadoAnterior = @{}
foreach ($k in @($estado.firstSeen.Keys)) { $estadoAnterior[$k] = $estado.firstSeen[$k] }

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

    # MONITOR-PROJETOMISTO1: reportedAt fica do primeiro dia em que este (code, lastRun) foi
    # visto; mudou code ou lastRun, e erro novo e o carimbo reinicia.
    $reportedAt = $hojeIso
    if ($estadoAnterior.ContainsKey($tname)) {
        $pa = $estadoAnterior[$tname]
        if ($pa.reportedAt -and ([string]$pa.lastCode -eq [string]$e.code) -and ([string]$pa.lastRun -eq [string]$e.lastRun)) { $reportedAt = [string]$pa.reportedAt }
    }
    $estado.firstSeen[$tname] = @{
        firstDetected = $first
        lastCode      = [long]$e.code
        lastSeen      = $hojeIso
        lastRun       = [string]$e.lastRun
        reportedAt    = $reportedAt
        escalated     = [bool]$e2['escalated']
    }
}
$erros = $errosComIdade
$sel = Select-ErrosParaEmail -Erros $erros -EstadoAnterior $estadoAnterior -HojeIso $hojeIso
Write-Log ("Dedup do e-mail: novos=" + @($sel.novos).Count + " escalados=" + @($sel.escalados).Count + " persistentes=" + @($sel.persistentes).Count)

# Remove do estado erros que sumiram (limpeza)
$chavesRemover = @()
foreach ($k in @($estado.firstSeen.Keys)) {
    if (-not $tasksComErroHoje.ContainsKey($k)) { $chavesRemover += $k }
}
foreach ($k in $chavesRemover) { $estado.firstSeen.Remove($k) }

if ($DryRun) {
    Write-Log 'DRYRUN: estado.json NAO gravado'
} else {
    try {
        $estadoOut = [ordered]@{
            updated   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
            firstSeen = $estado.firstSeen
        }
        $estadoOut | ConvertTo-Json -Depth 5 | Set-Content -Path $EstadoFile -Encoding UTF8
    } catch {
        Write-Log "AVISO: falha ao gravar estado.json - $($_.Exception.Message)"
    }
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
if ((Test-Path $BacklogFile) -and -not $DryRun) {
    try {
        $bl = Get-Content $BacklogFile -Raw -Encoding UTF8 -ErrorAction Stop
        # Escopo VIX mantem o marcador legado; os outros escopos escrevem bloco proprio.
        $markerStart = if ($Escopo -eq 'VIX') { '<!-- AUTO-MONITOR-START -->' } else { '<!-- AUTO-MONITOR-START:' + $Escopo + ' -->' }
        $markerEnd   = if ($Escopo -eq 'VIX') { '<!-- AUTO-MONITOR-END -->' } else { '<!-- AUTO-MONITOR-END:' + $Escopo + ' -->' }
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
if ($LlmBloqueado) {
    Write-Log ("PROVIDER BLOQUEADO (" + $LlmProvider + "): rotinas LLM paradas por design na Fase A (CLAUDE-FREE-MIGRATION). Exit 86 contado como esperado; entrega normal nao esperada ate haver provider (Fase B).")
}

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
# MONITOR-PROJETOMISTO1: e-mail so com erro NOVO ou ESCALADO (ou -ForcarEmail). Erro com o
# mesmo (task, code, lastRun) de um dia anterior e persistente: vai na secao propria, nao
# dispara envio. Medido: 27 a 30/08 o mesmo 0x40010004 de um unico reboot gerou 4 e-mails.
$nNovos = @($sel.novos).Count; $nEsc = @($sel.escalados).Count; $nPers = @($sel.persistentes).Count
$assuntoEmail = 'VIX Radar [' + $Escopo + '] - ' + $nNovos + ' nova(s), ' + $nEsc + ' escalada(s), ' + $nPers + ' persistente(s)'
$deveEnviar = ($nNovos -gt 0 -or $nEsc -gt 0 -or $ForcarEmail)
if ($DryRun) {
    Write-Log ('DRYRUN: e-mail ' + $(if ($SendEmail -and $deveEnviar) { 'SERIA enviado' } else { 'NAO seria enviado' }) + ' | assunto=' + $assuntoEmail)
}
if ($SendEmail -and $deveEnviar -and -not $DryRun) {
    try {
        $credScript = Join-Path $VixRoot 'api\Get-VixAdminCredential.ps1'
        if (-not (Test-Path $credScript)) { throw "credencial ausente: $credScript" }
        $adminSenha = & $credScript -AsPlainText
        if (-not $adminSenha) { throw 'Get-VixAdminCredential.ps1 devolveu vazio' }

        $linhaTr = {
            param($e)
            $idade = if ($null -ne $e.ageDaysFromFirst) { ('' + $e.ageDaysFromFirst + 'd desde ' + $e.firstDetected) } else { '-' }
            return ('<tr><td>' + $e.task + '</td><td>' + $e.code + ' (' + $e.codeHex + ')</td><td>' + $e.lastRun + '</td><td>' + $idade + '</td><td>' + $e.reason + '</td><td>' + $e.script + '</td></tr>')
        }
        $cab = '<tr><th>Task</th><th>Exit</th><th>Ultima execucao</th><th>Idade</th><th>Motivo</th><th>Script</th></tr>'
        $tabAtiva = ''
        foreach ($e in @($sel.novos)) { $tabAtiva += (& $linhaTr $e) }
        foreach ($e in @($sel.escalados)) { $tabAtiva += (& $linhaTr $e) }
        $tabPers = ''
        foreach ($e in @($sel.persistentes)) { $tabPers += (& $linhaTr $e) }
        $estiloTab = '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;font-family:sans-serif;font-size:13px">'
        $html = '<h2>VIX Radar [' + $Escopo + '] - falha em task agendada</h2>' +
                '<p>' + $nNovos + ' nova(s) e ' + $nEsc + ' escalada(s) na maquina ' + $env:COMPUTERNAME + ' (motor: ' + $MotorAtual + '). ' + $nPers + ' persistente(s) ja reportada(s) antes.</p>' +
                $(if ($tabAtiva) { '<h3>Novos e escalados</h3>' + $estiloTab + $cab + $tabAtiva + '</table>' } else { '<p>Sem erro novo nesta rodada (envio forcado).</p>' }) +
                $(if ($tabPers) { '<h3>Persistentes (ja reportados, sem mudanca)</h3>' + $estiloTab + $cab + $tabPers + '</table>' } else { '' }) +
                $(if ($custoLinhas.Count -gt 0) { '<p style="font-family:monospace;font-size:12px">' + ($custoLinhas -join '<br>') + '</p>' } else { '' }) +
                '<p>Warnings nesta rodada: ' + $warnings.Count + '. Relatorio completo em ' + $ErrFile + '</p>'

        $payload = @{
            action       = 'email_enviar'
            admin_senha  = $adminSenha
            assunto      = $assuntoEmail
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
