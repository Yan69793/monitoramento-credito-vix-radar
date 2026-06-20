# run_claude_routine.ps1 — Runner generico Claude Code para scheduled-tasks
param(
    [Parameter(Mandatory)]
    [string]$RoutineId,
    [switch]$SkipWeekend,
    [switch]$SkipHolidayB3
)

$ErrorActionPreference = 'Stop'

$ScheduledRoot = 'C:\Users\User\.claude\scheduled-tasks'
$VixRoot       = 'E:\Diretorio\Claude\Monitoramento de Credito'
$SiteRoot      = 'E:\Diretorio\Claude\Site\site-producao'
$FechamentoRoot = 'E:\Diretorio\Claude\relatorio-diario-mirabaud'
$LogDir        = Join-Path $VixRoot 'logs\routines'
$DateTag       = Get-Date -Format 'yyyyMMdd'
$CleanupScript = Join-Path $VixRoot 'scripts\cleanup-rotina-artifacts.ps1'

$Catalog = @{
    'vixradar-agenda-semanal' = @{
        Skill       = Join-Path $ScheduledRoot 'vixradar-agenda-semanal\SKILL.md'
        ProjectRoot = $VixRoot
        AddDirs     = @((Join-Path $VixRoot 'scripts'), $ScheduledRoot)
        LogPrefix   = 'vixradar-agenda-semanal'
        Model       = $null
    }
    'atualizar-agenda-macro-szuchmacher' = @{
        Skill       = Join-Path $ScheduledRoot 'atualizar-agenda-macro-szuchmacher\SKILL.md'
        ProjectRoot = $SiteRoot
        AddDirs     = @($SiteRoot, $ScheduledRoot)
        LogPrefix   = 'agenda-macro-szuchmacher'
        Model       = $null
    }
    'fechamento-diario-szuchmacher' = @{
        Skill       = Join-Path $ScheduledRoot 'fechamento-diario-szuchmacher\SKILL.md'
        ProjectRoot = $FechamentoRoot
        AddDirs     = @($FechamentoRoot, 'E:\Diretorio\Claude\Site\site-producao', $ScheduledRoot)
        LogPrefix   = 'fechamento-szuchmacher'
        Model       = $null
    }
}

if (-not $Catalog.ContainsKey($RoutineId)) {
    Write-Error "RoutineId desconhecido: $RoutineId"
}

$cfg = $Catalog[$RoutineId]
$LogFile = Join-Path $LogDir ($cfg.LogPrefix + '_' + $DateTag + '.log')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

$hoje = Get-Date
if ($SkipWeekend -and $hoje.DayOfWeek -in 'Saturday', 'Sunday') {
    Write-Log 'SKIP: fim de semana'
    return
}
if ($SkipHolidayB3) {
    $feriados = @(
        '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
        '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
    )
    if ($feriados -contains $hoje.ToString('yyyy-MM-dd')) {
        Write-Log 'SKIP: feriado B3'
        return
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
    if ($cfg.Model) { $claudeArgs += @('--model', $cfg.Model) }

    $out = $fullPrompt | & claude @claudeArgs 2>&1
    $exit = $LASTEXITCODE
    if ($out) { $out | ForEach-Object { Write-Log ('CLAUDE: ' + $_) } }
    if ($exit -ne 0) {
        Write-Log ('ERRO: claude exit ' + $exit)
        exit $exit
    }
    Write-Log 'FIM: concluido'
} finally {
    Pop-Location
}