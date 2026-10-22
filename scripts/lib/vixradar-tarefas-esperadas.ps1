# vixradar-tarefas-esperadas.ps1 - TAREFAAUSENTE1: o conjunto de tarefas do Agendador que precisa existir.
#
# Incidente 21/10/2026 21:03: VIXRadar-Noturno e VIXRadar-Sentinela foram apagadas do Agendador (por
# NT AUTHORITY\System, autor nao provado) e o Monitor-Tasks nao viu nada, porque ele so percorre as
# tarefas que EXISTEM. Tarefa apagada nao tem LastTaskResult para reprovar.
# Funcao pura: recebe nomes e devolve os que faltam. Nome de tarefa no Windows nao diferencia caixa.
# Compativel com Windows PowerShell 5.1, so ASCII.

$script:VixTarefasEsperadas = @(
    'VIXRadar-Matinal',
    'VIXRadar-Noturno',
    'VIXRadar-Verificacao-Async',
    'VIXRadar-Sentinela',
    'VIXRadar-AgendaSemanal',
    'VIXRadar-Coleta-Volatilidade',
    'VIXRadar-Export-Historico',
    'VIXRadar-Reconciliacao-CVM',
    'VIXRadar-EWS2-Pacote',
    'Szuchmacher-RetryVixNoturno'
)

function Get-VixTarefasAusentes {
    param([string[]]$Existentes, [string[]]$Esperadas = $script:VixTarefasEsperadas)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in @($Existentes)) { if ($e) { [void]$set.Add($e.Trim()) } }
    $faltam = @()
    foreach ($n in @($Esperadas)) { if (-not $set.Contains($n)) { $faltam += $n } }
    return $faltam
}
