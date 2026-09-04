# probe-claude-auth.ps1 - sonda do portao G4: prova em qual credencial o `claude -p` das
# rotinas se apoia, com a mesma lib e a mesma forma de invocacao do run_vixradar_varredura.ps1.
# PowerShell 5.1, ASCII puro, exit code real (chamado por driver externo ou Task Scheduler).
#
# Modos:
#   (normal)              token longevo do registro User -> esperado AUTH_MODO assinatura-token
#   -SemToken             token escondido so no processo + CLAUDE_CONFIG_DIR temporario VAZIO
#                         (o OAuth local de 24h fica fora do alcance) -> esperado modo api,
#                         ALERTA_AUTH e notificar_rotina (e-mail real, deliberado, uma vez)
#   -SemToken -SemApiKey  nada -> esperado modo nenhum, exit 5, ALERTA_AUTH, sem e-mail, sem loop
#   -SemAlerta            nunca chama notificar_rotina (teste do harness)
#
# Nao toca registro, agendamento nem Worker, alem do notificar_rotina no modo api.
# Valor de credencial nunca e impresso: so tamanho.
# Exit: 0 ok | 1 excecao | 5 sem credencial nenhuma | 7 chamada explicita recusada

param(
    [switch]$SemToken,
    [switch]$SemApiKey,
    [switch]$SemAlerta,
    [string]$Rotina = 'probe-auth',
    [string]$ModeloSonda = 'claude-haiku-4-5-20251001',
    [switch]$ForceClaude
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot   = Split-Path $PSScriptRoot -Parent
$LogDir        = Join-Path $ProjectRoot 'logs\routines'
$McpConfigFile = Join-Path $LogDir 'mcp-empty.json'
$Ts            = Get-Date -Format 'yyyyMMdd_HHmmss'
if ($SemToken -and $SemApiKey) { $Modo = 'sem-nada' } elseif ($SemToken) { $Modo = 'sem-token' } else { $Modo = 'normal' }
$LogFile    = Join-Path $LogDir ('probe-auth_' + $Ts + '_' + $Modo + '.log')
$StdoutFile = Join-Path $LogDir ('probe-auth_' + $Ts + '_' + $Modo + '_stdout.json')
$StderrFile = Join-Path $LogDir ('probe-auth_' + $Ts + '_' + $Modo + '_stderr.txt')
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
if (-not (Test-Path $McpConfigFile)) { Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8 }

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    try { Write-Host $line } catch { }
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}
function Get-Len([string]$v) { return ([string]$v).Length }
function Get-RoutineKey {
    # Mesma regra do runner (ROTA1): registro User primeiro, env depois.
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) { return $doRegistro }
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    return $null
}
function Get-Cabeca([string]$txt, [int]$max) {
    $t = ('' + $txt) -replace "[`r`n]+", ' '
    $t = $t.Trim()
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) + '...' }
    return $t
}

. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeSonda', 'Initialize-VixClaudeAuth', 'Get-VixClaudeAuthModo', 'Send-VixRoutineAlert', 'Get-VixUsageParcelas')

# CLAUDE-FREE-MIGRATION (2026-09-04): sonda diagnostica que invoca claude de verdade.
# Sem provider manual forcado, exit 86 ANTES de ler credencial, sondar ou disparar
# notificar_rotina. Para diagnosticar auth manualmente, setar VIXRADAR_LLM_PROVIDER=
# 'claude-manual' e rodar com -ForceClaude. Scheduler nunca passa -ForceClaude.
if (-not (Test-VixLlmPermiteClaude -ForceClaude:$ForceClaude)) {
    Write-Log (Get-VixLlmBloqueadoMsg 'probe-claude-auth.ps1')
    exit $VixLlmBloqueadoExit
}

Write-Log ('INICIO: probe-auth modo=' + $Modo + ' pid=' + $PID + ' ps=' + $PSVersionTable.PSVersion + ' user=' + $env:USERNAME + ' cwd=' + (Get-Location).Path)
Write-Log ('AMBIENTE registro User (so tamanho): VIXRADAR_ANTHROPIC_AUTH_TOKEN=' + (Get-Len ([Environment]::GetEnvironmentVariable('VIXRADAR_ANTHROPIC_AUTH_TOKEN', 'User'))) +
    ' VIXRADAR_ANTHROPIC_API_KEY=' + (Get-Len ([Environment]::GetEnvironmentVariable('VIXRADAR_ANTHROPIC_API_KEY', 'User'))) +
    ' CLAUDE_CODE_OAUTH_TOKEN=' + (Get-Len ([Environment]::GetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', 'User'))) +
    ' ANTHROPIC_AUTH_TOKEN=' + (Get-Len ([Environment]::GetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', 'User'))) +
    ' ANTHROPIC_API_KEY=' + (Get-Len ([Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User'))))
$herdadas = @(Get-ChildItem Env: | Where-Object { $_.Name -match '^(ANTHROPIC|CLAUDE)' } | ForEach-Object { $_.Name + '=' + (Get-Len $_.Value) })
if ($herdadas.Count -eq 0) { Write-Log 'AMBIENTE processo: nenhuma variavel ANTHROPIC*/CLAUDE* herdada' }
else { Write-Log ('AMBIENTE processo herdado (nome=tamanho): ' + ($herdadas -join ' ')) }
$credPadrao = Join-Path $env:USERPROFILE '.claude\.credentials.json'
Write-Log ('CREDENTIAL STORE padrao: ' + $credPadrao + ' existe=' + (Test-Path $credPadrao))

$CfgDir = $null
if ($SemToken) {
    $CfgDir = Join-Path $env:TEMP ('vixradar-probe-cfg-' + $Ts)
    New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
    $env:CLAUDE_CONFIG_DIR = $CfgDir
    $nArq = @(Get-ChildItem $CfgDir -Force -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Log ('ISOLAMENTO: CLAUDE_CONFIG_DIR=' + $CfgDir + ' arquivos=' + $nArq + ' credentials.json=' + (Test-Path (Join-Path $CfgDir '.credentials.json')) + ' (OAuth local de 24h fora do alcance do claude.exe deste processo)')
    function Get-VixAnthropicAuthToken { return $null }
    Write-Log 'SIMULACAO: token longevo escondido so neste processo (Get-VixAnthropicAuthToken redefinida para nulo), registro User intocado'
}
if ($SemApiKey) {
    function Get-VixAnthropicApiKey { return $null }
    Write-Log 'SIMULACAO: chave paga escondida so neste processo (Get-VixAnthropicApiKey redefinida para nulo), registro User intocado'
}

$exitCode = 0
try {
    Initialize-VixClaudeAuth -ModeloSonda $ModeloSonda -McpConfigFile $McpConfigFile | Out-Null
    $modo = Get-VixClaudeAuthModo
    Write-Log ('AUTH_MODO: ' + $modo)
    Set-VixClaudeAuthEnv
    $emUso = @()
    foreach ($n in @('CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN')) {
        $v = [Environment]::GetEnvironmentVariable($n, 'Process')
        if ($v) { $emUso += ($n + ' len=' + (Get-Len $v)) }
    }
    if ($emUso.Count -eq 0) {
        $cfgTxt = 'padrao'
        if ($env:CLAUDE_CONFIG_DIR) { $cfgTxt = $env:CLAUDE_CONFIG_DIR }
        $emUso = @('nenhuma variavel (credential store do OAuth, CLAUDE_CONFIG_DIR=' + $cfgTxt + ')')
    }
    Write-Log ('VARIAVEL_EM_USO: ' + ($emUso -join ' | ') + ' ANTHROPIC_BASE_URL=' + $env:ANTHROPIC_BASE_URL)

    if ($modo -eq 'nenhum') {
        Write-Log ('ALERTA_AUTH: sem credencial nenhuma na ' + $Rotina + ' (modo=nenhum) - nenhum lote seria disparado, sem loop')
        $exitCode = 5
    } else {
        $raw = 'responda apenas ok' | claude -p `
            --model $ModeloSonda `
            --permission-mode bypassPermissions `
            --output-format json `
            --tools 'WebSearch,WebFetch' `
            --strict-mcp-config --mcp-config $McpConfigFile `
            --setting-sources project `
            --disable-slash-commands `
            --no-session-persistence `
            --exclude-dynamic-system-prompt-sections 2>$StderrFile
        $code = $LASTEXITCODE
        $rawTxt = (@($raw) -join "`n")
        Set-Content -Path $StdoutFile -Value $rawTxt -Encoding UTF8
        $json = $null
        try {
            $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
            if ($jsonLine) { $json = $jsonLine | ConvertFrom-Json }
        } catch { Write-Log ('AVISO: stdout nao parseou como JSON: ' + $_.Exception.Message) }
        $parcelas = Get-VixUsageParcelas $json
        $isErr = ''; $res = ''; $dur = ''; $cost = ''
        if ($json) { $isErr = '' + $json.is_error; $res = Get-Cabeca ('' + $json.result) 80; $dur = '' + $json.duration_ms; $cost = '' + $json.total_cost_usd }
        Write-Log ('CLAUDE exit=' + $code + ' is_error=' + $isErr + ' result="' + $res + '" duration_ms=' + $dur + ' total_cost_usd=' + $cost + ' stdout=' + $StdoutFile)
        Write-Log ('USAGE input=' + $parcelas.input + ' output=' + $parcelas.output + ' cache_creation=' + $parcelas.cache_creation + ' cache_read=' + $parcelas.cache_read + ' trabalho=' + $parcelas.trabalho)
        if (Test-Path $StderrFile) {
            $errTxt = Get-Content $StderrFile -Raw -ErrorAction SilentlyContinue
            if ($errTxt -and $errTxt.Trim().Length -gt 0) { Write-Log ('STDERR: ' + (Get-Cabeca $errTxt 300)) } else { Write-Log 'STDERR: vazio' }
        }
        if ($code -ne 0 -or $isErr -eq 'True') { Write-Log 'ERRO: chamada explicita recusada'; $exitCode = 7 }
        if ($modo -eq 'api') {
            Write-Log ('ALERTA_AUTH: ' + $Rotina + ' escalou para chave paga (token longevo ausente ou recusado, OAuth indisponivel neste processo). Cada lote custaria dolar.')
            if ($SemAlerta) { Write-Log 'ALERTA NAO enviado (-SemAlerta)' }
            else {
                $rk = Get-RoutineKey
                $ok = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: sonda G4 escalou para chave paga (token longevo ausente/recusado e OAuth isolado) - regerar token com claude setup-token e gravar em VIXRADAR_ANTHROPIC_AUTH_TOKEN') -RoutineKey $rk
                Write-Log ('NOTIFICAR_ROTINA retorno=' + $ok)
            }
        }
    }
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message + ' | ' + $_.ScriptStackTrace)
    $exitCode = 1
} finally {
    if ($CfgDir) {
        $criados = @(Get-ChildItem $CfgDir -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($CfgDir.Length + 1) })
        $lista = ''
        if ($criados.Count -gt 0) { $lista = ' [' + ($criados -join ', ') + ']' }
        Write-Log ('ISOLAMENTO: arquivos que o claude.exe criou no CLAUDE_CONFIG_DIR temporario: ' + $criados.Count + $lista + ' credentials.json=' + (Test-Path (Join-Path $CfgDir '.credentials.json')))
        Remove-Item -Recurse -Force $CfgDir -ErrorAction SilentlyContinue
        Write-Log ('ISOLAMENTO: dir temporario removido=' + (-not (Test-Path $CfgDir)))
    }
    Write-Log ('FIM: probe-auth modo=' + $Modo + ' auth_modo=' + (Get-VixClaudeAuthModo) + ' exit=' + $exitCode)
}
exit $exitCode
