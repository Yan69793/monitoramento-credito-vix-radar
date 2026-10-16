# VERIF-METRICS-ACUM1 - regressao offline, PS 5.1 e 7.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
$script:pass=0; $script:fail=0
function Assert([bool]$cond,[string]$name) {
    if($cond){ $script:pass++; Write-Host ('OK: '+$name) }
    else { $script:fail++; Write-Host ('FALHA: '+$name) }
}
$dir=Join-Path $env:TEMP ('vix-verif-acum-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $dir)
$tag='20990101'
$metric=Join-Path $dir ('verificacao_async_metrics_'+$tag+'.json')
$log=Join-Path $dir ('vixradar-verificacao-async_'+$tag+'.log')
$cfg=@{ TETO_DIA=1000000; RESERVA_VERIFICACAO=150000; RESERVA_NOTURNO=700000; MARGEM_MINIMA=100000 }
try {
    '{"data":"20990101","total_fila":0,"lotes":0,"dryrun":false}' | Set-Content -LiteralPath $metric -Encoding UTF8
    @(
      '2099-01-01 02:46:16 FIM: fila=1 reservados=1 lotes=1 tokens=19481 cache_read=0 tokens_desconhecidos=0',
      '2099-01-01 09:30:00 FIM_DRYRUN: fila=2 lotes=1 tokens=99999',
      '2099-01-01 11:03:11 FIM: fila vazia, nada a fazer'
    ) | Set-Content -LiteralPath $log -Encoding UTF8
    $before=Get-VixCustoDia $dir $tag $cfg
    Assert ($before.por_rotina['verificacao'].trabalho -eq 19481) 'log recupera 19481 do JSON zerado'
    Assert ($before.total_consumido -eq 19481) 'dry-run log nao entra duas vezes'
    $zero=[ordered]@{data=$tag;tokens_trabalho=0;lotes=0;total_fila=0;dryrun=$false}
    Save-VixVerificacaoMetrics -Path $metric -Novas $zero -LogFile $log -ExecucaoId 'empty-1'
    $m=Get-Content $metric -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($m.tokens_trabalho -eq 19481 -and $m.tokens_recuperados_log -eq 19481) 'fila vazia preserva consumo e origem do resgate'
    Save-VixVerificacaoMetrics -Path $metric -Novas $zero -LogFile $log -ExecucaoId 'empty-1'
    $m=Get-Content $metric -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($m.tokens_trabalho -eq 19481 -and @($m.execucoes_aplicadas).Count -eq 1) 'execucao duplicada idempotente'
    $run2=[ordered]@{data=$tag;tokens_trabalho=250;tokens_input=180;tokens_output=70;tokens_cache_creation=0;tokens_cache_read=25;lotes=1;total_fila=1;aprovados=1}
    Save-VixVerificacaoMetrics -Path $metric -Novas $run2 -LogFile $log -ExecucaoId 'work-2'
    Add-Content -LiteralPath $log -Value '2099-01-01 19:20:00 FIM: fila=1 tokens=250 tokens_desconhecidos=0' -Encoding UTF8
    $after=Get-VixCustoDia $dir $tag $cfg
    Assert ($after.total_consumido -eq 19731) '19481 + 250 sem dupla contagem entre JSON e log'
    $m=Get-Content $metric -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($m.tokens_trabalho -eq 19731 -and $m.tokens_input -eq 180 -and $m.tokens_cache_read -eq 25) 'acumula parcelas medidas sem inventar parcelas do log antigo'
    $run3=[ordered]@{data=$tag;tokens_trabalho=350;tokens_input=320;tokens_output=30;lotes=1;total_fila=1;rejeitados=1}
    Save-VixVerificacaoMetrics -Path $metric -Novas $run3 -LogFile $log -ExecucaoId 'work-3'
    Add-Content -LiteralPath $log -Value '2099-01-01 20:20:00 FIM: fila=1 tokens=350 tokens_desconhecidos=0' -Encoding UTF8
    $after3=Get-VixCustoDia $dir $tag $cfg
    Assert ($after3.total_consumido -eq 20081) 'tres execucoes reais preservadas'
    $m=Get-Content $metric -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($m.aprovados -eq 1 -and $m.rejeitados -eq 1 -and @($m.execucoes_aplicadas).Count -eq 3) 'contadores e IDs das tres execucoes'
    $dry=Join-Path $dir ('verificacao_async_metrics_'+$tag+'_dryrun_100000.json')
    Save-VixVerificacaoMetrics -Path $dry -Novas ([ordered]@{data=$tag;tokens_trabalho=75;tokens_input=75;lotes=1}) -LogFile $log -ExecucaoId 'dry-1' -DryRun
    $cDry=Get-VixCustoDia $dir $tag $cfg
    Assert ($cDry.total_consumido -eq 20156) 'dryrun separado conta uma vez no total'
    Assert ((Get-Content $metric -Raw|ConvertFrom-Json).tokens_trabalho -eq 20081) 'dryrun nao sobrescreve real'
    $invalid=Join-Path $dir 'invalid.json'
    'BROKEN JSON' | Set-Content -LiteralPath $invalid -Encoding UTF8
    $blocked=$false
    try{Save-VixVerificacaoMetrics -Path $invalid -Novas $run2 -LogFile $log -ExecucaoId 'bad'}catch{$blocked=$true}
    Assert ($blocked -and (Get-Content -LiteralPath $invalid -Raw) -match 'BROKEN JSON') 'JSON antigo invalido: fail closed, sem apagar'
    $emptyPath=Join-Path $dir 'empty.json'
    [IO.File]::WriteAllText($emptyPath,'')
    $emptyBlocked=$false
    try{Save-VixVerificacaoMetrics -Path $emptyPath -Novas $run2 -LogFile $log -ExecucaoId 'empty-file'}catch{$emptyBlocked=$true}
    Assert ($emptyBlocked -and (Get-Item -LiteralPath $emptyPath).Length -eq 0) 'arquivo vazio bloqueado sem sobrescrita'
    Add-Content -LiteralPath $log -Value '2099-01-01 20:30:00 FIM: fila=1 tokens=10 tokens_desconhecidos=1' -Encoding UTF8
    $unknown=Get-VixCustoDia $dir $tag $cfg
    Assert (-not $unknown.mensuravel -and $unknown.total_consumido -eq 20166) 'uso desconhecido falha fechado e consumo conhecido continua contado'
    $runner=Get-Content (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1') -Raw -Encoding UTF8
    Assert (([regex]::Matches($runner,'Save-VixVerificacaoMetrics').Count) -eq 2) 'dois pontos de persistencia (fila vazia e trabalho)'
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULTADO: '+$script:pass+' OK, '+$script:fail+' falha(s)')
if($script:fail -ne 0){exit 1}
exit 0
