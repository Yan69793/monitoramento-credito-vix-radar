# vixradar-task-guard.ps1 - contrato unico do guarda de execucao, do lado dos REGISTRADORES.
#
# POR QUE ESTA LIB EXISTE (GUARD-REG1, 2026-09-24)
# Ate 24/09/2026 so register-reconciliacao-cvm-task.ps1 montava a Action apontando para
# scripts/preflight-and-run.ps1 (GUARD-CVM1). Todos os outros registradores montavam
# `powershell.exe ... -File "<rotina>"` direto: a task nascia desprotegida e so ficava certa
# quando alguem rodava scripts/apply-preflight-tasks.ps1 -Apply depois. Ou seja, o caminho
# canonico de recriar a task voltava ao estado vulneravel, e a protecao dependia de um passo
# manual posterior que ninguem garante.
#
# Esta lib e a reutilizacao simples desse contrato: o MESMO formato de argumento que
# apply-preflight-tasks.ps1:Get-ArgumentoGuarda monta, a MESMA exigencia de tokens e a MESMA
# comparacao deterministica contra a task viva. O contrato nao esta copiado por registrador.
#
# CONTRATO
#   - Assert-VixGuardPath      fail-closed: sem o guarda na arvore o registrador RECUSA.
#   - Get-VixGuardArgument     monta a linha de argumento no formato identico ao do apply.
#   - Get-VixGuardArgumentFaltas  lista os tokens obrigatorios ausentes (vazia = passa no guarda).
#   - Test-VixGuardAction      valida a Action montada e compara com a task viva; devolve falhas.
#
# NAO faz: nao registra, nao altera, nao habilita/desabilita e nao dispara task nenhuma. So
# monta, valida e compara. Quem escreve no Task Scheduler e o registrador, e o -DryRun de cada
# um usa estas funcoes para provar a Action final sem tocar no scheduler vivo.
#
# PowerShell 5.1, ASCII puro. Prova: scripts/test-registrador-guarda.ps1.

function Assert-VixGuardPath {
    param([string]$Guarda)
    if (-not $Guarda) {
        throw 'guarda nao informado: registrador sem o caminho de scripts/preflight-and-run.ps1'
    }
    if (-not (Test-Path -LiteralPath $Guarda)) {
        throw ('guarda ausente: ' + $Guarda + ' - lande scripts/preflight-and-run.ps1 antes de registrar a task')
    }
    return (Resolve-Path -LiteralPath $Guarda).Path
}

function Get-VixGuardArgument {
    # Formato identico ao Get-ArgumentoGuarda de scripts/apply-preflight-tasks.ps1. O apply compara
    # por igualdade exata de string, entao qualquer drift aqui faria a task ser re-apontada de novo
    # e o registrador voltaria a ser fonte divergente.
    param(
        [string]$Guarda,
        [string]$Target,
        [string]$Name,
        [string]$LogPattern,
        [string[]]$ExtraArgs = @()
    )
    $arg  = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Guarda + '"'
    $arg += ' -GuardTarget "' + $Target + '"'
    $arg += ' -GuardName ' + "'" + $Name + "'"
    $arg += ' -GuardLogPattern "' + $LogPattern + '"'
    foreach ($a in @($ExtraArgs)) {
        if ($null -eq $a) { continue }
        if (('' + $a).Trim() -eq '') { continue }
        $arg += ' ' + $a
    }
    return $arg
}

function Get-VixGuardArgumentFaltas {
    # Lista de tokens obrigatorios ausentes. Lista vazia = a Action passa pelo guarda.
    # Nao lanca de proposito: quem decide reprovar e o registrador, e o teste prova os dois lados.
    param([string]$Argument)
    $faltas = @()
    $texto = '' + $Argument
    if ($texto -notlike '*preflight-and-run.ps1*') { $faltas += 'sem preflight-and-run.ps1' }
    foreach ($obrig in @('-GuardTarget', '-GuardName', '-GuardLogPattern')) {
        if ($texto -notlike ('*' + $obrig + '*')) { $faltas += ('sem ' + $obrig) }
    }
    return $faltas
}

function Get-VixTaskLiveArgument {
    # Leitura da task viva. Ausente devolve $null (nada para comparar), sem lancar.
    param([string]$TaskName)
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { return $null }
    return [string](@($t.Actions)[0]).Arguments
}

function Test-VixGuardAction {
    # Nucleo do -DryRun de todo registrador: valida a Action montada e compara com a task viva por
    # igualdade exata de string. Devolve o numero de falhas (0 = aprovado).
    # Nao registra, nao altera, nao dispara.
    #
    # As mensagens saem por Write-Host (stream de informacao) de proposito: o retorno desta funcao
    # e SO o inteiro, para o chamador poder fazer `$falhas = Test-VixGuardAction ...` sem capturar
    # o texto junto e concluir, errado, que houve falha porque a string tem tamanho maior que zero.
    param(
        [string]$Nome,
        [string]$Argument
    )
    $falhas = 0
    foreach ($f in @(Get-VixGuardArgumentFaltas -Argument $Argument)) {
        Write-Host ('FALHA ' + $Nome + ': acao ' + $f)
        $falhas++
    }
    if ($falhas -gt 0) {
        Write-Host ('  argument: ' + $Argument)
    }
    $viva = Get-VixTaskLiveArgument -TaskName $Nome
    if ($null -eq $viva) {
        Write-Host ('task viva: ' + $Nome + ' ausente (nada para comparar)')
        return $falhas
    }
    if ($viva -eq $Argument) {
        Write-Host ('task viva: ' + $Nome + ' igual ao esperado (apply-preflight-tasks.ps1 nao teria o que corrigir)')
        return $falhas
    }
    Write-Host ('task viva: ' + $Nome + ' DIFERENTE do esperado')
    Write-Host ('  viva    : ' + $viva)
    Write-Host ('  esperado: ' + $Argument)
    return ($falhas + 1)
}
