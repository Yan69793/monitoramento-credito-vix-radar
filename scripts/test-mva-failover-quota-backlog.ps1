# test-mva-failover-quota-backlog.ps1 - prova do contrato MVA provider-agnostic (2026-09-14).
#   (1) wiring: o motor importa lib\vixradar-llm-provider.ps1, chama
#       Get-VixFailoverClasse no ramo de falha do adapter e trava o boot se a
#       lib estiver incompleta; o monitor tambem importa a lib;
#   (2) quota-exhausted = failover IMEDIATO, zero retry no mesmo recurso
#       (o corpo manda sobre o status: 429 com texto de limite e quota,
#       nao transient);
#   (3) transient = retry bounded, no maximo 3 tentativas, backoff 0/5/20
#       (trava em 20 acima de 3);
#   (4) parse-content = NUNCA failover automatico, mesmo com fallback;
#   (5) duro (401/403/404) = sem retry, sem failover, fail-closed;
#   (6) prioridade MATINAL (1) sobre NOTURNA (2) sobre SENTINELA (3);
#   (7) sentinela pausa SOMENTE com metrica verificavel; sem percentual e sem
#       exaustao confirmada, segue sem auto-pause (limitacao documentada);
#   (8) teto PAYG ausente ou invalido = estourado (fail-closed), nunca liberado;
#   (9) backlog so fecha com submit confirmado, nunca por tentativa ou exit 0;
#   (10) worker.js ja expoe painel_fresco + feed_fresco + motivo no health
#       publico (linha 20344) e checks.painel_fresco no admin (linha 19707):
#       prova por grep com numero da linha, sem mudar api/ (sem deploy).
# LIMITACAO DOCUMENTADA (sentinela): sem percentual de quota do provedor, a
# pausa sai por sinal de exaustao confirmado (session-limit/quota), nao por
# numero; Test-VixSentinelaPausada devolve limitacao explicando isso.
# ASCII puro, PS 5.1, sem rede, sem segredo, sem escrita fora de $env:TEMP.
$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib\vixradar-llm-provider.ps1')

$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

Write-Host '=== 1. Wiring: motor e monitor consomem a lib de verdade (nao orfa) ==='
$motor = Get-Content (Join-Path $scriptDir 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
$mont = Get-Content (Join-Path $scriptDir 'monitor-tasks.ps1') -Raw -Encoding UTF8
$lib = Get-Content (Join-Path $scriptDir 'lib\vixradar-llm-provider.ps1') -Raw -Encoding UTF8
Assert ($motor -match "lib\\vixradar-llm-provider\.ps1") 'motor importa lib\vixradar-llm-provider.ps1'
Assert ($motor -match 'Get-VixFailoverClasse -Status') 'motor CHAMA Get-VixFailoverClasse no ramo de falha do adapter'
Assert ($motor -match 'MVA_FAILOVER: classe=') 'motor loga a classe MVA (tag MVA_FAILOVER)'
Assert ($motor -match "'Test-VixBacklogPodeFechar'") 'boot do motor trava sem as funcoes MVA (Assert-VixLibFunctions)'
foreach ($fn in @('Get-VixFailoverClasse', 'Get-VixMvaBackoffSegundos', 'Get-VixFailoverDecisao', 'Get-VixRotinaPrioridade', 'Test-VixRotinaPreemptiva', 'Get-VixPaygTetoDiario', 'Test-VixPaygTetoEstourado', 'Test-VixContinuidadePermitida', 'Get-VixBacklogMotivo', 'Test-VixSentinelaPausada', 'Test-VixBacklogPodeFechar')) {
    Assert ($lib -match ('function ' + $fn)) ('lib define ' + $fn)
}
Assert ($mont -match "lib\\vixradar-llm-provider\.ps1") 'monitor importa lib\vixradar-llm-provider.ps1'

Write-Host '=== 2. Quota-exhausted: failover IMEDIATO, zero retry ==='
$cQuota = Get-VixFailoverClasse -Status 429 -Corpo 'Error: session-limit reached. You hit your weekly limit.' -RespostaOk $false
Assert ($cQuota -eq 'quota-exhausted') ('429 com texto de session-limit e quota, nao transient (classe=' + $cQuota + ')')
$cQuota402 = Get-VixFailoverClasse -Status 402 -Corpo 'credit balance too low' -RespostaOk $false
Assert ($cQuota402 -eq 'quota-exhausted') ('402 com texto de credito e quota-exhausted (classe=' + $cQuota402 + ')')
$dQuota = Get-VixFailoverDecisao -Classe 'quota-exhausted' -TentativasMesmoRecurso 1 -TemFallbackElegivel $true -PaygTetoEstourado $false
Assert ($dQuota -eq 'failover') ('quota na 1a tentativa com fallback vai direto a failover, sem retry (decisao=' + $dQuota + ')')
$dQuotaSem = Get-VixFailoverDecisao -Classe 'quota-exhausted' -TentativasMesmoRecurso 1 -TemFallbackElegivel $false -PaygTetoEstourado $false
Assert ($dQuotaSem -eq 'fail-closed') ('quota sem fallback elegivel fecha, nao inventa rota (decisao=' + $dQuotaSem + ')')

Write-Host '=== 3. Transient: no maximo 3 tentativas, backoff 0/5/20 ==='
Assert ((Get-VixMvaBackoffSegundos -Tentativa 1) -eq 0) 'backoff tentativa 1 = 0s'
Assert ((Get-VixMvaBackoffSegundos -Tentativa 2) -eq 5) 'backoff tentativa 2 = 5s'
Assert ((Get-VixMvaBackoffSegundos -Tentativa 3) -eq 20) 'backoff tentativa 3 = 20s'
Assert ((Get-VixMvaBackoffSegundos -Tentativa 4) -eq 20) 'backoff trava em 20s acima de 3 (nao escala sozinho)'
Assert ((Get-VixFailoverClasse -Status 0 -Corpo 'timeout apos 30s' -RespostaOk $false) -eq 'transient') 'status 0 (transporte) e transient'
Assert ((Get-VixFailoverClasse -Status 500 -Corpo '' -RespostaOk $false) -eq 'transient') '500 sem texto de quota e transient'
Assert ((Get-VixFailoverClasse -Status 429 -Corpo 'too many requests, retry later' -RespostaOk $false) -eq 'transient') '429 SEM texto de quota e transient (ponta que diferencia de quota)'
$dT1 = Get-VixFailoverDecisao -Classe 'transient' -TentativasMesmoRecurso 1 -TemFallbackElegivel $true -PaygTetoEstourado $false
$dT2 = Get-VixFailoverDecisao -Classe 'transient' -TentativasMesmoRecurso 2 -TemFallbackElegivel $true -PaygTetoEstourado $false
$dT3 = Get-VixFailoverDecisao -Classe 'transient' -TentativasMesmoRecurso 3 -TemFallbackElegivel $true -PaygTetoEstourado $false
$dT3s = Get-VixFailoverDecisao -Classe 'transient' -TentativasMesmoRecurso 3 -TemFallbackElegivel $false -PaygTetoEstourado $false
Assert ($dT1 -eq 'retry') 'transient tentativa 1 = retry'
Assert ($dT2 -eq 'retry') 'transient tentativa 2 = retry'
Assert ($dT3 -eq 'failover') 'transient esgotado (3) com fallback = failover'
Assert ($dT3s -eq 'fail-closed') 'transient esgotado (3) sem fallback = fail-closed'

Write-Host '=== 4. Parse-content NUNCA vira failover ==='
Assert ((Get-VixFailoverClasse -Status 200 -Corpo '' -RespostaOk $true) -eq 'parse-content') '2xx vazio e parse-content, nao sucesso'
Assert ((Get-VixFailoverClasse -Status 200 -Corpo 'invalid json: unexpected token' -RespostaOk $true) -eq 'parse-content') '2xx malformado e parse-content'
Assert ((Get-VixFailoverClasse -Status 422 -Corpo 'x' -RespostaOk $false) -eq 'parse-content') '422 e parse-content'
$dParse = Get-VixFailoverDecisao -Classe 'parse-content' -TentativasMesmoRecurso 1 -TemFallbackElegivel $true -PaygTetoEstourado $false
Assert ($dParse -eq 'fail-closed') ('parse com fallback e teto ok CONTINUA fail-closed, nunca failover (decisao=' + $dParse + ')')

Write-Host '=== 5. Duro: sem retry, sem failover ==='
Assert ((Get-VixFailoverClasse -Status 401 -Corpo '' -RespostaOk $false) -eq 'duro') '401 e duro'
Assert ((Get-VixFailoverClasse -Status 402 -Corpo 'pagamento recusado, tente de novo' -RespostaOk $false) -eq 'duro') '402 sem texto de saldo/credito/quota e duro, nao quota'
$dDuro = Get-VixFailoverDecisao -Classe 'duro' -TentativasMesmoRecurso 1 -TemFallbackElegivel $true -PaygTetoEstourado $false
Assert ($dDuro -eq 'fail-closed') 'duro com fallback CONTINUA fail-closed'

Write-Host '=== 6. Prioridade: MATINAL sobre NOTURNA sobre SENTINELA ==='
Assert ((Get-VixRotinaPrioridade 'matinal') -eq 1) 'matinal = 1'
Assert ((Get-VixRotinaPrioridade 'VIXRADAR-MATINAL') -eq 1) 'vixradar-matinal (case misto) = 1'
Assert ((Get-VixRotinaPrioridade 'noturna') -eq 2) 'noturna = 2'
Assert ((Get-VixRotinaPrioridade 'vixradar-noturno') -eq 2) 'vixradar-noturno = 2'
Assert ((Get-VixRotinaPrioridade 'sentinela') -eq 3) 'sentinela = 3'
Assert ((Get-VixRotinaPrioridade 'outra') -eq 99) 'desconhecida = 99 (nunca preempta ninguem)'
Assert ((Test-VixRotinaPreemptiva -A 'matinal' -B 'noturna') -eq $true) 'matinal preempta noturna'
Assert ((Test-VixRotinaPreemptiva -A 'noturna' -B 'matinal') -eq $false) 'noturna NAO preempta matinal'
Assert ((Test-VixRotinaPreemptiva -A 'noturna' -B 'sentinela') -eq $true) 'noturna preempta sentinela'
Assert ((Test-VixRotinaPreemptiva -A 'matinal' -B 'matinal') -eq $false) 'empate nunca preempta'

Write-Host '=== 7. Sentinela pausa SO com metrica verificavel (+ limitacao) ==='
$sBaixa = Test-VixSentinelaPausada -QuotaPercentRestante 10
Assert ($sBaixa.pausada -eq $true) 'quota 10% pausa a sentinela'
Assert ($sBaixa.motivo -eq 'quota_percentual_abaixo_20') 'motivo quota_percentual_abaixo_20'
$sAlta = Test-VixSentinelaPausada -QuotaPercentRestante 50
Assert ($sAlta.pausada -eq $false) 'quota 50% NAO pausa'
$sExausta = Test-VixSentinelaPausada -QuotaPercentRestante $null -ExaustaoVerificada $true
Assert ($sExausta.pausada -eq $true) 'sem percentual mas com exaustao confirmada pausa'
Assert ($sExausta.motivo -eq 'exaustao_verificada_sem_percentual') 'motivo exaustao_verificada_sem_percentual'
Assert (('' + $sExausta.limitacao).Length -gt 20) 'limitacao documentada: pausa por sinal confirmado, nao por numero'
$sCega = Test-VixSentinelaPausada -QuotaPercentRestante $null -ExaustaoVerificada $false
Assert ($sCega.pausada -eq $false) 'sem metrica e sem exaustao: SEM auto-pause (nao chuta no escuro)'
Assert (('' + $sCega.limitacao).Length -gt 20) 'limitacao documentada tambem quando nao pausa'

Write-Host '=== 8. Teto PAYG ausente/invalido = estourado (fail-closed) ==='
$oldTeto = [Environment]::GetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', 'Process')
try {
    [Environment]::SetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', '5000', 'Process')
    Assert ((Get-VixPaygTetoDiario) -eq 5000) 'teto 5000 lido do ambiente (so env, nunca arquivo)'
    Assert ((Test-VixPaygTetoEstourado -GastoDia 4999) -eq $false) 'gasto abaixo do teto nao estoura'
    Assert ((Test-VixPaygTetoEstourado -GastoDia 5000) -eq $true) 'gasto no teto estoura'
    [Environment]::SetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', 'abc', 'Process')
    Assert ((Get-VixPaygTetoDiario) -eq 0) 'teto invalido vale 0 (sem default permissivo)'
    Assert ((Test-VixPaygTetoEstourado -GastoDia 0) -eq $true) 'teto invalido com gasto zero JA estoura (fail-closed)'
    [Environment]::SetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', $null, 'Process')
    $tetoFora = Get-VixPaygTetoDiario
    if ($tetoFora -le 0) {
        Assert ((Test-VixPaygTetoEstourado -GastoDia 0) -eq $true) 'teto ausente com gasto zero JA estoura (fail-closed)'
    } else {
        Write-Host ('  AVISO teto vindo de User/Machine=' + $tetoFora + '; default ausente nao testavel aqui')
    }
} finally {
    [Environment]::SetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', $oldTeto, 'Process')
}
$dTeto = Get-VixFailoverDecisao -Classe 'quota-exhausted' -TentativasMesmoRecurso 1 -TemFallbackElegivel $true -PaygTetoEstourado $true
Assert ($dTeto -eq 'fail-closed') 'teto PAYG estourado fecha mesmo com fallback (nunca fura o teto)'
Assert ((Test-VixContinuidadePermitida -TemFallbackElegivel $true -PaygTetoEstourado $false) -eq $true) 'continuidade so com fallback E teto integro'
Assert ((Test-VixContinuidadePermitida -TemFallbackElegivel $false -PaygTetoEstourado $false) -eq $false) 'sem fallback nao ha continuidade'
Assert ((Get-VixBacklogMotivo -TemFallbackElegivel $true -PaygTetoEstourado $true -Classe 'quota-exhausted') -eq 'teto_payg_diario') 'motivo do backlog aponta o teto'

Write-Host '=== 9. Backlog so fecha com submit confirmado ==='
Assert ((Test-VixBacklogPodeFechar -SubmitConfirmado $false) -eq $false) 'sem submit confirmado o backlog NAO fecha'
Assert ((Test-VixBacklogPodeFechar -SubmitConfirmado $true) -eq $true) 'com submit confirmado o backlog fecha'

Write-Host '=== 10. Worker: painel_fresco + feed_fresco + motivo ja observaveis ==='
$wkPath = Join-Path (Split-Path $scriptDir -Parent) 'api\src\worker.js'
$wk = Get-Content $wkPath -Raw -Encoding UTF8
Assert ($wk -match 'painel_fresco: _painelFresco') 'health publico expoe painel_fresco'
Assert ($wk -match 'feed_fresco: _feedFresco') 'health publico expoe feed_fresco'
Assert ($wk -match 'cvm_fonte_motivo') 'health publico expoe motivo (cvm_fonte_motivo)'
Assert ($wk -match 'checks\.painel_fresco') 'health admin expoe checks.painel_fresco'
foreach ($campo in @('painel_fresco: _painelFresco', 'feed_fresco: _feedFresco', 'cvm_fonte_motivo')) {
    $ach = @(Select-String -Path $wkPath -Pattern ([regex]::Escape($campo)) -SimpleMatch:$false)
    $linhas = @($ach | ForEach-Object { $_.LineNumber }) -join ','
    Write-Host ('  INFO ' + $campo + ' em worker.js linha(s): ' + $linhas)
}

Write-Host '=== 11. Sintaxe: arquivos do MVA continuam parseaveis + ASCII puro ==='
foreach ($f in @('lib\vixradar-llm-provider.ps1', 'run_vixradar_varredura.ps1', 'monitor-tasks.ps1')) {
    $toks = $null; $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir $f), [ref]$toks, [ref]$errs)
    $n = @($errs).Count
    Assert ($n -eq 0) ($f + ': 0 erro de parse (achados=' + $n + ')')
}
$bytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
$nAscii = 0; foreach ($b in $bytes) { if ($b -gt 127) { $nAscii++ } }
Assert ($nAscii -eq 0) ('este teste e ASCII puro (bytes>127=' + $nAscii + ')')
$temBom = ($bytes.Count -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
Assert (-not $temBom) 'este teste nao tem BOM'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
