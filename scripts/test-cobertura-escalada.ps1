# test-cobertura-escalada.ps1 - COBERTURA-13OUT4 (2026-10-13)
# Prova deterministica, offline, sem token e sem rede da escalada seletiva por emissor:
#   E decisao de escalada: cada gatilho escala, e o caso sem gatilho NAO escala (duas pontas)
#   P prioridade e dedup da fila de escalada (risco manda na hora de cortar por orcamento)
#   T prompt: lote de escalada TEM ferramenta e lote barato NAO tem (duas pontas, texto real)
#   O orcamento: quantos cabem, e o que sobra e pendencia obrigatoria (nunca OK)
#   Q coleta incompleta e INCONCLUSIVO nunca viram QUIETO
#   R recuperacao: 3 execucoes encadeadas com escalada, sem duplicar e sem perder emissor
#   G guardas estruturais no motor (ligacao da escalada na rodada barata)
# SIMULACAO != EXECUCAO REAL: as partes O e R exercitam as funcoes da lib com custos
# ficticios. Elas NAO provam o custo real do modo FULL, que so a proxima execucao mede.
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Esc([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-custo.ps1')
. (Join-Path $Scripts 'lib\vixradar-profundidade.ps1')
$Tmp = Join-Path $env:TEMP ('vix-escalada-test-' + $PID)
New-Item -ItemType Directory -Force $Tmp | Out-Null

# Funcoes do motor extraidas por AST, a mesma tecnica de test-varredura-defeitos.ps1 e
# test-cobertura-recuperacao.ps1: o teste roda a funcao REAL, nao uma copia.
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
$tk = $null; $er = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($MotorPath, [ref]$tk, [ref]$er)
foreach ($fn in @('New-BatchPrompt', 'Get-SlimEmissor', 'Get-VixColetorParaEmissor')) {
    $d = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1
    if ($d) { Invoke-Expression $d.Extent.Text } else { Write-Host ('  info  funcao do motor ausente: ' + $fn) }
}
# Estado que as funcoes do motor leem do escopo do script.
$script:VixColetorAtivo = $false
$script:VixTriagemDados = @{}
$script:VixColetorCache = @{}
$script:VixColetorFalhas = @{}
$EwsContextoCritico = 38
$Perfil = @{ tier = 'LIGHT' }
$SkillFake = Join-Path $Tmp 'skill-fake.md'
Set-Content -LiteralPath $SkillFake -Value 'SKILL DE TESTE (COBERTURA1 F1-emissor F2-divida F3-fato FEEDRETRO1 FONTEDIVERG1)' -Encoding UTF8

function New-EmpFake([string]$Nome, [int]$Ews = 30, [int]$CvmNovos = 0) {
    return [pscustomobject][ordered]@{
        empresa = $Nome; setor = 'Teste'; tier = 'LIGHT'; ews_score = $Ews; cvm_novos = $CvmNovos
        cvm_documentos = @(); ultimo_evento_data = '2026-09-01'; eventos_conhecidos = 3
        janela_delta_inicio = '2026-10-10'; contexto_historico = 'ctx'; horas_desde_analise = 20; motivos = @('d')
    }
}
$hoje = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
function New-NovaFake([string]$Titulo, [string]$Veiculo = 'Money Times', [string]$Dominio = 'moneytimes.com.br') {
    return [pscustomobject]@{ familia = 'F1'; data = $hoje; veiculo = $Veiculo; dominio = $Dominio; titulo = $Titulo }
}

try {
# ------------------------------------------------------------------------------------
Write-Host '=== E: decisao de escalada (duas pontas por gatilho) ==='
$dNada = Get-VixEscaladaDecisao -Classificacao 'ECO' -Eventos 0 -Ews 30 -Novas @()
Assert-Esc ((-not $dNada.Escalar) -and $dNada.Motivo -eq 'sem_gatilho_de_escalada') 'E1 emissor fechado pela rodada barata NAO escala (ponta boa)'
Assert-Esc ($dNada.Prioridade -eq 0) 'E2 sem gatilho a prioridade e zero (nao entra em fila por engano)'

$dCol = Get-VixEscaladaDecisao -Classificacao 'NENHUM' -ColetaIndisponivel $true
Assert-Esc ($dCol.Escalar -and $dCol.Motivo -eq 'coleta_indisponivel' -and $dCol.Prioridade -eq 100) 'E3 coleta indisponivel escala com a maior prioridade (regra 5)'
$dDiv = Get-VixEscaladaDecisao -Classificacao 'NENHUM' -DivergenciaColetor $true
Assert-Esc ($dDiv.Escalar -and $dDiv.Motivo -eq 'divergencia_ia_coletor' -and $dDiv.Prioridade -eq 90) 'E4 divergencia IA x coletor escala'
$dEws = Get-VixEscaladaDecisao -Classificacao 'ECO' -Ews 50
Assert-Esc ($dEws.Escalar -and $dEws.Motivo -eq 'ews_critico_50' -and $dEws.Prioridade -eq 80) 'E5 EWS critico (>=50) escala'
Assert-Esc (-not (Get-VixEscaladaDecisao -Classificacao 'ECO' -Ews 49).Escalar) 'E6 ponta oposta: EWS 49 nao escala por EWS'
$dCvm = Get-VixEscaladaDecisao -Classificacao 'ECO' -CvmNovos 2 -Ews 10
Assert-Esc ($dCvm.Escalar -and $dCvm.Motivo -eq 'cvm_novos_2' -and $dCvm.Prioridade -eq 70) 'E7 documento CVM novo escala'
$dInc = Get-VixEscaladaDecisao -Classificacao 'INCONCLUSIVO' -Ews 10
Assert-Esc ($dInc.Escalar -and $dInc.Motivo -eq 'recheck_cobertura' -and $dInc.Prioridade -eq 60) 'E8 INCONCLUSIVO escala (nunca fecha sem prova)'
$dRec = Get-VixEscaladaDecisao -Classificacao 'NENHUM' -RecheckPendente $true -Ews 10
Assert-Esc ($dRec.Escalar -and $dRec.Motivo -eq 'recheck_cobertura') 'E9 recheck pendente escala mesmo sem INCONCLUSIVO'
$dCrit = Get-VixEscaladaDecisao -Classificacao 'RELEVANTE' -Eventos 1 -Ews 10 -Novas @(New-NovaFake 'Emissor X pede recuperacao judicial')
Assert-Esc ($dCrit.Escalar -and $dCrit.Motivo -eq 'termo_critico' -and $dCrit.Prioridade -eq 55) 'E10 termo de estresse de credito na manchete nova escala'
$dRat = Get-VixEscaladaDecisao -Classificacao 'RELEVANTE' -Eventos 1 -Ews 10 -Novas @(New-NovaFake 'Agencia revisa nota do emissor' 'Fitch Ratings' 'fitchratings.com')
Assert-Esc ($dRat.Escalar -and $dRat.Motivo -eq 'agencia_rating' -and $dRat.Prioridade -eq 52) 'E11 agencia de rating na fonte escala'
$dEv = Get-VixEscaladaDecisao -Classificacao 'RELEVANTE' -Eventos 2 -Ews 10 -Novas @(New-NovaFake 'Emissor X anuncia investimento em nova planta')
Assert-Esc ($dEv.Escalar -and $dEv.Motivo -eq 'evento_novo_2' -and $dEv.Prioridade -eq 40) 'E12 fato novo sem termo critico escala para confirmar em fonte primaria'
$dEv0 = Get-VixEscaladaDecisao -Classificacao 'RELEVANTE' -Eventos 0 -Ews 10 -Novas @(New-NovaFake 'Emissor X anuncia investimento em nova planta')
Assert-Esc (-not $dEv0.Escalar) 'E13 ponta oposta: sem evento e sem os outros gatilhos NAO escala'
$dOrdem = Get-VixEscaladaDecisao -Classificacao 'INCONCLUSIVO' -ColetaIndisponivel $true -Ews 90
Assert-Esc ($dOrdem.Motivo -eq 'coleta_indisponivel' -and $dOrdem.Prioridade -eq 100) 'E14 o gatilho mais grave vence quando dois casam'

# ------------------------------------------------------------------------------------
Write-Host '=== P: fila de escalada: prioridade, dedup e corte por risco ==='
$filaEsc = @(
    [pscustomobject]@{ Emp = (New-EmpFake 'Baixo' 10); Prioridade = 40; Motivo = 'evento_novo_1' },
    [pscustomobject]@{ Emp = (New-EmpFake 'Critico' 90); Prioridade = 80; Motivo = 'ews_critico_90' },
    [pscustomobject]@{ Emp = (New-EmpFake 'Cvm' 20); Prioridade = 70; Motivo = 'cvm_novos_1' },
    [pscustomobject]@{ Emp = (New-EmpFake 'Critico' 90); Prioridade = 100; Motivo = 'coleta_indisponivel' }
)
$ord = @(Select-VixEscaladaOrdenada -Itens $filaEsc)
Assert-Esc ($ord.Count -eq 3) 'P1 dedup: o mesmo emissor com dois gatilhos entra uma vez so'
Assert-Esc ($ord[0].Emp.empresa -eq 'Critico' -and $ord[0].Prioridade -eq 100) 'P2 dedup mantem a MAIOR prioridade do emissor'
Assert-Esc ($ord[1].Emp.empresa -eq 'Cvm' -and $ord[2].Emp.empresa -eq 'Baixo') 'P3 ordem por risco: CVM novo antes de fato novo'
$empate = @(Select-VixEscaladaOrdenada -Itens @(
    [pscustomobject]@{ Emp = (New-EmpFake 'Zebra' 30); Prioridade = 40; Motivo = 'evento_novo_1' },
    [pscustomobject]@{ Emp = (New-EmpFake 'Alfa' 80); Prioridade = 40; Motivo = 'evento_novo_1' }
))
Assert-Esc ($empate[0].Emp.empresa -eq 'Alfa') 'P4 empate de prioridade desempata por EWS'
Assert-Esc (@(Select-VixEscaladaOrdenada -Itens @()).Count -eq 0) 'P5 fila vazia devolve vazio (sem erro)'
Assert-Esc (@(Select-VixEscaladaOrdenada -Itens @($null, [pscustomobject]@{ Emp = $null; Prioridade = 50 })).Count -eq 0) 'P6 item sem emissor e ignorado'

# ------------------------------------------------------------------------------------
Write-Host '=== T: prompt do lote de escalada x lote barato (texto real) ==='
$emp = New-EmpFake 'Emissor Teste' 60
$script:VixColetorAtivo = $true
$pBarato = New-BatchPrompt @($emp) 'lote-1' 'modelo-x' $SkillFake '2026-10-01' '2026-10-13' 'codex' -Tier 'LIGHT' -ModoBarato
$pEscalada = New-BatchPrompt @($emp) 'escalada-1' 'modelo-x' $SkillFake '2026-10-01' '2026-10-13' 'codex' -Tier 'FULL' -ModoEscalada
$pFullRot = New-BatchPrompt @($emp) 'full-1' 'modelo-x' $SkillFake '2026-10-01' '2026-10-13' 'codex' -Tier 'FULL'
Assert-Esc ($pBarato -match 'COLETOR_PS_ATIVO' -and $pBarato -match 'PROIBIDO executar WebSearch') 'T1 lote barato proibe ferramenta (ponta que NAO pode abrir a fonte)'
Assert-Esc ($pBarato -match 'LOTE_RESUMO\|buscas=0') 'T2 lote barato declara buscas=0'
Assert-Esc ($pFullRot -notmatch 'COLETOR_PS_ATIVO' -and $pFullRot -match 'web_search') 'T2b ponta oposta no mesmo flag: o lote FULL da rotacao semanal MANTEM a ferramenta com o coletor ligado'
Assert-Esc ($pEscalada -match 'ESCALADA_FULL' -and $pEscalada -notmatch 'PROIBIDO executar WebSearch') 'T3 lote de escalada TEM ferramenta e nao carrega a proibicao'
Assert-Esc ($pEscalada -match 'web_fetch na URL do fato novo') 'T4 escalada obriga abrir a fonte primaria'
Assert-Esc ($pEscalada -match 'EVIDENCIA_INDISPONIVEL, isso NUNCA certifica' -and $pEscalada -match 'INCONCLUSIVO') 'T5 escalada proibe certificar ausencia a partir de coleta indisponivel'
Assert-Esc ($pEscalada -match 'F1-emissor' -and $pEscalada -match 'F2-divida' -and $pEscalada -match 'F3-fato') 'T6 escalada mantem o contrato das tres familias'
Assert-Esc ($pEscalada -match 'status_http' -and $pEscalada -match 'PROVAFALSA1') 'T7 escalada mantem a prova de consulta executada'
Assert-Esc ($pEscalada -match 'nao invente evento para justificar a escalada') 'T8 escalada proibe inventar o fato que a justificou'
$script:VixColetorAtivo = $false
$pSemColetor = New-BatchPrompt @($emp) 'lote-1' 'modelo-x' $SkillFake '2026-10-01' '2026-10-13' 'openrouter' -Tier 'FULL' -ModoBarato
Assert-Esc ($pSemColetor -notmatch 'COLETOR_PS_ATIVO' -and $pSemColetor -match 'web_search') 'T9 ponta oposta: sem coletor o prompt normal segue com busca, mesmo num lote marcado barato'
Assert-Esc ($pSemColetor -notmatch 'ESCALADA_FULL') 'T10 prompt normal nao carrega o texto de escalada'
$script:VixColetorAtivo = $true
$pEscSemColetor = New-BatchPrompt @($emp) 'lote-1' 'modelo-x' $SkillFake '2026-10-01' '2026-10-13' 'codex' -Tier 'FULL' -ModoEscalada
Assert-Esc ($pEscSemColetor -match 'ESCALADA_FULL' -and $pEscSemColetor -notmatch 'COLETOR_PS_ATIVO') 'T11 com o coletor ligado, o lote de escalada ainda e o de ferramenta (a escalada vence o flag global)'

# ------------------------------------------------------------------------------------
Write-Host '=== O: orcamento da escalada (simulacao com custo ficticio) ==='
$capEsc = [int64]500000
$custoBase = [int64]178000
$cabem = Get-VixEmissoresQueCabem -Acum 0 -Cap $capEsc -CustoPorEmissor $custoBase -Chunk 4
Assert-Esc ($cabem -eq 2) 'O1 cap de 500k com custo medido de 178k admite 2 emissores, nao 4'
$cabemZero = Get-VixEmissoresQueCabem -Acum 400000 -Cap $capEsc -CustoPorEmissor $custoBase -Chunk 4
Assert-Esc ($cabemZero -eq 0) 'O2 ponta oposta: sem sobra de cap nenhum emissor entra'
$dEstouro = Get-VixCustoPorEmissor -ObservadosExecucao @([int64]11000) -Historico @() -Default $custoBase -Piso $custoBase
Assert-Esc ($dEstouro.Custo -eq $custoBase) 'O3 o custo observado da rodada barata NAO barateia a escalada (o piso manda)'
$dSemPiso = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @() -Default $custoBase
Assert-Esc ($dSemPiso.Fonte -eq 'default' -and $dSemPiso.Custo -eq $custoBase) 'O4 sem medicao a estimativa e o custo-base honesto, nunca zero'
# 62 emissores com gatilho contra um cap que comporta 2: o resto e pendencia obrigatoria.
$pendentes = 62 - $cabem
$resParcial = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 104 -Analisados 2 -Skips 0 -PendentesObrigatorios $pendentes -Erros 0
Assert-Esc ($resParcial.Resultado -eq 'PARCIAL' -and $resParcial.Exit -eq 10) 'O5 escalada cortada por cap NAO fecha OK: PARCIAL exit 10'
$resOk = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 104 -Analisados 104 -Skips 0 -PendentesObrigatorios 0 -Erros 0
Assert-Esc ($resOk.Resultado -eq 'OK' -and $resOk.Exit -eq 0) 'O6 ponta oposta: sem pendencia o resultado e OK'

# ------------------------------------------------------------------------------------
Write-Host '=== Q: coleta incompleta e INCONCLUSIVO nunca viram QUIETO ==='
$q1 = Get-VixEscaladaDecisao -Classificacao 'INCONCLUSIVO' -ColetaIndisponivel $true
Assert-Esc ($q1.Escalar -and $q1.Prioridade -eq 100) 'Q1 coleta incompleta: escala e nunca fecha'
$q2 = Get-VixEscaladaDecisao -Classificacao 'INCONCLUSIVO' -Eventos 0
Assert-Esc ($q2.Escalar) 'Q2 INCONCLUSIVO sempre escala, com ou sem manchete'
$q3 = Get-VixEscaladaDecisao -Classificacao 'NENHUM' -Eventos 0 -Ews 10 -Novas @()
Assert-Esc (-not $q3.Escalar) 'Q3 so o emissor com coleta completa e sem gatilho fecha sem ferramenta'
# A decisao de escalada NAO tem caminho que devolva "quieto": o unico "nao escala" e
# 'sem_gatilho_de_escalada', e ele exige que nenhum sinal de incompletude tenha chegado.
$motivos = @()
foreach ($c in @('NENHUM', 'ECO', 'CRITICO', 'RELEVANTE', 'INCONCLUSIVO')) {
    $d = Get-VixEscaladaDecisao -Classificacao $c -Eventos 0 -Ews 10
    $motivos += ('' + $d.Motivo)
}
Assert-Esc (($motivos -join ',') -notmatch 'QUIETO') 'Q4 a decisao de escalada nao tem saida QUIETO em classificacao nenhuma'

# ------------------------------------------------------------------------------------
Write-Host '=== R: recuperacao encadeada com escalada (3 execucoes) ==='
# SIMULACAO: fila persistente em disco + fila de escalada em memoria, como no motor. Cada
# "execucao" e um processo novo do Agendador, que rele a fila do disco.
$filaPath = Join-Path $Tmp 'esc_pendente.json'
$carteira = @(1..10 | ForEach-Object { New-EmpFake ('Emissor' + $_.ToString('00')) ($_ * 9) })
$material = @($carteira | Where-Object { $_.ews_score -ge 50 })   # 5 emissores com gatilho de risco
$analisados = @{}
$retidosPorExecucao = @()
function Invoke-ExecEsc([int]$Exec, [int]$CapEmissores) {
    $esc = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.List[object]
    # rodada barata: decide por emissor (funcao REAL da lib)
    foreach ($e in $carteira) {
        if ($analisados.ContainsKey($e.empresa)) { continue }
        $d = Get-VixEscaladaDecisao -Classificacao 'ECO' -Ews ([int]$e.ews_score) -Novas @()
        if ($d.Escalar) { $esc.Add([pscustomobject]@{ Emp = $e; Prioridade = [int]$d.Prioridade; Motivo = $d.Motivo }) }
        else { $analisados[$e.empresa] = $Exec }
    }
    $ord = @(Select-VixEscaladaOrdenada -Itens $esc.ToArray())
    $rodada = 0
    foreach ($item in $ord) {
        if ($rodada -ge $CapEmissores) { $pending.Add($item); continue }
        $analisados[$item.Emp.empresa] = $Exec
        $rodada++
        # Regra do motor: analise efetiva solta a pendencia persistente (Remove-VixPendenteSeguro).
        $null = Remove-VixFilaPendente -Path $filaPath -Empresa $item.Emp.empresa
    }
    foreach ($p in $pending) { Add-VixFilaPendente -Path $filaPath -Empresa $p.Emp.empresa -Prioridade $p.Prioridade -Motivo 'escalada_sem_orcamento' -Rotina 'noturno' -Tier 'FULL' -SubmitRegistrado $true }
    return @{ Retidos = $ord.Count; Analisados = $rodada; Pendentes = $pending.Count }
}
$e1 = Invoke-ExecEsc 1 2
# Execucao 2 recupera a pendencia do dia anterior ANTES da cauda nova (ordem com pendentes).
$fila = Read-VixFilaPendente $filaPath
$nomesPend = @($fila.Values | ForEach-Object { $_.empresa })
$ordemComPend = @(Select-VixOrdemComPendentes -Emissores $carteira -Fila $fila)
$e2 = Invoke-ExecEsc 2 2
$e3 = Invoke-ExecEsc 3 2
$e4 = Invoke-ExecEsc 4 2
Assert-Esc ($e1.Retidos -eq 5 -and $e1.Analisados -eq 2 -and $e1.Pendentes -eq 3) 'R1 execucao 1: 5 com gatilho, 2 escalados, 3 deferidos por cap'
Assert-Esc ($e2.Analisados -eq 2 -and $e2.Pendentes -eq 1) 'R2 execucao 2 escala os 2 primeiros que sobraram e defere 1'
Assert-Esc ($ordemComPend.Count -eq $carteira.Count -and (@($ordemComPend | Select-Object -First 3 | ForEach-Object { $_.empresa }) | Where-Object { $_ -in $nomesPend }).Count -eq 3) 'R3 a pendencia de escalada vem na frente da cauda nova e sem duplicar emissor'
Assert-Esc ($analisados.Count -eq $carteira.Count) 'R4 depois de 4 execucoes os 10 emissores foram analisados (5 escalados + 5 fechados baratos)'
Assert-Esc ((@($analisados.Keys) | Sort-Object -Unique).Count -eq $analisados.Count) 'R5 nenhum emissor analisado duas vezes'
Assert-Esc ((Read-VixFilaPendente $filaPath).Count -eq 0) 'R6 fila persistente drenada: nenhuma pendencia de escalada ficou presa'
$faltou = @($carteira | Where-Object { -not $analisados.ContainsKey($_.empresa) })
Assert-Esc ($faltou.Count -eq 0) 'R7 nenhum emissor perdido entre as execucoes'
# A ordem de prioridade sobrevive ao corte: o de maior EWS foi escalado na primeira execucao.
Assert-Esc ($analisados[(@($material | Sort-Object -Property ews_score -Descending)[0]).empresa] -eq 1) 'R8 o corte por cap respeita o risco: o maior EWS saiu na primeira execucao'

# ------------------------------------------------------------------------------------
Write-Host '=== S: escopo da retencao: so lote SEM ferramenta pode reter ==='
# A regra do motor e um predicado puro, Test-VixEscaladaRetem. Ate 13/10 esta secao provava uma
# REPLICA local do predicado, escrita a mao no proprio teste: prova de copia. Copia diverge em
# silencio no dia em que alguem muda o motor - foi assim que a prova seguia verde enquanto a
# condicao real mudava de forma. Agora ela chama a funcao REAL, a mesma que o motor chama.
$jobBarato = [ordered]@{ Tier = 'LIGHT'; Barato = $true }
$jobFullRot = [ordered]@{ Tier = 'FULL' }
$jobEscalada = [ordered]@{ Tier = 'FULL'; Escalada = $true; Barato = $true }
function Test-RetencaoReal($Job, [bool]$Ativa) {
    return (Test-VixEscaladaRetem -Ativa $Ativa -JaEscalada ([bool]$Job.Escalada) -Barato ([bool]$Job.Barato))
}
Assert-Esc (Test-RetencaoReal $jobBarato $true) 'S1 lote barato com escalada ligada retem (ponta boa)'
Assert-Esc (-not (Test-RetencaoReal $jobFullRot $true)) 'S2 lote FULL da rotacao NAO retem: ele ja abriu a fonte primaria'
Assert-Esc (-not (Test-RetencaoReal $jobEscalada $true)) 'S3 lote de escalada nao retem (nao ha recursao)'
Assert-Esc (-not (Test-RetencaoReal $jobBarato $false)) 'S5 ponta oposta: com a escalada desligada nada retem'
Assert-Esc ($jobBarato.Contains('Barato') -and -not $jobFullRot.Contains('Barato')) 'S6 o marcador distingue os dois lotes da noturna (LIGHT barato x FULL da rotacao)'

# ------------------------------------------------------------------------------------
Write-Host '=== G: ligacao da escalada no motor (guardas estruturais) ==='
$mot = Get-Content -LiteralPath $MotorPath -Raw -Encoding UTF8
# Fonte da lib, para a guarda que confere que a funcao pura existe do outro lado da ligacao.
$lib = Get-Content -LiteralPath (Join-Path $Scripts 'lib\vixradar-cobertura.ps1') -Raw -Encoding UTF8
# Guarda estrutural por substring literal (single quote: `$` nao precisa de escape). Cada uma
# aponta a linha do motor que liga a escalada; a prova de comportamento das mesmas regras esta
# nas partes E, P, T, O, Q e R deste arquivo, sobre as funcoes REAIS.
Assert-Esc ($mot.Contains('VIXRADAR_ESCALADA_FULL') -and $mot.Contains('if ($script:VixColetorAtivo -and -not $script:VixColetorObrigatorio')) 'G1 escalada e opt-out e exige o coletor ativo'
Assert-Esc ($mot.Contains('ESCALADA_DECISAO|')) 'G2 o motor loga a decisao por emissor com o motivo'
Assert-Esc ($mot.Contains('Test-VixEscaladaRetem -Ativa ([bool]$script:VixEscaladaAtiva) -JaEscalada ([bool]$job.Escalada) -Barato ([bool]$job.Barato)')) 'G3 so lote barato retem: o motor delega a decisao para a funcao pura (a prova de comportamento e W1-W4)'
Assert-Esc ($mot.Contains("if (`$script:VixColetorAtivo -and -not `$script:VixColetorObrigatorio -and (`$null -ne (Get-Command 'Get-VixEscaladaDecisao'")) 'G3b escalada fica inerte sob provedor sem ferramenta (deepseek), onde escalar nao teria como abrir a fonte'
Assert-Esc ($mot.Contains('$__escaladaFila.Add(')) 'G4 emissor com gatilho entra na fila de escalada'
Assert-Esc ($mot.Contains('$stats.escalada_retidos++')) 'G5 emissor retido na rodada barata nao e contado como analisado'
Assert-Esc ($mot.Contains('while ($__filaLotes.Count -gt 0 -or -not $__escaladaMontada) {') -and $mot.Contains('if ($__filaLotes.Count -eq 0 -and -not $__escaladaMontada) {')) 'G6 a rodada de escalada entra na MESMA fila de lotes (sem caminho paralelo)'
Assert-Esc ($mot.Contains("`$__je['Escalada'] = `$true") -and $mot.Contains("`$__je['CustoTrabalho'] = [double]`$__custoEscalada")) 'G7 lote de escalada se identifica e carrega o custo honesto'
Assert-Esc ($mot.Contains('$jobs.Add($__je)')) 'G8 lote de escalada entra em $jobs (o aborto por auth alcanca os restantes)'
Assert-Esc ($mot.Contains('escalada_sem_orcamento') -and $mot.Contains('deferred_escalada')) 'G9 corte de escalada por cap tem motivo e contador proprios'
Assert-Esc ($mot.Contains('escalada_retidos = ') -and $mot.Contains("' escalada_retidos='")) 'G10 contadores de escalada no metrics e na linha FIM'
Assert-Esc ($mot.Contains("New-VixJobsPorTier -Selecionados `$__escEmissores -Tier 'FULL'")) 'G11 a escalada roda no tier FULL'
Assert-Esc ($mot.Contains('Get-VixEscaladaDecisao -Classificacao $classif')) 'G12 a decisao usa a classificacao que o portao de ausencia ja corrigiu'
Assert-Esc ($mot.Contains('$__coletaInd = ($null -eq $__colIA)')) 'G13 coleta indisponivel medida no proprio emissor alimenta a decisao'
Assert-Esc ($mot.Contains('continue') -and ($mot.IndexOf('$__escaladaFila.Add(') -lt $mot.IndexOf('$resp = Submit-Analise $routineKey $emp.empresa'))) 'G14 o emissor retido sai antes do submit: a rodada barata nao certifica o que exige fonte primaria'
Assert-Esc ($mot.Contains('if (-not $__escaladaMontada -and $__escaladaFila.Count -gt 0) {') -and $mot.Contains('ESCALADA_ABORTO')) 'G15 aborto por auth nao deixa o emissor retido sem desfecho (nem analisado, nem deferido)'
# ENVIADOS1: o ramo de descarte PARCIAL compara `$nEv -lt $enviados` e a variavel nao existia.
$semEnviados = $null          # estado ANTES da correcao: variavel inexistente
$comEnviados = 3              # estado DEPOIS: 3 eventos enviados
Assert-Esc (-not (1 -lt $semEnviados)) 'G16 ponta ruim: com a variavel ausente, persistidos=1 de 3 enviados NAO entrava no ramo de descarte parcial'
Assert-Esc ((1 -lt $comEnviados) -and -not (3 -lt $comEnviados)) 'G17 ponta boa: com $enviados definido, 1 de 3 entra e 3 de 3 nao entra'
Assert-Esc ($mot.Contains('$enviados = @($res.eventos).Count')) 'G18 o motor define $enviados antes de comparar (ramo de descarte parcial alcancavel)'
Assert-Esc ($mot.Contains("-ModoBarato:([bool]`$job.Barato)")) 'G19 o modo barato vai para o prompt pelo lote, nao por inferencia do tier'
Assert-Esc ($mot.Contains("`$jobProf['Barato'] = `$true; `$jobs.Add(`$jobProf) }") -and $mot.Contains("`$jobProf['CustoTrabalho'] = `$custoFullNoturno; `$jobs.Add(`$jobProf) }")) 'G20 so o lote LIGHT da noturna e barato; o FULL da rotacao nao e'
Assert-Esc ($mot.Contains('Provedor = $Perfil.provedor; Barato = $true }')) 'G21 os lotes da matinal sao a rodada barata quando o coletor esta ligado'
# ------------------------------------------------------------------------------------
Write-Host '=== V: validador de homologacao (duas pontas, log sintetico) ==='
# O validador julga o log de uma execucao dirigida. Sem prova das duas pontas ele mesmo seria a
# peca menos confiavel da homologacao: aqui um log COMPLETO tem de passar e um log PARCIAL tem de
# reprovar, com o codigo da marca que faltou.
$validador = Join-Path $Scripts 'check-homologacao-escalada.ps1'
$logBom = Join-Path $Tmp 'homolog-bom.log'
$logRuim = Join-Path $Tmp 'homolog-ruim.log'
$comuns = @(
    '2026-10-14 10:00:01 COLETOR_PS: ativo=True (VIXRADAR_COLETOR_PS; 0 desliga)',
    '2026-10-14 10:00:02 ESCALADA_FULL: ativo=True (VIXRADAR_ESCALADA_FULL; 0 desliga)',
    '2026-10-14 10:00:02 ESCALADA_CUSTO_BASE: 250000/emissor (constante FULL e maximo do historico do provedor n=0)',
    '2026-10-14 10:00:20 FONTES_COLETOR|Usina Pampa Sul|fontes_do_coletor_somadas|adicionadas=3',
    '2026-10-14 10:00:20 ESCALADA_DECISAO|Usina Pampa Sul|escalar=1|evento_novo_1|prioridade=40|classif=RELEVANTE|eventos=1|ews=44|cvm_novos=0|divergencia=0|coleta_indisponivel=0',
    '2026-10-14 10:00:21 ESCALADA_LOTE: 1 emissor(es) retido(s) na rodada barata em 1 lote(s) FULL custo_base=250000/emissor; gatilhos=evento_novo_1=1',
    '2026-10-14 10:02:10 OUT: prova de que a rodada FULL voltou a abrir a fonte: {"fontes_consultadas":[{"familia":"fato","query":"https://ri.exemplo.com/fato","provedor":"codex:web_fetch"}]}',
    '2026-10-14 10:02:11 LOTE_FECHADO|escalada-2|ok=1|fail=0|dryrun=0|buscas=2|criticos=0|tokens=178306|duracao_sec=110.0',
    '2026-10-14 10:02:40 OK|Usina Pampa Sul|FULL|RELEVANTE|1|true|ANALISADO|1',
    '2026-10-14 10:03:00 FIM: noturno concluido PARCIAL (pendentes_obrigatorios=0). Total do dia 1/1',
    '2026-10-14 10:03:01 ROTINA_RESUMO|vixradar-noturno|local|2026-10-14T13:00:00Z|2026-10-14T13:03:00Z|PARCIAL|1|0|0|v4.9.266',
    '2026-10-14 10:03:01 COBERTURA_RESULTADO: PARCIAL motivo=pendentes_obrigatorios=0 resultado=PARCIAL pendentes_obrigatorios=0',
    '2026-10-14 10:03:02 escalada_retidos=1 escalada_pendentes=1 escalada_lotes=1 escalada_analisados=1 escalada_sem_orcamento=0 deferidos_escalada=0',
    # CASO-SENSIVEL1: campo que TODO log real tem e o log sintetico nao tinha. Sem ele a prova nao
    # cobria o caso em que o contador SAUDOSO `cap_excedido=0` da linha FIM e lido pelo criterio H10
    # (que procura `CAP_EXCEDIDO` com -match insensivel a caixa) como se fosse o marcador de falha.
    '2026-10-14 10:03:02 analisados=1 skip=0 deferidos=0 cap_excedido=0 provider=codex disjuntor_provider=fechado'
)
Set-Content -LiteralPath $logBom -Value ($comuns -join "`r`n") -Encoding UTF8
$ruins = @($comuns | Where-Object { $_ -notmatch 'ESCALADA_DECISAO\|' -and $_ -notmatch 'OUT: prova' -and $_ -notmatch 'OK\|Usina' })
Set-Content -LiteralPath $logRuim -Value ($ruins -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logBom -Emissor 'Usina Pampa Sul' 2>&1
$eBom = $LASTEXITCODE
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logRuim -Emissor 'Usina Pampa Sul' 2>&1
$eRuim = $LASTEXITCODE
Assert-Esc ($eBom -eq 0) ('V1 ponta boa: log completo com coleta, decisao, escalada, fonte primaria e ledger FULL APROVA (exit=' + $eBom + ')')
Assert-Esc ($eRuim -ne 0) ('V2 ponta ruim: log sem decisao, sem fetch e sem ledger FULL REPROVA (exit=' + $eRuim + ')')
$textoRuim = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logRuim -Emissor 'Usina Pampa Sul' 2>&1 | Out-String)
Assert-Esc ($textoRuim -match 'H5' -and $textoRuim -match 'H8' -and $textoRuim -match 'H9') 'V3 a reprovacao aponta QUAIS marcas faltaram (H5 decisao, H8 fonte primaria, H9 ledger FULL)'
$semSwitch = @($comuns | Where-Object { $_ -notmatch 'ESCALADA_FULL: ativo=True' })
Set-Content -LiteralPath (Join-Path $Tmp 'homolog-noswitch.log') -Value ($semSwitch -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath (Join-Path $Tmp 'homolog-noswitch.log') 2>&1
Assert-Esc ($LASTEXITCODE -ne 0) 'V4 log de execucao SEM a escalada ligada reprova (nao homologa o caminho antigo por engano)'
$comEstouro = @($comuns + '2026-10-14 10:02:30 CAP_EXCEDIDO: lote escalada-2 custou 300000 contra estimativa 250000; acum=300000 > cap=700000')
Set-Content -LiteralPath (Join-Path $Tmp 'homolog-estouro.log') -Value ($comEstouro -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath (Join-Path $Tmp 'homolog-estouro.log') 2>&1
Assert-Esc ($LASTEXITCODE -ne 0) 'V5 log com CAP_EXCEDIDO reprova (estimativa otimista nao passa por homologacao)'
# DRYRUN-HOMOLOG1 (2026-10-13): o caso que V1 nao cobria, e por isso o defeito passou. A homologacao
# da escalada E uma execucao -DryRun (o motor diz isso no proprio codigo da retencao), e nesse modo
# Write-Ledger grava 'DRYRUN|' e o FIM publica 'resultado=DRYRUN'. O log sintetico de V1 usava a
# linha de execucao real ('OK|'), entao o validador aceitava a ponta que NUNCA acontece e reprovava
# a unica que acontece. V6 e essa ponta boa em dry-run; V7 e a ponta ruim que a exigencia de
# ANALISADO protege, provando que H9 nao virou carimbo ao aceitar o prefixo DRYRUN.
$comunsDry = @($comuns | ForEach-Object {
    $l = $_
    $l = $l -replace 'FIM: noturno concluido PARCIAL', 'FIM_DRYRUN: noturno concluido.'
    $l = $l -replace 'resultado=PARCIAL', 'resultado=DRYRUN'
    $l = $l -replace 'OK\|Usina Pampa Sul\|FULL\|RELEVANTE\|1\|true\|ANALISADO\|1', 'DRYRUN|Usina Pampa Sul|FULL|RELEVANTE|0|false|ANALISADO|0'
    $l
})
$logDry = Join-Path $Tmp 'homolog-dryrun-bom.log'
Set-Content -LiteralPath $logDry -Value ($comunsDry -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logDry -Emissor 'Usina Pampa Sul' 2>&1
Assert-Esc ($LASTEXITCODE -eq 0) ('V6 ponta boa em DRY-RUN (ledger DRYRUN|, resultado=DRYRUN) APROVA - e a execucao que a homologacao realmente faz (exit=' + $LASTEXITCODE + ')')
$comunsDef = @($comunsDry | ForEach-Object { $_ -replace '\|FULL\|RELEVANTE\|0\|false\|ANALISADO\|0', '|FULL|INCONCLUSIVO|0|false|DEFERIDO|0' })
$logDef = Join-Path $Tmp 'homolog-dryrun-deferido.log'
Set-Content -LiteralPath $logDef -Value ($comunsDef -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logDef -Emissor 'Usina Pampa Sul' 2>&1
Assert-Esc ($LASTEXITCODE -ne 0) 'V7 ponta ruim: ledger de dry-run em que o emissor escalado fechou DEFERIDO (nao ANALISADO) REPROVA'
# H13 deixou de ser eco do resultado anterior: a conta do desfecho tem de fechar de verdade.
$comunsDesbalanceado = @($comunsDry | ForEach-Object { $_ -replace 'escalada_analisados=1', 'escalada_analisados=0' })
$logDesb = Join-Path $Tmp 'homolog-desbalanceado.log'
Set-Content -LiteralPath $logDesb -Value ($comunsDesbalanceado -join "`r`n") -Encoding UTF8
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validador -LogPath $logDesb -Emissor 'Usina Pampa Sul' 2>&1
Assert-Esc ($LASTEXITCODE -ne 0) 'V8 ponta ruim: retido que nao aparece em nenhum destino (analisados=0 com retidos=1) REPROVA em H13'

# ------------------------------------------------------------------------------------
Write-Host '=== W: rotacao FULL nao e retida nem re-escalada (fixtures, decisao pura) ==='
# ROTACAOFULL-NAORETEM1 (2026-10-13): a condicao de retencao saiu do meio do laco de lotes do motor
# e virou funcao pura, para ser provada por comportamento e nao por leitura do fonte. A tabela
# verdade das quatro formas esta na secao S, sobre a funcao REAL; aqui fica a ligacao - o que
# garante que aquela prova vale para o codigo que roda - e a morte do caminho paralelo.
Assert-Esc ($mot.Contains('Test-VixEscaladaRetem -Ativa ([bool]$script:VixEscaladaAtiva) -JaEscalada ([bool]$job.Escalada) -Barato ([bool]$job.Barato)')) 'W5 o motor chama a funcao pura - a prova de comportamento vale para o codigo que roda'
Assert-Esc ($lib.Contains('function Test-VixEscaladaRetem([bool]$Ativa, [bool]$JaEscalada, [bool]$Barato)')) 'W6 a funcao pura existe na lib (o motor nao chama funcao fantasma)'
Assert-Esc (-not $mot.Contains('if ($script:VixEscaladaAtiva -and -not $job.Escalada -and [bool]$job.Barato)')) 'W7 a condicao inline morreu: nao sobrou caminho paralelo decidindo retencao'
# O gatilho continua disparando para esse emissor: o que o barra e a elegibilidade do LOTE, nao a
# ausencia de gatilho. Sem esta ponta, "nao foi retido" poderia significar "nao havia o que reter".
$__decRot = Get-VixEscaladaDecisao -Classificacao 'RELEVANTE' -Eventos 1 -Ews 55
Assert-Esc ($__decRot.Escalar -eq $true -and $__decRot.Gatilho -eq 'ews_critico') 'W8 o emissor da rotacao TEM gatilho (EWS 55 >= 50) - a retencao nao acontece por falta de gatilho'

# ORCAMENTO-13OUT7: pool proprio da escalada, provado nas duas pontas com a funcao REAL.
$cfgP = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }
$cDia0 = @{ mensuravel = $true; total_consumido = [int64]1000000; total_trabalho = [int64]1000000 }
$cDiaCheio = @{ mensuravel = $true; total_consumido = [int64]2200000; total_trabalho = [int64]2200000 }
$cDiaDesc = @{ mensuravel = $false; total_consumido = [int64]0; total_trabalho = [int64]0 }
$p1 = Get-VixCapEscaladaEfetivo 700000 540000 $cDia0 $cfgP 150000
Assert-Esc ($p1 -eq 1240000) ("P1 noturna com dia folgado: cap da escalada = cap proprio + pool (" + $p1 + ")")
$p2 = Get-VixCapEscaladaEfetivo 700000 540000 $cDiaCheio $cfgP 150000
Assert-Esc ($p2 -eq 250000 -and $p2 -lt 1240000) ("P2 ponta oposta: dia consumido 2,2M limita o pool pelo TETO (" + $p2 + "), o teto global manda")
$p3 = Get-VixCapEscaladaEfetivo 700000 540000 $cDiaDesc $cfgP 150000
Assert-Esc ($p3 -eq 0) 'P3 consumo nao mensuravel fecha tambem o pool (fail-closed)'
$p4 = Get-VixCapEscaladaEfetivo 700000 0 $cDia0 $cfgP 150000
Assert-Esc ($p4 -eq 700000) 'P4 sem pool o cap e o da rodada (comportamento anterior)'
$p5 = Get-VixCapEscaladaEfetivo 400000 360000 $cDia0 $cfgP 850000
Assert-Esc ($p5 -eq 750000) ("P5 matinal preserva a reserva da noturna+verificacao (" + $p5 + " = 2,6M-1M-850k)")
Assert-Esc ($mot.Contains('$__capLote = if ($job.Escalada) { $TokenHardCapEscalada } else { $TokenHardCap }') -and $mot.Contains('$capEscaladaFechado')) 'P6 o motor decide o cap e o fechamento por lane (escalada x barata)'
Assert-Esc ($mot.Contains('Get-VixCapEscaladaEfetivo ([int64]$Perfil.capProprio) ([int64]$Perfil.capEscalada)')) 'P7 o motor calcula o pool pela funcao real'

} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
