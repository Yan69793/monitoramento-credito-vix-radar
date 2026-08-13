# install-project-dev-skills.ps1 — execute-plan + superpowers (somente este projeto)
param(
    [switch]$Remove,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ClaudeSkills = Join-Path $ProjectRoot '.claude\skills'
$GrokSkills   = Join-Path $ProjectRoot '.grok\skills'
$GrokConfig   = Join-Path $ProjectRoot '.grok\config.toml'
$UserConfig   = 'C:\Users\User\.grok\config.toml'
$Bundled      = 'C:\Users\User\.grok\bundled\skills'
$SpCache      = 'C:\Users\User\.grok\marketplace-cache\f8a3f25821e2a56d\skills'

$ExecutePlanDirs = @(
    @{ Src = Join-Path $Bundled 'execute-plan'; Dst = Join-Path $ClaudeSkills 'execute-plan' }
    @{ Src = Join-Path $Bundled 'implement'; Dst = Join-Path $ClaudeSkills 'implement' }
    @{ Src = Join-Path $Bundled 'shared'; Dst = Join-Path $ClaudeSkills 'shared' }
)

$SuperpowersSkills = @(
    'using-superpowers', 'writing-plans', 'executing-plans', 'systematic-debugging',
    'brainstorming', 'test-driven-development', 'requesting-code-review',
    'receiving-code-review', 'verification-before-completion', 'dispatching-parallel-agents',
    'subagent-driven-development', 'using-git-worktrees', 'finishing-a-development-branch',
    'writing-skills'
)

function New-JunctionSafe($link, $target) {
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq 'Junction') { return }
        if ($DryRun) { Write-Host "DRY: remover $link"; return }
        Remove-Item $link -Recurse -Force
    }
    if ($DryRun) { Write-Host "DRY: junction $link -> $target"; return }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
}

function Copy-Tree($src, $dst) {
    if (-not (Test-Path $src)) { throw "Origem ausente: $src" }
    if ($DryRun) { Write-Host "DRY: copy $src -> $dst"; return }
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $src $dst -Recurse -Force
}

function Enable-UserSkill($name) {
    if (-not (Test-Path $UserConfig)) { return }
    $raw = Get-Content $UserConfig -Raw -Encoding UTF8
    if ($raw -notmatch '(?ms)\[skills\]\s*\r?\ndisabled\s*=\s*\[([^\]]*)\]') { return }
    $inner = $Matches[1]
    if ($inner -notmatch [regex]::Escape($name)) { return }
    $newInner = ($inner -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -and $_ -ne $name } |
        ForEach-Object { '"' + $_ + '"' }) -join ', '
    if (-not $newInner) { $newInner = '' }
    $replacement = "[skills]`ndisabled = [$newInner]"
    if ($DryRun) { Write-Host "DRY: remover '$name' de disabled em config global"; return }
    $raw = $raw -replace '(?ms)\[skills\]\s*\r?\ndisabled\s*=\s*\[[^\]]*\]', $replacement
    Set-Content $UserConfig $raw -Encoding UTF8 -NoNewline
}

if ($Remove) {
    foreach ($d in $ExecutePlanDirs) {
        if (Test-Path $d.Dst) { Remove-Item $d.Dst -Recurse -Force }
        $link = Join-Path $GrokSkills (Split-Path $d.Dst -Leaf)
        if (Test-Path $link) { Remove-Item $link -Force }
    }
    foreach ($n in $SuperpowersSkills) {
        $dst = Join-Path $ClaudeSkills $n
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        $link = Join-Path $GrokSkills $n
        if (Test-Path $link) { Remove-Item $link -Force }
    }
    if (Test-Path $GrokConfig) { Remove-Item $GrokConfig -Force }
    Write-Host 'Removido: execute-plan + superpowers do projeto'
    return
}

New-Item -ItemType Directory -Force -Path $ClaudeSkills | Out-Null
New-Item -ItemType Directory -Force -Path $GrokSkills | Out-Null

Write-Host '=== Instalando execute-plan (projeto) ===' -ForegroundColor Cyan
foreach ($d in $ExecutePlanDirs) {
    Copy-Tree $d.Src $d.Dst
    New-JunctionSafe (Join-Path $GrokSkills (Split-Path $d.Dst -Leaf)) $d.Dst
}
Enable-UserSkill 'execute-plan'
Enable-UserSkill 'implement'

Write-Host '=== Instalando superpowers skills (projeto) ===' -ForegroundColor Cyan
foreach ($n in $SuperpowersSkills) {
    $src = Join-Path $SpCache $n
    $dst = Join-Path $ClaudeSkills $n
    Copy-Tree $src $dst
    New-JunctionSafe (Join-Path $GrokSkills $n) $dst
}

$grokToml = @'
# VIX Radar — dev skills locais (execute-plan + superpowers)
# Sobrescreve ~/.grok/config.toml apenas neste repo.

[plugins]
enabled = ["superpowers"]
'@

if ($DryRun) {
    Write-Host 'DRY: escrever .grok/config.toml'
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $GrokConfig) | Out-Null
    Set-Content $GrokConfig $grokToml.Trim() -Encoding UTF8
}

Write-Host ''
Write-Host 'OK: skills instaladas no projeto' -ForegroundColor Green
Write-Host '  .claude/skills/ + junctions .grok/skills/'
Write-Host '  .grok/config.toml -> plugins.enabled superpowers'
Write-Host ''
Write-Host 'OBRIGATORIO: abrir sessao Grok NOVA neste repo para carregar skills.' -ForegroundColor Yellow
Write-Host 'Verificar: pwsh scripts/skills-verify-tokens.ps1'