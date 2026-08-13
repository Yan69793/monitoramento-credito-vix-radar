$rk = $env:ROUTINE_API_KEY
if (-not $rk) {
  Write-Error "ROUTINE_API_KEY nao definida. Ex.: `$env:ROUTINE_API_KEY = '...'"
  return
}
$worker = 'https://radar-credito-api.prospects-intel.workers.dev'
$failFiles = @('noturno_Hidrovias.json','noturno_Kora.json','noturno_MRV.json','noturno_Vibra.json','noturno_Raizen.json')
$dir = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito\testing'

foreach ($name in $failFiles) {
  $path = Join-Path $dir $name
  $raw = Get-Content $path -Raw -Encoding UTF8
  $j = $raw | ConvertFrom-Json
  if (-not $j.action) {
    $emp = if ($j.empresa) { $j.empresa } else { ($name -replace '^noturno_','' -replace '_',' ') }
    $setor = if ($j.setor) { $j.setor } else { 'Outros' }
    $wrapped = [ordered]@{ action='receber_analise'; routine_key=$rk; empresa=$emp; setor=$setor; _matinal=$false; resultado=$j }
    $postPath = Join-Path $dir "_wrap_$name"
    $wrapped | ConvertTo-Json -Depth 30 | Set-Content $postPath -Encoding UTF8
  } else {
    $postPath = $path
  }
  $out = curl.exe -s --max-time 90 -X POST $worker -H 'Content-Type: application/json' -d "@$postPath"
  Write-Output "$name => $out"
}