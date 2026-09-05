# vixradar-openrouter.ps1 - adapter HTTP proprio para OpenRouter (Fase B D1, 2026-09-04).
#
# CLAUDE-FREE-MIGRATION Fase B D1: substitui a invocacao `claude -p --tools WebSearch,WebFetch`
# por POST https://openrouter.ai/api/v1/chat/completions com as SERVER TOOLS nativas
# openrouter:web_search e openrouter:web_fetch. O OpenRouter roda o loop de agente server-side
# (o modelo chama 0..N vezes), o que preserva o comportamento de busca web que o claude -p
# tinha, sem depender do Claude CLI nem de auth Anthropic. Nenhum fallback Anthropic pago.
#
# Regra de seguranca (INC-2026-08-20): a chave OPENROUTER_API_KEY e lida do ambiente em
# processo, nunca aparece em argumento de linha de comando, em URL, em log ou em diff.
# Este arquivo NAO chama claude, NAO le chave Anthropic e NAO tem credencial em literal.
#
# Contrato de saida: devolve o MESMO envelope JSON do `claude -p --output-format json` em uma
# linha unica (campo .result com o texto, .usage com input_tokens/output_tokens/
# cache_creation_input_tokens/cache_read_input_tokens), para o parser de cada rotina
# (Get-ParsedResultados, Get-BalancedJson, Get-VixUsageParcelas) funcionar sem mudanca.
#
# Transport-first: o prompt das rotinas e enviado INTEIRO como mensagem de usuario; o modelo
# escreve o mesmo protocolo textual de antes (RESULTADO|empresa|{json}, etc). Schema JSON por
# rotina e passo 2, depois dos testes verdes. Nenhum response_format nesta fase.
#
# Politica de retry (spec D1): 401/402/403 = falha imediata sem retry; 408/429/500/502/503/
# 524/529 = retry bounded com backoff. Erro de transporte (status 0) tambem retenta.
#
# PowerShell 5.1, ASCII puro (sem BOM necessario), $ErrorActionPreference Continue.

$VixOpenRouterBase = 'https://openrouter.ai/api/v1/chat/completions'
$VixOpenRouterModelDefault = '~deepseek/deepseek-v4-flash-latest'
$VixOpenRouterRetryable = @(408, 429, 500, 502, 503, 504, 522, 524, 529)

function Get-VixOpenRouterEnv([string]$Name) {
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
    return $v
}

function Get-VixOpenRouterApiKey {
    $k = Get-VixOpenRouterEnv 'OPENROUTER_API_KEY'
    if (-not $k) { $k = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_API_KEY' }
    return $k
}

function Get-VixOpenRouterModel {
    $m = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_MODEL'
    if (-not $m) { $m = $VixOpenRouterModelDefault }
    return (('' + $m).Trim())
}

function Get-VixOpenRouterTimeoutMin {
    $t = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_TIMEOUT_MIN'
    if (-not $t) { return 12 }
    $n = 0
    if ([int]::TryParse(('' + $t).Trim(), [ref]$n) -and $n -gt 0) { return $n }
    return 12
}

function Test-VixOpenRouterPronto {
    # Sem segredo no retorno: so diz se a chave existe e o modelo resolveu.
    $key = Get-VixOpenRouterApiKey
    $model = Get-VixOpenRouterModel
    if (-not $key) { return [pscustomobject]@{ ok = $false; motivo = 'OPENROUTER_API_KEY ausente (processo/User/Machine). Rotina nao sai do bloqueio.' } }
    if (-not $model) { return [pscustomobject]@{ ok = $false; motivo = 'modelo OpenRouter vazio (VIXRADAR_OPENROUTER_MODEL).' } }
    return [pscustomobject]@{ ok = $true; motivo = 'pronto' }
}

function Test-VixOpenRouterStatusRetryable([int]$Status) {
    if ($Status -eq 0) { return $true }  # erro de transporte (timeout/conexao)
    return ($VixOpenRouterRetryable -contains $Status)
}

# Converte a resposta JSON do OpenRouter no envelope do claude -p. Pura e testavel sem rede.
#   $u.usage: prompt_tokens, completion_tokens, prompt_tokens_details.cached_tokens (quando vem)
#   Mapa: cache_read = cached_tokens (releitura 0,1x), cache_creation = 0 nesta fase,
#         input = prompt_tokens - cached (novo nao-cacheado), output = completion_tokens.
function ConvertTo-VixOpenRouterEnvelope($Resp) {
    $r = [ordered]@{}
    $msg = $null
    if ($Resp -and $Resp.choices -and @($Resp.choices).Count -gt 0) { $msg = @($Resp.choices)[0].message }
    $result = ''
    if ($msg -and $null -ne $msg.content) { $result = '' + $msg.content }
    $stop = ''
    if ($msg -and $null -ne $msg.stop_reason) { $stop = '' + $msg.stop_reason }
    elseif ($Resp -and $null -ne $Resp.choices -and @($Resp.choices)[0].finish_reason) { $stop = '' + @($Resp.choices)[0].finish_reason }

    $input = [int64]0; $output = [int64]0; $cacheRead = [int64]0
    if ($Resp -and $Resp.usage) {
        $u = $Resp.usage
        if ($u.prompt_tokens) { $input = [int64]$u.prompt_tokens }
        if ($u.completion_tokens) { $output = [int64]$u.completion_tokens }
        $cached = [int64]0
        if ($u.prompt_tokens_details -and $u.prompt_tokens_details.cached_tokens) { $cached = [int64]$u.prompt_tokens_details.cached_tokens }
        if ($cached -gt $input) { $cached = $input }
        if ($cached -gt 0) {
            $cacheRead = $cached
            $input = $input - $cached
        }
    }

    $r['result'] = $result
    $r['is_error'] = $false
    $r['model'] = if ($Resp -and $Resp.model) { '' + $Resp.model } else { (Get-VixOpenRouterModel) }
    $r['stop_reason'] = $stop
    $r['usage'] = [ordered]@{
        input_tokens = $input
        output_tokens = $output
        cache_creation_input_tokens = [int64]0
        cache_read_input_tokens = $cacheRead
    }
    if ($Resp -and $Resp.usage -and $Resp.usage.server_tool_use) {
        $r['server_tool_use'] = $Resp.usage.server_tool_use
    }
    return [pscustomobject]$r
}

# POST unico ao OpenRouter. Retorna @{ Status; Body; Erro } sem lancar. Nada de segredo no
# retorno. Timeout de parede por tentativa = Get-VixOpenRouterTimeoutMin.
function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
    $res = @{ Status = 0; Body = ''; Erro = '' }
    if (-not $ApiKey) { $res.Erro = 'chave ausente antes do POST'; return $res }
    $client = $null
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromMinutes((Get-VixOpenRouterTimeoutMin))
        $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $ApiKey)
        try { [void]$client.DefaultRequestHeaders.Add('X-OpenRouter-Metadata', 'enabled') } catch { }
        $content = New-Object System.Net.Http.StringContent($JsonBody, [System.Text.Encoding]::UTF8, 'application/json')
        $resp = $client.PostAsync($VixOpenRouterBase, $content).GetAwaiter().GetResult()
        $res.Status = [int]$resp.StatusCode
        try { $res.Body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { $res.Body = '' }
        try { $resp.Dispose() } catch { }
    } catch {
        $res.Erro = $_.Exception.Message
    } finally {
        if ($client) { try { $client.Dispose() } catch { } }
    }
    return $res
}

# Orquestra um lote completo: le o prompt, POSTa com server tools, normaliza o envelope.
# Retenta bounded em status retryable. Retorna @{ Linhas; ExitCode; Msg; Tokens; Parcelas }.
#   ExitCode 0 = resposta HTTP 2xx parseada (mesmo que o texto do modelo venha vazio).
#   ExitCode != 0 = falha apos retries; Linhas carrega linha de erro NAO-JSON (sem segredo).
function Invoke-VixOpenRouterLote([string]$PromptPath, [int[]]$RetryDelays = @(0, 5, 20)) {
    $falha = @{ Linhas = @('OPENROUTER_FALHA_COD=1'); ExitCode = 1; Msg = 'falha interna'; Tokens = -1; Parcelas = $null }
    $prompt = ''
    try { $prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8 -ErrorAction Stop } catch { $falha.Msg = 'falha ao ler prompt: ' + $_.Exception.Message; return $falha }
    if (-not $prompt) { $falha.Msg = 'prompt vazio'; return $falha }

    $apiKey = Get-VixOpenRouterApiKey
    $model = Get-VixOpenRouterModel
    $timeoutMin = Get-VixOpenRouterTimeoutMin
    if (-not $apiKey) { $falha.Msg = 'OPENROUTER_API_KEY ausente'; $falha.Linhas = @('OPENROUTER_FALHA_COD=1'); return $falha }

    $tools = @(
        [ordered]@{ type = 'openrouter:web_search'; parameters = [ordered]@{ engine = 'exa'; max_results = 5; max_total_results = 15 } },
        [ordered]@{ type = 'openrouter:web_fetch'; parameters = [ordered]@{ engine = 'openrouter'; max_content_tokens = 20000 } }
    )
    $bodyObj = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = $prompt })
        tools = $tools
        stream = $false
        # Roteamento (spec D1): nunca openrouter/auto, nunca :floor, nenhum Anthropic em
        # model/fallback. allow_fallbacks=false garante que provider nenhum assuma a chamada.
        provider = [ordered]@{ require_parameters = $true; allow_fallbacks = $false }
    }
    $json = $bodyObj | ConvertTo-Json -Depth 12 -Compress

    $delays = $RetryDelays
    if (-not $delays -or $delays.Count -eq 0) { $delays = @(0, 5, 20) }
    $ultimo = ''
    $ultimoCod = 0
    for ($i = 0; $i -lt $delays.Count; $i++) {
        if ($i -gt 0) { Start-Sleep -Seconds $delays[$i] }
        $http = Send-VixOpenRouterHttp -ApiKey $apiKey -JsonBody $json
        if ($http.Status -gt 0) { $ultimoCod = $http.Status }
        if ($http.Erro) { $ultimo = ('erro de transporte: ' + $http.Erro); continue }
        if ($http.Status -ge 200 -and $http.Status -lt 300) {
            $parsed = $null
            try { $parsed = $http.Body | ConvertFrom-Json } catch { $parsed = $null }
            if ($null -eq $parsed -or $null -eq $parsed.choices -or @($parsed.choices).Count -eq 0) {
                $ultimo = ('HTTP ' + $http.Status + ' resposta sem choices (body malformado ou vazio)')
                if (Test-VixOpenRouterStatusRetryable $http.Status) { continue }
                break
            }
            $env = ConvertTo-VixOpenRouterEnvelope $parsed
            $linha = $env | ConvertTo-Json -Depth 8 -Compress
            $parcelas = @{ input = [int64]$env.usage.input_tokens; output = [int64]$env.usage.output_tokens; cache_creation = [int64]$env.usage.cache_creation_input_tokens; cache_read = [int64]$env.usage.cache_read_input_tokens }
            $parcelas.trabalho = $parcelas.input + $parcelas.output + $parcelas.cache_creation
            return @{ Linhas = @($linha); ExitCode = 0; Msg = 'ok http=' + $http.Status + ' model=' + $env.model; Tokens = [int64]$parcelas.trabalho; Parcelas = $parcelas }
        }
        # corpo de erro pode vir com .error.message; extrai sem segredo, corta a 200 chars
        $motivo = ''
        try {
            $ep = $http.Body | ConvertFrom-Json
            if ($ep -and $ep.error -and $ep.error.message) { $motivo = (' ' + (('' + $ep.error.message))) }
        } catch { }
        if ($motivo.Length -gt 200) { $motivo = $motivo.Substring(0, 200) }
        $ultimo = ('OPENROUTER_HTTP_STATUS=' + $http.Status + $motivo)
        if (Test-VixOpenRouterStatusRetryable $http.Status) { continue }
        break  # 4xx duro: sem retry (401/402/403/400/404/...)
    }
    $falha.Msg = $ultimo
    # Linha de erro SEM corpo: o parser do motor varre o stdout por falha de auth Anthropic e o
    # motivo completo contem palavras (api key, token, unauthorized) que dariam falso positivo.
    $falha.Linhas = @('OPENROUTER_FALHA_COD=' + $ultimoCod)
    return $falha
}
