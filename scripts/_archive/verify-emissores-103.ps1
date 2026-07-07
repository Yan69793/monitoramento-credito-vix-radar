# Valida Worker retorna 103 emissores (rotina noturno)
$ErrorActionPreference = 'Stop'

$skillPath = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md'
$workerUrl = 'https://api.vixradar.com'

if (-not (Test-Path $skillPath)) {
    Write-Output 'FAIL: scheduled task noturno SKILL.md ausente'
    exit 1
}

$skill = Get-Content $skillPath -Raw
if ($skill -match 'ROUTINE_KEY\s*=\s*(\S+)') {
    $key = $Matches[1]
} elseif ($env:ROUTINE_API_KEY) {
    $key = $env:ROUTINE_API_KEY
} else {
    Write-Output 'FAIL: ROUTINE_KEY nao encontrada (env ou SKILL.md)'
    exit 1
}

$body = @{ action = 'listar_todos_emissores'; routine_key = $key } | ConvertTo-Json -Compress
$resp = Invoke-RestMethod -Uri $workerUrl -Method Post -ContentType 'application/json' -Body $body

$total = $resp.total
$ok = $resp.ok -eq $true
Write-Output "Worker: $workerUrl"
Write-Output "ok: $ok | total: $total | esperado: 103"

if ($ok -and $total -eq 103) {
    Write-Output 'PASS: universo 103/103'
    exit 0
}
Write-Output 'FAIL: total diferente de 103 ou ok=false'
exit 1