# Replay dos CRITICOs perdidos na rotina noturna 2026-07-06
# Extrai os JSONs do log e submete via API

$keyLine = Get-Content "$PSScriptRoot\..\..\..\..\..\..\Users\User\.claude\scheduled-tasks\vixradar-noturno-v2.js" -Encoding UTF8 | Select-String "routine_key = '" | Select-Object -First 1
$key = ($keyLine.Line -split "'")[1]
$workerUrl = 'https://api.vixradar.com'
$logPath = "$PSScriptRoot\..\logs\routines\vixradar-noturno_20260706.log"

$setores = @{
    'Oncoclínicas' = 'Saúde'
    'Kora Saúde' = 'Saúde'
    'Pão de Açúcar (GPA)' = 'Varejo e Consumo'
    'Raízen' = 'Petróleo, Gás e Combustíveis'
}

$linhas = Get-Content $logPath -Encoding UTF8
$resultados = @{}

foreach ($linha in $linhas) {
    if ($linha -match '^[\d\-: ]+OUT: RESULTADO\|(.+?)\|(\{.*\})$') {
        $emp = $Matches[1]
        $json = $Matches[2]
        if (-not $resultados.ContainsKey($emp)) {
            try { $null = $json | ConvertFrom-Json; $resultados[$emp] = $json } catch {}
        }
    }
}

Write-Output "=== JSONs extraidos: $($resultados.Count) emissores ==="
$resultados.Keys | ForEach-Object { Write-Output "  $_" }

$submitted = @()
$errors = @()

foreach ($emp in $resultados.Keys) {
    $setor = $setores[$emp]
    if (-not $setor) {
        Write-Output "ERRO: setor nao mapeado para $emp"
        $errors += $emp
        continue
    }

    $resultadoJson = $resultados[$emp] | ConvertFrom-Json

    $body = @{
        action = 'receber_analise'
        routine_key = $key
        empresa = $emp
        setor = $setor
        _matinal = $false
        provedor = 'claude-sonnet-routine'
        resultado = $resultadoJson
    }

    $json = $body | ConvertTo-Json -Depth 16 -Compress

    try {
        Write-Output "Enviando $emp ($setor)..."
        $resp = Invoke-RestMethod -Uri $workerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $json -TimeoutSec 60
        Write-Output "  OK: ok=$($resp.ok) n_eventos=$($resp.n_eventos) versao=$($resp.versao)"
        $submitted += "$emp ($($resp.n_eventos) eventos)"
    } catch {
        Write-Output "  ERRO: $($_.Exception.Message)"
        $errors += "$emp : $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 1
}

Write-Output ""
Write-Output "=== RESUMO ==="
Write-Output "Submetidos: $($submitted.Count)"
$submitted | ForEach-Object { Write-Output "  + $_" }
if ($errors.Count -gt 0) {
    Write-Output "Erros: $($errors.Count)"
    $errors | ForEach-Object { Write-Output "  - $_" }
}
