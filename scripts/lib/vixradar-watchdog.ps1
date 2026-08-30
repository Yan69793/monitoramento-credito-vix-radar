# vixradar-watchdog.ps1 - evidencia de entrega das rotinas por log (lib dot-source).
# ASCII puro (parse no powershell.exe 5.1). Usada por monitor-tasks.ps1 e por
# scripts/test-sentinela-watchdog.ps1 (prova de duas pontas).
#
# Vigia defensivo da Sentinela. As auditorias 93/95 apontaram "SENTINELA-DIAPERDIDO1:
# nenhuma execucao na sexta 29/08 e task verde". Medido em 30/08, o incidente original
# foi falso positivo: 29/08 e SABADO e a task roda so Seg-Sex (DaysOfWeek=62),
# LastRun=28/08 (sexta) 17:55 com log, NumberOfMissedRuns=0. O vigia segue como guarda
# contra queda silenciosa futura: dia util sem log do dia reprova, e log sem linha FIM:
# tambem (iniciou mas nao terminou). A Sentinela processa 0 a 8 emissores e quase sempre
# sai em 0 token, entao a regua de contagem da noturna/matinal (minSubmit) nao serve;
# aqui o sinal de entrega e "rodou ao menos uma vez e chegou ao fim". O monitor roda 07h,
# entao o alvo e o ultimo ciclo que ja deveria ter terminado (ontem, ou a sexta na segunda).

function Get-AlvoEntregaRotina([datetime]$Agora, [int]$Hora, [bool]$DiasUteis) {
    $alvo = $Agora.Date
    if ($Agora.Hour -lt ($Hora + 2)) { $alvo = $alvo.AddDays(-1) }
    if ($DiasUteis) {
        while ($alvo.DayOfWeek -eq 'Saturday' -or $alvo.DayOfWeek -eq 'Sunday') { $alvo = $alvo.AddDays(-1) }
    }
    return $alvo
}

function Test-EntregaSentinela([datetime]$Alvo, [string]$LogDir) {
    $alvoTxt = $Alvo.ToString('yyyy-MM-dd')
    $logPath = Join-Path $LogDir ('vixradar-sentinela_' + $Alvo.ToString('yyyyMMdd') + '.log')
    if (-not (Test-Path $logPath)) {
        return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = -1; motivo = ("$alvoTxt sem log de execucao - a Sentinela nao chegou a iniciar no dia util") }
    }
    $conteudo = ''
    try { $conteudo = Get-Content $logPath -Raw -Encoding UTF8 -ErrorAction Stop } catch { $conteudo = '' }
    # Mesma exclusao de SHADOW_FIM: do ROTINACEGA1 (monitor-tasks.ps1) - classe do Obs15
    # do task-observer (vigia que casa substring dentro de linha AVISO).
    $fims = [regex]::Matches($conteudo, '(?m)(?<!SHADOW_)FIM:')
    if ($fims.Count -eq 0) {
        return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = -1; motivo = ("$alvoTxt log existe mas sem linha FIM: - a Sentinela iniciou mas nenhuma execucao chegou ao fim") }
    }
    return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = $fims.Count; motivo = $null }
}
