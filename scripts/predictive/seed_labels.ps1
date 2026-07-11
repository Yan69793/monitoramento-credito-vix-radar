# seed_labels.ps1
# One-shot: constroi o dataset seed de labels de eventos de credito para o preditivo v2
# (plano 2026-07-11, nota 51). Fontes: semanas vivas de radar:estado:{YYYY-Www} no KV de
# producao + snapshots versionados em scans/*.json (jun/2026).
# Saida: data/labels/eventos_credito.jsonl (1 evento por linha, dedup empresa+data+titulo).
# Target de treino do v2 = evento real (RJ/default/downgrade/covenant...), nunca proxy.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\predictive\seed_labels.ps1" [-DeSemana 1] [-AteSemana 28]

param(
    [int]$DeSemana = 1,
    [int]$AteSemana = 28,
    [int]$Ano = 2026
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'
$OutDir      = Join-Path $ProjectRoot 'data\labels'
$OutPath     = Join-Path $OutDir 'eventos_credito.jsonl'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-KvValue([string]$Key) {
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $env:TEMP ("kvget_{0}_{1}.err" -f $PID, [System.IO.Path]::GetRandomFileName())
    try {
        Push-Location $ApiDir
        $raw = (& npx wrangler kv key get $Key --namespace-id $NamespaceId --remote 2>$stderrFile | Out-String)
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
        $i = $raw.IndexOf('{')
        if ($i -lt 0) { return $null }
        return $raw.Substring($i).Trim()
    } catch {
        if ((Get-Location).Path -eq $ApiDir) { Pop-Location }
        return $null
    } finally {
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

$labels = New-Object System.Collections.ArrayList
$vistos = @{}

function Add-Label($empresa, $setor, $ev, [string]$origem) {
    if (-not $ev) { return }
    $dataEv = [string]$ev.data_evento
    $titulo = [string]$ev.titulo
    $chave = ($empresa + '|' + $dataEv + '|' + $titulo).ToLowerInvariant().Trim()
    if ($vistos.ContainsKey($chave)) { return }
    $vistos[$chave] = $true
    [void]$labels.Add([pscustomobject]@{
        empresa       = $empresa
        setor         = $setor
        data_evento   = $dataEv
        classificacao = [string]$ev.classificacao
        tags          = @($ev.tags)
        fonte_tipo    = [string]$ev.fonte_tipo
        titulo        = $titulo
        oficial_tier1 = [bool]$ev._oficial_tier1
        origem        = $origem
    })
}

# ---- 1. Semanas vivas no KV ----
$semanasOk = 0
for ($w = $DeSemana; $w -le $AteSemana; $w++) {
    $semana = ('{0}-W{1:00}' -f $Ano, $w)
    $raw = Get-KvValue ('radar:estado:' + $semana)
    if (-not $raw) { [Console]::WriteLine(('  {0}: ausente' -f $semana)); continue }
    $estado = $null
    try { $estado = $raw | ConvertFrom-Json } catch {
        # W28 real: results com chaves de emissor diferindo so por caixa (bug de normalizacao
        # na escrita - registrado em PENDENCIAS). pwsh aceita via -AsHashtable; dedup colapsa.
        try { $estado = $raw | ConvertFrom-Json -AsHashtable } catch { [Console]::WriteLine(('  {0}: JSON invalido' -f $semana)); continue }
    }
    if (-not $estado -or -not $estado.results) { continue }
    $semanasOk++
    $nEv = 0
    $pares = @()
    if ($estado.results -is [System.Collections.IDictionary]) {
        foreach ($k in $estado.results.Keys) { $pares += [pscustomobject]@{ Name = $k; Value = $estado.results[$k] } }
    } else {
        $pares = @($estado.results.PSObject.Properties)
    }
    foreach ($prop in $pares) {
        $emp = $prop.Name
        $res = $prop.Value
        if (-not $res -or -not $res.eventos) { continue }
        $setorRes = ''
        if ($res -is [System.Collections.IDictionary]) { $setorRes = [string]$res['setor'] } else { $setorRes = [string]$res.setor }
        foreach ($ev in @($res.eventos)) { Add-Label $emp $setorRes $ev ('kv:' + $semana); $nEv++ }
    }
    [Console]::WriteLine(('  {0}: {1} eventos lidos' -f $semana, $nEv))
}

# ---- 2. Scans versionados (jun/2026) ----
$scanDir = Join-Path $ProjectRoot 'scans'
$scansOk = 0
if (Test-Path $scanDir) {
    foreach ($f in Get-ChildItem $scanDir -Filter '*.json' -File) {
        try {
            $scan = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        } catch { continue }
        $emp = [string]$scan.empresa
        if (-not $emp -or -not $scan.resultado -or -not $scan.resultado.eventos) { continue }
        $scansOk++
        foreach ($ev in @($scan.resultado.eventos)) { Add-Label $emp ([string]$scan.setor) $ev ('scan:' + $f.BaseName) }
    }
}

# ---- 3. Gravar JSONL ordenado por data ----
$ordenados = $labels | Sort-Object data_evento, empresa
$linhas = $ordenados | ForEach-Object { $_ | ConvertTo-Json -Depth 4 -Compress }
[System.IO.File]::WriteAllLines($OutPath, [string[]]$linhas, $Utf8NoBom)

[Console]::WriteLine('')
[Console]::WriteLine(('FIM: {0} labels unicos ({1} semanas KV + {2} scans) -> {3}' -f $labels.Count, $semanasOk, $scansOk, $OutPath))
if ($labels.Count -lt 1) { exit 1 }
exit 0
