# MUTEXVAZADO1: prova de duas pontas de que a espera pela sentinela nao segura o mutex.
# Ponta ruim: o padrao antigo (adquire no laco, adquire de novo e solta uma vez) vaza.
# Ponta boa: o padrao novo (solta o que adquiriu) deixa o mutex livre para terceiro.
# Mais a checagem estatica de que run_vixradar_varredura.ps1 usa o padrao novo.
# Saida por exit code (0 = tudo passou). Roda em PowerShell 5.1 e 7, sem rede e sem token.
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$falhas = 0

function Test-MutexAdquiravel {
    param([string]$Nome)
    $m = New-Object System.Threading.Mutex($false, $Nome)
    $ok = $m.WaitOne(0)
    if ($ok) { $m.ReleaseMutex() }
    $m.Dispose()
    return $ok
}

function Invoke-PadraoEmFilho {
    param([string]$Corpo, [string]$Nome)
    $cmd = '$n = ''' + $Nome + '''; $m = New-Object System.Threading.Mutex($false, $n); ' + $Corpo + ' Start-Sleep -Seconds 10'
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $cmd) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 4
    $livre = Test-MutexAdquiravel $Nome
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    return $livre
}

$corpoAntigo = 'while (-not $m.WaitOne(0)) { Start-Sleep -Seconds 1 }; if ($m.WaitOne(0)) { $m.ReleaseMutex() };'
$corpoNovo = '$a = $false; while (-not ($a = $m.WaitOne(0))) { Start-Sleep -Seconds 1 }; if ($a) { $m.ReleaseMutex() };'

$nomeA = 'Local\vixradar-test-mutexvazado1-' + [guid]::NewGuid().ToString('N')
$livreAntigo = Invoke-PadraoEmFilho $corpoAntigo $nomeA
if ($livreAntigo) { Write-Output 'FALHA ponta ruim: o padrao antigo deveria vazar o mutex e nao vazou'; $falhas++ }
else { Write-Output 'OK ponta ruim: o padrao antigo segura o mutex (terceiro nao adquire)' }

$nomeB = 'Local\vixradar-test-mutexvazado1-' + [guid]::NewGuid().ToString('N')
$livreNovo = Invoke-PadraoEmFilho $corpoNovo $nomeB
if (-not $livreNovo) { Write-Output 'FALHA ponta boa: o padrao novo deveria liberar o mutex e nao liberou'; $falhas++ }
else { Write-Output 'OK ponta boa: o padrao novo libera o mutex (terceiro adquire)' }

$fonte = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
$temNovo = $fonte.Contains('if ($__sentAdquirido) { $__sentMutex.ReleaseMutex() }')
$temAntigo = $fonte.Contains('if ($__sentMutex.WaitOne(0)) { $__sentMutex.ReleaseMutex() }')
if ($temNovo -and -not $temAntigo) { Write-Output 'OK estatico: run_vixradar_varredura.ps1 usa o padrao novo e nao tem o antigo' }
else { Write-Output ('FALHA estatico: novo=' + $temNovo + ' antigo=' + $temAntigo); $falhas++ }

function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}
# Guarda geral (auditoria 22/10, correcao 1): nenhum script de rotina pode repetir o padrao que vazou o mutex,
# isto e, adquirir em laco `while (-not $x.WaitOne(0))` e logo depois chamar `if ($x.WaitOne(0))` de novo.
$rxVazado = '(?s)while\s*\(\s*-not\s*\$(\w+)\.WaitOne\(\s*0\s*\)\s*\)\s*\{.{0,1200}?\}\s*if\s*\(\s*\$\1\.WaitOne\(\s*0\s*\)\s*\)'
$suspeitos = @()
foreach ($s in Get-ChildItem -LiteralPath $aqui -Filter '*.ps1' -File) {
    if ($s.Name -eq 'test-mutex-sentinela-liberado.ps1') { continue }
    $txt = Get-Content -LiteralPath $s.FullName -Raw -Encoding UTF8
    if ($txt -match $rxVazado) { $suspeitos += $s.Name }
}
Confere ('guarda geral: nenhum script repete o padrao de mutex vazado (' + ($suspeitos -join ',') + ')') ($suspeitos.Count -eq 0)
# E a guarda reprova o padrao ruim (ponta ruim da propria guarda).
$ruimTxt = 'while (-not $mx.WaitOne(0)) { Start-Sleep 1 }' + "`n" + 'if ($mx.WaitOne(0)) { $mx.ReleaseMutex() }'
Confere 'guarda geral reprova o padrao antigo' ($ruimTxt -match $rxVazado)
$bomTxt = '$ad = $false' + "`n" + 'while (-not ($ad = $mx.WaitOne(0))) { Start-Sleep 1 }' + "`n" + 'if ($ad) { $mx.ReleaseMutex() }'
Confere 'guarda geral aceita o padrao novo' (-not ($bomTxt -match $rxVazado))

Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
