# test-custofim1-15out.ps1 - CUSTOFIM1: o CUSTO_DIA soma todas as execucoes reais do dia.
# PowerShell 5.1, ASCII puro. Prova de duas pontas: o codigo antigo (backup) reprova os
# cenarios de sobrescrita; o novo aprova, sem dupla contagem e sem somar dry-run.
param([string]$LibAntiga = '')
$ErrorActionPreference = 'Continue'
$ok = 0; $falha = 0
function Assert-Caso([string]$nome, [bool]$cond, [string]$det) {
    if ($cond) { $script:ok++; Write-Host ('OK    ' + $nome + ' ' + $det) } else { $script:falha++; Write-Host ('FALHA ' + $nome + ' ' + $det) }
}
$lib = Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1'
if ($LibAntiga) { $lib = $LibAntiga }
. $lib

$tmp = Join-Path $env:TEMP ('custofim1_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $tag = '20991015'
    $met = '{"tokens_trabalho":602323,"tokens_input":595682,"tokens_output":6641,"tokens_cache_creation":0,"tokens_cache_read":0,"tokens_mensuraveis":true}'
    Set-Content -LiteralPath (Join-Path $tmp ('noturno_metrics_' + $tag + '.json')) -Value $met -Encoding UTF8
    $fimA = '2099-10-15 02:27:00 FIM: noturno concluido PARCIAL (pendentes_obrigatorios=1). Total do dia 104/104 tokens=442685 cache_read=0'
    $fimB = '2099-10-15 18:20:06 FIM: noturno concluido PARCIAL (pendentes_obrigatorios=7). Total do dia 104/104 tokens=602323 cache_read=0'
    # C1: madrugada no fallback, 18:05 no principal (o caso real de 15/10).
    Set-Content -LiteralPath (Join-Path $tmp ('vixradar-noturno_' + $tag + '.log')) -Value @('2099-10-15 18:05:00 INICIO', $fimB) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmp ('vixradar-noturno_' + $tag + '_fallback_22888.log')) -Value @('2099-10-15 01:31:00 x', $fimA) -Encoding UTF8
    $c = Get-VixCustoDia $tmp $tag
    Assert-Caso 'C1 soma as duas execucoes' ([int64]$c.por_rotina['noturno'].trabalho -eq 1045008) ('noturno=' + $c.por_rotina['noturno'].trabalho)
    Assert-Caso 'C1 total do dia' ([int64]$c.total_consumido -eq 1045008) ('total=' + $c.total_consumido)
    # C2: dry-run com FIM no log proprio nao entra pela regua do log (ja entra pelo metrics proprio).
    Set-Content -LiteralPath (Join-Path $tmp ('vixradar-noturno_' + $tag + '_dryrun_777.log')) -Value @('2099-10-15 12:00:00 FIM: noturno concluido OK tokens=99999') -Encoding UTF8
    $c = Get-VixCustoDia $tmp $tag
    Assert-Caso 'C2 dry-run fora da soma do log' ([int64]$c.por_rotina['noturno'].trabalho -eq 1045008) ('noturno=' + $c.por_rotina['noturno'].trabalho)
    # C3: a mesma linha FIM nos dois arquivos conta uma vez.
    Add-Content -LiteralPath (Join-Path $tmp ('vixradar-noturno_' + $tag + '_fallback_22888.log')) -Value $fimB -Encoding UTF8
    $c = Get-VixCustoDia $tmp $tag
    Assert-Caso 'C3 FIM duplicado conta uma vez' ([int64]$c.por_rotina['noturno'].trabalho -eq 1045008) ('noturno=' + $c.por_rotina['noturno'].trabalho)
    # C4 (ponta boa): uma execucao so, metrics e log iguais -> sem inflar.
    $tmp2 = Join-Path $tmp 'unica'; New-Item -ItemType Directory -Force -Path $tmp2 | Out-Null
    Set-Content -LiteralPath (Join-Path $tmp2 ('noturno_metrics_' + $tag + '.json')) -Value $met -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmp2 ('vixradar-noturno_' + $tag + '.log')) -Value @($fimB) -Encoding UTF8
    $c = Get-VixCustoDia $tmp2 $tag
    Assert-Caso 'C4 execucao unica nao infla' ([int64]$c.por_rotina['noturno'].trabalho -eq 602323) ('noturno=' + $c.por_rotina['noturno'].trabalho)
    # C5: metrics maior que o log (execucao sem FIM ainda) prevalece - max, nunca soma.
    Set-Content -LiteralPath (Join-Path $tmp2 ('vixradar-noturno_' + $tag + '.log')) -Value @('2099-10-15 18:05:00 INICIO') -Encoding UTF8
    $c = Get-VixCustoDia $tmp2 $tag
    Assert-Caso 'C5 sem FIM vale o metrics' ([int64]$c.por_rotina['noturno'].trabalho -eq 602323) ('noturno=' + $c.por_rotina['noturno'].trabalho)
    # C6: matinal com a mesma regra.
    Set-Content -LiteralPath (Join-Path $tmp2 ('matinal_metrics_' + $tag + '.json')) -Value '{"tokens_trabalho":300000,"tokens_input":300000,"tokens_output":0,"tokens_cache_creation":0,"tokens_cache_read":0}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $tmp2 ('vixradar-matinal_' + $tag + '.log')) -Value @('2099-10-15 10:08:55 FIM: matinal concluido PARCIAL tokens=21416 cache_read=0', '2099-10-15 22:30:00 FIM: matinal concluido OK tokens=300000 cache_read=0') -Encoding UTF8
    $c = Get-VixCustoDia $tmp2 $tag
    Assert-Caso 'C6 matinal soma execucoes' ([int64]$c.por_rotina['matinal'].trabalho -eq 321416) ('matinal=' + $c.por_rotina['matinal'].trabalho)
    # C7: cap efetivo enxerga o gasto real (teto 2.600.000, reserva 150.000).
    $cfg = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000; SENTINELA_DIA = 320000 }
    $c = Get-VixCustoDia $tmp $tag $cfg
    $cap = Get-VixCapEfetivo 2000000 $c $cfg 150000
    Assert-Caso 'C7 cap efetivo com gasto real' ([int64]$cap -eq (2600000 - 1045008 - 150000)) ('cap=' + $cap)
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULTADO: ' + $ok + ' OK, ' + $falha + ' falha(s)')
if ($falha -gt 0) { exit 1 }
exit 0
