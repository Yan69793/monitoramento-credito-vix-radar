# Estimativa tokens matinal (roteamento orquestrado)
$ErrorActionPreference = 'Stop'
$skillPath = 'C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\SKILL.md'
$raw = Get-Content $skillPath -Raw
if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { $key = $Matches[1] }
$plan = Invoke-RestMethod -Uri 'https://api.vixradar.com' -Method Post -ContentType 'application/json' `
    -Body (@{ action = 'listar_plano_rotina'; routine_key = $key; modo = 'matinal'; top_n = 15 } | ConvertTo-Json -Compress) -TimeoutSec 180
if ($plan.total -eq 0) {
    Write-Output 'SKIP: nenhum emissor prioritario'
    return
}
$analyze = @($plan.emissores | Where-Object { $_.tier -ne 'SKIP' })
$sonnet = @($analyze | Where-Object { ($_.tier -eq 'FULL') -and (($_.ews_score -ge 38) -or ($_.cvm_novos -gt 0)) })
$haiku = @($analyze | Where-Object { -not (($_.tier -eq 'FULL') -and (($_.ews_score -ge 38) -or ($_.cvm_novos -gt 0))) })
$estS = [Math]::Round($sonnet.Count * 15)
$estH = [Math]::Round($haiku.Count * 5)
Write-Output "SKIP=$($plan.contagem_tiers.SKIP) analyze=$($analyze.Count) sonnet=$($sonnet.Count) haiku=$($haiku.Count)"
$total = $estS + $estH
$flag = if ($total -le 120) { 'dentro meta 120k' } elseif ($total -le 180) { 'acima meta OK (hard 180k)' } else { 'risco deferred' }
Write-Output "estimativa_k: sonnet~${estS}k haiku~${estH}k total~${total}k — $flag"