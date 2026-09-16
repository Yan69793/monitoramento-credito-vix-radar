# test-dedup-causa-severidade.ps1 - prova do dedup por rotina+causa+severidade (C4 / NOTIFYDEDUP2).
#
# O dedup NAO vive no PowerShell: vive no Worker (api/src/worker.js, action=notificar_rotina),
# dentro do KV, e nao ha como exercita-lo aqui sem rede. Esta suite usa um MODELO LOCAL fiel
# dessas quatro linhas do Worker, lido no codigo-fonte:
#   21134  const _nrRotina = String(body.rotina || "rotina").slice(0, 40)
#   21140  const _nrDupKey = "rotina_alerta:" + _nrRotina.toLowerCase() + ":" + <dia ISO>
#   21142  chave ja no KV  -> {ok:true, enviado:false, dedup:true}   (nenhum e-mail)
#   21145  senao           -> envia e grava a chave com TTL 86400    (1 por dia)
# O modelo roda em memoria: nenhum POST, nenhum e-mail, nenhum KV real.
# Nenhum e-mail, nenhum POST real. ASCII puro, PS 5.1. Exit 0 = todos os asserts OK.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$script:Linhas = @()
function Write-Log([string]$m) { $script:Linhas += $m }

# ---------------------------------------------------------------- modelo do Worker
$script:KV = @{}
$script:Emails = @()
$script:Dia = '2026-09-15'
$script:SemCausa = $false   # $true = modelo do codigo ANTES do C4 (chave rotina+dia)

function Invoke-WorkerModelo {
    param([string]$BodyJson)
    $b = $BodyJson | ConvertFrom-Json
    if (-not $b.routine_key) { return [pscustomobject]@{ ok = $false; erro = 'Acesso negado.' } }
    $rotina = [string]$b.rotina
    if ($rotina.Length -gt 40) { $rotina = $rotina.Substring(0, 40) }        # worker.js:21134
    if ($script:SemCausa) { $rotina = ($rotina -split ':')[0] }             # :21134 sem o C4
    $chave = 'rotina_alerta:' + $rotina.ToLower() + ':' + $script:Dia       # worker.js:21140
    if ($script:KV.ContainsKey($chave)) {                                   # worker.js:21142
        return [pscustomobject]@{ ok = $true; enviado = $false; dedup = $true }
    }
    $script:KV[$chave] = $script:Dia                                        # worker.js:21145 (TTL 86400)
    $script:Emails += $rotina
    return [pscustomobject]@{ ok = $true; enviado = $true }
}
function Invoke-RestMethod {
    param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
    return (Invoke-WorkerModelo -BodyJson ('' + $Body))
}
function Reset-Caso { $script:Linhas = @(); $script:Emails = @(); $script:KV = @{}; $script:Dia = '2026-09-15'; $script:SemCausa = $false }
function Chaves { return ((@($script:KV.Keys) | Sort-Object) -join ' | ') }

# ================================================================
Write-Host '=== 1. Duas falhas de CREDENCIAL no mesmo dia, causas diferentes ==='
Write-Host '--- 1a: ANTES do C4 (chave rotina+dia) ---'
Reset-Caso
$script:SemCausa = $true
$r1 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'ALERTA_AUTH: nenhuma credencial Claude antes do primeiro lote' -RoutineKey 'k-de-teste' -Causa 'sem_credencial' -Severidade 'critico'
$r2 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'ALERTA_AUTH: limite de sessao da assinatura (cota) no lote light-6' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
Assert ($r1 -eq $true) ('1a: 1a falha enviada (retorno=' + $r1 + ')')
Assert ($r2 -eq $false) ('1a: 2a falha NAO enviada - engolida pelo dedup rotina+dia (retorno=' + $r2 + ')')
Assert ($script:Emails.Count -eq 1) ('1a: 1 e-mail no dia (obtido ' + $script:Emails.Count + ')')
Assert (($script:Linhas -join "`n") -match 'NAO enviado, dedup') '1a: log diz "NAO enviado, dedup do Worker"'

Write-Host '--- 1b: DEPOIS do C4 (chave rotina+causa+severidade) ---'
Reset-Caso
$r3 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'ALERTA_AUTH: nenhuma credencial Claude antes do primeiro lote' -RoutineKey 'k-de-teste' -Causa 'sem_credencial' -Severidade 'critico'
$r4 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'ALERTA_AUTH: limite de sessao da assinatura (cota) no lote light-6' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
Assert ($r3 -eq $true) ('1b: 1a falha enviada (retorno=' + $r3 + ')')
Assert ($r4 -eq $true) ('1b: 2a falha TAMBEM enviada (retorno=' + $r4 + ')')
Assert ($script:Emails.Count -eq 2) ('1b: 2 e-mails no dia (obtido ' + $script:Emails.Count + ')')
Assert ($script:KV.Count -eq 2) ('1b: 2 chaves distintas no KV (' + (Chaves) + ')')
Assert ($script:Emails[0] -eq 'noturno:sem_credencial:critico' -and $script:Emails[1] -eq 'noturno:falha_auth:critico') ('1b: nomes compostos enviados (' + ($script:Emails -join ' | ') + ')')
Assert (($script:Linhas -join "`n") -match 'rotina=noturno:falha_auth:critico') '1b: log nomeia o nome efetivo usado na chave'

# ================================================================
Write-Host '=== 2. Mesma causa+severidade repetida no dia: dedup preservado (anti-spam) ==='
Reset-Caso
$s1 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'm1' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
$s2 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'm2' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
Assert ($s1 -eq $true -and $s2 -eq $false) ('2: 1o enviado, 2o dedupado (retornos=' + $s1 + ',' + $s2 + ')')
Assert ($script:Emails.Count -eq 1) ('2: 1 e-mail (obtido ' + $script:Emails.Count + ')')

# ================================================================
Write-Host '=== 3. Alerta benigno/rotineiro (sem causa): rotina+dia, comportamento historico ==='
Reset-Caso
$a1 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'aviso rotineiro' -RoutineKey 'k-de-teste'
$a2 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'aviso rotineiro' -RoutineKey 'k-de-teste'
Assert ($a1 -eq $true -and $a2 -eq $false) ('3: 1/dia mantido (retornos=' + $a1 + ',' + $a2 + ')')
Assert ($script:KV.ContainsKey('rotina_alerta:noturno:2026-09-15')) ('3: chave historica intacta (' + (Chaves) + ')')

# ================================================================
Write-Host '=== 4. Mesma causa, severidades diferentes: dois alertas ==='
Reset-Caso
$u1 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'escalou para chave paga' -RoutineKey 'k-de-teste' -Causa 'escalacao_chave_paga' -Severidade 'aviso'
$u2 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'sem contingencia' -RoutineKey 'k-de-teste' -Causa 'escalacao_chave_paga' -Severidade 'critico'
Assert ($u1 -eq $true -and $u2 -eq $true) ('4: aviso e critico sao eventos distintos (retornos=' + $u1 + ',' + $u2 + ')')
Assert ($script:Emails.Count -eq 2) ('4: 2 e-mails (obtido ' + $script:Emails.Count + ')')

# ================================================================
Write-Host '=== 5. O dedup e por DIA: mesma causa+severidade no dia seguinte volta a enviar ==='
Reset-Caso
$d1 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'm' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
$script:Dia = '2026-09-16'
$d2 = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'm' -RoutineKey 'k-de-teste' -Causa 'falha_auth' -Severidade 'critico'
Assert ($d1 -eq $true -and $d2 -eq $true) ('5: dias diferentes nao deduplicam entre si (retornos=' + $d1 + ',' + $d2 + ')')
Assert ($script:KV.Count -eq 2) ('5: uma chave por dia (' + (Chaves) + ')')

# ================================================================
Write-Host '=== 6. Inventario real de nomes: o corte de 40 chars do Worker nao colide ==='
# Nomes efetivos que o codigo de scripts/ produz hoje (Causa+Severidade dos call sites reais,
# com os valores reais de $Rotina/$RoutineId), mais os nomes nao compostos que tambem caem no
# mesmo KV. A pergunta: depois do slice(0,40) do Worker, dois nomes distintos viram a mesma chave?
$nomes = @(
    'noturno:escalacao_chave_paga:aviso', 'noturno:falha_auth:critico',
    'matinal:escalacao_chave_paga:aviso', 'matinal:falha_auth:critico',
    'verificacao-async:escalacao_chave_paga:aviso', 'verificacao-async:sem_credencial:critico', 'verificacao-async:falha_auth:critico',
    'sentinela:falha_auth:critico', 'agenda-semanal:falha_auth:critico',
    'vixradar-noturno:preflight_timeout:critico', 'vixradar-noturno:preflight_ferramentas:critico',
    'vixradar-matinal:preflight_timeout:critico', 'vixradar-matinal:preflight_ferramentas:critico',
    'vixradar-noturno:limite_sessao:aviso', 'vixradar-noturno:limite_sessao_sem_contingencia:critico',
    'vixradar-noturno:limite_sessao_fallback_desativado:critico',
    'vixradar-matinal:limite_sessao:aviso', 'vixradar-matinal:limite_sessao_sem_contingencia:critico',
    'vixradar-matinal:limite_sessao_fallback_desativado:critico',
    'retry-vixradar-noturno:sem_log:critico', 'retry-vixradar-noturno:sem_entrega:critico',
    'retry-vixradar-matinal:sem_log:critico', 'retry-vixradar-matinal:sem_entrega:critico',
    'noturno', 'matinal', 'verificacao-async', 'sentinela', 'agenda-semanal',
    'watch-health-noturno', 'watch-health-matinal', 'frescor-ingestao'
)
$chaves = @()
foreach ($n in $nomes) {
    $k = $n.ToLower()
    if ($k.Length -gt 40) { $k = $k.Substring(0, 40) }
    $chaves += $k
}
$unicas = @($chaves | Select-Object -Unique)
Assert ($unicas.Count -eq $chaves.Count) ('6a: nenhuma colisao apos o corte de 40 (' + $unicas.Count + ' unicas de ' + $chaves.Count + ')')
$cortados = @($nomes | Where-Object { $_.Length -gt 40 })
Write-Host ('  6b: teto medido - nomes com mais de 40 chars (perdem o fim da chave no Worker): ' + $cortados.Count + ' de ' + $nomes.Count)
foreach ($c in $cortados) { Write-Host ('      len=' + $c.Length + '  ' + $c + '  ->  ' + $c.ToLower().Substring(0, 40)) }

# ================================================================
Write-Host '=== 7. Borda C4: retry-vixradar.ps1 (unica classe que seguia rotina+dia) ==='
$retryPath = Join-Path $PSScriptRoot 'retry-vixradar.ps1'
$srcRetry = Get-Content -LiteralPath $retryPath -Raw -Encoding UTF8
Assert ($srcRetry -match "Send-VixRetryAlerta -Motivo \`$motivo -Causa 'sem_log' -Severidade 'critico'") '7a: ramo "rotina nao iniciou" passa causa+severidade'
Assert ($srcRetry -match "Send-VixRetryAlerta -Motivo \`$motivoFalha -Causa 'sem_entrega' -Severidade 'critico'") '7b: ramo "sem entrega apos relancamento" passa causa+severidade'
Assert ($srcRetry -match "function Send-VixRetryAlerta\(\[string\]\`$Motivo, \[string\]\`$Causa, \[string\]\`$Severidade\)") '7c: Send-VixRetryAlerta recebe causa+severidade por parametro'
Assert ($srcRetry -match "\`$rotinaAlerta = 'retry-' \+ \`$RoutineId") '7d: o nome do alerta sai de retry-<RoutineId>'
Assert ($srcRetry -match "\`$rotinaAlerta = \`$rotinaAlerta \+ ':' \+ \`$Causa \+ ':' \+ \`$Severidade") '7e: o nome composto inclui causa+severidade'
Assert ($srcRetry -match "Send-VixRoutineAlert -Rotina \`$rotinaAlerta") '7f: a lib recebe o nome composto'
Assert ($srcRetry -match "rotina = \`$rotinaAlerta") '7g: o POST direto do fallback usa o MESMO nome (composicao nao se perde sem a lib)'
$t = $null; $e = $null
[System.Management.Automation.Language.Parser]::ParseFile($retryPath, [ref]$t, [ref]$e) | Out-Null
Assert ($e.Count -eq 0) ('7h: retry-vixradar.ps1 segue com parse limpo no PS 5.1 (erros=' + $e.Count + ')')
$t2 = $null; $e2 = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1'), [ref]$t2, [ref]$e2) | Out-Null
Assert ($e2.Count -eq 0) ('7i: lib/vixradar-claude-auth.ps1 segue com parse limpo (erros=' + $e2.Count + ')')

# ================================================================
Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
