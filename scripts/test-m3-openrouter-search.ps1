#requires -Version 5.1
# test-m3-openrouter-search.ps1 - smoke test A/B controlado MiniMax M3 via OpenRouter
#
# OBJETIVO: isolar MODELO do gap de infraestrutura. O mesmo `openrouter:web_search`
# server tool usado pelo Haiku em producao (via adapter Fase B), agora aplicado
# ao M3, com engine Exa fixo, custo medido.
#
# REGRA: standalone, NAO ALTERA motor, provider, scheduler, Worker, frontend,
# adapter versionado, ou qualquer arquivo de producao. So le arquivos.

param(
    [ValidateSet('smoke','lote')][string]$Modo = 'smoke',
    [string]$Emissor = 'Braskem',
    [int]$MaxEmissores = 10,
    # Override de modelo para passe honesto contra modelo vivo; default = slug pago
    # (:free foi retirado pela OpenRouter; smoke de 17/09 rodou no pago e custou $0.033)
    [string]$Modelo = 'minimax/minimax-m3',
    # Freio de custo para modelos pagos: aborta o lote se o acumulado passar disso (USD)
    [double]$CustoMaxUsd = 0.25
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# === Variaveis de controle (NAO alteram o ambiente persistente) ===
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$OpenRouterUrl = 'https://openrouter.ai/api/v1/chat/completions'
# $Modelo vem do parametro (default minimax/minimax-m3:free). NAO reatribuir aqui.
$EngineWebSearch = 'exa'        # fixo, NAO auto
$OutDir = Join-Path $ProjectRoot 'logs\routines\teste-miniaturaminimaxm3'
$TesteTag = 'm3-openrouter-exa-free'

# Pega chave do env (User) - nunca do argumento
$ApiKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY','User')
if (-not $ApiKey) {
    Write-Host 'ERRO: OPENROUTER_API_KEY ausente em env User' -ForegroundColor Red
    exit 2
}
# Mascara para log
$masked = $ApiKey.Substring(0,[Math]::Min(8,$ApiKey.Length)) + '...' + $ApiKey.Substring([Math]::Max(0,$ApiKey.Length-4))

# --- FIX: URL byte-for-byte preservation (M3-URLCORRUPT1) ---
# Ensure fonte_primaria URLs are preserved exactly byte-for-byte.
# Corruption detected: .ghtml -> .ghtm (lose last char `l`)
#                  acao-cai-13percent -> acao-cai-13 (lose `percent`)
# Fix: Never apply Substring/Replace to URL extension fields.
# When constructing prompts with source URLs, preserve them completely
# without truncating the file extension or query parameters.
# -----------------------------------------------------------
Write-Host ("API_KEY (mascarada): " + $masked)
Write-Host ("MODELO: " + $Modelo)
Write-Host ("ENGINE web_search: " + $EngineWebSearch)
Write-Host ("MODO: " + $Modo)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# === Carrega payloads (mesmos do teste A) ===
$payloadsPath = Join-Path $ProjectRoot 'logs\routines\teste-miniaturaminimaxm3-payloads.json'
if (-not (Test-Path $payloadsPath)) {
    Write-Host "ERRO: payloads ausentes em $payloadsPath - rode primeiro test-miniaturamax-m3-payload.ps1"
    exit 3
}
$rawPayloads = Get-Content $payloadsPath -Raw -Encoding UTF8
# Strip BOM se houver
if ($rawPayloads.Length -gt 0 -and $rawPayloads[0] -eq [char]0xFEFF) { $rawPayloads = $rawPayloads.Substring(1) }
$payloads = $rawPayloads | ConvertFrom-Json

# Seleciona emissores
if ($Modo -eq 'smoke') {
    $amostra = @($payloads.payloads | Where-Object { $_.empresa -eq $Emissor })
    if ($amostra.Count -eq 0) { Write-Host "ERRO: emissor '$Emissor' nao encontrado nos payloads"; exit 4 }
} else {
    # Lote: mesmos 10 do teste A, na ordem original
    $ordem = @('Braskem','Oncoclínicas','Oi','Raízen','CSN','Kora Saúde','Natura &Co','Cogna Educação','LWSA','Ultrapar')
    $amostra = @()
    foreach ($nome in $ordem) {
        $hit = $payloads.payloads | Where-Object { $_.empresa -eq $nome } | Select-Object -First 1
        if ($hit) { $amostra += $hit }
    }
    if ($MaxEmissores -gt 0 -and $MaxEmissores -lt $amostra.Count) {
        $amostra = $amostra[0..($MaxEmissores-1)]
    }
}
Write-Host ("EMISSORES NO LOTE: " + ($amostra | ForEach-Object { $_.empresa }) -join ', ')

# === Carrega skill analitica (mesma do motor) ===
$SkillPath = Join-Path $ProjectRoot 'scripts\noturno-batch-haiku.md'
if (-not (Test-Path $SkillPath)) { Write-Host "ERRO: skill ausente $SkillPath"; exit 5 }
$SkillText = (Get-Content $SkillPath -Raw -Encoding UTF8).Trim()

# === Helper: monta o prompt NO FORMATO EXATO do motor (Get-SlimEmissor + New-BatchPrompt) ===
function Get-SlimEmissorM3($emp) {
    $docs = @($emp.cvm_documentos | Select-Object -First 2 | ForEach-Object {
        $assunto = '' + $_.assunto
        if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
        $d = [ordered]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
        [pscustomobject]$d
    })
    $o = [ordered]@{
        empresa = $emp.empresa
        setor = $emp.setor
        tier = 'LIGHT'
        ews_score = 0  # payload de teste nao traz ews direto
        cvm_novos = 0
        cvm_documentos = $docs
    }
    $ctx = '' + $emp.contexto_historico
    if ($ctx) {
        $isCritico = ($ctx -match 'REX|RJ|recupera|default|CRITICO')
        $max = if ($isCritico) { 400 } else { 200 }
        if ($ctx.Length -gt $max) { $ctx = $ctx.Substring(0, $max) }
        $o['contexto_historico'] = $ctx
    }
    return $o
}

function New-BatchPromptM3($empresa, $skillPath, $skillText, $janelaInicio, $janelaFim) {
    $slim = Get-SlimEmissorM3 $empresa
    $json = ($slim | ConvertTo-Json -Depth 8 -Compress)
    return @"
Execute lote 1 (1 emissor). Modelo: $Modelo. Sequencial. Sem subagentes. Sem arquivos locais.
JANELA: $janelaInicio a $janelaFim
COBERTURA (OBRIGATORIO): execute pelo menos 1 busca por familia: F1-emissor (nome + contexto/fato conhecido), F2-divida (divida|debentures|emissao|captacao|titulos), F3-fato (CVM/RI/fato relevante/fonte primaria na janela). Cada item de fontes_consultadas DEVE ser objeto com TODOS os campos: "familia":"emissor|divida|fato", "query":"...", "timestamp":"YYYY-MM-DDTHH:MM:SSZ", "provedor":"openrouter:web_search", "status_http":200, "resultado":"<resposta textual>", "classificacao":"ok".
SAIDA - exatamente estas linhas e nada mais:
1 linha: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento, memo_importancia_credito, memo_monitorar preenchidos.
Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>

JSON:
$json

$skillText
"@
}

# === Funcao de chamada OpenRouter ===
function Invoke-ORCall {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt,
        [int]$TimeoutSec = 120
    )
    $tsCallStart = [DateTime]::UtcNow
    $body = [ordered]@{
        model = $Modelo
        messages = @(
            @{ role = 'system'; content = $SystemPrompt },
            @{ role = 'user'; content = $UserPrompt }
        )
        # Server tool atual do OpenRouter: `tools: [{type: openrouter:web_search}]` com engine fixa.
        # Estrutura EXATA do schema: type + parameters.engine + parameters.max_results.
        # NAO usa response_format (free-form texto, mesma compatibilidade que o motor tem com Haiku).
        tools = @(
            @{
                type = 'openrouter:web_search'
                parameters = @{
                    engine = $EngineWebSearch      # exa fixo, sem fallback
                    max_results = 8
                }
            }
        )
        tool_choice = 'auto'
        # max_tool_calls no nivel da raiz limita invocacoes da tool por request
        max_tool_calls = 3
        temperature = 0.2
        stream = $false
        # M3-TETO1 (t_391834cf): 6144 queimava em reasoning puro. Medido em 17/09:
        # reasoning_tokens=6424 no Braskem, content=null, finish=length. Duas mudancas:
        # 1) reasoning effort low (parametro suportado do M3, corta o thinking longo).
        # 2) teto 12288 para caber thinking curto + saida do lote com folga.
        reasoning = @{ effort = 'low' }
        max_tokens = 12288
    }
    $bodyJson = $body | ConvertTo-Json -Depth 8 -Compress
    $headers = @{
        'Authorization' = 'Bearer ' + $ApiKey
        'Content-Type' = 'application/json'
        'HTTP-Referer' = 'https://vixradar.local/teste-ab-m3'
        'X-Title' = 'VIX Radar A/B M3 smoke test'
    }
    try {
        $resp = Invoke-WebRequest -Uri $OpenRouterUrl -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec $TimeoutSec -UseBasicParsing
        $code = [int]$resp.StatusCode
        $rawBytes = $resp.RawContentStream.ToArray()
        $rawText = [System.Text.Encoding]::UTF8.GetString($rawBytes)
        $latencyMs = [int]([DateTime]::UtcNow - $tsCallStart).TotalMilliseconds
        return [pscustomobject]@{
            ok = $true
            http_status = $code
            latency_ms = $latencyMs
            raw = $rawText
            error = $null
        }
    } catch {
        $latencyMs = [int]([DateTime]::UtcNow - $tsCallStart).TotalMilliseconds
        $errBody = ''
        try {
            if ($_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $errBody = $reader.ReadToEnd()
            }
        } catch {}
        return [pscustomobject]@{
            ok = $false
            http_status = 0
            latency_ms = $latencyMs
            raw = $errBody
            error = $_.Exception.Message
        }
    }
}

# === Processa 1 emissor ===
$costGuardUsd = $CustoMaxUsd
$costGuardTripped = $false
function Process-Emissor($emp) {
    $janelaInicio = $emp.janela_inicio
    $janelaFim = $emp.janela_fim
    $prompt = New-BatchPromptM3 $emp $SkillPath $SkillText $janelaInicio $janelaFim
    $promptLen = $prompt.Length
    Write-Host ("  -> " + $emp.empresa + " | prompt_len=" + $promptLen + " chars")
    $resp = Invoke-ORCall -SystemPrompt 'Voce e um analista de credito corporativo. Siga o protocolo de saida EXATAMENTE. Sem markdown, sem prosa, so linhas RESULTADO| e LOTE_RESUMO|.' -UserPrompt $prompt -TimeoutSec 180
    return [pscustomobject]@{
        empresa = $emp.empresa
        janela_inicio = $janelaInicio
        janela_fim = $janelaFim
        prompt_chars = $promptLen
        response = $resp
    }
}

# === Extracao e gravacao por emissor ===
$results = @()
$failureCount = 0
$failedMetrics = @()
$custoAcumulado = 0.0
$smokeOut = @{
    teste = $TesteTag
    modo = $Modo
    modelo = $Modelo
    engine = $EngineWebSearch
    emissores = @()
}

foreach ($emp in $amostra) {
    # Freio de custo: aborta o lote inteiro se o acumulado estourou o teto
    if ($costGuardTripped) { break }
    $r = Process-Emissor $emp
    $entry = [ordered]@{
        empresa = $r.empresa
        janela = "$($r.janela_inicio) -> $($r.janela_fim)"
        prompt_chars = $r.prompt_chars
        http_status = $r.response.http_status
        latency_ms = $r.response.latency_ms
        error = $r.response.error
        raw_response = $null
        parsed = $null
    }

    # Parseia JSON do OpenRouter para extrair metricas
    $parsedJson = $null
    try {
        if ($r.response.raw) { $parsedJson = $r.response.raw | ConvertFrom-Json }
    } catch {}

    $metricas = [ordered]@{
        model_returned = $null
        provider_returned = $null
        engine_used = $null
        web_search_executed = $false
        web_search_count = 0
        input_tokens = $null
        output_tokens = $null
        total_tokens = $null
        cached_tokens = $null
        reasoning_tokens = $null
        cost_usd = $null
        cost_prompt = $null
        cost_completion = $null
        cost_request = $null
        cost_image = $null
        cost_web_search = $null
        finish_reason = $null
        native_finish_reason = $null
        content_text = $null
        tool_calls = $null
    }

    if ($parsedJson) {
        $entry.raw_response = $parsedJson
        if ($parsedJson.model) { $metricas.model_returned = $parsedJson.model }
        if ($parsedJson.provider) { $metricas.provider_returned = $parsedJson.provider }
        if ($parsedJson.choices) {
            $choice = $parsedJson.choices[0]
            if ($choice) {
                if ($choice.finish_reason) { $metricas.finish_reason = $choice.finish_reason }
                if ($choice.native_finish_reason) { $metricas.native_finish_reason = $choice.native_finish_reason }
                if ($choice.message) {
                    if ($choice.message.content) { $metricas.content_text = $choice.message.content }
                    if ($choice.message.tool_calls) { $metricas.tool_calls = @($choice.message.tool_calls) }
                }
            }
        }
        if ($parsedJson.usage) {
            $u = $parsedJson.usage
            if ($null -ne $u.prompt_tokens) { $metricas.input_tokens = [int64]$u.prompt_tokens }
            if ($null -ne $u.completion_tokens) { $metricas.output_tokens = [int64]$u.completion_tokens }
            if ($null -ne $u.total_tokens) { $metricas.total_tokens = [int64]$u.total_tokens }
            # Cache specifics
            if ($null -ne $u.cached_tokens) { $metricas.cached_tokens = [int64]$u.cached_tokens }
            if ($null -ne $u.cache_read_input_tokens) { $metricas.cached_tokens = [int64]$u.cache_read_input_tokens }
            if ($null -ne $u.reasoning_tokens) { $metricas.reasoning_tokens = [int64]$u.reasoning_tokens }
            # Cache real do OpenRouter vive em prompt_tokens_details.cached_tokens
            if ($u.prompt_tokens_details -and $null -ne $u.prompt_tokens_details.cached_tokens) { $metricas.cached_tokens = [int64]$u.prompt_tokens_details.cached_tokens }
            # Reasoning real vive em completion_tokens_details.reasoning_tokens
            if ($u.completion_tokens_details -and $null -ne $u.completion_tokens_details.reasoning_tokens) { $metricas.reasoning_tokens = [int64]$u.completion_tokens_details.reasoning_tokens }
            # OpenRouter cost breakdown
            $cost = $u.cost
            if ($null -ne $cost) {
                $metricas.cost_usd = [double]$cost
                if ($null -ne $cost.prompt_tokens) { $metricas.cost_prompt = [double]$cost.prompt_tokens }
                if ($null -ne $cost.completion_tokens) { $metricas.cost_completion = [double]$cost.completion_tokens }
                if ($null -ne $cost.request) { $metricas.cost_request = [double]$cost.request }
                if ($null -ne $cost.image) { $metricas.cost_image = [double]$cost.image }
                if ($null -ne $cost.web_search) { $metricas.cost_web_search = [double]$cost.web_search }
            }
            # web_search nativo do OpenRouter (M3-WSCOUNT1, t_391834cf): o contador NAO e
            # usage.web_search_requests (campo inexistente); e usage.server_tool_use_details.web_search_requests.
            # A rodada 19:31 de 17/09 executou 3 buscas reais (com url_citation) e o harness
            # lia zero por ler o campo errado. Fallback server_tool_use = nome que o adapter
            # de producao normaliza (scripts/lib/vixradar-openrouter.ps1).
            $wsCount = $null
            if ($u.server_tool_use_details -and $null -ne $u.server_tool_use_details.web_search_requests) { $wsCount = [int]$u.server_tool_use_details.web_search_requests }
            elseif ($u.server_tool_use -and $null -ne $u.server_tool_use.web_search_requests) { $wsCount = [int]$u.server_tool_use.web_search_requests }
            if ($null -ne $wsCount) {
                $metricas.web_search_count = $wsCount
                $metricas.web_search_executed = ($wsCount -gt 0)
            }
        }
    }
    $entry.metricas = $metricas
    $smokeOut.emissores += $entry

    # Freio de custo: acumula e compara com o teto
    if ($null -ne $metricas.cost_usd) {
        $custoAcumulado += [double]$metricas.cost_usd
        if ($custoAcumulado -gt $costGuardUsd) { $costGuardTripped = $true }
    }

    # === ASSERCOES (veiculo de reprovacao e o exit code, nao excecao) ===
    # Regra: http_status != 200 reprova; web_search_executed falso reprova;
    # input_tokens ou model_returned nulos reprovam. Cada falha soma 1 e nomeia a metrica.
    if ($entry.http_status -ne 200) {
        $failureCount++
        $failedMetrics += ("http_status=" + $entry.http_status + " (esperado 200) [" + $entry.empresa + "]")
        Write-Host ("     FALHA: http_status=" + $entry.http_status + " (esperado 200) [" + $entry.empresa + "]") -ForegroundColor Red
    }
    if (-not $metricas.web_search_executed) {
        $failureCount++
        $failedMetrics += ("web_search_executed=false [" + $r.empresa + "]")
        Write-Host ("     FALHA: web_search_executed=false [" + $r.empresa + "]") -ForegroundColor Red
    }
    if ($null -eq $metricas.input_tokens) {
        $failureCount++
        $failedMetrics += ("input_tokens=null [" + $r.empresa + "]")
        Write-Host ("     FALHA: input_tokens=null [" + $r.empresa + "]") -ForegroundColor Red
    }
    if ($null -eq $metricas.model_returned) {
        $failureCount++
        $failedMetrics += ("model_returned=null [" + $r.empresa + "]")
        Write-Host ("     FALHA: model_returned=null [" + $r.empresa + "]") -ForegroundColor Red
    }
    # M3-WSCOUNT1 (t_391834cf): teto queimado em reasoning antes de qualquer conteudo
    # e defeito real, nao so metrica de busca. finish=length com content vazio reprova:
    # a analise do emissor nao saiu, o custo queimou. Nao e enfraquecer assercao, e fechar
    # o furo que o falso verde anterior deixou (busca ok + saida perdida = ainda reprova).
    if ($metricas.finish_reason -eq 'length' -and -not $metricas.content_text) {
        $failureCount++
        $failedMetrics += ("saida_truncada finish=length sem conteudo (reasoning_tokens=" + $metricas.reasoning_tokens + ", max_tokens=6144... ver comentario M3-TETO1) [" + $r.empresa + "]")
        Write-Host ("     FALHA: saida_truncada finish=length sem conteudo (reasoning_tokens=" + $metricas.reasoning_tokens + ") [" + $r.empresa + "]") -ForegroundColor Red
    }

    # Persiste JSON individual
    $tsFile = (Get-Date).ToString('yyyyMMdd-HHmmss')
    if ($Modo -eq 'smoke') {
        $perFile = Join-Path $OutDir ("smoke_" + $tsFile + ".json")
    } else {
        $slug = ($emp.empresa -replace '[^\w]','_')
        $perFile = Join-Path $OutDir ("or_" + $slug + "_" + $tsFile + ".json")
    }
    $entry | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $perFile -Encoding UTF8
    Write-Host ("     gravado: " + $perFile)

    $results += $entry
}

# === Resumo final ===
$smokeOut | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir ("consolidado_" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".json")) -Encoding UTF8

Write-Host ""
Write-Host "=== RESUMO ==="
$total_in = 0; $total_out = 0; $total_cost = 0.0; $total_ws = 0
foreach ($r in $results) {
    $m = $r.metricas
    Write-Host ("  " + $r.empresa + " | http=" + $r.http_status + " lat=" + $r.latency_ms + "ms | model=" + $m.model_returned + " | provider=" + $m.provider_returned + " | in=" + $m.input_tokens + " out=" + $m.output_tokens + " cached=" + $m.cached_tokens + " ws=" + $m.web_search_count + " cost=$" + $m.cost_usd + " finish=" + $m.finish_reason)
    if ($null -ne $m.input_tokens) { $total_in += [int64]$m.input_tokens }
    if ($null -ne $m.output_tokens) { $total_out += [int64]$m.output_tokens }
    if ($null -ne $m.cost_usd) { $total_cost += [double]$m.cost_usd }
    $total_ws += [int]$m.web_search_count
}
Write-Host ("TOTAL: input=" + $total_in + " output=" + $total_out + " web_search_requests=" + $total_ws + " cost_usd=$" + $total_cost)

# === VEREDICTO: exit code e o veiculo da reprovacao ===
# 0 = pass. Nao-zero = falha de assercao (nao erro de runtime). 99 = testemunho do protocolo.
if ($failureCount -gt 0) {
    Write-Host ""
    Write-Host "=== REPROVADO: assercoes falharam ===" -ForegroundColor Red
    foreach ($fm in $failedMetrics) {
        Write-Host ("  METRICA_FALHOU: " + $fm) -ForegroundColor Red
    }
    Write-Host ("FALHAS: " + $failureCount)
    if ($costGuardTripped) {
        Write-Host ("CUSTO GUARD: teto de $" + $costGuardUsd + " estourado (acumulado $" + $custoAcumulado + ") - lote abortado") -ForegroundColor Red
    }
    Write-Host "EXITCODE_OPENROUTER=99"
    exit 99
}
if ($costGuardTripped) {
    Write-Host ("CUSTO GUARD: teto de $" + $costGuardUsd + " estourado (acumulado $" + $custoAcumulado + ") - lote abortado") -ForegroundColor Red
    Write-Host "EXITCODE_OPENROUTER=99"
    exit 99
}
Write-Host "=== APROVADO: todas as assercoes passaram ===" -ForegroundColor Green
Write-Host "EXITCODE_OPENROUTER=0"
exit 0
