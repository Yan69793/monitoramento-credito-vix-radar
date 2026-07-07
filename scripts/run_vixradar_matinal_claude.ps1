# run_vixradar_matinal_claude.ps1 - Matinal v2: SKIP PS1 + Haiku/Sonnet top 15, cap 120k tokens
$ErrorActionPreference = 'Stop'
# Mesma correcao de encoding do noturno (ver run_vixradar_noturno_claude.ps1) - stdout do
# binario 'claude' sem console interativo pode decodificar em ANSI/OEM e corromper nomes
# acentuados, quebrando o match de RESULTADO por emissor.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$CleanupScript  = Join-Path $ProjectRoot 'scripts\cleanup-rotina-artifacts.ps1'
$HaikuSkill     = Join-Path $ScriptsDir 'matinal-batch-haiku.md'
$SonnetSkill    = Join-Path $ScriptsDir 'matinal-batch-sonnet.md'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-matinal_' + $DateTag + '.log')
$MetricsFile    = Join-Path $LogDir ('matinal_metrics_' + $DateTag + '.json')

$ModelHaiku     = 'claude-haiku-4-5-20251001'
$ModelSonnet    = 'claude-sonnet-4-6'
$TopN           = 15
$TokenTarget    = 120000
$TokenHardCap   = 180000
$SonnetEwsMin   = 38
$HaikuChunk     = 6
$SonnetChunk    = 4
$PauseSec       = 2

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-Cleanup([switch]$Aggressive) {
    if (-not (Test-Path $CleanupScript)) { return }
    try {
        if ($Aggressive) { $out = & $CleanupScript -KeepDays 7 -Aggressive }
        else { $out = & $CleanupScript -KeepDays 7 }
        Write-Log ('Cleanup: ' + $out)
    } catch {
        Write-Log ('Cleanup aviso: ' + $_.Exception.Message)
    }
}

function Get-RoutineKey {
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    $skillPath = Join-Path $ScheduledTasks 'vixradar-matinal\SKILL.md'
    if (Test-Path $skillPath) {
        $raw = Get-Content $skillPath -Raw -Encoding UTF8
        if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { return $Matches[1] }
    }
    throw 'ROUTINE_KEY nao encontrada'
}

function Get-CvmResumo($docs) {
    if (-not $docs) { return '0 docs' }
    $arr = @($docs)
    if ($arr.Count -eq 0) { return '0 docs' }
    return ($arr.Count.ToString() + ' docs')
}

function Get-SlimEmissor($emp, [switch]$Ultra) {
    $docs = @($emp.cvm_documentos | Select-Object -First $(if ($Ultra) { 2 } else { 3 }))
    $o = [ordered]@{
        empresa        = $emp.empresa
        setor          = $emp.setor
        tier           = $emp.tier
        rodadas        = $emp.rodadas
        ews_score      = $emp.ews_score
        cvm_novos      = $emp.cvm_novos
        janela_inicio  = $emp.janela_inicio
        janela_fim     = $emp.janela_fim
        cvm_documentos = $docs
    }
    if (-not $Ultra -and $emp.contexto_historico) {
        $ctx = $emp.contexto_historico
        if ($ctx.Length -gt 120) { $ctx = $ctx.Substring(0, 120) }
        $o['contexto_historico'] = $ctx
    }
    return $o
}

function Invoke-WorkerJsonUtf8 {
    # Worker responde application/json SEM charset; Windows PowerShell 5.1 decodificaria a
    # resposta como ISO-8859-1, corrompendo acentos em memoria (Raizen -> "RaA*zen", match
    # do plano falha e CRITICO real vira NENHUM - P0 nota 43, 2026-07-07). Le bytes crus e
    # decoda UTF-8 explicitamente; envia body como bytes UTF-8 pelo mesmo motivo.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Submit-Analise($key, $empresa, $setor, $resultado, [string]$provedor = 'claude-sonnet-routine') {
    $body = @{
        action = 'receber_analise'; routine_key = $key; empresa = $empresa; setor = $setor
        _matinal = $true; provedor = $provedor; resultado = $resultado
    }
    $json = $body | ConvertTo-Json -Depth 16 -Compress
    return Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $json -TimeoutSec 120
}

function Submit-SkipEmissor($key, $emp) {
    $motivos = if ($emp.motivos) { ($emp.motivos -join ', ') } else { 'sem_delta_24h' }
    $cvmResumo = Get-CvmResumo $emp.cvm_documentos
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier SKIP. CVM: $cvmResumo. $($emp.cvm_novos) novos. Motivos: $motivos."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'Worker plano'; resultado = $cvmResumo })
        eventos = @(); _tier = 'SKIP'; _rotina_v2 = $true
    }
    $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado
    if ($resp.ok -ne $true) {
        Start-Sleep -Seconds $PauseSec
        $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado
    }
    return $resp
}

function Submit-CapDeferred($key, $emp) {
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier $($emp.tier). Cap hard ${TokenHardCap} tokens - ledger minimo. EWS=$($emp.ews_score). Priorizar amanha."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'token_cap'; resultado = 'deferred' })
        eventos = @(); _tier = $emp.tier; _rotina_v2 = $true; _token_cap_deferred = $true
    }
    return Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-cap-deferred'
}

function Build-LlmQueues($analyzeList) {
    $sonnet = @()
    $haiku = @()
    foreach ($emp in @($analyzeList)) {
        $high = ($emp.tier -eq 'FULL') -and (($emp.ews_score -ge $SonnetEwsMin) -or ($emp.cvm_novos -gt 0))
        if ($high) { $sonnet += $emp } else { $haiku += $emp }
    }
    return @{
        Sonnet = @($sonnet | Sort-Object -Property ews_score, cvm_novos -Descending)
        Haiku  = $haiku
    }
}

function Split-IntoChunks($items, [int]$chunkSize) {
    $list = @($items)
    if ($list.Count -eq 0) { return @() }
    $chunks = @()
    for ($i = 0; $i -lt $list.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize - 1, $list.Count - 1)
        $chunks += ,@($list[$i..$end])
    }
    return $chunks
}

function Parse-TokensFromOutput([string]$text) {
    $total = 0
    if (-not $text) { return 0 }
    foreach ($pat in @('total[_\s-]*tokens?[:\s]+([\d,]+)', '([\d,]+)\s+tokens?\s+used')) {
        foreach ($match in [regex]::Matches($text, $pat, 'IgnoreCase')) {
            $n = [int]($match.Groups[1].Value -replace ',', '')
            if ($n -gt $total) { $total = $n }
        }
    }
    return $total
}

function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    $out = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
        --model $Model `
        --add-dir $ScriptsDir `
        --add-dir $ScheduledTasks `
        --permission-mode bypassPermissions `
        --output-format text 2>&1
    return @{ Output = $out; ExitCode = $LASTEXITCODE }
}

function New-BatchPrompt($batch, $batchLabel, $modelName, $skillPath, $routineKey, [switch]$Ultra) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissor $_ -Ultra:$Ultra })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais.
ROUTINE_KEY=$routineKey
_matinal=true obrigatorio em receber_analise.
PROIBIDO: Task, listar_plano_rotina, testing/, narrativa longa.
Reporte: OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok
Final: LOTE_RESUMO|ok|fail|buscas|criticos

JSON:
$json

$skill
"@
}

function Remove-BatchPrompts([string]$tag) {
    Get-ChildItem $LogDir -Filter ('matinal_*_' + $tag + '.txt') -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LogDir ('matinal_plano_' + $tag + '.json')) -Force -ErrorAction SilentlyContinue
}

$hoje = Get-Date
if ($hoje.DayOfWeek -in 'Saturday', 'Sunday') {
    Write-Log 'SKIP: fim de semana'
    return
}
$feriados = @(
    '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
    '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
)
if ($feriados -contains $hoje.ToString('yyyy-MM-dd')) {
    Write-Log 'SKIP: feriado B3'
    return
}

foreach ($f in @($HaikuSkill, $SonnetSkill)) {
    if (-not (Test-Path $f)) { Write-Log ('ERRO: skill ausente ' + $f); exit 1 }
}

Write-Log "INICIO: matinal top=$TopN meta=${TokenTarget} hard=${TokenHardCap} haiku+sonnet(EWS>=$SonnetEwsMin)"
Invoke-Cleanup

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    # So bloqueia por dependencia real desta rotina (KV + telemetria) - ver nota em run_vixradar_noturno_claude.ps1
    if (-not $health.bindings.kv -or -not $health.bindings.telemetria) {
        Write-Log ('ERRO: health - kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
        exit 3
    }
    Write-Log ('Health ' + $health.versao + ' ok=' + $health.ok + ' verificador_ok=' + $health.verificador_ok + ' (nao bloqueante para esta rotina)')
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stats = @{
    skip_ok = 0; skip_fail = 0; batch_ok = 0; batch_fail = 0
    tokens_total = 0; tokens_over_target = $false; tokens_hard_hit = $false; deferred = 0
    batches_run = 0; sonnet_count = 0; haiku_count = 0
    criticos = New-Object System.Collections.Generic.List[string]
}
$pendingDeferred = New-Object System.Collections.Generic.List[object]
$exitCode = 0
$batchSeq = 0

Push-Location $ProjectRoot
try {
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = 'matinal'; top_n = $TopN } -TimeoutSec 180
    if ($plano.ok -ne $true) { Write-Log 'ERRO: plano'; exit 5 }
    if ($plano.total -eq 0) {
        Write-Log 'SKIP: nenhum emissor prioritario'
        return
    }
    if ($plano.total -ne $TopN) { Write-Log ('AVISO: total=' + $plano.total + ' esperado=' + $TopN) }

    @{
        data = $plano.data; tiers = $plano.contagem_tiers; buscas = $plano.buscas_estimadas
        emissores = @($plano.emissores | ForEach-Object { @{ e = $_.empresa; t = $_.tier; ews = $_.ews_score } })
    } | ConvertTo-Json -Compress | Set-Content (Join-Path $LogDir ('matinal_plano_' + $DateTag + '.json')) -Encoding UTF8

    Write-Log ('Plano ' + ($plano.contagem_tiers | ConvertTo-Json -Compress))

    foreach ($emp in @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' })) {
        try {
            $r = Submit-SkipEmissor $routineKey $emp
            if ($r.ok) { $stats.skip_ok++ } else { $stats.skip_fail++ }
        } catch { $stats.skip_fail++ }
        Start-Sleep -Seconds $PauseSec
    }
    Write-Log ('SKIP ' + $stats.skip_ok + ' via PS1')

    $analyzeList = @($plano.emissores | Where-Object { $_.tier -ne 'SKIP' })
    $queues = Build-LlmQueues $analyzeList
    Write-Log ('Filas: sonnet=' + $queues.Sonnet.Count + ' haiku=' + $queues.Haiku.Count)

    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in (Split-IntoChunks $queues.Sonnet $SonnetChunk)) {
        $jobs.Add([ordered]@{ Name = 'sonnet'; Model = $ModelSonnet; Chunk = @($chunk); Skill = $SonnetSkill; Ultra = $false })
    }
    foreach ($chunk in (Split-IntoChunks $queues.Haiku $HaikuChunk)) {
        $jobs.Add([ordered]@{ Name = 'haiku'; Model = $ModelHaiku; Chunk = @($chunk); Skill = $HaikuSkill; Ultra = $true })
    }

    $ji = 0
    foreach ($job in $jobs) {
        $ji++
        if ($stats.tokens_total -ge $TokenHardCap) {
            $stats.tokens_hard_hit = $true
            foreach ($e in $job.Chunk) { $pendingDeferred.Add($e) }
            continue
        }

        $batchSeq++
        $label = $job.Name + '-' + $ji
        $prompt = New-BatchPrompt $job.Chunk $label $job.Model $job.Skill $routineKey -Ultra:$job.Ultra
        $promptPath = Join-Path $LogDir ('matinal_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $prompt -Encoding UTF8

        Write-Log ('Lote ' + $label + ' [' + $job.Model + ']: ' + (($job.Chunk | ForEach-Object { $_.empresa }) -join ', '))
        $result = Invoke-ClaudeBatch $promptPath $job.Model
        $stats.batches_run++
        if ($job.Name -eq 'sonnet') { $stats.sonnet_count += $job.Chunk.Count } else { $stats.haiku_count += $job.Chunk.Count }

        if ($result.Output) {
            $result.Output | ForEach-Object { Write-Log ('OUT: ' + $_) }
            foreach ($line in $result.Output) {
                if ($line -match '^OK\|([^|]+)\|([^|]+)\|([^|]+)\|') {
                    if ($Matches[3] -eq 'CRITICO') { $stats.criticos.Add($Matches[1]) }
                }
            }
        }

        $bt = Parse-TokensFromOutput ($result.Output -join "`n")
        if ($bt -gt 0) { $stats.tokens_total += $bt }
        Write-Log ('Tokens lote=' + $bt + ' acum=' + $stats.tokens_total)

        if ($result.ExitCode -ne 0) { $stats.batch_fail++ } else { $stats.batch_ok++ }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue

        if ($stats.tokens_total -ge $TokenTarget -and -not $stats.tokens_over_target) {
            $stats.tokens_over_target = $true
            Write-Log ('AVISO: meta ' + $TokenTarget + ' ultrapassada - continua ate hard ' + $TokenHardCap)
        }
        if ($stats.tokens_total -ge $TokenHardCap) {
            $stats.tokens_hard_hit = $true
            Write-Log ('HARD CAP ' + $TokenHardCap + ' - restante deferred')
        }
    }

    foreach ($emp in $pendingDeferred) {
        try {
            $r = Submit-CapDeferred $routineKey $emp
            if ($r.ok) { $stats.deferred++ }
        } catch { Write-Log ('Deferred fail: ' + $emp.empresa) }
        Start-Sleep -Seconds 1
    }

    $sw.Stop()
    @{
        data = $DateTag; top_n = $TopN; token_target = $TokenTarget; token_hard_cap = $TokenHardCap
        tokens_total_est = $stats.tokens_total; tokens_over_target = $stats.tokens_over_target
        tokens_hard_hit = $stats.tokens_hard_hit; skip_ok = $stats.skip_ok
        sonnet_llm = $stats.sonnet_count; haiku_llm = $stats.haiku_count; deferred = $stats.deferred
        batches = $stats.batches_run; criticos = @($stats.criticos); duracao_sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
    } | ConvertTo-Json -Depth 5 | Set-Content $MetricsFile -Encoding UTF8

    Write-Log ('FIM: tokens=' + $stats.tokens_total + ' meta=' + $TokenTarget + ' hard=' + $TokenHardCap +
        ' sonnet=' + $stats.sonnet_count + ' haiku=' + $stats.haiku_count +
        ' deferred=' + $stats.deferred + ' criticos=' + $stats.criticos.Count)

    if ($stats.skip_fail -gt 0 -or $stats.batch_fail -gt 0) { $exitCode = 6 }
} finally {
    Remove-BatchPrompts $DateTag
    Invoke-Cleanup -Aggressive
    Pop-Location
}

if ($exitCode -ne 0) { exit $exitCode }
