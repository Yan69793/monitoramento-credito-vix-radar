# vixradar-progresso.ps1 - PROGRESSO1: checkpoint por lote, append-only, para retomada auditavel.
#
# Incidente 21/10/2026 21:02:40: a Noturna morreu no meio do lote full-10 sem FIM, sem stderr e sem
# rastro de QUAIS emissores estavam em voo. A instancia seguinte refez o lote (132 mil tokens) sem
# registrar que estava retomando. A idempotencia por emissor ja existe (o Worker marca analisado_hoje e
# o plano devolve SKIP), entao este arquivo NAO decide o que analisar: ele registra o que estava em voo
# e deixa a retomada visivel. Um lote morto antes de qualquer submit nao produziu nada que se possa
# salvar; o que da para provar e que ele foi retomado e por quem.
#
# Formato: <rotina>_progresso_<data>.jsonl, uma linha JSON por evento (append e kill-safe: no maximo a
# ultima linha fica truncada e e ignorada na leitura). Fail-open: qualquer erro devolve vazio.
# Compativel com Windows PowerShell 5.1, so ASCII.

function Get-VixProgressoPath([string]$LogDir, [string]$Rotina, [string]$DateTag) {
    return (Join-Path $LogDir ($Rotina + '_progresso_' + $DateTag + '.jsonl'))
}

function Get-VixProcessoInicioUtc([int]$ProcId) {
    try { return (Get-Process -Id $ProcId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o') } catch { return $null }
}

function Add-VixProgresso {
    param([string]$Path, [string]$Evento, [string]$Lote = '', $Empresas = @(), [hashtable]$Extra = @{})
    try {
        if (-not $Path) { return $false }
        $o = [ordered]@{
            ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            evento = $Evento
            pid = $PID
            pid_inicio_utc = (Get-VixProcessoInicioUtc $PID)
            lote = $Lote
            empresas = @($Empresas | ForEach-Object { '' + $_ })
        }
        foreach ($k in $Extra.Keys) { $o[$k] = $Extra[$k] }
        $linha = ($o | ConvertTo-Json -Compress -Depth 4) + "`n"
        [System.IO.File]::AppendAllText($Path, $linha, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch { return $false }
}

function Read-VixProgresso([string]$Path) {
    $out = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    try {
        foreach ($l in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)) {
            if (-not $l -or -not $l.Trim().StartsWith('{')) { continue }
            try { $out += ($l | ConvertFrom-Json) } catch { continue }   # ultima linha truncada por kill
        }
    } catch { }
    return $out
}

# O processo ainda e o mesmo? PID reaproveitado por outro processo (StartTime diferente) conta como morto.
function Test-VixProcessoAindaVivo([int]$ProcId, [string]$InicioUtc) {
    $atual = Get-VixProcessoInicioUtc $ProcId
    if (-not $atual) { return $false }
    if (-not $InicioUtc) { return $true }
    try { return ([datetime]$atual).ToUniversalTime() -eq ([datetime]$InicioUtc).ToUniversalTime() } catch { return ($atual -eq $InicioUtc) }
}

# Lotes iniciados e nunca fechados por um processo que ja morreu, ainda nao reportados por RETOMADA.
function Get-VixProgressoAbandonado([string]$Path) {
    $ev = @(Read-VixProgresso $Path)
    $abandonados = @()
    foreach ($i in @($ev | Where-Object { $_.evento -eq 'LOTE_INICIO' })) {
        $fechado = @($ev | Where-Object { $_.evento -eq 'LOTE_FECHADO' -and $_.lote -eq $i.lote -and [int]$_.pid -eq [int]$i.pid -and $_.pid_inicio_utc -eq $i.pid_inicio_utc }).Count -gt 0
        if ($fechado) { continue }
        $reportado = @($ev | Where-Object { $_.evento -eq 'RETOMADA' -and $_.lote -eq $i.lote -and [int]$_.pid_abandonado -eq [int]$i.pid -and $_.inicio_abandonado -eq $i.ts }).Count -gt 0
        if ($reportado) { continue }
        if (Test-VixProcessoAindaVivo ([int]$i.pid) ('' + $i.pid_inicio_utc)) { continue }   # outra instancia viva: nao e abandono
        $abandonados += $i
    }
    return $abandonados
}
