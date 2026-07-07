# Limpa artefatos temporarios das rotinas (disco) — prompts, planos, testing/, lotes
param(
    [int]$KeepDays = 7,
    [switch]$Aggressive,
    [string]$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
)

$ErrorActionPreference = 'SilentlyContinue'
$LogDir = Join-Path $ProjectRoot 'logs\routines'
$cutoff = (Get-Date).AddDays(-$KeepDays)
$removed = 0
$freed = 0L

function Remove-IfStale($path) {
    if (-not (Test-Path $path)) { return }
    $item = Get-Item $path
    if ($item.LastWriteTime.Date -eq (Get-Date).Date) { return }
    # Um diretorio pode conservar mtime antigo mesmo contendo arquivo alterado hoje.
    # Em modo agressivo, preservar o diretorio inteiro se houver qualquer artefato do dia.
    if ($item.PSIsContainer -and (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime.Date -eq (Get-Date).Date } | Select-Object -First 1)) { return }
    if ($Aggressive -or $item.LastWriteTime -lt $cutoff) {
        $sz = if ($item.PSIsContainer) {
            (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        } else { $item.Length }
        if ($null -eq $sz) { $sz = 0 }
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) {
            $script:removed++
            $script:freed += $sz
        }
    }
}

# Prompts e planos (principal fonte de acumulo)
$patterns = @(
    (Join-Path $LogDir 'noturno_*.txt'),
    (Join-Path $LogDir 'noturno_plano_*.json'),
    (Join-Path $LogDir 'noturno_prompt_*.txt'),
    (Join-Path $LogDir 'matinal_*.txt'),
    (Join-Path $LogDir 'matinal_plano_*.json'),
    (Join-Path $LogDir 'matinal_prompt_*.txt'),
    (Join-Path $ProjectRoot 'claude-vixradar-noturno-*.prompt.txt'),
    (Join-Path $ProjectRoot 'ctx*.json'),
    (Join-Path $ProjectRoot 'in.json'),
    (Join-Path $ProjectRoot 'out*.json'),
    (Join-Path $ProjectRoot 'tmp_in.json')
)
foreach ($pat in $patterns) {
    Get-ChildItem $pat -ErrorAction SilentlyContinue | ForEach-Object { Remove-IfStale $_.FullName }
}

# Diretorios de lote / replay (gitignored)
foreach ($dir in @('testing', '.noturno_lote', '.noturno_tmp', '.matinal_tmp', '_lote_tmp')) {
    Remove-IfStale (Join-Path $ProjectRoot $dir)
}

# Logs antigos (manter metricas JSON)
Get-ChildItem $LogDir -Filter 'vixradar-*.log' -ErrorAction SilentlyContinue | ForEach-Object { Remove-IfStale $_.FullName }
if ($Aggressive) {
    Get-ChildItem $LogDir -Filter '*_metrics_*.json' -ErrorAction SilentlyContinue | ForEach-Object { Remove-IfStale $_.FullName }
}

Write-Output "cleanup: $removed item(ns), $([Math]::Round($freed/1MB, 1)) MB liberados (keep=$KeepDays d, aggressive=$Aggressive)"
