# watch-noturno-progress.ps1
# Barra de progresso animada do noturno (console + HTML auto-refresh).
# Uso: pwsh -File scripts\watch-noturno-progress.ps1
#      pwsh -File scripts\watch-noturno-progress.ps1 -DateTag 20260804 -OpenBrowser
param(
    [string]$DateTag = (Get-Date -Format 'yyyyMMdd'),
    [string]$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito',
    [int]$TotalEsperado = 103,
    [int]$RefreshMs = 800,
    [switch]$OpenBrowser,
    [int]$MaxMinutes = 180
)

$ErrorActionPreference = 'Continue'
$LogDir = Join-Path $ProjectRoot 'logs\routines'
$LogFile = Join-Path $LogDir ("vixradar-noturno_$DateTag.log")
$ShadowJsonl = Join-Path $LogDir ("noturno_shadow_deepseek_$DateTag.jsonl")
$MetricsFile = Join-Path $LogDir ("noturno_metrics_$DateTag.json")
$HtmlFile = Join-Path $LogDir ("noturno_progress_$DateTag.html")
$JsonLive = Join-Path $LogDir ("noturno_progress_$DateTag.json")

$frames = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$barW = 36
$fi = 0
$deadline = (Get-Date).AddMinutes($MaxMinutes)

function Get-NomeNorm([string]$s) {
    if (-not $s) { return '' }
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Trim().ToLowerInvariant()
}

function Get-NoturnoSnapshot {
    $done = @{}
    $classif = @{}
    $criticos = New-Object System.Collections.Generic.List[string]
    $lastLine = ''
    $lastLote = ''
    $phase = 'aguardando'
    $inicioTs = $null
    $fim = $false
    $shadowOn = $false
    $tokensLine = ''
    $filas = ''
    $idem = 0
    $submitOk = 0
    $submitFail = 0
    $shadowN = 0
    $shadowDiv = 0
    $running = $false

    if (Test-Path $LogFile) {
        $lines = Get-Content $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            $lastLine = $line
            if ($line -match 'INICIO: noturno') {
                $inicioTs = $line.Substring(0, [Math]::Min(19, $line.Length))
                $phase = 'iniciado'
            }
            if ($line -match 'SHADOW: DeepSeek ON') { $shadowOn = $true }
            if ($line -match 'Idempotencia: (\d+)') { $idem = [int]$Matches[1]; $phase = 'idempotencia' }
            if ($line -match 'Filas: (.+)$') { $filas = $Matches[1]; $phase = 'filas' }
            if ($line -match 'Lote (haiku|sonnet)-\d+') { $lastLote = $line; $phase = 'lote_llm' }
            if ($line -match 'Tokens lote=') { $tokensLine = $line; $phase = 'tokens' }
            if ($line -match 'SHADOW\|') { $phase = 'shadow' }
            if ($line -match 'FIM: ') { $fim = $true; $phase = 'fim'; $tokensLine = $line }
            if ($line -match 'OK\|([^|]+)\|([^|]+)\|([^|]+)\|') {
                $emp = $Matches[1].Trim()
                $cl = $Matches[3].Trim()
                $k = Get-NomeNorm $emp
                if ($k -and -not $done.ContainsKey($k)) {
                    $done[$k] = $emp
                    $classif[$k] = $cl
                    $submitOk++
                    if ($cl -eq 'CRITICO') { $criticos.Add($emp) }
                } elseif ($k) {
                    $classif[$k] = $cl
                }
            }
            if ($line -match 'SUBMIT_ERRO\|') { $submitFail++ }
        }
    }

    if (Test-Path $ShadowJsonl) {
        $shadowLines = Get-Content $ShadowJsonl -Encoding UTF8 -ErrorAction SilentlyContinue
        $shadowN = @($shadowLines | Where-Object { $_.Trim() }).Count
        foreach ($sl in $shadowLines) {
            if ($sl -match '"diverge"\s*:\s*true' -or $sl -match '"diverge":true') { $shadowDiv++ }
        }
    }

    # processo noturno vivo? pwsh com script no command line e dificil; usa transcript recente + claude filho
    $running = $false
    try {
        $tfiles = Get-ChildItem $LogDir -Filter ("noturno_transcript_${DateTag}_*.txt") -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($tf in $tfiles) {
            if ($tf.LastWriteTime -gt (Get-Date).AddMinutes(-3)) { $running = $true; break }
        }
        if (-not $running) {
            $cl = Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -gt (Get-Date).AddHours(-3) }
            if ($cl -and -not $fim) {
                # so conta se log teve atividade recente
                if ((Test-Path $LogFile) -and ((Get-Item $LogFile).LastWriteTime -gt (Get-Date).AddMinutes(-15))) {
                    $running = $true
                }
            }
        }
    } catch {}

    $nDone = $done.Count
    if ($nDone -gt $TotalEsperado) { $nDone = $TotalEsperado }
    $pct = if ($TotalEsperado -gt 0) { [Math]::Min(100, [Math]::Round(100.0 * $nDone / $TotalEsperado, 1)) } else { 0 }
    if ($fim -and $nDone -ge $TotalEsperado) { $pct = 100; $running = $false }
    if ($fim) { $running = $false }

    $byClass = @{}
    foreach ($k in $classif.Keys) {
        $c = $classif[$k]
        if (-not $byClass.ContainsKey($c)) { $byClass[$c] = 0 }
        $byClass[$c]++
    }

    return [pscustomobject]@{
        dateTag     = $DateTag
        total       = $TotalEsperado
        done        = $nDone
        pct         = $pct
        remaining   = [Math]::Max(0, $TotalEsperado - $nDone)
        phase       = $phase
        running     = $running
        fim         = $fim
        lastLine    = $lastLine
        lastLote    = $lastLote
        inicioTs    = $inicioTs
        idem        = $idem
        filas       = $filas
        tokensLine  = $tokensLine
        shadowOn    = $shadowOn
        shadowN     = $shadowN
        shadowDiv   = $shadowDiv
        submitOk    = $submitOk
        submitFail  = $submitFail
        criticos    = @($criticos)
        byClass     = $byClass
        logFile     = $LogFile
        updatedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

function Write-ProgressHtml([object]$s) {
    $status = if ($s.fim) { 'CONCLUIDO' } elseif ($s.running) { 'RODANDO' } else { 'PARADO / AGUARDANDO' }
    $statusColor = if ($s.fim) { '#3dd68c' } elseif ($s.running) { '#5b9dff' } else { '#f5a524' }
    $pct = $s.pct
    $fill = $pct
    $critList = if ($s.criticos.Count -gt 0) { ($s.criticos -join ', ') } else { '—' }
    $last = ($s.lastLine -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
    $lote = ($s.lastLote -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;')
    $clsRows = ''
    foreach ($k in @($s.byClass.Keys | Sort-Object)) {
        $clsRows += "<tr><td>$k</td><td>$($s.byClass[$k])</td></tr>"
    }
    if (-not $clsRows) { $clsRows = '<tr><td colspan="2">sem OK ainda</td></tr>' }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8"/>
<meta http-equiv="refresh" content="2"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>VIX Radar Noturno — $pct%</title>
<style>
  :root {
    --bg: #0b0f14;
    --panel: #121820;
    --text: #e8eef7;
    --muted: #8b9bb0;
    --bar: #1a2330;
    --accent: #5b9dff;
    --ok: #3dd68c;
    --warn: #f5a524;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh;
    font-family: "Segoe UI", system-ui, sans-serif;
    background: radial-gradient(1200px 600px at 20% -10%, #152033 0%, var(--bg) 55%);
    color: var(--text);
    display: flex; align-items: center; justify-content: center;
    padding: 24px;
  }
  .card {
    width: min(720px, 100%);
    background: linear-gradient(180deg, #151c27 0%, var(--panel) 100%);
    border: 1px solid #243041;
    border-radius: 16px;
    padding: 28px 28px 22px;
    box-shadow: 0 20px 60px rgba(0,0,0,.45);
  }
  h1 { margin: 0 0 4px; font-size: 1.25rem; font-weight: 650; letter-spacing: .02em; }
  .sub { color: var(--muted); font-size: .9rem; margin-bottom: 22px; }
  .status {
    display: inline-flex; align-items: center; gap: 8px;
    font-size: .78rem; font-weight: 600; letter-spacing: .06em;
    padding: 4px 10px; border-radius: 999px;
    background: rgba(255,255,255,.04); border: 1px solid #2a384c;
    color: $statusColor; margin-bottom: 18px;
  }
  .status .dot {
    width: 8px; height: 8px; border-radius: 50%; background: $statusColor;
    box-shadow: 0 0 10px $statusColor;
    animation: pulse 1.2s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: .45; transform: scale(.85); }
  }
  .pct-row {
    display: flex; align-items: baseline; justify-content: space-between;
    margin-bottom: 10px;
  }
  .pct-big {
    font-size: 2.6rem; font-weight: 700; font-variant-numeric: tabular-nums;
    letter-spacing: -0.03em;
  }
  .pct-meta { color: var(--muted); font-size: .95rem; }
  .track {
    height: 18px; background: var(--bar); border-radius: 999px;
    overflow: hidden; border: 1px solid #2a384c; position: relative;
  }
  .fill {
    height: 100%; width: $fill%;
    background: linear-gradient(90deg, #2f6fed, #5b9dff 50%, #7ad0ff);
    border-radius: 999px;
    transition: width .6s ease;
    position: relative;
    box-shadow: 0 0 20px rgba(91,157,255,.35);
  }
  .fill::after {
    content: '';
    position: absolute; inset: 0;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,.28), transparent);
    background-size: 200% 100%;
    animation: sheen 1.6s linear infinite;
  }
  @keyframes sheen {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
  }
  .grid {
    display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
    margin-top: 22px;
  }
  .stat {
    background: rgba(0,0,0,.22); border: 1px solid #243041;
    border-radius: 10px; padding: 12px 14px;
  }
  .stat label { display: block; color: var(--muted); font-size: .72rem; text-transform: uppercase; letter-spacing: .08em; }
  .stat b { font-size: 1.15rem; font-variant-numeric: tabular-nums; }
  .full { grid-column: 1 / -1; }
  .mono { font-family: ui-monospace, Consolas, monospace; font-size: .78rem; color: #b7c5d8; word-break: break-all; line-height: 1.4; }
  table { width: 100%; border-collapse: collapse; font-size: .85rem; margin-top: 6px; }
  td { padding: 4px 0; border-bottom: 1px solid #1e2836; }
  td:last-child { text-align: right; font-variant-numeric: tabular-nums; }
  footer { margin-top: 16px; color: var(--muted); font-size: .75rem; }
</style>
</head>
<body>
  <div class="card">
    <div class="status"><span class="dot"></span> $status · NOTURNO $DateTag</div>
    <h1>VIX Radar — rotina noturna</h1>
    <div class="sub">103 emissores · shadow DeepSeek (sem submit) · auto-refresh 2s</div>

    <div class="pct-row">
      <div class="pct-big">$pct%</div>
      <div class="pct-meta">$($s.done) / $($s.total) · restam $($s.remaining)</div>
    </div>
    <div class="track"><div class="fill"></div></div>

    <div class="grid">
      <div class="stat"><label>Fase</label><b>$($s.phase)</b></div>
      <div class="stat"><label>Idempotência (hoje)</label><b>$($s.idem)</b></div>
      <div class="stat"><label>Shadow</label><b>$(if ($s.shadowOn) { "ON · $($s.shadowN) cmp · div $($s.shadowDiv)" } else { 'OFF' })</b></div>
      <div class="stat"><label>Críticos</label><b>$($s.criticos.Count)</b></div>
      <div class="stat full"><label>Último lote</label><div class="mono">$(if ($lote) { $lote } else { '—' })</div></div>
      <div class="stat full"><label>Última linha do log</label><div class="mono">$(if ($last) { $last } else { 'log vazio' })</div></div>
      <div class="stat full"><label>Críticos (lista)</label><div class="mono">$critList</div></div>
      <div class="stat full">
        <label>Distribuição por classificação</label>
        <table>$clsRows</table>
      </div>
    </div>
    <footer>Atualizado $($s.updatedAt) · $HtmlFile</footer>
  </div>
</body>
</html>
"@
    Set-Content -Path $HtmlFile -Value $html -Encoding UTF8
    ($s | ConvertTo-Json -Depth 6) | Set-Content -Path $JsonLive -Encoding UTF8
}

function Test-InteractiveConsole {
    try {
        if ([Console]::IsOutputRedirected) { return $false }
        $null = [Console]::WindowWidth
        return $true
    } catch { return $false }
}

function Show-ConsoleBar([object]$s, [int]$frameIdx) {
    $spin = $frames[$frameIdx % $frames.Count]
    if ($s.fim) { $spin = 'OK' }
    elseif (-not $s.running) { $spin = '..' }

    $filled = [int][Math]::Floor($barW * $s.pct / 100.0)
    if ($filled -gt $barW) { $filled = $barW }
    $empty = $barW - $filled
    # ASCII bar: seguro em Task Scheduler / pipe / log
    $bar = ('#' * $filled) + ('-' * $empty)

    $status = if ($s.fim) { 'DONE' } elseif ($s.running) { 'RUN ' } else { 'IDLE' }
    $line1 = "$spin Noturno $status  [$bar]  $($s.pct)%  $($s.done)/$($s.total)  restam $($s.remaining)"
    $line2 = "  fase=$($s.phase)  shadow=$(if($s.shadowOn){"$($s.shadowN)cmp"}else{'off'})  crit=$($s.criticos.Count)  $($s.updatedAt)"
    $tail = $s.lastLine
    if ($tail.Length -gt 110) { $tail = $tail.Substring(0, 110) + '...' }
    $line3 = "  $tail"

    if (Test-InteractiveConsole) {
        try {
            $ui = "$line1`n$line2`n$line3`n  HTML: $HtmlFile"
            Clear-Host
            Write-Host $ui
            return
        } catch { }
    }
    # modo pipe / background: uma linha por tick (sem cursor)
    Write-Host ("[{0}] {1} | {2}" -f $s.updatedAt, $line1, $s.phase)
}

# --- main ---
try { Clear-Host } catch {}
Write-Host "Monitor noturno $DateTag"
Write-Host "Log: $LogFile"
Write-Host "HTML: $HtmlFile"
Write-Host ""

$snap0 = Get-NoturnoSnapshot
Write-ProgressHtml $snap0
if ($OpenBrowser) {
    try { Start-Process $HtmlFile } catch { Write-Host "Nao abriu browser: $($_.Exception.Message)" }
}

while ((Get-Date) -lt $deadline) {
    $s = Get-NoturnoSnapshot
    Write-ProgressHtml $s
    Show-ConsoleBar $s $fi
    $fi++
    if ($s.fim -and $s.pct -ge 99) {
        Write-Host ""
        Write-Host "Concluido: $($s.done)/$($s.total) ($($s.pct)%)"
        break
    }
    Start-Sleep -Milliseconds $RefreshMs
}
