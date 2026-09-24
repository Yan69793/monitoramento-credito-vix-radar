# vixradar-monitor-kfp.ps1 - decisao da excecao de falso-positivo conhecido (lib dot-source).
# ASCII puro (parse no powershell.exe 5.1). Usada por monitor-tasks.ps1 e por
# scripts/test-monitor-kfp-janela.ps1 (prova de duas pontas, a MESMA funcao nos dois lados).
#
# KFPJANELA1 (2026-09-24). O defeito que esta lib fecha:
#   A regra antiga media a graca a partir do LastRunTime VIVO da task
#   (($agora - $lastRun).Days <= graceDays). Numa task semanal isso nao expira nunca: a
#   execucao seguinte renova o LastRunTime, o contador volta a zero e a falha real da
#   semana seguinte e mascarada de novo. Medido com a task viva VIXRadar-Reconciliacao-CVM
#   (segunda 12:00): numa simulacao de 8 semanas falhando toda semana, 52 de 52 rodadas do
#   monitor ficavam mascaradas. O exit 1 de 21/09/2026 da task viva, que nao tem nada a ver
#   com o incidente de 03/08 documentado na entrada, estava mascarado com ageDays=2/7.
#
#   A regra antiga tambem mascarava task diaria para sempre: falhar todo dia renova o
#   LastRunTime todo dia e o contador nunca passa de 0.
#
# A regra nova ancora a excecao na DATA DO INCIDENTE documentado (frozenLastRun), nunca no
# LastRunTime corrente. Duas consequencias, as duas cobertas por teste:
#   1. resultado mais novo que a ancora = FALHA NOVA, nao e falso-positivo: nao mascarar;
#   2. sem execucao nova, a janela expira mesmo assim apos graceDays contados da ancora.
#
# Formato da entrada em monitor-tasks.ps1 (nao renomear campo sem mexer aqui):
#   @{ code = 1; reason = '...'; frozenLastRun = '2026-08-03'; graceDays = 7 }

function Get-VixMonitorKfpDecision {
    param(
        [string]$Name,
        [int]$Code,
        [datetime]$LastRun,
        [datetime]$Now,
        [hashtable]$Entry
    )
    $out = [ordered]@{
        Name       = $Name
        Matched    = $false  # Code e o codigo documentado desta entrada
        Masked     = $false  # a excecao vale agora: nao reportar
        Expired    = $false  # excecao vencida e sem execucao nova: escalar para warning
        NewFailure = $false  # resultado mais novo que a ancora: seguir classificacao normal
        AgeDays    = -1
        GraceDays  = 0
        Frozen     = ''
        Reason     = ''
    }
    if ($null -eq $Entry) { return [pscustomobject]$out }

    $out.GraceDays = [int]$Entry.graceDays
    $frozenTxt = [string]$Entry.frozenLastRun

    # Codigo diferente do documentado: esta entrada nao tem opiniao nenhuma.
    if ($Code -ne [int]$Entry.code) { return [pscustomobject]$out }
    $out.Matched = $true

    # Entrada sem ancora e entrada invalida: fail-closed, nunca mascarar.
    if ([string]::IsNullOrWhiteSpace($frozenTxt)) {
        $out.Expired = $true
        $out.Reason = 'entrada de falso-positivo sem frozenLastRun: ancora invalida, nao mascarar'
        return [pscustomobject]$out
    }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # Ancora ilegivel (formato errado, data inexistente) tambem e entrada invalida: fail-closed
    # em vez de deixar o ParseExact estourar no meio do monitor e a excecao mascarar por acidente.
    $frozen = $null
    try { $frozen = [datetime]::ParseExact($frozenTxt, 'yyyy-MM-dd', $inv) } catch { $frozen = $null }
    if ($null -eq $frozen) {
        $out.Expired = $true
        $out.Reason = 'frozenLastRun ilegivel (' + $frozenTxt + '): ancora invalida, nao mascarar'
        return [pscustomobject]$out
    }
    $out.Frozen = $frozenTxt
    $out.AgeDays = ($Now.Date - $LastRun.Date).Days

    # 1. Resultado produzido DEPOIS da ancora nao e o incidente documentado.
    if ($LastRun.Date -gt $frozen.Date) {
        $out.NewFailure = $true
        $out.Reason = ('falha nova: LastRun ' + $LastRun.ToString('yyyy-MM-dd HH:mm', $inv) +
                       ' e posterior a ancora ' + $frozenTxt + ' - a excecao nao cobre este resultado')
        return [pscustomobject]$out
    }

    # 2. Incidente documentado dentro da janela: mascarar. Fora dela: expirar de verdade.
    if ($out.AgeDays -le $out.GraceDays) {
        $out.Masked = $true
    } else {
        $out.Expired = $true
        $out.Reason = ('falso-positivo conhecido ancorado em ' + $frozenTxt + ' ha ' + $out.AgeDays +
                       ' dias (> ' + $out.GraceDays + 'd) - reavaliar')
    }
    return [pscustomobject]$out
}
