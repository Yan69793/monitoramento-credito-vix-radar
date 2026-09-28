# vixradar-task-unit.ps1 - modo UNITARIO dos registradores: exatamente 1 task por execucao.
#
# POR QUE ESTA LIB EXISTE (UNITREG1, 2026-09-25)
# Quatro registradores escrevem, cada um, num conjunto de tasks maior que 1:
#   register-all-routines-scheduler.ps1 -> 7 tasks (e ainda remove VIXRadar-Matinal-Retry)
#   register-monitor-tasks.ps1          -> 2 tasks (Monitor-Tasks + Monitor-Tasks-Site)
#   register-retry-tasks.ps1            -> 2 tasks (RetryVixMatinal + RetryVixNoturno)
# Corrigir uma task de drift de StartWhenAvailable por esses scripts arrastava as irmas
# (e, no caso de register-retry-tasks.ps1, ressuscitava RetryVixMatinal, que hoje esta
# Disabled de proposito). O jeito de corrigir 1 task sem tocar em nenhuma irma e o
# parametro -TaskName, que reduz a tabela do proprio registrador a EXATAMENTE uma task
# e confere o conjunto de escrita ANTES de qualquer escrita.
#
# CONTRATO
#   - Select-VixUnitDef       devolve exatamente 1 def da tabela do registrador, ou LANCA.
#   - Get-VixUnitWriteSet     nomes de task que este modo unitario pode escrever.
#   - Assert-VixUnitWriteSet  LANCA se o conjunto nao for exatamente @($Nome).
#   - Write-VixUnitWriteSet   imprime os dois marcadores que o teste le.
#
# Fail-closed: alvo ausente, alvo ambiguo, tabela vazia e write-set com mais de 1 nome
# LANCA antes da primeira escrita. Nome de task desconhecido nunca vira "nada a fazer"
# silencioso, e nome de irma nunca entra no conjunto.
#
# NAO faz: nao registra, nao altera, nao habilita/desabilita e nao dispara task nenhuma.
# Quem escreve no Task Scheduler continua sendo o registrador.
#
# PowerShell 5.1, ASCII puro. Prova: scripts/test-registrador-unitario.ps1.

function Select-VixUnitDef {
    # Devolve a UNICA entrada da tabela do registrador cujo campo -NomeCampo e igual a -Nome.
    # Qualquer coisa diferente de exatamente 1 match LANCA (fail-closed).
    param(
        [Parameter(Mandatory = $true)]$Defs,
        [Parameter(Mandatory = $true)][string]$Nome,
        [string]$NomeCampo = 'Name'
    )
    if (('' + $Nome).Trim() -eq '') {
        throw 'VIX-UNIT-ALVO-AUSENTE: -TaskName vazio - o modo unitario exige o nome da task alvo'
    }
    $lista = @($Defs)
    if ($lista.Count -eq 0) {
        throw 'VIX-UNIT-TABELA-VAZIA: este registrador nao declara nenhuma task'
    }
    $alvos = @($lista | Where-Object { [string]$_.$NomeCampo -eq $Nome })
    if ($alvos.Count -eq 0) {
        $conhecidos = (@($lista | ForEach-Object { [string]$_.$NomeCampo }) -join ', ')
        throw ('VIX-UNIT-ALVO-AUSENTE: ' + $Nome + ' nao esta na tabela deste registrador (' + $conhecidos + ')')
    }
    if ($alvos.Count -gt 1) {
        throw ('VIX-UNIT-ALVO-AMBIGUO: ' + $Nome + ' aparece ' + $alvos.Count + ' vezes na tabela deste registrador')
    }
    return $alvos[0]
}

function Get-VixUnitWriteSet {
    # Conjunto de escrita declarado pelo modo unitario: os nomes da tabela ja filtrada
    # mais os alvos auxiliares que o registrador realmente for escrever nesta execucao.
    param(
        [Parameter(Mandatory = $true)]$Defs,
        [string]$NomeCampo = 'Name',
        [string[]]$Extras = @()
    )
    $nomes = @()
    foreach ($d in @($Defs)) { $nomes += [string]$d.$NomeCampo }
    foreach ($e in @($Extras)) {
        if ($null -eq $e) { continue }
        if (('' + $e).Trim() -eq '') { continue }
        $nomes += ('' + $e)
    }
    return $nomes
}

function Assert-VixUnitWriteSet {
    # LANCA se o conjunto de escrita nao for exatamente 1 nome, igual ao alvo do modo unitario.
    # Nao lanca por outra razao: quem chama decide o que fazer com o nome devolvido.
    param(
        [Parameter(Mandatory = $true)]$Defs,
        [Parameter(Mandatory = $true)][string]$Nome,
        [string]$NomeCampo = 'Name',
        [string[]]$Extras = @()
    )
    $ws = @(Get-VixUnitWriteSet -Defs $Defs -NomeCampo $NomeCampo -Extras $Extras)
    $fora = @($ws | Where-Object { $_ -ne $Nome })
    if (($ws.Count -ne 1) -or ($fora.Count -gt 0)) {
        throw ('VIX-UNIT-WRITESET-EXCEDIDO: esperado exatamente 1 task (' + $Nome + '), conjunto calculado = [' + ($ws -join ', ') + '] - nada foi escrito')
    }
    return $ws[0]
}

function Write-VixUnitWriteSet {
    # Marcadores legiveis por teste. Em -DryRun descrevem o conjunto declarado (nenhuma
    # escrita acontece); no apply descrevem exatamente o que vai ser escrito.
    # Write-Host de proposito: nao polui o stream de saida de quem conta falhas.
    param([Parameter(Mandatory = $true)][string]$Nome)
    Write-Host ('VIX-UNIT-WRITESET: ' + $Nome)
    Write-Host 'VIX-UNIT-WRITESET-TOTAL: 1'
}
