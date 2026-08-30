# test-sentinela-watchdog.ps1 - prova de duas pontas do vigia da Sentinela.
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test-sentinela-watchdog.ps1
# Cria dir temporario, nao toca producao. ASCII puro (parse no 5.1).
# SENTINELA-DIAPERDIDO1: apontado nas auditorias 93/95 ("0 execucoes na sexta 29/08"),
# medido em 30/08 virou falso positivo (29/08 e sabado, task roda so Seg-Sex). O vigia
# segue como guarda defensiva contra queda silenciosa: a prova roda a MESMA funcao que o
# monitor-tasks.ps1 usa em producao (dot-source da lib vixradar-watchdog.ps1).
# O vigia reprova dia util sem log/FIM: da rotina. A prova roda a MESMA funcao que o
# monitor-tasks.ps1 usa em producao (dot-source da lib vixradar-watchdog.ps1).
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'lib\vixradar-watchdog.ps1')

$tmpRoot = Join-Path $env:TEMP ('vixradar-watchdog-test_' + $PID)
if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot }
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$falhas = @()

# Ponta ruim 1: dia util sem log -> reprova nomeando a rotina.
# "hoje" = quarta 19/08 07:00 -> alvo = terca 18/08 (dia util). Sem log no tmp.
$agoraQuarta = [datetime]'2026-08-19 07:00:00'
$st = Test-EntregaSentinela -Alvo (Get-AlvoEntregaRotina $agoraQuarta 18 $true) -LogDir $tmpRoot
if (-not $st.motivo) { $falhas += 'PONTA RUIM: esperava reprova (sem log) mas aceitou' }
elseif ($st.motivo -notmatch 'Sentinela') { $falhas += 'PONTA RUIM: reprova sem nomear a rotina: ' + $st.motivo }
else { Write-Host ('PONTA RUIM OK: ' + $st.motivo) }

# Ponta boa: dia util com log + FIM -> aceita.
$alvo = Get-AlvoEntregaRotina $agoraQuarta 18 $true
$logPath = Join-Path $tmpRoot ('vixradar-sentinela_' + $alvo.ToString('yyyyMMdd') + '.log')
$conteudo = @(
    '2026-08-18 09:25:00 INICIO: sentinela teto=8 hard=120000',
    '2026-08-18 09:25:01 PORTAO: acervo do Worker inalterado e sem backlog. Nada a fazer.',
    '2026-08-18 09:25:01 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=sem_novidade'
) -join "`n"
[System.IO.File]::WriteAllText($logPath, $conteudo, (New-Object System.Text.UTF8Encoding($false)))
$st2 = Test-EntregaSentinela -Alvo $alvo -LogDir $tmpRoot
if ($st2.motivo) { $falhas += 'PONTA BOA: esperava aceitar (log+FIM) mas reprovou: ' + $st2.motivo }
else { Write-Host ('PONTA BOA OK: execucoes_com_fim=' + $st2.submitOk) }

# Ponta media: log existe mas sem FIM -> reprova (iniciou, nenhuma execucao chegou ao fim).
[System.IO.File]::WriteAllText($logPath, '2026-08-18 09:25:00 INICIO: sentinela teto=8 hard=120000', (New-Object System.Text.UTF8Encoding($false)))
$st3 = Test-EntregaSentinela -Alvo $alvo -LogDir $tmpRoot
if (-not $st3.motivo) { $falhas += 'PONTA SEM-FIM: esperava reprova (log sem FIM) mas aceitou' }
else { Write-Host ('PONTA SEM-FIM OK: ' + $st3.motivo) }

# Fim de semana: segunda 24/08 07:00 -> alvo sexta 21/08 -> sem log -> reprova.
$agoraSeg = [datetime]'2026-08-24 07:00:00'
$st4 = Test-EntregaSentinela -Alvo (Get-AlvoEntregaRotina $agoraSeg 18 $true) -LogDir $tmpRoot
if (-not $st4.motivo) { $falhas += 'SEXTA SEM LOG: esperava reprova na segunda' }
else { Write-Host ('FIM-DE-SEMANA OK: ' + $st4.motivo) }

Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
if ($falhas.Count -gt 0) {
    Write-Host 'FALHAS:'
    foreach ($f in $falhas) { Write-Host ('  - ' + $f) }
    exit 1
}
Write-Host 'VIGIA SENTINELA: prova de duas pontas OK'
exit 0
