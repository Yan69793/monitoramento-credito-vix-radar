# test-dryrun-metrics.ps1 - prova de duas pontas de:
#   (1) DRYRUN-METRICS-SOBRESCREVE1: Get-VixCustoDia soma TODOS os <rotina>_metrics_<data>_dryrun*.json
#       do dia (legado _dryrun.json + novos _dryrun_HHmmss.json), em vez de ler um so;
#   (2) DRYRUN-CRASH1: Get-VixAlertasAuth ignora DRYRUN_ALERTA_AUTH e pega ALERTA_AUTH;
#   (3) estatico: os runners com -DryRun nao gravam mais 'ALERTA_AUTH: ' literal, so pela tag.
# Tudo em diretorio temporario com data ficticia 2099-01-01. PowerShell 5.1, ASCII puro.

$ErrorActionPreference = 'Continue'
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-watchdog.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }
function New-Metrics([string]$path, [int]$trabalho, [int]$lotes, [int]$analisados, [bool]$dry) {
    [ordered]@{ data = '20990101'; dryrun = $dry; tokens_total_est = $trabalho; tokens_trabalho = $trabalho
        tokens_input = 10; tokens_output = 20; tokens_cache_creation = ($trabalho - 30); tokens_cache_read = 5
        analisados = $analisados; submit_ok = 0; lotes = $lotes; batches = $lotes } | ConvertTo-Json | Set-Content $path -Encoding UTF8
}

$tmp = Join-Path $env:TEMP ('vixradar-dryrun-metrics-test-' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$tag = '20990101'
$cfg = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }

Write-Host '=== 1. Get-VixCustoDia soma os dry-runs do dia ==='
New-Metrics (Join-Path $tmp ('noturno_metrics_' + $tag + '_dryrun.json')) 100 1 3 $true
$c1 = Get-VixCustoDia $tmp $tag $cfg
Assert ($c1.por_rotina['noturno'].trabalho -eq 100 -and $c1.por_rotina['noturno'].regua -eq 'parcelas+dryrun') ('um dry-run legado: trabalho=' + $c1.por_rotina['noturno'].trabalho + ' regua=' + $c1.por_rotina['noturno'].regua)
New-Metrics (Join-Path $tmp ('noturno_metrics_' + $tag + '_dryrun_120000.json')) 200 1 1 $true
New-Metrics (Join-Path $tmp ('noturno_metrics_' + $tag + '_dryrun_130000.json')) 300 2 1 $true
New-Metrics (Join-Path $tmp ('matinal_metrics_' + $tag + '.json')) 1000 1 4 $false
$c = Get-VixCustoDia $tmp $tag $cfg
$n = $c.por_rotina['noturno']; $m = $c.por_rotina['matinal']
Assert ($n.trabalho -eq 600) ('noturno trabalho=' + $n.trabalho + ' (esperado 600 = 100+200+300, antes seria 100)')
Assert ($n.lotes -eq 4) ('noturno lotes=' + $n.lotes + ' (esperado 4)')
Assert ($n.cache_read -eq 15) ('noturno cache_read=' + $n.cache_read + ' (esperado 15)')
Assert ($n.regua -eq 'parcelas+dryrunx3') ('noturno regua=' + $n.regua)
Assert ($m.trabalho -eq 1000 -and $m.regua -eq 'parcelas') ('matinal trabalho=' + $m.trabalho + ' regua=' + $m.regua)
Assert ($c.total_trabalho -eq 1600) ('TOTAL_DIA=' + $c.total_trabalho + ' (esperado 1600)')
Assert ($c.linha -match 'noturno=600\+cache_read=15' -and $c.linha -match 'TOTAL_DIA=1600') ('linha: ' + $c.linha)
Assert ($n.trabalho -ne 100) 'ponta ruim: o comportamento antigo (so o legado) daria 100'

Write-Host '=== 2. Get-VixAlertasAuth: DRYRUN_ nao e incidente ==='
@('2099-01-01 10:00:00 DRYRUN_ALERTA_AUTH: noturno comecou direto na chave paga (teste)',
  '2099-01-01 10:00:01 ALERTA_AUTH: sem credencial nenhuma na noturno (modo=nenhum)',
  '2099-01-01 10:00:02 INICIO: nada') | Set-Content (Join-Path $tmp ('vixradar-noturno_' + $tag + '.log')) -Encoding UTF8
$a = @(Get-VixAlertasAuth -RotinasLogDir $tmp -Dias @([datetime]'2099-01-01'))
Assert ($a.Count -eq 1) ('alertas=' + $a.Count + ' (esperado 1: so a linha real)')
Assert ($a.Count -eq 1 -and $a[0].linha -match 'sem credencial nenhuma') 'a linha capturada e a real, nao a DRYRUN_'

Write-Host '=== 3. estatico: runners com -DryRun so gravam ALERTA_AUTH pela tag ==='
$alvos = @((Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'), (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1'))
foreach ($f in $alvos) {
    $src = Get-Content $f -Raw -Encoding UTF8
    $literais = [regex]::Matches($src, "Write-Log \('ALERTA_AUTH: ").Count
    $porTag = [regex]::Matches($src, 'Write-Log \(\$(AlertaAuthTag|alertaTag) \+').Count
    Assert ($literais -eq 0) ((Split-Path $f -Leaf) + ': 0 Write-Log com ALERTA_AUTH literal (achado ' + $literais + ')')
    Assert ($porTag -ge 1) ((Split-Path $f -Leaf) + ': ' + $porTag + ' Write-Log pela tag')
}
$srcV = Get-Content (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1') -Raw -Encoding UTF8
Assert ($srcV -match "if \(\`$DryRun\) \{ Write-Log 'DRYRUN: alerta NAO enviado") 'verificacao: notificar_rotina suprimido em dry-run'
Assert ($srcV -match '_dryrun_' -and -not ($srcV -match "'_dryrun\.json'")) 'verificacao: metrics de dry-run com hora no nome'
$srcR = Get-Content (Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Assert ($srcR -match "'_dryrun_' \+ \(Get-Date -Format 'HHmmss'\)") 'runner: metrics de dry-run com hora no nome'

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
