# test-monitor-degradado402.ps1 - OR402-DEGRADA1 (2026-09-11).
#
# Prova, sem rede, sem e-mail e sem rodar rotina, as DUAS pontas do aviso de degradacao por
# saldo no OpenRouter (HTTP 402): o monitor DETECTA o aviso e ele NAO vira falha de rotina.
#
#   (1) dia com "DEGRADADO_402" no log e/ou degradados_402 no metrics -> achado, com o MAIOR
#       valor entre as duas fontes (o log e o metrics descrevem a MESMA chamada: somar dobraria);
#   (2) dia limpo (metrics com 0, log sem a linha) -> zero achados: o vigia nao inventa incidente.
#
# Terceira parte: as guardas estaticas do wiring no monitor-tasks.ps1 - usa Get-VixDegradado402,
# marca codigo 9007 e escreve em $warnings/$degradacoes, NUNCA em $erros (que e o que decide o
# exit code e a contagem de falhas).
#
# Roda em PowerShell 5.1 e pwsh 7. ASCII puro.
$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\vixradar-watchdog.ps1')

$script:ok = 0
$script:fal = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { $script:ok++; Write-Host ('  OK    ' + $Msg) } else { $script:fal++; Write-Host ('  FALHA ' + $Msg) }
}

$tmp = Join-Path $env:TEMP ('vixradar-monitor-402-test-' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$dia402 = [datetime]'2026-09-11'
$diaLimpo = [datetime]'2026-09-10'
$tag402 = '20260911'
$tagLimpo = '20260910'

$linhaWarn = '2026-09-11 18:40:00 WARN: DEGRADADO_402: lote vixradar-noturno_lote-3_20260911.txt caiu para o fallback por saldo insuficiente (tier=deepseek/deepseek-v4-pro-0813 fallback=deepseek/deepseek-v4-flash-0731) - repor credito OpenRouter'

Write-Host '=== 1. Deteccao: log + metrics, sem dobrar a mesma chamada ==='
@(
    '2026-09-11 18:10:00 INICIO: varredura noturna',
    $linhaWarn,
    ($linhaWarn -replace 'lote-3', 'lote-7'),
    '2026-09-11 19:40:00 FIM: noturno concluido. Total do dia 104/104.'
) | Set-Content (Join-Path $tmp ('vixradar-noturno_' + $tag402 + '.log')) -Encoding UTF8
[ordered]@{ data = $tag402; rotina = 'noturno'; degradados_402 = 2; silent_fail = 0; submit_ok = 104 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('noturno_metrics_' + $tag402 + '.json')) -Encoding UTF8

# Matinal: o metrics carrega a contagem e o log NAO tem a linha (caso real de log truncado).
[ordered]@{ data = $tag402; rotina = 'matinal'; degradados_402 = 3 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('matinal_metrics_' + $tag402 + '.json')) -Encoding UTF8
Set-Content (Join-Path $tmp ('vixradar-matinal_' + $tag402 + '.log')) -Value '2026-09-11 10:31:06 FIM: matinal concluido. submit_ok=23' -Encoding UTF8

# Verificacao: log com 1 linha e SEM metrics (arquivo ausente) -> o log vence e e a fonte.
Set-Content (Join-Path $tmp ('vixradar-verificacao-async_' + $tag402 + '.log')) -Value $linhaWarn -Encoding UTF8

# Sentinela: metrics com o NOME LONGO (vixradar-sentinela_metrics_...) -> o resolvedor cai no
# fallback e ainda acha. Prova que o mapa de prefixo nao fecha a porta para motor novo.
[ordered]@{ data = $tag402; rotina = 'sentinela'; degradados_402 = 1 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('vixradar-sentinela_metrics_' + $tag402 + '.json')) -Encoding UTF8
Set-Content (Join-Path $tmp ('vixradar-sentinela_' + $tag402 + '.log')) -Value '2026-09-11 13:25:04 FIM: sentinela sem gatilho. tokens=0' -Encoding UTF8

# Agenda semanal: existe no dia e nao degradou (ponta negativa).
Set-Content (Join-Path $tmp ('vixradar-agenda-semanal_' + $tag402 + '.log')) -Value '2026-09-09 22:00:00 FIM: agenda concluida.' -Encoding UTF8

$achados = @(Get-VixDegradado402 -RotinasLogDir $tmp -Dias @($dia402))
$porRotina = @{}
foreach ($a in $achados) { $porRotina[$a.rotina] = $a }
Assert ($achados.Count -eq 4) ('4 rotinas com degradacao detectadas (achados=' + $achados.Count + ')')
Assert ($porRotina.ContainsKey('vixradar-noturno')) 'vixradar-noturno detectado'
Assert ($porRotina['vixradar-noturno'].degradados -eq 2) ('noturno: 2 (log=2 metrics=2, sem somar para 4) -> ' + $porRotina['vixradar-noturno'].degradados)
Assert ($porRotina['vixradar-noturno'].linhas_log -eq 2 -and $porRotina['vixradar-noturno'].campo_metrics -eq 2) 'noturno: as duas fontes contadas separadamente'
Assert ($porRotina['vixradar-noturno'].exemplo -match 'DEGRADADO_402') 'noturno: exemplo da linha capturado para o alerta'
Assert ($porRotina['vixradar-noturno'].fonte -match 'noturno_metrics_') 'noturno: fonte do alerta e o metrics, quando ele existe'
Assert ($porRotina.ContainsKey('vixradar-matinal')) 'matinal detectado SO pelo metrics (log sem a linha)'
Assert ($porRotina['vixradar-matinal'].degradados -eq 3 -and $porRotina['vixradar-matinal'].linhas_log -eq 0) ('matinal: 3 pelo metrics, 0 no log -> ' + $porRotina['vixradar-matinal'].degradados)
Assert ($porRotina.ContainsKey('vixradar-verificacao-async')) 'verificacao detectada SO pelo log (metrics ausente)'
Assert ($porRotina['vixradar-verificacao-async'].degradados -eq 1 -and $porRotina['vixradar-verificacao-async'].campo_metrics -eq 0) ('verificacao: 1 pelo log, metrics=0 -> ' + $porRotina['vixradar-verificacao-async'].degradados)
Assert ($porRotina['vixradar-verificacao-async'].fonte -eq $porRotina['vixradar-verificacao-async'].log) 'verificacao: sem metrics, a fonte do alerta cai para o log (nao aponta arquivo inexistente)'
Assert ($porRotina.ContainsKey('vixradar-sentinela')) 'sentinela detectada pelo metrics de NOME LONGO (fallback do resolvedor)'
Assert ($porRotina['vixradar-sentinela'].degradados -eq 1) ('sentinela: 1 -> ' + $porRotina['vixradar-sentinela'].degradados)
Assert (-not $porRotina.ContainsKey('vixradar-agenda-semanal')) 'agenda nao aparece (nao degradou)'

Write-Host '=== 2. Ponta oposta: dia limpo nao gera achado ==='
[ordered]@{ data = $tagLimpo; rotina = 'noturno'; degradados_402 = 0 } |
    ConvertTo-Json | Set-Content (Join-Path $tmp ('noturno_metrics_' + $tagLimpo + '.json')) -Encoding UTF8
Set-Content (Join-Path $tmp ('vixradar-noturno_' + $tagLimpo + '.log')) -Value '2026-09-10 20:40:59 FIM: noturno concluido. submit_ok=100' -Encoding UTF8
$limpo = @(Get-VixDegradado402 -RotinasLogDir $tmp -Dias @($diaLimpo))
Assert ($limpo.Count -eq 0) ('dia limpo: 0 achados (antes teria contado log/metrics vazios: ' + $limpo.Count + ')')
$ambos = @(Get-VixDegradado402 -RotinasLogDir $tmp -Dias @($diaLimpo, $dia402))
Assert ($ambos.Count -eq 4) ('dois dias juntos: so o dia com degradacao (achados=' + $ambos.Count + ')')
$vazio = @(Get-VixDegradado402 -RotinasLogDir (Join-Path $tmp 'nao-existe') -Dias @($dia402))
Assert ($vazio.Count -eq 0) 'diretorio inexistente: 0 achados, sem excecao'

Write-Host '=== 3. Wiring do monitor: aviso, nunca falha ==='
$mont = Get-Content (Join-Path $scriptDir 'monitor-tasks.ps1') -Raw -Encoding UTF8
Assert ($mont -match 'Get-VixDegradado402') 'monitor-tasks usa Get-VixDegradado402'
Assert ($mont -match 'AVISO: DEGRADADO_402') 'monitor-tasks loga AVISO: DEGRADADO_402'
Assert ($mont -match "code\s*=\s*9007") 'monitor-tasks marca codigo 9007 (distinto de 9004/9005)'
Assert ($mont -match '\$degradacoes \+= \$entry') 'entrada entra em $degradacoes'
Assert ($mont -match '\$warnings \+= \$entry') 'entrada entra em $warnings'
$bloco = [regex]::Match($mont, 'OR402-DEGRADA1 \(2026-09-11\): degradacao por saldo \(HTTP 402\) e AVISO OPERACIONAL[\s\S]{0,2200}?\n\}').Value
Assert ($bloco.Length -gt 100) 'bloco de deteccao localizado no monitor-tasks.ps1'
Assert (-not ($bloco -match '\$erros \+=')) 'ponta ruim: o bloco NAO escreve em $erros (nao vira falha nem muda o exit code)'
Assert ($mont -match 'Degradados por 402 \(saldo, lote recuperado - NAO e falha\)') 'resumo do monitor publica a contagem separada'
Assert ($mont -match '\$nDeg -gt 0') 'degradacao participa do gatilho de e-mail'

Write-Host '=== 4. Sintaxe: monitor e lib continuam parseaveis (o vigia roda todo dia as 07:00) ==='
foreach ($f in @('monitor-tasks.ps1', 'lib\vixradar-watchdog.ps1')) {
    $toks = $null; $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir $f), [ref]$toks, [ref]$errs)
    $n = @($errs).Count
    Assert ($n -eq 0) ($f + ': 0 erro de parse (achados=' + $n + $(if ($n -gt 0) { ' -> ' + $errs[0].Message } else { '' }) + ')')
}
Assert ($mont -match '\$exitCode = \[Math\]::Min\(\$erros\.Count, 255\)') 'exit code do monitor continua sendo $erros.Count (degradacao nao muda o resultado da task)'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
