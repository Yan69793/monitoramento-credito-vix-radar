# run_claude_routine.ps1 - Runner generico Claude Code para scheduled-tasks.
# ASCII puro (powershell.exe 5.1). Hardenizado 2026-08-02 com pre-flight de
# ambiente + probe WebSearch (TASK-18, TASK-19 do pacote de recuperacao pos-27/07).
param(
    [Parameter(Mandatory)]
    [string]$RoutineId,
    [switch]$SkipWeekend,
    [switch]$SkipHolidayB3,
    [switch]$SkipPreFlight
)

$ErrorActionPreference = 'Continue'

$ScheduledRoot = 'C:\Users\User\.claude\scheduled-tasks'
$VixRoot       = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$SiteRoot      = 'E:\Diretorio\Claude\FREQUENTE\Site\site-producao'
$LibDir        = Join-Path $VixRoot 'scripts\lib'
$LogDir        = Join-Path $VixRoot 'logs\routines'
$DateTag       = Get-Date -Format 'yyyyMMdd'
$CleanupScript = Join-Path $VixRoot 'scripts\cleanup-rotina-artifacts.ps1'
$AmbientCheck  = Join-Path $LibDir 'vixradar-ambient-check.ps1'
$ClaudeAuth    = Join-Path $LibDir 'vixradar-claude-auth.ps1'
$McpConfig     = Join-Path $env:USERPROFILE '.claude\mcp-config.json'

# AGENDASEM-CAUSA1 (2026-08-18, FASE 2): 'vixradar-agenda-semanal' REMOVIDA deste catalogo.
# Este runner sobe o claude -p com --tools 'WebSearch,WebFetch' quando RequiresWebSearch=true
# (ver ~linha 229) - essa flag SUBSTITUI o conjunto de ferramentas, nao soma, entao o Bash
# desaparecia. A SKILL.md desta rotina mandava o proprio modelo rodar curl.exe contra o Worker.
# Sem shell, os logs de 2026-08-10 e 2026-08-16 mostram o modelo relatando "nao tenho shell" e
# "nao consigo executar curl", mas o wrapper gravava FIM: concluido com exit 0 do mesmo jeito -
# calendario trimestral ficou parado silenciosamente por pelo menos 2 execucoes (20 emissores
# com atualizado_em:null confirmado ao vivo em producao). A rotina agora tem wrapper dedicado
# em scripts/run_vixradar_agenda_semanal.ps1 (mesmo desenho de scripts/run_vixradar_verificacao_async.ps1:
# o PowerShell faz toda a I/O com o Worker, o claude -p so pesquisa e devolve JSON), invocado
# direto pela task VIXRadar-AgendaSemanal, sem passar por este catalogo generico. Nao reative
# esta entrada sem corrigir a causa raiz (Bash ausente) primeiro.
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
if (Test-Path -LiteralPath $AmbientCheck) {
    try { . $AmbientCheck; $temAmbientCheck = $true } catch { Write-Log "AVISO: dot-source $AmbientCheck falhou: $_" }
} else { Write-Log "AVISO: $AmbientCheck ausente" }
if (Test-Path -LiteralPath $ClaudeAuth) {
    try { . $ClaudeAuth; $temClaudeAuth = $true } catch { Write-Log "AVISO: dot-source $ClaudeAuth falhou: $_" }
} else { Write-Log "AVISO: $ClaudeAuth ausente" }

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

    # 2. WebSearch probe: validar que a ferramenta de busca funciona (incidente 27/07)
    if ($cfg.RequiresWebSearch -and $temAmbientCheck -and $temClaudeAuth) {
        try {
            Write-Log 'PRE-FLIGHT: sondando WebSearch...'
            $probeOk = Test-VixWebSearchProbe -McpConfigFile $McpConfig
            if (-not $probeOk) {
                Write-Log 'ERRO PRE-FLIGHT: WebSearch indisponivel'
                Write-Log 'ABORTANDO: busca indisponivel (risco de submeter analise sem cobertura)'
                exit 5
            }
            Write-Log 'PRE-FLIGHT: WebSearch funcional'
        } catch {
            Write-Log "AVISO: probe WebSearch falhou (nao abortando): $_"
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

Write-Log ('INICIO: ' + $RoutineId)

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

Push-Location $cfg.ProjectRoot
try {
    $claudeArgs = @('-p', '--permission-mode', 'bypassPermissions', '--output-format', 'text')
    foreach ($dir in $cfg.AddDirs) {
        if (Test-Path $dir) { $claudeArgs += @('--add-dir', $dir) }
    }

    # Auth + tools: aplicar credencial decidida pela lib de auth e garantir que
    # WebSearch/WebFetch estao disponiveis (incidente 27/07: sem --tools explicito,
    # o CLI pode herdar configuracao de ferramentas quebrada do settings.json).
    if ($temClaudeAuth) {
        try { Set-VixClaudeAuthEnv } catch { Write-Log "AVISO: Set-VixClaudeAuthEnv falhou: $_" }
    }
    if ($cfg.RequiresWebSearch) {
        $claudeArgs += @('--tools', 'WebSearch,WebFetch')
        if (Test-Path -LiteralPath $McpConfig) {
            $claudeArgs += @('--strict-mcp-config', '--mcp-config', $McpConfig)
        }
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
    Write-Log 'FIM: concluido'
} finally {
    Pop-Location
}