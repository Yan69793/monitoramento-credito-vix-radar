# run_vixradar_verificacao_async.ps1 - Dreno da fila de verificacao assincrona (radar:verif_fila:{data})
# Roda via Claude Code (assinatura mensal) em vez do Worker chamar a API Anthropic paga por token.
# NOTA (2026-07-13): v4.9.152 — migrado de pay-per-token para assinatura Claude Code.
# ANTHROPIC_API_KEY e removida do ambiente em Invoke-ClaudeBatch; claude -p usa OAuth.
# Motivo: saldo pre-pago esgotou 3x em 10 dias (03/07, 04/07, 10/07), interrompendo cobertura.
# Get-AnthropicApiKey e demais guards permanecem no codigo para eventual retorno a pay-per-token.
# Programado para rodar pouco depois de cada varredura. Desde a inversao de 25/08/2026:
# 11h00 (depois da varredura completa, que hoje roda as 10h sob o nome vixradar-noturno) e
# 18h45 (depois da passada do top 15, que hoje roda as 18h sob o nome vixradar-matinal).
# A sessao das 18h45 nao e opcional: sem ela a fila enfileirada as 18h fica presa ate o dia
# seguinte. Os nomes das rotinas estao invertidos em relacao aos horarios de proposito, ver
# routines/README.md.
# MOTOR1 (2026-09-02): reserva atomica antes de verificar (CONCORVERIF1, origem "local"),
# claimante padrao, 4 parcelas de usage na regua unica, ALERTA_AUTH na escalada e -DryRun
# (lista e reserva com origem "local-dryrun", nunca confirma). Drenos: local 11h03 e 19h15,
# remoto 02h07 (RemoteTrigger), mais o dreno inline no fim de cada varredura.
param([switch]$DryRun, [switch]$ForceClaude, [string]$ReplayFilaPath = '', [string]$ReplayOutPath = '', [ValidateRange(1, 4)][int]$MaxEventos = 1)
# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script
# aborta antes do 'exit' e o Task Scheduler/Claude Desktop perde o codigo de saida.
$ErrorActionPreference = 'Continue'
# Encoding UTF-8 na captura do stdout do 'claude' (higiene, alinhado ao noturno/matinal).
# NOTA: a falha de parse dos veredictos (2026-07-05) NAO era encoding - era o extrator ingenuo
# com LastIndexOf(']') casando com ']' de links markdown que o modelo anexa depois do JSON.
# Corrigido em Get-VeredictosArray/Get-BalancedJson (varredura balanceada).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$WorkerUrl      = 'https://api.vixradar.com'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
if ($ReplayFilaPath) {
    if (-not $ReplayOutPath) { Write-Error 'Replay exige -ReplayOutPath local.'; exit 2 }
    $LogDir = Split-Path -Parent ([IO.Path]::GetFullPath($ReplayOutPath))
}
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-verificacao-async_' + $DateTag + '.log')
$MetricsFile    = Join-Path $LogDir ('verificacao_async_metrics_' + $DateTag + '.json')
# DRYRUN-METRICS-SOBRESCREVE1 (02/09): dry-run nunca escreve o metrics da execucao real, e cada
# dry-run tem o proprio arquivo (hora no nome). Get-VixCustoDia soma os _dryrun*.json do dia.
$MetricsOut     = $MetricsFile
if ($DryRun) { $MetricsOut = [regex]::Replace($MetricsFile, '\.json$', ('_dryrun_' + (Get-Date -Format 'HHmmss') + '.json')) }
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'

$ModelVerificador = 'claude-sonnet-4-6'
$ModelFallback    = 'claude-sonnet-4-6'  # --fallback-model quando ModelVerificador != ModelFallback (ex.: troca futura pra claude-fable-5)
$ChunkSize        = 4
$PauseSec         = 2

# VERIF-TETO1 (2026-10-04): teto de conclusao EXCLUSIVO da verificacao no adapter OpenRouter.
# Antes o lote herdava o teto do tier FULL (49152) e, de 02 a 04/10, todo dreno tomou 402
# ("You requested up to 49152 tokens, but can only afford 2657..13493") com a fila parada.
# Medido nas verificacoes bem-sucedidas de 29 e 30/09: lotes de 1 a 5 eventos produziram de
# 326 a 1197 tokens de saida. 8192 e hipotese de validacao com folga de ~7x, nao garantia:
# resposta cortada no teto vira falha (ERRO_TRUNCADO) e o item fica na fila. As demais
# rotinas seguem com o teto do tier. Override por VIXRADAR_VERIF_MAX_TOKENS (Process>User),
# limitado pelo adapter a [1024, 49152].
$MaxTokensVerificacao = 8192
$__envVerifMax = [Environment]::GetEnvironmentVariable('VIXRADAR_VERIF_MAX_TOKENS', 'Process')
if (-not $__envVerifMax) { $__envVerifMax = [Environment]::GetEnvironmentVariable('VIXRADAR_VERIF_MAX_TOKENS', 'User') }
$__nVerifMax = 0
if ($__envVerifMax -and [int]::TryParse(('' + $__envVerifMax).Trim(), [ref]$__nVerifMax) -and $__nVerifMax -ge 1024) { $MaxTokensVerificacao = $__nVerifMax }

# Orcamento de token (2026-07-17): esta rotina era a UNICA das quatro sem teto nenhum — o token
# era somado para relatorio e nunca decidia nada. Medido em 16/07: 773.392 tokens para 18 eventos,
# 55% do consumo do dia inteiro e mais que o hard cap da noturna (700k). Como o limite da assinatura
# e semanal, o estouro nao aparece aqui: volta 1-2 dias depois como "weekly limit" abortando
# matinal/noturna — o erro recorrente que o operador via.
#
# Calibragem (deliberada, contra o real de 16/07): 773.392 / 5 lotes = ~155k por lote de 4, ou seja
# ~15k de boot + ~35k por evento. Um cap apertado (testado com 400k) deferiria 10 dos 18 eventos
# TODO DIA — e como a fila recebe eventos novos diariamente, ela cresceria sem limite: trocaria o
# estouro de token por uma fila que nunca drena, que e pior. Os 773k sao o custo legitimo de
# verificar 18 eventos com Sonnet + busca web, e o verificador e o gate que impede evento errado
# de entrar no painel: raciona-lo e desligar a qualidade para economizar.
# Entao o teto protege contra ANOMALIA (fila represada, dreno duplicado, loop), nao raciona o dia
# normal: 900k cobre a fila tipica com folga (~20 eventos); 1,3M corta so o que e anormal.
# NAO RESOLVIDO AQUI (estrutural, fica em PENDENCIAS): ~35k/evento e caro, e parte da fila e
# duplicata semantica do mesmo fato (W29 tem 7 eventos da Oncoclinicas para 2 fatos reais) — ou
# seja, paga-se Sonnet para verificar o mesmo fato varias vezes. Atacar a dedup reduz o custo na
# origem; mexer no cap so evita o desastre.
$TokenTarget  = 900000
$TokenHardCap = 1300000

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
# Ver run_vixradar_noturno_claude.ps1 para o achado completo: --mcp-config inline perdia as
# aspas em contexto de execucao agendada, quebrando 100% das chamadas. Arquivo elimina a fragilidade.
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Host $line
    # Retry com backoff: incidente 2026-07-17 (noturna) - lock de arquivo por instancia concorrente
    # fazia Add-Content sem try/catch derrubar a rotina inteira (ErrorActionPreference Stop).
    # Reincidencia sustentada 2026-07-18 (LOGLOCK1-REC, PENDENCIAS.md): lock ocupado 7+ min
    # seguidos (suspeita OneDrive/SearchIndexer). Backoff exponencial ate 8 tentativas
    # (200/400/800/1600/2000x4ms ~= 11s no pior caso) amplia a janela para locks curtos/medios
    # sem travar a rotina. Lock persistente/de minutos ainda degrada para Write-Host (transcript
    # captura), nunca derruba a rotina. Mitigacao parcial, nao a causa raiz (excluir logs/ do
    # sync do OneDrive seria a correcao completa, fora do escopo de codigo).
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) { Write-Host "FALHA Write-Log (Add-Content, $i tentativas): $($_.Exception.Message)" }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Identica a run_vixradar_noturno_claude.ps1/run_vixradar_matinal_claude.ps1 (achado 2026-07-08):
    # claude.exe pode perder a sessao OAuth local e imprimir esta mensagem em vez do envelope JSON,
    # com exit code 0. Sem isso o lote so cai no branch generico "parse de veredictos falhou" -
    # correto quanto ao efeito (erros_parse incrementa, exitCode vira 6), mas a causa fica oculta
    # no log (indistinguivel de JSON malformado/truncado por outro motivo).
    $texto = ($outputLines -join "`n")
    return $texto -match '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit'
}

function Get-RoutineKey {
    # v4.9.187: fallback de leitura de SKILL.md removido (recomendacao PENDENCIAS.md 2026-08-03).
    # O SKILL.md em scheduled-tasks/ pode conter chave velha apos rotacao. Env var e canonica.
    # ROTA1 (2026-08-18): apos a rotacao da chave, o registro User e a fonte da verdade.
    # Processo longevo (sessao do Claude Desktop) herda o env do boot e mandaria a chave
    # velha ate reiniciar - mesmo modo de falha que o rotate-routine-key.ps1 corrigiu na
    # hidratacao dele. Hidratar do registro SEMPRE, nao so quando o env esta ausente.
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) {
        $k = $doRegistro.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY no registro vazia apos trim.' }
        if ($k -ne $doRegistro) {
            Write-Log 'AVISO: ROUTINE_API_KEY do registro tinha espaco/quebra de linha nas bordas - usando o valor sem eles.'
        }
        return $k
    }
    # Trim (2026-08-05): o Worker compara com !== exato e NAO normaliza (worker.js ~16354).
    # Chave colada com quebra de linha ou espaco final produz 403 indistinguivel do 403 de
    # chave revogada - a causa mais barata de descartar antes de acusar rotacao.
    if ($env:ROUTINE_API_KEY) {
        $k = $env:ROUTINE_API_KEY.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY definida porem vazia apos trim.' }
        if ($k -ne $env:ROUTINE_API_KEY) {
            Write-Log 'AVISO: ROUTINE_API_KEY tinha espaco/quebra de linha nas bordas - usando o valor sem eles.'
        }
        return $k
    }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

# Auth do `claude -p` mora em um lugar so (2026-07-30). Critico neste script: a verificacao
# adversarial pressupoe um SEGUNDO modelo desafiando o primeiro, e com base URL de agregador
# Haiku e Sonnet colapsavam no mesmo modelo, virando o modelo se auditando. O helper fixa a
# API oficial em toda invocacao. Politica: assinatura primeiro, chave paga se o OAuth falhar.
. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')

# Assert-VixLibFunctions garante que funcoes removidas/renomeadas nas libs sem
# atualizar os call sites sao detectadas na hora, com erro claro, em vez de
# silenciosamente apos 24h como aconteceu em 04-05/08/2026.
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe', 'Send-VixRoutineAlert')
# Fase B D1 (2026-09-04): adapter OpenRouter e opcional. Ausencia do arquivo nao derruba
# os outros providers (none/claude-manual seguem intactos); so o provider 'openrouter'
# exige o adapter e o gate abaixo aborta 86 se ele nao existir.
if (Test-Path (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')) {
    . (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')
    $script:VixLibOpenRouterOk = $true
} else {
    $script:VixLibOpenRouterOk = $false
}
# COLETOR-PS1 (2026-09-23): evidencia deterministica para o verificador, desligavel para A/B.
$script:VixColetorAtivo = $false
$script:VixColetorCache = @{}
$script:VixColetorFalhas = @{}
$__coletorLib = Join-Path $PSScriptRoot 'lib\vixradar-coletor.ps1'
if (Test-Path $__coletorLib) {
    . $__coletorLib
    $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Process')
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'User') }
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Machine') }
    if (('' + $__flagColetor).Trim() -ne '0') { $script:VixColetorAtivo = $true }
    Write-Log ('COLETOR_PS: ativo=' + $script:VixColetorAtivo + ' (VIXRADAR_COLETOR_PS; 0 desliga)')
} else {
    Write-Log 'COLETOR_PS: lib ausente - o verificador continua buscando pelo modelo.'
}
$script:VixColetorObrigatorio = ((Get-VixLlmProvider) -eq 'deepseek')
if ($script:VixColetorObrigatorio -and -not $script:VixColetorAtivo) {
    Write-Log 'ERRO FATAL: provider deepseek exige COLETOR_PS ativo. DeepSeek direta nao tem WebSearch/WebFetch; nenhum lote sera chamado.'
    exit $VixLlmBloqueadoExit
}

function Get-AnthropicApiKey {
    # Mantida como fachada: ha chamadas antigas por este nome. A regra vive no helper.
    return (Get-VixAnthropicApiKey)
}

function Get-VixColetorParaEmissor([string]$Empresa) {
    if (-not $script:VixColetorAtivo) { return $null }
    $k = ('' + $Empresa).Trim().ToLowerInvariant()
    if ($script:VixColetorCache.ContainsKey($k)) { return $script:VixColetorCache[$k] }
    $c = $null
    try { $c = Get-VixColetorEvidencia -Empresa $Empresa } catch { $c = $null }
    if ($null -eq $c -or ($null -ne $c.PSObject.Properties['disponivel'] -and -not $c.disponivel)) { $script:VixColetorFalhas[$k] = $true }
    $script:VixColetorCache[$k] = $c
    return $c
}

function Get-VixBlocoColetorVerificacao($Itens) {
    if (-not $script:VixColetorAtivo) { return '' }
    $linhas = @()
    $linhas += 'COLETOR_PS_ATIVO: a evidencia abaixo foi coletada localmente pelo orquestrador para cada evento. PROIBIDO executar WebSearch, WebFetch, ferramenta de busca ou fetch. Use somente a evidencia fornecida e os dados do prompt do Worker.'
    $linhas += 'FONTES: nao invente URL, titulo, veiculo, dominio, data ou resultado. fontes_validas so pode conter URL ja presente no evento ou no prompt do Worker.'
    $linhas += 'COLETA_VAZIA: EVIDENCIA_VAZIA significa consulta concluida sem publicacao na janela. EVIDENCIA_INDISPONIVEL significa falha de coleta. Em qualquer um dos dois casos, retorne obrigatoriamente REPROVADO, confianca 0, fontes_validas [], com motivo fiel ao estado. Nao aprove nem corrija sem evidencia.'
    foreach ($item in @($Itens)) {
        $coleta = Get-VixColetorParaEmissor ('' + $item.empresa)
        $linhas += ('EVENTO_COLETOR|id=' + $item.id + '|empresa=' + $item.empresa)
        $linhas += (Format-VixColetorEvidenciaTexto $coleta)
        $linhas += 'FIM_EVENTO_COLETOR'
    }
    return ($linhas -join "`n")
}

function Get-VixCodexUsageProbe($Linhas) {
    foreach ($linha in @($Linhas)) {
        try {
            $obj = ('' + $linha).Trim() | ConvertFrom-Json
            if ($obj.usage -and $null -ne $obj.usage.input_tokens -and $null -ne $obj.usage.output_tokens) {
                $inputTotal = [int64]$obj.usage.input_tokens
                $cacheRead = [int64]$obj.usage.cached_input_tokens
                if ($null -ne $obj.usage.cache_read_input_tokens) { $cacheRead = [int64]$obj.usage.cache_read_input_tokens }
                if ($inputTotal -lt 0 -or $cacheRead -lt 0 -or $cacheRead -gt $inputTotal -or [int64]$obj.usage.output_tokens -lt 0) { continue }
                return [pscustomobject]@{ mensuravel = $true; parcelas = @{ input = ($inputTotal - $cacheRead); output = [int64]$obj.usage.output_tokens; cache_creation = [int64]$obj.usage.cache_creation_input_tokens; cache_read = $cacheRead } }
            }
        } catch { }
    }
    return [pscustomobject]@{ mensuravel = $false; parcelas = $null }
}

# Mesmas flags de isolamento Codex usadas pelo motor de varredura.
function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ('verifasync_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1
    # VERIF-TETO1: estado do provider HTTP, separado de parse. Ficam $false/vazios no ramo claude.
    $providerFalhou = $false; $providerMsg = ''; $semConsumo = $false; $truncado = $false; $stopReason = ''; $maxPedido = 0
    # --fallback-model so entra quando Model difere do fallback - evita fallback-pra-si-mesmo.
    # Hoje (Model=Sonnet=ModelFallback) isso NAO adiciona a flag; ativa sozinho se Model virar Fable.
    # Guard de nulidade: se a funcao for copiada para outro script sem $ModelFallback no escopo,
    # a comparacao com $null passaria e a flag iria vazia - quebrando o claude -p inteiro.
    $fallbackArgs = @()
    if ($ModelFallback -and $Model -ne $ModelFallback) { $fallbackArgs = @('--fallback-model', $ModelFallback) }
    try {
        # Fase B D1 (2026-09-04): provider openrouter despacha para o adapter HTTP proprio
        # (lib\vixradar-openrouter.ps1), com as server tools web_search/web_fetch. Sem claude,
        # sem auth Anthropic, sem escalacao paga. Retry bounded interno ao adapter; se esgotar,
        # itens ficam na fila (mesmo efeito do fluxo claude, sem tocar em chave paga).
        if ($script:VixUsaCodex) {
            $codexOutFile = Join-Path $LogDir ('verifasync_codex_' + $DateTag + '_' + $PID + '.txt')
            Remove-Item -LiteralPath $codexOutFile -Force -ErrorAction SilentlyContinue
            $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
            # CODEX-SKILLBLOCK1 (2026-10-09): ver run_vixradar_varredura.ps1/run_vixradar_sentinela.ps1.
            # Sem skip_host_skill_discovery o modelo tenta ler ~/.agents/skills, o sandbox read-only
            # rejeita o processo ("blocked by policy") e o lote sai como falha de provedor, 0 analise.
            $codexRaw = $promptText | codex -c features.skip_host_skill_discovery=true --search exec --json --ephemeral --sandbox read-only --ignore-user-config --ignore-rules --skip-git-repo-check -C $env:TEMP -o $codexOutFile - 2>>$stderrFile
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0 -and (Test-Path -LiteralPath $codexOutFile)) {
                $codexText = [string](Get-Content -LiteralPath $codexOutFile -Raw -Encoding UTF8)
                if ([string]::IsNullOrWhiteSpace($codexText)) {
                    $providerFalhou = $true; $providerMsg = 'Codex retornou resposta vazia'; $exitCode = 1
                } else {
                    $codexUsage = Get-VixCodexUsageProbe @($codexRaw)
                    $envelope = [ordered]@{ result = $codexText; is_error = $false; model = 'codex-subscription' }
                    if ($codexUsage.mensuravel) {
                        $envelope.usage = [ordered]@{ input_tokens = $codexUsage.parcelas.input; output_tokens = $codexUsage.parcelas.output; cache_creation_input_tokens = $codexUsage.parcelas.cache_creation; cache_read_input_tokens = $codexUsage.parcelas.cache_read }
                    } else { Write-Log 'USAGE_CODEX=NAO_MENSURAVEL: cap fecha apos este lote.' }
                    $raw = @(($envelope | ConvertTo-Json -Compress))
                }
            } else {
                $providerFalhou = $true; $providerMsg = ('Codex falhou ou nao produziu arquivo de resposta, exit=' + $exitCode)
                $raw = @($codexRaw)
            }
            Remove-Item -LiteralPath $codexOutFile -Force -ErrorAction SilentlyContinue
            if ($providerFalhou) { Write-Log ('ERRO_CODEX: ' + $providerMsg + ' - itens ficam na fila') }
        } elseif ($script:VixUsaOpenRouter) {
            $__orResp = Invoke-VixOpenRouterLote -PromptPath $promptPath -Tier 'FULL' -MaxTokens $MaxTokensVerificacao
            $raw = @($__orResp.Linhas)
            $exitCode = $__orResp.ExitCode
            # VERIF-TETO1: uma linha por tentativa (modelo, teto pedido, status, causa, consumo).
            foreach ($__t in @($__orResp.Tentativas)) { if ($__t) { Write-Log (Format-VixOpenRouterTentativa $__t) } }
            $truncado = [bool]$__orResp.Truncado
            $stopReason = '' + $__orResp.StopReason
            $maxPedido = [int]$__orResp.MaxTokensPedido
            if ($exitCode -ne 0) {
                $providerFalhou = $true
                $providerMsg = '' + $__orResp.Msg
                $semConsumo = [bool]$__orResp.SemConsumo
                Write-Log ('AVISO: lote OpenRouter falhou (' + $__orResp.Msg + ') - itens ficam na fila')
                # 402: diagnostico de causa pelo limit_source documentado e, uma vez por execucao,
                # leitura autenticada do estado da chave. So numeros vao ao log.
                if ([int]$__orResp.Status -eq 402) {
                    Write-Log ('OR_402|causa=' + $__orResp.Causa402 + '|afford=' + $__orResp.Afford + '|teto_pedido=' + $maxPedido)
                    if (-not $script:VixChaveStatusLida) {
                        $script:VixChaveStatusLida = $true
                        $__ck = Get-VixOpenRouterChaveStatus
                        Write-Log ('OR_CHAVE|ok=' + $__ck.ok + '|limit=' + $__ck.limit + '|limit_remaining=' + $__ck.limit_remaining + '|usage=' + $__ck.usage + '|is_free_tier=' + $__ck.is_free_tier + '|erro=' + $__ck.erro)
                    }
                }
            } else {
                Write-Log ('OR_OK: modelo=' + $__orResp.Modelo + ' intentos=' + $__orResp.Intentos + ' fallback=' + ('' + $__orResp.FallbackUsado).ToLower() + ' max_tokens=' + $maxPedido + ' stop=' + $stopReason)
            }
        } else {
            # Reforca UTF8 a cada lote (defesa contra reset de codepage mid-run, mesmo padrao
            # de mojibake achado no noturno em 08/07 - ver run_vixradar_noturno_claude.ps1).
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $OutputEncoding = [System.Text.Encoding]::UTF8
            # Auth resolvida no boot por Initialize-VixClaudeAuth: assinatura primeiro, chave paga
            # so se o OAuth nao responder. Reaplicada a cada lote porque o ambiente do processo
            # pode ter sido mexido no meio. Fixa a base URL oficial junto (incidente 73), o que
            # aqui e critico: com agregador, Haiku e Sonnet colapsavam no mesmo modelo.
            Set-VixClaudeAuthEnv
            $raw = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
                --model $Model `
                --permission-mode bypassPermissions `
                --output-format json `
                --tools 'WebSearch,WebFetch' `
                --strict-mcp-config --mcp-config $McpConfigFile `
                --setting-sources project `
                --disable-slash-commands `
                --no-session-persistence `
                --exclude-dynamic-system-prompt-sections `
                @fallbackArgs 2>>$stderrFile
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                # Sem retry interno aqui, entao a escalada nao recupera ESTE lote. Ela troca o
                # modo para os lotes seguintes, que e a diferenca entre perder um e perder a fila
                # inteira quando o OAuth vence no meio da drenagem.
                $saidaFalha = ('' + $raw)
                if (Test-Path $stderrFile) { $saidaFalha += (' ' + (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)) }
                if (Invoke-VixClaudeAuthEscalate $saidaFalha) {
                                    # MOTOR1: escalada nunca e silenciosa. Log, alerta ao admin e carimbo na FIM.
                                    $script:AuthEscalou = 'api'
                                    # DRYRUN-CRASH1: em dry-run a linha vira DRYRUN_ALERTA_AUTH (monitor nao trata teste como
                                    # 9004) e notificar_rotina nunca dispara (02/09 02:45 um teste mandou e-mail real).
                                    $alertaTag = 'ALERTA_AUTH: '
                                    if ($DryRun) { $alertaTag = 'DRYRUN_ALERTA_AUTH: ' }
                                    Write-Log ($alertaTag + 'verificacao-async escalou para chave paga (assinatura recusada no meio do dreno). Lotes seguintes custam dolar.')
                                    if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
                                    else { $null = Send-VixRoutineAlert -Rotina 'verificacao-async' -Motivo 'ALERTA_AUTH: escalou para chave paga no meio do dreno - assinatura recusada; regerar token com claude setup-token' -RoutineKey $script:routineKey -Causa 'escalacao_chave_paga' -Severidade 'aviso' }
                                }
            }
        }
    } catch {
        if ($script:VixUsaCodex) { $providerFalhou = $true; $providerMsg = $_.Exception.Message }
        $motorFalha = if ($script:VixUsaCodex) { 'codex exec' } else { 'claude -p/adapter HTTP' }
        Write-Log ('AVISO: excecao ao invocar ' + $motorFalha + ' (' + $_.Exception.Message + ') - lote marcado como falho')
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    $textOut = @($raw)
    $tokens = -1
    $parcelas = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = [int64]0 }
    $refusal = $false
    $refusalCategory = $null
    $refusalExplanation = $null
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                # REGUA-UNICA1 (2026-09-02): trabalho = input + output + cache_creation; cache_read
                # fica em coluna propria (antes entrava na soma e inflava contra o cap).
                $parcelas = Get-VixUsageParcelas $json
                $tokens = [int64]$parcelas.trabalho
            }
            # Classificador de seguranca do Fable 5/Mythos 5 pode recusar com stop_reason=refusal
            # (resposta HTTP 200 normal, nao excecao). stop_details.category/.explanation nao
            # confirmados no envelope do CLI (nunca observado em teste real) - le se existir, sem
            # quebrar se nao existir. Sem este guard, uma recusa cairia no branch generico de
            # parse-falhou e a causa raiz ficaria invisivel no log.
            # VERIF-TETO1: conclusao cortada no teto, nos dois motores, vira falha do lote.
            if (('' + $json.stop_reason) -eq 'max_tokens' -or ('' + $json.stop_reason) -eq 'length') { $truncado = $true; $stopReason = '' + $json.stop_reason }
            if ($json.stop_reason -eq 'refusal') {
                $refusal = $true
                if ($json.stop_details) {
                    $refusalCategory = $json.stop_details.category
                    $refusalExplanation = $json.stop_details.explanation
                }
            }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{
        Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; Parcelas = $parcelas; AuthFailure = $authFail
        Refusal = $refusal; RefusalCategory = $refusalCategory; RefusalExplanation = $refusalExplanation
        ProviderFalhou = $providerFalhou; ProviderMsg = $providerMsg; SemConsumo = $semConsumo
        Truncado = $truncado; StopReason = $stopReason; MaxTokensPedido = $maxPedido
        UsageNaoMensuravel = ($script:VixUsaCodex -and $tokens -lt 0)
    }
}

function Get-BalancedJson([string]$scan) {
    # Varre a partir do primeiro '[' (ou '{') ate o delimitador que o FECHA, contando profundidade
    # e ignorando colchetes/chaves dentro de strings JSON. Robusto contra texto apos o JSON
    # (ex.: o modelo via `claude -p` anexa uma lista de fontes em markdown `[titulo](url)` depois
    # do bloco - o LastIndexOf(']') ingenuo casava com esses ']' e corrompia a extracao).
    $start = $scan.IndexOf('[')
    $startObj = $scan.IndexOf('{')
    if ($start -lt 0 -or ($startObj -ge 0 -and $startObj -lt $start)) { $start = $startObj }
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($k = $start; $k -lt $scan.Length; $k++) {
        $ch = [string]$scan[$k]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $scan.Substring($start, $k - $start + 1) }
        }
    }
    return $null
}

function Get-VeredictosArray($outputLines, [int]$esperado) {
    # O verificador retorna um array JSON de veredictos, mas o `claude -p` costuma envolver em
    # cerca ```json ... ``` e anexar uma lista de fontes em markdown depois. Estrategia:
    #   1. Se houver bloco cercado ```json/```, extrair o conteudo dele (isola o JSON do resto).
    #   2. Senao, usar o texto inteiro.
    #   3. Extrair o JSON balanceado a partir do primeiro '[' (ignora qualquer coisa apos o array).
    $texto = ($outputLines -join "`n").Trim()
    $fence = [regex]::Match($texto, '```(?:json)?\s*([\s\S]*?)```')
    $scan = if ($fence.Success) { $fence.Groups[1].Value } else { $texto }
    # VERIF-PARSER2 (2026-09-29): quando o modelo ignora a instrucao de JSON puro,
    # a analise pode conter marcadores como [0], [1], [2] antes do array real.
    # Prioriza explicitamente o array de objetos de veredicto para nao capturar [0].
    $verdictStart = [regex]::Match($scan, '\[\s*\{\s*"veredicto"\s*:')
    if ($verdictStart.Success) { $scan = $scan.Substring($verdictStart.Index) }
    $bruto = Get-BalancedJson $scan
    if (-not $bruto) { return $null }
    try {
        $parsed = $bruto | ConvertFrom-Json
    } catch {
        return $null
    }
    $arr = @($parsed)
    if ($arr.Count -lt $esperado) { return $null }
    if ($arr.Count -gt $esperado) {
        Write-Log ("AVISO: modelo retornou " + $arr.Count + " veredictos para " + $esperado + " eventos - truncando para os primeiros " + $esperado)
        $arr = $arr[0..($esperado - 1)]
    }
    # 2026-07-13: mesmo padrao de array-unwrapping do Split-IntoChunks (return sem virgula unaria
    # desembrulha array de 1 elemento) - hoje inofensivo pois o unico consumo indexa so [0], mas
    # preventivo contra uso futuro (foreach, checagem de .Count) reativar a classe de bug.
    return ,$arr
}

# VERIF-TETO1 (2026-10-04): parecer completo e o unico que pode ir ao confirmar_verificacao.
# O Worker aceita APROVADO sem fonte e retrata o evento num CORRIGIR sem correcoes, entao a
# barreira fica aqui, antes da submissao. Devolve '' quando o parecer esta completo, ou o
# motivo curto da reprova. REPROVADO sem fonte e valido de proposito: e o que o prompt exige
# quando a coleta vem vazia. Pura, sem rede.
function Get-VixParecerIncompleto($V) {
    if ($null -eq $V) { return 'parecer_nulo' }
    $ver = ('' + $V.veredicto).Trim().ToUpperInvariant()
    if (@('APROVADO', 'REPROVADO', 'CORRIGIR') -notcontains $ver) { return ('veredicto_invalido:' + $ver) }
    if (('' + $V.veredicto) -cne $ver) { return 'veredicto_formato_invalido' }
    $conf = 0.0
    if ($null -eq $V.confianca -or -not [double]::TryParse(('' + $V.confianca), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$conf)) { return 'confianca_ausente' }
    if ([double]::IsNaN($conf) -or [double]::IsInfinity($conf) -or $conf -lt 0 -or $conf -gt 1) { return 'confianca_fora_de_0_1' }
    if ([string]::IsNullOrWhiteSpace(('' + $V.motivo))) { return 'motivo_vazio' }
    if ($ver -eq 'APROVADO' -or $ver -eq 'CORRIGIR') {
        $fontes = @(@($V.fontes_validas) | Where-Object { $_ -is [string] -and $_ -match '^(?i)https?://\S+' })
        if ($fontes.Count -eq 0) { return 'aprovacao_sem_fonte' }
        if ($V.fontes_validas -isnot [array]) { return 'fontes_validas_nao_array' }
    }
    if ($ver -eq 'CORRIGIR') {
        # Contrato real de aplicarCorrecaoVerificador no Worker. Um CORRIGIR que
        # nao altera campo suportado volta false e seria tratado como rejeicao.
        if ($conf -lt 0.8) { return 'corrigir_confianca_abaixo_de_0_8' }
        $c = $V.correcoes
        if ($null -eq $c -or $c -is [string] -or $c -is [array] -or @($c.PSObject.Properties).Count -eq 0) { return 'corrigir_sem_correcoes' }
        $aplicavel = $false
        $hojeBrt = [datetime]::UtcNow.AddHours(-3).Date
        $minimoBrt = $hojeBrt.AddDays(-35).ToString('yyyy-MM-dd')
        $hojeTexto = $hojeBrt.ToString('yyyy-MM-dd')
        $dataCorrecao = [datetime]::MinValue
        if ($c.data_evento -is [string] -and $c.data_evento -cmatch '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($c.data_evento, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dataCorrecao) -and [string]::CompareOrdinal($c.data_evento, $minimoBrt) -ge 0 -and [string]::CompareOrdinal($c.data_evento, $hojeTexto) -le 0) { $aplicavel = $true }
        if ($c.fonte_primaria -is [string] -and @($fontes | Where-Object { $_ -ceq $c.fonte_primaria }).Count -gt 0) { $aplicavel = $true }
        if (@('CRITICO', 'RELEVANTE', 'ECO') -ccontains $c.classificacao) { $aplicavel = $true }
        if ($c.titulo -is [string] -and $c.titulo.Trim().Length -ge 8 -and $c.titulo.Length -le 240) { $aplicavel = $true }
        if (-not $aplicavel) { return 'corrigir_sem_campo_aplicavel' }
    }
    return ''
}

function Invoke-WorkerJsonUtf8 {
    # Worker responde application/json SEM charset; Windows PowerShell 5.1 decodificaria a
    # resposta como ISO-8859-1, corrompendo acentos em memoria (nomes de emissor e ate o
    # system_prompt do verificador - P0 nota 43, 2026-07-07). Le bytes crus e decoda UTF-8
    # explicitamente; envia body como bytes UTF-8 pelo mesmo motivo.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

# Mutex (2026-07-17): esta era a unica das rotinas sem exclusao mutua, e a com MAIS gatilhos
# concorrentes: task VIXRadar-Verificacao-Async (10:20) + dreno inline pos-matinal + pos-noturno.
# Quase-colisao real em 15/07: POS-MATINAL as 10:16:08 e task as 10:20:02, 4 min de folga — so
# nao colidiu porque a fila estava vazia e o dreno durou 2s. Com fila cheia o dreno leva ~29 min
# (16/07: 18:39:38 -> 19:08:43), entao qualquer atraso da matinal faz as duas instancias drenarem
# os mesmos ids e pagarem o mesmo evento 2x. Mesmo padrao ja provado em noturno/matinal/export.
# CLAUDE-FREE-MIGRATION (2026-09-04): drenar a fila de verificacao consome claude por
# evento. Sem provider manual forcado, bloqueia com exit 86 antes do mutex e do preflight.
# Scheduler nunca passa -ForceClaude; provider 'none' (default) ou 'claude-manual' sem flag
# = BLOQUEADO_SEM_PROVIDER.
$script:VixUsaOpenRouter = (Test-VixUsaLlmAdapterHttp)
$script:VixUsaCodex = ((Get-VixLlmProvider) -eq 'codex')
$openRouterAdapterHabilitado = ($script:VixLibOpenRouterOk -and (Get-Command 'Invoke-VixOpenRouterLote' -ErrorAction SilentlyContinue) -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue))
$codexAdapterHabilitado = ($null -ne (Get-Command 'codex' -ErrorAction SilentlyContinue))
if (-not (Test-VixLlmProviderPermiteRotina -ForceClaude:$ForceClaude -OpenRouterAdapterHabilitado:$openRouterAdapterHabilitado -CodexAdapterHabilitado:$codexAdapterHabilitado)) {
    Write-Log (Get-VixLlmBloqueadoMsg 'run_vixradar_verificacao_async.ps1')
    exit $VixLlmBloqueadoExit
}

# Replay local termina antes do mutex, preflight, reserva, confirmacao e notificacoes.
# O payload preserva o contrato do Worker. Proveniencia deve declarar se veio de
# listar_fila_verificacao ou foi reconstruido localmente de eventos reais do KV
# e do template Worker. Reconstrucao local nao comprova o endpoint da fila.
if ($ReplayFilaPath) {
    try {
        if (-not $script:VixUsaCodex) { throw 'Replay local exige provider codex.' }
        $filaReplay = Get-Content -LiteralPath $ReplayFilaPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $itensReplay = @($filaReplay.itens)
        if ($filaReplay.ok -ne $true -or -not $filaReplay.system_prompt -or -not $filaReplay.user_prompt -or $itensReplay.Count -lt 1 -or $itensReplay.Count -gt $MaxEventos) { throw 'Payload real invalido ou quantidade acima de MaxEventos. Salve listar_fila_verificacao filtrado por ids.' }
        $idsReplay = @{}
        foreach ($itemReplay in $itensReplay) {
            if ([string]::IsNullOrWhiteSpace(('' + $itemReplay.id)) -or [string]::IsNullOrWhiteSpace(('' + $itemReplay.empresa)) -or $idsReplay.ContainsKey(('' + $itemReplay.id))) { throw 'Replay exige id unico e empresa em cada item.' }
            $idsReplay[('' + $itemReplay.id)] = $true
        }
        if ($script:VixColetorAtivo) {
            foreach ($itemReplay in $itensReplay) {
                $chaveReplay = ('' + $itemReplay.empresa).Trim().ToLowerInvariant()
                $propReplay = $null
                if ($filaReplay.coletor_por_emissor) { $propReplay = $filaReplay.coletor_por_emissor.PSObject.Properties[$chaveReplay] }
                if ($null -eq $propReplay -or $null -eq $propReplay.Value) { throw 'Replay com coletor ativo exige coletor_por_emissor real para cada empresa.' }
                $script:VixColetorCache[$chaveReplay] = $propReplay.Value
            }
        }
        $promptReplay = $filaReplay.system_prompt + "`n`n" + $filaReplay.user_prompt
        $blocoReplay = Get-VixBlocoColetorVerificacao $itensReplay
        if ($blocoReplay) { $promptReplay += "`n`n" + $blocoReplay }
        $promptReplay += "`n`nResponda SOMENTE com o array JSON de veredictos, um por evento, na mesma ordem em que os eventos foram listados acima. Nenhum texto antes ou depois do JSON."
        $promptReplay += "`nREPLAY LOCAL: execute apenas consultas de leitura para verificar evidencias. Proibido chamar o Worker do VIX, reservar, confirmar, notificar, enviar mensagem ou alterar qualquer servico. Retorne o parecer somente na resposta."
        $promptReplayPath = Join-Path $LogDir ('verifasync_replay_prompt_' + $PID + '.txt')
        Set-Content -LiteralPath $promptReplayPath -Value $promptReplay -Encoding UTF8 -ErrorAction Stop
        $resultadoReplay = Invoke-ClaudeBatch $promptReplayPath $ModelVerificador
        $pareceresReplay = $null
        if (-not $resultadoReplay.ProviderFalhou -and -not $resultadoReplay.Truncado -and -not $resultadoReplay.Refusal -and -not $resultadoReplay.AuthFailure -and $resultadoReplay.ExitCode -eq 0) { $pareceresReplay = Get-VeredictosArray $resultadoReplay.Output $itensReplay.Count }
        $completosReplay = 0
        foreach ($parecerReplay in @($pareceresReplay)) { if ($null -ne $parecerReplay -and -not (Get-VixParecerIncompleto $parecerReplay)) { $completosReplay++ } }
        $okReplay = ($null -ne $pareceresReplay -and $completosReplay -eq $itensReplay.Count)
        [ordered]@{ ok = $okReplay; modo = 'replay_local'; provenance = $filaReplay.provenance; proveniencia = $filaReplay.proveniencia; submit_ok = 0; esperados = $itensReplay.Count; completos = $completosReplay; resultado = $resultadoReplay; pareceres = $pareceresReplay } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReplayOutPath -Encoding UTF8 -ErrorAction Stop
        Write-Log ('REPLAY_LOCAL|ok=' + $okReplay + '|eventos=' + $itensReplay.Count + '|completos=' + $completosReplay + '|submit_ok=0')
        if (-not $okReplay) { exit 6 }
        exit 0
    } catch { Write-Log ('REPLAY_LOCAL_ERRO: ' + $_.Exception.Message); exit 6 }
    finally { if ($promptReplayPath) { Remove-Item -LiteralPath $promptReplayPath -Force -ErrorAction SilentlyContinue } }
}

$__verifMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-verifasync')
if (-not $__verifMutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia do dreno ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens'
    exit 0
}

Write-Log ('INICIO: drenar fila de verificacao assincrona meta=' + $TokenTarget + ' hard=' + $TokenHardCap)
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# PREFLIGHT DE CREDENCIAL (2026-08-05): Worker antes de Claude.
# A ordem anterior gastava Initialize-VixClaudeAuth + probe WebSearch (uma chamada
# `claude -p` real) antes de tocar no Worker, entao uma ROUTINE_API_KEY morta so
# aparecia depois do gasto. Pior: Invoke-WebRequest do PS 5.1 lanca excecao em 403 e o
# corpo {"erro":"Acesso negado."} fica preso dentro dela - no log o 403 de credencial
# ficava indistinguivel de rede caida. Health e chave sao GET/POST baratos, sem LLM;
# rodam primeiro e falham com causa nomeada. Confirmado 05/08: listar_fila_verificacao
# devolveu 403 a partir do host, com a chave que estava em disco.
try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    Write-Log ('Health ' + $health.versao + ' verificador_ok=' + $health.verificador_ok)
    $versaoWorker = $health.versao
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

# listar_todos_emissores: mesma guarda de routine_key dos endpoints da fila, somente
# leitura, sem efeito colateral e com total conferivel (103). E o teste canonico de
# chave usado nas auditorias do vault.
try {
    $__pfResp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_todos_emissores'; routine_key = $routineKey } -TimeoutSec 45
} catch {
    $__pfStatus = 0
    if ($_.Exception.Response) { $__pfStatus = [int]$_.Exception.Response.StatusCode }
    if ($__pfStatus -eq 403) {
        Write-Log 'ERRO FATAL: ROUTINE_API_KEY rejeitada pelo Worker (HTTP 403 Acesso negado).'
        Write-Log 'ERRO FATAL: a chave existe no ambiente mas nao bate com o secret ROUTINE_API_KEY do Worker. Causas usuais: chave rotacionada em producao, aspas coladas junto do valor, valor truncado.'
        Write-Log 'ERRO FATAL: reexportar $env:ROUTINE_API_KEY e reexecutar. Nenhum token de LLM foi gasto.'
        exit 8
    }
    Write-Log ('ERRO FATAL: preflight de credencial falhou (HTTP ' + $__pfStatus + '): ' + $_.Exception.Message)
    exit 8
}
if ($__pfResp.ok -ne $true) {
    Write-Log 'ERRO FATAL: preflight de credencial respondeu ok:false sem erro HTTP - endpoint recusou a chamada.'
    exit 8
}
Write-Log ('Preflight: ROUTINE_API_KEY aceita pelo Worker (' + [int]$__pfResp.total + ' emissores). Nenhum token gasto ate aqui.')
# Sonda a assinatura uma vez e registra no log qual credencial serviu a execucao. A linha
# importa para proveniencia: em 30/07 o log carimbava Claude sem que isso fosse verificavel.
# Fase B D1 (2026-09-04): provider openrouter nao usa auth Claude, nao roda probe WebSearch do
# CLI e nao exige claude.exe. O adapter tem a chave OpenRouter (ambiente) e as server tools
# web_search/web_fetch nativas; a credencial ja foi validada externamente pelo operador.
if ($script:VixUsaCodex) {
    Write-Log 'AUTH_MODO: codex (assinatura Codex CLI, sem OpenRouter e sem auth Anthropic)'
} elseif ($script:VixUsaOpenRouter) {
    $__orBoot = Test-VixOpenRouterPronto
    if (-not $__orBoot.ok) {
        Write-Log ('ERRO FATAL: ' + $__orBoot.motivo)
        Write-Log 'ERRO FATAL: OpenRouter configurado mas adapter nao pronto. Nenhuma chamada sera feita.'
        exit 5
    }
    Write-Log ('AUTH_MODO: ' + (Get-VixLlmEndpointDescricao) + ' (adapter HTTP, sem claude, sem auth Anthropic). busca_web=' + (Test-VixLlmEndpointTemBusca))
} else {
    Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
    $__claudeAuthModo = Get-VixClaudeAuthModo
    # CLAUDEFALLBACK-OR1 (2026-09-22): assinatura sem credencial (cota de sessao esgotada
    # ou nenhum token disponivel) nao aborta mais direto quando o operador autorizou o
    # desvio (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter). Ausencia da var = comportamento
    # antigo intocado (aborta e alerta). Decisao pura em Get-VixClaudeFallbackOpenRouterHabilitado.
    if ($__claudeAuthModo -eq 'nenhum' -and (Get-VixClaudeFallbackOpenRouterHabilitado) -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
        $__claudeFrBoot = Test-VixOpenRouterPronto
        if ($__claudeFrBoot.ok) {
            Write-Log 'FALLBACK_OPENROUTER: assinatura sem credencial, desviando a rotina inteira para openrouter (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter).'
            $script:VixUsaOpenRouter = $true
        } else {
            Write-Log ('FALLBACK_OPENROUTER: fallback habilitado mas adapter nao pronto (' + $__claudeFrBoot.motivo + '). Sem desvio possivel.')
        }
    }
    if ($script:VixUsaOpenRouter) {
        Write-Log 'AUTH_MODO: openrouter (fallback da assinatura esgotada, adapter HTTP D1)'
    } elseif ($__claudeAuthModo -eq 'nenhum') {
        Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel (assinatura expirada, token longevo ausente, chave paga invalida ou ausente). Abortando antes do primeiro lote.'
        Write-Log 'ERRO FATAL: rode `claude setup-token` para token longevo ou defina VIXRADAR_ANTHROPIC_API_KEY com chave sk-ant-valida.'
        # DRENOMUDO1 (2026-09-13): este ramo saia calado, ao contrario do ramo irmao de
        # escalada paga, que ja levanta ALERTA_AUTH. E ele e o caminho mais provavel de
        # todos, porque cota de assinatura estourada deixa o modo em 'nenhum'. Medido em
                # 13/09: o dreno pos-matinal das 16:46 morreu aqui, sem ALERTA_AUTH e sem nada que
                # o vigia diario lesse. O motor, que chamou o dreno, ainda escreveu no proprio log
                # "dreno concluido (exit=5)".
                $alertaTag = 'ALERTA_AUTH: '
                if ($DryRun) { $alertaTag = 'DRYRUN_ALERTA_AUTH: ' }
                Write-Log ($alertaTag + 'nenhuma credencial Claude na verificacao-async antes do primeiro lote - a fila de verificacao NAO foi drenada neste ciclo (exit 5).')
                if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
                else { $null = Send-VixRoutineAlert -Rotina 'verificacao-async' -Motivo ('ALERTA_AUTH: nenhuma credencial Claude na verificacao-async (cota de assinatura estourada ou token ausente) - fila de verificacao nao drenada') -RoutineKey $script:routineKey -Causa 'sem_credencial' -Severidade 'critico' }
                exit 5
    }
    # CLAUDEFALLBACK-OR1-FIX1 (2026-09-23): o desvio para openrouter acontece DENTRO deste ramo,
    # entao o if/elseif acima decidiu so o LOG. Sem esta guarda a execucao seguia para as
    # checagens exclusivas do caminho Claude (ambiente, probe WebSearch, claude.exe) e morria em
    # exit 7 mesmo tendo desviado. Medido em producao em 22/09 18:14 e 19:16, literal: a linha
    # 'AUTH_MODO: openrouter' seguida de 'ERRO FATAL: probe WebSearch falhou'. Mesmo padrao ja
    # correto em run_vixradar_varredura.ps1:1291 e run_vixradar_agenda_semanal.ps1:369, onde as
    # guardas ficam no else e sao puladas pelo desvio.
    if (-not $script:VixUsaOpenRouter) {
    # Alinhado com 2b025b0: a guarda perdeu o parametro -ModeloFixadoNaChamada e a funcao
    # Get-VixModeloEnvInfo, mas as duas chamadas continuaram aqui. Sob $ErrorActionPreference
    # 'Continue' isso nao mataria o script - e pior: parametro inexistente faz o bind falhar,
    # $ambientViolacao fica $null e o `if` abaixo nunca dispara. A guarda inteira (incluindo
    # ANTHROPIC_BASE_URL, o vetor real do 27/07) sairia de servico em silencio, com so um
    # registro de erro no log. Chamada normalizada para a assinatura que a lib expoe hoje.
    $ambientViolacao = Test-VixClaudeAmbienteLimpo
    if ($ambientViolacao) {
        Write-Log "ERRO FATAL: ambiente contaminado detectado — $ambientViolacao"
        Write-Log 'ERRO FATAL: variavel de ambiente ou settings.json aponta para agregador/modelo nao-Claude.'
        Write-Log 'ERRO FATAL: corrija o ambiente e reexecute. Verificar: registry User/Machine, settings.json, env vars do processo.'
        exit 6
    }
    if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
        Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel.'
        Write-Log 'ERRO FATAL: verificar modelo configurado e conectividade. A execucao foi abortada antes do primeiro evento.'
        exit 7
    }

    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Log 'ERRO: claude.exe ausente'
        exit 2
    }
    }
}

$stats = @{ total_fila = 0; lotes = 0; aprovados = 0; rejeitados = 0; erros_parse = 0; refusals = 0; tokens_total = 0; tokens_desconhecidos = 0; deferred = 0; token_hard_hit = $false
    input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; reservados = 0; ja_reservados = 0; protecao_ativa = $false; confirmados = 0
    falhas_provider = 0; truncados = 0; pareceres_incompletos = 0 }
$script:AuthEscalou = 'nenhum'
$exitCode = 0
$origemLocal = if ($DryRun) { 'local-dryrun' } else { 'local' }
if ($DryRun) { Write-Log 'DRYRUN: lista e reserva a fila, roda o verificador, mas NUNCA chama confirmar_verificacao (itens continuam na fila; a reserva expira em 20 min).' }

try {
    $fila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; dias = 3 } -TimeoutSec 60

    if ($fila.ok -ne $true) { Write-Log 'ERRO: listar_fila_verificacao'; exit 5 }
    $stats.total_fila = [int]$fila.total
    Write-Log ('Fila: ' + $stats.total_fila + ' evento(s) pendente(s)')

    if ($stats.total_fila -eq 0) {
        Write-Log 'FIM: fila vazia, nada a fazer'
        $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Write-Log ('ROTINA_RESUMO|vixradar-verificacao-async|local|' + $inicioIso + '|' + $fimIso + '|OK|0|0|0|' + $versaoWorker)
        @{ data = $DateTag; total_fila = 0; lotes = 0; dryrun = [bool]$DryRun } | ConvertTo-Json | Set-Content $MetricsOut -Encoding UTF8
        exit 0
    }

    $itens = @($fila.itens)

    # CONCORVERIF1 (2026-08-18) / MOTOR1 (2026-09-02): reserva atomica ANTES de gastar token.
    # A rotina remota (02h07, origem "remote") e qualquer outra mao na fila reservam pelo mesmo
    # Durable Object com janela de 20 min; quem chegou depois recebe ja_reservados e nao paga
    # verificacao repetida. O claimante local e sempre "local" (ou "local-dryrun" em dry-run):
    # em 01/09 um dreno manual com claimante inventado deixou a rotina das 18h45 sem trabalho.
    try {
        $itensReserva = @($itens | ForEach-Object { @{ id = $_.id; data_fila = $_.data_fila } })
        $resReserva = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'reservar_itens_fila'; routine_key = $routineKey; origem = $origemLocal; itens = $itensReserva } -Depth 6 -TimeoutSec 60
        if ($resReserva.ok -eq $true) {
            $reservados = @($resReserva.reservados)
            $jaRes = @($resReserva.ja_reservados)
            $stats.reservados = $reservados.Count
            $stats.ja_reservados = $jaRes.Count
            $stats.protecao_ativa = ($resReserva.protecao_ativa -eq $true)
            Write-Log ('RESERVA|origem=' + $origemLocal + '|reservados=' + $reservados.Count + '|ja_reservados=' + $jaRes.Count + '|protecao_ativa=' + $stats.protecao_ativa)
            if ($jaRes.Count -gt 0) {
                $claimantes = @($jaRes | ForEach-Object { '' + $_.claimante } | Sort-Object -Unique) -join ','
                Write-Log ('RESERVA_BLOQUEADA: ' + $jaRes.Count + '/' + $itens.Count + ' itens ja_reservados por claimante ' + $claimantes + ' - pulando esses, sem verificacao duplicada')
            }
            $setRes = @{}
            foreach ($r in $reservados) { $setRes[('' + $r)] = $true }
            $itens = @($itens | Where-Object { $setRes.ContainsKey('' + $_.id) })
        } else {
            Write-Log ('AVISO: reservar_itens_fila respondeu ok:false (' + $resReserva.erro + ') - seguindo sem reserva, com recheck antes de cada confirmacao')
        }
    } catch {
        Write-Log ('AVISO: reservar_itens_fila falhou (' + $_.Exception.Message + ') - seguindo sem reserva, com recheck antes de cada confirmacao')
    }
    if ($itens.Count -eq 0) {
        Write-Log ('FIM: submit_ok=0 fila=' + $stats.total_fila + ' reservados=0 ja_reservados=' + $stats.ja_reservados + ' (tudo reservado por outro claimante, nada a fazer nesta execucao)')
        $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Write-Log ('ROTINA_RESUMO|vixradar-verificacao-async|local|' + $inicioIso + '|' + $fimIso + '|OK|0|0|0|' + $versaoWorker)
        exit 0
    }

    for ($i = 0; $i -lt $itens.Count; $i += $ChunkSize) {
        if ($script:VixUsaCodex -and $stats.token_hard_hit) {
            $stats.deferred += ($itens.Count - $i)
            break
        }
        $fim = [Math]::Min($i + $ChunkSize - 1, $itens.Count - 1)
        $chunk = @($itens[$i..$fim])
        $stats.lotes++
        $label = 'verifasync-' + $stats.lotes

        # Hard cap PRE-lote (2026-07-17): mede antes de gastar, nao depois. Estimativa por lote =
        # boot (~15k) + eventos * 35k, ambos medidos no real de 16/07 (773.392 / 5 lotes de 4).
        # Deferir aqui e barato e reversivel: o item permanece na fila e o proximo dreno o pega —
        # ao contrario de deferir emissor na noturna, onde a cobertura do dia se perde.
        $estLote = 15000 + ($chunk.Count * 35000)
        if (($stats.tokens_total + $estLote) -ge $TokenHardCap) {
            Write-Log ('HARD CAP pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' >= ' + $TokenHardCap + ' - lote ' + $label + ' e restantes deferred (' + ($itens.Count - $i) + ' evento(s) ficam na fila)')
            $stats.token_hard_hit = $true
            $stats.deferred += ($itens.Count - $i)
            break
        }

        # Prompt construido pelo Worker (fonte unica de verdade das regras do verificador) so para os ids deste chunk -
        # evita duplicar o template do prompt em PowerShell e mantem o system_prompt/user_prompt alinhados ao chunk exato.
        $chunkIds = @($chunk | ForEach-Object { $_.id })
        $chunkFila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; ids = $chunkIds } -TimeoutSec 60
        if ($chunkFila.ok -ne $true -or -not $chunkFila.system_prompt) {
            Write-Log ('ERRO: nao consegui montar prompt do lote ' + $label + ' via listar_fila_verificacao(ids) - itens ficam na fila')
            $stats.erros_parse++
            Start-Sleep -Seconds $PauseSec
            continue
        }

        # VERIFCACHE1 (2026-07-24): cache de verificacao no fluxo real.
        # O Worker retorna cache_hits (mapa id->veredicto). Itens com cache hit pulam o LLM
        # e vao direto para confirmar_verificacao, economizando ~35k tokens/evento.
        $confirmarItens = @()
        $cachedIds = @{}
        if ($chunkFila.cache_hits) {
            $chunkFila.cache_hits.PSObject.Properties | ForEach-Object { $cachedIds[$_.Name] = $_.Value }
        }
        $cacheHitCount = 0
        foreach ($item in $chunk) {
            if ($cachedIds.ContainsKey($item.id)) {
                $confirmarItens += @{
                    id = $item.id; empresa = $item.empresa; semana = $item.semana
                    setor = $item.setor; data_fila = $item.data_fila; evento = $item.evento
                    veredicto = $cachedIds[$item.id]
                }
                $cacheHitCount++
            }
        }
        if ($cacheHitCount -gt 0) {
            Write-Log ('CACHE_HITS|' + $label + '|' + $cacheHitCount + ' evento(s) do cache - ' + (($chunk | Where-Object { $cachedIds.ContainsKey($_.id) } | ForEach-Object { $_.empresa }) -join ', '))
            if (-not $stats.cache_hits) { $stats.cache_hits = 0 }
            $stats.cache_hits += $cacheHitCount
        }

        # Itens sem cache: fluxo LLM normal
        $nonCached = @($chunk | Where-Object { -not $cachedIds.ContainsKey($_.id) })
        if ($nonCached.Count -gt 0) {
            $nonCachedIds = @($nonCached | ForEach-Object { $_.id })
            # Se todo o chunk era cache hit, nao precisa de prompt LLM
            if ($nonCachedIds.Count -eq $chunkIds.Count) {
                # Nenhum cache hit — usa o prompt ja obtido (contem todos os itens)
                $promptChunkIds = $chunkIds
                $promptChunkFila = $chunkFila
            } else {
                # Cache parcial — re-obtem prompt so para os nao-cached
                $promptChunkIds = $nonCachedIds
                $promptChunkFila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; ids = $nonCachedIds } -TimeoutSec 60
            }
            if ($promptChunkFila.ok -ne $true -or -not $promptChunkFila.system_prompt) {
                Write-Log ('ERRO: nao consegui montar prompt do lote ' + $label + ' (non-cached) - itens ficam na fila')
                $stats.erros_parse++
                Start-Sleep -Seconds $PauseSec
                continue
            }
            $blocoColetor = Get-VixBlocoColetorVerificacao $nonCached
            if ($script:VixColetorObrigatorio -and $script:VixColetorFalhas.Count -gt 0) {
                Write-Log ('ERRO FATAL: coletor indisponivel para evento(s) do lote ' + $label + ' sob provider deepseek. DeepSeek nao pode verificar sem evidencia coletada.')
                exit 6
            }
            $promptTexto = $promptChunkFila.system_prompt + "`n`n" + $promptChunkFila.user_prompt
            if ($blocoColetor) { $promptTexto += ("`n`n" + $blocoColetor) }
            $promptTexto += "`n`nResponda SOMENTE com o array JSON de veredictos, um por evento, na mesma ordem em que os eventos foram listados acima. Nenhum texto antes ou depois do JSON."
            $promptPath = Join-Path $LogDir ('verifasync_' + $label + '_' + $DateTag + '.txt')
            Set-Content $promptPath -Value $promptTexto -Encoding UTF8

            Write-Log ('Lote ' + $label + ': ' + $nonCached.Count + ' evento(s) [cache=' + $cacheHitCount + '] - ' + (($nonCached | ForEach-Object { $_.empresa }) -join ', '))
            $result = Invoke-ClaudeBatch $promptPath $ModelVerificador
            if ($result.UsageNaoMensuravel) { $stats.token_hard_hit = $true }
            # VERIF-TETO1: falha do provider (402, 4xx, transporte esgotado) e categoria propria.
            # Antes caia no parse e virava "parse de veredictos falhou" com erros_parse=1 e uma
            # estimativa de 85000 a 120000 tokens cobrada contra o cap, sem nada ter sido gerado.
            if ($result.ProviderFalhou) {
                if ($result.SemConsumo) {
                    Write-Log ('Tokens lote=0 (provider recusou todas as tentativas com 4xx antes de gerar) acum=' + $stats.tokens_total)
                } else {
                    $stats.tokens_total += $estLote
                    $stats.tokens_desconhecidos++
                    Write-Log ('AVISO: tokens do lote ' + $label + ' DESCONHECIDOS (falha de provider com possivel consumo) - cobrando estimativa ' + $estLote + ' contra o cap; acum=' + $stats.tokens_total)
                }
                $stats.falhas_provider++
                Write-Log ('ERRO_PROVIDER|' + $label + '|eventos=' + $nonCached.Count + '|teto=' + $result.MaxTokensPedido + '|sem_consumo=' + $result.SemConsumo + '|pareceres_completos=0 - itens ficam na fila')
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }
            if ($result.Tokens -gt 0) {
                $stats.tokens_total += $result.Tokens
                $stats.input += $result.Parcelas.input; $stats.output += $result.Parcelas.output
                $stats.cache_creation += $result.Parcelas.cache_creation; $stats.cache_read += $result.Parcelas.cache_read
                Write-Log ('Tokens lote=' + $result.Tokens + ' (input=' + $result.Parcelas.input + ' output=' + $result.Parcelas.output + ' cache_creation=' + $result.Parcelas.cache_creation + ' cache_read=' + $result.Parcelas.cache_read + ') acum=' + $stats.tokens_total)
            } else {
                $stats.tokens_total += $estLote
                $stats.tokens_desconhecidos++
                if ($result.UsageNaoMensuravel) {
                    $stats.token_hard_hit = $true
                    Write-Log 'USAGE_CODEX=NAO_MENSURAVEL: lote corrente pode concluir, lotes seguintes deferred.'
                } else { Write-Log ('AVISO: tokens do lote ' + $label + ' DESCONHECIDOS (parse do envelope falhou) - cobrando estimativa ' + $estLote + ' contra o cap; acum=' + $stats.tokens_total) }
            }

            if ($result.AuthFailure) {
                            Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no lote ' + $label + ' - reautentique com "claude /login". Abortando lotes restantes - itens ficam na fila.')
                            # AUTHWEEK1 (2026-08-14): avisa o admin no momento do abort (limite semanal,
                            # OAuth vencido etc). O Monitor-Tasks nao enxerga esta rotina.
                            $null = Send-VixRoutineAlert -Rotina 'verificacao-async' -Motivo 'claude CLI nao autenticado ou limite semanal atingido - itens permanecem na fila' -RoutineKey $routineKey -Causa 'falha_auth' -Severidade 'critico'
                            $stats.erros_parse++
                            $exitCode = 7
                            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                            break
                        }

            if ($result.Refusal) {
                $categoria = if ($result.RefusalCategory) { $result.RefusalCategory } else { 'desconhecida (stop_details ausente no envelope)' }
                $rawOutPath = Join-Path $LogDir ('verifasync_rawout_refusal_' + $label + '_' + $DateTag + '.txt')
                Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
                Write-Log ('AVISO: classificador de seguranca recusou o lote ' + $label + ' (' + $nonCached.Count + ' evento(s); stop_reason=refusal, categoria=' + $categoria + ', modelo=' + $ModelVerificador + ') - possivel falso-positivo. Recusa e por conteudo do evento, nao por sessao - prosseguindo para o proximo lote. Itens deste lote ficam na fila (janela de releitura: 3 dias). Saida bruta em ' + $rawOutPath)
                if ($result.RefusalExplanation) { Write-Log ('  explicacao do classificador: ' + $result.RefusalExplanation) }
                $stats.refusals++
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }

            # VERIF-TETO1: resposta cortada no teto nao vale, mesmo que o JSON pareca fechar.
            # Nada e submetido, o lote inteiro fica na fila e a saida bruta fica para auditoria.
            if ($result.Truncado) {
                $rawOutPath = Join-Path $LogDir ('verifasync_rawout_truncado_' + $label + '_' + $DateTag + '.txt')
                Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
                Write-Log ('ERRO_TRUNCADO|' + $label + '|stop=' + $result.StopReason + '|teto=' + $result.MaxTokensPedido + '|output=' + $result.Parcelas.output + '|pareceres_completos=0 - itens ficam na fila. Saida bruta em ' + $rawOutPath)
                $stats.truncados++
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }

            $veredictos = Get-VeredictosArray $result.Output $nonCached.Count
            if (-not $veredictos) {
                $rawOutPath = Join-Path $LogDir ('verifasync_rawout_' + $label + '_' + $DateTag + '.txt')
                Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
                Write-Log ('ERRO: parse de veredictos falhou ou contagem nao bate no lote ' + $label +
                    ' (esperado=' + $nonCached.Count + ') - saida bruta em ' + $rawOutPath + ' - itens ficam na fila')
                $stats.erros_parse++
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }

            $completosLote = 0
            for ($j = 0; $j -lt $nonCached.Count; $j++) {
                # VERIF-TETO1: parecer incompleto nao e submetido. O item fica na fila, sem
                # aprovacao automatica e sem retratacao por CORRIGIR vazio.
                $motivoIncompleto = Get-VixParecerIncompleto $veredictos[$j]
                if ($motivoIncompleto) {
                    $stats.pareceres_incompletos++
                    Write-Log ('PARECER_INCOMPLETO|' + $label + '|id=' + $nonCached[$j].id + '|empresa=' + $nonCached[$j].empresa + '|motivo=' + $motivoIncompleto + ' - item fica na fila')
                    continue
                }
                $completosLote++
                $confirmarItens += @{
                    id = $nonCached[$j].id; empresa = $nonCached[$j].empresa; semana = $nonCached[$j].semana
                    setor = $nonCached[$j].setor; data_fila = $nonCached[$j].data_fila; evento = $nonCached[$j].evento
                    veredicto = $veredictos[$j]
                }
            }
            Write-Log ('PARECERES|' + $label + '|completos=' + $completosLote + '|esperados=' + $nonCached.Count + '|teto=' + $result.MaxTokensPedido + '|stop=' + $result.StopReason)
        } else {
            Write-Log ('Lote ' + $label + ': ' + $chunk.Count + ' evento(s) TODOS do cache - sem chamada LLM')
        }

        if ($confirmarItens.Count -eq 0) {
            # VERIF-TETO1: nenhum parecer completo neste lote, nada a submeter.
            Write-Log ('LOTE_SEM_SUBMISSAO|' + $label + '|nenhum parecer completo - itens ficam na fila')
        } elseif ($DryRun) {
            Write-Log ('DRYRUN_CONFIRM|' + $label + '|itens=' + $confirmarItens.Count + '|veredictos=' + (($confirmarItens | ForEach-Object { '' + $_.empresa + ':' + $_.veredicto.veredicto }) -join ', ') + ' (nao confirmado, itens seguem na fila)')
        } else {
            # Sem protecao atomica (DO indisponivel) o recheck e obrigatorio: so confirma o que
            # ainda esta na fila, para nao retratar item que outra mao ja fechou.
            if (-not $stats.protecao_ativa -and $confirmarItens.Count -gt 0) {
                try {
                    $recheck = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; ids = @($confirmarItens | ForEach-Object { $_.id }) } -TimeoutSec 60
                    $aindaNaFila = @{}
                    foreach ($it in @($recheck.itens)) { $aindaNaFila[('' + $it.id)] = $true }
                    $antes = $confirmarItens.Count
                    $confirmarItens = @($confirmarItens | Where-Object { $aindaNaFila.ContainsKey('' + $_.id) })
                    if ($confirmarItens.Count -lt $antes) { Write-Log ('RECHECK: ' + ($antes - $confirmarItens.Count) + ' item(ns) ja fechados por outra mao, nao confirmados') }
                } catch { Write-Log ('AVISO: recheck antes da confirmacao falhou (' + $_.Exception.Message + ') - confirmando mesmo assim') }
            }
            try {
                $confirmResp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'confirmar_verificacao'; routine_key = $routineKey; origem = 'local'; itens = $confirmarItens } -Depth 12 -TimeoutSec 60
                if ($confirmResp.ok -eq $true) {
                    $stats.aprovados += [int]$confirmResp.resultado.aprovados
                    $stats.rejeitados += [int]$confirmResp.resultado.rejeitados
                    $stats.confirmados += $confirmarItens.Count
                    Write-Log ('LOTE_FECHADO|' + $label + '|aprovados=' + $confirmResp.resultado.aprovados + '|rejeitados=' + $confirmResp.resultado.rejeitados + '|erros=' + $confirmResp.resultado.erros + '|cache=' + $cacheHitCount)
                } else {
                    Write-Log ('ERRO: confirmar_verificacao falhou no lote ' + $label + ' - ' + $confirmResp.erro)
                }
            } catch {
                Write-Log ('EXCECAO: confirmar_verificacao ' + $label + ' - ' + $_.Exception.Message)
            }
        }

        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        if ($script:VixUsaCodex -and $result.UsageNaoMensuravel) {
            $stats.deferred += [Math]::Max(0, $itens.Count - $fim - 1)
            break
        }
        Start-Sleep -Seconds $PauseSec
    }

    $metricsOut = $MetricsOut
    [ordered]@{
        data = $DateTag; rotina = 'verificacao-async'; dryrun = [bool]$DryRun; total_fila = $stats.total_fila; lotes = $stats.lotes
        reservados = $stats.reservados; ja_reservados = $stats.ja_reservados; protecao_ativa = $stats.protecao_ativa
        aprovados = $stats.aprovados; rejeitados = $stats.rejeitados; confirmados = $stats.confirmados
        erros_parse = $stats.erros_parse; refusals = $stats.refusals
        falhas_provider = $stats.falhas_provider; truncados = $stats.truncados; pareceres_incompletos = $stats.pareceres_incompletos; max_tokens_verificacao = $MaxTokensVerificacao
        tokens_total_est = $stats.tokens_total; tokens_trabalho = $stats.tokens_total
        tokens_input = $stats.input; tokens_output = $stats.output; tokens_cache_creation = $stats.cache_creation; tokens_cache_read = $stats.cache_read
        auth_escalou = $script:AuthEscalou
    } | ConvertTo-Json | Set-Content $metricsOut -Encoding UTF8

    $fimTag = if ($DryRun) { 'FIM_DRYRUN: ' } else { 'FIM: ' }
    Write-Log ($fimTag + 'fila=' + $stats.total_fila + ' reservados=' + $stats.reservados + ' ja_reservados=' + $stats.ja_reservados + ' lotes=' + $stats.lotes + ' aprovados=' + $stats.aprovados + ' rejeitados=' + $stats.rejeitados + ' submit_ok=' + $stats.confirmados + ' erros_parse=' + $stats.erros_parse + ' refusals=' + $stats.refusals + ' tokens=' + $stats.tokens_total + ' cache_read=' + $stats.cache_read + ' meta=' + $TokenTarget + ' hard=' + $TokenHardCap + ' hard_hit=' + $stats.token_hard_hit + ' deferred=' + $stats.deferred + ' tokens_desconhecidos=' + $stats.tokens_desconhecidos + ' auth_escalou=' + $script:AuthEscalou + ' falhas_provider=' + $stats.falhas_provider + ' truncados=' + $stats.truncados + ' pareceres_incompletos=' + $stats.pareceres_incompletos + ' max_tokens=' + $MaxTokensVerificacao)

    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    # VERIF-TETO1: falha de provider, truncamento e parecer incompleto contam como erro do dreno
    # (PARCIAL e exit 6, mesmo efeito que o monitor ja conhece), mas com causa separada no log.
    $errosTotal = $stats.erros_parse + $stats.refusals + $stats.falhas_provider + $stats.truncados + $stats.pareceres_incompletos
    $resultadoTxt = if ($errosTotal -gt 0) { 'PARCIAL' } else { 'OK' }
    Write-Log ('ROTINA_RESUMO|vixradar-verificacao-async|local|' + $inicioIso + '|' + $fimIso + '|' + $resultadoTxt + '|' + ($stats.aprovados + $stats.rejeitados) + '|' + $errosTotal + '|' + $stats.deferred + '|' + $versaoWorker)

    if (($stats.erros_parse + $stats.falhas_provider + $stats.truncados + $stats.pareceres_incompletos) -gt 0) { $exitCode = 6 } elseif ($stats.refusals -gt 0) { $exitCode = 8 }
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
}

if ($exitCode -ne 0) { exit $exitCode }
