# test-monitor-drenofalha.ps1 - prova do aviso 9008 (DRENOMUDO1, 2026-09-13).
#   (1) linha `dreno FALHOU (exit=N)` no log vira achado, com o exemplo carregado;
#   (2) campo `dreno_exit` no metrics vira achado MESMO com log limpo (as duas fontes);
#   (3) dia limpo (exit 0 / null / log sem falha) nao vira achado - nao inventa falha;
#   (4) log ANTIGO, do formato anterior ao fix, NAO casa: o texto antigo mentia e nao prova nada;
#   (5) wiring do monitor: grava em $degradacoes/$warnings, nunca em $erros, com rotulo proprio;
#   (6) monitor e lib continuam parseaveis.
# ASCII puro, PS 5.1, sem rede, sem escrita fora de $env:TEMP. Devolve a lib de verdade.
$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib\vixradar-watchdog.ps1')

$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$tmp = Join-Path $env:TEMP ('vix-dreno-' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$diaFalha = [datetime]'2099-03-01'   # domingo, mas a funcao nao julga dia
$diaLimpo = [datetime]'2099-03-02'

Write-Host '=== 1. Log com dreno falho vira achado ==='
$tagF = $diaFalha.ToString('yyyyMMdd')
@('2099-03-01 16:46:22 POS-MATINAL: drena a fila de verificacao...',
  '2099-03-01 16:46:55 POS-MATINAL: dreno FALHOU (exit=5) - a fila de verificacao NAO foi drenada',
  '2099-03-01 16:46:55 ERRO DRENO: a fila de verificacao NAO foi drenada por esta rotina (exit=5). Log do dreno: logs/routines/vixradar-verificacao-async_20990301.log') |
    Set-Content (Join-Path $tmp ('vixradar-matinal_' + $tagF + '.log')) -Encoding UTF8
$ach = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaFalha))
Assert ($ach.Count -eq 1) ('um achado (achados=' + $ach.Count + ')')
Assert ($ach.Count -eq 1 -and $ach[0].exit -eq 5) ('exit capturado do log=' + $(if ($ach.Count -eq 1) { $ach[0].exit } else { 'n/a' }))
Assert ($ach.Count -eq 1 -and $ach[0].rotina -eq 'vixradar-matinal') 'rotina carimbada'
Assert ($ach.Count -eq 1 -and ($ach[0].exemplo -match 'ERRO DRENO')) 'exemplo traz a linha ERRO DRENO, nao a introducao'

Write-Host '=== 2. Metrics com dreno_exit prova a falha mesmo com log limpo ==='
$tagL = $diaLimpo.ToString('yyyyMMdd')
[ordered]@{ data = $tagL; rotina = 'noturno'; dreno_exit = 7 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('noturno_metrics_' + $tagL + '.json')) -Encoding UTF8
Set-Content (Join-Path $tmp ('vixradar-noturno_' + $tagL + '.log')) -Value '2099-03-02 19:02:00 FIM: noturno concluido. submit_ok=100' -Encoding UTF8
$achMet = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaLimpo))
Assert ($achMet.Count -eq 1) ('achado pelo metrics (achados=' + $achMet.Count + ')')
Assert ($achMet.Count -eq 1 -and $achMet[0].exit -eq 7 -and $achMet[0].exit_metrics -eq 7) 'exit efetivo vem do metrics quando o log esta limpo'
Assert ($achMet.Count -eq 1 -and $achMet[0].fonte -match 'metrics') 'fonte aponta o metrics quando ele existe'

Write-Host '=== 3. Dia limpo nao vira achado (nao inventa falha) ==='
$diaLimpo2 = [datetime]'2099-03-03'
$tagL2 = $diaLimpo2.ToString('yyyyMMdd')
@('2099-03-03 16:46:22 POS-MATINAL: dreno concluido (exit=0)',
  '2099-03-03 16:46:22 FIM: matinal concluido. submit_ok=23 dreno_exit=0') |
    Set-Content (Join-Path $tmp ('vixradar-matinal_' + $tagL2 + '.log')) -Encoding UTF8
[ordered]@{ data = $tagL2; rotina = 'matinal'; dreno_exit = 0 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('matinal_metrics_' + $tagL2 + '.json')) -Encoding UTF8
$limpo = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaLimpo2))
Assert ($limpo.Count -eq 0) ('exit 0: nenhum achado (achados=' + $limpo.Count + ')')
$diaSemDreno = [datetime]'2099-03-04'
$tagS = $diaSemDreno.ToString('yyyyMMdd')
[ordered]@{ data = $tagS; rotina = 'matinal'; dreno_exit = $null } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('matinal_metrics_' + $tagS + '.json')) -Encoding UTF8
Set-Content (Join-Path $tmp ('vixradar-matinal_' + $tagS + '.log')) -Value '2099-03-04 16:10:00 FIM: matinal concluido. submit_ok=0' -Encoding UTF8
$semDreno = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaSemDreno))
Assert ($semDreno.Count -eq 0) ('dreno_exit null (nem tentado): nenhum achado (achados=' + $semDreno.Count + ')')

Write-Host '=== 4. Texto ANTIGO (antes do fix) nao casa ==='
$diaAntigo = [datetime]'2099-03-05'
$tagA = $diaAntigo.ToString('yyyyMMdd')
Set-Content (Join-Path $tmp ('vixradar-matinal_' + $tagA + '.log')) -Value '2099-03-05 16:46:55 POS-MATINAL: dreno concluido (exit=5)' -Encoding UTF8
$antigo = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaAntigo))
Assert ($antigo.Count -eq 0) ('linha do formato antigo nao gera achado - ela mentia e nao prova falha (achados=' + $antigo.Count + ')')
Assert ($antigo.Count -eq 0) 'ponta ruim: sem o fix no motor nenhum dreno falho seria detectavel aqui'

Write-Host '=== 5. Dois dias: so o dia com falha; diretorio inexistente devolve vazio ==='
$ambos = @(Get-VixDrenoFalha -RotinasLogDir $tmp -Dias @($diaFalha, $diaLimpo2))
Assert ($ambos.Count -eq 1) ('dois dias juntos: so o dia com falha (achados=' + $ambos.Count + ')')
$vazio = @(Get-VixDrenoFalha -RotinasLogDir (Join-Path $tmp 'nao-existe') -Dias @($diaFalha))
Assert ($vazio.Count -eq 0) 'diretorio inexistente: 0 achados, sem excecao'

Write-Host '=== 6. Wiring do monitor: aviso operacional, nunca falha da rotina ==='
$mont = Get-Content (Join-Path $scriptDir 'monitor-tasks.ps1') -Raw -Encoding UTF8
Assert ($mont -match 'Get-VixDrenoFalha') 'monitor-tasks chama Get-VixDrenoFalha'
Assert ($mont -match 'AVISO: DRENO_FALHOU') 'monitor-tasks loga AVISO: DRENO_FALHOU'
Assert ($mont -match "code\s*=\s*9008") 'monitor-tasks marca codigo 9008 (distinto de 9004/9007)'
Assert ($mont -match 'Drenos de verificacao falhos') 'resumo do monitor publica o contador proprio'
Assert ($mont -match '\$nDreno') 'contador de dreno entra no gatilho de e-mail com rotulo proprio'
$bloco = [regex]::Match($mont, 'DRENOMUDO1 \(2026-09-13\): o dreno pos-varredura[\s\S]{0,4000}?\$warnings \+= \$entry\r?\n    \}').Value
Assert ($bloco.Length -gt 100) 'bloco de deteccao localizado no monitor-tasks.ps1'
Assert (-not ($bloco -match '\$erros \+=')) 'ponta ruim: o bloco NAO escreve em $erros (nao muda o exit code do monitor)'
Assert ($bloco -match 'Get-VixDrenoFalha') 'o bloco localizado e mesmo o do dreno'

Write-Host '=== 7. Sintaxe: monitor e lib continuam parseaveis (o vigia roda todo dia as 07:00) ==='
foreach ($f in @('monitor-tasks.ps1', 'lib\vixradar-watchdog.ps1', 'run_vixradar_varredura.ps1')) {
    $toks = $null; $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir $f), [ref]$toks, [ref]$errs)
    $n = @($errs).Count
    Assert ($n -eq 0) ($f + ': 0 erro de parse (achados=' + $n + $(if ($n -gt 0) { ' -> ' + $errs[0].Message } else { '' }) + ')')
}
$motor = Get-Content (Join-Path $scriptDir 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Assert ($motor -match 'dreno_exit = \$stats\.dreno_exit') 'motor grava dreno_exit no metrics'
Assert ($motor -match '(?m)^\s*dreno_exit = \$null\s*$') 'motor inicializa dreno_exit como null (nao confunde "nao rodou" com "drenou")'
Assert ($motor -match 'Invoke-VixDrenoPosRotina -ScriptPath') 'motor chama o dreno pela funcao testavel'
Assert ($motor -match 'dreno_exit=') 'motor publica dreno_exit no resumo do dia'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
