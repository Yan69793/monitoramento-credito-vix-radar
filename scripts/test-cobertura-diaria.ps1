# test-cobertura-diaria.ps1 - COBDIARIA1 (2026-10-14). Prova deterministica, offline e sem token
# do controle diario de verificacao por emissor:
#   A evidencia do dia (familias, HTTP, timestamp fora do dia)
#   B verificacao do dia separada da revalidacao de IA
#   C transicao monotona (terminal nunca rebaixa, sem evidencia nunca vira terminal)
#   D ledger em disco (registro, tentativas, falha depois de verificado, analise)
#   E resumo (omitidos, pendentes, universo desconhecido/abaixo do minimo, uniao do universo)
#   F cascata economica (recoleta, primario, Claude por ultimo, INSUFICIENCIA fail-closed)
#   G reserva da cobertura obrigatoria antes da complementar
#   H ordem obrigatorio-primeiro (estavel, sem perda, sem duplicidade)
#   I reserva da matinal contra noturna que atravessa a meia-noite
#   J fechamento (relatorio, incidente, alerta so fora de dry-run, ledger ausente)
#   K simulacao de um dia com os custos MEDIDOS nos logs de 13-14/10 (simulacao != execucao)
#   L guardas estruturais no motor (o que o motor realmente chama)
# Toda guarda e provada nas duas pontas. ASCII puro, PowerShell 5.1. exit 0 = verde, 1 = falha.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Cd([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-cobertura-diaria.ps1')

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('vix-cobdiaria-' + $PID)
if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force }
New-Item -ItemType Directory -Path $Tmp | Out-Null

# Relogio fixo: 14/10/2026 15:00 UTC = 12:00 BRT. Dia do ledger 20261014.
$Agora = [datetime]::SpecifyKind([datetime]'2026-10-14T15:00:00', [DateTimeKind]::Utc)
$Dia = '20261014'
$TsHoje = '2026-10-14T14:30:00Z'
$TsOntem = '2026-10-13T20:00:00Z'
# 01:00 UTC do dia 14 = 22:00 BRT do dia 13: precisa cair em 20261013.
$TsBordaUtc = '2026-10-14T01:00:00Z'

function New-Fonte([string]$Fam, [string]$Ts, $Http = 200, [string]$Cls = 'ok') {
    return [pscustomobject][ordered]@{ rodada = 'C'; familia = $Fam; query = ('q ' + $Fam); timestamp = $Ts; provedor = 'coletor:google_news_rss'; status_http = $Http; resultado = 'x'; classificacao = $Cls }
}
function New-Fontes3([string]$Ts) { return @((New-Fonte 'emissor' $Ts), (New-Fonte 'divida' $Ts), (New-Fonte 'fato' $Ts)) }
function New-Coleta([string]$Emp, [string]$ColetadoEm, [object[]]$Evid = @(), [int]$BrutoF1 = 30, [bool]$Disp = $true) {
    return [pscustomobject]@{
        empresa = $Emp; coletado_em = $ColetadoEm; janela_dias = 2
        queries = @([pscustomobject]@{ familia = 'F1'; query = $Emp }, [pscustomobject]@{ familia = 'F2'; query = ($Emp + ' divida') }, [pscustomobject]@{ familia = 'F3'; query = ($Emp + ' fato') })
        evidencias = $Evid; total = @($Evid).Count; por_familia = @{ F1 = 0; F2 = 0; F3 = 0 }; itens_brutos = @{ F1 = $BrutoF1; F2 = 10; F3 = 5 }
        disponivel = $Disp; erros = @()
    }
}

Write-Host 'A. evidencia do dia'
$a1 = Test-VixCobDiariaEvidencia -Fontes (New-Fontes3 $TsHoje) -DateTag $Dia -ExigirFamilias $true
Assert-Cd ($a1.ok -and $a1.validas -eq 3) 'A1 tres familias de hoje com HTTP 200 => ok'
$a2 = Test-VixCobDiariaEvidencia -Fontes @((New-Fonte 'emissor' $TsHoje), (New-Fonte 'divida' $TsHoje)) -DateTag $Dia -ExigirFamilias $true
Assert-Cd ((-not $a2.ok) -and $a2.motivo -eq 'familias_faltando_fato') 'A2 familia fato ausente reprova a ausencia certificada'
$a3 = Test-VixCobDiariaEvidencia -Fontes (New-Fontes3 $TsOntem) -DateTag $Dia -ExigirFamilias $true
Assert-Cd ((-not $a3.ok) -and $a3.motivo -eq 'evidencia_fora_do_dia') 'A3 evidencia de ontem reprova (cache antigo)'
$a4 = Test-VixCobDiariaEvidencia -Fontes @((New-Fonte 'emissor' $TsHoje 503), (New-Fonte 'divida' $TsHoje), (New-Fonte 'fato' $TsHoje)) -DateTag $Dia -ExigirFamilias $true
Assert-Cd ((-not $a4.ok) -and $a4.reprovadas -eq 1) 'A4 HTTP 503 numa familia reprova'
$a5 = Test-VixCobDiariaEvidencia -Fontes @((New-Fonte 'emissor' $TsHoje 200 'degradada'), (New-Fonte 'divida' $TsHoje), (New-Fonte 'fato' $TsHoje)) -DateTag $Dia -ExigirFamilias $true
Assert-Cd (-not $a5.ok) 'A5 classificacao degradada reprova'
Assert-Cd ((Get-VixCobDiariaDiaBrt $TsBordaUtc) -eq '20261013') 'A6 01:00 UTC do dia 14 e dia 13 em BRT'
Assert-Cd ((Get-VixCobDiariaDiaBrt 'lixo') -eq '') 'A7 timestamp invalido nao vira dia'
$a8 = Test-VixCobDiariaEvidencia -Fontes @((New-Fonte 'emissor' $TsHoje)) -DateTag $Dia -ExigirFamilias $false
Assert-Cd $a8.ok 'A8 sem exigencia de familias, uma fonte valida do dia basta (ponta boa)'

Write-Host 'B. verificacao do dia separada da revalidacao'
$cq = New-Coleta 'Equatorial Energia' $TsHoje
$b1 = Get-VixVerificacaoDiaria -Coleta $cq -DeltaInicio '2026-10-13' -DateTag $Dia -Agora $Agora
Assert-Cd ($b1.Resultado -eq 'SEM_NOVIDADE' -and @($b1.Fontes).Count -eq 3) 'B1 coleta completa, nada novo => SEM_NOVIDADE com 3 fontes (mesmo com IA vencida ha 537h)'
$tri537 = Get-VixTriagemEmissor -Coleta $cq -DeltaInicio '2026-10-13' -HorasDesdeIA 537 -Agora $Agora
Assert-Cd ($tri537.Classe -eq 'MATERIAL') 'B2 a MESMA coleta na triagem com 537h segue MATERIAL (revalidacao e complementar)'
$ev = @([pscustomobject]@{ familia = 'F1'; titulo = 'Equatorial Energia anuncia emissao'; veiculo = 'Valor'; dominio = 'valor.globo.com'; data = '2026-10-14' })
$b3 = Get-VixVerificacaoDiaria -Coleta (New-Coleta 'Equatorial Energia' $TsHoje $ev) -DeltaInicio '2026-10-13' -DateTag $Dia -Agora $Agora
Assert-Cd ($b3.Resultado -eq 'NOVIDADE' -and $b3.Motivo -like 'evidencia_nova*') 'B3 manchete nova citando o emissor => NOVIDADE'
$b4 = Get-VixVerificacaoDiaria -Coleta $cq -DeltaInicio '2026-10-13' -CvmNovos 2 -DateTag $Dia -Agora $Agora
Assert-Cd ($b4.Resultado -eq 'NOVIDADE' -and $b4.Motivo -eq 'cvm_novos_2') 'B4 documento CVM novo => NOVIDADE'
$b5 = Get-VixVerificacaoDiaria -Coleta (New-Coleta 'X' $TsHoje @() 30 $false) -DateTag $Dia -Agora $Agora
Assert-Cd ($b5.Resultado -eq 'FALHA_CONSULTA') 'B5 coleta indisponivel => FALHA_CONSULTA, nunca SEM_NOVIDADE'
$b6 = Get-VixVerificacaoDiaria -Coleta (New-Coleta 'X' $TsHoje @() 0) -DateTag $Dia -Agora $Agora
Assert-Cd ($b6.Resultado -eq 'FALHA_CONSULTA' -and $b6.Motivo -eq 'f1_feed_vazio_suspeito') 'B6 feed F1 vazio => FALHA_CONSULTA (throttling nao e quieto)'
$b7 = Get-VixVerificacaoDiaria -Coleta (New-Coleta 'X' $TsOntem) -DateTag $Dia -Agora $Agora
Assert-Cd ($b7.Resultado -eq 'CACHE_ANTIGO') 'B7 coleta de ontem => CACHE_ANTIGO'
$b8 = Get-VixVerificacaoDiaria -Coleta $cq -DeltaInicio '2026-10-13' -EstadoNaoResolvido $true -MotivoNaoResolvido 'inconclusivo_anterior' -DateTag $Dia -Agora $Agora
Assert-Cd ($b8.Resultado -eq 'NOVIDADE') 'B8 pergunta aberta (INCONCLUSIVO anterior) => exige IA'
$b9 = Get-VixVerificacaoDiaria -Coleta $null -DateTag $Dia -Agora $Agora
Assert-Cd ($b9.Resultado -eq 'FALHA_CONSULTA') 'B9 sem coleta => FALHA_CONSULTA'

Write-Host 'C. transicao monotona'
$c1 = Get-VixCobDiariaTransicao -Atual 'VERIFICADO_SEM_NOVIDADE' -Novo 'FALHA_CONSULTA'
Assert-Cd ($c1.Estado -eq 'VERIFICADO_SEM_NOVIDADE' -and -not $c1.Aplicada) 'C1 falha posterior nao rebaixa verificado'
$c2 = Get-VixCobDiariaTransicao -Atual 'VERIFICADO_SEM_NOVIDADE' -Novo 'VERIFICADO_ANALISADO' -EvidenciaOk $true
Assert-Cd ($c2.Estado -eq 'VERIFICADO_ANALISADO') 'C2 analise sobe sobre sem-novidade'
$c3 = Get-VixCobDiariaTransicao -Atual 'VERIFICADO_ANALISADO' -Novo 'VERIFICADO_SEM_NOVIDADE' -EvidenciaOk $true
Assert-Cd ($c3.Estado -eq 'VERIFICADO_ANALISADO') 'C3 sem-novidade nao rebaixa analisado'
$c4 = Get-VixCobDiariaTransicao -Atual '' -Novo 'VERIFICADO_SEM_NOVIDADE' -EvidenciaOk $false
Assert-Cd ($c4.Estado -eq 'PENDENTE') 'C4 terminal sem evidencia do dia vira PENDENTE'
$c5 = Get-VixCobDiariaTransicao -Atual '' -Novo 'VERIFICADO_ANALISADO' -EvidenciaOk $false
Assert-Cd ($c5.Estado -eq 'PENDENTE_IA') 'C5 analise sem prova vira PENDENTE_IA'
$c6 = Get-VixCobDiariaTransicao -Atual 'PENDENTE_IA' -Novo 'PENDENTE'
Assert-Cd ($c6.Estado -eq 'PENDENTE_IA') 'C6 deferimento nao apaga fato novo visto'
$c7 = Get-VixCobDiariaTransicao -Atual 'PENDENTE_IA' -Novo 'VERIFICADO_ANALISADO' -EvidenciaOk $true
Assert-Cd ($c7.Estado -eq 'VERIFICADO_ANALISADO') 'C7 pendente com prova fecha (ponta boa)'

Write-Host 'D. ledger em disco'
$P = Get-VixCobDiariaPath $Tmp $Dia
$d1 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'CEMIG' -Estado 'VERIFICADO_SEM_NOVIDADE' -Motivo 'sem_publicacao' -Rotina 'noturno' -Fontes (New-Fontes3 $TsHoje) -ColetadoEm $TsHoje -Agora $Agora
Assert-Cd ($d1.Estado -eq 'VERIFICADO_SEM_NOVIDADE' -and $d1.Aplicada) 'D1 registro com 3 fontes do dia => verificado'
$d2 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Eneva' -Estado 'VERIFICADO_SEM_NOVIDADE' -Rotina 'noturno' -Fontes (New-Fontes3 $TsOntem) -Agora $Agora
Assert-Cd ($d2.Estado -eq 'PENDENTE' -and $d2.Prova -eq 'evidencia_fora_do_dia') 'D2 fontes de ontem => recusado (zero conclusao por cache antigo)'
$null = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Oi' -Estado 'FALHA_CONSULTA' -Motivo 'coleta_incompleta' -Rotina 'matinal' -Agora $Agora
$d3 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Oi' -Estado 'FALHA_CONSULTA' -Motivo 'coleta_incompleta' -Rotina 'noturno' -Agora $Agora
$L = Read-VixCobDiaria $P $Dia
Assert-Cd ([int]$L.emissores[(ConvertTo-VixChaveEmissor 'Oi')].tentativas_coleta -eq 2) 'D3 falha transitoria conta tentativa sem duplicar registro'
$d4 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'CEMIG' -Estado 'FALHA_CONSULTA' -Rotina 'sentinela' -Agora $Agora
Assert-Cd ($d4.Estado -eq 'VERIFICADO_SEM_NOVIDADE' -and -not $d4.Aplicada) 'D4 falha depois de verificado nao rebaixa'
$anIn = @{ provider = 'codex'; modelo = 'm'; tier = 'BARATO'; classificacao = 'INCONCLUSIVO'; tokens = 11000; submit_ok = $true; n_eventos = 0 }
$d5 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Raizen' -Estado 'VERIFICADO_ANALISADO' -Rotina 'noturno' -Fontes (New-Fontes3 $TsHoje) -Analise $anIn -Agora $Agora
Assert-Cd ($d5.Estado -eq 'PENDENTE_IA' -and $d5.Prova -eq 'analise_inconclusiva') 'D5 analise INCONCLUSIVO nao fecha o dia'
$anOk = @{ provider = 'codex'; modelo = 'm'; tier = 'FULL'; classificacao = 'RELEVANTE'; tokens = 74569; submit_ok = $true; n_eventos = 1 }
$d6 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Raizen' -Estado 'VERIFICADO_ANALISADO' -Rotina 'noturno' -Fontes @((New-Fonte 'fato' $TsHoje)) -Analise $anOk -Agora $Agora
$L = Read-VixCobDiaria $P $Dia
$rz = $L.emissores[(ConvertTo-VixChaveEmissor 'Raizen')]
Assert-Cd ($d6.Estado -eq 'VERIFICADO_ANALISADO' -and [int]$rz.tentativas_ia -eq 2 -and ('' + $rz.analise.provider) -eq 'codex' -and [int64]$rz.analise.tokens -eq 74569) 'D6 analise aceita fecha com provider, tokens e tentativas'
$anSub = @{ provider = 'codex'; classificacao = 'RELEVANTE'; submit_ok = $false }
$d7 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Vale' -Estado 'VERIFICADO_ANALISADO' -Rotina 'noturno' -Fontes @((New-Fonte 'fato' $TsHoje)) -Analise $anSub -Agora $Agora
Assert-Cd ($d7.Estado -eq 'PENDENTE_IA' -and $d7.Prova -eq 'submit_nao_aceito') 'D7 submit recusado nao conta como entrega'
$d8 = Register-VixCobDiaria -Path $P -DateTag $Dia -Empresa 'Vale' -Estado 'VERIFICADO_ANALISADO' -Rotina 'noturno' -Fontes @((New-Fonte 'fato' $TsHoje)) -Analise $anOk -Agora ($Agora.AddDays(1))
Assert-Cd ($d8.Estado -eq 'PENDENTE_IA' -and $d8.Prova -eq 'analise_fora_do_dia') 'D8 analise de outro dia nao fecha este dia'
Assert-Cd ($null -ne $rz.evidencia -and @($rz.evidencia.fontes).Count -ge 1 -and @($rz.historico).Count -eq 2) 'D9 evidencia individual e historico gravados'
Assert-Cd (Test-Path -LiteralPath ($P + '.bak')) 'D10 escrita atomica com .bak'

Write-Host 'E. resumo'
$U = @(1..104 | ForEach-Object { 'Emissor ' + $_ })
$Pe = Join-Path $Tmp 'e'; New-Item -ItemType Directory -Path $Pe | Out-Null
$PE1 = Get-VixCobDiariaPath $Pe $Dia
$null = Set-VixCobDiariaUniverso -Path $PE1 -DateTag $Dia -Nomes $U -Total 104 -Fonte 'plano_noturno'
foreach ($n in $U) { $null = Register-VixCobDiaria -Path $PE1 -DateTag $Dia -Empresa $n -Estado 'VERIFICADO_SEM_NOVIDADE' -Rotina 'noturno' -Fontes (New-Fontes3 $TsHoje) -Agora $Agora }
$e1 = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $PE1 $Dia) -UniversoMinimo 104
Assert-Cd ($e1.ok -and $e1.verificados -eq 104) 'E1 104/104 com evidencia => ok'
$Le = Read-VixCobDiaria $PE1 $Dia
$Le.emissores.Remove((ConvertTo-VixChaveEmissor 'Emissor 7'))
$e2 = Get-VixCobDiariaResumo -Ledger $Le -UniversoMinimo 104
Assert-Cd ((-not $e2.ok) -and @($e2.omitidos).Count -eq 1 -and @($e2.omitidos)[0] -eq 'Emissor 7') 'E2 emissor sem registro aparece OMITIDO, sem falso OK'
$null = Register-VixCobDiaria -Path $PE1 -DateTag $Dia -Empresa 'Emissor 9' -Estado 'PENDENTE_IA' -Rotina 'x' -Agora $Agora
$e3 = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $PE1 $Dia) -UniversoMinimo 104
Assert-Cd ($e3.ok -and $e3.verificados -eq 104) 'E3 PENDENTE_IA posterior nao derruba verificado (monotonia no resumo)'
$Le2 = Read-VixCobDiaria $PE1 $Dia
$Le2.emissores[(ConvertTo-VixChaveEmissor 'Emissor 11')] = @{ empresa = 'Emissor 11'; estado = 'PENDENTE_IA'; motivo = 'deferido:cap_efetivo'; tentativas_coleta = 0; tentativas_ia = 0 }
$e4 = Get-VixCobDiariaResumo -Ledger $Le2 -UniversoMinimo 104
Assert-Cd ((-not $e4.ok) -and $e4.pendentes_ia -eq 1 -and $e4.verificados -eq 103) 'E4 pendente de IA => 103/104, nao ok'
$e5 = Get-VixCobDiariaResumo -Ledger (New-VixCobDiariaLedger $Dia) -UniversoMinimo 0
Assert-Cd ((-not $e5.ok) -and (@($e5.motivos) -contains 'universo_desconhecido')) 'E5 universo desconhecido nunca e ok'
$Le3 = Read-VixCobDiaria $PE1 $Dia
$e6 = Get-VixCobDiariaResumo -Ledger $Le3 -UniversoMinimo 105
Assert-Cd ((-not $e6.ok) -and (@($e6.motivos) -like 'universo_abaixo_do_minimo*').Count -eq 1) 'E6 universo abaixo do minimo declarado reprova'
$null = Set-VixCobDiariaUniverso -Path $PE1 -DateTag $Dia -Nomes @('Emissor 1', 'Emissor 2') -Total 22 -Fonte 'plano_matinal'
$Le4 = Read-VixCobDiaria $PE1 $Dia
Assert-Cd ($Le4.universo_total -eq 104 -and @($Le4.universo).Count -eq 104) 'E7 plano parcial da matinal nao encolhe o universo'
$Le4.universo_total = 105
$e8 = Get-VixCobDiariaResumo -Ledger $Le4 -UniversoMinimo 0
Assert-Cd ((-not $e8.ok) -and (@($e8.motivos) -like 'universo_incompleto*').Count -eq 1) 'E8 total maior que a lista de nomes reprova'

Write-Host 'F. cascata economica'
$f = @{ CustoBarato = [int64]13700; CustoFull = [int64]93212 }
$f1 = Get-VixCobDiariaProximoPasso -Estado 'VERIFICADO_SEM_NOVIDADE' @f
Assert-Cd ($f1.Passo -eq 'NADA') 'F1 verificado nao gasta nada'
$f2 = Get-VixCobDiariaProximoPasso -Estado 'FALHA_CONSULTA' -TentativasColeta 1 -OrcamentoPrimario 0 @f
Assert-Cd ($f2.Passo -eq 'RECOLETAR' -and $f2.Custo -eq 0) 'F2 falha transitoria => recoleta a custo zero, mesmo sem orcamento'
$f3 = Get-VixCobDiariaProximoPasso -Estado 'FALHA_CONSULTA' -TentativasColeta 3 -OrcamentoPrimario 1000000 @f
Assert-Cd ($f3.Passo -eq 'IA_PRIMARIA' -and $f3.Tier -eq 'FULL') 'F3 falha persistente => IA com ferramenta (busca propria)'
$f4 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000000 @f
Assert-Cd ($f4.Passo -eq 'IA_PRIMARIA' -and $f4.Tier -eq 'BARATO') 'F4 fato novo comum => pacote barato primeiro'
$f5 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -IaInconclusiva $true -OrcamentoPrimario 1000000 @f
Assert-Cd ($f5.Tier -eq 'FULL') 'F5 barato inconclusivo => escala para ferramenta'
$f6 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000 @f
Assert-Cd ($f6.Passo -eq 'INSUFICIENCIA' -and $f6.Motivo -like '*claude_desligado') 'F6 sem orcamento e Claude desligado => INSUFICIENCIA'
$f7 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000 -ClaudeHabilitado $true -OrcamentoClaude 500000 @f
Assert-Cd ($f7.Passo -eq 'CLAUDE_FALLBACK') 'F7 sem orcamento primario e Claude habilitado => Claude por ultimo'
$f8 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000 -ClaudeHabilitado $true -ClaudeLimiteAtingido $true -OrcamentoClaude 500000 @f
Assert-Cd ($f8.Passo -eq 'INSUFICIENCIA' -and $f8.Motivo -like '*claude_no_limite') 'F8 Claude no limite da assinatura => INSUFICIENCIA'
$f9 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000000 -CustoBarato 0 -CustoFull 0
Assert-Cd ($f9.Passo -eq 'INSUFICIENCIA' -and $f9.Motivo -eq 'custo_desconhecido_fail_closed') 'F9 custo desconhecido nunca libera lote'
$f10 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -PrimarioDisponivel $false -OrcamentoPrimario 9000000 -ClaudeHabilitado $true -OrcamentoClaude 500000 @f
Assert-Cd ($f10.Passo -eq 'CLAUDE_FALLBACK' -and $f10.Motivo -like 'primario_indisponivel*') 'F10 primario com cota esgotada => Claude mesmo com orcamento local'
$f11 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000000 -ClaudeHabilitado $true -OrcamentoClaude 500000 @f
Assert-Cd ($f11.Passo -eq 'IA_PRIMARIA') 'F11 com primario disponivel Claude NAO e usado (ultimo recurso de verdade)'
$f12 = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario 1000 -ClaudeHabilitado $true -OrcamentoClaude 100 @f
Assert-Cd ($f12.Passo -eq 'INSUFICIENCIA' -and $f12.Motivo -like '*claude_sem_orcamento') 'F12 teto do fallback Claude respeitado'

Write-Host 'G. reserva obrigatoria'
$g1 = Get-VixCobDiariaReserva -PendentesIa 16 -FalhasPersistentes 0 -CustoBarato 13700 -CustoFull 93212 -TaxaEscalada 1.0 -CapEfetivo 2450000
Assert-Cd ($g1.Reserva -eq 1710592 -and $g1.Cabe -and $g1.Complementar -eq 739408) 'G1 16 obrigatorios no pior caso cabem no dia e sobra o complementar'
$g2 = Get-VixCobDiariaReserva -PendentesIa 16 -CustoBarato 13700 -CustoFull 93212 -TaxaEscalada 1.0 -CapEfetivo 700000
Assert-Cd ((-not $g2.Cabe) -and $g2.Complementar -eq 0 -and $g2.Deficit -eq 1010592) 'G2 cap de uma rotina nao cobre => deficit explicito, complementar zero'
$g3 = Get-VixCobDiariaReserva -PendentesIa 0 -FalhasPersistentes 2 -CustoBarato 13700 -CustoFull 93212 -CapEfetivo 700000
Assert-Cd ($g3.Reserva -eq 186424) 'G3 falha persistente reserva FULL'
$g4 = Get-VixCobDiariaReserva -PendentesIa 4 -CustoBarato 100 -CustoFull 1000 -TaxaEscalada 7 -CapEfetivo 0
Assert-Cd ($g4.Reserva -eq 4400) 'G4 taxa de escalada limitada a 1'

Write-Host 'H. ordem obrigatorio-primeiro'
$es = @('A', 'B', 'C', 'D', 'E', 'B') | ForEach-Object { [pscustomobject]@{ empresa = $_ } }
$ob = @{}; $ob[(ConvertTo-VixChaveEmissor 'D')] = 60; $ob[(ConvertTo-VixChaveEmissor 'C')] = 90; $ob[(ConvertTo-VixChaveEmissor 'E')] = 60
$h1 = @(Select-VixCobDiariaOrdem -Emissores $es -Obrigatorios $ob | ForEach-Object { $_.empresa })
Assert-Cd (($h1 -join ',') -eq 'C,D,E,A,B') 'H1 obrigatorios por prioridade e entrada, depois complementares'
Assert-Cd ($h1.Count -eq 5) 'H2 sem duplicar e sem perder'
$h3 = @(Select-VixCobDiariaOrdem -Emissores $es -Obrigatorios @{} | ForEach-Object { $_.empresa })
Assert-Cd (($h3 -join ',') -eq 'A,B,C,D,E') 'H3 sem obrigatorios a ordem nao muda'
Assert-Cd ((Get-VixCobDiariaPrioridade 'FALHA_CONSULTA' '') -gt (Get-VixCobDiariaPrioridade 'NOVIDADE' 'cvm_novos_1') -and (Get-VixCobDiariaPrioridade 'NOVIDADE' 'cvm_novos_1') -gt (Get-VixCobDiariaPrioridade 'NOVIDADE' 'evidencia_nova_2')) 'H4 prioridade: falha > cvm > manchete'

Write-Host 'I. reserva da matinal'
Assert-Cd ((Get-VixReservaMatinalPendente -Agora ([datetime]'2026-10-14T02:28:00') -MatinalJaRodou $false -CapMatinal 400000) -eq 400000) 'I1 noturna das 02:28 reserva a matinal (caso real de 14/10)'
Assert-Cd ((Get-VixReservaMatinalPendente -Agora ([datetime]'2026-10-14T18:05:00') -MatinalJaRodou $false -CapMatinal 400000) -eq 0) 'I2 noturna das 18:05 nao reserva (janela passou)'
Assert-Cd ((Get-VixReservaMatinalPendente -Agora ([datetime]'2026-10-14T09:00:00') -MatinalJaRodou $true -CapMatinal 400000) -eq 0) 'I3 matinal ja rodou => sem reserva'

Write-Host 'J. fechamento'
$PJ = Join-Path $Tmp 'j'; New-Item -ItemType Directory -Path $PJ | Out-Null
Copy-Item -LiteralPath $PE1 -Destination (Get-VixCobDiariaPath $PJ $Dia)
$j1 = Invoke-VixCobDiariaFechamento -LogDir $PJ -DateTag $Dia -Fechamento -DryRun -UniversoMinimo 104
Assert-Cd ($j1.Status -eq 'OK' -and $j1.Exit -eq 0 -and -not (Test-Path (Join-Path $PJ ('DRYRUN_incidente_cobertura_' + $Dia + '.json')))) 'J1 104/104 fecha OK sem incidente'
$Lj = Read-VixCobDiaria (Get-VixCobDiariaPath $PJ $Dia) $Dia
$Lj.emissores[(ConvertTo-VixChaveEmissor 'Emissor 3')] = @{ empresa = 'Emissor 3'; estado = 'PENDENTE_IA'; motivo = 'deferido:cap_efetivo'; tentativas_coleta = 0; tentativas_ia = 0 }
$Lj.emissores[(ConvertTo-VixChaveEmissor 'Emissor 4')] = @{ empresa = 'Emissor 4'; estado = 'PENDENTE_IA'; motivo = 'deferido:cap_efetivo'; tentativas_coleta = 0; tentativas_ia = 0 }
$Lj.emissores[(ConvertTo-VixChaveEmissor 'Emissor 5')] = @{ empresa = 'Emissor 5'; estado = 'FALHA_CONSULTA'; motivo = 'coleta_incompleta'; tentativas_coleta = 1; tentativas_ia = 0 }
Write-VixCobDiaria (Get-VixCobDiariaPath $PJ $Dia) $Lj
$script:alertas = 0
$al = { param($t) $script:alertas++; $script:alertaTxt = $t; return $true }
$capJ = @{ PrimarioDisponivel = $true; OrcamentoPrimario = [int64]20000; CustoBarato = [int64]13700; CustoFull = [int64]93212; ClaudeHabilitado = $false; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64]0 }
$j2 = Invoke-VixCobDiariaFechamento -LogDir $PJ -DateTag $Dia -Fechamento -DryRun -UniversoMinimo 104 -AlertaAcao $al -Capacidade $capJ
Assert-Cd ($j2.Status -eq 'INCIDENTE_CRITICO' -and $j2.Exit -eq 20 -and $script:alertas -eq 0) 'J2 fechamento 101/104 => incidente, mas dry-run NUNCA alerta'
Assert-Cd (Test-Path (Join-Path $PJ ('DRYRUN_incidente_cobertura_' + $Dia + '.json'))) 'J3 dry-run grava incidente com prefixo DRYRUN_'
$pp = @($j2.Relatorio.proximos_passos)
$porEmp = @{}; foreach ($x in $pp) { $porEmp[$x.empresa] = $x.passo }
Assert-Cd ($porEmp['Emissor 5'] -eq 'RECOLETAR' -and (@($pp | Where-Object { $_.passo -eq 'IA_PRIMARIA' }).Count -eq 1) -and (@($pp | Where-Object { $_.passo -eq 'INSUFICIENCIA' }).Count -eq 1)) 'J4 saldo consumido em ordem: 1 cabe, o outro vira INSUFICIENCIA, falha recoleta'
$capJ2 = @{ PrimarioDisponivel = $true; OrcamentoPrimario = [int64]20000; CustoBarato = [int64]13700; CustoFull = [int64]93212; ClaudeHabilitado = $false; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64]0 }
$j5 = Invoke-VixCobDiariaFechamento -LogDir $PJ -DateTag $Dia -Fechamento -UniversoMinimo 104 -AlertaAcao $al -Capacidade $capJ2
Assert-Cd ($j5.Alertado -and $script:alertas -eq 1 -and $script:alertaTxt -like '*101/104*' -and (Test-Path (Join-Path $PJ ('incidente_cobertura_' + $Dia + '.json')))) 'J5 fechamento real alerta uma vez com 101/104 e grava incidente'
$j6 = Invoke-VixCobDiariaFechamento -LogDir $PJ -DateTag $Dia -DryRun -UniversoMinimo 104 -AlertaAcao $al
Assert-Cd ($j6.Status -eq 'PARCIAL' -and $j6.Exit -eq 10 -and $script:alertas -eq 1) 'J6 durante o dia e PARCIAL, sem incidente nem alerta'
$PJ2 = Join-Path $Tmp 'j2'; New-Item -ItemType Directory -Path $PJ2 | Out-Null
$j7 = Invoke-VixCobDiariaFechamento -LogDir $PJ2 -DateTag $Dia -Fechamento -DryRun
Assert-Cd ($j7.Status -eq 'INCIDENTE_CRITICO' -and (@($j7.Relatorio.motivos) -contains 'ledger_ausente')) 'J7 ledger ausente no fechamento => incidente (rotina que nao rodou nao e OK)'
Assert-Cd ($j2.Linha -like 'COBERTURA_DIARIA|20261014|INCIDENTE_CRITICO|verificados=101/104*') 'J8 linha canonica no log'

Write-Host 'K. simulacao de um dia (custos medidos, SIMULACAO != EXECUCAO REAL)'
# Medidos nos logs: pacote barato 21.892/2 emissores (noturno dry-run 13/10) => 10.946; FULL com
# ferramenta 1.193.101/16 (noturna 14/10) => 74.569. Margem de classe 1,25 da lib aplicada.
$cb = [int64][Math]::Ceiling(10946 * 1.25); $cf = [int64][Math]::Ceiling(74569 * 1.25)
$PK = Join-Path $Tmp 'k'; New-Item -ItemType Directory -Path $PK | Out-Null
$PKL = Get-VixCobDiariaPath $PK $Dia
$null = Set-VixCobDiariaUniverso -Path $PKL -DateTag $Dia -Nomes $U -Total 104 -Fonte 'plano_noturno'
$i = 0
foreach ($n in $U) {
    $i++
    if ($i -le 88) { $null = Register-VixCobDiaria -Path $PKL -DateTag $Dia -Empresa $n -Estado 'VERIFICADO_SEM_NOVIDADE' -Rotina 'noturno' -Fontes (New-Fontes3 $TsHoje) -Agora $Agora }
    else { $null = Register-VixCobDiaria -Path $PKL -DateTag $Dia -Empresa $n -Estado 'PENDENTE_IA' -Motivo 'evidencia_nova' -Rotina 'noturno' -Agora $Agora }
}
$kr = Get-VixCobDiariaReserva -PendentesIa 16 -CustoBarato $cb -CustoFull $cf -TaxaEscalada 1.0 -CapEfetivo (2600000 - 150000)
Assert-Cd ($kr.Cabe) ('K1 16 obrigatorios no pior caso (barato+FULL) cabem no TETO_DIA: reserva=' + $kr.Reserva)
$saldo = [int64](2600000 - 150000)
foreach ($n in ($U | Select-Object -Skip 88)) {
    $d = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -OrcamentoPrimario $saldo -CustoBarato $cb -CustoFull $cf
    if ($d.Passo -eq 'IA_PRIMARIA') { $saldo -= ($cb + $cf); $null = Register-VixCobDiaria -Path $PKL -DateTag $Dia -Empresa $n -Estado 'VERIFICADO_ANALISADO' -Rotina 'noturno' -Fontes @((New-Fonte 'fato' $TsHoje)) -Analise $anOk -Agora $Agora }
}
$k2 = Invoke-VixCobDiariaFechamento -LogDir $PK -DateTag $Dia -Fechamento -DryRun -UniversoMinimo 104
Assert-Cd ($k2.Status -eq 'OK' -and $k2.Relatorio.sem_novidade -eq 88 -and $k2.Relatorio.analisados -eq 16) 'K2 dia simulado fecha 104/104 (88 coletor + 16 IA)'
$PK2 = Join-Path $Tmp 'k2'; New-Item -ItemType Directory -Path $PK2 | Out-Null
Copy-Item -LiteralPath $PKL -Destination (Get-VixCobDiariaPath $PK2 $Dia)
$Lk = Read-VixCobDiaria (Get-VixCobDiariaPath $PK2 $Dia) $Dia
foreach ($n in ($U | Select-Object -Skip 98)) { $Lk.emissores[(ConvertTo-VixChaveEmissor $n)] = @{ empresa = $n; estado = 'PENDENTE_IA'; motivo = 'deferido:cap_efetivo'; tentativas_coleta = 0; tentativas_ia = 1 } }
Write-VixCobDiaria (Get-VixCobDiariaPath $PK2 $Dia) $Lk
$capK = @{ PrimarioDisponivel = $false; OrcamentoPrimario = [int64]0; CustoBarato = $cb; CustoFull = $cf; ClaudeHabilitado = $false; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64]0 }
$k3 = Invoke-VixCobDiariaFechamento -LogDir $PK2 -DateTag $Dia -Fechamento -DryRun -UniversoMinimo 104 -Capacidade $capK
Assert-Cd ($k3.Status -eq 'INCIDENTE_CRITICO' -and $k3.Relatorio.insuficiencia -eq 6 -and $k3.Relatorio.verificados -eq 98) 'K3 cota do Codex esgotada e Claude desligado => 98/104 e 6 INSUFICIENCIA nomeados'
$capK2 = @{ PrimarioDisponivel = $false; OrcamentoPrimario = [int64]0; CustoBarato = $cb; CustoFull = $cf; ClaudeHabilitado = $true; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64](3 * $cb) }
$k4 = Invoke-VixCobDiariaFechamento -LogDir $PK2 -DateTag $Dia -Fechamento -DryRun -UniversoMinimo 104 -Capacidade $capK2
Assert-Cd ((@($k4.Relatorio.proximos_passos | Where-Object { $_.passo -eq 'CLAUDE_FALLBACK' -and $_.tier -eq 'BARATO' }).Count -eq 3) -and $k4.Relatorio.insuficiencia -eq 3) 'K4 Claude com teto para 3 pacotes baratos cobre 3, os outros 3 seguem INSUFICIENCIA'

Write-Host 'L. guardas estruturais no motor'
$motor = [IO.File]::ReadAllText((Join-Path $Scripts 'run_vixradar_varredura.ps1'))
Assert-Cd ($motor -match "lib\\vixradar-cobertura-diaria\.ps1") 'L1 motor carrega a lib da cobertura diaria'
Assert-Cd ($motor -match 'Set-VixCobDiariaUniverso') 'L2 motor grava o universo do plano'
Assert-Cd (([regex]::Matches($motor, 'Register-VixCobDiaria(Verificacao)? ')).Count -ge 4) 'L3 motor registra skip, triagem, analise e deferimento'
Assert-Cd ($motor -match 'Register-VixCobDiariaVerificacao') 'L4 motor classifica a verificacao do dia pela funcao pura'
$mCap = [regex]::Match($motor, "modo = 'matinal'; top_n = 20[\s\S]{0,400}?capProprio = (\d+)")
$mRes = [regex]::Match($motor, 'Get-VixReservaMatinalPendente[^\r\n]*-CapMatinal (\d+)')
Assert-Cd ($mCap.Success -and $mRes.Success -and $mCap.Groups[1].Value -eq $mRes.Groups[1].Value) 'L8 reserva da matinal = capProprio do perfil matinal (sem numero solto divergente)'
Assert-Cd ($motor -match "VIXRADAR_COBERTURA_DIARIA" -and $motor -match 'Fechamento:\(\$script:VixCobDiariaAtivo') 'L9 incidente/alerta so com VIXRADAR_COBERTURA_DIARIA=1 (sombra por padrao)'
Assert-Cd ($motor -match "if \(\`$__decAus\.recheck\) \{ \`$__cdCls = 'INCONCLUSIVO' \}") 'L10 recheck de ausencia nunca fecha o dia como analisado'

Write-Host 'M. segunda amostra e recoleta'
$PM = Join-Path $Tmp 'm'; New-Item -ItemType Directory -Path $PM | Out-Null
$PML = Get-VixCobDiariaPath $PM $Dia
$colNova = New-Coleta 'Rumo' $TsHoje @([pscustomobject]@{ familia = 'F1'; titulo = 'Rumo capta R$ 1 bi'; veiculo = 'Valor'; dominio = 'valor.globo.com'; data = '2026-10-14' })
$script:chamadas = 0
$fnNova = { $script:chamadas++; return $colNova }
$m1 = Register-VixCobDiariaVerificacao -Path $PML -DateTag $Dia -Empresa 'Rumo' -Coleta (New-Coleta 'Rumo' $TsHoje) -ColetaFn $fnNova -DeltaInicio '2026-10-13' -Rotina 't' -Agora $Agora
Assert-Cd ($m1.Resultado -eq 'NOVIDADE' -and $m1.Estado -eq 'PENDENTE_IA' -and $m1.Motivo -like 'segunda_amostra_*' -and $script:chamadas -eq 1) 'M1 quieto na 1a amostra e fato na 2a => obrigacao (RSS nao deterministico)'
$script:chamadas = 0
$m2 = Register-VixCobDiariaVerificacao -Path $PML -DateTag $Dia -Empresa 'Vibra' -Coleta (New-Coleta 'Vibra' $TsHoje) -ColetaFn $fnNova -JaConfirmado $true -DeltaInicio '2026-10-13' -Rotina 't' -Agora $Agora
Assert-Cd ($m2.Estado -eq 'VERIFICADO_SEM_NOVIDADE' -and $script:chamadas -eq 0) 'M2 quieto ja confirmado pelo motor nao recoleta'
$fnHoje = { return (New-Coleta 'Copel' $TsHoje) }
$m3 = Register-VixCobDiariaVerificacao -Path $PML -DateTag $Dia -Empresa 'Copel' -Coleta (New-Coleta 'Copel' $TsOntem) -ColetaFn $fnHoje -DeltaInicio '2026-10-13' -Rotina 't' -Agora $Agora
Assert-Cd ($m3.Estado -eq 'VERIFICADO_SEM_NOVIDADE') 'M3 cache de ontem e recoletado antes de concluir'
$m4 = Register-VixCobDiariaVerificacao -Path $PML -DateTag $Dia -Empresa 'Sabesp' -Coleta (New-Coleta 'Sabesp' $TsOntem) -ColetaFn $null -Rotina 't' -Agora $Agora
Assert-Cd ($m4.Estado -eq 'FALHA_CONSULTA') 'M4 cache de ontem sem recoleta possivel => FALHA_CONSULTA, nunca verificado'
$m5 = Register-VixCobDiariaVerificacao -Path $PML -DateTag $Dia -Empresa 'Light' -Coleta (New-Coleta 'Light' $TsHoje) -ColetaFn { throw 'rede' } -DeltaInicio '2026-10-13' -Rotina 't' -Agora $Agora
Assert-Cd ($m5.Estado -eq 'FALHA_CONSULTA' -and -not $m5.Erro) 'M5 segunda amostra que falha nao certifica ausencia e nao derruba a rotina'
Assert-Cd ($motor -match 'Invoke-VixCobDiariaFechamento') 'L5 noturna fecha o dia pelo portao'
Assert-Cd ($motor -match 'Get-VixReservaMatinalPendente') 'L6 cap da noturna reserva a matinal pendente'
Assert-Cd ($motor -match 'Select-VixCobDiariaOrdem') 'L7 obrigatorio do dia na frente da fila'

Write-Host 'N. idempotencia nao trava deferido (caso real 14/10 18:05)'
$logReal = Join-Path (Split-Path $Scripts -Parent) 'logs\routines\vixradar-noturno_20261014.log'
$linhasN = @()
if (Test-Path -LiteralPath $logReal) { $linhasN = @(Get-Content -LiteralPath $logReal -Encoding UTF8 | Where-Object { $_ -match '^2026-10-14 0[0-9]:[\d:]+ OK\|' }) }
if ($linhasN.Count -ge 100) {
    $nOld = Get-VixIdempotenciaProcessados -Linhas $linhasN -ReprocessarDeferidos $false
    $nNew = Get-VixIdempotenciaProcessados -Linhas $linhasN -ReprocessarDeferidos $true
    Assert-Cd (@($nOld.Processados).Count -eq 104) ('N1 regra antiga trava os 104 da execucao das 02:28 (medido: ' + @($nOld.Processados).Count + ')')
    Assert-Cd (@($nNew.Processados).Count -eq 32 -and @($nNew.DeferidosReabertos).Count -eq 72) ('N2 regra nova trava 16 analisados + 16 skip e reabre os 72 deferidos (medido: ' + @($nNew.Processados).Count + '/' + @($nNew.DeferidosReabertos).Count + ')')
} else { Write-Host '  PULO  N1/N2 log real de 14/10 ausente nesta maquina (nao conta como OK)' }
$sint = @('2026-10-14 02:40:00 OK|Vale|FULL|-|0|true|DEFERIDO|0', '2026-10-14 18:30:00 OK|Vale|LIGHT|NENHUM|0|true|ANALISADO|0', '2026-10-14 02:41:00 OK|Rumo|FULL|-|0|true|DEFERIDO|0', '2026-10-14 02:42:00 OK|Oi|SKIP|-|0|true|SKIP|0', '2026-10-14 02:43:00 DRYRUN|Gol|FULL|-|0|false|ANALISADO|0')
$n3 = Get-VixIdempotenciaProcessados -Linhas $sint -ReprocessarDeferidos $true
Assert-Cd ((@($n3.Processados) -contains 'Vale') -and (@($n3.Processados) -contains 'Oi') -and -not (@($n3.Processados) -contains 'Rumo') -and (@($n3.DeferidosReabertos) -join ',') -eq 'Rumo') 'N3 deferido depois analisado trava; so-deferido reabre; SKIP trava'
Assert-Cd (-not (@($n3.Processados) -contains 'Gol')) 'N4 linha DRYRUN nunca conta como processada'
$n5 = Get-VixIdempotenciaProcessados -Linhas @('2026-10-14 02:40:00 OK|Legado|FULL') -ReprocessarDeferidos $true
Assert-Cd (@($n5.Processados) -contains 'Legado') 'N5 linha OK| em formato antigo continua travando (fail-safe)'

Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falhas')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
