<#
.SYNOPSIS
  Teste do scripts/rollback-pages.ps1 (VXROLLBACK1): as guardas reprovam o caso ruim E aceitam o bom.
  Offline, sem publicar nada: so exercita o plano (sem -Publicar) e as recusas.
#>
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'rollback-pages.ps1'
$falhas = 0
function Rodar([string[]]$ArgsExtra) {
  $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }
  $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $script @ArgsExtra 2>&1 | Out-String
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
}
function Afirmar([bool]$cond, [string]$msg) {
  if ($cond) { Write-Host ("  OK   " + $msg) -ForegroundColor Green } else { Write-Host ("  FALHA " + $msg) -ForegroundColor Red; $script:falhas++ }
}

Push-Location $root
try {
  $verHead = (git show HEAD:app/deploy_zip/version.json | ConvertFrom-Json).version
  Write-Host ("versao do bundle em HEAD: " + $verHead)

  # ponta boa: plano do commit atual, versao certa, destino de preview
  $r = Rodar @('-Ref', 'HEAD', '-VersaoEsperada', $verHead)
  Afirmar ($r.Exit -eq 0) 'plano do HEAD com a versao certa: exit 0'
  Afirmar ($r.Out -match 'nada foi enviado' -or $r.Out -match 'Nada foi enviado' -or $r.Out -match 'Plano') 'sem -Publicar nao envia nada (so imprime o plano)'
  Afirmar ($r.Out -match 'allowlist OK') 'allowlist do Pages aprovou o pacote'

  # pontas ruins
  $r = Rodar @('-Ref', 'HEAD', '-VersaoEsperada', 'v999.999')
  Afirmar ($r.Exit -ne 0 -and $r.Out -match 'difere') 'versao esperada diferente: recusa'
  $r = Rodar @('-Ref', 'HEAD', '-Branch', 'main', '-Publicar')
  Afirmar ($r.Exit -ne 0 -and $r.Out -match 'exige -Producao') 'producao sem -Producao: recusa antes de qualquer envio'
  $r = Rodar @('-Ref', 'HEAD', '-Branch', 'ui-v2-preview', '-Producao')
  Afirmar ($r.Exit -ne 0 -and $r.Out -match 'so combina com -Branch main') '-Producao com branch de preview: recusa'
  $r = Rodar @('-Ref', 'ref-que-nao-existe-vx')
  Afirmar ($r.Exit -ne 0 -and $r.Out -match 'nao resolve') 'ref inexistente: recusa'
} finally {
  Pop-Location
}
if ($falhas -gt 0) { Write-Host ("TESTE VXROLLBACK1: {0} FALHA(S)" -f $falhas) -ForegroundColor Red; exit 1 }
Write-Host 'TESTE VXROLLBACK1: OK (recusa o caso ruim e aceita o bom; nada publicado)' -ForegroundColor Green
exit 0
