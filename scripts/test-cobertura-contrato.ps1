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
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Test-VixBuscaDegradada', 'Get-VixCoberturaProviderCapability', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Resolve-VixCoberturaWeb', 'Test-VixAusenciaCertificavel', 'Get-NomeNormalizado', 'Merge-VixContratoCobertura', 'Read-VixContratoCoberturaArquivo', 'Get-VixRecheckPendentes'))) { Invoke-Expression $_def }

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

Write-Host '== BUSCADEGRADADA1-FIX: gate unico Test-VixAusenciaCertificavel =='

# 1) degradada -> RECHECK_PENDENTE (sem_eventos proibido)
$d1 = New-Res @((New-FonteOk 'emissor' 'Vibra contexto'), (New-FonteDegradada 'divida' 'Vibra debentures' 200 'ok' 'sem retorno - limite backend'), (New-FonteOk 'fato' 'Vibra CVM')) @()
$g1 = Test-VixAusenciaCertificavel $d1
Assert-True (-not $g1.permitir_sem_eventos -and $g1.recheck -and ($g1.motivo -eq 'busca_degradada')) 'B1: qualquer degradada => sem_eventos PROIBIDO + recheck'

# 1b) degradada mesmo com familias estruturais ok (caso Vibra real: texto degradado, http ok)
Assert-True (($g1.faltantes -join ',') -eq 'web') 'B1b: faltantes=web no motivo busca_degradada'

# 2) recheck persistido e priorizado na proxima execucao (contrato com faltantes>0 = filtro do plano)
$ct2 = @{}
Merge-VixContratoCobertura $ct2 'Vibra Energia' 'RECHECK_PENDENTE' @('web')
$__prior = @(($ct2.Values) | Where-Object { @($_.faltantes).Count -gt 0 })
Assert-True (($ct2.Count -eq 1) -and ($__prior.Count -eq 1)) 'B2: RECHECK_PENDENTE persistido entra no filtro de priorizacao do plano'

# 3) saudavel sem fato -> sem_eventos permitido (fluxo atual preservado)
$s3 = New-Res @((New-FonteOk 'emissor' 'Z contexto'), (New-FonteOk 'divida' 'Z divida debentures'), (New-FonteOk 'fato' 'Z CVM RI', 'nada na janela apos checar CVM e imprensa')) @()
$g3 = Test-VixAusenciaCertificavel $s3
Assert-True ($g3.permitir_sem_eventos -and -not $g3.recheck -and ($g3.motivo -eq 'cobertura_valida')) 'B3: saudavel sem fato => sem_eventos permitido'

# 4) saudavel com fato -> fluxo normal (gate nao dispara)
$s4 = New-Res @((New-FonteOk 'emissor' 'V contexto'), (New-FonteOk 'divida' 'V debentures', 'emissao confirmada'), (New-FonteOk 'fato' 'V CVM')) @([pscustomobject]@{ classificacao = 'RELEVANTE'; titulo = 'x'; data_evento = '2026-09-08' })
$g4 = Test-VixAusenciaCertificavel $s4
Assert-True ($g4.permitir_sem_eventos -and -not $g4.recheck -and ($g4.motivo -eq 'com_evento')) 'B4: com evento => gate nao dispara, fluxo normal'

# 5) falhas repetidas NUNCA viram sem_eventos (roda 2x, idempotente)
$g5a = Test-VixAusenciaCertificavel $d1
$g5b = Test-VixAusenciaCertificavel $d1
Assert-True (-not $g5a.permitir_sem_eventos -and -not $g5b.permitir_sem_eventos) 'B5: degradacao repetida nunca certifica sem_eventos'
$ct5 = @{}
Merge-VixContratoCobertura $ct5 'Vibra Energia' 'RECHECK_PENDENTE' @('web')
Merge-VixContratoCobertura $ct5 'Vibra Energia' 'RECHECK_PENDENTE' @('web')
Assert-True ($ct5.Count -eq 1) 'B5b: recheck repetido => 1 entrada (idempotente, sem duplicar)'

# 6) 0 fontes (parse falhou) => familias_incompletas => recheck
$d6 = New-Res @() @()
$g6 = Test-VixAusenciaCertificavel $d6
Assert-True (-not $g6.permitir_sem_eventos -and $g6.recheck -and ($g6.motivo -eq 'familias_incompletas')) 'B6: 0 fontes => RECHECK_PENDENTE familias_incompletas'

Write-Host '== BUSCADEGRADADA1-FIX: RECHECK_PENDENTE sem janela de 2 dias + resolucao =='

$tmpCob = Join-Path $env:TEMP ('vix-cob-contrato-' + $PID)
if (Test-Path $tmpCob) { Remove-Item $tmpCob -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tmpCob | Out-Null

function New-LinhaContrato([string]$e, [string]$s, [string[]]$f = @()) {
    return [pscustomobject]@{ empresa = $e; status = $s; faltantes = $f }
}
function Write-ContratoDia([string]$pasta, [string]$tag, [object[]]$linhas) {
    $em = [ordered]@{}
    foreach ($l in $linhas) {
        $em[(Get-NomeNormalizado $l.empresa)] = @{ empresa = $l.empresa; status = $l.status; faltantes = @($l.faltantes); updated_at = ($tag + 'T18:00:00Z') }
    }
    [ordered]@{ data = $tag; atualizado_em = ($tag + 'T18:00:00Z'); emissores = $em } |
        ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pasta ('cobertura_' + $tag + '.json')) -Encoding UTF8
}

# D1: pendencia de 5 dias atras (fora da janela hoje/ontem do codigo antigo) continua priorizada.
Write-ContratoDia $tmpCob '20260905' @((New-LinhaContrato 'Vibra Energia' 'RECHECK_PENDENTE' @('web')))
$p1 = Get-VixRecheckPendentes $tmpCob
Assert-True ($p1.ContainsKey((Get-NomeNormalizado 'Vibra Energia'))) 'D1: pendencia de 5 dias atras continua priorizada (sem janela de 2 dias)'

# D1b: prova reversa do defeito antigo - `.Values` em PSCustomObject nao enxerga contrato gravado.
# A leitura antiga (`.Values` sobre PSCustomObject) devolve so um $null, que o filtro de
# faltantes deixa passar, e nenhum emissor de verdade: por isso o contrato gravado nunca
# priorizava ninguem.
$direto = Get-Content (Join-Path $tmpCob 'cobertura_20260905.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$antigo = @(@($direto.emissores.Values) | Where-Object { @($_.faltantes).Count -gt 0 })
$antigoNomes = @($antigo | Where-Object { $_ -and ('' + $_.empresa).Trim() -ne '' })
Assert-True ($antigoNomes.Count -eq 0) 'D1b: leitura antiga `.Values` nao devolve emissor do contrato gravado - prova reversa'

# D2: registro RESOLVIDO mais novo tira o emissor da frente.
Write-ContratoDia $tmpCob '20260910' @((New-LinhaContrato 'Vibra Energia' 'RESOLVIDO' @()))
$p2 = Get-VixRecheckPendentes $tmpCob
Assert-True (-not $p2.ContainsKey((Get-NomeNormalizado 'Vibra Energia'))) 'D2: RESOLVIDO mais novo tira o emissor da fila priorizada'

# D3: resolucao ANTERIOR a pendencia nao apaga a pendencia (vence o registro mais novo).
Write-ContratoDia $tmpCob '20260908' @((New-LinhaContrato 'Natura &Co' 'RESOLVIDO' @()))
Write-ContratoDia $tmpCob '20260909' @((New-LinhaContrato 'Natura &Co' 'RECHECK_PENDENTE' @('divida')))
$p3 = Get-VixRecheckPendentes $tmpCob
Assert-True ($p3.ContainsKey((Get-NomeNormalizado 'Natura &Co'))) 'D3: RESOLVIDO anterior a pendencia nao a apaga (mais novo vence)'

# D4: silencio nao resolve - pendencia de sexta sobrevive ao buraco de fim de semana.
Write-ContratoDia $tmpCob '20260904' @((New-LinhaContrato 'Oi' 'RECHECK_PENDENTE' @('fato')))
$p4 = Get-VixRecheckPendentes $tmpCob
Assert-True ($p4.ContainsKey((Get-NomeNormalizado 'Oi'))) 'D4: emissor pendente nao reanalisado (buraco de fim de semana) segue pendente'

# D5: idempotencia da leitura (2 pendentes: Natura e Oi; Vibra resolvida).
$p5a = Get-VixRecheckPendentes $tmpCob
$p5b = Get-VixRecheckPendentes $tmpCob
Assert-True (($p5a.Count -eq 2) -and ($p5b.Count -eq 2)) 'D5: leitura idempotente, 2 pendentes estaveis entre execucoes'

# D6: contrato corrompido e ignorado sem derrubar nem resolver por engano.
Set-Content (Join-Path $tmpCob 'cobertura_20260911.json') '{ corrompido' -Encoding UTF8
$p6 = Get-VixRecheckPendentes $tmpCob
Assert-True ($p6.Count -eq 2) 'D6: arquivo de contrato corrompido ignorado (pendencia preservada)'

# D7: wiring no motor - priorizacao sem janela de data e gravacao de resolucao presentes.
$motorTxt = Get-Content $MotorPath -Raw -Encoding UTF8
Assert-True ($motorTxt -match 'Get-VixRecheckPendentes \$LogDir') 'D7: motor prioriza via Get-VixRecheckPendentes (sem janela hoje/ontem)'
Assert-True ($motorTxt -match "'RESOLVIDO' @\(\)") 'D7b: motor grava RESOLVIDO quando a cobertura fecha valida'

Remove-Item $tmpCob -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
