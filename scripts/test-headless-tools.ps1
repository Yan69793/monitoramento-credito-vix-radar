# test-headless-tools.ps1 - prova de duas pontas da linha de comando headless
# (INCIDENTE-FRESHNESS2, A3/A6, decisao do operador 03/09/2026). Parte I:
# Get-VixRunnerClaudeArgs isolada (sem CLI, sem custo). Parte J: Test-VixHeadlessTools
# com o CLI REAL (2 chamadas, poucos milhares de tokens Haiku na assinatura):
# a linha NOVA (--tools default + dontAsk + allowedTools) tem que passar; a
# linha ANTIGA (--tools WebSearch,WebFetch) tem que reprovar, provando que o
# defeito de 02/09 era real e que a correcao resolve. Nao altera o repo (so
# %TEMP%), conferido no fim via git status. ASCII puro, PS 5.1.
param(
    [switch]$PularCLI  # so a Parte I (rapida, sem custo), para iteracao local
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-runner-args.ps1')

# PROVIDERFIX (2026-10-14): esta suite prova o caminho do CLI Claude (Get-VixRunnerClaudeArgs e
# Test-VixHeadlessTools), que o gate CLAUDE-FREE so libera sob provider de Claude. Com o provider
# ativo hoje em `codex` (medido: User=[codex], desde 13/10), ela morria em exit 86
# (BLOQUEADO_SEM_PROVIDER, gatilho=lib-ambient-Test-VixHeadlessTools) ANTES de exercitar
# qualquer coisa - o ambiente da maquina nao e a variavel sob teste. A suite passa a declarar,
# no escopo DESTE processo e so nele, o provider do caminho que ela exercita, e restaura no fim.
$__providerOriginal = $env:VIXRADAR_LLM_PROVIDER
$env:VIXRADAR_LLM_PROVIDER = 'claude-subscription'

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

# ============================================================
Write-Host '=== I: Get-VixRunnerClaudeArgs (linha de comando, sem CLI) ==='
$cfgNoturno = @{
    AddDirs           = @('E:\Diretorio\Claude\Monitoramento de Credito\scripts', 'C:\Users\User\.claude\scheduled-tasks')
    RequiresWebSearch = $true
}
$mcpEmpty = Join-Path (Join-Path $PSScriptRoot '..') 'logs\routines\mcp-empty.json'
$argsNovos = Get-VixRunnerClaudeArgs -Cfg $cfgNoturno -McpConfigFile $mcpEmpty
$argsTexto = $argsNovos -join ' '
Write-Host ('  linha: ' + $argsTexto)
Assert ($argsNovos -contains '--tools' -and ($argsNovos[$argsNovos.IndexOf('--tools') + 1] -eq 'default')) 'I: contem --tools default'
Assert ($argsNovos -contains '--permission-mode' -and ($argsNovos[$argsNovos.IndexOf('--permission-mode') + 1] -eq 'dontAsk')) 'I: contem --permission-mode dontAsk'
Assert ($argsNovos -contains '--allowedTools') 'I: contem --allowedTools'
if ($argsNovos -contains '--allowedTools') {
    $allow = $argsNovos[$argsNovos.IndexOf('--allowedTools') + 1]
    foreach ($t in @('PowerShell', 'Bash', 'Read', 'Write', 'Edit', 'Agent', 'WebSearch', 'WebFetch')) {
        Assert ($allow -match [regex]::Escape($t)) ('I: allowedTools inclui ' + $t)
    }
}
Assert ($argsNovos -contains '--strict-mcp-config') 'I: contem --strict-mcp-config'
Assert (($argsNovos -join '|') -match [regex]::Escape('mcp-empty.json')) 'I: --mcp-config aponta para mcp-empty.json'
Assert (-not ($argsTexto -match 'bypassPermissions')) 'I: NAO contem bypassPermissions'
# A allowlist NOVA (--allowedTools) contem "WebSearch,WebFetch" como
# SUBSTRING legitima (ela pre-aprova as 8 ferramentas, WebSearch e WebFetch
# entre elas). O que nao pode existir e o valor de --tools SER a allowlist
# antiga - ja conferido acima ('--tools default'). Esta linha confere
# especificamente que --tools nao aponta para o valor antigo.
$idxTools = $argsNovos.IndexOf('--tools')
Assert ($idxTools -ge 0 -and $argsNovos[$idxTools + 1] -ne 'WebSearch,WebFetch') 'I: --tools NAO e mais a allowlist antiga WebSearch,WebFetch'

if ($PularCLI) {
    Write-Host ''
    Write-Host ('RESULTADO (so Parte I): ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
    $env:VIXRADAR_LLM_PROVIDER = $__providerOriginal
    if ($script:fal -gt 0) { exit 1 }
    exit 0
}

# ============================================================
Write-Host ''
Write-Host '=== J: Test-VixHeadlessTools com o CLI REAL (2 chamadas, custo pequeno) ==='
$gitAntes = (& git -C $PSScriptRoot\.. status --porcelain) -join "`n"

Write-Host '--- J1: linha NOVA (--tools default + dontAsk + allowedTools) tem que PASSAR ---'
$streamArgsNovos = Get-VixRunnerClaudeArgs -Cfg $cfgNoturno -McpConfigFile $mcpEmpty -OutputFormat 'stream-json'
$rJ1 = Test-VixHeadlessTools -ClaudeArgsStreamJson $streamArgsNovos -ProjectRoot (Resolve-Path (Join-Path $PSScriptRoot '..'))
Write-Host ('  Ok=' + $rJ1.Ok + ' ToolsFaltando=[' + ($rJ1.ToolsFaltando -join ',') + '] PermissionDenials=' + $rJ1.PermissionDenials.Count + ' PS=' + $rJ1.ProvaPS + ' Leitura=' + $rJ1.ProvaLeitura + ' Escrita=' + $rJ1.ProvaEscrita + ' Busca=' + $rJ1.ProvaBusca + ' Erro=' + $rJ1.Erro)

# CLI-AUSENTE1 (2026-10-14): a Parte J1 invoca o CLI Claude DE VERDADE e so pode passar com uma
# credencial Claude valida. Medido nesta maquina em 14/10: o CLI responde
# "Failed to authenticate: OAuth session expired and could not be refreshed" com 0 token
# consumido - nao ha assinatura Claude ativa (CLAUDE-FREE-MIGRATION; o provider das rotinas e
# codex desde 13/10). Sem esta guarda a suite ficava vermelha por falta de credencial, o que
# nao e defeito de codigo nem prova de nada.
#
# J1 e PULADO (condicional e nomeado). J2 NAO e pulado: a lista de ferramentas que ele julga vem
# do evento `system/init` LOCAL do CLI, emitido ANTES da autenticacao - logo J2 mede de verdade o
# classificador de disponibilidade de ferramenta sem precisar de credencial. Nunca se marca OK
# sem prova: assert pulado nao conta, assert executado conta.
$j1Pulado = $false
if ($rJ1.SemAutenticacao) {
    $j1Pulado = $true
    Write-Host ''
    Write-Host 'PULADO (J1): sonda headless nao executavel - o CLI Claude desta maquina nao autentica.'
    Write-Host ('  evidencia medida na propria sonda: ' + $rJ1.Erro)
    Write-Host '  motivo: sem assinatura Claude ativa (CLAUDE-FREE-MIGRATION); provider das rotinas = codex.'
} else {
    Assert ($rJ1.Ok -eq $true) ('J1: linha nova PASSA a sonda headless (obtido Ok=' + $rJ1.Ok + ')')
    Assert ($rJ1.ToolsFaltando.Count -eq 0) 'J1: nenhuma ferramenta faltando'
    Assert ($rJ1.PermissionDenials.Count -eq 0) 'J1: nenhuma permissao negada'
    Assert ($rJ1.ProvaPS -and $rJ1.ProvaLeitura -and $rJ1.ProvaEscrita -and $rJ1.ProvaBusca) 'J1: shell, leitura, escrita e busca via subagente confirmados'
}

Write-Host '--- J2: linha ANTIGA (--tools WebSearch,WebFetch) tem que REPROVAR ---'
$argsAntigos = @('-p', '--permission-mode', 'bypassPermissions', '--output-format', 'stream-json', '--verbose',
    '--add-dir', 'E:\Diretorio\Claude\Monitoramento de Credito\scripts', '--add-dir', 'C:\Users\User\.claude\scheduled-tasks',
    '--tools', 'WebSearch,WebFetch', '--strict-mcp-config', '--mcp-config', $mcpEmpty)
$rJ2 = Test-VixHeadlessTools -ClaudeArgsStreamJson $argsAntigos -ProjectRoot (Resolve-Path (Join-Path $PSScriptRoot '..'))
Write-Host ('  Ok=' + $rJ2.Ok + ' ToolsFaltando=[' + ($rJ2.ToolsFaltando -join ',') + '] PermissionDenials=' + $rJ2.PermissionDenials.Count + ' PS=' + $rJ2.ProvaPS + ' Leitura=' + $rJ2.ProvaLeitura + ' Escrita=' + $rJ2.ProvaEscrita + ' Busca=' + $rJ2.ProvaBusca + ' Erro=' + $rJ2.Erro)
Assert ($rJ2.Ok -eq $false) ('J2: linha antiga REPROVA a sonda headless (obtido Ok=' + $rJ2.Ok + ')')
Assert ($rJ2.ToolsFaltando.Count -gt 0) ('J2: aponta ferramenta(s) faltando (obtido [' + ($rJ2.ToolsFaltando -join ',') + '])')
Assert ($rJ2.ToolsFaltando -contains 'PowerShell/Bash') 'J2: falta especificamente PowerShell/Bash (mesmo defeito de 02/09)'

Write-Host ''
Write-Host '=== Conferindo que nada mudou no repo (git status antes == depois) ==='
$gitDepois = (& git -C $PSScriptRoot\.. status --porcelain) -join "`n"
Assert ($gitAntes -eq $gitDepois) 'git status identico antes e depois (nenhuma sonda tocou o repo)'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)' + $(if ($j1Pulado) { ', J1 PULADO (sem autenticacao no CLI)' } else { '' }))
$env:VIXRADAR_LLM_PROVIDER = $__providerOriginal
if ($script:fal -gt 0) { exit 1 }
exit 0
