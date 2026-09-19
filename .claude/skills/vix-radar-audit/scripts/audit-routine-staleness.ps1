param(
    [string]$ApiUrl = 'https://api.vixradar.com',
    [string]$StuckDate,
    [double]$MaxAgeHours = 24,
    [string]$RoutineKey = $env:ROUTINE_API_KEY,
    [string]$RoutineSkill = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md'
)

$ErrorActionPreference = 'Stop'

# Fonte real da chave hoje e a variavel de ambiente ROUTINE_API_KEY, herdada pelo
# processo. O fallback abaixo e legado da epoca em que a chave era escrita na SKILL da
# scheduled task: medido em 2026-09-18, o arquivo existe e nao casa ROUTINE_KEY nenhuma
# vez, entao quem nao tiver a variavel no ambiente vai falhar aqui, alto e claro, que e
# o comportamento correto. Nao transformar em silencio.
if (-not $RoutineKey -and (Test-Path -LiteralPath $RoutineSkill)) {
    $raw = Get-Content -LiteralPath $RoutineSkill -Raw -Encoding UTF8
    if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { $RoutineKey = $Matches[1] }
}
if (-not $RoutineKey) { throw 'ROUTINE_API_KEY ausente no ambiente (a SKILL da scheduled task nao carrega mais a chave).' }

$body = @{
    action = 'listar_plano_rotina'
    routine_key = $RoutineKey
    modo = 'noturno'
} | ConvertTo-Json -Compress

$plan = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
if ($plan.ok -ne $true) { throw ('listar_plano_rotina falhou: ' + $plan.erro) }

$items = @($plan.emissores)
# EMISSORSTALE2 (2026-09-19): desde a v4.9.259 horas_stale mede a ultima ANALISE real e vem
# com horas_stale_base ao lado. Sem a base, o Worker e anterior e horas_stale mede VARREDURA,
# que SKIP e deferido renovam; foi assim que 18/09 passou com 0/104 stale enquanto a noturna
# nao analisava ninguem. Falha fechado em vez de medir o relogio errado.
$semBase = @($items | Where-Object { -not $_.horas_stale_base })
if ($semBase.Count -gt 0) {
    throw ('listar_plano_rotina sem horas_stale_base em ' + $semBase.Count + ' de ' + $items.Count + ' emissores (worker_version=' + $plan.worker_version + '). O Worker e anterior ao EMISSORSTALE2 (v4.9.259) e horas_stale ainda mede a varredura, nao a analise.')
}
# sem_analise_registrada e numero proprio (sentinela 9999), nunca diluido nos atrasados.
$semRegistro = @($items | Where-Object { $_.horas_stale_base -eq 'sem_analise_registrada' })
$foraMescla = @($items | Where-Object { $_.horas_stale_base -eq 'ultima_analise_fora_da_mescla' })
$comCarimbo = @($items | Where-Object { $_.horas_stale_base -ne 'sem_analise_registrada' })
$staleAll = @($comCarimbo | Where-Object { [double]$_.horas_stale -ge $MaxAgeHours })
# STALE-GATE1 (v4.9.159): _status/inconclusivo vem do Worker, distingue staleness
# genuina de INCONCLUSIVO (clock pausado de proposito pelo mecanismo FIN1, aguardando
# promocao a tier FULL). So stale_real deve contar como severidade ALTO.
$staleReal = @($staleAll | Where-Object { -not $_.inconclusivo })
$staleInconclusivo = @($staleAll | Where-Object { $_.inconclusivo })
$stuck = if ($StuckDate) {
    @($items | Where-Object { ('' + $_.contexto_historico) -match [regex]::Escape($StuckDate) })
} else { @() }
$max = if ($comCarimbo.Count) { ($comCarimbo | Measure-Object horas_stale -Maximum).Maximum } else { $null }
$oldestReal = @($staleReal | Sort-Object horas_stale -Descending | Select-Object -First 10 empresa, horas_stale, horas_stale_base, horas_desde_varredura, contexto_historico, status)
$oldestInconclusivo = @($staleInconclusivo | Sort-Object horas_stale -Descending | Select-Object -First 10 empresa, horas_stale, horas_stale_base, horas_desde_varredura, contexto_historico, status)
# EMISSORES104 (2026-09-18): o gate tinha 103 fixo e a carteira passou a ter 104
# emissores, entao ele nunca fechava verde, nem com zero stale. O numero tem que
# acompanhar EMISSORES_LISTA do Worker. Quando a carteira mudar de tamanho, muda
# aqui e no plano esperado, senao o gate volta a mentir.
$EmissoresEsperados = 104
$healthy = ($items.Count -eq $EmissoresEsperados -and $staleReal.Count -eq 0 -and $semRegistro.Count -eq 0 -and $stuck.Count -eq 0)

[ordered]@{
    ok = $healthy
    api_ok = $plan.ok
    worker_version = $plan.worker_version
    checked_at = (Get-Date).ToString('o')
    regua = 'ultima_analise (EMISSORSTALE2)'
    total = $items.Count
    max_age_hours_allowed = $MaxAgeHours
    stale_24h_total = $staleAll.Count
    stale_24h_real = $staleReal.Count
    stale_24h_inconclusivo = $staleInconclusivo.Count
    sem_analise_registrada = $semRegistro.Count
    sem_analise_registrada_nomes = @($semRegistro | Select-Object -First 20 -ExpandProperty empresa)
    fora_da_mescla = $foraMescla.Count
    max_stale_hours = $max
    stuck_date = $StuckDate
    presos_data = $stuck.Count
    tiers = $plan.contagem_tiers
    oldest_real = $oldestReal
    oldest_inconclusivo = $oldestInconclusivo
} | ConvertTo-Json -Depth 6

if (-not $healthy) { exit 2 }
