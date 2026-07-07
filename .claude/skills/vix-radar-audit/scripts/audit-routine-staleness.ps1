param(
    [string]$ApiUrl = 'https://api.vixradar.com',
    [string]$StuckDate,
    [double]$MaxAgeHours = 24,
    [string]$RoutineKey = $env:ROUTINE_API_KEY,
    [string]$RoutineSkill = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md'
)

$ErrorActionPreference = 'Stop'

if (-not $RoutineKey -and (Test-Path -LiteralPath $RoutineSkill)) {
    $raw = Get-Content -LiteralPath $RoutineSkill -Raw -Encoding UTF8
    if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { $RoutineKey = $Matches[1] }
}
if (-not $RoutineKey) { throw 'ROUTINE_API_KEY ausente no ambiente e na scheduled task.' }

$body = @{
    action = 'listar_plano_rotina'
    routine_key = $RoutineKey
    modo = 'noturno'
} | ConvertTo-Json -Compress

$plan = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
if ($plan.ok -ne $true) { throw ('listar_plano_rotina falhou: ' + $plan.erro) }

$items = @($plan.emissores)
$stale = @($items | Where-Object { [double]$_.horas_stale -ge $MaxAgeHours })
$stuck = if ($StuckDate) {
    @($items | Where-Object { ('' + $_.contexto_historico) -match [regex]::Escape($StuckDate) })
} else { @() }
$max = if ($items.Count) { ($items | Measure-Object horas_stale -Maximum).Maximum } else { $null }
$oldest = @($items | Sort-Object horas_stale -Descending | Select-Object -First 10 empresa, horas_stale, contexto_historico)
$healthy = ($items.Count -eq 103 -and $stale.Count -eq 0 -and $stuck.Count -eq 0)

[ordered]@{
    ok = $healthy
    api_ok = $plan.ok
    worker_version = $plan.worker_version
    checked_at = (Get-Date).ToString('o')
    total = $items.Count
    max_age_hours_allowed = $MaxAgeHours
    stale_24h = $stale.Count
    max_stale_hours = $max
    stuck_date = $StuckDate
    presos_data = $stuck.Count
    tiers = $plan.contagem_tiers
    oldest = $oldest
} | ConvertTo-Json -Depth 6

if (-not $healthy) { exit 2 }
