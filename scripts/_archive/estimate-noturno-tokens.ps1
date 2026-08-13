# Estimativa tokens noturno (roteamento atual)
$ErrorActionPreference = 'Stop'
$skillPath = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md'
$raw = Get-Content $skillPath -Raw
if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { $key = $Matches[1] }
$plan = Invoke-RestMethod -Uri 'https://api.vixradar.com' -Method Post -ContentType 'application/json' `
    -Body (@{ action = 'listar_plano_rotina'; routine_key = $key; modo = 'noturno' } | ConvertTo-Json -Compress) -TimeoutSec 180
$analyze = @($plan.emissores | Where-Object { $_.tier -ne 'SKIP' })
$sonnet = @($analyze | Where-Object { ($_.tier -eq 'FULL') -and (($_.ews_score -ge 38) -or ($_.cvm_novos -gt 0)) })
$haiku = @($analyze | Where-Object { -not (($_.tier -eq 'FULL') -and (($_.ews_score -ge 38) -or ($_.cvm_novos -gt 0))) })
$estS = [Math]::Round($sonnet.Count * 15)
$estH = [Math]::Round($haiku.Count * 5)
Write-Output "SKIP=$($plan.contagem_tiers.SKIP) analyze=$($analyze.Count) sonnet=$($sonnet.Count) haiku=$($haiku.Count)"
$total = $estS + $estH
$flag = if ($total -le 500) { 'dentro meta 500k' } elseif ($total -le 700) { 'acima meta OK (hard 700k)' } else { 'risco deferred' }
Write-Output "estimativa_k: sonnet~${estS}k haiku~${estH}k total~${total}k — $flag"