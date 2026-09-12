# skills-index.ps1 — catálogo compacto de skills (projeto + global opcional)
# Uso: pwsh -File scripts/skills-index.ps1 [-Global]

param(
    [switch]$Global
)

$ErrorActionPreference = 'Continue'
$script:SkillIndexHadErrors = $false

function Get-SkillEntry {
    param([string]$SkillDir)

    $skillMd = Join-Path $SkillDir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $skillMd -Raw -Encoding UTF8 -ErrorAction Stop
        $name = Split-Path $SkillDir -Leaf
        $desc = '(sem description)'
        $sizeKB = [math]::Round((Get-Item -LiteralPath $skillMd -ErrorAction Stop).Length / 1KB, 1)
    }
    catch {
        $script:SkillIndexHadErrors = $true
        Write-Warning ("Falha ao ler skill '{0}': {1}" -f $skillMd, $_.Exception.Message)
        return $null
    }

    if ($raw -match '(?ms)^---\s*\r?\n(.*?)\r?\n---') {
        $fm = $Matches[1]
        if ($fm -match '(?m)^name:\s*(.+)$') { $name = $Matches[1].Trim() }
        if ($fm -match '(?ms)^description:\s*>\s*\r?\n((?:\s+.+\r?\n?)+)') {
            $desc = ($Matches[1] -replace '(?m)^\s+', '' -replace '\s+', ' ').Trim()
        }
        elseif ($fm -match '(?m)^description:\s*(.+)$') {
            $desc = $Matches[1].Trim()
        }
    }

    if ($desc.Length -gt 120) { $desc = $desc.Substring(0, 117) + '...' }

    [PSCustomObject]@{
        Name = $name
        SizeKB = $sizeKB
        Description = $desc
    }
}

function Show-SkillsBlock {
    param([string]$Root, [string]$Label)

    if (-not (Test-Path $Root)) { return }

    try {
        $skillDirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop)
    }
    catch {
        $script:SkillIndexHadErrors = $true
        Write-Warning ("Falha ao enumerar skills em '{0}': {1}" -f $Root, $_.Exception.Message)
        return
    }

    $entries = @($skillDirs | ForEach-Object {
        Get-SkillEntry -SkillDir $_.FullName
    } | Where-Object { $_ -ne $null } | Sort-Object Name)

    if ($entries.Count -eq 0) { return }

    Write-Host ""
    Write-Host "=== $Label ($($entries.Count) skills) ==="
    $entries | Format-Table Name, SizeKB, Description -AutoSize | Out-String -Width 200 | Write-Host
    $totalKB = ($entries | Measure-Object SizeKB -Sum).Sum
    Write-Host "Total SKILL.md: $([math]::Round($totalKB, 1)) KB"
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$projectSkills = Join-Path (Join-Path $projectRoot '.claude') 'skills'

Show-SkillsBlock -Root $projectSkills -Label 'Projeto VIX Radar'

if ($Global) {
    Show-SkillsBlock -Root 'C:\Users\User\.claude\skills' -Label 'Global Claude'
    Show-SkillsBlock -Root 'C:\Users\User\.grok\skills' -Label 'Global Grok'
}

Write-Host ""
Write-Host "Router: .claude/SKILLS-ROUTER.md"
Write-Host "Dica: sem -Global = so projeto (~2k tokens). Com -Global = catalogo completo."

if ($script:SkillIndexHadErrors) {
    Write-Error 'Indice de skills incompleto. Corrija os avisos acima.'
    exit 1
}
