# test-cobertura-contrato.ps1 - COBERTURA1 (2026-09-09), offline por CONTRATO.
# Extrai por AST as funcoes REAIS do motor (run_vixradar_varredura.ps1) e prova os 6 cenarios
# RCA do incidente Vibra/Natura + PROVAFALSA1 (texto do modelo nao vale como prova mecanica)
# + idempotencia do merge do contrato. ASCII puro (PS 5.1 e pwsh 7), sem rede, sem Worker.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

function Get-MotorFuncDefs([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $out += $f.Extent.Text
    }
    return ,$out
}

$MotorPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_varredura.ps1'
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Test-VixBuscaDegradada', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Get-NomeNormalizado', 'Merge-VixContratoCobertura'))) { Invoke-Expression $_def }

function New-FonteOk([string]$fam, [string]$q, [string]$res = 'sem fato novo na janela apos consulta') {
    return [pscustomobject]@{ familia = $fam; query = $q; timestamp = '2026-09-09T18:00:00Z'; provedor = 'openrouter:web_search'; status_http = 200; resultado = $res; classificacao = 'ok' }
}
function New-FonteDegradada([string]$fam, [string]$q, [int]$http, [string]$cl, [string]$res) {
    return [pscustomobject]@{ familia = $fam; query = $q; timestamp = '2026-09-09T18:00:00Z'; provedor = 'openrouter:web_search'; status_http = $http; resultado = $res; classificacao = $cl }
}
function New-FonteProsa([string]$q, [string]$res) {
    return [pscustomobject]@{ rodada = 'R2'; query = $q; resultado = $res }
}
function New-Res([object[]]$fontes, [object[]]$eventos = @()) {
    return [pscustomobject]@{ sem_eventos = $true; classificacao_geral = 'NENHUM'; eventos = $eventos; fontes_consultadas = $fontes }
}

Write-Host '== Cenarios RCA =='

$r1 = New-Res @((New-FonteOk 'emissor' 'Vibra Energia contexto'), (New-FonteDegradada 'divida' 'Vibra debentures' 429 'degradada' 'sem retorno - limite backend'), (New-FonteOk 'fato' 'Vibra CVM fato relevante')) @()
$c1 = Resolve-VixCoberturaFamilias $r1
Assert-True (-not $c1.ok) 'R1: 429 na familia divida => cobertura NAO ok (DEFERIDO)'
Assert-True (($c1.faltantes -join ',') -eq 'divida') 'R1: faltantes so da familia degradada (divida)'

$r2 = New-Res @((New-FonteDegradada 'emissor' 'Natura &Co' 429 'degradada' 'rate limit atingido'), (New-FonteOk 'divida' 'Natura divida debentures'), (New-FonteOk 'fato' 'Natura RI CVM')) @()
$c2 = Resolve-VixCoberturaFamilias $r2
Assert-True (-not $c2.ok -and (($c2.faltantes -join ',') -eq 'emissor')) 'R2: rate limit em F1 => faltante emissor'

$r3 = New-Res @((New-FonteOk 'emissor' 'X'), (New-FonteDegradada 'divida' 'X divida' 200 'ok' 'vazio'), (New-FonteOk 'fato' 'X CVM')) @()
$c3 = Resolve-VixCoberturaFamilias $r3
Assert-True (-not $c3.ok -and (($c3.faltantes -join ',') -eq 'divida')) 'R3: resposta vazia anomalia => divida faltante'

$r4 = New-Res @((New-FonteOk 'emissor' 'Natura &Co contexto'), (New-FonteOk 'fato' 'Natura Fitch rating CVM')) @()
$c4 = Resolve-VixCoberturaFamilias $r4
Assert-True (-not $c4.ok -and (($c4.faltantes -join ',') -eq 'divida')) 'R4: F2 ausente (so rating/RI) => DEFERIDO faltante divida'

$r5 = New-Res @((New-FonteOk 'emissor' 'Z empresa contexto'), (New-FonteOk 'divida' 'Z divida debentures'), (New-FonteOk 'fato' 'Z CVM fato relevante', 'nada na janela apos checar CVM e imprensa')) @()
$c5 = Resolve-VixCoberturaFamilias $r5
Assert-True ($c5.ok -and $c5.n_provas -eq 3) 'R5: 3 familias ok => NENHUM legitimo (pesquisada sem evento)'

$r6 = New-Res @((New-FonteOk 'emissor' 'V contexto'), (New-FonteOk 'divida' 'V debentures', 'emissao de R$ 1,4 bi confirmada'), (New-FonteOk 'fato' 'V CVM fato relevante')) @([pscustomobject]@{ classificacao = 'RELEVANTE'; titulo = 'x'; data_evento = '2026-09-08' })
$c6 = Resolve-VixCoberturaFamilias $r6
Assert-True ($c6.ok) 'R6: 3 familias ok com evento => sem DEFERIDO por cobertura'
$__g6 = ('RELEVANTE' -in @('NENHUM', 'ECO', '')) -and (@($r6.eventos).Count -eq 0)
Assert-True (-not $__g6) 'R6b: com evento presente o gate de ausencia (NENHUM/ECO sem evento) nao dispara'

Write-Host '== PROVAFALSA1 (texto do modelo sem campos mecanicos nao prova busca) =='
$rf = New-Res @((New-FonteProsa 'Vibra Energia setembro 2026 debentures rating' 'sem retorno - limite backend'), (New-FonteProsa 'Vibra Energia noticias' 'sem eventos na janela')) @()
$cf = Resolve-VixCoberturaFamilias $rf
Assert-True ($cf.n_provas -eq 0) 'PF1: prova falsa (texto sem mecanica) => 0 provas validas'
Assert-True (-not $cf.ok -and ($cf.faltantes -join ',') -eq 'emissor,divida,fato') 'PF1b: prova falsa => todas familias faltantes (DEFERIDO), nunca NENHUM'

Write-Host '== Contrato: merge idempotente (sem duplicar) =='
$ct = @{}
Merge-VixContratoCobertura $ct 'Vibra Energia' 'DEFERIDO' @('divida')
Merge-VixContratoCobertura $ct 'Vibra Energia' 'DEFERIDO' @('divida', 'fato')
Assert-True ($ct.Count -eq 1) 'C1: mesma empresa mergeada 2x => 1 entrada (sem duplicar)'
Assert-True ((($ct[(Get-NomeNormalizado 'Vibra Energia')].faltantes) -join ',') -eq 'divida,fato') 'C2: ultimo merge atualiza faltantes'

Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
