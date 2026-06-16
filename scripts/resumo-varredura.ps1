$dir = 'E:\Diretorio\Claude\Monitoramento de Credito\testing'
$files = Get-ChildItem $dir -Filter 'noturno_*.json' | Where-Object { $_.Name -notlike '_wrap_*' }
Write-Output "ARQUIVOS_NOTURNO=$($files.Count)"
$withEvents = 0
$semEventos = 0
foreach ($f in $files) {
  $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
  $r = if ($j.resultado) { $j.resultado } else { $j }
  if ($r.sem_eventos -eq $true) { $semEventos++ }
  elseif ($r.eventos -and $r.eventos.Count -gt 0) { $withEvents++ }
}
Write-Output "COM_EVENTOS_NO_JSON=$withEvents"
Write-Output "SEM_EVENTOS_NO_JSON=$semEventos"
$health = curl.exe -s --max-time 10 'https://radar-credito-api.prospects-intel.workers.dev'
Write-Output "HEALTH=$health"