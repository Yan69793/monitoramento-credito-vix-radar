# run_vixradar_noturno_claude.ps1 - wrapper da varredura NOTURNA (cauda LIGHT, seg-sex 18h05).
#
# MOTOR1 (2026-09-02): o corpo antigo (1027 linhas, fila Haiku + fila Sonnet + reserva da
# aprofundada + shadow DeepSeek) foi substituido pelo motor unico run_vixradar_varredura.ps1,
# perfil -Rotina noturno. Este arquivo existe porque o nome esta amarrado ao Task Scheduler
# (VIXRadar-Noturno), aos vigias (retry-vixradar.ps1, monitor-tasks.ps1) e aos logs
# (vixradar-noturno_<data>.log). O conteudo antigo segue no historico do git.
# -ShadowDeepSeek foi descontinuado (piloto de 24/08); aceito e ignorado com aviso.
param(
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido,
    [switch]$ShadowDeepSeek,
    [switch]$ForceClaude
)
$ErrorActionPreference = 'Continue'
if ($ShadowDeepSeek) { Write-Host 'AVISO: -ShadowDeepSeek descontinuado no MOTOR1, ignorado.' }
# PROVIDER-SPLIT1 (12/09/2026): a noturna e o trabalho bruto e nao assistido (104 emissores,
# madrugada, sem ninguem olhando). Ela sai pelo OpenRouter justamente para NAO consumir a cota
# da assinatura Claude Code Pro, que fica inteira para o uso manual de dia. Motivo medido em
# 12/09: a assinatura bateu em "session limit" as 19h e a matinal morreu com exit 5 antes disso.
# Get-VixLlmProvider le o escopo Process ANTES do User, entao este override vale so para ESTA
# execucao: matinal, sentinela, verificacao e agenda seguem no provider User.
# O desvio so acontece com SALDO MEDIDO no OpenRouter. A conta e pre-paga e ficou zerada
# (restante -0,20 USD em 12/09): sem este guarda cada lote vira DEGRADADO_402 e a noite fecha
# INCONCLUSIVO, que e PIOR que consumir cota. Falha de medicao tambem cai no provider User.
# -ForceClaude preserva o escape manual para quem pedir Claude na noturna.
if (-not $ForceClaude) {
    $libAdapter = Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1'
    $destino = 'claude-subscription'
    $motivoProvider = ''
    if (-not (Test-Path $libAdapter)) {
        $motivoProvider = ('adapter ausente: ' + $libAdapter)
    } else {
        . $libAdapter
        $saldo = Get-VixOpenRouterSaldo
        if ($saldo.ok) {
            $destino = 'openrouter'
            $motivoProvider = $saldo.motivo
        } else {
            $motivoProvider = $saldo.motivo
        }
    }
    $env:VIXRADAR_LLM_PROVIDER = $destino
    Write-Host ('PROVIDER-SPLIT1: noturna em ' + $destino + ' (' + $motivoProvider + ')')
}
$engine = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
if (-not (Test-Path $engine)) { Write-Host ('ERRO: motor ausente ' + $engine); exit 1 }
& $engine -Rotina noturno -Force:$Force -DryRun:$DryRun -MaxEmissores $MaxEmissores -SimularTokenVencido:$SimularTokenVencido -ForceClaude:$ForceClaude
exit $LASTEXITCODE
