# vixradar-llm-provider.ps1 - config unica de provider de LLM das rotinas do VIX Radar.
#
# CLAUDE-FREE-MIGRATION (2026-09-04): Claude deixou de ser infraestrutura operacional.
# O operador nao tem mais assinatura paga (plano FREE) e PAYG Anthropic e NAO AUTORIZADO.
# Este arquivo e a unica fonte da decisao de provider. Nenhuma rotina LLM roda sem passar
# por aqui. Esta lib NAO chama claude e NAO le credencial nenhuma: so decide e bloqueia.
#
# Variavel de ambiente (escopo User, nunca versionada):
#   VIXRADAR_LLM_PROVIDER = none           (padrao) rotinas LLM BLOQUEADO_SEM_PROVIDER
#                          | claude-subscription assinatura Claude Code Pro, sem API paga
#                          | claude-manual Claude so com -ForceClaude explicito (operador)
#                          | openrouter            permitido com adapter habilitado
#                          | codex                 permitido com Codex CLI autenticado
#                          | deepseek              reservado, bloqueado
#
# Exit canonico do bloqueio: 86 ($VixLlmBloqueadoExit). Nao colide com o mapa 0-8 do
# monitor nem com os exits 1/2/3/4/5/7/8 das rotinas. Linha canonica de log:
#   BLOQUEADO_SEM_PROVIDER provider=<v> exit=86 gatilho=<script> motivo=<por que>
#
# Contrato das funcoes:
#   Get-VixLlmProvider                -> 'none'|'claude-subscription'|'claude-manual'|'deepseek'|'openrouter'|'codex'
#   Set-VixLlmForceClaude [switch]    -> registra forca manual no escopo do script
#   Test-VixLlmPermiteClaude [-ForceClaude] -> bool; caminho Claude manual
#   Test-VixLlmProviderPermiteRotina        -> bool; decisao canonica do motor
#   Test-VixLlmGateViolacao                 -> bool; classifica 9006 no monitor
#   Get-VixLlmBloqueadoMsg [Gatilho]  -> string canonica (para o Write-Log do chamador)
#   Stop-VixLlmBloqueado [Gatilho]    -> imprime a linha canonica e exit 86 (backstop)
#
# PowerShell 5.1, ASCII puro, sem dependencia de rede nem de credencial.

$VixLlmBloqueadoExit = 86
$VixLlmSentinel      = 'BLOQUEADO_SEM_PROVIDER'

# Estado do escopo do script que dot-source esta lib. Cada driver (.ps1) tem o proprio
# escopo; o flag de forca manual vale so para aquela execucao, nunca para o scheduler.
# As libs auth/ambient dot-source este arquivo e compartilham o mesmo escopo do driver.
# Inicializacao idempotente: auth/ambient re-dot-source este arquivo no mesmo escopo do
# driver (cada um carrega a lib por cima), e um re-carregamento NAO pode apagar o flag de
# forca que o operador ja registrou na linha de comando. So inicializa quando vazio.
if (-not $script:VixLlmForceClaude) { $script:VixLlmForceClaude = $false }
if ($null -eq $script:VixLlmMotivo)  { $script:VixLlmMotivo      = $null }

function Get-VixLlmProvider {
    $v = [Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'User') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'Machine') }
    if (-not $v) { $v = 'none' }
    return (('' + $v).Trim().ToLowerInvariant())
}

function Set-VixLlmForceClaude {
    param([switch]$ForceClaude)
    if ($ForceClaude) { $script:VixLlmForceClaude = $true }
    return $script:VixLlmForceClaude
}

function Test-VixLlmPermiteClaude {
    # Retorna $true SOMENTE quando o operador forcou o caminho manual explicito
    # (provider 'claude-manual' E -ForceClaude na linha de comando). Scheduler nunca
    # passa -ForceClaude, entao provider 'none'/'claude-manual'/'deepseek'/'openrouter'
    # bloqueiam aqui com exit 86 antes de qualquer auth ou chamada a claude.
    param([switch]$ForceClaude)
    if ($ForceClaude) { $script:VixLlmForceClaude = $true }
    $provider = Get-VixLlmProvider
    if ($provider -eq 'claude-subscription') {
        $script:VixLlmMotivo = $null
        return $true
    }
    if ($provider -eq 'claude-manual' -and $script:VixLlmForceClaude) {
        $script:VixLlmMotivo = $null
        return $true
    }
    if ($provider -eq 'none') {
        $script:VixLlmMotivo = 'provider nao configurado (VIXRADAR_LLM_PROVIDER ausente ou none)'
    } elseif ($provider -eq 'claude-manual') {
        $script:VixLlmMotivo = 'Claude manual exige -ForceClaude explicito do operador (scheduler nunca passa)'
    } else {
        $script:VixLlmMotivo = ('provider ' + $provider + ' reservado para Fase B, motor ainda nao migrado')
    }
    return $false
}

function Test-VixLlmProviderPermiteRotina {
    # Decisao unica para qualquer rotina LLM. OpenRouter e permitido somente quando o
    # adapter que o motor despacha esta habilitado. O monitor recebe a mesma condicao,
    # sem reinterpretar provider como se fosse o caminho Claude legado.
    param(
        [switch]$ForceClaude,
        [bool]$OpenRouterAdapterHabilitado = $false,
        [bool]$CodexAdapterHabilitado = $false
    )
    $provider = Get-VixLlmProvider
    if ($provider -eq 'openrouter') {
        if ($OpenRouterAdapterHabilitado) {
            $script:VixLlmMotivo = $null
            return $true
        }
        $script:VixLlmMotivo = 'provider openrouter configurado sem adapter habilitado'
        return $false
    }
    if ($provider -eq 'codex') {
        if ($CodexAdapterHabilitado) {
            $script:VixLlmMotivo = $null
            return $true
        }
        $script:VixLlmMotivo = 'provider codex configurado sem Codex CLI habilitado'
        return $false
    }
    return (Test-VixLlmPermiteClaude -ForceClaude:$ForceClaude)
}

function Test-VixLlmGateViolacao {
    # Exit 86 e o unico termino esperado de uma rotina LLM cujo provider efetivo esta
    # bloqueado. Codigos benignos preservam os casos deterministas, como sentinela sem alvo.
    param(
        [bool]$ProviderBloqueado,
        [int]$ExitCode,
        [int[]]$BenignCodes = @()
    )
    return ($ProviderBloqueado -and $ExitCode -ne $VixLlmBloqueadoExit -and $ExitCode -notin $BenignCodes)
}

function Get-VixLlmBloqueadoMsg {
    param([string]$Gatilho = '')
    $provider = Get-VixLlmProvider
    $motivo = $script:VixLlmMotivo
    if (-not $motivo) { $motivo = 'forca manual ausente ou provider nao habilitado' }
    return ($VixLlmSentinel + ' provider=' + $provider + ' exit=' + $VixLlmBloqueadoExit + ' gatilho=' + $Gatilho + ' motivo=' + $motivo)
}

function Stop-VixLlmBloqueado {
    # Backstop para libs (auth/ambient) e scripts de diagnostico. O driver normal usa
    # Get-VixLlmBloqueadoMsg no proprio Write-Log e sai com o mesmo exit; esta funcao e
    # para o caso em que o bloqueio precisaria acontecer dentro de uma lib sem Write-Log.
    param([string]$Gatilho = 'lib')
    Write-Host (Get-VixLlmBloqueadoMsg $Gatilho)
    # Purga do bloco de ambiente DESTE processo (nunca o registro User): em ramo bloqueado
    # nenhuma chave pode vazar para um claude.exe filho acidental. O registro do operador
    # nao e tocado - VIXRADAR_* e configuracao legitima dele para uso manual/advisory.
    Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\VIXRADAR_ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\VIXRADAR_ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', '', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', '', 'Process')
    exit $VixLlmBloqueadoExit
}

# MVA-FAILOVER1: classificacao provider-agnostic de falha de lote, sem rede e sem segredo.
#
# Contrato (provado por scripts/test-mva-failover.ps1):
#   Get-VixFailoverClasse -> 'quota-exhausted' | 'transient' | 'parse-content' | 'duro'
#   1. quota-exhausted (session-limit, quota, credito esgotado) = failover IMEDIATO,
#      zero retry no mesmo recurso. Corpo manda sobre o status: 429 com texto de
#      limite de sessao e quota, nao transient.
#   2. transient (timeout, 5xx retryable, erro de transporte status 0, 408/429 sem
#      texto de quota) = retry bounded, no maximo 3 tentativas no mesmo recurso,
#      com backoff. Get-VixMvaBackoffSegundos devolve 0/5/20 e trava em 3.
#   3. parse-content (2xx vazio/malformado, 400/422, erro de parse) = NUNCA failover
#      automatico. Vira falha dura registrada com motivo, sem trocar de modelo.
#   4. duro (401/403/404 e demais 4xx sem texto de quota) = sem retry, sem failover.
#
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue.
$VixFailoverMaxTransientTentativas = 3
$VixFailoverQuotaRegex = '(?i)(session.?limit|hit your.*limit|weekly limit|quota|quota.?exhausted|exhausted|insufficient|credit balance|credit.*too low|out of credit|billing.*limit|rate.?limit.*exceed.*quota|quota.*exceed)'
$VixFailoverParseRegex = '(?i)(empty.?result|sem choices|malformad|parse|invalid.?json|unexpected token|empty response|sem conteudo|no content)'

function Get-VixFailoverClasse {
    param(
        [int]$Status = 0,
        [string]$Corpo = '',
        [bool]$RespostaOk = $false
    )
    $texto = '' + $Corpo
    if ($texto -match $VixFailoverQuotaRegex) { return 'quota-exhausted' }
    if ($Status -eq 402) {
        if ($texto -match '(?i)(credit|quota|saldo|afford|max_tokens)') { return 'quota-exhausted' }
        return 'duro'
    }
    if ($RespostaOk) {
        if ($texto -match $VixFailoverParseRegex) { return 'parse-content' }
        if ([string]::IsNullOrWhiteSpace($texto)) { return 'parse-content' }
        return 'duro'
    }
    if ($Status -eq 0) { return 'transient' }
    if ($Status -eq 408 -or $Status -eq 429) { return 'transient' }
    if ($Status -ge 500 -and $Status -le 599) { return 'transient' }
    if ($Status -eq 400 -or $Status -eq 422) { return 'parse-content' }
    return 'duro'
}

function Get-VixMvaBackoffSegundos {
    # Backoff bounded do MVA: tentativa 1 = 0s, 2 = 5s, 3 = 20s. Acima de 3, trava
    # no ultimo (o chamador nao deve passar de 3 tentativas no mesmo recurso).
    param([int]$Tentativa = 1)
    if ($Tentativa -le 1) { return 0 }
    if ($Tentativa -eq 2) { return 5 }
    return 20
}

function Get-VixFailoverDecisao {
    # Decisao unica de roteamento pos-falha. TemFallbackElegivel = fallback JA
    # configurado e autorizado (nunca inventado aqui). PaygTetoEstourado = teto
    # diario atingido ou ausente (fail-closed). Retorna 'failover' | 'retry' |
    # 'fail-closed'. Parse-content e duro NUNCA viram 'failover'.
    param(
        [Parameter(Mandatory)][string]$Classe,
        [int]$TentativasMesmoRecurso = 1,
        [bool]$TemFallbackElegivel = $false,
        [bool]$PaygTetoEstourado = $true
    )
    if ($Classe -eq 'parse-content') { return 'fail-closed' }
    if ($Classe -eq 'duro') { return 'fail-closed' }
    if ($PaygTetoEstourado) { return 'fail-closed' }
    if ($Classe -eq 'quota-exhausted') {
        if ($TemFallbackElegivel) { return 'failover' }
        return 'fail-closed'
    }
    if ($Classe -eq 'transient') {
        if ($TentativasMesmoRecurso -lt $VixFailoverMaxTransientTentativas) { return 'retry' }
        if ($TemFallbackElegivel) { return 'failover' }
        return 'fail-closed'
    }
    return 'fail-closed'
}

# MVA-PRIORIDADE1: MATINAL sobre NOTURNA sobre SENTINELA, provider-agnostic.
# Numeros fixos: matinal=1, noturna=2, sentinela=3, resto=99. A rotina de menor
# numero preempta a de maior; empate nunca preempta.
function Get-VixRotinaPrioridade {
    param([string]$Rotina = '')
    $r = ('' + $Rotina).Trim().ToLowerInvariant()
    if ($r -eq 'matinal' -or $r -like 'vixradar-matinal*') { return 1 }
    if ($r -eq 'noturna' -or $r -eq 'noturno' -or $r -like 'vixradar-noturno*') { return 2 }
    if ($r -eq 'sentinela' -or $r -like 'vixradar-sentinela*') { return 3 }
    return 99
}

function Test-VixRotinaPreemptiva {
    param([string]$A = '', [string]$B = '')
    return ((Get-VixRotinaPrioridade $A) -lt (Get-VixRotinaPrioridade $B))
}

# MVA-PAYG1: teto diario PAYG env-only, fail-closed, sem default permissivo.
# VIXRADAR_TETO_PAYG_DIARIO vive so em ambiente (Process/User/Machine), nunca em
# arquivo versionado e nunca no wrangler.toml. Ausente ou invalido = estourado
# (bloqueia continuidade PAYG em vez de liberar sem teto).
function Get-VixPaygTetoDiario {
    $v = [Environment]::GetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', 'User') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable('VIXRADAR_TETO_PAYG_DIARIO', 'Machine') }
    $n = [int64]0
    if ($v -and [int64]::TryParse(('' + $v).Trim(), [ref]$n) -and $n -gt 0) { return $n }
    return [int64]0
}

function Test-VixPaygTetoEstourado {
    param([int64]$GastoDia = 0)
    $teto = Get-VixPaygTetoDiario
    if ($teto -le 0) { return $true }
    return ($GastoDia -ge $teto)
}

# MVA-SAFETY1 (gate de continuidade): continuidade so com fallback JA configurado
# e autorizado E teto PAYG integro. Sem fallback elegivel, FAIL CLOSED: itens ficam
# no backlog, motivo operacional exato registrado, zero retry artificial. Nunca
# criar credencial, habilitar billing, furar o teto ou fabricar disponibilidade.
function Test-VixContinuidadePermitida {
    param(
        [bool]$TemFallbackElegivel = $false,
        [bool]$PaygTetoEstourado = $true
    )
    if (-not $TemFallbackElegivel) { return $false }
    if ($PaygTetoEstourado) { return $false }
    return $true
}

function Get-VixBacklogMotivo {
    param(
        [bool]$TemFallbackElegivel = $false,
        [bool]$PaygTetoEstourado = $false,
        [string]$Classe = ''
    )
    if ($PaygTetoEstourado) { return 'teto_payg_diario' }
    if (-not $TemFallbackElegivel) { return 'sem_fallback_elegivel' }
    if ($Classe -eq 'quota-exhausted') { return 'quota_exhausted_no_fallback' }
    if ($Classe -eq 'parse-content') { return 'parse_sem_failover' }
    return 'falha_sem_continuidade'
}

# MVA-SENTINELA1: auto-pause da sentinela abaixo de 20% SOMENTE com metrica de
# quota verificavel. Sem percentual verificavel, vale o sinal de exaustao ja
# confirmado (quota-exhausted classificado); sem nenhum dos dois, sem auto-pause.
# QuotaPercentRestante = $null quando nao ha metrica verificavel.
function Test-VixSentinelaPausada {
    param(
        $QuotaPercentRestante = $null,
        [bool]$ExaustaoVerificada = $false
    )
    $r = [pscustomobject]@{ pausada = $false; motivo = ''; limitacao = '' }
    if ($null -ne $QuotaPercentRestante) {
        $p = 0.0
        try { $p = [double]$QuotaPercentRestante } catch { $p = 0.0 }
        if ($p -lt 20.0) {
            $r.pausada = $true
            $r.motivo = 'quota_percentual_abaixo_20'
            return $r
        }
        return $r
    }
    if ($ExaustaoVerificada) {
        $r.pausada = $true
        $r.motivo = 'exaustao_verificada_sem_percentual'
        $r.limitacao = 'percentual de quota indisponivel no provedor; pausa por sinal de exaustao confirmado (session-limit/quota), nao por numero'
        return $r
    }
    $r.limitacao = 'sem metrica de quota verificavel e sem exaustao confirmada; sentinela segue sem auto-pause'
    return $r
}

# MVA-BACKLOG1: backlog so fecha com submit confirmado. SubmitConfirmado = prova
# de aceite (submit_ok gravado/relido), nunca presenca de tentativa, FIM: solto
# ou exit 0 do lote.
function Test-VixBacklogPodeFechar {
    param([bool]$SubmitConfirmado = $false)
    return ([bool]$SubmitConfirmado)
}
