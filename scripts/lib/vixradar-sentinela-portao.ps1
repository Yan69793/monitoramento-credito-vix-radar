# vixradar-sentinela-portao.ps1 - portao da Sentinela por marcador de acervo (SENTINELASHA1, 2026-10-19)
#
# Antes: a Sentinela decidia "acervo novo" comparando cvm_fonte_last_modified do health com
# o estado. Desde a ingestao ENET (fd87df1, 13/09) o campo vinha null, a comparacao de data
# do zip contra '' dava sempre "precisa sync", e toda execucao sincronizava e entrava por
# acervo_novo. O resultado era certo por acidente: o sync a cada 30 min e o que mantem a
# ENET fresca no dia, e o plano pontual so pega cvm_novos > 0.
#
# Agora o sync da ENET e explicito em toda execucao, e "acervo novo" e decidido pelo
# marcador do acervo do Worker (health.cvm_acervo_sha256, CVMLASTMOD1). Health sem o campo
# (Worker anterior a CVMLASTMOD1) cai na regua legada, que reproduz o comportamento medido:
# sync concluido = acervo novo. Assim a rotina funciona com os dois Workers.
#
# Regra pura e unica aqui; run_vixradar_sentinela.ps1 so mede e chama.
# PowerShell 5.1, ASCII puro.

# Acao: 'entrar' (consultar plano), 'quieto' (sair 0 sem gasto), 'cego' (sair 3, fonte sem visao).
function Get-VixSentinelaPortao {
    param(
        [string]$ShaAtual,
        [string]$ShaEstado,
        [string]$WorkerLm,
        [string]$WorkerLmEstado,
        [bool]$SyncFeito,
        [bool]$Pending,
        [bool]$Plantao
    )
    $regua = 'legado'
    if (-not [string]::IsNullOrWhiteSpace($ShaAtual)) { $regua = 'sha' }
    $acervoMudou = $false
    if ($regua -eq 'sha') { $acervoMudou = ($ShaAtual -ne ('' + $ShaEstado)) }
    else { $acervoMudou = ((('' + $WorkerLm) -ne ('' + $WorkerLmEstado)) -or $SyncFeito) }

    if ($acervoMudou) { return [pscustomobject]@{ Acao = 'entrar'; Motivo = 'acervo_novo'; Regua = $regua; AcervoMudou = $true } }
    if ($Plantao) {
        # Plantao so tem um gatilho, o acervo. Sem sync concluido nesta execucao, "nada mudou"
        # nao foi verificado: e fonte cega, nunca dia quieto. Backlog nao dispara em plantao.
        if (-not $SyncFeito) { return [pscustomobject]@{ Acao = 'cego'; Motivo = 'plantao_sync_falhou'; Regua = $regua; AcervoMudou = $false } }
        return [pscustomobject]@{ Acao = 'quieto'; Motivo = 'plantao_sem_novidade'; Regua = $regua; AcervoMudou = $false }
    }
    if ($Pending) { return [pscustomobject]@{ Acao = 'entrar'; Motivo = 'backlog'; Regua = $regua; AcervoMudou = $false } }
    return [pscustomobject]@{ Acao = 'quieto'; Motivo = 'sem_novidade'; Regua = $regua; AcervoMudou = $false }
}
