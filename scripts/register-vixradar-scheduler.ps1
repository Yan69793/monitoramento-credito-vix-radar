# register-vixradar-scheduler.ps1 — atalho para registro completo VIX + Szuchmacher
param(
    [switch]$Remove,
    [switch]$Status,
    [switch]$RunNowMatinal,
    [switch]$RunNowNoturno
)

$All = Join-Path $PSScriptRoot 'register-all-routines-scheduler.ps1'

if ($Remove) {
    & $All -Remove
    return
}
if ($Status) {
    & $All -Status
    return
}

& $All

if ($RunNowMatinal) {
    & (Join-Path $PSScriptRoot 'run_vixradar_matinal_claude.ps1')
}
if ($RunNowNoturno) {
    & (Join-Path $PSScriptRoot 'run_vixradar_noturno_claude.ps1')
}