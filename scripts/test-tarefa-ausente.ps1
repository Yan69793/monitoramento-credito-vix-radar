# test-tarefa-ausente.ps1 - TAREFAAUSENTE1: prova de duas pontas da deteccao de tarefa apagada.
# Funcao pura sobre listas de nomes. Nao consulta o Agendador, nao toca rotina viva.
# Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-tarefas-esperadas.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}

$todas = @($script:VixTarefasEsperadas)
Confere 'lista esperada inclui Noturno e Sentinela' (($todas -contains 'VIXRadar-Noturno') -and ($todas -contains 'VIXRadar-Sentinela'))

# Ponta boa: tudo presente, nada falta.
$r0 = @(Get-VixTarefasAusentes -Existentes ($todas + @('Outra-Tarefa-Qualquer')))
Confere 'ponta boa: todas presentes => nenhuma ausente' ($r0.Count -eq 0)

# Ponta ruim: o cenario de 21/10 (Noturno e Sentinela apagadas).
$sem = @($todas | Where-Object { $_ -ne 'VIXRadar-Noturno' -and $_ -ne 'VIXRadar-Sentinela' })
$r1 = @(Get-VixTarefasAusentes -Existentes $sem)
Confere ('ponta ruim: detecta as duas apagadas => ' + ($r1 -join ',')) ($r1.Count -eq 2 -and ($r1 -contains 'VIXRadar-Noturno') -and ($r1 -contains 'VIXRadar-Sentinela'))

# Caixa nao importa (o Agendador registrou VIXRADAR-NOTURNO em maiusculas na exclusao).
$r2 = @(Get-VixTarefasAusentes -Existentes ($todas | ForEach-Object { $_.ToUpper() }))
Confere 'caixa diferente conta como presente' ($r2.Count -eq 0)

# Lista vazia do Agendador => tudo ausente (falha alta, nunca silenciosa).
$r3 = @(Get-VixTarefasAusentes -Existentes @())
Confere 'Agendador vazio => todas ausentes' ($r3.Count -eq $todas.Count)

# Estatico: o monitor usa a funcao e so com motor task-scheduler.
$fonte = Get-Content -LiteralPath (Join-Path $aqui 'monitor-tasks.ps1') -Raw -Encoding UTF8
Confere 'monitor-tasks usa Get-VixTarefasAusentes com erro 9009' ($fonte.Contains('Get-VixTarefasAusentes') -and $fonte.Contains('code    = 9009'))
Confere 'monitor-tasks so checa com motor task-scheduler' ($fonte.Contains("`$MotorAtual -eq 'task-scheduler' -and (Get-Command Get-VixTarefasAusentes -ErrorAction SilentlyContinue)") -and $fonte.Contains("Join-Path `$ScriptDir 'lib\vixradar-tarefas-esperadas.ps1'"))

Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
