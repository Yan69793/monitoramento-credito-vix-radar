# run_vixradar_varredura.ps1 - motor unico das varreduras do VIX Radar (Task Scheduler + claude -p).
#
# MOTOR1 (2026-09-02, decisao do operador). Substitui o corpo de run_vixradar_noturno_claude.ps1
# e run_vixradar_matinal_claude.ps1, que viraram wrappers de uma linha. Um so motor, dois perfis:
#   -Rotina matinal : dona do TOPO. Plano modo=matinal top_n=20, tudo que nao for SKIP vai para a
#                     fila Sonnet FULL (lotes de 4, prompt matinal-batch-sonnet.md, 3 buscas).
#   -Rotina noturno : dona da CAUDA. Plano modo=noturno, tudo que nao for SKIP vai para a fila
#                     Haiku LIGHT (lotes de 15, prompt noturno-batch-haiku.md). Sem fila Sonnet,
#                     sem reserva de aprofundada, cap inteiro na cauda. O topo ja veio SKIP do
#                     Worker por credito de analise do dia (CREDITODIA1, v4.9.234).
# O que mudou em relacao aos dois scripts antigos, tudo medido na auditoria de 01/09 (nota 99):
#   - ledger OK| de 6 campos com <status> SKIP|ANALISADO|DEFERIDO e linha FIM: com analisados=,
#     skip=, deferidos=, submits_aceitos= (SUBMITOK-ENGANOSO1; guarda check-ledger-noturno.ps1);
#   - receber_analise com origem, _tier aplicado e cvm_ids_analisados do plano (CVMNOVOSDEAD1);
#   - usage do claude -p gravado nas 4 parcelas (input, output, cache_creation, cache_read) por
#     lote, regua unica em lib\vixradar-custo.ps1 (REGUA-UNICA1);
#   - cap dinamico por dia: TETO_DIA menos gasto ja feito menos reserva das outras rotinas
#     (custo-config.json), circuito aberto quando a margem some;
#   - lock de arquivo escrito ANTES da primeira chamada ao Worker, tocado a cada lote e
#     removido no fim; abandono em 30 min sem toque (a sentinela le a mesma regra);
#   - espera de ate 25 min pelo mutex da sentinela antes de montar o plano;
#   - ALERTA_AUTH quando a lib de auth escala para a chave paga (nunca silencioso);
#   - -DryRun (analisa, nunca submete, ledger DRYRUN|), -MaxEmissores N (amostra),
#     -SimularTokenVencido (so com -DryRun, prova a escalada).
# Tudo que os scripts antigos tinham de defesa foi trazido: mutex, idempotencia por ledger,
# retry parcial por emissor, silent_fail, encoding UTF-8 forcado, Write-Log com backoff,
# Start-Transcript, mcp-empty.json em arquivo, stderr por PID, auth centralizada na lib.
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue, exit obrigatorio (Task Scheduler).

param(
    [Parameter(Mandatory = $true)][ValidateSet('noturno', 'matinal')][string]$Rotina,
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido,
    [switch]$ForceClaude,
    # COBFALLBACK1 (2026-10-14): executor do fallback Claude da cobertura diaria. Roda SO os
    # pendentes que o relatorio do dia decidiu CLAUDE_FALLBACK, pela assinatura (ProviderOverride
    # claude-subscription), dentro de CLAUDE_FALLBACK_DIA. Opt-in por
    # VIXRADAR_COBERTURA_FALLBACK_CLAUDE=1; sem ela sai 0 aqui no topo, sem log, lock, rede ou token.
    [switch]$CoberturaFallbackClaude,
    # PLANTAO1 (2026-10-19): fim de semana e feriado a matinal vira plantao (lib\vixradar-plantao.ps1).
    # -IgnorarPlantao e so para o operador forcar a varredura cheia nesses dias. -SimularData
    # (yyyy-MM-dd) so vale com -DryRun, para provar a decisao do dia sem esperar o calendario.
    [switch]$IgnorarPlantao,
    [string]$SimularData = ''
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# COBFALLBACK1: gate de inercia ANTES de qualquer efeito (transcript, arquivo de log, mcp-empty,
# mutex, rede). Mesma regra de Test-VixCobFallbackFlag (lib\vixradar-cobertura-diaria.ps1):
# Process, depois User, valor exatamente '1'. O modo so existe sobre o perfil noturno, que e o
# dono do universo do dia.
$script:VixCobFallbackModo = $false
$script:VixCobFallbackProvider = ''
if ($CoberturaFallbackClaude) {
    if ($Rotina -ne 'noturno') { try { Write-Host 'ERRO: -CoberturaFallbackClaude exige -Rotina noturno' } catch { }; exit 1 }
    $__cfFlag = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_FALLBACK_CLAUDE', 'Process')
    if (-not $__cfFlag) { $__cfFlag = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_FALLBACK_CLAUDE', 'User') }
    if (('' + $__cfFlag).Trim() -ne '1') { try { Write-Host 'COBFALLBACK_INERTE: VIXRADAR_COBERTURA_FALLBACK_CLAUDE != 1 - nada executado' } catch { }; exit 0 }
    $script:VixCobFallbackModo = $true
    $script:VixCobFallbackProvider = 'claude-subscription'
}

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$CleanupScript  = Join-Path $ProjectRoot 'scripts\cleanup-rotina-artifacts.ps1'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'
$ModelHaiku     = 'claude-haiku-4-5-20251001'
$ModelSonnet    = 'claude-sonnet-4-6'
$PauseSec       = 2
$EwsContextoCritico = 38
$LockAbandonoMin = 30
$EsperaSentinelaMaxMin = 25

if ($Rotina -eq 'noturno') {
    $Perfil = @{
        id = 'vixradar-noturno'; modo = 'noturno'; top_n = 0
        skill = (Join-Path $ScriptsDir 'noturno-batch-haiku.md'); model = $ModelHaiku; chunk = 15; ultra = $true
        tier = 'LIGHT'; provedor = 'claude-haiku-routine'; matinal = $false
        capProprio = 700000; capEscalada = 540000; meta = 500000; bootTok = 15000; unitTok = 3800
        mutex = 'Global\vixradar-noturno-v2'; prefix = 'noturno'; reservaOutrasKey = 'RESERVA_VERIFICACAO'
    }
} else {
    $Perfil = @{
        id = 'vixradar-matinal'; modo = 'matinal'; top_n = 20
        skill = (Join-Path $ScriptsDir 'matinal-batch-sonnet.md'); model = $ModelSonnet; chunk = 4; ultra = $false
        tier = 'FULL'; provedor = 'claude-sonnet-routine'; matinal = $true
        capProprio = 400000; capEscalada = 360000; meta = 300000; bootTok = 15000; unitTok = 11500
        mutex = 'Global\vixradar-matinal-v2'; prefix = 'matinal'; reservaOutrasKey = 'RESERVA_NOTURNO'
    }
}
# COBFALLBACK1: perfil proprio sobre o noturno. Log, lock, mutex, metrics e prompts com prefixo
# 'cobfallback': o ledger OK| do fallback nao se mistura com o da noturna (idempotencia), o
# metrics nao entra no TETO_DIA do primario (Get-VixCustoDia le nomes fixos) e o fallback pode
# rodar sem disputar o mutex da noturna. `origem` do submit continua $Rotina (noturno).
$RotinaArq = $Rotina
if ($script:VixCobFallbackModo) {
    $RotinaArq = 'cobfallback'
    $Perfil.id = 'vixradar-cobfallback'; $Perfil.modo = 'cobfallback'; $Perfil.prefix = 'cobfallback'
    $Perfil.mutex = 'Global\vixradar-cobfallback-v1'; $Perfil.reservaOutrasKey = ''
}
# DRYRUN-PROBE1 (10/09/2026): o probe (-DryRun) passa a usar log e lock PROPRIOS, com o PID no
# nome. Antes ele escrevia no MESMO arquivo da execucao real: 17 probes em 10/09 deixaram 15
# linhas ABORT e nenhuma INICIO no log do dia, e um lock de probe fresco bloqueava o noturno
# real por 30 min (exit 0 sem rodar nada). O nome do log e do lock da execucao REAL nao muda.
$DryRunSufixo = if ($DryRun) { '_dryrun_' + $PID } else { '' }
$LogFile     = Join-Path $LogDir ('vixradar-' + $RotinaArq + '_' + $DateTag + $DryRunSufixo + '.log')
# DRYRUN-METRICS-SOBRESCREVE1 (02/09): um so _dryrun.json por dia apagava o gasto do dry-run anterior
# (16h59 apagou os 35.619 de 12h58) e o cap dinamico lia 85k onde o dia tinha gasto 120k. Cada dry-run
# grava o proprio arquivo, com hora no nome, e Get-VixCustoDia soma todos os _dryrun*.json do dia.
$MetricsFile = Join-Path $LogDir ($Perfil.prefix + '_metrics_' + $DateTag + $(if ($DryRun) { '_dryrun_' + (Get-Date -Format 'HHmmss') } else { '' }) + '.json')
$LockFile    = Join-Path $LogDir ('vixradar-' + $RotinaArq + '_' + $DateTag + $DryRunSufixo + '.lock')
$TokenTarget = $Perfil.meta
$TokenHardCap = $Perfil.capProprio

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# PIPE1 (2026-07-28): Write-Host sob -WindowStyle Hidden quebrava o pipe do console apos
# ~28 min (ERROR_PIPE_NOT_CONNECTED). O log em arquivo ja registrou a linha.
function Write-Safe([string]$msg) { try { Write-Host $msg } catch { } }

$TranscriptFile = Join-Path $LogDir ($Perfil.prefix + '_transcript_' + $DateTag + '_' + $PID + '.txt')
try { Start-Transcript -Path $TranscriptFile -Append -Force -ErrorAction Stop } catch {
    Write-Safe "AVISO: Start-Transcript falhou ($($_.Exception.Message)) - continuando sem transcript"
}

# --mcp-config em ARQUIVO: inline perdia as aspas em execucao agendada (achado 2026-07-05).
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Safe $line
    # LOGLOCK1-REC: backoff exponencial ate 8 tentativas; fallback com PID no nome.
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                $fallbackFile = ([regex]::Replace($LogFile, '\.log$', "_fallback_$pid.log"))
                Write-Safe "FALHA Write-Log ($i tentativas), fallback: $fallbackFile - $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Safe "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

$script:AuthFailRegex = '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit|authentication_error|invalid.*(api key|token)|oauth.*(expired|invalid)|token.*(expired|invalid)|(http|status)\s*401'

# TETOPAREDE1 (04/09/2026): teto de parede COMPARTILHADO por toda espera desta execucao.
#
# O problema que ele resolve nao e uma espera longa, e a SOMA delas. A politica de 429 do
# pre-flight (INCIDENTE-FRESHNESS2, run_claude_routine.ps1) ja podia esperar ate 120 min, e
# a espera de limite de sessao por lote, abaixo, pode pedir outro tanto. Cada uma dentro do
# seu proprio teto, somadas, estouram o ExecutionTimeLimit PT4H da task e o Windows mata o
# processo no meio de um lote, sem linha FIM: e sem ledger fechado.
#
# Numeros medidos em 04/09, nao estimados: a noturna completa de 103 emissores levou 48 min
# em 01/09 (10:07:18 -> 10:55:51) e 26 min em 03/09 (09:07:18 -> 09:33:03). O comentario
# antigo de run_claude_routine.ps1 assumia "~2h de execucao", cerca de 2,5x o real. Com o
# retry das 21h30 e PT4H, o processo tem ate 01h30. Reservando 60 min para a rotina rodar
# depois de qualquer espera (o dobro da mediana medida) e 30 de margem, sobram 150 min de
# espera total, que e exatamente o teto que o plano pediu.
$script:VixInicioProcesso = (Get-Date)
$script:VixTetoParedeMin = 240   # ExecutionTimeLimit PT4H da task
$script:VixReservaRotinaMin = 60 # tempo guardado para a rotina rodar apos a ultima espera
$script:VixMargemMin = 30        # folga para housekeeping, dreno da fila e escrita do ledger

function Get-VixEsperaDisponivelMin {
    # Minutos que ainda podem ser gastos ESPERANDO, ja descontado o tempo decorrido e o que
    # a rotina precisa depois. Nunca negativo.
    $decorrido = ((Get-Date) - $script:VixInicioProcesso).TotalMinutes
    $disp = $script:VixTetoParedeMin - $decorrido - $script:VixReservaRotinaMin - $script:VixMargemMin
    if ($disp -lt 0) { return 0 }
    return $disp
}

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Achado 2026-07-08: o claude.exe pode perder a sessao e imprimir a mensagem com exit 0.
    # MOTOR1: regex ampliada para token longevo recusado (401/authentication_error/token expirado).
    $texto = ($outputLines -join "`n")
    return $texto -match $script:AuthFailRegex
}

# DRYRUN-CRASH1 (2026-09-02): o log dizia "claude CLI nao autenticado" para o que era limite
# de uso da assinatura (sessao estourada as 02:45, reset 06:10). Mensagem honesta: cita o
# trecho que casou. Categoria decide o texto do alerta, nao muda o abort.
function Get-ClaudeAuthMotivo([string[]]$outputLines) {
    $texto = ($outputLines -join "`n")
    if ($texto -match $script:AuthFailRegex) {
        $m = $Matches[0]
        if ($m -match '(?i)limit') { return ('limite de uso da assinatura atingido ("' + $m + '")') }
        if ($m -match '(?i)credit') { return ('credito da chave esgotado ("' + $m + '")') }
        return ('credencial recusada ("' + $m + '")')
    }
    return 'motivo nao identificado na saida'
}

# DRYRUN-CRASH1: $jobs.IndexOf($jr) com [ordered] estourava no binder do PowerShell 5.1
# ("Os tipos de argumento nao correspondem", PSToObjectArrayBinder). Indice por referencia.
function Get-JobIndex($jobsList, $job) {
    for ($k = 0; $k -lt $jobsList.Count; $k++) {
        if ([object]::ReferenceEquals($jobsList[$k], $job)) { return $k }
    }
    return -1
}

function Invoke-Cleanup([switch]$Aggressive) {
    if (-not (Test-Path $CleanupScript)) { return }
    try {
        if ($Aggressive) { $out = & $CleanupScript -KeepDays 7 -Aggressive } else { $out = & $CleanupScript -KeepDays 7 }
        Write-Log ('Cleanup: ' + $out)
    } catch { Write-Log ('Cleanup aviso: ' + $_.Exception.Message) }
}

function Get-RoutineKey {
    # ROTA1: hidratar do registro User SEMPRE (processo longevo herda env velho apos rotacao).
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) { return $doRegistro }
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
# LOCKIDENT1 (2026-10-09): Get-VixLockState sai deste arquivo e passa a viver em
# lib\vixradar-lock.ps1, para que o motor e o retry julguem "execucao viva" pela MESMA
# identidade (pid + inicio_utc). Ver lib\vixradar-lock.ps1.
. (Join-Path $PSScriptRoot 'lib\vixradar-lock.ps1')
if (-not (Get-Command Get-VixLockState -ErrorAction SilentlyContinue)) { Write-Safe 'ERRO: lib\vixradar-lock.ps1 ausente ou sem Get-VixLockState'; exit 1 }
# IDEMEFETIVA1 (2026-10-15): a regra de "entrega efetiva" do ledger (idempotencia, reconciliacao
# do dia) e a MESMA do retry e do monitor, carregada da lib do vigia. Sem ela o motor nao sabe
# quem ja foi entregue hoje, e adivinhar foi o que travou a noturna de 14/10: falha fechada.
. (Join-Path $PSScriptRoot 'lib\vixradar-watchdog.ps1')
foreach ($fn in @('Get-VixIdempotenciaEntregas', 'Get-VixReconciliacaoUniverso', 'Get-VixLedgerLinhaEntrega', 'Get-VixLogDiaLinhas')) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Safe ('ERRO: funcao ' + $fn + ' ausente em lib\vixradar-watchdog.ps1'); exit 1 }
}
. (Join-Path $PSScriptRoot 'lib\vixradar-profundidade.ps1')
# COBERTURA-13OUT1 (2026-10-13): contexto enxuto do Codex, consumo medido do JSONL, orcamento
# por emissor, disjuntor de provedor, resultado OK/PARCIAL/FALHA e fila pendente persistente.
. (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1')
# COBDIARIA1 (2026-10-14): controle diario de verificacao por emissor (ledger com evidencia do dia,
# fechamento com incidente). Duas fases, por decisao de seguranca: SOMBRA (padrao) so grava o
# ledger e o relatorio local; ATIVO (VIXRADAR_COBERTURA_DIARIA=1) tambem poe o obrigatorio do dia
# na frente da fila, reserva a matinal contra noturna que atravessa a meia-noite e alerta o
# incidente de fechamento. Lib ausente nao derruba a rotina: so desliga o controle.
$script:VixCobDiariaOk = $false
$script:VixCobDiariaAtivo = $false
try {
    . (Join-Path $PSScriptRoot 'lib\vixradar-cobertura-diaria.ps1')
    $script:VixCobDiariaOk = ($null -ne (Get-Command 'Register-VixCobDiaria' -ErrorAction SilentlyContinue))
    $__flagCobD = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', 'Process')
    if (-not $__flagCobD) { $__flagCobD = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', 'User') }
    $script:VixCobDiariaAtivo = ($script:VixCobDiariaOk -and (('' + $__flagCobD).Trim() -eq '1'))
} catch { $script:VixCobDiariaOk = $false }
$script:VixCobDiariaObrig = @{}
# COBFALLBACK1: sem a lib o executor nao tem regra de saldo, alvo nem incidente - nao roda.
if ($script:VixCobFallbackModo -and -not ($script:VixCobDiariaOk -and ($null -ne (Get-Command 'Invoke-VixCobFallbackPreparo' -ErrorAction SilentlyContinue)))) {
    Write-Log 'ERRO: -CoberturaFallbackClaude sem lib\vixradar-cobertura-diaria.ps1 completa (Invoke-VixCobFallbackPreparo) - nada executado'
    exit 1
}
foreach ($fn in @('Get-VixCodexArgsBase', 'Get-VixCodexPreambulo', 'Get-VixCodexUsageJsonl', 'ConvertTo-VixParcelasCodex', 'Get-VixCustoPorEmissor', 'Get-VixEmissoresQueCabem', 'Get-VixHistoricoCustoPorEmissor', 'Get-VixClasseFalhaProvider', 'New-VixDisjuntorProvider', 'Update-VixDisjuntorProvider', 'Get-VixResultadoRotina', 'Add-VixFilaPendente', 'Remove-VixFilaPendente', 'Read-VixFilaPendente', 'Select-VixOrdemComPendentes', 'Get-VixEscaladaDecisao', 'Select-VixEscaladaOrdenada', 'Test-VixEscaladaRetem', 'Test-VixAnaliseConcluida', 'Get-VixClasseLote', 'Get-VixHistoricoCustoClasse', 'Get-VixModeloLoteClasse', 'Get-VixEstimativaLoteClasse', 'Get-VixEstimativaClasseResumo', 'Get-VixEmissoresQueCabemModelo', 'Read-VixRotacaoCiclo', 'Write-VixRotacaoCiclo', 'Invoke-VixRotacaoSob', 'Select-VixRotacaoCandidatos', 'Update-VixRotacaoCiclo', 'Test-VixCoberturaReconciliacao', 'Test-VixReconciliacaoExecucao')) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Safe ('ERRO: funcao ' + $fn + ' ausente em lib\vixradar-cobertura.ps1'); exit 1 }
}
# MVA-WIRING1 (2026-09-16): import EXPLICITO da lib de provider. O motor JA consome funcoes
# dela direto (Get-VixLlmProvider nas linhas 995/996/1126, Test-VixLlmProviderPermiteRotina na
# 999, Get-VixLlmBloqueadoMsg na 1004) e ate hoje so a carregava de carona pelo dot-source de
# vixradar-claude-auth.ps1/vixradar-ambient-check.ps1: dependencia implicita, que some sem aviso
# se a lib encolher. E o padrao que test-mva-failover-quota-backlog.ps1 chama de lib orfa.
# Mesmo formato dos outros consumidores (monitor-tasks.ps1:33, run_vixradar_sentinela.ps1:373).
. (Join-Path $PSScriptRoot 'lib\vixradar-llm-provider.ps1')
# Fase B D1 (2026-09-04): adapter OpenRouter e opcional. Ausencia do arquivo nao derruba
# os outros providers (none/claude-manual seguem intactos); so o provider 'openrouter'
# exige o adapter e o gate abaixo aborta 86 se ele nao existir.
if (Test-Path (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')) {
    . (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')
    $script:VixLibOpenRouterOk = $true
} else {
    $script:VixLibOpenRouterOk = $false
}
# COLETOR-PS1 (2026-09-23): a coleta deterministica substitui a busca feita pelo modelo.
# VIXRADAR_COLETOR_PS=0 preserva o fluxo anterior para medicao A/B.
$script:VixColetorAtivo = $false
$script:VixColetorCache = @{}
$script:VixColetorFalhas = @{}
$__coletorLib = Join-Path $ScriptsDir 'lib\vixradar-coletor.ps1'
if (Test-Path $__coletorLib) {
    . $__coletorLib
    $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Process')
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'User') }
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Machine') }
    if (('' + $__flagColetor).Trim() -ne '0') { $script:VixColetorAtivo = $true }
    Write-Log ('COLETOR_PS: ativo=' + $script:VixColetorAtivo + ' (VIXRADAR_COLETOR_PS; 0 desliga)')
} else {
    Write-Log 'COLETOR_PS: lib ausente - a evidencia continua sendo buscada pelo modelo.'
}
$script:VixColetorObrigatorio = ((Get-VixLlmProvider) -eq 'deepseek')
if ($script:VixColetorObrigatorio -and -not $script:VixColetorAtivo) {
    Write-Log 'ERRO FATAL: provider deepseek exige COLETOR_PS ativo. DeepSeek direta nao tem WebSearch/WebFetch; nenhum lote sera chamado.'
    exit $VixLlmBloqueadoExit
}
# COBERTURA-13OUT4 (2026-10-13): escalada seletiva. O pacote barato do coletor NAO abre a fonte
# primaria: medido em 13/10, os 3 emissores do lote de medicao com manchete nova voltaram
# INCONCLUSIVO porque a IA recebia so titulo e data. A escalada poe esses emissores numa segunda
# passada COM ferramenta, so eles, depois da rodada barata e pelo mesmo caminho (orcamento,
# disjuntor, portao de ausencia, submit, ledger e fila pendente). Sem coletor nao existe pacote
# barato, entao a escalada so liga junto com ele. Desligamento explicito: VIXRADAR_ESCALADA_FULL=0,
# porque a escalada gasta token do modo FULL (~178k por emissor, medido em 13/10).
$script:VixEscaladaAtiva = $false
# Terceira condicao, e ela nao e formalidade: escalar significa abrir a fonte primaria. Provedor
# sem ferramenta nao consegue - e o caso do deepseek, que e justamente o provedor para o qual o
# coletor e OBRIGATORIO porque a IA nao tem WebSearch/WebFetch proprio. Ligar a escalada ali
# produziria dois danos mediveis: o lote de escalada cairia em Test-VixColetorObrigatorioPronto
# para um emissor cuja coleta falhou (que e um dos gatilhos) e o motor sairia com exit 6, matando
# a execucao inteira; e, se rodasse, entregaria o mesmo INCONCLUSIVO pagando um lote caro. Com o
# guard, sob deepseek a escalada simplesmente nao existe e o comportamento anterior fica intacto.
if ($script:VixColetorAtivo -and -not $script:VixColetorObrigatorio -and ($null -ne (Get-Command 'Get-VixEscaladaDecisao' -ErrorAction SilentlyContinue))) {
    $__flagEscalada = [Environment]::GetEnvironmentVariable('VIXRADAR_ESCALADA_FULL', 'Process')
    if (-not $__flagEscalada) { $__flagEscalada = [Environment]::GetEnvironmentVariable('VIXRADAR_ESCALADA_FULL', 'User') }
    if (-not $__flagEscalada) { $__flagEscalada = [Environment]::GetEnvironmentVariable('VIXRADAR_ESCALADA_FULL', 'Machine') }
    if (('' + $__flagEscalada).Trim() -ne '0') { $script:VixEscaladaAtiva = $true }
    Write-Log ('ESCALADA_FULL: ativo=' + $script:VixEscaladaAtiva + ' (VIXRADAR_ESCALADA_FULL; 0 desliga; exige COLETOR_PS ativo)')
}
# COBFALLBACK1: o tier de cada alvo ja foi decidido pela cascata (FULL para inconclusivo, critico
# ou sem coleta). Escalada dentro do fallback compraria um segundo lote Claude para o mesmo emissor.
if ($script:VixCobFallbackModo -and $script:VixEscaladaAtiva) { $script:VixEscaladaAtiva = $false; Write-Log 'ESCALADA_FULL: desligada no modo cobfallback (tier ja decidido pela cascata da cobertura diaria)' }
# MVA-WIRING1 (2026-09-16): o boot passa a travar tambem pelo bloco MVA da lib, e nao so pelas
# funcoes do provider gate. Get-VixFailoverClasse e chamada no ramo de falha de Invoke-ClaudeBatch
# e Test-VixBacklogPodeFechar e a regra que o dreno de DEFERIDO aplica. Lib truncada
# quebra no boot com o nome da funcao faltante, em vez de morrer no meio do lote.
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe', 'Send-VixRoutineAlert', 'Invoke-VixClaudeAuthEscalate', 'Invoke-VixClaudeAuthEscalateForcado', 'Get-VixSessionLimitAcao', 'Get-VixWsProbeClassificacao', 'ConvertTo-VixWsProbeResetAt', 'Initialize-VixClaudeAuth', 'Get-VixClaudeAuthModo', 'Get-VixFailoverClasse', 'Test-VixBacklogPodeFechar')
foreach ($fn in @('Get-VixCustoConfig', 'Get-VixCustoDia', 'Get-VixCapEfetivo', 'Get-VixCapEscaladaEfetivo', 'Get-VixUsageParcelas', 'Get-VixCustoEstimadoTier', 'Get-VixFullConfirmadosDoLedger', 'Get-VixFullSemanaDosLedgers', 'Merge-VixFullSemana', 'Select-VixProfundidadeNoturna', 'New-VixJobsPorTier', 'Get-VixCaudaRotacao')) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Safe ('ERRO: funcao ' + $fn + ' ausente em lib\vixradar-custo.ps1'); exit 1 }
}
# D4 do P0 PROFUNDIDADE-NOTURNA1: boot gate da skill FULL. O lote FULL e um caminho novo do
# motor, e ate 19/09/2026 ele carregava um prompt de 15/07 que definia esquema proprio de buscas
# (rodadas R2/R6/R5, "max 3 buscas") em contradicao direta com o contrato COBERTURA1 de tres
# familias obrigatorias que o proprio motor injeta no prompt. As duas regras chegariam juntas ao
# modelo. O gate recusa o boot se a skill sumir ou se ela deixar de declarar as tres familias, o
# override explicito e o delta - em vez de deixar a noite inteira sair com prompt divergente.
# So vale para a noturna (e para o fallback de cobertura, que usa o mesmo prompt FULL).
if ($Perfil.modo -eq 'noturno' -or $script:VixCobFallbackModo) {
    $skillFullPath = Join-Path $ScriptsDir 'noturno-batch-sonnet.md'
    if (-not (Test-Path -LiteralPath $skillFullPath)) {
        Write-Safe ('ERRO: skill do lote FULL ausente em ' + $skillFullPath + ' - a noturna nao sobe sem o prompt aprofundado')
        exit 1
    }
    $skillFullTxt = Get-Content -LiteralPath $skillFullPath -Raw -Encoding UTF8
    foreach ($marcador in @('COBERTURA1', 'F1-emissor', 'F2-divida', 'F3-fato', 'FEEDRETRO1', 'FONTEDIVERG1')) {
        if ($skillFullTxt -notmatch [regex]::Escape($marcador)) {
            Write-Safe ('ERRO: skill do lote FULL sem o marcador ' + $marcador + ' em ' + $skillFullPath + ' - contrato divergente do motor')
            exit 1
        }
    }
}

function Get-CvmResumo($docs) {
    if (-not $docs) { return '0 docs' }
    $arr = @($docs)
    if ($arr.Count -eq 0) { return '0 docs' }
    return ($arr.Count.ToString() + ' docs')
}

function Get-VixColetorParaEmissor([string]$Empresa) {
    # Cache por emissor dentro da execucao. O mesmo emissor pode reaparecer em retry de lote.
    if (-not $script:VixColetorAtivo) { return $null }
    $k = ('' + $Empresa).Trim().ToLowerInvariant()
    if ($script:VixColetorCache.ContainsKey($k)) { return $script:VixColetorCache[$k] }
    $c = $null
    try { $c = Get-VixColetorEvidencia -Empresa $Empresa } catch { $c = $null }
    if ($null -eq $c -or ($null -ne $c.PSObject.Properties['disponivel'] -and -not $c.disponivel)) { $script:VixColetorFalhas[$k] = $true }
    $script:VixColetorCache[$k] = $c
    return $c
}

function Test-VixColetorObrigatorioPronto($Emissores) {
    if (-not $script:VixColetorObrigatorio) { return $true }
    foreach ($emp in @($Emissores)) {
        $coleta = Get-VixColetorParaEmissor ('' + $emp.empresa)
        if ($null -eq $coleta -or ($null -ne $coleta.PSObject.Properties['disponivel'] -and -not $coleta.disponivel)) { return $false }
    }
    return $true
}

function Get-SlimEmissor($emp, [string]$Tier = '', [switch]$Ultra) {
    if (-not $Tier) { $Tier = $Perfil.tier }
    $docs = @($emp.cvm_documentos | Select-Object -First $(if ($Ultra) { 2 } else { 3 }) | ForEach-Object {
        $assunto = '' + $_.assunto
        if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
        $d = [ordered]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
        if ($_.empresa_cvm -and ($_.empresa_cvm -notmatch [regex]::Escape(($emp.empresa -split ' ')[0]))) { $d['empresa_cvm'] = $_.empresa_cvm }
        [pscustomobject]$d
    })
    $o = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; tier = $Tier
        ews_score = $emp.ews_score; cvm_novos = $emp.cvm_novos; cvm_documentos = $docs
        # FEEDRETRO1 FASE2 (2026-09-04): delta que o Worker ja calcula no plano
        # (montarPlanoRotina), so repassado aqui. Sem isso o modelo nao tem como
        # saber "o que ja sabemos" e reencontra o mesmo fato do mes toda noite.
        ultimo_evento_data = $emp.ultimo_evento_data
        eventos_conhecidos = $emp.eventos_conhecidos
        janela_delta_inicio = $emp.janela_delta_inicio
    }
    # COBERTURA-13OUT1: pistas da triagem (so manchetes NOVAS que citam o emissor). O modelo parte
    # delas para confirmar em fonte primaria, em vez de refazer a busca ampla das tres familias.
    if ($script:VixTriagemDados -and $script:VixTriagemDados.ContainsKey((ConvertTo-VixChaveEmissor ('' + $emp.empresa)))) {
        $__pistas = Format-VixLeadsTriagem $script:VixTriagemDados[(ConvertTo-VixChaveEmissor ('' + $emp.empresa))].Triagem
        if ($__pistas) { $o['pistas_triagem'] = $__pistas }
    }
    $ctx = '' + $emp.contexto_historico
    if ($ctx) {
        $isCritico = ($emp.ews_score -ge $EwsContextoCritico) -or ($ctx -match 'REX|RJ|recupera|default|CRITICO')
        $max = if ($isCritico) { 400 } elseif ($Ultra) { 200 } else { 120 }
        if ($ctx.Length -gt $max) { $ctx = $ctx.Substring(0, $max) }
        $o['contexto_historico'] = $ctx
    }
    # F1/F2 abaixo sao contagens do RSS. F3 so conta documento que o proprio plano do Worker
    # trouxe, porque resultado de RSS nao prova cobertura de CVM/RI/fato primario.
    $coleta = Get-VixColetorParaEmissor ('' + $emp.empresa)
    if ($coleta) {
        $o['evidencia_coletada'] = Format-VixColetorEvidenciaTexto $coleta
        # RECHECKDIVERG1: ids que a conferencia vai exigir veredito, calculados pela mesma regra.
        $__ids = @(Get-VixManchetesExigemVeredito -Coleta $coleta -DeltaInicio ('' + $emp.janela_delta_inicio))
        if ($__ids.Count -gt 0) { $o['manchetes_exigem_veredito'] = $__ids }
        $f1 = 0; $f2 = 0
        try { $f1 = [int]$coleta.por_familia['F1'] } catch { $f1 = 0 }
        try { $f2 = [int]$coleta.por_familia['F2'] } catch { $f2 = 0 }
        $o['cobertura_familias'] = [ordered]@{
            F1 = $f1
            F2 = $f2
            F3 = $(if ($docs.Count -gt 0) { $docs.Count } else { 0 })
            origem = 'F1/F2 coletor PowerShell (Google News RSS); F3 somente cvm_documentos do plano'
        }
    }
    return $o
}

function Invoke-WorkerJsonUtf8 {
    # P0 nota 43: Worker responde JSON sem charset; PS 5.1 decodificaria como ISO-8859-1.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Submit-Analise($key, $empresa, $setor, $resultado, [string]$provedor, [string]$tier, $cvmIds) {
    if ($DryRun) { return [pscustomobject]@{ ok = $true; n_eventos = 0; dryrun = $true } }
    $body = [ordered]@{
        action = 'receber_analise'; routine_key = $key; empresa = $empresa; setor = $setor
        _matinal = [bool]$Perfil.matinal; origem = $Rotina; _tier = $tier; provedor = $provedor
        cvm_ids_analisados = @($cvmIds | Where-Object { $_ }); resultado = $resultado
    }
    return Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $body -Depth 16 -TimeoutSec 120
}

function Submit-SkipEmissor($key, $emp) {
    $motivos = if ($emp.motivos) { ($emp.motivos -join ', ') } else { 'sem_delta' }
    $cvmResumo = Get-CvmResumo $emp.cvm_documentos
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier SKIP. CVM: $cvmResumo. $($emp.cvm_novos) novos. Motivos: $motivos."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'Worker plano'; resultado = $cvmResumo })
        eventos = @(); _tier = 'SKIP'; _rotina_v2 = $true
    }
    $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-skip-routine' 'SKIP' @()
    if ($resp.ok -ne $true) { Start-Sleep -Seconds $PauseSec; $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-skip-routine' 'SKIP' @() }
    return $resp
}

function Submit-CapDeferred($key, $emp, [string]$Motivo = 'cap_efetivo', [string]$Tier = '') {
    if (-not $Tier) { $Tier = $Perfil.tier }
    # COBERTURAAUTH1 (2026-09-15): a nota de cobertura passa a nomear a causa REAL do
    # deferimento. Antes ela era fixa ("Cap efetivo <N> tokens") e ia para o estado de producao
    # descrevendo cap de tokens numa execucao que morreu por limite de sessao da assinatura -
    # medido em 14/09: 24 emissores DEFERIDO com motivo=cap_efetivo e apenas 378424/700000
    # tokens gastos. `_token_cap_deferred` continua true de proposito: e a chave que o Worker le
    # (DEFERREDREC1, worker.js:11938/11965) para devolver o emissor no plano seguinte como FULL
    # motivo deferred_prioritario; renomear exigiria mexer no Worker, fora do escopo deste card.
    $causa = if ($Motivo -eq 'cap_efetivo') {
        'Cap efetivo ' + $TokenHardCap + ' tokens - ledger minimo.'
    } elseif ($Motivo -eq 'rotacao_semanal') {
        'Rotacao semanal de profundidade (PROFUNDIDADE-NOTURNA1) - emissor nao selecionado para FULL nem LIGHT nesta noite. Nao e corte por orcamento.'
    } elseif ($Motivo -eq 'falha_provider') {
        'Provedor de analise falhou ou ficou indisponivel nesta execucao (COBERTURA-13OUT1) - emissor NAO analisado, sem certificar ausencia de evento.'
    } elseif ($Motivo -eq 'max_emissores') {
        'Fora do limite -MaxEmissores da execucao (MAXEMISSORESREAL1) - emissor NAO analisado nesta execucao, segue pendente.'
    } else {
        'Limite de sessao da assinatura no meio da execucao (NAO e cap de tokens: ' + $Motivo + ') - lote nao processado.'
    }
    # D1 do P0 PROFUNDIDADE-NOTURNA1: `_token_cap_deferred` e a chave que o Worker le
    # (DEFERREDREC1, worker.js:11938/11965) para devolver o emissor no plano seguinte como FULL
    # motivo deferred_prioritario. Para corte por cap ou por assinatura isso e desejado. Para
    # rotacao semanal NAO e: o emissor ficou de fora por desenho da rotacao, e devolve-lo como
    # FULL prioritario no dia seguinte desfaria a propria rotacao que o deixou de fora, enchendo
    # a noite seguinte de emissores que a anterior acabou de decidir nao aprofundar.
    $ehCorteDeCap = ($Motivo -ne 'rotacao_semanal')
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier $Tier. $causa EWS=$($emp.ews_score). Priorizar amanha."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'token_cap'; resultado = 'deferred' })
        eventos = @(); _tier = $Tier; _rotina_v2 = $true; _token_cap_deferred = $ehCorteDeCap
        _defer_motivo = $Motivo
    }
    return Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-cap-deferred' $Tier @()
}

function Split-IntoChunks($items, [int]$chunkSize) {
    $list = @($items)
    if ($list.Count -eq 0) { return @() }
    $chunks = @()
    for ($i = 0; $i -lt $list.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize - 1, $list.Count - 1)
        $chunks += ,@($list[$i..$end])
    }
    return ,$chunks
}

function Update-VixLock {
    try { (Get-Item $LockFile -ErrorAction Stop).LastWriteTime = Get-Date } catch { }
}

# D1: lock so bloqueia quando o processo que o escreveu continua vivo COM o mesmo
# inicio. PID sozinho pode ser reutilizado pelo Windows depois de um crash.
# LOCKIDENT1 (2026-10-09): a implementacao mudou para lib\vixradar-lock.ps1 (dot-source no
# boot), para o retry julgar vida pela MESMA regra. Nao redefinir Get-VixLockState aqui.
# D4: o total final e a leitura do ledger do dia. Contadores da execucao atual
# nao representam um reinicio e podem divergir de linhas ja persistidas.
function Get-VixResumoLedger([string]$Path) {
    $vistos = @{}
    # LOGFALLBACK1: principal + _fallback_<pid>.log do dia, pela regra unica da lib do vigia.
    if (@(Get-VixLogDiaArquivos $Path).Count -gt 0) {
        foreach ($linha in @(Get-VixLogDiaLinhas $Path)) {
            if ($linha -match '^(?:[\d-]+\s+[\d:]+\s+)?(?:OK|DRYRUN)\|([^|]+)\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|(SKIP|ANALISADO|DEFERIDO)\|') {
                $vistos[(Get-NomeNormalizado $Matches[1])] = $Matches[2]
            }
        }
    }
    $analisados = 0; $skips = 0; $deferidos = 0
    foreach ($status in @($vistos.Values)) {
        if ($status -eq 'ANALISADO') { $analisados++ }
        elseif ($status -eq 'SKIP') { $skips++ }
        elseif ($status -eq 'DEFERIDO') { $deferidos++ }
    }
    return [pscustomobject]@{ total = $vistos.Count; analisados = $analisados; skips = $skips; deferidos = $deferidos }
}

# D3: codex exec --json pode nao publicar usage. Sem evento de usage, a ausencia
# e declarada, nunca convertida em quatro zeros inventados.
function Get-VixCodexUsageProbe($Linhas) {
    # COBERTURA-13OUT1: a versao anterior devolvia o PRIMEIRO evento com usage e lia
    # cache_read_input_tokens, campo que o Codex nao publica (ele publica cached_input_tokens).
    # Agora soma todos os eventos e registra o cache a parte, sem tirar nada da regua do cap.
    $uso = Get-VixCodexUsageJsonl $Linhas
    if (-not $uso.mensuravel) { return [pscustomobject]@{ mensuravel = $false; parcelas = $null; uso = $uso } }
    return [pscustomobject]@{ mensuravel = $true; parcelas = (ConvertTo-VixParcelasCodex $uso); uso = $uso }
}

function Invoke-ClaudeBatch([string]$promptPath, [string]$Model, [int]$Emissores = 0, [string]$Tier = '', [string]$ProviderOverride = '', [string]$PromptAppend = '') {
    if (-not $Tier) { $Tier = $Perfil.tier }
    # Fallback cross-provider opt-in. O provider global continua sendo OpenRouter durante
    # toda a rotina. A substituicao vale apenas para esta invocacao recursiva, quando o
    # OpenRouter devolveu 402 de credito. Nunca habilitar a chave paga por este caminho.
    $providerProcessAnterior = $null
    $providerOverrideAtivo = [bool]$ProviderOverride
    $providerDaInvocacao = if ($ProviderOverride) {
        $ProviderOverride.Trim().ToLowerInvariant()
    } elseif ($script:VixUsaOpenRouter) {
        'openrouter'
    } elseif ($script:VixUsaCodex) {
        'codex'
    } else {
        'claude-subscription'
    }
    $usaOpenRouterNestaInvocacao = ($providerDaInvocacao -eq 'openrouter')
    $usaCodexNestaInvocacao = ($providerDaInvocacao -eq 'codex')
    $fallbackAuthIndisponivel = $false
    $skipProviderInvoke = $false
    if ($providerOverrideAtivo) {
        $providerProcessAnterior = [Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'Process')
        [Environment]::SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', $providerDaInvocacao, 'Process')
    }
    # Flags de economia (medidas 2026-07-03): boot 33.9k -> ~13.6k tokens/invocacao.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ($Perfil.prefix + '_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1; $escalou = $false; $usoMensuravel = $true
    # COBERTURA-13OUT1: falha de PROVEDOR (o Codex nao entregou) separada de falha de conteudo.
    # O chamador usa isto para nao repetir chamada sem perspectiva (disjuntor de provedor).
    $providerFalhou = $false; $providerClasse = ''; $providerSemPerspectiva = $false
    # COTAESGOTADA1 (2026-09-16): cota da assinatura esgotada CONFIRMADA (limite de sessao
    # classificado + reset que nao cabe no teto de parede) e sem chave paga para assumir.
    # Zera por invocacao: e o sinal de fail-closed entregue ao chamador.
    $cotaEsgotadaSemFallback = $false
    $cotaEsgotadaMotivo = ''
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $retryDelays = @(0, 30, 60)
        if ($usaCodexNestaInvocacao) { $retryDelays = @(0) }
        # OR429-CAMADAUNICA (2026-09-09): com allow_fallbacks=true no adapter, o failover entre
        # providers do MESMO modelo e nativo do OpenRouter e o retry de 429/transporte e bounded
        # DENTRO do adapter (respeitando Retry-After). Re-disparar o lote inteiro aqui (30s/60s)
        # duplicava ate ~11 POSTs no mesmo payload apos cada 429 e foi o que matou a matinal de
        # 09/09 no backoff, sem FIM (pid 23428). Camada unica: 1 chamada do adapter por payload;
        # falha controlada no fluxo normal abaixo (FIM/ROTINA_RESUMO + exit != 0).
        if ($usaOpenRouterNestaInvocacao) { $retryDelays = @(0) }
        if ($providerOverrideAtivo -and $providerDaInvocacao -eq 'claude-subscription') {
            if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
                Write-Log 'FALLBACK_ANTHROPIC: claude.exe ausente, lote nao transferido.'
                $fallbackAuthIndisponivel = $true
            } else {
                try {
                    Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
                    $modoFallback = Get-VixClaudeAuthModo
                    if ($modoFallback -ne 'assinatura' -and $modoFallback -ne 'assinatura-token') {
                        Write-Log ('FALLBACK_ANTHROPIC: assinatura indisponivel (modo=' + $modoFallback + '), chave paga nao sera usada.')
                        $fallbackAuthIndisponivel = $true
                    } else {
                        Write-Log ('FALLBACK_ANTHROPIC: assinatura pronta (modo=' + $modoFallback + ').')
                    }
                } catch {
                    Write-Log ('FALLBACK_ANTHROPIC: falha ao inicializar assinatura - ' + $_.Exception.Message)
                    $fallbackAuthIndisponivel = $true
                }
            }
            if ($fallbackAuthIndisponivel) {
                $cotaEsgotadaSemFallback = $true
                $cotaEsgotadaMotivo = 'fallback Claude subscription indisponivel; chave paga bloqueada'
                $exitCode = 5
                $raw = @('CLAUDE_FALLBACK_AUTH_UNAVAILABLE')
                $skipProviderInvoke = $true
            }
        }
        $retryLog = @()
        # OR402-DEGRADA1 (2026-09-11): quantas chamadas ao adapter desta invocacao cairam para o
        # modelo de fallback por saldo insuficiente (HTTP 402) no modelo do tier. Vai no retorno
        # e no resumo operacional: o lote fecha (nao e erro e nao mexe em silent_fail), mas saldo
        # baixo nao pode sair do log como se nada tivesse acontecido.
        $degradado402Lote = 0
        # Limite que volta DEPOIS de ja ter esperado o reset nao se resolve esperando de
        # novo: o plano manda escalar nesse caso. Sem esta memoria, duas esperas seguidas
        # comeriam o teto de parede e a rotina morreria mesmo assim.
        $jaEsperouReset = $false
        for ($attempt = 0; $attempt -lt $retryDelays.Count; $attempt++) {
            if ($skipProviderInvoke) { break }
            if ($attempt -gt 0) {
                $delay = $retryDelays[$attempt]
                Write-Log ('RETRY: tentativa ' + ($attempt + 1) + '/' + $retryDelays.Count + ' aguardando ' + $delay + 's (lote morreu na anterior)')
                Start-Sleep -Seconds $delay
            }
            Update-VixLock
            # Fase B D1: provider openrouter despacha para o adapter HTTP proprio
            # (lib\vixradar-openrouter.ps1), com as server tools web_search/web_fetch.
            # Mesmo prompt, mesmo protocolo textual; envelope normalizado no parser abaixo.
            if ($usaCodexNestaInvocacao) {
                $codexOutFile = Join-Path $LogDir ($Perfil.prefix + '_codex_' + $DateTag + '_' + $PID + '.txt')
                Remove-Item -LiteralPath $codexOutFile -Force -ErrorAction SilentlyContinue
                # COBERTURA-13OUT1: preambulo headless no topo (neutraliza o fluxo de skills do
                # AGENTS.md global, que nao tem chave de config que o desligue).
                $promptText = (Get-VixCodexPreambulo) + "`r`n`r`n" + (Get-Content $promptPath -Raw -Encoding UTF8)
                # CODEX-SKILLBLOCK1 (2026-10-09): o Codex CLI anunciava as skills do host
                # (~/.agents/skills) ao modelo, que tentava le-las com `pwsh -Command Get-Content`,
                # e o sandbox read-only rejeitava a criacao de processo ("blocked by policy"). O
                # lote morria como falha de provedor com ZERO analise - medido em 09/10/2026 no
                # log da sentinela (sentinela_stderr_20261009_*.txt). O prompt ja embute a skill
                # em texto; desligar a descoberta de skills do host NAO afrouxa o sandbox (segue
                # read-only, --ignore-user-config, --ignore-rules) - apenas retira do modelo a
                # lista de arquivos que ele nao pode ler.
                # COBERTURA-13OUT1: Get-VixCodexArgsBase tira do contexto o catalogo de skills, as
                # instrucoes de permissao, apps e plugins (50.309 -> 14.468 chars por passo do
                # agente, medido com `codex debug prompt-input`). Sandbox e flags de isolamento
                # abaixo ficam iguais.
                $__codexBase = @(Get-VixCodexArgsBase)
                $codexRaw = $promptText | codex @__codexBase --search exec --json --ephemeral --sandbox read-only --ignore-user-config --ignore-rules --skip-git-repo-check -C $env:TEMP -o $codexOutFile - 2>>$stderrFile
                $exitCode = $LASTEXITCODE
                # Consumo medido SEMPRE, inclusive quando o lote falha: lote que falhou tambem
                # gastou. Sem evento de usage = NAO_MENSURAVEL, nunca zero.
                $__usoCodex = Get-VixCodexUsageProbe @($codexRaw)
                $script:VixUltimoCodexCached = [int64]0
                if ($__usoCodex.uso.mensuravel) { $script:VixUltimoCodexCached = [int64]$__usoCodex.uso.cached }
                if ($__usoCodex.uso.mensuravel) {
                    Write-Log ('USAGE_CODEX: eventos=' + $__usoCodex.uso.eventos + ' input_total=' + $__usoCodex.uso.input_total + ' cached_input=' + $__usoCodex.uso.cached + ' output=' + $__usoCodex.uso.output + ' reasoning=' + $__usoCodex.uso.reasoning + ' exit=' + $exitCode)
                }
                if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $codexOutFile) -or [string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $codexOutFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue))) {
                    $providerFalhou = $true
                    $__errTxt = ''
                    if (Test-Path -LiteralPath $stderrFile) { $__errTxt = '' + (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue) }
                    $__clsProv = Get-VixClasseFalhaProvider ((@($codexRaw) -join ' ') + ' ' + $__errTxt)
                    $providerClasse = $__clsProv.Classe; $providerSemPerspectiva = [bool]$__clsProv.SemPerspectiva
                    if ($exitCode -eq 0) { $exitCode = 1 }
                    Write-Log ('PROVIDER_FALHOU: codex exit=' + $LASTEXITCODE + ' classe=' + $providerClasse + ' sem_perspectiva=' + $providerSemPerspectiva + ' (resultado vazio ou processo falhou)')
                    # CODEXFALLBACK-OR1 (2026-10-14): o provedor ativo e o Codex e ele nao tinha
                    # nenhum fallback. Aqui mora o desvio opt-in para o adapter OpenRouter, com a
                    # MESMA forma dos outros dois sentidos (VIXRADAR_CLAUDE_FALLBACK_PROVIDER e
                    # VIXRADAR_OPENROUTER_FALLBACK_PROVIDER): sem a var, sem adapter pronto ou ja
                    # dentro de um override, nada muda. A regra e pura e vive em
                    # Get-VixCodexFailoverDecisao (lib\vixradar-llm-provider.ps1); aqui entram
                    # apenas os fatos medidos neste lote.
                    $script:VixCodexProviderFalhasConsecutivas = [int]$script:VixCodexProviderFalhasConsecutivas + 1
                    $__fxHabilitado = (Get-VixCodexFallbackOpenRouterHabilitado)
                    $__fxDestino = $false
                    if ($__fxHabilitado -and -not $providerOverrideAtivo -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
                        $__fxBoot = Test-VixOpenRouterPronto
                        $__fxDestino = [bool]$__fxBoot.ok
                        if (-not $__fxDestino) { Write-Log ('FALLBACK_OPENROUTER_CODEX: habilitado, mas o destino nao esta pronto (' + $__fxBoot.motivo + '). Sem desvio; vale o fail-closed anterior.') }
                    }
                    $__fxDec = Get-VixCodexFailoverDecisao -Classe $providerClasse -FalhasConsecutivas $script:VixCodexProviderFalhasConsecutivas -DestinoPronto $__fxDestino -Habilitado $__fxHabilitado -ProviderOverrideAtivo $providerOverrideAtivo
                    if ($__fxDec -eq 'failover') {
                        # Custo da tentativa que falhou: medido quando o Codex publicou usage,
                        # -1 (desconhecido) quando nao publicou. O chamador cobra os dois, nunca zero.
                        $__fxTokens = [int64]-1
                        if ($__usoCodex.uso.mensuravel) { $__fxTokens = [int64]$__usoCodex.parcelas.trabalho }
                        Write-Log ('FALLBACK_OPENROUTER_CODEX: codex classe=' + $providerClasse + ' exit=' + $exitCode + ' tokens_codex=' + $(if ($__fxTokens -ge 0) { '' + $__fxTokens } else { 'NAO_MENSURAVEL' }) + ' - transferindo somente este lote para openrouter (VIXRADAR_CODEX_FALLBACK_PROVIDER=openrouter).')
                        $__fxResp = Invoke-ClaudeBatch -promptPath $promptPath -Model $Model -Emissores $Emissores -Tier $Tier -ProviderOverride 'openrouter'
                        if ($__fxResp) {
                            $__fxResp['TokensFalhaFallback'] = $__fxTokens
                            return $__fxResp
                        }
                        Write-Log 'FALLBACK_OPENROUTER_CODEX: o adapter nao devolveu lote; seguindo o fail-closed do Codex.'
                    }
                    if ($__usoCodex.uso.mensuravel) {
                        $usoMensuravel = $true
                        # CACHECODEX-VISIVEL1-FIX (2026-10-14): a parcela de cache medida no JSONL
                        # vai no envelope em campo PROPRIO. Sem ela o metrics fechava
                        # `tokens_cache_codex=0` enquanto o FIM dizia `codex_cached_input=1036416`.
                        $raw = @(([ordered]@{ result = ''; is_error = $true; model = 'codex-subscription'; usage = [ordered]@{ input_tokens = $__usoCodex.parcelas.input; output_tokens = $__usoCodex.parcelas.output; cache_creation_input_tokens = 0; cache_read_input_tokens = 0; cache_codex_input_tokens = $__usoCodex.parcelas.cache_codex } }) | ConvertTo-Json -Compress)
                    } else {
                        # Falha sem usage: consumo desconhecido. O chamador cobra a ESTIMATIVA do
                        # lote (nunca zero) em vez de congelar o dia inteiro por um lote que
                        # provavelmente morreu antes de trabalhar.
                        $raw = @($codexRaw)
                    }
                    $retryLog += ('t' + ($attempt + 1) + ':codex:exit=' + $exitCode + ':classe=' + $providerClasse)
                    break
                }
                if ($exitCode -eq 0 -and (Test-Path -LiteralPath $codexOutFile)) {
                    # CODEXFALLBACK-OR1: lote do Codex entregue zera o contador de falhas
                    # consecutivas do provedor (e o que separa instabilidade de indisponibilidade
                    # persistente para a decisao de desvio).
                    $script:VixCodexProviderFalhasConsecutivas = 0
                    # CODEX-PSDECOR1 (2026-10-09): Get-Content -Raw devolve uma string COM note
                    # properties (PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/ReadCount).
                    # ConvertTo-Json DESCE nelas: o envelope vira
                    # {"result":{"value":"<texto>","PSPath":"...","ReadCount":1},...} e o parse
                    # do lote le "@{value=[...]; PSPath=...}" e falha - foi o que deixou os 20
                    # emissores da agenda sem atualizacao em 07/10/2026. O cast [string] chama
                    # ToString e descarta as note properties. Ver a mesma correcao na agenda e
                    # na verificacao (que ja usa [string] desde a migracao para codex).
                    $codexText = [string](Get-Content -LiteralPath $codexOutFile -Raw -Encoding UTF8)
                    $codexUsage = Get-VixCodexUsageProbe @($codexRaw)
                    $usoMensuravel = [bool]$codexUsage.mensuravel
                    $envelope = [ordered]@{
                        result = $codexText
                        is_error = $false
                        model = 'codex-subscription'
                    }
                    if ($usoMensuravel) {
                        $envelope.usage = [ordered]@{ input_tokens = $codexUsage.parcelas.input; output_tokens = $codexUsage.parcelas.output; cache_creation_input_tokens = $codexUsage.parcelas.cache_creation; cache_read_input_tokens = $codexUsage.parcelas.cache_read; cache_codex_input_tokens = $codexUsage.parcelas.cache_codex }
                    }
                    else { Write-Log 'USAGE_CODEX=NAO_MENSURAVEL: codex exec --json nao emitiu usage; cap fecha apos este lote.' }
                    $raw = @($envelope | ConvertTo-Json -Compress)
                } else { $raw = @($codexRaw) }
                $retryLog += ('t' + ($attempt + 1) + ':codex:exit=' + $exitCode)
                if ($exitCode -eq 0) { break }
                Write-Log ('RETRY codex: tentativa ' + ($attempt + 1) + '/' + $retryDelays.Count + ' falhou')
                continue
            }
            if ($usaOpenRouterNestaInvocacao) {
                # OR429-TETO (2026-09-09): teto de parede TOTAL do lote passado ao adapter, para o
                # ciclo retry+fallback+Retry-After nunca estourar o orcamento (09/09 morreu no meio
                # do backoff sem teto). Default = 2 paredes de tentativa
                # (VIXRADAR_OPENROUTER_TIMEOUT_MIN, 12 min cada) + 120s de margem; override por
                # VIXRADAR_OPENROUTER_LOTE_TIMEOUT_MIN (minutos).
                $__loteTimeoutSec = 0
                $__loteMinEnv = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_LOTE_TIMEOUT_MIN'
                if ($__loteMinEnv) {
                    $__loteMin = 0
                    if ([int]::TryParse(('' + $__loteMinEnv).Trim(), [ref]$__loteMin) -and $__loteMin -gt 0) { $__loteTimeoutSec = $__loteMin * 60 }
                }
                if ($__loteTimeoutSec -le 0) { $__loteTimeoutSec = (Get-VixOpenRouterTimeoutMin) * 120 + 120 }
                # SEARCHBUDGET1: o tamanho do lote vai ao adapter porque o teto de resultados de
                # busca (max_total_results) e GLOBAL do POST: sem ele o lote de 15 emissores
                # entrega 2 buscas e 13 RECHECK_PENDENTE (medido no dry-run de 03:34).
                $__orResp = Invoke-VixOpenRouterLote -PromptPath $promptPath -Tier $Tier -TotalTimeoutSec $__loteTimeoutSec -Emissores $Emissores
                # JSONCICLO1: serializacao pre-HTTP passa a ser observavel. Sem isto, os 55 min
                # presos de 05/09 nao apareceram em log nenhum.
                Write-Log ('PAYLOAD: serializacao=' + ([double]$script:VixOpenRouterUltimaSerializacaoSeg).ToString('F3') +
                           's bytes=' + $script:VixOpenRouterUltimoPayloadBytes +
                           ' modelo=' + (Get-VixOpenRouterModel $Tier) +
                           ' teto_lote_s=' + $__loteTimeoutSec +
                           ' emissores=' + $Emissores +
                           ' busca_teto=' + $script:VixOpenRouterUltimoMaxTotalResults)
                $raw = @($__orResp.Linhas)
                $exitCode = $__orResp.ExitCode
                $retryLog += ('t' + ($attempt + 1) + ':openrouter:exit=' + $exitCode + ':model=' + (Get-VixOpenRouterModel $Tier))
                if ($__orResp.Degradado402) {
                    $degradado402Lote++
                    Write-Log ('WARN: DEGRADADO_402: lote ' + (Split-Path $promptPath -Leaf) + ' caiu para o fallback por saldo insuficiente (tier=' + (Get-VixOpenRouterModel $Tier) + ' fallback=' + $__orResp.Modelo + ') - repor credito OpenRouter')
                }
                if ($exitCode -eq 0) { Write-Log ('OR_OK: modelo=' + $__orResp.Modelo + ' intentos=' + $__orResp.Intentos + ' fallback=' + ('' + $__orResp.FallbackUsado).ToLower()); break }
                Write-Log ('RETRY openrouter: tentativa ' + ($attempt + 1) + '/' + $retryDelays.Count + ': ' + $__orResp.Msg)
                if ($script:VixOpenRouterFallbackAnthropic -and $__orResp.Status -eq 402 -and -not $ProviderOverride) {
                    Write-Log 'FALLBACK_ANTHROPIC: OpenRouter sem credito, transferindo somente este lote para a assinatura.'
                    $anthropicResp = Invoke-ClaudeBatch -promptPath $promptPath -Model 'claude-sonnet-4-6' -Emissores $Emissores -Tier $Tier -ProviderOverride 'claude-subscription' -PromptAppend 'Fallback temporario por saldo do OpenRouter. Use economia de tokens: responda de forma concisa, sem explicacoes fora do formato exigido, preserve o JSON e as linhas RESULTADO exigidas pelo protocolo.'
                    if ($anthropicResp) {
                        $anthropicResp.Degradados402 = [int]$anthropicResp.Degradados402 + 1
                        if ($anthropicResp.ExitCode -eq 0) {
                            Write-Log 'FALLBACK_ANTHROPIC: lote concluido pela assinatura.'
                        } else {
                            Write-Log ('FALLBACK_ANTHROPIC: lote falhou na assinatura, exit=' + $anthropicResp.ExitCode)
                        }
                        return $anthropicResp
                    }
                }
                continue
            }
            Set-VixClaudeAuthEnv
            $promptForClaude = Get-Content $promptPath -Raw -Encoding UTF8
            if ($PromptAppend) { $promptForClaude += "`r`n`r`n" + $PromptAppend }
            $raw = $promptForClaude | claude -p `
                --model $Model `
                --permission-mode bypassPermissions `
                --output-format json `
                --tools 'WebSearch,WebFetch' `
                --strict-mcp-config --mcp-config $McpConfigFile `
                --setting-sources project `
                --disable-slash-commands `
                --no-session-persistence `
                --exclude-dynamic-system-prompt-sections 2>>$stderrFile
            $exitCode = $LASTEXITCODE
            $retryLog += ('t' + ($attempt + 1) + ':exit=' + $exitCode + ':model=' + $Model)
            if ($exitCode -eq 0) { break }
            $saidaFalha = ('' + $raw)
            $stderrTxt = ''
            if (Test-Path $stderrFile) { $stderrTxt = ('' + (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)) }
            $saidaFalha += (' ' + $stderrTxt)
            # MVA_FAILOVER (2026-09-16): classe provider-agnostic da falha do lote, para a taxonomia
            # ficar no proprio log da rotina (no dry-run de 15/09 a causa real de um lote morto era
            # invisivel no log). Neste caminho NAO existe status HTTP - o CLI devolve exit code e
            # texto - entao o status vai 0 (transporte/desconhecido) e quem decide a classe e o TEXTO
            # do stdout+stderr: session-limit/quota/saldo => quota-exhausted, 2xx vazio/malformado =>
            # parse-content, resto => transient. Isto e DIAGNOSTICO: nao altera roteamento nenhum.
            # Quem decide seguir/abortar continua sendo Get-VixWsProbeClassificacao +
            # Get-VixSessionLimitAcao logo abaixo, com o fail-closed do COTAESGOTADA1.
            $mvaClasse = Get-VixFailoverClasse -Status 0 -Corpo $saidaFalha -RespostaOk $false
            Write-Log ('MVA_FAILOVER: classe=' + $mvaClasse + ' exit=' + $exitCode + ' tentativa=' + ($attempt + 1) + '/' + $retryDelays.Count + ' (diagnostico provider-agnostic; roteamento de retry/failover inalterado)')

            # SESSIONLIMIT1 (04/09/2026): limite de uso da assinatura NAO e credencial
            # invalida, e ate hoje caia no mesmo balde. O motor classificava como falha de
            # auth pela regex propria, chamava Invoke-VixClaudeAuthEscalate, e a lib recusava
            # porque a regex DELA nao cobre 'hit your ... limit'. Nenhum ramo esperava o
            # reset, nenhum ramo escalava, e o backoff @(0,30,60) se esgotava em 90 segundos.
            # Foi assim que a noturna de 03/09 morreu as 21h38 com a chave paga disponivel.
            #
            # Ordem agora: esperar o reset REAL quando ele cabe no teto de parede (assinatura
            # e mais barata que a chave paga), e so escalar quando esperar nao resolve.
            $cls = Get-VixWsProbeClassificacao -Saida $saidaFalha -StderrTxt $stderrTxt
            if ($cls.Motivo -eq 'session_limit') {
                # A tabela de decisao vive em Get-VixSessionLimitAcao (lib de auth), pura e
                # testavel sem CLI. Aqui so se EXECUTA o que ela decidiu, para o que roda em
                # producao ser exatamente o que scripts/test-session-limit-policy.ps1 prova.
                $acao = Get-VixSessionLimitAcao -Agora (Get-Date) -ResetAt $cls.ResetAt -EsperaDisponivelMin (Get-VixEsperaDisponivelMin) -JaEsperou $jaEsperouReset
                if ($acao.Acao -eq 'esperar') {
                    Write-Log ('RETRY: limite de sessao da assinatura. ' + $acao.Motivo + ' (' + [Math]::Round($acao.EsperaMin, 1) + ' min).')
                    $retryLog += ('espera:reset:' + [Math]::Round($acao.EsperaMin, 1) + 'min')
                    Start-Sleep -Seconds ([int]($acao.EsperaMin * 60))
                    $jaEsperouReset = $true
                    Update-VixLock
                }
                else {
                    Write-Log ('RETRY: ' + $acao.Motivo + '. Escalando em vez de esperar.')
                    if (Invoke-VixClaudeAuthEscalateForcado $acao.Motivo) { $retryLog += ('auth:forcado:' + $acao.Acao); $escalou = $true }
                    else {
                        # COTAESGOTADA1 (2026-09-16): sem chave paga a escalada nao existe, e a partir
                        # daqui a cota esta CONFIRMADAMENTE esgotada. Repetir `claude -p` com a MESMA
                        # credencial nao muda o desfecho: so queima teto de parede. Medido no dry-run da
                        # noturna de 15/09 (log ..._20260915_dryrun_39464.log:219/223/227): TRES
                        # escaladas forcadas inuteis (03:18:16, 03:18:59, 03:20:11) e zero lote entregue.
                        # Sai do laco com UMA chamada e entrega o lote ao aborto/deferimento que ja
                        # existe (AuthFailure -> exit 7 -> motivo=limite_sessao_assinatura), sem
                        # inventar disponibilidade e sem fallback pago Anthropic (Get-VixAnthropicApiKey
                        # devolve $null sob claude-subscription; ANTHROPIC_API_PAYG=NAO AUTORIZADO).
                        #
                        # CLAUDEFALLBACK-OR1 (2026-09-22): antes de desistir do lote, tenta o adapter
                        # OpenRouter - so quando o operador autorizou explicitamente
                        # (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter) e so para ESTE lote
                        # (-not $providerOverrideAtivo evita recursao quando ja estamos numa invocacao
                        # de fallback). Simetrico ao FALLBACK_ANTHROPIC ja existente no ramo openrouter
                        # (402 de credito -> assinatura), agora no sentido inverso.
                        $__claudeFrDesviado = $false
                        if ((Get-VixClaudeFallbackOpenRouterHabilitado) -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue) -and -not $providerOverrideAtivo) {
                            $__claudeFrBoot = Test-VixOpenRouterPronto
                            if ($__claudeFrBoot.ok) {
                                Write-Log ('FALLBACK_OPENROUTER: ' + $acao.Motivo + '. Transferindo somente este lote para openrouter (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter).')
                                $__orFrResp = Invoke-ClaudeBatch -promptPath $promptPath -Model $Model -Emissores $Emissores -Tier $Tier -ProviderOverride 'openrouter'
                                if ($__orFrResp) {
                                    $__claudeFrDesviado = $true
                                    if ($__orFrResp.ExitCode -eq 0) { Write-Log 'FALLBACK_OPENROUTER: lote concluido pelo openrouter.' }
                                    else { Write-Log ('FALLBACK_OPENROUTER: lote falhou no openrouter, exit=' + $__orFrResp.ExitCode) }
                                    return $__orFrResp
                                }
                            } else {
                                Write-Log ('FALLBACK_OPENROUTER: fallback habilitado mas adapter nao pronto (' + $__claudeFrBoot.motivo + '). Sem desvio possivel, lote segue para aborto.')
                            }
                        }
                        if (-not $__claudeFrDesviado) {
                            $cotaEsgotadaSemFallback = $true
                            $cotaEsgotadaMotivo = ($acao.Motivo + '; sem chave paga para assumir; sem retry e sem fallback autorizado')
                            Write-Log ($AlertaAuthTag + $acao.Motivo + ', e sem chave paga para assumir. Cota da assinatura esgotada confirmada: sem retry (a mesma credencial nao muda) e sem fallback pago autorizado. A rotina vai morrer neste lote.')
                            $retryLog += ('cota:esgotada:sem-fallback:' + $acao.Acao)
                            break
                        }
                    }
                }
            }
            # Credencial que venceu no meio da rotina: escala para a chave paga e repete.
            elseif (Invoke-VixClaudeAuthEscalate $saidaFalha) { $retryLog += 'auth:escalado-para-api'; $escalou = $true }
        }
        if ($retryLog.Count -gt 1) { Write-Log ('RETRY log: ' + ($retryLog -join ' ')) }
        # DRYRUN-CRASH1: exit != 0 sem stderr deixava a causa sem evidencia (02/09 02:45).
        # Guarda a cabeca do stdout no log para a proxima falha ter prova.
        if ($exitCode -ne 0) {
            $cabeca = ('' + (@($raw) -join ' ')).Trim()
            if ($cabeca.Length -gt 300) { $cabeca = $cabeca.Substring(0, 300) }
            if ($cabeca) { Write-Log ('CLAUDE_STDOUT_FALHA: ' + $cabeca) } else { Write-Log 'CLAUDE_STDOUT_FALHA: (stdout vazio, stderr em ' + $stderrFile + ')' }
        }
    } catch {
        Write-Log ('AVISO: excecao ao invocar claude -p (' + $_.Exception.Message + ') - lote marcado como falho')
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    $textOut = @($raw)
    $parcelas = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = [int64]0 }
    $tokens = -1
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) { $parcelas = Get-VixUsageParcelas $json; $tokens = [int64]$parcelas.trabalho }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    # COTAESGOTADA1 (2026-09-16): cota esgotada CONFIRMADA e fail-closed aqui de proposito. A
    # classificacao le stdout E stderr; a regex do motor roda so no stdout ja parseado, entao sem
    # esta linha um reset declarado apenas no stderr nao chegaria ao aborto/deferimento.
    if ($cotaEsgotadaSemFallback) { $authFail = $true }
    if ($fallbackAuthIndisponivel) { $authFail = $true }
    if (-not $usoMensuravel) {
        $tokens = $null
        $parcelas = @{ input = 'NAO_MENSURAVEL'; output = 'NAO_MENSURAVEL'; cache_creation = 'NAO_MENSURAVEL'; cache_read = 'NAO_MENSURAVEL'; trabalho = 'NAO_MENSURAVEL' }
    }
    # COBERTURA-13OUT1: tokens=-1 (envelope sem usage ou parse falho) NAO e zero. Antes o
    # chamador logava "acum inalterado" e seguia disparando lote sem medir (fail-open).
    # Regra: chamada que ENTREGOU (exit 0) sem usage = NAO_MENSURAVEL (fail-closed do dia,
    # FAILCLOSED-CONSUMO1). Chamada que FALHOU sem usage = ConsumoDesconhecidoFalha: o chamador
    # cobra a estimativa do lote no acumulado, com rotulo proprio.
    $consumoDesconhecidoFalha = $false
    if ($usoMensuravel -and ($null -eq $tokens -or $tokens -lt 0)) {
        if ($exitCode -eq 0 -and -not $providerFalhou) {
            $usoMensuravel = $false
            $tokens = $null
            $parcelas = @{ input = 'NAO_MENSURAVEL'; output = 'NAO_MENSURAVEL'; cache_creation = 'NAO_MENSURAVEL'; cache_read = 'NAO_MENSURAVEL'; trabalho = 'NAO_MENSURAVEL' }
        } else {
            $consumoDesconhecidoFalha = $true
            $tokens = -1
        }
    }
    # Falha de provedor em qualquer caminho (exit != 0 sem ser auth, que ja tem fluxo proprio).
    if ($exitCode -ne 0 -and -not $providerFalhou -and -not $authFail) {
        $providerFalhou = $true
        $__clsGen = Get-VixClasseFalhaProvider ('' + (@($raw) -join ' '))
        $providerClasse = $__clsGen.Classe; $providerSemPerspectiva = [bool]$__clsGen.SemPerspectiva
    }
    if ($providerOverrideAtivo) {
        [Environment]::SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', $providerProcessAnterior, 'Process')
    }
    return @{ Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; Parcelas = $parcelas; UsoMensuravel = $usoMensuravel; AuthFailure = $authFail; Escalou = $escalou; Degradados402 = $degradado402Lote; CotaEsgotada = $cotaEsgotadaSemFallback; CotaEsgotadaMotivo = $cotaEsgotadaMotivo; ProviderFalhou = $providerFalhou; ProviderClasse = $providerClasse; ProviderSemPerspectiva = $providerSemPerspectiva; ConsumoDesconhecidoFalha = $consumoDesconhecidoFalha }
}

function Get-NomeNormalizado([string]$s) {
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Trim()
}

function Get-ParsedResultados($outputLines) {
    $map = @{}
    $buscas = -1
    foreach ($line in @($outputLines)) {
        $t = ('' + $line).Trim()
        if ($t -match '^RESULTADO\|([^|]+)\|(\{.*\})\s*$') {
            $empName = Get-NomeNormalizado ($Matches[1].Trim())
            try { $obj = $Matches[2] | ConvertFrom-Json; if ($obj) { $map[$empName] = $obj } }
            catch { Write-Log ('AVISO: RESULTADO com JSON invalido para ' + $empName) }
        } elseif ($t -match '^LOTE_RESUMO\|buscas=(\d+)') {
            $buscas = [int]$Matches[1]
        } elseif ($t -match '^ANOTA\|(.+)$') {
            Write-Log ('ANOTA: ' + $Matches[1])
        }
    }
    return @{ Map = $map; Buscas = $buscas }
}

function Get-ResultadoEmissor($parsedMap, [string]$empresaPlano) { return $parsedMap[(Get-NomeNormalizado $empresaPlano)] }

# BUSCADEGRADADA1 (2026-09-08): busca web esgotada/indisponivel NAO e evidencia de "sem fato
# novo". O lote noturno de 08/09 provou o modo de falha: 15 emissores num POST unico com server
# tools, max_total_results=8 no adapter; apos 2 buscas bem-sucedidas o limite esgotou e 23 buscas
# seguiram com resultado literal "sem resultados - limite de busca". O motor contava essas como
# busca efetiva (nao casavam o regex antigo), o modelo classificava NENHUM/sem_eventos=true, e o
# emissor virava "analisado sem evento" no estado — feed preso em 04/09 com tudo verde.
# BUSCADEGRADADA1-REV (2026-09-09): a Vibra Energia na noturna real de 09/09 reafirmou
# sem_eventos com a unica busca degradada escrita pelo modelo como "sem retorno - limite
# backend" — redacao que o lexico abaixo nao cobria (so pegava "limite de busca"). Como a
# busca falhou no backend e o texto nao casava, ela contou como EFETIVA e o emissor saiu
# certificado NENHUM no mesmo dia em que a emissao de R$1,4 bi em debentures (08/09) circulava.
# Regra: so contam como DEGRADADA as respostas com evidencia EXPLICITA de falha/esgotamento
# (limite de busca, esgotad, max_total_results, restric.*busca, indisponivel, falha, erro,
# nao execut, timeout, sem retorno, limite backend, rate limit, 429). "sem resultados"
# generico (busca valida com zero achados) NAO e degradada: buscar e nao achar nada e
# resultado legitimo de busca efetiva.
# DRENOMUDO1 (2026-09-13): o dreno pos-rotina registrava "dreno concluido (exit=N)" com
# qualquer N. Em 13/09 saiu `POS-MATINAL: dreno concluido (exit=5)` depois de a verificacao
# assincrona morrer sem credencial, ou seja, palavra de sucesso carimbando fila NAO drenada.
# Quem le o log e quem procura falha passa a ver FALHOU com o codigo ao lado.
function Get-VixDrenoTexto {
    param(
        [Parameter(Mandatory)][string]$Rotina,
        [Parameter(Mandatory)][int]$ExitCode
    )
    $prefixo = 'POS-' + $Rotina.ToUpper() + ': dreno '
    if ($ExitCode -eq 0) { return ($prefixo + 'concluido (exit=0)') }
    return ($prefixo + 'FALHOU (exit=' + $ExitCode + ') - a fila de verificacao NAO foi drenada')
}

# DRENOMUDO1-FIX2 (2026-09-16): o dreno pos-rotina passa a ser uma funcao testavel, com o mesmo
# padrao das demais funcoes do motor extraidas por AST nos testes (test-varredura-defeitos.ps1 D5/D6,
# test-monitor-drenofalha.ps1). Antes, subir o filho, LER o exit code e escrever o desfecho existiam
# so inline no corpo do motor: nenhum teste offline conseguia provar o caminho do incidente de 13/09
# (dreno que morreu sem credencial saindo no log como "dreno concluido (exit=5)").
# Contrato: sobe o filho de verdade, devolve o exit code dele (-1 quando o processo nem sobe),
# escreve no log o desfecho por Get-VixDrenoTexto e a linha ERRO DRENO que o vigia le quando falha.
function Invoke-VixDrenoPosRotina {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$Rotina
    )
    Write-Log ('POS-' + $Rotina.ToUpper() + ': drenando fila de verificacao...')
    try {
        $verifProc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -PassThru -Wait -NoNewWindow
        # DRENOMUDO1 (2026-09-13): o codigo de saida do dreno e AVALIADO, nunca apenas citado.
        # Antes, exit=5 (dreno sem credencial) saia no log como "dreno concluido (exit=5)", ou
        # seja, falha com cara de sucesso.
        $exitCode = [int]$verifProc.ExitCode
    } catch {
        Write-Log ('POS-' + $Rotina.ToUpper() + ': ERRO ao executar dreno - ' + $_.Exception.Message)
        return -1
    }
    Write-Log (Get-VixDrenoTexto -Rotina $Rotina -ExitCode $exitCode)
    if ($exitCode -ne 0) {
        Write-Log ('ERRO DRENO: a fila de verificacao NAO foi drenada por esta rotina (exit=' + $exitCode + '). Log do dreno: logs/routines/vixradar-verificacao-async_' + $DateTag + '.log')
    }
    return $exitCode
}

# COBERTURAAUTH1 (2026-09-15): motivo do deferimento. Duas causas MUITO diferentes saem pela
# mesma porta do motor e ate hoje saiam com o mesmo rotulo, o que fazia um aborto por limite de
# sessao da assinatura ser lido como planejamento de cap de tokens.
#   cap_efetivo              -> planejado: o cap de tokens do dia (Get-VixCapEfetivo) foi
#                               alcancado e a cauda de menor EWS vai para a proxima execucao.
#   limite_sessao_assinatura -> NAO planejado: a assinatura estourou o limite de sessao no meio
#                               da execucao, o reset nao cabe no teto de parede e nao ha chave
#                               paga (Get-VixSessionLimitAcao, acao escalar_reset_longe). Os
#                               lotes que faltavam NAO foram chamados.
function Get-VixDeferidoMotivo([bool]$AbortoAuth) {
    if ($AbortoAuth) { return 'limite_sessao_assinatura' }
    return 'cap_efetivo'
}

# Linha DEFERIDOS do log. Mantem byte a byte o texto historico quando o motivo e cap_efetivo
# (ha leitura humana e historico de log dependendo dele) e acrescenta os dois campos que faltavam
# quando o corte veio da assinatura: o aviso de que o cap NAO foi a causa e o numero de lotes que
# o aborto deixou sem chamada.
function Get-VixDeferidosTexto {
    param(
        [Parameter(Mandatory)][string]$Motivo,
        [Parameter(Mandatory)][int]$Ok,
        [Parameter(Mandatory)][int]$Falha,
        [Parameter(Mandatory)][int]$Total,
        $TokensRealizados = 0,
        [int]$CapEfetivo = 0,
        [int]$LotesNaoProcessados = 0
    )
    $linha = 'DEFERIDOS: ok=' + $Ok + ' falha=' + $Falha + ' total=' + $Total + ' motivo=' + $Motivo + ' (' + $TokensRealizados + '/' + $CapEfetivo + ' realizados'
    if ($Motivo -ne 'cap_efetivo') { $linha += ' - o cap NAO foi a causa' }
    $linha += ')'
    if ($LotesNaoProcessados -gt 0) { $linha += ' lotes_nao_processados=' + $LotesNaoProcessados }
    return $linha
}

# COBERTURAAUTH1: declaracao observavel e acionavel de cobertura incompleta, com a DECISAO
# registrada por escrito (regra do operador, 15/09/2026): quando a assinatura estoura o limite de
# sessao, o reset nao cabe no teto de parede e nao ha chave paga, o motor DEFERE os emissores que
# sobraram COM PRIORIDADE GARANTIDA para a proxima execucao - nunca espera o reset dentro da
# mesma execucao (nao cabe no teto de parede) e nunca inventa cota. A garantia nao e promessa: o
# submit de deferido grava _token_cap_deferred=true e o Worker (DEFERREDREC1) devolve o emissor
# no plano seguinte como tier FULL motivo deferred_prioritario.
# Devolve '' quando o corte e planejado (cap_efetivo): a cauda por cap ja e esperada e anunciar
# isso como 'incompleto' fabricaria alarme diario.
function Get-VixCoberturaIncompletaTexto {
    param(
        [Parameter(Mandatory)][string]$Rotina,
        [Parameter(Mandatory)][string]$Motivo,
        [int]$Deferidos = 0,
        [int]$Plano = 0,
        [int]$LotesNaoProcessados = 0,
        [string]$DetalheAuth = ''
    )
    if ($Deferidos -le 0) { return '' }
    if ($Motivo -eq 'cap_efetivo') { return '' }
    $txt = 'COBERTURA_INCOMPLETA: ' + $Rotina + ' nao varreu ' + $Deferidos + '/' + $Plano + ' emissores - motivo=' + $Motivo
    if ($DetalheAuth) { $txt += ' (' + $DetalheAuth + ')' }
    if ($LotesNaoProcessados -gt 0) { $txt += ' - lotes_nao_processados=' + $LotesNaoProcessados }
    $txt += '. DECISAO: deferidos com prioridade garantida na proxima execucao (nao esperar o reset dentro desta, nao inventar cota)' +
        ' - o submit de deferido marca _token_cap_deferred=true e o Worker devolve o emissor como FULL/deferred_prioritario.' +
        ' Nenhum lote fica sem desfecho: os ' + $Deferidos + ' constam no ledger como DEFERIDO.'
    return $txt
}

# DRENOMUDO1-FIX (2026-09-15): o desfecho do dreno tem de existir no contrato do dia, nao so numa
# linha de log. Duas falhas medidas em 14/09: (1) quando o metrics ganhou o campo dreno_exit ele
# era serializado ANTES do dreno rodar, entao nascia null - os dois unicos metrics com o campo
# (matinal e noturno de 14/09) estao null com `dreno FALHOU (exit=5)` no log do mesmo dia;
# (2) o motor nao levantava alerta proprio nenhum pelo dreno - o e-mail de 14/09 veio da rotina
# de verificacao (ALERTA_AUTH dela), o que so acontece quando a causa do dreno e credencial.
# Esta funcao devolve o texto do alerta ('' quando nao ha o que alertar) e nunca lanca.
function Get-VixDrenoAlerta($ExitCode) {
    if ($null -eq $ExitCode) { return '' }
    if ([int]$ExitCode -eq 0) { return '' }
    return 'ALERTA_DRENO: dreno pos-rotina da fila de verificacao FALHOU (exit=' + [int]$ExitCode + ') - a fila NAO foi drenada por esta rotina; o proximo dreno agendado e a rede de seguranca'
}

# Escreve o desfecho do dreno no metrics do dia, depois de o dreno ter rodado. Nunca inventa
# campo em execucao que nao tentou o dreno ($null nao escreve) e nunca lanca: falha de escrita
# aqui nao pode derrubar o fechamento da rotina.
function Set-VixMetricsDrenoExit([string]$MetricsPath, $ExitCode) {
    if ($null -eq $ExitCode) { return $false }
    if (-not $MetricsPath) { return $false }
    if (-not (Test-Path -LiteralPath $MetricsPath)) { return $false }
    try {
        $j = Get-Content -LiteralPath $MetricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $j.dreno_exit = [int]$ExitCode
        ($j | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $MetricsPath -Encoding UTF8 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Test-VixBuscaDegradada([string]$resultadoTxt) {
    $iA = [char]0x00ED  # i com acento agudo
    $aT = [char]0x00E3  # a com til
    $re = 'limite de busca|esgotad|esgotou|max_total_results|restric.*busca|indisponivel|indispon' + $iA + 'vel|falha|erro|n[a' + $aT + ']o execut|timeout|sem retorno|limite backend|rate ?limit|429'
    return ('' + $resultadoTxt) -match $re
}

# Resolve a cobertura web de UM resultado de emissor. Efetiva = buscou e obteve resposta
# utilizavel (inclusive "nada na janela"); degradada = falha/esgotamento explicito
# (Test-VixBuscaDegradada). Vazia/ausente nao conta em nenhum dos dois.
# pendente = true quando NAO ha evento e a web nao entregou NENHUMA busca efetiva mas teve
# busca degradada: esse emissor NAO pode sair como "sem fato novo certificado" — vira
# INCONCLUSIVO e volta no fluxo normal (BUSCADEGRADADA1).
function Resolve-VixCoberturaWeb($res) {
    $efetivas = 0; $degradadas = 0
    foreach ($f in @($res.fontes_consultadas)) {
        $r = '' + $f.resultado
        if (-not $r -or $r -match '^vazio$') { continue }
        if (Test-VixBuscaDegradada $r) { $degradadas++ } else { $efetivas++ }
    }
    $temEventos = @($res.eventos).Count -gt 0
    $pendente = (-not $temEventos -and $efetivas -eq 0 -and $degradadas -gt 0)
    return [pscustomobject]@{ efetivas = $efetivas; degradadas = $degradadas; pendente = $pendente }
}

# COBERTURA1 (2026-09-09, decisao do operador): contrato persistido de cobertura por emissor/data.
# A prova de cada familia e MECANICA: so conta como "pesquisada com sucesso" uma fonte com os
# campos estruturais query/timestamp/provedor/status_http/resultado/classificacao, familia
# conhecida e classificacao ok. Texto do modelo sem esses campos (PROVAFALSA1) NAO prova nada:
# "busca realizada" por prosa, sem status http e classificacao, e tratada como NAO PESQUISADA.
# NENHUM/sem_eventos so e aceito quando F1-emissor, F2-divida/emissao/captacao e F3-fato/
# CVM/RI/fonte primaria foram pesquisadas com sucesso; familia ausente, degradada (429, rate
# limit, limite backend, sem retorno) ou resposta vazia anomalia => RECHECK_PENDENTE com
# faltantes e reanalise na proxima execucao (faltantes antes de itens novos), idempotente e
# sem duplicar, mantido na frente da fila ate ser resolvido (sem janela de 2 dias).
function Get-VixCoberturaProviderCapability([string]$Provedor) {
    # D2: allowlist de capability, nao uma excecao generica para campo HTTP nulo.
    $allowlist = @{
        'openrouter' = [pscustomobject]@{ requer_http = $true; contrato = 'cobertura_http_provider_openrouter' }
        'codex' = [pscustomobject]@{ requer_http = $false; contrato = 'cobertura_parcial_provider_codex' }
        # COBERTURA-13OUT1: consulta feita pelo ORQUESTRADOR (coletor RSS), HTTP real medido.
        # Exige status_http 2xx como o openrouter; nao e excecao de capability.
        'coletor' = [pscustomobject]@{ requer_http = $true; contrato = 'cobertura_http_coletor_rss' }
    }
    $base = ('' + $Provedor).Trim().ToLowerInvariant().Split(':')[0]
    if (-not $allowlist.ContainsKey($base)) { return $null }
    return $allowlist[$base]
}

function ConvertTo-VixFonteEstrutural($f) {
    # Normaliza UMA fonte em @{ familia; ok; motivo }. Falha estrutural = sem_prova (nao conta).
    $out = [pscustomobject]@{ familia = 'desconhecida'; ok = $false; motivo = 'sem_prova' }
    if ($null -eq $f) { return $out }
    $fam = ('' + $f.familia).Trim().ToLowerInvariant()
    if ($fam -notin @('emissor', 'divida', 'fato')) { $out.motivo = 'sem_prova_sem_familia'; return $out }
    $q = ('' + $f.query).Trim()
    $ts = ('' + $f.timestamp).Trim()
    $prov = ('' + $f.provedor).Trim()
    $capability = Get-VixCoberturaProviderCapability $prov
    if ($null -eq $capability) { $out.motivo = 'sem_prova_provedor_desconhecido'; return $out }
    if ($null -eq $f.PSObject.Properties['status_http']) { $out.motivo = 'sem_prova_sem_status_http'; return $out }
    $httpRaw = '' + $f.status_http
    $http = 0
    $semHttpPermitido = (-not $capability.requer_http -and $null -eq $f.status_http)
    if (-not $semHttpPermitido -and -not [int]::TryParse($httpRaw, [ref]$http)) { $out.motivo = 'sem_prova_sem_status_http'; return $out }
    $res = ('' + $f.resultado).Trim()
    $cl = ('' + $f.classificacao).Trim().ToLowerInvariant()
    if (-not $q -or -not $ts -or -not $prov -or -not $res) { $out.motivo = 'sem_prova_campo_vazio'; return $out }
    if ($res -eq 'vazio') { $out.motivo = 'resposta_vazia_anomalia'; return $out }
    $okHttp = ($semHttpPermitido -or ($http -ge 200 -and $http -lt 300))
    $okCl = ($cl -in @('ok', 'efetiva', 'sucesso', 'valida'))
    if (-not $okHttp) { $out.motivo = ('degradada_http_' + $http); return $out }
    if (-not $okCl) { $out.motivo = ('degradada_classificacao_' + $cl); return $out }
    if (Test-VixBuscaDegradada $res) { $out.motivo = 'degradada_conteudo'; return $out }
    $out.familia = $fam
    $out.ok = $true
    if ($semHttpPermitido) {
        $out.motivo = 'ok_sem_http_provider'
        $out | Add-Member -NotePropertyName cobertura_parcial -NotePropertyValue $true
        $out | Add-Member -NotePropertyName contrato_provedor -NotePropertyValue $capability.contrato
    } else {
        $out.motivo = 'ok'
        $out | Add-Member -NotePropertyName cobertura_parcial -NotePropertyValue $false
        $out | Add-Member -NotePropertyName contrato_provedor -NotePropertyValue $capability.contrato
    }
    return $out
}

function Resolve-VixCoberturaFamilias($res) {
    # F1 emissor, F2 divida (divida|debentures|emissao|captacao), F3 fato (CVM/RI/fonte primaria).
    # Retorna @{ ok; faltantes = [string[]]; n_provas = int }.
    $okFam = @{ 'emissor' = $false; 'divida' = $false; 'fato' = $false }
    $nProvas = 0; $contratosParciais = @()
    foreach ($f in @($res.fontes_consultadas)) {
        $e = ConvertTo-VixFonteEstrutural $f
        if ($e.ok) {
            $okFam[$e.familia] = $true; $nProvas++
            if ($e.cobertura_parcial -and $e.contrato_provedor -notin $contratosParciais) { $contratosParciais += $e.contrato_provedor }
        }
    }
    $faltantes = @()
    foreach ($fam in @('emissor', 'divida', 'fato')) { if (-not $okFam[$fam]) { $faltantes += $fam } }
    return [pscustomobject]@{ ok = ($faltantes.Count -eq 0); faltantes = $faltantes; n_provas = $nProvas; cobertura_parcial = ($contratosParciais.Count -gt 0); contratos_provedor = $contratosParciais }
}

# BUSCADEGRADADA1-FIX (2026-09-09, decisao do operador): sem_eventos NUNCA pode sair quando
# QUALQUER busca do emissor falhou, degradou, esgotou, deu timeout ou ficou insuficiente.
# Ausencia de fato so e certificavel com busca valida E suficiente (3 familias ok, 0 degradadas).
# Com evento, o fluxo normal nao e tocado. Emissor bloqueado vira RECHECK_PENDENTE persistido
# no contrato do dia (mesmo arquivo do COBERTURA1) e a priorizacao existente o recoloca no
# inicio da fila da proxima execucao. Repeticao nao afrouxa: o gate nao tem excecao por
# recorrencia — 100 dias degradados = 100 dias INCONCLUSIVO/RECHECK_PENDENTE, nunca sem_eventos.
function Test-VixAusenciaCertificavel($res) {
    if (@($res.eventos).Count -gt 0) { return [pscustomobject]@{ permitir_sem_eventos = $true; recheck = $false; motivo = 'com_evento'; faltantes = @() } }
    $cob = Resolve-VixCoberturaWeb $res
    if ($cob.degradadas -gt 0) { return [pscustomobject]@{ permitir_sem_eventos = $false; recheck = $true; motivo = 'busca_degradada'; faltantes = @('web') } }
    $fam = Resolve-VixCoberturaFamilias $res
    if (-not $fam.ok) { return [pscustomobject]@{ permitir_sem_eventos = $false; recheck = $true; motivo = 'familias_incompletas'; faltantes = @($fam.faltantes) } }
    return [pscustomobject]@{ permitir_sem_eventos = $true; recheck = $false; motivo = 'cobertura_valida'; faltantes = @() }
}

# Contrato persistido em logs\routines\cobertura_YYYYMMDD.json (RECHECK_PENDENTE/RESOLVIDO por cobertura).
function Get-VixContratoCoberturaPath([string]$tag) {
    return Join-Path $LogDir ('cobertura_' + $tag + '.json')
}

function Read-VixContratoCoberturaArquivo([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try { $o = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json; if ($o -and $o.emissores) { return $o.emissores } } catch { }
    return $null
}

# BUSCADEGRADADA1-FIX (2026-09-10, decisao do operador): RECHECK_PENDENTE vale ATE SER
# RESOLVIDO, sem janela de 2 dias. Le TODOS os cobertura_*.json do diretorio, do mais novo
# para o mais antigo, e resolve cada emissor pelo registro MAIS RECENTE dele (o primeiro que
# aparece na varredura). Uma pendencia de sexta continua na frente na segunda, coisa que a
# janela fixa de hoje/ontem descartava. Um registro novo com faltantes vazio (RESOLVIDO)
# devolve o emissor a fila normal, entao a prioridade nao fica presa para sempre. Ausencia
# nao resolve: emissor que nao voltou a ser analisado mantem a pendencia viva.
# A leitura e por PSObject.Properties porque o JSON volta como PSCustomObject e `.Values`
# nao existe nesse tipo: era por isso que a varredura antiga nao enxergava contrato gravado.
function Get-VixRecheckPendentes([string]$pasta) {
    $pend = @{}
    $visto = @{}
    foreach ($arq in @(Get-ChildItem -Path $pasta -Filter 'cobertura_*.json' -File -ErrorAction SilentlyContinue | Sort-Object -Property Name -Descending)) {
        $em = Read-VixContratoCoberturaArquivo $arq.FullName
        if (-not $em) { continue }
        foreach ($prop in @($em.PSObject.Properties)) {
            $e = $prop.Value
            if ($null -eq $e -or -not $e.empresa) { continue }
            $k = Get-NomeNormalizado ('' + $e.empresa)
            if ($visto.ContainsKey($k)) { continue }
            $visto[$k] = $true
            if (@($e.faltantes).Count -gt 0) { $pend[$k] = $true }
        }
    }
    return $pend
}

function Merge-VixContratoCobertura($alvo, [string]$empresa, [string]$status, [string[]]$faltantes) {
    # Idempotente: mesma empresa/data so atualiza a entrada (nunca duplica).
    # TRIADOMERGE1 (2026-10-15): `triado` e pegajoso (ver Set-VixContratoEstado) e esta funcao
    # reescrevia a entrada sem ele. Todo emissor triado que passava por RECHECK_PENDENTE ou
    # RESOLVIDO perdia a prova da triagem, e o Set-VixContratoEstado seguinte ja lia `triado`
    # ausente. Medido na noturna de 15/10 18:05: os 9 analisados sairam triado=False e a
    # reconciliacao fechou DIVERGENTE `triados:92<101` com os 101 elegiveis triados no log.
    $k = Get-NomeNormalizado $empresa
    $jaTriado = $null
    if ($alvo.ContainsKey($k)) {
        $ant = $alvo[$k]
        if ($ant -is [System.Collections.IDictionary]) { if ($ant.Contains('triado')) { $jaTriado = [bool]$ant['triado'] } }
        elseif ($null -ne $ant -and $null -ne $ant.PSObject.Properties['triado']) { $jaTriado = [bool]$ant.triado }
    }
    $novo = @{
        empresa = $empresa; status = $status
        faltantes = @($faltantes); updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($null -ne $jaTriado) { $novo['triado'] = $jaTriado }
    $alvo[$k] = $novo
}

function New-BatchPrompt($batch, $batchLabel, $modelName, $skillPath, $janelaInicio, $janelaFim, [string]$FonteProvedor = 'openrouter', [switch]$Ultra, [string]$Tier = '', [switch]$ModoEscalada, [switch]$ModoBarato) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissor $_ -Tier $Tier -Ultra:$Ultra })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    $instrucaoCobertura = @"
COBERTURA (OBRIGATORIO, COBERTURA1): para CADA emissor execute ao menos 1 consulta por familia, nesta ordem: F1-emissor (web_search: nome + contexto/fato conhecido), F2-divida (web_search: divida|debentures|emissao|captacao|titulos), F3-fato (CVM/RI/fato relevante/fonte primaria na janela). F3FETCH1 - MECANISMO DA F3: fetch-first com fallback obrigatorio. Se o emissor tem link em cvm_documentos[], faca web_fetch no documento mais relevante da janela (fonte primaria, sem custo de busca) - 1 (UM) fetch nesta familia. SEM link no JSON, OU web_fetch que falha / devolve erro / conteudo vazio / PDF binario ilegivel: execute web_search na F3 imediatamente - a familia F3 NUNCA fica sem consulta executada. PROIBIDO substituir o fetch falho por fetch de OUTRA URL (homepage RI, site institucional): o fallback da F3 e SEMPRE web_search. Cada item de fontes_consultadas DEVE ser objeto com TODOS os campos: "familia":"emissor|divida|fato", "query":"...", "timestamp":"YYYY-MM-DDTHH:MM:SSZ", "provedor":"$($FonteProvedor):web_search|web_fetch", "status_http":200, "resultado":"<resposta textual da consulta>", "classificacao":"ok". Item de web_fetch: query = a URL primaria fetchada; provedor = "$($FonteProvedor):web_fetch" (prefixo completo, NUNCA so "web_fetch"); status_http 200 somente quando a tool devolveu conteudo (status completed); resultado = o que o documento diz de fato na janela (data_evento sai dele, FONTEDIVERG1). Fetch que falhou NAO vira item de fontes_consultadas e NUNCA sustenta a familia: a F3 fica com a busca de fallback que rodou de verdade (provedor "$($FonteProvedor):web_search"). SAIDA JSON SEM QUEBRA DE LINHA DENTRO DO OBJETO: cada linha RESULTADO| e uma unica linha com JSON compacto, sem \n interno (quebra interna faz o parser perder o emissor inteiro). EXCECAO DE CAPABILITY DECLARADA: somente provedor "codex" pode emitir "status_http":null porque o Codex CLI nao publica HTTP; nesse caso mantenha todos os outros campos e classificacao "ok", e a cobertura sera marcada parcial sob o contrato provider_codex_sem_http. Todo outro provedor exige status_http inteiro 2xx. PROIBIDO (PROVAFALSA1): registrar consulta que nao executou, inventar status_http/resultado/timestamp ou omitir campos; busca que falhou (429, rate limit, limite backend, sem retorno, resposta vazia) vai com status_http real e classificacao "degradada", nunca "ok". "Pesquisada sem evento" = resultado ok descrevendo o que achou (ex.: "nada na janela apos X"); "nao pesquisada" = familia ausente.
"@
    $linhaBuscas = 'Ultima linha: LOTE_RESUMO|buscas=<total de consultas executadas: web_search + web_fetch>'
    # RECHECKDIVERG1 (2026-10-15): veredito por manchete. Vale para a rodada barata e para a
    # escalada, porque a conferencia de divergencia roda depois de qualquer lote com coletor.
    $instrucaoVeredito = ''
    if ($script:VixColetorAtivo) {
        $instrucaoVeredito = 'VEREDITO POR MANCHETE (RECHECKDIVERG1, OBRIGATORIO): quando o emissor tiver "manchetes_exigem_veredito" no JSON, inclua no objeto resultado o campo "vereditos_manchetes" com UM objeto por id da lista: {"id":"<id exatamente como na lista>","veredito":"sem_efeito_credito|evento|ruido_homonimo","motivo":"<uma linha: o que a manchete diz e por que tem ou nao efeito de credito>"}. O id aparece na linha da manchete em evidencia_coletada (id=...). sem_efeito_credito = cita o emissor mas nao muda risco de credito (resultado operacional comum, premio, evento institucional). ruido_homonimo = a manchete e sobre outra coisa com o mesmo nome. evento = a manchete descreve fato de credito novo e esse fato DEVE estar em eventos[]. Id sem veredito, veredito fora destes tres, ou evento sem item em eventos[] mantem o emissor INCONCLUSIVO. Nao invente id que nao esta na lista.'
    }
    # COBERTURA-13OUT4: lote de ESCALADA. Estes emissores vieram da rodada barata com fato novo,
    # divergencia ou cobertura nao certificavel, e por isso recebem ferramenta de volta. O texto
    # e explicito em duas coisas que o pacote barato nao podia fazer: abrir a fonte primaria e
    # NUNCA certificar ausencia a partir de EVIDENCIA_INDISPONIVEL do coletor.
    if ($ModoEscalada) {
        $instrucaoCobertura = @"
ESCALADA_FULL (COBERTURA-13OUT4): este emissor veio do pacote barato (coleta do orquestrador sem fonte primaria) por fato novo, divergencia ou cobertura nao certificavel. NESTA passada voce TEM ferramenta. Execute o contrato de tres familias (F1-emissor, F2-divida, F3-fato) e OBRIGATORIAMENTE abra a fonte primaria antes de classificar: primeiro web_fetch na URL do fato novo quando houver link (documento em cvm_documentos[] ou link em pistas_triagem); sem link, web_search ancorado no mes corrente e web_fetch da materia. A manchete herdada do pacote barato ("evidencia_coletada", "pistas_triagem") e PISTA, nao prova: o que sustenta a classificacao e o conteudo que voce abriu, e data_evento sai dele, nunca da busca (FONTEDIVERG1). Cada item de fontes_consultadas DEVE ser objeto com TODOS os campos: "familia":"emissor|divida|fato", "query":"...", "timestamp":"YYYY-MM-DDTHH:MM:SSZ", "provedor":"$($FonteProvedor):web_search|web_fetch", "status_http":200, "resultado":"<resposta textual da consulta>", "classificacao":"ok". Busca ou fetch que falhou vai com status_http real e classificacao "degradada", nunca "ok" (PROVAFALSA1). Se o fato da pista NAO se confirmar na fonte, diga isso em cobertura_nota e devolva a classificacao que a fonte sustenta - nao invente evento para justificar a escalada. Se o coletor devolveu EVIDENCIA_INDISPONIVEL, isso NUNCA certifica "NENHUM"/sem_eventos: nesse caso a classificacao minima e INCONCLUSIVO, com cobertura_nota explicando o que faltou. SAIDA JSON SEM QUEBRA DE LINHA DENTRO DO OBJETO: cada linha RESULTADO| e uma unica linha com JSON compacto, sem \n interno.
"@
    }
    # COBERTURA-13OUT4: o modo barato e explicito por LOTE, nunca inferido do tier. Motivo
    # medido: com o coletor ligado o texto de proibicao de ferramenta valia para TODO lote, e o
    # lote FULL da rotacao semanal noturna - cuja razao de existir e abrir a fonte primaria -
    # sairia sem ferramenta, entregando profundidade FULL no rotulo e coleta barata no conteudo.
    # O tier nao serve para decidir isto: a matinal rotula os proprios lotes como FULL, e nela o
    # lote barato E o rotulado FULL. Quem decide e o chamador, marcando o lote da rodada barata.
    elseif ($ModoBarato -and $script:VixColetorAtivo) {
        $instrucaoCobertura = @"
COLETOR_PS_ATIVO: a busca ja foi executada pelo orquestrador. Use somente "evidencia_coletada", "cvm_documentos" e "contexto_historico" do JSON. PROIBIDO executar WebSearch, WebFetch, ferramenta de busca ou fetch. Em "fontes_consultadas", registre somente fonte que esta nesses campos, copiando familia, data, veiculo e dominio quando houver evidencia coletada. Nao invente URL, query, veiculo, dominio, data, status HTTP ou resultado. "cobertura_familias" informa contagens observadas, nao uma garantia de cobertura. EVIDENCIA_VAZIA significa que as consultas terminaram e nao acharam publicacao na janela, podendo retornar classificacao_geral "NENHUM", sem_eventos true e cobertura_nota correspondente. EVIDENCIA_INDISPONIVEL significa falha de coleta e NUNCA certifica NENHUM ou sem_eventos, devendo registrar cobertura indisponivel. A saida do lote deve registrar buscas=0.
"@
        $linhaBuscas = 'Ultima linha: LOTE_RESUMO|buscas=0'
    }
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais. Sem chamadas HTTP de submit - o orquestrador grava os resultados.
JANELA: $janelaInicio a $janelaFim
DELTA - nao recrie fato conhecido (FEEDRETRO1): cada emissor no JSON abaixo tem ultimo_evento_data, eventos_conhecidos e janela_delta_inicio. Primeira busca com ancora de recencia (mes e ano correntes, nao termo generico), procure primeiro fato com data_evento >= janela_delta_inicio. So achar fato ja em eventos_conhecidos, mesmo com URL diferente da que esta la: eventos=[], cobertura_nota="sem fato novo desde <ultimo_evento_data>, confirmado <o que achou>". Continuacao de saga conhecida (nova decisao judicial, novo prazo, nova negociacao, nova acao de rating sobre o MESMO caso) e evento NOVO com a data do fato de agora, nunca dobra no protocolo antigo.

DATA - sai da fonte, nunca da busca (FONTEDIVERG1): data_evento e a data em que o fato ocorreu ou foi publicado pela fonte que voce esta citando, lida no proprio conteudo (data no topo da materia, data no path da URL, protocolo CVM). Encontrar a materia numa busca ancorada no mes corrente NAO a torna do mes corrente: a ancora estreita a busca, nao data o resultado. Sem conseguir confirmar a data de publicacao, trate como fato conhecido (eventos=[]) em vez de carimbar hoje. Medido em 04/09/2026: a Kora Saude voltou com data_evento=2026-09-04 citando materia cujo article:published_time no HTML era 2026-05-05.
PROIBIDO: markdown, tabelas, backticks, headers, narrativa, texto fora do protocolo abaixo.
$instrucaoCobertura
$instrucaoVeredito
SAIDA - exatamente estas linhas e nada mais:
1 linha por emissor: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases, o que aconteceu - alimenta o card do usuario E o contexto_historico da rotina de amanha), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir). Sem esses 3 campos preenchidos o evento fica incompleto - nao omitir.
$linhaBuscas
Anomalia operacional (opcional, max 1): ANOTA|<frase curta>
Exemplo literal de saida completa para lote de 2 emissores:
RESULTADO|Empresa A|{"classificacao_geral":"ECO","sem_eventos":true,"cobertura_nota":"R2 sem sinal de credito na janela.","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"Empresa A divida rating","resultado":"sem eventos"}]}
RESULTADO|Empresa B|{"classificacao_geral":"RELEVANTE","sem_eventos":false,"cobertura_nota":"","eventos":[{"classificacao":"RELEVANTE","titulo":"Emissao de debentures","evento":"...","impacto_credito":"...","memo_acontecimento":"Empresa B emitiu R$500mi em debentures em 01/07 para rolagem de divida de curto prazo.","memo_importancia_credito":"Reduz risco de refinanciamento no curto prazo, sem piora de alavancagem.","memo_monitorar":"Prazo e taxa da nova emissao vs divida anterior.","fonte_primaria":"https://exemplo.com/materia-especifica","fonte_tipo":"IMPRENSA","data_evento":"2026-07-01","data_aproximada":false,"tags":["emissao"]}],"fontes_consultadas":[{"rodada":"R2","query":"Empresa B debentures","resultado":"emissao confirmada"},{"rodada":"R6","query":"Empresa B rating","resultado":"sem acao de rating"}]}
LOTE_RESUMO|buscas=3

JSON:
$json

$skill
"@
}

function Remove-BatchPrompts([string]$tag) {
    Get-ChildItem $LogDir -Filter ($Perfil.prefix + '_*_' + $tag + '.txt') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike ($Perfil.prefix + '_stderr_*') -and $_.Name -notlike ($Perfil.prefix + '_transcript_*') } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LogDir ($Perfil.prefix + '_plano_' + $tag + '.json')) -Force -ErrorAction SilentlyContinue
}

function Write-Ledger([string]$emp, [string]$tier, [string]$classif, [int]$nEv, [bool]$subOk, [string]$status, [int]$nAvancoData = 0) {
    # FEEDRETRO1 FASE2 (2026-09-04): campo novo NO FINAL da linha, para nao deslocar os
    # indices que Get-VixLedgerEmissoresNaJanela e Test-VixLedgerEntregueNaJanela ja usam
    # (regex por posicao fixa dos 6 campos originais). SKIP e DEFERIDO sempre mandam 0
    # (nunca analisam, nunca avancam data); ANALISADO manda o n_eventos_avanco_data que
    # o Worker devolveu nesta submissao.
    $pfx = if ($DryRun) { 'DRYRUN|' } else { 'OK|' }
    Write-Log ($pfx + $emp + '|' + $tier + '|' + $classif + '|' + $nEv + '|' + $subOk.ToString().ToLower() + '|' + $status + '|' + $nAvancoData)
    # IDEMEFETIVA1: o que ESTA execucao escreveu no ledger, para a reconciliacao por execucao.
    if (-not $DryRun) { $script:VixLedgerExec[(Get-NomeNormalizado $emp)] = $status }
}
$script:VixLedgerExec = @{}
$script:VixContratoExec = @{}
$script:VixIdemReabertos = 0
$script:VixElegiveisExec = -1

# CLAUDE-FREE-MIGRATION (2026-09-04): Claude nao e mais requisito operacional. Sem provider
# manual forcado (VIXRADAR_LLM_PROVIDER='claude-manual' + -ForceClaude), esta rotina bloqueia
# AQUI com exit 86, antes de mutex, lock de arquivo, sonda, auth ou claude. Scheduler nunca
# passa -ForceClaude, entao provider 'none' (default) ou 'claude-manual' sem flag = bloqueio.
# Fase B D1 (2026-09-04): provider 'openrouter' libera a execucao pelo adapter HTTP proprio
# (lib\vixradar-openrouter.ps1), sem claude, sem auth Anthropic, sem escalacao paga.
$script:VixUsaOpenRouter = (Test-VixUsaLlmAdapterHttp)
$__anthropicFallbackProvider = [Environment]::GetEnvironmentVariable('VIXRADAR_OPENROUTER_FALLBACK_PROVIDER', 'Process')
if (-not $__anthropicFallbackProvider) { $__anthropicFallbackProvider = [Environment]::GetEnvironmentVariable('VIXRADAR_OPENROUTER_FALLBACK_PROVIDER', 'User') }
if (-not $__anthropicFallbackProvider) { $__anthropicFallbackProvider = [Environment]::GetEnvironmentVariable('VIXRADAR_OPENROUTER_FALLBACK_PROVIDER', 'Machine') }
$script:VixOpenRouterFallbackAnthropic = (((Get-VixLlmProvider) -eq 'openrouter') -and (('' + $__anthropicFallbackProvider).Trim().ToLowerInvariant() -eq 'claude-subscription'))
$script:VixUsaCodex = ((Get-VixLlmProvider) -eq 'codex')
$openRouterAdapterHabilitado = ($script:VixLibOpenRouterOk -and (Get-Command 'Invoke-VixOpenRouterLote' -ErrorAction SilentlyContinue) -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue))
$codexAdapterHabilitado = ($null -ne (Get-Command 'codex' -ErrorAction SilentlyContinue))
if (-not (Test-VixLlmProviderPermiteRotina -ForceClaude:$ForceClaude -OpenRouterAdapterHabilitado:$openRouterAdapterHabilitado -CodexAdapterHabilitado:$codexAdapterHabilitado)) {
    if ($script:VixUsaOpenRouter) {
        Write-Log 'ERRO FATAL: adapter OpenRouter ausente ou incompleto (scripts/lib/vixradar-openrouter.ps1). Provider openrouter sem adapter = bloqueio.'
    }
    else {
        Write-Log (Get-VixLlmBloqueadoMsg ('run_vixradar_varredura.ps1 ' + $Rotina))
    }
    exit $VixLlmBloqueadoExit
}
# COBFALLBACK1: o gate acima continua valendo com o provider REAL (provider 'none' bloqueia o
# fallback tambem). Passado o gate, esta execucao e Claude pela assinatura e nada mais: o provider
# do PROCESSO vira claude-subscription (nunca o registro User), sem desvio para OpenRouter nem
# Codex. Com claude-subscription a lib de auth nao entrega chave paga (ANTHROPIC_API_PAYG).
$script:VixCobFallbackProviderOriginal = [Environment]::GetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'Process')
if ($script:VixCobFallbackModo) {
    [Environment]::SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'claude-subscription', 'Process')
    $script:VixUsaOpenRouter = $false
    $script:VixUsaCodex = $false
    $script:VixOpenRouterFallbackAnthropic = $false
}

if (-not (Test-Path $Perfil.skill)) { Write-Log ('ERRO: skill ausente ' + $Perfil.skill); exit 1 }

# PLANTAO1 (2026-10-19, decisao do operador): sabado, domingo e feriado B3 nao rodam
# varredura. A matinal (diaria no Scheduler) vira plantao: delega para a Sentinela com
# -Plantao, que so analisa se houve acervo novo da CVM, e fecha com a linha canonica
# 'FIM: matinal plantao ...' que o monitor reconhece. A noturna (seg-sex) segue com o SKIP
# de feriado de antes. Ate 18/10 a matinal rodava a varredura cheia no fim de semana e
# pulava tudo no feriado, inclusive qualquer checagem.
. (Join-Path $PSScriptRoot 'lib\vixradar-plantao.ps1')
if (-not (Get-Command Get-VixModoDia -ErrorAction SilentlyContinue)) { Write-Log 'ERRO: lib\vixradar-plantao.ps1 ausente ou sem Get-VixModoDia'; exit 1 }
$__dataDia = Get-Date
if ($SimularData) {
    if ($DryRun) { $__dataDia = [datetime]::ParseExact($SimularData, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    else { Write-Log ('AVISO: -SimularData ' + $SimularData + ' ignorado fora de -DryRun') }
}
$__modoDia = Get-VixModoDia -Data $__dataDia -Feriados (Get-VixFeriadosB3)
# Noturna: so o feriado pula, com a linha de sempre. Ela nao e agendada no fim de semana, e
# chamada manual nesses dias (reposicao) continua permitida como antes.
if ($__modoDia -eq 'feriado' -and $Rotina -eq 'noturno' -and -not $DryRun) {
    Write-Log ('SKIP: feriado B3. FIM: ' + $Rotina + ' pulado por feriado. Total do dia 0/0. analisados=0 skip=0 deferidos=0 submits_aceitos=0')
    exit 0
}
if ($__modoDia -ne 'util' -and $Rotina -eq 'matinal' -and -not $IgnorarPlantao) {
    if ($CoberturaFallbackClaude) {
        Write-Log ('SKIP: plantao ' + $__modoDia + ', fallback de cobertura nao roda em dia nao util. FIM_PLANTAO_FALLBACK: nada executado')
        exit 0
    }
    $__sentScript = Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1'
    Write-Log ('PLANTAO: ' + $__dataDia.ToString('yyyy-MM-dd') + ' e ' + $__modoDia + '. Sem varredura; checagem de evento extraordinario pela Sentinela -Plantao.')
    if ($DryRun) {
        Write-Log ('FIM_DRYRUN: matinal plantao modo=' + $__modoDia + ' chamaria ' + $__sentScript + ' -Plantao. tokens=0')
        exit 0
    }
    $__sentArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $__sentScript, '-Plantao')
    if ($ForceClaude) { $__sentArgs += '-ForceClaude' }
    & powershell.exe @__sentArgs | Out-Null
    $__sentExit = $LASTEXITCODE
    if ($null -eq $__sentExit) { $__sentExit = 1 }
    $__sentLog = Join-Path $LogDir ('vixradar-sentinela_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $__sentFim = ''
    try { $__sentFim = Get-VixSentinelaUltimoFim @(Get-VixLogDiaLinhas $__sentLog) } catch { $__sentFim = '' }
    Write-Log (Get-VixPlantaoFimLinha -Modo $__modoDia -ExitSentinela ([int]$__sentExit) -FimSentinela $__sentFim)
    exit (Get-VixPlantaoExit -ExitSentinela ([int]$__sentExit) -FimSentinela $__sentFim)
}

# Mutex global: nunca duas instancias da mesma rotina (incidente 2026-07-06).
$__mutex = New-Object System.Threading.Mutex($false, $Perfil.mutex)
if (-not $__mutex.WaitOne(0)) {
    Write-Log ('ABORT: outra instancia da ' + $Rotina + ' ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens')
    exit 0
}

# Espera pela sentinela (ela roda ate 22 min a partir de :25/:55 e a noturna comeca 18h05).
$__sentMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-sentinela-v1')
$__esperou = 0
while (-not $__sentMutex.WaitOne(0)) {
    if ($__esperou -eq 0) { Write-Log ('AGUARDANDO sentinela: mutex Global\vixradar-sentinela-v1 ocupado, esperando ate ' + $EsperaSentinelaMaxMin + ' min') }
    if ($__esperou -ge ($EsperaSentinelaMaxMin * 2)) { Write-Log 'AVISO: sentinela ainda ocupada apos o limite de espera - seguindo mesmo assim (o lock de arquivo abaixo segura a proxima sentinela)'; break }
    Start-Sleep -Seconds 30
    $__esperou++
}
if ($__sentMutex.WaitOne(0)) { $__sentMutex.ReleaseMutex() }
if ($__esperou -gt 0) { Write-Log ('sentinela livre apos ' + ($__esperou * 30) + 's') }

# DRYRUN-PROBE1 (10/09/2026, regra do operador): o probe tem log e lock proprios e NUNCA
# bloqueia a execucao real (nome diferente, logo abaixo). A reciproca tambem vale: com execucao
# real viva, o probe nao roda em cima dela. ANTES de olhar o proprio lock, o probe consulta o
# lock REAL e sai limpo AQUI - antes do boot do provider, sem rede e sem token. A execucao real
# nao consulta lock de probe em momento nenhum.
if ($DryRun) {
    $LockReal = Join-Path $LogDir ('vixradar-' + $RotinaArq + '_' + $DateTag + '.lock')
    $__lockReal = Get-VixLockState $LockReal $LockAbandonoMin
    if ($__lockReal.bloqueia) {
        Write-Log ('ABORT: lock real ' + (Split-Path $LockReal -Leaf) + ' pid=' + $__lockReal.pid + ' ' + $__lockReal.motivo + ' (execucao real viva) - probe sai antes de provider/network/tokens')
        $__mutex.ReleaseMutex()
        exit 0
    }
    if ($__lockReal.motivo -like 'LOCK_ORFAO_*' -and $__lockReal.motivo -ne 'LOCK_ORFAO_AUSENTE') {
        Write-Log ('LOCK_ORFAO: lock real ' + (Split-Path $LockReal -Leaf) + ' pid=' + $__lockReal.pid + ' motivo=' + $__lockReal.motivo + ' - probe assume')
    }
}

# D1: somente PID vivo com StartTime igual bloqueia. Idade do arquivo nao prova vida.
$__lockAtual = Get-VixLockState $LockFile $LockAbandonoMin
if ($__lockAtual.bloqueia) {
    Write-Log ('ABORT: lock ' + (Split-Path $LockFile -Leaf) + ' pid=' + $__lockAtual.pid + ' ' + $__lockAtual.motivo + ' (outra execucao viva) - saindo limpo em 0 tokens')
    $__mutex.ReleaseMutex()
    exit 0
}
if ($__lockAtual.motivo -like 'LOCK_ORFAO_*' -and $__lockAtual.motivo -ne 'LOCK_ORFAO_AUSENTE') {
    Write-Log ('LOCK_ORFAO: ' + (Split-Path $LockFile -Leaf) + ' pid=' + $__lockAtual.pid + ' motivo=' + $__lockAtual.motivo + ' - assumindo lock')
}
try {
    ("source=run_vixradar_varredura.ps1`nrotina=$Rotina`npid=$PID`ninicio_utc=" + (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o') + "`ndryrun=$DryRun") | Set-Content -Path $LockFile -Encoding UTF8 -ErrorAction Stop
    Write-Log ('LOCK_OK: ' + (Split-Path $LockFile -Leaf) + ' criado com pid e inicio_utc, toque a cada lote')
} catch {
    Write-Log ('AVISO: nao consegui escrever o lock ' + $LockFile + ' - ' + $_.Exception.Message)
}

$modoTxt = if ($DryRun) { 'DRYRUN' } else { 'real' }
# DRYRUN-CRASH1: em dry-run a linha vira DRYRUN_ALERTA_AUTH para o monitor (9004) nao tratar teste como incidente.
$AlertaAuthTag = if ($DryRun) { 'DRYRUN_ALERTA_AUTH: ' } else { 'ALERTA_AUTH: ' }
Write-Log ('INICIO: ' + $Rotina + ' (motor Task Scheduler, run_vixradar_varredura.ps1, modo=' + $modoTxt + ') tier=' + $Perfil.tier + ' modelo=' + $Perfil.model + ' lote=' + $Perfil.chunk + ' cap_proprio=' + $Perfil.capProprio)
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

if ($SimularTokenVencido) {
    if (-not $DryRun) {
        Write-Log 'ERRO: -SimularTokenVencido so e aceito com -DryRun (nunca contra submissao real).'
        exit 1
    }
    # So no processo, nunca no registro: a lib le o env do processo antes do registro User.
    # Placebo montado em dois pedacos: nao e credencial, e o gate de segredo do pre-commit
    # (RX_ANTHROPIC) nao pode ver o formato inteiro no fonte.
    $env:VIXRADAR_ANTHROPIC_AUTH_TOKEN = 'sk-ant-' + 'oat01-SIMULADO-VENCIDO-' + $PID
    Write-Log 'SIMULACAO: VIXRADAR_ANTHROPIC_AUTH_TOKEN invalido injetado no processo (prova de escalada, -SimularTokenVencido)'
}

if ($script:VixCobFallbackModo) {
    # COBFALLBACK1: preparo em ordem de custo (lib Invoke-VixCobFallbackPreparo). Relatorio, ledger
    # e saldo antes de qualquer chamada; auth da assinatura e sonda (session limit/429) so quando ha
    # alvo que cabe. Nenhum desvio: modo de auth diferente de assinatura e incidente, nao escalada.
    $script:VixCobFallbackGastoPath = Get-VixCobFallbackGastoPath $LogDir $DateTag
    $script:VixCobFallbackExecId = ('pid' + $PID + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmss'))
    $__cfAuthFn = {
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { return @{ ok = $false; modo = 'sem_cli'; motivo = 'claude_exe_ausente' } }
        Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
        $__m = '' + (Get-VixClaudeAuthModo)
        return @{ ok = ($__m -eq 'assinatura' -or $__m -eq 'assinatura-token'); modo = $__m; motivo = ('modo_' + $__m) }
    }
    $__cfSondaFn = {
        $__ok = [bool](Test-VixWebSearchProbe $McpConfigFile)
        return @{ ok = $__ok; motivo = $(if ($__ok) { 'ok' } else { '' + $script:VixWsProbeMotivo }) }
    }
    $__cfPrep = Invoke-VixCobFallbackPreparo -LogDir $LogDir -DateTag $DateTag -FlagValor (Get-VixCobFallbackFlagValor) -AuthFn $__cfAuthFn -SondaFn $__cfSondaFn -DryRun ([bool]$DryRun)
    Write-Log ('COBFALLBACK_PREPARO: acao=' + $__cfPrep.Acao + ' motivo=' + $__cfPrep.Motivo + ' teto=' + $__cfPrep.Teto + ' gasto=' + $__cfPrep.Gasto + ' saldo=' + $__cfPrep.Saldo + ' candidatos=' + $__cfPrep.Candidatos + ' alvos=' + @($__cfPrep.Alvos).Count + ' fora=' + @($__cfPrep.Fora).Count + ' auth=' + $__cfPrep.AuthModo + ' sonda=' + $__cfPrep.Sonda)
    foreach ($__cfF in @($__cfPrep.Fora)) { Write-Log ('COBFALLBACK_FORA|' + $__cfF.empresa + '|' + $__cfF.tier + '|custo=' + $__cfF.custo + '|' + $__cfF.motivo) }
    if ($__cfPrep.Acao -ne 'EXECUTAR') {
        if ($__cfPrep.Acao -eq 'INCIDENTE') {
            Write-Log ('COBFALLBACK_INCIDENTE: ' + $__cfPrep.Motivo + ' - ' + $__cfPrep.Candidatos + ' pendente(s) decidido(s) para o Claude e nenhum coube. Incidente local: ' + $__cfPrep.IncidentePath)
            # Efeito externo so fora de dry-run e com a cobertura diaria ATIVA (mesma regra do
            # fechamento: sombra registra, nao alerta).
            if (-not $DryRun -and $script:VixCobDiariaAtivo) {
                try { $__cfKey = Get-RoutineKey; $null = Send-VixRoutineAlert -Rotina 'vixradar-cobertura-diaria' -Motivo ('COBFALLBACK ' + $DateTag + ': ' + $__cfPrep.Motivo + ' (' + $__cfPrep.Candidatos + ' pendentes para o Claude, saldo ' + $__cfPrep.Saldo + '/' + $__cfPrep.Teto + ')') -RoutineKey $__cfKey -Causa 'cobertura' -Severidade 'critico' } catch { Write-Log ('AVISO: alerta do incidente do fallback nao enviado - ' + $_.Exception.Message) }
            }
        }
        Write-Log ('FIM: cobfallback ' + $__cfPrep.Acao + ' (' + $__cfPrep.Motivo + '). analisados=0 tokens=0')
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
        try { $__mutex.ReleaseMutex() } catch { }
        if ($__cfPrep.Acao -eq 'INCIDENTE') { exit 20 }
        exit 0
    }
    $script:VixCobFallbackAlvos = @($__cfPrep.Alvos)
    $script:VixCobFallbackSaldo = [int64]$__cfPrep.Saldo
    $authModoInicial = $__cfPrep.AuthModo
    Write-Log ('AUTH_MODO: ' + $authModoInicial + ' (cobfallback: assinatura via CLI, ProviderOverride claude-subscription, sem chave paga e sem desvio)')
    Invoke-Cleanup
} elseif ($script:VixUsaOpenRouter) {
    # Fase B D1: provider openrouter nao usa auth Claude, nao roda probe WebSearch do CLI e
    # nao exige claude.exe. O adapter tem a chave OpenRouter (ambiente) e as server tools
    # web_search/web_fetch nativas; a credencial ja foi validada externamente pelo operador.
    $__orBoot = Test-VixOpenRouterPronto
    if (-not $__orBoot.ok) {
        Write-Log ('ERRO FATAL: ' + $__orBoot.motivo)
        Write-Log 'ERRO FATAL: OpenRouter configurado mas adapter nao pronto. Nenhuma chamada sera feita.'
        exit 5
    }
    Write-Log ('AUTH_MODO: ' + (Get-VixLlmEndpointDescricao) + ' (adapter HTTP, sem claude, sem auth Anthropic). busca_web=' + (Test-VixLlmEndpointTemBusca))
    # MODELOLOG1 (05/09): o modelo efetivo sai resolvido AQUI, inclusive quando vem do default
    # do adapter. Antes so existia o rotulo legado de Claude nos lotes, que dizia
    # claude-haiku-4-5 numa execucao que nao tocava em Anthropic nenhuma.
    $__orModelo = Get-VixOpenRouterModel $Perfil.tier
    $__orOrigem = if (Get-VixOpenRouterEnv ('VIXRADAR_OPENROUTER_MODEL_' + $Perfil.tier)) { 'env VIXRADAR_OPENROUTER_MODEL_' + $Perfil.tier } elseif (Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_MODEL') { 'env VIXRADAR_OPENROUTER_MODEL' } else { 'default do adapter' }
    Write-Log ('MODELO_EFETIVO: ' + $__orModelo + ' (origem: ' + $__orOrigem + ')')
} elseif ($script:VixUsaCodex) {
    # CODEx-ADAPTER1: o Codex CLI ja gerencia a autenticacao da assinatura e a busca web.
    # Nao chamar nenhuma rotina de auth Claude neste caminho.
    Write-Log 'AUTH_MODO: codex (assinatura Codex CLI, sem OpenRouter e sem auth Anthropic)'
} else {
    Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
    $authModoInicial = Get-VixClaudeAuthModo
    $__claudeBloqueado = (($authModoInicial -eq 'nenhum') -or ($authModoInicial -eq 'api' -and (Get-VixLlmProvider) -eq 'claude-subscription'))
    # CLAUDEFALLBACK-OR1 (2026-09-22): os dois motivos de bloqueio (sem credencial nenhuma,
    # ou escalada para API paga barrada por politica) tem a mesma causa raiz - assinatura
    # indisponivel - e os dois desviam para openrouter quando o operador autorizou
    # (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter). Ausencia da var preserva o
    # comportamento antigo (aborta, COTAESGOTADA1/ANTHROPIC_API_PAYG continuam intocados).
    if ($__claudeBloqueado -and (Get-VixClaudeFallbackOpenRouterHabilitado) -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
        $__claudeFrBoot = Test-VixOpenRouterPronto
        if ($__claudeFrBoot.ok) {
            Write-Log ('FALLBACK_OPENROUTER: assinatura indisponivel (modo=' + $authModoInicial + '), desviando ' + $Rotina + ' para openrouter (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter).')
            $script:VixUsaOpenRouter = $true
        } else {
            Write-Log ('FALLBACK_OPENROUTER: fallback habilitado mas adapter nao pronto (' + $__claudeFrBoot.motivo + '). Sem desvio possivel.')
        }
    }
    if ($script:VixUsaOpenRouter) {
        Write-Log 'AUTH_MODO: openrouter (fallback da assinatura esgotada, adapter HTTP D1)'
        $__orModelo = Get-VixOpenRouterModel $Perfil.tier
        Write-Log ('MODELO_EFETIVO: ' + $__orModelo + ' (origem: fallback CLAUDEFALLBACK-OR1)')
    } else {
        Write-Log ('AUTH_MODO: ' + $authModoInicial)
        if ($authModoInicial -eq 'nenhum') {
            Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel (assinatura expirada, token longevo ausente, chave paga invalida ou ausente). Abortando antes do primeiro lote.'
            Write-Log 'ERRO FATAL: rode `claude setup-token` para token longevo ou defina VIXRADAR_ANTHROPIC_API_KEY com chave sk-ant-valida.'
            # DRYRUN-CRASH1: tambem aqui a tag decide (02/09 16:00 um dry-run sem credencial virou 9004 real).
            Write-Log ($AlertaAuthTag + 'sem credencial nenhuma na ' + $Rotina + ' (modo=nenhum)')
            exit 5
        }
        if ($authModoInicial -eq 'api' -and (Get-VixLlmProvider) -eq 'claude-subscription') {
            Write-Log 'ERRO FATAL: assinatura Claude Code Pro indisponivel e fallback para Anthropic API paga bloqueado.'
            Write-Log ($AlertaAuthTag + 'assinatura Claude Code Pro indisponivel na ' + $Rotina + ' (nenhum custo sera gerado)')
            exit 5
        }
        if ($authModoInicial -eq 'api') {
            Write-Log ($AlertaAuthTag +$Rotina + ' comecou direto na chave paga (assinatura indisponivel no boot). Cada lote custa dolar.')
        }
        $ambientViolacao = Test-VixClaudeAmbienteLimpo
        if ($ambientViolacao) {
            Write-Log "AVISO: ambiente contaminado detectado - $ambientViolacao"
            $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
            Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
            Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
            Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
            Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
            [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', '', 'Process')
            [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User')
            [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'User')
            Write-Log 'RECUPERACAO: env vars Anthropic injetadas para neutralizar contaminacao do settings.json.'
        }
        if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
            Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel. Abortado antes do primeiro submit.'
            exit 7
        }
        Invoke-Cleanup
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Log 'ERRO: claude.exe ausente'; exit 2 }
    }
}

try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    if (-not $health.bindings.kv -or -not $health.bindings.telemetria) {
        Write-Log ('ERRO: health - kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
        exit 3
    }
    Write-Log ('Health ' + $health.versao + ' ok=' + $health.ok + ' verificador_ok=' + $health.verificador_ok + ' (nao bloqueante para esta rotina)')
    $versaoWorker = $health.versao
} catch { Write-Log ('ERRO: health ' + $_.Exception.Message); exit 3 }

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

# Cap dinamico por dia (REGUA-UNICA1): teto do dia menos o que as outras rotinas ja gastaram
# hoje, menos a reserva de quem ainda vai rodar.
$custoCfg = Get-VixCustoConfig $LogDir
if (-not $custoCfg.ContainsKey('RESERVA_NOTURNO')) { $custoCfg['RESERVA_NOTURNO'] = 700000 }
$custoDia = Get-VixCustoDia $LogDir $DateTag $custoCfg
$reservaOutras = [int64]$custoCfg.RESERVA_VERIFICACAO
if ($Perfil.reservaOutrasKey -eq 'RESERVA_NOTURNO') { $reservaOutras += [int64]$custoCfg.RESERVA_NOTURNO }
# COBDIARIA1: noturna que comeca antes da janela da matinal (catch-up depois da meia-noite) reserva
# o cap proprio da matinal. Em 14/10 a noturna das 02:28 deixou 20.721 para a matinal das 10:06.
if ($script:VixCobDiariaOk -and $Perfil.modo -eq 'noturno') {
    $__resMat = [int64](Get-VixReservaMatinalPendente -Agora (Get-Date) -MatinalJaRodou (Test-Path -LiteralPath (Join-Path $LogDir ('matinal_metrics_' + $DateTag + '.json'))) -CapMatinal 400000)
    if ($__resMat -gt 0) {
        if ($script:VixCobDiariaAtivo) { $reservaOutras += $__resMat; Write-Log ('COBDIARIA_RESERVA_MATINAL: ' + $__resMat + ' reservados (matinal ainda nao rodou hoje)') }
        else { Write-Log ('COBDIARIA_RESERVA_MATINAL_SOMBRA: reservaria ' + $__resMat + ' (matinal ainda nao rodou hoje); modo sombra nao altera o cap') }
    }
}
$TokenHardCap = [int64](Get-VixCapEfetivo ([int64]$Perfil.capProprio) $custoDia $custoCfg $reservaOutras)
if ($TokenTarget -gt $TokenHardCap) { $TokenTarget = $TokenHardCap }
# ORCAMENTO-13OUT7: cap proprio da escalada FULL (mesma protecao de reserva do cap efetivo).
$TokenHardCapEscalada = [int64](Get-VixCapEscaladaEfetivo ([int64]$Perfil.capProprio) ([int64]$Perfil.capEscalada) $custoDia $custoCfg $reservaOutras)
if ($TokenHardCapEscalada -lt $TokenHardCap) { $TokenHardCapEscalada = $TokenHardCap }
Write-Log ('CAP_ESCALADA=' + $TokenHardCapEscalada + ' (pool_escalada=' + $Perfil.capEscalada + ' cap_efetivo_rodada=' + $TokenHardCap + ')')
Write-Log ('CAP_EFETIVO=' + $TokenHardCap + ' (cap_proprio=' + $Perfil.capProprio + ' gasto_dia=' + $custoDia.total_trabalho + ' consumo_dia=' + $custoDia.total_consumido + ' mensuravel=' + $custoDia.mensuravel + ' teto=' + $custoDia.teto + ' reserva_outras=' + $reservaOutras + ')')
Write-Log $custoDia.linha
if ($custoDia.circuito_aberto) {
    Write-Log ('CIRCUITO_ABERTO: margem do dia ' + $custoDia.margem + ' abaixo de ' + $custoDia.margem_minima + '. Nenhum lote sera disparado; tudo que nao for SKIP sai como DEFERIDO.')
    $TokenHardCap = 0
    $TokenHardCapEscalada = 0
}
# COBFALLBACK1: o cap desta execucao e o SALDO do fallback Claude (CLAUDE_FALLBACK_DIA menos o
# gasto do fallback hoje), nao o TETO_DIA do primario: e outra regua e outro provedor. O circuito
# do primario aberto e justamente um dos motivos de o fallback existir, entao ele nao zera este cap.
if ($script:VixCobFallbackModo) {
    $TokenHardCap = [int64]$script:VixCobFallbackSaldo
    $TokenHardCapEscalada = $TokenHardCap
    $TokenTarget = $TokenHardCap
    Write-Log ('COBFALLBACK_CAP: cap_efetivo=' + $TokenHardCap + ' (saldo CLAUDE_FALLBACK_DIA; TETO_DIA do primario nao se aplica)')
}

$sw =[System.Diagnostics.Stopwatch]::StartNew()
$stats = @{
    skip_ok = 0; skip_fail = 0; batch_ok = 0; batch_fail = 0; silent_fail = 0
    tokens_total = [int64]0; tokens_mensuraveis = $true; tokens_over_target = $false; tokens_hard_hit = $false; deferred = 0; deferred_fail = 0
    batches_run = 0; analisados = 0; submit_ok = 0; submit_fail = 0; buscas_total = 0; lotes_com_trabalho = 0
    input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0
    # CACHECODEX-VISIVEL1: parcela de visibilidade (nao entra em tokens_total, logo nao entra em
    # cap nenhum). Serve para separar, no fechamento do dia, quanto do numero do cap e cache.
    cache_codex = [int64]0
    auth_escalou = 'nenhum'
    # COBERTURAAUTH1 (2026-09-15): o deferimento tem DUAS causas e elas passam a ficar separadas.
    # `deferred` segue sendo o TOTAL (ledger, FIM, ROTINA_RESUMO e metrics nao mudam de formato);
    # `deferred_auth` conta so quem ficou de fora porque a assinatura estourou o limite de sessao
    # no meio da execucao; `lotes_nao_processados` conta os lotes que o aborto deixou sem chamada.
    deferred_auth = 0; lotes_nao_processados = 0
    # PROFUNDIDADE-NOTURNA1 (D1): deferidos por rotacao semanal de profundidade, que nao sao
    # corte por orcamento nem por assinatura. Contador proprio para o FIM e o metrics nao
    # chamarem de cap um corte que a rotacao decidiu de proposito.
    deferred_rotacao = 0
    # COBERTURA-13OUT4: quarta causa de deferimento, a da rodada de escalada (emissor retido pelo
    # pacote barato que o cap nao deixou escalar). Separada das outras tres pela mesma regra: cada
    # causa com contador proprio para o FIM e o metrics nao somarem coisas diferentes.
    deferred_escalada = 0
    # DRENOMUDO1-FIX (2026-09-15): desfecho do dreno pos-rotina. $null = nao tentado (sem submit
    # ou em dry-run), 0 = drenou, outro valor = falhou. Nunca 0 por omissao: "nao rodou" nao pode
    # se ler como "rodou e deu certo".
    dreno_exit = $null
    # FEEDRETRO1 FASE2 (2026-09-04): eventos_avanco_data soma o campo homonimo que o
    # Worker devolve por emissor (avanco TEMPORAL, nao contagem de fatos); descartados
    # conta submit com evento enviado mas n_eventos=0 (Worker aceitou o transporte e
    # descartou tudo no saneamento ou no pre-verificador - ver DESCARTADO| no log).
    eventos_avanco_data = 0; chaves_novas = 0; descartados = 0; descartes_inesperados = 0
    cobertura_deferidos = 0; recheck_resolvidos = 0
    # OR402-DEGRADA1: chamadas ao adapter que cairam para o fallback por 402 (saldo). Contador
    # separado de silent_fail de proposito: o lote fechou, mas a degradacao fica visivel.
    degradados_402 = 0
    # COBERTURA-13OUT1: deferidos porque o provedor falhou (disjuntor), consumo cobrado por
    # estimativa quando o lote falhou sem usage, input em cache do Codex (so medicao) e
    # quantas vezes um lote passou do cap mesmo com a estimativa (deve ficar em 0).
    deferred_provider = 0; tokens_estimados_falha = [int64]0; codex_cached = [int64]0; cap_excedido = 0
    triagem_quieto = 0; triagem_material = 0; triagem_indisponivel = 0
    # COBERTURA-13OUT4: escalada seletiva. `retidos` = emissores que a rodada barata NAO pode
    # fechar e passou para a fila de ferramenta; `pendentes` = retidos depois do dedup;
    # `analisados` = quantos fecharam de fato na rodada FULL; `sem_orcamento` = quantos o cap
    # deixou sem lote (pendencia obrigatoria, vai para a fila persistente).
    escalada_retidos = 0; escalada_pendentes = 0; escalada_lotes = 0; escalada_analisados = 0; escalada_sem_orcamento = 0
    fila_pendente_falha = 0
    # COBERTURA-RECON1 (2026-10-14): contadores de ESTADO no contrato de cobertura. Existem para
    # reconciliar publicacao aceita (ledger), cobertura e fila pendente. Em 14/10 o dia fechou com
    # 16 analises publicadas e 11 registros de cobertura e ninguem podia dizer qual numero valia -
    # faltava cobertura ou faltava registro. Agora os dois numeros fecham por regra e a divergencia
    # nao e sucesso: ela entra em errosTotal e a rotina nao fecha OK.
    contrato_triado = 0; contrato_analisado = 0; contrato_inconclusivo = 0; contrato_resolvido = 0; contrato_reutilizado = 0; contrato_deferido = 0
    cobertura_divergencias = 0; cobertura_reconciliacao = 'nao_avaliada'
    # ROTACAO-14OUT1: auditoria da fila justa dos 104 (cota diaria, posicao, perdas, duplicidade).
    rotacao_aplicada = 0; rotacao_prioritarios = 0; rotacao_candidatos = 0; rotacao_adiados_cota = 0
    rotacao_perdidos = 0; rotacao_duplicados = 0; rotacao_reiniciou = 0; rotacao_na_fila = 0
    rotacao_servidos_ciclo = 0; rotacao_candidatos_dia = 0; rotacao_limite_dia = 0
    criticos = New-Object System.Collections.Generic.List[string]
}
$lotesDetalhe = New-Object System.Collections.Generic.List[object]
$pendingDeferred = New-Object System.Collections.Generic.List[object]
# MAXEMISSORESREAL1: chaves normalizadas cortadas pelo -MaxEmissores em execucao real.
$script:VixMaxEmissoresCortados = @{}
# COBERTURA-13OUT1: provedor efetivo desta execucao (vai no metrics para calibrar a regua por
# provedor), custos observados por emissor nesta execucao e disjuntor de provedor.
$__providerExec = if ($script:VixUsaOpenRouter) { 'openrouter' } elseif ($script:VixUsaCodex) { 'codex' } else { 'claude-subscription' }
$__custosObservados = New-Object System.Collections.Generic.List[object]
$script:VixUltimoCodexCached = [int64]0
$__disjuntor = New-VixDisjuntorProvider
# ORCAMENTO-CLASSE1 (2026-10-14): historico de custo POR CLASSE DE LOTE, lido ANTES da escolha
# de profundidade da noturna - a escolha de quantos FULL a noite tenta comprar usa o mesmo
# envelope do pre-lote. Antes ela usava a constante de setembro (31.068,75/emissor) e pedia 22
# FULL numa noite cujo cap de 700.000 nao pagava nem 5.
# A lista antiga (uma populacao so) fica para o custo-base da escalada, que e o MAXIMO
# declarado: ali misturar classes erra para cima, que e o lado seguro.
$__histCusto = @()
try { $__histCusto = @(Get-VixHistoricoCustoPorEmissor -LogDir $LogDir -Provider $__providerExec -Dias 7) } catch { $__histCusto = @() }
$__histClasse = @{ FULL = @(); LIGHT = @(); BARATO = @(); ESCALADA = @() }
foreach ($__cls in @('FULL', 'LIGHT', 'BARATO', 'ESCALADA')) {
    try { $__histClasse[$__cls] = @(Get-VixHistoricoCustoClasse -LogDir $LogDir -Provider $__providerExec -Classe $__cls -Dias 7) } catch { $__histClasse[$__cls] = @() }
}
# Limite operacional de candidatos NAO prioritarios por dia (rotacao justa). Nao e teto de
# gasto: quem limita o gasto e o cap. E teto de ROTACAO, para a fila girar e nao viciar sempre
# nos mesmos emissores. Prioridade de risco (EWS, analise vencida, pendencia viva) nunca entra
# nesta cota.
$script:VixRotacaoLimiteDiario = 40
$__filaPendentePath = Get-VixFilaPendentePath $LogDir
function Add-VixPendenteSeguro([string]$Empresa, $Ews, [string]$Motivo, [string]$Tier, [bool]$SubmitOk) {
    if ($DryRun) { return }
    try { Add-VixFilaPendente -Path $__filaPendentePath -Empresa $Empresa -Prioridade ([int]$Ews) -Motivo $Motivo -Rotina $Rotina -Tier $Tier -SubmitRegistrado $SubmitOk }
    catch { $stats.fila_pendente_falha++; Write-Log ('FILA_PENDENTE_ERRO: add ' + $Empresa + ' - ' + $_.Exception.Message) }
}
# COBFALLBACK1: gasto acumulado desta execucao no registro do dia do fallback (tambem em dry-run:
# token gasto na assinatura e gasto). Falha de escrita fecha o cap desta execucao (fail-closed),
# para a proxima nao enxergar saldo que ja foi consumido.
$script:VixCobFallbackFalha = '$nulo'
$script:VixCobFallbackUltimaClasse = ''
# Classifica a falha do Claude pela regra unica (Get-VixClasseFalhaProvider) e a deixa para o proximo
# registro de gasto: cota/429 vira ClaudeLimiteAtingido no fechamento, qualquer classe vira motivo
# do pendente. Nunca silencioso: tambem vai ao log.
function Set-VixCobFallbackFalhaClasse([string]$Texto, [string]$Origem) {
    if (-not $script:VixCobFallbackModo) { return }
    $__cls = Get-VixCobFallbackFalhaClasse $Texto
    $script:VixCobFallbackFalha = $__cls
    $script:VixCobFallbackUltimaClasse = $__cls
    Write-Log ('COBFALLBACK_FALHA_CLAUDE: origem=' + $Origem + ' classe=' + $__cls + ' limite_atingido=' + [int]($__cls -eq 'cota'))
}
function Update-VixCobFallbackGastoSeguro([string[]]$Tentados = @()) {
    if (-not $script:VixCobFallbackModo) { return }
    try {
        $__r = Set-VixCobFallbackGastoExecucao -Path $script:VixCobFallbackGastoPath -DateTag $DateTag -Execucao $script:VixCobFallbackExecId -Tokens ([int64]$stats.tokens_total) -Mensuravel ([bool]$stats.tokens_mensuraveis) -DryRun ([bool]$DryRun) -Tentados $Tentados -Falha $script:VixCobFallbackFalha
        $script:VixCobFallbackFalha = '$nulo'
        Write-Log ('COBFALLBACK_GASTO: execucao=' + $script:VixCobFallbackExecId + ' tokens=' + $stats.tokens_total + ' mensuravel=' + $stats.tokens_mensuraveis + ' gasto_dia=' + $__r.Gasto + ' tentados+=' + @($Tentados).Count)
    } catch {
        $script:capAtingido = $true; $script:capEscaladaFechado = $true
        Write-Log ('COBFALLBACK_GASTO_ERRO: ' + $_.Exception.Message + ' - cap fechado para os lotes seguintes (fail-closed)')
    }
}
function Remove-VixPendenteSeguro([string]$Empresa) {
    if ($DryRun) { return }
    try { if (Remove-VixFilaPendente -Path $__filaPendentePath -Empresa $Empresa) { Write-Log ('FILA_PENDENTE: ' + $Empresa + ' resolvido (analise efetiva)') } }
    catch { $stats.fila_pendente_falha++; Write-Log ('FILA_PENDENTE_ERRO: remove ' + $Empresa + ' - ' + $_.Exception.Message) }
}
# COBERTURA-RECON1 (2026-10-14): registra o ESTADO do emissor no contrato do dia. Um estado por
# emissor; o mais novo vence (idempotente). `triado` e PEGAJOSO de proposito - quem foi triado e
# depois analisado continua contando como triado na reconciliacao, senao a analise apagaria a
# prova da triagem universal. `faltantes` nao vazio e o que mantem a pendencia viva para
# Get-VixRecheckPendentes (mesmo contrato COBERTURA1, sem segundo mecanismo paralelo).
function Set-VixContratoEstado {
    param([string]$Empresa, [string]$Estado, [string]$Motivo = '', [string[]]$Faltantes = @(), [bool]$Triado = $false)
    if (-not $Empresa -or -not $Estado) { return }
    if ($DryRun) { return }
    $k = Get-NomeNormalizado $Empresa
    $ant = $null
    if ($contratoCobertura.ContainsKey($k)) { $ant = $contratoCobertura[$k] }
    $jaTriado = $Triado
    if (-not $jaTriado -and $null -ne $ant) {
        if ($ant -is [System.Collections.IDictionary]) {
            if ($ant.Contains('triado')) { $jaTriado = [bool]$ant['triado'] }
        } elseif ($null -ne $ant.PSObject.Properties['triado']) {
            $jaTriado = [bool]$ant.triado
        }
    }
    $contratoCobertura[$k] = @{
        empresa = $Empresa
        status = $Estado
        estado = $Estado
        motivo = $Motivo
        faltantes = @($Faltantes)
        triado = $jaTriado
        updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        rotina = $Perfil.modo
    }
    # IDEMEFETIVA1: o que ESTA execucao escreveu no contrato (a reconciliacao e por execucao).
    $script:VixContratoExec[$k] = $Estado
}
# Chaves de PRIORIDADE da rotacao (ROTACAO-14OUT1): risco nao entra na cota diaria. Fontes, todas
# do proprio registro do sistema, nenhuma inferencia nova: (a) recheck de cobertura aberto no
# contrato; (b) pendencia viva na fila persistente (recheck_cobertura / submit_recusado); (c) EWS
# critico ou documento CVM novo; (d) analise VENCIDA pelo mesmo limite da triagem (48h para EWS
# >= 50, 120h para o resto). Deferimento por ORCAMENTO nao entra aqui de proposito: e divida de
# GASTO, nao de fato - ela volta pela fila justa, que preserva posicao e tentativas.
function Get-VixChavesPrioritariasRotacao($Emissores, $FaltAnt, $FilaPendente) {
    $out = New-Object System.Collections.Generic.List[string]
    $visto = @{}
    $pend = @{}
    try {
        foreach ($ch in @($FilaPendente.Keys)) {
            $it = $FilaPendente[$ch]
            $mo = ''
            if ($null -ne $it -and $null -ne $it.PSObject.Properties['motivo']) { $mo = '' + $it.motivo }
            if ($mo -eq 'recheck_cobertura' -or $mo -eq 'submit_recusado') { $pend[$ch] = $true }
        }
    } catch { }
    foreach ($e in @($Emissores)) {
        if ($null -eq $e) { continue }
        $nome = '' + $e.empresa
        $k = Get-NomeNormalizado $nome
        $ck = ConvertTo-VixChaveEmissor $nome
        $pr = $false
        if ($FaltAnt -and $FaltAnt.ContainsKey($k)) { $pr = $true }
        if (-not $pr -and $pend.ContainsKey($ck)) { $pr = $true }
        $ews = 0; try { $ews = [int]$e.ews_score } catch { $ews = 0 }
        $cvm = 0; try { $cvm = [int]$e.cvm_novos } catch { $cvm = 0 }
        if ($ews -ge $script:VixTriagemEwsCritico -or $cvm -gt 0) { $pr = $true }
        if (-not $pr -and $null -ne $e.horas_desde_analise) {
            $h = [double]$e.horas_desde_analise
            $lim = $script:VixTriagemRevalidacaoH
            if ($ews -ge $script:VixTriagemEwsCritico) { $lim = $script:VixTriagemRevalidacaoCriticoH }
            if ($h -gt $lim) { $pr = $true }
        }
        # TRIAGEMATIVA1 (2026-10-14): INCONSISTENCIA ABERTA tambem e prioridade. As duas fontes sao
        # as MESMAS que o portao de ausencia da triagem ja usa para nao certificar QUIETO (motivo do
        # plano com `inconclusivo` e `ultima_origem` inconclusiva): se o caso nao pode ser lido como
        # quieto, ele tambem nao pode esperar o turno da rotacao - e a mesma pergunta viva. Somar
        # prioridade nao mexe na cota (prioritarios nao consomem turno) nem no orcamento (admissao
        # segue fail-closed): so muda a ORDEM, que e o que o risco exige.
        if (-not $pr) {
            foreach ($__mvPr in @($e.motivos)) { if (('' + $__mvPr).ToLowerInvariant().Contains('inconclusivo')) { $pr = $true; break } }
        }
        if (-not $pr -and $null -ne $e.PSObject.Properties['ultima_origem'] -and ('' + $e.ultima_origem).ToLowerInvariant().Contains('inconclusivo')) { $pr = $true }
        if ($pr -and -not $visto.ContainsKey($ck)) { $visto[$ck] = $true; $out.Add($nome) }
    }
    return $out.ToArray()
}
# COBERTURAAUTH1 (2026-09-15): causa do deferimento DESTA execucao. Comeca no planejado
# (cap_efetivo) e so muda para limite_sessao_assinatura se o aborto de auth acontecer no meio dos
# lotes. Ver Get-VixDeferidoMotivo/Get-VixCoberturaIncompletaTexto.
$motivoDeferido = Get-VixDeferidoMotivo $false
$abortoAuthDetalhe = ''
$contratoCobertura = @{}
# COBERTURA-RECON1: reinicio no MESMO dia nao pode apagar registro de cobertura do dia. O
# arquivo do dia e o registro mais novo da leitura de RECHECK, entao ele e carregado aqui e
# apenas o que for reavaliado nesta execucao e sobrescrito. Sem isto, uma segunda passada com
# idempotencia ligada (que nao reprocessa ninguem) regravaria o arquivo sem os estados da
# primeira - e a pendencia aberta na primeira passada viraria pendencia invisivel.
try {
    $__cobAnt = Read-VixContratoCoberturaArquivo (Get-VixContratoCoberturaPath $DateTag)
    if ($__cobAnt) { foreach ($__prC in @($__cobAnt.PSObject.Properties)) { $contratoCobertura[$__prC.Name] = $__prC.Value } }
} catch { }
$exitCode = 0
$batchSeq = 0

Push-Location $ProjectRoot
try {
    # COBFALLBACK1: o fallback le o plano NOTURNO (universo inteiro, com janela e delta de cada
    # emissor); o Worker nao conhece o modo cobfallback.
    $bodyPlano = @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = $(if ($script:VixCobFallbackModo) { 'noturno' } else { $Perfil.modo }) }
    if ($Perfil.top_n -gt 0) { $bodyPlano.top_n = $Perfil.top_n }
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $bodyPlano -TimeoutSec 180
    if ($plano.ok -ne $true) { Write-Log 'ERRO: plano'; exit 5 }
    # CARTEIRA-PISO1 (2026-09-04): este gate era `-ne 103`. A carteira cresceu para 104
    # (Usina Pampa Sul, commit da4c2ba) e a igualdade exata matou a noturna com exit 5 antes
    # de analisar qualquer emissor - medido no dry-run das 05:15 ("ERRO: plano noturno com
    # total 104 (esperado 103)"). O gate existe para barrar plano TRUNCADO, nao para congelar
    # o tamanho da carteira: quem cresce a carteira nao deve precisar lembrar de um numero
    # magico em dois motores. Piso barra truncagem; a linha CARTEIRA avisa que o numero mudou
    # sem derrubar a rotina. Mesma regra no Passo 3 da SKILL.md do motor CCD.
    $PlanoPisoNoturno = 100
    $PlanoBaseNoturno = 104
    if ($Perfil.modo -eq 'noturno') {
        if ($plano.total -lt $PlanoPisoNoturno) { Write-Log ('ERRO: plano noturno com total ' + $plano.total + ' (piso ' + $PlanoPisoNoturno + ' - plano truncado)'); exit 5 }
        if ($plano.total -ne $PlanoBaseNoturno) { Write-Log ('CARTEIRA: plano noturno com ' + $plano.total + ' emissores (base conhecida ' + $PlanoBaseNoturno + ') - carteira mudou, conferir cadastro') }
    }
    if ($plano.total -eq 0) {
        Write-Log ('FIM: ' + $Rotina + ' concluido. Total do dia 0/0. analisados=0 skip=0 deferidos=0 submits_aceitos=0 (plano vazio)')
        exit 0
    }
    $planoTotal = [int]$plano.total
    # COBDIARIA1: o plano do Worker e o denominador do dia. Uniao: o plano parcial da matinal nunca
    # encolhe o universo que a noturna gravou.
    $script:VixCobDiariaPath = ''
    if ($script:VixCobDiariaOk -and -not $DryRun) {
        $script:VixCobDiariaPath = Get-VixCobDiariaPath $LogDir $DateTag
        try {
            $__univ = Set-VixCobDiariaUniverso -Path $script:VixCobDiariaPath -DateTag $DateTag -Nomes @($plano.emissores | ForEach-Object { '' + $_.empresa }) -Total $planoTotal -Fonte ('plano_' + $Perfil.modo)
            Write-Log ('COBDIARIA_UNIVERSO: ' + $__univ + ' emissor(es) no denominador do dia (plano ' + $Perfil.modo + '=' + $planoTotal + ', modo=' + $(if ($script:VixCobDiariaAtivo) { 'ativo' } else { 'sombra' }) + ')')
        } catch { Write-Log ('COBDIARIA_ERRO: universo - ' + $_.Exception.Message); $script:VixCobDiariaPath = '' }
    }

    @{
        data = $plano.data; tiers = $plano.contagem_tiers; buscas = $plano.buscas_estimadas
        emissores = @($plano.emissores | ForEach-Object { @{ e = $_.empresa; t = $_.tier; ews = $_.ews_score; m = @($_.motivos)[0] } })
    } | ConvertTo-Json -Compress -Depth 5 | Set-Content (Join-Path $LogDir ($Perfil.prefix + '_plano_' + $DateTag + '.json')) -Encoding UTF8
    Write-Log ('Plano ' + ($plano.contagem_tiers | ConvertTo-Json -Compress) + ' total=' + $planoTotal + $(if ($Perfil.modo -eq 'matinal') { ' top_n_solicitado=' + $plano.top_n_solicitado + ' extras_setor=' + @($plano.extras_setor).Count } else { '' }))
    $creditados = @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' -and @($_.motivos)[0] -like 'analisado_hoje_por_*' })
    if ($creditados.Count -gt 0) {
        Write-Log ('CREDITO_DIA: ' + $creditados.Count + ' emissores ja analisados hoje por outra rotina (SKIP): ' + (($creditados | ForEach-Object { $_.empresa + '<' + (@($_.motivos)[0] -replace '^analisado_hoje_por_', '') + '>' }) -join ', '))
    }

    # Idempotencia por ledger do dia (v4.9.151): reinicio nao reprocessa quem ja foi ENTREGUE.
    # IDEMEFETIVA1 (2026-10-15): so trava quem tem entrega efetiva hoje (ANALISADO ou SKIP com
    # submit aceito), pela regra unica da lib do vigia. Incidente de 14/10: a regra antiga ("toda
    # linha OK| e trabalho feito") contou os 72 DEFERIDO por orcamento das 02:28 como processados,
    # e a noturna das 18:05 e os retries de 21:30 e 23:20 fecharam com `Fila aplicada: 0` e exit 6
    # com cap livre. DEFERIDO e submit recusado voltam a ser elegiveis e entram na MESMA fila, sob
    # o MESMO cap: reabrir nao aumenta orcamento nenhum, so impede que o orcamento livre fique parado.
    # Nao depende mais de VIXRADAR_COBERTURA_DIARIA: e correcao de defeito, nao controle novo.
    $jaProcessados = @{}
    $script:VixIdemReabertos = 0
    # LOGFALLBACK1 (2026-10-15): o ledger do dia e o log principal MAIS os _fallback_<pid>.log
    # (Get-VixLogDiaLinhas, lib do vigia). Em 15/10 103 das 104 linhas OK| foram para o fallback.
    if (-not $Force -and -not $DryRun -and @(Get-VixLogDiaArquivos $LogFile).Count -gt 0) {
        $linhasOk = @(Get-VixLogDiaLinhas $LogFile | Where-Object { $_ -match '^[\d-]+ [\d:]+ OK\|' })
        $__idem = Get-VixIdempotenciaEntregas -Linhas $linhasOk
        foreach ($__nIdem in @($__idem.Entregues)) { $jaProcessados[(Get-NomeNormalizado $__nIdem)] = $true }
        $script:VixIdemReabertos = @($__idem.ReabertosDeferido).Count + @($__idem.ReabertosSubmitFalho).Count
        Write-Log ('IDEMPOTENCIA_ENTREGA: entregues_hoje=' + @($__idem.Entregues).Count + ' reabertos_deferido=' + @($__idem.ReabertosDeferido).Count + ' reabertos_submit_falho=' + @($__idem.ReabertosSubmitFalho).Count + ' (so entrega efetiva trava reinicio)')
        if ($jaProcessados.Count -gt 0) { Write-Log ('Idempotencia: ' + $jaProcessados.Count + ' emissores ja entregues hoje, pulando') }
    } elseif ($Force) {
        Write-Log 'AVISO: -Force ativo. Trava de idempotencia ignorada.'
    }
    # Elegiveis desta execucao = plano menos quem ja foi entregue hoje. E o denominador honesto do
    # resultado e da triagem: execucao que nao tem nada a fazer porque tudo ja foi entregue nao e
    # "sem_analise_efetiva", e execucao com elegiveis que nao entrega nada continua sendo FALHA.
    $script:VixElegiveisExec = @($plano.emissores | Where-Object { -not $jaProcessados.ContainsKey((Get-NomeNormalizado ('' + $_.empresa))) }).Count

    $janIni = '' + $plano.emissores[0].janela_inicio
    $janFim = '' + $plano.emissores[0].janela_fim

    # SKIP do plano (inclui os creditados): submissao minima para o ledger fechar em 103.
    $skipQueue = @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    # COBFALLBACK1: o fallback nao reenvia SKIP ao Worker - isso e da noturna. Ele so analisa alvo.
    if ($script:VixCobFallbackModo) { $skipQueue = @() }
    $skipN = 0
    foreach ($emp in $skipQueue) {
        $skipN++
        $subOk = $false
        try { $r = Submit-SkipEmissor $routineKey $emp; $subOk = ($r.ok -eq $true) } catch { $subOk = $false }
        if ($subOk) { $stats.skip_ok++ } else { $stats.skip_fail++ }
        Write-Ledger $emp.empresa 'SKIP' '-' 0 $subOk 'SKIP'
        # COBERTURA-13OUT1: SKIP aceito pelo Worker e cobertura do dia (outra rotina ja analisou
        # ou o plano provou que nao ha delta) - solta a pendencia persistente se houver.
        if ($subOk) { Remove-VixPendenteSeguro $emp.empresa }
        # COBERTURA-RECON1: o SKIP entra no contrato como REUTILIZADO (analise valida do dia
        # reaproveitada, nunca republicada como nova) - e o que faz o numero do ledger fechar com
        # o numero do contrato. A prova e o motivo do proprio plano (`analisado_hoje_por_*`) ou o
        # delta ja coberto por outra rotina.
        $__motSkip = ''
        if (@($emp.motivos).Count -gt 0) { $__motSkip = '' + @($emp.motivos)[0] }
        Set-VixContratoEstado -Empresa $emp.empresa -Estado 'REUTILIZADO' -Motivo $__motSkip -Triado $true
        if (-not $DryRun) { Start-Sleep -Milliseconds 400 }
    }
    Write-Log ('SKIP_LOTE: ok=' + $stats.skip_ok + ' falha=' + $stats.skip_fail + ' total=' + $skipQueue.Count)
    # COBDIARIA1: SKIP e credito de ANALISE (outra rotina analisou hoje), nao prova de verificacao
    # com evidencia guardada aqui. Na NOTURNA, dona do universo, o SKIP tambem passa pelo coletor
    # (zero token, cache do dia reaproveitado) para o ledger ter prova propria por emissor. Emissor
    # que ja fechou hoje no ledger (analise registrada) nao e coletado de novo.
    if ($script:VixCobDiariaPath -and $Perfil.modo -eq 'noturno' -and ($null -ne (Get-Command 'Get-VixColetorEvidencia' -ErrorAction SilentlyContinue))) {
        $__cdLedger = $null
        try { $__cdLedger = Read-VixCobDiaria $script:VixCobDiariaPath $DateTag } catch { $__cdLedger = $null }
        $__cdCache = Get-VixColetaCachePath $LogDir $DateTag
        $__cdN = 0; $__cdSem = 0
        foreach ($emp in @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' })) {
            $__cdK = ConvertTo-VixChaveEmissor ('' + $emp.empresa)
            if ($null -ne $__cdLedger -and $__cdLedger.emissores.ContainsKey($__cdK) -and ($script:VixCobDiariaTerminais -contains ('' + (Get-VixCobDiariaCampo $__cdLedger.emissores[$__cdK] 'estado')))) { continue }
            Update-VixLock
            $__cdNome = '' + $emp.empresa
            $__cdCol = Get-VixColetaCacheada -Path $__cdCache -Empresa $__cdNome -TtlMin 180
            if ($null -eq $__cdCol) {
                try { $__cdCol = Get-VixColetorEvidencia -Empresa $__cdNome -JanelaDias 2 -MaxPorFamilia 20 } catch { $__cdCol = $null }
                try { Save-VixColetaCache -Path $__cdCache -Coleta $__cdCol } catch { }
            }
            $__cdCvm = 0; try { $__cdCvm = [int]$emp.cvm_novos } catch { $__cdCvm = 0 }
            $__cdFn = [scriptblock]::Create('Start-Sleep -Seconds 3; Get-VixColetorEvidencia -Empresa ''' + ($__cdNome -replace "'", "''") + ''' -JanelaDias 2 -MaxPorFamilia 20')
            $__cdR = Register-VixCobDiariaVerificacao -Path $script:VixCobDiariaPath -DateTag $DateTag -Empresa $__cdNome -Coleta $__cdCol -ColetaFn $__cdFn -DeltaInicio ('' + $emp.janela_delta_inicio) -CvmNovos $__cdCvm -Rotina ($Perfil.modo + ':skip')
            $__cdN++
            if ($__cdR.Estado -eq 'VERIFICADO_SEM_NOVIDADE') { $__cdSem++ }
            Write-Log ('COBDIARIA|' + $__cdNome + '|skip|' + $__cdR.Resultado + '|' + $__cdR.Motivo + '|estado=' + $__cdR.Estado + $(if ($__cdR.Erro) { '|erro=' + $__cdR.Erro } else { '' }))
        }
        Write-Log ('COBDIARIA_SKIP: verificados_pelo_coletor=' + $__cdN + ' sem_novidade=' + $__cdSem)
    }

    # Fila e tier aplicados. A noturna deriva FULL_SEMANA dos ledgers confirmados, une a
    # matinal do proprio dia por emissor e so entao calcula ceil(faltam/noites_restantes).
    # Nao existe credito por contagem bruta nem leitura de ultimo_tier do plano.
    $analyzeList = @($plano.emissores | Where-Object { $_.tier -ne 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    # COBFALLBACK1: a fila do fallback e EXATAMENTE a lista de alvos do preparo (qualquer tier do
    # plano, inclusive SKIP creditado - quem decide e o ledger da cobertura, nao o tier do plano).
    # Alvo fora do plano do Worker nao tem janela/delta para o prompt: registrado e fora.
    $script:VixCobFallbackTierPorChave = @{}
    if ($script:VixCobFallbackModo) {
        foreach ($__cfA in @($script:VixCobFallbackAlvos)) { $script:VixCobFallbackTierPorChave[(ConvertTo-VixChaveEmissor ('' + $__cfA.empresa))] = $__cfA }
        $analyzeList = @($plano.emissores | Where-Object { $script:VixCobFallbackTierPorChave.ContainsKey((ConvertTo-VixChaveEmissor ('' + $_.empresa))) -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
        $__cfNoPlano = @{}
        foreach ($__cfE in $analyzeList) { $__cfNoPlano[(ConvertTo-VixChaveEmissor ('' + $__cfE.empresa))] = $true }
        foreach ($__cfK in @($script:VixCobFallbackTierPorChave.Keys)) {
            if (-not $__cfNoPlano.ContainsKey($__cfK)) { Write-Log ('COBFALLBACK_FORA|' + $script:VixCobFallbackTierPorChave[$__cfK].empresa + '|' + $script:VixCobFallbackTierPorChave[$__cfK].tier + '|fora_do_plano_ou_ja_processado_hoje_pelo_fallback') }
        }
        $planoTotal = $analyzeList.Count
        Write-Log ('COBFALLBACK_FILA: ' + $analyzeList.Count + ' de ' + @($script:VixCobFallbackAlvos).Count + ' alvo(s) no plano noturno')
    }
    $__faltAnt = Get-VixRecheckPendentes $LogDir
    foreach ($emp in $analyzeList) {
        if ($__faltAnt.ContainsKey((Get-NomeNormalizado $emp.empresa))) {
            try { $emp | Add-Member -NotePropertyName vix_recheck_pendente -NotePropertyValue $true -Force } catch { }
        }
    }
    # COBERTURA-13OUT1 parte 2: TRIAGEM DETERMINISTICA antes de qualquer lote de IA. O coletor
    # (Google News RSS, 3 familias, HTTP real, zero token) decide quem tem fato novo desde o
    # delta. Emissor QUIETO (coleta completa, nada novo, nenhum CVM novo, IA recente dentro da
    # janela de revalidacao) fecha aqui sem modelo, com as tres familias provadas por consulta
    # medida. MATERIAL e INDISPONIVEL seguem para a IA, MATERIAL com as pistas coletadas. A
    # triagem roda sobre a $analyzeList, antes da selecao de profundidade e dos lotes, entao o
    # emissor quieto nao vira cauda de rotacao nem DEFERIDO. OPT-IN: so liga
    # com VIXRADAR_TRIAGEM_DETERMINISTICA=1. Ela certifica ausencia de fato sem passar pelo modelo,
    # o que e decisao de qualidade do operador, nao otimizacao automatica. Ausente = fluxo anterior.
    $script:VixTriagemDados = @{}
    $__flagTriagem = [Environment]::GetEnvironmentVariable('VIXRADAR_TRIAGEM_DETERMINISTICA', 'Process')
    if (-not $__flagTriagem) { $__flagTriagem = [Environment]::GetEnvironmentVariable('VIXRADAR_TRIAGEM_DETERMINISTICA', 'User') }
    $script:VixTriagemAtiva = ((('' + $__flagTriagem).Trim() -eq '1') -and ($null -ne (Get-Command 'Get-VixColetorEvidencia' -ErrorAction SilentlyContinue)))
    # MODO SOMBRA (VIXRADAR_TRIAGEM_DETERMINISTICA=sombra): roda a mesma triagem e registra
    # TRIAGEM_SOMBRA, mas NENHUM emissor sai da IA e nada e submetido pelo coletor. Serve para
    # medir revocacao (QUIETO da sombra x o que a IA achou) antes de o operador ligar o modo 1.
    $script:VixTriagemSombra = ((('' + $__flagTriagem).Trim().ToLowerInvariant() -eq 'sombra') -and ($null -ne (Get-Command 'Get-VixColetorEvidencia' -ErrorAction SilentlyContinue)))
    # COBFALLBACK1: alvo do fallback ja foi triado hoje (e por isso esta pendente). Triagem de novo
    # so gastaria rede e poderia certificar QUIETO por outro caminho - fora do escopo do executor.
    if ($script:VixCobFallbackModo) { $script:VixTriagemAtiva = $false; $script:VixTriagemSombra = $false }
    if (($script:VixTriagemAtiva -or $script:VixTriagemSombra) -and $analyzeList.Count -gt 0) {
        $__cacheColeta = Get-VixColetaCachePath $LogDir $DateTag
        $__ultimaIAPath = Get-VixUltimaIAPath $LogDir
        # ESTADONAORESOLVIDO1 (2026-10-13): a fila persistente precisa estar em maos AQUI, antes da
        # triagem, e nao so na fase de plano (onde ela so ordena). Dois motivos representam pergunta
        # VIVA do emissor - `recheck_cobertura` (a IA nao conseguiu cobrir) e `submit_recusado` (a
        # analise nao entrou) - e nenhum dos dois pode ser apagado por uma certificacao de ausencia
        # feita pelo caminho mais barato. Os motivos de ORCAMENTO (cap_efetivo, cap_sentinela,
        # escalada_sem_orcamento, falha_provider, uso_desconhecido) ficam de fora de proposito: ali
        # a divida era de GASTO, nao de fato, e a pergunta de fato e respondida pelo mesmo portao de
        # ausencia que a IA usa. Se o registro nao puder ser lido, ninguem e marcado.
        $__pendVivas = @{}
        try {
            $__filaPendTri = Read-VixFilaPendente $__filaPendentePath
            foreach ($__chaveP in @($__filaPendTri.Keys)) {
                $__itP = $__filaPendTri[$__chaveP]
                $__motP = ''
                if ($null -ne $__itP -and $null -ne $__itP.PSObject.Properties['motivo']) { $__motP = '' + $__itP.motivo }
                if ($__motP -eq 'recheck_cobertura' -or $__motP -eq 'submit_recusado') { $__pendVivas[$__chaveP] = $__motP }
            }
            if ($__pendVivas.Count -gt 0) { Write-Log ('TRIAGEM_ESTADO_ABERTO: ' + $__pendVivas.Count + ' emissor(es) com pendencia de analise aberta na fila persistente - nenhum deles pode ser certificado QUIETO') }
        } catch { Write-Log ('TRIAGEM_ESTADO_ABERTO_ERRO: fila pendente ilegivel - nenhum emissor marcado - ' + $_.Exception.Message) }
        $__restoIA = New-Object System.Collections.Generic.List[object]
        $__relRuido = 0
        $__tq = 0; $__tm = 0; $__ti = 0; $__swTri = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($emp in $analyzeList) {
            Update-VixLock
            $__nome = '' + $emp.empresa
            # Janela da coleta = dias desde o delta do emissor (+1 de folga), 2..7. Com a janela
            # padrao de 7 dias e teto de 5 manchetes o coletor guardava as 5 primeiras DA JANELA, na
            # ordem do RSS (nao e por data), e as recentes podiam ficar de fora: falso-quieto medido
            # em 13/10 (Raizen). Janela curta + teto 20 ate o delta cobre o que importa.
            $__jd = 2
            $__dd = [datetime]::MinValue
            $__dTxt = '' + $emp.janela_delta_inicio
            if ($__dTxt.Length -ge 10 -and [datetime]::TryParseExact($__dTxt.Substring(0, 10), 'yyyy-MM-dd', $null, [Globalization.DateTimeStyles]::None, [ref]$__dd)) {
                $__jd = [int][Math]::Min(7, [Math]::Max(2, [Math]::Ceiling(((Get-Date).ToUniversalTime().Date - $__dd.Date).TotalDays) + 1))
            }
            $__col = Get-VixColetaCacheada -Path $__cacheColeta -Empresa $__nome -TtlMin 180
            if ($null -ne $__col -and [int]$__col.janela_dias -lt $__jd) { $__col = $null }
            $__orig = 'cache'
            if ($null -eq $__col) {
                $__orig = 'rss'
                try { $__col = Get-VixColetorEvidencia -Empresa $__nome -JanelaDias $__jd -MaxPorFamilia 20 } catch { $__col = $null }
                if (-not $DryRun) { try { Save-VixColetaCache -Path $__cacheColeta -Coleta $__col } catch { Write-Log ('TRIAGEM_CACHE_ERRO: ' + $__nome + ' - ' + $_.Exception.Message) } }
            }
            $__hIA = Get-VixHorasDesdeIA -Path $__ultimaIAPath -Empresa $__nome -HorasPlano $emp.horas_desde_analise
            $__cvmN = 0; try { $__cvmN = [int]$emp.cvm_novos } catch { $__cvmN = 0 }
            $__ews = 0; try { $__ews = [int]$emp.ews_score } catch { $__ews = 0 }
            # ESTADONAORESOLVIDO1: pergunta viva nao vira QUIETO. Duas fontes, e as duas vem do
            # proprio registro do sistema, nenhuma e inferencia nova: (a) pendencia de analise
            # aberta na fila persistente (recheck_cobertura / submit_recusado); (b) motivo do plano
            # declarando INCONCLUSIVO anterior - o Worker ja rotula esses emissores com
            # `inconclusivo_*`, e o texto do motivo e o unico lugar por onde essa informacao chega
            # sem uma varredura extra do estado.
            $__chaveT = ConvertTo-VixChaveEmissor $__nome
            $__estAberto = $false; $__motAberto = ''
            if ($__pendVivas.ContainsKey($__chaveT)) { $__estAberto = $true; $__motAberto = ('pendencia_' + $__pendVivas[$__chaveT]) }
            elseif (-not $__estAberto) {
                foreach ($__mv in @($emp.motivos)) {
                    if (('' + $__mv).ToLowerInvariant().Contains('inconclusivo')) { $__estAberto = $true; $__motAberto = 'inconclusivo_anterior'; break }
                }
            }
            if ($emp.PSObject.Properties['ultima_origem'] -and ('' + $emp.ultima_origem).ToLowerInvariant().Contains('inconclusivo')) { $__estAberto = $true; if (-not $__motAberto) { $__motAberto = 'inconclusivo_anterior' } }
            $__tri = Get-VixTriagemEmissor -Coleta $__col -DeltaInicio ('' + $emp.janela_delta_inicio) -CvmNovos $__cvmN -HorasDesdeIA $__hIA -Ews $__ews -EstadoNaoResolvido $__estAberto -MotivoNaoResolvido $__motAberto
            if ($__estAberto -and $__tri.Classe -eq 'MATERIAL' -and ('' + $__tri.Motivo).StartsWith('estado_nao_resolvido_')) { Write-Log ('TRIAGEM_NAO_QUIETO|' + $__nome + '|' + $__motAberto + ' -> segue para IA (estado nao resolvido nunca certifica ausencia)') }
            # Confirmacao por segunda amostra: o RSS e NAO deterministico (a Raizen saiu quieta em dois
            # lotes de medicao e com 4 manchetes novas nas coletas isoladas, no mesmo dia). QUIETO so
            # vale se uma coleta NOVA, fora do cache e separada por alguns segundos, concordar. Qualquer
            # discordancia manda o emissor para a IA com as pistas da amostra que viu fato.
            if ($__tri.Classe -eq 'QUIETO') {
                Start-Sleep -Seconds 3
                $__col2 = $null
                try { $__col2 = Get-VixColetorEvidencia -Empresa $__nome -JanelaDias $__jd -MaxPorFamilia 20 } catch { $__col2 = $null }
                $__tri2 = Get-VixTriagemEmissor -Coleta $__col2 -DeltaInicio ('' + $emp.janela_delta_inicio) -CvmNovos $__cvmN -HorasDesdeIA $__hIA -Ews $__ews -EstadoNaoResolvido $__estAberto -MotivoNaoResolvido $__motAberto
                if ($__tri2.Classe -ne 'QUIETO') {
                    Write-Log ('TRIAGEM_DISCORDANCIA|' + $__nome + '|1a=QUIETO|2a=' + $__tri2.Classe + '|' + $__tri2.Motivo + ' -> segue para IA')
                    $__tri = $__tri2; $__col = $__col2
                }
            }
            $script:VixTriagemDados[(ConvertTo-VixChaveEmissor $__nome)] = @{ Coleta = $__col; Triagem = $__tri }
            # COBDIARIA1: a MESMA coleta responde a pergunta do dia ("houve fato novo?") sem a regra
            # de revalidacao de IA. Fato novo, pergunta aberta ou falha de coleta viram obrigacao do
            # dia; quieto confirmado por segunda amostra fecha a verificacao com prova propria.
            if ($script:VixCobDiariaPath) {
                $__cdFnT = [scriptblock]::Create('Start-Sleep -Seconds 3; Get-VixColetorEvidencia -Empresa ''' + ($__nome -replace "'", "''") + ''' -JanelaDias ' + $__jd + ' -MaxPorFamilia 20')
                $__cdT = Register-VixCobDiariaVerificacao -Path $script:VixCobDiariaPath -DateTag $DateTag -Empresa $__nome -Coleta $__col -ColetaFn $__cdFnT -JaConfirmado ($__tri.Classe -eq 'QUIETO') -DeltaInicio ('' + $emp.janela_delta_inicio) -CvmNovos $__cvmN -EstadoNaoResolvido $__estAberto -MotivoNaoResolvido $__motAberto -Rotina $Perfil.modo
                if ($__cdT.Resultado -ne 'SEM_NOVIDADE') { $script:VixCobDiariaObrig[(ConvertTo-VixChaveEmissor $__nome)] = (Get-VixCobDiariaPrioridade $__cdT.Resultado $__cdT.Motivo) }
                Write-Log ('COBDIARIA|' + $__nome + '|triagem|' + $__cdT.Resultado + '|' + $__cdT.Motivo + '|estado=' + $__cdT.Estado + $(if ($__cdT.Erro) { '|erro=' + $__cdT.Erro } else { '' }))
            }
            # COBERTURA-RECON1: a triagem universal registra o estado TRIADO de TODO emissor da
            # fila de decisao, com a classe que a coleta determinou (MATERIAL / QUIETO /
            # INDISPONIVEL). E o denominador do dia que faltava: em 14/10 a triagem rodou em 88
            # emissores e nao persistiu prova por emissor - so a sombra de revogacao.
            Set-VixContratoEstado -Empresa $__nome -Estado 'TRIADO' -Motivo ('' + $__tri.Classe + ':' + $__tri.Motivo) -Triado $true
            $__hTxt = if ($null -eq $__hIA) { '-' } else { [int]$__hIA }
            Write-Log ('TRIAGEM|' + $__nome + '|' + $__tri.Classe + '|' + $__tri.Motivo + '|coleta=' + $__orig + '|h_ia=' + $__hTxt)
            if ($script:VixTriagemSombra) {
                Write-Log ('TRIAGEM_SOMBRA|' + $__nome + '|' + $__tri.Classe + '|' + $__tri.Motivo + '|segue_para_ia=1')
                if ($__tri.Classe -eq 'MATERIAL') {
                    $__rel = Get-VixRelevanciaCredito -Triagem $__tri -CvmNovos $__cvmN -Ews $__ews
                    Write-Log ('RELEVANCIA_SOMBRA|' + $__nome + '|' + $__rel.Decisao + '|' + $__rel.Motivo + '|segue_para_ia=1')
                    if ($__rel.Decisao -eq 'RUIDO') { $__relRuido++ }
                    if (-not $DryRun) { try { Add-VixRelevanciaRegistro (Get-VixRelevanciaSombraPath $LogDir $DateTag) ([ordered]@{ tipo = 'decisao'; empresa = $__nome; decisao = $__rel.Decisao; motivo = $__rel.Motivo; ts = (Get-Date).ToString('s') }) } catch { Write-Log ('RELEVANCIA_SOMBRA_ERRO: ' + $__nome + ' - ' + $_.Exception.Message) } }
                }
                if ($__tri.Classe -eq 'QUIETO') { $__tq++ } elseif ($__tri.Classe -eq 'MATERIAL') { $__tm++ } else { $__ti++ }
                $__restoIA.Add($emp); continue
            }
            if ($__tri.Classe -ne 'QUIETO') {
                if ($__tri.Classe -eq 'MATERIAL') { $__tm++ } else { $__ti++ }
                $__restoIA.Add($emp); continue
            }
            $__res = [pscustomobject](New-VixResultadoDeterministico -Empresa $__nome -Coleta $__col -Triagem $__tri -DeltaInicio ('' + $emp.janela_delta_inicio))
            # Prova mecanica: o resultado deterministico tem de passar no MESMO portao de ausencia
            # que a IA passa. Se nao passar, nao ha atalho: o emissor vai para a IA.
            $__cert = Test-VixAusenciaCertificavel $__res
            if (-not $__cert.permitir_sem_eventos) {
                Write-Log ('TRIAGEM_NAO_CERTIFICAVEL|' + $__nome + '|' + $__cert.motivo + '|faltantes=' + ($__cert.faltantes -join ',') + ' -> segue para IA')
                $__ti++; $__restoIA.Add($emp); continue
            }
            # Tier LIGHT de proposito: tres consultas RSS cobrem o contrato LIGHT, nao o FULL.
            # Registrar FULL creditaria profundidade semanal que nao aconteceu
            # (Get-VixFullConfirmadosDoLedger conta so FULL ANALISADO).
            $__tierEmp = 'LIGHT'
            try { $__res | Add-Member -NotePropertyName '_tier' -NotePropertyValue $__tierEmp -Force } catch { }
            $__subOk = $false; $__nEv = 0
            try {
                $__resp = Submit-Analise $routineKey $__nome $emp.setor $__res 'coletor-deterministico' $__tierEmp @()
                if ($__resp.ok -ne $true -and -not $DryRun) { Start-Sleep -Seconds $PauseSec; $__resp = Submit-Analise $routineKey $__nome $emp.setor $__res 'coletor-deterministico' $__tierEmp @() }
                $__subOk = ($__resp.ok -eq $true)
            } catch { Write-Log ('SUBMIT_EXC|' + $__nome + '|' + $_.Exception.Message) }
            if ($DryRun) { $__subOk = $false }
            Write-Ledger $__nome $__tierEmp 'NENHUM' 0 $__subOk 'ANALISADO' 0
            $stats.analisados++; $stats.triagem_quieto++
            $stats.buscas_total += @($__res.fontes_consultadas).Count
            if ($DryRun) { }
            elseif ($__subOk) {
                $stats.submit_ok++
                Remove-VixPendenteSeguro $__nome
                if ($__faltAnt.ContainsKey((Get-NomeNormalizado $__nome))) { Merge-VixContratoCobertura $contratoCobertura $__nome 'RESOLVIDO' @(); $stats.recheck_resolvidos++ }
            } else {
                $stats.submit_fail++
                Add-VixPendenteSeguro $__nome $emp.ews_score 'submit_recusado' $__tierEmp $false
            }
            # COBERTURA-RECON1: o caminho deterministico tambem registra estado. Sem isto o
            # emissor certificado pelo coletor entraria no ledger e nao no contrato - o mesmo
            # buraco que produziu 16 analises para 11 coberturas em 14/10.
            if ($__subOk -and $__faltAnt.ContainsKey((Get-NomeNormalizado $__nome))) {
                Set-VixContratoEstado -Empresa $__nome -Estado 'RESOLVIDO' -Motivo 'resolvido:coletor_deterministico' -Faltantes @() -Triado $false
            } elseif ($__subOk) {
                Set-VixContratoEstado -Empresa $__nome -Estado 'ANALISADO' -Motivo 'coletor_deterministico' -Faltantes @() -Triado $false
            } else {
                Set-VixContratoEstado -Empresa $__nome -Estado 'INCONCLUSIVO' -Motivo 'nao_conclusiva:submit_recusado' -Faltantes @('submit_recusado') -Triado $false
            }
            $__tq++
        }
        $__swTri.Stop()
        $stats.triagem_material = $__tm; $stats.triagem_indisponivel = $__ti
        Write-Log ('TRIAGEM_RESUMO: candidatos=' + $analyzeList.Count + ' quietos_sem_ia=' + $(if ($script:VixTriagemSombra) { 0 } else { $__tq }) + ' quietos_sombra=' + $(if ($script:VixTriagemSombra) { $__tq } else { 0 }) + ' sombra=' + [int]$script:VixTriagemSombra + ' relevancia_ruido_sombra=' + $__relRuido + ' material_ia=' + $__tm + ' indisponivel_ia=' + $__ti + ' duracao_s=' + [Math]::Round($__swTri.Elapsed.TotalSeconds, 1) + ' tokens_llm=0')
        $analyzeList = @($__restoIA.ToArray())
    } elseif (-not $script:VixTriagemAtiva -and -not $script:VixTriagemSombra) {
        Write-Log 'TRIAGEM: desligada (opt-in VIXRADAR_TRIAGEM_DETERMINISTICA=1 nao setado ou lib do coletor ausente) - todos os candidatos seguem para IA'
    }
    $jobs = New-Object System.Collections.Generic.List[object]
    if ($script:VixCobFallbackModo) {
        # COBFALLBACK1: lotes por tier da DECISAO da cascata, sem rotacao nem profundidade semanal.
        # FULL = Sonnet com ferramenta (prompt FULL da noturna); BARATO = Haiku sobre a coleta do
        # orquestrador quando o coletor esta ligado. Custo por emissor de cada lote = o maior custo
        # estimado pela decisao entre os emissores do lote (lado seguro); a admissao pre-lote segue
        # a mesma do motor, contra o cap que aqui e o saldo do fallback.
        $__cfFull = @($analyzeList | Where-Object { $script:VixCobFallbackTierPorChave[(ConvertTo-VixChaveEmissor ('' + $_.empresa))].tier -eq 'FULL' })
        $__cfBar = @($analyzeList | Where-Object { $script:VixCobFallbackTierPorChave[(ConvertTo-VixChaveEmissor ('' + $_.empresa))].tier -ne 'FULL' })
        $jobsFull = New-VixJobsPorTier -Selecionados $__cfFull -Tier 'FULL' -Chunk 4 -Model $ModelSonnet -Skill (Join-Path $ScriptsDir 'noturno-batch-sonnet.md') -Ultra $false -Provedor 'claude-sonnet-routine'
        $jobsLight = New-VixJobsPorTier -Selecionados $__cfBar -Tier 'LIGHT' -Chunk $Perfil.chunk -Model $ModelHaiku -Skill $Perfil.skill -Ultra ([bool]$Perfil.ultra) -Provedor $Perfil.provedor
        $__cfTodos = New-Object System.Collections.Generic.List[object]
        foreach ($__cfJ0 in $jobsFull) { $__cfTodos.Add($__cfJ0) }
        foreach ($__cfJ0 in $jobsLight) { $__cfTodos.Add($__cfJ0) }
        foreach ($__cfJ in $__cfTodos) {
            $__cfMax = [int64]0
            foreach ($__cfE in @($__cfJ.Chunk)) { $__cfC = [int64]$script:VixCobFallbackTierPorChave[(ConvertTo-VixChaveEmissor ('' + $__cfE.empresa))].custo; if ($__cfC -gt $__cfMax) { $__cfMax = $__cfC } }
            $__cfJ['CustoTrabalho'] = [double]$__cfMax
            if ($__cfJ.Tier -eq 'LIGHT') { $__cfJ['Barato'] = [bool]$script:VixColetorAtivo }
            $jobs.Add($__cfJ)
        }
        $fila = @($__cfFull) + @($__cfBar)
        Write-Log ('COBFALLBACK_LOTES: full=' + $__cfFull.Count + ' barato=' + $__cfBar.Count + ' lotes=' + $jobs.Count + ' cap=' + $TokenHardCap + ' provider=claude-subscription')
    } elseif ($Perfil.modo -eq 'noturno') {
        $agoraProfundidade = Get-Date
        # D2 do P0 PROFUNDIDADE-NOTURNA1: ler ate HOJE, nao ate ontem. A varredura le os ledgers
        # confirmados de SEGUNDA ATE HOJE, matinal e noturno de cada dia, e une por emissor. Com
        # `-Ate ontem` um restart no mesmo dia perdia os FULL que a propria noturna ja tinha
        # concluido hoje e os recomprava na segunda passada - o oposto do que a rotacao quer.
        # A leitura conta so OK|...|FULL|...|true|ANALISADO|: DRYRUN, submit false, SKIP e
        # DEFERIDO nao creditam semana (Get-VixFullConfirmadosDoLedger).
        $fullSemana = Get-VixFullSemanaDosLedgers $LogDir $agoraProfundidade -Ate $agoraProfundidade
        $fullMatinalHoje = Get-VixFullConfirmadosDoLedger $LogDir 'matinal' $agoraProfundidade
        $fullNoturnoHoje = Get-VixFullConfirmadosDoLedger $LogDir 'noturno' $agoraProfundidade
        $fullSemana = Merge-VixFullSemana -FullSemana $fullSemana -EmissoresFull $fullMatinalHoje -Data $agoraProfundidade
        $fullSemana = Merge-VixFullSemana -FullSemana $fullSemana -EmissoresFull $fullNoturnoHoje -Data $agoraProfundidade
        $cobertosHoje = @{}
        foreach ($emp in $creditados) { $cobertosHoje[(Get-NomeNormalizado $emp.empresa)] = 'plano_creditado' }
        # D3: os custos vem da funcao unica, nunca de constante solta no motor.
        # ORCAMENTO-CLASSE1 (14/10): a constante do tier (31.068,75/emissor) sai do caminho e
        # entra o ENVELOPE medido da classe na configuracao que vai rodar. Com a constante, a
        # noite de 14/10 pediu 22 FULL para um cap de 700.000 que nao pagava nem 5 - e o pre-lote
        # so descobriu depois de admitir um lote de 16 que custou 1.193.101.
        $__modeloFullSel = Get-VixModeloLoteClasse -Amostras @($__histClasse['FULL']) -DefaultEmissor $script:VixCustoEmissorDefaultCodex -PisoEmissor ([int64][Math]::Ceiling($script:VixCustoEmissorDefaultCodex))
        $__modeloBaratoSel = Get-VixModeloLoteClasse -Amostras @($__histClasse['BARATO']) -DefaultEmissor $script:VixCustoEmissorDefaultCodex -PisoEmissor ([int64][Math]::Ceiling((Get-VixCustoEstimadoTier 'LIGHT').Custo))
        $custoFullNoturno = [double](Get-VixEstimativaClasseResumo -Modelo $__modeloFullSel -Emissores 16).Custo
        $custoLightNoturno = [double](Get-VixEstimativaClasseResumo -Modelo $__modeloBaratoSel -Emissores $Perfil.chunk).Custo
        Write-Log ('CUSTO_CLASSE_SELECAO: full=' + [int64]$custoFullNoturno + '/emissor (chunk 16, fonte=' + $__modeloFullSel.fonte + ') barato=' + [int64]$custoLightNoturno + '/emissor (chunk ' + $Perfil.chunk + ', fonte=' + $__modeloBaratoSel.fonte + ')')
        # ROTACAO-14OUT1: fila justa persistente dos 104. A prioridade de RISCO (recheck aberto,
        # pendencia viva, EWS critico, CVM novo, analise vencida) entra inteira e primeiro, fora
        # da cota; os nao prioritarios giram pela fila do ciclo, limitados ao teto diario. A
        # $analyzeList completa segue intacta para a cauda de rotacao (nenhum emissor sai do
        # ledger por causa da cota).
        $__rotCicloPath = Get-VixRotacaoPath $LogDir
        $__rotCiclo = Read-VixRotacaoCiclo $__rotCicloPath
        $__filaPendRot = @{}
        try { $__filaPendRot = Read-VixFilaPendente $__filaPendentePath } catch { $__filaPendRot = @{} }
        $__chavesPrior = @(Get-VixChavesPrioritariasRotacao $analyzeList $__faltAnt $__filaPendRot)
        # COBDIARIA1 (ativo): o obrigatorio do dia (fato novo, pergunta aberta, falha de coleta) entra
        # como prioridade fora da cota e na frente da entrada; a revalidacao vencida (complementar)
        # continua prioritaria, mas atras dele. Sombra: so registra o que faria.
        if ($script:VixCobDiariaOk -and $script:VixCobDiariaObrig.Count -gt 0) {
            if ($script:VixCobDiariaAtivo) {
                $analyzeList = @(Select-VixCobDiariaOrdem -Emissores $analyzeList -Obrigatorios $script:VixCobDiariaObrig)
                $__chavesPrior = @(@($analyzeList | Where-Object { $script:VixCobDiariaObrig.ContainsKey((ConvertTo-VixChaveEmissor ('' + $_.empresa))) } | ForEach-Object { '' + $_.empresa }) + @($__chavesPrior))
                Write-Log ('COBDIARIA_ORDEM: ' + $script:VixCobDiariaObrig.Count + ' obrigatorio(s) do dia na frente da fila e fora da cota de rotacao')
            } else { Write-Log ('COBDIARIA_ORDEM_SOMBRA: ' + $script:VixCobDiariaObrig.Count + ' obrigatorio(s) do dia; modo sombra nao altera a fila') }
        }
        $__rot = Select-VixRotacaoCandidatos -Emissores $analyzeList -ChavesPrioritarias $__chavesPrior -Ciclo $__rotCiclo -LimiteDiario $script:VixRotacaoLimiteDiario -DiaTag $DateTag
        $__analiseSelecao = @($__rot.Candidatos)
        $stats.rotacao_aplicada = 1
        $stats.rotacao_prioritarios = @($__rot.PriorChaves).Count
        $stats.rotacao_candidatos = @($__rot.ConsumidosChaves).Count
        $stats.rotacao_adiados_cota = @($__rot.AdiadosCota).Count
        $stats.rotacao_limite_dia = [int]$script:VixRotacaoLimiteDiario
        $stats.rotacao_candidatos_dia = [int]$__rot.JaHoje + @($__rot.ConsumidosChaves).Count
        Write-Log ('ROTACAO_FILA: prioritarios=' + @($__rot.PriorChaves).Count + ' candidatos_rotacao=' + @($__rot.ConsumidosChaves).Count + ' adiados_pela_cota=' + @($__rot.AdiadosCota).Count + ' cota_restante=' + $__rot.CotaRestante + ' limite_dia=' + $script:VixRotacaoLimiteDiario + ' na_fila_ciclo=' + @($__rotCiclo.ordem).Count)
        # D2: a lista enviada ao seletor e a $analyzeList, que ja exclui SKIP e o que a
        # idempotencia do ledger marcar como processado hoje. Restart no mesmo dia nao recompra
        # FULL ja concluido, nem por dentro dos lotes nem por dentro da selecao.
        $selecaoProfundidade = Select-VixProfundidadeNoturna -Emissores $__analiseSelecao -FullSemana $fullSemana -CobertosHoje $cobertosHoje `
            -BaseCarteira $planoTotal -NoitesRestantes (Get-VixDiasUteisRestantes $agoraProfundidade) -CapEfetivo $TokenHardCap `
            -CustoFull $custoFullNoturno -CustoLight $custoLightNoturno -ChunkFull 16 -ChunkLight $Perfil.chunk
        $fullSelecionados = @($selecaoProfundidade.Full)
        $lightSelecionados = @($selecaoProfundidade.Light)
        if ($script:VixCobDiariaAtivo -and $script:VixCobDiariaObrig.Count -gt 0) {
            $fullSelecionados = @(Select-VixCobDiariaOrdem -Emissores $fullSelecionados -Obrigatorios $script:VixCobDiariaObrig)
            $lightSelecionados = @(Select-VixCobDiariaOrdem -Emissores $lightSelecionados -Obrigatorios $script:VixCobDiariaObrig)
        }
        if ($MaxEmissores -gt 0) {
            # MAXEMISSORESREAL1 (2026-10-15): o corte vale tambem fora de -DryRun. Quem sai da
            # selecao por este corte vira DEFERIDO motivo=max_emissores (pendencia, nao rotacao),
            # nunca some do ledger. A ordem da selecao (prioridade primeiro) e preservada.
            $__maxAntes = @(@($fullSelecionados) + @($lightSelecionados))
            $nFullAmostra = [Math]::Min($MaxEmissores, $fullSelecionados.Count)
            $fullSelecionados = if ($nFullAmostra -gt 0) { @($fullSelecionados | Select-Object -First $nFullAmostra) } else { @() }
            $restoAmostra = $MaxEmissores - $fullSelecionados.Count
            $lightSelecionados = if ($restoAmostra -gt 0) { @($lightSelecionados | Select-Object -First $restoAmostra) } else { @() }
            if ($DryRun) {
                Write-Log ('AMOSTRA: -MaxEmissores ' + $MaxEmissores + ' (dry-run, medicao)')
            } else {
                $__maxFicam = @{}
                foreach ($__mx in @(@($fullSelecionados) + @($lightSelecionados))) { $__maxFicam[(Get-NomeNormalizado ('' + $__mx.empresa))] = $true }
                foreach ($__mx in $__maxAntes) { $__mxK = Get-NomeNormalizado ('' + $__mx.empresa); if (-not $__maxFicam.ContainsKey($__mxK)) { $script:VixMaxEmissoresCortados[$__mxK] = $true } }
                Write-Log ('MAX_EMISSORES: -MaxEmissores ' + $MaxEmissores + ' em execucao real: full=' + $fullSelecionados.Count + ' light=' + $lightSelecionados.Count + ' cortados=' + $script:VixMaxEmissoresCortados.Count + ' (saem DEFERIDO motivo=max_emissores)')
            }
        }
        $jobsFull = New-VixJobsPorTier -Selecionados $fullSelecionados -Tier 'FULL' -Chunk 16 -Model $ModelSonnet -Skill (Join-Path $ScriptsDir 'noturno-batch-sonnet.md') -Ultra $false -Provedor 'claude-sonnet-routine'
        $jobsLight = New-VixJobsPorTier -Selecionados $lightSelecionados -Tier 'LIGHT' -Chunk $Perfil.chunk -Model $ModelHaiku -Skill $Perfil.skill -Ultra ([bool]$Perfil.ultra) -Provedor $Perfil.provedor
        # COBERTURA-13OUT4: so o lote LIGHT e rodada barata. O FULL da rotacao semanal mantem a
        # ferramenta: ele existe para abrir fonte primaria (rotacao por risco da semana), e a
        # escalada e a segunda razao de rodar FULL (evidencia do dia). As duas convivem.
        foreach ($jobProf in @($jobsFull)) { $jobProf['CustoTrabalho'] = $custoFullNoturno; $jobs.Add($jobProf) }
        foreach ($jobProf in @($jobsLight)) { $jobProf['CustoTrabalho'] = $custoLightNoturno; $jobProf['Barato'] = $true; $jobs.Add($jobProf) }
        $fila = @($fullSelecionados) + @($lightSelecionados)
        Write-Log ('PROFUNDIDADE: full_semana=' + $fullSemana.Count + ' full_matinal_hoje=' + $fullMatinalHoje.Count + ' full_noturno_hoje=' + $fullNoturnoHoje.Count + ' faltam=' + $selecaoProfundidade.Meta.faltam_na_semana + ' noites=' + $selecaoProfundidade.Meta.noites_restantes + ' min_full=' + $selecaoProfundidade.Meta.min_full_noite + ' full=' + $fullSelecionados.Count + ' light=' + $lightSelecionados.Count + ' cap=' + $TokenHardCap + ' gap_dias_proxy_nao_web=' + $selecaoProfundidade.Meta.gap_dias_proxy_nao_web)
    } else {
        $fila = @($analyzeList | Sort-Object -Property ews_score, cvm_novos -Descending)
        if ($__faltAnt.Count -gt 0) {
            $__com = @($fila | Where-Object { $__faltAnt.ContainsKey((Get-NomeNormalizado $_.empresa)) })
            $__sem = @($fila | Where-Object { -not $__faltAnt.ContainsKey((Get-NomeNormalizado $_.empresa)) })
            if ($__com.Count -gt 0) { Write-Log ('COBERTURA1: ' + $__com.Count + ' emissor(es) com RECHECK_PENDENTE de cobertura priorizados no inicio da fila (sem janela de data)') }
            $fila = @($__com) + @($__sem)
        }
        # COBERTURA-13OUT1: pendencias persistentes de execucoes anteriores (cap, provedor, uso
        # desconhecido) vem logo depois do RECHECK, antes do resto. Sem duplicar, sem perder.
        try {
            $__filaPend = Read-VixFilaPendente $__filaPendentePath
            if ($__filaPend.Count -gt 0) {
                $__nRecheck = 0
                if ($__faltAnt.Count -gt 0) { $__nRecheck = @($fila | Where-Object { $__faltAnt.ContainsKey((Get-NomeNormalizado $_.empresa)) }).Count }
                $__cabeca = @($fila | Select-Object -First $__nRecheck)
                $__cauda = @($fila | Select-Object -Skip $__nRecheck)
                $fila = @($__cabeca) + @(Select-VixOrdemComPendentes $__cauda $__filaPend)
                $__noPlano = @($fila | Where-Object { $__filaPend.ContainsKey((ConvertTo-VixChaveEmissor $_.empresa)) }).Count
                Write-Log ('FILA_PENDENTE: ' + $__filaPend.Count + ' pendente(s) persistente(s), ' + $__noPlano + ' no plano desta execucao priorizado(s); fora do plano dependem do deferred_prioritario do Worker')
            }
        } catch { $stats.fila_pendente_falha++; Write-Log ('FILA_PENDENTE_ERRO: leitura - ' + $_.Exception.Message + ' (ordem original mantida)') }
        if ($MaxEmissores -gt 0) {
            if ($DryRun) {
                $fila = @($fila | Select-Object -First $MaxEmissores)
                Write-Log ('AMOSTRA: -MaxEmissores ' + $MaxEmissores + ' (dry-run, medicao)')
            } else {
                # MAXEMISSORESREAL1: na matinal nao ha cauda de rotacao; o excedente entra direto
                # nos deferidos desta execucao, para o ledger e o contrato fecharem emissor a emissor.
                $__mxResto = @($fila | Select-Object -Skip $MaxEmissores)
                $fila = @($fila | Select-Object -First $MaxEmissores)
                foreach ($__mx in $__mxResto) {
                    $script:VixMaxEmissoresCortados[(Get-NomeNormalizado ('' + $__mx.empresa))] = $true
                    $pendingDeferred.Add([pscustomobject]@{ emissor = $__mx; tier = $Perfil.tier; motivo = 'max_emissores' })
                }
                Write-Log ('MAX_EMISSORES: -MaxEmissores ' + $MaxEmissores + ' em execucao real: fila=' + $fila.Count + ' cortados=' + $__mxResto.Count + ' (saem DEFERIDO motivo=max_emissores)')
            }
        }
        foreach ($chunk in (Split-IntoChunks $fila $Perfil.chunk)) {
            # COBERTURA-13OUT4: a matinal rotula os proprios lotes como FULL, mas com o coletor
            # ligado ela E a rodada barata dos emissores de maior risco; quem precisa de fonte
            # primaria volta pela escalada. Por isso o marcador e explicito aqui.
            $jobs.Add([ordered]@{ Name = $Perfil.tier.ToLower(); Tier = $Perfil.tier; Model = $Perfil.model; Chunk = @($chunk); Skill = $Perfil.skill; Ultra = [bool]$Perfil.ultra; Provedor = $Perfil.provedor; Barato = $true })
        }
    }
    foreach ($job in $jobs) {
        foreach ($emp in $job.Chunk) {
            try { $emp | Add-Member -NotePropertyName tier_aplicado -NotePropertyValue $job.Tier -Force } catch { }
            $h = if ($null -ne $emp.horas_desde_analise) { $emp.horas_desde_analise } else { '-' }
            $u = if ($emp.ultima_origem) { $emp.ultima_origem } else { '-' }
            Write-Log ('ALVO ' + $emp.empresa + ' tier_plano=' + $emp.tier + ' tier_aplicado=' + $job.Tier + ' cvm_novos=' + $emp.cvm_novos + ' motivo=' + @($emp.motivos)[0] + ' ews=' + $emp.ews_score + ' ultimo=' + $u + ' h=' + $h)
        }
    }
    Write-Log ('Fila aplicada: ' + $fila.Count + ' emissores em ' + $jobs.Count + ' lote(s) (cap_efetivo=' + $TokenHardCap + ')')
    $lotesEsperados = if ($Perfil.modo -eq 'noturno' -or $script:VixCobFallbackModo) { @($jobsFull).Count + @($jobsLight).Count } elseif ($fila.Count -eq 0) { 0 } else { [Math]::Ceiling($fila.Count / $Perfil.chunk) }
    if ($jobs.Count -ne $lotesEsperados) {
        Write-Log ("AVISO CRITICO: agrupamento de lotes incorreto - lotes=$($jobs.Count) esperado=$lotesEsperados (fila=$($fila.Count)). Possivel regressao de Split-IntoChunks.")
    }

    $ji = 0
    $abortAfterSubmit = $false
    $capAtingido = $false
    # ORCAMENTO-13OUT7: a escalada FULL tem lane propria. O cap da rodada barata fechado NAO
    # fecha a escalada; so fecham a escalada o proprio cap dela e o uso nao mensuravel.
    $capEscaladaFechado = $false
    # COBERTURA-13OUT4: escalada seletiva. Fila de emissores que o pacote barato nao pode fechar
    # sem ferramenta e a rodada FULL que os atende. A rodada de escalada NAO tem caminho proprio:
    # ela entra na MESMA fila de lotes e passa pelo mesmo orcamento, disjuntor, retry parcial,
    # portao de ausencia, submit, ledger e fila pendente. Duplicar esse caminho seria a forma mais
    # rapida de os dois divergirem em silencio.
    $__escaladaFila = New-Object System.Collections.Generic.List[object]
    $__escaladaMontada = $false
    $__escaladaLotes = 0
    # Custo-base da escalada: constante conservadora do tier FULL e o MAXIMO do historico do
    # provedor (nunca a mediana). Motivo medido: o lote barato da rodada 1 e observado por
    # Get-VixCustoPorEmissor e baratearia a estimativa da rodada 2; o piso do lote de escalada e
    # justamente o que impede isso. Media de 13/10 no modo FULL: ~178k por emissor.
    $__custoEscalada = [double](Get-VixCustoEstimadoTier 'FULL').Custo
    if ($__histCusto.Count -gt 0) {
        $__maxHist = [double](($__histCusto | Measure-Object -Maximum).Maximum)
        if ($__maxHist -gt $__custoEscalada) { $__custoEscalada = $__maxHist }
    }
    if ($script:VixEscaladaAtiva) { Write-Log ('ESCALADA_CUSTO_BASE: ' + [int64][Math]::Ceiling($__custoEscalada) + '/emissor (constante FULL e maximo do historico do provedor n=' + $__histCusto.Count + ')') }
    $__filaLotes = New-Object System.Collections.Generic.List[object]
    foreach ($__j0 in $jobs) { $__filaLotes.Add($__j0) }
    # LOTEFILA1 (2026-10-15): a montagem da escalada vivia no FIM do corpo do laco, e todo
    # `continue` (CAP pre-lote, disjuntor aberto) pulava por cima dela. Quando o ULTIMO lote
    # barato saia por `continue`, o laco terminava com a escalada nunca montada e o emissor
    # retido sumia: nem ANALISADO, nem DEFERIDO. Medido na matinal de 15/10 10:08: GPA retida
    # (ESCALADA_DECISAO escalar=1), 4 lotes por `CAP pre-lote`, `RECONCILIACAO_DIA ...
    # sem_registro=1 ... sem_registro_nomes=Pao de Acucar (GPA)`. A montagem agora e o primeiro
    # passo do laco e o laco so termina com a escalada montada.
    while ($__filaLotes.Count -gt 0 -or -not $__escaladaMontada) {
        # COBERTURA-13OUT4: a rodada barata acabou (fila vazia) e ainda nao houve rodada de
        # escalada. Monta os lotes FULL dos emissores retidos e devolve os lotes para a MESMA
        # fila, entao eles passam por orcamento, disjuntor, retry, portao de ausencia, submit,
        # ledger e fila pendente sem nenhum caminho paralelo. Entra em $jobs tambem, senao o
        # aborto por auth (Get-JobIndex) nao os enxergaria e eles ficariam sem desfecho.
        # Modelo e skill sao os do tier FULL; o custo-base e o medido, nunca o da rodada barata.
        if ($__filaLotes.Count -eq 0 -and -not $__escaladaMontada) {
            $__escaladaMontada = $true
            $__escOrd = @(Select-VixEscaladaOrdenada -Itens $__escaladaFila.ToArray())
            $stats.escalada_pendentes = $__escOrd.Count
            if ($__escOrd.Count -gt 0) {
                $__escEmissores = @($__escOrd | ForEach-Object { $_.Emp })
                $__escSkill = if ($Perfil.modo -eq 'noturno') { Join-Path $ScriptsDir 'noturno-batch-sonnet.md' } else { $Perfil.skill }
                $__jobsEsc = @(New-VixJobsPorTier -Selecionados $__escEmissores -Tier 'FULL' -Chunk $script:VixEscaladaChunk -Model $ModelSonnet -Skill $__escSkill -Provedor 'claude-sonnet-routine')
                foreach ($__je in $__jobsEsc) {
                    $__je['Escalada'] = $true
                    # Nome proprio no log: sem ele a escalada apareceria como 'full-N', igual ao
                    # FULL da rotacao noturna, e as duas coisas sao diferentes (a escalada e por
                    # evidencia do dia, a rotacao e por risco da semana).
                    $__je['Name'] = 'escalada'
                    $__je['CustoTrabalho'] = [double]$__custoEscalada
                    $jobs.Add($__je)
                    $__filaLotes.Add($__je)
                }
                $__escaladaLotes = $__jobsEsc.Count
                Write-Log ('ESCALADA_LOTE: ' + $__escOrd.Count + ' emissor(es) retido(s) na rodada barata em ' + $__escaladaLotes + ' lote(s) FULL custo_base=' + [int64][Math]::Ceiling($__custoEscalada) + '/emissor; gatilhos=' + ((@($__escOrd | Group-Object Motivo | ForEach-Object { $_.Name + '=' + $_.Count })) -join ','))
            } elseif ($script:VixEscaladaAtiva) {
                Write-Log 'ESCALADA_LOTE: nenhum emissor retido na rodada barata - nada a escalar'
            }
            if ($__filaLotes.Count -eq 0) { continue }
        }
        $job = $__filaLotes[0]
        $__filaLotes.RemoveAt(0)
        $ji++
        Update-VixLock
        if ($__disjuntor.aberto) {
            # Disjuntor de provedor aberto: nenhuma chamada nova nesta execucao. Os emissores
            # ficam pendentes com motivo proprio e voltam pela fila/deferred_prioritario.
            foreach ($e in $job.Chunk) { $pendingDeferred.Add([pscustomobject]@{ emissor = $e; tier = $job.Tier; motivo = 'falha_provider' }) }
            $stats.lotes_nao_processados++
            Write-Log ('DISJUNTOR_PROVIDER: aberto (' + $__disjuntor.motivo + ') - lote ' + $job.Name + '-' + $ji + ' nao chamado, ' + $job.Chunk.Count + ' emissor(es) pendentes motivo=falha_provider')
            continue
        }
        # COBERTURA-13OUT4: lote de escalada que nao cabe no orcamento sai com motivo proprio.
        # O emissor NAO foi analisado (a rodada barata o reteve de proposito), entao ele e
        # pendencia obrigatoria de verdade e nao pode entrar na conta como "cap da cauda".
        $__motivoEscalada = if ($job.Escalada) { 'escalada_sem_orcamento' } else { $null }
        $__estAntigo = if ($null -ne $job.CustoTrabalho) { [double]$job.CustoTrabalho } else { [double](($Perfil.bootTok + ($job.Chunk.Count * $Perfil.unitTok)) / [Math]::Max(1, $job.Chunk.Count)) }
        $__default = if ($__providerExec -eq 'codex') { [int64][Math]::Max([double]$script:VixCustoEmissorDefaultCodex, $__estAntigo) } else { [int64][Math]::Ceiling($__estAntigo) }
        # ORCAMENTO-CLASSE1 (2026-10-14): a admissao do lote passa a usar o ENVELOPE da CLASSE
        # (FULL / LIGHT / BARATO / ESCALADA) com margem, no lugar de um custo por emissor
        # constante medido numa populacao que misturava lote barato e lote FULL. O custo por
        # emissor publicado no log e o do tamanho REAL do lote (estimativa / emissores). Era a
        # divisao pelo lote cheio (31.069 por emissor num envelope que nao vale para lote menor)
        # que admitia 1.193.101 contra cap de 700.000.
        $__classeLote = Get-VixClasseLote -Tier $job.Tier -Barato ([bool]$job.Barato) -Escalada ([bool]$job.Escalada)
        $__amostrasClasse = @()
        if ($__histClasse.ContainsKey($__classeLote)) { $__amostrasClasse = @($__histClasse[$__classeLote]) }
        $__modelo = Get-VixModeloLoteClasse -Amostras $__amostrasClasse -DefaultEmissor $__default -PisoEmissor ([int64][Math]::Ceiling($__estAntigo))
        $__resumoEst = Get-VixEstimativaClasseResumo -Modelo $__modelo -Emissores $job.Chunk.Count
        $__cpe = @{ Custo = [int64]$__resumoEst.Custo; Fonte = ('classe_' + $__classeLote + ':' + $__resumoEst.Fonte) }
        $__capLote = if ($job.Escalada) { $TokenHardCapEscalada } else { $TokenHardCap }
        $__laneFechada = if ($job.Escalada) { $capEscaladaFechado } else { $capAtingido }
        $__cabem = if ($__laneFechada) { 0 } else { Get-VixEmissoresQueCabemModelo -Modelo $__modelo -Acum $stats.tokens_total -Cap $__capLote -Chunk $job.Chunk.Count }
        if ($__cabem -le 0) {
            $estLote = [int64]$__resumoEst.Est
            $stats.tokens_hard_hit = $true
            if ($job.Escalada) { $capEscaladaFechado = $true } else { $capAtingido = $true }
            foreach ($e in $job.Chunk) { $pendingDeferred.Add([pscustomobject]@{ emissor = $e; tier = $job.Tier; motivo = $__motivoEscalada }) }
            if ($job.Escalada) { $stats.escalada_sem_orcamento += $job.Chunk.Count }
            Write-Log ('CAP pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' (' + $__cpe.Custo + '/emissor fonte=' + $__cpe.Fonte + ') >= ' + $__capLote + ' - lote ' + $job.Name + '-' + $ji + ' deferred (' + $job.Chunk.Count + ' emissores, cauda de menor EWS)')
            continue
        }
        if ($__cabem -lt $job.Chunk.Count) {
            # Lote encolhido para caber no que resta do cap: roda os de maior prioridade, em vez de
            # estourar o teto (14/10) ou deferir o lote inteiro.
            # LOTEFILA1 (2026-10-15): o resto do lote era DEFERIDO aqui e a faixa fechava
            # ($capAtingido) com base so na ESTIMATIVA, antes de o lote rodar. Toda a fila seguinte
            # caia em `CAP pre-lote` sem reavaliar contra o consumo real. Matinal de 15/10: estimativa
            # 312.500/emissor, lote reduzido a 1 (GPA), consumo real 21.416, e os 19 emissores de
            # maior EWS (Oi, Kora, Raizen 55, Light 50, CSN 42...) DEFERIDOS com 378.584 do cap de
            # 400.000 livres. O resto volta para a FRENTE da fila (mantem a ordem de prioridade) e
            # passa de novo pela mesma admissao, com o acumulado real. Termina: cada passada roda
            # pelo menos 1 emissor ou defere o lote inteiro e fecha a faixa no ramo de cima.
            $__fora = @($job.Chunk | Select-Object -Skip $__cabem)
            $job.Chunk = @($job.Chunk | Select-Object -First $__cabem)
            $__resto = [ordered]@{}
            foreach ($__kJ in @($job.Keys)) { $__resto[$__kJ] = $job[$__kJ] }
            $__resto['Chunk'] = $__fora
            $__filaLotes.Insert(0, $__resto)
            # Entra em $jobs logo depois do lote atual: o aborto por auth (Get-JobIndex) defere tudo
            # que vem depois do lote que falhou, e o resto nao pode ficar fora desse alcance.
            $__idxJ = Get-JobIndex $jobs $job
            if ($__idxJ -ge 0) { $jobs.Insert($__idxJ + 1, $__resto) } else { $jobs.Add($__resto) }
            # Fragmentacao adaptativa: a estimativa e reavaliada para o lote que VAI rodar.
            $__resumoEst = Get-VixEstimativaClasseResumo -Modelo $__modelo -Emissores $__cabem
            $__cpe = @{ Custo = [int64]$__resumoEst.Custo; Fonte = $__cpe.Fonte }
            Write-Log ('CAP_LOTE_REDUZIDO: lote ' + $job.Name + '-' + $ji + ' roda ' + $__cabem + ' emissor(es), ' + $__fora.Count + ' de volta a frente da fila para reavaliar com o consumo real (' + $__cpe.Custo + '/emissor fonte=' + $__cpe.Fonte + ' acum=' + $stats.tokens_total + ' cap=' + $__capLote + ')')
        }
        $estLote = [int64]$__resumoEst.Est
        Write-Log ('EST_LOTE: ' + $job.Name + '-' + $ji + ' emissores=' + $job.Chunk.Count + ' custo_emissor=' + $__cpe.Custo + ' fonte=' + $__cpe.Fonte + ' est=' + $estLote + ' acum=' + $stats.tokens_total + ' cap=' + $TokenHardCap)
        if (($stats.tokens_total + $estLote) -ge $TokenTarget -and -not $stats.tokens_over_target) {
            $stats.tokens_over_target = $true
            Write-Log ('AVISO: meta ' + $TokenTarget + ' sera ultrapassada neste lote (acum=' + $stats.tokens_total + ' est=' + $estLote + ') - continua ate o cap ' + $TokenHardCap)
        }

        $batchSeq++
        $label = $job.Name + '-' + $ji
        if (-not (Test-VixColetorObrigatorioPronto $job.Chunk)) {
            Write-Log ('ERRO FATAL: coletor indisponivel para lote ' + $label + ' sob provider deepseek. DeepSeek nao pode classificar sem evidencia coletada.')
            exit 6
        }
        $modeloPrompt = $job.Model
        $fonteProvedor = 'openrouter'
        if ($script:VixUsaOpenRouter) { $modeloPrompt = Get-VixOpenRouterModel $job.Tier }
        elseif ($script:VixUsaCodex) { $modeloPrompt = 'codex-subscription'; $fonteProvedor = 'codex' }
        $prompt = New-BatchPrompt $job.Chunk $label $modeloPrompt $job.Skill $janIni $janFim $fonteProvedor -Ultra:$job.Ultra -Tier $job.Tier -ModoEscalada:([bool]$job.Escalada) -ModoBarato:([bool]$job.Barato)
        $promptPath = Join-Path $LogDir ($Perfil.prefix + '_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $prompt -Encoding UTF8

        # MODELOLOG1: provider openrouter nunca imprime o rotulo Claude legado como se fosse o
        # modelo executado. $job.Model so descreve o TIER do plano (rapido x aprofundado).
        $modeloLote = $job.Model
        if ($script:VixUsaOpenRouter) { $modeloLote = 'openrouter:' + (Get-VixOpenRouterModel $job.Tier) + ' tier=' + $job.Name }
        elseif ($script:VixUsaCodex) { $modeloLote = 'codex:codex-subscription tier=' + $job.Name }
        Write-Log ('Lote ' + $label + ' [' + $modeloLote + ']: ' + (($job.Chunk | ForEach-Object { $_.empresa }) -join ', '))
        # COBFALLBACK1: gasto acumulado ate aqui (lote anterior e retry dele) e emissores deste lote
        # marcados como tentados ANTES da chamada - crash no meio nao libera repeticao no mesmo dia.
        Update-VixCobFallbackGastoSeguro -Tentados @($job.Chunk | ForEach-Object { '' + $_.empresa })
        $swLote = [System.Diagnostics.Stopwatch]::StartNew()
        # COBFALLBACK1: ProviderOverride claude-subscription (padrao CODEXFALLBACK-OR1). Fora do modo
        # o valor e '' e a chamada e identica a anterior. Com o override, Invoke-ClaudeBatch confere
        # a assinatura por lote, recusa chave paga e nao desvia para OpenRouter (-not override).
        $result = Invoke-ClaudeBatch $promptPath $job.Model $job.Chunk.Count $job.Tier -ProviderOverride $script:VixCobFallbackProvider
        $swLote.Stop()
        $stats.degradados_402 += [int]$result.Degradados402
        $stats.batches_run++
        if ($result.Escalou) {
                    $stats.auth_escalou = 'api'
                    Write-Log ($AlertaAuthTag +$Rotina + ' escalou para chave paga no lote ' + $label + ' (credencial de assinatura recusada no meio da execucao). Lotes seguintes custam dolar.')
                    # DRYRUN-CRASH1: dry-run nunca dispara notificar_rotina (02/09 02:45 mandou e-mail real de um teste).
                    if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
                    else { $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: escalou para chave paga no lote ' + $label + ' - assinatura recusada no meio da execucao; regerar token com claude setup-token') -RoutineKey $routineKey -Causa 'escalacao_chave_paga' -Severidade 'aviso' }
                }
                        if ($result.AuthFailure) {
                            $motivoAuth = Get-ClaudeAuthMotivo $result.Output
                            # COTAESGOTADA1 (2026-09-16): com a cota esgotada confirmada, o motivo real e a
                            # classificacao (ex.: reset fora do teto de parede), nao o fragmento que a
                            # regex do motor achou. O texto vai para o ERRO CRITICO, o ALERTA_AUTH e o
                            # detalhe do deferimento.
                            if ($result.CotaEsgotadaMotivo) { $motivoAuth = $result.CotaEsgotadaMotivo }
                            $jIdx = Get-JobIndex $jobs $job
                            Set-VixCobFallbackFalhaClasse ((@($result.Output) -join ' ') + ' ' + $result.CotaEsgotadaMotivo + ' ' + $motivoAuth) ('lote ' + $label)
                            Write-Log ('ERRO CRITICO: claude -p recusou o lote ' + $label + ' - ' + $motivoAuth + ' - abortando lotes restantes (' + ($jobs.Count - $jIdx - 1) + ' lote(s) NAO processado(s)).')
                            Write-Log ($AlertaAuthTag +$Rotina + ' abortada no lote ' + $label + ' - ' + $motivoAuth)
                            if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
                            else { $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: ' + $motivoAuth + ' - lotes restantes abortados (' + $label + ')') -RoutineKey $routineKey -Causa 'falha_auth' -Severidade 'critico' }
                            $exitCode = 7
                            $stats.batch_fail++
                            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                            # COBERTURAAUTH1 (2026-09-15): o motivo do deferimento passa a ser o REAL. Antes, os
                            # emissores deste lote e dos seguintes saiam todos como motivo=cap_efetivo, com
                            # cobertura_nota "Cap efetivo 700000 tokens" em producao, mesmo com o cap longe de ser
                            # alcancado (14/09: 378424/700000 e 24 DEFERIDO por limite de sessao da assinatura).
                            # lotes_nao_processados fica explicito: o numero que aparecia so no ERRO CRITICO.
                            $motivoDeferido = Get-VixDeferidoMotivo $true
                            $abortoAuthDetalhe = $motivoAuth
                            $stats.lotes_nao_processados = ($jobs.Count - $jIdx - 1)
                            # Lote atual (nada submetido) e todos os seguintes vao para DEFERIDO.
                            if ($jIdx -ge 0) { for ($k = $jIdx; $k -lt $jobs.Count; $k++) { foreach ($e in $jobs[$k].Chunk) { $pendingDeferred.Add([pscustomobject]@{ emissor = $e; tier = $jobs[$k].Tier }) } } }
                            break
                        }

                        if ($result.Output) { $result.Output | ForEach-Object { Write-Log ('OUT: ' + $_) } }

        $bt = $result.Tokens
        # CODEXFALLBACK-OR1 (2026-10-14): quando o lote do Codex foi desviado para o OpenRouter,
        # a tentativa do Codex que falhou continua cobrada no consumo do dia. Medida quando o
        # Codex publicou usage; estimada (estLote) quando nao publicou - consumo desconhecido
        # nunca vira zero (regra CUSTOFALHA-TETO1/COBERTURA-13OUT1).
        if ($result.ContainsKey('TokensFalhaFallback')) {
            $__fxCobrado = [int64]$result.TokensFalhaFallback
            if ($__fxCobrado -ge 0) {
                # Custo MEDIDO da tentativa que falhou: consumo real, nao estimativa.
                if ($__fxCobrado -gt 0) {
                    $stats.tokens_total += $__fxCobrado
                    Write-Log ('FALLBACK_CODEX_COBRADO: ' + $__fxCobrado + ' tokens medidos da tentativa codex que falhou antes do desvio; cobrados no consumo do dia. acum=' + $stats.tokens_total)
                }
            } else {
                # Consumo desconhecido da tentativa que falhou: cobrado pela estimativa, nunca zero.
                $__fxEst = [int64]$estLote
                if ($__fxEst -gt 0) {
                    $stats.tokens_total += $__fxEst
                    $stats.tokens_estimados_falha += $__fxEst
                    Write-Log ('FALLBACK_CODEX_COBRADO: ESTIMADO_FALHA ' + $__fxEst + ' tokens da tentativa codex que falhou sem usage antes do desvio; cobrados no consumo do dia. acum=' + $stats.tokens_total)
                }
            }
        }
        if (-not $result.UsoMensuravel) {
            $stats.tokens_mensuraveis = $false
            $stats.tokens_hard_hit = $true
            $capAtingido = $true; $capEscaladaFechado = $true
            $bt = 'NAO_MENSURAVEL'
            Write-Log 'Tokens lote=NAO_MENSURAVEL (codex nao emitiu usage) - cap fechado para lotes seguintes, sem diagnostico de parse'
        }
        elseif ($bt -ge 0) {
            $stats.tokens_total += $bt
            $stats.input += $result.Parcelas.input; $stats.output += $result.Parcelas.output
            $stats.cache_creation += $result.Parcelas.cache_creation; $stats.cache_read += $result.Parcelas.cache_read
            try { if ($null -ne $result.Parcelas.cache_codex) { $stats.cache_codex += [int64]$result.Parcelas.cache_codex } } catch { }
            Write-Log ('Tokens lote=' + $bt + ' (input=' + $result.Parcelas.input + ' output=' + $result.Parcelas.output + ' cache_creation=' + $result.Parcelas.cache_creation + ' cache_read=' + $result.Parcelas.cache_read + ') acum=' + $stats.tokens_total)
            if ($script:VixUsaCodex -and $script:VixUltimoCodexCached -gt 0) { $stats.codex_cached += [int64]$script:VixUltimoCodexCached }
            # Custo observado calibra os proximos lotes DESTA execucao, e agora com a CLASSE
            # junto: amostra de lote barato nao barateia a estimativa de um lote FULL (foi essa
            # mistura que produziu a estimativa de 497.104 para um lote de 1.193.101 em 14/10).
            # So conta lote que entregou (provedor ok), para falha nao baratear a estimativa.
            if (-not $result.ProviderFalhou -and $job.Chunk.Count -gt 0 -and $bt -gt 0) { $__custosObservados.Add(@{ classe = $__classeLote; emissores = $job.Chunk.Count; trabalho = [int64]$bt }) }
            if ($stats.tokens_total -gt $__capLote) {
                $stats.cap_excedido++
                if ($job.Escalada) { $capEscaladaFechado = $true } else { $capAtingido = $true }
                $stats.tokens_hard_hit = $true
                Write-Log ('CAP_EXCEDIDO: lote ' + $label + ' custou ' + $bt + ' contra estimativa ' + $estLote + '; acum=' + $stats.tokens_total + ' > cap=' + $__capLote + '. Cap fechado; estimativa recalibrada pelo custo observado.')
            }
        } elseif ($result.ConsumoDesconhecidoFalha) {
            # COBERTURA-13OUT1: lote que falhou sem usage. Consumo desconhecido NUNCA vira zero:
            # cobra a estimativa do lote, em contador proprio, e segue o disjuntor de provedor.
            $stats.tokens_total += [int64]$estLote
            $stats.tokens_estimados_falha += [int64]$estLote
            $bt = $estLote
            Write-Log ('Tokens lote=ESTIMADO_FALHA ' + $estLote + ' (provedor falhou sem publicar usage; cobrado pela estimativa, nunca zero) acum=' + $stats.tokens_total)
        } else {
            # Nao deveria acontecer depois de COBERTURA-13OUT1 (Invoke-ClaudeBatch converte
            # tokens<0 em NAO_MENSURAVEL ou ConsumoDesconhecidoFalha). Fail-closed por garantia.
            $stats.tokens_mensuraveis = $false; $stats.tokens_hard_hit = $true; $capAtingido = $true; $capEscaladaFechado = $true
            $bt = 'NAO_MENSURAVEL'
            Write-Log 'Tokens lote=DESCONHECIDO - tratado como NAO_MENSURAVEL, cap fechado (nunca acum inalterado)'
        }
        if ($result.ProviderFalhou) {
            Set-VixCobFallbackFalhaClasse ((@($result.Output) -join ' ') + ' ' + $result.ProviderClasse) ('lote ' + $label)
            $__disjuntor = Update-VixDisjuntorProvider $__disjuntor $true $result.ProviderClasse ([bool]$result.ProviderSemPerspectiva)
            # Lote inteiro sem analise: pendente com motivo proprio, sem retry parcial (repetir a
            # mesma chamada no mesmo provedor e o que COBERTURA-13OUT1 proibe) e sem submit de stub.
            foreach ($e in $job.Chunk) { $pendingDeferred.Add([pscustomobject]@{ emissor = $e; tier = $job.Tier; motivo = 'falha_provider' }) }
            $stats.batch_fail++
            Write-Log ('LOTE_FALHA_PROVIDER|' + $label + '|classe=' + $result.ProviderClasse + '|sem_perspectiva=' + $result.ProviderSemPerspectiva + '|emissores=' + $job.Chunk.Count + '|disjuntor=' + $(if ($__disjuntor.aberto) { 'ABERTO:' + $__disjuntor.motivo } else { 'fechado' }) + '|tokens=' + $bt)
            $lotesDetalhe.Add([ordered]@{ nome = $label; fila = $job.Name; classe = $__classeLote; emissores = 0; provider = $__providerExec; falha_provider = $true; input = $result.Parcelas.input; output = $result.Parcelas.output; cache_creation = $result.Parcelas.cache_creation; cache_read = $result.Parcelas.cache_read; trabalho = $bt; duracao_sec = [Math]::Round($swLote.Elapsed.TotalSeconds, 1) })
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            Update-VixLock
            continue
        }
        $__disjuntor = Update-VixDisjuntorProvider $__disjuntor $false
        # COBFALLBACK1: lote entregue limpa a falha registrada (cota que ja passou nao fica pendurada).
        if ($script:VixCobFallbackModo -and $script:VixCobFallbackFalha -eq '$nulo') { $script:VixCobFallbackFalha = '' }
        $lotesDetalhe.Add([ordered]@{
            nome = $label; fila = $job.Name; classe = $__classeLote; emissores = $job.Chunk.Count; provider = $__providerExec
            input = $result.Parcelas.input; output = $result.Parcelas.output; cache_creation = $result.Parcelas.cache_creation
            cache_read = $result.Parcelas.cache_read; trabalho = $result.Parcelas.trabalho; duracao_sec = [Math]::Round($swLote.Elapsed.TotalSeconds, 1)
        })

        $parsed = Get-ParsedResultados $result.Output
        $buscasLote = $parsed.Buscas

        $missing = @($job.Chunk | Where-Object { -not (Get-ResultadoEmissor $parsed.Map $_.empresa) })
        # COBERTURA-13OUT1: o retry parcial tambem passa pelo orcamento. Sem caber, os faltantes
        # seguem o caminho de RECHECK_PENDENTE (sem certificar ausencia) e ficam na fila.
        $__retryCabe = $true
        if ($missing.Count -gt 0 -and $result.UsoMensuravel) {
            # ORCAMENTO-CLASSE1: o retry parcial usa o MESMO envelope da classe do lote - nao a
            # estimativa antiga por emissor constante. O retry roda com o lote menor de faltantes,
            # entao o envelope compativel e o de `$missing.Count`.
            $__cpeRetry = Get-VixEstimativaClasseResumo -Modelo $__modelo -Emissores $missing.Count
            $__retryCabe = (-not $__laneFechada) -and ((Get-VixEmissoresQueCabemModelo -Modelo $__modelo -Acum $stats.tokens_total -Cap $__capLote -Chunk $missing.Count) -ge $missing.Count)
            if (-not $__retryCabe) { Write-Log ('RETRY_PARCIAL_SUPRIMIDO: ' + $missing.Count + ' faltante(s) no lote ' + $label + ' nao cabem no cap (acum=' + $stats.tokens_total + ' cap=' + $TokenHardCap + ' custo_emissor=' + $__cpeRetry.Custo + ') - seguem para RECHECK_PENDENTE e fila pendente') }
        }
        if ($missing.Count -gt 0 -and $result.UsoMensuravel -and $__retryCabe) {
            Write-Log ('WARN: ' + $missing.Count + ' sem RESULTADO no lote ' + $label + ' - retry parcial: ' + (($missing | ForEach-Object { $_.empresa }) -join ', '))
            $retryLabel = $label + '-retry'
            $retryPrompt = New-BatchPrompt $missing $retryLabel $modeloPrompt $job.Skill $janIni $janFim $fonteProvedor -Ultra:$job.Ultra -Tier $job.Tier -ModoEscalada:([bool]$job.Escalada) -ModoBarato:([bool]$job.Barato)
            $retryPath = Join-Path $LogDir ($Perfil.prefix + '_' + $retryLabel + '_' + $DateTag + '.txt')
            Set-Content $retryPath -Value $retryPrompt -Encoding UTF8
            $retryRes = Invoke-ClaudeBatch $retryPath $job.Model $missing.Count $job.Tier -ProviderOverride $script:VixCobFallbackProvider
            $stats.degradados_402 += [int]$retryRes.Degradados402
            if ($retryRes.Escalou) { $stats.auth_escalou = 'api'; Write-Log ($AlertaAuthTag + 'escalou para chave paga no retry ' + $retryLabel) }
            if ($retryRes.AuthFailure) {
                Set-VixCobFallbackFalhaClasse ((@($retryRes.Output) -join ' ') + ' ' + $retryRes.CotaEsgotadaMotivo) ('retry ' + $retryLabel)
                # RETRYDROP1: preserva o que o lote principal ja parseou, marca abort apos submit.
                Write-Log ('ERRO CRITICO: claude -p recusou o retry do lote ' + $label + ' - ' + (Get-ClaudeAuthMotivo $retryRes.Output) + ' - ' + $missing.Count + ' faltantes recebem fallback; lotes restantes NAO serao processados.')
                # COBERTURAAUTH1 (2026-09-15): mesma correcao do aborto direto - a causa real
                # (limite de sessao da assinatura) substitui o rotulo fixo de cap de tokens.
                $motivoDeferido = Get-VixDeferidoMotivo $true
                $abortoAuthDetalhe = Get-ClaudeAuthMotivo $retryRes.Output
                # COTAESGOTADA1: mesma regra do aborto direto - a causa real (reset fora do teto)
                # substitui o fragmento da regex no detalhe do deferimento.
                if ($retryRes.CotaEsgotadaMotivo) { $abortoAuthDetalhe = $retryRes.CotaEsgotadaMotivo }
                $exitCode = 7
                $stats.batch_fail++
                $abortAfterSubmit = $true
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
            } else {
                if ($retryRes.Output) { $retryRes.Output | ForEach-Object { Write-Log ('OUT-RETRY: ' + $_) } }
                if (-not $retryRes.UsoMensuravel) {
                    $stats.tokens_mensuraveis = $false
                    $stats.tokens_hard_hit = $true
                    $capAtingido = $true; $capEscaladaFechado = $true
                    Write-Log 'Tokens retry=NAO_MENSURAVEL (codex nao emitiu usage) - cap fechado para lotes seguintes'
                }
                elseif ($retryRes.Tokens -ge 0) {
                    $stats.tokens_total += $retryRes.Tokens
                    $stats.input += $retryRes.Parcelas.input; $stats.output += $retryRes.Parcelas.output
                    $stats.cache_creation += $retryRes.Parcelas.cache_creation; $stats.cache_read += $retryRes.Parcelas.cache_read
                    if ($script:VixUsaCodex -and $script:VixUltimoCodexCached -gt 0) { $stats.codex_cached += [int64]$script:VixUltimoCodexCached }
                    $lotesDetalhe.Add([ordered]@{ nome = $retryLabel; fila = $job.Name; classe = $__classeLote; emissores = $missing.Count; provider = $__providerExec; input = $retryRes.Parcelas.input; output = $retryRes.Parcelas.output; cache_creation = $retryRes.Parcelas.cache_creation; cache_read = $retryRes.Parcelas.cache_read; trabalho = $retryRes.Parcelas.trabalho; duracao_sec = 0 })
                    if ($stats.tokens_total -gt $__capLote) { $stats.cap_excedido++; if ($job.Escalada) { $capEscaladaFechado = $true } else { $capAtingido = $true }; $stats.tokens_hard_hit = $true; Write-Log ('CAP_EXCEDIDO: retry ' + $retryLabel + ' levou acum a ' + $stats.tokens_total + ' > cap=' + $__capLote) }
                }
                elseif ($retryRes.ConsumoDesconhecidoFalha) {
                    $__estRetry = [int64]$__cpeRetry.Custo * $missing.Count
                    $stats.tokens_total += $__estRetry; $stats.tokens_estimados_falha += $__estRetry
                    Write-Log ('Tokens retry=ESTIMADO_FALHA ' + $__estRetry + ' (provedor falhou sem usage; nunca zero) acum=' + $stats.tokens_total)
                }
                else {
                    $stats.tokens_mensuraveis = $false; $stats.tokens_hard_hit = $true; $capAtingido = $true; $capEscaladaFechado = $true
                    Write-Log 'Tokens retry=DESCONHECIDO - tratado como NAO_MENSURAVEL, cap fechado'
                }
                if ($retryRes.ProviderFalhou) {
                    $__disjuntor = Update-VixDisjuntorProvider $__disjuntor $true $retryRes.ProviderClasse ([bool]$retryRes.ProviderSemPerspectiva)
                    Write-Log ('RETRY_FALHA_PROVIDER|' + $retryLabel + '|classe=' + $retryRes.ProviderClasse + '|disjuntor=' + $(if ($__disjuntor.aberto) { 'ABERTO:' + $__disjuntor.motivo } else { 'fechado' }))
                }
                $retryParsed = Get-ParsedResultados $retryRes.Output
                foreach ($k in @($retryParsed.Map.Keys)) { $parsed.Map[$k] = $retryParsed.Map[$k] }
                if ($retryParsed.Buscas -gt 0) { if ($buscasLote -lt 0) { $buscasLote = 0 }; $buscasLote += $retryParsed.Buscas }
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
            }
        }
        elseif ($missing.Count -gt 0 -and -not $result.UsoMensuravel) {
            Write-Log ('USAGE_CODEX=NAO_MENSURAVEL: retry parcial suprimido para nao derrotar o cap (' + $missing.Count + ' emissor(es))')
        }

        $parsedCount = 0
        foreach ($emp in $job.Chunk) { if (Get-ResultadoEmissor $parsed.Map $emp.empresa) { $parsedCount++ } }
        if ($parsedCount -eq 0) {
            $stats.silent_fail++
            Write-Log ('ERRO: lote ' + $label + ' sem RESULTADO| - falha silenciosa (0/' + $job.Chunk.Count + ' emissores com analise real)')
        }
        if ($parsedCount -gt 0) { $stats.lotes_com_trabalho++ }

        $loteOk = 0; $loteFail = 0; $loteCrit = 0; $loteDry = 0
        $buscasReaisLote = 0
        foreach ($emp in $job.Chunk) {
            $res = Get-ResultadoEmissor $parsed.Map $emp.empresa
            if (-not $res) {
                Write-Log ('WARN: ' + $emp.empresa + '|sem RESULTADO apos retry - submit minimo de cobertura pendente')
                $res = [pscustomobject]@{
                    classificacao_geral = 'NENHUM'; sem_eventos = $true
                    cobertura_nota = 'Falha de parse do agente apos retry - cobertura pendente, revisar manualmente.'
                    eventos = @(); fontes_consultadas = @()
                }
            }
            # BUSCADEGRADADA1 (2026-09-08): conta buscas EFETIVAS x DEGRADADAS por emissor.
            # Antes o regex so pegava "indisponivel|falha|erro|timeout|vazio"; o texto real de
            # esgotamento ("sem resultados - limite de busca", "max_total_results", "restric")
            # NAO casava e virava "busca efetiva" — lote noturno de 08/09 gravou 15 emissores
            # ANALISADO/sem_eventos com 23 das 25 buscas esgotadas por limite do lote.
            # COBERTURA-13OUT2: no modo coletor, soma ao resultado da IA as consultas que o orquestrador
            # fez (HTTP real). Coleta incompleta ou divergencia IA x coletor nao somam nada.
            # COBERTURA-13OUT4: os sinais da coleta que decidem a escalada saem daqui, e nao de uma
            # segunda leitura: o coletor ja foi consultado para este emissor e repetir a chamada
            # custaria rede sem trazer prova nova.
            $__divergiu = $false
            $__novasTri = @()
            $__coletaInd = $false
            # RECHECKDIVERG1: horario medido do lote nas fontes Codex completas e sem timestamp.
            try {
                $__nTs = Set-VixTimestampLoteCodex -Res $res -Ts ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
                if ($__nTs -gt 0) { Write-Log ('TIMESTAMP_LOTE|' + $emp.empresa + '|fontes_codex_carimbadas=' + $__nTs + ' (origem=orquestrador_lote)') }
            } catch { Write-Log ('TIMESTAMP_LOTE_ERRO|' + $emp.empresa + '|' + $_.Exception.Message) }
            if ($script:VixColetorAtivo) {
                try {
                    $__colIA = Get-VixColetorParaEmissor ('' + $emp.empresa)
                    $__triIA = $null
                    if ($null -ne $__colIA) { $__triIA = Get-VixTriagemEmissor -Coleta $__colIA -DeltaInicio ('' + $emp.janela_delta_inicio) -CvmNovos 0 -HorasDesdeIA 0 -Ews 0 }
                    if ($null -ne $__triIA) { $__novasTri = @($__triIA.Novas) }
                    $__coletaInd = ($null -eq $__colIA) -or ($null -ne $__colIA.PSObject.Properties['disponivel'] -and -not $__colIA.disponivel)
                    $__novasIA = $__novasTri
                    $__mg = Add-VixFontesColetorAoResultado -Res $res -Coleta $__colIA -DeltaInicio ('' + $emp.janela_delta_inicio) -Novas $__novasIA
                    Write-Log ('FONTES_COLETOR|' + $emp.empresa + '|' + $__mg.Motivo + '|adicionadas=' + $__mg.Adicionadas + '|vereditos=' + $__mg.Vereditos)
                    if ($__mg.Divergencia) { $__divergiu = $true; Write-Log ('DIVERGENCIA_IA_COLETOR|' + $emp.empresa + '|' + $__mg.Motivo + ' -> sem somar fontes, segue INCONCLUSIVO para reanalise') }
                } catch { Write-Log ('FONTES_COLETOR_ERRO|' + $emp.empresa + '|' + $_.Exception.Message) }
            }
            # RECHECKDIVERG1: os vereditos servem a conferencia local e ja ficaram no log (OUT:). O
            # objeto submetido ao Worker volta ao contrato de sempre, so com a contagem.
            if ($null -ne $res.PSObject.Properties['vereditos_manchetes']) {
                try {
                    $res | Add-Member -NotePropertyName '_vereditos_manchetes_n' -NotePropertyValue (@($res.vereditos_manchetes).Count) -Force
                    $res.PSObject.Properties.Remove('vereditos_manchetes')
                } catch { }
            }
            $cobWeb = Resolve-VixCoberturaWeb $res
            $buscasEfetivas = $cobWeb.efetivas
            $buscasReaisLote += $buscasEfetivas
            $classif = '' + $res.classificacao_geral
            if (-not $classif) { $classif = if (@($res.eventos).Count -gt 0) { 'RELEVANTE' } else { 'ECO' } }
            if ($script:VixTriagemSombra -and -not $DryRun) { try { Add-VixRelevanciaRegistro (Get-VixRelevanciaSombraPath $LogDir $DateTag) ([ordered]@{ tipo = 'desfecho'; empresa = ('' + $emp.empresa); classificacao = $classif; n_eventos = @($res.eventos).Count; ts = (Get-Date).ToString('s') }) } catch { } }
            # BUSCADEGRADADA1-FIX (2026-09-09): gate UNICO de ausencia. Substitui as tres rotas
            # antigas (web pendente, FULL 0 buscas, COBERTURA1 de familias) que certificavam
            # sem_eventos=true mesmo INCONCLUSIVO e nao persistiam recheck — foi assim que a
            # Vibra saiu "sem evento" no dia da emissao de R$1,4 bi. Agora: QUALQUER busca
            # falhada/degradada/esgotada/timeout/insuficiente PROIBE sem_eventos, classifica
            # INCONCLUSIVO e grava RECHECK_PENDENTE no contrato do dia; a priorizacao existente
            # (contrato com faltantes>0 vai ao inicio da fila) recoloca o emissor na proxima
            # execucao. Saudavel sem fato => sem_eventos=true segue intocado; com evento, o
            # fluxo normal segue intocado.
            $__decAus = Test-VixAusenciaCertificavel $res
            # DIVERGENCIACOMPROVA1 (2026-10-14): divergencia IA x coletor e PROVA de que a
            # ausencia nao esta certificada - a IA disse "sem evento" e o coletor viu manchete
            # nova citando o emissor. O log ja dizia "segue INCONCLUSIVO para reanalise" desde
            # 13/10, mas nada no fluxo mudava: a classificacao seguia NENHUM/ECO, o portao de
            # ausencia voltava `cobertura_valida` (as tres familias voltaram com status null,
            # permitido no contrato do Codex), o emissor era carimbado como concluido, solto da
            # fila e o contrato gravava RESOLVIDO. Em 14/10 isso aconteceu com SETE emissores
            # (VLI, Vale, Rumo, Usiminas, Eletrobras, Gerdau, PRIO) num total de 16 analises -
            # falso estado de sucesso medido. Agora a divergencia entra no MESMO portao de
            # ausencia como recheck pendente, com motivo proprio.
            if ($__divergiu -and -not $__decAus.recheck) {
                $__decAus = [pscustomobject]@{ permitir_sem_eventos = $false; recheck = $true; motivo = 'divergencia_ia_coletor'; faltantes = @('coletor') }
            }
            $__classifAusencia = ($classif -in @('NENHUM', 'ECO', '')) -and (@($res.eventos).Count -eq 0)
            if ($__classifAusencia -and -not $__decAus.permitir_sem_eventos) {
                Write-Log ('RECHECK_PENDENTE|' + $emp.empresa + '|motivo=' + $__decAus.motivo + '|faltantes=' + ($__decAus.faltantes -join ',') + '|buscas=' + $cobWeb.degradadas + '_degradadas/' + $cobWeb.efetivas + '_efetivas -> INCONCLUSIVO, sem_eventos PROIBIDO, reanalise priorizada na proxima execucao')
                $classif = 'INCONCLUSIVO'
                $res.sem_eventos = $false
                $__faltaTxt = 'Cobertura nao verificavel (' + $__decAus.motivo + ') - RECHECK_PENDENTE, reanalise priorizada na proxima execucao. Familias/itens: ' + ($__decAus.faltantes -join ', ') + '.'
                if (-not $res.cobertura_nota) { $res.cobertura_nota = $__faltaTxt } else { $res.cobertura_nota = $res.cobertura_nota + ' ' + $__faltaTxt }
                try { $res | Add-Member -NotePropertyName '_cobertura_web_degradada' -NotePropertyValue $true -Force } catch { }
                try { $res | Add-Member -NotePropertyName '_recheck_pendente' -NotePropertyValue $true -Force } catch { }
                try { $res | Add-Member -NotePropertyName '_familia_faltantes' -NotePropertyValue @($__decAus.faltantes) -Force } catch { }
                $stats.cobertura_deferidos++
                if (-not $DryRun) { Merge-VixContratoCobertura $contratoCobertura $emp.empresa 'RECHECK_PENDENTE' $__decAus.faltantes }
            }
            # COBERTURA-13OUT4: escalada por emissor. Decide com os sinais JA medidos nesta
            # passada (classificacao, eventos, portao de ausencia, divergencia IA x coletor, CVM
            # novo, EWS e as manchetes novas do coletor). Emissor retido aqui NAO e submetido na
            # rodada barata: o pacote barato nao tem a prova que este emissor exige, e submeter
            # agora seria certificar com manchete o que so a fonte primaria sustenta. Ele volta
            # na rodada de escalada, com ferramenta, e e essa submissao que fecha o ledger dele.
            # Dois guards de escopo, ambos por comportamento medido no proprio desenho:
            # (1) $job.Escalada: lote de escalada nao reescala, senao a escalada se chamaria para
            #     sempre;
            # (2) $job.Barato: SO lote que rodou SEM ferramenta pode reter. Sem este guard, o lote
            #     FULL da rotacao semanal noturna - Sonnet, COM ferramenta, escolhido por risco,
            #     ou seja cheio de EWS >= 50 - casaria gatilho em quase todo emissor, seria retido
            #     e re-escalado: a rodada boa (que ja abriu a fonte primaria) seria descartada e o
            #     mesmo emissor pagaria dois lotes FULL na mesma noite. Escalada existe para
            #     consertar o que o pacote barato nao conseguiu, e um lote com ferramenta nao tem o
            #     que consertar.
            # Dry-run NAO e excluido de proposito. A homologacao da escalada e uma execucao
            # dirigida (-DryRun -MaxEmissores 1): sem a retencao no dry-run, a rodada de escalada
            # nunca seria exercitada antes de ligar o coletor em producao, e a unica forma de
            # medir o custo real de um lote de escalada seria uma execucao real. Em dry-run nada e
            # submetido e o ledger sai com prefixo DRYRUN, que os leitores de entrega nao contam.
            if (Test-VixEscaladaRetem -Ativa ([bool]$script:VixEscaladaAtiva) -JaEscalada ([bool]$job.Escalada) -Barato ([bool]$job.Barato)) {
                $__ewsE = 0; try { $__ewsE = [int]$emp.ews_score } catch { $__ewsE = 0 }
                $__cvmE = 0; try { $__cvmE = [int]$emp.cvm_novos } catch { $__cvmE = 0 }
                $__esc = Get-VixEscaladaDecisao -Classificacao $classif -Eventos @($res.eventos).Count -RecheckPendente ([bool]$__decAus.recheck) -DivergenciaColetor $__divergiu -CvmNovos $__cvmE -Ews $__ewsE -ColetaIndisponivel $__coletaInd -Novas $__novasTri
                Write-Log ('ESCALADA_DECISAO|' + $emp.empresa + '|escalar=' + $(if ($__esc.Escalar) { 1 } else { 0 }) + '|' + $__esc.Motivo + '|prioridade=' + $__esc.Prioridade + '|classif=' + $classif + '|eventos=' + @($res.eventos).Count + '|ews=' + $__ewsE + '|cvm_novos=' + $__cvmE + '|divergencia=' + [int]$__divergiu + '|coleta_indisponivel=' + [int]$__coletaInd)
                if ($__esc.Escalar) {
                    $__escaladaFila.Add([pscustomobject]@{ Emp = $emp; Prioridade = [int]$__esc.Prioridade; Motivo = $__esc.Motivo })
                    $stats.escalada_retidos++
                    continue
                }
            }
            try { $res | Add-Member -NotePropertyName '_tier' -NotePropertyValue $job.Tier -Force } catch { }
            # ENVIADOS1 (2026-10-13): $enviados nunca era atribuido. O ramo de DESCARTE_PARCIAL
            # compara `$nEv -lt $enviados` e, com a variavel inexistente, o PowerShell converte o
            # $null para 0 na comparacao: a condicao era sempre falsa e o ramo estava morto desde
            # FEEDRETRO1 FASE2. Consequencia: submit em que o Worker persiste PARTE dos eventos
            # nao incrementava `descartes_inesperados`, e `descartes_inesperados` entra em
            # `errosTotal`, que decide OK x PARCIAL. Ou seja, o dia fechava OK com evento
            # descartado por causa inesperada (fonte inacessivel no fetch, data da fonte
            # divergente) sem ninguem ver. Medido por leitura do fonte: a string 'enviados' so
            # existia nos textos de log.
            $enviados = @($res.eventos).Count
            $subOk = $false; $nEv = 0; $nAvanco = 0
            try {
                $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor $job.Tier @($emp.cvm_novos_ids)
                if ($resp.ok -ne $true -and -not $DryRun) {
                    Start-Sleep -Seconds $PauseSec
                    $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor $job.Tier @($emp.cvm_novos_ids)
                }
                $subOk = ($resp.ok -eq $true)
                if ($subOk) {
                    $nEv = [int]$resp.n_eventos
                    if ($null -ne $resp.n_eventos_avanco_data) { $nAvanco = [int]$resp.n_eventos_avanco_data }
                    $stats.eventos_avanco_data += $nAvanco
                    if ($null -ne $resp.n_chaves_novas) { $stats.chaves_novas += [int]$resp.n_chaves_novas }
                    # FEEDRETRO1 FASE2 (2026-09-04, guarda portada de repor-varredura.ps1): o
                    # Worker responde ok:true mesmo quando descarta TODOS os eventos enviados
                    # (removidos_pre_verificador>0 ou saneamento). ok de transporte nao prova
                    # que o fato entrou no estado - so n_eventos>=1 prova. Sem esta linha, um
                    # submit assim contava como sucesso pleno e ninguem via o descarte (e foi
                    # exatamente isso que passou 5 dias uteis sem alarme em 28/08-03/09).
                    # -not $DryRun e obrigatorio: Submit-Analise em dry-run devolve o stub
                    # { ok=true; n_eventos=0 } sem chamar o Worker (linha 218), entao TODO
                    # emissor que devolvesse evento sairia como DESCARTADO falso. Medido no
                    # dry-run de 04/09: Kora Saude, 1 evento real de 04/09, logou
                    # 'DESCARTADO|Kora Saude|enviados=1|persistidos=0|motivo_nao_detalhado'
                    # e somou descartados=1 no FIM_DRYRUN sem nenhum descarte ter existido.
                    if (-not $DryRun -and @($res.eventos).Count -ge 1) {
                                            if ($nEv -eq 0) {
                                                # Caso esperado: nenhum evento persistido
                                                $descMotivos = @()
                                                if ($resp.descartes) {
                                                    foreach ($k in @('ruido', 'sem_data', 'fora_janela', 'data_futura', 'data_aproximada', 'fonte_inacessivel')) {
                                                        if ($resp.descartes.$k -gt 0) { $descMotivos += ($k + '=' + $resp.descartes.$k) }
                                                    }
                                                }
                                                $motivoTxt = if ($descMotivos.Count -gt 0) { $descMotivos -join ',' } else { 'motivo_nao_detalhado' }
                                                Write-Log ('DESCARTADO|' + $emp.empresa + '|enviados=' + @($res.eventos).Count + '|persistidos=0|' + $motivoTxt)
                                                $stats.descartados++
                                            } elseif ($nEv -lt $enviados) {
                                                # Caso inesperado: alguns eventos persistidos, mas não todos
                                                $descMotivosInesperados = @()
                                                $descMotivosEsperados = @()
                                                if ($resp.descartes) {
                                                    foreach ($k in @('ruido', 'sem_data', 'fora_janela', 'data_futura', 'data_aproximada', 'data_url_antiga', 'data_fonte_antiga')) {
                                                        if ($resp.descartes.$k -gt 0) { $descMotivosEsperados += ($k + '=' + $resp.descartes.$k) }
                                                    }
                                                    foreach ($k in @('fonte_inacessivel_fetch', 'data_fonte_divergente')) {
                                                        if ($resp.descartes.$k -gt 0) { $descMotivosInesperados += ($k + '=' + $resp.descartes.$k) }
                                                    }
                                                }
                                                $motivoEsperado = if ($descMotivosEsperados.Count -gt 0) { $descMotivosEsperados -join ',' } else { 'ruido' }
                                                $motivoInesperado = if ($descMotivosInesperados.Count -gt 0) { $descMotivosInesperados -join ',' } else { 'motivo_nao_detalhado' }
                                                Write-Log ('DESCARTE_PARCIAL|' + $emp.empresa + '|enviados=' + @($res.eventos).Count + '|persistidos=' + $nEv + '|' + $motivoEsperado + '|' + $motivoInesperado)
                                                # Contador de descartes inesperados: somados a errosTotal fazem a rotina fechar PARCIAL
                                                if ($descMotivosInesperados.Count -gt 0) { $stats.descartes_inesperados += $descMotivosInesperados.Count }
                                                $stats.descartados++
                                            }
                                        }
                }
                elseif ($resp.erro) { Write-Log ('SUBMIT_ERRO|' + $emp.empresa + '|' + $resp.erro) }
            } catch {
                Write-Log ('SUBMIT_EXC|' + $emp.empresa + '|' + $_.Exception.Message)
            }
            if ($DryRun) { $subOk = $false }
            Write-Ledger $emp.empresa $job.Tier $classif $nEv $subOk 'ANALISADO' $nAvanco
            # COBERTURA-13OUT1: marca a ultima analise de IA do emissor (a revalidacao periodica
            # da triagem le daqui; a analise deterministica NAO conta como IA).
            # INCONCLUSIVONAOECONCLUSAO1 (2026-10-13): so analise CONCLUIDA carimba. Ate 13/10
            # qualquer submit aceito carimbava, inclusive INCONCLUSIVO, e a linha logo abaixo ja
            # dizia o contrario (`$classif -ne 'INCONCLUSIVO'` mantem a pendencia). O efeito era
            # INCONCLUSIVO virar QUIETO na execucao seguinte: carimbo fresco -> portao de
            # revalidacao da triagem passa -> emissor certificado sem ninguem resolver a pergunta.
            $__concluida = (Test-VixAnaliseConcluida -SubOk ([bool]$subOk) -Classificacao ('' + $classif))
            if ($__concluida -and -not $DryRun) { try { Set-VixUltimaIA -Path (Get-VixUltimaIAPath $LogDir) -Empresa ('' + $emp.empresa) } catch { Write-Log ('ULTIMA_IA_ERRO: ' + $emp.empresa + ' - ' + $_.Exception.Message) } }
            # COBDIARIA1: analise do dia com provider, modelo, tier e prova. Recheck (ausencia nao
            # certificada) conta como INCONCLUSIVO: nao fecha o dia do emissor.
            if ($script:VixCobDiariaPath) {
                try {
                    $__cdCls = '' + $classif
                    if ($__decAus.recheck) { $__cdCls = 'INCONCLUSIVO' }
                    $__cdAn = [ordered]@{ provider = ('' + (Get-VixLlmProvider)); provedor_rotulo = ('' + $job.Provedor); modelo = ('' + $job.Model); tier = ('' + $job.Tier); barato = [bool]$job.Barato; escalada = [bool]$job.Escalada; classificacao = $__cdCls; submit_ok = [bool]$subOk; n_eventos = [int]$nEv; lote = ('' + $job.Name) }
                    $__cdA = Register-VixCobDiaria -Path $script:VixCobDiariaPath -DateTag $DateTag -Empresa ('' + $emp.empresa) -Estado 'VERIFICADO_ANALISADO' -Motivo ('analise:' + $__cdCls) -Rotina $Perfil.modo -Fontes @($res.fontes_consultadas) -Analise $__cdAn
                    Write-Log ('COBDIARIA|' + $emp.empresa + '|analise|' + $__cdCls + '|prova=' + $__cdA.Prova + '|estado=' + $__cdA.Estado)
                } catch { Write-Log ('COBDIARIA_ERRO: analise ' + $emp.empresa + ' - ' + $_.Exception.Message) }
            }
            # COBERTURA-13OUT1: so analise EFETIVA solta a pendencia persistente (submit aceito
            # e sem recheck). Recheck ou submit recusado mantem/abre a pendencia. Mesma definicao
            # de "concluida" da linha de cima, agora vinda da mesma funcao.
            if ($__concluida -and -not $__decAus.recheck) { Remove-VixPendenteSeguro $emp.empresa }
            elseif (-not $subOk) { Add-VixPendenteSeguro $emp.empresa $emp.ews_score 'submit_recusado' $job.Tier $false }
            else { Add-VixPendenteSeguro $emp.empresa $emp.ews_score 'recheck_cobertura' $job.Tier $true }
            # BUSCADEGRADADA1-FIX: RECHECK_PENDENTE so sai da frente da fila quando RESOLVIDO.
            # Emissor que estava pendente e fechou esta execucao com busca valida (sem recheck)
            # grava a resolucao no contrato do dia; o registro mais novo vence na leitura, entao
            # a prioridade termina aqui em vez de ficar presa para sempre. Sem submit aceito nao
            # ha resolucao: a pendencia continua viva para a proxima execucao.
            if ($subOk -and -not $__decAus.recheck -and $__faltAnt.ContainsKey((Get-NomeNormalizado $emp.empresa))) {
                if (-not $DryRun) { Merge-VixContratoCobertura $contratoCobertura $emp.empresa 'RESOLVIDO' @() }
                $stats.recheck_resolvidos++
                Write-Log ('RECHECK_RESOLVIDO|' + $emp.empresa + '|motivo=' + $__decAus.motivo)
            }
            # COBERTURA-RECON1: ESTADO do emissor no contrato do dia. Tres desfechos possiveis,
            # todos registrados - e o que faz `analisadas publicadas` (ledger) fechar com
            # `registros de cobertura`. Em 14/10 so quem estava PENDENTE ganhava registro, entao o
            # dia fechou com 16 analises e 11 coberturas e nao havia como saber se faltava
            # cobertura ou faltava registro.
            #   ANALISADO     - submit aceito e ausencia/evento certificado (sem recheck)
            #   INCONCLUSIVO  - recheck pendente (busca degradada, familias incompletas,
            #                   divergencia IA x coletor) ou submit recusado
            # RESOLVIDO nao e classificado aqui de proposito: quem estava pendente e fechou ja
            # gravou RESOLVIDO acima, e o registro mais novo vence. Estado nao se promove por
            # ausencia de prova - so por submit aceito com cobertura verificada.
            # RESOLVIDO e estado proprio: quem estava pendente e fechou com submit aceito e
            # cobertura verificada. Ele conta como analise publicada na reconciliacao - se virasse
            # ANALISADO, a informacao de que a pendencia foi resolvida se perderia; se nao
            # contasse, o dia em que a fila de recheck e resolvida pareceria faltar cobertura.
            # Estado nao se promove por ausencia de prova - so por submit aceito com cobertura
            # verificada.
            if ($__concluida -and -not $__decAus.recheck) {
                if ($__faltAnt.ContainsKey((Get-NomeNormalizado $emp.empresa))) {
                    Set-VixContratoEstado -Empresa $emp.empresa -Estado 'RESOLVIDO' -Motivo ('resolvido:' + $__decAus.motivo) -Faltantes @() -Triado $false
                } else {
                    Set-VixContratoEstado -Empresa $emp.empresa -Estado 'ANALISADO' -Motivo ('cobertura_valida:' + $__decAus.motivo) -Faltantes @() -Triado $false
                }
            } else {
                $__faltaEstado = @($__decAus.faltantes)
                if ($__faltaEstado.Count -eq 0) { $__faltaEstado = @(('motivo:' + $__decAus.motivo)) }
                if (-not $subOk) { $__faltaEstado = @('submit_recusado') }
                Set-VixContratoEstado -Empresa $emp.empresa -Estado 'INCONCLUSIVO' -Motivo ('nao_conclusiva:' + $(if ($subOk) { $__decAus.motivo } else { 'submit_recusado' })) -Faltantes $__faltaEstado -Triado $false
            }
            $stats.analisados++
            # COBERTURA-13OUT4: quantos dos analisados desta execucao vieram da rodada de escalada.
            if ($job.Escalada) { $stats.escalada_analisados++ }
            # Dry-run nao submete: nao e ok nem fail, e contado a parte (antes saia fail=3 enganoso).
            if ($DryRun) { $loteDry++ } elseif ($subOk) { $loteOk++ } else { $loteFail++ }
            if ($classif -eq 'CRITICO') { $loteCrit++; $stats.criticos.Add($emp.empresa) }
        }
        $stats.submit_ok += $loteOk
        $stats.submit_fail += $loteFail
        if ($buscasReaisLote -gt 0 -or $buscasLote -lt 0) { $buscasLote = $buscasReaisLote }
        if ($buscasLote -ge 0) { $stats.buscas_total += $buscasLote }
        Write-Log ('LOTE_FECHADO|' + $label + '|ok=' + $loteOk + '|fail=' + $loteFail + '|dryrun=' + $loteDry + '|buscas=' + $buscasLote + '|criticos=' + $loteCrit + '|tokens=' + $bt + '|duracao_sec=' + [Math]::Round($swLote.Elapsed.TotalSeconds, 1))
        if ($loteFail -gt 0 -and -not $DryRun) { $stats.batch_fail++ } else { $stats.batch_ok++ }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        Update-VixLock
        if ($abortAfterSubmit) {
            Write-Log 'ABORT: retry AuthFailure - resultados deste lote submetidos, lotes restantes NAO processados'
            # Lote atual ja submetido: so os seguintes vao para DEFERIDO.
            $jIdx = Get-JobIndex $jobs $job
            if ($jIdx -ge 0) { $stats.lotes_nao_processados = ($jobs.Count - $jIdx - 1) }
            if ($jIdx -ge 0) { for ($k = $jIdx + 1; $k -lt $jobs.Count; $k++) { foreach ($e in $jobs[$k].Chunk) { $pendingDeferred.Add([pscustomobject]@{ emissor = $e; tier = $jobs[$k].Tier }) } } }
            # COBERTURA-13OUT4: emissor retido na rodada barata e ainda sem rodada de escalada
            # nao pode sumir aqui. Ele nao tem lote, nao tem ledger e nao tem fila: sem esta
            # linha, o aborto por auth o deixaria fora do DEFERIDO do dia e o ledger fecharia
            # sem ele - nem analisado, nem deferido, sem ninguem ver. Com a rodada de escalada ja
            # montada, o aborto pelo contrario ja o alcanca por $jobs, entao aqui nao se repete.
            if (-not $__escaladaMontada -and $__escaladaFila.Count -gt 0) {
                foreach ($__itAb in @(Select-VixEscaladaOrdenada -Itens $__escaladaFila.ToArray())) { $pendingDeferred.Add([pscustomobject]@{ emissor = $__itAb.Emp; tier = 'FULL' }) }
                Write-Log ('ESCALADA_ABORTO: ' + $__escaladaFila.Count + ' emissor(es) retido(s) para escalada sem rodada FULL por causa do aborto - seguem DEFERIDO com o motivo do aborto, sem sumir do ledger')
            }
            break
        }
    }

    # COBFALLBACK1: gasto final desta execucao (ultimo lote e retry dele).
    Update-VixCobFallbackGastoSeguro
    # D1 do P0 PROFUNDIDADE-NOTURNA1: a cauda de rotacao entra no MESMO desfecho dos demais
    # deferidos, para o ledger fechar. O motivo e decidido aqui, depois do laco de lotes, porque
    # so aqui se sabe se o cap fechou no meio da noite ou se o circuito ja abriu. Circuito
    # aberto e cap estourado nao sao rotacao: sao corte por orcamento, e o texto de
    # CIRCUITO_ABERTO sempre prometeu exatamente isso ("tudo que nao for SKIP sai como DEFERIDO").
    if ($Perfil.modo -eq 'noturno') {
        $caudaRotacao = Get-VixCaudaRotacao -AnalyzeList $analyzeList -Fila $fila -CapAtingido $capAtingido -TokenHardCap $TokenHardCap -CircuitoAberto ([bool]$custoDia.circuito_aberto)
        if ($caudaRotacao.Emissores.Count -gt 0) {
            foreach ($eRot in $caudaRotacao.Emissores) {
                # MAXEMISSORESREAL1: cortado pelo -MaxEmissores do operador nao e rotacao.
                $__motRot = $caudaRotacao.Motivo
                if ($script:VixMaxEmissoresCortados.ContainsKey((Get-NomeNormalizado ('' + $eRot.empresa)))) { $__motRot = 'max_emissores' }
                $pendingDeferred.Add([pscustomobject]@{ emissor = $eRot; tier = $eRot.tier; motivo = $__motRot })
            }
            Write-Log ('ROTACAO: ' + $caudaRotacao.Emissores.Count + ' emissor(es) nao selecionados para FULL nem LIGHT saem como DEFERIDO motivo=' + $caudaRotacao.Motivo)
        }
    }

    foreach ($pendente in $pendingDeferred) {
        $emp = $pendente.emissor
        # O motivo do item vence o global quando existe (rotacao). Item sem motivo proprio
        # continua lendo $motivoDeferido, que e o comportamento de COBERTURAAUTH1: o corte por
        # assinatura no meio da execucao reescreve a causa de TODOS os deferidos, inclusive os
        # que entraram antes dele.
        $motivoItem = $motivoDeferido
        if ($pendente.PSObject.Properties['motivo'] -and $pendente.motivo) { $motivoItem = $pendente.motivo }
        $subOk = $false
        # COBFALLBACK1: o fallback NAO envia stub de deferido ao Worker. O emissor ja saiu DEFERIDO
        # pela noturna (com _token_cap_deferred); um segundo stub seria escrita em producao sem
        # analise nenhuma. O desfecho fica no ledger da cobertura (PENDENTE abaixo) e no log.
        $__cfSemSubmit = [bool]$script:VixCobFallbackModo
        if (-not $__cfSemSubmit) {
            try { $r = Submit-CapDeferred $routineKey $emp $motivoItem $pendente.tier; $subOk = ($r.ok -eq $true) } catch { $subOk = $false }
        }
        # MVA-BACKLOG1 (2026-09-16): a regra "backlog so fecha com submit confirmado" passa a vir da
        # lib (Test-VixBacklogPodeFechar), nao de um if inline. O valor e o MESMO - prova de aceite e
        # $r.ok, nunca presenca de tentativa - e a regra fica testavel e travada no boot.
        if ($__cfSemSubmit -or (Test-VixBacklogPodeFechar -SubmitConfirmado $subOk)) {
            $stats.deferred++
            if ($motivoItem -eq 'rotacao_semanal') { $stats.deferred_rotacao++ }
            elseif ($motivoItem -eq 'falha_provider') { $stats.deferred_provider++ }
            # COBERTURA-13OUT4: corte por orcamento da rodada de escalada. Contador proprio pela
            # mesma razao das outras causas: e um corte por cap, mas de um emissor que a rodada
            # barata RETeve de proposito, entao nao pode se misturar com a cauda de rotacao.
            elseif ($motivoItem -eq 'escalada_sem_orcamento') { $stats.deferred_escalada++ }
            elseif ($motivoDeferido -ne 'cap_efetivo') { $stats.deferred_auth++ }
        } else { $stats.deferred_fail++ }
        Write-Ledger $emp.empresa $pendente.tier '-' 0 $subOk 'DEFERIDO'
        # COBERTURA-13OUT1: todo deferimento obrigatorio entra na fila persistente, com submit
        # aceito ou nao (sem submit aceito o Worker nem sabe que o emissor ficou de fora). Rotacao
        # semanal nao e pendencia: foi decisao de distribuicao da profundidade.
        if ($motivoItem -ne 'rotacao_semanal') { Add-VixPendenteSeguro $emp.empresa $emp.ews_score $motivoItem $pendente.tier $subOk }
        # COBERTURA-RECON1: DEFERIDO entra no contrato do dia com o motivo. Sem isto o ledger
        # registrava o deferimento e a cobertura nao, e os dois numeros nao fechavam.
        Set-VixContratoEstado -Empresa $emp.empresa -Estado 'DEFERIDO' -Motivo $motivoItem -Faltantes @() -Triado $false
        # COBDIARIA1: deferir a ANALISE nao desfaz a VERIFICACAO do dia (transicao monotona). Quem
        # nao tem prova fica pendente com o motivo do corte.
        if ($script:VixCobDiariaPath) {
            try {
                # COBFALLBACK1: emissor que o Claude NAO fechou fica PENDENTE_IA (pergunta aberta) com
                # classe e motivo; o fechamento o devolve como INSUFICIENCIA. Nunca terminal.
                if ($script:VixCobFallbackModo) { $null = Register-VixCobDiaria -Path $script:VixCobDiariaPath -DateTag $DateTag -Empresa ('' + $emp.empresa) -Estado 'PENDENTE_IA' -Motivo (Get-VixCobFallbackMotivoPendente $motivoItem $script:VixCobFallbackUltimaClasse) -Rotina $Perfil.modo }
                else { $null = Register-VixCobDiaria -Path $script:VixCobDiariaPath -DateTag $DateTag -Empresa ('' + $emp.empresa) -Estado 'PENDENTE' -Motivo ('deferido:' + $motivoItem) -Rotina $Perfil.modo }
            } catch { Write-Log ('COBDIARIA_ERRO: deferido ' + $emp.empresa + ' - ' + $_.Exception.Message) }
        }
        if (-not $DryRun) { Start-Sleep -Milliseconds 400 }
    }
    # ROTACAO-14OUT1: fecha o ciclo com o desfecho REAL da execucao. `Servidos` = quem fechou
    # (analisado ou skip) sai da fila; `Consumidos` = quem foi oferecido como candidato de
    # rotacao e nao fechou (deferido por orcamento) CONTINUA na fila, na frente - o cursor nao
    # passa por ele, que e o que impede starvation. Reinicio de ciclo so com fila zerada.
    # A matinal nao participa: a rotacao diaria dos 104 e da noturna, e o credito de analise do
    # dia ja tira o emissor da fila da noturna pelo plano (CREDITODIA1).
    if ($Perfil.modo -eq 'noturno' -and -not $DryRun) {
        try {
            # Fonte do "fechou": o contrato do dia que acabou de ser montado. ANALISADO /
            # INCONCLUSIVO = analise saiu (com ou sem cobertura); REUTILIZADO = skip;
            # DEFERIDO = nao fechou. Emissor sem registro nenhum tambem nao fechou.
            $__rotServidos = New-Object System.Collections.Generic.List[string]
            foreach ($__kCont in @($contratoCobertura.Keys)) {
                $__eCont = $contratoCobertura[$__kCont]
                $__stCont = ''
                if ($__eCont -is [System.Collections.IDictionary]) { $__stCont = '' + $__eCont['estado'] }
                elseif ($null -ne $__eCont.PSObject.Properties['estado']) { $__stCont = '' + $__eCont.estado }
                if ($__stCont -eq 'ANALISADO' -or $__stCont -eq 'INCONCLUSIVO' -or $__stCont -eq 'REUTILIZADO') { $__rotServidos.Add($__kCont) }
            }
            $__rotPresentes = @($analyzeList | ForEach-Object { '' + $_.empresa })
            # Read-modify-write sob mutex: o ciclo e RELIDO no momento da gravacao, entao um
            # restart/catch-up concorrente nao apaga o avanco do outro.
            $__rotRes = Invoke-VixRotacaoSob -Path $__rotCicloPath -Acao {
                param($__cAtual)
                return (Update-VixRotacaoCiclo -Ciclo $__cAtual -Presentes $__rotPresentes -Servidos $__rotServidos.ToArray() -Consumidos @($__rot.ConsumidosChaves) -Ring @($__rot.Ring) -DiaTag $DateTag)
            }
            $stats.rotacao_perdidos = [int]$__rotRes.Perdidos
            $stats.rotacao_duplicados = [int]$__rotRes.Duplicados
            $stats.rotacao_reiniciou = $(if ($__rotRes.Reiniciou) { 1 } else { 0 })
            $stats.rotacao_na_fila = [int]$__rotRes.NaFila
            $stats.rotacao_servidos_ciclo = [int]$__rotRes.ServidosCiclo
            $stats.rotacao_candidatos_dia = [int]$__rotRes.CandidatosDia
            Write-Log ('ROTACAO_CICLO: ciclo=' + $(if ($__rotRes.Ciclo.ciclo_id) { $__rotRes.Ciclo.ciclo_id } else { 'novo' }) + ' na_fila=' + $__rotRes.NaFila + ' servidos_ciclo=' + $__rotRes.ServidosCiclo + ' posicao=' + $__rotRes.Posicao + ' candidatos_dia=' + $__rotRes.CandidatosDia + '/' + $script:VixRotacaoLimiteDiario + ' reiniciou=' + [int]$__rotRes.Reiniciou + ' perdidos=' + $__rotRes.Perdidos + ' duplicados=' + $__rotRes.Duplicados)
        } catch { Write-Log ('ROTACAO_CICLO_ERRO: ' + $_.Exception.Message) }
    }
    # DEFERIDOZERO1 (2026-09-18): execucao que nao deferiu nada nao tem causa de
    # deferimento, e repetir o valor de partida (cap_efetivo) faz a linha afirmar um
    # corte que nao houve. Medido na matinal de 18/09, execucao ociosa por
    # idempotencia: `deferidos_cap=0 deferidos_auth=0 motivo_deferimento=cap_efetivo`.
    # D1: quando TODOS os deferidos do dia vieram da rotacao semanal, o rotulo do dia e a
    # rotacao, nao o `cap_efetivo` de partida. Sem isto a linha afirmaria um corte por
    # orcamento numa noite que gastou pouco e so distribuiu profundidade.
    # PROFUNDIDADE-NOTURNA1 / D6 (2026-09-19): a definicao veio para ANTES da linha DEFERIDOS.
    # Antes ela era calculada depois, e o texto do corte ainda lia `$motivoDeferido`, o valor de
    # partida: uma noite de rotacao (deferidos_cap=0, deferidos_rotacao>0) escrevia
    # `motivo=cap_efetivo` no log enquanto o metrics e a linha FIM do MESMO dia diziam
    # rotacao_semanal. Agora log, metrics e FIM leem a mesma variavel.
    $motivoDeferimentoEfetivo = if ($stats.deferred -le 0) { 'nenhum' } elseif ($stats.deferred_rotacao -gt 0 -and $stats.deferred_rotacao -ge $stats.deferred) { 'rotacao_semanal' } else { $motivoDeferido }
    if ($pendingDeferred.Count -gt 0) {
        Write-Log (Get-VixDeferidosTexto -Motivo $motivoDeferimentoEfetivo -Ok $stats.deferred -Falha $stats.deferred_fail -Total $pendingDeferred.Count -TokensRealizados $stats.tokens_total -CapEfetivo $TokenHardCap -LotesNaoProcessados $stats.lotes_nao_processados)
        # COBERTURAAUTH1: declaracao + DECISAO registrada. So sai quando o corte nao foi planejado.
        $__declCobertura = Get-VixCoberturaIncompletaTexto -Rotina $Rotina -Motivo $motivoDeferido -Deferidos $stats.deferred -Plano $planoTotal -LotesNaoProcessados $stats.lotes_nao_processados -DetalheAuth $abortoAuthDetalhe
        if ($__declCobertura) { Write-Log $__declCobertura }
    }

    # DEFERIDOZERO1 (18/09) + D1: a definicao de `$motivoDeferimentoEfetivo` subiu para antes da
    # linha DEFERIDOS (D6, 19/09). Aqui ficou so o consumidor do FIM e do metrics.
    # PROFUNDIDADE-NOTURNA1: `deferidos_cap` passa a significar APENAS corte por cap. Antes era
    # `deferred - deferred_auth`, e a rotacao semanal entrava nessa conta sem ser corte de
    # orcamento, inflando o numero que o painel le como "faltou token". O max(0, ...) e
    # defensivo: nenhum contador pode ficar negativo se uma execucao futura incrementar as
    # causas sem incrementar o total. Calculado UMA vez e usado no metrics e na linha FIM, para
    # as duas pontas nao divergirem.
    $deferidosCap = [int][Math]::Max(0, ([int]$stats.deferred - [int]$stats.deferred_auth - [int]$stats.deferred_rotacao - [int]$stats.deferred_provider - [int]$stats.deferred_escalada))
    # COBERTURA-13OUT1: pendencias obrigatorias desta execucao = tudo que foi deferido sem ser
    # rotacao (aceito ou recusado pelo Worker) + recheck de cobertura + submit de analise recusado.
    $pendentesObrigatorios = [int]([Math]::Max(0, ([int]$stats.deferred - [int]$stats.deferred_rotacao)) + [int]$stats.deferred_fail + [int]$stats.cobertura_deferidos + [int]$stats.submit_fail)

    $sw.Stop()
    $submitsAceitos = $stats.skip_ok + $stats.submit_ok + $stats.deferred
    $ledgerResumo = Get-VixResumoLedger $LogFile
    $ledgerTotal = $ledgerResumo.total
    $tokensPublicados = if ($stats.tokens_mensuraveis) { $stats.tokens_total } else { 'NAO_MENSURAVEL' }

    # COBERTURA-RECON1 (2026-10-14): RECONCILIACAO publicacao aceita x cobertura x fila. Os
    # contadores saem do contrato do dia (estado final por emissor + `triado` pegajoso), nunca de
    # um segundo contador paralelo que poderia divergir do arquivo. Divergencia entra em
    # errosTotal e a rotina NAO fecha OK - e o oposto do 14/10, em que 16 analises conviveram com
    # 11 registros de cobertura sem nenhum sinal.
    $__estContrato = @{ TRIADO = 0; ANALISADO = 0; INCONCLUSIVO = 0; REUTILIZADO = 0; DEFERIDO = 0; RESOLVIDO = 0 }
    $__triadosContrato = 0
    $__estadosSuportados = @('TRIADO', 'ANALISADO', 'INCONCLUSIVO', 'REUTILIZADO', 'DEFERIDO', 'RESOLVIDO')
    foreach ($__kRec in @($contratoCobertura.Keys)) {
        $__eRec = $contratoCobertura[$__kRec]
        $__stRec = ''; $__tmRec = $false
        if ($__eRec -is [System.Collections.IDictionary]) {
            $__stRec = '' + $__eRec['estado']
            if ($__eRec.Contains('triado')) { $__tmRec = [bool]$__eRec['triado'] }
        } else {
            if ($null -ne $__eRec.PSObject.Properties['estado']) { $__stRec = '' + $__eRec.estado }
            if ($null -ne $__eRec.PSObject.Properties['triado']) { $__tmRec = [bool]$__eRec.triado }
        }
        if ($__estadosSuportados -contains $__stRec) { $__estContrato[$__stRec]++ }
        if ($__tmRec) { $__triadosContrato++ }
    }
    $stats.contrato_triado = $__triadosContrato
    $stats.contrato_analisado = $__estContrato['ANALISADO']
    $stats.contrato_inconclusivo = $__estContrato['INCONCLUSIVO']
    $stats.contrato_resolvido = $__estContrato['RESOLVIDO']
    $stats.contrato_reutilizado = $__estContrato['REUTILIZADO']
    $stats.contrato_deferido = $__estContrato['DEFERIDO']
    # IDEMEFETIVA1 (2026-10-15): reconciliacao no escopo da EXECUCAO, emissor por emissor (ver
    # Test-VixReconciliacaoExecucao). Os contadores do contrato acima seguem publicados no FIM
    # como estavam (sao o retrato do dia), mas nao decidem mais a divergencia: ledger do dia contra
    # contrato do dia misturava execucoes anteriores e a matinal, e produziu 4 divergencias falsas
    # em 14/10 enquanto nao havia nenhum emissor sem registro.
    $__triPorChave = @{}
    foreach ($__kTr in @($contratoCobertura.Keys)) {
        $__eTr = $contratoCobertura[$__kTr]; $__tTr = $false
        if ($__eTr -is [System.Collections.IDictionary]) { if ($__eTr.Contains('triado')) { $__tTr = [bool]$__eTr['triado'] } }
        elseif ($null -ne $__eTr.PSObject.Properties['triado']) { $__tTr = [bool]$__eTr.triado }
        $__triPorChave[$__kTr] = $__tTr
    }
    $__elegChaves = @($plano.emissores | ForEach-Object { Get-NomeNormalizado ('' + $_.empresa) } | Where-Object { -not $jaProcessados.ContainsKey($_) })
    $__recon = Test-VixReconciliacaoExecucao -LedgerExec $script:VixLedgerExec -ContratoExec $script:VixContratoExec -TriadoPorChave $__triPorChave -Elegiveis $__elegChaves `
        -RotacaoPerdidos ([int]$stats.rotacao_perdidos) -ExigirTriagem ([bool]($script:VixTriagemAtiva -or $script:VixTriagemSombra))
    # Conta do DIA contra o universo do plano: cada emissor em exatamente uma classe, soma = plano.
    $__reconDia = $null
    if (-not $DryRun -and -not $script:VixCobFallbackModo) {
        try {
            $__reconDia = Get-VixReconciliacaoUniverso -Universo @($plano.emissores | ForEach-Object { '' + $_.empresa }) -Linhas @(Get-VixLogDiaLinhas $LogFile | Where-Object { $_ -match '^[\d-]+ [\d:]+ OK\|' })
            Write-Log ('RECONCILIACAO_DIA: universo=' + $__reconDia.Universo + ' entregues=' + $__reconDia.Entregues + ' deferidos=' + $__reconDia.Deferidos + ' submit_falho=' + $__reconDia.SubmitFalho + ' sem_registro=' + $__reconDia.SemRegistro + ' soma=' + $__reconDia.Soma + ' fecha=' + [int]$__reconDia.Fecha + ' completo=' + [int]$__reconDia.Completo + ' fora_do_universo=' + $__reconDia.ForaDoUniverso + $(if ($__reconDia.SemRegistro -gt 0) { ' sem_registro_nomes=' + ((@($__reconDia.SemRegistroNomes) | Select-Object -First 10) -join ',') } else { '' }))
        } catch { Write-Log ('RECONCILIACAO_DIA_ERRO: ' + $_.Exception.Message) }
    }
    # IDEMEFETIVA1: denominador do resultado = elegiveis desta execucao (plano menos entregues hoje).
    # Tudo entregue antes = nada a fazer, nao FALHA; elegivel sem entrega nenhuma = FALHA, como antes.
    $__planoResultado = $planoTotal
    if (-not $script:VixCobFallbackModo -and $script:VixElegiveisExec -ge 0) { $__planoResultado = [int]$script:VixElegiveisExec }
    # COBFALLBACK1: o ledger do fallback cobre so os alvos dele, e o contrato do dia (carregado
    # inteiro para nao apagar o que a noturna gravou) cobre o universo. Os dois nao reconciliam por
    # construcao; a reconciliacao do dia e da noturna. O fallback registra o proprio desfecho no
    # ledger da cobertura diaria e no registro de gasto.
    if ($script:VixCobFallbackModo) {
        $stats.cobertura_reconciliacao = 'nao_aplicavel_cobfallback'
        Write-Log 'COBERTURA_RECONCILIACAO: nao aplicavel ao modo cobfallback (ledger parcial por desenho)'
    } elseif ($__recon.ok) {
        $stats.cobertura_reconciliacao = 'ok'
        Write-Log ('COBERTURA_RECONCILIACAO: OK execucao(ledger analisados=' + $__recon.analisados + ' skip=' + $__recon.skips + ' deferidos=' + $__recon.deferidos + ', todos com contrato da execucao, triados=' + $__recon.triados + '/' + $__recon.elegiveis + ' elegiveis) dia(ledger analisados=' + $ledgerResumo.analisados + ' skip=' + $ledgerResumo.skips + ' deferidos=' + $ledgerResumo.deferidos + ')')
    } else {
        $stats.cobertura_reconciliacao = 'divergente'
        $stats.cobertura_divergencias = @($__recon.divergencias).Count
        Write-Log ('COBERTURA_RECONCILIACAO: DIVERGENTE - ' + (@($__recon.divergencias) -join ' | ') + ' (publicacao aceita, ledger, cobertura e fila tem de fechar; divergencia nao vira OK)')
    }

    # Dreno da fila de verificacao logo apos a varredura (v4.9.150): evento CRITICO nao fica
    # preso ate o proximo dreno agendado. Nunca em dry-run.
    # DRENOMUDO1-FIX (2026-09-15): este bloco passou para ANTES do contrato do dia (metrics e
    # linha FIM). Motivo medido: o desfecho do dreno existia SO como linha de log. Em 14/09 o log
    # dizia `POS-NOTURNO: dreno FALHOU (exit=5)` + `ERRO DRENO: ...` e o metrics do dia, escrito
    # antes de o dreno rodar, dizia dreno_exit=null (idem matinal do mesmo dia) - quem le o
    # contrato do dia nao via fila nao drenada nenhuma. E o motor nao levantava alerta proprio: o
    # e-mail de 14/09 veio da rotina de verificacao, o que so acontece quando a causa e credencial.
    # COBFALLBACK1: o override de provider e do PROCESSO e seria herdado pelo dreno (filho), que
    # passaria a verificar pelo Claude. Restaura o valor de antes do override: o dreno roda com o
    # provider configurado pelo operador, como em qualquer outra rotina.
    if ($script:VixCobFallbackModo) { [Environment]::SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', $script:VixCobFallbackProviderOriginal, 'Process') }
    if ($stats.submit_ok -gt 0 -and -not $DryRun) {
        $verifScript = Join-Path $ScriptsDir 'run_vixradar_verificacao_async.ps1'
        if (Test-Path $verifScript) {
            # DRENOMUDO1-FIX2 (2026-09-16): subir o filho, LER o exit code e escrever o desfecho
            # saiu daqui para Invoke-VixDrenoPosRotina, funcao testavel provada offline por
            # test-varredura-defeitos.ps1 (D6) e exigida por test-monitor-drenofalha.ps1. O
            # comportamento e o mesmo: exit code AVALIADO (nunca citado como sucesso) e -1 quando
            # o processo nem sobe.
            $stats.dreno_exit = Invoke-VixDrenoPosRotina -ScriptPath $verifScript -Rotina $Rotina
            # DRENOMUDO1-FIX: alerta pelo PROPRIO desfecho. Antes o unico alerta possivel era o da
            # rotina de verificacao (ALERTA_AUTH dela), que so existe quando a causa e credencial;
            # dreno que morre por crash (exit 1) ou que nem sobe (-1) nao alertava ninguem.
            $__alertaDreno = Get-VixDrenoAlerta $stats.dreno_exit
            if ($__alertaDreno) {
                Write-Log $__alertaDreno
                try { $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo $__alertaDreno -RoutineKey $routineKey -Causa ('dreno_exit' + $stats.dreno_exit) -Severidade 'critico' } catch { Write-Log ('AVISO: alerta de dreno nao enviado - ' + $_.Exception.Message) }
            }
        }
    }

    # FIMFALSO1 (2026-09-12): analisados>0 com buscas=0 significa que nenhum lote
    # devolveu RESULTADO real; cada emissor recebeu stub fabricado e o ledger marcou
    # ANALISADO sem analise (contador de sucesso saiu da tentativa, nao do efeito).
    # Medido 11/09 e 12/09: FIM "concluido 104/104" com tokens=0 e buscas=0, provider
    # 402/credencial ausente em todos os lotes e o motor fechou como se tivesse varrido.
    # Regra: marca FIM_INVALIDO, forca exit 9 (disparou, nao processou nenhum lote com
    # analise real) e nao sobrescreve metrics de uma execucao real do mesmo dia.
    $trabalhoZero = $false
    if (-not $DryRun -and $stats.analisados -gt 0 -and $stats.buscas_total -eq 0) {
        $trabalhoZero = $true
        Write-Log ('FIMFALSO1: analisados=' + $stats.analisados + ' com buscas=0 e lotes_com_trabalho=' + $stats.lotes_com_trabalho + ' - trabalho/busca ausente, independente de medicao_tokens=' + $tokensPublicados + '. FIM marcado INVALIDO.')
    }
    # METRICSZERO1: reinicio idempotente nao sobrescreve metrics de execucao real com zeros.
    $gravarMetrics = $true
    if (-not $DryRun -and $stats.analisados -eq 0 -and $stats.skip_ok -eq 0 -and (Test-Path $MetricsFile)) {
        try {
            $existente = Get-Content $MetricsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existente.analisados -gt 0 -or $existente.submit_ok -gt 0) { Write-Log 'METRICSZERO1: metrics preservado (execucao atual zerada por idempotencia)'; $gravarMetrics = $false }
        } catch {}
    }
    # FIMFALSO1: execucao com trabalho zero nao sobrescreve metrics de execucao real do
    # mesmo dia (a chave do arquivo e por data, nao por execucao - proveniencia).
    if ($gravarMetrics -and $trabalhoZero -and (Test-Path $MetricsFile)) {
        try {
            $existente = Get-Content $MetricsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existente.buscas_total -gt 0 -or $existente.tokens_total_est -gt 0) {
                Write-Log 'FIMFALSO1: metrics preservado (execucao atual com trabalho zero nao sobrescreve execucao real do dia)'
                $gravarMetrics = $false
            }
        } catch {}
    }
    if ($gravarMetrics) {
        [ordered]@{
            data = $DateTag; rotina = $Rotina; dryrun = [bool]$DryRun; motor = 'task-scheduler'
            token_target = $TokenTarget; token_hard_cap = $TokenHardCap; cap_proprio = $Perfil.capProprio; circuito_aberto = [bool]$custoDia.circuito_aberto
            tokens_mensuraveis = [bool]$stats.tokens_mensuraveis
            tokens_total_est = $tokensPublicados; tokens_trabalho = $tokensPublicados
            tokens_input = $(if ($stats.tokens_mensuraveis) { $stats.input } else { 'NAO_MENSURAVEL' }); tokens_output = $(if ($stats.tokens_mensuraveis) { $stats.output } else { 'NAO_MENSURAVEL' }); tokens_cache_creation = $(if ($stats.tokens_mensuraveis) { $stats.cache_creation } else { 'NAO_MENSURAVEL' }); tokens_cache_read = $(if ($stats.tokens_mensuraveis) { $stats.cache_read } else { 'NAO_MENSURAVEL' })
            # CACHECODEX-VISIVEL1: o cache do Codex ganha campo proprio no metrics (antes so existia
            # na linha FIM e a lib de custo nao o via).
            tokens_cache_codex = $(if ($stats.tokens_mensuraveis) { $stats.cache_codex } else { 'NAO_MENSURAVEL' })
            tokens_over_target = $stats.tokens_over_target; tokens_hard_hit = $stats.tokens_hard_hit
            analisados = $stats.analisados; skip_ok = $stats.skip_ok; deferred = $stats.deferred; submits_aceitos = $submitsAceitos
            submit_ok = $stats.submit_ok; submit_fail = $stats.submit_fail; buscas_total = $stats.buscas_total; silent_fail = $stats.silent_fail
            degradados_402 = $stats.degradados_402
            # DRYRUN-CRASH1: @(List[object]) com [ordered] dentro estoura o binder do 5.1
            # ("Os tipos de argumento nao correspondem"), reproduzido isolado em 02/09. ToArray() nao.
            lotes = $stats.batches_run; batches = $stats.batches_run; lotes_com_trabalho = $stats.lotes_com_trabalho; lotes_detalhe = $lotesDetalhe.ToArray()
            criticos = $stats.criticos.ToArray(); duracao_sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            auth_modo_inicial = $authModoInicial; auth_escalou = $stats.auth_escalou
            # COBERTURAAUTH1 (2026-09-15): o contrato do dia passa a dizer POR QUE os deferidos
            # sairam de fora. `deferidos_cap` = cauda planejada pelo cap de tokens;
            # `deferidos_auth` = emissores que o limite de sessao da assinatura deixou sem lote;
            # `lotes_nao_processados` = lotes que o aborto deixou sem chamada (nada silencioso).
            deferidos_cap = $deferidosCap
            deferidos_auth = $stats.deferred_auth
            # D1: terceira causa de deferimento, separada das outras duas. As tres se somam ao
            # total de deferidos, e `deferidos_cap` exclui explicitamente auth e rotacao.
            deferidos_rotacao = $stats.deferred_rotacao
            motivo_deferimento = $motivoDeferimentoEfetivo
            lotes_nao_processados = $stats.lotes_nao_processados
            # DRENOMUDO1-FIX: desfecho do dreno pos-rotina. $null quando nao houve dreno (sem
            # submit ou dry-run), 0 quando drenou, outro valor quando falhou.
            dreno_exit = $stats.dreno_exit
            # COBERTURA-13OUT1: provedor (calibra a regua de custo por emissor so com a mesma
            # configuracao), pendencias obrigatorias e os contadores de consumo novos.
            provider = $__providerExec
            pendentes_obrigatorios = $pendentesObrigatorios
            cobertura = (Get-VixResultadoRotina -DryRun ([bool]$DryRun) -TrabalhoZero $trabalhoZero -PlanoTotal $__planoResultado -Analisados $stats.analisados -Skips $stats.skip_ok -PendentesObrigatorios $pendentesObrigatorios -Erros ($stats.silent_fail + $stats.skip_fail + $stats.batch_fail + $stats.submit_fail + $stats.deferred_fail + $stats.descartes_inesperados + $stats.cobertura_divergencias)).Resultado
            deferidos_provider = $stats.deferred_provider
            deferidos_escalada = $stats.deferred_escalada
            tokens_estimados_falha = $stats.tokens_estimados_falha
            codex_cached_input = $stats.codex_cached
            cap_excedido = $stats.cap_excedido
            triagem_quieto = $stats.triagem_quieto
            triagem_material = $stats.triagem_material
            triagem_indisponivel = $stats.triagem_indisponivel
            # COBERTURA-RECON1: contrato x ledger (estado por emissor) e a reconciliacao do dia.
            contrato_triado = $stats.contrato_triado
            contrato_analisado = $stats.contrato_analisado
            contrato_inconclusivo = $stats.contrato_inconclusivo
            contrato_resolvido = $stats.contrato_resolvido
            contrato_reutilizado = $stats.contrato_reutilizado
            contrato_deferido = $stats.contrato_deferido
            cobertura_reconciliacao = $stats.cobertura_reconciliacao
            cobertura_divergencias = $stats.cobertura_divergencias
            # ROTACAO-14OUT1: auditoria da fila justa dos 104.
            rotacao_aplicada = $stats.rotacao_aplicada
            rotacao_prioritarios = $stats.rotacao_prioritarios
            rotacao_candidatos = $stats.rotacao_candidatos
            rotacao_adiados_cota = $stats.rotacao_adiados_cota
            rotacao_limite_dia = $stats.rotacao_limite_dia
            rotacao_candidatos_dia = $stats.rotacao_candidatos_dia
            rotacao_na_fila = $stats.rotacao_na_fila
            rotacao_servidos_ciclo = $stats.rotacao_servidos_ciclo
            rotacao_reiniciou = $stats.rotacao_reiniciou
            rotacao_perdidos = $stats.rotacao_perdidos
            rotacao_duplicados = $stats.rotacao_duplicados
            escalada_ativa = [bool]$script:VixEscaladaAtiva
            escalada_retidos = $stats.escalada_retidos
            escalada_pendentes = $stats.escalada_pendentes
            escalada_lotes = $__escaladaLotes
            escalada_analisados = $stats.escalada_analisados
            escalada_sem_orcamento = $stats.escalada_sem_orcamento
            escalada_custo_base_emissor = [int64][Math]::Ceiling($__custoEscalada)
            disjuntor_provider = $(if ($__disjuntor.aberto) { $__disjuntor.motivo } else { 'fechado' })
        } | ConvertTo-Json -Depth 6 | Set-Content $MetricsFile -Encoding UTF8
    }

    # COBERTURA1: persiste o contrato do dia (RECHECK_PENDENTE p/ reprocessar primeiro,
    # RESOLVIDO p/ tirar da frente). O arquivo do dia e sempre o registro mais novo da leitura.
    if ($contratoCobertura.Count -gt 0 -and -not $DryRun) {
        [ordered]@{ data = $DateTag; atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); emissores = $contratoCobertura } |
            ConvertTo-Json -Depth 6 | Set-Content (Get-VixContratoCoberturaPath $DateTag) -Encoding UTF8
        Write-Log ('COBERTURA1: contrato persistido com ' + $contratoCobertura.Count + ' emissor(es) por cobertura (recheck_pendente=' + $stats.cobertura_deferidos + ' resolvidos=' + $stats.recheck_resolvidos + ')')
    }

    # COBERTURA-13OUT1: o resultado sai ANTES da linha FIM para ela nao declarar "concluido"
    # sem qualificar. Mesma conta repetida abaixo para o ROTINA_RESUMO (os valores nao mudam).
    $__errosPre = $stats.silent_fail + $stats.skip_fail + $stats.batch_fail + $stats.submit_fail + $stats.deferred_fail + $stats.descartes_inesperados + $stats.cobertura_divergencias
    $__resPre = Get-VixResultadoRotina -DryRun ([bool]$DryRun) -TrabalhoZero $trabalhoZero -PlanoTotal $__planoResultado -Analisados $stats.analisados -Skips $stats.skip_ok -PendentesObrigatorios $pendentesObrigatorios -Erros $__errosPre
    $fimTag = if ($DryRun) { 'FIM_DRYRUN: ' } elseif ($trabalhoZero) { 'FIM_INVALIDO: ' } else { 'FIM: ' }
    $fimVerbo = if ($trabalhoZero) { 'INVALIDO (trabalho zero)' } elseif ($__resPre.Resultado -eq 'OK' -or $__resPre.Resultado -eq 'DRYRUN') { 'concluido' } else { 'concluido ' + $__resPre.Resultado + ' (' + $__resPre.Motivo + ')' }
    # FEEDRETRO1 FASE2 (2026-09-04): eventos_avanco_data pode ser 0 legitimamente num dia
    # quieto - nao e criterio de falha. Mede avanco TEMPORAL, nunca prova ausencia de
    # outro fato legitimo na mesma data maxima (ver n_chaves_novas ao lado).
    Write-Log ($fimTag + $Rotina + ' ' + $fimVerbo + '. Total do dia ' + $ledgerTotal + '/' + $planoTotal + ' (ledger analisados=' + $ledgerResumo.analisados + ' skip=' + $ledgerResumo.skips + ' deferidos=' + $ledgerResumo.deferidos + '). analisados_execucao=' + $stats.analisados + ' skip_execucao=' + $stats.skip_ok + ' deferidos_execucao=' + $stats.deferred + ' submits_aceitos=' + $submitsAceitos +
        ' submit_ok=' + $stats.submit_ok + ' submit_fail=' + $stats.submit_fail + ' tokens=' + $tokensPublicados + ' cache_read=' + $(if ($stats.tokens_mensuraveis) { $stats.cache_read } else { 'NAO_MENSURAVEL' }) + ' cap_efetivo=' + $TokenHardCap + ' lotes=' + $stats.batches_run + ' lotes_com_trabalho=' + $stats.lotes_com_trabalho +
        ' buscas=' + $stats.buscas_total + ' silent_fail=' + $stats.silent_fail + ' degradados_402=' + $stats.degradados_402 + ' criticos=' + $stats.criticos.Count + ' auth_escalou=' + $stats.auth_escalou +
        ' eventos_avanco_data=' + $stats.eventos_avanco_data + ' chaves_novas=' + $stats.chaves_novas + ' descartados=' + $stats.descartados +
        # COBERTURAAUTH1 / DRENOMUDO1-FIX (2026-09-15): campos NOVOS vao no fim, depois dos
        # historicos. Toda leitura existente deste resumo e por regex de campo, entao acrescentar
        # no fim nao muda leitor nenhum; inserir no meio mudaria quem le posicionalmente.
        ' deferidos_cap=' + $deferidosCap +
        ' deferidos_auth=' + $stats.deferred_auth +
        ' deferidos_rotacao=' + $stats.deferred_rotacao +
        ' motivo_deferimento=' + $motivoDeferimentoEfetivo +
        ' lotes_nao_processados=' + $stats.lotes_nao_processados +
        $(if ($null -eq $stats.dreno_exit) { '' } else { ' dreno_exit=' + $stats.dreno_exit }) +
        ' duracao_sec=' + [Math]::Round($sw.Elapsed.TotalSeconds, 1) +
        # COBERTURA-13OUT1: campos novos no fim (leitores sao por regex de campo).
        ' resultado=' + $__resPre.Resultado + ' pendentes_obrigatorios=' + $pendentesObrigatorios +
        ' deferidos_provider=' + $stats.deferred_provider + ' tokens_estimados_falha=' + $stats.tokens_estimados_falha +
        ' codex_cached_input=' + $stats.codex_cached + ' cap_excedido=' + $stats.cap_excedido + ' provider=' + $__providerExec +
        ' triagem_quieto=' + $stats.triagem_quieto + ' triagem_material=' + $stats.triagem_material + ' triagem_indisponivel=' + $stats.triagem_indisponivel +
        # COBERTURA-13OUT4: escalada seletiva (campos novos no fim, mesma regra dos anteriores).
        ' escalada_retidos=' + $stats.escalada_retidos + ' escalada_pendentes=' + $stats.escalada_pendentes +
        ' escalada_lotes=' + $__escaladaLotes + ' escalada_analisados=' + $stats.escalada_analisados +
        ' escalada_sem_orcamento=' + $stats.escalada_sem_orcamento + ' deferidos_escalada=' + $stats.deferred_escalada +
        # COBERTURA-RECON1 / ROTACAO-14OUT1: campos novos no fim (mesma regra dos anteriores -
        # leitores deste resumo sao por regex de campo).
        ' contrato_triado=' + $stats.contrato_triado + ' contrato_analisado=' + $stats.contrato_analisado +
        ' contrato_inconclusivo=' + $stats.contrato_inconclusivo + ' contrato_resolvido=' + $stats.contrato_resolvido + ' contrato_reutilizado=' + $stats.contrato_reutilizado +
        ' contrato_deferido=' + $stats.contrato_deferido + ' cobertura_reconciliacao=' + $stats.cobertura_reconciliacao +
        ' cobertura_divergencias=' + $stats.cobertura_divergencias +
        ' rotacao_aplicada=' + $stats.rotacao_aplicada + ' rotacao_prioritarios=' + $stats.rotacao_prioritarios +
        ' rotacao_candidatos=' + $stats.rotacao_candidatos + ' rotacao_adiados_cota=' + $stats.rotacao_adiados_cota +
        ' rotacao_limite_dia=' + $stats.rotacao_limite_dia + ' rotacao_candidatos_dia=' + $stats.rotacao_candidatos_dia +
        ' rotacao_na_fila=' + $stats.rotacao_na_fila + ' rotacao_servidos_ciclo=' + $stats.rotacao_servidos_ciclo +
        ' rotacao_reiniciou=' + $stats.rotacao_reiniciou + ' rotacao_perdidos=' + $stats.rotacao_perdidos + ' rotacao_duplicados=' + $stats.rotacao_duplicados +
        ' disjuntor_provider=' + $(if ($__disjuntor.aberto) { 'ABERTO:' + $__disjuntor.motivo } else { 'fechado' }) +
        # IDEMEFETIVA1: "Total do dia N/D" e contagem de REGISTRO (soma DEFERIDO, e o que o
        # check-ledger-noturno.ps1 confere). A entrega de verdade do dia sai aqui, pela regra unica.
        $(if ($null -ne $__reconDia) { ' entregues_dia=' + $__reconDia.Entregues + '/' + $__reconDia.Universo + ' nao_entregues_dia=' + ($__reconDia.Universo - $__reconDia.Entregues) + ' reconciliacao_dia=' + $(if ($__reconDia.Fecha) { 'fecha' } else { 'nao_fecha' }) } else { '' }) +
        ' elegiveis_execucao=' + $__planoResultado + ' reabertos_idempotencia=' + $script:VixIdemReabertos)

    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $errosTotal = $stats.silent_fail + $stats.skip_fail + $stats.batch_fail + $stats.submit_fail + $stats.deferred_fail + $stats.descartes_inesperados + $stats.cobertura_divergencias
    # SEM-ANALISE-EFETIVA1 (2026-10-06): nenhuma rotina declara OK quando a
    # analise efetiva nao ocorreu. ANALISADO e SKIP contam como efetivos;
    # DEFERIDO e FALHA nao. Se o plano tinha trabalho (planoTotal>0) e nada
    # foi efetivamente analisado, o resultado e no maximo PARCIAL, mesmo com
    # errosTotal=0 (ex.: todos DEFERIDOS com submit aceito e sem batch_fail).
    $semAnaliseEfetiva = (-not $DryRun) -and ($stats.analisados -eq 0) -and ($stats.skip_ok -eq 0) -and ($__planoResultado -gt 0)
    # COBERTURA-13OUT1: regra unica (lib) para OK/PARCIAL/FALHA. Em 13/10 a matinal fechou
    # ROTINA_RESUMO "OK" com 17 de 21 emissores DEFERIDO por cap. Pendencia obrigatoria agora
    # impede OK; nenhuma analise efetiva com plano nao vazio e FALHA (antes saia PARCIAL).
    $__resRot = Get-VixResultadoRotina -DryRun ([bool]$DryRun) -TrabalhoZero $trabalhoZero -PlanoTotal $__planoResultado -Analisados $stats.analisados -Skips $stats.skip_ok -PendentesObrigatorios $pendentesObrigatorios -Erros $errosTotal
    $resultadoTxt = $__resRot.Resultado
    Write-Log ('COBERTURA_RESULTADO: ' + $resultadoTxt + ' motivo=' + $__resRot.Motivo + ' pendentes_obrigatorios=' + $pendentesObrigatorios + ' (deferidos_nao_rotacao=' + ([int]$stats.deferred - [int]$stats.deferred_rotacao) + ' deferidos_submit_falho=' + $stats.deferred_fail + ' recheck=' + $stats.cobertura_deferidos + ' submit_fail=' + $stats.submit_fail + ') analisados=' + $stats.analisados + ' skip=' + $stats.skip_ok + ' plano=' + $planoTotal)
    # COBDIARIA1: a noturna e a ultima varredura do dia e dona do universo, entao e ela que fecha o
    # dia da cobertura. O resultado da rotina (exit, OK/PARCIAL) NAO muda por isto: o fechamento
    # tem relatorio, incidente e alerta proprios. Sombra: relatorio PARCIAL/OK local, sem alerta.
    # Matinal: so inspecao. Capacidade medida (envelope da classe + saldo do circuito do dia).
    # COBFALLBACK1: o fallback nao reescreve o relatorio de fechamento do dia (ele e da noturna e
    # carrega o status de incidente). Resumo proprio, lido do ledger da cobertura agora.
    if ($script:VixCobFallbackModo) {
        try {
            $__cfL = Read-VixCobDiaria (Get-VixCobDiariaPath $LogDir $DateTag) $DateTag
            $__cfFechados = 0; $__cfAbertos = New-Object System.Collections.Generic.List[string]
            foreach ($__cfA in @($script:VixCobFallbackAlvos)) {
                $__cfK = ConvertTo-VixChaveEmissor ('' + $__cfA.empresa)
                $__cfEst = ''
                if ($__cfL.emissores.ContainsKey($__cfK)) { $__cfEst = '' + (Get-VixCobDiariaCampo $__cfL.emissores[$__cfK] 'estado') }
                if ($script:VixCobDiariaTerminais -contains $__cfEst) { $__cfFechados++ } else { $__cfAbertos.Add(('' + $__cfA.empresa) + ':' + $__cfEst) }
            }
            Write-Log ('COBFALLBACK_RESUMO: alvos=' + @($script:VixCobFallbackAlvos).Count + ' fechados=' + $__cfFechados + ' abertos=' + $__cfAbertos.Count + ' tokens=' + $tokensPublicados + ' cap=' + $TokenHardCap + $(if ($__cfAbertos.Count -gt 0) { ' pendentes=' + ($__cfAbertos.ToArray() -join ',') } else { '' }))
        } catch { Write-Log ('COBFALLBACK_ERRO: resumo - ' + $_.Exception.Message) }
    } elseif ($script:VixCobDiariaPath) {
        try {
            $__cdProv = '' + (Get-VixLlmProvider)
            $__cdMB = Get-VixModeloLoteClasse -Amostras @(Get-VixHistoricoCustoClasse $LogDir $__cdProv 'BARATO') -DefaultEmissor 0
            $__cdMF = Get-VixModeloLoteClasse -Amostras @(@(Get-VixHistoricoCustoClasse $LogDir $__cdProv 'FULL') + @(Get-VixHistoricoCustoClasse $LogDir $__cdProv 'ESCALADA')) -DefaultEmissor 0
            $__cdCusto = Get-VixCustoDia $LogDir $DateTag $custoCfg
            $__cdCfg = Get-VixCobDiariaConfig $LogDir
            $__cdFlagCl = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_FALLBACK_CLAUDE', 'Process')
            if (-not $__cdFlagCl) { $__cdFlagCl = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_FALLBACK_CLAUDE', 'User') }
            # COBFALLBACK1: orcamento Claude = SALDO do dia (teto menos o que o executor ja gastou,
            # zero se o gasto for nao mensuravel/ilegivel), nao o teto cheio.
            $__cdG = Read-VixCobFallbackGasto (Get-VixCobFallbackGastoPath $LogDir $DateTag) $DateTag
            $__cdRg = Get-VixCobFallbackResumoGasto $__cdG
            $__cdOrcCl = Get-VixCobFallbackSaldo -Teto ([int64]$__cdCfg.CLAUDE_FALLBACK_DIA) -Gasto ([int64]$__cdRg.Gasto) -Mensuravel ([bool]$__cdRg.Mensuravel)
            $__cdCap = @{
                PrimarioDisponivel = ((-not $__disjuntor.aberto) -and (-not $__cdCusto.circuito_aberto))
                OrcamentoPrimario = [int64](Get-VixCapEfetivo ([int64]$custoCfg.TETO_DIA) $__cdCusto $custoCfg ([int64]$custoCfg.RESERVA_VERIFICACAO))
                CustoBarato = [int64](Get-VixEstimativaLoteClasse -Modelo $__cdMB -Emissores 1); CustoFull = [int64](Get-VixEstimativaLoteClasse -Modelo $__cdMF -Emissores 1)
                ClaudeHabilitado = ((('' + $__cdFlagCl).Trim() -eq '1') -and [int64]$__cdCfg.CLAUDE_FALLBACK_DIA -gt 0); ClaudeLimiteAtingido = [bool](Get-VixCobFallbackLimiteAtingido $__cdG); OrcamentoClaude = [int64]$__cdOrcCl
            }
            $__cdAlerta = $null
            if ($script:VixCobDiariaAtivo -and ($null -ne (Get-Command 'Send-VixRoutineAlert' -ErrorAction SilentlyContinue))) {
                $__cdAlerta = { param($t) Send-VixRoutineAlert -Rotina 'vixradar-cobertura-diaria' -Motivo $t -RoutineKey $routineKey -Causa 'cobertura' -Severidade 'critico' }
            }
            $__cdFech = Invoke-VixCobDiariaFechamento -LogDir $LogDir -DateTag $DateTag -Fechamento:($script:VixCobDiariaAtivo -and $Perfil.modo -eq 'noturno') -AlertaAcao $__cdAlerta -Rotina $Perfil.id -Capacidade $__cdCap
            Write-Log $__cdFech.Linha
            Write-Log ('COBDIARIA_CAPACIDADE: provider=' + $__cdProv + ' barato=' + $__cdCap.CustoBarato + ' full=' + $__cdCap.CustoFull + ' saldo_dia=' + $__cdCap.OrcamentoPrimario + ' claude_fallback=' + [int]$__cdCap.ClaudeHabilitado + ' relatorio=' + $__cdFech.RelatorioPath)
        } catch { Write-Log ('COBDIARIA_ERRO: fechamento - ' + $_.Exception.Message) }
    }
    Write-Log ('ROTINA_RESUMO|' + $Perfil.id + '|local|' + $inicioIso + '|' + $fimIso + '|' + $resultadoTxt + '|' + $stats.submit_ok + '|' + $errosTotal + '|' + $stats.deferred + '|' + $versaoWorker)

    # DRENOMUDO1-FIX: o dreno roda ANTES deste ponto agora (ver bloco acima). Aqui o desfecho ja
    # esta em $stats.dreno_exit e entra no metrics do dia pelo arquivo, inclusive no caso em que o
    # metrics foi PRESERVADO (METRICSZERO1/FIMFALSO1): nesse caminho o arquivo do dia nao e
    # reescrito, e o desfecho do dreno desta execucao se perderia.
    if (-not $DryRun) { $null = Set-VixMetricsDrenoExit -MetricsPath $MetricsFile -ExitCode $stats.dreno_exit }

    if ($trabalhoZero) { $exitCode = 9 }
    if ($semAnaliseEfetiva -and ($exitCode -eq 0)) { $exitCode = 6 }
    if (-not $DryRun -and ($stats.silent_fail -gt 0 -or $stats.skip_fail -gt 0 -or $stats.batch_fail -gt 0)) { if ($exitCode -eq 0) { $exitCode = 6 } }
    # COBERTURA-13OUT1: PARCIAL por pendencia obrigatoria sai nao-zero (10, mesma convencao da
    # sentinela), para o Scheduler e o monitor nao lerem cobertura incompleta como sucesso.
    # O retry agendado julga pelo ledger da janela, nao pelo exit, entao isto nao relanca nada.
    if (-not $DryRun -and $exitCode -eq 0 -and $__resRot.Exit -ne 0) { $exitCode = [int]$__resRot.Exit }
} catch {
    $errMsg = 'ERRO FATAL: excecao nao tratada no bloco principal - ' + $_.Exception.Message
    # DRYRUN-CRASH1: o StackTrace do .NET nao diz a linha do script. ScriptStackTrace e PositionMessage dizem.
    $stackMsg = 'STACK: ' + ('' + $_.ScriptStackTrace) + ' | POS: ' + (('' + $_.InvocationInfo.PositionMessage) -replace '\r?\n', ' ') + ' | NET: ' + $_.Exception.StackTrace
    Write-Safe $errMsg; Write-Safe $stackMsg
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $errMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $stackMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    $exitCode = 1
} finally {
    Remove-BatchPrompts $DateTag
    Invoke-Cleanup -Aggressive
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    try { $__mutex.ReleaseMutex() } catch { }
    Pop-Location
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
}

if ($exitCode -ne 0) { exit $exitCode }
exit 0
