$lista = (Get-Content 'E:\Diretorio\Claude\Monitoramento de Credito\_lote_tmp\emissores_lista.json' -Raw | ConvertFrom-Json).emissores.empresa
$replay = @()
Get-ChildItem 'E:\Diretorio\Claude\Monitoramento de Credito\testing\noturno_*.json' | ForEach-Object {
  $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
  if ($j.empresa) { $replay += $j.empresa }
  elseif ($j.resultado.empresa) { $replay += $j.resultado.empresa }
}
$replay = $replay | Select-Object -Unique
$missing = $lista | Where-Object { $replay -notcontains $_ }
Write-Output "LISTA_API=$($lista.Count)"
Write-Output "REPLAY_ARQUIVOS=$($replay.Count)"
Write-Output "FALTAM=$($missing.Count)"
$missing | ForEach-Object { Write-Output $_ }
$missing | ConvertTo-Json | Set-Content 'E:\Diretorio\Claude\Monitoramento de Credito\_lote_tmp\emissores_faltantes.json' -Encoding UTF8