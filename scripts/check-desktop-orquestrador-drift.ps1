# check-desktop-orquestrador-drift.ps1
# ORQUESTRADOR1 (auditoria 2026-08-15): o caminho real de producao das rotinas
# matinal/noturno/verificacao e o SKILL.md das sessoes agendadas do Claude Desktop
# (~\.claude\scheduled-tasks\vixradar-*\), que ficava FORA do repo. O repo agora
# guarda copia canonica em routines\claude-desktop\ e este script compara as duas.
# Drift = a automacao real mudou sem passar pelo git, ou o repo mudou sem a rotina
# acompanhar. Ambos sao perigosos.
#
# Uso: pwsh ./scripts/check-desktop-orquestrador-drift.ps1
# Exit: 0 = sincronizado | 1 = drift | 2 = diretorio do Desktop inacessivel
#
# ASCII puro de proposito (sem BOM), ErrorActionPreference Continue, exit real.

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$DesktopRoot = Join-Path $env:USERPROFILE '.claude\scheduled-tasks'
$RepoRoot = Join-Path $Root 'routines\claude-desktop'

$pares = @(
    @{ Desktop = 'vixradar-matinal\SKILL.md';                 Repo = 'matinal\SKILL.md' },
    @{ Desktop = 'vixradar-noturno\SKILL.md';                 Repo = 'noturno\SKILL.md' },
    @{ Desktop = 'vixradar-noturno\BATCH.md';                 Repo = 'noturno\BATCH.md' },
    @{ Desktop = 'vixradar-noturno\noturno-batch-haiku.md';   Repo = 'noturno\noturno-batch-haiku.md' },
    @{ Desktop = 'vixradar-noturno\noturno-batch-sonnet.md';  Repo = 'noturno\noturno-batch-sonnet.md' },
    @{ Desktop = 'vixradar-noturno\ROUTINES-CLOUD.md';        Repo = 'noturno\ROUTINES-CLOUD.md' },
    @{ Desktop = 'vixradar-verificacao-async\SKILL.md';       Repo = 'verificacao-async\SKILL.md' }
)

if (-not (Test-Path $DesktopRoot)) {
    Write-Output 'ERRO: diretorio de scheduled-tasks do Claude Desktop inacessivel.'
    exit 2
}

$drift = 0
foreach ($p in $pares) {
    $d = Join-Path $DesktopRoot $p.Desktop
    $r = Join-Path $RepoRoot $p.Repo
    if (-not (Test-Path $r)) {
        Write-Output ('AUSENTE NO REPO: ' + $p.Repo)
        $drift++
        continue
    }
    if (-not (Test-Path $d)) {
        Write-Output ('AUSENTE NO DESKTOP: ' + $p.Desktop + ' (rotina pode ter sido removida)')
        $drift++
        continue
    }
    $hd = (Get-FileHash $d -Algorithm SHA256).Hash
    $hr = (Get-FileHash $r -Algorithm SHA256).Hash
    if ($hd -ne $hr) {
        Write-Output ('DRIFT: ' + $p.Desktop + ' != routines\claude-desktop\' + $p.Repo)
        $drift++
    }
}

if ($drift -gt 0) {
    Write-Output ('DRIFT TOTAL: ' + $drift + ' arquivo(s) divergente(s). Sincronizar: copiar do Desktop para o repo (se a mudanca for valida) e commitar, ou reverter o Desktop.')
    exit 1
}
Write-Output 'OK: orquestradores do Claude Desktop sincronizados com routines\claude-desktop\.'
exit 0
