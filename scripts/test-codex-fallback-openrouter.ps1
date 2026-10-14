# test-codex-fallback-openrouter.ps1 - prova do CODEXFALLBACK-OR1 (2026-10-14), duas pontas.
#
# O que existe: o provedor ativo das rotinas e o Codex e ele NAO tinha fallback - quando o
# Codex ficava inutilizavel (cota da assinatura, credencial recusada, modelo indisponivel ou
# indisponibilidade persistente), o lote falhava e a cobertura parava. Existiam os dois outros
# sentidos de desvio (openrouter->claude e claude->openrouter); faltava este.
#
# O que esta suite prova:
#   Parte 1: Get-VixCodexFallbackOpenRouterHabilitado - leitura de env var, precedencia de
#            escopo (Process > User > Machine), caixa/espaco, valores invalidos desligam.
#   Parte 2: Get-VixCodexFailoverDecisao - funcao PURA. PONTA BOA: cota/auth/modelo_indisponivel
#            com destino pronto e var ligada = 'failover'; transitoria so apos o limite de
#            falhas consecutivas. PONTA RUIM: var desligada, destino nao pronto, override ativo
#            (guarda contra recursao) e transitoria isolada = 'fail-closed'.
#   Parte 3: LIGACAO - os dois chamadores (motor de varredura e sentinela) chamam a decisao,
#            tem a guarda contra recursao, validam o destino antes de desviar, corrigem a
#            contabilidade do provedor que falhou e registram o desvio no log. Cada assert e
#            uma ponta ruim (defeito) que reprova.
#
# Offline puro: nenhum token, nenhuma rede, nenhum POST, nenhuma rotina executada.
# ASCII puro, PS 5.1.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-llm-provider.ps1')

$script:ok = 0; $script:fal = 0
function Assert([bool]$c, [string]$m) { if ($c) { $script:ok++; Write-Host ('  OK    ' + $m) } else { $script:fal++; Write-Host ('  FALHA ' + $m) } }

# Remove a var dos tres escopos e guarda o original do User para restaurar no finally.
Remove-Item Env:\VIXRADAR_CODEX_FALLBACK_PROVIDER -ErrorAction SilentlyContinue
$userOriginal = [Environment]::GetEnvironmentVariable('VIXRADAR_CODEX_FALLBACK_PROVIDER', 'User')
[Environment]::SetEnvironmentVariable('VIXRADAR_CODEX_FALLBACK_PROVIDER', $null, 'User')

try {
    # ============================================================
    Write-Host '=== Parte 1: Get-VixCodexFallbackOpenRouterHabilitado (env) ==='
    Assert (-not (Get-VixCodexFallbackOpenRouterHabilitado)) 'A1: sem a variavel em nenhum escopo, desligado (fail-closed por omissao)'

    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = 'openrouter'
    Assert (Get-VixCodexFallbackOpenRouterHabilitado) 'B1: Process=openrouter liga'

    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = '  OpenRouter  '
    Assert (Get-VixCodexFallbackOpenRouterHabilitado) 'C1: maiuscula e espaco nao impedem o match'

    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = 'claude-subscription'
    Assert (-not (Get-VixCodexFallbackOpenRouterHabilitado)) 'D1: outro provedor nao liga o desvio'
    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = 'codex'
    Assert (-not (Get-VixCodexFallbackOpenRouterHabilitado)) 'D2: o proprio codex nao liga (sem auto-desvio)'
    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = ''
    Assert (-not (Get-VixCodexFallbackOpenRouterHabilitado)) 'D3: string vazia fica desligado'

    [Environment]::SetEnvironmentVariable('VIXRADAR_CODEX_FALLBACK_PROVIDER', 'openrouter', 'User')
    $env:VIXRADAR_CODEX_FALLBACK_PROVIDER = 'nenhum'
    Assert (-not (Get-VixCodexFallbackOpenRouterHabilitado)) 'E1: valor invalido no Process NAO cai para o User'
    Remove-Item Env:\VIXRADAR_CODEX_FALLBACK_PROVIDER -ErrorAction SilentlyContinue
    Assert (Get-VixCodexFallbackOpenRouterHabilitado) 'E2: sem Process, User=openrouter liga (precedencia documentada)'
    [Environment]::SetEnvironmentVariable('VIXRADAR_CODEX_FALLBACK_PROVIDER', $null, 'User')

    # ============================================================
    Write-Host '=== Parte 2: Get-VixCodexFailoverDecisao (pura, duas pontas) ==='
    $fx = { param($classe, $hab, $dest, $ovr, $fal) Get-VixCodexFailoverDecisao -Classe $classe -FalhasConsecutivas $fal -DestinoPronto $dest -Habilitado $hab -ProviderOverrideAtivo $ovr }

    Assert ((& $fx 'cota' $true $true $false 1) -eq 'failover') 'F1: cota (inclui saldo) com tudo pronto = failover'
    Assert ((& $fx 'auth' $true $true $false 1) -eq 'failover') 'F2: credencial recusada = failover'
    Assert ((& $fx 'modelo_indisponivel' $true $true $false 1) -eq 'failover') 'F3: modelo indisponivel = failover'
    Assert ((& $fx 'transitoria' $true $true $false 2) -eq 'failover') 'F4: transitoria PERSISTENTE (2 consecutivas) = failover'
    Assert ((& $fx 'transitoria' $true $true $false 1) -eq 'fail-closed') 'F5: transitoria isolada (1) NAO desvia - retry antes de trocar de provedor'
    Assert ((& $fx 'transitoria' $true $true $false 3) -eq 'failover') 'F6: excesso de falhas consecutivas tambem desvia (>= limite)'

    Assert ((& $fx 'cota' $false $true $false 5) -eq 'fail-closed') 'G1: sem a var ligada, fail-closed mesmo com cota esgotada'
    Assert ((& $fx 'cota' $true $false $false 5) -eq 'fail-closed') 'G2: destino NAO pronto, fail-closed (nunca desvia para lugar incerto)'
    Assert ((& $fx 'cota' $true $true $true 5) -eq 'fail-closed') 'G3: com override ativo, fail-closed (guarda contra recursao)'
    Assert ((& $fx 'parse-content' $true $true $false 9) -eq 'fail-closed') 'G4: classe de conteudo/parse nunca desvia (nao e problema de provedor)'
    Assert ((& $fx 'duro' $true $true $false 9) -eq 'fail-closed') 'G5: falha dura de conteudo nunca desvia'
    Assert ((& $fx '' $true $true $false 9) -eq 'fail-closed') 'G6: classe vazia nunca desvia'

    $lim = Get-VixCodexFailoverDecisao -Classe 'transitoria' -FalhasConsecutivas 4 -DestinoPronto $true -Habilitado $true -LimitePersistencia 4
    Assert ($lim -eq 'failover') 'H1: o limite de persistencia e parametrizavel (4 com 4 falhas)'
    $lim2 = Get-VixCodexFailoverDecisao -Classe 'transitoria' -FalhasConsecutivas 3 -DestinoPronto $true -Habilitado $true -LimitePersistencia 4
    Assert ($lim2 -eq 'fail-closed') 'H2: abaixo do limite parametrizado, segue fail-closed'

    # ============================================================
    Write-Host '=== Parte 3: ligacao nos chamadores (motor de varredura e sentinela) ==='
    $srcVarredura = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
    $srcSentinela = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8

    Assert ($srcVarredura -match 'Get-VixCodexFailoverDecisao') 'I1: o motor de varredura usa a decisao pura'
    Assert ($srcSentinela -match 'Get-VixCodexFailoverDecisao') 'I2: a sentinela usa a decisao pura'
    Assert ($srcVarredura -match 'Get-VixCodexFallbackOpenRouterHabilitado') 'I3: o motor le a var de habilitacao'
    Assert ($srcSentinela -match 'Get-VixCodexFallbackOpenRouterHabilitado') 'I4: a sentinela le a var de habilitacao'
    Assert ($srcVarredura -match 'Test-VixOpenRouterPronto') 'I5: o motor valida a prontidao do destino antes de desviar'
    Assert ($srcSentinela -match 'Test-VixOpenRouterPronto') 'I6: a sentinela valida a prontidao do destino antes de desviar'
    Assert ($srcVarredura -match 'ProviderOverrideAtivo \$providerOverrideAtivo') 'I7: o motor passa a guarda contra recursao a decisao'
    Assert ($srcSentinela -match 'ProviderOverrideAtivo \$providerOverrideAtivoS') 'I8: a sentinela passa a guarda contra recursao a decisao'
    Assert ($srcSentinela -match 'function Invoke-ClaudeBatchSentinela\(\[string\]\$promptPath, \[string\]\$Model, \[int\]\$TimeoutMin, \[string\]\$Tier = '''', \[string\]\$ProviderOverride = ''''\)') 'I9: a sentinela ganhou ProviderOverride (sem ele nao ha como desviar um lote)'
    Assert ($srcVarredura -match "FALLBACK_OPENROUTER_CODEX") 'I10: o desvio e registrado no log (executor visivel)'
    Assert ($srcSentinela -match "FALLBACK_OPENROUTER_CODEX") 'I11: o desvio e registrado no log da sentinela'
    Assert ($srcVarredura -match 'TokensFalhaFallback') 'I12: o motor contabiliza o custo do provedor que falhou'
    Assert ($srcSentinela -match 'TokensFalhaFallback') 'I13: a sentinela contabiliza o custo do provedor que falhou'
    # A regra do desvio do Codex NAO pode ser decidida fora da funcao pura: nenhuma copia local
    # da condicao de elegibilidade pode existir nos dois chamadores.
    Assert (-not ($srcVarredura -match "Classe -eq 'cota'")) 'I14: o motor nao reimplementa a elegibilidade (sem copia da regra)'
    Assert (-not ($srcSentinela -match "Classe -eq 'cota'")) 'I15: a sentinela nao reimplementa a elegibilidade (sem copia da regra)'

    # ============================================================
    Write-Host '=== Parte 4: ligacao nos outros dois chamadores (verificacao_async e agenda_semanal) ==='
    # Fecham as CINCO rotinas de IA: matinal e noturna vivem no motor de varredura (Parte 3),
    # a sentinela na Parte 3, e estes dois scripts cobrem verificacao_async e agenda_semanal.
    $srcVerif = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1') -Raw -Encoding UTF8
    $srcAgenda = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_agenda_semanal.ps1') -Raw -Encoding UTF8

    Assert ($srcVerif -match 'Get-VixCodexFailoverDecisao') 'J1: a verificacao_async usa a decisao pura'
    Assert ($srcAgenda -match 'Get-VixCodexFailoverDecisao') 'J2: a agenda_semanal usa a decisao pura'
    Assert ($srcVerif -match 'Get-VixCodexFallbackOpenRouterHabilitado') 'J3: a verificacao_async le a var de habilitacao'
    Assert ($srcAgenda -match 'Get-VixCodexFallbackOpenRouterHabilitado') 'J4: a agenda_semanal le a var de habilitacao'
    Assert ($srcVerif -match 'Test-VixOpenRouterPronto') 'J5: a verificacao_async valida a prontidao do destino antes de desviar'
    Assert ($srcAgenda -match 'Test-VixOpenRouterPronto') 'J6: a agenda_semanal valida a prontidao do destino antes de desviar'
    Assert ($srcVerif -match 'ProviderOverrideAtivo \$providerOverrideAtivoV') 'J7: a verificacao_async passa a guarda contra recursao a decisao'
    Assert ($srcAgenda -match 'ProviderOverrideAtivo \$providerOverrideAtivoA') 'J8: a agenda_semanal passa a guarda contra recursao a decisao'
    Assert ($srcVerif -match '\[string\]\$ProviderOverride = ''''') 'J9: a verificacao_async ganhou ProviderOverride (sem ele nao ha como desviar um lote)'
    Assert ($srcAgenda -match '\[string\]\$ProviderOverride = ''''') 'J10: a agenda_semanal ganhou ProviderOverride (sem ele nao ha como desviar um lote)'
    Assert ($srcVerif -match "FALLBACK_OPENROUTER_CODEX") 'J11: o desvio e registrado no log da verificacao_async'
    Assert ($srcAgenda -match "FALLBACK_OPENROUTER_CODEX") 'J12: o desvio e registrado no log da agenda_semanal'
    Assert ($srcVerif -match 'TokensFalhaFallback') 'J13: a verificacao_async contabiliza o custo do provedor que falhou'
    Assert ($srcAgenda -match 'TokensFalhaFallback') 'J14: a agenda_semanal contabiliza o custo do provedor que falhou'
    Assert (-not ($srcVerif -match "Classe -eq 'cota'")) 'J15: a verificacao_async nao reimplementa a elegibilidade (sem copia da regra)'
    Assert (-not ($srcAgenda -match "Classe -eq 'cota'")) 'J16: a agenda_semanal nao reimplementa a elegibilidade (sem copia da regra)'
    # O desvio tem de estar no ramo do CODEX: sem a resolucao local de provedor o texto poderia
    # existir e o caminho nao. A guarda contra recursao continua sendo o override.
    Assert ($srcVerif -match '-not \$providerOverrideAtivoV') 'J17: a verificacao_async nao desvia quando ja esta dentro de um override'
    Assert ($srcAgenda -match '-not \$providerOverrideAtivoA') 'J18: a agenda_semanal nao desvia quando ja esta dentro de um override'
    Assert ($srcAgenda -match 'Invoke-ClaudeBatch \$promptPath \$ModeloChamada -ProviderOverride ''openrouter''') 'J19: a agenda_semanal reenvia o MESMO lote com o override'
    Assert ($srcVerif -match 'Invoke-ClaudeBatch \$promptPath \$Model -ProviderOverride ''openrouter''') 'J20: a verificacao_async reenvia o MESMO lote com o override'

    # Cinto-e-suspensorio: as CINCO rotinas de IA precisam estar cobertas. Matinal e noturna
    # compartilham o motor de varredura, entao a cobertura se mede em 4 scripts.
    $quatro = @('run_vixradar_varredura.ps1', 'run_vixradar_sentinela.ps1', 'run_vixradar_verificacao_async.ps1', 'run_vixradar_agenda_semanal.ps1')
    $cobertas = 0
    foreach ($nome in $quatro) {
        $src = Get-Content -LiteralPath (Join-Path $PSScriptRoot $nome) -Raw -Encoding UTF8
        if ($src -match 'Get-VixCodexFailoverDecisao') { $cobertas++ }
    }
    Assert ($cobertas -eq 4) ('K1: as 4 pontas de codigo das 5 rotinas de IA usam a decisao unica; cobertas=' + $cobertas + '/4')
}
finally {
    Remove-Item Env:\VIXRADAR_CODEX_FALLBACK_PROVIDER -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('VIXRADAR_CODEX_FALLBACK_PROVIDER', $userOriginal, 'User')
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
