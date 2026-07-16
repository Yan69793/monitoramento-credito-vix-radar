# skills-audit.ps1 — alerta se skills crescerem além do limite seguro
# Uso: pwsh -File scripts/skills-audit.ps1

$ErrorActionPreference = 'Stop'

$Limits = @{
    GlobalSkillsMB = 50
    GlobalSkillMdKB = 500
    ProjectSkillsMB = 5
    ProjectSkillMdKB = 100
}

function Get-SkillsStats {
    param([string]$Root)

    if (-not (Test-Path $Root)) {
        return [PSCustomObject]@{ Root = $Root; Exists = $false }
    }

    $allFiles = Get-ChildItem $Root -Recurse -File -ErrorAction SilentlyContinue
    $skillMd = $allFiles | Where-Object { $_.Name -eq 'SKILL.md' }
    $totalBytes = ($allFiles | Measure-Object Length -Sum).Sum
    $mdBytes = ($skillMd | Measure-Object Length -Sum).Sum

    [PSCustomObject]@{
        Root = $Root
        Exists = $true
        SkillFolders = (Get-ChildItem $Root -Directory).Count
        TotalMB = [math]::Round($totalBytes / 1MB, 2)
        SkillMdKB = [math]::Round($mdBytes / 1KB, 1)
        SkillMdCount = $skillMd.Count
    }
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$checks = @(
    Get-SkillsStats -Root (Join-Path $projectRoot '.claude' 'skills')
    Get-SkillsStats -Root (Join-Path $projectRoot '.grok' 'skills')
    Get-SkillsStats -Root 'C:\Users\User\.grok\skills'
    Get-SkillsStats -Root 'C:\Users\User\.claude\_off-skills'
)

$alerts = @()

foreach ($c in $checks) {
    if (-not $c.Exists) { continue }

    $isProject = $c.Root -like "*Monitoramento de Credito*"
    $maxMB = if ($isProject) { $Limits.ProjectSkillsMB } else { $Limits.GlobalSkillsMB }
    $maxMdKB = if ($isProject) { $Limits.ProjectSkillMdKB } else { $Limits.GlobalSkillMdKB }

    if ($c.TotalMB -gt $maxMB) {
        $alerts += "ALERTA: $($c.Root) = $($c.TotalMB) MB (limite $maxMB MB)"
    }
    if ($c.SkillMdKB -gt $maxMdKB) {
        $alerts += "ALERTA: SKILL.md em $($c.Root) = $($c.SkillMdKB) KB (limite $maxMdKB KB)"
    }
}

Write-Output "=== Skills Audit $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
$checks | Where-Object { $_.Exists } | Format-Table Root, SkillFolders, TotalMB, SkillMdKB, SkillMdCount -AutoSize

if ($alerts.Count -eq 0) {
    Write-Output "OK: dentro dos limites."
    exit 0
}

foreach ($a in $alerts) { Write-Output $a }
exit 1