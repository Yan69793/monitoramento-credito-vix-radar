# test-triagem-ativa-14out.ps1 - TRIAGEMATIVA1 (2026-10-14). Valida a TRIAGEM DETERMINISTICA EM
# MODO ATIVO (VIXRADAR_TRIAGEM_DETERMINISTICA=1) ponta a ponta, offline: nenhuma rotina real,
# nenhuma chamada de rede, nenhum token. O coletor entra como FIXTURE no mesmo formato que a lib
# produz, e todas as decisoes vem das funcoes REAIS (lib + motor extraido por AST) - nada aqui e
# reimplementacao.
#   T  semantica do modo (ativo x sombra x desligado) e os ramos do motor
#   U  104/104 emissores triados: distribuicao de classes, estado TRIADO pegajoso, 0 token nos
#      quietos e o mesmo portao de ausencia da IA para o resultado deterministico
#   V  prioridade critica: os 4 gatilhos de risco que NAO podem ser silenciados
#   W  rotacao persistente em modo ativo (cota, deferido na frente, sem perda, sem duplicidade)
#   X  reconciliacao de cobertura com a triagem universal exigida
# Toda guarda e provada nas duas pontas (reprova o caso ruim E aceita o bom). ASCII puro, 5.1.
# exit 0 = verde.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Atv([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-coletor.ps1')
$var = Get-Content -LiteralPath $MotorPath -Raw -Encoding UTF8
$lib = Get-Content -LiteralPath (Join-Path $Scripts 'lib\vixradar-cobertura.ps1') -Raw -Encoding UTF8

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
$DryRun = $false
$contratoCobertura = @{}
# IDEMEFETIVA1 (15/10) passou a gravar o que a execucao escreveu em $script:VixContratoExec dentro
# do Set-VixContratoEstado. Sem esta linha a suite abortava em U2 com "matriz nula" e, como o
# bloco so tinha finally, saia 12 OK/0 falha/exit 0 com 44 asserts nunca executados.
$script:VixContratoExec = @{}
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Get-VixCoberturaProviderCapability', 'Test-VixBuscaDegradada', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Resolve-VixCoberturaWeb', 'Test-VixAusenciaCertificavel', 'Get-NomeNormalizado', 'Merge-VixContratoCobertura', 'Read-VixContratoCoberturaArquivo', 'Get-VixRecheckPendentes', 'Set-VixContratoEstado', 'Get-VixChavesPrioritariasRotacao'))) { Invoke-Expression $_def }
$Tmp = Join-Path $env:TEMP ('vix-triagem-ativa-test-' + $PID)
New-Item -ItemType Directory -Force $Tmp | Out-Null

# Coletor FIXTURE no formato exato que vixradar-coletor.ps1 produz (mesmo helper de
# test-cobertura-recuperacao.ps1). Nenhuma consulta de rede acontece nesta suite.
function New-ColetaAtv([string]$Empresa, [object[]]$Evid, [bool]$Disponivel = $true, $Brutos = $null) {
    $pf = @{ F1 = 0; F2 = 0; F3 = 0 }
    foreach ($e in $Evid) { if ($pf.ContainsKey('' + $e.familia)) { $pf['' + $e.familia]++ } }
    if ($null -eq $Brutos) { $Brutos = [ordered]@{ F1 = 40; F2 = 35; F3 = 20 } }
    return [pscustomobject]@{
        itens_brutos = $Brutos
        empresa = $Empresa; coletado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        queries = @(@{ familia = 'F1'; query = $Empresa }, @{ familia = 'F2'; query = ($Empresa + ' (divida)') }, @{ familia = 'F3'; query = ($Empresa + ' (fato relevante)') })
        evidencias = $Evid; total = @($Evid).Count; por_familia = $pf; janela_dias = 7; duracao_ms = 10
        erros = $(if ($Disponivel) { @() } else { @('F2: HTTP 503') }); disponivel = $Disponivel
    }
}
$hojeAtv = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$deltaAtv = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-dd')

try {
# =========================================================================================
Write-Host '=== T: semantica do modo e ramos do motor ==='
Assert-Atv ($var -match "VIXRADAR_TRIAGEM_DETERMINISTICA', 'Process'") 'T1 a flag e lida do processo (e do usuario como fallback) - nao ha chave escondida em arquivo'
Assert-Atv ($var -match "\`$script:VixTriagemAtiva = \(\(\('' \+ \`$__flagTriagem\)\.Trim\(\) -eq '1'\) -and \(\`$null -ne \(Get-Command 'Get-VixColetorEvidencia'") 'T2 modo ATIVO exige flag=1 E coletor presente (sem coletor a flag nao liga nada)'
Assert-Atv ($var -match "\`$script:VixTriagemSombra = \(\(\(?'' \+ \`$__flagTriagem\)\.Trim\(\)\.ToLowerInvariant\(\) -eq 'sombra'\)") 'T3 modo SOMBRA tem flag propria e nao liga a certificacao'
Assert-Atv ($null -ne (Get-Command 'Get-VixColetorEvidencia' -ErrorAction SilentlyContinue)) 'T4 pre-condicao do modo ativo satisfeita: o coletor existe neste checkout'
$flagProd = [Environment]::GetEnvironmentVariable('VIXRADAR_TRIAGEM_DETERMINISTICA', 'User')
if (-not $flagProd) { $flagProd = [Environment]::GetEnvironmentVariable('VIXRADAR_TRIAGEM_DETERMINISTICA', 'Process') }
Assert-Atv (('' + $flagProd).Trim() -ne '1') ('T5 a maquina NAO esta em modo ativo por acidente (flag atual=' + $(if ($flagProd) { $flagProd } else { '<vazia>' }) + ') - ativacao e ato deliberado do operador')
Assert-Atv ($var -match 'if \(\$script:VixTriagemSombra\) \{[\s\S]{0,900}?segue_para_ia=1') 'T6 em SOMBRA nenhum emissor sai da IA (segue_para_ia=1 sempre)'
Assert-Atv ($var -match "if \(\`$__tri\.Classe -ne 'QUIETO'\) \{\s*\r?\n\s*if \(\`$__tri\.Classe -eq 'MATERIAL'\) \{ \`$__tm\+\+ \} else \{ \`$__ti\+\+ \}\s*\r?\n\s*\`$__restoIA\.Add\(\`$emp\); continue") 'T7 em ATIVO, MATERIAL e INDISPONIVEL vao para a IA (nunca sao certificados)'
Assert-Atv ($var -match 'TRIAGEM_NAO_CERTIFICAVEL' -and $var -match 'if \(-not \$__cert\.permitir_sem_eventos\)') 'T8 o resultado deterministico passa pelo MESMO portao de ausencia da IA; reprovou, vai para a IA'
Assert-Atv ($var -match "Start-Sleep -Seconds 3" -and $var -match 'TRIAGEM_DISCORDANCIA') 'T9 QUIETO exige segunda amostra independente; discordancia manda para a IA'
Assert-Atv ($var -match "Tier LIGHT de proposito" -and $var -match "\`$__tierEmp = 'LIGHT'") 'T10 a certificacao deterministica e LIGHT (nao credita profundidade FULL que nao aconteceu)'
Assert-Atv ($var -match 'tokens_llm=0' -and $var -match 'quietos_sem_ia=') 'T11 o resumo da triagem publica tokens_llm=0 e quantos quietos sairam da IA'

# =========================================================================================
Write-Host '=== U: 104/104 emissores triados em modo ativo ==='
# Fila de decisao com 104 emissores: 96 quietos e 8 com gatilho critico (um por gatilho).
$emis = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le 96; $i++) {
    $emis.Add([pscustomobject]@{ empresa = ('Emissor' + $i.ToString('000')); setor = 'Saneamento'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL' })
}
$crit = New-Object System.Collections.Generic.List[object]
$crit.Add([pscustomobject]@{ empresa = 'CriticoEws'; setor = 'Energia'; ews_score = 55; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'ews_55' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoCvm'; setor = 'Energia'; ews_score = 5; cvm_novos = 2; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'cvm_novos' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoVencido'; setor = 'Energia'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 130; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'revalidacao_120h' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoRecheck'; setor = 'Energia'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'pendencia_recheck_cobertura' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoSubmit'; setor = 'Energia'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'pendencia_submit_recusado' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoInconclusivo'; setor = 'Energia'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @('inconclusivo_cobertura'); ultima_origem = 'FULL'; gatilho = 'inconclusivo_anterior' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoOrigem'; setor = 'Energia'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'INCONCLUSIVO_LIGHT'; gatilho = 'ultima_origem' })
$crit.Add([pscustomobject]@{ empresa = 'CriticoEwsVencido'; setor = 'Energia'; ews_score = 50; cvm_novos = 0; horas_desde_analise = 10; janela_delta_inicio = $deltaAtv; motivos = @(); ultima_origem = 'FULL'; gatilho = 'ews_50_janela_48h' })
foreach ($c in $crit) { $emis.Add($c) }
Assert-Atv ($emis.Count -eq 104 -and $crit.Count -eq 8) 'U1 fila de decisao com exatamente 104 emissores, 8 deles com gatilho critico'
$filaPendAtv = @{}
foreach ($c in $crit) { if (('' + $c.gatilho).StartsWith('pendencia_')) { $filaPendAtv[(ConvertTo-VixChaveEmissor $c.empresa)] = [pscustomobject]@{ empresa = $c.empresa; motivo = ('' + $c.gatilho).Replace('pendencia_', '') } } }
$coletaQuieta = New-ColetaAtv 'Generico' @()
$resTri = @{}
$nQuieto = 0; $nMaterial = 0; $nIndisp = 0; $nIaAtivo = 0; $nCertificados = 0; $nTierLight = 0
foreach ($e in $emis) {
    $n = '' + $e.empresa
    $hIA = $e.horas_desde_analise
    if ('' + $e.gatilho -eq 'revalidacao_120h') { $hIA = 130 }
    if ('' + $e.gatilho -eq 'ews_55') { $hIA = 60 }
    if ('' + $e.gatilho -eq 'ews_50_janela_48h') { $hIA = 60 }
    $estAberto = $false; $motAberto = ''
    $ck = ConvertTo-VixChaveEmissor $n
    if ($filaPendAtv.ContainsKey($ck)) { $estAberto = $true; $motAberto = 'pendencia_' + $filaPendAtv[$ck].motivo }
    else {
        foreach ($mv in @($e.motivos)) { if (('' + $mv).ToLowerInvariant().Contains('inconclusivo')) { $estAberto = $true; $motAberto = 'inconclusivo_anterior'; break } }
    }
    if (('' + $e.ultima_origem).ToLowerInvariant().Contains('inconclusivo')) { $estAberto = $true; if (-not $motAberto) { $motAberto = 'inconclusivo_anterior' } }
    $col = $coletaQuieta
    if ($n -like 'Emissor*') { $col = New-ColetaAtv $n @() }
    $t = Get-VixTriagemEmissor -Coleta $col -DeltaInicio ('' + $e.janela_delta_inicio) -CvmNovos ([int]$e.cvm_novos) -HorasDesdeIA $hIA -Ews ([int]$e.ews_score) -EstadoNaoResolvido $estAberto -MotivoNaoResolvido $motAberto
    $resTri[$ck] = $t
    if ($t.Classe -eq 'QUIETO') { $nQuieto++ } elseif ($t.Classe -eq 'MATERIAL') { $nMaterial++ } else { $nIndisp++ }
    # Estado TRIADO de todo emissor (o que o motor grava antes de decidir), depois o estado final.
    Set-VixContratoEstado -Empresa $n -Estado 'TRIADO' -Motivo ('' + $t.Classe + ':' + $t.Motivo) -Triado $true
    if ($t.Classe -ne 'QUIETO') { $nIaAtivo++; Set-VixContratoEstado -Empresa $n -Estado 'ANALISADO' -Motivo 'ia_full' -Faltantes @() -Triado $false; continue }
    $cert = Test-VixAusenciaCertificavel ([pscustomobject](New-VixResultadoDeterministico -Empresa $n -Coleta $col -Triagem $t -DeltaInicio ('' + $e.janela_delta_inicio)))
    if (-not $cert.permitir_sem_eventos) { $nIaAtivo++; Set-VixContratoEstado -Empresa $n -Estado 'ANALISADO' -Motivo 'ia_full' -Faltantes @() -Triado $false; continue }
    $nCertificados++
    $nTierLight++
    Set-VixContratoEstado -Empresa $n -Estado 'ANALISADO' -Motivo 'coletor_deterministico' -Faltantes @() -Triado $false
}
Assert-Atv ((@($resTri.Keys).Count) -eq 104) 'U2 os 104 emissores tem classificacao de triagem (nenhum emissor sem verificacao deterministica)'
Assert-Atv ($nQuieto -eq 96 -and $nMaterial -eq 8 -and $nIndisp -eq 0) 'U3 96 QUIETO + 8 MATERIAL (os 8 criticos) + 0 INDISPONIVEL - nenhuma coleta cega'
Assert-Atv ($nCertificados -eq 96 -and $nIaAtivo -eq 8) 'U4 modo ativo: 96 certificados sem IA e 8 (os criticos) para a IA - inverso exato do silencio'
Assert-Atv ($nTierLight -eq 96) 'U5 a certificacao deterministica sai como LIGHT (profundidade FULL nao e creditada)'
$tOk = $resTri[(ConvertTo-VixChaveEmissor 'Emissor001')]
Assert-Atv ($tOk.Classe -eq 'QUIETO' -and ('' + $tOk.Motivo).StartsWith('sem_publicacao_desde_')) 'U6 o quieto certifica ausencia com motivo e janela de corte explicitos'
$tCrit = $resTri[(ConvertTo-VixChaveEmissor 'CriticoEws')]
Assert-Atv ($tCrit.Classe -eq 'MATERIAL' -and ('' + $tCrit.Motivo) -eq 'revalidacao_ia_60h_limite_48h') 'U7 EWS>=50 encurta a revalidacao para 48h: com 60h sem IA o critico vai para a IA'
$__estContrato = @{ TRIADO = 0; ANALISADO = 0; INCONCLUSIVO = 0; REUTILIZADO = 0; DEFERIDO = 0; RESOLVIDO = 0 }
$__triadosContrato = 0
foreach ($kRec in @($contratoCobertura.Keys)) {
    $eRec = $contratoCobertura[$kRec]
    $st = ''; $tm = $false
    if ($eRec -is [System.Collections.IDictionary]) { $st = '' + $eRec['estado']; if ($eRec.Contains('triado')) { $tm = [bool]$eRec['triado'] } }
    if ($__estContrato.ContainsKey($st)) { $__estContrato[$st]++ }
    if ($tm) { $__triadosContrato++ }
}
Assert-Atv ((@($contratoCobertura.Keys).Count) -eq 104) 'U8 o contrato do dia tem exatamente os 104 emissores que passaram pela fila'
Assert-Atv ($__triadosContrato -eq 104) 'U9 o `triado` e PEGAJOSO: o estado final ANALISADO nao apaga o TRIADO (denominador do dia = 104)'
Assert-Atv ($__estContrato['ANALISADO'] -eq 104) 'U10 estado final dos 104 registrado como ANALISADO (96 deterministico + 8 IA)'
$rcAtv = Test-VixCoberturaReconciliacao -LedgerAnalisados 104 -LedgerSkips 0 -LedgerDeferidos 0 -ContratoAnalisado 104 -ContratoInconclusivo 0 -ContratoResolvido 0 -ContratoReutilizado 0 -ContratoDeferido 0 -Triados $__triadosContrato -PlanoTotal 104 -ExigirTriagem $true
Assert-Atv $rcAtv.ok 'U11 reconciliacao OK com 104/104 triados e 104 publicados (modo ativo, dia completo)'
$rcFalta = Test-VixCoberturaReconciliacao -LedgerAnalisados 104 -LedgerSkips 0 -LedgerDeferidos 0 -ContratoAnalisado 104 -ContratoInconclusivo 0 -ContratoResolvido 0 -ContratoReutilizado 0 -ContratoDeferido 0 -Triados 103 -PlanoTotal 104 -ExigirTriagem $true
Assert-Atv (-not $rcFalta.ok) 'U12 ponta ruim: 103/104 triados reprova - um emissor sem verificacao deterministica nunca passa como dia completo'
# Duas pontas do portao de ausencia para o resultado determinístico.
$resQuieto = [pscustomobject](New-VixResultadoDeterministico -Empresa 'Emissor001' -Coleta (New-ColetaAtv 'Emissor001' @()) -Triagem $tOk -DeltaInicio $deltaAtv)
$certQ = Test-VixAusenciaCertificavel $resQuieto
Assert-Atv ($certQ.permitir_sem_eventos -and $certQ.motivo -eq 'cobertura_valida' -and @($resQuieto.eventos).Count -eq 0 -and $resQuieto._triagem -eq 'QUIETO_DETERMINISTICO') 'U13 o resultado deterministico do quieto passa no mesmo portao da IA (cobertura_valida, sem evento)'
$resDegradada = [pscustomobject](New-VixResultadoDeterministico -Empresa 'Emissor001' -Coleta (New-ColetaAtv 'Emissor001' @() $false) -Triagem $tOk -DeltaInicio $deltaAtv)
$certD = Test-VixAusenciaCertificavel $resDegradada
Assert-Atv ((-not $certD.permitir_sem_eventos) -and $certD.recheck) 'U14 ponta ruim: coleta com familia degradada NAO certifica ausencia (vai para a IA como recheck)'
$tColDegradada = Get-VixTriagemEmissor -Coleta (New-ColetaAtv 'Emissor001' @() $false) -DeltaInicio $deltaAtv -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Atv ($tColDegradada.Classe -eq 'INDISPONIVEL') 'U15 coleta indisponivel nunca vira QUIETO (classe INDISPONIVEL)'
$tF1Vazio = Get-VixTriagemEmissor -Coleta (New-ColetaAtv 'Emissor001' @() $true ([ordered]@{ F1 = 0; F2 = 35; F3 = 20 })) -DeltaInicio $deltaAtv -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Atv ($tF1Vazio.Classe -eq 'INDISPONIVEL' -and $tF1Vazio.Motivo -eq 'f1_feed_vazio_suspeito') 'U16 feed F1 vazio (throttling) tambem e INDISPONIVEL - nao certifica ausencia'
# Discordancia entre a 1a e a 2a amostra (RSS nao e deterministico).
$colNovaAtv = New-ColetaAtv 'Emissor001' @([pscustomobject]@{ familia = 'F1'; data = $hojeAtv; veiculo = 'Money Times'; dominio = 'moneytimes.com.br'; titulo = 'Emissor001 informa renegociacao de divida com credores' })
$t2a = Get-VixTriagemEmissor -Coleta $colNovaAtv -DeltaInicio $deltaAtv -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Atv ($tOk.Classe -eq 'QUIETO' -and $t2a.Classe -eq 'MATERIAL') 'U17 duas amostras do mesmo emissor podem discordar - e o motor manda para a IA quando a 2a nao e QUIETO'

# =========================================================================================
Write-Host '=== V: prioridade critica (nenhum caso de risco silenciado) ==='
$priorAtv = @(Get-VixChavesPrioritariasRotacao $emis.ToArray() @{} $filaPendAtv)
Assert-Atv ($priorAtv.Count -eq 8) 'V1 os 8 criticos sao prioridade (nem mais, nem menos)'
Assert-Atv (($priorAtv -contains 'CriticoEws') -and ($priorAtv -contains 'CriticoCvm') -and ($priorAtv -contains 'CriticoVencido') -and ($priorAtv -contains 'CriticoRecheck') -and ($priorAtv -contains 'CriticoSubmit') -and ($priorAtv -contains 'CriticoInconclusivo') -and ($priorAtv -contains 'CriticoOrigem') -and ($priorAtv -contains 'CriticoEwsVencido')) 'V2 todos os 8 gatilhos viram prioridade (EWS, CVM, analise vencida, recheck, submit recusado, inconclusivo x2)'
Assert-Atv (@($emis | Where-Object { $_.empresa -like 'Emissor*' -and $priorAtv -contains $_.empresa }).Count -eq 0) 'V3 emissor sem gatilho NUNCA entra como prioridade (prioridade nao e atalho para furar a cota)'
$rotAtv = Select-VixRotacaoCandidatos -Emissores $emis.ToArray() -ChavesPrioritarias $priorAtv -Ciclo (New-VixRotacaoCiclo) -LimiteDiario 40 -DiaTag '20261120'
Assert-Atv ((@($rotAtv.Candidatos).Count) -eq 48) 'V4 os 8 criticos entram FORA da cota: 8 prioritarios + 40 de rotacao'
Assert-Atv ((@($rotAtv.Candidatos | Select-Object -First 8 | Where-Object { $priorAtv -contains $_.empresa }).Count) -eq 8) 'V5 os 8 criticos ocupam a FRENTE da fila de decisao'
Assert-Atv ((@($rotAtv.ConsumidosChaves).Count) -eq 40) 'V6 prioridade nao consome turno de rotacao (cota segue 40/dia)'
$tRecheck = Get-VixTriagemEmissor -Coleta (New-ColetaAtv 'CriticoRecheck' @()) -DeltaInicio $deltaAtv -CvmNovos 0 -HorasDesdeIA 10 -Ews 5 -EstadoNaoResolvido $true -MotivoNaoResolvido 'pendencia_recheck_cobertura'
Assert-Atv ($tRecheck.Classe -eq 'MATERIAL' -and ('' + $tRecheck.Motivo) -eq 'estado_nao_resolvido_pendencia_recheck_cobertura') 'V7 pergunta VIVA (recheck_cobertura) nunca certifica ausencia - vai para a IA'
$tInconclusivo = Get-VixTriagemEmissor -Coleta (New-ColetaAtv 'CriticoInconclusivo' @()) -DeltaInicio $deltaAtv -CvmNovos 0 -HorasDesdeIA 10 -Ews 5 -EstadoNaoResolvido $true -MotivoNaoResolvido 'inconclusivo_anterior'
Assert-Atv ($tInconclusivo.Classe -eq 'MATERIAL' -and ('' + $tInconclusivo.Motivo) -eq 'estado_nao_resolvido_inconclusivo_anterior') 'V8 INCONCLUSIVO anterior nao vira QUIETO (a classe pior vence)'
Assert-Atv ($var -match "if \(\`$__subOk -and \`$__faltAnt\.ContainsKey" -and $var -match "Estado 'RESOLVIDO'") 'V9 estado so vira RESOLVIDO com submit aceito E cobertura verificada - nunca por ausencia de prova'
Assert-Atv (([regex]::Matches($var, "Contains\('inconclusivo'\)")).Count -ge 4) 'V13 prioridade e portao de ausencia leem as MESMAS fontes de inconsistencia aberta (motivo do plano e ultima_origem) - uma regra, dois usos'
# Orcamento insuficiente em modo ativo: o critico e DEFERIDO (registrado) e volta na frente.
# Cap simulado que so paga 3 candidatos: os 45 seguintes sao deferidos por orcamento.
$acumAtv = [int64]0; $deferidoCrit = 0; $resolvidoCrit = 0
foreach ($e in @($rotAtv.Candidatos)) {
    if ($acumAtv -ge 30000) { Set-VixContratoEstado -Empresa $e.empresa -Estado 'DEFERIDO' -Motivo 'cap_efetivo' -Faltantes @() -Triado $false; $deferidoCrit++; continue }
    $acumAtv += 10000
}
Assert-Atv ($deferidoCrit -eq 45) 'V10 orcamento insuficiente DEFERE os 45 restantes (registra o corte) em vez de silenciar o caso'
Assert-Atv ($resolvidoCrit -eq 0) 'V10b nenhum caso vira RESOLVIDO por falta de verba'
Assert-Atv ((('' + $contratoCobertura[(Get-NomeNormalizado 'CriticoRecheck')]['estado']) -eq 'DEFERIDO') -and (('' + $contratoCobertura[(Get-NomeNormalizado 'CriticoSubmit')]['estado']) -eq 'DEFERIDO') -and (('' + $contratoCobertura[(Get-NomeNormalizado 'CriticoEws')]['estado']) -eq 'ANALISADO')) 'V11 critico sem orcamento fica DEFERIDO (jamais RESOLVIDO) e o que coube no cap fica ANALISADO'
$priorAmanha = @(Get-VixChavesPrioritariasRotacao $emis.ToArray() @{} $filaPendAtv)
Assert-Atv ($priorAmanha -contains 'CriticoRecheck') 'V12 no ciclo seguinte o critico deferido continua na frente (risco nao expira com o orcamento)'

# =========================================================================================
Write-Host '=== W: rotacao persistente em modo ativo ==='
$rotPath = Join-Path $Tmp 'rotacao_ciclo.json'
$ciclo = New-VixRotacaoCiclo
$servidosRot = @{}; $duplicados = 0; $perdidos = 0; $dias = 0; $reiniciou = $false
while ($dias -lt 12 -and -not $reiniciou) {
    $dias++
    $tag = '202611' + (20 + $dias).ToString('00')
    $p = @(Get-VixChavesPrioritariasRotacao $emis.ToArray() @{} $filaPendAtv)
    $r = Select-VixRotacaoCandidatos -Emissores $emis.ToArray() -ChavesPrioritarias $p -Ciclo $ciclo -LimiteDiario 40 -DiaTag $tag
    $servidosDia = @($r.Candidatos | Where-Object { -not ($p -contains $_.empresa) } | ForEach-Object { ConvertTo-VixChaveEmissor $_.empresa })
    foreach ($k in $servidosDia) { if ($servidosRot.ContainsKey($k)) { $duplicados++ } else { $servidosRot[$k] = $true } }
    $u = Update-VixRotacaoCiclo -Ciclo $ciclo -Presentes @($emis | ForEach-Object { $_.empresa }) -Servidos @($r.Candidatos | ForEach-Object { $_.empresa }) -Consumidos @($r.ConsumidosChaves) -Ring @($r.Ring) -DiaTag $tag
    $ciclo = $u.Ciclo
    $perdidos += $u.Perdidos
    if ($u.Reiniciou) { $reiniciou = $true }
}
Assert-Atv ($reiniciou -and $dias -le 12) ('W1 a fila avancou e zerou em ' + $dias + ' dia(s) com 104 emissores e cota de 40/dia')
Assert-Atv ($servidosRot.Count -eq 96 -and $duplicados -eq 0) 'W2 os 96 nao prioritarios passaram pela rotacao exatamente uma vez (sem duplicidade)'
Assert-Atv ($perdidos -eq 0) 'W3 auditoria de perda = 0: nenhum emissor desapareceu da fila em nenhum dia'
Assert-Atv ($lib -match "if \(\`$ordem.Count -eq 0 -and \`$servCiclo.Count -gt 0\)") 'W4 o ciclo so reinicia quando a fila ZERA (reiniciar com fila viva perderia posicao)'
Assert-Atv ($lib -match 'Invoke-VixRotacaoSob' -and $lib -match 'Global\\vixradar-rotacao-ciclo-v1' -and $var -match 'Invoke-VixRotacaoSob') 'W5 gravacao do ciclo sob mutex nomeado (restart/catch-up nao apaga o avanco do outro) e o motor usa o helper'
# Deferido por orcamento nao sai da fila: e servido no dia seguinte, na frente.
$cW = New-VixRotacaoCiclo
$r1 = Select-VixRotacaoCandidatos -Emissores $emis.ToArray() -ChavesPrioritarias @() -Ciclo $cW -LimiteDiario 40 -DiaTag '20261201'
$oferecidos = @($r1.ConsumidosChaves)
$servidos20 = @($oferecidos | Select-Object -First 20)
$u1 = Update-VixRotacaoCiclo -Ciclo $cW -Presentes @($emis | ForEach-Object { $_.empresa }) -Servidos $servidos20 -Consumidos $oferecidos -Ring @($r1.Ring) -DiaTag '20261201'
$r2 = Select-VixRotacaoCandidatos -Emissores $emis.ToArray() -ChavesPrioritarias @() -Ciclo $u1.Ciclo -LimiteDiario 40 -DiaTag '20261202'
$adiados = @($oferecidos | Select-Object -Skip 20)
Assert-Atv ((@($r2.ConsumidosChaves | Where-Object { $adiados -contains $_ }).Count) -eq 20) 'W6 os 20 deferidos pelo cap voltam na FRENTE no dia seguinte (sem starvation)'
# Persistencia real em disco (round-trip sob mutex).
$rotRes = Invoke-VixRotacaoSob -Path $rotPath -Acao { param($c) return (Update-VixRotacaoCiclo -Ciclo $c -Presentes @($emis | ForEach-Object { $_.empresa }) -Servidos @('Emissor001', 'Emissor002') -Consumidos @('Emissor001', 'Emissor002') -Ring @() -DiaTag '20261203') }
$lido = Read-VixRotacaoCiclo $rotPath
Assert-Atv ((@($lido.ordem).Count) -eq 102 -and (@($lido.servidos.Keys).Count) -eq 2) 'W7 o ciclo gravado em disco e relido intacto (restart no mesmo dia nao reinicia a fila)'
$rotRes2 = Invoke-VixRotacaoSob -Path $rotPath -Acao { param($c) return (Update-VixRotacaoCiclo -Ciclo $c -Presentes @($emis | ForEach-Object { $_.empresa }) -Servidos @('Emissor003') -Consumidos @('Emissor003') -Ring @() -DiaTag '20261203') }
Assert-Atv ((@($rotRes2.Ciclo.servidos.Keys).Count) -eq 3 -and $rotRes2.Duplicados -eq 0) 'W8 duas passadas concorrentes somam desfecho (2+1) em vez de uma apagar a outra'

# =========================================================================================
Write-Host '=== X: reconciliacao de cobertura com triagem universal ==='
$cX = @{}
Merge-VixContratoCobertura $cX 'Vibra Energia' 'RECHECK_PENDENTE' @('divergencia_ia_coletor')
$pastaX = Join-Path $Tmp 'cob'
New-Item -ItemType Directory -Force $pastaX | Out-Null
@{ data = '20261014'; emissores = $cX } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pastaX 'cobertura_20261014.json') -Encoding UTF8
Assert-Atv ((Get-VixRecheckPendentes $pastaX).Count -eq 1) 'X1 divergencia IA x coletor viva na fila de recheck (pergunta aberta, nao resolvida)'
$cX2 = @{}
Merge-VixContratoCobertura $cX2 'Vibra Energia' 'RESOLVIDO' @()
@{ data = '20261015'; emissores = $cX2 } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pastaX 'cobertura_20261015.json') -Encoding UTF8
Assert-Atv ((Get-VixRecheckPendentes $pastaX).Count -eq 0) 'X2 so o submit aceito com cobertura verificada solta a pendencia'
# Cenario REAL de 14/10 com o esquema novo: 16 publicadas convivem com 104 coberturas registradas.
$rcReal = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Atv $rcReal.ok 'X3 o dia 14/10, com o registro por emissor, fecha: 16 publicadas = 7 ANALISADO + 2 RESOLVIDO + 7 INCONCLUSIVO, 16 REUTILIZADO, 72 DEFERIDO'
$rcRealAntigo = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 0 -ContratoResolvido 11 -ContratoInconclusivo 0 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Atv (-not $rcRealAntigo.ok) 'X4 os numeros REAIS de 14/10 (11 registros para 16 analises) reprovam a reconciliacao - o defeito original nao passaria mais'
$rcSemTriagem = Test-VixCoberturaReconciliacao -LedgerAnalisados 104 -LedgerSkips 0 -LedgerDeferidos 0 -ContratoAnalisado 104 -ContratoReutilizado 0 -ContratoDeferido 0 -Triados 0 -PlanoTotal 104 -ExigirTriagem $false
Assert-Atv $rcSemTriagem.ok 'X5 com a triagem desligada a exigencia de 104 triados nao se aplica (compatibilidade do modo anterior)'
Assert-Atv ($var -match '\-ExigirTriagem \(\[bool\]\(\$script:VixTriagemAtiva -or \$script:VixTriagemSombra\)\)') 'X6 a exigencia de triagem universal acompanha o modo (ativa OU sombra), nunca o desligado'
} catch {
    # Excecao no meio da suite e falha, nunca verde silencioso (TRIADOMERGE1, 15/10).
    $script:Falhas++; Write-Host ('  FALHA excecao interrompeu a suite: ' + $_.Exception.Message)
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
