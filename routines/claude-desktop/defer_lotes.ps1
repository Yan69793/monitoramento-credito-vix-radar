$ErrorActionPreference = 'Continue'
$base = "E:\Diretorio\Claude\Monitoramento de Credito\logs\routines"
$dir = "$base\lotes_20260814"
$logFile = "$base\vixradar-noturno_$(Get-Date -Format 'yyyyMMdd').log"
$key = $env:ROUTINE_API_KEY
if (-not $key) { "KEY_VAZIA"; return }

$emiss = @()
foreach ($f in @("$dir\rapida_7.json", "$dir\aprofundada_1.json")) {
    $lote = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    $emiss += @($lote)
}
$ok = 0; $falha = 0
foreach ($em in $emiss) {
    $res = [ordered]@{
        empresa = $em.empresa
        setor = $em.setor
        sem_eventos = $true
        cobertura_nota = "Tier $($em.tier). Cap de sessao - ledger minimo. EWS=$($em.ews_score). Priorizar amanha."
        fontes_consultadas = @(@{ rodada = "0"; query = "token_cap"; resultado = "deferred" })
        eventos = @()
        _tier = $em.tier
        _rotina_v2 = $true
        _token_cap_deferred = $true
    }
    $body = @{ action='receber_analise'; routine_key=$key; empresa=$em.empresa; setor=$em.setor; _matinal=$false; provedor='claude-cap-deferred'; resultado=$res }
    $jsonBody = $body | ConvertTo-Json -Depth 10
    $submitOk = $false
    for ($tent = 1; $tent -le 2 -and -not $submitOk; $tent++) {
        try {
            $r = Invoke-RestMethod -Uri "https://api.vixradar.com" -Method Post -ContentType "application/json; charset=utf-8" -Body $jsonBody -TimeoutSec 60
            if ($r.ok) { $submitOk = $true }
        } catch {
            if ($tent -lt 2) { Start-Sleep -Seconds 2 }
        }
    }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') OK|$($em.empresa)|$($em.tier)|DEFERRED|0|$submitOk" | Out-File -Append $logFile -Encoding UTF8
    if ($submitOk) { $ok++ } else { $falha++ }
}
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') DEFERIDOS=$ok FALHA=$falha TOTAL=$($emiss.Count) motivo=token_cap_hard_700k" | Out-File -Append $logFile -Encoding UTF8
"DEFER_OK=$ok FALHA=$falha TOTAL=$($emiss.Count)"
