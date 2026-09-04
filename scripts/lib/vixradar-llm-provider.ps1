# vixradar-llm-provider.ps1 - config unica de provider de LLM das rotinas do VIX Radar.
#
# CLAUDE-FREE-MIGRATION (2026-09-04): Claude deixou de ser infraestrutura operacional.
# O operador nao tem mais assinatura paga (plano FREE) e PAYG Anthropic e NAO AUTORIZADO.
# Este arquivo e a unica fonte da decisao de provider. Nenhuma rotina LLM roda sem passar
# por aqui. Esta lib NAO chama claude e NAO le credencial nenhuma: so decide e bloqueia.
#
# Variavel de ambiente (escopo User, nunca versionada):
#   VIXRADAR_LLM_PROVIDER = none           (padrao) rotinas LLM BLOQUEADO_SEM_PROVIDER
#                          | claude-manual Claude so com -ForceClaude explicito (operador)
#                          | deepseek | openrouter   reservado Fase B, ainda BLOQUEADO
#
# Exit canonico do bloqueio: 86 ($VixLlmBloqueadoExit). Nao colide com o mapa 0-8 do
# monitor nem com os exits 1/2/3/4/5/7/8 das rotinas. Linha canonica de log:
#   BLOQUEADO_SEM_PROVIDER provider=<v> exit=86 gatilho=<script> motivo=<por que>
#
# Contrato das funcoes:
#   Get-VixLlmProvider                -> 'none'|'claude-manual'|'deepseek'|'openrouter'
#   Set-VixLlmForceClaude [switch]    -> registra forca manual no escopo do script
#   Test-VixLlmPermiteClaude [-ForceClaude] -> bool; registra -ForceClaude se vier
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
