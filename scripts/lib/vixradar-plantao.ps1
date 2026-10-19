# vixradar-plantao.ps1 - modo plantao da matinal em fim de semana e feriado (PLANTAO1, 2026-10-19)
#
# Decisao do operador em 19/10/2026: sabado, domingo e feriado B3 nao rodam varredura.
# Roda so uma checagem rapida de evento extraordinario. A matinal (diaria no Scheduler)
# continua disparando todo dia, mas em dia nao util ela delega para a Sentinela com
# -Plantao: o unico gatilho e acervo novo da CVM (documento publicado), backlog de dia
# util nao dispara analise e fica preservado para o proximo dia util.
#
# Regra pura e unica aqui, usada pelo motor (run_vixradar_varredura.ps1), pelo monitor
# (monitor-tasks.ps1) e pela prova (test-plantao-matinal.ps1).
#
# PowerShell 5.1, ASCII puro.

# Feriados B3 de 2026. Antes desta lib a lista vivia inline no motor.
$script:VixFeriadosB3 = @(
    '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
    '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
)

function Get-VixFeriadosB3 { return @($script:VixFeriadosB3) }

# 'feriado' | 'fim_de_semana' | 'util'. Feriado vence fim de semana (15/11/2026 e domingo).
function Get-VixModoDia([datetime]$Data, [string[]]$Feriados) {
    if ($null -eq $Feriados) { $Feriados = Get-VixFeriadosB3 }
    if ($Feriados -contains $Data.ToString('yyyy-MM-dd')) { return 'feriado' }
    if ($Data.DayOfWeek -eq [DayOfWeek]::Saturday -or $Data.DayOfWeek -eq [DayOfWeek]::Sunday) { return 'fim_de_semana' }
    return 'util'
}

# Exit da Sentinela -> resultado do plantao. 0 = checagem fechou (com ou sem evento).
# 10 = evento achado mas analise incompleta. 86 = provider bloqueado. Resto = falha.
function Get-VixPlantaoResultado([int]$ExitSentinela) {
    if ($ExitSentinela -eq 0) { return 'OK' }
    if ($ExitSentinela -eq 10) { return 'PARCIAL' }
    if ($ExitSentinela -eq 86) { return 'BLOQUEADO' }
    return 'FALHA'
}

# Ultima linha FIM: da Sentinela no log do dia (ou '' se nao houver).
function Get-VixSentinelaUltimoFim([string[]]$Linhas) {
    $ult = ''
    foreach ($l in @($Linhas)) {
        $t = '' + $l
        if ($t -match '(?<!SHADOW_)FIM: sentinela') { $ult = $t }
    }
    return $ult
}

function Get-VixCampoFim([string]$Linha, [string]$Campo) {
    $m = [regex]::Match($Linha, '(?:^|\s)' + [regex]::Escape($Campo) + '=([^\s]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# Linha FIM canonica do plantao. O monitor so reconhece este formato.
function Get-VixPlantaoFimLinha([string]$Modo, [int]$ExitSentinela, [string]$FimSentinela) {
    $res = Get-VixPlantaoResultado $ExitSentinela
    $tok = Get-VixCampoFim $FimSentinela 'tokens'
    $ana = Get-VixCampoFim $FimSentinela 'analisados'
    $mot = Get-VixCampoFim $FimSentinela 'motivo'
    if (-not $tok) { $tok = 'desconhecido' }
    if (-not $ana) { $ana = 'desconhecido' }
    if (-not $mot) { $mot = 'sem_fim_sentinela' }
    if (-not $FimSentinela -and $res -eq 'OK') { $res = 'FALHA' }
    return ('FIM: matinal plantao modo=' + $Modo + ' resultado=' + $res + ' sentinela_exit=' + $ExitSentinela + ' tokens=' + $tok + ' analisados=' + $ana + ' motivo_sentinela=' + $mot)
}

# Exit da matinal em plantao: 0 so quando a checagem fechou; senao o da Sentinela.
function Get-VixPlantaoExit([int]$ExitSentinela, [string]$FimSentinela) {
    if ($ExitSentinela -eq 0 -and -not $FimSentinela) { return 1 }
    return $ExitSentinela
}

# Monitor: o log do dia tem plantao fechado? Devolve $null (nao e plantao) ou objeto.
function Get-VixPlantaoEntrega([string]$Conteudo) {
    if (-not $Conteudo) { return $null }
    $ms = [regex]::Matches($Conteudo, '(?m)^.*FIM: matinal plantao modo=(\S+) resultado=(\S+).*$')
    if ($ms.Count -eq 0) { return $null }
    $m = $ms[$ms.Count - 1]
    return [pscustomobject]@{ Modo = $m.Groups[1].Value; Resultado = $m.Groups[2].Value; Linha = $m.Value.Trim(); Entregue = ($m.Groups[2].Value -eq 'OK' -or $m.Groups[2].Value -eq 'PARCIAL') }
}
