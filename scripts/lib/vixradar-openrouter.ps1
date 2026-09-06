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

# Teto CURTO e explicito da serializacao pre-HTTP. Serializar este corpo e trabalho de
# milissegundos; qualquer coisa em segundos ja e patologia. Ver JSONCICLO1 abaixo.
function Get-VixOpenRouterJsonTimeoutSec {
    $t = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_JSON_TIMEOUT_SEC'
    if (-not $t) { return 20 }
    $n = 0
    if ([int]::TryParse(('' + $t).Trim(), [ref]$n) -and $n -gt 0) { return $n }
    return 20
}

# JSONCICLO1 (2026-09-05): a noturna de 05/09 ficou 55 min presa ANTES do POST, sem socket
# aberto, queimando 1 core e subindo ~41 MB/s ate 9 GB, e morreu sem escrever FIM.
#
# Causa: `Get-Content -Raw` NAO devolve System.String puro. Devolve a string decorada pelo
# provider de arquivo com as note properties PSPath, PSParentPath, PSChildName, PSDrive e
# PSProvider. `.GetType()` mente e diz System.String porque desembrulha o PSObject, mas o
# ConvertTo-Json enxerga as properties e desce nelas. PSDrive e um PSDriveInfo cujo .Provider
# e um ProviderInfo cujo .Drives e uma colecao de PSDriveInfo, que tem .Provider de novo:
# ciclo. ConvertTo-Json do 5.1 nao tem deteccao de ciclo, entao ele expande o ciclo ate
# gastar o -Depth inteiro. Medido com o prompt real (40.619 chars): json_len 65 no depth 1,
# 44.035 no 2, 44.563 no 4, 68.766 no 5, 428.091 no 6, crescendo ~6x por nivel. No depth 12
# isso projeta ~1e10 chars, que e exatamente a rampa de memoria vista em producao.
# Forcar [string] apaga a decoracao: json_len fica 43.713 constante do depth 1 ao 12.
#
# Regra que fica: NADA entra no payload sem passar por aqui. So [ordered]/hashtable, array,
# string e primitivo. Qualquer outro tipo aborta o lote de imediato, com o caminho do campo
# no erro, em vez de virar rampa de memoria.
function ConvertTo-VixOpenRouterPayloadSeguro($Valor, [string]$Caminho = '$body', [int]$Nivel = 0) {
    if ($Nivel -gt 8) { throw ('PAYLOAD_PROFUNDO_DEMAIS em ' + $Caminho) }
    if ($null -eq $Valor) { return $null }

    # NAO usar "-is [PSObject]" para desembrulhar: em PowerShell essa checagem e
    # SEMPRE verdadeira, para qualquer valor (quirk documentado do motor), e ".BaseObject"
    # numa string ja "achatada" (como a que sai de Get-Content) devolve $null. A tentativa
    # antiga de desembrulhar aqui zerava TODO valor que entrava nesta funcao antes mesmo de
    # checar o tipo, string, hashtable ou o que fosse. GetType() ja reporta o tipo real
    # (System.String, Hashtable, FileInfo, PSCustomObject) sem precisar de BaseObject; o
    # [string]::Copy() abaixo e o suficiente para descartar note properties de string.
    if ($Valor -is [string]) { return [string]::Copy([string]$Valor) }
    if ($Valor -is [bool] -or $Valor -is [int] -or $Valor -is [long] -or $Valor -is [int16] -or
        $Valor -is [byte] -or $Valor -is [double] -or $Valor -is [single] -or $Valor -is [decimal]) {
        return $Valor
    }

    if ($Valor -is [System.Collections.Specialized.OrderedDictionary] -or $Valor -is [hashtable]) {
        $novo = [ordered]@{}
        foreach ($k in @($Valor.Keys)) {
            $novo[[string]$k] = ConvertTo-VixOpenRouterPayloadSeguro $Valor[$k] ($Caminho + '.' + $k) ($Nivel + 1)
        }
        return $novo
    }

    if ($Valor -is [System.Array] -or ($Valor -is [System.Collections.IList] -and -not ($Valor -is [string]))) {
        $itens = @()
        $i = 0
        foreach ($item in $Valor) {
            $itens += ,(ConvertTo-VixOpenRouterPayloadSeguro $item ($Caminho + '[' + $i + ']') ($Nivel + 1))
            $i++
        }
        return ,$itens
    }

    throw ('TIPO_NAO_SERIALIZAVEL em ' + $Caminho + ': ' + $Valor.GetType().FullName)
}

# ConvertTo-Json com teto de parede. Roda em runspace proprio e desiste no limite, para que
# uma patologia de serializacao aborte o lote em segundos em vez de comer as 4h do Scheduler.
# Retorna @{ Ok; Json; Erro; Segundos }.
#
# LIMITE CONHECIDO (medido nesta sessao): $ps.Stop() pede parada cooperativa entre cmdlets;
# um UNICO ConvertTo-Json que ja entrou numa recursao nao-cooperativa (caso do ciclo
# PSDrive->Provider->Drives->Provider) NAO e interrompido por Stop(), so PAROU DE SER
# ESPERADO por este runspace. A thread de fundo continua rodando e alocando ate estourar
# sozinha. Por isso esta funcao NAO e a defesa principal contra JSONCICLO1: quem realmente
# impede o ciclo de chegar aqui e o sanitizador (ConvertTo-VixOpenRouterPayloadSeguro), que
# reconstroi a arvore inteira em tipos limpos ANTES desta chamada e tem teto de profundidade
# proprio (Nivel>8 lanca na hora, sem alocar). Este teto de parede e so o cinto de seguranca
# para um payload SANITIZADO que acabe grande ou lento por outro motivo, nao para o ciclo
# original. Nunca chamar esta funcao com um objeto que nao passou pelo sanitizador antes.
function ConvertTo-VixOpenRouterJsonLimitado($Obj, [int]$Depth = 12, [double]$TimeoutSec = 0.0) {
    if ($TimeoutSec -le 0) { $TimeoutSec = Get-VixOpenRouterJsonTimeoutSec }
    $res = @{ Ok = $false; Json = ''; Erro = ''; Segundos = 0.0 }
    $ps = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $ps = [System.Management.Automation.PowerShell]::Create()
        [void]$ps.AddScript('param($o, $d) $o | ConvertTo-Json -Depth $d -Compress')
        [void]$ps.AddArgument($Obj)
        [void]$ps.AddArgument($Depth)
        $async = $ps.BeginInvoke()
        if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSec))) {
            $sw.Stop()
            $res.Segundos = $sw.Elapsed.TotalSeconds
            $res.Erro = 'SERIALIZACAO_ESTOUROU_TETO=' + $TimeoutSec + 's'
            try { $ps.Stop() } catch { }
            return $res
        }
        $saida = $ps.EndInvoke($async)
        $sw.Stop()
        $res.Segundos = $sw.Elapsed.TotalSeconds
        if ($ps.Streams.Error.Count -gt 0) {
            $res.Erro = 'SERIALIZACAO_ERRO=' + ('' + $ps.Streams.Error[0].Exception.Message)
            return $res
        }
        $txt = ''
        if ($saida) { $txt = '' + (@($saida)[0]) }
        if (-not $txt) { $res.Erro = 'SERIALIZACAO_VAZIA'; return $res }
        $res.Json = $txt
        $res.Ok = $true
        return $res
    } catch {
        $sw.Stop()
        $res.Segundos = $sw.Elapsed.TotalSeconds
        $res.Erro = 'SERIALIZACAO_EXCECAO=' + $_.Exception.Message
        return $res
    } finally {
        # JSONCICLO1-FIN (2026-09-06): Dispose SEMPRE, tambien en timeout/error. Antes era
        # `if ($ps -and $res.Ok)`, y los paths que devolvian Ok=false (teto de pared, error de
        # streams, excepcion) dejaban el runspace y su thread de fondo vivos: leak de handles/
        # threads en cada lote que pasaba por aqui. El dispose incondicional vuelve al baseline.
        if ($ps) { try { $ps.Dispose() } catch { } }
    }
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
    # JSONCICLO1: o [string] nao e cosmetico. Get-Content devolve string decorada com PSDrive/
    # PSProvider, e essa decoracao e o ciclo que travou a noturna de 05/09 no ConvertTo-Json.
    try { $prompt = [string]::Copy([string](Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8 -ErrorAction Stop)) } catch { $falha.Msg = 'falha ao ler prompt: ' + $_.Exception.Message; return $falha }
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
    # JSONCICLO1, guarda de 2 estagios antes de qualquer rede:
    #   1) sanitiza: reconstroi o payload so com [ordered], array, string e primitivo. Tipo
    #      complexo aborta AQUI, em microssegundos, nomeando o campo.
    #   2) serializa com teto de parede curto. Nada de POST sem JSON pronto.
    $bodySeguro = $null
    try {
        $bodySeguro = ConvertTo-VixOpenRouterPayloadSeguro $bodyObj
    } catch {
        $falha.Msg = 'PAYLOAD_INVALIDO: ' + $_.Exception.Message
        $falha.Linhas = @('OPENROUTER_FALHA_COD=1')
        return $falha
    }
    $ser = ConvertTo-VixOpenRouterJsonLimitado $bodySeguro 12
    if (-not $ser.Ok) {
        $falha.Msg = $ser.Erro + ' (prompt_chars=' + $prompt.Length + ', ' + $ser.Segundos.ToString('F1') + 's)'
        $falha.Linhas = @('OPENROUTER_FALHA_COD=1')
        return $falha
    }
    $json = $ser.Json
    $script:VixOpenRouterUltimaSerializacaoSeg = $ser.Segundos
    $script:VixOpenRouterUltimoPayloadBytes = [System.Text.Encoding]::UTF8.GetByteCount($json)

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
