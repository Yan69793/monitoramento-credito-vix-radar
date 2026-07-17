<#
.SYNOPSIS
  Mede o staleness (_last_scanned_at) dos 103 emissores do VIX Radar via op=state.
.DESCRIPTION
  Login admin legitimo (ADMIN_SENHA de api/.env) -> admin_auto_login -> JWT ->
  op=state. Computa idade de _last_scanned_at por emissor, distribui em faixas,
  salva snapshot JSON em logs/monitor-tasks/ e imprime resumo. Serve de baseline
  e de re-medicao (comparar antes/depois de uma varredura) para o FIN1-REV.
  NUNCA imprime a senha nem o JWT.
.PARAMETER Label
  Rotulo do snapshot (ex.: 'baseline-pre-noturna', 'pos-noturna'). Vai no nome do arquivo.
.PARAMETER CompareTo
  (Opcional) Caminho de um snapshot JSON anterior para comparar (delta de staleness por emissor).
#>
[CmdletBinding()]
param(
  [string]$Label = "snapshot",
  [string]$CompareTo = ""
)
$ErrorActionPreference = "Stop"
# scripts/monitoring/ -> sobe 2 niveis ate a raiz do projeto
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile = Join-Path $root "api\.env"
if (-not (Test-Path $envFile)) { Write-Host "ERRO: api/.env nao encontrado" -ForegroundColor Red; exit 1 }
$senha = ((Get-Content $envFile | Where-Object { $_ -match '^ADMIN_SENHA=' } | Select-Object -First 1) -replace '^ADMIN_SENHA=','').Trim().Trim('"')
if (-not $senha) { Write-Host "ERRO: ADMIN_SENHA vazia em api/.env" -ForegroundColor Red; exit 1 }

$API = "https://api.vixradar.com"
$tok = (Invoke-RestMethod -Uri "$API/" -Method Post -ContentType 'application/json' -Body (@{ action='admin_auto_login'; admin_senha=$senha } | ConvertTo-Json) -TimeoutSec 30).token
if (-not $tok) { Write-Host "ERRO: login admin nao retornou token" -ForegroundColor Red; exit 1 }
$st = Invoke-RestMethod -Uri "$API/?op=state" -Method Get -Headers @{ Authorization = "Bearer $tok" } -TimeoutSec 60
if (-not $st.results) { Write-Host "ERRO: op=state sem results" -ForegroundColor Red; exit 1 }

$now = (Get-Date).ToUniversalTime()
$rows = foreach ($p in $st.results.PSObject.Properties) {
  $e = $p.Value
  $ls = $e._last_scanned_at
  $idade = $null
  $lsIso = $null
  if ($ls) {
    if ($ls -is [datetime]) { $dt = $ls } else { $dt = [datetime]::Parse($ls) }
    $dtu = $dt.ToUniversalTime()
    $idade = [Math]::Round(($now - $dtu).TotalHours, 1)
    $lsIso = $dtu.ToString('o')
  }
  [pscustomobject]@{ empresa = $p.Name; last_scanned_at = $lsIso; idade_h = $idade; status = $e.classificacao_geral }
}
$comLs = $rows | Where-Object { $_.idade_h -ne $null }
$fresh = ($comLs | Where-Object { $_.idade_h -le 24 }).Count
$m2448 = ($comLs | Where-Object { $_.idade_h -gt 24 -and $_.idade_h -le 48 }).Count
$gt48  = ($comLs | Where-Object { $_.idade_h -gt 48 }).Count
$idadeMax = ($comLs | Measure-Object idade_h -Maximum).Maximum

Write-Host "=== STALENESS ($Label) — $($now.ToString('o')) ===" -ForegroundColor Cyan
Write-Host "total: $($rows.Count) | com _last_scanned_at: $($comLs.Count)"
Write-Host "FRESCOS (<=24h): $fresh" -ForegroundColor Green
Write-Host "STALE 24-48h:   $m2448" -ForegroundColor Yellow
Write-Host "STALE >48h:     $gt48" -ForegroundColor $(if ($gt48 -gt 0) { 'Red' } else { 'Green' })
Write-Host "idade maxima: ${idadeMax}h"
Write-Host "--- top 12 mais stale ---"
$comLs | Sort-Object idade_h -Descending | Select-Object -First 12 | Format-Table empresa, idade_h, last_scanned_at, status -AutoSize | Out-String | Write-Host

$snap = [pscustomobject]@{
  label = $Label; gerado_em = $now.ToString('o'); worker = $st.week
  total = $rows.Count; fresh_le24h = $fresh; stale_24_48h = $m2448; stale_gt48h = $gt48; idade_max_h = $idadeMax
  emissores = $rows
}
$outDir = Join-Path $root "logs\monitor-tasks"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = $now.ToString('yyyyMMdd-HHmmss')
$outFile = Join-Path $outDir "staleness_${Label}_${stamp}.json"
$snap | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
Write-Host "snapshot salvo: $outFile" -ForegroundColor DarkGray

if ($CompareTo -and (Test-Path $CompareTo)) {
  $base = Get-Content $CompareTo -Raw | ConvertFrom-Json
  Write-Host "`n=== DELTA vs $([System.IO.Path]::GetFileName($CompareTo)) ===" -ForegroundColor Cyan
  Write-Host ("stale>48h: {0} -> {1}  (delta {2})" -f $base.stale_gt48h, $gt48, ($gt48 - $base.stale_gt48h))
  Write-Host ("frescos<=24h: {0} -> {1}  (delta {2})" -f $base.fresh_le24h, $fresh, ($fresh - $base.fresh_le24h))
  $baseMap = @{}; foreach ($b in $base.emissores) { $baseMap[$b.empresa] = $b.idade_h }
  $destravados = $comLs | Where-Object { $baseMap.ContainsKey($_.empresa) -and $baseMap[$_.empresa] -gt 24 -and $_.idade_h -le 6 }
  Write-Host "DESTRAVADOS (eram >24h, agora <=6h): $($destravados.Count)" -ForegroundColor Green
  if ($destravados) { $destravados | Sort-Object empresa | Select-Object -First 30 | ForEach-Object { Write-Host ("  {0}: {1}h -> {2}h" -f $_.empresa, $baseMap[$_.empresa], $_.idade_h) } }
}
exit 0
