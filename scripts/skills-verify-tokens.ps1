# Verificacao pos-fix de tokens (skills no system prompt)
# Uso: pwsh -File scripts/skills-verify-tokens.ps1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$limits = @{
    HomeActiveMax = 30
    VixActiveMax = 65
    HomeTokensMax = 2500
    VixTokensMax = 5500
}

function Get-SkillMetrics($cwd) {
    Push-Location $cwd
    try {
        $json = grok inspect --json 2>&1 | Out-String
        $j = $json | ConvertFrom-Json
        $active = @($j.skills | Where-Object { -not $_.disabled })
        $chars = ($active | ForEach-Object { $_.description.Length } | Measure-Object -Sum).Sum
        [PSCustomObject]@{
            Cwd = $cwd
            Total = $j.skills.Count
            Active = $active.Count
            Project = @($active | Where-Object { $_.source.type -eq 'project' }).Count
            TokensApprox = [math]::Round($chars / 4)
            VixSkills = @(
                'sprite-health', 'vix-radar-audit', 'vix-radar-next-steps',
                'vix-radar-session-briefing', 'wrangler', 'workers-best-practices'
            )
        }
    } finally {
        Pop-Location
    }
}

function Test-VixProjectSkills($metrics) {
    Push-Location $projectRoot
    try {
        $json = grok inspect --json 2>&1 | Out-String
        $j = $json | ConvertFrom-Json
        $names = $j.skills | Where-Object { -not $_.disabled } | Select-Object -ExpandProperty name
        $required = @(
            'sprite-health', 'vix-radar-audit', 'vix-radar-next-steps',
            'vix-radar-session-briefing', 'wrangler', 'workers-best-practices'
        )
        $missing = $required | Where-Object { $_ -notin $names }
        return $missing
    } finally {
        Pop-Location
    }
}

$homeMetrics = Get-SkillMetrics 'C:\Users\User'
$vixMetrics = Get-SkillMetrics $projectRoot
$missing = Test-VixProjectSkills $vixMetrics

$alerts = @()

if ($homeMetrics.Active -gt $limits.HomeActiveMax) {
    $alerts += "HOME skills ativas $($homeMetrics.Active) > limite $($limits.HomeActiveMax)"
}
if ($homeMetrics.TokensApprox -gt $limits.HomeTokensMax) {
    $alerts += "HOME tokens~ $($homeMetrics.TokensApprox) > limite $($limits.HomeTokensMax)"
}
if ($vixMetrics.Active -gt $limits.VixActiveMax) {
    $alerts += "VIX skills ativas $($vixMetrics.Active) > limite $($limits.VixActiveMax)"
}
if ($vixMetrics.TokensApprox -gt $limits.VixTokensMax) {
    $alerts += "VIX tokens~ $($vixMetrics.TokensApprox) > limite $($limits.VixTokensMax)"
}
if ($missing.Count -gt 0) {
    $alerts += "VIX skills ausentes: $($missing -join ', ')"
}

Write-Output '=== skills-verify-tokens ==='
Write-Output "HOME: $($homeMetrics.Active)/$($homeMetrics.Total) ativas | tokens~ $($homeMetrics.TokensApprox)"
Write-Output "VIX:  $($vixMetrics.Active)/$($vixMetrics.Total) ativas | projeto $($vixMetrics.Project) | tokens~ $($vixMetrics.TokensApprox)"

$schedOk = (Test-Path 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md') -and
           (Test-Path 'C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\SKILL.md')
Write-Output "Scheduled tasks matinal/noturno: $(if ($schedOk) { 'OK' } else { 'FAIL' })"

if ($alerts.Count -eq 0) {
    Write-Output 'PASS: limites dentro do esperado'
    exit 0
}

Write-Output 'ALERTAS:'
$alerts | ForEach-Object { Write-Output "  - $_" }
Write-Output 'Acao: reiniciar sessao; conferir config.toml; nao rodar import-claude/sk sync'
exit 1