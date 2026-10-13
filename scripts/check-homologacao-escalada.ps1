# check-homologacao-escalada.ps1 - COBERTURA-13OUT4 (2026-10-13)
#
# Para que serve. A escalada seletiva esta implementada e provada offline, mas NUNCA rodou ponta a
# ponta: a prova offline usa as funcoes reais, nao o lote real. Homologar e rodar UMA execucao
# dirigida, com coletor economico ligado e poucos emissores, e julgar o LOG dela contra uma lista
# fechada de marcas. Este script e esse julgamento, e existe para a leitura nao depender de alguem
# lembrar de todos os campos no meio de um log de milhares de linhas.
#
# Ele NAO executa rotina nenhuma. So le arquivo de log. Rodar isto nao gasta token, nao toca
# producao e nao altera agendamento.
#
# Uso:
#   pwsh ./scripts/check-homologacao-escalada.ps1 -LogPath logs/routines/vixradar-noturno_20261014_dryrun_1234.log
#   pwsh ./scripts/check-homologacao-escalada.ps1 -LogPath <log> -Emissor "Usina Pampa Sul"
#
# Saida: uma linha por marca (OK/FALHA) e o veredito. exit 0 = homologacao aprovada,
# exit 1 = reprovada. Reprovacao NAO se mascara: cada FALHA imprime o motivo e o que procurar.
#
# ASCII puro, PowerShell 5.1, $ErrorActionPreference Continue.

param(
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$Emissor = ''
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $LogPath)) { Write-Host ('ERRO: log ausente: ' + $LogPath); exit 2 }
$texto = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
if (-not $texto) { Write-Host ('ERRO: log vazio: ' + $LogPath); exit 2 }
$linhas = @($texto -split "`r?`n")

$script:Ok = 0
$script:Falhas = 0
function Assert-Hom([bool]$Cond, [string]$Nome, [string]$ComoResolver) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) }
    else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome); if ($ComoResolver) { Write-Host ('        procurar: ' + $ComoResolver) } }
}
# CASO-SENSIVEL1 (2026-10-13): -cmatch, nao -match. Os 13 criterios procuram marcadores LITERAIS
# que o motor escreve em maiuscula (COLETOR_PS, ESCALADA_LOTE, CAP_EXCEDIDO...), mas -match e
# insensivel a caixa por padrao e a linha FIM publica o contador SAUDOSO `cap_excedido=0` - que
# casava com o criterio H10 e o reprovava em toda execucao boa. Medido no log real de 13/10
# (vixradar-noturno_20261013_dryrun_20036.log): nenhuma linha CAP_EXCEDIDO existe, e o H10
# reprovava mesmo assim. A prova sintetica nao pegava porque o log "bom" dela nao tinha o campo
# `cap_excedido=` que todo log real tem. Comparar marcador de maquina pela caixa exata e o que
# torna o criterio sobre o evento e nao sobre o resumo do evento.
function Select-Linha([string]$Padrao) { return @($linhas | Where-Object { $_ -cmatch $Padrao }) }

Write-Host ('=== homologacao da escalada seletiva: ' + $LogPath + ' ===')
if ($Emissor) { Write-Host ('  (emissor filtrado: ' + $Emissor + ')') }

# H1/H2 - os dois interruptores. Sem eles a execucao nao testou nada: o motor sobe, roda o
# caminho antigo e o log fica identico ao de antes desta mudanca.
Assert-Hom (@(Select-Linha 'COLETOR_PS: ativo=True').Count -ge 1) 'H1 coletor economico ativo nesta execucao' 'VIXRADAR_COLETOR_PS=1 no escopo User ou no processo'
Assert-Hom (@(Select-Linha 'ESCALADA_FULL: ativo=True').Count -ge 1) 'H2 escalada seletiva ativa nesta execucao' 'VIXRADAR_ESCALADA_FULL ausente ou diferente de 0 (e COLETOR_PS=1)'
Assert-Hom (@(Select-Linha 'ESCALADA_CUSTO_BASE:').Count -ge 1) 'H3 custo-base da escalada declarado no log' 'linha ESCALADA_CUSTO_BASE: <n>/emissor'

# H4 - a coleta economica chegou no emissor. Sem isso a decisao cairia em coleta_indisponivel.
$fontes = @(Select-Linha 'FONTES_COLETOR\|')
Assert-Hom ($fontes.Count -ge 1) 'H4 consultas do coletor foram somadas ao resultado' 'linha FONTES_COLETOR|<emissor>|<motivo>|adicionadas=3'

# H5/H6 - a decisao foi tomada e alguem foi retido. `escalar=0` em todos os emissores significa
# que o gatilho nao disparou: homologa o caminho barato, nao a escalada.
$decisoes = @(Select-Linha 'ESCALADA_DECISAO\|')
Assert-Hom ($decisoes.Count -ge 1) 'H5 decisao de escalada registrada por emissor' 'linha ESCALADA_DECISAO|<emissor>|escalar=0|1|motivo|prioridade|...'
$escalados = @($decisoes | Where-Object { $_ -match 'escalar=1' })
Assert-Hom ($escalados.Count -ge 1) 'H6 ao menos um emissor foi retido para a rodada FULL' 'ESCALADA_DECISAO com escalar=1; sem gatilho, escolher emissor com fato novo ou EWS >= 50'
$lotes = @(Select-Linha 'ESCALADA_LOTE:')
Assert-Hom ($lotes.Count -ge 1 -and (($lotes -join ' ') -notmatch 'nenhum emissor retido')) 'H7 rodada de escalada montada com lote' 'linha ESCALADA_LOTE: <n> emissor(es) retido(s) ... <m> lote(s) FULL'

# H8 - a fonte primaria foi ABERTA. Esta e a marca que separa "escalou" de "escalou e confirmou":
# sem fetch/busca real, a rodada FULL pagou caro para repetir a manchete do pacote barato.
$outFetch = @(Select-Linha 'OUT.*web_fetch|OUT.*web_search')
$buscasEsc = @(Select-Linha 'LOTE_FECHADO\|escalada-[0-9]+\|.*buscas=[1-9]')
Assert-Hom ($outFetch.Count -ge 1 -or $buscasEsc.Count -ge 1) 'H8 a rodada de escalada abriu fonte primaria (fetch ou busca real)' 'OUT com web_fetch/web_search, ou LOTE_FECHADO|escalada-N|...|buscas>=1'

# H9 - o ledger fechou o emissor como ANALISADO no tier FULL. E a prova de que a rodada de
# escalada SUBSTITUIU a submissao barata (o retido nao submete duas vezes).
# DRYRUN-HOMOLOG1 (2026-10-13): o prefixo do ledger tem de ser aceito nas DUAS formas. A
# homologacao que este validador existe para julgar e uma execucao dirigida -DryRun (o proprio
# motor diz isso: "a homologacao da escalada e uma execucao dirigida (-DryRun -MaxEmissores 1)"),
# e Write-Ledger grava 'DRYRUN|' quando $DryRun, nao 'OK|'. A versao anterior exigia 'OK|' e
# reprovava toda execucao legitima de dry-run - defeito que a prova V1 nao pegou porque o log
# sintetico dela usava a linha de execucao real. O status ANALISADO passa a ser exigido: sem ele
# o criterio aceitaria DEFERIDO, que e exatamente o caso em que a escalada NAO fechou o emissor.
$padraoLedger = '(OK|DRYRUN)\|[^|]+\|FULL\|[^|]*\|[^|]*\|[^|]*\|ANALISADO\|'
if ($Emissor) { $padraoLedger = ('(OK|DRYRUN)\|' + [regex]::Escape($Emissor) + '\|FULL\|[^|]*\|[^|]*\|[^|]*\|ANALISADO\|') }
$ledger = @(Select-Linha $padraoLedger)
Assert-Hom ($ledger.Count -ge 1) 'H9 existe linha de ledger ANALISADO no tier FULL para o emissor escalado' '(OK|DRYRUN)|<emissor>|FULL|<classif>|<n>|true|ANALISADO|'

# H10 - nada estourou o teto. CAP_EXCEDIDO na rodada de escalada significa que a estimativa
# continua otimista e o cap segue sendo so teto de admissao.
$capExc = @(Select-Linha 'CAP_EXCEDIDO')
Assert-Hom ($capExc.Count -eq 0) 'H10 nenhum CAP_EXCEDIDO na execucao' 'nenhuma linha CAP_EXCEDIDO; se houver, a estimativa por emissor subestimou'

# H11 - o desfecho da execucao esta declarado e e legivel por maquina.
$fim = @(Select-Linha '(FIM_DRYRUN|FIM|FIM_INVALIDO): ')
Assert-Hom ($fim.Count -ge 1) 'H11 linha FIM/FIM_DRYRUN presente' 'linha FIM: <rotina> concluido ... resultado=<OK|PARCIAL|FALHA>'
# DRYRUN-HOMOLOG1: o desfecho de uma execucao dirigida em dry-run e literalmente
# 'resultado=DRYRUN' (o motor nao inventa OK nem PARCIAL para uma execucao que nao submeteu) e a
# versao anterior reprovava esse caso. Os dois campos exigidos pelo proprio rotulo deste criterio
# passam a ser exigidos de verdade: resultado= qualificado E pendentes_obrigatorios= presentes.
$comResultado = @(Select-Linha 'resultado=(OK|PARCIAL|FALHA|DRYRUN)')
$comPendentes = @(Select-Linha 'pendentes_obrigatorios=')
Assert-Hom ($comResultado.Count -ge 1 -and $comPendentes.Count -ge 1) 'H12 desfecho da rotina qualificado (resultado= e pendentes_obrigatorios=)' 'linha ROTINA_RESUMO|<id>|...|resultado=... pendentes_obrigatorios=...'

# H13 - nenhum retido ficou sem desfecho. Somatorio dos destinos tem de fechar com o total retido.
# DRYRUN-HOMOLOG1 (2026-10-13): a versao anterior se auto-anulava. A condicao era
# `$script:Falhas -eq 0 -or ...`, ou seja, passava SEMPRE que H1-H12 passavam, sem conferir nada:
# nao era guarda, era eco do resultado anterior. E o criterio que existe justamente para provar
# "nenhum retido sem desfecho" - exigencia explicita da homologacao - entao agora a conta e feita
# de verdade, pelos contadores que o proprio FIM publica: retido = analisado + sem orcamento +
# abortado. Aborto por auth e somado a parte porque o motivo do deferido passa a ser o do aborto
# (COBERTURAAUTH1) e o contador por causa deixa de isolar o emissor escalado.
$retidos = 0
foreach ($l in @(Select-Linha 'ESCALADA_LOTE: [0-9]+ emissor')) {
    $m = [regex]::Match($l, 'ESCALADA_LOTE: (\d+) emissor')
    if ($m.Success) { $retidos += [int]$m.Groups[1].Value }
}
$aborto = @(Select-Linha 'ESCALADA_ABORTO:')
$abortados = 0
foreach ($l in $aborto) {
    $m = [regex]::Match($l, 'ESCALADA_ABORTO: (\d+) emissor')
    if ($m.Success) { $abortados += [int]$m.Groups[1].Value }
}
$fechados = -1
$temContadores = $false
foreach ($l in @(Select-Linha 'escalada_retidos=[0-9]+')) {
    $m = [regex]::Match($l, 'escalada_analisados=(\d+).*?escalada_sem_orcamento=(\d+)')
    if ($m.Success) { $temContadores = $true; $fechados = [int]$m.Groups[1].Value + [int]$m.Groups[2].Value + $abortados }
}
if ($retidos -gt 0) {
    Assert-Hom ($temContadores -and $fechados -eq $retidos) 'H13 todo emissor retido tem desfecho declarado (escalado + sem orcamento + abortado = retido)' ('retidos=' + $retidos + ' fechados=' + $fechados + ' sem_contadores=' + (-not $temContadores) + '; diferenca = emissor retido que sumiu entre a retencao e a rodada FULL')
} else {
    Assert-Hom $false 'H13 todo emissor retido tem desfecho declarado' 'nenhuma linha ESCALADA_LOTE com emissor retido - a escalada nao foi exercitada'
}

Write-Host ('RESULTADO_HOMOLOGACAO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { Write-Host 'VEREDITO: REPROVADO'; exit 1 }
Write-Host 'VEREDITO: APROVADO'
exit 0
