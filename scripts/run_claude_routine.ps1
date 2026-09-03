# run_claude_routine.ps1 - Runner generico Claude Code para scheduled-tasks.
# ASCII puro (powershell.exe 5.1). Hardenizado 2026-08-02 com pre-flight de
# ambiente + probe WebSearch (TASK-18, TASK-19 do pacote de recuperacao pos-27/07).
param(
    [Parameter(Mandatory)]
    [string]$RoutineId,
    [switch]$SkipWeekend,
    [switch]$SkipHolidayB3,
    [switch]$SkipPreFlight,
    # INCIDENTE-FRESHNESS2 (03/09/2026): politica de 429 session limit da sonda
    # WebSearch. 'ChavePaga' (default) espera o reset ate o teto e so entao
    # escala para VIXRADAR_ANTHROPIC_API_KEY como contingencia. 'Nenhum' desliga
    # a contingencia (usado na execucao de recuperacao real, decisao do
    # operador: nesta execucao especifica nao gastar chave paga).
    [ValidateSet('ChavePaga', 'Nenhum')]
    [string]$Fallback429 = 'ChavePaga',
    # Instante em que a TASK (nao este processo) comecou a rodar. retry-vixradar.ps1
    # e o proprio entry point da task do Task Scheduler, entao ele passa o proprio
    # StartTime aqui. Chamada manual/direta usa o default (este processo comecou
    # agora), que nunca aciona a guarda de margem abaixo.
    [datetime]$TaskInicio = (Get-Process -Id $PID).StartTime
)

$ErrorActionPreference = 'Continue'

$ScheduledRoot = 'C:\Users\User\.claude\scheduled-tasks'
$VixRoot       = 'E:\Diretorio\Claude\Monitoramento de Credito'
$SiteRoot      = 'E:\Diretorio\Claude\FREQUENTE\Site\site-producao'
$LibDir        = Join-Path $VixRoot 'scripts\lib'
$LogDir        = Join-Path $VixRoot 'logs\routines'
$DateTag       = Get-Date -Format 'yyyyMMdd'
$CleanupScript = Join-Path $VixRoot 'scripts\cleanup-rotina-artifacts.ps1'
$AmbientCheck  = Join-Path $LibDir 'vixradar-ambient-check.ps1'
$ClaudeAuth    = Join-Path $LibDir 'vixradar-claude-auth.ps1'
$RunnerArgsLib = Join-Path $LibDir 'vixradar-runner-args.ps1'
# INCIDENTE-FRESHNESS2 (A3): ~/.claude/mcp-config.json nunca existiu nesta
# maquina (medido 03/09/2026). Sem ele, --strict-mcp-config ficava sem efeito
# e o processo carregava os MCPs do usuario inteiros. logs/routines/mcp-empty.json
# ja existe e e usado pela verificacao async com o mesmo proposito.
$McpConfig     = Join-Path $env:USERPROFILE '.claude\mcp-config.json'
if (-not (Test-Path -LiteralPath $McpConfig)) {
    $McpConfig = Join-Path $LogDir 'mcp-empty.json'
}

# AGENDASEM-CAUSA1 (2026-08-18, FASE 2): 'vixradar-agenda-semanal' REMOVIDA deste catalogo.
# Naquela epoca este runner subia o claude -p com --tools 'WebSearch,WebFetch' quando
# RequiresWebSearch=true - essa flag SUBSTITUIA o conjunto de ferramentas, nao somava, entao
# o Bash desaparecia. A SKILL.md desta rotina mandava o proprio modelo rodar curl.exe contra
# o Worker. Sem shell, os logs de 2026-08-10 e 2026-08-16 mostram o modelo relatando "nao
# tenho shell" e "nao consigo executar curl", mas o wrapper gravava FIM: concluido com exit 0
# do mesmo jeito - calendario trimestral ficou parado silenciosamente por pelo menos 2
# execucoes (20 emissores com atualizado_em:null confirmado ao vivo em producao).
# INCIDENTE-FRESHNESS2 (03/09/2026): o MESMO defeito (--tools como allowlist, nao soma)
# derrubou a noturna/matinal via retry-vixradar.ps1 - o relancamento saia exit 0 sem
# nenhum submit. Corrigido para as duas: Get-VixRunnerClaudeArgs (lib/vixradar-runner-args.ps1)
# usa '--tools default' + '--permission-mode dontAsk' + '--allowedTools' fail-closed, e a
# linha de fecho ('RUNNER_FIM', mais abaixo) parou de se chamar 'FIM: concluido' para nao
# parecer entrega. A agenda-semanal segue FORA deste catalogo por motivo diferente e ainda
# valido: tem wrapper dedicado em scripts/run_vixradar_agenda_semanal.ps1 (mesmo desenho de
# scripts/run_vixradar_verificacao_async.ps1, o PowerShell faz toda a I/O com o Worker e o
# claude -p so pesquisa e devolve JSON), invocado direto pela task VIXRadar-AgendaSemanal.
# Nao reative esta entrada no catalogo generico sem decisao explicita.
$Catalog = @{
    'atualizar-agenda-macro-szuchmacher' = @{
        Skill             = Join-Path $ScheduledRoot 'atualizar-agenda-macro-szuchmacher\SKILL.md'
        ProjectRoot       = $SiteRoot
        AddDirs           = @($SiteRoot, $ScheduledRoot)
        LogPrefix         = 'agenda-macro-szuchmacher'
        Model             = $null
        RequiresWebSearch = $false
    }
    # RETRY-VIX (2026-08-17): as rotinas noturna e matinal migraram para sessoes
    # agendadas do Claude Desktop, que entram em idle no meio do cascade e matam
    # a rotina sem rastro. O retry via retry-vixradar.ps1 relanca a skill por
    # aqui quando o log do dia nao tem FIM valido. O lock de 3h da propria
    # skill protege contra duplicata com execucao Desktop ainda viva.
    'vixradar-noturno' = @{
        Skill             = Join-Path $ScheduledRoot 'vixradar-noturno\SKILL.md'
        ProjectRoot       = $VixRoot
        AddDirs           = @((Join-Path $VixRoot 'scripts'), $ScheduledRoot)
        LogPrefix         = 'vixradar-noturno'
        Model             = $null
        RequiresWebSearch = $true
    }
    'vixradar-matinal' = @{
        Skill             = Join-Path $ScheduledRoot 'vixradar-matinal\SKILL.md'
        ProjectRoot       = $VixRoot
        AddDirs           = @((Join-Path $VixRoot 'scripts'), $ScheduledRoot)
        LogPrefix         = 'vixradar-matinal'
        Model             = $null
        RequiresWebSearch = $true
    }
}

if (-not $Catalog.ContainsKey($RoutineId)) {
    Write-Error "RoutineId desconhecido: $RoutineId"
    exit 2
}

$cfg = $Catalog[$RoutineId]
$LogFile = Join-Path $LogDir ($cfg.LogPrefix + '_' + $DateTag + '.log')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Safe([string]$msg) {
    try { Write-Host $msg -ErrorAction Stop } catch { }
}

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Safe $line
    # LOGLOCK1-REC (2026-07-24): backoff exponencial + fallback file com PID.
    # Lock persistente por OneDrive/SearchIndexer pode durar minutos. Se todas as
    # tentativas falharem, escreve em arquivo alternativo para nao perder linha.
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                $fallbackFile = ([regex]::Replace($LogFile, '\.log$', "_fallback_$pid.log"))
                Write-Safe "FALHA Write-Log ($i tentativas), fallback: $fallbackFile - $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Safe "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

# --- Pre-flight de ambiente (TASK-18, 2026-08-02) ---
# Dot-source das libs de guarda. Se ausentes, seguir sem abortar (nao vamos quebrar
# rotina por falta de lib, mas logamos o aviso).
$temAmbientCheck = $false
$temClaudeAuth   = $false
$temRunnerArgs   = $false
if (Test-Path -LiteralPath $AmbientCheck) {
    try { . $AmbientCheck; $temAmbientCheck = $true } catch { Write-Log "AVISO: dot-source $AmbientCheck falhou: $_" }
} else { Write-Log "AVISO: $AmbientCheck ausente" }
if (Test-Path -LiteralPath $ClaudeAuth) {
    try { . $ClaudeAuth; $temClaudeAuth = $true } catch { Write-Log "AVISO: dot-source $ClaudeAuth falhou: $_" }
} else { Write-Log "AVISO: $ClaudeAuth ausente" }
if (Test-Path -LiteralPath $RunnerArgsLib) {
    try { . $RunnerArgsLib; $temRunnerArgs = $true } catch { Write-Log "AVISO: dot-source $RunnerArgsLib falhou: $_" }
} else { Write-Log "AVISO: $RunnerArgsLib ausente" }

# ROUTINE_API_KEY: le do escopo User (nunca em argumento de linha de comando).
# Usada so para alertar o admin (notificar_rotina) se o pre-flight abortar; o
# POST real de submit e feito pela propria skill via $env:ROUTINE_API_KEY, que
# ja chega ao processo filho por heranca normal de variavel de ambiente User.
$routineKeyAlerta = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
if (-not $routineKeyAlerta) { $routineKeyAlerta = $env:ROUTINE_API_KEY }

# INCIDENTE-FRESHNESS2 (A3): margem de seguranca contra o ExecutionTimeLimit
# PT4H da task Szuchmacher-RetryVixNoturno/Matinal. Sem isso, uma espera de 429
# perto do teto de 120 min somada a uma rotina de ate ~2h podia estourar o
# limite da task no MEIO de um lote, sem log de fecho. Aborta ANTES de gastar
# qualquer token se a TASK (nao este processo) ja estiver rodando ha mais de
# 220 min (20 min de folga dentro do PT4H). $TaskInicio vem de retry-vixradar.ps1
# (proprio entry point da task); chamada manual usa o default e nunca aciona isto.
$decorridoMin = ((Get-Date) - $TaskInicio).TotalMinutes
$MargemTaskMin = 220
if ($decorridoMin -gt $MargemTaskMin) {
    Write-Log ('ERRO PRE-FLIGHT: task rodando ha ' + [Math]::Round($decorridoMin, 1) + ' min, perto do limite PT4H. Abortando antes de comecar.')
    if ($routineKeyAlerta -and $temClaudeAuth -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
        $null = Send-VixRoutineAlert -Rotina $RoutineId -Motivo ('ERRO PRE-FLIGHT: task com ' + [Math]::Round($decorridoMin, 1) + ' min de execucao, perto do limite PT4H - abortado antes de comecar') -RoutineKey $routineKeyAlerta
    }
    exit 8
}

if (-not $SkipPreFlight) {
    # 1. Ambiente: detectar roteamento para agregador de LLM (incidente 27/07)
    if ($temAmbientCheck) {
        try {
            $violacao = Test-VixClaudeAmbienteLimpo
            if ($violacao) {
                Write-Log "AVISO PRE-FLIGHT: ambiente contaminado - $violacao"
                Write-Log 'RECUPERACAO: injetando env vars Anthropic para neutralizar contaminacao.'
                # Sobrescreve roteamento de agregador com valores oficiais Anthropic.
                # Remove-Item elimina do bloco de ambiente; SetEnvironmentVariable
                # blinda contra leitura de registro pelo binario nativo claude.exe.
                $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
                Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
                Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
                Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
                Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
                Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
                [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
                [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', '', 'Process')
                [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User')
                [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'User')
                $env:CLAUDE_CODE_SUBAGENT_MODEL = 'claude-sonnet-5'
                Write-Log 'RECUPERACAO: env vars Anthropic injetadas. A rotina continua.'
            } else {
                Write-Log 'PRE-FLIGHT: ambiente limpo (sem roteamento de agregador)'
            }
        } catch {
            Write-Log "AVISO: pre-flight ambiente falhou (nao abortando): $_"
        }
    }

    # 2. WebSearch probe com politica de 429 (INCIDENTE-FRESHNESS2, A2): classifica
    # a falha, espera o reset real ate um teto quando for limite de sessao da
    # assinatura, e so entao considera chave paga como contingencia. Nunca mais
    # converte todo 429 em "WebSearch indisponivel" (era o que o retry das 21:30
    # de 02/09 fazia, sem esperar os 70 min ate o reset real).
    if ($cfg.RequiresWebSearch -and $temAmbientCheck -and $temClaudeAuth) {
        try {
            Write-Log 'PRE-FLIGHT: sondando WebSearch...'
            $preflightResult = Invoke-VixWebSearchPreflight -McpConfigFile $McpConfig -Rotina $RoutineId -RoutineKey $routineKeyAlerta -Fallback429 $Fallback429
            if (-not $preflightResult.Ok) {
                Write-Log ('ABORTANDO: pre-flight de busca reprovado (motivo=' + $preflightResult.Motivo + ')')
                exit $preflightResult.ExitCode
            }
            if ($preflightResult.Escalou) {
                Write-Log 'PRE-FLIGHT: WebSearch funcional (via chave paga, contingencia de 429)'
            } else {
                Write-Log 'PRE-FLIGHT: WebSearch funcional'
            }
        } catch {
            Write-Log "AVISO: probe WebSearch falhou (nao abortando): $_"
        }
    }

    # 3. Ferramentas headless (INCIDENTE-FRESHNESS2, A6, decisao do operador
    # 03/09/2026): prova real, com o CLI de verdade e a MESMA linha de comando
    # que o Passo 4 vai usar, de que PowerShell/Bash, Read, Write, Agent e
    # WebSearch estao disponiveis E autorizados sem prompt pendurado. Roda so
    # depois do WebSearch ja confirmado funcional (passo 2), para nao gastar
    # este teste quando a causa e so credencial/rede. Custo: um subagente com
    # uma busca trivial, poucos milhares de tokens Haiku.
    if ($cfg.RequiresWebSearch -and $temAmbientCheck -and $temRunnerArgs) {
        try {
            Write-Log 'PRE-FLIGHT: sondando ferramentas headless (shell, leitura, escrita, subagente, busca)...'
            $streamArgs = Get-VixRunnerClaudeArgs -Cfg $cfg -McpConfigFile $McpConfig -OutputFormat 'stream-json'
            $headlessResult = Test-VixHeadlessTools -ClaudeArgsStreamJson $streamArgs -ProjectRoot $cfg.ProjectRoot
            if (-not $headlessResult.Ok) {
                $motivoFalha = if ($headlessResult.Erro) { $headlessResult.Erro }
                    elseif ($headlessResult.ToolsFaltando.Count -gt 0) { 'ferramentas indisponiveis: ' + ($headlessResult.ToolsFaltando -join ', ') }
                    elseif ($headlessResult.PermissionDenials.Count -gt 0) { 'ferramentas negadas: ' + (($headlessResult.PermissionDenials | ConvertTo-Json -Compress)) }
                    else { 'prova incompleta (PS=' + $headlessResult.ProvaPS + ' Leitura=' + $headlessResult.ProvaLeitura + ' Escrita=' + $headlessResult.ProvaEscrita + ' Busca=' + $headlessResult.ProvaBusca + ')' }
                Write-Log ('ERRO PRE-FLIGHT: ferramentas headless indisponiveis ou negadas - ' + $motivoFalha)
                Write-Log 'ABORTANDO: sonda headless reprovada (risco de rodar a skill sem shell/subagente/busca)'
                if ($routineKeyAlerta -and $temClaudeAuth -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
                    $null = Send-VixRoutineAlert -Rotina $RoutineId -Motivo ('ERRO PRE-FLIGHT: ferramentas headless indisponiveis ou negadas - ' + $motivoFalha) -RoutineKey $routineKeyAlerta
                }
                exit 6
            }
            Write-Log 'PRE-FLIGHT: ferramentas headless confirmadas (shell, leitura, escrita, subagente, busca)'
        } catch {
            Write-Log "AVISO: sonda de ferramentas headless falhou (nao abortando): $_"
        }
    }
} else {
    Write-Log 'PRE-FLIGHT: suprimido por -SkipPreFlight'
}

$hoje = Get-Date
if ($SkipWeekend -and $hoje.DayOfWeek -in 'Saturday', 'Sunday') {
    Write-Log 'SKIP: fim de semana'
    exit 0
}
if ($SkipHolidayB3) {
    $feriados = @(
        '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
        '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
    )
    if ($feriados -contains $hoje.ToString('yyyy-MM-dd')) {
        Write-Log 'SKIP: feriado B3'
        exit 0
    }
}

if (Test-Path $CleanupScript) {
    try { Write-Log ('Cleanup: ' + (& $CleanupScript -KeepDays 7)) } catch { }
}

if (-not (Test-Path $cfg.Skill)) {
    Write-Log ('ERRO: SKILL ausente ' + $cfg.Skill)
    exit 1
}

$prompt = Get-Content $cfg.Skill -Raw -Encoding UTF8
if ($RoutineId -eq 'vixradar-agenda-semanal') {
    $routineKey = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if (-not $routineKey) { $routineKey = $env:ROUTINE_API_KEY }
    if (-not $routineKey) { Write-Log 'ERRO: ROUTINE_API_KEY ausente'; exit 3 }
    $env:ROUTINE_API_KEY = $routineKey
    # Nunca enviar ao Claude uma chave literal que tenha ficado em uma definicao antiga.
    $keyPattern = '(?i)(\\?"routine_key\\?"\s*:\s*\\?")[^"\\]+(\\?")'
    $prompt = [regex]::Replace($prompt, $keyPattern, {
        param($m)
        $m.Groups[1].Value + '$env:ROUTINE_API_KEY' + $m.Groups[2].Value
    })
}
if ($prompt -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
    $prompt = $Matches[1].Trim()
}

$header = "Execute AGORA a rotina $RoutineId. Sem pedir confirmacao.`n`n"
$footer = "`n`nRegras: Lei Zero; nao gravar artefatos em testing/; resuma resultado ao final."
$fullPrompt = $header + $prompt + $footer

# INCIDENTE-FRESHNESS2 (A3, endurecido depois do gate adversarial de 03/09): a
# guarda de margem la em cima roda ANTES do pre-flight e por isso mede ~0 min,
# era decorativa. A que vale e esta, DEPOIS do pre-flight: se houve espera de
# 429 (ate 120 min), o tempo ja gasto entra na conta. Com ~2h de execucao
# tipica da noturna, passar de 220 min aqui significa estourar o PT4H da task
# no meio de um lote, sem linha de fecho. Melhor nao comecar.
$decorridoAgoraMin = ((Get-Date) - $TaskInicio).TotalMinutes
if ($decorridoAgoraMin -gt $MargemTaskMin) {
    Write-Log ('ERRO PRE-FLIGHT: apos o pre-flight ja se passaram ' + [Math]::Round($decorridoAgoraMin, 1) + ' min (teto ' + $MargemTaskMin + '). Abortando antes do primeiro lote para nao ser morto no meio pelo PT4H da task.')
    if ($routineKeyAlerta -and $temClaudeAuth -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
        $null = Send-VixRoutineAlert -Rotina $RoutineId -Motivo ('ERRO PRE-FLIGHT: ' + [Math]::Round($decorridoAgoraMin, 1) + ' min gastos antes do primeiro lote (espera de 429 + sondas), sem margem para o PT4H da task') -RoutineKey $routineKeyAlerta
    }
    exit 8
}

Write-Log ('INICIO: ' + $RoutineId)

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

Push-Location $cfg.ProjectRoot
try {
    # Auth: aplicar a credencial decidida pelo pre-flight (assinatura, token
    # longevo, ou chave paga se o Passo 2 escalou por 429). Chamar de novo aqui
    # e barato (so seta env vars) e garante que o modo mais recente vale para a
    # invocacao real, nao so para a sonda.
    if ($temClaudeAuth) {
        try { Set-VixClaudeAuthEnv } catch { Write-Log "AVISO: Set-VixClaudeAuthEnv falhou: $_" }
    }
    # CLAUDE_CODE_USE_POWERSHELL_TOOL: so no ambiente deste processo (herdado
    # pelo claude filho), nunca em escopo User. Sem isto o CLI no Windows nao
    # tem certeza de rodar comandos via PowerShell nativo em vez de Git Bash.
    $env:CLAUDE_CODE_USE_POWERSHELL_TOOL = '1'

    # INCIDENTE-FRESHNESS2 (A3): linha de comando montada por
    # Get-VixRunnerClaudeArgs (--tools default, --permission-mode dontAsk,
    # --allowedTools fail-closed), nunca mais --tools WebSearch,WebFetch (que
    # era allowlist e tirava PowerShell/Bash/Read/Write/Agent da skill -
    # AGENDASEM-CAUSA1 ja documentava esse mesmo defeito para a agenda semanal).
    if ($temRunnerArgs) {
        $claudeArgs = Get-VixRunnerClaudeArgs -Cfg $cfg -McpConfigFile $McpConfig
    } else {
        Write-Log 'AVISO: lib de args ausente, usando fallback minimo (sem allowedTools/dontAsk).'
        $claudeArgs = @('-p', '--permission-mode', 'bypassPermissions', '--output-format', 'text')
        foreach ($dir in $cfg.AddDirs) {
            if (Test-Path $dir) { $claudeArgs += @('--add-dir', $dir) }
        }
        if ($cfg.RequiresWebSearch) { $claudeArgs += @('--tools', 'default') }
    }

    # RETRY1 (2026-07-27): retry com backoff + fallback Haiku na ultima tentativa.
    # Mesmo padrao do Invoke-ClaudeBatch nos scripts noturno/matinal.
    $retryModel = if ($cfg.Model) { $cfg.Model } else { $null }
    $retryDelays = @(0, 30, 60)
    $out = $null; $exit = 1
    for ($attempt = 0; $attempt -lt $retryDelays.Count; $attempt++) {
        if ($attempt -gt 0) {
            $delay = $retryDelays[$attempt]
            Write-Log ('RETRY: tentativa ' + ($attempt+1) + '/' + $retryDelays.Count + ' aguardando ' + $delay + 's')
            Start-Sleep -Seconds $delay
        }
        $attemptArgs = $claudeArgs.Clone()
        if ($attempt -eq $retryDelays.Count - 1 -and $attemptArgs -notcontains '--model') {
            Write-Log ('RETRY: fallback para Haiku (ultima tentativa)')
            $attemptArgs += @('--model', 'claude-haiku-4-5-20251001')
        }
        $previousEap = $ErrorActionPreference
        try {
            # Stderr nativo nao vira excecao antes de lermos o exit code.
            $ErrorActionPreference = 'Continue'
            $out = $fullPrompt | & claude @attemptArgs 2>&1
            $exit = $LASTEXITCODE
        } catch {
            $out = @($_.Exception.Message)
            $exit = 1
        } finally {
            $ErrorActionPreference = $previousEap
        }
        if ($exit -eq 0) { break }
    }
    if ($out) { $out | ForEach-Object { Write-Log ('CLAUDE: ' + $_) } }
    if ($exit -ne 0) {
        Write-Log ('ERRO: claude exit ' + $exit + ' (esgotadas ' + $retryDelays.Count + ' tentativas com backoff)')
        exit $exit
    }
    # INCIDENTE-FRESHNESS2 (A3, condicao do COO): exit 0 do claude NAO prova que a
    # skill entregou (19/08: relancamento da matinal saiu exit 0 em 1m54s sem
    # nenhum submit, porque --tools WebSearch,WebFetch tinha tirado o shell dela).
    # Para as rotinas vixradar-*, a linha de fecho passa a dizer explicitamente
    # que exit 0 nao e FIM de rotina - quem julga entrega e sempre o ledger OK|
    # (retry-vixradar.ps1, Test-VixLedgerEntregueNaJanela). Rotinas fora do
    # catalogo vixradar-* (ex.: atualizar-agenda-macro-szuchmacher) nao tem esse
    # ledger e mantem a linha antiga.
    if ($RoutineId -like 'vixradar-*') {
        Write-Log 'RUNNER_FIM: claude exit 0 (entrega e julgada pelo ledger OK| da skill, nao por este exit code)'
    } else {
        Write-Log 'FIM: concluido'
    }
} finally {
    Pop-Location
}