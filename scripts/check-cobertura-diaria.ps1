# check-cobertura-diaria.ps1 - leitura do controle diario de verificacao por emissor (COBDIARIA1).
#
# Le logs\routines\cobertura_diaria_<data>.json, compara com o universo do plano gravado pelas
# rotinas e diz, por emissor, quem foi verificado hoje com evidencia do dia, quem esta pendente e
# qual o proximo passo da cascata (recoleta, IA primaria, Claude como ultimo recurso, ou
# INSUFICIENCIA). Nunca chama IA, nunca submete, nunca alerta: o alerta de fechamento sai da
# propria noturna, que tem a routine_key. Escreve so o relatorio local (DRYRUN_ com -DryRun).
#
# Uso:
#   pwsh -NoProfile -File scripts\check-cobertura-diaria.ps1                 # hoje, parcial
#   pwsh -NoProfile -File scripts\check-cobertura-diaria.ps1 -Data 20261014 -Fechamento -DryRun
# Exit: 0 = N/N verificados; 10 = parcial; 20 = fechamento com incidente critico.
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue, exit (pode ir para o Agendador).

param(
    [string]$Data = '',
    [switch]$Fechamento,
    [switch]$DryRun,
    [string]$LogDir = ''
)

$ErrorActionPreference = 'Continue'
$ScriptsDir = $PSScriptRoot
if (-not $LogDir) { $LogDir = Join-Path (Split-Path $ScriptsDir -Parent) 'logs\routines' }
if (-not $Data) { $Data = Get-Date -Format 'yyyyMMdd' }

. (Join-Path $ScriptsDir 'lib\vixradar-cobertura.ps1')
. (Join-Path $ScriptsDir 'lib\vixradar-cobertura-diaria.ps1')
. (Join-Path $ScriptsDir 'lib\vixradar-custo.ps1')

function Get-VixEnvRotina([string]$Nome) {
    $v = [Environment]::GetEnvironmentVariable($Nome, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Nome, 'User') }
    return ('' + $v).Trim()
}

# Capacidade medida, nunca constante: envelope da classe no historico do provedor ativo e saldo do
# circuito do dia. Sem amostra, custo 0 => o proximo passo sai INSUFICIENCIA (fail-closed).
$provider = Get-VixEnvRotina 'VIXRADAR_LLM_PROVIDER'
$cap = @{ PrimarioDisponivel = $false; OrcamentoPrimario = [int64]0; CustoBarato = [int64]0; CustoFull = [int64]0; ClaudeHabilitado = $false; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64]0 }
try {
    $mB = Get-VixModeloLoteClasse -Amostras @(Get-VixHistoricoCustoClasse $LogDir $provider 'BARATO') -DefaultEmissor 0
    $mF = Get-VixModeloLoteClasse -Amostras @(@(Get-VixHistoricoCustoClasse $LogDir $provider 'FULL') + @(Get-VixHistoricoCustoClasse $LogDir $provider 'ESCALADA')) -DefaultEmissor 0
    $cap.CustoBarato = [int64](Get-VixEstimativaLoteClasse -Modelo $mB -Emissores 1)
    $cap.CustoFull = [int64](Get-VixEstimativaLoteClasse -Modelo $mF -Emissores 1)
    $cfgC = Get-VixCustoConfig $LogDir
    $custo = Get-VixCustoDia $LogDir $Data $cfgC
    $cap.PrimarioDisponivel = ($provider -and $provider -ne 'none' -and -not $custo.circuito_aberto)
    $cap.OrcamentoPrimario = [int64](Get-VixCapEfetivo ([int64]$cfgC.TETO_DIA) $custo $cfgC 0)
    $cd = Get-VixCobDiariaConfig $LogDir
    $cap.ClaudeHabilitado = ((Get-VixEnvRotina 'VIXRADAR_COBERTURA_FALLBACK_CLAUDE') -eq '1' -and [int64]$cd.CLAUDE_FALLBACK_DIA -gt 0)
    $cap.OrcamentoClaude = [int64]$cd.CLAUDE_FALLBACK_DIA
} catch { }

$r = Invoke-VixCobDiariaFechamento -LogDir $LogDir -DateTag $Data -Fechamento:$Fechamento -DryRun:$DryRun -Capacidade $cap
Write-Output $r.Linha
Write-Output ($r.Relatorio | ConvertTo-Json -Depth 6 -Compress)
exit $r.Exit
