# vixradar-runner-args.ps1 - monta a linha de comando do claude -p headless para as
# rotinas do catalogo de run_claude_routine.ps1 (INCIDENTE-FRESHNESS2, A3).
# Extraida para lib propria para ser testavel isolada, sem o param() obrigatorio
# de run_claude_routine.ps1 (scripts/test-headless-tools.ps1, teste I).
#
# CORRECAO 03/09/2026 (decisao do operador, fail-closed): a linha antiga passava
# --tools WebSearch,WebFetch para as rotinas noturno/matinal, que EXIGEM shell
# (Passo 0 lock, Passo 1 health, Passo 10 POST). --tools e allowlist no CLI
# instalado ("claude --help": "Specify the list of available tools from the
# built-in set... 'default' to use all tools"), entao aquela linha REMOVIA
# PowerShell, Bash, Read, Write e Agent da sessao. A skill ficava sem shell e o
# runner gravava "FIM: concluido" com exit 0 mesmo sem nenhum submit (mesmo
# defeito documentado em AGENDASEM-CAUSA1 para a agenda semanal, e medido de
# novo no relancamento da matinal em 19/08, 1m54s sem ledger).
#
# Fail-closed com --permission-mode dontAsk: "Claude Code denies anything not
# in your permissions.allow rules or the read-only command set" (doc oficial).
# --allowedTools pre-aprova SO o que a skill usa, nada mais.
$VixRunnerAllowedTools = 'PowerShell,Bash,Read,Write,Edit,Agent,WebSearch,WebFetch'

function Get-VixRunnerClaudeArgs {
    param(
        [Parameter(Mandatory)][hashtable]$Cfg,
        [string]$McpConfigFile,
        [string]$OutputFormat = 'text'
    )
    $claudeArgs = @('-p', '--permission-mode', 'dontAsk', '--allowedTools', $VixRunnerAllowedTools, '--output-format', $OutputFormat)
    if ($OutputFormat -eq 'stream-json') { $claudeArgs += '--verbose' }
    foreach ($dir in $Cfg.AddDirs) {
        if (Test-Path $dir) { $claudeArgs += @('--add-dir', $dir) }
    }
    if ($Cfg.RequiresWebSearch) {
        $claudeArgs += @('--tools', 'default')
        if ($McpConfigFile -and (Test-Path -LiteralPath $McpConfigFile)) {
            $claudeArgs += @('--strict-mcp-config', '--mcp-config', $McpConfigFile)
        }
    }
    return $claudeArgs
}
