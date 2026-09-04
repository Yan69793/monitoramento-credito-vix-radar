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

# INCIDENTE-FRESHNESS2 (A4/H, 03/09/2026): FIM:/RUNNER_FIM: e o ledger OK| so contam
# como entrega dentro da JANELA REAL da rotina do dia (noturno >= 18:00, matinal >=
# 10:00 BRT). Sem isto, uma linha remanescente de um dry-run de madrugada, ou de uma
# execucao de recuperacao manual, podia mascarar a falta de entrega da execucao
# agendada seguinte - o proprio incidente que gerou esta guarda comecou com a
# noturna de 02/09 morrendo as 18:12 sem nenhum OK| e o retry das 21:30 abortando
# sem alertar. Compartilhada entre retry-vixradar.ps1 e monitor-tasks.ps1 (mesmo
# ledger, mesma regra), para os dois julgarem entrega da mesma forma.
function Test-VixLedgerEntregueNaJanela {
    # Entregue exige, dentro da janela: ledger OK| com >= MinimoLedger emissores
    # distintos (sinal AUTORITATIVO, ROTINACEGA2), OU uma linha FIM:/RUNNER_FIM:
    # cujo PROPRIO texto reporte contagem >= MinimoLedger (FIMREAL, os 4 formatos
    # historicos: submit_ok=N, Total do dia N/D, N processados, processados=N).
    # Uma linha FIM: SEM contagem parseavel NAO basta sozinha - "RUNNER_FIM:"
    # (INCIDENTE-FRESHNESS2) existe justamente para marcar "exit 0, mas isso nao
    # prova entrega", entao tratar a mera presenca de FIM: como prova contradiria
    # a razao de o rotulo ter sido criado.
    param(
        [Parameter(Mandatory)][string]$Conteudo,
        [Parameter(Mandatory)][datetime]$DataLog,
        [Parameter(Mandatory)][int]$JanelaHora,
        [int]$MinimoLedger = 90
    )
    $limite = Get-Date -Year $DataLog.Year -Month $DataLog.Month -Day $DataLog.Day -Hour $JanelaHora -Minute 0 -Second 0
    $vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $fimComContagemSuficiente = $false
    $linhaRegex = [regex]'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) (.*)$'
    foreach ($linhaRaw in ($Conteudo -split "`r?`n")) {
        $lm = $linhaRegex.Match($linhaRaw)
        if (-not $lm.Success) { continue }
        # TryParseExact, nao TryParse: no PowerShell 5.1 o overload generico de 2
        # argumentos falha com "Cannot find an overload" (ambiguidade contra o
        # overload de ReadOnlySpan<Char>, que o binder do PS 5.1 nao resolve).
        $ts = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($lm.Groups[1].Value + ' ' + $lm.Groups[2].Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ts)) { continue }
        if ($ts -lt $limite) { continue }
        $resto = $lm.Groups[3].Value
        $okM = [regex]::Match($resto, '^OK\|([^|]+)\|')
        if ($okM.Success) { [void]$vistos.Add($okM.Groups[1].Value.Trim()); continue }
        if ($resto -match '(?<!SHADOW_)(?:RUNNER_)?FIM:') {
            $n = -1
            if ($resto -match 'submit_ok=(\d+)') { $n = [int]$Matches[1] }
            elseif ($resto -match 'Total do dia (\d+)/\d+') { $n = [int]$Matches[1] }
            elseif ($resto -match '(\d+)(?:/\d+)?(?:\s+\S+)?\s+processados') { $n = [int]$Matches[1] }
            elseif ($resto -match 'processados=(\d+)') { $n = [int]$Matches[1] }
            if ($n -ge $MinimoLedger) { $fimComContagemSuficiente = $true }
        }
    }
    $entregue = ($vistos.Count -ge $MinimoLedger) -or $fimComContagemSuficiente
    return [PSCustomObject]@{
        Entregue                 = $entregue
        LedgerNaJanela            = $vistos.Count
        FimComContagemSuficiente = $fimComContagemSuficiente
        LimiteUsado               = $limite
    }
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

# RECOVERY-JANELA1 (03/09/2026): a SKILL da noturna (Passo 4) julgava idempotencia por DIA
# CIVIL - qualquer linha OK| do dia, a qualquer hora, tirava o emissor da fila. Em 03/09 a
# recuperacao manual das 09:07 fechou o ledger com 103 OK| e a invocacao agendada das 18:15
# saiu sem submeter nada, enquanto retry-vixradar.ps1 e o PAINEL_SLA do Worker julgam entrega
# por JANELA (>= 18:00). Resultado previsto: relancamento das 21:30 tambem no-op, alerta falso
# do retry, painel_fresco=false das 01:30 ate a matinal. As duas funcoes abaixo dao a skill a
# MESMA regua do vigia (mesmo regex de linha, mesmo corte por timestamp), devolvendo o CONJUNTO
# de emissores em vez da contagem, para ela decidir quem pular e quem processar.
function Get-VixJanelaInicioRotina {
    # Inicio da janela que vale AGORA. A partir de JanelaHora do dia, a janela e
    # [JanelaHora:00, fim do dia). Antes disso (recuperacao manual de manha, dry-run de
    # madrugada), a janela e o dia inteiro, preservando o comportamento antigo para
    # reexecucao fora do horario agendado. Sem ternario (PS 5.1).
    param(
        [Parameter(Mandatory)][datetime]$Agora,
        [Parameter(Mandatory)][int]$JanelaHora
    )
    $inicio = $Agora.Date
    if ($Agora.Hour -ge $JanelaHora) { $inicio = $Agora.Date.AddHours($JanelaHora) }
    return $inicio
}

function Get-VixLedgerEmissoresNaJanela {
    # Emissores com linha OK| carimbada >= JanelaInicio (ja processados NESTA janela) e
    # contagem dos que so aparecem antes dela (fora da janela: nao contam para pular).
    #
    # DEFERIDO-NAO-E-ENTREGA1 (04/09/2026): linha com status DEFERIDO NAO conta como
    # processada. O formato do ledger e
    #   OK|empresa|tier|classe|n_eventos|submit|status|n_avanco_data
    # e o regex antigo parava no nome, entao os emissores que o cap adiou apareciam como
    # feitos. Consequencia medida no ledger de 03/09: a passada fechou 58 ANALISADO e 45
    # DEFERIDO, e uma segunda invocacao DENTRO da mesma janela via 103 processados e saia
    # em no-op, sem tocar na cauda adiada, mesmo tendo orcamento sobrando na hora.
    # SKIP continua contando como entrega: o emissor foi avaliado e submetido de proposito,
    # so nao precisou de busca. Status ausente (ledger antigo, anterior a este formato)
    # tambem conta como entrega, para nao reprocessar historico retroativamente.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Conteudo,
        [Parameter(Mandatory)][datetime]$JanelaInicio
    )
    $dentro    = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $fora      = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $deferidos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $linhas = 0
    $linhaRegex = [regex]'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) OK\|([^|]+)\|'
    foreach ($linhaRaw in ($Conteudo -split "`r?`n")) {
        $lm = $linhaRegex.Match($linhaRaw)
        if (-not $lm.Success) { continue }
        $linhas++
        $ts = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($lm.Groups[1].Value + ' ' + $lm.Groups[2].Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ts)) { continue }
        $nome = $lm.Groups[3].Value.Trim()
        # Status pelo indice do campo, nao por regex rigido: o campo 8 (n_avanco_data)
        # entrou em 04/09 e outro pode entrar depois. Split tolera linha curta.
        $campos = $linhaRaw.Substring($linhaRaw.IndexOf('OK|')) -split '\|'
        $status = ''
        if ($campos.Count -ge 7) { $status = $campos[6].Trim() }
        if ($ts -lt $JanelaInicio) { [void]$fora.Add($nome); continue }
        if ($status -eq 'DEFERIDO') { [void]$deferidos.Add($nome); continue }
        [void]$dentro.Add($nome)
    }
    # .ToArray() de proposito: @() sobre List generica estoura o binder do PS 5.1.
    $lista = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in $dentro) { $lista.Add($n) }
    $listaDef = New-Object 'System.Collections.Generic.List[string]'
    foreach ($n in $deferidos) { $listaDef.Add($n) }
    return [PSCustomObject]@{
        Emissores         = $lista.ToArray()
        NaJanela          = $dentro.Count
        ForaDaJanela      = $fora.Count
        Deferidos         = $listaDef.ToArray()
        DeferidosNaJanela = $deferidos.Count
        LinhasOK          = $linhas
        JanelaInicio      = $JanelaInicio
    }
}
