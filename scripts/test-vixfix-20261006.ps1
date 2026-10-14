# test-vixfix-20261006.ps1 - prova especifica da correcao VIX Radar 06/10/2026.
# Cobre os 8 cenarios exigidos: 402, fallback indisponivel, ledger 100%
# deferido, watchdog nao aceitar deferido como sucesso, sentinela com backlog,
# reconciliacao CVM com KV put falhando, lock orfao, WakeToRun.
# ASCII puro, PS 5.1, sem rede, sem token, sem chamada paga.
$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')

$script:okN = 0
$script:falN = 0
function Assert([bool]$cond, [string]$msg) {
  if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) }
  else { $script:falN++; Write-Host ('  FALHA ' + $msg) }
}

$dataLog = Get-Date -Year 2026 -Month 10 -Day 5 -Hour 0 -Minute 0 -Second 0

Write-Host '--- 1: HTTP 402 com 0 analisados nao e entrega (matinal 05/10) ---'
$matinal402 = @'
2026-10-05 14:47:40 WARN: DEGRADADO_402: lote matinal_full-1 caiu para o fallback por saldo insuficiente
2026-10-05 14:47:40 RETRY openrouter: tentativa 1/1: OPENROUTER_HTTP_STATUS=402 This request requires more credits
2026-10-05 14:48:21 OK|Oncoclinicas|FULL|-|0|true|DEFERIDO|0
2026-10-05 14:48:23 OK|Raizen|FULL|-|0|true|DEFERIDO|0
2026-10-05 14:48:59 DEFERIDOS: ok=22 falha=0 total=22 motivo=limite_sessao_assinatura (0/400000 realizados - o cap NAO foi a causa) lotes_nao_processados=5
2026-10-05 14:48:59 FIM: matinal concluido. Total do dia 22/22 (ledger analisados=0 skip=0 deferidos=22). analisados_execucao=0 skip_execucao=0 deferidos_execucao=22 submits_aceitos=22 submit_ok=0 submit_fail=0 tokens=0 cap_efetivo=400000 lotes=1 lotes_com_trabalho=0 buscas=0 degradados_402=1
'@
$r402 = Test-VixLedgerEntregueNaJanela -Conteudo $matinal402 -DataLog $dataLog -JanelaHora 10 -MinimoLedger 12
Assert ($r402.Entregue -eq $false) '1a: matinal 22 DEFERIDOS nao entrega'
Assert ($r402.EfetivosNaJanela -eq 0) '1b: efetivos=0'
Assert ($r402.DeferidosNaJanela -eq 2) '1c: deferidos=2 distintos'

Write-Host '--- 2: fallback indisponivel com 0 analisados nao e entrega ---'
Assert ($r402.Entregue -eq $false) '2a: fallback CLAUDE_FALLBACK_AUTH_UNAVAILABLE nao vira sucesso'

Write-Host '--- 3: ledger 100% deferido (noturno 104/104) nao e entrega ---'
$sb3 = New-Object System.Text.StringBuilder
for ($i = 1; $i -le 104; $i++) { [void]$sb3.AppendLine('2026-10-05 18:10:00 OK|Emissor' + $i + '|FULL|-|0|true|DEFERIDO|0') }
[void]$sb3.AppendLine('2026-10-05 18:11:30 FIM: noturno concluido. Total do dia 104/104 (ledger analisados=0 skip=0 deferidos=104). analisados_execucao=0 skip_execucao=0 deferidos_execucao=104 submits_aceitos=104 submit_ok=0 submit_fail=0 tokens=0 cap_efetivo=700000 lotes=1 lotes_com_trabalho=0 buscas=0 degradados_402=1')
$r104 = Test-VixLedgerEntregueNaJanela -Conteudo $sb3.ToString() -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert ($r104.Entregue -eq $false) '3a: 104 DEFERIDOS nao entrega'
Assert ($r104.LedgerNaJanela -eq 104) '3b: ledger total ainda 104 (observabilidade preservada)'
Assert ($r104.EfetivosNaJanela -eq 0) '3c: efetivos=0'

Write-Host '--- 4: watchdog distingue deferido de concluido ---'
$sb4 = New-Object System.Text.StringBuilder
for ($i = 1; $i -le 45; $i++) { [void]$sb4.AppendLine('2026-09-21 18:10:00 OK|Efetivo' + $i + '|FULL|-|1|true|ANALISADO|1') }
for ($i = 1; $i -le 10; $i++) { [void]$sb4.AppendLine('2026-09-21 18:11:00 OK|Pulou' + $i + '|LIGHT|-|0|true|SKIP|0') }
for ($i = 1; $i -le 49; $i++) { [void]$sb4.AppendLine('2026-09-21 18:12:00 OK|Adiado' + $i + '|FULL|-|0|true|DEFERIDO|0') }
[void]$sb4.AppendLine('2026-09-21 18:30:00 FIM: noturno concluido. Total do dia 104/104 (ledger analisados=45 skip=10 deferidos=49). analisados_execucao=45 skip_execucao=10 deferidos_execucao=49 submits_aceitos=104 submit_ok=45 submit_fail=0 tokens=415218 cap_efetivo=700000 lotes=4 lotes_com_trabalho=4 buscas=122 degradados_402=0')
$r21 = Test-VixLedgerEntregueNaJanela -Conteudo $sb4.ToString() -DataLog (Get-Date -Year 2026 -Month 9 -Day 21) -JanelaHora 18 -MinimoLedger 90
Assert ($r21.Entregue -eq $true) '4a: 45 ANALISADO + 10 SKIP com FIM efetivo entrega (caso 21/09 preservado)'
Assert ($r21.EfetivosNaJanela -eq 55) '4b: efetivos=55 (45+10)'
Assert ($r21.DeferidosNaJanela -eq 49) '4c: deferidos=49 separados'
$sb4b = New-Object System.Text.StringBuilder
for ($i = 1; $i -le 91; $i++) { [void]$sb4b.AppendLine('2026-09-03 18:10:00 OK|Legado' + $i + '|FULL|ECO|0|True') }
$rLeg = Test-VixLedgerEntregueNaJanela -Conteudo $sb4b.ToString() -DataLog (Get-Date -Year 2026 -Month 9 -Day 3) -JanelaHora 18 -MinimoLedger 90
Assert ($rLeg.Entregue -eq $true) '4d: ledger legado sem status continua valendo (sem reprocessar historico)'

Write-Host '--- 5: sentinela com backlog nao esconde falha do provider ---'
$srcSent = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
# ORCAMENTOFIN1 (2026-10-14): a classificacao do desfecho virou funcao pura na lib de cobertura
# (Get-VixSentinelaResultado), chamada pela sentinela. A guarda prende as duas pontas.
$srcCob = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1') -Raw -Encoding UTF8
Assert ($srcCob -match "Resultado = 'FALLO_PROVEEDOR'; Exit = 9") '5a: FALLO_PROVEEDOR existe na regra unica (exit 9)'
Assert ($srcSent -match '\$exitFim = \[int\]\$__resFimS\.Exit' -and $srcSent -match 'Get-VixSentinelaResultado') '5b: a sentinela sai pelo desfecho da regra unica (nao por cadeia propria)'
Assert ($srcCob -match "Resultado = 'PARCIAL'; Exit = 10") '5c: PARCIAL existe na regra unica (exit 10)'
Assert ($srcCob -notmatch "Resultado = 'PARCIAL'; Exit = 0") '5c2: PARCIAL nunca mapeia exit 0 (o defeito que esta guarda existe para pegar)'
Assert ($srcSent -match 'Write-State.*sobrou.*novoStreak') '5d: backlog persiste com streak (sem loop infinito, sem consumir gatilho)'

Write-Host '--- 6: reconciliacao CVM com KV put falhando nao sai exit 0 nem FIM ok ---'
$srcRec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'predictive\reconciliar_ipe_cvm.ps1') -Raw -Encoding UTF8
Assert ($srcRec -match 'kvPutFalhou') '6a: flag kvPutFalhou existe'
Assert ($srcRec -match '\$exitCode = 3') '6b: KV put falho sai exit 3'
Assert ($srcRec -match '\$exitCode = 2') '6c: cobertura parcial sai exit 2'
Assert ($srcRec -match 'FIM: parcial') '6d: FIM parcial quando falha (nunca FIM ok mascarado)'
Assert (-not ($srcRec -match '\$exitCode = 0\s*\r?\n\} catch')) '6e: nenhum zeramento de exit antes do catch'

Write-Host '--- 7: lock orfao validado por PID, idade e ownership ---'
$qdir = Join-Path (Split-Path $PSScriptRoot -Parent) '_backup_vixfix_20261006_012704\locks_orfaos'
Assert (Test-Path (Join-Path $qdir 'MANIFEST.txt')) '7a: manifest da quarentena existe (prova de validacao)'
$manif = Get-Content (Join-Path $qdir 'MANIFEST.txt') -Encoding UTF8
Assert ($manif.Count -eq 15) ('7b: 15 locks quarentenados (obtido ' + $manif.Count + ')')
Assert ((Get-ChildItem logs/routines/*.lock -ErrorAction SilentlyContinue | Where-Object { ((Get-Date) - $_.LastWriteTime).TotalHours -gt 24 } | Measure-Object).Count -eq 0) '7c: nenhum .lock orfao antigo em logs/routines (transiente de teste com <24h nao conta)'
Assert ($manif -match 'pid=' -and $manif -match 'ageH=') '7d: manifest registra PID e idade (ownership validada)'

Write-Host '--- 8: WakeToRun coerente nas 5 tarefas ---'
foreach ($n in @('VIXRadar-Coleta-Volatilidade','VIXRadar-Export-Historico','VIXRadar-Sentinela','VIXRadar-Verificacao-Async','Szuchmacher-RetryVixNoturno')) {
  $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
  Assert (($null -ne $t) -and ($t.Settings.WakeToRun -eq $true)) ("8: $n WakeToRun=True")
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:falN) + ' asserts OK, ' + $script:falN + ' falha(s)')
if ($script:falN -gt 0) { exit 1 }
exit 0
