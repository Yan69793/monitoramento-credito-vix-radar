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

# ---------------------------------------------------------------------------
# AGENDASEM-TRAVA1 (2026-08-30): mesma lib, cadencia domingo E quarta.
# Datas reais: 23/08 domingo, 24/08 segunda, 25/08 terca, 26/08 quarta, 27/08 quinta,
# 28/08 sexta. As duas pontas usam o formato real dos logs de producao daqueles dias.
# ---------------------------------------------------------------------------
$diasAgenda = @('Sunday','Wednesday')

# Cadencia 1: terca 07:00 -> alvo domingo 23/08, NAO segunda 24/08.
# Sem isto o vigia cobraria log de um dia em que a rotina nunca roda.
$alvoTer = Get-AlvoEntregaRotina -Agora ([datetime]'2026-08-25 07:00:00') -Hora 22 -DiasUteis $false -DiasPermitidos $diasAgenda
if ($alvoTer.ToString('yyyy-MM-dd') -ne '2026-08-23') { $falhas += 'CADENCIA TERCA: esperava alvo 2026-08-23 (domingo), veio ' + $alvoTer.ToString('yyyy-MM-dd') }
else { Write-Host ('CADENCIA TERCA OK: alvo=' + $alvoTer.ToString('yyyy-MM-dd') + ' (' + $alvoTer.DayOfWeek + ')') }

# Cadencia 2: sexta 07:00 -> alvo quarta 26/08, NAO quinta 27/08.
$alvoSex = Get-AlvoEntregaRotina -Agora ([datetime]'2026-08-28 07:00:00') -Hora 22 -DiasUteis $false -DiasPermitidos $diasAgenda
if ($alvoSex.ToString('yyyy-MM-dd') -ne '2026-08-26') { $falhas += 'CADENCIA SEXTA: esperava alvo 2026-08-26 (quarta), veio ' + $alvoSex.ToString('yyyy-MM-dd') }
else { Write-Host ('CADENCIA SEXTA OK: alvo=' + $alvoSex.ToString('yyyy-MM-dd') + ' (' + $alvoSex.DayOfWeek + ')') }

# Ponta ruim (caso real de 26/08): rodou, morreu no lote 3 por reboot, log sem FIM:.
$logQua = Join-Path $tmpRoot ('vixradar-agenda-semanal_' + $alvoSex.ToString('yyyyMMdd') + '.log')
$conteudoQua = @(
    '2026-08-26 22:00:01 INICIO: agenda-semanal meta=400000 hard=600000',
    '2026-08-26 22:07:55 OK|Engie Brasil Energia|trimestres_count=2',
    '2026-08-26 22:14:44 Lote agendasem-3: 4 empresa(s) - Santos Brasil, EcoRodovias, JSL, Embraer'
) -join "`n"
[System.IO.File]::WriteAllText($logQua, $conteudoQua, (New-Object System.Text.UTF8Encoding($false)))
$stA1 = Test-EntregaPorLog -Alvo $alvoSex -LogDir $tmpRoot -Prefixo 'vixradar-agenda-semanal' -Rotulo 'AgendaSemanal'
if (-not $stA1.motivo) { $falhas += 'AGENDA PONTA RUIM: esperava reprova (log sem FIM:) mas aceitou' }
elseif ($stA1.motivo -notmatch 'AgendaSemanal') { $falhas += 'AGENDA PONTA RUIM: reprova sem nomear a rotina: ' + $stA1.motivo }
else { Write-Host ('AGENDA PONTA RUIM OK: ' + $stA1.motivo) }

# Ponta boa (caso real de 23/08): completou com FIM: -> aceita.
$logDom = Join-Path $tmpRoot ('vixradar-agenda-semanal_' + $alvoTer.ToString('yyyyMMdd') + '.log')
$conteudoDom = @(
    '2026-08-23 22:00:01 INICIO: agenda-semanal meta=400000 hard=600000',
    '2026-08-23 22:26:10 FIM: agenda-semanal | stale_inicial=20 atualizados=16 pulados=4 mismatch=0 erros=0 lotes=5 tokens=581945'
) -join "`n"
[System.IO.File]::WriteAllText($logDom, $conteudoDom, (New-Object System.Text.UTF8Encoding($false)))
$stA2 = Test-EntregaPorLog -Alvo $alvoTer -LogDir $tmpRoot -Prefixo 'vixradar-agenda-semanal' -Rotulo 'AgendaSemanal'
if ($stA2.motivo) { $falhas += 'AGENDA PONTA BOA: esperava aceitar (log+FIM) mas reprovou: ' + $stA2.motivo }
else { Write-Host ('AGENDA PONTA BOA OK: execucoes_com_fim=' + $stA2.submitOk) }

# Ponta SHADOW (ROTINACEGA1): SHADOW_FIM: contem 'FIM:' como substring e NAO conta como
# conclusao. A lookbehind da lib trata isso e nenhuma prova exercitava o caso.
[System.IO.File]::WriteAllText($logDom, "2026-08-23 22:00:01 INICIO: agenda-semanal meta=400000`n2026-08-23 22:26:10 AVISO SHADOW_FIM: simulacao, nao e conclusao real", (New-Object System.Text.UTF8Encoding($false)))
$stA3 = Test-EntregaPorLog -Alvo $alvoTer -LogDir $tmpRoot -Prefixo 'vixradar-agenda-semanal' -Rotulo 'AgendaSemanal'
if (-not $stA3.motivo) { $falhas += 'AGENDA SHADOW: SHADOW_FIM: foi contado como conclusao real' }
else { Write-Host ('AGENDA SHADOW OK: ' + $stA3.motivo) }

Remove-Item -Recurse -Force $tmpRoot -ErrorAction SilentlyContinue
if ($falhas.Count -gt 0) {
    Write-Host 'FALHAS:'
    foreach ($f in $falhas) { Write-Host ('  - ' + $f) }
    exit 1
}
Write-Host 'VIGIA SENTINELA + AGENDASEMANAL: prova de duas pontas OK'
exit 0
