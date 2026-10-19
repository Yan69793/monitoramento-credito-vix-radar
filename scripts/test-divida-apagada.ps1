param(
    [string]$Lib = (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1'),
    [string]$Varredura = (Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1')
)
# DIVIDAAPAGADA1 (2026-10-19). Duas regras locais e a ligacao delas na varredura.
#  a) SKIP aceito so solta a pendencia persistente quando e credito de analise real do dia.
#  b) Deferido por rotacao_semanal mantem a divida (_token_cap_deferred=true) de quem esta sem
#     analise real ha 120h ou mais, ou sem registro.
# Prova de duas pontas: rodar contra HEAD (-Lib/-Varredura apontando para copia do git show)
# tem que reprovar, e contra a arvore atual tem que aprovar.
$ErrorActionPreference = 'Continue'
$script:falhas = 0
$script:total = 0
function Assert-Divida([bool]$Cond, [string]$Nome) {
    $script:total++
    if ($Cond) { Write-Output ('PASS ' + $Nome) } else { $script:falhas++; Write-Output ('FAIL ' + $Nome) }
}
function New-ItemPlano([string]$Empresa, $Motivos, $HorasAnalise) {
    $o = [ordered]@{ empresa = $Empresa; motivos = @($Motivos); ews_score = 0 }
    if ($null -ne $HorasAnalise) { $o.horas_desde_analise = $HorasAnalise } else { $o.horas_desde_analise = $null }
    return [pscustomobject]$o
}

. $Lib

$temRegras = [bool](Get-Command Test-VixRotacaoMantemDivida -ErrorAction SilentlyContinue) -and [bool](Get-Command Test-VixSkipSoltaPendente -ErrorAction SilentlyContinue)
Assert-Divida $temRegras 'regras existem na lib'

if ($temRegras) {
    # Retrato da CPFL em 15/10: rotacao com analise real ha 394h.
    $cpfl = New-ItemPlano 'CPFL Energia' @('ews_medio_ou_stale_2d') 394
    Assert-Divida (Test-VixRotacaoMantemDivida $cpfl 'rotacao_semanal') 'b PONTA RUIM: rotacao com analise ha 394h mantem a divida'
    $semReg = New-ItemPlano 'X' @('cobertura_padrao') $null
    Assert-Divida (Test-VixRotacaoMantemDivida $semReg 'rotacao_semanal') 'b sem registro de analise mantem a divida (fail-closed)'
    Assert-Divida (Test-VixRotacaoMantemDivida (New-ItemPlano 'X' @() 120) 'rotacao_semanal') 'b limite: 120h exatas mantem'
    Assert-Divida (-not (Test-VixRotacaoMantemDivida (New-ItemPlano 'X' @() 119.9) 'rotacao_semanal')) 'b PONTA BOA: rotacao com analise ha 119,9h nao mantem (a rotacao continua valendo)'
    Assert-Divida (-not (Test-VixRotacaoMantemDivida (New-ItemPlano 'X' @() 20) 'rotacao_semanal')) 'b PONTA BOA: rotacao com analise ha 20h nao mantem'
    Assert-Divida (Test-VixRotacaoMantemDivida (New-ItemPlano 'X' @() 2) 'cap_efetivo') 'b corte por cap sempre mantem, mesmo com analise recente'
    Assert-Divida (Test-VixRotacaoMantemDivida (New-ItemPlano 'X' @() 2) 'falha_provider') 'b falha de provedor sempre mantem'
    Assert-Divida (Test-VixRotacaoMantemDivida ([pscustomobject]@{ empresa = 'X'; horas_desde_analise = 'lixo' }) 'rotacao_semanal') 'b horas ilegiveis contam como sem registro'

    # Retrato da CPFL em 15/10 18:05: SKIP por frescor de varredura.
    $skipFrescor = New-ItemPlano 'CPFL Energia' @('sem_delta_30h') 394
    Assert-Divida (-not (Test-VixSkipSoltaPendente $skipFrescor)) 'a PONTA RUIM: SKIP sem_delta_30h nao solta a pendencia'
    Assert-Divida (-not (Test-VixSkipSoltaPendente (New-ItemPlano 'X' @('scan_recente_sem_delta') 300))) 'a SKIP da matinal por frescor nao solta'
    Assert-Divida (Test-VixSkipSoltaPendente (New-ItemPlano 'Eneva' @('analisado_hoje_por_pontual', 'credito_FULL_8h') 8)) 'a PONTA BOA: SKIP por credito de analise do dia solta'
    Assert-Divida (-not (Test-VixSkipSoltaPendente (New-ItemPlano 'X' @() 1))) 'a SKIP sem motivo nao solta'
    Assert-Divida (-not (Test-VixSkipSoltaPendente $null)) 'a item nulo nao solta'
}

# Ligacao na varredura: as tres pontas usam as regras e as formas antigas sumiram.
$src = [IO.File]::ReadAllText($Varredura, [Text.Encoding]::UTF8)
Assert-Divida ($src -match '\$ehCorteDeCap = Test-VixRotacaoMantemDivida \$emp \$Motivo') 'ligacao: submit do deferido usa a regra b'
Assert-Divida (-not ($src -match [regex]::Escape("`$ehCorteDeCap = (`$Motivo -ne 'rotacao_semanal')"))) 'ligacao: regra antiga do submit do deferido removida'
Assert-Divida ($src -match "-or \(Test-VixRotacaoMantemDivida \`$emp \`$motivoItem\)\) \{ Add-VixPendenteSeguro") 'ligacao: fila local recebe a rotacao que manteve a divida'
Assert-Divida ($src -match 'if \(\$subOk -and \(Test-VixSkipSoltaPendente \$emp\)\) \{ Remove-VixPendenteSeguro') 'ligacao: SKIP usa a regra a'
Assert-Divida (-not ($src -match 'if \(\$subOk\) \{ Remove-VixPendenteSeguro \$emp\.empresa \}')) 'ligacao: SKIP nao solta mais a pendencia sem condicao'

# PS 5.1: a varredura roda no powershell.exe do Task Scheduler.
$tokens = $null; $erros = $null
[void][Management.Automation.Language.Parser]::ParseFile($Varredura, [ref]$tokens, [ref]$erros)
Assert-Divida (@($erros).Count -eq 0) ('varredura parseia sem erro (' + @($erros).Count + ' erros)')

Write-Output ('RESULTADO: ' + ($script:total - $script:falhas) + '/' + $script:total)
if ($script:falhas -gt 0) { exit 1 }
exit 0
