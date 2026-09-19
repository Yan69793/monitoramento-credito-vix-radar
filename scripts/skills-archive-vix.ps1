# skills-archive-vix.ps1 - arquiva skills fora da whitelist. Reversivel.
#
# Substitui o wrapper antigo que so chamava C:\Users\User\skills-archive-vix.ps1,
# arquivo que nao existe mais (a correcao de junho tinha sido desfeita e o script
# perdido). Agora a logica vive aqui e nao depende de nada fora do repo.
#
# Uso:    pwsh -File scripts/skills-archive-vix.ps1
# Conferir sem mover: pwsh -File scripts/skills-archive-vix.ps1 -WhatIf
# Voltar tudo:        pwsh -File scripts/skills-restore.ps1
# Medir:              pwsh -File scripts/skills-verify-tokens.ps1
#
# ASCII-only de proposito. O Gate 1 exige BOM UTF-8 em .ps1 com acento, e nao usar
# acento e mais simples que depender do BOM. Sem ternario e sem '??' para valer no PS 5.1.

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$HomeDir     = 'C:\Users\User'

# Governanca global (CLAUDE.md global) + manutencao de skills + fluxos recorrentes.
$KeepGlobal = @(
    'humanizer', 'task-observer', 'prompt-refinery', 'melhorar-e-executar', 'model-router',
    'skill-creator', 'writing-skills', 'find-skills',
    'ghost', 'ODDA', 'godmode',
    'brainstorming', 'writing-plans', 'executing-plans', 'using-superpowers',
    'systematic-debugging', 'verification-before-completion', 'test-driven-development',
    'subagent-driven-development', 'dispatching-parallel-agents',
    'requesting-code-review', 'receiving-code-review', 'using-git-worktrees',
    'selective-git-gate', 'windows-compatibility', 'session-hygiene', 'consolidate-memory',
    'encerrar-sessao', 'workspace-memory', 'retomar-sessao',
    'copywriting', 'node', 'technical-analyst', 'vcp-screener', 'system-connector',
    'observer-sessions', 'desktop-commander-guide', 'local-llm-expert', 'ollama-optimizer'
)

# Fonte da verdade do projeto: .claude/SKILLS-ROUTER.md mais o fluxo Awwwards.
$KeepProject = @(
    'vix-radar-briefing', 'sprite-health', 'vix-radar-audit', 'vix-radar-general-audit',
    'repor-varredura', 'vixradar-varredura', 'vix-radar-next-steps', 'vix-radar-predictive',
    'vix-radar-session-briefing', 'vix-radar-system-council',
    'wrangler', 'workers-best-practices', 'cloudflare',
    'ODDA', 'ghost', 'godmode', '299', 'artifact', 'execute-plan',
    'writing-plans', 'executing-plans', 'systematic-debugging', 'using-superpowers',
    'awwwards-vix-radar', 'awwwards-estudo', 'awwwards-maestro', 'impeccable', 'web-perf',
    'auditoria', 'radar-credito-privado',
    'humanizer', 'prompt-refinery', 'task-observer', 'model-router', 'melhorar-e-executar',
    'skill-creator', 'writing-skills', 'find-skills',
    'selective-git-gate', 'using-git-worktrees', 'verification-before-completion',
    'brainstorming', 'test-driven-development', 'subagent-driven-development',
    'dispatching-parallel-agents', 'requesting-code-review', 'receiving-code-review',
    'implement', 'finishing-a-development-branch', 'durable-objects', 'shared',
    'session-hygiene', 'windows-compatibility', 'consolidate-memory'
)

$Targets = @(
    @{ Active = (Join-Path $HomeDir '.agents\skills');     Archive = (Join-Path $HomeDir '.agents\_off-skills');            Keep = $KeepGlobal  }
    @{ Active = (Join-Path $HomeDir '.claude\skills');     Archive = (Join-Path $HomeDir '.claude\_off-skills');            Keep = $KeepGlobal  }
    @{ Active = (Join-Path $HomeDir '.grok\skills');       Archive = (Join-Path $HomeDir '.grok\_off-skills');              Keep = $KeepGlobal  }
    @{ Active = (Join-Path $ProjectRoot '.agents\skills'); Archive = (Join-Path $HomeDir '.agents\_off-skills-vix-projeto'); Keep = $KeepProject }
)

Write-Output '=== skills-archive-vix ==='
$movedTotal = 0

foreach ($t in $Targets) {
    if (-not (Test-Path -LiteralPath $t.Active)) {
        Write-Output ("ausente: " + $t.Active)
        continue
    }
    if (-not (Test-Path -LiteralPath $t.Archive)) {
        if ($PSCmdlet.ShouldProcess($t.Archive, 'criar pasta de arquivo')) {
            New-Item -ItemType Directory -Path $t.Archive -Force | Out-Null
        }
    }
    $moved = 0
    $kept  = 0
    foreach ($d in Get-ChildItem -LiteralPath $t.Active -Directory -ErrorAction SilentlyContinue) {
        if ($t.Keep -contains $d.Name) { $kept++; continue }
        $dest = Join-Path $t.Archive $d.Name
        if (Test-Path -LiteralPath $dest) { $dest = Join-Path $t.Archive ($d.Name + '_dup') }
        if ($PSCmdlet.ShouldProcess($d.FullName, ('arquivar em ' + $t.Archive))) {
            Move-Item -LiteralPath $d.FullName -Destination $dest -ErrorAction Continue
            if ($?) { $moved++ }
        } else {
            $moved++
        }
    }
    $movedTotal += $moved
    Write-Output ("{0,-56} mover={1,4} manter={2,3}" -f $t.Active, $moved, $kept)
}

Write-Output ("total a mover: " + $movedTotal)
Write-Output 'Reinicie a sessao para o corte valer no system prompt.'
exit 0
