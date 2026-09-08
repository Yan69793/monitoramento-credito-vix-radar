# test-routine-alert.ps1 - prova de duas pontas de Send-VixRoutineAlert (NOTIFYDEDUP-LOG1) sem rede:
# Invoke-RestMethod e substituido por uma funcao local que devolve a resposta simulada do Worker.
# Antes da correcao a lib dizia "admin notificado" para {ok:true, enviado:false, dedup:true}.
# PowerShell 5.1, ASCII puro. Exit 0 = todos os asserts OK. Nenhum e-mail, nenhum POST real.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$script:Linhas = @()
function Write-Log([string]$m) { $script:Linhas += $m }
$script:Fake = $null; $script:Chamadas = 0; $script:Lancar = $false; $script:UltimoBody = ''
function Invoke-RestMethod {
    param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
    $script:Chamadas++
    $script:UltimoBody = '' + $Body
    if ($script:Lancar) { throw 'rede caiu' }
    return $script:Fake
}
function Reset-Caso { $script:Linhas = @(); $script:Chamadas = 0; $script:Lancar = $false; $script:UltimoBody = '' }

Write-Host '=== 1. enviado:true -> $true, "admin notificado" ==='
Reset-Caso
$script:Fake = [pscustomobject]@{ ok = $true; enviado = $true }
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey 'k-de-teste'
Assert ($r -eq $true) ('retorno=' + $r)
Assert (($script:Linhas -join "`n") -match 'admin notificado') 'log: admin notificado'
Assert ($script:Chamadas -eq 1) 'um POST'
Assert ($script:UltimoBody -match '"action":"notificar_rotina"' -and $script:UltimoBody -match '"rotina":"teste"') 'body JSON com action e rotina'

Write-Host '=== 2. ok:true enviado:false dedup:true -> $false, "NAO enviado, dedup" ==='
Reset-Caso
$script:Fake = [pscustomobject]@{ ok = $true; enviado = $false; dedup = $true }
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey 'k-de-teste'
Assert ($r -eq $false) ('retorno=' + $r)
Assert (($script:Linhas -join "`n") -match 'NAO enviado, dedup') 'log: NAO enviado, dedup'
Assert (-not (($script:Linhas -join "`n") -match 'admin notificado')) 'log NAO diz admin notificado (ponta ruim do comportamento antigo)'

Write-Host '=== 3. ok:false -> $false ==='
Reset-Caso
$script:Fake = [pscustomobject]@{ ok = $false; erro = 'Acesso negado.' }
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey 'k-de-teste'
Assert ($r -eq $false) ('retorno=' + $r)
Assert (($script:Linhas -join "`n") -match 'ok:false') 'log: ok:false'

Write-Host '=== 4. excecao de rede -> $false, sem derrubar o chamador ==='
Reset-Caso
$script:Lancar = $true
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey 'k-de-teste'
Assert ($r -eq $false) ('retorno=' + $r)
Assert (($script:Linhas -join "`n") -match 'falha ao notificar admin') 'log: falha ao notificar'

Write-Host '=== 5. sem routine_key -> $false e zero POST ==='
Reset-Caso
$script:Fake = [pscustomobject]@{ ok = $true; enviado = $true }
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey ''
Assert ($r -eq $false) ('retorno=' + $r)
Assert ($script:Chamadas -eq 0) 'nenhum POST sem chave'

Write-Host '=== 6. Worker antigo sem campo enviado -> $true (compatibilidade) ==='
Reset-Caso
$script:Fake = [pscustomobject]@{ ok = $true }
$r = Send-VixRoutineAlert -Rotina 'teste' -Motivo 'm' -RoutineKey 'k-de-teste'
Assert ($r -eq $true) ('retorno=' + $r)

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
