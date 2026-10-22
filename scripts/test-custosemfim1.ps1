# test-custosemfim1.ps1 - CUSTOSEMFIM1: execucao morta sem linha FIM deve contar pelos LOTE_FECHADO.
# Prova de duas pontas com logs sinteticos em pasta temporaria. Nao toca logs reais, mutex nem rotina viva.
# Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-custo.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}
$tmp = Join-Path $env:TEMP ('custosemfim1_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$dia = '20261021'
$ini = '2026-10-21 18:05:00 INICIO: noturno (motor Task Scheduler, run_vixradar_varredura.ps1, modo=real) tier=LIGHT'
$lote = { param($n, $t, $dry) '2026-10-21 18:30:00 LOTE_FECHADO|full-' + $n + '|ok=4|fail=0|dryrun=' + $dry + '|buscas=20|criticos=0|tokens=' + $t + '|duracao_sec=100' }
$fim = { param($t) '2026-10-21 22:54:58 FIM: noturno concluido PARCIAL (pendentes_obrigatorios=4). Total do dia 104/104 tokens=' + $t + ' cache_read=1' }

# Caso A (ponta ruim do codigo antigo): execucao morta, 3 lotes, sem FIM. Antes dava 0.
$a = Join-Path $tmp 'a'; New-Item -ItemType Directory -Force -Path $a | Out-Null
@($ini, (& $lote 1 100000 0), (& $lote 2 200000 0), (& $lote 3 50000 0)) | Set-Content -LiteralPath (Join-Path $a ('vixradar-noturno_' + $dia + '.log')) -Encoding UTF8
$ra = Get-VixRotinaLogConsumo $a 'noturno' $dia
Confere ('A execucao morta soma os lotes tokens=' + $ra.tokens) ($ra.tokens -eq 350000 -and $ra.sem_fim -eq 1)

# Caso B (ponta boa): execucao completa com FIM nao soma os lotes de novo.
$b = Join-Path $tmp 'b'; New-Item -ItemType Directory -Force -Path $b | Out-Null
@($ini, (& $lote 1 100000 0), (& $lote 2 200000 0), (& $fim 400000)) | Set-Content -LiteralPath (Join-Path $b ('vixradar-noturno_' + $dia + '.log')) -Encoding UTF8
$rb = Get-VixRotinaLogConsumo $b 'noturno' $dia
Confere ('B execucao completa conta so o FIM tokens=' + $rb.tokens) ($rb.tokens -eq 400000 -and $rb.sem_fim -eq 0)

# Caso C: morta + recuperacao completa no mesmo log (o cenario de 21/10).
$c = Join-Path $tmp 'c'; New-Item -ItemType Directory -Force -Path $c | Out-Null
@($ini, (& $lote 1 100000 0), (& $lote 2 200000 0), $ini, (& $lote 1 50000 0), (& $fim 70000)) | Set-Content -LiteralPath (Join-Path $c ('vixradar-noturno_' + $dia + '.log')) -Encoding UTF8
$rc = Get-VixRotinaLogConsumo $c 'noturno' $dia
Confere ('C morta + completa soma as duas tokens=' + $rc.tokens) ($rc.tokens -eq 370000 -and $rc.execucoes -eq 2 -and $rc.sem_fim -eq 1)

# Caso D: lote de dry-run nao entra.
$d = Join-Path $tmp 'd'; New-Item -ItemType Directory -Force -Path $d | Out-Null
@($ini, (& $lote 1 100000 1)) | Set-Content -LiteralPath (Join-Path $d ('vixradar-noturno_' + $dia + '.log')) -Encoding UTF8
$rd = Get-VixRotinaLogConsumo $d 'noturno' $dia
Confere ('D lote dryrun=1 fica fora tokens=' + $rd.tokens) ($rd.tokens -eq 0)

# Caso E: log de outra rotina nao vaza para a consultada.
$e = Join-Path $tmp 'e'; New-Item -ItemType Directory -Force -Path $e | Out-Null
@(($ini -replace 'noturno', 'matinal'), (& $lote 1 100000 0)) | Set-Content -LiteralPath (Join-Path $e ('vixradar-matinal_' + $dia + '.log')) -Encoding UTF8
$re = Get-VixRotinaLogConsumo $e 'noturno' $dia
Confere ('E rotina diferente nao soma tokens=' + $re.tokens) ($re.tokens -eq 0)

# Caso F (F11, contabilidade concorrente): a Matinal ainda esta rodando, sem FIM nem metrics. Uma rotina
# que calcula o custo do dia nesse instante (a Noturna, 18:30 de 21/10) lia matinal=0 com ~951k gastos.
$g = Join-Path $tmp 'g'; New-Item -ItemType Directory -Force -Path $g | Out-Null
$iniM = '2026-10-21 17:14:17 INICIO: matinal (motor Task Scheduler, run_vixradar_varredura.ps1, modo=real) tier=FULL'
@($iniM, (& $lote 1 500000 0), (& $lote 2 451000 0)) | Set-Content -LiteralPath (Join-Path $g ('vixradar-matinal_' + $dia + '.log')) -Encoding UTF8
$rg = Get-VixRotinaLogConsumo $g 'matinal' $dia
Confere ('F rotina em curso conta o que ja gastou tokens=' + $rg.tokens) ($rg.tokens -eq 951000)
# E quando ela termina, o FIM substitui a soma parcial (sem contagem dupla).
Add-Content -LiteralPath (Join-Path $g ('vixradar-matinal_' + $dia + '.log')) -Value ('2026-10-21 19:31:46 FIM: matinal concluido PARCIAL (pendentes_obrigatorios=2). tokens=1208459 cache_read=1') -Encoding UTF8
$rg2 = Get-VixRotinaLogConsumo $g 'matinal' $dia
Confere ('F2 depois do FIM vale so o FIM tokens=' + $rg2.tokens) ($rg2.tokens -eq 1208459 -and $rg2.sem_fim -eq 0)

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
