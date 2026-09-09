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
# OR429-FIX (2026-09-09): allow_fallbacks=true no payload reativa o failover NATIVO do
# OpenRouter entre providers do mesmo modelo; o retry bounded abaixo e a camada unica apos
# esse failover, respeitando Retry-After (0..120s).
#
# PowerShell 5.1, ASCII puro (sem BOM necessario), $ErrorActionPreference Continue.

$VixOpenRouterBase = 'https://openrouter.ai/api/v1/chat/completions'
$VixOpenRouterModelDefault = 'deepseek/deepseek-v4-flash-0731'
$VixOpenRouterModelLightDefault = $VixOpenRouterModelDefault
$VixOpenRouterFallbackDefault = 'deepseek/deepseek-v4-flash'
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

# Test-VixModeloIdValido: ID concreto vendor/modelo. Rechaza alias ~name (semantica
# ~latest de OpenRouter) y sufijo -latest: son punteros moviles que OpenRouter reparte
# entre upstreams, y ese reparto fue la fuente del 429 intermitente de la sentinela
# 07/09/2026. La rotina manda con ID fijo; un alias en env cae al default operacional.
function Test-VixModeloIdValido([string]$Modelo) {
    $m = ('' + $Modelo).Trim()
    if ($m -eq '') { return $false }
    if ($m.StartsWith('~')) { return $false }
    if ($m -match '(?i)-latest$') { return $false }
    return ($m -match '^[a-z0-9_-]+/[a-z0-9][a-z0-9._-]*$')
}

function Get-VixOpenRouterModel([string]$Tier = '') {
    $tierUpper = ('' + $Tier).Trim().ToUpperInvariant()
    $envName = if ($tierUpper -eq 'LIGHT') { 'VIXRADAR_OPENROUTER_MODEL_LIGHT' } elseif ($tierUpper -eq 'FULL') { 'VIXRADAR_OPENROUTER_MODEL_FULL' } else { '' }
    $m = if ($envName) { Get-VixOpenRouterEnv $envName } else { $null }
    if (-not $m) { $m = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_MODEL' }
    if (-not $m) { return $VixOpenRouterModelLightDefault }
    $m = ('' + $m).Trim()
    if (Test-VixModeloIdValido $m) { return $m }
    return $VixOpenRouterModelDefault
}

# Fallback explicito (politica C2): segundo modelo DeepSeek validado, usado SOLO cuando el
# primario agota retries con status retryable/transporte/resultado vacio. Nunca para 400
# (modelo invalido) ni para auth (401/403): deterministas, no se enmascaran. Sin fallback
# si la env es invalida o igual al primario. Las server tools van en la llamada de fallback
# igual que en la primaria (mismo contrato).
function Get-VixOpenRouterFallbackModel([string]$Tier = '') {
    $m = Get-VixOpenRouterEnv 'VIXRADAR_OPENROUTER_FALLBACK_MODEL'
    if (-not $m) { $m = $VixOpenRouterFallbackDefault }
    $m = ('' + $m).Trim()
    if (-not (Test-VixModeloIdValido $m)) { return $null }
    if ($m -eq (Get-VixOpenRouterModel $Tier)) { return $null }
    return $m
}

function Get-VixOpenRouterInfo {
    return [pscustomobject]@{
        provider = 'openrouter'
        modelo   = (Get-VixOpenRouterModel)
        fallback = (Get-VixOpenRouterFallbackModel)
        alias_restringido = '~name y sufijo -latest'
    }
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
    $res = @{ Status = 0; Body = ''; Erro = ''; RetryAfter = '' }
    if (-not $ApiKey) { $res.Erro = 'chave ausente antes del POST'; return $res }
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
        # Retry-After (429/503): OpenRouter lo envia en segundos o como HTTP-date. Se captura
        # aqui y la malha de retry lo respeta acotado (Get-VixOpenRouterRetryAfterSec).
        try { $ra = $resp.Headers.GetFirst('Retry-After'); if ($ra) { $res.RetryAfter = ('' + $ra).Trim() } } catch { }
        if (-not $res.RetryAfter) { try { $ra2 = $resp.Headers.GetFirst('retry-after'); if ($ra2) { $res.RetryAfter = ('' + $ra2).Trim() } } catch { } }
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
# Retry-After (429/503): resuelve el header a segundos acotados (0..120). Segundos
# enteros o HTTP-date; invalido/ausente -> $DefaultSec. Pura y testable sin red ni reloj.
function Get-VixOpenRouterRetryAfterSec([string]$Header, [int]$DefaultSec) {
    $h = ('' + $Header).Trim()
    if ($h -eq '') { return $DefaultSec }
    $n = 0
    if ([int]::TryParse($h, [ref]$n) -and $n -gt 0) {
        if ($n -gt 120) { $n = 120 }
        return $n
    }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($h, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d)) {
        $diff = [int](( $d - (Get-Date).ToUniversalTime()).TotalSeconds)
        if ($diff -lt 0) { $diff = 0 }
        if ($diff -gt 120) { $diff = 120 }
        return $diff
    }
    return $DefaultSec
}


# Orquestra un lote completo: lee el prompt, POST con server tools, normaliza el envelope.
# Retenta bounded en status retryable; agotado el primario, prueba el fallback explicito
# (DeepSeek validado) con su propia malha de retry. Retorna
#   @{ Linhas; ExitCode; Msg; Tokens; Parcelas; Modelo; FallbackUsado; Intentos; Status; RetryAfter }
#   ExitCode 0 = HTTP 2xx parseado (aunque el texto del modelo venga vacio).
#   ExitCode != 0 = falla tras retries; Linhas lleva linea de error NO-JSON (sin segredo).
#   400/401/402/403/404: duros, SIN retry y SIN fallback (deterministas).
#   Retry-After de un 429 se respeta (acotado a 120s) en la espera de la siguiente tentativa.
function Invoke-VixOpenRouterLote([string]$PromptPath, [int[]]$RetryDelays = @(0, 5, 20), [int[]]$FallbackRetryDelays = @(0, 10), [int]$TotalTimeoutSec = 0, [string]$Tier = '') {
    $falha = @{ Linhas = @('OPENROUTER_FALHA_COD=1'); ExitCode = 1; Msg = 'falha interna'; Tokens = -1; Parcelas = $null; Modelo = ''; FallbackUsado = $false; Intentos = 0; Status = 0; RetryAfter = '' }
    $prompt = ''
    # JSONCICLO1: el [string] no es cosmetico. Get-Content devuelve string decorada con
    # PSDrive/PSProvider, y esa decoracion es el ciclo que trabo la noturna de 05/09 en el
    # ConvertTo-Json. Copia OS pura o el serializador vuelve a entrar en ciclo.
    try { $prompt = [string]::Copy([string](Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8 -ErrorAction Stop)) } catch { $falha.Msg = 'falha ao ler prompt: ' + $_.Exception.Message; return $falha }
    if (-not $prompt) { $falha.Msg = 'prompt vazio'; return $falha }

    $apiKey = Get-VixOpenRouterApiKey
    if (-not $apiKey) { $falha.Msg = 'OPENROUTER_API_KEY ausente'; $falha.Linhas = @('OPENROUTER_FALHA_COD=1'); return $falha }

    # SENTINELA-TOOLSVOL1 (2026-09-08): a Fase B D1 subio el fetch a 20000 tokens y el total a
    # 15 resultados, muy por encima del WebFetch legado (~un resumen de pagina). Dos corridas de
    # sentinela reales (00:43 y 01:03) mostraron: probe minimo con server tools = ~3s; lote real de
    # 4 emissores jamas completo con timeout de 12 min por intento (5 x 12 min al 00:43). El costo
    # NO esta en la inferencia base, esta en el bucle de server tools con volumen pesado. Se vuelve
    # a paridad con el flujo claude (fetch recortado) para que 12 min alcancen a una pasada.
    $tools = @(
        [ordered]@{ type = 'openrouter:web_search'; parameters = [ordered]@{ engine = 'exa'; max_results = 5; max_total_results = 8 } },
        [ordered]@{ type = 'openrouter:web_fetch'; parameters = [ordered]@{ engine = 'openrouter'; max_content_tokens = 4000 } }
    )
    $modeloPrincipal = Get-VixOpenRouterModel $Tier
    $modeloFallback  = Get-VixOpenRouterFallbackModel $Tier
    $modelos = @()
    if ($modeloPrincipal) { $modelos += ,@{ M = $modeloPrincipal; Delays = $RetryDelays } }
    if ($modeloFallback) { $modelos += ,@{ M = $modeloFallback; Delays = $FallbackRetryDelays } }
    $modeloUsado = ''
    $intentos = 0
    $ultimoCod = 0
    $ultimoMsg = 'falha interna'
    $ultimoRetryAfter = ''
    $vacioFinal = $false
    $duro = $false
    $inicioLote = Get-Date
    foreach ($item in $modelos) {
        $modeloUsado = $item.M
        $esFallback = ($item.M -ne $modeloPrincipal)
        $delays = $item.Delays
        if (-not $delays -or $delays.Count -eq 0) { $delays = @(0, 5, 20) }
        for ($i = 0; $i -lt $delays.Count; $i++) {
            $intentos++
            if ($i -gt 0) {
                $sleepSec = $delays[$i]
                if (($ultimoCod -eq 429) -and ($ultimoRetryAfter -ne '')) { $sleepSec = Get-VixOpenRouterRetryAfterSec $ultimoRetryAfter $sleepSec }
                if ($sleepSec -gt 0) { Start-Sleep -Seconds $sleepSec }
            }
            # SENTINELA-TIMEOUT1: teto de parede por lote (respeita TempoMaxMin da sentinela).
            if ($TotalTimeoutSec -gt 0 -and ([int](((Get-Date) - $inicioLote).TotalSeconds)) -ge $TotalTimeoutSec) {
                $ultimoMsg = 'OPENROUTER_TIMEOUT_TOTAL (excedeu ' + $TotalTimeoutSec + 's)'
                $vacioFinal = $false
                $duro = $false
                break
            }
            $bodyObj = [ordered]@{
                model = $item.M
                messages = @([ordered]@{ role = 'user'; content = $prompt })
                tools = $tools
                stream = $false
                # Ruteo (spec D1, revisado OR429-FIX 2026-09-09): allow_fallbacks=true reativa o
                # FAILOVER NATIVO do OpenRouter entre providers do MESMO modelo (o slug fixo
                # deepseek/deepseek-v4-flash-0731 tem varios providers; 429 de um upstream e
                # absorvido pelo OpenRouter sem POST repetido do adapter). require_parameters=true
                # permanece: so roteia para provider que aceite os parametros/tools deste payload.
                # Sem provider.only/order/ignore. Retry bounded 429/transporte (com Retry-After)
                # continua AQUI como camada unica apos o failover nativo.
                provider = [ordered]@{ require_parameters = $true; allow_fallbacks = $true }
            }
            # JSONCICLO1, guarda de 2 estagios antes de cualquier red:
            #   1) sanitiza: reconstruye el payload solo con [ordered], array, string y primitivo.
            #   2) serializa con teto de pared corto. Nada de POST sin JSON listo.
            $bodySeguro = $null
            try { $bodySeguro = ConvertTo-VixOpenRouterPayloadSeguro $bodyObj }
            catch {
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

            $http = Send-VixOpenRouterHttp -ApiKey $apiKey -JsonBody $json
            if ($http.RetryAfter) { $ultimoRetryAfter = '' + $http.RetryAfter }
            $script:VixOpenRouterUltimoRetryAfter = $ultimoRetryAfter
            if ($http.Status -gt 0) { $ultimoCod = $http.Status }
            if ($http.Erro) { $ultimoMsg = ('erro de transporte: ' + $http.Erro); continue }
            if ($http.Status -ge 200 -and $http.Status -lt 300) {
                $parsed = $null
                try { $parsed = $http.Body | ConvertFrom-Json } catch { $parsed = $null }
                if ($null -eq $parsed -or $null -eq $parsed.choices -or @($parsed.choices).Count -eq 0) {
                    $ultimoMsg = ('HTTP ' + $http.Status + ' resposta sem choices (body malformado ou vazio)')
                    $vacioFinal = $false
                    if (Test-VixOpenRouterStatusRetryable $http.Status) { continue }
                    $duro = $true
                    break
                }
                $env = ConvertTo-VixOpenRouterEnvelope $parsed
                if ([string]::IsNullOrWhiteSpace(('' + $env.result))) {
                    # 2xx valido pero sin contenido: el modelo no produjo trabajo (completion
                    # vacio tras loop de server-tools). Retryable semantico: agota la malha y
                    # luego prueba el fallback, igual que un 429.
                    $ultimoMsg = 'OPENROUTER_EMPTY_RESULT'
                    $vacioFinal = $true
                    continue
                }
                $linha = $env | ConvertTo-Json -Depth 8 -Compress
                $parcelas = @{ input = [int64]$env.usage.input_tokens; output = [int64]$env.usage.output_tokens; cache_creation = [int64]$env.usage.cache_creation_input_tokens; cache_read = [int64]$env.usage.cache_read_input_tokens }
                $parcelas.trabajo = $parcelas.input + $parcelas.output + $parcelas.cache_creation
                return @{ Linhas = @($linha); ExitCode = 0; Msg = 'ok http=' + $http.Status + ' model=' + $env.model + ' intentos=' + $intentos + ' fallback=' + $esFallback.ToString().ToLower(); Tokens = [int64]$parcelas.trabajo; Parcelas = $parcelas; Modelo = $item.M; FallbackUsado = $esFallback; Intentos = $intentos; Status = [int]$http.Status; RetryAfter = $ultimoRetryAfter }
            }
            # cuerpo de error puede venir con .error.message; extrae sin secreto, corta a 200
            $motivo = ''
            try {
                $ep = $http.Body | ConvertFrom-Json
                if ($ep -and $ep.error -and $ep.error.message) { $motivo = (' ' + (('' + $ep.error.message))) }
            } catch { }
            if ($motivo.Length -gt 200) { $motivo = $motivo.Substring(0, 200) }
            $ultimoMsg = 'OPENROUTER_HTTP_STATUS=' + $http.Status + $motivo + ' modelo=' + $item.M + ' intento=' + $intentos
            $vacioFinal = $false
            if (Test-VixOpenRouterStatusRetryable $http.Status) { continue }
            $duro = $true
            break  # 4xx duro: sin retry (401/402/403/400/404/...)
        }
        # Fallback SOLO si la ultima falla fue retryable (o transporte, o resultado vacio).
        # 400 de modelo invalido / auth: deterministas, no se enmascaran con otro modelo.
        if ($duro) { break }
        if ($vacioFinal -and -not $modeloFallback) { break }
    }
    $falha.Msg = $ultimoMsg
    $falha.Modelo = $modeloUsado
    $falha.Intentos = $intentos
    $falha.Status = $ultimoCod
    $falha.RetryAfter = $ultimoRetryAfter
    if ($vacioFinal) {
        # Esgotou los retries (y fallback si existia) con resultado vacio: codigo SEMANTICO
        # estable, sin body/prompt/secret, para que el parser del motor no confunda con auth.
        $falha.Linhas = @('OPENROUTER_EMPTY_RESULT')
        return $falha
    }
    # Linea de error SIN cuerpo: el parser del motor barre stdout por falla de auth Anthropic
    # y el motivo completo contiene palabras (api key, token, unauthorized) que darias falso
    # positivo. Modelo/intentos van solo en Msg (log), nunca en la linea del parser.
    $falha.Linhas = @('OPENROUTER_FALHA_COD=' + $ultimoCod)
    return $falha
}
