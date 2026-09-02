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
# MONITOR-PROJETOMISTO1 (2026-09-02): $MinFim generaliza para rotina com mais de uma janela
# no dia (verificacao-async: drenos locais 11h03 e 19h15). Uma execucao so com FIM: em dia
# util e janela pulada, nao entrega. FIM_DRYRUN: nao conta (nao tem 'FIM:' como substring).
function Test-EntregaPorLog([datetime]$Alvo, [string]$LogDir, [string]$Prefixo, [string]$Rotulo, [int]$MinFim = 1) {
    if ([string]::IsNullOrWhiteSpace($Rotulo)) { $Rotulo = $Prefixo }
    if ($MinFim -lt 1) { $MinFim = 1 }
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
    if ($fims.Count -lt $MinFim) {
        return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = $fims.Count; motivo = ("$alvoTxt log tem $($fims.Count) execucao(oes) com FIM:, esperado >= $MinFim - a $Rotulo pulou uma janela") }
    }
    return [pscustomobject]@{ alvoTxt = $alvoTxt; logPath = $logPath; submitOk = $fims.Count; motivo = $null }
}

function Test-EntregaSentinela([datetime]$Alvo, [string]$LogDir) {
    return Test-EntregaPorLog -Alvo $Alvo -LogDir $LogDir -Prefixo 'vixradar-sentinela' -Rotulo 'Sentinela'
}

# MONITOR-PROJETOMISTO1 (2026-09-02): o e-mail "VIX Radar - N task(s) com falha" carregava
# tasks de outros projetos (01/09: AgendaAgent e FechamentoDiario, nenhum do VIX). Escopo
# decide os prefixos; o retry do VIX tem prefixo Szuchmacher- e por isso e listado a parte.
function Get-PrefixosEscopo([string]$Escopo) {
    switch ($Escopo) {
        'VIX'   { return @{ prefixos = @('VIXRadar-', 'Monitor-', 'Szuchmacher-RetryVix'); excluir = @() } }
        'Site'  { return @{ prefixos = @('Szuchmacher-', 'MorningCall-', 'RadarQuant-', 'PME-', 'YanOS_'); excluir = @('Szuchmacher-RetryVix') } }
        default { return @{ prefixos = @('Szuchmacher-', 'VIXRadar-', 'Monitor-', 'PME-', 'YanOS_', 'MorningCall-', 'RadarQuant-'); excluir = @() } }
    }
}

# Dedup do e-mail: erro com o MESMO (task, code, lastRun) ja reportado num dia anterior e
# "persistente" (LastTaskResult congelado de task que nao rodou de novo). So erro novo, erro
# que mudou de codigo ou de ultima execucao, e escalada (>48h) justificam e-mail. Codigos
# 9004 (ALERTA_AUTH) e 9005 (circuito de custo) nunca deduplicam: sao urgentes todo dia.
function Select-ErrosParaEmail([object[]]$Erros, [hashtable]$EstadoAnterior, [string]$HojeIso) {
    $novos = @(); $escalados = @(); $persistentes = @()
    foreach ($e in @($Erros)) {
        if ($null -eq $e) { continue }
        $key = [string]$e.task
        $prev = $null
        if ($EstadoAnterior -and $EstadoAnterior.ContainsKey($key)) { $prev = $EstadoAnterior[$key] }
        $semDedup = ([long]$e.code -eq 9004 -or [long]$e.code -eq 9005)
        $mesmo = $false
        if ($prev -and $prev.reportedAt -and ([string]$prev.lastCode -eq [string]$e.code) -and ([string]$prev.lastRun -eq [string]$e.lastRun)) { $mesmo = $true }
        if ($semDedup -or -not $mesmo) { $novos += $e; continue }
        $jaEscalado = ($prev -and $prev.escalated)
        if ($e.escalated -and -not $jaEscalado) { $escalados += $e; continue }
        $persistentes += $e
    }
    return @{ novos = $novos; escalados = $escalados; persistentes = $persistentes }
}

# ALERTA_AUTH nos logs das rotinas (motor MOTOR1): escalada para chave paga ou credencial
# nenhuma. Varre os logs dos dias pedidos e devolve uma entrada por linha encontrada.
function Get-VixAlertasAuth([string]$RotinasLogDir, [datetime[]]$Dias) {
    $achados = @()
    foreach ($d in @($Dias)) {
        $tag = $d.ToString('yyyyMMdd')
        foreach ($rot in @('vixradar-noturno', 'vixradar-matinal', 'vixradar-verificacao-async', 'vixradar-sentinela', 'vixradar-agenda-semanal')) {
            $p = Join-Path $RotinasLogDir ($rot + '_' + $tag + '.log')
            if (-not (Test-Path $p)) { continue }
            foreach ($l in (Get-Content $p -Encoding UTF8)) {
                # DRYRUN_ALERTA_AUTH e teste, nao incidente (lookbehind).
                if ($l -match '(?<!DRYRUN_)ALERTA_AUTH') {
                    $txt = $l
                    if ($txt.Length -gt 220) { $txt = $txt.Substring(0, 220) }
                    $achados += @{ rotina = $rot; dia = $d.ToString('yyyy-MM-dd'); linha = $txt; log = $p }
                }
            }
        }
    }
    return $achados
}
