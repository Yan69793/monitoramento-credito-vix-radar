# test-coletateto1-17out.ps1 - guarda do COLETATETO1 (17/10/2026).
# Em 16/10 o upload da Coleta-Volatilidade passou do limite de 15 min da task e o Task
# Scheduler matou o processo (0x40010004) sem FIM nem causa no log, porque a saida do filho
# ficava so em memoria. Prova de duas pontas, offline, sem rede e sem KV:
#   1. comportamento: etapa que estoura o teto volta Timeout=true/Exit=124 com a saida parcial
#      ja gravada; etapa normal volta o exit real e a saida inteira.
#   2. estrutura: o script real usa Invoke-ColetaEtapa nas duas etapas e a soma dos tetos fica
#      abaixo do ExecutionTimeLimit de 15 min; a forma antiga (& powershell.exe ... 2>&1) reprova.
# ASCII puro, PS 5.1.
param([string]$Alvo = (Join-Path $PSScriptRoot 'run_coleta_volatilidade.ps1'))
$ErrorActionPreference = 'Continue'
$ok = 0; $falha = 0
function Test-Assert([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:ok++; Write-Host ('  OK    ' + $Nome) } else { $script:falha++; Write-Host ('  FALHA ' + $Nome) }
}

$fonte = Get-Content -LiteralPath $Alvo -Raw
$ast = [System.Management.Automation.Language.Parser]::ParseInput($fonte, [ref]$null, [ref]$null)
$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ColetaEtapa' }, $true)

Write-Host 'Parte 2: estrutura do script real'
Test-Assert (@($fn).Count -eq 1) 'Invoke-ColetaEtapa definida'
Test-Assert ($fonte -notmatch '&\s*powershell\.exe[^\r\n]*\$Uploader') 'uploader nao roda mais por & powershell.exe sem teto'
Test-Assert ($fonte -notmatch '&\s*powershell\.exe[^\r\n]*\$Collector') 'coletor nao roda mais por & powershell.exe sem teto'
$mC = [regex]::Match($fonte, '\$TetoColetorSeg\s*=\s*(\d+)')
$mU = [regex]::Match($fonte, '\$TetoUploaderSeg\s*=\s*(\d+)')
Test-Assert ($mC.Success -and $mU.Success -and (([int]$mC.Groups[1].Value + [int]$mU.Groups[1].Value) -lt 840)) 'soma dos tetos abaixo de 14 min (limite da task 15 min)'

if (@($fn).Count -ne 1) {
    Write-Host ''
    Write-Host ('RESULTADO: {0} OK, {1} falha(s)' -f $ok, $falha)
    exit 1
}

Write-Host 'Parte 1: comportamento'
$tmp = Join-Path $env:TEMP ('coletateto1_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$LogDir = $tmp
. ([scriptblock]::Create($fn[0].Extent.Text))

$lento = Join-Path $tmp 'lento.ps1'
Set-Content -LiteralPath $lento -Encoding ASCII -Value "Write-Output 'PARCIAL_ANTES_DO_TRAVAMENTO'; Start-Sleep -Seconds 60; Write-Output 'NUNCA'"
$normal = Join-Path $tmp 'normal.ps1'
Set-Content -LiteralPath $normal -Encoding ASCII -Value "param([int]`$Dias) Write-Output ('UPLOAD_OK dias=' + `$Dias); [Console]::Error.WriteLine('aviso-stderr'); exit 3"

$t0 = Get-Date
$r1 = Invoke-ColetaEtapa -Script $lento -Argumentos '' -TetoSeg 4 -Rotulo 'lento'
$dur = ((Get-Date) - $t0).TotalSeconds
Test-Assert ($r1.Timeout -eq $true -and $r1.Exit -eq 124) 'caso ruim: estouro vira Timeout=true Exit=124'
Test-Assert ($dur -lt 30) ('caso ruim: encerrado perto do teto (' + [int]$dur + 's)')
Test-Assert ((@($r1.Saida) -join ' ') -match 'PARCIAL_ANTES_DO_TRAVAMENTO') 'caso ruim: saida parcial preservada em arquivo'
Test-Assert ((@($r1.Saida) -join ' ') -notmatch 'NUNCA') 'caso ruim: processo nao continuou depois do teto'

$r2 = Invoke-ColetaEtapa -Script $normal -Argumentos '-Dias 252' -TetoSeg 60 -Rotulo 'normal'
Test-Assert ($r2.Timeout -eq $false) 'caso bom: sem timeout'
Test-Assert ($r2.Exit -eq 3) ('caso bom: exit real propagado (' + $r2.Exit + ')')
Test-Assert ((@($r2.Saida) -join ' ') -match 'UPLOAD_OK dias=252') 'caso bom: stdout e argumento chegam'
Test-Assert ((@($r2.Saida) -join ' ') -match 'aviso-stderr') 'caso bom: stderr capturado'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: {0} OK, {1} falha(s)' -f $ok, $falha)
if ($falha -gt 0) { exit 1 }
exit 0
