# test-sentinela-portao.ps1 - prova de duas pontas do SENTINELASHA1 (2026-10-19)
#
# Decisao do portao da Sentinela (lib\vixradar-sentinela-portao.ps1), a MESMA funcao que a
# rotina chama, com o health atual (sem cvm_acervo_sha256, regua legada) e o novo (regua sha),
# em dia util e em plantao. Mais checagens de que a rotina sincroniza em toda execucao e
# grava o marcador no estado. Sem rede, sem token. Exit 0 so com tudo verde.
$ErrorActionPreference = 'Continue'
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptsDir 'lib\vixradar-sentinela-portao.ps1')

$script:ok = 0; $script:falhas = New-Object System.Collections.Generic.List[string]
function Assert-Portao($nome, $esperadoAcao, $esperadoMotivo, $r) {
    $obt = '' + $r.Acao + '/' + $r.Motivo
    if ($r.Acao -eq $esperadoAcao -and $r.Motivo -eq $esperadoMotivo) { $script:ok++; Write-Output ("OK   " + $nome + " -> " + $obt + " regua=" + $r.Regua) }
    else { $script:falhas.Add($nome); Write-Output ("FAIL " + $nome + " esperado=" + $esperadoAcao + "/" + $esperadoMotivo + " obtido=" + $obt) }
}
function Assert-Verdade($nome, $cond) {
    if ($cond) { $script:ok++; Write-Output ("OK   " + $nome) } else { $script:falhas.Add($nome); Write-Output ("FAIL " + $nome) }
}
$A = 'a' * 64; $B = 'b' * 64

# 1. Health atual (sem sha): reproduz o comportamento medido em producao
Assert-Portao 'legado util: sync ok = acervo novo' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $false -Plantao $false)
Assert-Portao 'legado util: sync falhou, sem backlog = quieto' 'quieto' 'sem_novidade' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $false -Plantao $false)
Assert-Portao 'legado util: sync falhou, com backlog = backlog' 'entrar' 'backlog' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $true -Plantao $false)
Assert-Portao 'legado util: last_modified mudou sem sync = acervo novo' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '2026-10-18' -WorkerLmEstado '2026-10-11' -SyncFeito $false -Pending $false -Plantao $false)
Assert-Portao 'legado plantao: sync ok = acervo novo (plano filtra cvm_novos)' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $true -Plantao $true)

# 2. Ponta ruim que o PLANTAO1 deixava passar: plantao, sync falhou, SEM backlog
Assert-Portao 'legado plantao: sync falhou sem backlog = cego (nunca quieto)' 'cego' 'plantao_sync_falhou' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $false -Plantao $true)
Assert-Portao 'legado plantao: sync falhou com backlog = cego' 'cego' 'plantao_sync_falhou' (Get-VixSentinelaPortao -ShaAtual '' -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $true -Plantao $true)

# 3. Health novo (sha): sync ok sem mudanca de acervo NAO e mais acervo novo
Assert-Portao 'sha util: mesmo sha, sem backlog = quieto' 'quieto' 'sem_novidade' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -WorkerLm '2026-10-18' -WorkerLmEstado '2026-10-18' -SyncFeito $true -Pending $false -Plantao $false)
Assert-Portao 'sha util: mesmo sha, com backlog = backlog' 'entrar' 'backlog' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $true -Plantao $false)
Assert-Portao 'sha util: sha mudou = acervo novo' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual $B -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $false -Plantao $false)
Assert-Portao 'sha util: sha mudou mesmo com sync falho (cron ingeriu)' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual $B -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $false -Plantao $false)
Assert-Portao 'sha: last_modified mudou mas sha igual = quieto (sha manda)' 'quieto' 'sem_novidade' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -WorkerLm '2026-10-25' -WorkerLmEstado '2026-10-18' -SyncFeito $true -Pending $false -Plantao $false)
Assert-Portao 'sha: primeira execucao apos o deploy (estado sem sha) entra uma vez' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado '' -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $false -Plantao $false)
Assert-Portao 'sha plantao: mesmo sha, sync ok = plantao quieto' 'quieto' 'plantao_sem_novidade' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $true -Plantao $true)
Assert-Portao 'sha plantao: mesmo sha, sync falhou = cego' 'cego' 'plantao_sync_falhou' (Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $false -Pending $false -Plantao $true)
Assert-Portao 'sha plantao: sha mudou = acervo novo' 'entrar' 'acervo_novo' (Get-VixSentinelaPortao -ShaAtual $B -ShaEstado $A -WorkerLm '' -WorkerLmEstado '' -SyncFeito $true -Pending $false -Plantao $true)
Assert-Verdade 'regua sha quando o health traz o campo' ((Get-VixSentinelaPortao -ShaAtual $A -ShaEstado $A -SyncFeito $true).Regua -eq 'sha')
Assert-Verdade 'regua legado quando o health nao traz' ((Get-VixSentinelaPortao -ShaAtual '' -ShaEstado $A -SyncFeito $true).Regua -eq 'legado')

# 4. Estrutura da rotina
$sent = Get-Content -LiteralPath (Join-Path $ScriptsDir 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
Assert-Verdade 'rotina sem caractere de controle' (-not ($sent -match '[\x00-\x08\x0B\x0C\x0E-\x1F]'))
Assert-Verdade 'rotina carrega a lib do portao' ($sent -match [regex]::Escape('lib\vixradar-sentinela-portao.ps1'))
Assert-Verdade 'rotina decide pelo portao' ($sent -match 'Get-VixSentinelaPortao -ShaAtual \$shaAtual')
Assert-Verdade 'sync nao depende mais de precisaSync' ($sent -notmatch '\$precisaSync')
Assert-Verdade 'sync chamado fora de condicao do zip' ($sent -match "(?ms)^\`$senha = Get-AdminSenha\r?\nif \(-not \`$senha\)")
Assert-Verdade 'estado grava acervo_sha256' ($sent -match "acervo_sha256\s+= '' \+ \`$script:AcervoShaParaEstado")
Assert-Verdade 'health relido le cvm_acervo_sha256' ($sent -match '\$shaAtual = .. \+ \$h2\.cvm_acervo_sha256')
Assert-Verdade 'cego sai exit 3 com motivo do portao' ($sent -match "(?ms)Acao -eq 'cego'.*?motivo=' \+ \`$portao\.Motivo\)\r?\n\s+exit 3")
Assert-Verdade 'formato FIM sem gatilho preservado' ($sent -match "FIM: sentinela sem gatilho\. tokens=0 analisados=0 motivo=' \+ \`$portao\.Motivo")

$res = [ordered]@{ suite = 'test-sentinela-portao'; ok = $script:ok; falhas = $script:falhas.Count; nomes_falha = @($script:falhas) }
Write-Output ($res | ConvertTo-Json -Compress)
if ($script:falhas.Count -gt 0) { exit 1 }
exit 0
