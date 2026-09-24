# test-monitor-kfp-janela.ps1 - prova de duas pontas da janela de falso-positivo conhecido.
#
# KFPJANELA1 (2026-09-24). A regra antiga media a graca a partir do LastRunTime VIVO da task
# (($agora - $lastRun).Days <= graceDays). Task que falha em toda execucao renova o
# LastRunTime, o contador volta a zero e a excecao nunca expira: a falha real fica mascarada
# para sempre (medido: 52 de 52 rodadas do monitor em 8 semanas de falha semanal continua).
#
# Este teste roda a MESMA funcao que a producao usa (dot-source da lib vixradar-monitor-kfp)
# e compara contra a regra antiga, reproduzida aqui apenas como linha de base do "antes".
# Nao executa o monitor, nao le nem escreve task, nao usa rede. ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'
$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib\vixradar-monitor-kfp.ps1')

$inv = [System.Globalization.CultureInfo]::InvariantCulture
function Dt([string]$s) { return [datetime]::ParseExact($s, 'yyyy-MM-dd HH:mm', $inv) }

$entrada = @{ code = 1; reason = 'teste'; frozenLastRun = '2026-08-03'; graceDays = 7 }
function Decisao([string]$lr, [string]$agora, [int]$code = 1, $e = $null) {
    if ($null -eq $e) { $e = $entrada }
    return Get-VixMonitorKfpDecision -Name 'VIXRadar-Reconciliacao-CVM' -Code $code -LastRun (Dt $lr) -Now (Dt $agora) -Entry $e
}
# Regra antiga, so como linha de base do defeito. Nao e usada pela producao.
function MascaradoRegraAntiga([string]$lr, [string]$agora, [int]$grace, [int]$code, [int]$codeKfp) {
    if ($code -ne $codeKfp) { return $false }
    return (((Dt $agora) - (Dt $lr)).Days -le $grace)
}

Write-Host '=== 1. caso vivo medido: exit 1 de 21/09 nao e o incidente documentado de 03/08 ==='
$d = Decisao '2026-09-21 08:00' '2026-09-24 07:00'
Assert ($d.Matched) 'codigo 1 casa com a entrada do mapa'
Assert (-not $d.Masked) 'NAO mascarado: resultado de 21/09 e posterior a ancora 03/08'
Assert ($d.NewFailure) 'marcado como falha nova (segue para a classificacao normal = erro)'
Assert (MascaradoRegraAntiga '2026-09-21 08:00' '2026-09-24 07:00' 7 1 1) 'linha de base: a regra antiga mascarava ESTE caso'

Write-Host ''
Write-Host '=== 2. incidente documentado dentro da janela: mascarar ==='
$d = Decisao '2026-08-03 08:00' '2026-08-07 07:00'
Assert ($d.Masked) 'ancora 03/08 com 4 dias: mascarado'
Assert (-not $d.NewFailure) 'nao e falha nova (LastRun igual a ancora)'

Write-Host ''
Write-Host '=== 3. limites da janela: 7 dias mascara, 8 dias expira ==='
$d = Decisao '2026-08-03 08:00' '2026-08-10 07:00'
Assert ($d.Masked -and $d.AgeDays -eq 7) 'dia 7/7 ainda mascarado (limite inclusivo)'
$d = Decisao '2026-08-03 08:00' '2026-08-11 07:00'
Assert ((-not $d.Masked) -and $d.Expired -and $d.AgeDays -eq 8) 'dia 8/7 expira: escala para warning, nao mascara'

Write-Host ''
Write-Host '=== 4. codigo diferente do documentado: entrada nao opina ==='
$d = Decisao '2026-08-03 08:00' '2026-08-04 07:00' 2
Assert ((-not $d.Matched) -and (-not $d.Masked) -and (-not $d.Expired) -and (-not $d.NewFailure)) 'code 2 nao casa com code 1: nenhuma interceptacao'

Write-Host ''
Write-Host '=== 5. fail-closed: entrada sem ancora nunca mascara ==='
$semAncora = @{ code = 1; reason = 'teste'; graceDays = 7 }
$d = Decisao '2026-08-03 08:00' '2026-08-04 07:00' 1 $semAncora
Assert ((-not $d.Masked) -and $d.Expired) 'entrada sem frozenLastRun expira em vez de mascarar'
$ancoraIlegivel = @{ code = 1; reason = 'teste'; frozenLastRun = '03/08/2026'; graceDays = 7 }
$d = Decisao '2026-08-03 08:00' '2026-08-04 07:00' 1 $ancoraIlegivel
Assert ((-not $d.Masked) -and $d.Expired) 'frozenLastRun ilegivel expira em vez de estourar/mascarar'

Write-Host ''
Write-Host '=== 6. simulacao: task semanal (segunda 12:00) falhando TODA semana, monitor diario 07:00 ==='
$maskOld = 0; $maskNew = 0; $maskNewForaJanela = 0; $total = 0
$baseSeg = Dt '2026-08-03 12:00'
for ($dia = Dt '2026-08-04 07:00'; $dia -le (Dt '2026-09-24 07:00'); $dia = $dia.AddDays(1)) {
    $lr = $baseSeg
    while ($lr.AddDays(7) -lt $dia) { $lr = $lr.AddDays(7) }
    $lrTxt = $lr.ToString('yyyy-MM-dd HH:mm', $inv)
    $agoraTxt = $dia.ToString('yyyy-MM-dd HH:mm', $inv)
    $total++
    if (MascaradoRegraAntiga $lrTxt $agoraTxt 7 1 1) { $maskOld++ }
    $dec = Decisao $lrTxt $agoraTxt
    if ($dec.Masked) {
        $maskNew++
        if ($dia -gt (Dt '2026-08-10 23:59')) { $maskNewForaJanela++ }
    }
}
Write-Host ("  rodadas do monitor: $total | mascaradas regra antiga: $maskOld | mascaradas regra nova: $maskNew")
Assert ($maskOld -eq $total) 'linha de base: regra antiga mascarou 100% das rodadas (defeito reproduzido)'
Assert ($maskNew -lt $maskOld) 'regra nova mascarou menos que a antiga'
Assert ($maskNewForaJanela -eq 0) 'regra nova NUNCA mascara depois de 10/08 (janela 03/08+7d)'
Assert ($maskNew -eq 7) 'regra nova mascara exatamente os 7 dias da janela documentada'

Write-Host ''
Write-Host '=== 7. ligacao do pipeline: o monitor usa a lib, sem a condicao antiga ==='
$srcMon = Get-Content (Join-Path $scriptDir 'monitor-tasks.ps1') -Raw -Encoding UTF8
Assert ($srcMon -match 'Get-VixMonitorKfpDecision') 'monitor-tasks.ps1 chama Get-VixMonitorKfpDecision'
Assert ($null -ne (Get-Command 'Get-VixMonitorKfpDecision' -ErrorAction SilentlyContinue)) 'a funcao existe na lib que o monitor dot-sourceia'
Assert (-not ($srcMon -match '\$ageDays\s*-le\s*\$kfp\.graceDays')) 'a condicao antiga (graca sobre LastRun vivo) nao existe mais no monitor'
Assert ($srcMon -match "Join-Path\s+\`$ScriptDir\s+'lib\\vixradar-monitor-kfp\.ps1'") 'o monitor carrega a lib pelo caminho que o guarda de funcoes le'
$bloco = [regex]::Match($srcMon, '(?s)\$KnownFalsePositives\s*=\s*@\{(.*?)\n\}').Groups[1].Value
$nCodes = ([regex]::Matches($bloco, 'code\s*=')).Count
$nAncoras = ([regex]::Matches($bloco, 'frozenLastRun\s*=')).Count
Assert ($nCodes -ge 3) ('leu o mapa de verdade (entradas=' + $nCodes + ')')
Assert ($nCodes -eq $nAncoras) ('toda entrada do mapa tem frozenLastRun (code=' + $nCodes + ' ancora=' + $nAncoras + ')')
Assert ($bloco -match "'VIXRadar-Reconciliacao-CVM'") 'a entrada da Reconciliacao-CVM esta no mapa'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
