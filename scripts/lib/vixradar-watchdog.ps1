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

# AGENDASEM-TRAVA1 (2026-08-30): o eixo "dia util" nao serve para toda rotina. A
# AgendaSemanal roda domingo E quarta (DaysOfWeek=9 no Scheduler, decisao deliberada de
# 14/08 pela regra 9 do CALVAL-V2), entao para ela domingo e dia de ENTREGA, nao dia de
# recuar. $DiasPermitidos generaliza o laco: recua ate o dia mais recente que pertence ao
# conjunto da rotina. $DiasUteis continua valendo como atalho de Seg-Sex (Sentinela e
# matinal) e quem nao passa nenhum dos dois nao filtra dia nenhum (noturno, diario).
function Get-AlvoEntregaRotina([datetime]$Agora, [int]$Hora, [bool]$DiasUteis, [string[]]$DiasPermitidos) {
    $alvo = $Agora.Date
    if ($Agora.Hour -lt ($Hora + 2)) { $alvo = $alvo.AddDays(-1) }
    $permitidos = $DiasPermitidos
    if ($null -eq $permitidos -or $permitidos.Count -eq 0) {
        $permitidos = $null
        if ($DiasUteis) { $permitidos = @('Monday','Tuesday','Wednesday','Thursday','Friday') }
    }
    if ($null -ne $permitidos -and $permitidos.Count -gt 0) {
        # Guarda de 7 voltas: conjunto invalido nao pode prender o monitor em laco.
        $voltas = 0
        while ($permitidos -notcontains [string]$alvo.DayOfWeek) {
            $alvo = $alvo.AddDays(-1)
            $voltas++
            if ($voltas -ge 7) { break }
        }
    }
    return $alvo
}

# AGENDASEM-TRAVA1 (2026-08-30): a checagem "log do dia alvo tem FIM:" nao tem nada de
# especifico da Sentinela, so o prefixo do arquivo e o nome na mensagem. Generalizada para
# servir tambem a AgendaSemanal, cuja execucao de 26/08 morreu por reboot da maquina no
# meio do lote 3 (Kernel-Power 109 e 577 as 22:16:27 e 22:16:29) e deixou log sem FIM:.
# O exit code do Scheduler dizia 0x40010004 e so; a evidencia boa e o log, nao o codigo.
# Test-EntregaSentinela fica como atalho para nao quebrar call site nem prova existente.
function Test-EntregaPorLog([datetime]$Alvo, [string]$LogDir, [string]$Prefixo, [string]$Rotulo) {
    if ([string]::IsNullOrWhiteSpace($Rotulo)) { $Rotulo = $Prefixo }
    $alvoTxt = $Alvo.ToString('yyyy-MM-dd')
    $logPath = Join-Path $LogDir ($Prefixo + '_' + $Alvo.ToString('yyyyMMdd') + '.log')
    if (-not (Test-Path $logPath)) {
        return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = -1; motivo = ("$alvoTxt sem log de execucao - a $Rotulo nao chegou a iniciar na janela agendada") }
    }
    $conteudo = ''
    try { $conteudo = Get-Content $logPath -Raw -Encoding UTF8 -ErrorAction Stop } catch { $conteudo = '' }
    # Mesma exclusao de SHADOW_FIM: do ROTINACEGA1 (monitor-tasks.ps1) - classe do Obs15
    # do task-observer (vigia que casa substring dentro de linha AVISO).
    $fims = [regex]::Matches($conteudo, '(?m)(?<!SHADOW_)FIM:')
    if ($fims.Count -eq 0) {
        return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = -1; motivo = ("$alvoTxt log existe mas sem linha FIM: - a $Rotulo iniciou mas nenhuma execucao chegou ao fim") }
    }
    return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = $fims.Count; motivo = $null }
}

function Test-EntregaSentinela([datetime]$Alvo, [string]$LogDir) {
    return Test-EntregaPorLog -Alvo $Alvo -LogDir $LogDir -Prefixo 'vixradar-sentinela' -Rotulo 'Sentinela'
}
